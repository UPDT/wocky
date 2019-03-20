defmodule Wocky.Callbacks.Block do
  @moduledoc """
  Callbacks for Block opertaions
  """

  use DawdleDB.Handler, type: Wocky.Block

  alias Wocky.{Block, Bot, Repo, User}
  alias Wocky.Bot.{Invitation, Item}
  alias Wocky.User.Notification

  def handle_insert(new) do
    %Block{blocker: blocker, blockee: blockee} =
      Repo.preload(new, [:blocker, :blockee])

    if blocker != nil && blockee != nil do
      # Delete content items on owned bots by blocker/blockee
      delete_bot_references(blocker, blockee)
      delete_bot_references(blockee, blocker)

      # Delete invitations
      Invitation.delete(blocker, blockee)
      Invitation.delete(blockee, blocker)

      # Delete notifications
      Notification.delete(blocker, blockee)
      Notification.delete(blockee, blocker)

      :ok
    end
  end

  defp delete_bot_references(a, b) do
    a
    |> User.get_owned_bots()
    |> Enum.each(fn bot ->
      Item.delete(bot, b)
      Bot.unsubscribe(bot, b)
    end)
  end
end
