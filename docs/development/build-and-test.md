# Build and test

## Requirements

- Lua 5.4 for the supported Runtime version.
- `make` to run the test targets.
- `bash` and `grep` for `make boundary` and the Pipeline tasks. Runtime is pure
  Lua and has no other dependency: it links no logger or native library.

Run the commands from the repository root. The test files set their Lua module
paths themselves.

## Commands

```sh
make unit         # tests for individual modules
make integration  # Runtime behavior using a simulated Host
make test         # unit and integration tests
make check        # the full local test target
make boundary     # static guards: no console output, native code or second logger
```

If your Lua 5.4 executable is named differently, pass the name to `make`:

```sh
make check LUA=lua
```

Only use this when `lua` is Lua 5.4. Tests on another version are a useful smoke
test but do not prove the supported runtime behaves correctly.

## Pipeline, PSX and gix

CI and releases run through [m-mdy-m/pipeline](https://github.com/m-mdy-m/pipeline).
Its tasks are defined in `pipeline.toml`:

| Task | What it does |
|---|---|
| `deps` | Makes sure a Lua 5.4+ interpreter exists (`scripts/install-deps.sh`). |
| `unit`, `integration` | Run the test suites with the detected interpreter. |
| `boundary` | Runs `scripts/check-boundaries.sh`. |
| `check` | The gate CI runs: `integration` and `boundary`. |
| `package` | Builds the source archives into `dist/` (needs `PIPELINE_RELEASE_TAG`). |

With the Pipeline engine checked out locally, run a task with
`PYTHONPATH=<pipeline>/src python -m pipeline run check`.
`scripts/ci-check.sh` runs the same gate without Python.

`psx.yml` configures PSX project checks. PSX has no Lua project type, so the
project is `generic`, and `src_folder` is not enabled because Runtime's sources
live in `lua/`. `.gix/config.default` is the branch-flow template;
`scripts/init-git-flow.sh` turns it into `.gix/config` in a real checkout.

`.github/workflows/ci.yml` calls Pipeline's reusable CI and docs workflows, plus
a small `portability` job for Lua 5.5, macOS and Windows that the Linux-only
reusable CI cannot cover. `release.yml` calls Pipeline's release workflow with a
single `source` target because Runtime's archives are identical on every
platform.

## Try the Runtime

Start with the [User Guide](../user-guide.md). Its example uses
`tests/support/fake_host.lua`, which simulates the services expected from the
Backend. It is intended for tests and learning, not for a production CDIN build.

The public module is `require("cdin.runtime")`. It installs strict-global
checking before loading the application. Product boot code must not import the
internal module `cdin.runtime.application` directly.

## What the tests cover

- `tests/unit/run.lua` checks module behavior such as commands, key bindings,
  configuration, project context, views, syntax rules, extension sandboxing and
  structured errors.
- `tests/integration/run.lua` checks how modules work together with the fake
  Host, including document edits, undo/redo, snapshots, transactions,
  notifications, saving, extension cleanup and shutdown.
- `tests/unit/log_tests.lua` and `tests/integration/logging_tests.lua` cover the
  logger, the Host `logging` descriptor, Kernel-logger routing, privacy (no
  document content or paths in records) and survival of a failing Host logger.

## What the tests do not prove

The fake Host is not the real Kernel adapter. Passing local tests does not prove
native handle ownership, Kernel ABI conformance, thread handoff or real file I/O.
The companion Backend repository provides a live Lua 5.4 + Kernel + Runtime
workflow, including a Frontend Protocol create/edit/versioned-line-read smoke
test. Run that workflow before treating a combined CDIN build as integrated.
