-module(friend_logic).
%%%
%  friend 业务逻辑模块
%%%
-export([search/1]).
-export([add_friend/4]).
-export([confirm_friend/4]).
-export([confirm_friend_resp/2]).
-export([delete_friend/2]).
-export([move_to_category/3]).
-export([information/2]).


-include_lib("imboy/include/log.hrl").


-spec add_friend(CurrentUid::integer(),
    To::binary(),
    Payload::list(),
    CreatedAt::integer() | CreatedAt::binary()
) -> ok | {error, Msg::binary(), Param::binary()}.
add_friend(_, undefined, _, _) ->
    {error, <<"Parameter error">>, <<"to">>};
add_friend(_, _, undefined, _) ->
    {error, <<"Parameter error">>, <<"payload">>};
add_friend(_, _, _, undefined) ->
    {error, <<"Parameter error">>, <<"created_at">>};
add_friend(CurrentUid, To, Payload, CreatedAt) when is_binary(CreatedAt) ->
    add_friend(CurrentUid, To, Payload, binary_to_integer(CreatedAt));
add_friend(CurrentUid, To, Payload, CreatedAt) ->
    ToId = imboy_hashids:uid_decode(To),
    NowTs = imboy_dt:millisecond(),
    From = imboy_hashids:uid_encode(CurrentUid),
    MsgId = <<"af_", From/binary, "_", To/binary>>,
    % ?LOG([is_binary(Payload), Payload]),
    % 存储消息
    msg_s2c_ds:write_msg(CreatedAt, MsgId, Payload,
        CurrentUid, ToId, NowTs),
    Msg = message_ds:assemble_msg(<<"S2C">>, From, To, Payload, MsgId),
    % ?LOG(Msg),
    MsLi = [0, 1500, 1500, 3000, 5000, 7000],
    message_ds:send_next(ToId, MsgId, jsone:encode(Msg, [native_utf8]), MsLi),
    ok.

-spec confirm_friend(CurrentUid::integer(),
    From::binary(),
    To::binary(),
    Payload::list()
) -> {ok, list()} | {error, Msg::binary(), Param::binary()}.
confirm_friend(_, undefined, _, _) ->
    {error, <<"Parameter error">>, <<"from">>};
confirm_friend(_, _, undefined, _) ->
    {error, <<"Parameter error">>, <<"to">>};
confirm_friend(_, _, _, undefined) ->
    {error, <<"Parameter error">>, <<"payload">>};
confirm_friend(CurrentUid, From, To, Payload) ->
    FromID = imboy_hashids:uid_decode(From),
    ToID = imboy_hashids:uid_decode(To),
    NowTs = imboy_dt:millisecond(),
    Payload2 = jsone:decode(Payload, [{object_format, proplist}]),

    FromSetting = proplists:get_value(<<"from">>, Payload2),
    % Remark1 为 from 对 to 定义的 remark
    Remark1 = proplists:get_value(<<"remark">>, FromSetting),
    Source = proplists:get_value(<<"source">>, FromSetting),
    FromToIsFriend = friend_ds:is_friend(FromID, ToID),
    % 好友关系写入数据库
    friend_repo:confirm_friend(FromToIsFriend,
        FromID, ToID, Remark1, [{<<"is_from">>, 1} | FromSetting], NowTs),

    ToSetting = proplists:get_value(<<"to">>, Payload2),
    ToFromIsFriend = friend_ds:is_friend(ToID, FromID),
    % Remark2 为 to 对 from 定义的 remark
    Remark2 = proplists:get_value(<<"remark">>, ToSetting),
    % 好友关系写入数据库
    friend_repo:confirm_friend(ToFromIsFriend,
        ToID, FromID, Remark2, [{<<"source">>, Source} | ToSetting], NowTs),

    % 因为是 ToID 通过API确认的，所以只需要给FromID 发送消息
    MsgId = <<"afc_", From/binary, "_", To/binary>>,
    MsgType = proplists:get_value(<<"msg_type">>, Payload2),
    Payload3 = confirm_friend_resp(ToID, Remark1),
    Payload4 = [{<<"is_from">>, 1} | Payload3],
    Payload5 = [{<<"source">>, Source} | Payload4],
    Payload6 = [{<<"msg_type">>, MsgType} | Payload5],

    % 存储消息
    msg_s2c_ds:write_msg(NowTs, MsgId, Payload6, CurrentUid, FromID, NowTs),

    % 这里的From To 需要对调，离线消息需要对调
    Msg = message_ds:assemble_msg(<<"S2C">>, To, From, Payload, MsgId),

    % ?LOG(Msg),
    MsLi = [0, 1500, 1500, 3000, 5000, 7000],
    message_ds:send_next(FromID, MsgId, jsone:encode(Msg, [native_utf8]), MsLi),
    {ok, FromID, Remark2, Source}.


confirm_friend_resp(Uid, Remark) ->
    Column = <<"`id`,`account`,`nickname`,`avatar`,`gender`,`sign`,`region`,`status`">>,
    User = user_logic:find_by_id(Uid, Column),
    [{<<"remark">>, Remark} | imboy_hashids:replace_id(User)].

-spec delete_friend(CurrentUid::integer(), UID::binary()) -> ok.
delete_friend(CurrentUid, UID) ->
    friend_repo:delete(CurrentUid, imboy_hashids:uid_decode(UID)),
    ok.

%%% 查找非好友
search(Uid) ->
    % 只能够搜索“用户被允许搜索”的用户
    %
    FriendIDs = friend_ids(Uid),
    Info = FriendIDs,
    Info.

move_to_category(CurrentUid, Uid, CategoryId) ->
    friend_repo:move_to_category(CurrentUid, Uid, CategoryId),
    ok.

information(CurrentUid, Uid) ->
    ?LOG([CurrentUid, Uid]),
    Info = [],
    Info.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------


friend_ids(Uid) ->
    Column = <<"`to_user_id`">>,
    case friend_repo:find_by_uid(Uid, Column) of
        [] ->
            [];
        Friends ->
            [ID || [{<<"to_user_id">>, ID}] <- Friends]
    end.
