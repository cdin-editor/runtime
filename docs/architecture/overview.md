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

Runtime implements the Lua side of Host API `0.3.0` and Frontend Protocol `0.2.0`:
version-pinned line windows, semantic UI metadata, bounded model snapshots, and
owner-thread Frontend event dispatch. The companion Backend repository provides
the production PUC Lua 5.4 C bridge and Kernel adapter. FakeHost tests verify the
Runtime behavior; the Backend's live integration workflow is the release gate
for the real Lua 5.4 + Kernel + Backend path. Concrete out-of-process transports
and the GUI are separate deliverables.

See the [CDIN Specification](https://github.com/cdin-editor/spec) for the
cross-project design.
