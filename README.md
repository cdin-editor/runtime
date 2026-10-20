# cdin-runtime (bootstrap extraction)

This repository is the **initial modular extraction** of CDIN's Lua runtime. The copied application modules preserve their current `require "core.*"` identities and are kept under `data/core/` to minimize migration churn.

> **Status: experimental / migration scaffold — not yet a standalone editor.** The existing modules still consume the original CDIN host globals (`system`, `renderer`, and `core`) and are not all migrated to the proposed versioned Runtime Host API. In particular, `data/core/doc/init.lua` is intentionally copied unchanged and still owns an in-memory line buffer and undo/redo stacks. That is tracked migration debt, not a claim of Spec 1.0.0 conformance.

## Scope

- Runtime-owned Lua application code: commands, keymaps, config, project state, plugin loader, syntax/highlighting and UI model.
- Copied CDIN architecture/user documentation and a reference snapshot of the Spec and Kernel ABI.
- Provisional, dependency-injected building blocks for Host API validation, stable error records and named registries.
- Plain-Lua unit tests, inherited CDIN integration tests, deterministic plugin/theme fixtures and Python structural checks.

## Explicitly out of scope

The C host, SDL renderer, OS/file-system implementation, Lua C binding, build/install/package system and Kernel implementation remain in their respective repositories. The Kernel header under `references/kernel/` is for documentation and code review only; do not compile the Runtime against that copy. Integration builds must use the canonical `cdin-kernel` repository's public header and library through the CDIN Backend.

## Layout

```text
data/core/                   Lua runtime (`core.*` import paths preserved)
  runtime/                   strict mode + modular migration utilities
  commands/ input/ views/    current runtime feature modules
scripts/                     inherited CDIN test support and fixtures
 tests/unit/                  host-independent Lua unit tests
 tests/integration/           integration-test instructions/contracts
docs/                         current CDIN docs and extraction decisions
references/spec/              read-only Spec snapshot for traceability
references/kernel/             read-only ABI/header snapshot for reference
```

## Requirements

- Lua 5.4 for Lua tests; no third-party Lua testing framework is required.
- Python 3.10+ for static checks and source-manifest verification.

## Checks

```sh
python3 scripts/check_structure.py
lua tests/unit/run.lua
lua ./scripts/test_commands.lua
lua ./scripts/test_lua.lua
```

`make test` runs all host-independent and inherited Lua tests. `make test-site-dir` and `make test-workflows` require a compatible `cdin-x` checkout via `CDINX_DIR`. `make lint` runs `luacheck` when installed.

## Architecture references

- [Architecture and boundaries](docs/architecture.md)
- [Source map](docs/source-map.md)
- [Migration status and open items](docs/migration-status.md)
- [Runtime Host API draft](docs/runtime-host-api.md)
- [Types and ownership](docs/types-and-ownership.md)
- [Test strategy](docs/testing.md)
- [Source provenance manifest](docs/source-manifest.md)
- [Spec Runtime contract](references/spec/docs/components/runtime.md)
- [Spec migration plan](references/spec/docs/architecture/migration.md)
- [Kernel ABI reference](references/kernel/docs/abi.md)
