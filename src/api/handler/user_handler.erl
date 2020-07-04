-module(user_handler).
-behavior(cowboy_rest).

-export([init/2]).

-include("imboy.hrl").

init(Req0, State) ->
    % ?LOG(State),
    Req1 = case lists:keyfind(action, 1, State) of
        {action, change_state} ->
            change_state(Req0, State);
        {action, change_sign} ->
            change_sign(Req0, State);
        false ->
            Req0
    end,
    {ok, Req1, State}.

%% 切换在线状态
change_state(Req0, State) ->
    CurrentUid = proplists:get_value(current_uid, State),
    {ok, PostVals, _Req} = cowboy_req:read_urlencoded_body(Req0),
    ChatState = proplists:get_value(<<"state">>, PostVals, <<"hide">>),
    user_setting_ds:save_state(CurrentUid, ChatState),
    % 切换在线状态 异步通知好友
    gen_server:cast(offline_server, {notice_friend, CurrentUid, ChatState}),
    resp_json_dto:success(Req0, [], "操作成功.").

%% 修改签名
change_sign(Req0, State) ->
    CurrentUid = proplists:get_value(current_uid, State),
    {ok, PostVals, _Req} = cowboy_req:read_urlencoded_body(Req0),
    Sign = proplists:get_value(<<"sign">>, PostVals, <<"">>),
    case user_ds:change_sign(CurrentUid, Sign) of
        {error, {_, _, ErrorMsg}} ->
            resp_json_dto:error(Req0, ErrorMsg);
        ok ->
            resp_json_dto:success(Req0, [], "操作成功.")
    end.


