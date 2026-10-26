# Notes for Runtime changes

The Runtime implements editor behavior; it is not a second document engine or a
frontend. Keep these rules in mind when changing code.

1. Follow the [CDIN Specification](https://github.com/cdin-editor/spec). If it
   conflicts with this repository, the Specification wins.
2. The Kernel owns canonical document bytes, versions and undo/redo history.
   Runtime stores only opaque handles, small metadata and temporary read results.
3. Runtime calls document services only through the Backend-provided Host API.
   Do not import Kernel headers, private Kernel symbols, SDL or OS APIs here.
4. Lua code runs on one owner thread. Worker threads must never enter the Lua
   state directly.
5. Keep UI data semantic. Runtime may describe views and pane relationships,
   but it must not decide pixel positions, wrap lines, shape text or render.
6. Give every resource a clear owner and release path. Use explicit `close()`;
   garbage collection is a fallback, not the primary lifetime contract.
7. Keep buffers, histories, caches and queues bounded where the component owns
   them. Never keep a shadow copy of a Kernel document.
8. Use structured errors with stable codes. Do not make callers parse messages.
9. Extensions receive only the capabilities granted by their facade. Do not
   expose `io`, `os`, `debug`, native handles or Backend internals by default.
10. Keep modules small enough to follow. Explain ownership and non-obvious
    control flow in comments; avoid comments that merely restate a line of code.
11. Write public guides for someone who is new to CDIN. Explain the purpose
    first, then introduce API names. Put low-level details in contract pages.
12. Do not claim real Kernel or Frontend integration based on fake-Host tests.
