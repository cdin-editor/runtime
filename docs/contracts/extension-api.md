# Extension API

**Contract version:** `1.0` (compatibility target; host-side legacy parity is incomplete)

Extensions run inside a dedicated Lua environment and receive the capabilities
explicitly exposed by the Runtime. The API preserves the basic module shape used
by CDIN extensions, while deliberately not recreating unrestricted globals.

## Entry point

An extension module returns a table with `init(core, config)` and optional
`unload()` functions:

```lua
return {
  init = function(core, config)
    core.commands:register("sample.hello", function()
      core:log("info", "hello from an extension")
      return true
    end, { description = "Example command" })
  end,
  unload = function()
    -- Release extension-owned Lua resources here.
  end,
}
```

`init` and `unload` are functions, not arbitrary values. An entry point must
return a table. Initialization failure rolls back registrations for that
extension and does not call its unload hook. Explicit unload invokes `unload`
once, then removes the extension's commands, keymap contributions and event
listeners, styles, themes and syntax contributions. Runtime shutdown drops
registrations without invoking extension unload hooks; this preserves the
stated current contract and avoids running arbitrary extension code while
the runtime is closing.

### Duplicate, unload and shutdown semantics

- Loading a name that is already active is idempotent: Runtime returns the
  existing active record without resolving the entry again or re-running
  `init`. There is no in-place hot reload; explicitly unload the extension
  before loading that name again.
- If `unload()` raises, Runtime still removes the extension's owned commands,
  keymaps, event listeners, styles, themes and syntax registrations and
  removes the active record before returning the structured error. A later
  load of the same name starts from a clean lifecycle state.
- Unloading an unknown name returns `false` and performs no work.
- Manager shutdown removes all active owner-scoped contributions and clears
  the active set without invoking extension `unload()` hooks. Shutdown is
  cleanup, not a sequence of user-visible explicit unload operations.

## Capability facade

The current manager exposes limited capabilities:

- `core.commands:register(name, handler, options)` and `remove(name)` for
  extension-owned commands. An extension cannot replace a command owned by
  another component.
- `core.keymap:bind(sequence, commands, options)` for extension-owned bindings.
  Extensions cannot request `overwrite`.
- `core.events:on(event_name, callback)` for event subscriptions owned by that
  extension.
- `core:log(level, message, fields?)` and `core:error(message, fields?)` write
  to the shared Kernel logger through Runtime (see Host API section 5). Levels
  are `error`, `warn`, `info`, `debug`, `trace` and `fatal`; an unknown level is
  recorded as a warning. Records are tagged with the component
  `cdin-runtime.extension.<name>`. The component cannot be overridden, fields
  must be flat strings, numbers or booleans, and extensions never touch a
  logger, `io` or the console directly.
- `core.unload_plugin(name)` for explicit unload.
- `core.ui:publish(model)` is currently a narrow provisional passthrough and is
  expected to be replaced by validated extension UI contributions before a
  stable release.

The full legacy `system`, `themes`, package path and UI extension API has not
been migrated. It must not be assumed available based on the old CDIN tree.

## Resolver-backed lifecycle

A Runtime embedded by a trusted application may be constructed with the optional
`module_resolver(plugin_name, module_name)` callback. Backend owns this callback
and its filesystem/catalog policy. Runtime never accepts a filesystem path and
never reads extension files itself.

For each extension, Backend resolves the entry module name `init` inside that
extension's namespace. Nested Lua `require("sub.module")` calls use the same
resolver and the same owning extension name. The resolver returns the exact Lua
source string and may return a virtual chunk name for diagnostics. It must
return `nil` for a module that does not exist. For access, I/O or limit
failures, it may raise a structured Runtime error in the `cdin.runtime` domain.
Runtime preserves that code when the resolver fails and through entry-module
execution, nested module loading and the extension `init` hook. Ordinary Lua
errors that are not recognized Runtime records remain `BAD_EXTENSION`.
Resolvers must not expose absolute host paths in chunk names or error messages.

Trusted embedders may use the following Runtime methods:

- `runtime:load_extension(name, config?, options?)` resolves and loads the
  extension entry point, then returns only `{ name, state, source }`.
- `runtime:unload_extension(name)` invokes the explicit unload hook and removes
  the extension's owned registrations.
- `runtime:list_extensions()` returns sorted metadata records; it does not
  expose module tables, sandbox environments or source bytes.

The extension name is a bounded namespace identifier, not a path. Nested
module names are bounded dotted identifiers; slash, backslash, traversal and
other path syntax are rejected before the resolver is called. Backend must
still canonicalize and confine the resolved file/catalog entry to the
requesting extension's root, reject symlink/reparse-point escape, bound source
bytes, and return only on the Lua owner thread. Runtime-side name validation is
defense in depth, not a substitute for Backend path confinement.

These methods are trusted embedding APIs, **not Frontend Protocol commands**.
A connected Driver must not gain the ability to load arbitrary local code by
sending `request.command`. An application that exposes extension management
to users must supply its own local administrative authorization boundary and
must not route it through an ordinary remote editing session.

When no resolver is supplied, resolver-backed loading fails closed with
`UNSUPPORTED`. Explicit-source loading via the manager remains available to
controlled embedding and deterministic tests; it must not be exposed to
untrusted clients. The Lua sandbox remains defense in depth, not process
isolation.

## Sandbox rules

- No ambient `io`, `os`, `debug`, `package`, `dofile`, native loader or unrestricted
  global environment is provided.
- Standard `math`, `string`, `table` and `utf8` libraries are read-only proxies.
- Global reads/writes that are not explicitly approved fail with a structured
  extension error.
- `require()` is disabled unless the Backend supplies a module resolver; nested
  names are dotted identifiers and resolution must remain inside the requesting
  extension namespace. Backend must prevent canonical path/reparse-point escape.
- Filesystem, process, clock and clipboard functionality is available only via
  separately documented capabilities when granted by Backend.

This sandbox is defense in depth, not an operating-system security boundary.
Untrusted or hostile extensions require process isolation outside this runtime.
