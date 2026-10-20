# Validation report — cdin-runtime 0.1.0-dev

Date: 2026-10-20

## Passed in the available environment

- `python3 scripts/check_structure.py`: PASS. It verifies 138 source-provenance entries, the literal `core.*` import graph for 53 Lua core files, required architecture documents, the deliberate legacy document-ownership exception, and relative Markdown links apart from explicitly excluded native C source links.
- `texlua tests/unit/run.lua`: PASS, 43 assertions. `texlua` in this environment embeds Lua 5.3; a standalone Lua 5.4 executable was not available, so these are not evidence of execution under Lua 5.4.
- `texlua ./scripts/test_commands.lua`: PASS, 39 assertions; 135 commands and 85 key strokes were registered in the stubbed legacy core.
- `texlua ./scripts/test_lua.lua` default environment: PASS, 37 assertions.
- `CDIN_SITE=empty texlua ./scripts/test_lua.lua`: PASS, 21 assertions.
- `CDIN_PLUGINS=false texlua ./scripts/test_lua.lua`: PASS, 34 assertions.
- `CDIN_PLUGINS=demo texlua ./scripts/test_lua.lua`: PASS, 38 assertions.
- `CDIN_SITE=empty CDIN_PLUGINS=false texlua ./scripts/test_lua.lua`: PASS, 21 assertions.
- `make LUA=texlua test`: PASS for the defined local gate.
- The plugin/theme regression now removes only the fixture tree it created; an externally supplied `CDIN_DIR` is not deleted.

## Not run / not claimed

- The suite has not yet been executed by a native Lua 5.4 binary in this environment. GitHub Actions is configured to use Lua 5.4; the remote CI result has not been observed here.
- `test_site_dir.lua` and `test_workflows.lua` were not run because no compatible `cdin-x` checkout was supplied.
- No SDL/native build is performed in this repository. Native Host/Backend code is intentionally excluded.
- No end-to-end Kernel test is claimed: the provisional `Runtime Host API` adapter is not wired into legacy `core.init()` yet. Integration must be run in the CDIN composition root against the real Kernel ABI 1.0.0.

## Important architectural status

This is an initial extraction scaffold, not a Runtime 1.0.0 release. The copied `data/core/doc/init.lua` still keeps its own line buffer and undo/redo stacks. That known violation of the target single-owner document rule is explicitly tracked in `docs/migration-status.md` and `MIGRATION-STATUS.json`; the module was not silently rewritten into a fake Kernel adapter.
