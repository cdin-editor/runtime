local errors = require("cdin.runtime.core.error")
local tablex = require("cdin.runtime.util.tablex")

local Registry = {}
Registry.__index = Registry

function Registry.new(style_registry)
  return setmetatable({
    styles = style_registry,
    themes = {},
    active = "default",
  }, Registry)
end

function Registry:register(name, theme, options)
  options = options or {}
  if type(name) ~= "string" or name == "" or type(theme) ~= "table" then
    errors.raise("INVALID_ARGUMENT", "theme requires a name and a style map")
  end
  if self.themes[name] and not options.overwrite then
    errors.raise("DUPLICATE_REGISTRATION", "theme already exists: " .. name)
  end

  local copied = tablex.copy(theme)
  for role_name, style in pairs(copied) do
    if not self.styles:has(role_name) then
      errors.raise("INVALID_ARGUMENT", "theme references unknown style role", {
        role = role_name,
      })
    end
    if type(style) ~= "table" then
      errors.raise("INVALID_ARGUMENT", "theme style role must map to a table", {
        role = role_name,
      })
    end
  end

  self.themes[name] = {
    styles = copied,
    owner = options.owner or "core",
  }
  return true
end

function Registry:remove(name, owner)
  local entry = self.themes[name]
  if not entry or (owner and owner ~= entry.owner) then
    return false
  end

  self.themes[name] = nil
  if self.active == name then
    self.active = "default"
  end
  return true
end

function Registry:activate(name)
  if not self.themes[name] then
    errors.raise("NOT_FOUND", "no such theme: " .. name, { name = name })
  end
  self.active = name
  return self:snapshot()
end

function Registry:snapshot()
  local theme = self.themes[self.active]
  return {
    name = self.active,
    styles = theme and tablex.copy(theme.styles) or {},
  }
end

function Registry:list()
  local names = {}
  for name in pairs(self.themes) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

return Registry
