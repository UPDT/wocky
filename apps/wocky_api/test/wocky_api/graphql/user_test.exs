defmodule WockyAPI.GraphQL.UserTest do
  use WockyAPI.GraphQLCase, async: true

  alias Faker.Name
  alias Wocky.Block
  alias Wocky.Push
  alias Wocky.Push.Token
  alias Wocky.Repo
  alias Wocky.Repo.{Factory, ID, Timestamp}
  alias Wocky.Roster
  alias Wocky.User
  alias Wocky.User.{BotEvent, Location}

  setup do
    [user, user2] = Factory.insert_list(2, :user)

    {:ok, user: user, user2: user2}
  end

  describe "current user" do
    @query """
    {
      currentUser {
        id
        firstName
        email
        media {
          tros_url
        }
      }
    }
    """

    test "get user info", %{user: user} do
      result = run_query(@query, user)

      refute has_errors(result)

      assert result.data == %{
               "currentUser" => %{
                 "id" => user.id,
                 "firstName" => user.first_name,
                 "email" => user.email,
                 "media" => %{
                   "tros_url" => user.image_url
                 }
               }
             }
    end

    @query """
    query ($id: UUID!) {
      user (id: $id) {
        id
        ... on CurrentUser {
          email
        }
      }
    }
    """

    test "get info via user query", %{user: user} do
      result = run_query(@query, user, %{"id" => user.id})

      refute has_errors(result)

      assert result.data == %{
               "user" => %{
                 "id" => user.id,
                 "email" => user.email
               }
             }
    end

    @query """
    {
      currentUser {
        id
      }
    }

    """

    test "get user info anonymously" do
      result = run_query(@query)

      assert error_count(result) == 1
      assert error_msg(result) =~ "requires an authenticated user"
      assert result.data == %{"currentUser" => nil}
    end

    @query """
    mutation ($values: UserUpdateInput!) {
      userUpdate (input: {values: $values}) {
        successful
        result {
          id
        }
      }
    }
    """

    test "update user info", %{user: user} do
      new_name = Name.first_name()

      result =
        run_query(@query, user, %{"values" => %{"first_name" => new_name}})

      refute has_errors(result)

      assert result.data == %{
               "userUpdate" => %{
                 "successful" => true,
                 "result" => %{
                   "id" => user.id
                 }
               }
             }

      assert Repo.get(User, user.id).first_name == new_name
    end

    @query """
    mutation ($enable: Boolean!, $expire: DateTime) {
      userHide (input: {enable: $enable, expire: $expire}) {
        result
      }
    }
    """

    test "set user as permanently hidden", %{user: user} do
      result = run_query(@query, user, %{"enable" => true})

      refute has_errors(result)

      assert result.data == %{"userHide" => %{"result" => true}}

      assert User.hidden_state(Repo.get(User, user.id)) == {true, nil}
    end

    test "set user as not hidden", %{user: user} do
      result = run_query(@query, user, %{"enable" => false})

      refute has_errors(result)

      assert result.data == %{"userHide" => %{"result" => true}}

      assert User.hidden_state(Repo.get(User, user.id)) == {false, nil}
    end

    test "set user as temporarally hidden", %{user: user} do
      ts = Timestamp.shift(days: 1) |> Timestamp.to_string!()
      result = run_query(@query, user, %{"enable" => true, "expire" => ts})

      refute has_errors(result)

      assert result.data == %{"userHide" => %{"result" => true}}

      assert User.hidden_state(Repo.get(User, user.id)) ==
               {true, Timestamp.from_string!(ts)}
    end
  end

  describe "other user" do
    @query """
    query ($id: String!) {
      user (id: $id) {
        id
        handle
      }
    }
    """

    test "get user info", %{user: user, user2: user2} do
      result = run_query(@query, user, %{"id" => user2.id})

      refute has_errors(result)

      assert result.data == %{
               "user" => %{
                 "id" => user2.id,
                 "handle" => user2.handle
               }
             }
    end

    test "get user info with non-existant ID", %{user: user} do
      result = run_query(@query, user, %{"id" => ID.new()})

      assert error_count(result) == 1
      assert error_msg(result) =~ "User not found"
      assert result.data == %{"user" => nil}
    end

    test "get user info with invalid ID", %{user: user} do
      result = run_query(@query, user, %{"id" => "not_an_id"})

      assert error_count(result) == 1
      assert error_msg(result) =~ "invalid value"
      refute has_data(result)
    end

    test "get user info for blocked user", %{user: user, user2: user2} do
      Block.block(user2, user)

      result = run_query(@query, user, %{"id" => user2.id})

      assert error_count(result) == 1
      assert error_msg(result) =~ "User not found"
      assert result.data == %{"user" => nil}
    end

    test "get user info anonymously", %{user2: user2} do
      result = run_query(@query, nil, %{"id" => user2.id})

      refute has_errors(result)

      assert result.data == %{
               "user" => %{
                 "id" => user2.id,
                 "handle" => user2.handle
               }
             }
    end

    test "get user info anonymously with non-existant ID" do
      result = run_query(@query, nil, %{"id" => ID.new()})

      assert error_count(result) == 1
      assert error_msg(result) =~ "User not found"
      assert result.data == %{"user" => nil}
    end
  end

  describe "push notification mutations" do
    @query """
    mutation ($input: PushNotificationsEnableInput!) {
      pushNotificationsEnable (input: $input) {
        successful
      }
    }
    """

    test "enable notifications with defaults", %{user: user} do
      device = Factory.device()
      token = ID.new()

      input = %{
        "device" => device,
        "token" => token
      }

      result = run_query(@query, user, %{"input" => input})

      refute has_errors(result)

      assert result.data == %{
               "pushNotificationsEnable" => %{
                 "successful" => true
               }
             }

      assert %Token{
               device: ^device,
               token: ^token,
               platform: :apns,
               dev_mode: false,
               valid: true
             } = Repo.get_by(Token, user_id: user.id)
    end

    test "enable notifications with no defaults", %{user: user} do
      device = Factory.device()
      token = ID.new()

      input = %{
        "device" => device,
        "token" => token,
        "platform" => "APNS",
        "devMode" => true
      }

      result = run_query(@query, user, %{"input" => input})

      refute has_errors(result)

      assert result.data == %{
               "pushNotificationsEnable" => %{
                 "successful" => true
               }
             }

      assert %Token{
               device: ^device,
               token: ^token,
               platform: :apns,
               dev_mode: true,
               valid: true
             } = Repo.get_by(Token, user_id: user.id)
    end

    @query """
    mutation ($input: PushNotificationsDisableInput!) {
      pushNotificationsDisable (input: $input) {
        successful
      }
    }
    """

    test "disable notifications", %{user: user} do
      device = Factory.device()

      Push.enable(user, device, ID.new())

      result = run_query(@query, user, %{"input" => %{"device" => device}})

      refute has_errors(result)

      assert result.data == %{
               "pushNotificationsDisable" => %{
                 "successful" => true
               }
             }

      assert %Token{
               device: ^device,
               valid: false
             } = Repo.get_by(Token, user_id: user.id)
    end
  end

  describe "location queries" do
    setup %{user: user} do
      bot = Factory.insert(:bot, user: user)
      loc = Factory.insert(:location, user_id: user.id)
      BotEvent.insert(user, loc.device, bot, loc, :enter)

      {:ok, loc: loc, bot: bot}
    end

    @query """
    query ($device: String!) {
      currentUser {
        locations (device: $device, first: 1) {
          totalCount
          edges {
            node {
              lat
              lon
              accuracy
              isFetch
            }
          }
        }
      }
    }
    """

    test "get locations", %{user: user, loc: loc} do
      result = run_query(@query, user, %{"device" => loc.device})

      refute has_errors(result)

      assert result.data == %{
               "currentUser" => %{
                 "locations" => %{
                   "totalCount" => 1,
                   "edges" => [
                     %{
                       "node" => %{
                         "lon" => loc.lon,
                         "lat" => loc.lat,
                         "accuracy" => loc.accuracy,
                         "isFetch" => false
                       }
                     }
                   ]
                 }
               }
             }
    end

    @query """
    query ($device: String!) {
      currentUser {
        locations (device: $device, first: 1) {
          totalCount
          edges {
            node {
              events (first: 1) {
                totalCount
                edges {
                  node {
                    event
                  }
                }
              }
            }
          }
        }
      }
    }
    """

    test "get events from location", %{user: user, loc: loc} do
      result = run_query(@query, user, %{"device" => loc.device})

      refute has_errors(result)

      assert result.data == %{
               "currentUser" => %{
                 "locations" => %{
                   "totalCount" => 1,
                   "edges" => [
                     %{
                       "node" => %{
                         "events" => %{
                           "totalCount" => 1,
                           "edges" => [%{"node" => %{"event" => "ENTER"}}]
                         }
                       }
                     }
                   ]
                 }
               }
             }
    end

    @query """
    query ($device: String!) {
      currentUser {
        locationEvents (device: $device, first: 1) {
          totalCount
          edges {
            node {
              event
              location {
                lat
                lon
              }
              bot {
                id
              }
            }
          }
        }
      }
    }
    """

    test "get all location events", %{user: user, bot: bot, loc: loc} do
      result = run_query(@query, user, %{"device" => loc.device})

      refute has_errors(result)

      assert result.data == %{
               "currentUser" => %{
                 "locationEvents" => %{
                   "totalCount" => 1,
                   "edges" => [
                     %{
                       "node" => %{
                         "event" => "ENTER",
                         "location" => %{
                           "lat" => loc.lat,
                           "lon" => loc.lon
                         },
                         "bot" => %{
                           "id" => bot.id
                         }
                       }
                     }
                   ]
                 }
               }
             }
    end
  end

  describe "location mutations" do
    @query """
    mutation ($input: UserLocationUpdateInput!) {
      userLocationUpdate (input: $input) {
        successful
      }
    }
    """

    test "set location", %{user: user} do
      lat = :rand.uniform() * 89.0
      lon = :rand.uniform() * 179.0
      accuracy = :rand.uniform() * 10.0
      device = Factory.device()

      location_input = %{
        "lat" => lat,
        "lon" => lon,
        "accuracy" => accuracy,
        "device" => device,
        "isFetch" => true
      }

      result = run_query(@query, user, %{"input" => location_input})

      refute has_errors(result)

      assert result.data == %{
               "userLocationUpdate" => %{
                 "successful" => true
               }
             }

      assert %Location{
               lat: ^lat,
               lon: ^lon,
               device: ^device,
               accuracy: ^accuracy,
               is_fetch: true
             } = Repo.get_by(Location, user_id: user.id)
    end

    test "invalid location", %{user: user} do
      location_input = %{
        "lat" => :rand.uniform() * 89.0,
        "lon" => :rand.uniform() * 179.0,
        "accuracy" => -1.0,
        "device" => Factory.device()
      }

      result = run_query(@query, user, %{"input" => location_input})

      refute has_errors(result)

      assert result.data == %{
               "userLocationUpdate" => %{
                 "successful" => false
               }
             }

      assert Repo.get_by(Location, user_id: user.id) == nil
    end

    @query """
    mutation {
      userLocationGetToken {
        successful
        result
      }
    }
    """

    test "get location token", %{user: user} do
      result = run_query(@query, user, %{})

      refute has_errors(result)

      assert %{
               "userLocationGetToken" => %{
                 "successful" => true,
                 "result" => token
               }
             } = result.data

      assert is_binary(token)
    end
  end

  describe "contacts" do
    @query """
    query ($rel: UserContactRelationship) {
      currentUser {
        contacts (first: 1, relationship: $rel) {
          totalCount
          edges {
            relationship
            created_at
            node {
              id
            }
          }
        }
      }
    }
    """

    test "get contacts by relationship", %{user: user, user2: user2} do
      Roster.befriend(user, user2)
      id2 = user2.id

      for rel <- [nil, "FRIEND"] do
        result = run_query(@query, user, %{"rel" => rel})

        refute has_errors(result)

        assert %{
                 "currentUser" => %{
                   "contacts" => %{
                     "edges" => [
                       %{
                         "node" => %{"id" => ^id2},
                         "relationship" => "FRIEND",
                         "created_at" => _
                       }
                     ],
                     "totalCount" => 1
                   }
                 }
               } = result.data
      end
    end

    test "get contacts by relationship 'none'", %{user: user} do
      result = run_query(@query, user, %{"rel" => "NONE"})

      assert has_errors(result)

      assert [%{message: "unsupported"}] = result.errors
    end
  end

  describe "invitation codes" do
    @query """
    mutation {
      userInviteMakeCode {
        successful
        result
      }
    }
    """

    test "get invitation code", %{user: user} do
      result = run_query(@query, user)

      refute has_errors(result)

      assert %{
               "userInviteMakeCode" => %{
                 "successful" => true,
                 "result" => code
               }
             } = result.data

      assert is_binary(code)
      assert byte_size(code) > 1
    end

    @query """
    mutation ($code: String!) {
      userInviteRedeemCode(input: {code: $code}) {
        result
      }
    }
    """

    test "redeem invitation code", %{user: user} do
      inviter = Factory.insert(:user)
      code = User.make_invite_code(inviter)

      result = run_query(@query, user, %{"code" => code})
      refute has_errors(result)
      assert result.data == %{"userInviteRedeemCode" => %{"result" => true}}
    end
  end

  describe "delete user mutation" do
    test "Should be false with no related bots", %{user: user} do
      query = "mutation { userDelete { result } }"
      result = run_query(query, user)
      refute has_errors(result)
      assert result.data == %{"userDelete" => %{"result" => true}}
      assert User.get_user(user.id) == nil
    end
  end

  describe "friend invite mutation" do
    @query """
    mutation ($userId: UUID!) {
      friendInvite(input: {userId: $userId}) {
        successful
        result
      }
    }
    """
    test "should make a invited user from a non-relationship", shared do
      result = run_query(@query, shared.user, %{"userId" => shared.user2.id})
      refute has_errors(result)

      assert result.data == %{
               "friendInvite" => %{
                 "successful" => true,
                 "result" => "INVITED"
               }
             }

      assert Roster.relationship(shared.user, shared.user2) == :invited
    end

    test "should make a friend from a invited_by", shared do
      Roster.invite(shared.user2, shared.user)
      result = run_query(@query, shared.user, %{"userId" => shared.user2.id})
      refute has_errors(result)

      assert result.data == %{
               "friendInvite" => %{
                 "successful" => true,
                 "result" => "FRIEND"
               }
             }

      assert Roster.relationship(shared.user, shared.user2) == :friend
    end

    test "should return an error for a blocked user", shared do
      Block.block(shared.user2, shared.user)
      result = run_query(@query, shared.user, %{"userId" => shared.user2.id})
      assert has_errors(result)
      assert error_msg(result) =~ "Invalid user"
    end

    test "should return an error if you try to follow yourself", shared do
      result = run_query(@query, shared.user, %{"userId" => shared.user.id})
      assert has_errors(result)
      assert error_msg(result) =~ "Invalid user"
    end

    test "should return an error for a non-existant", shared do
      result = run_query(@query, shared.user, %{"userId" => ID.new()})
      assert has_errors(result)
      assert error_msg(result) =~ "Invalid user"
    end
  end

  describe "unfriend mutation" do
    @query """
    mutation ($userId: UUID!) {
      unfriend(input: {userId: $userId}) {
        successful
        result
      }
    }
    """
    test "should remove all relationship with a friend", shared do
      Roster.befriend(shared.user, shared.user2)
      result = run_query(@query, shared.user, %{"userId" => shared.user2.id})
      refute has_errors(result)

      assert result.data == %{
               "unfriend" => %{
                 "successful" => true,
                 "result" => true
               }
             }

      assert Roster.relationship(shared.user, shared.user2) == :none
    end

    test "should remove all relationship with an invitee", shared do
      Roster.invite(shared.user, shared.user2)
      result = run_query(@query, shared.user, %{"userId" => shared.user2.id})
      refute has_errors(result)

      assert result.data == %{
               "unfriend" => %{
                 "successful" => true,
                 "result" => true
               }
             }

      assert Roster.relationship(shared.user, shared.user2) == :none
    end

    test "should remove all relationship with an invited_by", shared do
      Roster.invite(shared.user2, shared.user)
      result = run_query(@query, shared.user, %{"userId" => shared.user2.id})
      refute has_errors(result)

      assert result.data == %{
               "unfriend" => %{
                 "successful" => true,
                 "result" => true
               }
             }

      assert Roster.relationship(shared.user, shared.user2) == :none
    end

    test "should return an error for a blocked user", shared do
      Block.block(shared.user2, shared.user)
      result = run_query(@query, shared.user, %{"userId" => shared.user2.id})
      assert has_errors(result)
      assert error_msg(result) =~ "Invalid user"
    end

    test "should return an error if you try to unfriend yourself", shared do
      result = run_query(@query, shared.user, %{"userId" => shared.user.id})
      assert has_errors(result)
      assert error_msg(result) =~ "Invalid user"
    end

    test "should return an error for a non-existant", shared do
      result = run_query(@query, shared.user, %{"userId" => ID.new()})
      assert has_errors(result)
      assert error_msg(result) =~ "Invalid user"
    end
  end

  describe "freinds connection" do
    @query """
    query {
      currentUser {
        friends (first: 1) {
          totalCount
          edges {
            node {
              user { id }
              name
              created_at
            }
          }
        }
      }
    }
    """

    test "get friends", %{user: user, user2: user2} do
      Roster.befriend(user, user2)
      name = Name.name()
      Roster.set_name(user, user2, name)
      id2 = user2.id

      result = run_query(@query, user)

      refute has_errors(result)

      assert %{
               "currentUser" => %{
                 "friends" => %{
                   "edges" => [
                     %{
                       "node" => %{
                         "user" => %{"id" => ^id2},
                         "name" => ^name,
                         "created_at" => _
                       }
                     }
                   ],
                   "totalCount" => 1
                 }
               }
             } = result.data
    end
  end

  describe "sent_invitations connection" do
    @query """
    query {
      currentUser {
        sentInvitations (first: 1) {
          totalCount
          edges {
            node {
              sender { id }
              recipient { id }
              created_at
            }
          }
        }
      }
    }
    """

    test "get sent_invitations", %{user: user, user2: user2} do
      Roster.invite(user, user2)
      id = user.id
      id2 = user2.id

      result = run_query(@query, user)

      refute has_errors(result)

      assert %{
               "currentUser" => %{
                 "sentInvitations" => %{
                   "edges" => [
                     %{
                       "node" => %{
                         "sender" => %{"id" => ^id},
                         "recipient" => %{"id" => ^id2},
                         "created_at" => _
                       }
                     }
                   ],
                   "totalCount" => 1
                 }
               }
             } = result.data
    end
  end

  describe "received_invitations connection" do
    @query """
    query {
      currentUser {
        receivedInvitations (first: 1) {
          totalCount
          edges {
            node {
              sender { id }
              recipient { id }
              created_at
            }
          }
        }
      }
    }
    """

    test "get received_invitations", %{user: user, user2: user2} do
      Roster.invite(user2, user)
      id = user.id
      id2 = user2.id

      result = run_query(@query, user)

      refute has_errors(result)

      assert %{
               "currentUser" => %{
                 "receivedInvitations" => %{
                   "edges" => [
                     %{
                       "node" => %{
                         "sender" => %{"id" => ^id2},
                         "recipient" => %{"id" => ^id},
                         "created_at" => _
                       }
                     }
                   ],
                   "totalCount" => 1
                 }
               }
             } = result.data
    end
  end

  describe "naming a friend" do
    @query """
    mutation ($user_id: UUID!, $name: String!) {
      friendName (input: {user_id: $user_id, name: $name}) {
        successful
        result
      }
    }
    """

    test "assign a name to a friend", %{user: user, user2: user2} do
      Roster.befriend(user, user2)
      new_name = Name.name()

      result =
        run_query(@query, user, %{"user_id" => user2.id, "name" => new_name})

      refute has_errors(result)

      assert result.data == %{
               "friendName" => %{
                 "successful" => true,
                 "result" => true
               }
             }

      assert Roster.get_item(user, user2).name == new_name
    end

    test "should fail when the user doesn't exist", %{user: user} do
      new_name = Name.name()

      result =
        run_query(@query, user, %{"user_id" => ID.new(), "name" => new_name})

      assert has_errors(result)
      assert error_msg(result) =~ "User not found"
    end

    test "should fail when the user is not a friend", %{
      user: user,
      user2: user2
    } do
      new_name = Name.name()

      result =
        run_query(@query, user, %{"user_id" => user2.id, "name" => new_name})

      assert has_errors(result)
      assert error_msg(result) =~ "User not found"
    end
  end
end
