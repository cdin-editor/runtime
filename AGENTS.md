# Runtime repository working rules

1. Keep Lua at 5.4 and preserve `core.*` module identities until a reviewed migration changes them.
2. `cdin-kernel` is a separate C repository. Runtime must not link/load its implementation or own canonical document bytes/history.
3. Backend owns native handles, filesystem/system services, Kernel lifecycle and the Runtime Host API. Frontend owns drawing, shaping/bidi and toolkit state.
4. New infrastructure should be dependency-injected, pure where possible, and unit-testable without `core.init`, SDL or native globals.
5. Do not label code as migrated merely because it was copied. Update `docs/migration-status.md` and tests when a gate is actually met.
6. Host API version `0.1.0` is provisional. Do not freeze or advertise it as stable without an ADR, conformance tests and real Backend integration.
7. Keep error codes machine-readable and stable; never branch on human-readable error messages.
8. Lua State access is owner-thread-only. Background work must return through a queued event.
9. Every PR runs `make test` on Lua 5.4 and Python 3.10+.
