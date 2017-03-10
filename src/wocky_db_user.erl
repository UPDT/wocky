%%% @copyright 2015+ Hippware, Inc.
%%% @doc Wocky database interface for "users"
%%%
%%% == Terminology ==
%%% <dl>
%%% <dt>JID</dt>
%%% <dd>
%%%   Short for "Jabber IDentifier" and defined in RFC 6122, the JID is the
%%%   canonical identifier for a specific user within the Jabber network.
%%%
%%%   Briefly, the JID is composed of three parts: the "localpart" that
%%%   identifies the user, the "domainpart" that identifies the Jabber network
%%%   and the "resourcepart" that identifies the current connection to the
%%%   network.
%%%
%%% </dd>
%%% <dt>User/LUser</dt>
%%% <dd>
%%%   The "localpart" of the JID.
%%%
%%%   For Wocky it is a timeuuid generated when the user is created and
%%%   formatted as a canonical UUID string. This is the canonical user ID within
%%%   Wocky but is not meant for display to the end user.
%%%
%%%   The "L" prefix indicates that the string has been normalized according to
%%%   RFC 6122. Variables without the "L" prefix are assumed to not be
%%%   normalized and must be processed before use.
%%%
%%% </dd>
%%% <dt>Server/LServer</dt>
%%% <dd>
%%%   The "domainpart" of the JID.
%%%
%%%   For Wocky this is the virtual host that the user connects to. This is not
%%%   the physical machine that is handling the user's connection, but a domain
%%%   representing a single cluster of application instances.
%%%
%%%   The "L" prefix indicates that the string has been normalized according to
%%%   RFC 6122. Variables without the "L" prefix are assumed to not be
%%%   normalized and must be processed before use.
%%%
%%% </dd>
%%% <dt>Handle</dt>
%%% <dd>
%%%   This is the name that is displayed to the user and is chosen by the user
%%%   when they create their account.
%%%
%%%   It must be globally unique.
%%%
%%% </dd>
%%% </dl>
%%%
%%% @reference See <a href="http://xmpp.org/rfcs/rfc6122.html">RFC 6122</a>
%%% for more information on JIDs.
%%%
%%% @reference See <a href="https://tools.ietf.org/html/rfc4122">RFC 4122</a>
%%% for the definition of UUIDs.
%%%
%%% @reference
%%% <a href="https://en.wikipedia.org/wiki/Universally_unique_identifier">
%%% This Wikipedia article</a> provides a good overview of UUIDs.
%%%
-module(wocky_db_user).

-include("wocky.hrl").

-type handle()       :: binary().
-type phone_number() :: binary().
-type password()     :: binary().
-type token()        :: binary().
-export_type([handle/0, phone_number/0, password/0, token/0]).

%% API
-export([update_user/3,
         remove_user/2,
         find_user/2,
         find_user_by/2,
         get_handle/2,
         get_phone_number/2,
         set_location/6,
         set_location/6
        ]).


-compile({parse_transform, do}).


%%%===================================================================
%%% API
%%%===================================================================

%% @doc Update the data on an existing user.
%%
%% `LUser': the "localpart" of the user's JID.
%%
%% `LServer': the "domainpart" of the user's JID.
%%
%% `Fields': is a map containing fields to update. Valid keys are `handle',
%%           `avatar', `first_name', `last_name' and `email'. All other keys
%%           are ignored.
%%
-spec update_user(binary(), binary(), map()) -> ok | {error, atom()}.
update_user(User, Server, Fields) ->
    UpdateFields = maps:with(valid_user_fields(), Fields),
    do([error_m ||
        UserData <- maybe_lookup_user(should_lookup_user(Fields), User, Server),
        prepare_avatar(User, Server, Fields),
        check_reserved_handle(UserData, Fields),
        update_handle_lookup(User, Server, UserData, Fields),
        delete_existing_avatar(UserData),
        do_update_user(User, Server, UpdateFields, maps:size(UpdateFields))
       ]).

%% @private
do_update_user(_, _, _, 0) ->
    ok;
do_update_user(User, Server, UpdateFields, _) ->
    ok = wocky_db:update(shared, user, UpdateFields,
                         #{user => User, server => Server}),
    'Elixir.Wocky.Index':user_updated(User, UpdateFields).

%% @private
valid_user_fields() ->
    [handle, avatar, first_name, last_name, email].

%% @private
should_lookup_user(Fields) ->
    maps:is_key(avatar, Fields) orelse maps:is_key(handle, Fields).

%% @private
maybe_lookup_user(false, _User, _Server) -> {ok, #{}};
maybe_lookup_user(true, User, Server) ->
    case find_user(User, Server) of
        not_found -> {ok, #{}};
        UserData -> {ok, UserData}
    end.

%% @private
prepare_avatar(UserID, LServer, #{avatar := NewAvatar}) ->
    do([error_m ||
        {FileServer, FileID} <- tros:parse_url(NewAvatar),
        check_file_is_local(LServer, FileServer),
        Metadata <- tros:get_metadata(LServer, FileID),
        check_avatar_owner(UserID, Metadata),
        tros:keep(LServer, FileID)
       ]);
prepare_avatar(_, _, _) -> ok.

%% @private
check_file_is_local(Server, Server) -> ok;
check_file_is_local(_, _) -> {error, not_local_file}.

%% @private
check_avatar_owner(UserID, Metadata) ->
    case tros:get_owner(Metadata) of
        {ok, UserID} -> ok;
        _ -> {error, not_file_owner}
    end.

%% @private
check_reserved_handle(#{handle := OldHandle},
                      #{handle := NewHandle}) when OldHandle =/= NewHandle ->
    Reserved = application:get_env(wocky, reserved_handles, []),
    case lists:member(wocky_util:bin_to_lower(NewHandle), Reserved) of
        false -> ok;
        true -> {error, duplicate_handle}
    end;
check_reserved_handle(_, _) -> ok.

%% @private
update_handle_lookup(User, Server, #{handle := OldHandle},
                     #{handle := NewHandle}) when OldHandle =/= NewHandle ->
    %% Unfortunately we cannot run these queries in a batch. The LWT means
    %% that the batch will only work if the records are all in the same
    %% partition, and since the handle is the partition key, this will never
    %% be the case.
    Values = #{user => User, server => Server, handle => NewHandle},
    case wocky_db:insert_new(shared, handle_to_user, Values) of
        true -> delete_old_handle(OldHandle);
        false -> {error, duplicate_handle}
    end;
update_handle_lookup(_, _, _, _) -> ok.

%% @private
delete_old_handle(null) -> ok;
delete_old_handle(OldHandle) ->
    wocky_db:delete(shared, handle_to_user, all, #{handle => OldHandle}).

%% @private
delete_existing_avatar(#{avatar := OldAvatar}) ->
    case tros:parse_url(OldAvatar) of
        {ok, {Server, FileID}} -> tros:delete(Server, FileID);
        {error, _} -> ok
    end;
delete_existing_avatar(_) -> ok.


%% @doc Removes the user from the database.
%%
%% `LUser': the "localpart" of the user's JID.
%%
%% `LServer': the "domainpart" of the user's JID.
%%
-spec remove_user(ejabberd:luser(), ejabberd:lserver()) -> ok.
remove_user(LUser, LServer) ->
    ok = remove_shared_user_data(LUser, LServer),
    ok = remove_local_user_data(LUser, LServer),
    ok = 'Elixir.Wocky.Index':user_removed(LUser),
    ok.

%% @private
remove_shared_user_data(LUser, LServer) ->
    Handle = get_handle(LUser, LServer),
    PhoneNumber = get_phone_number(LUser, LServer),
    Queries = [remove_handle_lookup_query(Handle),
               remove_phone_lookup_query(PhoneNumber),
               remove_user_record_query(LUser, LServer)],
    {ok, void} = wocky_db:batch_query(shared, lists:flatten(Queries), quorum),
    ok.

%% @private
remove_local_user_data(LUser, LServer) ->
    Queries = [remove_tokens_query(LUser, LServer),
               remove_locations_query(LUser, LServer)],
    {ok, void} = wocky_db:batch_query(LServer, Queries, quorum),
    ok.

%% @private
remove_handle_lookup_query(not_found) -> [];
remove_handle_lookup_query(Handle) ->
    {"DELETE FROM handle_to_user WHERE handle = ?",
     #{handle => Handle}}.

%% @private
remove_phone_lookup_query(not_found) -> [];
remove_phone_lookup_query(PhoneNumber) ->
    {"DELETE FROM phone_number_to_user WHERE phone_number = ?",
     #{phone_number => PhoneNumber}}.

%% @private
remove_user_record_query(LUser, LServer) ->
    {"DELETE FROM user WHERE user = ? AND server = ?",
     #{user => LUser, server => LServer}}.

%% @private
remove_tokens_query(LUser, LServer) ->
    {"DELETE FROM auth_token WHERE user = ? AND server = ?",
     #{user => LUser, server => LServer}}.

%% @private
remove_locations_query(LUser, LServer) ->
    {"DELETE FROM location WHERE user = ? AND server = ?",
     #{user => LUser, server => LServer}}.


%% @doc Returns a map of all fields for a given user or `not_found' if no such
%% user exists.
%%
%% `LUser': the "localpart" of the user's JID.
%%
%% `LServer': the "domainpart" of the user's JID.
%%
-spec find_user(ejabberd:lserver(), ejabberd:lserver()) -> map() | not_found.
find_user(LUser, LServer) ->
    Conditions = #{user => LUser, server => LServer},
    wocky_db:select_row(shared, user, all, Conditions).


%% @doc Returns a map of all fields for a given user or `not_found' if no such
%% user exists.
%%
%% `Key': the key to use to lookup the user. Acceptable values include
%%        `handle', `phone_number' and `external_id'.
%%
%% `Value': the value that corresponds to `Key'.
%%
-spec find_user_by(Key :: atom(), Value :: binary()) -> map() | not_found.
find_user_by(handle, Handle) ->
    find_user_by_lookup(handle_to_user, handle, Handle);
find_user_by(phone_number, PhoneNumber) ->
    find_user_by_lookup(phone_number_to_user, phone_number, PhoneNumber);
find_user_by(external_id, ExternalId) ->
    find_user_by_lookup(external_id_to_user, external_id, ExternalId).

%% @private
find_user_by_lookup(Table, Col, Value) ->
    case lookup_userid(Table, Col, Value) of
        {User, Server} -> find_user(User, Server);
        not_found -> not_found
    end.

%% @private
lookup_userid(Table, Col, Value) ->
    case wocky_db:select_row(shared, Table, [user, server], #{Col => Value}) of
        not_found -> not_found;
        #{user := User, server := Server} -> {User, Server}
    end.


%% @doc Returns the user's handle.
%%
%% `LUser': the "localpart" of the user's JID.
%%
%% `LServer': the "domainpart" of the user's JID.
%%
-spec get_handle(ejabberd:luser(), ejabberd:lserver())
                -> handle() | not_found.
get_handle(LUser, LServer) ->
    Conditions = #{user => LUser, server => LServer},
    case wocky_db:select_one(shared, user, handle, Conditions) of
        not_found -> not_found;
        null -> not_found;
        Value -> Value
    end.


%% @doc Returns the user's phone number.
%%
%% `LUser': the "localpart" of the user's JID.
%%
%% `LServer': the "domainpart" of the user's JID.
%%
-spec get_phone_number(ejabberd:luser(), ejabberd:lserver())
                      -> binary() | not_found.
get_phone_number(LUser, _LServer) ->
    wocky_db:select_one(shared, user_to_phone_number, phone_number,
                        #{user => LUser}).


%% @doc Updates the user's location.
%%
%% `LUser': the "localpart" of the user's JID.
%%
%% `LServer': the "domainpart" of the user's JID.
%%
%% `LResource': the "resourcepart" of the user's JID.
%%
%% `Lat': the latitude of the user's location in degrees North
%%
%% `Lon': the longditude of the user's location in degrees East
%%
%% `Accuracy': the accuracy of the user's location in meters
%%
-spec set_location(ejabberd:luser(), ejabberd:lserver(), ejabberd:lresource(),
                   number(), number(), number()) -> ok.
set_location(LUser, LServer, LResource, Lat, Lon, Accuracy) ->
    wocky_db:insert(LServer, location, #{user =>     LUser,
                                         server =>   LServer,
                                         resource => LResource,
                                         time =>     now,
                                         lat =>      Lat,
                                         lon =>      Lon,
                                         accuracy => Accuracy}).
