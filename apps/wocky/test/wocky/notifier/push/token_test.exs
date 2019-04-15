defmodule Wocky.Notifier.Push.TokenTest do
  use Wocky.DataCase, async: true

  alias Wocky.Notifier.Push.Token

  @attrs [:user_id, :device, :token]

  test "required attributes" do
    changeset = Token.register_changeset(%{})
    refute changeset.valid?

    for a <- @attrs do
      assert "can't be blank" in errors_on(changeset)[a]
    end
  end
end
