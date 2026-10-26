local errors = require("cdin.runtime.core.error")
local Selection = require("cdin.runtime.presentation.ui.selection")
-- RT-008 | Reference: https://github.com/cdin-editor/spec
-- A view is one editing surface over a Kernel document. Several views can
-- refer to the same document while keeping different selections and scroll anchors.
local View = {}
View.__index = View

function View.new(options)
  options = options or {}
  if type(options.id) ~= "string" or options.id == "" or type(options.document_id) ~= "string" then
    errors.raise("INVALID_ARGUMENT", "view id and document id are required")
  end
  return setmetatable({ id = options.id, document_id = options.document_id,
    selection = Selection.new(0, 0), scroll_anchor = 0, focused = false,
    visible = true, revision = 0 }, View)
end

function View:set_selection(anchor, caret)
  self.selection = Selection.new(anchor, caret)
  self.revision = self.revision + 1
end

function View:set_cursor(offset)
  self:set_selection(offset, offset)
end

function View:selection_blob()
  return Selection.encode(self.selection, self.scroll_anchor)
end

function View:restore_selection_blob(blob)
  local selection, scroll_anchor = Selection.decode(blob)
  self:set_selection(selection.anchor, selection.caret)
  self.scroll_anchor = scroll_anchor
end

function View:clamp_selection(length)
  local anchor = math.min(self.selection.anchor, length)
  local caret = math.min(self.selection.caret, length)
  self:set_selection(anchor, caret)
end

local function transform_offset(offset, edit)
  local start = edit.start
  local removed = edit.removed or 0
  local inserted = edit.inserted or 0
  local finish = start + removed
  if offset < start then return offset end
  if removed == 0 then return offset + inserted end
  if offset == start then return start end -- left affinity at replacement start
  if offset > finish then return offset + inserted - removed end
  -- Positions inside or at the end of removed text map to the end of the
  -- replacement. Insertions use right affinity above.
  return start + inserted
end

function View:apply_edit(edit)
  if type(edit) ~= "table" or type(edit.start) ~= "number"
      or type(edit.removed) ~= "number" or type(edit.inserted) ~= "number"
      or edit.start < 0 or edit.removed < 0 or edit.inserted < 0 then
    errors.raise("INVALID_ARGUMENT", "view edit transformation is malformed")
  end
  local anchor = transform_offset(self.selection.anchor, edit)
  local caret = transform_offset(self.selection.caret, edit)
  local scroll_anchor = transform_offset(self.scroll_anchor, edit)
  self:set_selection(anchor, caret)
  self.scroll_anchor = scroll_anchor
end

function View:replace_selection(document, bytes, options)
  if type(bytes) ~= "string" then errors.raise("INVALID_ARGUMENT", "inserted bytes must be a string") end
  local start_offset, end_offset = Selection.range(self.selection)
  local before = self:selection_blob()
  local result = document:replace(start_offset, end_offset, bytes, {
    expected_version = options and options.expected_version,
    coalesce_key = options and options.coalesce_key or 0,
    undo_blob_before = before,
    undo_blob_after = Selection.encode({ anchor = start_offset + #bytes, caret = start_offset + #bytes }, self.scroll_anchor),
  })
  self:set_cursor(start_offset + #bytes)
  return result
end

function View:snapshot()
  return { id = self.id, document_id = self.document_id,
    selection = { anchor = self.selection.anchor, caret = self.selection.caret },
    scroll_anchor = self.scroll_anchor, focused = self.focused, visible = self.visible, revision = self.revision }
end
return View
