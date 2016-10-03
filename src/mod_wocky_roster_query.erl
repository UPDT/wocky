%%% @copyright 2016+ Hippware, Inc.
%%%
%%% @doc Module implementing roster query
%%% See https://github.com/hippware/tr-wiki/wiki/Roster-query
%%%
-module(mod_wocky_roster_query).

-behaviour(gen_mod).

-compile({parse_transform, do}).
-compile({parse_transform, cut}).

-include_lib("ejabberd/include/jlib.hrl").
-include_lib("ejabberd/include/ejabberd.hrl").
-include("wocky.hrl").
-include("wocky_roster.hrl").

-ignore_xref([handle_iq/3]).

%% gen_mod handlers
-export([start/2, stop/1]).

%% IQ hook
-export([handle_iq/3]).

%%%===================================================================
%%% gen_mod handlers
%%%===================================================================

start(Host, _Opts) ->
    gen_iq_handler:add_iq_handler(ejabberd_sm, Host, ?NS_WOCKY_ROSTER,
                                  ?MODULE, handle_iq, parallel),
    mod_disco:register_feature(Host, ?NS_WOCKY_ROSTER),
    ejabberd_hooks:add(roster_updated, Host,
                       fun roster_updated/3, 50).

stop(Host) ->
    mod_disco:unregister_feature(Host, ?NS_WOCKY_ROSTER),
    gen_iq_handler:remove_iq_handler(ejabberd_sm, Host, ?NS_WOCKY_ROSTER),
    ejabberd_hooks:delete(roster_updated, Host,
                          fun roster_updated/3, 50).

%%%===================================================================
%%% Event handler
%%%===================================================================

-spec handle_iq(From :: ejabberd:jid(),
                To :: ejabberd:jid(),
                IQ :: iq()) -> iq().
handle_iq(From, To, IQ) ->
    case handle_iq_type(From, To, IQ) of
        {ok, ResponseIQ} -> ResponseIQ;
        {error, Error} -> wocky_util:make_error_iq_response(IQ, Error)
    end.

% Retrieve
handle_iq_type(From, To, IQ = #iq{type = get,
                                  sub_el = #xmlel{name = <<"query">>}
                                 }) ->
    handle_retrieve(From, To, IQ);

handle_iq_type(_From, _To, _IQ) ->
    {error, ?ERRT_BAD_REQUEST(?MYLANG, <<"Invalid query">>)}.

%%%===================================================================
%%% Action - retrieve
%%%===================================================================

handle_retrieve(From, To = #jid{luser = LUser, lserver = LServer}, IQ) ->
    %% There is the potential for a query to be sent a roster that is newer
    %% than the attached version, since we query the version first then the
    %% roster separately. However in reality this shouldn't pose a problem
    %% since at worst the subscriber will later be sent the same (new) roster
    %% with the correct version when they re-query.
    do([error_m ||
        check_permissions(From, To),
        QueryVersion <- get_query_version(IQ),
        RosterVersion <- get_roster_version(LUser, LServer),
        Roster <- maybe_get_roster(QueryVersion, RosterVersion, LUser, LServer),
        RosterEl <- make_roster_el(Roster, RosterVersion),
        {ok, IQ#iq{type = result, sub_el = RosterEl}}
       ]).

check_permissions(From, #jid{luser = LUser, lserver = LServer}) ->
    Viewers = wocky_db_user:get_roster_viewers(LUser, LServer),
    case is_viewer(From, Viewers) of
        false -> {error, ?ERR_FORBIDDEN};
        true -> ok
    end.

is_viewer(_, not_found) -> false;
is_viewer(From, List) ->
    lists:member(jid:to_binary(viewer_jid(From)), List).

viewer_jid(JID = #jid{luser = <<>>}) -> JID;
viewer_jid(JID) -> jid:to_bare(JID).

get_query_version(#iq{sub_el = #xmlel{attrs = Attrs}}) ->
    case xml:get_attr(<<"version">>, Attrs) of
        {value, V} -> {ok, V};
        false -> {ok, undefined}
    end.

get_roster_version(LUser, LServer) ->
    {ok, wocky_db_roster:get_roster_version(LUser, LServer)}.

maybe_get_roster(Ver, Ver, _, _) ->
    {ok, unchanged};

maybe_get_roster(_, _, LUser, LServer) ->
    {ok, wocky_db_roster:get_roster(LUser, LServer)}.

make_roster_el(Roster, Version) ->
    {ok, #xmlel{name = <<"query">>,
                attrs = [{<<"xmlns">>, ?NS_WOCKY_ROSTER},
                         {<<"version">>, Version}],
                children = make_item_els(Roster)}}.

make_item_els(unchanged) ->
    [];
make_item_els(Roster) ->
    [make_item_el(R) || R <- Roster].

make_item_el(#wocky_roster{contact_jid = JID, contact_handle = Name,
                           subscription = Subscription, groups = Groups}) ->
    #xmlel{name = <<"item">>,
           attrs = [{<<"jid">>, jid:to_binary(JID)},
                    {<<"name">>, Name},
                    {<<"subscription">>, atom_to_binary(Subscription, utf8)}],
           children = group_els(Groups)}.

group_els(Groups) ->
    [group_el(G) || G <- Groups].

group_el(Group) ->
    #xmlel{name = <<"group">>, children = [#xmlcdata{content = Group}]}.

%%%===================================================================
%%% Roster update hook handler
%%%===================================================================

-spec roster_updated(ejabberd:luser(), ejabberd:lserver(),
                     wocky_roster()) -> ok.
roster_updated(LUser, LServer, _Item) ->
    Viewers = wocky_db_user:get_roster_viewers(LUser, LServer),
    lists:foreach(notify_roster_update(LUser, LServer, _), Viewers).

notify_roster_update(LUser, LServer, Viewer) ->
    ejabberd_router:route(jid:make(LUser, LServer, <<>>),
                          jid:from_binary(Viewer),
                          roster_change_packet()).

roster_change_packet() ->
    #xmlel{name = <<"message">>,
           attrs = [{<<"type">>, <<"headline">>}],
           children = [#xmlel{name = <<"roster-changed">>}]}.
