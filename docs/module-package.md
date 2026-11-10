# Runtime module package

Runtime is a pure Lua component. Product consumers need its Lua module tree,
not a clone of this repository and not a native library or precompiled Lua
bytecode.

## Package layout

The release pipeline creates two byte-identical package layouts:

```text
cdin-runtime-<version>/
├── LICENSE
├── NOTICE
├── package-manifest.json
└── lua/
    └── cdin/
        ├── runtime.lua
        └── runtime/
            └── ...
```

The archive contains tracked Runtime Lua modules and the notices required to
redistribute them. It excludes Git metadata, tests, CI configuration,
development scripts and documentation. The generated `release_metadata.lua`
binds the extracted tree to the exact package version, so the normal Runtime
version resolver works without a Git checkout.

The module tree remains Lua source. Consumers must provide PUC Lua 5.4.x; the
package does not bundle a Lua interpreter or precompile bytecode.

## Build and verify locally

From a clean Runtime checkout with the supported Lua 5.4 interpreter:

```sh
python3 scripts/package-modules.py
python3 scripts/test-module-package.py
```

The builder derives the version and full source commit from Runtime itself.
On a version-tagged release run, the exact tag must resolve to the packaged
HEAD commit and agree with the Runtime version. The publisher emits the
canonical `runtime-<version>.json` metadata asset with the ADR-0028
`publication` identity. An untagged local package build emits the same
filename without claiming GitHub publication provenance. The output directory
is `dist/`.

The test verifies both archive checksums and sizes, rejects unsafe or
non-regular archive entries, compares the extracted TAR.GZ and ZIP contents,
checks every file digest in `package-manifest.json`, and loads the Runtime
version and strict-mode modules from each extracted tree with Lua 5.4. The
load test runs outside the Runtime Git checkout.

## Registry delivery

For a tagged release, `runtime-<version>.json` is the canonical ADR-0028
Component Release Metadata asset and uses schema 1.2.0. Its
`publication` object binds `github-releases-v1`, the canonical Runtime
repository URI, exact tag, full tag-resolved commit and this metadata asset's
basename. It records the Runtime Extension Contract 1.0.0, Runtime Host API
requirement 1.0.0, canonical artifact digest/size, immutable artifact URL,
recipe and toolchain. It deliberately omits its own URI/digest/size because
Registry obtains those from the GitHub Release Assets API.

An untagged local package build emits the same JSON basename as a package-test
fixture but omits `publication`; it is not a publishable Release Metadata
document.

TAR.GZ is the single canonical Registry artifact for the universal
`any/any/none` target. ZIP is also published as a direct-download companion,
but is recorded under the metadata extension
`org.cdin.runtime.package-formats`; publishing both formats as separate
Registry artifacts for the same target would create an ambiguous match.

The generated metadata is a GitHub Release Asset, not a tracked
per-version source file. Under ADR-0028, the Catalog declares the Runtime
repository once through a `release_sources` mapping; Registry discovers and
verifies eligible release metadata assets through the GitHub Releases API.
This becomes consumable only after Registry #53 implements the accepted
discovery contract and the product uses a compatible Catalog schema. Preserve
the existing RC1/RC2 metadata and Manifest identities for historical replay;
never retarget or overwrite them.
