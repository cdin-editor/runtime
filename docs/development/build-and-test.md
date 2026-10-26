# Build and test

## Requirements

- Lua 5.4 for the supported Runtime version.
- `make` to run the test targets.

Run the commands from the repository root. The test files set their Lua module
paths themselves.

## Commands

```sh
make unit         # tests for individual modules
make integration  # Runtime behavior using a simulated Host
make test         # unit and integration tests
make check        # the full local test target
```

If your Lua 5.4 executable is named differently, pass the name to `make`:

```sh
make check LUA=lua
```

Only use this when `lua` is Lua 5.4. Tests on another version are a useful smoke
test but do not prove the supported runtime behaves correctly.

## Try the Runtime

Start with the [User Guide](../user-guide.md). Its example uses
`tests/support/fake_host.lua`, which simulates the services expected from the
Backend. It is intended for tests and learning, not for a production CDIN build.

The public module is `require("cdin.runtime")`. It installs strict-global
checking before loading the application. Product boot code must not import the
internal module `cdin.runtime.application` directly.

## What the tests cover

- `tests/unit/run.lua` checks module behavior such as commands, key bindings,
  configuration, project context, views, syntax rules, extension sandboxing and
  structured errors.
- `tests/integration/run.lua` checks how modules work together with the fake
  Host, including document edits, undo/redo, snapshots, transactions,
  notifications, saving, extension cleanup and shutdown.

## What the tests do not prove

The fake Host is not the real Kernel adapter. Passing local tests does not prove
native handle ownership, Kernel ABI conformance, thread handoff, real file I/O,
or Frontend Protocol integration. The Runtime must not be treated as integrated
into CDIN until those checks are run against the production components.
