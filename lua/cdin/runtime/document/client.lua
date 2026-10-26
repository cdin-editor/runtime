local errors = require("cdin.runtime.core.error")
local Snapshot = require("cdin.runtime.document.snapshot")
local Transaction = require("cdin.runtime.document.transaction")
-- Thin client for a single Backend-owned document handle. The Kernel owns the
-- bytes, versioned state and history; this object owns only metadata, a
-- notification subscription and the snapshot/transaction leases it opens.
local Client = {}
Client.__index = Client

local function check_result(value, operation)
  if type(value) ~= "table" then
    errors.raise("INTERNAL", "host document " .. operation .. " returned an invalid result")
  end
  return value
end

local function single_edit(result)
  if result.edit_count ~= 1
      or type(result.start) ~= "number"
      or type(result.removed) ~= "number"
      or type(result.inserted) ~= "number" then
    return nil
  end

  return {
    { start = result.start, removed = result.removed, inserted = result.inserted },
  }
end

function Client.new(options)
  if type(options) ~= "table"
      or type(options.host) ~= "table"
      or options.handle == nil
      or type(options.id) ~= "string"
      or options.id == "" then
    errors.raise("INVALID_ARGUMENT", "document client requires a Host, handle and id")
  end

  return setmetatable({
    host = options.host,
    handle = options.handle,
    id = options.id,
    version = options.version or 0,
    length = options.length or 0,
    path = options.path,
    state = "open",
    subscription = options.subscription,
    events = options.events,
    snapshots = {},
    active_transactions = {},
    next_transaction_id = 0,
  }, Client)
end

function Client:_assert_open()
  if self.state ~= "open" then
    errors.raise("INVALID_HANDLE", "document is not open", {
      document_id = self.id,
      state = self.state,
    })
  end
end

function Client:read(start_offset, length)
  self:_assert_open()
  if type(start_offset) ~= "number" or start_offset < 0 or start_offset % 1 ~= 0 then
    errors.raise("INVALID_ARGUMENT", "read offset must be a non-negative integer")
  end
  if type(length) ~= "number" or length < 0 or length % 1 ~= 0 then
    errors.raise("INVALID_ARGUMENT", "read length must be a non-negative integer")
  end
  local result = check_result(self.host.documents:read(self.handle, {
    start = start_offset, length = length, expected_version = self.version,
  }), "read")
  if type(result.bytes) ~= "string"
      or type(result.version) ~= "number"
      or type(result.total_length) ~= "number"
      or result.version < 0
      or result.total_length < 0
      or #result.bytes > length then
    errors.raise("INTERNAL", "host document read result violates the documented shape")
  end

  self.version = result.version
  self.length = result.total_length

  -- Return bytes to the caller as a transient result; never cache them here.
  return result.bytes, {
    version = result.version,
    total_length = result.total_length,
    flags = result.flags,
  }
end

-- Every write uses the last observed version unless the caller supplies one.
-- The Kernel decides whether that version is still current and commits atomically.
function Client:replace(start_offset, end_offset, bytes, options)
  self:_assert_open()
  options = options or {}

  if type(start_offset) ~= "number"
      or type(end_offset) ~= "number"
      or start_offset < 0
      or end_offset < start_offset
      or start_offset % 1 ~= 0
      or end_offset % 1 ~= 0
      or type(bytes) ~= "string" then
    errors.raise("INVALID_ARGUMENT", "invalid document replacement", {
      start = start_offset,
      finish = end_offset,
    })
  end

  local request = {
    expected_version = options.expected_version or self.version,
    start = start_offset,
    finish = end_offset,
    bytes = bytes,
    coalesce_key = options.coalesce_key or 0,
    undo_blob_before = options.undo_blob_before or "",
    undo_blob_after = options.undo_blob_after or "",
  }
  local result = check_result(self.host.documents:replace(self.handle, request), "replace")
  if type(result.version) ~= "number" or type(result.accepted_seq) ~= "number"
      or result.version < 0 or result.accepted_seq < 0 then
    errors.raise("INTERNAL", "host document replace result violates the documented shape")
  end
  self.version = result.version
  if result.new_length ~= nil then self.length = result.new_length end
  local edits = single_edit(result)
  self:_emit("document.changed", {
    document_id = self.id,
    version = self.version,
    result = result,
    edits = edits,
  })
  return result
end

local function apply_history_operation(client, operation, options)
  client:_assert_open()
  options = options or {}

  local result = check_result(client.host.documents[operation](
    client.host.documents,
    client.handle,
    {
      expected_version = options.expected_version or client.version,
      blob_capacity = options.blob_capacity or 4096,
    }
  ), operation)

  if result.version ~= nil then
    client.version = result.version
  end
  if result.new_length ~= nil then
    client.length = result.new_length
  end

  client:_emit("document.changed", {
    document_id = client.id,
    version = client.version,
    history = operation,
    result = result,
    edits = single_edit(result),
  })
  return result
end

function Client:undo(options)
  return apply_history_operation(self, "undo", options)
end

function Client:redo(options)
  return apply_history_operation(self, "redo", options)
end

function Client:snapshot()
  self:_assert_open()
  local result = self.host.documents:acquire_snapshot(self.handle)
  if type(result) ~= "table"
      or result.handle == nil
      or type(result.version) ~= "number"
      or type(result.length) ~= "number" then
    errors.raise("INTERNAL", "host snapshot acquisition returned invalid metadata")
  end
  local snapshot
  snapshot = Snapshot.new(self.host, result.handle, result.version, result.length, function(closed)
    self.snapshots[closed] = nil
  end)
  self.snapshots[snapshot] = true
  return snapshot
end

function Client:with_snapshot(callback)
  return self:snapshot():with(callback)
end

function Client:replace_batch(edits, options)
  self:_assert_open()
  options = options or {}
  if type(edits) ~= "table" or #edits == 0 then
    errors.raise("INVALID_ARGUMENT", "batch must contain at least one edit")
  end
  local previous_end, normalized = -1, {}
  for index, edit in ipairs(edits) do
    if type(edit) ~= "table"
        or type(edit.start) ~= "number"
        or type(edit.finish) ~= "number"
        or type(edit.bytes) ~= "string"
        or edit.start < 0
        or edit.finish < edit.start
        or edit.start % 1 ~= 0
        or edit.finish % 1 ~= 0
        or edit.start < previous_end then
      errors.raise("INVALID_ARGUMENT", "batch edits must be sorted, non-overlapping byte ranges", {
        index = index,
      })
    end

    normalized[#normalized + 1] = {
      start = edit.start,
      finish = edit.finish,
      bytes = edit.bytes,
    }
    previous_end = edit.finish
  end
  local result = check_result(self.host.documents:replace_batch(self.handle, {
    expected_version = options.expected_version or self.version,
    edits = normalized,
    undo_blob_before = options.undo_blob_before or "",
    undo_blob_after = options.undo_blob_after or "",
  }), "replace_batch")
  if result.version then self.version = result.version end
  if result.new_length then self.length = result.new_length end
  local changed_edits = {}
  for index, edit in ipairs(normalized) do
    changed_edits[index] = {
      start = edit.start,
      removed = edit.finish - edit.start,
      inserted = #edit.bytes,
    }
  end

  self:_emit("document.changed", {
    document_id = self.id,
    version = self.version,
    history = "batch",
    result = result,
    edits = changed_edits,
    edits_coordinate = "original",
  })
  return result
end

function Client:begin_transaction(options)
  self:_assert_open()
  options = options or {}
  local result = self.host.documents:begin_transaction(self.handle, {
    expected_version = options.expected_version or self.version,
  })
  if type(result) ~= "table" or result.handle == nil then
    errors.raise("INTERNAL", "host transaction begin returned no opaque handle")
  end

  self.next_transaction_id = self.next_transaction_id + 1
  local transaction = Transaction.new({
    host = self.host,
    handle = result.handle,
    document = self,
    base_version = result.base_version or self.version,
    id = self.next_transaction_id,
  })
  self.active_transactions[transaction.id] = transaction
  return transaction
end

function Client:mark_clean()
  self:_assert_open()
  self.host.documents:mark_clean(self.handle)
end

function Client:is_clean()
  self:_assert_open()
  return self.host.documents:is_clean(self.handle)
end

function Client:search(pattern, options)
  self:_assert_open()
  options = options or {}

  if type(pattern) ~= "string" then
    errors.raise("INVALID_ARGUMENT", "search pattern must be a string")
  end

  local mode = options.mode or "literal"
  if mode == "regex" then
    errors.raise("UNSUPPORTED", "regex search is not available through Kernel ABI 1.0.0")
  end
  if mode ~= "literal" and mode ~= "bytes" then
    errors.raise("INVALID_ARGUMENT", "unsupported search mode", { mode = mode })
  end

  return check_result(self.host.documents:search(self.handle, {
    pattern = pattern,
    mode = mode,
    direction = options.direction or "forward",
    from = options.from or 0,
    bound = options.bound,
    limit = options.limit or 100,
    expected_version = options.expected_version or self.version,
    case_insensitive = options.case_insensitive == true,
    any_newline = options.any_newline == true,
    step_limit = options.step_limit or 0,
  }), "search")
end

-- Consume notifications on the Runtime thread. Incomplete history is never
-- guessed: a gap or truncated edit list forces a metadata refresh instead.
function Client:drain_notifications(max_events)
  self:_assert_open()
  if not self.subscription then return {} end
  local events = self.host.documents:drain(self.subscription, max_events or 64)
  if type(events) ~= "table" then
    errors.raise("INTERNAL", "host notification drain must return an array")
  end

  local needs_resync = false
  local edit_kinds = {
    EDIT = true,
    BATCH = true,
    TRANSACTION = true,
    UNDO = true,
    REDO = true,
    RELOAD = true,
  }
  for _, event in ipairs(events) do
    if type(event) ~= "table" or type(event.kind) ~= "string" then
      errors.raise("INTERNAL", "host returned a malformed document notification")
    end
    if event.kind == "CLOSED" then
      self:_handle_external_close()
      break
    elseif needs_resync then
      self.version = event.current_version or event.to_version or self.version
    elseif event.kind == "RESYNC" or event.edits_truncated == true then
      needs_resync = true
      self.version = event.current_version or event.to_version or self.version
    elseif event.kind == "SAVED_STATE_CHANGED" or event.kind == "HISTORY_EVICTED" then
      -- These change metadata/history availability but not canonical text offsets.
      self:_emit("document.notification", { document_id = self.id, event = event, version = self.version })
    elseif event.to_version ~= nil and event.to_version <= self.version then
      -- A local mutation already updated this client synchronously. Its queued
      -- notification is stale from this client's perspective and must not be
      -- applied to selections a second time.
    elseif event.from_version ~= nil and event.from_version ~= self.version then
      needs_resync = true
      self.version = event.current_version or event.to_version or self.version
    elseif edit_kinds[event.kind] then
      if type(event.to_version) ~= "number"
          or type(event.from_version) ~= "number"
          or type(event.edits) ~= "table"
          or (event.edit_count and #event.edits < event.edit_count) then
        needs_resync = true
        self.version = event.current_version or event.to_version or self.version
      else
        self.version = event.to_version
        if type(event.new_length) == "number" then
          self.length = event.new_length
        else
          for _, edit in ipairs(event.edits) do
            if type(edit.start) ~= "number"
                or type(edit.removed) ~= "number"
                or type(edit.inserted) ~= "number" then
              needs_resync = true
              break
            end
            self.length = self.length + edit.inserted - edit.removed
          end
        end
        if not needs_resync then
          self:_emit("document.notification", {
            document_id = self.id,
            event = event,
            version = self.version,
            edits = event.edits,
            edits_coordinate = event.edits_coordinate or "sequential",
          })
        end
      end
    else
      if type(event.to_version) == "number" then self.version = event.to_version end
      self:_emit("document.notification", { document_id = self.id, event = event, version = self.version })
    end
  end
  if needs_resync and self.state == "open" then
    -- Reads are metadata-pinned at the version returned by the backend when
    -- possible. If nil is supported, the backend returns the latest version.
    local refreshed = self.host.documents:read(self.handle, {
      start = 0,
      length = 0,
      expected_version = nil,
    })
    if type(refreshed) ~= "table"
        or type(refreshed.version) ~= "number"
        or type(refreshed.total_length) ~= "number" then
      errors.raise("INTERNAL", "metadata resync read returned invalid version/length")
    end

    self.version = refreshed.version
    self.length = refreshed.total_length
    self:_emit("document.resync_required", {
      document_id = self.id,
      version = self.version,
      length = self.length,
    })
  end
  return events
end

function Client:_handle_external_close()
  if self.state ~= "open" then
    return
  end
  for transaction_id, transaction in pairs(self.active_transactions) do
    pcall(transaction.abort, transaction)
    self.active_transactions[transaction_id] = nil
  end
  for snapshot in pairs(self.snapshots) do
    pcall(snapshot.close, snapshot)
  end
  if self.subscription then
    pcall(self.host.documents.unsubscribe, self.host.documents, self.subscription)
  end
  self.subscription, self.handle, self.state = nil, nil, "closed"
  self:_emit("document.closed_external", { document_id = self.id })
end

function Client:_emit(name, payload)
  if self.events then
    local failures = self.events:emit(name, payload)
    for _, failure in ipairs(failures) do
      self.host:log("error", failure.message, {
        code = failure.code,
        event = name,
      })
    end
  end
end

function Client:close()
  if self.state ~= "open" then
    return false
  end
  self.state = "closing"
  local first_error
  for transaction_id, transaction in pairs(self.active_transactions) do
    local ok, err = pcall(transaction.abort, transaction)
    if not ok and not first_error then first_error = errors.normalize(err) end
    self.active_transactions[transaction_id] = nil
  end
  for snapshot in pairs(self.snapshots) do
    local ok, err = pcall(snapshot.close, snapshot)
    if not ok and not first_error then first_error = errors.normalize(err) end
  end
  if self.subscription then
    local ok, err = pcall(self.host.documents.unsubscribe, self.host.documents, self.subscription)
    if not ok and not first_error then first_error = errors.normalize(err) end
    self.subscription = nil
  end
  local ok, err = pcall(self.host.documents.close, self.host.documents, self.handle)
  if not ok and not first_error then first_error = errors.normalize(err) end
  self.handle, self.state = nil, "closed"
  if first_error then error(first_error, 0) end
  return true
end

return Client
