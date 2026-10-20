# Source provenance manifest

- `SOURCE-MANIFEST.json` is the machine-readable inventory. `source_sha256` identifies the supplied upstream file; `sha256` identifies the file in this repository. `transform` is `verbatim` unless an intentional local adaptation is documented.
- `SOURCE-MANIFEST.csv` is the same inventory for spreadsheet/diff review.
- `MIGRATION-STATUS.json` lists completed extraction tasks and open architectural migration items.

The only source-file adaptation in the initial import is the inherited `scripts/test_lua.lua` test: it now removes the temporary fixture tree it owns on exit, while preserving an externally supplied `CDIN_DIR`. Application modules under `data/core/` are copied without modification.

The Spec and Kernel copies are reference snapshots, not Git submodules and not authoritative repositories. Do not refresh them by hand without updating the canonical upstream project first.
