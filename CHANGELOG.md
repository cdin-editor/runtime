# Changelog

## 0.1.0-dev — initial extraction scaffold

- Copy the Lua `data/core/` runtime from the supplied CDIN snapshot without changing existing module paths.
- Preserve CDIN architecture docs, extension contract, and plain-Lua regression tests.
- Add deterministic plugin/theme fixtures that were absent from the supplied working-tree snapshot.
- Add read-only reference snapshots of Spec architecture documents and Kernel ABI header/docs.
- Add provisional Host API metadata/validation, structured error records, a reusable named registry, LuaDoc types, and host-independent tests.
- Explicitly document migration gaps, especially local document/history ownership and the current host-global dependency.

This version is not a claim of integration completeness or ABI/Host API stability.
