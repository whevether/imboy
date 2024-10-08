-module(msg_c2g_repo).
%%%
% msg_c2g_repo 是 msg_c2g repository 缩写
%%%

-include_lib("imlib/include/chat.hrl").
-include_lib("imlib/include/log.hrl").

-export([tablename/0]).
-export([write_msg/6]).
-export([list_by_ids/2]).
-export([delete_msg/1]).
-export([delete_msg/2]).

%% ===================================================================
%% API
%% ===================================================================


tablename() ->
    imboy_db:public_tablename(<<"msg_c2g">>).


write_msg(CreatedAt, Id, Payload, FromId, ToUids, Gid) when is_integer(FromId) ->
    FromId2 = integer_to_binary(FromId),
    write_msg(CreatedAt, Id, Payload, FromId2, ToUids, Gid);
write_msg(CreatedAt, Id, Payload, FromId, ToUids, Gid) when is_integer(Gid) ->
    Gid2 = integer_to_binary(Gid),
    write_msg(CreatedAt, Id, Payload, FromId, ToUids, Gid2);
% 批量插入群离线消息表 及 时间线表
write_msg(CreatedAt, MsgId, Payload, FromId, ToUids, Gid) ->
    Tb = tablename(),
    % ?LOG([CreatedAt, Payload, FromId, ToUids, Gid]),
    imboy_db:with_transaction(fun(Conn) ->
        CreatedAt2 = integer_to_binary(CreatedAt),
        Payload2 = imboy_hasher:encoded_val(Payload),
        % ?LOG(CreatedAt2),
        Column = <<"(payload,to_id,from_id,created_at,msg_id)">>,
        Sql = <<"INSERT INTO ", Tb/binary, " ", Column/binary, " VALUES(", Payload2/binary,
              ", '", Gid/binary, "', '", FromId/binary, "', '", CreatedAt2/binary,
              "', '", MsgId/binary, "');">>,
        % ?LOG(Sql),
        {ok, Stmt} = epgsql:parse(Conn, Sql),
        epgsql:execute_batch(Conn, [{Stmt, []}]),
        % Res = epgsql:execute_batch(Conn, [{Stmt, []}]),
        % ?LOG(["Res", Res]), % [{ok,1}]
         % [{ok, 1, _}] = Res,
        Vals = lists:map(fun(ToId) ->
                ToId2 = ec_cnv:to_binary(ToId),
               Val = <<"('", MsgId/binary, "', '", ToId2/binary, "', '",
                       Gid/binary, "', '", CreatedAt2/binary, "')">>,
               binary_to_list(Val)
           end,
           ToUids),
        L1 = lists:flatmap(fun(Val) -> [Val, ","] end, Vals),
        [_ | L2] = lists:reverse(L1),
        Values = list_to_binary(lists:concat(L2)),
        Column2 = <<"(msg_id,to_uid,to_gid,created_at)">>,
        Tb2 = msg_c2g_timeline_repo:tablename(),
        Sql2 = <<"INSERT INTO ", Tb2/binary, " ", Column2/binary, " VALUES",
               Values/binary>>,
        % ?LOG([Sql, Sql2]),
        {ok, Stmt2} = epgsql:parse(Conn, Sql2),
        epgsql:execute_batch(Conn, [{Stmt2, []}]),
        ok
    end),
    ok.


% msg_c2g_repo:list_by_ids(MsgIds, <<"payload">>).
list_by_ids([], _Column) ->
    {ok, [], []};
list_by_ids(Ids, Column) ->
    Tb = tablename(),
    L1 = lists:flatmap(fun(Id) -> [Id, "','"] end, Ids),
    [_ | L2] = lists:reverse(L1),
    Ids2 = erlang:iolist_to_binary(L2),
    Where = <<" WHERE msg_id IN ('", Ids2/binary, "')">>,
    Sql = <<"SELECT ", Column/binary, " FROM ", Tb/binary, Where/binary, " order by created_at ASC">>,
    % ?LOG(Sql),
    imboy_db:query(Sql).


% msg_c2g_repo:delete_msg(6).
delete_msg(Id) ->
    Where = <<"WHERE msg_id = $1">>,
    delete_msg(Where, [Id]).


delete_msg(Where, Params) when is_list(Params) ->
    Tb = tablename(),
    Sql = <<"DELETE FROM ", Tb/binary, " ", Where/binary>>,
    imboy_db:execute(Sql, Params).
