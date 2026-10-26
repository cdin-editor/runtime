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
      core.log("info", "hello from an extension")
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
listeners. Runtime shutdown drops registrations without invoking extension
unload hooks; this preserves the stated current contract and avoids running
arbitrary extension code while the runtime is closing.

## Capability facade

The current manager exposes limited capabilities:

- `core.commands:register(name, handler, options)` and `remove(name)` for
  extension-owned commands. An extension cannot replace a command owned by
  another component.
- `core.keymap:bind(sequence, commands, options)` for extension-owned bindings.
  Extensions cannot request `overwrite`.
- `core.events:on(event_name, callback)` for event subscriptions owned by that
  extension.
- `core.log(level, message, fields?)` and `core.error(message, fields?)`.
- `core.unload_plugin(name)` for explicit unload.
- `core.ui:publish(model)` is currently a narrow provisional passthrough and is
  expected to be replaced by validated extension UI contributions before a
  stable release.

The full legacy `system`, `themes`, package path and UI extension API has not
been migrated. It must not be assumed available based on the old CDIN tree.

## Sandbox rules

- No ambient `io`, `os`, `debug`, `package`, `dofile`, native loader or unrestricted
  global environment is provided.
- Standard `math`, `string`, `table` and `utf8` libraries are read-only proxies.
- Global reads/writes that are not explicitly approved fail with a structured
  extension error.
- `require()` is disabled unless the host supplies a module resolver; a resolver
  must scope module access to the requesting extension and prevent path escape.
- Filesystem, process, clock and clipboard functionality is available only via
  separately documented capabilities when granted by Backend.

This sandbox is defense in depth, not an operating-system security boundary.
Untrusted or hostile extensions require process isolation outside this runtime.
