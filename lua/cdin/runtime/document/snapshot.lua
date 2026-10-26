local errors = require("cdin.runtime.core.error")

-- A snapshot pins one Kernel document version until close(). It exposes reads,
-- but never retains the returned document bytes.
local Snapshot = {}
Snapshot.__index = Snapshot

function Snapshot.new(host, handle, version, length, on_close)
  return setmetatable({
    host = host,
    handle = handle,
    version = version,
    length = length,
    state = "open",
    on_close = on_close,
  }, Snapshot)
end

function Snapshot:read(start_offset, length)
  if self.state ~= "open" then
    errors.raise("INVALID_HANDLE", "snapshot is closed")
  end
  if type(start_offset) ~= "number"
      or type(length) ~= "number"
      or start_offset < 0
      or length < 0
      or start_offset % 1 ~= 0
      or length % 1 ~= 0 then
    errors.raise("INVALID_ARGUMENT", "snapshot range must use non-negative integer byte offsets")
  end
  if start_offset > self.length then
    errors.raise("OUT_OF_RANGE", "snapshot read starts past the snapshot end", {
      requested = start_offset,
      length = self.length,
    })
  end

  local result = self.host.documents:read_snapshot(self.handle, {
    start = start_offset,
    length = length,
  })
  if type(result) ~= "table" or type(result.bytes) ~= "string" then
    errors.raise("INTERNAL", "snapshot read returned invalid data")
  end
  if result.version ~= nil and result.version ~= self.version then
    errors.raise("INTERNAL", "snapshot service violated version pinning", {
      expected = self.version,
      actual = result.version,
    })
  end
  if #result.bytes > length then
    errors.raise("INTERNAL", "snapshot service returned more bytes than requested", {
      requested = length,
      returned = #result.bytes,
    })
  end

  return result.bytes
end

function Snapshot:close()
  if self.state ~= "open" then
    return false
  end

  self.state = "closing"
  local ok, failure = pcall(
    self.host.documents.release_snapshot,
    self.host.documents,
    self.handle
  )
  self.handle = nil
  self.state = "closed"
  if self.on_close then
    self.on_close(self)
  end

  if not ok then
    error(errors.normalize(failure, "INTERNAL", "release snapshot"), 0)
  end
  return true
end

function Snapshot:with(callback)
  if type(callback) ~= "function" then
    errors.raise("INVALID_ARGUMENT", "snapshot callback must be a function")
  end

  local result = table.pack(pcall(callback, self))
  local close_ok, close_error = pcall(self.close, self)
  if not result[1] then
    error(errors.normalize(result[2]), 0)
  end
  if not close_ok then
    error(errors.normalize(close_error), 0)
  end

  return table.unpack(result, 2, result.n)
end

return Snapshot
