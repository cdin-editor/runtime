local errors = require("cdin.runtime.core.error")

local Bus = {}
Bus.__index = Bus

function Bus.new()
  return setmetatable({ listeners = {}, next_id = 0, closed = false }, Bus)
end

function Bus:on(name, callback, owner)
  if self.closed then errors.raise("SHUTDOWN", "event bus is closed") end
  if type(name) ~= "string" or name == "" or type(callback) ~= "function" then
    errors.raise("INVALID_ARGUMENT", "event name and callback are required")
  end
  self.next_id = self.next_id + 1
  local token = { id = self.next_id, event = name, owner = owner, active = true }
  local list = self.listeners[name] or {}
  self.listeners[name] = list
  list[#list + 1] = { token = token, callback = callback }
  return token
end

function Bus:off(token)
  if type(token) ~= "table" or not token.active then return false end
  token.active = false
  local list = self.listeners[token.event]
  if list then
    for index = #list, 1, -1 do
      if list[index].token == token then table.remove(list, index); break end
    end
    if #list == 0 then self.listeners[token.event] = nil end
  end
  return true
end

function Bus:off_owner(owner)
  local removed = 0
  for event_name, list in pairs(self.listeners) do
    local kept = {}
    for _, listener in ipairs(list) do
      if listener.token.owner == owner then
        listener.token.active = false
        removed = removed + 1
      else
        kept[#kept + 1] = listener
      end
    end
    self.listeners[event_name] = #kept > 0 and kept or nil
  end
  return removed
end

function Bus:emit(name, payload)
  if self.closed then return {} end
  local list = self.listeners[name] or {}
  local snapshot, failures = {}, {}
  for index, listener in ipairs(list) do snapshot[index] = listener end
  for _, listener in ipairs(snapshot) do
    if listener.token.active then
      local ok, err = pcall(listener.callback, payload)
      if not ok then failures[#failures + 1] = errors.normalize(err, "INTERNAL", "event:" .. name) end
    end
  end
  return failures
end

function Bus:close()
  self.closed = true
  for _, list in pairs(self.listeners) do
    for _, listener in ipairs(list) do listener.token.active = false end
  end
  self.listeners = {}
end

return Bus
