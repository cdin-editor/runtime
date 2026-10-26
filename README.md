# CDIN Runtime

CDIN Runtime is the Lua part of CDIN that controls editor behavior. It handles
commands, key bindings, views, settings and extensions. It asks the Backend to
perform document operations instead of storing the document itself.

## How it fits into CDIN

| Part | Main job |
| --- | --- |
| Frontend | Shows the editor and receives user input. |
| Runtime | Decides what editor actions mean and describes the current UI state. |
| Backend | Connects the Runtime with the Kernel and operating-system services. |
| Kernel | Owns document text, edits, versions and undo/redo history. |

The Runtime is not a standalone editor. It does not create a window, draw text,
or access the operating system directly.

## Current state

This repository contains the reorganized Lua Runtime and tests that use a
simulated Host. It cannot run as a complete editor yet: the production Backend
adapter, live Kernel connection and Frontend Protocol integration are not
included. The Host API and UI model are still provisional.

The [CDIN Specification](https://github.com/cdin-editor/spec) defines the
cross-project design and takes priority over this repository's implementation.

## Try the tests

Install Lua 5.4 and `make`, then run from the repository root:

```sh
make check
```

You can also run one test group at a time:

```sh
make unit
make integration
```

The integration tests use a simulated Host. Passing them does not prove that
the real Kernel or Frontend is connected.

## Start here

- [User Guide](docs/user-guide.md) — an introduction and a small example.
- [Architecture](docs/architecture/overview.md) — a simple explanation of how the parts fit together.
- [Runtime Host API](docs/contracts/runtime-host-api.md) — what the Backend must provide.
- [Extension API](docs/contracts/extension-api.md) — how Runtime extensions work.
- [Build and test](docs/development/build-and-test.md) — local test commands.

## Source layout

- `lua/cdin/runtime/` — Runtime implementation.
- `tests/` — unit tests and tests using a simulated Host.
- `docs/` — user guide and developer reference.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
