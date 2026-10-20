-- Reusable named registry with deterministic enumeration and explicit override policy.
local Errors = require "core.runtime.errors"
local Registry = {}
Registry.__index = Registry

function Registry.new(options)
  options = options or {}
  return setmetatable({
    _entries = {},
    _count = 0,
    _label = options.label or "entry",
  }, Registry)
end

function Registry:register(name, value, overwrite)
  if type(name) ~= "string" or name == "" then
    return nil, Errors.new("INVALID_ARGUMENT", "registry name must be a non-empty string")
  end
  if value == nil then
    return nil, Errors.new("INVALID_ARGUMENT", "registry value must not be nil", { name = name })
  end
  if self._entries[name] ~= nil and overwrite ~= true then
    return nil, Errors.new("DUPLICATE_REGISTRATION", self._label .. " already exists: " .. name, { name = name })
  end
  if self._entries[name] == nil then self._count = self._count + 1 end
  self._entries[name] = value
  return true
end

function Registry:get(name) return self._entries[name] end
function Registry:has(name) return self._entries[name] ~= nil end
function Registry:count() return self._count end

function Registry:unregister(name)
  if self._entries[name] == nil then return false end
  self._entries[name] = nil
  self._count = self._count - 1
  return true
end

function Registry:names()
  local names = {}
  for name in pairs(self._entries) do names[#names + 1] = name end
  table.sort(names)
  return names
end

function Registry:clear()
  self._entries = {}
  self._count = 0
end

return Registry
