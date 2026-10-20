# ADR-0002: Runtime uses Kernel only through Backend Host API

- **Status:** Accepted by the Spec baseline
- **Context:** Kernel is a separate C library with its own ABI, concurrency rules and resource lifecycle.
- **Decision:** Runtime Lua sees a versioned Host API supplied by CDIN Backend. It never links, loads or owns the Kernel implementation.
- **Consequences:** Host API conformance is independently testable; Backend remains the only component responsible for translating Lua requests to Kernel ABI 1.0.0.
