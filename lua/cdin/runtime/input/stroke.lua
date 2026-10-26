local errors = require("cdin.runtime.core.error")

local Stroke = {}

local modifier_order = { "ctrl", "alt", "altgr", "shift" }
local modifier_aliases = {
  ["left ctrl"] = "ctrl",
  ["right ctrl"] = "ctrl",
  ["left shift"] = "shift",
  ["right shift"] = "shift",
  ["left alt"] = "alt",
  ["right alt"] = "altgr",
}
local modifier_keys = {
  ["left ctrl"] = true,
  ["right ctrl"] = true,
  ["left shift"] = true,
  ["right shift"] = true,
  ["left alt"] = true,
  ["right alt"] = true,
  ctrl = true,
  shift = true,
  alt = true,
  altgr = true,
}

local function add_modifier(set, name)
  name = tostring(name):lower()
  local canonical = modifier_aliases[name] or name
  if canonical == "ctrl"
      or canonical == "alt"
      or canonical == "altgr"
      or canonical == "shift" then
    set[canonical] = true
  end
end

function Stroke.from_event(event)
  if type(event) ~= "table" then
    errors.raise("INVALID_ARGUMENT", "raw key event must be a table")
  end
  if event.kind and event.kind ~= "key_down" and event.kind ~= "key_pressed" then
    return nil, "not-key-down"
  end
  if type(event.key) ~= "string" or event.key == "" then
    errors.raise("INVALID_ARGUMENT", "raw key event must include key")
  end

  local key = event.key:lower()
  if modifier_keys[key] then
    return nil, "modifier-only"
  end

  local modifiers = {}
  if type(event.modifiers) == "table" then
    for name, enabled in pairs(event.modifiers) do
      if type(name) == "number" then
        if enabled then
          add_modifier(modifiers, enabled)
        end
      elseif enabled then
        add_modifier(modifiers, name)
      end
    end
  end

  -- Some platforms report AltGr as Ctrl+Alt. Treat it as one modifier.
  if modifiers.altgr then
    modifiers.ctrl = nil
    modifiers.alt = nil
  end

  local parts = {}
  for _, name in ipairs(modifier_order) do
    if modifiers[name] then
      parts[#parts + 1] = name
    end
  end
  parts[#parts + 1] = key
  return table.concat(parts, "+")
end

return Stroke
