# Types and ownership

Lua has dynamic types; shared shapes are documented with Lua Language Server annotations in `data/core/runtime/types.lua`. That file returns an empty table and has no runtime behavior.

| Shape | Owner | Rule |
|---|---|---|
| `RuntimeVersion` | component contract | Integer `major`, `minor`, `patch`; stage is informative only |
| `RuntimeError` | Runtime/Host boundary | Stable `code`, display-only `message`, optional structured `details` |
| `DocumentHandle` | Host/Kernel via Backend | Opaque identity; Runtime never decodes a native Kernel handle |
| `DocumentSnapshot` | Host response | Versioned read result; not a mutable canonical Runtime buffer |
| `DocumentEditRequest` | Runtime caller | Includes expected version and byte range; validation happens at boundary |
| `DocumentEditResult` | Host response | New version, accepted sequence, byte length/status per mapping contract |
| `RuntimeCapabilities` | Backend | Explicit capabilities, not inferred from SDL or frontend identity |
| `RuntimeHostDescriptor` | Backend | Version, Kernel ABI metadata, services, capabilities |
| `CommandDescriptor` | Runtime registry | Named, testable action with optional predicate/metadata |
| `ViewState` | Runtime UI model | Selection and logical scroll metadata; no canonical text storage |
| `StyleRole` | Runtime/Frontend contract | Semantic style names/data; renderer chooses pixels |
| `PluginModule` | Extension loader contract | Required `init(core, config)`, optional `unload()` |

## Ownership constraints

- Kernel: canonical bytes, content version, snapshots, transactions, undo/redo and Kernel notifications.
- Runtime: commands, selection/view metadata, keymaps, config, syntax/highlighting and extension lifecycle.
- Backend: OS services, native handles, Kernel instance, Host callbacks, lifecycle and protocol relay.
- Frontend: windows, rendering, shaping/bidi, pixel/viewport measurements and toolkit objects.
- Extension: its own state; no direct access to Kernel handles or Backend internals.

`data/core/doc/init.lua` violates the future single-owner rule today. It remains as a documented transitional exception until the Host document client and all callers are migrated.
