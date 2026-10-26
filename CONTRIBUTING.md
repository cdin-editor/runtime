# Contributing to CDIN Runtime

Thanks for taking the time to improve CDIN Runtime. Contributions do not need to
be large: a focused bug fix, a clearer example, a missing test or a correction
that makes a module easier to understand is valuable.

Runtime is still under development. Its Host API and UI model are provisional,
and it is not yet connected to the production Backend, live Kernel or Frontend
Protocol. Please keep that status in mind when proposing changes.

## Before starting

For a small typo or a self-contained bug fix, you can open a pull request
straight away. For a new feature, a public API change, a large refactor or a
change that affects more than one CDIN project, open an issue first so the scope
and ownership can be discussed.

Before designing a cross-project change, check the
[CDIN Specification](https://github.com/cdin-editor/spec). It takes priority
when a local implementation disagrees with a shared contract. Avoid adding a
Runtime-only interpretation of behavior that should be defined by the shared
specification.

## What belongs in Runtime?

Runtime contains editor behavior that should not depend on a particular window
system or operating system. In general:

- commands and key bindings belong in Runtime;
- views, selections, focus, themes, syntax rules, settings and project context
  belong in Runtime when they describe editor behavior rather than drawing;
- document text, authoritative versions, snapshots and undo/redo history belong
  to the Kernel;
- operating-system access and the connection to the Kernel belong behind the
  Backend/Host boundary;
- pixels, font shaping, line wrapping, window events and drawing belong to the
  Frontend.

Runtime should not keep a second authoritative document buffer or call native
Kernel/OS APIs directly. It should use the Host interface and keep only the
handles and metadata needed to coordinate editor behavior. If a change appears
to cross these boundaries, describe why in the issue or pull request before
implementing it.

## Set up a development environment

You need:

- Git;
- Lua 5.4 (the supported local test version);
- `make` for the standard commands shown below.

Clone the repository and enter its root directory:

```sh
git clone https://github.com/cdin-editor/runtime.git
cd runtime
```

Check the interpreter and run the tests:

```sh
lua -v
make check
```

If Lua 5.4 is installed as `lua` instead of `lua5.4`, pass the executable
explicitly:

```sh
make check LUA=lua
```

The repository has no native build step at present. It is a Lua codebase, so
you can edit a module and rerun its tests without compiling a C binary.

## Run tests

Use the targets from the repository root:

```sh
make unit          # isolated module tests
make integration   # modules working together with a simulated Host
make test          # unit and integration tests
make check         # the full local test target
```

When changing behavior, add a test that fails before the fix and passes after
it. Prefer tests that describe observable behavior rather than tests coupled to
private table layouts or implementation details. Add negative tests for invalid
inputs and lifecycle tests for close, unload, failed startup and cleanup when
those paths are affected.

Integration tests use a simulated Host. They are useful for checking Runtime
coordination, but they do **not** prove compatibility with the production
Backend, a running Kernel, native resource ownership or the Frontend Protocol.
Be precise about what was actually tested; do not describe simulated-Host tests
as end-to-end integration.

If a test fails, include the exact command, Lua version and relevant error in
the issue or pull request. Do not paste secrets, access tokens or private user
data into logs.

## Working on the code

### Keep changes focused

One pull request should normally solve one problem. Avoid combining an unrelated
refactor, new feature and formatting pass: separate changes are easier to
review, test and revert. Prefer a small, direct implementation over an
abstraction that is only used once and has no clear second use.

### Follow the existing module boundaries

Keep related behavior in the module that owns it. Reuse the existing registry,
Host, event and lifecycle patterns rather than creating a parallel way to do
the same job. Do not introduce compatibility wrappers for paths that are no
longer part of the public entry point unless a migration requirement has been
agreed on.

The public Lua entry point is `require("cdin.runtime")`. Treat other module
paths as implementation details unless the relevant contract explicitly makes
them public.

### Handle errors and cleanup deliberately

Validate values at public boundaries and return the established Runtime error
shape/code instead of silently changing invalid data. Keep error messages useful
without putting secrets or whole document contents into them. When a component
registers commands, events, key bindings or other resources, make sure those
registrations can be removed during failure and unload. Avoid partial mutation
when an operation can be validated before it starts.

### Respect ownership of document state

Do not store a second authoritative copy of document text, edit history or
version state in Runtime. Use the Host-provided operations and handles. Any
change to document operations, snapshot lifetime, version checks or transaction
semantics should include tests that cover stale or invalid state where
appropriate.

### Keep extension code constrained

Extensions must not gain direct access to `io`, `os`, `debug`, native loaders,
raw Kernel handles or other privileged APIs through their environment. Do not
weaken the extension sandbox to make a test pass. Any new capability should have
an explicit Host-side owner, a clear permission boundary and relevant tests.
The Lua sandbox is not an operating-system security boundary; see
[SECURITY.md](SECURITY.md) for reporting and security guidance.

### Write readable Lua

- Choose descriptive names and keep functions small enough to follow.
- Prefer explicit control flow to clever metaprogramming or hidden global state.
- Follow the nearby formatting and error-handling style; avoid unrelated
  reformatting.
- Do not add a dependency unless it solves a concrete need and its maintenance
  cost is justified.
- Comments should explain a non-obvious reason or constraint, not paraphrase
  every line of code.

## Documentation

Update documentation when a change affects how Runtime is used, a public
contract, extension behavior, error handling or the developer workflow. Keep
beginner-facing explanations direct and high-level; put detailed contract
information in the relevant contract page. Do not add internal planning
reports, temporary test notes or redundant architecture documents to the
repository.

If the implementation and docs disagree, either fix the docs or correct the
implementation before requesting review. Mention known limitations explicitly,
especially where the real Backend/Kernel/Frontend path is not available yet.

## Branches and commits

Use a descriptive branch name, for example:

```text
fix/failed-extension-cleanup
feature/config-validation
docs/first-run-guide
```

Keep commits focused and write commit messages that state the change. A prefix
such as `fix:`, `feat:`, `test:`, `docs:` or `refactor:` is encouraged but not
required. Do not include generated build output, temporary files, local editor
settings or unrelated changes.

## Versioning and releases

Do not edit `lua/cdin/runtime/core/version.lua` just to change the Runtime version.
In a Git checkout, that module reads the nearest matching `v...` tag and derives
its development version from the number of commits since the tag. At the tagged
commit, `v1.2.3` is reported as `1.2.3`; later commits produce a development
version that also includes the short commit hash.

For a release:

1. Add a section for the intended version to `CHANGELOG.md`.
2. Create and push a tag using the `vMAJOR.MINOR.PATCH` format, or a supported
   prerelease tag such as `v1.2.3-rc.1`.
3. Let the Release workflow verify that the tag-derived version matches the
   changelog before it creates the source archives.

The workflow adds generated release metadata to the archives because release
archives do not contain the `.git` directory. That generated module is not part
of the source tree and should not be committed. There is no top-level `VERSION`
file to keep in sync. `CDIN_RUNTIME_VERSION` can be set by a downstream build
system when an explicit override is necessary.

## Open a pull request

1. Push your branch to your fork and open a pull request against the project's
   default branch.
2. Explain the problem and the behavior your change introduces or corrects.
3. Link the related issue, if there is one, and call out any API or compatibility
   implications.
4. List the commands you ran and their results. If a test could not be run,
   say so rather than implying it passed.
5. Keep the pull request focused and respond to review comments with either a
   change or a clear technical explanation.

The pull request template is there to help reviewers understand scope, tests
and limitations. You do not need to fill sections with boilerplate when they
truly do not apply; write "Not applicable" and explain briefly if needed.

## Review and merge

CI runs the unit and simulated-Host integration tests across the supported
matrix. A passing CI run is required evidence, but it does not replace a review
of correctness, boundaries, readability and compatibility with the shared
specification. Maintainers may ask for a smaller diff, more tests, a spec change
or a separate issue before merging a broader design.

Do not merge your own pull request unless the maintainers have explicitly
configured the project to allow it. Do not force-push over another contributor's
work or commit to the main branch without authorization.

## Security issues

Do not report a suspected vulnerability in a public issue. Follow the private
reporting instructions in [SECURITY.md](SECURITY.md). Please include enough
information to understand the affected boundary and reproduce the behavior,
but avoid posting exploit details publicly before a fix is available.

Thank you for helping keep CDIN Runtime small, understandable and dependable.
