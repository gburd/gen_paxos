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

-export([behaviour_info/1]).

behaviour_info(callbacks)->
    [
     {start, 4},
     {stop,  1},
     {result,1}
    ].
