%%% @copyright 2016+ Hippware, Inc.
%%% @doc Integration test suite for wocky_reg
-module(rest_db_SUITE).

-export([all/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_testcase/2,
         end_per_testcase/2]).

-export([
         unauthorized/1,
         reset_db/1
        ]).

-include("wocky_db_seed.hrl").

-define(URL, "http://localhost:1096/wocky/v1/db/reset").

all() ->
    [unauthorized, reset_db].

init_per_suite(Config) ->
    ok = test_helper:ensure_wocky_is_running(),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(_CaseName, Config) ->
    wocky_db_seed:clear_tables(?LOCAL_CONTEXT, [auth_token]),
    wocky_db_seed:clear_tables(shared, [user, handle_to_user,
                                        phone_number_to_user]),
    ok = wocky_db_seed:seed_tables(?LOCAL_CONTEXT, [auth_token]),
    ok = wocky_db_seed:seed_tables(shared, [user, handle_to_user,
                                            phone_number_to_user]),
    Config.

end_per_testcase(_CaseName, Config) ->
    Config.


%%%===================================================================
%%% Tests
%%%===================================================================

unauthorized(_) ->
    JSON = encode(unauthorized_test_data()),
    {ok, {403, _}} = request(JSON).

reset_db(_) ->
    wocky_db_user:update_user(#{user => ?ALICE, server => ?LOCAL_CONTEXT,
                                external_id => <<"badexternalid">>}),

    JSON = encode(test_data()),
    {ok, {201, []}} = request(JSON),

    #{external_id := ?EXTERNAL_ID} =
    wocky_db_user:get_user_data(?ALICE, ?LOCAL_CONTEXT).

%%%===================================================================
%%% Helpers
%%%===================================================================

encode(Data) ->
    iolist_to_binary(mochijson2:encode({struct, Data})).

request(Body) ->
    httpc:request(post, {?URL, [{"Accept", "application/json"}],
                  "application/json", Body}, [], [{full_result, false}]).

unauthorized_test_data() ->
    [
     {user, ?ALICE},
     {resource, ?RESOURCE},
     {token, <<"asldkfjsadlkj">>}
    ].

test_data() ->
    [
     {user, ?ALICE},
     {resource, ?RESOURCE},
     {token, ?TOKEN}
    ].

