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
On a version-tagged release run, the tag, Runtime version and generated
Component Release Metadata must agree. The output directory is `dist/`.

The test verifies both archive checksums and sizes, rejects unsafe or
non-regular archive entries, compares the extracted TAR.GZ and ZIP contents,
checks every file digest in `package-manifest.json`, and loads the Runtime
version and strict-mode modules from each extracted tree with Lua 5.4. The
load test runs outside the Runtime Git checkout.

## Registry delivery

`runtime-<version>.release.json` is a Registry Component Release Metadata
candidate using schema 1.1.0. It records the exact source commit, Runtime
Extension Contract 1.0.0, Runtime Host API requirement 1.0.0, canonical
artifact digest/size, immutable GitHub Release URL, recipe and toolchain.

TAR.GZ is the single canonical Registry artifact for the universal
`any/any/none` target. ZIP is also published as a direct-download companion,
but is recorded under the metadata extension
`org.cdin.runtime.package-formats`; publishing both formats as separate
Registry artifacts for the same target would create an ambiguous match.

The generated metadata is a release output, not a mutable update to an
existing Registry Catalog entry. After the release assets are published and
verified, the exact metadata bytes must be committed under a new immutable
Registry release identity and then referenced by a Catalog update. Do not
retarget or overwrite the existing RC1/RC2 metadata documents.
