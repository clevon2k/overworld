%%%-------------------------------------------------------------------
%% @doc gremlin top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(gremlin_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer()}        % optional
%% child_spec() = #{id => child_id(),       % mandatory
%%                  start => mfargs(),      % mandatory
%%                  restart => restart(),   % optional
%%                  shutdown => shutdown(), % optional
%%                  type => worker(),       % optional
%%                  modules => modules()}   % optional
init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 1,
        period => 5
    },
    Modules = [
        gremlin_account,
        gremlin_session
    ],
    ChildSpecs = [
        #{
            id => gremlin_protocol,
            start => {gremlin_protocol, start, [Modules]}
        },
        %#{
        %    id => gremlin_instance_sup,
        %    start => {gremlin_instance_sup, start_link, []}
        %},
        #{
            id => gremlin_script_sup,
            start => {gremlin_script_sup, start_link, []}
        }
        %,
        %        #{
        %            id => gremlin_entity_sup,
        %            start => {gremlin_entity_sup, start_link, []}
        %        }
    ],
    {ok, {SupFlags, ChildSpecs}}.

%% internal functions