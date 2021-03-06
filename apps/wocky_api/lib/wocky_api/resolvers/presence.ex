# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule WockyAPI.Resolvers.Presence do
  @moduledoc "GraphQL resolver for presence data"

  import WockyAPI.Resolvers.Utils

  alias Wocky.Account.User
  alias Wocky.Presence

  # -------------------------------------------------------------------
  # Queries

  def get_presence_status(other_user, args, context) do
    {:ok, %{status: status}} = get_presence(other_user, args, context)
    {:ok, status}
  end

  def get_presence(%User{presence: nil} = other_user, _args, %{
        context: %{current_user: user}
      }) do
    {:ok, Presence.get(other_user, user)}
  end

  def get_presence(%User{presence: presence}, _args, _context) do
    {:ok, presence}
  end

  # -------------------------------------------------------------------
  # Mutations

  def presence_status(args, %{context: %{current_user: user}}) do
    Presence.set_status(user, args[:input][:status])
    {:ok, true}
  end

  # -------------------------------------------------------------------
  # Subscriptions

  def presence_subscription_topic(user_id),
    do: "presence_subscription_" <> user_id

  def presence_catchup(user) do
    {:ok, Presence.connect(user)}
  end

  def publish_presence(contact, recipient_id) do
    recipient_id
    |> presence_subscription_topic()
    |> publish_subscription(:presence, contact)
  end
end
