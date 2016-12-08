defmodule Wocky.Location do
  @moduledoc "Interface for user location processing."

  use Exref, ignore: [__struct__: 0, __struct__: 1, user_location_changed: 3]
  use Wocky.Ejabberd
  alias Wocky.Location
  alias Wocky.User
  alias Wocky.Bot
  require Logger

  @type t :: %__MODULE__{
    lat: float,
    lon: float,
    accuracy: float
  }

  @enforce_keys [:lat, :lon]
  defstruct [
    lat: nil,
    lon: nil,
    accuracy: 0.0
  ]

  @type location_tuple :: {float, float, float}


  @doc """
  Process a location change event for a user. The processing happens
  asynchronously and the function always returns `:ok`.
  """
  def user_location_changed(user, location, async \\ true)

  @spec user_location_changed(Ejabberd.jid, location_tuple, boolean) :: :ok
  def user_location_changed(jid, {lat, lon, accuracy}, async) do
    location = %Location{lat: lat, lon: lon, accuracy: accuracy}
    user = User.from_jid(jid)

    user_location_changed(user, location, async)
  end

  @spec user_location_changed(User.t, Location.t, boolean) :: :ok
  def user_location_changed(user, location, true) do
    {:ok, _} = Task.start(fn () -> check_for_bot_events(user, location) end)
    {:ok, _} = Task.start(fn () -> update_bot_locations(user, location) end)

    :ok
  end
  def user_location_changed(user, location, false) do
    check_for_bot_events(user, location)
    update_bot_locations(user, location)
    :ok
  end

  defp check_for_bot_events(user, location) do
    user
    |> User.set_location(location)
    |> User.get_subscribed_bots
    |> Enum.map(&:wocky_bot_util.get_id_from_jid(&1))
    |> bots_with_events(user, location)
    |> Enum.each(&trigger_bot_notification(user, &1))
  end

  defp update_bot_locations(user, location) do
    user
    |> owned_bots_with_follow_me
    |> Enum.each(&Bot.set_location(&1, location))
  end

  defp bots_with_events(bots, user, location) do
    bots |> Enum.reduce([], &check_for_event(&1, user, location, &2))
  end

  defmacrop log_check_result(user, bot_id, result) do
    quote do
      :ok = Logger.debug("""
      User #{unquote(user).user} #{unquote(result)} the perimeter \
      of #{unquote(bot_id)}\
      """)
    end
  end

  defp check_for_event(bot_id, user, location, acc) do
    :ok = Logger.debug("""
    Checking user #{user.user} for collision with bot #{bot_id} \
    at location (#{location.lat},#{location.lon})...\
    """)
    bot = Bot.get(bot_id)
    if bot |> is_nil do
      :ok = Logger.warn("Could not find bot for ID #{bot_id}")
      acc
    else
      bot
      |> intersects?(location)
      |> handle_intersection(user, bot, acc)
    end
  end

  defp intersects?(nil, _location), do: false
  defp intersects?(bot, location) do
    radius = (bot.radius / 1000.0) # Bot radius is stored as millimeters
    distance = Geocalc.distance_between(Map.from_struct(bot),
                                        Map.from_struct(location))
    intersects = distance <= radius
    :ok = Logger.debug("""
    The distance of #{distance} meters is \
    #{if intersects, do: "within", else: "outside"} the radius of bot \
    #{bot.id} (#{radius} meters)\
    """)
    intersects
  end

  defp handle_intersection(true, user, %Bot{id: bot_id} = bot, acc) do
    if check_for_enter_event(user, bot_id) do
      log_check_result(user, bot_id, "has entered")
      User.add_bot_event(user, bot_id, :enter)
      [{bot, :enter} | acc]
    else
      log_check_result(user, bot_id, "is within")
      acc
    end
  end
  defp handle_intersection(false, user, %Bot{id: bot_id} = bot, acc) do
    if check_for_exit_event(user, bot_id) do
      log_check_result(user, bot_id, "has left")
      User.add_bot_event(user, bot_id, :exit)
      [{bot, :exit} | acc]
    else
      log_check_result(user, bot_id, "is outside of")
      acc
    end
  end

  defp check_for_enter_event(user, bot_id) do
    case User.get_last_bot_event(user, bot_id) do
      [] -> true
      [%{event: "exit"}] -> true
      _ -> false
    end
  end

  defp check_for_exit_event(user, bot_id) do
    case User.get_last_bot_event(user, bot_id) do
      [] -> false
      [%{event: "enter"}] -> true
      _ -> false
    end
  end

  defp trigger_bot_notification(user, {bot, event}) do
    jid = User.to_jid_string(user)
    :ok = Logger.info("User #{jid} #{event}ed the perimeter of bot #{bot.id}")

    :ok = send_notification(user, bot, event)
    :ok = send_push_notification(user, bot, event)
  end

  defp send_push_notification(user, bot, event) do
    jid = User.to_jid(user)
    case :wocky_notification_handler.notify_bot_event(jid, bot.id, event) do
      :ok -> :ok
      {:error, reason} ->
        Logger.error("""
        Failed to send push notification to #{User.to_jid_string(user)}: \
        #{inspect(reason)}\
        """)
    end
  end

  defp send_notification(user, bot, event) do
    :ejabberd_router.route(Ejabberd.make_jid!("", :wocky_app.server),
                           User.to_bare_jid(user),
                           bot_notification_stanza(user, bot, event))
  end

  defp bot_notification_stanza(user, bot, event) do
    user_jid = User.to_bare_jid_string(user)
    bot_jid = Bot.to_jid_string(bot)
    xmlel(name: "message",
          attrs: [
            {"from", :wocky_app.server},
            {"to", user_jid},
            {"type", "headline"}
          ],
          children: [
            xmlel(name: "bot", attrs: [{"xmlns", "hippware.com/hxep/bot"}],
                  children: [
                    xmlel(name: "jid", children: [xmlcdata(content: bot_jid)]),
                    xmlel(name: "id", children: [xmlcdata(content: bot.id)]),
                    xmlel(name: "server", children: [
                            xmlcdata(content: bot.server)
                          ]),
                    xmlel(name: "action", children: [
                            xmlcdata(content: to_string(event))
                          ]),
                    xmlel(name: "user-jid", children: [
                            xmlcdata(content: user_jid)
                          ])
                  ])
          ])
  end

  defp owned_bots_with_follow_me(user) do
    user
    |> User.get_owned_bots
    |> Enum.filter(&following_me?(&1))
  end

  defp following_me?(%Bot{follow_me: true, follow_me_expiry: expiry}) do
    expiry > :wocky_db.now_to_timestamp(:os.timestamp)
  end
  defp following_me?(_), do: false
end
