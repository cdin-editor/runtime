# User Guide

This guide is for anyone who has just heard about CDIN and wants to understand
what the Runtime is for, what it does, and how to work with it.

You do not need to know the CDIN architecture before starting here.

## 1. What is the Runtime?

The Runtime is the part of CDIN that decides how the editor behaves.

When you press a key, the Runtime finds the matching command. When that command
needs to change a document, the Runtime asks the Backend to do it. The Runtime
then updates its view of the editor and sends the new UI state back through the
Backend so a Frontend can display it.

The Runtime is not the whole editor. It is one part of a larger system.

## 2. How the parts work together

```text
You press a key
      |
      v
Frontend receives the key
      |
      v
Runtime chooses a command
      |
      v
Backend carries out the document request
      |
      v
Kernel updates the document
      |
      v
Runtime publishes the new editor state
      |
      v
Frontend displays the update
```

Each part has one main job:

| Part | What it does |
| --- | --- |
| Frontend | Shows text and controls, and reports user input. |
| Runtime | Runs commands and key bindings; manages views, settings and extensions. |
| Backend | Connects the Runtime to the Kernel and operating-system services. |
| Kernel | Owns document text, edit history, versions and text operations. |

Keeping these jobs separate makes the Runtime easier to test and allows CDIN to
support different frontends without putting window or terminal code into the
editing logic.

## 3. What the Runtime does

The Runtime is responsible for editor behavior shared by frontends:

- **Commands and key bindings.** It maps input to editor actions.
- **Views and selections.** It tracks which view is active, where the cursor is,
  and what text is selected. The Kernel does not own cursor or view state.
- **Settings and project context.** It keeps validated editor settings and
  lightweight information about the current project.
- **Themes and syntax rules.** It stores style roles and syntax definitions;
  the Frontend decides how to draw them.
- **Extensions.** It provides a restricted environment for extension code and
  tracks the commands and key bindings an extension adds.
- **UI state.** It describes what views, panels, prompts and status information
  exist. It does not choose pixel positions, wrap lines or draw text.

## 4. What the Runtime does not do

The Runtime does not keep its own permanent copy of the document text or its
undo history. The Kernel is the source of truth for both. The Runtime asks the
Backend for document operations and keeps only handles, versions, view state and
small pieces of metadata.

The Runtime also does not create windows, render text, access the filesystem
through direct operating-system calls, or implement the Frontend Protocol
transport. Those jobs belong to the Frontend or Backend.

## 5. Can I run it as an editor today?

Not by itself. The Runtime needs a Backend that implements its Host API. The
production adapter connecting this Runtime to the real Kernel and Frontend
Protocol is not included yet.

For that reason, the current practical entry point is the test environment. It
uses a simulated Host to exercise Runtime behavior without pretending that the
real Kernel or GUI is already connected.

## 6. Run the tests

Install Lua 5.4 and `make`, then run these commands from the repository root:

```sh
make test
```

To run the complete local check target, use:

```sh
make check
```

If Lua 5.4 is installed under a different command name, pass it to `make`:

```sh
make check LUA=lua
```

Use that last command only when `lua` points to Lua 5.4. Running tests with a
different interpreter can catch many ordinary bugs, but the target runtime is
Lua 5.4.

## 7. Follow a document through the Runtime

The public Lua entry point is `require("cdin.runtime")`. A Backend creates the
Host object and passes it into the Runtime. The Host object is the bridge to
services such as document operations, UI publication and logging.

The example below uses the test-only Host. It shows the Runtime lifecycle and
how a document and view are created; it does not connect to a real file or GUI.

```lua
-- Run from the repository root. The extra paths make the test Host importable.
package.path = "lua/?.lua;lua/?/init.lua;tests/?.lua;tests/?/init.lua;" .. package.path

local Runtime = require("cdin.runtime")
local FakeHost = require("support.fake_host")

local host = FakeHost.new()
local runtime = Runtime.new({ host = host })
runtime:start()

local document = runtime:open_document("Hello, CDIN\n", {
  path = "hello.txt",
})
local view = runtime:create_view(document.id)

local bytes, info = document:read(0, document.length)
assert(bytes == "Hello, CDIN\n")
assert(info.version == document.version)

-- The real Backend will call this on the Lua owner thread when it is time
-- to process document notifications.
runtime:pump_notifications()
runtime:shutdown()
```

The module search path in the example is for this repository's test fixture.
Do not ship `tests/support/fake_host.lua` in a production build.

## 8. Main Runtime operations

The current development API exposes these entry points:

| Call | Purpose |
| --- | --- |
| `Runtime.new({ host = host })` | Create a Runtime instance with an injected Host. |
| `runtime:start()` | Check the Host and register built-in behavior. |
| `runtime:open_document(bytes, options)` | Ask the Host to create a document and return a lightweight client. |
| `runtime:create_view(document_id, options)` | Create a view with its own selection and focus state. |
| `runtime:handle_key(event)` | Turn a raw key event into a command. |
| `runtime:pump_notifications()` | Process Kernel change notifications on the Lua owner thread. |
| `runtime:save_document(id, path, options)` | Save through the Host's optional atomic-write service. |
| `runtime:close_document(id)` | Close a document and detach its views. |
| `runtime:shutdown()` | Stop the Runtime and release its owned resources. |

The Host API is still provisional, and the production adapter is not included.
These calls describe the current implementation, not a promise that its API is
already stable for third-party applications.

## 9. Add a command while developing

Assume you have started a Runtime as in the previous example. Commands are
registered by name. Owners make cleanup predictable: a feature can remove the
commands and key bindings it registered without removing another feature's entries.

```lua
runtime.commands:register("example.hello", function()
  runtime.host:log("info", "Hello from a Runtime command", {
    source = "example.hello",
  })
  return true
end, {
  owner = "example",
  description = "Example command",
})

runtime.keymap:bind("ctrl+alt+h", "example.hello", {
  owner = "example",
})
```

This is an internal development example, not yet a stable third-party API.
The final extension-facing API is described in the [Extension API](contracts/extension-api.md).

## 10. Where to go next

- [Module boundaries](architecture/module-boundaries.md) — which part owns each responsibility.
- [Runtime Host API](contracts/runtime-host-api.md) — the provisional interface provided by the Backend.
- [Extension API](contracts/extension-api.md) — how extensions are loaded and restricted.
- [Build and test](development/build-and-test.md) — tests and local development.
