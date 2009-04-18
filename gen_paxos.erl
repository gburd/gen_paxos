%% -*- coding: utf-8 -*-
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

%% @doc generic PAXOS consensus protocol executer.
-module(gen_paxos).
-author('kuenishi+paxos@gmail.com').

-export([behaviour_info/1, version_info/0]).

-export([ask/2, start_link/2,
	 stop/0, clear/0]).

behaviour_info(callbacks)->
    [
     {start, 4},
     {stop,  1},
     {result,1}
    ];
behaviour_info(_Other)->
    undefined.

version_info()-> {?MODULE, 1}.

-define( DEFAULT_COORDINATOR_NUM, 3 ).

%% spawns a coordinator process.
%% @spec  start_link( node_identifier(), initN, other_players() ) -> Pid
start_link( InitN, Others )->
    start_link( InitN, Others, ?DEFAULT_COORDINATOR_NUM ).


start_link( InitN, Others, 0 )->
    ok;
start_link( InitN, Others, NumCoordinators )->
    Pid = spawn_link( ?MODULE,  coordinator, [InitN, Others] ),
    register( get_process_name_from_int(NumCoordinators), Pid ),
    start_link( InitN, Others, NumCoordinators-1).

get_process_name_from_int( N )-> % 1...?DEFAULT_COORDINATOR_NUM
    list_to_atom( "coordinator" ++ integer_to_list(N) ).

get_process_name_from_key( Key )-> 
    get_process_name_from_int( erlang:phash( Key, ?DEFAULT_COORDINATOR_NUM ) ). % 1...?DEFAULT_COORDINATOR_NUM

stop()->
    stop( ?DEFAULT_COORDINATOR_NUM ).

stop(0)-> ok;
stop(N)-> 
    Coordinator = get_process_name_from_int( N ),
    Coordinator ! {self(), stop, normal}.
    

%%ask(Key, void, Callback)->
%%    ok.
ask(Key, Value)->
    Coordinator = get_process_name_from_key( Key ),
    Coordinator ! {self(), ask, { Key, Value }},
    receive
	{From, result, {Key, Value} }-> %success
	    Value;
	{From, result, {Key, Other} }->
	    Other
    end.

clear()->
    clear( ?DEFAULT_COORDINATOR_NUM ).

clear(0)-> ok;
clear(N)-> 
    Coordinator = get_process_name_from_int( N ),
    Coordinator ! {self(), clear, normal}.


coordinator( InitN, Others )->
    receive
	{From, ask, {Key, void}}->
	    From ! {self(), result, {Key, get( Key )}};
	{From, ask, {Key, Value}}->
	    case get( Key ) of
		undefined->            %% when the subject not yet done
		    paxos_fsm:start( Key, InitN, Value, Others );
		ResultValue-> %% when the subject already done
		    From ! {self(), result, {Key, ResultValue} } %% return the result
	    end;
	{From, set, {Key, Value}}->
	    put( Key, Value );
	{From, stop, normal}->
	    exit( stop )
    end,
    coordinator( InitN, Others ).
%% TODO: need renewal of Waiting list
