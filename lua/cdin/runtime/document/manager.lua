local errors = require("cdin.runtime.core.error")
local Client = require("cdin.runtime.document.client")

-- Owns live Lua clients. The Backend/Kernel owns every underlying document.
local Manager = {}
Manager.__index = Manager

function Manager.new(host, event_bus)
  return setmetatable({
    host = host,
    event_bus = event_bus,
    documents = {},
    next_id = 0,
    closed = false,
  }, Manager)
end

function Manager:open(initial_bytes, options)
  if self.closed then
    errors.raise("SHUTDOWN", "document manager is closed")
  end
  if type(initial_bytes) ~= "string" then
    errors.raise("INVALID_ARGUMENT", "initial document bytes must be a string")
  end
  options = options or {}

  local created = self.host.documents:create(initial_bytes, {
    path = options.path,
  })
  local valid_metadata = type(created) == "table"
    and created.handle ~= nil
    and type(created.version) == "number"
    and type(created.length) == "number"
    and created.version >= 0
    and created.length >= 0
  if not valid_metadata then
    if type(created) == "table" and created.handle ~= nil then
      pcall(self.host.documents.close, self.host.documents, created.handle)
    end
    errors.raise("INTERNAL", "host document create returned invalid handle/version/length metadata")
  end

  if created.length ~= #initial_bytes then
    pcall(self.host.documents.close, self.host.documents, created.handle)
    errors.raise("INTERNAL", "host document length does not match initial bytes", {
      expected = #initial_bytes,
      actual = created.length,
    })
  end

  self.next_id = self.next_id + 1
  local ok, subscription_result = pcall(
    self.host.documents.subscribe,
    self.host.documents,
    created.handle
  )
  if not ok then
    pcall(self.host.documents.close, self.host.documents, created.handle)
    error(errors.normalize(subscription_result, "INTERNAL", "subscribe document notifications"), 0)
  end
  if type(subscription_result) ~= "table" or subscription_result.handle == nil then
    pcall(self.host.documents.close, self.host.documents, created.handle)
    errors.raise("INTERNAL", "host document subscribe returned no opaque handle")
  end

  local subscription = subscription_result.handle
  if type(subscription_result.version) == "number"
      and subscription_result.version ~= created.version then
    -- A new document must not change between create and subscribe. If it does,
    -- the Host implementation is not honoring the documented lifecycle.
    pcall(self.host.documents.unsubscribe, self.host.documents, subscription)
    pcall(self.host.documents.close, self.host.documents, created.handle)
    errors.raise("HOST_API_MISMATCH", "document changed between create and subscribe", {
      created_version = created.version,
      subscribed_version = subscription_result.version,
    })
  end

  local document = Client.new({
    host = self.host,
    handle = created.handle,
    id = "doc-" .. self.next_id,
    version = created.version,
    length = created.length,
    path = options.path,
    subscription = subscription,
    events = self.event_bus,
  })
  self.documents[document.id] = document
  self.event_bus:emit("document.opened", {
    document_id = document.id,
    path = document.path,
    version = document.version,
  })
  return document
end

function Manager:forget_closed(id)
  if not self.documents[id] then
    return false
  end

  self.documents[id] = nil
  self.event_bus:emit("document.closed", {
    document_id = id,
    external = true,
  })
  return true
end

function Manager:get(id)
  local document = self.documents[id]
  if not document then
    errors.raise("NOT_FOUND", "no such runtime document: " .. tostring(id), {
      document_id = id,
    })
  end
  return document
end

function Manager:close(id)
  local document = self:get(id)
  local ok, result = pcall(document.close, document)

  -- The Host handle is invalidated even when cleanup reports an error. Never
  -- let callers reuse a Lua client after the close attempt.
  self.documents[id] = nil
  self.event_bus:emit("document.closed", { document_id = id })
  if not ok then
    error(errors.normalize(result, "INTERNAL", "close document " .. id), 0)
  end
  return result
end

function Manager:close_all()
  local failures = {}
  for id, document in pairs(self.documents) do
    local ok, failure = pcall(document.close, document)
    if not ok then
      failures[#failures + 1] = errors.normalize(failure, "INTERNAL", "close document " .. id)
    end
    self.documents[id] = nil
  end
  return failures
end

function Manager:list()
  local result = {}
  for id, document in pairs(self.documents) do
    result[#result + 1] = {
      id = id,
      version = document.version,
      length = document.length,
      path = document.path,
      state = document.state,
    }
  end
  table.sort(result, function(a, b)
    return a.id < b.id
  end)
  return result
end

function Manager:shutdown()
  self.closed = true
  return self:close_all()
end

return Manager
