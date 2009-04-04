%%     gen_paxos
%% 　  Copyright (C) 2009   kuenishi+paxos@gmail.com

%%     This program is free software: you can redistribute it and/or modify
%%     it under the terms of the GNU General Public License as published by
%%     the Free Software Foundation, either version 3 of the License, or
%%     (at your option) any later version.

%%     This program is distributed in the hope that it will be useful,
%%     but WITHOUT ANY WARRANTY; without even the implied warranty of
%%     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%     GNU General Public License for more details.

%%     You should have received a copy of the GNU General Public License
%%     along with this program.  If not, see <http://www.gnu.org/licenses/>.

-module(paxos_fsm).
-author('kuenishi@gmail.com').

-behaviour(gen_fsm).

-export([start/4, stop/1, get_result/1]).

-export([init/1, handle_event/3, handle_sync_event/4,
	 handle_info/3, terminate/3, code_change/4]).

-export([nil/2, preparing/2, proposing/2, acceptor/2,
	 learner/2, decided/2]).

-define( DEFAULT_TIMEOUT, 3000 ).

start(S, InitN, V, Players) ->
    lists:map( fun(Player)-> net_adm:ping(Player) end, Players ),
    gen_fsm:start_link( 
      {global, {?MODULE, node(), S}}, %{global, ?MODULE}, 
      %{local, {?MODULE, S} },
      ?MODULE, [S, InitN, V, Players],
      [{timeout, ?DEFAULT_TIMEOUT}]%, {debug, debug_info} ]
     ).

stop(S) ->  %    io:format("~p ~p.~n",  [?MODULE, stopped]),
    gen_fsm:send_all_state_event({global, {?MODULE,node(),S}}, stop).

get_result(S)->
    gen_fsm:sync_send_all_state_event({global, {?MODULE,node(),S}}, result).

init([S, InitN, V, Players])->
    io:format("~p~n", [[S, InitN, V, Players]]),
    All = length(Players)+1,
    Quorum = All / 2 ,
    io:format("~p ~p.~n",  [?MODULE, started]),
    process_flag(trap_exit, true),
    {ok, 
     nil,
     {{S, InitN, V},{All, Quorum, 0, Players, InitN} },
     ?DEFAULT_TIMEOUT
    }.

broadcast(Players, S, Message)->
    PaxosPlayers = [ {global, {?MODULE, P, S}} || P <-  Players ],
    lists:map( fun(Player)-> gen_fsm:send_event( Player, Message ) end , %Timeout * 1) end,
 	       PaxosPlayers ).

send(Node, S, Message)->
%    io:format("sending: ~p to ~p~n", [Message, {global, {?MODULE, Node, S}}] ),
    gen_fsm:send_event( {global, {?MODULE, Node, S}}, Message ).

get_next_n( N , A )->
    (( N div A )+1) * A.

%% =========================================
%% states:
%%  - nil
%%  - preparing
%%  - proposing
%%  - acceptor
%%  - learner
%%  - decided
%% events: n' < n < n''...
%%  - {prepare, {S, N, V}}
%%  - {prepare_result, {S, N, V}}
%%  - propose
%%  - propose_result
%%  - timeout
%%  - decide
%% Data:
%%  - {{Sc, Nc, Vc}, {All, Quorum, Current, Players, InitN}}

%% =========================================
%%  - nil ( master lease time out )
nil( {prepare,  {S, N, V, From}},  {{S, Nc, _Vc}, Nums} ) when N > Nc ->
%    gen_fsm:sync_send_event(From, {prepare_result, {0, nil}}),
    send(From, S, {prepare_result, {S, 0, nil, node()}}),
    {next_state, 
     acceptor, {{S, N, V}, Nums}, 
     ?DEFAULT_TIMEOUT};
nil( {prepare,  {S, N, _V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%    gen_fsm:sync_send_event(From, {prepare_result, {0, nil}}),
    send(From, S, {prepare_result, {S, Nc, Vc, node()}}),
    {next_state, nil, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};

%% nil( {decide,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc -> % always ignore
%%     {next_state, nil, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
nil( {decide,  {S, N, V, _From}}, StateData ) -> % when N == Nc
    {_OldNums , Members} = StateData,
    {next_state, decided, {{S, N, V}, Members}, ?DEFAULT_TIMEOUT};

nil( timeout, {{S, N, V}, {All, Quorum, _Current, Players, InitN}} )->
    % send prepare ! to all members.
    NewN = get_next_n( N, All ) + InitN,
    io:format( "starting paxos ... ~p. ~n", [[S, NewN, V, All, Quorum, _Current, Players, InitN]]),
    Result = broadcast( Players, S, {prepare, {S,NewN,V, node()}} ),
    io:format( "broadcast: ~p. ~n", [Result]),
    {next_state, preparing, {{S, NewN, V}, {All, Quorum, 1, Players, InitN}}, ?DEFAULT_TIMEOUT};

nil(UnknownEvent, StateData)-> % ignore
    io:format( "unknown event: ~p,  ~p : all ignored.~n", [UnknownEvent, StateData] ),
    {next_state, nil, StateData, ?DEFAULT_TIMEOUT}.


%% =========================================
%%  - preparing
preparing( {prepare,  {S, N, _V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%    gen_fsm:sync_send_event( From, {prepare, {S, Nc, Vc} } ),
    send( From, S,  {prepare, {S, Nc, Vc, node()} } ),
    {next_state, preparing, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% preparing( {prepare,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
preparing( {prepare,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N > Nc ->
    send( From, S, {prepare_result, {S, Nc, Vc, node()}}),
    io:format("sending prepare_result and going acceptor...~n", []),
    {next_state, acceptor, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

preparing( {prepare_result,  {S, N, V, From}},  {{S, Nc, _Vc}, Nums} ) when N > Nc ->
    send( From, S, {prepare_result, {S, N, V, node()}} ),
    {next_state, acceptor, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

preparing( {prepare_result,  {S, _N, _V, _From}}, 
	   {{S, Nc, Vc}, {All, Quorum, Current, Players, InitN}} ) when Current > Quorum->
    broadcast( Players, S, {propose, {S, Nc, Vc}, node()} ),
    {next_state, proposing, {{S, Nc, Vc}, {All, Quorum, 1, Players, InitN}}, ?DEFAULT_TIMEOUT};

preparing( {prepare_result,  {S, N, V, _From}}, {{S, N, V}, {All, Quorum, Current, Players, InitN}} )->
    {next_state, proposing, {{S, N, V}, {All, Quorum, Current+1, Players, InitN}}, ?DEFAULT_TIMEOUT};

preparing( {prepare_result,  {S, N, _V, _From}}, {{S, Nc, Vc}, {All, Quorum, Current, Players, InitN}} ) when N < Nc->
    io:format("recvd: ~p; (Current, Quorum)=(~p,~p)~n", [{{S,N,_V,_From}, {S, Nc, Vc }}, Current, Quorum]),
    case (Current + 1 > Quorum) of
	true -> 
	    io:format("got quorum at prepare!~n", []),
	    broadcast( Players, S, {propose, {S, Nc, Vc, node()}} ),
	    io:format("proposing ~p...~n", [{propose, {S,Nc,Vc,node()}}]),
	    {next_state, proposing, {{S, Nc, Vc}, {All, Quorum, 1, Players, InitN}}, ?DEFAULT_TIMEOUT};
	false ->
	    {next_state, preparing, {{S, Nc, Vc}, {All, Quorum, Current+1, Players, InitN}}, ?DEFAULT_TIMEOUT}
    end;

%% preparing( {propose,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     {next_state, hoge, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% preparing( {propose,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
preparing( {propose,  {S, N, V, From}},  {{S, Nc, _Vc}, Nums} ) when N > Nc ->
    send( From, S, {propose_result, {S, N, V, node()}} ),
    {next_state, learner, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

%% preparing( {propose_result,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     {next_state, hoge, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% preparing( {propose_result,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
preparing( {propose_result,  {S, N, V, From}},  {{S, Nc, _Vc}, Nums} ) when N > Nc ->
    send( From, S, {propose_result, {S, N, V, node()}} ),
    {next_state, learner, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

preparing( {decide,  {S, N, V, _From}}, {{S, _Nc, _Vc}, Nums} ) ->
    {next_state, decided, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

preparing( timeout, {{S, N, V},  {All, Quorum, _Current, Players, InitN} } )->
    {next_state, nil, {{S, N, V}, {All, Quorum, 0, Players, InitN}}, ?DEFAULT_TIMEOUT}.

%% =========================================
%%  - proposing
%% proposing( {prepare,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     {next_state, proposing, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% proposing( {prepare,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
proposing( {prepare,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N > Nc ->
    send( From, S,  {prepare_result, {S, Nc, Vc, node() }}),
    {next_state, acceptor, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

%% proposing( {prepare_result,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     {next_state, hoge, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% proposing( {prepare_result,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
proposing( {prepare_result,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N > Nc ->
    send( From, S, {prepare_result, {S, Nc, Vc, node()}}),
    {next_state, acceptor, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

%% proposing( {propose,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     {next_state, hoge, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% proposing( {propose,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
proposing( {propose,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N > Nc ->
    send( From, S, {propose_result, {S, Nc, Vc, node()}}),
    {next_state, learner, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

%% proposing( {propose_result,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     {next_state, hoge, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
proposing( {propose_result,  {S, N, V, _From}}, 
	   {{S, N, V}, {All, Quorum, Current, Players, InitN}} ) when (Quorum > Current+1) -> % when N == Nc
    {next_state, proposing, {{S,N,V},{All, Quorum, Current+1, Players, InitN}}, ?DEFAULT_TIMEOUT };

%% Got quorum!!!
proposing( {propose_result,  {S, N, V, _From}},
	   {{S, N, V}, {All, Quorum, Current, Players, InitN}} )-> % when N == Nc
    io:format("got quorum at proposing!!~n", []),
    broadcast( Players, S, {decide, {S, N, V, node()}} ),
    {next_state, decided, {{S,N,V},{All, Quorum, Current+1, Players, InitN}}, ?DEFAULT_TIMEOUT };

proposing( {propose_result,  {S, N, V, From}},  {{S, Nc, _Vc}, Nums} ) when N > Nc ->
    send( From,  S, {propose_result, {S, N, V, node()}}),
    {next_state, learner, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

%% proposing( {decide,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc -> % always ignore
%%     {next_state, proposing, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% proposing( {decide,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, decided, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
proposing( {decide,  {S, N, V, _From}}, {{S, Nc, _Vc}, Nums} ) when N >= Nc ->
    {next_state, decided, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

proposing( timeout, {{S, N, V}, {All, Quorum, _Current, Players, InitN}} )->
    io:format("proposing timeout: ~p (N,_Current)=(~p)~n" , [{propose},{ N, _Current}]),
    {next_state, nil, {{S, N, V}, {All, Quorum, 1, Players, InitN}}, ?DEFAULT_TIMEOUT};

proposing( _Event, StateData) ->
    {next_state, proposing, StateData}.


%% =========================================
%%  - acceptor
acceptor( {prepare,  {S, N, _V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
    send( From, S, { prepare_result, {S, Nc, Vc, node()}} ),
    {next_state, acceptor, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% acceptor( {prepare,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, acceptor, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
acceptor( {prepare,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N >= Nc ->
    send( From, S, { prepare_result, {S, Nc, Vc, node()}} ),
    {next_state, acceptor, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

%% acceptor( {prepare_result,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     {next_state, hoge, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% acceptor( {prepare_result,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
%% acceptor( {prepare_result,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N > Nc ->
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

acceptor( {propose,  {S, N, _V, _From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
    io:format("bad state: ~p (N,Nc)=(~p)~n" , [{propose},{ N, Nc}]),
    {next_state, propose, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
acceptor( {propose,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
    send( From, S, {propose_result , {S, N,  V,  node() }} ),
    {next_state, learner, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
acceptor( {propose,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N > Nc ->
    send( From, S, {propose_result , {S, Nc, Vc, node() }} ),
    {next_state, learner, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

%% acceptor( {propose_result,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     {next_state, hoge, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% acceptor( {propose_result,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
%% acceptor( {propose_result,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N > Nc ->
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

%% acceptor( {decide,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc -> % always ignore
%%     {next_state, acceptor, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% acceptor( {decide,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, decided, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
acceptor( {decide,  {S, N, V, _From}}, {{S, Nc, _Vc}, Nums} ) when N >= Nc ->
    {next_state, decided, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

acceptor( timeout, {{S, N, V}, {All, Quorum, _Current, Players, InitN} })->
    io:format("acceptor timeout: ~p (N,V)=(~p)~n" , [{propose},{ N, V}]),
    {next_state, nil, {{S, N, V}, {All, Quorum, 1, Players, InitN}}, ?DEFAULT_TIMEOUT};

acceptor( _Event, StateData) ->
    io:format("acceptor unknown event: ~p ,~p~n" , [_Event , StateData]),
    {next_state, acceptor, StateData}.

%% =========================================
%%  - learner
%% learner( {prepare,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     {next_state, hoge, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% learner( {prepare,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
learner( {prepare,  {S, N, V, From}},  {{S, Nc, _Vc}, Nums} ) when N > Nc ->
    send( From, S, {prepare_result, {S, N, V, node()}} ),
    {next_state, acceptor, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

learner( {prepare_result,  {S, _N, _V, _From}}, {{S, Nc, Vc}, Nums} )-> % when N < Nc ->
    {next_state, learner, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT };
%    {next_state, hoge, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% learner( {prepare_result,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
%% learner( {prepare_result,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N > Nc ->
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

learner( {propose,  {S, N, _V, _From}}, {{S, Nc, Vc}, Nums} ) when N < Nc ->
    {next_state, learner, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% learner( {propose,  {S, N, V, _From}}, {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
learner( {propose,  {S, N, V, From}},  {{S, Nc, _Vc}, Nums} ) when N > Nc ->
    send( From, S, {propose_result, {S, N, V, node()}}),
    {next_state, learner, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

%% learner( {propose_result,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     {next_state, hoge, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% learner( {propose_result,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
%% learner( {propose_result,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N > Nc ->
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

%% learner( {decide,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc -> % always ignore
%%     {next_state, learner, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% learner( {decide,  {S, N, V, _From}}, {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, decided, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
learner( {decide,  {S, N, V, _From}}, {{S, Nc, _Vc}, Nums} ) when N >= Nc ->
    {next_state, decided, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

learner( timeout, {{S, N, V}, {All, Quorum, _Current, Players, InitN}} )->
    {next_state, nil, {{S, N, V}, {All, Quorum, 0, Players, InitN}}, ?DEFAULT_TIMEOUT};

learner( _Event, StateData )->
    {next_state, learner, StateData }.


%% =========================================
%%  - decided ( within master lease time )

%% decided( {propose,  {S, N, _V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     send( From, S, {decide, {S, Nc, Vc, node()}} ),
%%     {next_state, decided, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};

%% decided( {propose_result,  {S, N, V, From}}, {Values, Nums} )->
%%     send( From, S, {decide , {S, N, V, node()}} ),
%%     {next_state, decided, {Values, Nums}, ?DEFAULT_TIMEOUT};

%% %% decided( {decide,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc -> % always ignore
%% %%     {next_state, decided, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% decided( {decide,  {S, N, V, _From}}, {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, decided, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
%% decided( {decide,  {S, N, V, _From}}, {{S, Nc, _Vc}, Nums} ) when N > Nc ->
%%     {next_state, decided, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

decided( {_Message, {S,_N,_V, From}}, {{S, N, V}, Nums})->
    send( From, S, {decide, {S,N,V,node()}} ),
    {next_state, decided, {{S,N,V},Nums} };

decided( timeout, {{S, N, V}, Nums} )->
    io:format( "paxos mediation done. decided: ~p - (N=~p)~n", [V, N] ),
    {next_state, decided, {{S, N, V}, Nums}}.
%    {stop, normal, {{S,N,V},Nums}}.



code_change(_,_,_,_)->
    ok.

handle_event( stop, _StateName, StateData )->
    {stop, normal, StateData}.

handle_info(_,_,_)->
    ok.
handle_sync_event(result, _From, StateName, StateData)->
    {{S,N,V},Nums} = StateData,
    {reply, {StateName, V}  , StateName, StateData};
handle_sync_event(stop, From, StateName, StateData)->
    {stop, From, StateName, StateData}.

terminate(Reason, StateName, StateData) ->
    io:format("~p terminated (~p).~n", [?MODULE, Reason]),
    io:format("StateName: ~p~nStateData: ~p~n",  [StateName, StateData]),
    ok.
