# ADR-0003: Do not copy native Backend or Frontend implementation into Runtime

- **Status:** Accepted
- **Context:** CDIN `src/` includes SDL, renderer, filesystem, loop, Lua C binding and OS code.
- **Decision:** Extract Runtime-owned Lua modules only. Keep `src/api`, `src/lua`, `src/ui`, `src/fs`, `src/loop`, `src/platform`, `src/core/window` and `src/base` in the CDIN Backend/Frontend repositories according to Spec boundaries.
- **Consequences:** This repository can be unit-tested with plain Lua; it is not standalone until Backend Host integration is implemented.
