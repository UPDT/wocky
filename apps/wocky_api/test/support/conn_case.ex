defmodule WockyAPI.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common datastructures and query the data layer.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate
  use Phoenix.ConnTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Phoenix.ConnTest

  using do
    quote do
      alias Wocky.Repo.Factory

      # Import conveniences for testing with connections
      use Phoenix.ConnTest

      import WockyAPI.Router.Helpers
      import WockyAPI.ConnHelper

      # The default endpoint for testing
      @endpoint WockyAPI.Endpoint
    end
  end

  setup tags do
    :ok = Sandbox.checkout(Wocky.Repo)

    unless tags[:async] do
      Sandbox.mode(Wocky.Repo, {:shared, self()})
    end

    {:ok, conn: ConnTest.build_conn()}
  end
end
