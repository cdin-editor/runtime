# Current state

CDIN Runtime is an early Lua implementation of the policy layer described in the
[CDIN Specification](https://github.com/cdin-editor/spec). It is useful for
working on Runtime modules and testing their behavior against a simulated Host.
It is not yet ready to replace the existing Lua core in a runnable CDIN build.

## Available now

- A public Lua entry point with strict-global checks.
- Command and key-binding registries.
- Configuration and project-context modules.
- A document client that talks only through the Runtime Host API.
- Logical views, selections and a data-only UI model.
- Theme, style and syntax registries.
- An extension manager with owner-scoped cleanup and a restricted Lua environment.
- Unit and simulated-Host integration tests.

## Still needed

- The production Backend adapter for the Host API.
- Tests against the real Kernel C ABI, including ownership and failure cases.
- Connection to the Frontend Protocol and a working frontend.
- Compatibility tests for behaviors that users rely on in the current CDIN code.
- A reviewed, stable Runtime Host API and UI model contract.

The Host API, Frontend Protocol model and extension-facing Runtime API in this
repository are provisional. The Specification remains authoritative: a design
marked `PROPOSED` there is not made an accepted project contract by this code.

Production integration remains open until the Backend adapter is tested against
the real Kernel and the Frontend Protocol is connected end to end.
