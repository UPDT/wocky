%%% @copyright 2016+ Hippware, Inc.
%%% @doc Implementation module for HXEP file transfer system
%%% (https://github.com/hippware/tr-wiki/wiki/HXEP%3A-Files-over-http).
%%%
%%% TODO:
%%% * Implement permission system
%%% * Impelment purpose system?
%%% * Store supplied filename?
%%%
-module(mod_tros).

-define(TROS_NS, <<"hippware.com/hxep/http-file">>).

-export([
   start/2,
   stop/1,
   handle_iq/3,
   make_file_id/0,
   set_config_from_opt/2
        ]).

-ifdef(TEST).
-export([backend/0]).
-endif.

-include_lib("ejabberd/include/ejabberd.hrl").
-include_lib("ejabberd/include/jlib.hrl").

-behaviour(gen_mod).

-compile({parse_transform, do}).

-record(request, {
          from_jid :: ejabberd:jid(),
          to_jid :: ejabberd:jid(),
          iq :: iq()
         }).

-define(DEFAULT_BACKEND, francus).
-define(DEFAULT_MAX_UPLOAD_SIZE, (1024*1024 * 10)). % 10MB

configs() ->
    %% Name in .cfg   |Name in ejabberd_config|Default value
    [
     {backend,         tros_backend,          ?DEFAULT_BACKEND},
     {max_upload_size, tros_max_upload_size,  ?DEFAULT_MAX_UPLOAD_SIZE}
    ].

start(Host, Opts) ->
    lists:foreach(fun(C) -> set_config_from_opt(C, Opts) end, configs()),
    (backend()):start(Opts),
    gen_iq_handler:add_iq_handler(ejabberd_local, Host, ?TROS_NS,
                                  ?MODULE, handle_iq, parallel).

stop(Host) ->
    _ = gen_iq_handler:remove_iq_handler(ejabberd_local, Host, ?TROS_NS),
    (backend()):stop().

-spec handle_iq(From :: ejabberd:jid(),
                To :: ejabberd:jid(),
                IQ :: iq()) -> ignore | iq().
handle_iq(FromJID, ToJID, IQ = #iq{type = Type, sub_el = ReqEl}) ->
    Req = #request{from_jid = FromJID, to_jid = ToJID, iq = IQ},
    case handle_request(Req, Type, ReqEl) of
        {error, E} -> error_response(IQ, E);
        {ok, R} -> R
    end.

handle_request(Req, get, ReqEl = #xmlel{name = <<"download-request">>}) ->
    handle_download_request(Req, ReqEl);
handle_request(Req, set, ReqEl = #xmlel{name = <<"upload-request">>}) ->
    handle_upload_request(Req, ReqEl);
handle_request(_, _, _) ->
    {ok, ignore}.

handle_download_request(Req = #request{from_jid = FromJID}, DR) ->
    do([error_m ||
        Fields <- extract_fields(DR, [<<"id">>], []),
        FileID <- check_file_id(Fields),
        OwnerID <- check_download_permissions(FromJID, FileID),
        download_response(Req, OwnerID, FileID)
       ]).

handle_upload_request(Req = #request{from_jid = FromJID}, UR) ->
    RequiredFields = [<<"filename">>, <<"size">>,
                      <<"mime-type">>, <<"purpose">>],
    OptionalFields = [<<"width">>, <<"height">>],
    do([error_m ||
        Fields <- extract_fields(UR, RequiredFields, OptionalFields),
        Size <- check_upload_size(Fields),
        check_upload_type(Fields),
        check_upload_permissions(FromJID, Fields),
        upload_response(Req, Fields, Size)
       ]).

extract_fields(Req, RequiredFields, OptionalFields) ->
    Fields = lists:foldl(fun(F, Acc) -> add_field(Req, F, Acc) end, #{},
                         RequiredFields ++ OptionalFields),
    check_fields(Fields, RequiredFields).

add_field(UR, Field, Acc) ->
    case exml_query:path(UR, [{element, Field}, cdata]) of
        undefined ->
            Acc;
        Value when is_binary(Value) ->
            Acc#{Field => Value}
    end.

check_fields(Fields, []) -> {ok, Fields};
check_fields(Fields, [H|T]) ->
    case maps:is_key(H, Fields) of
        false -> {error, missing_field_error(H)};
        true -> check_fields(Fields, T)
    end.

missing_field_error(FieldName) ->
    Text = iolist_to_binary(["Required field missing: ", FieldName]),
    {error, ?ERRT_BAD_REQUEST(?MYLANG, Text)}.

upload_validation_error(ErrorStr) ->
    Text = iolist_to_binary(["Upload request denied: ", ErrorStr]),
    validation_error(Text).

download_validation_error(ErrorStr) ->
    Text = iolist_to_binary(["Download request denied: ", ErrorStr]),
    validation_error(Text).

validation_error(Text) ->
    {error, ?ERRT_NOT_ACCEPTABLE(?MYLANG, Text)}.

check_file_id(#{<<"id">> := <<"tros:", JID/binary>>}) ->
    case jid:from_binary(JID) of
        #jid{lresource = <<"file/", LResource/binary>>} ->
            check_file_id(LResource);
        _ ->
            download_validation_error("Invalid file URL")
    end;

check_file_id(#{<<"id">> := ID}) ->
    check_file_id(ID);

check_file_id(ID) when is_binary(ID) ->
    case wocky_db:is_valid_id(ID) of
        true -> {ok, ID};
        false -> download_validation_error(["Invalid file ID: ", ID])
    end.

check_upload_size(#{<<"size">> := SizeBin}) ->
    Size = binary_to_integer_def(SizeBin, 0),
    MaxSize = ejabberd_config:get_local_option(tros_max_upload_size),
    case Size =< MaxSize andalso Size > 0 of
        true -> {ok, Size};
        false -> upload_validation_error(["Invalid size: ", SizeBin])
    end.

% TODO: configure a list of valid upload types
check_upload_type(_Fields) -> ok.

check_upload_permissions(FromJID, #{<<"purpose">> := Purpose}) ->
    case tros_permissions:can_upload(FromJID, Purpose) of
        true -> ok;
        false -> upload_validation_error("Permission denied")
    end.

check_download_permissions(FromJID, FileID) ->
    case tros_permissions:can_download(FromJID, FileID) of
        {true, OwnerID} ->
            {ok, OwnerID};
        {false, Reason} ->
            {error, ?ERRT_FORBIDDEN(?MYLANG,
                                    iolist_to_binary(
                                      ["No permission to download this file: ",
                                       atom_to_list(Reason)]))}
    end.

upload_response(Req = #request{from_jid = FromJID, to_jid = ToJID},
                #{<<"mime-type">> := MimeType,
                  <<"filename">> := Filename,
                  <<"purpose">> := Purpose},
                Size) ->
    Metadata = #{<<"content-type">> => MimeType,
                 <<"name">> => Filename,
                 <<"purpose">> => Purpose},
    FileID = make_file_id(),
    {Headers, RespFields} =
        (backend()):make_upload_response(FromJID, ToJID, FileID,
                                         Size, Metadata),


    FullFields = common_fields(FromJID, FileID) ++ RespFields,
    response(Req, Headers, FullFields, <<"upload">>).

download_response(Req = #request{from_jid = FromJID, to_jid = ToJID},
                          OwnerID, FileID) ->
    {Headers, RespFields} =
    (backend()):make_download_response(FromJID, ToJID, OwnerID, FileID),

    response(Req, Headers, RespFields, <<"download">>).

response(#request{iq = IQ}, Headers, RespFields, RespType) ->
    HeaderElement = #xmlel{name = <<"headers">>,
                           children =
                           [to_header_element(H) || H <- Headers]},

    ActionElement = #xmlel{name = RespType,
                           children =
                           [HeaderElement |
                            [to_xmlel(F) || F <- RespFields]]},

    {ok, IQ#iq{type = result, sub_el = ActionElement}}.

error_response(IQ = #iq{sub_el = SubEl}, Error) ->
    IQ#iq{type = error, sub_el = [SubEl, Error]}.

common_fields(#jid{lserver = Server}, FileID) ->
    [{<<"id">>, FileID},
     {<<"jid">>, jid:to_binary(tros:make_jid(Server, FileID))}].

to_header_element({Name, Value}) ->
    #xmlel{name = <<"header">>,
           attrs = [{<<"name">>, Name}, {<<"value">>, Value}]}.

to_xmlel({Name, Content}) ->
    #xmlel{name = Name, children = [#xmlcdata{content = Content}]}.

set_config_from_opt({CfgName, EJDName, Default}, Opts) ->
    Val = proplists:get_value(CfgName, Opts, Default),
    {atomic, _} = ejabberd_config:add_local_option(EJDName, Val),
    ok.

backend() ->
    list_to_atom("mod_tros_" ++
      atom_to_list(
        ejabberd_config:get_local_option(tros_backend))).

make_file_id() ->
    ossp_uuid:make(v1, text).

binary_to_integer_def(Binary, Default) ->
    try
        binary_to_integer(Binary)
    catch
        error:badarg -> Default
    end.
