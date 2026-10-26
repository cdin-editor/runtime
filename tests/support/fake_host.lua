-- Test-only Backend/Kernel model. Production Runtime never stores document bytes;
-- this fake stores them to model the Kernel ABI for deterministic tests.
local errors = require("cdin.runtime.core.error")
local tablex = require("cdin.runtime.util.tablex")
local M = {}

local function check_version(document, expected)
  if expected ~= nil and expected ~= document.version then
    errors.raise("STALE_VERSION", "document version changed", { expected = expected, current = document.version })
  end
end

local function single_diff(before, after)
  local prefix = 0
  local max_prefix = math.min(#before, #after)
  while prefix < max_prefix and before:byte(prefix + 1) == after:byte(prefix + 1) do prefix = prefix + 1 end
  local suffix = 0
  while suffix < #before - prefix and suffix < #after - prefix
      and before:byte(#before - suffix) == after:byte(#after - suffix) do suffix = suffix + 1 end
  return { start = prefix, removed = #before - prefix - suffix, inserted = #after - prefix - suffix }
end

function M.new(options)
  options = options or {}
  local host = { logs = {}, published = {}, docs = {}, subscriptions = {}, next_doc = 0,
    next_subscription = 0, sequence = 0 }
  function host:info()
    return {
      host_api = options.host_api or { major = 0, minor = 1, patch = 0 },
      kernel_abi = options.kernel_abi or { major = 1, minor = 0, patch = 0 },
      extension_contract = options.extension_contract or { major = 1, minor = 0 },
      frontend_protocol = options.frontend_protocol or { major = 0, minor = 1, patch = 0 },
      features = options.features or { documents = true, notifications = true, snapshots = true, transactions = true, batch_edits = true, literal_search = true, ui_model = true, logging = true },
      kernel_features = { transactions = true, snapshots = true, notifications = true, batch = true, search_literal = true, search_bytes = true, search_regex = false },
    }
  end
  function host:log(level, message, fields)
    self.logs[#self.logs + 1] = { level = level, message = message, fields = tablex.copy(fields or {}) }
  end
  host.ui = {}
  function host.ui:publish(model) host.published[#host.published + 1] = tablex.copy(model); return true end
  host.documents = {}
  local service = host.documents
  local function get_doc(handle)
    if type(handle) ~= "table" or not host.docs[handle.id] then errors.raise("INVALID_HANDLE", "invalid fake document handle") end
    return host.docs[handle.id]
  end
  local function notify(document, event)
    for _, subscription in pairs(host.subscriptions) do
      if subscription.document == document then subscription.queue[#subscription.queue + 1] = tablex.copy(event) end
    end
  end
  function host:test_external_close(handle)
    local document = get_doc(handle)
    notify(document, { kind = "CLOSED", current_version = document.version })
    self.docs[handle.id] = nil
    return true
  end
  function service:create(bytes, metadata)
    if type(bytes) ~= "string" then errors.raise("INVALID_ARGUMENT", "bytes must be a string") end
    host.next_doc = host.next_doc + 1
    local handle = { id = host.next_doc, opaque = true }
    local document = { handle = handle, bytes = bytes, version = 0, clean = true, history = {}, redo = {}, metadata = metadata or {} }
    host.docs[handle.id] = document
    return { handle = handle, version = 0, length = #bytes }
  end
  function service:close(handle)
    local document = get_doc(handle)
    notify(document, { kind = "CLOSED", current_version = document.version })
    for id, subscription in pairs(host.subscriptions) do if subscription.document == document then host.subscriptions[id] = nil end end
    host.docs[handle.id] = nil
    return true
  end
  function service:read(handle, request)
    local document = get_doc(handle); check_version(document, request.expected_version)
    local start, length = request.start, request.length
    if start > #document.bytes then errors.raise("OUT_OF_RANGE", "read starts past document end", { requested = start, length = #document.bytes }) end
    local bytes = document.bytes:sub(start + 1, math.min(#document.bytes, start + length))
    return { bytes = bytes, version = document.version, total_length = #document.bytes, flags = 0 }
  end
  local function mutate(document, request, kind, new_bytes, blob)
    if document.active_txn then errors.raise("BUSY", "document has an active transaction") end
    check_version(document, request.expected_version)
    local before = document.bytes
    local before_blob = request.undo_blob_before or ""
    local after_blob = request.undo_blob_after or ""
    local edits
    if kind == "edit" then
      if type(request.start) ~= "number" or type(request.finish) ~= "number" or request.start < 0 or request.finish < request.start or request.finish > #before then
        errors.raise("OUT_OF_RANGE", "invalid edit range", { requested = request.finish, length = #before })
      end
      edits = { { start = request.start, removed = request.finish - request.start, inserted = #request.bytes } }
      document.history[#document.history + 1] = { bytes = before, blob_before = before_blob, blob_after = after_blob, edits = edits }
      document.redo = {}
      document.bytes = before:sub(1, request.start) .. request.bytes .. before:sub(request.finish + 1)
    else
      document.bytes = new_bytes
      edits = { single_diff(before, new_bytes) }
    end
    host.sequence = host.sequence + 1
    document.version = document.version + 1
    document.clean = false
    local edit = edits[1]
    local result = { version = document.version, accepted_seq = host.sequence, edit_count = #edits,
      new_length = #document.bytes, start = #edits == 1 and edit.start or 0,
      removed = #edits == 1 and edit.removed or 0, inserted = #edits == 1 and edit.inserted or 0,
      selection_blob = blob }
    notify(document, { kind = kind == "edit" and "EDIT" or kind:upper(), from_version = document.version - 1,
      to_version = document.version, edit_count = #edits, edits_stored = #edits, edits = edits,
      edits_truncated = false, new_length = #document.bytes })
    return result
  end
  function service:replace(handle, request)
    local document = get_doc(handle)
    return mutate(document, request, "edit")
  end
  function service:undo(handle, request)
    local document = get_doc(handle); check_version(document, request.expected_version)
    local item = table.remove(document.history)
    if not item then errors.raise("INVALID_STATE", "nothing to undo") end
    document.redo[#document.redo + 1] = { bytes = document.bytes, blob_before = item.blob_before, blob_after = item.blob_after }
    return mutate(document, { expected_version = document.version }, "undo", item.bytes, item.blob_before)
  end
  function service:redo(handle, request)
    local document = get_doc(handle); check_version(document, request.expected_version)
    local item = table.remove(document.redo)
    if not item then errors.raise("INVALID_STATE", "nothing to redo") end
    document.history[#document.history + 1] = { bytes = document.bytes, blob_before = item.blob_before, blob_after = item.blob_after }
    return mutate(document, { expected_version = document.version }, "redo", item.bytes, item.blob_after)
  end
  function service:acquire_snapshot(handle)
    local document = get_doc(handle); host.next_snapshot = (host.next_snapshot or 0) + 1
    host.snapshots = host.snapshots or {}
    local snapshot_handle = { id = host.next_snapshot, opaque = true }
    host.snapshots[snapshot_handle.id] = { bytes = document.bytes, version = document.version }
    return { handle = snapshot_handle, version = document.version, length = #document.bytes }
  end
  function service:read_snapshot(snapshot_handle, request)
    local snapshot = host.snapshots and type(snapshot_handle) == "table" and host.snapshots[snapshot_handle.id]
    if not snapshot then errors.raise("INVALID_HANDLE", "invalid fake snapshot") end
    return { bytes = snapshot.bytes:sub(request.start + 1, math.min(#snapshot.bytes, request.start + request.length)), version = snapshot.version }
  end
  function service:release_snapshot(snapshot_handle)
    if host.snapshots then host.snapshots[snapshot_handle.id] = nil end
    return true
  end
  function service:replace_batch(handle, request)
    local document = get_doc(handle); check_version(document, request.expected_version)
    if document.active_txn then errors.raise("BUSY", "document has an active transaction") end
    local before, current_end = document.bytes, -1
    for _, edit in ipairs(request.edits) do
      if edit.start < current_end or edit.finish > #before then errors.raise("OUT_OF_RANGE", "invalid batch range") end
      current_end = edit.finish
    end
    document.history[#document.history + 1] = { bytes = before, blob_before = request.undo_blob_before or "", blob_after = request.undo_blob_after or "", edits = request.edits }
    document.redo = {}
    for index = #request.edits, 1, -1 do
      local edit = request.edits[index]
      document.bytes = document.bytes:sub(1, edit.start) .. edit.bytes .. document.bytes:sub(edit.finish + 1)
    end
    host.sequence = host.sequence + 1; document.version = document.version + 1; document.clean = false
    local event_edits = {}
    for index = #request.edits, 1, -1 do
      local edit = request.edits[index]
      event_edits[#event_edits + 1] = { start = edit.start, removed = edit.finish - edit.start, inserted = #edit.bytes }
    end
    notify(document, { kind = "BATCH", from_version = document.version - 1, to_version = document.version,
      edit_count = #event_edits, edits_stored = #event_edits, edits = event_edits, edits_truncated = false,
      new_length = #document.bytes })
    return { version = document.version, accepted_seq = host.sequence, edit_count = #request.edits, new_length = #document.bytes }
  end
  function service:begin_transaction(handle, request)
    local document = get_doc(handle); check_version(document, request.expected_version)
    if document.active_txn then errors.raise("INVALID_STATE", "nested transaction") end
    host.next_transaction = (host.next_transaction or 0) + 1
    local txn_handle = { id = host.next_transaction, opaque = true }
    local txn = { handle = txn_handle, document = document, bytes = document.bytes, base_version = document.version, edit_count = 0, edits = {} }
    host.transactions = host.transactions or {}; host.transactions[txn_handle.id] = txn; document.active_txn = txn
    return { handle = txn_handle, base_version = document.version }
  end
  local function get_txn(handle)
    local txn = host.transactions and type(handle) == "table" and host.transactions[handle.id]
    if not txn then errors.raise("INVALID_HANDLE", "invalid fake transaction") end
    return txn
  end
  function service:transaction_replace(handle, request)
    local txn = get_txn(handle)
    if request.start < 0 or request.finish < request.start or request.finish > #txn.bytes then errors.raise("OUT_OF_RANGE", "transaction range is invalid") end
    txn.bytes = txn.bytes:sub(1, request.start) .. request.bytes .. txn.bytes:sub(request.finish + 1)
    txn.edit_count = txn.edit_count + 1
    txn.edits[#txn.edits + 1] = { start = request.start, removed = request.finish - request.start, inserted = #request.bytes }
    return { new_length = #txn.bytes, edit_count = txn.edit_count }
  end
  function service:transaction_read(handle, request)
    local txn = get_txn(handle)
    return { bytes = txn.bytes:sub(request.start + 1, math.min(#txn.bytes, request.start + request.length)), total_length = #txn.bytes }
  end
  function service:commit_transaction(handle, request)
    local txn = get_txn(handle); local doc = txn.document
    if doc.version ~= txn.base_version or doc.active_txn ~= txn then errors.raise("STALE_VERSION", "transaction base version changed", { expected = txn.base_version, current = doc.version }) end
    local before = doc.bytes
    doc.history[#doc.history + 1] = { bytes = before, blob_before = request.undo_blob_before or "", blob_after = request.undo_blob_after or "", edits = txn.edits }
    doc.redo = {}; doc.bytes = txn.bytes; doc.version = doc.version + 1; doc.clean = false
    doc.active_txn = nil; host.transactions[handle.id] = nil; host.sequence = host.sequence + 1
    notify(doc, { kind = "TRANSACTION", from_version = doc.version - 1, to_version = doc.version,
      edit_count = #txn.edits, edits_stored = #txn.edits, edits = txn.edits, edits_truncated = false, new_length = #doc.bytes })
    return { version = doc.version, accepted_seq = host.sequence, edit_count = txn.edit_count, new_length = #doc.bytes }
  end
  function service:abort_transaction(handle)
    local txn = get_txn(handle); txn.document.active_txn = nil; host.transactions[handle.id] = nil; return true
  end
  function service:mark_clean(handle) get_doc(handle).clean = true; return true end
  function service:mark_clean_if_version(handle, expected_version)
    local document = get_doc(handle)
    if document.version ~= expected_version then return false end
    document.clean = true; return true
  end
  function service:is_clean(handle) return get_doc(handle).clean end
  function service:subscribe(handle)
    local document = get_doc(handle); host.next_subscription = host.next_subscription + 1
    local subscription_handle = { id = host.next_subscription, opaque = true }
    host.subscriptions[subscription_handle.id] = { handle = subscription_handle, document = document, queue = {} }
    return { handle = subscription_handle, version = document.version }
  end
  function service:unsubscribe(subscription_handle)
    if type(subscription_handle) ~= "table" or not host.subscriptions[subscription_handle.id] then return true end
    host.subscriptions[subscription_handle.id] = nil; return true
  end
  function service:drain(subscription_handle, max_events)
    local sub = type(subscription_handle) == "table" and host.subscriptions[subscription_handle.id]
    if not sub then errors.raise("INVALID_HANDLE", "invalid subscription") end
    local result = {}
    while #result < (max_events or 64) and #sub.queue > 0 do result[#result + 1] = table.remove(sub.queue, 1) end
    return result
  end
  function service:search(handle, request)
    local document = get_doc(handle); check_version(document, request.expected_version)
    local pattern, ranges = request.pattern, {}
    if pattern == "" then return { version = document.version, ranges = {}, count = 0, exhausted = true } end
    local text, pos = document.bytes, (request.from or 0) + 1
    while #ranges < (request.limit or 100) do
      local start, finish = text:find(pattern, pos, true)
      if not start then break end
      ranges[#ranges + 1] = { start - 1, finish }
      pos = finish + 1
    end
    return { version = document.version, ranges = ranges, count = #ranges, exhausted = true }
  end
  host.fs = {}
  local files = {}
  function host.fs:begin_atomic_write(path) return { path = path, parts = {}, open = true } end
  function host.fs:write_chunk(writer, bytes)
    if not writer.open or type(bytes) ~= "string" then errors.raise("INVALID_STATE", "invalid atomic writer") end
    writer.parts[#writer.parts + 1] = bytes
  end
  function host.fs:commit_atomic_write(writer)
    if not writer.open then errors.raise("INVALID_STATE", "writer is closed") end
    files[writer.path] = table.concat(writer.parts); writer.open = false; return true
  end
  function host.fs:abort_atomic_write(writer) writer.open = false; writer.parts = {}; return true end
  function host.fs:read_test_file(path) return files[path] end
  return host
end

return M
