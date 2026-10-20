# Migration status and open items

This document distinguishes copied code from completed architectural migration.

## Complete in this scaffold

- [x] Copy all 48 Lua modules under `cdin/data/core/` while preserving relative paths and `require "core.*"` names.
- [x] Copy current CDIN docs, extension contract and the supplied Spec docs into read-only references.
- [x] Copy the public Kernel header and ABI documentation as references only.
- [x] Preserve inherited plain-Lua tests; add deterministic fixtures the snapshot's test scripts expect.
- [x] Add host-independent infrastructure for structured errors, a named registry and Host descriptor validation.
- [x] Add a source checksum manifest and structural tests.

## Known debt — do not interpret this scaffold as Spec conformance

- [ ] **Document ownership:** `data/core/doc/init.lua` stores `self.lines`, `undo_stack`, and `redo_stack`. It still owns canonical content/history and does not satisfy RT-003/RT-004. It is retained unmodified temporarily because views and commands currently depend on this API.
- [ ] **Host integration:** current core modules use legacy globals `system`, `renderer`, and `core`; `data/core/runtime/host.lua` is a provisional adapter and is not wired into `core.init()` yet.
- [ ] **File I/O:** current Doc `load`/`save` paths call `io.open`. These must move behind Backend services before a headless/multi-frontend boundary is claimed.
- [ ] **View/frontend ownership:** `views/` and `rootview/` contain logical state and direct rendering calls. Split UI model from renderer commands in a compatibility-preserving phase.
- [ ] **Text ownership:** `text/bidi.lua` and `text/shaper.lua` are copied for traceability, but the target assigns bidi/shaping to Frontend. Confirm all callers before moving them.
- [ ] **Kernel notifications/versioning:** replace local content edits with Host API operations; consume Kernel version and notification semantics with deterministic unsubscribe/close lifecycle.
- [ ] **Headless integration:** add tests proving the same Runtime can run without SDL and without a GUI-specific `renderer` table.
- [ ] **Build integration:** pin a Runtime revision from the CDIN composition root only after Host API tests pass.
- [ ] **Platform validation:** run Lua tests in CI on Windows, Linux and macOS, and validate with the actual Lua 5.4 version supported by CDIN.

## Safe migration sequence

1. Freeze provisional Host API descriptors and error mapping in docs/tests.
2. Implement the API on the CDIN Backend backed by Kernel ABI 1.0.0; test ABI major on startup.
3. Implement a new `doc/client.lua` that only retains opaque handles, versions and view metadata.
4. Migrate one command/view vertical slice (read → insert → notification → redraw), then expand.
5. Move file operations to `host.fs`; separate UI model from frontend rendering commands.
6. Add headless integration CI, then switch core boot to the Host adapter.
7. Remove legacy document implementation only after all call sites and extension compatibility tests pass.

## Release gate

Do not declare Runtime `1.0.0` until no Lua module owns canonical document bytes/history, core startup validates a versioned Host API, and the Kernel-backed create/edit/notify/read integration test passes.
