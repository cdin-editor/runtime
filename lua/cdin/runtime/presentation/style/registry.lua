local errors = require("cdin.runtime.core.error")
local tablex = require("cdin.runtime.util.tablex")

local Registry = {}
Registry.__index = Registry

function Registry.new()
  return setmetatable({
    roles = {},
    next_id = 0,
  }, Registry)
end

function Registry:define(name, options)
  options = options or {}
  if type(name) ~= "string" or name == "" then
    errors.raise("INVALID_ARGUMENT", "style role name is required")
  end
  if self.roles[name] then
    errors.raise("DUPLICATE_REGISTRATION", "style role already exists: " .. name)
  end

  self.next_id = self.next_id + 1
  local role = {
    id = self.next_id,
    name = name,
    description = options.description,
    category = options.category or "general",
  }
  self.roles[name] = role
  return tablex.copy(role)
end

function Registry:get(name)
  local role = self.roles[name]
  return role and tablex.copy(role) or nil
end

function Registry:has(name)
  return self.roles[name] ~= nil
end

function Registry:list()
  local result = {}
  for _, role in pairs(self.roles) do
    result[#result + 1] = tablex.copy(role)
  end
  table.sort(result, function(a, b)
    return a.name < b.name
  end)
  return result
end

return Registry
