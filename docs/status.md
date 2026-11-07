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

The current Release Metadata still needs the Extension Contract provider declaration required by RT-012. Its canonical Registry identity and SemVer representation are pending [Spec issue #16](https://github.com/cdin-editor/spec/issues/16), tracked for Runtime in [issue #7](https://github.com/cdin-editor/runtime/issues/7). Do not assign a guessed `contract_id` or edit the published RC metadata in place.

The Runtime Host API contract is frozen at `1.0.0`; release readiness still depends on native integration and the explicitly scoped extension/migration gates. The Frontend Protocol is the
stable `1.0.0` shared wire contract. These are independent contracts and must
not be conflated with the Runtime package version.

See the [Runtime component specification](https://github.com/cdin-editor/spec/blob/main/docs/components/runtime.md) for normative requirements and [current implementation status](status.md) for the evidence boundary. The Specification remains authoritative; `PROPOSED`, `OPEN` and `DEFERRED` items are not made accepted by adding code here.
