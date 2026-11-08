# Changelog

## [Unreleased]

### Runtime RC2 Registry integration candidate

- Add a separate immutable Release Metadata candidate
  `runtime-1.0.0-rc.2.json` that provides
  `org.cdin.runtime-extension-contract` version `1.0.0`, as defined by the
  merged Spec decision in PR #27.
- Update the tracked Registry/archive fallback module to report
  `1.0.0-rc.2`. Preserve the original RC1 metadata document, digest and
  source pin; the Catalog and CDIN Manifest still need the coordinated RC2
  update before this candidate is selected.
- This is an integration candidate, not a formal `v1.0.0-rc.2` tag or
  GitHub Release. Live product-version verification remains an exit gate.


### Release metadata and verification

- Confirm the Registry source snapshot for package `1.0.0-rc.1` is 41 commits
  beyond the original release tag but retains the embedded RC1 package version.
  The exact CDIN manifest/runtime version check and tagged source-archive
  verification passed (see [docs/status.md](docs/status.md)).
- Resolve the RT-012 Extension Contract identity in Spec: the provider ID is
  `org.cdin.runtime-extension-contract`, and API label `1.0` maps to Registry
  SemVer `1.0.0`. The published RC1 metadata remains immutable and does not
  yet declare that provider; the declaration belongs in a new candidate
  metadata identity, not an in-place RC1 edit.

### Added

- Resolver-backed extension loading through the trusted Runtime embedding API:
  `load_extension`, `unload_extension` and `list_extensions`.
- Entry modules are resolved as `init` within the extension namespace; nested
  `require` accepts bounded dotted module identifiers only.
- Resolver-backed lifecycle tests cover module loading, owner scoping, unload
  cleanup, unavailable resolver failure and path-traversal rejection.

### Security

- Align the README and Registry integration guide with package candidate `1.0.0-rc.1` and the frozen Host API `1.0.0`; explicitly track the missing RT-012 Extension Contract provider declaration without inventing a Registry contract identity.

- Extension lifecycle methods are not exposed as Frontend Protocol commands.
  Loading remains disabled when no approved Backend resolver is supplied.
- Runtime rejects path-like extension and nested module names before they reach
  the Backend resolver. Backend must still enforce canonical path confinement,
  symlink/reparse-point protection and source-size limits.

## [1.0.0-rc.1] - 2026-11-04

### Added

- Frozen Runtime Host API `1.0.0` contract with stable same-major /
  additive-minor compatibility policy.
- Host API compatibility tests: 1.1 is accepted by a 1.0 consumer; 0.x and
  2.x are rejected.

### Changed

- Runtime and FakeHost now require/advertise Host API `1.0.0`.
- Runtime no longer treats Host API as a provisional 0.x exact-match contract.

### Verification

- Lua unit and simulated-Host verification results are recorded in the
  release gate report.
- Backend build and test results are recorded separately.

### Release status

- This is a release candidate, not a stable Runtime release.
- Stable Runtime `1.0.0` remains gated on live Backend, Lua 5.4 and Kernel
  lifecycle/error-mapping integration, together with the outstanding
  extension and migration conformance requirements.

## [0.4.1] — 2026-11-04

### Fixed

- Release/test helper scripts invoke the Lua detector through `bash`, so source
  archives remain usable when executable mode bits are not preserved.
- Frontend Protocol negotiation now follows the accepted Protocol 1.x
  compatibility rule: the same major version and a provided minor version at
  least as new as the Runtime requirement. Protocol 0.x and 2.x remain rejected.
  This corrects the stale exact-match guard left behind during the 1.0.0 wire
  alignment; the provisional Runtime Host API 0.3.0 still requires an exact
  major/minor match.

### Verification

- Lua 5.4 unit tests: 137 assertions passed.
- Lua 5.4 simulated-Host integration tests: 131 assertions passed.
- `scripts/ci-check.sh`: passed.
- Source TAR and ZIP package tests: passed; archive checksums verified.

### Specification references

- [ADR-0018 — Frontend Protocol wire format](https://github.com/cdin-editor/spec/blob/main/docs/adr/ADR-0018-frontend-protocol-wire.md)
- [Protocol version evolution](https://github.com/cdin-editor/spec/blob/main/docs/architecture/protocol-wire.md#version-evolution)

This file records user-visible changes to CDIN Runtime. Runtime versions are
read from Git tags: a release tag such as `v0.2.0` corresponds to the `0.2.0`
entry below. Release archives receive generated version metadata and do not need
a separate `VERSION` file.

## [0.4.0] — 2026-11-04

### Added

- Backend Host API `0.3.0` integration: bounded, version-pinned document line
  windows through `documents.read_lines` and owner-thread Frontend event handling.
- UI snapshots now carry bounded view/panel state, document version/length,
  active theme and style data required by Backend Protocol projection.
- FakeHost and integration coverage for line endings, raw bytes, stale versions,
  paste/key/command events, resize/focus/mouse input and scroll-anchor clamping.

### Changed

- Frontend Protocol descriptor is now `1.0.0`, matching the stable shared wire
  contract implemented by Backend and Frontend. Runtime rejects provisional
  Protocol `0.2.x`; no silent downgrade or fallback is performed.
- Runtime Host API is `0.3.0`. It remains a provisional internal Backend boundary;
  this does not declare the entire Runtime product production-ready.
- Startup compatibility diagnostics distinguish the provisional Host API from
  the stable Frontend Protocol contract.

### Verification

- Lua 5.4 unit tests: 137 assertions passed.
- Lua 5.4 simulated-Host integration tests: 128 assertions passed.
- Static boundary checks passed.
- Live Backend + installed Kernel integration remains pending until the pinned
  `cdin-kernel` package and Lua development dependencies are available.

## [0.3.0] — 2026-11-02

### Added

- Kernel-backed logging. Runtime now sends every record through
  `host:log(level, message, fields)` and the Backend forwards it to the one
  logger the Kernel owns (`cdin_kernel_log`, Kernel ABI 1.1.0). Runtime does not
  bind `m-mdy-m/log.c`, load native code, or write to stdout/stderr.
- `cdin.runtime.core.log`: a bounded, never-raising logger facade with the six
  Kernel levels (`error`, `warn`, `info`, `debug`, `trace`, `fatal`),
  sub-components (`cdin-runtime.documents`, `cdin-runtime.extension.<name>`),
  UTF-8-safe message truncation, scalar-only fields, and drop/failure counters
  (`runtime:log_stats()`).
- Lifecycle records for startup, shutdown, documents, saves and extensions.
  Records carry ids, versions and sizes; document content and file paths are
  never logged.
- Host API `info.logging` descriptor (`provider`, `levels`, `max_message_bytes`).
- Pipeline, PSX and gix tooling: `pipeline.toml` (tasks `deps`, `unit`,
  `integration`, `boundary`, `check`, `package`), `psx.yml`, `.gix/config.default`
  with `scripts/init-git-flow.sh`, and `scripts/check-boundaries.sh`, a static
  guard against console output, native code and a second logger.
- Release archives are verified after build (`scripts/test-package.sh`).

### Changed

- **Breaking (provisional contract):** Host API is now 0.2.0 and requires Kernel
  ABI 1.1.0 or newer. A Host that reports ABI 1.0.x, omits `info.logging`, or
  names a logger provider other than `cdin-kernel` is rejected with
  `HOST_API_MISMATCH`.
- Extension `core:log` and `core:error` now log under the extension's own
  component. The `component` field is owned by the logger and cannot be set by
  callers; unknown levels are recorded as warnings.
- `.github/workflows/ci.yml` and `release.yml` now call the shared
  `m-mdy-m/pipeline` workflows.

### Removed

- `lua/cdin/runtime/core/release_metadata.lua` was committed by mistake with a
  stale version. It is generated during release packaging and is now ignored.

## [0.2.0] — 2026-10-26

### Added

- Versioned selection snapshots that preserve each view's logical scroll
  anchor while continuing to decode the earlier `CDINSEL1` format.
- Owner-scoped cleanup for extension-defined style roles, themes, and syntax
  definitions when an extension is unloaded or fails to initialize.
- Extension-facing presentation capabilities for registering styles, themes,
  and syntax definitions through the Runtime's restricted capability facade.
- Integration tests that verify extension presentation resources are removed
  after unload, and unit tests for selection snapshot compatibility and scroll
  restoration.

### Changed

- View edits now transform the logical scroll anchor together with the
  selection, keeping the view attached to the intended document position.
- Documentation clarifies that opaque selection snapshots contain view metadata
  only; canonical document content and undo/redo history remain Kernel-owned.
- Release version discovery remains Git-tag based in source checkouts, while the
  tagged release workflow embeds the exact version into source archives.

### Verification

- Unit tests passed: 79 assertions.
- Simulated-Host integration tests passed: 72 assertions.
- The tests do not prove integration with the production Backend, live Kernel,
  or Frontend Protocol transport.

### Known limitations

- The production Backend-owned Host adapter and live Kernel integration are not
  included.
- Frontend Protocol transport and end-to-end UI integration are not included.
- Compatibility with all legacy CDIN commands, UI behavior, and extensions has
  not yet been demonstrated.

## [0.1.0] — 2026-10-26

### Added

- Introduced the Lua Runtime as a distinct CDIN component, with
  `require("cdin.runtime")` as its public entry point.
- Added application startup and shutdown lifecycle handling, a Host contract,
  shared error helpers, an event bus, and strict-global checks.
- Added command registration and default commands.
- Added document clients and management for opening and coordinating documents,
  with transaction, snapshot, and save helpers that delegate document ownership
  to the Kernel.
- Added input strokes and keymap registration, including cleanup of registrations
  owned by an extension.
- Added a semantic UI model, views, selections, and a logical pane tree.
- Added configuration defaults and a settings store with validation and safe
  loading/saving behavior.
- Added workspace project state.
- Added registries for themes, styles, and syntax definitions, plus a syntax
  highlighter and plain-text fallback.
- Added extension registration, lifecycle management, and a restricted extension
  sandbox.
- Added unit tests and integration tests that exercise the Runtime through a
  simulated Host.
- Added user-facing and developer documentation: a first-time User Guide, a
  simple architecture overview, build/test instructions, Runtime Host API,
  Extension API, shared types, and lifecycle/error contracts.
- Added GitHub Actions workflows for CI and tagged releases, including test
  execution, source archives, and SHA-256 checksums.
- Added YAML forms for bug reports and feature requests, a pull request template,
  `CODEOWNERS`, contribution guidance, security reporting guidance, and a Code
  of Conduct.

### Changed

- Reorganized the Runtime around clear responsibilities instead of carrying
  forward the old `data/core/` layout.
- Kept document text, document versions, snapshots, and undo/redo history as
  Kernel responsibilities; Runtime coordinates operations through the Host API
  rather than maintaining a competing source of truth.
- Made the pane tree represent logical relationships between views instead of
  pixel-level layout, which belongs to the Frontend.
- Improved module boundaries, validation, error paths, cleanup, and readability
  across document handling, settings, keymaps, commands, views, and extensions.
- Prevented invalid save chunk sizes from causing a non-progressing save loop.
- Kept settings loading from replacing active configuration with invalid data.
- Simplified the README and documentation navigation so newcomers can first learn
  what Runtime does before reading API details.
- Made `version.lua` derive the Runtime version from Git tags in source checkouts.
  Release packaging generates metadata for archives that do not contain `.git`.

### Removed

- Removed the standalone `VERSION` file so the version is not maintained in two
  places.
- Removed the copied legacy `data/core/` tree and obsolete scripts/reports from
  the Runtime package.
- Removed unnecessary internal planning documents and complex architecture
  diagrams in favor of concise, task-focused documentation.

### Verification

- Unit tests pass: 74 assertions.
- Simulated-Host integration tests pass: 66 assertions.
- Lua syntax checks and the User Guide example were verified during development.

### Known limitations

- The production Backend adapter, live Kernel connection, and Frontend Protocol
  transport are not included yet, so this is not a complete runnable editor.
- The Runtime Host API and semantic UI model remain provisional and may change
  as the cross-project CDIN specification is implemented.
- The test suite uses a simulated Host; passing it does not yet prove integration
  with the real Kernel or Frontend.

[0.1.0]: https://github.com/cdin-editor/cdin/releases/tag/v0.1.0
