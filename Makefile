.PHONY: test test-unit test-static test-legacy test-site-dir test-workflows lint clean
LUA ?= lua
PYTHON ?= python3

# Host-independent checks, then regressions inherited from CDIN.
test: test-static test-unit test-legacy

test-static:
	$(PYTHON) scripts/check_structure.py

test-unit:
	$(LUA) tests/unit/run.lua

test-legacy:
	$(LUA) ./scripts/test_commands.lua
	$(LUA) ./scripts/test_lua.lua

test-site-dir:
	@test -n "$(CDINX_DIR)" || (echo "Set CDINX_DIR to a compatible cdin-x checkout" >&2; exit 2)
	CDINX_DIR="$(CDINX_DIR)" $(LUA) ./scripts/test_site_dir.lua

test-workflows:
	@test -n "$(CDINX_DIR)" || (echo "Set CDINX_DIR to a compatible cdin-x checkout" >&2; exit 2)
	CDINX_DIR="$(CDINX_DIR)" $(LUA) ./scripts/test_workflows.lua

lint:
	@if command -v luacheck >/dev/null 2>&1; then luacheck data/core tests scripts/test_commands.lua ./scripts/test_lua.lua; else echo "luacheck not installed; skipped"; fi

clean:
	find . -type d -name __pycache__ -prune -exec rm -rf {} +
	$(PYTHON) -c "import shutil; shutil.rmtree('cdin-test-lua', ignore_errors=True)"
