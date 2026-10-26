# User Guide

CDIN is an editor project. The Runtime is one part of it: the Lua code that
controls editor behavior. This guide explains what it does and how to try the
current code, even if you have never worked on CDIN before.

## What does Runtime do?

When someone presses a key, Runtime works out which editor command should run.
It keeps track of views, selections, settings and extensions. When a command
needs to read or change a document, Runtime asks the Backend to do that work.

The other parts have their own jobs:

- **Frontend:** shows the editor and receives keyboard or mouse input.
- **Runtime:** decides how the editor should respond.
- **Backend:** connects Runtime to the Kernel and operating-system services.
- **Kernel:** owns document text, changes, versions and undo/redo history.

Runtime does not draw the screen, manage files through direct operating-system
calls, or keep a second permanent copy of a document.

## Can I use it as an editor now?

Not yet. The Runtime code can be built and tested, but this repository does not
yet include the production Backend adapter, a live Kernel connection or the
Frontend Protocol connection needed for a complete CDIN editor.

You can still run the tests and try the example below. It uses a simulated Host
that stands in for the services a real Backend will provide.

## Run the tests

Install Lua 5.4 and `make`. From the repository root, run:

```sh
make check
```

To run just one group:

```sh
make unit
make integration
```

The integration tests use a simulated Host, so they test Runtime behavior but
not the real Kernel adapter or a running editor.

## Try a small example

The public entry point is `require("cdin.runtime")`. A Host is passed in when
Runtime is created. The real CDIN Backend will provide this Host; this example
uses the test version instead.

```lua
-- Run from the repository root.
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

This example creates an in-memory test document. It does not open a real file or
show a window. Do not include `tests/support/fake_host.lua` in a production
build.

## Where to go next

- Read [Architecture](architecture/overview.md) for the responsibilities of each part.
- Read the [Runtime Host API](contracts/runtime-host-api.md) if you are implementing the Backend.
- Read the [Extension API](contracts/extension-api.md) if you are experimenting with extensions.
- Read [Build and test](development/build-and-test.md) for the available test commands.

The interfaces in this repository are still under development and may change.
