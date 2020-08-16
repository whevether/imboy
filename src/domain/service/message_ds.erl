-module (message_ds).
%%%
% message_ds 是 message domain service 缩写
%%%
-export ([msg_md5/1]).

-include("common.hrl").

msg_md5(Msg) ->
    %%%
    % msg key 的顺序和前端约定的
    %%%
    Payload = proplists:get_value(<<"payload">>, Msg),
    Msg2 = [
        {<<"type">>, proplists:get_value(<<"type">>, Msg)},
        {<<"from">>, proplists:get_value(<<"from">>, Msg)},
        {<<"to">>, proplists:get_value(<<"to">>, Msg)},
        {<<"payload">>, [
            {<<"msg_type">>, proplists:get_value(<<"msg_type">>, Payload)},
            {<<"content">>, proplists:get_value(<<"content">>, Payload)},
            {<<"send_ts">>, proplists:get_value(<<"send_ts">>, Payload)}
        ]}
    ],
    hash_util:md5(jsx:encode(Msg2)).
