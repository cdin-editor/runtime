# Runtime 1.0.0 release readiness

**Status: RELEASE PREPARATION — NOT PUBLISHED.** The intended Runtime package
version is `1.0.0`. As of 2026-11-13, no `v1.0.0` tag or GitHub Release exists.
This document separates checked evidence, pending native conformance, and
downstream CDIN product acceptance. It does not mark the whole editor Stable.

## Version boundaries

These version numbers describe different interfaces and must not be conflated:

| Identity | Version | Meaning |
| --- | --- | --- |
| Runtime package | `1.0.0` (target) | Version of the Lua policy-layer package and its immutable module archive. |
| Runtime Host API | `1.0.0` | Stable Backend-to-Runtime service contract. |
| Frontend Protocol | `1.0.0` | Stable Frontend-to-Backend wire contract. |
| Runtime Extension Contract | `1.0.0` | Registry SemVer for the documented extension API. |
| Kernel ABI | `1.1.0` | Native document/host boundary provided by Backend's Kernel adapter. |

A stable Runtime package does not imply that CDIN's TUI, GUI-SDL, Registry
bootstrap or complete editor application is Stable.

## Verified evidence

- **Runtime CI** on main commit
  [`5f37d733b42ad363abd8c26669157ae1bcc55186`](https://github.com/cdin-editor/runtime/commit/5f37d733b42ad363abd8c26669157ae1bcc55186)
  passed in [run 43385962122](https://github.com/cdin-editor/runtime/actions/runs/43385962122):
  Lua 5.4 on macOS and Windows, Lua 5.5 on Linux, Pipeline quality, and
  documentation/workflow validation.
- **Runtime package workflow** passed its package build, checksum and extracted
  Lua 5.4 consumer checks in
  [run 43385962119](https://github.com/cdin-editor/runtime/actions/runs/43385962119).
  This was a branch push / dry-run, not a tag publication. It verified the
  branch-derived development identity
  `1.0.0-rc.2.next.9+g5f37d73`, not a stable `1.0.0` Release.
- **Live Backend + PUC Lua 5.4 + installed Kernel integration** passed in
  [Backend run 43385975403](https://github.com/cdin-editor/backend/actions/runs/43385975403).
  The Backend checked out Runtime main at the exact commit above, installed
  Kernel package 1.2.1 / ABI 1.1.0 and logger 0.1.0, ran Runtime tests and
  boundaries, built Backend with Lua, and passed Backend/Kernel integration
  plus the real Runtime startup/pump/shutdown smoke. The workflow ran on
  Ubuntu 24.04; it is not cross-platform live-bridge evidence.
- The same live Backend run exercised document lifecycle, snapshots,
  transactions, notifications, stale handles, Backend session ownership,
  queue backpressure, ACK handling, Driver promotion and the Runtime
  PaneTree result/layout/flush path. These checks are real native integration,
  not FakeHost-only tests.

## Required gates before publishing Runtime 1.0.0

1. **Native Host status and userdata ownership.** Backend PR
   [#40](https://github.com/cdin-editor/backend/pull/40) adds live Lua 5.4
   assertions for structured `STALE_VERSION` details and `__gc` release of
   document, snapshot, transaction and subscription handles. Its initial live
   integration run [43449265418](https://github.com/cdin-editor/backend/actions/runs/43449265418)
   passed and logged both `PASS runtime_host_conformance` and
   `PASS runtime_host_smoke`. The follow-up head
   [`4d002c3`](https://github.com/cdin-editor/backend/commit/4d002c3bf917418ee7c63ccd5c827bd791a5964f)
   only corrects failure-diagnostic newline escaping; its fresh CI, live
   integration and resource-stress runs were queued at this checkpoint.
   Require those latest-head checks to pass and the PR to merge before treating
   this gate as closed.
2. **Complete native error/status conformance.** Verify the Host API's stable
   status-code mapping and detail payloads, invalid/stale handle behavior,
   owner-thread rejection, cleanup after partial startup, and shutdown/failure
   paths against the actual Backend adapter. A single stale-version vector is
   not the entire mapping table.
3. **Native event and projection conformance.** Preserve the already-passing
   real Backend/Runtime UI projection, per-client ACK, backpressure and
   PaneTree ordering checks; retain explicit notification overflow/resync and
   failure-injection evidence where the relevant requirement applies.
4. **Extension and migration scope.** Spec RT-013 records both directory
   `<name>/init.lua` and top-level `<name>.lua` entry shapes. Backend PR
   [#41](https://github.com/cdin-editor/backend/pull/41) implements the
   single-file path with confined, bounded, no-follow reads, rejects
   directory/file ambiguity and adds native tests. Its Linux/macOS/Windows CI
   and live integration must pass and the PR must merge before this gate is
   closed. The documented 1.0.0 contract supports both entry shapes; a
   single-file package has no nested module namespace. RT-020 and RT-021 remain
   Proposed and are explicitly not compatibility promises in this package:
   no automatic deprecated-API shims or blanket parity for undocumented
   behavior is claimed. The provisional `core.ui:publish` passthrough is not
   part of the stable extension API.
5. **Exact immutable publication.** A final `v1.0.0` tag must resolve to the
   exact source commit being packaged. The tagged workflow must publish the
   universal Lua module TAR.GZ, ZIP companion, checksums and canonical
   `runtime-1.0.0.json` ADR-0028 metadata generated from that same tag commit.
   The extracted package test must load the modules with PUC Lua 5.4 outside
   a Runtime source checkout. A branch dry-run or the historical RC2 release
   is not a substitute.

## Immutable history and downstream adoption

- Existing Runtime `v1.0.0-rc.1`, `v1.0.0-rc.2`, `v0.3.0`,
  `v0.2.0` and `v0.1.0` tags/releases remain immutable. In particular,
  RC2's historical `runtime-1.0.0-rc.2.release.json` asset is not rewritten
  or renamed; canonical ADR-0028 metadata is generated only for the new tag.
- Registry/CDIN must later select the published Runtime `1.0.0` metadata
  identity, verify its GitHub-published digest and size, and consume the
  immutable module archive. This downstream Catalog/Manifest adoption is
  separate from Runtime's component release and does not make the complete
  CDIN application Stable.
- CDIN product status remains **Development** until its own artifact-first
  install, IME/PaneTree, interactive behavior, recovery, performance and
  Product Acceptance gates pass.

Spec references: [Runtime component requirements and 1.0.0 gates](https://github.com/cdin-editor/spec/blob/main/docs/components/runtime.md),
[ADR-0019 Runtime bridge](https://github.com/cdin-editor/spec/blob/main/docs/adr/ADR-0019-runtime-bridge.md),
[ADR-0028 GitHub Release metadata discovery](https://github.com/cdin-editor/spec/blob/main/docs/adr/ADR-0028-github-release-metadata-discovery.md).
