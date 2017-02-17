%%% @copyright 2015+ Hippware, Inc.
%%% @doc Cassandra-backed authentication backend
%%%
%%% This module serves a number of purposes:
%%%
%%% 1) Pluggable ejabberd authentication backend ({@link ejabberd_gen_auth})
%%% 2) Application specific user functionality
%%%
%%% Complications arise because they are not identical.
%%%
%%% Ejabberd users are a (localpart, domainpart) pair with localpart being the
%%% 'username'. Wocky users are a (localpart, domainpart, username) tuple with
%%% username being a separate quantity (which is also globally unique across all
%%% domains).
%%%
%%% In order to utilise existing code, this module needs to conform to {@link
%%% ejabberd_gen_auth} but not all of the functions required of (1) make sense
%%% for (2). Hence, for those functions which don't make sense, a "best effort"
%%% implementation which is "least surprising" will have to suffice. In other
%%% words, all the functions of (1) need to be implemented, but not all of them
%%% will be useful or are expected to be used in normal operations.
%%%
%%%
%%% For schema, see priv/schema*.cql
%%%
%%% Enable with the following in ejabberd.cfg
%%%
%%% ```
%%% {auth_method, wocky}.
%%% '''

-module(ejabberd_auth_wocky).

-behaviour(ejabberd_gen_auth).
-export([start/1,
         stop/1,
         store_type/1,
         authorize/1,
         set_password/3,
         check_password/3,
         check_password/5,
         try_register/3,
         dirty_get_registered_users/0,
         get_vh_registered_users/1,
         get_vh_registered_users/2,
         get_vh_registered_users_number/1,
         get_vh_registered_users_number/2,
         get_password/2,
         get_password_s/2,
         does_user_exist/2,
         remove_user/2,
         remove_user/3]).

-ignore_xref([check_password/3, check_password/5]).

-include_lib("ejabberd/include/ejabberd.hrl").


%%%----------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------

-spec start(ejabberd:server()) -> ok.
start(Host) ->
    ejabberd_auth_riak:start(Host).

-spec stop(ejabberd:server()) -> ok.
stop(Host) ->
    ejabberd_auth_riak:stop(Host).

-spec store_type(ejabberd:lserver()) -> scram | plain.
store_type(LServer) ->
    ejabberd_auth_riak:store_type(LServer).

-spec authorize(mongoose_credentials:t()) ->
    {ok, mongoose_credentials:t()} | {error, any()}.
authorize(Creds) ->
    ejabberd_auth:authorize_with_check_password(?MODULE, Creds).

-spec set_password(ejabberd:luser(), ejabberd:lserver(), binary()) ->
    ok | {error, not_allowed | invalid_jid}.
set_password(LUser, LServer, Password) ->
    ejabberd_auth_riak:set_password(LUser, LServer, Password).

-spec check_password(ejabberd:luser(), ejabberd:lserver(), binary()) ->
    boolean().
check_password(LUser, LServer, <<"$T$", _/binary>> = Token) ->
    wocky_db_user:check_token(LUser, LServer, Token);
check_password(LUser, LServer, Password) ->
    ejabberd_auth_riak:check_password(LUser, LServer, Password).

-spec check_password(ejabberd:luser(), ejabberd:lserver(), binary(), binary(),
                     fun()) -> boolean().
check_password(LUser, LServer, Password, Digest, DigestGen) ->
    ejabberd_auth_riak:check_password(LUser, LServer, Password,
                                      Digest, DigestGen).

%% Not really suitable for use since it does not pass in extra profile
%% information and we expect LUser to be a timeuuid. It is implemented
%% here to enable Escalus to create users in integration tests.
-spec try_register(ejabberd:luser(), ejabberd:lserver(), binary()) -> ok.
try_register(LUser, LServer, Password) ->
    ejabberd_auth_riak:try_register(LUser, LServer, Password).

-spec dirty_get_registered_users() -> [ejabberd:simple_bare_jid()].
dirty_get_registered_users() ->
    ejabberd_auth_riak:dirty_get_registered_users().

-spec get_vh_registered_users(ejabberd:lserver()) ->
    [ejabberd:simple_bare_jid()].
get_vh_registered_users(LServer) ->
    ejabberd_auth_riak:get_vh_registered_users(LServer).

-spec get_vh_registered_users(ejabberd:lserver(), list()) ->
    [ejabberd:simple_bare_jid()].
get_vh_registered_users(LServer, Opts) ->
    ejabberd_auth_riak:get_vh_registered_users(LServer, Opts).

-spec get_vh_registered_users_number(ejabberd:lserver()) -> non_neg_integer().
get_vh_registered_users_number(LServer) ->
    ejabberd_auth_riak:get_vh_registered_users_number(LServer).

-spec get_vh_registered_users_number(ejabberd:lserver(), list()) ->
    non_neg_integer().
get_vh_registered_users_number(LServer, Opts) ->
    ejabberd_auth_riak:get_vh_registered_users_number(LServer, Opts).

-spec get_password(ejabberd:luser(), ejabberd:lserver()) ->
    scram:scram_tuple() | binary() | false.
get_password(LUser, LServer) ->
    ejabberd_auth_riak:get_password(LUser, LServer).

-spec get_password_s(ejabberd:luser(), ejabberd:lserver()) -> binary().
get_password_s(LUser, LServer) ->
    ejabberd_auth_riak:get_password_s(LUser, LServer).

-spec does_user_exist(ejabberd:luser(), ejabberd:lserver()) -> boolean().
does_user_exist(LUser, LServer) ->
    ejabberd_auth_riak:does_user_exist(LUser, LServer).

-spec remove_user(ejabberd:luser(), ejabberd:lserver()) -> ok.
remove_user(LUser, LServer) ->
    ejabberd_auth_riak:remove_user(LUser, LServer).

-spec remove_user(ejabberd:luser(), ejabberd:lserver(), binary()) ->
    no_return().
remove_user(LUser, LServer, Password) ->
    ejabberd_auth_riak:remove_user(LUser, LServer, Password).
