-module(location_handler).
%%%
% location 控制器模块
% location controller module
%%%
-behavior(cowboy_rest).

-export([init/2]).

-ifdef(EUNIT).
-include_lib("eunit/include/eunit.hrl").
-endif.
-include_lib("kernel/include/logger.hrl").
-include_lib("imboy/include/common.hrl").
-include_lib("imboy/include/log.hrl").

%% ------------------------------------------------------------------
%% api
%% ------------------------------------------------------------------

init(Req0, State0) ->
    % ?LOG(State),
    Action = maps:get(action, State0),
    % ?LOG([people_nearby, handler, Action]),
    State = maps:remove(action, State0),
    Req1 = case Action of
        make_myself_visible ->
            make_myself_visible(Req0, State);
        make_myself_unvisible ->
            make_myself_unvisible(Req0, State);
        people_nearby ->
            people_nearby(Req0, State);
        false ->
            Req0
    end,
    {ok, Req1, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
% 让自己可见
make_myself_visible(Req0, State) ->
    CurrentUid = maps:get(current_uid, State),
    Uid = imboy_hashids:uid_encode(CurrentUid),

   {ok, PostVals, _Req} = cowboy_req:read_body(Req0),
   LatLng = jsone:decode(PostVals, [{object_format, map}]),
   Lat = maps:get(<<"latitude">>, LatLng, <<"">>),
   Lng = maps:get(<<"longitude">>, LatLng, <<"">>),
   case location_logic:make_myself_visible(Uid, Lat, Lng) of
        ok ->
           imboy_response:success(Req0, #{}, "success.");
        {error, Msg} ->
           imboy_response:error(Req0, Msg)
    end.

% 让自己不可见
make_myself_unvisible(Req0, State) ->
    CurrentUid = maps:get(current_uid, State),
    Uid = imboy_hashids:uid_encode(CurrentUid),
   location_logic:make_myself_unvisible(Uid),
   imboy_response:success(Req0, #{}, "success.").

% 附近的人
people_nearby(Req0, _State) ->
    #{longitude := Lng} = cowboy_req:match_qs([{longitude, [], undefined}], Req0),
    #{latitude := Lat} = cowboy_req:match_qs([{latitude, [], undefined}], Req0),
    #{radius := Radius} = cowboy_req:match_qs([{radius, [], <<"500">>}], Req0),
    #{unit := Unit} = cowboy_req:match_qs([{unit, [], <<"km">>}], Req0),
    #{limit := Limit} = cowboy_req:match_qs([{limit, [], <<"100">>}], Req0),

    % ?LOG([people_nearby, handler, Lng, Lat, Radius, Unit, Limit]),
    List = location_logic:people_nearby(Lng, Lat, Radius, Unit, Limit),
    imboy_response:success(Req0, [
        {<<"radius">>, Radius},
        {<<"size">>, length(List)},
        {<<"unit">>, Unit},
        {<<"list">>, List}
    ], "success.").

%% ------------------------------------------------------------------
%% EUnit tests.
%% ------------------------------------------------------------------

-ifdef(EUNIT).
%addr_test_() ->
%    [?_assert(is_public_addr(?PUBLIC_IPV4ADDR)),
%     ?_assert(is_public_addr(?PUBLIC_IPV6ADDR)),
%     ?_test(my_if_addr(inet)),
%     ?_test(my_if_addr(inet6))].
-endif.
