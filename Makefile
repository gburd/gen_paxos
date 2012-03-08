
APP             ?=gen_paxos
ERL             ?=erl
CT_RUN          ?=ct_run
ERL_FLAGS       ?=+A10
REBAR_FLAGS     :=

all: deps compile

deps:
	$(REBAR) get-deps

compile:
	ERL_FLAGS=$(ERL_FLAGS) $(REBAR) $(REBAR_FLAGS) compile

test: tests

tests:
	@ $(REBAR) $(REBAR_FLAGS) eunit app=$(APP)
	@ $(REBAR) $(REBAR_FLAGS) ct app=$(APP)

clean:
	$(REBAR) $(REBAR_FLAGS) clean
	-rm test/*.beam

distclean: clean
	$(REBAR) delete-deps

include rebar.mk

.EXPORT_ALL_VARIABLES:
