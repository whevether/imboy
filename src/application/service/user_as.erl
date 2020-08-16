-module (user_as).
%%%
% user_as 是 user application service 缩写
%%%
-export ([do_login/2]).
-export ([refreshtoken/2]).
-export ([online/3]).
-export ([offline/2]).
-export ([idle_timeout/1]).

-include("common.hrl").

do_login(InputAccount, Pwd) ->
    Column = <<"`id`,`account`,`password`,`nickname`,`avatar`,`gender`">>,
    Res = case func:is_mobile(InputAccount) of
        true ->
            user_repo:find_by_mobile(InputAccount, Column);
        false ->
            user_repo:find_by_account(InputAccount, Column)
    end,
    ?LOG(Res),
    {Check, User} = case Res of
        {ok, _FieldList, [[Id, Account, Password, Nickname, Avator, Gender]]} ->
            ?LOG([Pwd, Password]),
            case password_util:verify(Pwd, Password) of
                {ok, _} ->
                    {true, [Id, Account, Nickname, Avator, Gender]};
                {error, Msg} ->
                    {false, Msg}
            end;
        _ ->
            % io:format("res is ~p~n",[Res]),
            {false, []}
    end,
    ?LOG([Check, User]),
    if Check == true ->
            {ok, login_success_aas:data(User)};
        true ->
            {error, "账号或密码错误"}
    end.

refreshtoken(Token, Refreshtoken) ->
    [Token, Refreshtoken].

-spec online(any(), pid(), any()) -> ok.
online(Uid, Pid, Type) ->
    case user_ds:is_offline(Uid) of
        {ToPid, _Uid, _Type} ->
            Msg = [
                {<<"type">>, <<"error">>},
                {<<"from_id">>, Uid},
                {<<"to_id">>, Uid},
                {<<"code">>, 786},
                {<<"msg">>, unicode:characters_to_binary("在其他地方上线")},
                {<<"timestamp">>, dt_util:milliseconds()}
            ],
            erlang:start_timer(10, ToPid, jsx:encode(Msg));
        true ->
            ok
    end,
    user_ds:online(Uid, Pid, Type),

    % 检查离线消息 用异步队列实现
    gen_server:cast(offline_server, {online, Uid, Pid}),
    ok.

-spec offline(any(), pid()) -> ok.
offline(Uid, Pid) ->
    user_ds:offline(Pid),
    % 检查离线消息 用异步队列实现
    gen_server:cast(offline_server, {offline, Uid, Pid}).

% 设置用户websocket超时时间，默认60秒
idle_timeout(_UId) ->
    60000.
