defmodule WockyAPI.Resolvers.User do
  @moduledoc "GraphQL resolver for user objects"

  import Ecto.Query

  alias Absinthe.Relay.Connection
  alias Wocky.Blocking
  alias Wocky.Repo
  alias Wocky.Roster
  alias Wocky.User
  alias WockyAPI.Resolvers.Utils

  @default_search_results 50

  def get_current_user(_root, _args, %{context: %{current_user: user}}) do
    {:ok, user}
  end
  def get_current_user(_root, _args, _info) do
    {:ok, nil}
  end

  def update_user(_root, args, %{context: %{current_user: user}}) do
    input = args[:input]

    case User.update(user, input) do
      {:ok, user} ->
        {:ok, %{user: user, private_user_data: user}}

      {:error, _} ->
        {:error, "Could not update user"}
    end
  end

  def get_contacts(user, args, %{context: %{current_user: requestor}}) do
    query =
      case args[:relationship] do
        nil -> Roster.all_contacts_query(user.id, requestor.id, false)
        :friends -> Roster.friends_query(user.id, requestor.id, false)
        :followers -> Roster.followers_query(user.id, requestor.id, false)
        :followees -> Roster.followees_query(user.id, requestor.id, false)
      end

    query
    |> order_by(asc: :updated_at)
    |> Connection.from_query(&Repo.all/1, args)
    |> Utils.add_query(query)
    |> Utils.add_edge_parent(user)
  end

  def get_contact_relationship(_root, _args, %{
        source: %{node: target_user, parent: parent}
      }) do
    {:ok, Roster.relationship(parent, target_user)}
  end

  def get_home_stream(_root, args, %{context: %{current_user: _user}}) do
    Connection.from_list([], args)
  end

  def get_conversations(_root, args, %{context: %{current_user: _user}}) do
    Connection.from_list([], args)
  end

  def get_user(_root, %{id: id}, %{context: %{current_user: current_user}}) do
    with %User{} = user <- Repo.get(User, id),
         false <- Blocking.blocked?(current_user.id, id) do
           {:ok, user}
    else
      _ -> user_not_found(id)
    end
  end
  # This is kind of dumb - an anonymous user can see more than an authenticated
  # but blocked user...
  def get_user(_root, %{id: id}, _info) do
    with %User{} = user <- Repo.get(User, id) do
         {:ok, user}
    else
      _ -> user_not_found(id)
    end
  end

  def search_users(_root, %{limit: limit}, _info) when limit < 0 do
    {:error, "limit cannot be less than 0"}
  end
  def search_users(_root, %{search_term: search_term} = args,
                   %{context: %{current_user: current_user}}) do
    limit = args[:limit] || @default_search_results
    {:ok, User.search_by_name(search_term, current_user.id, limit)}
  end

  def set_location(_root, args, %{context: %{current_user: user}}) do
    location = args[:location]
    with :ok <- User.set_location(user, location[:resource], location[:lat],
                                  location[:lon], location[:accuracy]) do
                                    {:ok, true}
                                  end
  end

  defp user_not_found(id), do: {:error, "User not found: " <> id}
end