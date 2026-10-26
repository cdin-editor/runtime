local errors = require("cdin.runtime.core.error")
local M = {}
local PREFIX_V1 = "CDINSEL1;"
local PREFIX_V2 = "CDINSEL2;"

function M.new(anchor, caret)
  anchor, caret = anchor or 0, caret or anchor or 0
  if type(anchor) ~= "number" or type(caret) ~= "number" or anchor < 0 or caret < 0
      or anchor % 1 ~= 0 or caret % 1 ~= 0 then
    errors.raise("INVALID_ARGUMENT", "selection offsets must be non-negative integer byte offsets")
  end
  return { anchor = anchor, caret = caret }
end

function M.range(selection)
  local a, b = selection.anchor, selection.caret
  return math.min(a, b), math.max(a, b)
end

function M.is_empty(selection) return selection.anchor == selection.caret end
function M.cursor(selection) return selection.caret end

-- Stable opaque caller metadata for Kernel undo units. It stores view state only,
-- not document content. Keep the format versioned because the Kernel preserves it.
-- RT-008 | Reference: https://github.com/cdin-editor/spec
-- V2 includes the view's scroll anchor while retaining V1 decode compatibility.
-- The opaque blob remains metadata only; document bytes stay owned by Kernel.
function M.encode(selection, scroll_anchor)
  scroll_anchor = scroll_anchor or 0
  if type(scroll_anchor) ~= "number" or scroll_anchor < 0 or scroll_anchor % 1 ~= 0 then
    errors.raise("INVALID_ARGUMENT", "scroll anchor must be a non-negative integer")
  end
  return PREFIX_V2 .. tostring(selection.anchor) .. ";" .. tostring(selection.caret)
    .. ";" .. tostring(scroll_anchor)
end

function M.decode(blob)
  if type(blob) ~= "string" then
    errors.raise("INVALID_ARGUMENT", "unknown selection snapshot format")
  end
  if blob:sub(1, #PREFIX_V2) == PREFIX_V2 then
    local anchor, caret, scroll = blob:sub(#PREFIX_V2 + 1):match("^(%d+);(%d+);(%d+)$")
    if not anchor then errors.raise("INVALID_ARGUMENT", "malformed selection snapshot") end
    return M.new(tonumber(anchor), tonumber(caret)), tonumber(scroll)
  end
  if blob:sub(1, #PREFIX_V1) == PREFIX_V1 then
    local anchor, caret = blob:sub(#PREFIX_V1 + 1):match("^(%d+);(%d+)$")
    if not anchor then errors.raise("INVALID_ARGUMENT", "malformed selection snapshot") end
    return M.new(tonumber(anchor), tonumber(caret)), 0
  end
  errors.raise("INVALID_ARGUMENT", "unknown selection snapshot format")
end

return M
