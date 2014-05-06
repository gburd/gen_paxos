
APP             ?=gen_paxos
REBAR=          /usr/bin/env rebar
DIALYZER=	/usr/bin/env dialyzer
ERL=		/usr/bin/env erl

all: deps compile

deps:
	$(REBAR) get-deps

compile:
	$(REBAR) compile

plt: compile
	@$(DIALYZER) --build_plt --output_plt .$(TARGET).plt \
		-pa deps/plain_fsm/ebin \
		deps/plain_fsm/ebin \
		--apps kernel stdlib

analyze: compile
	$(DIALYZER) --plt .$(TARGET).plt \
	-pa deps/plain_fsm/ebin \
	-pa deps/ebloom/ebin \
	ebin

repl:
	$(ERL) -pz deps/*/ebin -pa ebin

test: tests

tests:
	@ $(REBAR) skip_deps=true $(REBAR_FLAGS) $(EUNIT_OPTIONS) eunit app=$(APP)
	@ $(REBAR) $(REBAR_FLAGS) ct app=$(APP)

clean:
	$(REBAR) $(REBAR_FLAGS) clean
	-rm test/*.beam

distclean: clean
	$(REBAR) delete-deps
