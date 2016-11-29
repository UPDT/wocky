%%% @copyright 2016+ Hippware, Inc.
%%% @doc Wocky interface to Algolia for full text search of users
-module(wocky_index).

-behaviour(gen_server).

%% API
-export([start_link/0,
         user_updated/2,
         user_removed/1,
         bot_updated/1,
         bot_removed/1,
         reindex/0,
         reindex/1]).

-ignore_xref([start_link/0, reindex/0, reindex/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).
-define(algolia, 'Elixir.Algolia').

-record(state, {enabled = false :: boolean(),
                user_index :: term(),
                bot_index :: term()}).
-type state() :: #state{}.


%%%===================================================================
%%% API
%%%===================================================================

%% @doc Starts the server
-spec start_link() -> {ok, pid()} | ignore | {error, any()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Called after a user is updated to update the index.
-spec user_updated(binary(), map()) -> ok.
user_updated(UserID, Data) ->
    gen_server:cast(?SERVER, {user_updated, UserID, Data}).

%% @doc Called after a user is removed to update the index.
-spec user_removed(binary()) -> ok.
user_removed(UserID) ->
    gen_server:cast(?SERVER, {user_removed, UserID}).

%% @doc Called after a bot is updated to update the index.
-spec bot_updated(map()) -> ok.
bot_updated(#{id := BotID} = Data) ->
    gen_server:cast(?SERVER, {bot_updated, BotID, Data}).

%% @doc Called after a bot is removed to update the index.
-spec bot_removed(binary()) -> ok.
bot_removed(BotID) ->
    gen_server:cast(?SERVER, {bot_removed, BotID}).

%% @doc Update the index for all of the users and bots in the databse.
%% NOTE: This is meant for dev and test. It is probably not appropriate
%% for production environments.
reindex() ->
    reindex(users),
    reindex(bots).

%% @doc Update the index for all records in a specific collection.
reindex(Collection) ->
    gen_server:call(?SERVER, {reindex, Collection}, 60000).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
%% @doc Initializes the server
-spec init([]) -> {ok, state()}.
init([]) ->
    {ok, UserIndex} = application:get_env(wocky, algolia_user_index_name),
    {ok, BotIndex} = application:get_env(wocky, algolia_bot_index_name),
    {ok, IndexingEnvs} = application:get_env(wocky, indexing_enabled_envs),
    {ok, CurrentEnv} = application:get_env(wocky, wocky_env),

    Enabled = lists:member(CurrentEnv, IndexingEnvs),

    ok = lager:info("Indexing enabled: ~p", [Enabled]),

    {ok, #state{enabled = Enabled,
                user_index = UserIndex,
                bot_index = BotIndex}}.

%% @private
%% @doc Handling call messages
-spec handle_call(any(), {pid(), any()}, state()) ->
    {reply, ok | {error, term()}, state()}.
handle_call({reindex, users}, _From, #state{user_index = Index} = State) ->
    Users = wocky_db:select(shared, user, all, #{}),
    lists:foreach(
      fun (#{user := UserID} = User) ->
              Object = map_to_object(UserID, User, user_fields()),
              update_index(Index, UserID, Object)
      end, Users),
    {reply, ok, State};
handle_call({reindex, bots}, _From, #state{bot_index = Index} = State) ->
    Bots = wocky_db:select(shared, bot, all, #{}),
    lists:foreach(
      fun (#{id := BotID} = Bot) ->
              lager:info("Found bot ~s", [BotID]),
              Object = map_to_object(BotID, Bot, bot_fields()),
              update_index(Index, BotID, Object)
      end, Bots),
    {reply, ok, State};
handle_call(_Request, _From, State) ->
    {reply, {error, bad_call}, State}.

%% @private
%% @doc Handling cast messages
-spec handle_cast({atom(), binary()} | {atom(), binary(), map()} | any(),
                  state()) -> {noreply, state()}.
handle_cast(_Msg, #state{enabled = false} = State) ->
    %% do nothing
    {noreply, State};
handle_cast({user_updated, UserID, Data}, #state{user_index = Index} = State) ->
    Object = map_to_object(UserID, Data, user_fields()),
    ok = lager:debug("Updating user index with object ~p", [Object]),
    {ok, _} = update_index(Index, UserID, Object),
    {noreply, State};
handle_cast({user_removed, UserID}, #state{user_index = Index} = State) ->
    ok = lager:debug("Removing user ~s from index", [UserID]),
    {ok, _} = ?algolia:delete_object(Index, UserID),
    {noreply, State};
handle_cast({bot_updated, BotID, Data}, #state{bot_index = Index} = State) ->
    Object = map_to_object(BotID, Data, bot_fields()),
    ok = lager:debug("Updating bot index with object ~p", [Object]),
    {ok, _} = update_index(Index, BotID, Object),
    {noreply, State};
handle_cast({bot_removed, BotID}, #state{bot_index = Index} = State) ->
    ok = lager:debug("Removing bot ~s from index", [BotID]),
    {ok, _} = ?algolia:delete_object(Index, BotID),
    {noreply, State};
handle_cast(Msg, State) ->
    ok = lager:warning("Unhandled cast: ~p", [Msg]),
    {noreply, State}.

%% @private
%% @doc Handling all non call/cast messages
-spec handle_info(any(), state()) -> {noreply, state()}.
handle_info(_Info, State) ->
    {noreply, State}.

%% @private
%% @doc This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
-spec terminate(any(), state()) -> ok.
terminate(_Reason, _State) ->
    ok.

%% @private
%% @doc Convert process state when code is changed
-spec code_change(any(), state(), any()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%%%===================================================================
%%% Internal functions
%%%===================================================================

user_fields() ->
    [handle, last_name, first_name, avatar].

bot_fields() ->
    [server, title, image, lat, lon, radius].

map_to_object(ID, MapData, Fields) ->
    maps:fold(fun (K, V, Acc) -> Acc#{atom_to_binary(K, utf8) => V} end,
              #{<<"objectID">> => ID},
              maps:with(Fields, with_geoloc(MapData))).

with_geoloc(#{lat := Lat, lon := Lon} = Data) ->
    Data#{'_geoloc' => #{lat => Lat, lng => Lon}};
with_geoloc(Data) ->
    Data.

update_index(Index, ObjectID, Object) ->
    case maps:size(Object) < 1 of
        true ->
            {ok, no_changes};
        false ->
            ?algolia:partial_update_object(Index, Object, ObjectID)
    end.
