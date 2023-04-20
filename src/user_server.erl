-module(user_server).

-include_lib("imboy/include/chat.hrl").

-include_lib("imboy/include/log.hrl").
%%%
% 用户异步行为服务
%%%
-behaviour(gen_server).

%% API.
-export([start_link/0]).
-export([stop/0]).

%% gen_server.
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).

%%
-export([cast_notice_friend/2]).
-export([cast_online/3]).
-export([cast_offline/3]).


%% API.

-spec start_link() -> {ok, pid()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).


-spec stop() -> stopped.
stop() ->
    gen_server:call(?MODULE, stop).


%% gen_server.

-spec init([]) -> {ok, []}.
init([]) ->
    {ok, []}.


handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};
handle_call(Request, From, State) ->
    ?LOG([handle_call, Request, From, State]),
    {reply, ignored, State}.


% 异步处理请求

% 用户注册成功后的逻辑处理
handle_cast({signup_success, Uid, PostVals}, State) ->
    ?LOG([Uid, imboy_hashids:uid_decode(Uid), PostVals]),
    % 生成account
    {noreply, State, hibernate};
% 用户登录成功后的逻辑处理
handle_cast({login_success, Uid, PostVals}, State) ->
    % 用户登录成功之后的业务逻辑处理
    % 更新 user 表
    % 更新 user_client 表
    Uid2 = imboy_hashids:uid_decode(Uid),
    Now = imboy_dt:millisecond(),
    ?LOG([Uid, Uid2, PostVals]),
    % 记录设备信息
    DID = proplists:get_value(<<"did">>, PostVals, <<"">>),
    user_device_repo:save(Now, Uid2, DID, PostVals),
    % 记录设备信息 END
    {noreply, State, hibernate};

handle_cast({notice_friend, Uid, ToState}, State) ->
    ?LOG([notice_friend, Uid, ToState]),
    notice_friend(Uid, ToState),
    {noreply, State, hibernate};
handle_cast({offline, Uid, _Pid, DID}, State) ->
    ?LOG([offline, Uid, State, DID]),
    notice_friend(Uid, <<"offline">>),
    {noreply, State, hibernate};
handle_cast({online, Uid, Pid, DID}, State) ->
    ?LOG([online, Uid, Pid, State, DID]),
    DName = user_device_repo:device_name(Uid, DID),
    % 在其他设备登录了
    MsgType = <<"logged_another_device">>,
    Payload = [
        {<<"msg_type">>, MsgType},
        {<<"did">>, DID},
        {<<"dname">>, DName}
    ],
    ToUid = imboy_hashids:uid_encode(Uid),
    Msg = message_ds:assemble_msg(<<"S2C">>, <<"">>, ToUid, Payload, MsgType),

    MsLi = [0, 5000, 10000],
    message_ds:send_next(DID, Uid, MsgType, jsone:encode(Msg, [native_utf8]), MsLi),
    % 检查上线通知好友
    case user_setting_ds:chat_state_hide(Uid) of
        false ->
            % 上线通知好友
            notice_friend(Uid, <<"online">>),
            ok;
        true ->
            ok
    end,
    % ?LOG(["before check_msg/2",Uid, Pid, State]),
    % 检查离线消息
    msg_c2c_logic:check_msg(Uid, Pid, DID),
    % 检查群聊离线消息
    msg_c2g_logic:check_msg(Uid, Pid, DID),
    {noreply, State, hibernate};

handle_cast(Msg, State) ->
    ?LOG([Msg, State]),
    {noreply, State}.


handle_info(_Info, State) ->
    {noreply, State}.


-spec terminate(_, _) -> ok.
terminate(_Reason, _State) ->
    ok.


code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% 切换在线状态 异步通知好友
cast_notice_friend(CurrentUid, ChatState) ->
    gen_server:cast(?MODULE, {notice_friend, CurrentUid, ChatState}),
    ok.


%% 检查消息 用异步队列实现

-spec cast_online(Uid :: binary(), Pid :: pid(), DID :: binary()) -> ok.
cast_online(Uid, Pid, DID) ->
    gen_server:cast(?MODULE, {online, Uid, Pid, DID}),
    ok.


%% 检查离线消息 用异步队列实现
cast_offline(Uid, Pid, DID) ->
    gen_server:cast(?MODULE, {offline, Uid, Pid, DID}),
    ok.


%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

-spec notice_friend(Uid::integer(), binary()) -> ok.
notice_friend(Uid, State) ->
    Column = <<"`to_user_id`">>,
    case friend_repo:find_by_uid(Uid, Column) of
        {ok, _, []} ->
            ok;
        {ok, ColumnList, Rows} ->
            Friends = [lists:zipwith(fun(X, Y) -> {X, Y} end, ColumnList, Row) ||
                Row <- Rows],
            % ?LOG([State, Friends]),
            send_state_msg(Uid, State, Friends),
            ok
    end.


-spec send_state_msg(any(), user_chat_state(), list()) -> ok.
send_state_msg(_FromId, _State, []) ->
    ok;
% 给在线好友发送上线消息
send_state_msg(FromId, State, [[{<<"to_user_id">>, ToUid}] | Tail]) ->
    % ?LOG([FromId, State, ToUid, Tail]), % echo [1,<<"3">>,<0.892.0>]
    case chat_online:lookup(ToUid) of
        [] ->
            ok;
        List ->
            [send_msg(State, FromId, ToUid2, ToPid2) ||
                {_, ToPid2, ToUid2, _DType, _DID} <- List]
    end,
    send_state_msg(FromId, State, Tail).

-spec send_msg(State::binary(), From::integer(), To::binary(), ToPid::pid())
    ->ok.
send_msg(State, From, To, ToPid) ->
    ?LOG([State, From, To, ToPid]),
    % 用户在线状态变更
    % State: <<"online">> | <<"offline">> | <<"hide">>.
    Payload = [
        {<<"msg_type">>, State}
    ],
    From2 = imboy_hashids:uid_encode(From),
    To2 = imboy_hashids:uid_encode(To),
    Msg = message_ds:assemble_msg(<<"S2C">>, From2, To2, Payload, <<"">>),
    erlang:start_timer(1, ToPid, jsone:encode(Msg, [native_utf8])),
    ok.
