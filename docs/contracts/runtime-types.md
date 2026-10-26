# Runtime data types and ownership

These Lua shapes are provisional and are intentionally smaller than native
Kernel structures. They describe Runtime-facing data only.

## Document client

```lua
{
  id = "doc-1",        -- Runtime-local identifier, not a Kernel handle
  handle = opaque,      -- Backend-created Host handle
  version = 12,         -- last observed Kernel version
  length = 512,         -- byte length at that version
  path = "file.txt",    -- optional metadata
  state = "open",
}
```

The client must never add `bytes`, `lines`, `undo_stack` or `redo_stack` fields.
Transient bytes can exist in a local variable during a read or save operation,
but they are not retained as canonical document state.

## Edit coordinate convention

- Every offset is zero-based and measured in bytes.
- Ranges are half-open: `[start, finish)`.
- A single edit result describes `{ start, removed, inserted }`.
- A batch request uses sorted, non-overlapping ranges against the same original
  document version; when transforming selections, process those edits from the
  highest start offset to the lowest.
- Notification edit sequences may use sequential coordinates. The Backend must
  mark coordinate convention explicitly when it cannot use the default.

## View and selection

```lua
{
  id = "view-1",
  document_id = "doc-1",
  selection = { anchor = 18, caret = 24 },
  scroll_anchor = 0,
  focused = true,
  visible = true,
  revision = 3,
}
```

The view owns the selection and logical scroll anchor. The UI model's `layout`
field is a logical split tree with IDs and ratios. It does not contain pixels,
rectangles, line wrapping or glyph shaping. The implementation lives in
`presentation/ui/pane_tree.lua` to make this distinction clear in the source.

## UI model

The published model uses `schema = "cdin.ui-model.v1"`, a monotonically
increasing `revision`, view snapshots, logical layout, focus, panels, prompt,
status data and a theme identifier. UI models must be serializable: do not put
functions, userdata, cycles, Host handles or document bytes inside them.

## Opaque selection-history blob

The built-in selection encoding is a small versioned byte string passed through
to Kernel history as caller metadata. Kernel stores it but does not interpret
it. If the encoding changes, the Runtime must decode old versions safely and
must not assume every blob originates from the current Runtime build.
