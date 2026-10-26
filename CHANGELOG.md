# Changelog

This file records user-visible changes to CDIN Runtime. Runtime versions are
read from Git tags: a release tag such as `v0.2.0` corresponds to the `0.2.0`
entry below. Release archives receive generated version metadata and do not need
a separate `VERSION` file.

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
