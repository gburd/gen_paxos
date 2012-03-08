README: gen_paxos/paxos_fsm

                                                                   2009.8.1
                                                   kuenishi+paxos@gmail.com

* Motivation

  gen_paxos is a generic paxos module, easy to use in distributed system.
 paxos implementation is to be a large finite state machine. My motivation
 is to reduce the cost of re-invention of wheels.
  PAXOS is a consensus method in distributed and masterless environment,
 which is mathmatically guaranteed to make conclusion in infinite time.


* Current status

  Freezed. Anyone who wants to succeed, keep tracking and developing this code,
 will be welcomed very much. It is also free under LGPL to download,  branch
 and use this code, permitted everywhere. If you please this code, I'd 
 like you to tell usage/technical report to me, I'll be very pleased so much!!!

  A prototype of paxos consensus protocol (paxos_fsm) has successfully worked.
 GENeric PAXOS module has still more to do. 2-phase paxos consensus 
 algorithm works, but not so fast as other replication/consensus protocols.


* Usage

  With setting (1)Name of Subject, (2)Identity Number in PAXOS group,
 (3)Value that PAXOS agent will propose, and (4)Other PAXOS agents into
 paxos_fsm:start/4, PAXOS consensus IPC (part-time parliament) starts. With
 calling paxos_fsm:get_result/1 you'll get result of the parliament. With
 calling paxos_fsm:stop/1 you'll garbage-collect the part-time parliament.

** Usage Sample
- in node A:
 nodeA> node().
 'nodeA'.
 nodeA> nodes().
 ['nodeB'].
 nodeA> gen_paxos:start_link( 0, nodes() ).
 nodeA> gen_paxos:ask( somekey, somevalue ).
 ...(paxos consensus protocol started; messages will be printed)...
 paxos mediation done. decided: hogehoge - (N=2)
 nodeA> gen_paxos:stop().
 paxos_fsm terminated (normal).
 ok
 StateName: decided
 StateData: ....
 nodeA>

- in node B:
 nodeB> node().
 'nodeB'.
 nodeB> nodes().
 ['nodeA'].
 nodeB> gen_paxos:start_link( 1, nodes() ).
 ...(paxos consensus protocol started; messages will be printed)...
 paxos mediation done. decided: hogehoge - (N=2)
 nodeB> gen_paxos:ask( somekey, void ).
 somevalue
 nodeB> 


* Future works

 - to refine the code so as to work as a generic erlang module - deprecated. 
 - automation of basic tests.
 - to expand coverege of tested combinations of states.
   - because paxos is complex FSM as a whole
 - to create a gen_leader[2] compatible interface?
 - gen_serverize
 - master election module with lease time, with replication consistency
 - performance test
 - documentation :P


* Related works

 - libpaxos ( http://sourceforge.net/projects/libpaxos )
 libpaxos is almost same implementation of PAXOS consensus protocol. it has Simple
 version and Fast version of paxos and seems well working. it's implementation
 has paxos coordinator process, SPOF in a really distributed environment,
 which is solved in gen_paxos.

 - gen_leader ( http://www.cs.chalmers.se/~hanssv/leader_election/ )
 gen_leader is a master election module whose behaviour looks like gen_server.
 It's siginificant in churn environment (maybe) and small rate of mis-election,
 controllability with proirity. Valid information and details are in [2].


* Appendix
 - Usage / Copy / Redistribution License is LGPLv3; see COPYING and COPYING.LESSER.


[1] Chandra, Tushar; Robert Griesemer, Joshua Redstone (2007).
 "Paxos Made Live – An Engineering Perspective". PODC '07:
 26th ACM Symposium on Principles of Distributed Computing.
 http://labs.google.com/papers/paxos_made_live.html.

[2] Svensson, H. and Arts, T. 2005. A new leader election implementation. 
 In Proceedings of the 2005 ACM SIGPLAN Workshop on Erlang (Tallinn, Estonia, 
 September 26 - 28, 2005). ERLANG '05. ACM, New York, NY, 35-39. DOI= 
  http://doi.acm.org/10.1145/1088361.1088368 
