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

- **Runtime CI baseline** passed on
  [`5f37d733b42ad363abd8c26669157ae1bcc55186`](https://github.com/cdin-editor/runtime/commit/5f37d733b42ad363abd8c26669157ae1bcc55186)
  in [run 43385962122](https://github.com/cdin-editor/runtime/actions/runs/43385962122):
  Lua 5.4 on macOS and Windows, Lua 5.5 on Linux, Pipeline quality, and
  documentation/workflow validation. The later 1.0.0 preparation merge is
  `dafd508a0d862cf3b0efc5a5b70f7fcf8a735ab1`; its exact-main CI run is
  [43455232678](https://github.com/cdin-editor/runtime/actions/runs/43455232678)
  and must complete successfully before the release tag is created.
- **Runtime package workflow** passed its package build, checksum and extracted
  Lua 5.4 consumer checks in
  [run 43385962119](https://github.com/cdin-editor/runtime/actions/runs/43385962119).
  This was a branch push / dry-run, not a tag publication. It verified the
  branch-derived development identity
  `1.0.0-rc.2.next.9+g5f37d73`, not a stable `1.0.0` Release.
- **Live Backend + PUC Lua 5.4 + installed Kernel integration** passed on
  Backend main commit
  [`5d6371e8ca9ce1ee236d961181c259b3dfe72158`](https://github.com/cdin-editor/backend/commit/5d6371e8ca9ce1ee236d961181c259b3dfe72158)
  in [run 43455376627](https://github.com/cdin-editor/backend/actions/runs/43455376627).
  The run passed Linux, macOS and Windows live integration jobs. The separate
  Backend resource/sanitizer run
  [43455376090](https://github.com/cdin-editor/backend/actions/runs/43455376090)
  also completed successfully, including ThreadSanitizer, ASan/UBSan and
  bounded-job coverage. The five-target Backend package build passed in
  [run 43455376998](https://github.com/cdin-editor/backend/actions/runs/43455376998);
  its release-publication/provenance jobs were skipped because this was a
  branch push, not a tag.
- Backend PR [#40](https://github.com/cdin-editor/backend/pull/40) and
  [#41](https://github.com/cdin-editor/backend/pull/41) are merged. PR #40
  added live Lua 5.4 structured stale-version details and exact-once
  `__gc` cleanup coverage for document, snapshot, transaction and
  subscription handles. PR #41 adds the RT-013 single-file extension entry
  path with ambiguity, symlink, confinement and bounded-read tests. The
  merged Backend run above verifies these changes on all three OSes.

## Required gates before publishing Runtime 1.0.0

1. **Native Host status and userdata ownership.** Backend PRs
   [#40](https://github.com/cdin-editor/backend/pull/40) and
   [#41](https://github.com/cdin-editor/backend/pull/41) are merged. Latest
   Backend main live integration, native platform matrix and sanitizer /
   bounded-job checks passed in runs
   [43455376627](https://github.com/cdin-editor/backend/actions/runs/43455376627),
   [43455376998](https://github.com/cdin-editor/backend/actions/runs/43455376998)
   and [43455376090](https://github.com/cdin-editor/backend/actions/runs/43455376090).
   The live Runtime Host smoke explicitly verifies structured
   `STALE_VERSION` details and exact-once finalization of document, snapshot,
   transaction and subscription userdata. This closes the specific PR #40/#41
   work; it does not claim exhaustive runtime vectors for every Host API error
   code.
2. **Complete native error/status conformance.** Verify the Host API's stable
   status-code mapping and detail payloads, invalid/stale handle behavior,
   owner-thread rejection, cleanup after partial startup, and shutdown/failure
   paths against the actual Backend adapter. A single stale-version vector is
   not the entire mapping table.
3. **Native event and projection conformance.** Real Backend/Runtime UI
   projection, per-client ACK, backpressure, driver promotion and PaneTree
   result/layout/flush ordering pass in the latest Backend live integration.
   Runtime PR [#28](https://github.com/cdin-editor/runtime/pull/28) adds
   regression cases for both explicit `edits_truncated` notifications and
   version-chain gaps, asserting authoritative version/length refresh and
   unchanged exact document bytes. Its CI must pass before merge; these
   additional tests exercise Runtime's fail-safe notification consumer with
   FakeHost and do not replace the native Backend integration.
4. **Extension and migration scope.** Spec RT-013 records both directory
   `<name>/init.lua` and top-level `<name>.lua` entry shapes. Backend PR #41
   is merged and its cross-platform live integration passed. The documented
   1.0.0 contract supports both entry shapes; a single-file package has no
   nested module namespace. RT-020 and RT-021 remain Proposed and are
   explicitly not compatibility promises in this package: no automatic
   deprecated-API shims or blanket parity for undocumented behavior is
   claimed. The provisional `core.ui:publish` passthrough is not part of the
   stable extension API.
5. **Exact immutable publication.** A final `v1.0.0` tag must resolve to the
   exact source commit being packaged. The tagged workflow must publish the
   universal Lua module TAR.GZ, ZIP companion, checksums and canonical
   `runtime-1.0.0.json` ADR-0028 metadata generated from that same tag commit.
   The extracted package test must load the modules with PUC Lua 5.4 outside
   a Runtime source checkout. The publisher script already enforces exact
   `v1.0.0` tag-to-commit identity, canonical metadata name, schema 1.2.0
   publication declaration, one Registry artifact and archive digest/size
   consistency. A branch dry-run or the historical RC2 release is not a
   substitute.

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
