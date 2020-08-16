-module (user_setting_repo).
%%%
% user_setting_repo 是 user_setting repository 缩写
%%%
-export ([find_by_uid/2]).
-export ([update/2]).

-include("common.hrl").


find_by_uid(Uid, Column) ->
    Where = <<"WHERE `user_id` = ?">>,
    Sql = <<"SELECT ", Column/binary, " FROM `user_setting` ", Where/binary>>,
    mysql_pool:query(Sql, [Uid]).

update(Uid, Setting) ->
    Sql = <<"REPLACE INTO `user_setting` (`user_id`, `setting`, `updated_at`) VALUES (?, ?, ?)">>,
    % ?LOG([Sql, [Uid, jsx:encode(Setting), dt_util:milliseconds()]]),
    mysql_pool:query(Sql, [Uid, jsx:encode(Setting), dt_util:milliseconds()]).
