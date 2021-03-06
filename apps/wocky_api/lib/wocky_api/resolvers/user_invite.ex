# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule WockyAPI.Resolvers.UserInvite do
  @moduledoc """
  GraphQL resolver for invitations to join the service
  """
  alias Wocky.UserInvite
  alias Wocky.UserInvite.DynamicLink
  alias Wocky.UserInvite.InviteCode

  # -------------------------------------------------------------------
  # Queries

  def user_invite_get_sender(%{invite_code: code}, %{
        context: %{current_user: user}
      }) do
    case UserInvite.get_by_code(code, user) do
      %InviteCode{user: sender, share_type: share_type} ->
        {:ok, %{user: sender, share_type: share_type}}

      _ ->
        {:error, "Invitation code not found"}
    end
  end

  # -------------------------------------------------------------------
  # Mutations

  def user_invite_send(%{input: input}, %{context: %{current_user: user}}) do
    {:ok, UserInvite.send(input[:phone_number], input[:share_type], user)}
  end

  def user_invite_redeem_code(%{input: input}, %{context: %{current_user: user}}) do
    share_type = input[:share_type] || :disabled
    result = UserInvite.redeem_code(user, input[:code], share_type)
    {:ok, %{successful: result, result: result}}
  end

  def user_invite_make_code(_args, %{context: %{current_user: user}}) do
    with {:ok, code} <- UserInvite.make_code(user) do
      {:ok, %{successful: true, result: code}}
    end
  end

  def user_invite_make_url(%{input: input}, %{context: %{current_user: user}}) do
    share_type = input[:share_type]

    with {:ok, code} <- UserInvite.make_code(user, nil, share_type),
         {:ok, link} <- DynamicLink.invitation_link(code) do
      {:ok, %{successful: true, result: link}}
    end
  end

  def friend_bulk_invite(%{input: input}, %{context: %{current_user: user}}) do
    {:ok, UserInvite.send_multi(input[:phone_numbers], user)}
  end
end
