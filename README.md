# CDIN Runtime

CDIN Runtime is the Lua component that controls editor behavior in CDIN. It
handles commands, key bindings, views, settings, workspace state and extensions.
When a command needs to read or change a document, Runtime asks the Backend to
perform the operation instead of keeping its own copy of the document.

CDIN is made of several parts:

- **Frontend** shows the editor and receives keyboard or mouse input.
- **Runtime** decides how the editor should respond and describes UI state.
- **Backend** connects Runtime to the Kernel and operating-system services.
- **Kernel** owns document text, edits, versions and undo/redo history.

Runtime is not a standalone editor. It does not create a window, draw the UI,
or access operating-system services directly.

## Current status

This repository contains the reorganized Lua Runtime and tests that use a
simulated Host. It is not yet a complete, runnable CDIN editor: the production
Backend adapter, live Kernel connection and Frontend Protocol integration are
not included. The Host API and UI model are still provisional and may change.

The [CDIN specification](https://github.com/cdin-editor/spec) defines the
cross-project architecture and takes priority over implementation details in
this repository.

## Get started

You need Lua 5.4 and `make` to run the standard local test commands. From the
repository root, run:

```sh
make check
```

To run only one test group:

```sh
make unit
make integration
```

The default Makefile interpreter is `lua5.4`. If your Lua 5.4 executable is
named `lua`, pass it explicitly:

```sh
make check LUA=lua
```

The integration tests use a simulated Host. Passing them checks Runtime behavior
against that test interface; it does not prove that the real Kernel, Backend or
Frontend is connected.

If this is your first time with CDIN, start with the [User Guide](docs/user-guide.md).

## Main responsibilities

Runtime currently provides:

- application startup, shutdown and component wiring;
- command registration and execution;
- input normalization and key bindings;
- document clients that delegate document ownership to the Host/Kernel;
- configuration and workspace state;
- logical views, selections, a pane tree and a semantic UI model;
- theme, style and syntax registries;
- extension lifecycle management and a restricted extension sandbox;
- common errors, events and lifecycle contracts.

Runtime does not own the permanent source of truth for document text or undo
history. Those responsibilities remain with the Kernel; drawing and pixel-level
layout remain with the Frontend.

## Documentation

- [User Guide](docs/user-guide.md) — what Runtime does and how to run its example.
- [Architecture overview](docs/architecture/overview.md) — how CDIN's parts fit together.
- [Runtime Host API](docs/contracts/runtime-host-api.md) — services the Backend must provide.
- [Extension API](docs/contracts/extension-api.md) — how Runtime extensions are registered and managed.
- [Runtime types](docs/contracts/runtime-types.md) — shared data shapes used by the API.
- [Errors and lifecycle](docs/contracts/errors-and-lifecycle.md) — error handling and startup/shutdown behavior.
- [Build and test](docs/development/build-and-test.md) — local development and test commands.

## Contributing

Bug reports and feature requests can be opened through the YAML forms in
`.github/ISSUE_TEMPLATE/`. Before sending a change, read
[CONTRIBUTING.md](CONTRIBUTING.md), run the relevant tests, and open a pull
request using the repository's pull request template.

The repository also includes:

- `CODE_OF_CONDUCT.md` — expectations for project participation;
- `SECURITY.md` — how to report security issues privately;
- `CODEOWNERS` — default code review ownership;
- `.github/workflows/ci.yml` — automated test runs for supported CI platforms;
- `.github/workflows/release.yml` — validation and source-package creation for tagged releases.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
