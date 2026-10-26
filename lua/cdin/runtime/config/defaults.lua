local M = {}

local function one_of(...)
  local allowed = { ... }
  return function(value)
    for _, item in ipairs(allowed) do
      if value == item then
        return true
      end
    end
    return false, "expected one of: " .. table.concat(allowed, ", ")
  end
end

local function is_integer_between(minimum, maximum)
  return function(value)
    local valid = type(value) == "number"
      and value >= minimum
      and value <= maximum
      and value % 1 == 0
    return valid, string.format("expected integer %d..%d", minimum, maximum)
  end
end

local function is_boolean(value)
  return type(value) == "boolean", "expected boolean"
end

local function is_non_empty_string(value)
  return type(value) == "string" and value ~= "", "expected non-empty string"
end

M.schema = {
  ["editor.tab_width"] = {
    validate = is_integer_between(1, 32),
    default = 4,
  },
  ["editor.insert_spaces"] = {
    validate = is_boolean,
    default = true,
  },
  ["editor.line_numbers"] = {
    validate = is_boolean,
    default = true,
  },
  ["editor.wrap"] = {
    validate = one_of("none", "soft", "word"),
    default = "none",
  },
  ["ui.theme"] = {
    validate = is_non_empty_string,
    default = "default",
  },
}

function M.new_store()
  local Store = require("cdin.runtime.config.store")
  local schema = {}
  local defaults = {}

  for path, definition in pairs(M.schema) do
    schema[path] = definition
    defaults[path] = definition.default
  end

  return Store.new(schema, defaults)
end

return M
