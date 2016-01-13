%%% @copyright 2015+ Hippware, Inc.
%%% @doc Test suite for ejabberd_auth_cassandra.erl
-module(wocky_db_tests).

-include_lib("eunit/include/eunit.hrl").

-define(LONG_STRING, <<"Lorem ipsum dolor sit amet, consectetur cras amet.">>).

wocky_db_to_keyspace_test_() -> {
  "to_keyspace/1", [
    { "should replace non-alphanumeric characters with underscores", [
      ?_assertEqual(<<"abc123___">>, wocky_db:to_keyspace("abc123$!@"))
    ]},
    { "should truncate strings at 48 characters", [
      ?_assert(byte_size(?LONG_STRING) > 48),
      ?_assertEqual(48, byte_size(wocky_db:to_keyspace(?LONG_STRING)))
    ]}
]}.


%% This is a very simple test to verify that basic communication with
%% Cassandra works. It probably isn't worth testing this functionality more
%% thoroughly since at that point we would essentially be testing the
%% Cassandra driver.

wocky_db_api_smoke_test() ->
    ok = wocky_app:start(),

    Q1 = "INSERT INTO username_to_user (id, domain, username) VALUES (?, ?, ?)",
    Values = [
      [{id, now}, {domain, <<"localhost">>}, {username, <<"alice">>}],
      [{id, now}, {domain, <<"localhost">>}, {username, <<"bob">>}],
      [{id, now}, {domain, <<"localhost">>}, {username, <<"charlie">>}]
    ],
    {ok, _} = wocky_db:batch_query(shared, Q1, Values, unlogged, quorum),

    Q2 = "SELECT username FROM username_to_user",
    {ok, R1} = wocky_db:query(shared, Q2, quorum),
    ?assertEqual(3, length(wocky_db:rows(R1))),
    ?assertEqual(1, length(wocky_db:single_row(R1))),

    NotBob = fun (Row) -> proplists:get_value(username, Row) =/= <<"bob">> end,
    ?assertEqual(2, wocky_db:count(NotBob, R1)),

    Q3 = "TRUNCATE username_to_user",
    {ok, _} = wocky_db:query(shared, Q3, quorum),

    {ok, R2} = wocky_db:query(shared, Q2, quorum),
    ?assertEqual(0, length(wocky_db:rows(R2))),
    ?assertEqual([], wocky_db:single_row(R2)),

    wocky_app:stop(),
    ok.
