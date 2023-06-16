-module(collect_handler).
%%%
% collect 控制器模块
% collect controller module
%%%
-behavior(cowboy_rest).

-export([init/2]).

-ifdef(EUNIT).
-include_lib("eunit/include/eunit.hrl").
-endif.
-include_lib("imboy/include/log.hrl").
-include_lib("kernel/include/logger.hrl").
-include_lib("imboy/include/common.hrl").

%% ===================================================================
%% API
%% ===================================================================

init(Req0, State0) ->
    % ?LOG(State),
    Action = maps:get(action, State0),
    State = maps:remove(action, State0),
    Req1 = case Action of
        page ->
            page(Req0, State);
        add ->
            add(Req0, State);
        remove ->
            remove(Req0, State);
        change ->
            change(Req0, State);
        false ->
            Req0
    end,
    {ok, Req1, State}.

%% ===================================================================
%% Internal Function Definitions
%% ===================================================================

page(Req0, State) ->
    CurrentUid = maps:get(current_uid, State),
    {Page, Size} = imboy_req:page_size(Req0),
    Kind = imboy_req:get_int(kind, Req0, 0),
    #{order := OrderBy} = cowboy_req:match_qs([{order, [], <<>>}], Req0),
    #{kwd := Kwd} = cowboy_req:match_qs([{kwd, [], <<>>}], Req0),
    % #{kind := Kind} = cowboy_req:match_qs([{kind, [], 0}], Req0),
    UidBin = integer_to_binary(CurrentUid),
    ?LOG([page, Kind]),

    KwdWhere = if
        byte_size(Kwd) > 0 ->
            <<" and (cu.source like '%", Kwd/binary, "%' or cu.remark like '%", Kwd/binary, "%' or r.info like '%", Kwd/binary, "%')">>;
        true ->
            <<>>
    end,

    % use index i_collect_user_UserId_Status_Kind
    KindWhere = case Kind of
        {ok, 0}  ->
            {ok, <<"cu.user_id = ", UidBin/binary," and cu.status = 1", KwdWhere/binary>>};
        {ok, Kind2} when is_integer(Kind2)  ->
            Kind3 = integer_to_binary(Kind2),
            {ok, <<"cu.user_id = ", UidBin/binary," and cu.status = 1 and cu.kind = ", Kind3/binary, KwdWhere/binary>>};
        _ ->
            {error, "Kind is invalid"}
    end,

    case {KindWhere, OrderBy} of
        {{error, Msg}, _OrderBy} ->
            imboy_response:error(Req0, Msg);
        {{ok, Where}, <<"recent_use">>} ->
            Payload = collect_logic:page(Page, Size, Where, <<"cu.updated_at desc, cu.id desc">>),
            imboy_response:success(Req0, Payload);
        {{ok, Where}, _} ->
            Payload = collect_logic:page(Page, Size, Where, <<"cu.id desc">>),
            imboy_response:success(Req0, Payload)
    end.

add(Req0, State) ->
    CurrentUid = maps:get(current_uid, State),
    PostVals = imboy_req:post_params(Req0),
    % 被收藏的资源种类： 1 文本  2 图片  3 语音  4 视频  5 文件
    Kind = proplists:get_value(<<"kind">>, PostVals, <<"">>),
    KindId = proplists:get_value(<<"kind_id">>, PostVals, <<"">>),
    Source = proplists:get_value(<<"source">>, PostVals, <<"">>),
    Remark = proplists:get_value(<<"remark">>, PostVals, <<"">>),
    Info = proplists:get_value(<<"info">>, PostVals, []),
    case collect_logic:add(CurrentUid, Kind, KindId, Info, Source, Remark) of
        {ok, _Msg} ->
            imboy_response:success(Req0);
        {error, Msg} ->
            imboy_response:error(Req0, Msg)
    end.

remove(Req0, State) ->
    CurrentUid = maps:get(current_uid, State),
    PostVals = imboy_req:post_params(Req0),
    KindId = proplists:get_value(<<"kind_id">>, PostVals, ""),
    % Val2 = proplists:get_value(<<"val2">>, PostVals, ""),
    collect_logic:remove(CurrentUid, KindId),
    imboy_response:success(Req0, #{}, "success.").

change(Req0, State) ->
    CurrentUid = maps:get(current_uid, State),
    PostVals = imboy_req:post_params(Req0),
    collect_logic:change(CurrentUid, PostVals),
    imboy_response:success(Req0, #{}, "success.").

%% ===================================================================
%% EUnit tests.
%% ===================================================================

-ifdef(EUNIT).
%addr_test_() ->
%    [?_assert(is_public_addr(?PUBLIC_IPV4ADDR)),
%     ?_assert(is_public_addr(?PUBLIC_IPV6ADDR)),
%     ?_test(my_if_addr(inet)),
%     ?_test(my_if_addr(inet6))].
-endif.
