defmodule Wocky.Roster do
  @moduledoc """
  Context module for managing the friends list (roster)
  """

  import Ecto.Query

  alias Ecto.Queryable
  alias Wocky.Account.User
  alias Wocky.Events.UserInvitationResponse
  alias Wocky.Notifier
  alias Wocky.Repo
  alias Wocky.Roster.Invitation
  alias Wocky.Roster.Item

  require Logger

  @type relationship :: :self | :friend | :invited | :invited_by | :none
  @type error :: {:error, term()}

  # ----------------------------------------------------------------------
  # Roster item management

  @spec insert_item(User.t(), User.t()) :: {:ok, Item.t()} | error()
  def insert_item(user, contact) do
    %{user_id: user.id, contact_id: contact.id}
    |> Item.insert_changeset()
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:user_id, :contact_id]
    )
  end

  @spec get_item(User.t() | User.id(), User.t() | User.id()) :: Item.t() | nil
  def get_item(%User{id: user_id}, %User{id: contact_id}),
    do: get_item(user_id, contact_id)

  def get_item(user_id, contact_id) do
    Item
    |> where([i], i.user_id == ^user_id and i.contact_id == ^contact_id)
    |> Repo.one()
  end

  @spec update_item(Item.t(), map()) :: {:ok, Item.t()} | error()
  def update_item(item, changes) do
    item
    |> Item.update_changeset(changes)
    |> Repo.update()
  end

  # ----------------------------------------------------------------------
  # High-level friendship API

  @doc "Returns the relationship of user to target"
  @spec relationship(User.t(), User.t()) :: relationship
  def relationship(%User{id: id}, %User{id: id}), do: :self

  def relationship(user, target) do
    # TODO: This can be optimised into a single query with some JOIN magic,
    # but I'm going for "simple and working" first.
    cond do
      friend?(user, target) -> :friend
      invited?(user, target) -> :invited
      invited_by?(user, target) -> :invited_by
      true -> :none
    end
  end

  @doc "Returns true if the two users are friends or the same person"
  @spec self_or_friend?(User.t() | User.id(), User.t() | User.id()) :: boolean
  def self_or_friend?(%User{id: id}, %User{id: id}), do: true
  def self_or_friend?(user_id, user_id), do: true
  def self_or_friend?(a, b), do: friend?(a, b)

  @doc "Returns true if the two users are friends"
  @spec friend?(User.t() | User.id(), User.t() | User.id()) :: boolean
  def friend?(%User{id: user_a_id}, %User{id: user_b_id}),
    do: friend?(user_a_id, user_b_id)

  def friend?(user_a_id, user_b_id) do
    Item
    |> where(user_id: ^user_a_id)
    |> where(contact_id: ^user_b_id)
    |> Repo.one()
    |> Kernel.!=(nil)
  end

  @spec befriend(User.t(), User.t(), boolean) :: :ok
  def befriend(user, contact, notify \\ true) do
    {:ok, _} = insert_item(user, contact)
    {:ok, _} = insert_item(contact, user)
    Invitation.delete_pair(user, contact)

    if notify do
      %UserInvitationResponse{
        from: user,
        to: contact
      }
      |> Notifier.notify()
    end

    :ok
  end

  @doc "Removes all relationships (friend + follow) between the two users"
  @spec unfriend(User.t(), User.t()) :: :ok
  def unfriend(a, b) do
    Item
    |> with_pair(a, b)
    |> Repo.delete_all()

    Invitation.delete_pair(a, b)

    :ok
  end

  defp with_pair(query, a, b) do
    from r in query,
      where:
        (r.user_id == ^a.id and r.contact_id == ^b.id) or
          (r.user_id == ^b.id and r.contact_id == ^a.id)
  end

  # ----------------------------------------------------------------------
  # Roster invitations

  @doc "Returns true if the first user has invited the second to be friends"
  @spec invited?(User.t(), User.t()) :: boolean
  def invited?(user, target) do
    Invitation
    |> where(user_id: ^user.id)
    |> where(invitee_id: ^target.id)
    |> Repo.one()
    |> Kernel.!=(nil)
  end

  @doc "Returns true if the roster item refers to a followee of the item owner"
  @spec invited_by?(User.t(), User.t()) :: boolean
  def invited_by?(user, target), do: invited?(target, user)

  @doc """
  Invites `contact` to become a friend of `user`
  """
  @spec invite(User.t(), User.t()) :: :friend | :invited | :self
  def invite(user, target) do
    case relationship(user, target) do
      :none ->
        :ok = Invitation.add(user, target)
        :invited

      :invited_by ->
        befriend(user, target)
        :friend

      :invited ->
        :invited

      :friend ->
        :friend

      :self ->
        :self
    end
  end

  # ----------------------------------------------------------------------
  # Queries

  @spec friends_query(User.t(), User.t()) :: Queryable.t() | error()
  def friends_query(%User{id: id} = user, %User{id: id}) do
    User
    |> join(:left, [u], i in Item, on: u.id == i.contact_id)
    |> where([..., i], i.user_id == ^user.id)
  end

  def friends_query(_, _), do: {:error, :permission_denied}

  @spec sent_invitations_query(User.t(), User.t()) :: Queryable.t() | error()
  def sent_invitations_query(%User{id: id} = user, %User{id: id}),
    do: Invitation.sent_query(user)

  def sent_invitations_query(_, _), do: {:error, :permission_denied}

  @spec received_invitations_query(User.t(), User.t()) ::
          Queryable.t() | error()
  def received_invitations_query(%User{id: id} = user, %User{id: id}),
    do: Invitation.received_query(user)

  def received_invitations_query(_, _), do: {:error, :permission_denied}

  @spec items_query(User.t(), User.t()) :: Queryable.t() | error()
  def items_query(%User{id: id} = user, %User{id: id}),
    do: where(Item, [i], i.user_id == ^user.id)

  def items_query(_, _), do: {:error, :permission_denied}
end
