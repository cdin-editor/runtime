# Registry release metadata

The Runtime repository now prepares package candidate
`runtime-1.0.0-rc.2.json`. It keeps the previous
`runtime-1.0.0-rc.1.json` immutable and adds the Extension Contract provider
required by accepted Spec RT-012.

- Component identity: `runtime/default`
- Candidate package version: `1.0.0-rc.2` (prerelease)
- Provided contract: `org.cdin.runtime-extension-contract` version `1.0.0`
- Required contract: `org.cdin.runtime-host-api`, constraint
  `>=1.0.0 <2.0.0`
- Component dependencies: none

The RC2 candidate source snapshot carries
`lua/cdin/runtime/core/release_metadata.lua` returning `1.0.0-rc.2` for
Registry/archive environments without usable Git metadata. Full Git source
checkouts continue to derive their development identity from `git describe`.

## Publication and immutability

The existing Registry Catalog still selects RC1 until a Registry Catalog
update adds the new metadata URI and exact SHA-256 digest. Do not edit
`runtime-1.0.0-rc.1.json` or its source pin in place. The RC2 document has its
own package version and immutable source revision; the RC1 document remains
available for older consumers.

This is an active integration candidate, not a formal
`v1.0.0-rc.2` Git tag or GitHub Release. The release workflow remains
tag-driven. A later tagged source archive must report the same version as its
embedded release metadata.

The candidate provides the canonical contract identity accepted in
[Spec PR #27](https://github.com/cdin-editor/spec/pull/27). Runtime's public
Extension API label `1.0` maps to Registry SemVer `1.0.0`; it remains
independent of the Runtime package version and the Backend-provided Host API
version.
