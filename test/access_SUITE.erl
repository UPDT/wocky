%%% @copyright 2016+ Hippware, Inc.
%%% @doc Integration test suite mod_wocky_access.erl
-module(access_SUITE).
-compile(export_all).
-compile({parse_transform, fun_chain}).

-include_lib("ejabberd/include/jlib.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-include("wocky.hrl").
-include("wocky_db_seed.hrl").

-import(test_helper, [expect_iq_success/2]).

%%--------------------------------------------------------------------
%% Suite configuration
%%--------------------------------------------------------------------

all() -> [
          bot_access
         ].

suite() ->
    escalus:suite().


%%--------------------------------------------------------------------
%% Init & teardown
%%--------------------------------------------------------------------

init_per_suite(Config) ->
    ok = test_helper:ensure_wocky_is_running(),
    wocky_db:clear_user_tables(?LOCAL_CONTEXT),
    wocky_db_seed:seed_table(shared, bot),
    Users = escalus:get_users([alice]),
    fun_chain:first(Config,
        escalus:init_per_suite(),
        escalus:create_users(Users)
    ).

end_per_suite(Config) ->
    escalus:delete_users(Config, escalus:get_users([alice])),
    escalus:end_per_suite(Config).

init_per_testcase(CaseName, Config) ->
    escalus:init_per_testcase(CaseName, Config).

end_per_testcase(CaseName, Config) ->
    escalus:end_per_testcase(CaseName, Config).

%%--------------------------------------------------------------------
%% Tests
%%--------------------------------------------------------------------

bot_access(Config) ->
    escalus:story(Config, [{alice, 1}], fun(Alice) ->
      %% Alice can see her own bot
      expect_allow(
        expect_iq_success(
          access_query(bot_node(?BOT), ?ALICE_B_JID, <<"view">>), Alice)),

      %% Tim cannot see Alice's bot because he's not a friend
      expect_deny(
        expect_iq_success(
          access_query(bot_node(?BOT), ?TIM_B_JID, <<"view">>), Alice)),

      %% Bob can see the bot because he's an affiliate
      expect_allow(
        expect_iq_success(
          access_query(bot_node(?BOT), ?BOB_B_JID, <<"view">>), Alice)),

      %% Alice canedit it because she's the owner
      expect_allow(
        expect_iq_success(
          access_query(bot_node(?BOT), ?ALICE_B_JID, <<"modify">>), Alice)),
      expect_allow(
        expect_iq_success(
          access_query(bot_node(?BOT), ?ALICE_B_JID, <<"delete">>), Alice)),

      %% Bob cannot edit it because he's not the owner
      expect_deny(
        expect_iq_success(
          access_query(bot_node(?BOT), ?BOB_B_JID, <<"modify">>), Alice)),
      expect_deny(
        expect_iq_success(
          access_query(bot_node(?BOT), ?BOB_B_JID, <<"delete">>), Alice)),

      %% Nobody has permissions on a non-existant bot
      expect_deny(
        expect_iq_success(
          access_query(bot_node(?wocky_id:create()),
                       ?ALICE_B_JID, <<"view">>), Alice))
    end).

access_query(ID, Actor, Op) ->
    test_helper:iq_get(?NS_ACCESS,
                       #xmlel{name = <<"query">>,
                              attrs = [{<<"node">>, <<ID/binary>>},
                                       {<<"actor">>, Actor},
                                       {<<"op">>, Op}]}).

expect_allow(#xmlel{children = [#xmlel{name = <<"allow">>}]}) -> ok;
expect_allow(Stanza) -> ct:fail("Not an allow stanza: ~p", [Stanza]).
expect_deny(#xmlel{children = [#xmlel{name = <<"deny">>}]}) -> ok;
expect_deny(Stanza) -> ct:fail("Not a deny stanza: ~p", [Stanza]).
expect_redirect(#xmlel{children = [#xmlel{name = <<"redirect">>,
                                          children =
                                          [#xmlcdata{content = Target}]}]},
                Target) -> ok;
expect_redirect(Stanza, Target) ->
    ct:fail("Invalid redirect stanza (target ~p): ~p", [Target, Stanza]).

bot_node(ID) ->
    <<"bot/", ID/binary>>.
