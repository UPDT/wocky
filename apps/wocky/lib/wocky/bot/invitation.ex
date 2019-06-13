defmodule Wocky.Bot.Invitation do
  @moduledoc "An invitation from a user to subscribe to a bot"

  use Wocky.Repo.Schema

  import Ecto.Query

  alias Ecto.Changeset
  alias Wocky.Account.User
  alias Wocky.Bot
  alias Wocky.Repo
  alias Wocky.Roster

  @foreign_key_type :binary_id
  schema "bot_invitations" do
    field :accepted, :boolean

    belongs_to :user, User
    belongs_to :invitee, User
    belongs_to :bot, Bot

    timestamps()
  end

  @type id :: integer
  @type t :: %Invitation{}

  @spec put(User.t(), Bot.t(), User.t()) :: {:ok, t()} | {:error, any()}
  def put(
        invitee,
        %Bot{id: bot_id, user_id: user_id},
        %User{id: user_id} = user
      ) do
    if Roster.friend?(invitee, user) do
      %Invitation{}
      |> changeset(%{
        user_id: user.id,
        bot_id: bot_id,
        invitee_id: invitee.id
      })
      |> Repo.insert(
        returning: true,
        on_conflict: [set: [updated_at: DateTime.utc_now()]],
        conflict_target: [:user_id, :bot_id, :invitee_id]
      )
    else
      {:error, :permission_denied}
    end
  end

  def put(_, _, _), do: {:error, :permission_denied}

  @spec get(id() | Bot.t(), User.t()) :: nil | t()
  def get(%Bot{} = bot, requestor) do
    Invitation
    |> where(
      [i],
      i.bot_id == ^bot.id and
        (i.user_id == ^requestor.id or i.invitee_id == ^requestor.id)
    )
    |> Repo.one()
  end

  def get(id, requestor) do
    Invitation
    |> where(
      [i],
      i.id == ^id and
        (i.user_id == ^requestor.id or i.invitee_id == ^requestor.id)
    )
    |> Repo.one()
  end

  @spec invited?(Bot.t(), User.t()) :: boolean()
  def invited?(bot, requestor) do
    result =
      Invitation
      |> where([i], i.bot_id == ^bot.id and i.invitee_id == ^requestor.id)
      |> Repo.one()

    result != nil
  end

  @spec exists?(id() | Bot.t(), User.t()) :: boolean()
  def exists?(bot_or_id, requestor), do: get(bot_or_id, requestor) != nil

  @spec respond(t(), boolean(), User.t()) :: {:ok, t()} | {:error, any()}
  def respond(
        %Invitation{invitee_id: invitee_id} = invitation,
        accepted?,
        %User{id: invitee_id}
      ) do
    invitation = Repo.preload(invitation, [:bot, :invitee])

    with {:ok, result} <- do_respond(invitation, accepted?),
         :ok <- maybe_subscribe(invitation, accepted?) do
      {:ok, result}
    end
  end

  def respond(_, _, _), do: {:error, :permission_denied}

  defp do_respond(invitation, accepted?) do
    invitation
    |> changeset(%{accepted: accepted?})
    |> Repo.update()
  end

  defp maybe_subscribe(_, false), do: :ok

  defp maybe_subscribe(invitation, true) do
    Bot.subscribe(invitation.bot, invitation.invitee)
  end

  @spec delete(User.t(), User.t()) :: :ok
  def delete(user, invitee) do
    Invitation
    |> where([i], i.user_id == ^user.id and i.invitee_id == ^invitee.id)
    |> Repo.delete_all()

    :ok
  end

  @spec changeset(t(), map()) :: Changeset.t()
  defp changeset(struct, params) do
    struct
    |> cast(params, [:user_id, :bot_id, :invitee_id, :accepted])
    |> validate_required([:user_id, :bot_id, :invitee_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:bot_id)
    |> foreign_key_constraint(:invitee_id)
  end
end
