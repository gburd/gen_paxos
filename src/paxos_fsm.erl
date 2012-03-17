%% -*- coding: utf-8 -*-
%%     gen_paxos
%% 　  Copyright (C) 2009   kuenishi+paxos@gmail.com

%%     This program is free software: you can redistribute it and/or modify
%%     it under the terms of the Apache Software License 2.0

%% @doc PAXOS Finite State Machine implementation
-module(paxos_fsm).
-author('kuenishi+paxos@gmail.com').

-behaviour(gen_fsm).

-export([version_info/0]).

%% @doc functions for users.
-export([start/5, stop/1, get_result/1]).

%% @doc functions for gen_fsm.
-export([init/1, handle_event/3, handle_sync_event/4,
         handle_info/3, terminate/3, code_change/4]).

%% @doc states of FSM.
-export([nil/2, preparing/2, proposing/2, acceptor/2,
         learner/2, decided/2]).

-define( DEFAULT_TIMEOUT, 3000 ).

%% @doc state data for all machines,
%%
-record( state, {subject, n, value,
                 all, quorum, current=0, others, init_n,
                 return_pids=[]
                } ).

%% -record( event, {name,
%%               subject, n, value,
%%               from} ).

%% @type subject_identifier() = atom()
%% @type propose_number() = int()
%% @type players() = list()

version_info()-> {?MODULE, 1}.

%% @doc   Users call this function. Initializes PAXOS FSM.
%%        subject_identifier - subject name. this names process, unless paxos_fsm can't find others.
%%        n()                - paxos_fsm agent id. this must be unique in the paxos_fsm group.
%%                             no more than length of players.
%%        any()              - value to suggest (prepare, propose).
%%        other_players()    - member list of paxos_fsm group, which consists of agents, except oneself.
%%        return_pids()       - when consensus got decided, result is to be sent to return_pid().
%%
%% @spec  start( subject_identifier(), n(), any(), other_players(), return_pid() ) -> Result
%%    Result = {ok, Pid} | ignore | { error, Error }
%%    Error  = {already_started, Pid } | term()
%%    Pid = pid()
%%
start(S, InitN, V, Others, ReturnPids) ->
%%    lists:map( fun(Other)-> net_adm:ping(Other) end, Others ),
    %% setting data;
    All = length(Others)+1,    Quorum = All / 2 ,
    InitStateData = #state{ subject=S, n=InitN, value=V,
                            all=All, quorum=Quorum, others=Others, init_n=InitN,
                            return_pids=ReturnPids },
    gen_fsm:start_link(
      generate_global_address( node(), S ), %FsmName  %%{global, ?MODULE},       %{local, {?MODULE, S} },
      ?MODULE,                        %Module
      InitStateData,                %Args
      [{timeout, ?DEFAULT_TIMEOUT}]   %Options  %%, {debug, debug_info} ]
     ).

%% @doc    Users can stop the FSM after or before PAXOS have make result.
%% @spec   stop( subject_identifier() ) ->  ok
stop(S) ->  %    io:format("~p ~p.~n",  [?MODULE, stopped]),
    gen_fsm:send_all_state_event( generate_global_address( node(),S ), stop).

%% @doc    Users can get result as long as FSM remains.
%% @spec   get_result( subject_identifier() ) -> Reply
%%    Reply = {decided, V} | {OtherStateName, V}
get_result(S)->
    gen_fsm:sync_send_all_state_event( generate_global_address( node(),S ), result).


%% ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ %%
%%   codes below are for gen_fsm. users don't need.       %%
%% ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ %%

init(InitStateData)->
    %% message;
    io:format("~p ~p: ~p~n", [?MODULE, started, InitStateData]),
    %% starting paxos_fsm...
    process_flag(trap_exit, true),
    {ok,
     nil,  %% initial statename
     InitStateData,     %%{{S, InitN, V},{All, Quorum, 0, Others, InitN}, Misc }, %% initial state data
     ?DEFAULT_TIMEOUT %% initial state timeout
    }.

broadcast(Others, S, Message)->
    PaxosOthers = [ generate_global_address( P, S ) || P <-  Others ],
    lists:map( fun(Other)-> gen_fsm:send_event( Other, Message ) end , %Timeout * 1) end,
               PaxosOthers ).

send(Node, S, Message)->
%    io:format("sending: ~p to ~p~n", [Message, {global, {?MODULE, Node, S}}] ),
    gen_fsm:send_event( generate_global_address( Node, S ), Message ).

get_next_n( N , All )-> (( N div All )+1) * All.

generate_global_address( Node, Subject )->  {global, {?MODULE, Node, Subject}}.

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
%%  - {{Sc, Nc, Vc}, {All, Quorum, Current, Others, InitN}}

%% =========================================
%%  - nil ( master lease time out )
nil( {prepare,  {S, N, _V, From}},  StateData) when N > StateData#state.n ->
%    {{S, Nc, _Vc}, Nums} ) when N > Nc ->
%    gen_fsm:sync_send_event(From, {prepare_result, {0, nil}}),
    send(From, S, {prepare_result, {S, 0, nil, node()}}),
    NewStateData = StateData#state{n=N},
    {next_state, acceptor, NewStateData, %{{S, N, V}, Nums},
     ?DEFAULT_TIMEOUT};
nil( {prepare,  {S, N, _V, From}}, StateData) when N < StateData#state.n ->  %{{S, Nc, Vc}, Nums} ) when N < Nc ->
%    gen_fsm:sync_send_event(From, {prepare_result, {0, nil}}),
    send(From, S, {prepare_result, {S, StateData#state.n, StateData#state.value, node()}}),
    {next_state, nil, StateData, ?DEFAULT_TIMEOUT};
%    {next_state, nil, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};

%% nil( {decide,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc -> % always ignore
%%     {next_state, nil, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
nil( {decide,  {S, N, V, _From}}, StateData ) -> % when N == Nc
%    {_OldNums , Members} = StateData,
%    {next_state, decided, {{S, N, V}, Members}, ?DEFAULT_TIMEOUT};
    S=StateData#state.subject,
    decided_callback( StateData#state{n=N, value=V} );
%    {next_state, decided, StateData#state{subject=S, n=N, value=V}, ?DEFAULT_TIMEOUT};

%nil( timeout, {{S, N, V}, {All, Quorum, _Current, Others, InitN}} )->
nil( timeout, StateData )-> %{{S, N, V}, {All, Quorum, _Current, Others, InitN}} )->
    % send prepare ! to all members.
    NewN = get_next_n( StateData#state.n, StateData#state.all ) + StateData#state.init_n,
    io:format( "starting paxos ... ~p. ~n", [[NewN, StateData]]),
%    Result = broadcast( Others, S, {prepare, {S,NewN,V, node()}} ),
    S=StateData#state.subject,
    V=StateData#state.value,
    Result = broadcast( StateData#state.others, S, {prepare, {S, NewN, V, node()}} ),
    io:format( "broadcast: ~p. ~n", [Result]),
%    {next_state, preparing, {{S, NewN, V}, {All, Quorum, 1, Others, InitN}}, ?DEFAULT_TIMEOUT};
    {next_state, preparing, StateData#state{n=NewN, current=1}, ?DEFAULT_TIMEOUT};

nil(UnknownEvent, StateData)-> % ignore
    io:format( "unknown event: ~p,  ~p : all ignored.~n", [UnknownEvent, StateData] ),
    {next_state, nil, StateData, ?DEFAULT_TIMEOUT}.


%% =========================================
%%  - preparing
%preparing( {prepare,  {S, N, _V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
preparing( {prepare,  {S, N, _V, From}},  StateData ) when N < StateData#state.n ->
%    gen_fsm:sync_send_event( From, {prepare, {S, Nc, Vc} } ),
    send( From, S,  {prepare, {S, StateData#state.n, StateData#state.value, node()} } ),
    {next_state, preparing, StateData, ?DEFAULT_TIMEOUT};
%% preparing( {prepare,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
preparing( {prepare,  {S, N, V, From}},  StateData ) when N > StateData#state.n ->
    send( From, S, {prepare_result, {S, StateData#state.n, StateData#state.value, node()}}),
    io:format("sending prepare_result and going acceptor...~n", []),
    {next_state, acceptor, StateData#state{subject=S, n=N, value=V}, ?DEFAULT_TIMEOUT};

%preparing( {prepare_result,  {S, N, V, From}},  {{S, Nc, _Vc}, Nums} ) when N > Nc ->
preparing( {prepare_result,  {S, N, V, From}},  StateData ) when N > StateData#state.n ->
    send( From, S, {prepare_result, {S, N, V, node()}} ),
    {next_state, acceptor, StateData#state{subject=S, n=N, value=V}, ?DEFAULT_TIMEOUT};

preparing( {prepare_result,  {S, _N, _V, _From}}, StateData ) when StateData#state.current > StateData#state.quorum ->
%          {{S, Nc, Vc}, {All, Quorum, Current, Others, InitN}} ) when Current > Quorum->
    broadcast( StateData#state.others, S, {propose, {S,StateData#state.n,StateData#state.value, node()}} ),
%    {next_state, proposing, {{S, Nc, Vc}, {All, Quorum, 1, Others, InitN}}, ?DEFAULT_TIMEOUT};
    {next_state, proposing, StateData#state{current=1}, ?DEFAULT_TIMEOUT};

%preparing( {prepare_result,  {S, N, V, _From}}, {{S, N, V}, {All, Quorum, Current, Others, InitN}} )->
preparing( {prepare_result,  {S, N, V, _From}}, StateData )
  when S==StateData#state.subject , N==StateData#state.n , V==StateData#state.value ->
    Current = StateData#state.current,
    {next_state, proposing, StateData#state{current=Current+1}, ?DEFAULT_TIMEOUT};

%preparing( {prepare_result,  {S, N, _V, _From}}, {{S, Nc, Vc}, {All, Quorum, Current, Others, InitN}} ) when N < Nc->
preparing( {prepare_result,  {S, N, _V, _From}}, StateData ) when N < StateData#state.n ->
 %{{S, Nc, Vc}, {All, Quorum, Current, Others, InitN}} ) when N < Nc->
 %   io:format("recvd: ~p; (Current, Quorum)=(~p,~p)~n", [{{S,N,_V,_From}, {S, Nc, Vc }}, Current, Quorum]),
    case (StateData#state.current + 1 > StateData#state.quorum) of
        true ->
            io:format("got quorum at prepare!~n", []),
            broadcast( StateData#state.others, S, {propose, {S, StateData#state.n, StateData#state.value, node()}} ),
%           io:format("proposing ~p...~n", [{propose, {S,Nc,Vc,node()}}]),
            {next_state, proposing, StateData#state{current=1}, ?DEFAULT_TIMEOUT};
        false ->
            Current = StateData#state.current,
            {next_state, preparing, StateData#state{current=Current+1}, ?DEFAULT_TIMEOUT}
                                                %{{S, Nc, Vc}, {All, Quorum, Current+1, Others, InitN}},
    end;

%% preparing( {propose,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     {next_state, hoge, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% preparing( {propose,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
preparing( {propose,  {S, N, V, From}},  StateData ) when N > StateData#state.n ->
    send( From, S, {propose_result, {S, N, V, node()}} ),
    {next_state, learner, StateData#state{n=N, value=V}, ?DEFAULT_TIMEOUT};

%% preparing( {propose_result,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     {next_state, hoge, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% preparing( {propose_result,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
preparing( {propose_result,  {S, N, V, From}}, StateData) when N > StateData#state.n ->
    send( From, S, {propose_result, {S, N, V, node()}} ),
    {next_state, learner, StateData#state{n=N, value=V}, ?DEFAULT_TIMEOUT};

preparing( {decide,  {_S, N, V, _From}}, StateData)-> %{{S, _Nc, _Vc}, Nums} ) ->
    decided_callback( StateData#state{n=N, value=V} );
%    {next_state, decided, StateData#state{n=N, value=V}, ?DEFAULT_TIMEOUT};

preparing( timeout, StateData)-> %{{S, N, V},  {All, Quorum, _Current, Others, InitN} } )->
    {next_state, nil,  StateData#state{current=0}, ?DEFAULT_TIMEOUT}.
     %{{S, N, V}, {All, Quorum, 0, Others, InitN}}, ?DEFAULT_TIMEOUT}.

%% =========================================
%%  - proposing
%% proposing( {prepare,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     {next_state, proposing, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% proposing( {prepare,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
proposing( {prepare,  {S, N, V, From}},  StateData) when N > StateData#state.n ->  %{{S, Nc, Vc}, Nums} ) when N > Nc ->
    send( From, S,  {prepare_result, {S, StateData#state.n, StateData#state.value, node() }}),
    {next_state, acceptor, StateData#state{n=N, value=V}, ?DEFAULT_TIMEOUT};

%% proposing( {prepare_result,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     {next_state, hoge, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% proposing( {prepare_result,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
proposing( {prepare_result,  {S, N, V, From}},  StateData) when N > StateData#state.n -> %{{S, Nc, Vc}, Nums} ) when N > Nc ->
    send( From, S, {prepare_result, {S, StateData#state.n, StateData#state.value, node()}}),
    {next_state, acceptor, StateData#state{n=N, value=V}, ?DEFAULT_TIMEOUT};

%% proposing( {propose,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     {next_state, hoge, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% proposing( {propose,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
proposing( {propose,  {S, N, V, From}},  StateData) when N > StateData#state.n -> %{{S, Nc, Vc}, Nums} ) when N > Nc ->
    send( From, S, {propose_result, {S, StateData#state.n, StateData#state.value, node()}}),
    {next_state, learner, StateData#state{n=N, value=V}, ?DEFAULT_TIMEOUT};

%% proposing( {propose_result,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     {next_state, hoge, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};

%% proposing( {propose_result,  {S, N, V, _From}},
%%         {{S, N, V}, {All, Quorum, Current, Others, InitN}} ) when (Quorum > Current+1) -> % when N == Nc
proposing( {propose_result,  {S, N, V, _From}}, StateData)
  when N==StateData#state.n, V==StateData#state.value, StateData#state.quorum > StateData#state.current+1 ->
    S=StateData#state.subject,
    Current = StateData#state.current,
    {next_state, proposing, StateData#state{current=Current+1}, ?DEFAULT_TIMEOUT };

%% Got quorum!!!
%% proposing( {propose_result,  {S, N, V, _From}},
%%         {{S, N, V}, {All, Quorum, Current, Others, InitN}} )-> % when N == Nc
proposing( {propose_result,  {S, N, V, _From}}, StateData) when N==StateData#state.n, V==StateData#state.value->
    io:format("got quorum at proposing!!~n", []),
    broadcast( StateData#state.others, S, {decide, {S, N, V, node()}} ),
    Current=StateData#state.current,
    decided_callback( StateData#state{current=Current+1} );
%    {next_state, decided, StateData#state{current=Current+1}, ?DEFAULT_TIMEOUT };

proposing( {propose_result,  {S, N, V, From}}, StateData) when N > StateData#state.n -> % {{S, Nc, _Vc}, Nums} ) when N > Nc ->
    send( From,  S, {propose_result, {S, N, V, node()}}),
    {next_state, learner, StateData#state{n=N, value=V}, ?DEFAULT_TIMEOUT};

%% proposing( {decide,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc -> % always ignore
%%     {next_state, proposing, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% proposing( {decide,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, decided, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

proposing( {decide,  {S, N, V, _From}}, StateData) when N >= StateData#state.n-> %{{S, Nc, _Vc}, Nums} ) when N >= Nc ->
    S=StateData#state.subject,
    decided_callback( StateData#state{n=N, value=V} );
%    {next_state, decided, StateData#state{n=N, value=V}, ?DEFAULT_TIMEOUT};

proposing( timeout, StateData)-> %{{S, N, V}, {All, Quorum, _Current, Others, InitN}} )->
    io:format("proposing timeout: ~p  , StateData=~p~n" , [propose, StateData]),
    {next_state, nil, StateData#state{current=1}, ?DEFAULT_TIMEOUT};

proposing( _Event, StateData) ->
    {next_state, proposing, StateData}.


%% =========================================
%%  - acceptor
acceptor( {prepare,  {S, N, _V, From}},  StateData) when N < StateData#state.n-> %{{S, Nc, Vc}, Nums} ) when N < Nc ->
    send( From, S, { prepare_result, {S, StateData#state.n, StateData#state.value, node()}} ),
    {next_state, acceptor, StateData, ?DEFAULT_TIMEOUT};

%% acceptor( {prepare,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, acceptor, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
acceptor( {prepare,  {S, N, V, From}},  StateData ) when N >= StateData#state.n ->
    send( From, S, { prepare_result, {S, StateData#state.n, StateData#state.value, node()}} ),
    {next_state, acceptor, StateData#state{n=N, value=V}, ?DEFAULT_TIMEOUT};

%% acceptor( {prepare_result,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     {next_state, hoge, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% acceptor( {prepare_result,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
%% acceptor( {prepare_result,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N > Nc ->
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

acceptor( {propose,  {S, N, _V, _From}},  StateData) when N < StateData#state.n -> %{{S, Nc, Vc}, Nums} ) when N < Nc ->
    io:format("bad state: ~p (N,Nc)=(~p)~n" , [{propose},{ N, StateData#state.n}]),
    S=StateData#state.subject,
    {next_state, propose, StateData, ?DEFAULT_TIMEOUT};
acceptor( {propose,  {S, N, V, From}},  StateData ) when N > StateData#state.n ->
    send( From, S, {propose_result , {S, StateData#state.n, StateData#state.value, node() }} ),
    {next_state, learner, StateData#state{n=N, value=V}, ?DEFAULT_TIMEOUT};
acceptor( {propose,  {S, N, V, From}},  StateData)-> % when N == Nc
    {N,V}={StateData#state.n, StateData#state.value},
    send( From, S, {propose_result , {S, StateData#state.n, StateData#state.value,  node() }} ),
    {next_state, learner, StateData, ?DEFAULT_TIMEOUT};

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
acceptor( {decide,  {S, N, V, _From}}, StateData) when N >= StateData#state.n -> %{{S, Nc, _Vc}, Nums} ) when N >= Nc ->
    S=StateData#state.subject,
    decided_callback( StateData#state{n=N, value=V} );
%    {Next_state, decided, StateData#state{n=N, value=V}, ?DEFAULT_TIMEOUT};

acceptor( timeout, StateData)-> %{{S, N, V}, {All, Quorum, _Current, Others, InitN} })->
    io:format("acceptor timeout: ~p (N,V)=(~p)~n" , [{propose},{StateData#state.n, StateData#state.value}]),
    {next_state, nil, StateData#state{current=1}, ?DEFAULT_TIMEOUT};

acceptor( _Event, StateData) ->
    io:format("acceptor unknown event: ~p ,~p~n" , [_Event , StateData]),
    {next_state, acceptor, StateData}.

%% =========================================
%%  - learner
%% learner( {prepare,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N < Nc ->
%%     {next_state, hoge, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% learner( {prepare,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
learner( {prepare,  {S, N, V, From}}, StateData) when N > StateData#state.n -> % {{S, Nc, _Vc}, Nums} ) when N > Nc ->
    send( From, S, {prepare_result, {S, N, V, node()}} ),
    {next_state, acceptor, StateData#state{n=N, value=V}, ?DEFAULT_TIMEOUT};

learner( {prepare_result,  {S, _N, _V, _From}}, StateData )-> % when N < Nc ->
    S=StateData#state.subject,
    {next_state, learner, StateData, ?DEFAULT_TIMEOUT };
%    {next_state, hoge, {{S, Nc, Vc}, Nums}, ?DEFAULT_TIMEOUT};
%% learner( {prepare_result,  {S, N, V, From}},  {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
%% learner( {prepare_result,  {S, N, V, From}},  {{S, Nc, Vc}, Nums} ) when N > Nc ->
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};

learner( {propose,  {S, N, _V, _From}}, StateData) when N < StateData#state.n -> %{{S, Nc, Vc}, Nums} ) when N < Nc ->
    S=StateData#state.subject,
    {next_state, learner, StateData, ?DEFAULT_TIMEOUT};
%% learner( {propose,  {S, N, V, _From}}, {{S, N, V}, Nums} ) -> % when N == Nc
%%     {next_state, hoge, {{S, N, V}, Nums}, ?DEFAULT_TIMEOUT};
learner( {propose,  {S, N, V, From}},  StateData) when N > StateData#state.n -> %{{S, Nc, _Vc}, Nums} ) when N > Nc ->
    send( From, S, {propose_result, {S, N, V, node()}}),
    {next_state, learner, StateData#state{n=N, value=V}, ?DEFAULT_TIMEOUT};

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
learner( {decide,  {S, N, V, _From}}, StateData) when N >= StateData#state.n -> %{{S, Nc, _Vc}, Nums} ) when N >= Nc ->
    S=StateData#state.subject,
    decided_callback( StateData#state{n=N, value=V} );
%    {next_state, decided, StateData#state{n=N, value=V}, ?DEFAULT_TIMEOUT};

learner( timeout, StateData)-> %{{S, N, V}, {All, Quorum, _Current, Others, InitN}} )->
    {next_state, nil, StateData#state{current=0}, ?DEFAULT_TIMEOUT};

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

decided( {_Message, {S,_N,_V, From}}, StateData)->
    send( From, S, {decide, {S,StateData#state.n, StateData#state.value,node()}} ),
    {next_state, decided, StateData, ?DEFAULT_TIMEOUT };

decided( timeout,  StateData )->
    io:format( "paxos mediation done. decided: ~p - (N=~p)~n", [StateData#state.value, StateData#state.n] ),
%    {next_state, decided, StateData}. %{{S, N, V}, Nums}}.
    {stop, normal, StateData }.

%% @doc must be called back whenever the subject got consensus!
decided_callback(StateData)->
    callback(StateData#state.subject, StateData#state.value, StateData#state.return_pids ),
    {next_state, decided, StateData, ?DEFAULT_TIMEOUT}.

%% @doc send back message to originator to share the consensus value.
callback(S, V, ReturnPids)->
    lists:map( fun(ReturnPid)-> ReturnPid ! {self(), result, {S, V}} end, ReturnPids ).

code_change(_,_,_,_)->
    ok.

handle_event( stop, _StateName, StateData )->
    {stop, normal, StateData}.

handle_info(_,_,_)->
    ok.

handle_sync_event(result, _From, StateName, StateData)->
    {reply, {StateName, StateName#state.value}  , StateName, StateData};

handle_sync_event(stop, From, StateName, StateData)->
    {stop, From, StateName, StateData}.

terminate(Reason, StateName, StateData) ->
    io:format("~p terminated (~p).~n", [?MODULE, Reason]),
    io:format("StateName: ~p~nStateData: ~p~n",  [StateName, StateData]),
    ok.
