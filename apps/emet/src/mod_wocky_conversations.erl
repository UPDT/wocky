%%% @copyright 2016+ Hippware, Inc.
%%%
%%% @doc Module implementing conversation list querying
%%% See https://github.com/hippware/tr-wiki/wiki/Conversations-List
%%%

-module(mod_wocky_conversations).

-behaviour(gen_mod).

-include("wocky.hrl").
-include_lib("ejabberd/include/ejabberd.hrl").
-include_lib("ejabberd/include/jlib.hrl").

-compile({parse_transform, cut}).

%% gen_mod handlers
-export([start/2, stop/1]).

-export([handle_iq/3]).

-export([archive_message_hook/9]).

-define(DEFAULT_MAX, 50).

-define(INDEX, <<"conversation">>).

-define(timex, 'Elixir.Timex').
-define(datetime, 'Elixir.DateTime').
-define(conversation, 'Elixir.Wocky.Conversation').

start(Host, Opts) ->
    wocky_util:set_config_from_opt(default_max,
                                   conv_max,
                                   ?DEFAULT_MAX,
                                   Opts),
    gen_iq_handler:add_iq_handler(ejabberd_sm, Host, ?NS_CONVERSATIONS,
                                  ?MODULE, handle_iq, parallel),
    ejabberd_hooks:add(mam_archive_message, Host, ?MODULE,
                       archive_message_hook, 50).

stop(Host) ->
    ejabberd_hooks:delete(mam_archive_message, Host, ?MODULE,
                          archive_message_hook, 50),
    gen_iq_handler:remove_iq_handler(ejabberd_sm, Host, ?NS_CONVERSATIONS).

%%%===================================================================
%%% IQ packet handling
%%%===================================================================

-spec handle_iq(From :: ejabberd:jid(),
                To :: ejabberd:jid(),
                IQ :: iq()) -> iq().
handle_iq(From, To, IQ) ->
    handle_iq_type(From, To, IQ).

handle_iq_type(From, _To,
               IQ = #iq{type = set,
                        sub_el = #xmlel{name = <<"query">>}}) ->
    get_conversations_response(From, IQ);
handle_iq_type(_From, _To, _IQ) ->
    {error, ?ERRT_BAD_REQUEST(?MYLANG, <<"Invalid query">>)}.

%%%===================================================================
%%% mam_archive_message callback
%%%===================================================================

-spec archive_message_hook(Result :: any(),
                           Host   :: ejabberd:server(),
                           MessID :: mod_mam:message_id(),
                           ArcID  :: mod_mam:archive_id(),
                           LocJID :: ejabberd:jid(),
                           RemJID :: ejabberd:jid(),
                           SrcJID :: ejabberd:jid(),
                           Dir    :: incoming | outgoing,
                           Packet :: exml:element()
                          ) -> ok.
archive_message_hook(_Result, Host, MessID, _ArcID,
                LocJID, RemJID, _SrcJID, Dir, Packet) ->
    Conv = ?conversation:new(
              MessID,
              Host,
              wocky_util:archive_jid(LocJID),
              wocky_util:archive_jid(RemJID),
              ossp_uuid:make(v1, text),
              exml:to_binary(Packet),
              Dir =:= outgoing),
    ok = ?conversation:put(Conv).

%%%===================================================================
%%% Conversation retrieval
%%%===================================================================

get_conversations_response(From, IQ = #iq{sub_el = SubEl}) ->
    RSM = jlib:rsm_decode(SubEl),
    RSM2 = id_to_int(cap_max(RSM)),
    {Conversations, RSMOut} = get_conversations(From, RSM2),
    create_response(IQ, Conversations, RSMOut).

get_conversations(From, RSMIn) ->
    UserJID = wocky_util:archive_jid(From),
    Rows = ?conversation:find(UserJID),
    ResultWithTimes = [R#{timestamp => integer_to_binary(
                                         uuid:get_v1_time(
                                           uuid:string_to_uuid(T)))} ||
                       R = #{time := T} <- Rows],
    SortedResult = sort_result(ResultWithTimes),
    rsm_util:filter_with_rsm(SortedResult, RSMIn).

%%%===================================================================
%%% Helpers
%%%===================================================================

sort_result(Rows) ->
    lists:sort(fun sort_by_id/2, Rows).

% Sort the most recent to the front
sort_by_id(#{id := ID1}, #{id := ID2}) ->
    ID1 > ID2.

cap_max(none) ->
    #rsm_in{max = max_results()};
cap_max(RSM = #rsm_in{max = Max}) ->
    RSM#rsm_in{max = min(Max, max_results())}.

id_to_int(RSM = #rsm_in{id = ID})
  when ID =:= undefined orelse ID =:= <<>> ->
    RSM#rsm_in{id = undefined};
id_to_int(RSM = #rsm_in{id = ID}) ->
    RSM#rsm_in{id = wocky_util:default_bin_to_integer(ID, 0)}.

max_results() ->
    ejabberd_config:get_local_option(conv_max).

create_response(IQ, Conversations, RSMOut) ->
    IQ#iq{type = result,
          sub_el = [#xmlel{name = <<"query">>,
                           attrs = [{<<"xmlns">>, ?NS_CONVERSATIONS}],
                           children =
                           conversations_xml(Conversations) ++
                           jlib:rsm_encode(RSMOut)
                          }]}.

conversations_xml(Conversations) ->
    [conversation_xml(C) || C <- Conversations].

conversation_xml(Conversation = #{id := ID}) ->
    #xmlel{name = <<"item">>,
           attrs = [{<<"id">>, integer_to_binary(ID)}],
           children = conversation_data_xml(Conversation)}.

conversation_data_xml(Conversation) ->
    Elements = [other_jid, timestamp, outgoing],
    [message_element(Conversation) |
    [conversation_element(E, Conversation) || E <- Elements]].

message_element(C) ->
    case exml:parse(maps:get(message, C)) of
        {ok, XML} -> XML;
        {error, _} -> #xmlel{name = <<"message">>,
                             children = [#xmlcdata{content = <<"error">>}]}
    end.

conversation_element(E, C) ->
    wocky_xml:cdata_el(atom_to_binary(E, utf8), to_binary(maps:get(E, C))).

to_binary(B) when is_binary(B) -> B;
to_binary(I) when is_integer(I) -> integer_to_binary(I);
to_binary(A) when is_atom(A) -> atom_to_binary(A, utf8).