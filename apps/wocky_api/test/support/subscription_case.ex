defmodule WockyAPI.SubscriptionCase do
  @moduledoc """
  Test case framework for Absinthe subscription tests
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use WockyAPI.ChannelCase
      use Absinthe.Phoenix.SubscriptionTest, schema: WockyAPI.Schema

      setup do
        user = Wocky.Repo.Factory.insert(:user)
        {:ok, {token, _}} = Wocky.Account.assign_token(user.id, "abc")
        {:ok, socket} =
          Phoenix.ChannelTest.connect(WockyAPI.UserSocket,
                                      %{"x-auth-user" => user.id,
                                        "x-auth-token" => token})
        {:ok, socket} =
          Absinthe.Phoenix.SubscriptionTest.join_absinthe(socket)
        {:ok, socket: socket, user: user}
      end
    end
  end
end
