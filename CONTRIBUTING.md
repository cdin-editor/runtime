# Contributing to cdin-runtime

This repository is an experimental Lua runtime extraction. Read [architecture](docs/architecture.md), [source map](docs/source-map.md), and [migration status](docs/migration-status.md) before changing module ownership.

## Requirements

- Lua 5.4 for the supported test target.
- Python 3.10+ for source-manifest and structural checks.
- `luacheck` is recommended but not required for the basic checks.

## Local checks

```sh
python3 scripts/check_structure.py
lua tests/unit/run.lua
lua ./scripts/test_commands.lua
lua ./scripts/test_lua.lua
```

Or run `make test` with `LUA=lua5.4` if your Lua executable is named differently.

## Change rules

1. Keep pure Runtime utilities independent of `core.init`, SDL and process globals.
2. Add tests for both valid and failing inputs.
3. Update `docs/migration-status.md` when a boundary is actually migrated; copying a file is not a migration gate.
4. Do not add C Host, SDL, native bindings, OS services, or Kernel implementation here.
5. Do not change the provisional Host API version without updating tests and a reviewed architecture decision.
6. Keep the Kernel document/history as the only canonical owner once the Backend Host API is integrated.

## Pull requests

Keep a PR focused, include the test output, and distinguish unit-test evidence from integration tests using the real CDIN Backend and Kernel.
