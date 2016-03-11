%%% @copyright 2016+ Hippware, Inc.
%%% @doc Francus backend for `mod_hxep'
-module(mod_hxep_francus).

-include_lib("ejabberd/include/jlib.hrl").
-include("mod_hxep_francus.hrl").

-export([start/1,
         stop/0,
         make_download_response/4,
         make_upload_response/5,
         make_auth/0
        ]).

-define(DEFAULT_PORT, 1025).

start(_Opts) ->
    hxep_req_tracker:start(),
    Dispatch = cowboy_router:compile([{'_', [{'_', hxep_francus_http, []}]}]),
    cowboy:start_http(hxep_francus_listener, 100,
                       [
                        {port, port()}
                       ],
                       [{env, [{dispatch, Dispatch}]}]).

stop() ->
    hxep_req_tracker:stop().

make_download_response(FromJID, ToJID, OwnerID, FileID) ->
    {Auth, _User, UserServer, URL} =
        common_response_data(FromJID, ToJID, OwnerID, FileID),
    add_request(get, OwnerID, FileID, UserServer, Auth, 0, #{}),
    Headers = [{<<"authorization">>, Auth}],
    RespFields = [
                  {<<"url">>, URL},
                  {<<"method">>, <<"GET">>}
                 ],
    {Headers, RespFields}.

make_upload_response(FromJID, ToJID, FileID, Size, Metadata =
                     #{<<"content-type">> := ContentType}) ->
    {Auth, User, UserServer, URL} =
        common_response_data(FromJID, ToJID, FromJID#jid.luser, FileID),
    add_request(put, User, FileID, UserServer, Auth, Size, Metadata),
    Headers = [
               {<<"content-type">>, ContentType},
               {<<"authorization">>, Auth}
              ],
    RespFields = [
                  {<<"url">>, URL},
                  {<<"method">>, <<"PUT">>}
                 ],
    {Headers, RespFields}.

common_response_data(FromJID, ToJID, Owner, FileID) ->
    %% Explicit module named added to allow us to mock out make_auth/0 for
    %% testing
    Auth = ?MODULE:make_auth(),
    User = FromJID#jid.luser,
    UserServer = FromJID#jid.lserver,
    Server = ToJID#jid.lserver,
    URL = url(Server, Owner, FileID),
    {Auth, User, UserServer, URL}.

make_auth() ->
    base64:encode(crypto:strong_rand_bytes(48)).

add_request(Op, User, FileID, UserServer, Auth, Size, Metadata) ->
    Req = #hxep_request{op = Op, request = {User, FileID, Auth},
                        user_server = UserServer, size = Size,
                        metadata = Metadata
                       },
    hxep_req_tracker:add(Req).

port() -> ?DEFAULT_PORT.

url(Server, User, FileID) ->
    iolist_to_binary(
      ["https://", Server, ":", integer_to_list(port()),
       "/users/", User, "/files/", FileID]).
