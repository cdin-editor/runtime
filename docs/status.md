# Current state

CDIN Runtime `1.0.0-rc.1` is the Lua 5.4 policy-layer release candidate. It contains
commands and key-binding registries, configuration, workspace context,
Host-backed document clients, logical views and selections, semantic UI model,
theme/style/syntax registries, extension sandboxing, and Kernel-logger routing.

## Verified in this source package

- Lua 5.4.7 unit tests: 137 assertions passed.
- Lua 5.4.7 simulated-Host integration tests: 131 assertions passed after the
  Protocol compatibility regression test was added.
- Static architecture boundary checks: passed.
- Registry-collected Runtime source pin
  `d2acb6f174edf127c3bf59e8e5d4aedcbef0d490` reports the selected package
  version `1.0.0-rc.1` in the real CDIN lifecycle check. The log records
  `runtime started host_api=1.0.0 version=1.0.0-rc.1 kernel_abi=1.1.0` in
  [CDIN workflow run 42407924719](https://github.com/cdin-editor/cdin/actions/runs/42407924719).
  Its Linux/macOS/Windows TUI/GUI-SDL matrix and full-stack sanitizer job passed.
- The tagged `v1.0.0-rc.1` source archive was built, tested, checksum-verified and published successfully by [Runtime release workflow 41737747346](https://github.com/cdin-editor/runtime/actions/runs/41737747346). Its artifact-test and assembled-asset verification steps passed.
- Frontend Protocol negotiation follows Spec `1.x` minor compatibility;
  Runtime Host API `1.0.0` is stable and uses same-major / minimum-minor compatibility.

## Not verified / release blockers

- Live Backend + Lua 5.4 + installed Kernel startup and document round-trip.
- Native Lua C binding ownership, `__gc` fallback, owner-thread enforcement and
  Kernel status-to-Lua error mapping under failure injection.
- Live Runtime → Backend UI projection/ACK integration against the real Lua/Kernel host.
- The companion Backend legacy patcher targets pre-integration Runtime source; it must not be run against this already-integrated 1.0.0 candidate.
- Filesystem discovery/loading and complete legacy extension-contract parity (RT-013 / RT-020 / RT-021 scope).
- Existing editor behaviour parity during migration, including approved command
  and keymap defaults.
- Cross-platform production integration evidence supplied by the companion
  Backend and full CDIN build.
- Live native lifecycle/error-mapping conformance and approved Runtime/extension API surface.

The published RC1 Release Metadata still has an empty `contracts.provides` array, so it does not yet satisfy the Extension Contract provider portion of RT-012. [Spec issue #16](https://github.com/cdin-editor/spec/issues/16) is now resolved by [Spec PR #27](https://github.com/cdin-editor/spec/pull/27): the canonical ID is `org.cdin.runtime-extension-contract`, and the existing API label `1.0` maps to Registry SemVer `1.0.0`. The already-published RC1 metadata is immutable and MUST NOT be edited in place; the provider declaration belongs in the next immutable Runtime candidate metadata document. This remains tracked by [Runtime issue #7](https://github.com/cdin-editor/runtime/issues/7).

The Runtime Host API contract is frozen at `1.0.0`; release readiness still depends on native integration and the explicitly scoped extension/migration gates. The Frontend Protocol is the
stable `1.0.0` shared wire contract. These are independent contracts and must
not be conflated with the Runtime package version.

See the [Runtime component specification](https://github.com/cdin-editor/spec/blob/main/docs/components/runtime.md) for normative requirements and [current implementation status](status.md) for the evidence boundary. The Specification remains authoritative; `PROPOSED`, `OPEN` and `DEFERRED` items are not made accepted by adding code here.
