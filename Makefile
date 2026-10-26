LUA ?= lua5.4

.PHONY: test unit integration check clean

test: unit integration

unit:
	$(LUA) tests/unit/run.lua

integration:
	$(LUA) tests/integration/run.lua

check: test

clean:
	rm -rf build coverage
