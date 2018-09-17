defmodule Wocky.Bot.InvitationTest do
  use Wocky.WatcherHelper

  alias Faker.Code
  alias Pigeon.APNS.Notification
  alias Wocky.Bot
  alias Wocky.Bot.Invitation
  alias Wocky.Push
  alias Wocky.Push.Sandbox
  alias Wocky.Repo
  alias Wocky.Repo.Factory

  setup do
    [user, invitee] = Factory.insert_list(2, :user, resource: "testing")
    bot = Factory.insert(:bot, user: user)

    Sandbox.clear_notifications(global: true)

    {:ok, user: user, invitee: invitee, bot: bot}
  end

  describe "put/3" do
    test "insert", shared do
      token = Code.isbn13()
      :ok = Push.enable(shared.invitee.id, shared.invitee.resource, token)
      assert {:ok, invitation} =
               Invitation.put(shared.invitee, shared.bot, shared.user)

      assert invitation == Repo.get_by(Invitation, id: invitation.id)
      assert invitation.accepted == nil

      msgs = Sandbox.wait_notifications(count: 1, timeout: 500, global: true)
      assert length(msgs) == 1

      assert %Notification{
               payload: %{
                 "aps" => %{"alert" => message}
               }
             } = hd(msgs)

      assert message == "@#{shared.user.handle} invited you to their bot"
    end

    test "refuse invitation to non-owned bot", shared do
      other_user = Factory.insert(:user)

      assert {:error, :permission_denied} ==
               Invitation.put(shared.invitee, shared.bot, other_user)
    end

    test "subsequent invitations should overwrite existing ones", shared do
      assert {:ok, invitation} =
               Invitation.put(shared.invitee, shared.bot, shared.user)

      assert {:ok, invitation2} =
               Invitation.put(shared.invitee, shared.bot, shared.user)

      assert invitation.id == invitation2.id

      assert DateTime.compare(invitation.updated_at, invitation2.updated_at) ==
               :lt
    end
  end

  describe "get/3" do
    setup shared do
      %{id: id} =
        Factory.insert(:invitation,
          user: shared.user,
          invitee: shared.invitee
        )

      {:ok, id: id}
    end

    test "User can get their own invitation", shared do
      assert %Invitation{} = Invitation.get(shared.id, shared.user)
    end

    test "Invitee can get their own invitation", shared do
      assert %Invitation{} = Invitation.get(shared.id, shared.invitee)
    end

    test "Unrelated user cannot get the invitation", shared do
      assert nil == Invitation.get(shared.id, Factory.insert(:user))
    end
  end

  describe "respond/3" do
    setup shared do
      invitation =
        Factory.insert(:invitation,
          user: shared.user,
          invitee: shared.invitee,
          bot: shared.bot
        )

      {:ok, invitation: invitation}
    end

    test "Invitee can accept", shared do
      assert {:ok, invitation} =
               Invitation.respond(shared.invitation, true, shared.invitee)

      assert invitation.accepted == true
    end

    test "Invitee becomes subscribed", shared do
      assert Bot.subscription(shared.bot, shared.invitee) == nil

      assert {:ok, invitation} =
               Invitation.respond(shared.invitation, true, shared.invitee)

      assert Bot.subscription(shared.bot, shared.invitee) == :guest
    end

    test "Invitee can decline", shared do
      assert {:ok, invitation} =
               Invitation.respond(shared.invitation, false, shared.invitee)

      assert invitation.accepted == false
    end

    test "Inviter cannot respond", shared do
      assert {:error, :permission_denied} =
               Invitation.respond(shared.invitation, false, shared.user)
    end

    test "Other user cannot respond", shared do
      assert {:error, :permission_denied} =
               Invitation.respond(
                 shared.invitation,
                 false,
                 Factory.insert(:user)
               )
    end
  end
end
