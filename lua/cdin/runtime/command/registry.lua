local errors = require("cdin.runtime.core.error")
local Registry = {}
Registry.__index = Registry

function Registry.new()
  return setmetatable({ entries = {}, closed = false }, Registry)
end

function Registry:register(name, handler, options)
  options = options or {}
  if self.closed then errors.raise("SHUTDOWN", "command registry is closed") end
  if type(name) ~= "string" or name == "" or type(handler) ~= "function" then
    errors.raise("INVALID_ARGUMENT", "command requires a non-empty name and handler")
  end
  if options.available ~= nil and type(options.available) ~= "function" then
    errors.raise("INVALID_ARGUMENT", "command availability predicate must be a function")
  end
  if self.entries[name] and not options.overwrite then
    errors.raise("DUPLICATE_REGISTRATION", "command already exists: " .. name, { name = name })
  end
  local entry = { name = name, handler = handler, owner = options.owner or "core",
    description = options.description, available = options.available }
  self.entries[name] = entry
  return entry
end

function Registry:remove(name, owner)
  local entry = self.entries[name]
  if not entry or (owner ~= nil and entry.owner ~= owner) then return false end
  self.entries[name] = nil
  return true
end

function Registry:remove_owner(owner)
  local removed = 0
  for name, entry in pairs(self.entries) do
    if entry.owner == owner then self.entries[name] = nil; removed = removed + 1 end
  end
  return removed
end

function Registry:get(name) return self.entries[name] end

function Registry:can_execute(name, context, args)
  local entry = self.entries[name]
  if not entry then return false end
  if not entry.available then return true end
  local ok, available = pcall(entry.available, context, args)
  return ok and available == true
end

function Registry:execute(name, context, args)
  local entry = self.entries[name]
  if not entry then errors.raise("NOT_FOUND", "no such command: " .. tostring(name), { name = name }) end
  if entry.available and not self:can_execute(name, context, args) then return false, "unavailable" end
  local ok, result = pcall(entry.handler, context or {}, args or {})
  if not ok then error(errors.normalize(result, "INTERNAL", "command:" .. name), 0) end
  return true, result
end

function Registry:list()
  local result = {}
  for name, entry in pairs(self.entries) do
    result[#result + 1] = { name = name, owner = entry.owner, description = entry.description }
  end
  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

function Registry:close() self.closed = true; self.entries = {} end
return Registry
