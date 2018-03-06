defmodule WockyAPI.UserResolver do
  @moduledoc "GraphQL resolver for user objects"

  alias Wocky.Repo
  alias Wocky.User

  def get_profile(_root, _args, %{context: %{current_user: user}}) do
    {:ok, user}
  end

  def update_profile(_root, args, %{context: %{current_user: user}}) do
    input = args[:input]
    cmi = input[:client_mutation_id]
    case User.update(user, input) do
      {:ok, user} ->
        {:ok, %{client_mutation_id: cmi, profile: user}}

      {:error, _} ->
        {:error, "Could not update profile"}
    end
  end

  def get_contacts(_root, _args, _info) do
    {:ok, %{
      total_count: 0,
      page_info: %{has_next_page: false, has_previous_page: false},
      edges: []
    }}
  end

  def get_home_stream(_root, _args, _info) do
    {:ok, %{
      total_count: 0,
      page_info: %{has_next_page: false, has_previous_page: false},
      edges: []
    }}
  end

  def get_conversations(_root, _args, _info) do
    {:ok, %{
      total_count: 0,
      page_info: %{has_next_page: false, has_previous_page: false},
      edges: []
    }}
  end

  def get_bots(_root, _args, %{context: %{current_user: user}}) do
    {:ok, %{
      total_count: User.bot_count(user),
      page_info: %{has_next_page: false, has_previous_page: false},
      edges: for bot <- User.get_owned_bots(user) do
        %{node: bot, relationship: :owned, cursor: bot.id}
      end
    }}
  end

  def get_user(_root, args, %{context: %{current_user: _current_user}}) do
    Repo.get(User, args[:id])
  end
end