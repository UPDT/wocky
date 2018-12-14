defmodule Wocky.BlockTest do
  use Wocky.WatcherHelper

  alias Wocky.Block
  alias Wocky.Bot
  alias Wocky.Bot.Invitation
  alias Wocky.Repo
  alias Wocky.Repo.Factory
  alias Wocky.User.Notification

  setup do
    [u1, u2, u3] = Factory.insert_list(3, :user)
    bot = Factory.insert(:bot, user: u1)

    {:ok, user1: u1, user2: u2, user3: u3, bot: bot}
  end

  describe "basic functions" do
    test "block/2 should be bi-directional", %{user1: u1, user2: u2} do
      Block.block(u1, u2)

      assert Block.blocked?(u1, u2)
      assert Block.blocked?(u2, u1)
    end

    test "unblock/2 should remove a block", %{user1: u1, user2: u2} do
      Block.block(u1, u2)
      Block.unblock(u1, u2)

      refute Block.blocked?(u1, u2)
      refute Block.blocked?(u2, u1)
    end

    test "block should remain if both users block and one unblocks", %{
      user1: u1,
      user2: u2
    } do
      Block.block(u1, u2)
      Block.block(u2, u1)
      Block.unblock(u1, u2)

      assert Block.blocked?(u1, u2)
      assert Block.blocked?(u2, u1)
    end

    test "blocks_query/1", %{user1: u1, user2: u2} do
      Block.block(u1, u2)

      assert [block] = u1.id |> Block.blocks_query() |> Repo.all()
      assert block.blocker_id == u1.id
      assert block.blockee_id == u2.id
    end

    test "object_visible_query/3", ctx do
      Block.block(ctx.user1, ctx.user2)

      query =
        ctx.bot.id
        |> Bot.get_query()
        |> Block.object_visible_query(ctx.user2.id)

      assert is_nil(Repo.one(query))

      Block.unblock(ctx.user1, ctx.user2)

      refute is_nil(Repo.one(query))
    end
  end

  describe "block-triggered item deletion" do
    setup %{user1: user1, user2: user2} do
      invitation1 = Factory.insert(:invitation, user: user1, invitee: user2)
      invitation2 = Factory.insert(:invitation, user: user2, invitee: user1)

      notification1 =
        Factory.insert(:invitation_notification, user: user1, other_user: user2)

      notification2 =
        Factory.insert(:invitation_notification, user: user2, other_user: user1)

      Block.block(user1, user2)

      {:ok,
       invitation1: invitation1,
       invitation2: invitation2,
       notification1: notification1,
       notification2: notification2}
    end

    test "should delete invitations between the two users", ctx do
      refute_eventually(Repo.get(Invitation, ctx.invitation1.id), 500, 10)
      refute_eventually(Repo.get(Invitation, ctx.invitation2.id))
    end

    test "should delete notifications between the two users", ctx do
      refute_eventually(Repo.get(Notification, ctx.notification1.id))
      refute_eventually(Repo.get(Notification, ctx.notification2.id))
    end
  end
end
