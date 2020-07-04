-module(websocket_handler).
-behavior(cowboy_websocket).

-export([init/2]).
-export([websocket_init/1]).
-export([websocket_handle/2]).
-export([websocket_info/2]).
-export([terminate/3]).

-include("imboy.hrl").

%%websocket 握手
init(Req0, State0) ->
    case websocket_ds:check_subprotocols(Req0, State0) of
        {ok, Req1, State1} ->
            {ok, Req1, State1};
        {cowboy_websocket, Req1, State1, Opt} ->
            case cowboy_req:match_qs([{token, [], undefined}], Req1) of
                #{token := undefined} ->
                    % HTTP 412 - 先决条件失败
                    Req2 = cowboy_req:reply(412, Req1),
                    {ok, Req2, State1};
                #{token := Token} ->
                    ?LOG(Token),
                    case catch token_ds:decrypt_token(Token) of
                        {ok, Uid, _ExpireAt, _Type} ->
                            Timeout = user_as:idle_timeout(Uid),
                            {cowboy_websocket, Req1, [{current_uid, Uid}|State1], Opt#{idle_timeout := Timeout}};
                        {error, Code, _Msg, _Li} ->
                            {cowboy_websocket, Req1, [{error, Code} | State1], Opt}
                    end
            end
    end.

%%连接初始 onopen
websocket_init(State) ->
    CurrentPid = self(),
    % ?LOG([websocket_init, lists:keyfind(error, 1, State), State]),
    case lists:keyfind(error, 1, State) of
        {error, Code} ->
            Msg = [
                {<<"type">>, <<"error">>},
                {<<"code">>, Code},
                {<<"timestamp">>, imboy_func:milliseconds()}
            ],
            {reply, {text, jsx:encode(Msg)}, State, hibernate};
        false ->
            CurrentUid = proplists:get_value(current_uid, State),
            % 用户上线
            user_as:online(CurrentUid, CurrentPid, web),
            {ok, State, hibernate}
    end.

%%处理客户端发送投递的消息 onmessage
websocket_handle(ping, State) ->
    ?LOG([ping, cowboy_clock:rfc1123(), State]),
    case lists:keyfind(error, 1, State) of
        {error, _Code} ->
            {stop, State};
        false ->
            {reply, pong, State, hibernate}
    end;
websocket_handle({text, <<"ping">>}, State) ->
    ?LOG([<<"ping">>, cowboy_clock:rfc1123(), State]),
    case lists:keyfind(error, 1, State) of
        {error, _Code} ->
            {stop, State};
        false ->
            {reply, {text, <<"pong">>}, State, hibernate}
    end;
websocket_handle({text, Msg}, State) ->
    % ?LOG([State, Msg]),
    % ?LOG(State),
    try
        case lists:keyfind(error, 1, State) of
            {error, Code} ->
                ErrMsg = [
                    {<<"type">>, <<"error">>},
                    {<<"code">>, Code},
                    {<<"timestamp">>, imboy_func:milliseconds()}
                ],
                {reply, ErrMsg};
            false ->
                CurrentUid = proplists:get_value(current_uid, State),
                Data = jsx:decode(Msg),
                Type = proplists:get_value(<<"type">>, Data),
                case cowboy_bstr:to_upper(Type) of
                    <<"C2C">> ->
                        websocket_as:dialog(CurrentUid, Data);
                    <<"GROUP">> ->
                        websocket_as:group_dialog(CurrentUid, Data);
                    <<"SYSTEM">> ->
                        websocket_as:system(CurrentUid, Data)
                end
        end
    of
        Res ->
            ?LOG(Res),
            case Res of
                ok ->
                    {ok, State, hibernate};
                {reply, Msg2} ->
                    {reply, {text, jsx:encode(Msg2)}, State, hibernate}
            end
    catch
        ErrCode:ErrorMsg ->
            % lager:error("websocket_handle try catch: ~p", [ErrCode,ErrorMsg, Msg]),
            ?LOG(["websocket_handle try catch: ", ErrCode, ErrorMsg, Msg]),
            {ok, State, hibernate}
    end;
websocket_handle({binary, Msg}, State) ->
    {[{binary, Msg}], State};
websocket_handle(_Frame, State) ->
    {ok, State, hibernate}.

%% 处理erlang 发送的消息
websocket_info({timeout, _Ref, Msg}, State) ->
    % ?LOG(Msg),
    {reply, {text, Msg}, State, hibernate};
websocket_info(stop, State) ->
    ?LOG([stop, State]),
    {stop, State};
websocket_info(_Info, State) ->
    {ok, State}.

%% 断开socket onclose
%% Rename websocket_terminate/3 to terminate/3
%% link: https://github.com/ninenines/cowboy/issues/787
terminate(_Reason, _Req, State) ->
    ?LOG([terminate, State]),
    case lists:keyfind(current_uid, 1, State) of
        {current_uid, Uid} ->
            user_as:offline(Uid, self());
        false ->
            chat_store_repo:dirty_delete(self())
    end,
    ok.
