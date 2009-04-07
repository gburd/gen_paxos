-module(gen_paxos).

-export([behaviour_info/1]).

behaviour_info(callbacks)->
    [
     {start, 4},
     {stop,  1},
