local errors = require("cdin.runtime.core.error")
local M = {}
local PREFIX = "CDINSEL1;"

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
function M.encode(selection)
  return PREFIX .. tostring(selection.anchor) .. ";" .. tostring(selection.caret)
end

function M.decode(blob)
  if type(blob) ~= "string" or blob:sub(1, #PREFIX) ~= PREFIX then
    errors.raise("INVALID_ARGUMENT", "unknown selection snapshot format")
  end
  local anchor, caret = blob:sub(#PREFIX + 1):match("^(%d+);(%d+)$")
  if not anchor then errors.raise("INVALID_ARGUMENT", "malformed selection snapshot") end
  return M.new(tonumber(anchor), tonumber(caret))
end

return M
