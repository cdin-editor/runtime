# Integration tests

- `lua ./scripts/test_commands.lua`: existing command/keymap/extension-contract regression against the copied Runtime Lua core and deterministic stub host.
- `lua ./scripts/test_lua.lua`: plugin/theme loading tests with local fixtures under `scripts/fixtures/`; no network or cdin-x checkout required.
- `CDINX_DIR=/path/to/cdin-x lua ./scripts/test_site_dir.lua`: checks the site path shared by CDIN and cdin-x.
- `CDINX_DIR=/path/to/cdin-x lua ./scripts/test_workflows.lua`: validates workflow commands and ownership after the cdin-x split.

These are inherited CDIN tests. They exercise compatibility with the old host model; they do **not** prove Kernel-backed document behavior. Future Host integration tests belong in the CDIN composition-root CI and must load the actual Kernel library.
