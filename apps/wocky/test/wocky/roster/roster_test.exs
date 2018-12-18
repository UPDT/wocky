defmodule Wocky.RosterTest do
  use Wocky.DataCase, async: true

  alias Faker.Lorem
  alias Faker.Name
  alias Wocky.Block
  alias Wocky.Repo
  alias Wocky.Repo.Factory
  alias Wocky.Repo.ID
  alias Wocky.Roster
  alias Wocky.Roster.Item, as: RosterItem
  alias Wocky.User

  setup do
    # A user with 5 contacts in a randomised subset of 5 groups
    user = Factory.insert(:user)

    contacts = for _ <- 1..5, do: Factory.insert(:user)

    groups = for _ <- 1..5, do: Lorem.word()
    Enum.map(contacts, &insert_friend_pair(user, &1, groups))

    rosterless_user = Factory.insert(:user)

    follower = Factory.insert(:user)
    followee = Factory.insert(:user)

    blocked_viewer = Factory.insert(:user)
    Block.block(follower, blocked_viewer)
    Block.block(blocked_viewer, followee)

    insert_follower_pair(follower, followee)

    system_user = Factory.insert(:user, roles: [User.system_role()])
    insert_friend_pair(user, system_user, [Lorem.word()])

    nil_handle_user = Factory.insert(:user, handle: nil)
    insert_friend_pair(nil_handle_user, user, [Lorem.word()])

    visible_contacts = Enum.sort([system_user | contacts])

    {:ok,
     user: user,
     all_contacts: Enum.sort([system_user, nil_handle_user | contacts]),
     visible_contacts: visible_contacts,
     contact: hd(contacts),
     rosterless_user: rosterless_user,
     follower: follower,
     followee: followee,
     blocked_viewer: blocked_viewer,
     groups: groups,
     system_user: system_user}
  end

  describe "get/2" do
    test "should return the roster item for the specified contact", ctx do
      Enum.map(ctx.all_contacts, fn c ->
        assert ctx.user |> Roster.get(c) |> Map.get(:contact) == c
      end)
    end
  end

  describe "put/1 when there is no existing entry for the contact" do
    setup do
      contact = Factory.insert(:user)
      {:ok, contact: contact}
    end

    test "should insert a new contact", ctx do
      name = Name.first_name()
      groups = take_random(ctx.groups)

      assert {:ok, %RosterItem{}} =
               Roster.put(%{
                 user_id: ctx.user.id,
                 contact_id: ctx.contact.id,
                 name: name,
                 groups: groups,
                 ask: :out,
                 subscription: :both
               })

      item = Roster.get(ctx.user, ctx.contact)
      assert item.contact == ctx.contact
      assert item.name == name
      assert item.ask == :out
      assert item.subscription == :both
      assert length(item.groups) == length(groups)
    end

    test "should not fail with an empty name", ctx do
      groups = take_random(ctx.groups)

      assert {:ok, %RosterItem{}} =
               Roster.put(%{
                 user_id: ctx.user.id,
                 contact_id: ctx.contact.id,
                 name: "",
                 groups: groups,
                 ask: :out,
                 subscription: :both
               })
    end

    test "should return an error for an invalid user id", ctx do
      assert {:error, _} =
               Roster.put(%{
                 user_id: ID.new(),
                 contact_id: ctx.contact.id,
                 name: "",
                 groups: [],
                 ask: :out,
                 subscription: :both
               })
    end

    test "should return an error for an invalid contact id", ctx do
      assert {:error, _} =
               Roster.put(%{
                 user_id: ctx.user.id,
                 contact_id: ID.new(),
                 name: "",
                 groups: [],
                 ask: :out,
                 subscription: :both
               })
    end
  end

  describe "put/1 when there is an existing entry for the contact" do
    test "should update the existing contact", ctx do
      new_name = Name.first_name()
      new_groups = take_random(ctx.groups)

      assert {:ok, %RosterItem{}} =
               Roster.put(%{
                 user_id: ctx.user.id,
                 contact_id: ctx.contact.id,
                 name: new_name,
                 groups: new_groups,
                 ask: :out,
                 subscription: :both
               })

      item = Roster.get(ctx.user, ctx.contact)
      assert item.contact == ctx.contact
      assert item.name == new_name
      assert item.ask == :out
      assert item.subscription == :both
      assert item.groups == new_groups
    end
  end

  describe "friend?/1" do
    test "should return true when a user is subscribed", ctx do
      assert friend?(ctx.user, ctx.contact)
    end

    test "should return false if the user has blocked the contact", ctx do
      Block.block(ctx.user, ctx.contact)

      refute friend?(ctx.user, ctx.contact)
    end

    test "should return true if the contact has blocked the user", ctx do
      Block.block(ctx.contact, ctx.user)

      refute friend?(ctx.user, ctx.contact)
    end

    test "should return false if the contact does not have 'both' subscription",
         ctx do
      Roster.put(%{
        user_id: ctx.contact.id,
        contact_id: ctx.user.id,
        name: Name.first_name(),
        groups: [],
        ask: :none,
        subscription: :from
      })

      refute friend?(ctx.user, ctx.contact)
    end

    test "should return false for non-existant contacts", ctx do
      refute friend?(ctx.user, Factory.build(:user))
      refute friend?(ctx.user, ctx.rosterless_user)
    end
  end

  describe "follower?/1" do
    test "should return true when a user is subscribed", ctx do
      assert follower?(ctx.user, ctx.contact)
    end

    test "should return false if the user has blocked the contact", ctx do
      Block.block(ctx.user, ctx.contact)

      refute follower?(ctx.user, ctx.contact)
    end

    test "should return false if the user is blocked by the contact", ctx do
      Block.block(ctx.contact, ctx.user)

      refute follower?(ctx.user, ctx.contact)
    end

    test "should return true if the user has 'to' subscription", ctx do
      assert follower?(ctx.follower, ctx.followee)
    end

    test "should return false if the user does not have 'both' or 'to' subscription",
         ctx do
      refute follower?(ctx.followee, ctx.follower)
    end

    test "should return false for non-existant contacts", ctx do
      refute follower?(ctx.user, Factory.build(:user))
      refute follower?(ctx.user, ctx.rosterless_user)
    end
  end

  describe "followee?/2" do
    test "should return true when a user is subscribed", ctx do
      assert followee?(ctx.user, ctx.contact)
    end

    test "should return false if the user has blocked the contact", ctx do
      Block.block(ctx.user, ctx.contact)

      refute followee?(ctx.user, ctx.contact)
    end

    test "should return false if the user is blocked by the contact", ctx do
      Block.block(ctx.contact, ctx.user)

      refute followee?(ctx.user, ctx.contact)
    end

    test "should return true if the user has 'from' subscription", ctx do
      assert followee?(ctx.followee, ctx.follower)
    end

    test "should return false if the user does not have 'both' or 'from' subscription",
         ctx do
      refute followee?(ctx.follower, ctx.followee)
    end

    test "should return false for non-existant contacts", ctx do
      refute followee?(ctx.user, Factory.build(:user))
      refute followee?(ctx.user, ctx.rosterless_user)
    end
  end

  describe "followers_query/2" do
    test "should return all followers", ctx do
      query = Roster.followers_query(ctx.followee, ctx.user)

      assert Repo.all(query) == [ctx.follower]
    end

    test "should exclude system users when set to do so", ctx do
      query = Roster.followers_query(ctx.user, ctx.user, false)

      assert Enum.sort(Repo.all(query)) ==
               ctx.visible_contacts -- [ctx.system_user]
    end

    test "should not return entries blocked by the requester", ctx do
      query = Roster.followers_query(ctx.followee, ctx.blocked_viewer)

      assert Repo.all(query) == []
    end
  end

  describe "followees_query/2" do
    test "should return all followees", ctx do
      query = Roster.followees_query(ctx.follower, ctx.user)

      assert Repo.all(query) == [ctx.followee]
    end

    test "should exclude system users when set to do so", ctx do
      query = Roster.followees_query(ctx.user, ctx.user, false)

      assert Enum.sort(Repo.all(query)) ==
               ctx.visible_contacts -- [ctx.system_user]
    end

    test "should not return entries blocked by the requester", ctx do
      query = Roster.followees_query(ctx.follower, ctx.blocked_viewer)

      assert Repo.all(query) == []
    end
  end

  describe "friends_query/2" do
    setup ctx do
      blocked_friend = Factory.insert(:user, %{first_name: "BLOCKYMCBLOCK"})
      insert_friend_pair(ctx.user, blocked_friend, [Lorem.word()])
      Block.block(blocked_friend, ctx.blocked_viewer)
      {:ok, blocked_friend: blocked_friend}
    end

    test "should return all friends", ctx do
      query = Roster.friends_query(ctx.user, ctx.follower)

      assert Enum.sort(Repo.all(query)) ==
               Enum.sort([ctx.blocked_friend | ctx.visible_contacts])
    end

    test "should exclude system users when set to do so", ctx do
      query = Roster.friends_query(ctx.user, ctx.user, false)

      assert Enum.sort(Repo.all(query)) ==
               Enum.sort([ctx.blocked_friend | ctx.visible_contacts]) --
                 [ctx.system_user]
    end

    test "should not return entries blocked by the requester", ctx do
      query = Roster.friends_query(ctx.user, ctx.blocked_viewer)

      assert Enum.sort(Repo.all(query)) == ctx.visible_contacts
    end
  end

  describe "relationship/2" do
    test "should return :self when both user IDs are equal", ctx do
      assert Roster.relationship(ctx.user, ctx.user) == :self
    end

    test "should return :friend where the two users are friends", ctx do
      assert Roster.relationship(ctx.user, ctx.contact) == :friend
      assert Roster.relationship(ctx.contact, ctx.user) == :friend
    end

    test "should return :follower where user a is following user b", ctx do
      assert Roster.relationship(ctx.follower, ctx.followee) == :follower
    end

    test "should return :followee where user b is following user a", ctx do
      assert Roster.relationship(ctx.followee, ctx.follower) == :followee
    end

    test "should return :none if the users have no relationship", ctx do
      assert Roster.relationship(ctx.user, ctx.rosterless_user) == :none
      assert Roster.relationship(ctx.rosterless_user, ctx.user) == :none
    end
  end

  describe "relationship management functions" do
    setup do
      user2 = Factory.insert(:user)
      {:ok, user2: user2}
    end

    test "befriend/2 when there is no existing relationship", ctx do
      assert :ok = Roster.befriend(ctx.user, ctx.user2)
      assert friend?(ctx.user, ctx.user2)
    end

    test "befriend/2 when there is an existing relationship", ctx do
      name = Name.first_name()
      name2 = Name.first_name()

      Factory.insert(
        :roster_item,
        name: name,
        user_id: ctx.user.id,
        contact_id: ctx.user2.id,
        subscription: :from,
        name: name
      )

      Factory.insert(
        :roster_item,
        user_id: ctx.user2.id,
        contact_id: ctx.user.id,
        subscription: :to,
        name: name2
      )

      assert :ok = Roster.befriend(ctx.user, ctx.user2)
      assert friend?(ctx.user, ctx.user2)
      assert Roster.get(ctx.user, ctx.user2).name == name
      assert Roster.get(ctx.user2, ctx.user).name == name2
    end

    test "follow/2 when there is no existing relationship", ctx do
      assert :ok = Roster.follow(ctx.user, ctx.user2)

      assert follower?(ctx.user, ctx.user2)
      refute friend?(ctx.user, ctx.user2)
    end

    test "follow/2 when there is an existing relationship", ctx do
      name = Name.first_name()
      name2 = Name.first_name()

      Factory.insert(
        :roster_item,
        name: name,
        user_id: ctx.user.id,
        contact_id: ctx.user2.id,
        subscription: :both,
        name: name
      )

      Factory.insert(
        :roster_item,
        user_id: ctx.user2.id,
        contact_id: ctx.user.id,
        subscription: :both,
        name: name2
      )

      assert :ok = Roster.follow(ctx.user, ctx.user2)
      assert follower?(ctx.user, ctx.user2)
      assert Roster.get(ctx.user, ctx.user2).name == name
      assert Roster.get(ctx.user2, ctx.user).name == name2
    end

    test "unfriend/2 when users are friends", ctx do
      Roster.befriend(ctx.user, ctx.user2)

      assert :ok = Roster.unfriend(ctx.user, ctx.user2)
      assert Roster.relationship(ctx.user, ctx.user2) == :none
    end

    test "unfriend/2 when a is following b", ctx do
      Roster.follow(ctx.user, ctx.user2)

      assert :ok = Roster.unfriend(ctx.user, ctx.user2)
      assert Roster.relationship(ctx.user, ctx.user2) == :none
    end

    test "unfriend/2 when b is following a", ctx do
      Roster.follow(ctx.user, ctx.user2)

      assert :ok = Roster.unfriend(ctx.user, ctx.user2)
      assert Roster.relationship(ctx.user, ctx.user2) == :none
    end

    test "unfriend/2 when there is no existing relationship", ctx do
      assert :ok = Roster.unfriend(ctx.user, ctx.user2)
      assert Roster.relationship(ctx.user, ctx.user2) == :none
    end
  end

  defp friend?(a, b), do: b |> Roster.get(a) |> Roster.friend?()
  defp follower?(a, b), do: b |> Roster.get(a) |> Roster.follower?()
  defp followee?(a, b), do: b |> Roster.get(a) |> Roster.followee?()

  defp insert_friend_pair(user, contact, groups) do
    a =
      Factory.insert(
        :roster_item,
        user_id: user.id,
        contact_id: contact.id,
        groups: take_random(groups)
      )

    b =
      Factory.insert(
        :roster_item,
        user_id: contact.id,
        contact_id: user.id,
        groups: take_random(groups)
      )

    {a, b}
  end

  defp insert_follower_pair(follower, followee) do
    Factory.insert(
      :roster_item,
      subscription: :from,
      user_id: followee.id,
      contact_id: follower.id
    )

    Factory.insert(
      :roster_item,
      subscription: :to,
      user_id: follower.id,
      contact_id: followee.id
    )
  end

  defp take_random(list) do
    Enum.take_random(list, :rand.uniform(length(list)))
  end
end
