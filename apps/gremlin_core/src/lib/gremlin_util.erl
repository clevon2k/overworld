-module(gremlin_util).

-export([
    run_checks/1,
    run_bchecks/1,
    any_in_list/2,
    pipeline/2,
    remove_dups/1
]).

-spec run_bchecks(list()) -> ok | any().
run_bchecks([]) ->
    ok;
run_bchecks([H | T]) when is_function(H, 0) ->
    case H() of
        true -> run_bchecks(T);
        _ -> false
    end.

-spec run_checks(list()) -> ok | any().
run_checks([]) ->
    ok;
run_checks([H | T]) when is_function(H, 0) ->
    case H() of
        ok -> run_checks(T);
        Error -> Error
    end.

% poor man's pipe
-spec pipeline(any(), list()) -> any().
pipeline(Input, Funs) ->
    lists:foldl(fun(F, State) -> F(State) end, Input, Funs).

-spec any_in_list(list(), list()) -> list().
any_in_list(L1, L2) ->
    % Checks to see if any item in L1 is present in L2
    [X || X <- L1, lists:member(X, L2) == true].

% Remove duplicates from a list
% https://stackoverflow.com/questions/13673161/remove-duplicate-elements-from-a-list-in-erlang
remove_dups([]) -> [];
remove_dups([H | T]) -> [H | [X || X <- remove_dups(T), X /= H]].

% some map* functions equivalent to the list functions that operate over tuples
% shameless stolen from https://github.com/biokoda/bkdcore/blob/master/src/butil.erl
mapfind(K,V,[H|L]) ->
	case maps:get(K,H) of
		V ->
			H;
		_ ->
			mapfind(K,V,L)
	end;
mapfind(_,_,[]) ->
	false.

mapstore(Key,Val,[H|L],Map) ->
	case maps:get(Key,H) of
		Val ->
			[Map|L];
		_ ->
			[H|mapstore(Key,Val,L,Map)]
	end;
mapstore(_,_,[],Map) ->
	[Map].

maplistsort(Key,L) ->
	maplistsort(Key,L,asc).
maplistsort(Key,L,asc) ->
	Asc = fun(A,B) -> maps:get(Key,A) =< maps:get(Key,B) end,
	lists:sort(Asc,L);
maplistsort(Key,L,desc) ->
	Desc = fun(A,B) -> maps:get(Key,A) >= maps:get(Key,B) end,
	lists:sort(Desc,L).
