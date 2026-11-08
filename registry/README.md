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

The Catalog snapshot consumed by CDIN is now updated at
[Registry commit `2a611eca830c0f235dacab04a1d006a8fd46e586`](https://github.com/cdin-editor/registry/commit/2a611eca830c0f235dacab04a1d006a8fd46e586).
It contains the RC2 metadata URI and exact SHA-256 digest
`b572ab0a390599d95815a70af97899ec17d003d3c47ee78584920db9ee387412`.
CDIN's Composition Root branch now pins that Catalog snapshot and selects the
RC2 candidate through Backend's existing Runtime dependency range. The
exact-head CDIN TUI/GUI-SDL product matrix and runtime-vs-Manifest check are
being verified in [CDIN run 42447891569](https://github.com/cdin-editor/cdin/actions/runs/42447891569).
Do not edit `runtime-1.0.0-rc.1.json` or its source pin in place; the RC1
document remains available for older consumers.

This is an active integration candidate, not a formal
`v1.0.0-rc.2` Git tag or GitHub Release. The release workflow remains
tag-driven. A later tagged source archive must report the same version as its
embedded release metadata.

The candidate provides the canonical contract identity accepted in
[Spec PR #27](https://github.com/cdin-editor/spec/pull/27). Runtime's public
Extension API label `1.0` maps to Registry SemVer `1.0.0`; it remains
independent of the Runtime package version and the Backend-provided Host API
version.
