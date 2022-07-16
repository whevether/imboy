-module(chat_online).

-include_lib("stdlib/include/qlc.hrl").
-include_lib("imboy/include/log.hrl").

%% API
-export([dirty_insert/4,
         dirty_delete/1]).

-export([init/0,
         lookup/1,
         lookup/2,
         lookup_by_dtype/2,
         lookall/0]).

%%
% pid   进程ID
% uid   登录用户ID
% dtype 设备类型 web ios android macos windows等
% did   设备ID
-record(chat_online, {
          pid,
          uid,
          dtype,
          did
         }).

%%%===================================================================
%%% API
%%%===================================================================
init() ->
    % ok.
    dynamic_db_init().


%--------------------------------------------------------------------
%% @doc  dirty insert uid pid dtype did
%% @spec  dirty_insert(UID, Pid, DType, DID)
%% @end
%%--------------------------------------------------------------------

dirty_insert(UID, Pid, DType, DID) when is_integer(UID) ->
    dirty_insert(integer_to_binary(UID), Pid, DType, DID);
dirty_insert(UID, Pid, DType, DID) when is_list(UID) ->
    dirty_insert(list_to_binary(UID), Pid, DType, DID);
dirty_insert(UID, Pid, DType, DID) when is_pid(Pid) ->
    mnesia:dirty_write(#chat_online{pid = Pid,
                                    uid = UID,
                                    dtype = DType,
                                    did = DID}).

dirty_delete(Pid) when is_pid(Pid) ->
    mnesia:dirty_delete(chat_online, Pid);
dirty_delete(UID) when is_integer(UID) ->
    dirty_delete(integer_to_binary(UID));
dirty_delete(UID) when is_list(UID) ->
    dirty_delete(list_to_binary(UID));
dirty_delete(UID) ->
    [dirty_delete(Pid) || {chat_online, Pid, _UID, _DType, _DID} <- lookup(UID)],
    ok.


%%--------------------------------------------------------------------
%% @doc Find a pid given a key.
%% @spec lookup(Key) -> {ok, Pid} | {error, not_found}
%% @end
%% @link https://blog.csdn.net/wudixiaotie/article/details/84735787
%%      chat_online:lookup(1).
%%--------------------------------------------------------------------
%% [{chat_online,<0.1155.0>,<<"1">>,<<"iOS">>,<<"78ece1d4d7d346a1">>}]
-spec lookup(pid() | integer()) -> list().
lookup(Pid) when is_pid(Pid) ->
    mnesia:dirty_read(chat_online, Pid);
lookup(UID) when is_integer(UID) ->
    lookup(integer_to_binary(UID));
lookup(UID) when is_list(UID) ->
    lookup(list_to_binary(UID));
lookup(UID) ->
    mnesia:dirty_index_read(chat_online, UID, #chat_online.uid).


lookup(UID, DID) ->
    [M1 || M1 <- lookup(UID), M1#chat_online.did =:= DID].

lookup_by_dtype(UID, Dtype) ->
    [M1 || M1 <- lookup(UID), M1#chat_online.dtype =:= Dtype].

%%--------------------------------------------------------------------
%% @doc Find all list
%% @spec lookall() -> {List} | {error, not_found}
%% @end
%%--------------------------------------------------------------------
lookall() ->
    do(qlc:q([[X#chat_online.pid,
               X#chat_online.uid,
               X#chat_online.dtype,
               X#chat_online.did] || X <- mnesia:table(chat_online)])).


%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------

%%%===================================================================
%%% Internal functions
%%%===================================================================
dynamic_db_init() ->
    % 不过 mnesia 是否启动这里都先停止它，便于下面初始化成功
    application:stop(mnesia),
    % mnesia检查数据库是否创建
    % 确保先创建 schema 之后再启动 mnesia
    case mnesia:system_info(use_dir) of
        true ->
            alread_created_schema;
        _ ->
            % mnesia:delete_schema([node()|nodes()])
            mnesia:create_schema([node() | nodes()])
    end,

    application:start(mnesia),
    % 创建表 chat_online
    % 确保已经 mnesia:start().
    case lists:member(chat_online, mnesia:system_info(tables)) of
        false ->
            % 创建表
            mnesia:create_table(chat_online,
                                [{type, set},
                                 % disc_copies 磁盘 + 内存; ram_copies 内存
                                 {ram_copies, [node() | nodes()]},
                                 {attributes, record_info(fields,
                                                          chat_online)}]),
            mnesia:add_table_index(chat_online, uid);
        % mnesia:add_table_index(chat_online, did);
        true ->
            alread_created_table
    end,
    % 暂停10毫秒，等待创建、启动mnesia数据库
    timer:sleep(10),
    ok.


do(Query) ->
    F = fun() -> qlc:e(Query) end,
    {atomic, Value} = mnesia:transaction(F),
    Value.
