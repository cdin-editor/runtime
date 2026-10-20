# Test strategy

## Layers

1. **Unit** (`tests/unit/run.lua`): no SDL, no native binding, no filesystem mutation; tests contracts, registry, error mapping and Host validation with injected tables.
2. **Structure** (`python3 scripts/check_structure.py`): source provenance hashes, module import closure, required docs, no accidental C/build/kernel implementation in Runtime, and no build artifacts.
3. **Legacy Lua regression** (`scripts/test_commands.lua`, `scripts/test_lua.lua`): exercise the copied command/keymap and plugin/theme implementations against the small deterministic fixture tree.
4. **CDIN-X integration** (`scripts/test_site_dir.lua`, `scripts/test_workflows.lua`): optional until `CDINX_DIR` points to a compatible cdin-x checkout.
5. **Future Host/Kernel integration**: run in CDIN composition-root CI, with the real Kernel ABI 1.0.0; Runtime-only CI must never replace these with mocks and claim end-to-end conformance.

## Rules for new modules

- Prefer plain Lua tables and injected service parameters; don't require `core.init` in pure infrastructure.
- Test success, invalid input, duplicate registration, absent capabilities, incompatible version and host failure paths.
- Never depend on global `system`, `renderer`, or `core` in pure utility modules.
- Avoid test order dependency and fresh-process pollution from `package.loaded` for tests that initialize the legacy core.
- Keep tests deterministic; no network or live user config.
