%%% @copyright 2016+ Hippware, Inc.
%%% @doc Behavior and interface to client notification services
-module(wocky_notification_handler).

-include_lib("ejabberd/include/ejabberd.hrl").
-include_lib("ejabberd/include/jlib.hrl").

-callback register(User :: binary(), Platform :: binary(),
                   DeviceId :: binary()) -> {ok, Endpoint :: binary()}.

-callback notify(From :: binary(), To :: binary(), Message :: binary()) ->
    ok.

-export([register/3, notify/3]).

-spec register(ejabberd:jid(), binary(), binary()) -> {ok, binary()}.
register(UserJID, Platform, DeviceId) ->
    User = jid:to_binary(UserJID),
    ok = lager:debug("Registering device '~s' for user '~s'",
                     [DeviceId, User]),
    (handler()):register(User, Platform, DeviceId).

-spec notify(binary(), ejabberd:jid(), binary()) -> ok.
notify(Endpoint, FromJID, Message) ->
    From = jid:to_binary(FromJID),
    ok = lager:debug("Sending notification for message from ~s with body '~s'",
                     [From, Message]),
    (handler()):notify(Endpoint, From, Message).

handler() ->
    {ok, Handler} = application:get_env(wocky, notification_handler),
    Handler.
