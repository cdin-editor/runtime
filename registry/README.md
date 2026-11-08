# Registry release metadata

Runtime publishes its component Release Metadata in `registry/releases/`. The
current Catalog entry is `runtime-1.0.0-rc.1.json`, with package version
`1.0.0-rc.1` and immutable source revision
`d2acb6f174edf127c3bf59e8e5d4aedcbef0d490`.

- Component identity: `runtime/default`
- Package version: `1.0.0-rc.1` (prerelease)
- Required contract: `org.cdin.runtime-host-api`, constraint
  `>=1.0.0 <2.0.0`
- Dependencies: none declared at the component level

Backend provides the Runtime Host API contract. The current CDIN Product
Definitions temporarily allow prerelease selection because this is the
currently integrated Runtime candidate. A stable Runtime release should be
published with a new immutable metadata document; CDIN can then disable
prerelease selection. Registry is not a Runtime dependency.

## Package version and source identity

The Registry-selected source revision is intentionally newer than the original
`v1.0.0-rc.1` tag: the tag points to
`fda2db69d8e0ab90c854c3a74efa1dd80d9714cc`, while the Catalog source pin is
41 commits ahead at `d2acb6f174edf127c3bf59e8e5d4aedcbef0d490`. This does not
create a second package version. The Registry source snapshot retains the
package-version fallback module
`lua/cdin/runtime/core/release_metadata.lua`, which returns
`1.0.0-rc.1` when Git tag metadata is unavailable. A normal full source
checkout still derives a development identity from `git describe`; that is
not the package identity consumed by CDIN.

This behavior was verified end to end rather than inferred from the files:

- The real CDIN Registry-backed composition run selected the RC1 metadata and
  logged `runtime started host_api=1.0.0 version=1.0.0-rc.1 kernel_abi=1.1.0`.
  [CDIN workflow run 42407924719](https://github.com/cdin-editor/cdin/actions/runs/42407924719)
  passed its Linux, macOS and Windows TUI/GUI-SDL jobs and the full-stack
  ASan/UBSan/leak job.
- The tagged `v1.0.0-rc.1` archive was built, tested, checksum-verified and
  published by [Runtime release workflow 41737747346](https://github.com/cdin-editor/runtime/actions/runs/41737747346).

The RC1 package identity therefore remains `1.0.0-rc.1`; the 41-commit
source distance is an intentional Registry source snapshot, not an unreported
package-version bump. This does not promote the candidate to a stable release.

## Contract metadata status

The published RC1 metadata requires Runtime Host API
`org.cdin.runtime-host-api` but has an empty `contracts.provides` array.
Accepted Spec requirement
[RT-012](https://github.com/cdin-editor/spec/blob/main/docs/components/runtime.md#L65)
also requires Runtime to declare the Extension Contract version it provides.

[Spec issue #16](https://github.com/cdin-editor/spec/issues/16) is resolved by
[Spec PR #27](https://github.com/cdin-editor/spec/pull/27). The canonical
Registry identity is `org.cdin.runtime-extension-contract`, and the Runtime
Extension API label `1.0` maps to Registry SemVer `1.0.0`. A consumer using
the baseline v1 contract may require `>=1.0.0 <2.0.0`.

Do not edit `runtime-1.0.0-rc.1.json` in place or publish a second metadata
identity for the same component/version. The provider declaration must ship in
a new immutable Runtime candidate metadata document with its own package
identity and exact source revision. This remaining RT-012 release step is
tracked in [Runtime issue #7](https://github.com/cdin-editor/runtime/issues/7).
