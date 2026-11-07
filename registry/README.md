# Registry release metadata

Runtime publishes its component Release Metadata in `registry/releases/`. The current entry is `runtime-1.0.0-rc.1.json`, with source revision `d2acb6f174edf127c3bf59e8e5d4aedcbef0d490`.

- Component identity: `runtime/default`
- Package version: `1.0.0-rc.1` (prerelease)
- Required contract: `org.cdin.runtime-host-api`, constraint `>=1.0.0 <2.0.0`
- Dependencies: none declared at the component level

Backend provides the Runtime Host API contract. The current CDIN Product Definitions
temporarily allow prerelease selection because this is the currently integrated
Runtime candidate. A stable Runtime release should be published with a new
immutable metadata document; CDIN can then disable prerelease selection.
Registry is not a Runtime dependency.

## Contract metadata status

The current Release Metadata declares the required Runtime Host API but has an
empty `contracts.provides` array. Accepted Spec requirement
[RT-012](https://github.com/cdin-editor/spec/blob/main/docs/components/runtime.md#L65)
also requires Runtime to declare the Extension Contract version/range it
provides.

The Runtime Extension API currently documents version `1.0`, but the Spec has
not yet defined its canonical namespaced Registry `contract_id` or how that
version maps to Registry's SemVer 2.0.0 contract field. Do not invent a
contract ID or silently normalize the version. This gap is tracked in
[Spec issue #16](https://github.com/cdin-editor/spec/issues/16) and
[Runtime issue #7](https://github.com/cdin-editor/runtime/issues/7). Publish a
new immutable Release Metadata identity after the contract decision is
accepted.

The selected source revision is immutable and later than the original
`v1.0.0-rc.1` tag. Runtime's package-version fallback file and tag-derived
source-checkout version are distinct paths; Runtime issue #7 tracks verifying
their behavior alongside CDIN's Resolved Manifest version check. This note
does not promote the package candidate to a stable release.
