-module(skipinttab).
-export([]).
-compile(export_all).

-define(DISTANCE, 10000).

new(Name) ->
    case ets:info(Name, size) of
        undefined ->
            ets:new(Name, [ordered_set, named_table, public, {write_concurrency, true}, compressed]);
        _ ->
            Name %% already created
    end.


new_bulk_write() ->
    undefined.

bulk_write(Tab, K, V, undefined) ->
    KDiv = K div ?DISTANCE,
    KMod = K rem ?DISTANCE,
    case ets:lookup(Tab, KDiv) of
        [{_, Stored}] ->
            List = insert_value(KMod, V, Stored),
            {KDiv, List};
        [] ->
            {KDiv, [KMod, V]}
    end;
bulk_write(Tab, K, V, {CurKDiv, Stored}=Acc) ->
    KDiv = K div ?DISTANCE,
    case KDiv of
        CurKDiv ->
            KMod = K rem ?DISTANCE,
            List = insert_value(KMod, V, Stored),
            {CurKDiv, List};
        _ ->
            bulk_flush(Tab, Acc),
            bulk_write(Tab, K, V, undefined)
    end.

bulk_flush(Tab, Acc) ->
    ets:insert(Tab, Acc).

write(Tab, K, V) ->
    KDiv = K div ?DISTANCE,
    case ets:lookup(Tab, KDiv) of
        [{_, Stored}] ->
            write_updated(Tab, K, V, KDiv, Stored);
        [] ->
            write_new(Tab, K, V, KDiv)
    end.

write_updated(Tab, K, V, KDiv, Stored) ->
    KMod = K rem ?DISTANCE,
    List = insert_value(KMod, V, Stored),
    ets:insert(Tab, {KDiv, List}).

lookup(Tab, K) ->
    KDiv = K div ?DISTANCE,
    case ets:lookup(Tab, KDiv) of
        [{_, Stored}] ->
            KMod = K rem ?DISTANCE,
            lookup_value(KMod, Stored);
        [] ->
            undefined
    end.


%% Stores [{Key,Value}, {DiffBetweenKeys, DiffBetweenValues}, {DiffBetweenKeys2, DiffBetweenValues2}, ...]
insert_value(K, V, [HK,HV|T]) when K > HK ->
    [K, V, K-HK, V-HV|T];
insert_value(K, V, [K,V|_]=List) ->
    List;
insert_value(K, V, [K,_]) ->
    [K,V];
insert_value(K, V, [K,OldV,NextK,NextV|T]) ->
    Diff = V-OldV,
    [K,V,NextK,NextV+Diff|T];
insert_value(K, V, [HK,HV|T]) ->
    [HK,HV|insert_value2(K, V, HK, HV, T)];
insert_value(K, V, []) ->
    [K, V].

insert_value2(K, V, PrevActualK, PrevActualV, [DiffK,DiffV|T]=List) ->
    CurActualK = PrevActualK - DiffK,
    CurActualV = PrevActualV - DiffV,
    if
        CurActualK > K ->
            [DiffK,DiffV|insert_value2(K, V, CurActualK, CurActualV, T)];
        CurActualK =:= K, CurActualV =:= V ->
            List;
        CurActualK =:= K ->
            case T of
                [] ->
                    DiffV1 = PrevActualV - V,
                    [DiffK,DiffV1];
                [NextK,NextV|T2] ->
                    DiffV1 = PrevActualV - V,
                    Diff = DiffV - DiffV1,
                    [DiffK,DiffV1,NextK,NextV+Diff|T2]
            end;
        CurActualK < K ->
            DiffK1 = PrevActualK - K,
            DiffK2 = K - CurActualK,
            DiffV1 = PrevActualV - V,
            DiffV2 = V - CurActualV,
            [DiffK1, DiffV1, DiffK2, DiffV2|T]
    end;
insert_value2(K, V, PrevActualK, PrevActualV, []) ->
    [PrevActualK-K, PrevActualV-V].


lookup_value(K, [K,V|_]) ->
    V;
lookup_value(K, [FirstK,FirstV|List]) ->
    lookup_value(FirstK-K, FirstV, List).

lookup_value(K, V, [CurK, CurV|T]) when K > CurK ->
    %% not right place yet
    K2 = K-CurK,
    V2 = V-CurV,
    lookup_value(K2, V2, T);
lookup_value(K, V, [K, CurV|_]) ->
    V-CurV;
lookup_value(_K, _V, _) -> % when K > CurK
    undefined.

write_new(Tab, K, V, KDiv) ->
    KMod = K rem ?DISTANCE,
    List = [KMod, V],
    ets:insert(Tab, {KDiv, List}).


-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

lookup_value_test_() ->
    List0123 = insert_value(3,9,insert_value(2,4,insert_value(1,1, insert_value(0,0,[])))),
    List1023 = insert_value(3,9,insert_value(2,4,insert_value(0,0, insert_value(1,1,[])))),
    List3021 = insert_value(1,1,insert_value(2,4,insert_value(0,0, insert_value(3,9,[])))),
    List3012 = insert_value(2,4,insert_value(1,1,insert_value(0,0, insert_value(3,9,[])))),
    List30021 = insert_value(1,1,insert_value(2,4,insert_value(0,0, insert_value(0,10, insert_value(3,9,[]))))),
    List32021 = insert_value(1,1,insert_value(2,4,insert_value(0,0, insert_value(2,10, insert_value(3,9,[]))))),
    [?_assertEqual(0, lookup_value(0, List0123))
    ,?_assertEqual(1, lookup_value(1, List0123))
    ,?_assertEqual(4, lookup_value(2, List0123))
    ,?_assertEqual(9, lookup_value(3, List0123))

    ,?_assertEqual(0, lookup_value(0, List1023))
    ,?_assertEqual(1, lookup_value(1, List1023))
    ,?_assertEqual(4, lookup_value(2, List1023))
    ,?_assertEqual(9, lookup_value(3, List1023))

    ,?_assertEqual(0, lookup_value(0, List3021))
    ,?_assertEqual(1, lookup_value(1, List3021))
    ,?_assertEqual(4, lookup_value(2, List3021))
    ,?_assertEqual(9, lookup_value(3, List3021))

    %% all keys are positive
    ,?_assert(lists:all(fun(X) -> X > 0 end, keys(List0123)))
    ,?_assert(lists:all(fun(X) -> X > 0 end, keys(List1023)))
    ,?_assert(lists:all(fun(X) -> X > 0 end, keys(List3021)))

    %% transitive
    ,?_assertEqual(keys(List0123), keys(List1023))
    ,?_assertEqual(keys(List0123), keys(List3021))

    %% transitive
    ,?_assertEqual(List0123, List1023)
    ,?_assertEqual(List0123, List3021)
    ].

keys([K,_|T]) ->
    [K|keys(T)];
keys([]) ->
    [].

vals([K,_|T]) ->
    [K|vals(T)];
vals([]) ->
    [].

-endif.
