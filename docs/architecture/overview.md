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

## Current implementation

The Lua modules and simulated-Host tests are present. The production Backend
adapter, live Kernel integration and Frontend Protocol connection are not yet
included, so the architecture above describes the intended connection between
components, not a fully integrated editor today.

See the [CDIN Specification](https://github.com/cdin-editor/spec) for the
cross-project design.
