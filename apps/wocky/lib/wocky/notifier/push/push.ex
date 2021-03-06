defmodule Wocky.Notifier.Push do
  @moduledoc """
  The Push context. Single interface for push notifications.
  """

  @behaviour Wocky.Notifier

  use Elixometer
  use ModuleConfig, otp_app: :wocky

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Pigeon.APNS.Notification, as: APNSNotification
  alias Pigeon.FCM.Notification, as: FCMNotification
  alias Wocky.Account.User
  alias Wocky.Audit
  alias Wocky.Audit.PushLog
  alias Wocky.Notifier.Push.Backend.APNS
  alias Wocky.Notifier.Push.Backend.FCM
  alias Wocky.Notifier.Push.Backend.Sandbox
  alias Wocky.Notifier.Push.Event
  alias Wocky.Notifier.Push.Token
  alias Wocky.Repo

  require Logger

  @max_retries 5

  defstruct [
    :token,
    :user,
    :device,
    :platform,
    :event,
    :backend,
    :on_response,
    retries: 0,
    resp: nil
  ]

  @type message :: String.t()
  @type notification :: APNSNotification.t() | FCMNotification.t()
  @type id :: String.t() | nil
  @type payload :: map()
  @type response ::
          APNSNotification.response()
          | FCMNotification.status()
          | FCMNotification.regid_error_response()
  @type on_response :: (notification() -> no_return())

  @type t :: %__MODULE__{
          token: Token.token(),
          user: User.t(),
          device: User.device(),
          platform: Token.PushServicePlatformEnum.t(),
          event: Event.t(),
          backend: module(),
          on_response: on_response(),
          retries: non_neg_integer(),
          resp: response()
        }

  # ===================================================================
  # Push Token API

  @spec enable(
          User.tid(),
          User.device(),
          Token.token(),
          String.t() | nil,
          boolean() | nil
        ) :: :ok | {:error, any()}
  def enable(user, device, token, platform \\ nil, dev_mode \\ nil) do
    changeset =
      Token.register_changeset(%{
        user_id: User.id(user),
        device: device,
        token: token,
        platform: platform,
        dev_mode: dev_mode
      })

    cleanup_query =
      from t in Token,
        where: t.user_id == ^User.id(user),
        where: t.device == ^device,
        where: t.token != ^token

    case do_upsert(changeset, cleanup_query, dev_mode) do
      {:ok, _} ->
        :ok

      {:error, _, cs, _} ->
        {:error, cs}
    end
  end

  defp do_upsert(changeset, cleanup_query, dev_mode) do
    Multi.new()
    |> Multi.insert(
      :token,
      changeset,
      on_conflict: [set: conflict_updates(dev_mode)],
      conflict_target: [:user_id, :device, :token]
    )
    |> Multi.update_all(
      :cleanup,
      cleanup_query,
      set: [valid: false, disabled_at: DateTime.utc_now()]
    )
    |> Repo.transaction()
  end

  defp conflict_updates, do: [valid: true, enabled_at: DateTime.utc_now()]

  defp conflict_updates(nil), do: conflict_updates()

  defp conflict_updates(dev_mode) do
    [dev_mode: dev_mode] ++ conflict_updates()
  end

  @spec disable(User.tid(), User.device()) :: :ok
  def disable(user, device) do
    Repo.update_all(
      from(Token, where: [user_id: ^User.id(user), device: ^device, valid: true]),
      set: [valid: false, disabled_at: DateTime.utc_now()]
    )

    :ok
  end

  # ===================================================================
  # Push Notification API

  @impl true
  def notify(event) do
    notify_all(Event.recipient(event), event)
  end

  @spec notify_all(User.t(), Event.t()) :: :ok
  def notify_all(user, event) do
    config = config()

    if config.enabled do
      for token <- Token.all_for_user(user) do
        platform = token.platform

        backend =
          cond do
            config.sandbox -> Sandbox
            platform == :apns -> APNS
            platform == :fcm -> FCM
          end

        do_notify(%__MODULE__{
          token: token.token,
          user: user,
          device: token.device,
          platform: platform,
          backend: backend,
          event: event
        })
      end

      :ok
    else
      :ok
    end
  end

  # ===================================================================
  # Helpers

  defp do_notify(%__MODULE__{token: nil, user: user, device: device}) do
    Logger.error(
      "PN Error: Attempted to send notification to user " <>
        "#{user.id}/#{device} but they have no token."
    )
  end

  defp do_notify(
         %__MODULE__{backend: backend, resp: resp, retries: @max_retries} =
           params
       ) do
    log_failure(params)
    Logger.error("PN Error: #{backend.error_msg(resp)}")
  end

  defp do_notify(%__MODULE__{backend: backend} = params) do
    # Don't start_link here - we want the timeout to fire even if we crash
    {:ok, timeout_pid} = Task.start(fn -> push_timeout(params) end)

    on_response = fn r -> handle_response(r, timeout_pid, params) end

    params
    |> Map.put(:backend, backend)
    |> Map.put(:on_response, on_response)
    |> backend.push()
  end

  defp handle_response(notification, timeout_pid, params) do
    send(timeout_pid, :push_complete)
    resp = params.backend.get_response(notification)
    update_metric(resp)

    Audit.log_push(log_msg(notification, params), params.user)

    maybe_handle_error(%{params | resp: resp})
  end

  defp maybe_handle_error(%__MODULE__{resp: :success}), do: :ok

  defp maybe_handle_error(
         %__MODULE__{
           backend: backend,
           user: user,
           device: device,
           retries: retries,
           token: token,
           resp: resp
         } = params
       ) do
    _ = Logger.error("PN Error: #{backend.error_msg(resp)}")

    case backend.handle_error(resp) do
      :retry -> do_notify(%{params | retries: retries + 1})
      :invalidate_token -> invalidate_token(user.id, device, token)
    end
  end

  defp invalidate_token(user_id, device, token) do
    Repo.update_all(
      from(
        Token,
        where: [user_id: ^user_id, device: ^device, token: ^token]
      ),
      set: [valid: false, invalidated_at: DateTime.utc_now()]
    )
  end

  defp update_metric(resp),
    do: update_counter("push_notfications.#{to_string(resp)}", 1)

  defp push_timeout(%__MODULE__{retries: retries} = params) do
    timeout = get_config(:timeout) * 2

    receive do
      :push_complete -> :ok
    after
      timeout ->
        log_timeout(params)
        do_notify(%{params | retries: retries + 1})
    end
  end

  defp log_msg(n, %__MODULE__{device: device, token: token, backend: backend}) do
    resp = backend.get_response(n)

    %PushLog{
      device: device,
      token: token,
      message_id: backend.get_id(n),
      payload_string: n |> backend.get_payload() |> Poison.encode!(),
      payload: backend.get_payload(n),
      response: to_string(resp),
      details: backend.error_msg(resp)
    }
  end

  defp log_timeout(%__MODULE__{
         token: token,
         user: user,
         device: device,
         event: event
       }) do
    # TODO This log message is not informative. It is currently used only
    # to test that timeouts are handled, and we should find a better way to
    # do that.
    # _ = Logger.error("PN Error: timeout expired")

    log = %PushLog{
      device: device,
      token: token,
      message_id: "",
      payload_string: payload_string(event),
      payload: %{message: Event.message(event)},
      response: "timeout",
      details: "Timeout waiting for response from Pigeon"
    }

    Audit.log_push(log, user)

    :ok
  end

  defp log_failure(%__MODULE__{
         token: token,
         user: user,
         device: device,
         event: event
       }) do
    log = %PushLog{
      device: device,
      token: token,
      message_id: "",
      payload_string: payload_string(event),
      payload: %{message: Event.message(event)},
      response: "max retries reached",
      details:
        "Maximum number of #{@max_retries} retries sending push notification."
    }

    Audit.log_push(log, user)

    :ok
  end

  defp payload_string(event), do: event |> Event.message() |> Poison.encode!()
end
