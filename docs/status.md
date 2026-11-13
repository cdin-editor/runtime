# Runtime 1.0.0 release readiness

**Status: RELEASE PREPARATION — NOT PUBLISHED.** The intended Runtime package
version is `1.0.0`. As of 2026-11-13, no `v1.0.0` tag or GitHub Release exists.
This document separates checked component evidence, pending native conformance,
and downstream CDIN product acceptance. It does not mark the whole editor Stable.

## Version boundaries

These version numbers describe different interfaces and must not be conflated:

| Identity | Version | Meaning |
| --- | --- | --- |
| Runtime package | `1.0.0` (target) | Version of the Lua policy-layer package and immutable module archive. |
| Runtime Host API | `1.0.0` | Stable Backend-to-Runtime service contract. |
| Frontend Protocol | `1.0.0` | Stable Frontend-to-Backend wire contract. |
| Runtime Extension Contract | `1.0.0` | Registry SemVer for the documented extension API. |
| Kernel ABI | `1.1.0` | Native document/host boundary provided by Backend's Kernel adapter. |

A stable Runtime package does not imply that CDIN's TUI, GUI-SDL, Registry
bootstrap or complete editor application is Stable.

## Verified evidence

- **Runtime main CI** passed on
  [`b4444cb8a7fa78e142402ab0bbd094d34914f13b`](https://github.com/cdin-editor/runtime/commit/b4444cb8a7fa78e142402ab0bbd094d34914f13b)
  in [run 43457131023](https://github.com/cdin-editor/runtime/actions/runs/43457131023).
  This includes the merged notification-resynchronization tests from Runtime
  PR [#28](https://github.com/cdin-editor/runtime/pull/28), Lua 5.4 macOS and
  Windows, Lua 5.5 Linux, Pipeline quality, and documentation/workflow checks.
- **Runtime main package workflow** passed its source/module tests, package
  build, extracted-package checks, assembly and checksum verification in
  [run 43457131021](https://github.com/cdin-editor/runtime/actions/runs/43457131021).
  Because this was a branch push rather than a signed version-tag event, its
  Release publication and provenance jobs were skipped. It is not a stable
  Runtime release.
- **Live Backend + PUC Lua 5.4 + installed Kernel integration** passed on
  Backend main commit
  [`5d6371e8ca9ce1ee236d961181c259b3dfe72158`](https://github.com/cdin-editor/backend/commit/5d6371e8ca9ce1ee236d961181c259b3dfe72158)
  in [run 43455376627](https://github.com/cdin-editor/backend/actions/runs/43455376627).
  Linux, macOS and Windows live-integration jobs passed. Backend resource
  sanitizer coverage passed in
  [run 43455376090](https://github.com/cdin-editor/backend/actions/runs/43455376090),
  including ThreadSanitizer, ASan/UBSan and bounded-job checks. The five-target
  Backend package build passed in
  [run 43455376998](https://github.com/cdin-editor/backend/actions/runs/43455376998);
  its release/provenance jobs were skipped because the run was not a tag event.
- Backend PRs [#40](https://github.com/cdin-editor/backend/pull/40) and
  [#41](https://github.com/cdin-editor/backend/pull/41) are merged. PR #40
  added live Lua 5.4 structured `STALE_VERSION` details and exact-once
  `__gc` cleanup coverage for document, snapshot, transaction and
  subscription userdata. PR #41 completed the RT-013 single-file extension
  entry path with ambiguity, symlink, confinement and bounded-read checks.
- Runtime PR #28 is merged. It adds regression tests for truncated edit
  notifications and version-chain gaps, verifying authoritative version/length
  refresh while preserving exact document bytes.
- Runtime PR [#29](https://github.com/cdin-editor/runtime/pull/29) adds the
  Runtime-side owner-scoped declarative panel/prompt model and bounded
  presentation validation. Exact head
  [`1b42779cfc3c78035fa182a7ca928d2d7e85809d`](https://github.com/cdin-editor/runtime/commit/1b42779cfc3c78035fa182a7ca928d2d7e85809d)
  passed Runtime CI in
  [run 43459807211](https://github.com/cdin-editor/runtime/actions/runs/43459807211)
  and source/module package build, extracted-artifact tests, assembly and
  checksum verification in
  [run 43459793982](https://github.com/cdin-editor/runtime/actions/runs/43459793982).
  The PR remains open and is not yet part of `main`. It does not advertise
  `ui-presentation/1` or claim Backend/Frontend conformance.

## Required gates before publishing Runtime 1.0.0

1. **Native Host status and userdata ownership.** Backend PRs #40 and #41 are
   merged. The latest Backend main live integration, cross-platform matrix
   and sanitizer/bounded-job checks passed in runs
   [43455376627](https://github.com/cdin-editor/backend/actions/runs/43455376627),
   [43455376998](https://github.com/cdin-editor/backend/actions/runs/43455376998)
   and [43455376090](https://github.com/cdin-editor/backend/actions/runs/43455376090).
   The live Host smoke verifies structured stale-version details and exact-once
   finalization of document, snapshot, transaction and subscription userdata.
   This closes the specific #40/#41 work; it does not claim exhaustive vectors
   for every Runtime Host API error code.
2. **Complete native error/status conformance.** Verify the Host API's stable
   status-code mapping and typed detail payloads, invalid/stale handle behavior,
   owner-thread rejection, cleanup after partial startup, and shutdown/failure
   paths against the actual Backend adapter. A single stale-version vector is
   not the entire mapping table.
3. **Native event and projection conformance.** Real Backend/Runtime UI
   projection, per-client ACK, backpressure, Driver promotion and PaneTree
   result/layout/flush ordering pass in the latest Backend live integration.
   Runtime PR #28 is merged and its notification truncation/version-gap
   regression tests pass in the latest Runtime main CI. These Runtime tests
   use FakeHost for the incomplete-history vectors; they complement but do not
   replace the native Backend integration.
4. **Extension and migration scope.** Spec RT-013 records both directory
   `<name>/init.lua` and top-level `<name>.lua` entry shapes. Backend PR #41
   is merged and its cross-platform live integration passed. The documented
   Runtime 1.0.0 contract supports both layouts; a single-file package has no
   nested module namespace. RT-020 and RT-021 remain Proposed and are not
   compatibility promises: no automatic deprecated-API shims or blanket
   parity for undocumented legacy behavior is claimed.
5. **Extension presentation contract.** Runtime PR #29 supplies the
   owner-scoped semantic panel/prompt model, schema validation and lifecycle
   cleanup. It must be reviewed and merged before treating that Runtime API as
   part of the package. Backend and Frontend still need to validate and render
   the accepted `ui-presentation/1` vectors and negotiate the capability before
   interactive widgets can be advertised. Until then, the Runtime does not
   advertise that capability, unknown widgets remain data-only, and the
   optional `canvas` path remains separate. The legacy `core.ui.publish`
   escape hatch is hidden from extensions by default; only a trusted embedding
   application can explicitly enable it for migration.
6. **Exact immutable publication.** A final `v1.0.0` tag must resolve to the
   exact source commit being packaged. The tagged workflow must publish the
   universal Lua module TAR.GZ, ZIP companion, checksums and canonical
   `runtime-1.0.0.json` ADR-0028 metadata generated from that same tag commit.
   The extracted package test must load the modules with PUC Lua 5.4 outside a
   Runtime source checkout. A branch dry-run or the historical RC2 release is
   not a substitute.

## Immutable history and downstream adoption

- Existing Runtime `v1.0.0-rc.1`, `v1.0.0-rc.2`, `v0.3.0`,
  `v0.2.0` and `v0.1.0` tags/releases remain immutable. RC2's historical
  `runtime-1.0.0-rc.2.release.json` asset is not rewritten or renamed;
  canonical ADR-0028 metadata is generated only for the new tag.
- A branch-push workflow run on the branch named `v1.0.0`
  [43457218293](https://github.com/cdin-editor/runtime/actions/runs/43457218293)
  failed because the changelog did not yet contain a stable `1.0.0` section.
  That run was not a tag event: no `v1.0.0` tag or GitHub Release exists.
  Add the final dated changelog section only when the release contents and
  acceptance gates are settled; do not treat that branch run as publication.
- Registry/CDIN must later select the published Runtime 1.0.0 metadata identity,
  verify its GitHub-published digest and size, and consume the immutable module
  archive. This downstream Catalog/Manifest adoption is separate from the
  Runtime component release and does not make the complete CDIN application
  Stable.
- CDIN product status remains **Development** until its own artifact-first
  install, IME/PaneTree, interactive behavior, recovery, performance and
  Product Acceptance gates pass.

Spec references: [Runtime component requirements and 1.0.0 gates](https://github.com/cdin-editor/spec/blob/main/docs/components/runtime.md),
[ADR-0019 Runtime bridge](https://github.com/cdin-editor/spec/blob/main/docs/adr/ADR-0019-runtime-bridge.md),
[ADR-0028 GitHub Release metadata discovery](https://github.com/cdin-editor/spec/blob/main/docs/adr/ADR-0028-github-release-metadata-discovery.md).
