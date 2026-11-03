# Current state

CDIN Runtime is the Lua policy layer described by the [CDIN Specification](https://github.com/cdin-editor/spec). It owns commands, keymaps, logical views, configuration, extensions and the semantic UI model. It delegates document bytes and history to the Kernel through the Backend Host API.

## Available now

- Public Lua entry point, strict-global checks and explicit startup/shutdown lifecycle.
- Command and key-binding registries, including `document.new` for creating the first document/view through the Runtime policy layer.
- Host API `0.3.0` validation against Kernel ABI `1.1.x` and Frontend Protocol `0.2.0`.
- Bounded, version-pinned line-window reads through `DocumentClient:read_lines()` and `Runtime:read_view_lines()`; content remains Kernel-owned and is returned as transient byte strings.
- `Runtime:handle_frontend_event()` for owner-thread key, text, paste, mouse, resize, focus, position and command dispatch.
- Semantic UI snapshots with document version/length metadata, active theme styles and protocol-aligned view/panel bounds.
- Theme, style, syntax, workspace and extension registries.
- Logging through the Kernel's single logger via `host:log`; Runtime has no independent logger.
- Unit and simulated-Host integration tests, plus static boundary checks.

## Still needed

- Live Lua 5.4 + Backend + Kernel + Runtime integration results on the supported CI runner.
- A concrete out-of-process Frontend transport (Unix Domain Socket / Windows Named Pipe) and end-to-end GUI implementation.
- Compatibility tests for behavior and extensions carried over from the existing `cdin` application.
- A reviewed stable Host API and Runtime-facing extension contract before 1.0.

The Host API remains provisional. Runtime source compatibility is deliberately exact for Host API `0.x`; a Backend with a different minor version must not bypass this startup guard.
