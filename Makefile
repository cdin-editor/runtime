LUA ?= lua5.4

.PHONY: deps test unit integration boundary check clean

deps:
	bash scripts/install-deps.sh

test: unit integration

unit:
	$(LUA) tests/unit/run.lua

integration:
	$(LUA) tests/integration/run.lua

# Static guards (no console output, no native code, no second logger). Needs bash and grep.
boundary:
	bash scripts/check-boundaries.sh

# `check` stays Lua-only so it runs anywhere Lua does; CI and `scripts/ci-check.sh` add `boundary`.
check: test

clean:
	rm -rf build coverage dist
