defmodule WockyAPI.GraphQL.NotificationSubscriptionTest do
  use WockyAPI.SubscriptionCase, async: false

  import Wocky.Eventually
  import WockyAPI.ChannelHelper

  alias Wocky.Bot
  alias Wocky.Bot.{Invitation, Subscription}
  alias Wocky.Repo
  alias Wocky.Repo.Factory
  alias Wocky.Roster

  setup_all do
    setup_watcher()
  end

  @subscription """
  subscription {
    notifications {
      __typename
      ... on Notification {
        data {
          __typename
          ... on BotItemNotification {
            user { id }
            bot { id }
            bot_item { id }
          }
          ... on GeofenceEventNotification {
            user { id }
            bot { id }
            event
          }
          ... on BotInvitationNotification {
            invitation { id }
            user { id }
            bot { id }
          }
          ... on BotInvitationResponseNotification {
            invitation { id }
            user { id }
            bot { id }
            accepted
          }
          ... on UserInvitationNotification {
            user { id }
          }
        }
        created_at
      }
      ... on NotificationDeleted {
        id
      }
    }
  }
  """
  setup %{user: user, socket: socket, token: token} do
    authenticate(user.id, token, socket)
    ref = push_doc(socket, @subscription)
    assert_reply ref, :ok, %{subscriptionId: subscription_id}, 1000

    user2 = Factory.insert(:user)
    bot = Factory.insert(:bot, user: user)
    Subscription.put(user2, bot)

    assert_eventually(Subscription.state(user, bot) == :subscribed)

    {:ok, user2: user2, bot: bot, ref: ref, subscription_id: subscription_id}
  end

  describe "event notifications" do
    test "user posts item to bot", %{
      user2: user2,
      bot: bot,
      subscription_id: subscription_id
    } do
      item = Factory.insert(:item, user: user2, bot: bot)

      assert_push "subscription:data", push, 2000

      assert_notification_update(push, subscription_id, %{
        "__typename" => "BotItemNotification",
        "bot" => %{"id" => bot.id},
        "bot_item" => %{"id" => item.id},
        "user" => %{"id" => user2.id}
      })
    end

    test "user enters bot", %{
      user2: user2,
      bot: bot,
      subscription_id: subscription_id
    } do
      Bot.visit(bot, user2, true)

      assert_push "subscription:data", push, 2000

      assert_notification_update(push, subscription_id, %{
        "__typename" => "GeofenceEventNotification",
        "bot" => %{"id" => bot.id},
        "user" => %{"id" => user2.id},
        "event" => "ENTER"
      })
    end

    test "user exits bot", %{
      user2: user2,
      bot: bot,
      subscription_id: subscription_id
    } do
      Bot.depart(bot, user2, true)

      assert_push "subscription:data", push, 2000

      assert_notification_update(push, subscription_id, %{
        "__typename" => "GeofenceEventNotification",
        "bot" => %{"id" => bot.id},
        "user" => %{"id" => user2.id},
        "event" => "EXIT"
      })
    end

    test "user receives an invitation", %{
      user: user,
      user2: user2,
      subscription_id: subscription_id
    } do
      bot2 = Factory.insert(:bot, user: user2)
      {:ok, invitation} = Invitation.put(user, bot2, user2)

      assert_push "subscription:data", push, 2000

      assert_notification_update(push, subscription_id, %{
        "__typename" => "BotInvitationNotification",
        "invitation" => %{"id" => to_string(invitation.id)},
        "bot" => %{"id" => bot2.id},
        "user" => %{"id" => user2.id}
      })
    end

    test "user responds to an invitation", %{
      user: user,
      user2: user2,
      bot: bot,
      subscription_id: subscription_id
    } do
      invitation =
        Factory.insert(:bot_invitation, user: user, invitee: user2, bot: bot)

      Invitation.respond(invitation, true, user2)

      assert_push "subscription:data", push, 2000

      assert_notification_update(push, subscription_id, %{
        "__typename" => "BotInvitationResponseNotification",
        "invitation" => %{"id" => to_string(invitation.id)},
        "bot" => %{"id" => bot.id},
        "user" => %{"id" => user2.id},
        "accepted" => true
      })
    end

    test "user invites", %{
      user: user,
      user2: user2,
      subscription_id: subscription_id
    } do
      Roster.invite(user2, user)

      assert_push "subscription:data", push, 2000

      assert_notification_update(push, subscription_id, %{
        "__typename" => "UserInvitationNotification",
        "user" => %{"id" => user2.id}
      })
    end
  end

  describe "notification deletion" do
    setup %{user: user} do
      notification = Factory.insert(:bot_item_notification, user: user)
      assert_push "subscription:data", _push, 2000

      {:ok, notification: notification}
    end

    test "notification deleted", %{
      notification: notification,
      subscription_id: subscription_id
    } do
      Repo.delete(notification)
      assert_push "subscription:data", push, 2000

      assert push == %{
               result: %{
                 data: %{
                   "notifications" => %{
                     "__typename" => "NotificationDeleted",
                     "id" => to_string(notification.id)
                   }
                 }
               },
               subscriptionId: subscription_id
             }
    end
  end

  defp assert_notification_update(push, subscription_id, data) do
    assert %{
             result: %{
               data: %{
                 "notifications" => %{
                   "__typename" => "Notification",
                   "created_at" => _,
                   "data" => ^data
                 }
               }
             },
             subscriptionId: ^subscription_id
           } = push
  end
end
