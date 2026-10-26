local errors = require("cdin.runtime.core.error")

-- This is a wrapper around an opaque transaction owned by the Kernel. Only
-- the Kernel holds tentative text; Runtime tracks leases and edit offsets.
local Transaction = {}
Transaction.__index = Transaction

function Transaction.new(options)
  return setmetatable({
    host = options.host,
    handle = options.handle,
    document = options.document,
    base_version = options.base_version,
    state = "active",
    id = options.id,
    edits = {},
  }, Transaction)
end

function Transaction:_assert_active()
  if self.state ~= "active" then
    errors.raise("INVALID_STATE", "transaction is not active", {
      state = self.state,
    })
  end
end

function Transaction:replace(start_offset, end_offset, bytes)
  self:_assert_active()
  if type(start_offset) ~= "number"
      or type(end_offset) ~= "number"
      or type(bytes) ~= "string"
      or start_offset < 0
      or end_offset < start_offset
      or start_offset % 1 ~= 0
      or end_offset % 1 ~= 0 then
    errors.raise("INVALID_ARGUMENT", "invalid transaction replacement")
  end

  local result = self.host.documents:transaction_replace(self.handle, {
    expected_version = nil,
    start = start_offset,
    finish = end_offset,
    bytes = bytes,
    coalesce_key = 0,
    undo_blob_before = "",
    undo_blob_after = "",
  })
  self.edits[#self.edits + 1] = {
    start = start_offset,
    removed = end_offset - start_offset,
    inserted = #bytes,
  }
  return result
end

function Transaction:read(start_offset, length)
  self:_assert_active()
  if type(start_offset) ~= "number"
      or type(length) ~= "number"
      or start_offset < 0
      or length < 0
      or start_offset % 1 ~= 0
      or length % 1 ~= 0 then
    errors.raise("INVALID_ARGUMENT", "transaction read range must use non-negative integer offsets")
  end

  local result = self.host.documents:transaction_read(self.handle, {
    start = start_offset,
    length = length,
  })
  if type(result) ~= "table" or type(result.bytes) ~= "string" then
    errors.raise("INTERNAL", "transaction read returned invalid data")
  end

  return result.bytes, { length = result.total_length }
end

function Transaction:commit(options)
  self:_assert_active()
  options = options or {}

  local result = self.host.documents:commit_transaction(self.handle, {
    undo_blob_before = options.undo_blob_before or "",
    undo_blob_after = options.undo_blob_after or "",
  })

  self.state = "committed"
  self.handle = nil
  self.document.active_transactions[self.id] = nil

  if type(result) ~= "table" then
    errors.raise("INTERNAL", "transaction commit returned an invalid result")
  end
  if type(result.version) ~= "number" or type(result.new_length) ~= "number" then
    errors.raise("INTERNAL", "transaction commit result misses version/new_length")
  end

  self.document.version = result.version
  self.document.length = result.new_length
  self.document:_emit("document.changed", {
    document_id = self.document.id,
    version = self.document.version,
    history = "transaction",
    result = result,
    edits = self.edits,
    edits_coordinate = "sequential",
  })
  return result
end

function Transaction:abort()
  if self.state ~= "active" then
    return false
  end

  local ok, failure = pcall(
    self.host.documents.abort_transaction,
    self.host.documents,
    self.handle
  )
  self.state = "aborted"
  self.handle = nil
  self.document.active_transactions[self.id] = nil

  if not ok then
    error(errors.normalize(failure, "INTERNAL", "abort transaction"), 0)
  end
  return true
end

return Transaction
