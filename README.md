<p align="center">
  <a href="https://github.com/cdin-editor/cdin-editor.github.io/tree/main/public/cdin-icons" target="_blank" rel="noreferrer">
    <img src="https://raw.githubusercontent.com/cdin-editor/cdin-editor.github.io/main/public/cdin-icons/source/cdin-original-transparent-512.png" width="180" alt="CDIN logo" />
  </a>
</p>

<p align="center">
  <a href="https://github.com/cdin-editor/runtime/actions/workflows/ci.yml"><img src="https://github.com/cdin-editor/runtime/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <a href="https://github.com/cdin-editor/runtime/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0--or--later-blue.svg" alt="License: GPL-3.0"></a>
  <a href="https://www.lua.org/versions.html"><img src="https://img.shields.io/badge/Lua-5.4-blue.svg" alt="Lua 5.4"></a>
  <a href="https://github.com/cdin-editor/spec"><img src="https://img.shields.io/badge/CDIN-Specification-purple.svg" alt="CDIN specification"></a>
</p>

<h1 align="center">CDIN Runtime</h1>

<p align="center">The Lua layer that coordinates editor behavior in CDIN.</p>


CDIN Runtime contains the editor behavior: commands, key bindings, views, settings, workspace state and extensions. It is written in Lua and is designed to work with the other parts of CDIN rather than replace them.

## What is Runtime?

When a user presses a key or runs a command, Runtime decides what should happen next. It coordinates editor features and describes the logical UI state. It delegates document operations to the Host instead of keeping a second, independent copy of document text.

The parts of CDIN have separate responsibilities:

| Part | Responsibility |
| --- | --- |
| **Frontend** | Displays the editor and forwards user input. |
| **Runtime** | Coordinates commands, key bindings, views, settings and extensions. |
| **Backend** | Provides Runtime with access to Kernel and operating-system services. |
| **Kernel** | Owns document content, edits, versions and undo/redo history. |

The separation is intentional: Runtime does not draw the window, perform pixel-level layout, or directly own the document's permanent contents.

## Current status

This repository contains the reorganized Runtime implementation and tests that use a simulated Host. It is **not yet a complete, runnable CDIN editor**. The production Backend adapter, live Kernel connection and Frontend Protocol integration are not included, and the Host API and UI model are still under development.

The [CDIN specification](https://github.com/cdin-editor/spec) is the source of truth for cross-project contracts. This README describes the current state of this repository; it does not override the specification.

## Try it

You need **Lua 5.4** and **make**. Clone the repository and run the tests:

```sh
git clone https://github.com/cdin-editor/runtime.git
cd runtime
make check
```

Run one test group at a time when debugging:

```sh
make unit
make integration
```

The integration tests use a simulated Host. Passing them verifies Runtime behavior against that test interface; it does not prove that a real Kernel, Backend or Frontend is connected. The default interpreter is `lua5.4`. If your installation exposes Lua 5.4 as `lua`, run `make check LUA=lua`.

For a first-time walkthrough, see the [User Guide](docs/user-guide.md).

## A small example

Runtime is created with a Host. The real CDIN Backend will provide it; this example uses the test Host so you can explore the current API without a running editor.

```lua
-- Run from the repository root with Lua 5.4.
package.path = "lua/?.lua;lua/?/init.lua;tests/?.lua;tests/?/init.lua;" .. package.path

local Runtime = require("cdin.runtime")
local FakeHost = require("support.fake_host")

local runtime = Runtime.new({ host = FakeHost.new() })
runtime:start()

local document = runtime:open_document("Hello, CDIN\n", {
  path = "hello.txt",
})
local view = runtime:create_view(document.id)

local text, info = document:read(0, document.length)
assert(text == "Hello, CDIN\n")
assert(info.version == document.version)

runtime:pump_notifications()
runtime:shutdown()
```

This example creates an in-memory document. It does not open a real file or display a window, and `FakeHost` is test support—not part of a production build.

## What it provides

- Application startup and shutdown, shared errors and event notifications.
- Command registration and execution, input normalization and key bindings.
- Document clients and helpers that delegate document ownership to the Host/Kernel.
- Configuration, workspace state, views, selections and a logical pane tree.
- A semantic UI model, theme and style registries, and syntax highlighting.
- Extension registration, lifecycle management and a restricted extension sandbox.

## Documentation

| Guide | What it covers |
| --- | --- |
| [User Guide](docs/user-guide.md) | What Runtime does and how to run the current example. |
| [Architecture](docs/architecture/overview.md) | How Runtime fits into CDIN. |
| [Runtime Host API](docs/contracts/runtime-host-api.md) | Services that the Backend must provide. |
| [Extension API](docs/contracts/extension-api.md) | Registering and managing Runtime extensions. |
| [Runtime types](docs/contracts/runtime-types.md) | Shared data structures used by the API. |
| [Errors and lifecycle](docs/contracts/errors-and-lifecycle.md) | Error handling, startup and shutdown. |
| [Build and test](docs/development/build-and-test.md) | Local development and test commands. |
| [Changelog](CHANGELOG.md) | Changes recorded for each version. |

## CDIN ecosystem

Runtime is one part of CDIN. These repositories describe the neighboring projects:

| Project | Role |
| --- | --- |
| [CDIN](https://github.com/cdin-editor/cdin) | The editor application. |
| [Kernel](https://github.com/cdin-editor/kernel) | The document and text engine. |
| [Specification](https://github.com/cdin-editor/spec) | Shared contracts between CDIN components. |
| [cdin-x](https://github.com/cdin-editor/cdin-x) | Extensions and additional editor features. |

## Contributing

Bug reports and feature requests can be submitted through the YAML forms in [`.github/ISSUE_TEMPLATE/`](.github/ISSUE_TEMPLATE/). Before opening a pull request, read [CONTRIBUTING.md](CONTRIBUTING.md) and run the relevant tests. Please keep changes aligned with the [CDIN specification](https://github.com/cdin-editor/spec).

See also: [Code of Conduct](CODE_OF_CONDUCT.md) · [Security](SECURITY.md) · [Code owners](CODEOWNERS).

## License

CDIN Runtime is licensed under **GPL-3.0-or-later**. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
