# Runtime Host API draft

**Status: provisional 0.1.0.** This document defines a testable shape for the first adapter, not a stable public API. The authoritative API must be implemented by CDIN Backend and reviewed alongside Spec ADRs before pinning it in production.

## Ownership boundary

Lua Runtime receives a capability-limited descriptor from Backend. It must not load `cdin-kernel`, link the kernel directly, or receive native Kernel pointers/handles. `doc` service calls are forwarded by Backend to Kernel ABI 1.0.0; filesystem, process, logging and UI relay are also Backend-provided services.

## Draft descriptor

```lua
local host = {
  api_version = { major = 0, minor = 1, patch = 0 },
  kernel_abi = { major = 1, minor = 0, patch = 0 },
  capabilities = {
    ui_model = true,
    filesystem = true,
    search_literal = true,
    notifications = true,
  },
  services = {
    doc = {},      -- create/open/close/snapshot/edit/undo/redo/subscribe
    fs = {},       -- read/write/stat/list using explicit byte lengths/errors
    path = {},     -- normalize/join/absolute paths; no hidden chdir policy
    system = {},   -- clock, cancellation, logging and host lifecycle
    search = {},   -- only modes actually advertised by the Kernel, no assumed regex
    ui = {},       -- publish declarative model updates/capabilities
  },
}
```

## Service contract rules

- Every descriptor version is a non-negative integer triplet.
- Runtime checks Host API compatibility and Kernel ABI **major** before opening documents.
- A missing optional capability is queried with `has_capability`; callers do not infer it from a frontend name.
- A required service missing at startup is a structured `MISSING_SERVICE` error; no silent fallback to a different owner.
- Document edits use expected versions and return `{ version, accepted_seq, byte_length, status? }` based on the Backend mapping of the Kernel result. Byte buffers and lengths must not rely on NUL termination.
- Notifications are events, not a FIFO transaction queue. Do not invent FIFO ordering beyond the Kernel/Host contract.
- All Kernel status mapping is structured `{ code, message, details }`; unknown status codes remain failures (`UNKNOWN_STATUS`).
- Lua state and its service callbacks stay on the Runtime owner thread. Workers deliver queued events; they never access Lua directly.
- Explicit close/unsubscribe is the primary resource lifecycle; finalizers are fallback only.
- Do not pass opaque selection/history blobs through string munging or parse them in extensions.

## Current implementation status

`data/core/runtime/host.lua` validates metadata and required services with dependency injection. It is not yet used by legacy `core.init()` because the current C Host registers globals (`system`, `renderer`, `core`) rather than this descriptor. A transition adapter must be added in CDIN Backend before enabling it in production.

## Versioning

The Host API is still `0.x` and is intentionally not promised stable. A `0.x` minor release may change shape; code must pin the tested API version. A future `1.0.0` needs explicit compatibility policy, conformance fixtures and integration tests. Kernel ABI versioning is independent and remains 1.0.0.
