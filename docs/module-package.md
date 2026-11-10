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

`runtime-<version>.json` is the canonical Component Release Metadata
Release Asset name for the default Runtime variant. A version-tagged build
emits schema 1.2.0 and the ADR-0028 `publication` declaration, binding
`github-releases-v1`, the canonical Runtime repository URI, exact `v<version>`
tag, full tag-resolved commit SHA and exact metadata asset basename. It is
generated after the module archives and checksum sidecars, from the same
tagged source commit as the package artifacts.

A local or branch build emits a schema 1.1.0 metadata candidate without
`publication`; it is useful for package inspection but is not eligible for
GitHub Release discovery. The test rejects any mismatch between the candidate
filename, source-unit repository/revision and publication identity.

TAR.GZ is the single canonical Registry artifact for the universal
`any/any/none` target. ZIP is also published as a direct-download companion,
but is recorded under the metadata extension
`org.cdin.runtime.package-formats`; publishing both formats as separate
Registry artifacts for the same target would create an ambiguous match.

The generated metadata is uploaded to the matching GitHub Release as a
Release Asset. It does not contain its own URI or digest; Registry obtains and
verifies those from the GitHub Release Asset API. Do not commit new per-version
metadata files under `registry/releases/`. Historical RC1/RC2 source metadata
and already-published release assets remain immutable and backward-compatible.
