defmodule WockyAPI.GraphQL.AuthenticationTest do
  use WockyAPI.GraphQLCase

  alias Faker.Lorem
  alias Wocky.Repo.Factory
  alias WockyAPI.Factory, as: APIFactory

  @query """
  mutation ($token: String!) {
  authenticate (input: {token: $token}) {
      user {
        id
      }
    }
  }
  """

  describe "GraphQL in-band JWT authentication" do
    setup do
      user = Factory.insert(:user)
      jwt = APIFactory.get_test_token(user)
      {:ok, user: user, jwt: jwt}
    end

    test "successful authentication", %{user: user, jwt: jwt} do
      result = run_query(@query, nil, %{"token" => jwt})

      refute has_errors(result)
      assert result.data == %{"authenticate" => %{"user" => %{"id" => user.id}}}
    end

    test "unsuccessful authentication" do
      result = run_query(@query, nil, %{"token" => Lorem.word()})

      assert error_count(result) == 1
      assert error_msg(result) =~ "invalid user"
      assert result.data == %{"authenticate" => nil}
    end
  end
end
