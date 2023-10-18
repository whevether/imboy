-module(group_logic).
%%%
% group 业务逻辑模块
%%%
-export([member_list/1]).

-include_lib("imlib/include/log.hrl").


% group_logic:member_list(1).
member_list(Gid) ->
    Column = <<"user_id,alias,description,role">>,
    case group_member_repo:find_by_gid(Gid, Column) of
        {ok, _, []} ->
            [];
        {ok, _ColumnLi, Members} ->
            Uids = [Uid || {Uid, _, _, _} <- Members],
            Members2 = [lists:zipwith(fun(X, Y) -> {X, Y} end,
                                      [<<"alias">>, <<"description">>, <<"role">>],
                                      [Alias, Desc, Role]) || {_Uid, Alias, Desc, Role} <- Members],
            Users = user_logic:find_by_ids(Uids),
            % 获取用户在线状态
            Users2 = [user_logic:online_state(User) || User <- Users],
            % 合并 user 信息 和 member信息
            lists:zipwith(fun(X, Y) -> X ++ Y end, Users2, Members2);
        _ ->
            []
    end.
