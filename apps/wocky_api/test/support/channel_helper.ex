defmodule WockyAPI.ChannelHelper do
  @moduledoc """
  Helper functions for graphql channel tests
  """

  use Phoenix.ChannelTest

  import Absinthe.Phoenix.SubscriptionTest
  import ExUnit.Assertions

  def authenticate(user_id, token, socket) do
    authenticate = """
      mutation ($input: AuthenticateInput) {
        authenticate(input: $input) {
          user {
            id
          }
        }
      }
    """

    ref =
      push_doc(
        socket,
        authenticate,
        variables: %{input: %{token: token}}
      )

    assert_reply ref,
                 :ok,
                 %{
                   data: %{"authenticate" => %{"user" => %{"id" => ^user_id}}}
                 },
                 150

    ref
  end
end
