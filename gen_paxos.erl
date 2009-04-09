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

-export([ask/3, start_link/2, stop/0, clear/0]).

behaviour_info(callbacks)->
    [
     {start, 4},
     {stop,  1},
     {result,1}
    ].

version_info()-> [?MODULE, 0.1.0].

%% spawns a coordinator process.
%% @spec  start_link( node_identifier(), initN, other_players() ) -> Pid
start_link( InitN, Others )->
    Pid = spawn_link( ?MODULE,  coordinator, [InitN, Others] ),
    register( coordinator, Pid ),
    Pid.

stop

%%ask(Key, void, Callback)->
%%    ok.
ask(Key, Value, Callback)->
    coordinator ! {self(), ask, { Key, Value, Callback }},
    receive
	{From, result, {Key, Value} }-> %success
	    Value;
	{From, result, {Key, Other} }->
	    Other;
	{From, doing, _} ->
	    ask(Key, Value, Callback)
    end.

coordinator( InitN, Others, DoingList )->
    receive
	{From, ask, {Key, Value, Callback}}->
	    case get( Key ) of
		undefined->            %% when the subject not yet done
		    paxos_fsm:start( Key, InitN, Value, Others ),
		    NewDoingList = [Key | DoingList ];
		{done, ResultValue} -> %% when the subject already done
%%		    Callback( Key, Value ),
		    From ! {self(), result, {Key, ResultValue} }, %% return the result
		    NewDoingList = DoingList
	    end
    end,
    %% TODO: need renewal of Waiting list
    coordinator( InitN, Others, NewDoingList).
