# Architecture

CDIN is split into a few parts so that editor behavior does not depend on one
specific window system or operating system.

## The main parts

| Part | Responsibility |
| --- | --- |
| Frontend | Displays text and controls, and sends user input. |
| Runtime | Maps input to commands, manages views and settings, and describes UI state. |
| Backend | Provides Runtime services and forwards document requests to the Kernel. |
| Kernel | Manages document text, edits, versions, snapshots and undo/redo. |

In a complete CDIN application, the Frontend communicates through the Backend.
Runtime asks the Backend for document work; the Backend is the only part that
calls the Kernel. This keeps window code out of Runtime and editor policy out of
the Kernel.

## What belongs in Runtime?

Runtime contains the behavior that should be shared by different frontends:

- commands and key bindings;
- views, selections and focus state;
- settings and project context;
- syntax, theme and style registries;
- extension registration and cleanup;
- a data-only description of the UI.

Runtime keeps document handles and small pieces of metadata. The Kernel remains
the source of truth for document content and edit history. The Frontend decides
how to draw the UI, including pixel positions, font shaping and line wrapping.

## Code layout

- `core/` — errors, events and basic Runtime utilities.
- `host/` — checks that the supplied Host has the required services.
- `document/` — document client, edits, snapshots and save flow.
- `command/` and `input/` — commands and key bindings.
- `config/` and `workspace/` — settings and project context.
- `presentation/` — views, UI state, themes, styles and syntax rules.
- `extension/` — extension loading and cleanup.
- `application.lua` — creates the parts and manages Runtime startup/shutdown.
- `core/log.lua` — the logging facade. Records go to `host:log`, then through the
  Backend to the Kernel's one logger; Runtime owns no logger and prints nothing.

## Current implementation

The Backend bridge now provides a bounded `cdin.ui-model.v1` projection, owner-thread
inbound event dispatch, and version-pinned line-window reads through the Host API.
The production Kernel adapter and Frontend Protocol implementation are present in
the companion Backend source snapshot. This Runtime patch and FakeHost tests verify
the Lua side; a live Lua 5.4 + Kernel + Backend build and the OS matrix remain
release gates and must not be inferred from FakeHost tests.

See the [CDIN Specification](https://github.com/cdin-editor/spec) for the
cross-project design.
