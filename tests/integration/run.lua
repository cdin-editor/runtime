package.path = "lua/?.lua;lua/?/init.lua;tests/?.lua;tests/?/init.lua;" .. package.path
local A = require("support.assert")
local FakeHost = require("support.fake_host")
local Runtime = require("cdin.runtime")
local Selection = require("cdin.runtime.presentation.ui.selection")

local host = FakeHost.new()
local runtime = Runtime.new({ host = host })
runtime:start()
A.equal(runtime.state, "running")
local document = runtime:open_document("abc", { path = "virtual.txt" })
local view = runtime:create_view(document.id)
local split_view = runtime:create_view(document.id, { split_with = view.id, axis = "vertical", ratio = 0.5 })
A.equal(#runtime.ui.pane_tree:list_views(), 2)
A.equal(runtime.ui.pane_tree:snapshot().root.kind, "split")
runtime.ui:remove_view(split_view.id)
view:set_selection(1, 2)
runtime.commands:register("test.replace_selection", function(context)
  return context.view:replace_selection(context.document, "Z")
end)
runtime.keymap:bind("ctrl+e", "test.replace_selection")
local input_result = runtime:handle_key({ kind = "key_down", key = "e", modifiers = { ctrl = true } })
A.equal(input_result.status, "executed")
A.equal(input_result.command, "test.replace_selection")
local bytes, read_meta = document:read(0, 10)
A.equal(bytes, "aZc"); A.equal(read_meta.version, 1); A.equal(document.version, 1)
A.falsy(document:is_clean())
local undo_ok = runtime:dispatch("document.undo", {}, { document = document, view = view })
A.truthy(undo_ok)
local restored; restored = document:read(0, 10); A.equal(restored, "abc")
local redo_ok = runtime:dispatch("document.redo", {}, { document = document, view = view })
A.truthy(redo_ok)
local redone = document:read(0, 10); A.equal(redone, "aZc")

document:mark_clean(); A.truthy(document:is_clean())
-- The Frontend event path reaches Runtime on its owner thread and preserves paste bytes.
local event_document = runtime:open_document("abc")
local event_view = runtime:create_view(event_document.id)
local initial_position_event = runtime:handle_frontend_event({
  type = "view.set_position", view_id = event_view.id, version = event_document.version, anchor = 1, caret = 1,
})
A.equal(initial_position_event.status, "position-set")
local text_event = runtime:handle_frontend_event({ type = "input.text", text = "Q" })
A.equal(text_event.status, "inserted")
local after_text = event_document:read(0, 16); A.equal(after_text, "aQbc")
local paste_event = runtime:handle_frontend_event({ type = "input.paste", bytes = "\0P" })
A.equal(paste_event.status, "inserted")
local after_paste = event_document:read(0, 16); A.equal(after_paste, "aQ\0Pbc")
local position_event = runtime:handle_frontend_event({
  type = "view.set_position", view_id = event_view.id, version = event_document.version, anchor = 0, caret = 1,
})
A.equal(position_event.status, "position-set")
A.error_code(function()
  runtime:handle_frontend_event({
    type = "view.set_position", view_id = event_view.id, version = 0, anchor = 0, caret = 1,
  })
end, "STALE_VERSION")
local key_event = runtime:handle_frontend_event({
  type = "input.key", key = "e", action = "press", modifiers = { "ctrl" },
})
A.equal(key_event.status, "executed")
local after_key = event_document:read(0, 16); A.equal(after_key, "ZQ\0Pbc")
local command_event = runtime:handle_frontend_event({ type = "request.command", name = "document.undo", arguments = {} })
A.equal(command_event.status, "executed")
local resized_width
runtime.events:on("frontend.window_resized", function(payload) resized_width = payload.width end)
runtime:handle_frontend_event({ type = "window.resize", width = 80, height = 24, units = "cells" })
A.equal(resized_width, 80)
runtime:handle_frontend_event({ type = "focus", focused = false })
runtime:handle_frontend_event({
  type = "input.mouse", action = "press", button = "left", modifiers = {}, target = event_view.id,
  position = { x = 2, y = 1 },
})

-- Semantic PaneTree resize is dispatched on the Runtime owner thread. Nested
-- split identity, children, focus and exact-once revision semantics are stable.
local outer_split_view = runtime:create_view(event_document.id, {
  split_with = event_view.id, axis = "vertical", ratio = 0.5,
})
local inner_split_view = runtime:create_view(event_document.id, {
  split_with = outer_split_view.id, axis = "horizontal", ratio = 0.4,
})
local before_tree = runtime.ui.pane_tree:snapshot().root
A.equal(before_tree.kind, "split")
A.equal(before_tree.second.kind, "split")
local outer_id = before_tree.id
local inner_id = before_tree.second.id
local outer_first_id = before_tree.first.id
local outer_second_id = before_tree.second.id
local inner_first_id = before_tree.second.first.id
local inner_second_id = before_tree.second.second.id
local retained_focus = runtime.ui.focus
local before_revision = runtime.ui.revision
A.equal(runtime:supports_protocol_capability("pane-splitter-resize/1"), true)
A.equal(runtime:supports_protocol_capability("unknown-extension/1"), false)

local resize_result = runtime:handle_frontend_event({
  type = "pane.set_split_ratio", split_id = inner_id, ratio = 0.62,
})
A.equal(resize_result.status, "applied")
A.equal(resize_result.split_id, inner_id)
A.equal(resize_result.ratio, 0.62)
A.equal(resize_result.revision, before_revision + 1)
A.equal(runtime.ui.revision, before_revision + 1)
A.equal(runtime.ui.focus, retained_focus)

local after_tree = runtime.ui.pane_tree:snapshot().root
A.equal(after_tree.id, outer_id)
A.equal(after_tree.ratio, 0.5)
A.equal(after_tree.first.id, outer_first_id)
A.equal(after_tree.second.id, outer_second_id)
A.equal(after_tree.second.id, inner_id)
A.equal(after_tree.second.ratio, 0.62)
A.equal(after_tree.second.first.id, inner_first_id)
A.equal(after_tree.second.second.id, inner_second_id)

local rejected_revision = runtime.ui.revision
A.error_code(function()
  runtime:handle_frontend_event({
    type = "pane.set_split_ratio", split_id = "missing-split", ratio = 0.5,
  })
end, "NOT_FOUND")
A.error_code(function()
  runtime:handle_frontend_event({
    type = "pane.set_split_ratio", split_id = inner_first_id, ratio = 0.5,
  })
end, "NOT_FOUND")
local minimum_result = runtime:handle_frontend_event({
  type = "pane.set_split_ratio", split_id = inner_id, ratio = 0.1,
})
A.equal(minimum_result.status, "applied")
A.equal(minimum_result.revision, rejected_revision + 1)
A.equal(runtime.ui.pane_tree:snapshot().root.second.ratio, 0.1)

local maximum_result = runtime:handle_frontend_event({
  type = "pane.set_split_ratio", split_id = inner_id, ratio = 0.8999,
})
A.equal(maximum_result.status, "applied")
A.equal(maximum_result.revision, rejected_revision + 2)
A.equal(runtime.ui.pane_tree:snapshot().root.second.ratio, 0.8999)

local boundary_revision = runtime.ui.revision
A.error_code(function()
  runtime:handle_frontend_event({
    type = "pane.set_split_ratio", split_id = inner_id, ratio = 0.0999,
  })
end, "INVALID_ARGUMENT")
A.error_code(function()
  runtime:handle_frontend_event({
    type = "pane.set_split_ratio", split_id = inner_id, ratio = 0.9,
  })
end, "INVALID_ARGUMENT")
A.equal(runtime.ui.revision, boundary_revision)
A.equal(runtime.ui.pane_tree:snapshot().root.second.ratio, 0.8999)
A.equal(runtime.ui.focus, retained_focus)

runtime:close_document(event_document.id)

local search = document:search("Z", { mode = "literal" }); A.equal(search.count, 1)
A.error_code(function() document:search("Z", { mode = "regex" }) end, "UNSUPPORTED")

-- Version-pinned line service preserves CRLF, LF, NUL and exact document bytes.
local line_document = runtime:open_document("one\r\ntwo\nlast\0")
local line_client = runtime.documents:get(line_document.id)
local line_window = line_client:read_lines(0, 8, 0)
A.equal(line_window.version, 0)
A.equal(line_window.total_lines, 3)
A.equal(line_window.lines[1], "one\r\n")
A.equal(line_window.lines[2], "two\n")
A.equal(line_window.lines[3], "last\0")
A.error_code(function() line_client:read_lines(0, 1, 1) end, "STALE_VERSION")
local line_view = runtime:create_view(line_document.id)
line_view.scroll_anchor = line_document.length
local prior_line_version = line_document.version
host.documents:replace(line_document.handle, {
  expected_version = prior_line_version, start = 0, finish = line_document.length, bytes = "x",
  undo_blob_before = "", undo_blob_after = "",
})
A.error_code(function() runtime:read_view_lines(line_view.id, 0, 1, prior_line_version) end,
  "STALE_VERSION")
A.equal(line_document.version, prior_line_version + 1)
A.equal(line_document.length, 1)
A.equal(line_view.scroll_anchor, 1)
runtime:close_document(line_document.id)

-- Snapshots remain version-pinned while live document edits continue.
local snapshot = document:snapshot()
A.equal(snapshot:read(0, 10), "aZc")
local pinned_version = snapshot.version
local transaction = document:begin_transaction()
transaction:replace(0, 1, "A")
local live_before_commit = document:read(0, 10)
A.equal(live_before_commit, "aZc")
local txn_result = transaction:commit({ undo_blob_before = view:selection_blob(), undo_blob_after = view:selection_blob() })
A.equal(document.version, txn_result.version)
A.equal(snapshot.version, pinned_version)
A.equal(snapshot:read(0, 10), "aZc")
snapshot:close()
local post_txn = document:read(0, 10); A.equal(post_txn, "AZc")

local batch_result = document:replace_batch({
  { start = 0, finish = 1, bytes = "a" },
  { start = 2, finish = 3, bytes = "C" },
}, { undo_blob_before = view:selection_blob(), undo_blob_after = view:selection_blob() })
A.equal(batch_result.edit_count, 2)
local post_batch = document:read(0, 10); A.equal(post_batch, "aZC")
local save_result = runtime:save_document(document.id, "saved.txt")
A.equal(save_result.bytes_written, 3)
A.equal(host.fs:read_test_file("saved.txt"), "aZC")
A.truthy(save_result.clean); A.truthy(document:is_clean())

-- Changes from another owner arrive as versioned Kernel notifications. Local
-- notifications already reflected in the client version must not be replayed.
local remote_result = host.documents:replace(document.handle, {
  expected_version = document.version, start = 0, finish = 0, bytes = "!",
  undo_blob_before = "", undo_blob_after = "",
})
local pumped, pump_failures = runtime:pump_notifications()
A.truthy(pumped >= 1); A.equal(#pump_failures, 0)
local remote_bytes = document:read(0, 20)
A.equal(remote_bytes, "!aZC"); A.equal(document.version, remote_result.version)
A.equal(view.selection.caret, 3)

-- External closure invalidates the opaque handle, detaches the view, and removes
-- the closed client from the manager without issuing a second native close.
local externally_closed = runtime:open_document("gone")
local external_view = runtime:create_view(externally_closed.id)
host:test_external_close(externally_closed.handle)
local close_pumped, close_failures = runtime:pump_notifications()
A.truthy(close_pumped >= 1); A.equal(#close_failures, 0)
A.equal(externally_closed.state, "closed")
A.equal(runtime.documents.documents[externally_closed.id], nil)
A.equal(runtime.ui.views[external_view.id], nil)

-- Closing a document must release outstanding snapshots and abort transactions.
local cleanup_doc = runtime:open_document("temporary")
local outstanding_snapshot = cleanup_doc:snapshot()
local outstanding_snapshot_id = outstanding_snapshot.handle.id
local outstanding_txn = cleanup_doc:begin_transaction()
outstanding_txn:replace(0, 1, "T")
A.truthy(runtime:close_document(cleanup_doc.id))
A.equal(outstanding_txn.state, "aborted")
A.equal(outstanding_snapshot.state, "closed")
A.equal(host.snapshots[outstanding_snapshot_id], nil)

-- The client holds no text buffer: only the opaque Host handle/version metadata.
A.equal(rawget(document, "bytes"), nil)
A.equal(rawget(document, "history"), nil)
A.truthy(#host.published >= 2)
A.equal(host.published[#host.published].schema, "cdin.ui-model.v1")

local plugin_source = [[
return {
  init = function(core, config)
    core.commands:register("plugin.hello", function() return "hello" end)
    core.events:on("probe", function() end)
  end,
  unload = function() end
}
]]
local record = runtime.plugins:load("sample", plugin_source, {})
A.equal(record.state, "active")
local plugin_ok, plugin_value = runtime.commands:execute("plugin.hello", {}, {})
A.truthy(plugin_ok); A.equal(plugin_value, "hello")
A.truthy(runtime.plugins:unload("sample"))
A.falsy(runtime.commands:get("plugin.hello"))
-- RT-013 | Reference: https://github.com/cdin-editor/spec
-- Extension-owned presentation contributions must be removed on unload.
local owned_plugin = [[return { init = function(core)
  core.styles:define("plugin.sample", { category = "test" })
  core.themes:register("plugin.sample", { ["plugin.sample"] = { role = "plugin.sample" } })
  core.syntax:register("plugin-sample", { extensions = { "psamp" }, tokenize = function() return {} end })
end }]]
runtime.plugins:load("presentation-sample", owned_plugin, {})
A.truthy(runtime.styles:has("plugin.sample"))
A.truthy(runtime.themes.themes["plugin.sample"] ~= nil)
A.truthy(runtime.syntax:get("plugin-sample") ~= nil)
runtime.plugins:unload("presentation-sample")
A.falsy(runtime.styles:has("plugin.sample"))
A.falsy(runtime.themes.themes["plugin.sample"] ~= nil)
A.falsy(runtime.syntax:get("plugin-sample") ~= nil)
local command_takeover = [[return { init = function(core)
  core.commands:register("document.undo", function() return "hijacked" end, { overwrite = true })
end }]]
local takeover_error = A.error_code(function() runtime.plugins:load("takeover", command_takeover, {}) end, "PERMISSION_DENIED")
A.equal(takeover_error.domain, "cdin.runtime")
A.equal(takeover_error.details.command, "document.undo")
A.equal(takeover_error.details.owner, "core")
A.truthy(runtime.commands:get("document.undo"))
A.equal(runtime.commands:get("document.undo").owner, "core")
local failed_plugin = [[return { init = function(core)
  core.commands:register("plugin.partial", function() return true end)
  error("intentional init failure")
end, unload = function() error("must not run after init failure") end }]]
A.error_code(function() runtime.plugins:load("broken", failed_plugin, {}) end, "BAD_EXTENSION")
A.falsy(runtime.commands:get("plugin.partial"))

-- Resolver-backed extension lifecycle is available only to trusted Runtime
-- embedders. It is deliberately not registered as a Frontend Protocol command.
A.equal(#runtime:list_extensions(), 0)
A.equal(runtime.commands:get("extension.load"), nil)
A.error_code(function() runtime:load_extension("disabled", {}) end, "UNSUPPORTED")

local extension_sources = {
  init = [[
    local greeting = require("helpers.greeting")
    return {
      init = function(core, config)
        core.commands:register("resolved.greeting", function()
          return greeting.value .. (config.suffix or "")
        end)
      end,
      unload = function() end
    }
  ]],
  ["helpers.greeting"] = [[return { value = "hello" }]],
}
local resolver_calls = {}
local resolver_runtime = Runtime.new({
  host = FakeHost.new(),
  module_resolver = function(owner, module_name)
    resolver_calls[#resolver_calls + 1] = owner .. ":" .. module_name
    local source = extension_sources[module_name]
    if source == nil then return nil end
    return source, "extension://" .. owner .. "/" .. module_name
  end,
})
resolver_runtime:start()
A.error_code(function()
  resolver_runtime:load_extension("../outside", {})
end, "INVALID_ARGUMENT")
local resolved = resolver_runtime:load_extension("sample-resolved", { suffix = "!" })
A.equal(resolved.name, "sample-resolved")
-- A duplicate load is idempotent: it returns the active record without
-- resolving modules again or re-running init with new configuration.
local resolver_calls_before_duplicate = #resolver_calls
local duplicate_resolved = resolver_runtime:load_extension("sample-resolved", { suffix = "ignored" })
A.equal(duplicate_resolved.name, resolved.name)
A.equal(duplicate_resolved.state, "active")
A.equal(#resolver_calls, resolver_calls_before_duplicate)
A.equal(resolved.state, "active")
A.equal(resolved.source, "resolver")
local resolved_ok, resolved_value = resolver_runtime.commands:execute("resolved.greeting", {}, {})
A.truthy(resolved_ok)
A.equal(resolved_value, "hello!")
A.equal(resolver_calls[1], "sample-resolved:init")
A.equal(resolver_calls[2], "sample-resolved:helpers.greeting")
local listed_extensions = resolver_runtime:list_extensions()
A.equal(#listed_extensions, 1)
A.equal(listed_extensions[1].name, "sample-resolved")
A.truthy(resolver_runtime:unload_extension("sample-resolved"))
A.falsy(resolver_runtime.commands:get("resolved.greeting"))
A.equal(#resolver_runtime:list_extensions(), 0)
local module_path_escape = [[return { init = function() require("../outside") end }]]
A.error_code(function()
  resolver_runtime.plugins:load("module-escape", module_path_escape, {})
end, "PERMISSION_DENIED")
A.falsy(resolver_runtime.commands:get("module-escape.command"))

-- Dotted module identifiers must accept ordinary segments and reject empty
-- segments/path syntax before the resolver is called.
local invalid_module_names = {
  ".leading",
  "trailing.",
  "double..dot",
  "helpers/escape",
  "helpers\\\\escape",
  "../outside",
}
for index, module_name in ipairs(invalid_module_names) do
  local plugin_name = "invalid-module-" .. index
  local source = "return { init = function() require(" .. string.format("%q", module_name) .. ") end }"
  local resolver_calls_before = #resolver_calls
  A.error_code(function()
    resolver_runtime.plugins:load(plugin_name, source, {})
  end, "PERMISSION_DENIED")
  A.equal(#resolver_calls, resolver_calls_before)
  A.falsy(resolver_runtime.commands:get(plugin_name .. ".command"))
end

-- An unload-hook failure still releases every owner-scoped contribution and
-- removes the name from the active set. The structured failure is returned
-- only after cleanup has completed.
local unload_failure_runtime = Runtime.new({
  host = FakeHost.new(),
  module_resolver = function()
    return [[return {
      init = function(core)
        core.commands:register("unload.failure.command", function() return true end)
      end,
      unload = function()
        error({
          domain = "cdin.runtime",
          code = "PERMISSION_DENIED",
          message = "extension cleanup was denied",
          details = { stage = "unload" },
        })
      end,
    }]]
  end,
})
unload_failure_runtime:start()
unload_failure_runtime:load_extension("unload-failure", {})
A.truthy(unload_failure_runtime.commands:get("unload.failure.command"))
local unload_error = A.error_code(function()
  unload_failure_runtime:unload_extension("unload-failure")
end, "PERMISSION_DENIED")
A.equal(unload_error.details.stage, "unload")
A.equal(#unload_failure_runtime:list_extensions(), 0)
A.equal(unload_failure_runtime.commands:get("unload.failure.command"), nil)
A.falsy(unload_failure_runtime:unload_extension("unload-failure"))
A.truthy(unload_failure_runtime:shutdown())

-- Manager shutdown drops owner registrations without invoking extension
-- unload hooks. A hook that would fail must not turn shutdown into a failure.
local shutdown_extension_runtime = Runtime.new({
  host = FakeHost.new(),
  module_resolver = function()
    return [[return {
      init = function(core)
        core.commands:register("shutdown.extension.command", function() return true end)
      end,
      unload = function() error("shutdown must not invoke extension unload") end,
    }]]
  end,
})
shutdown_extension_runtime:start()
shutdown_extension_runtime:load_extension("shutdown-extension", {})
A.truthy(shutdown_extension_runtime.commands:get("shutdown.extension.command"))
A.truthy(shutdown_extension_runtime:shutdown())
A.equal(shutdown_extension_runtime.plugins.plugins["shutdown-extension"], nil)
A.equal(shutdown_extension_runtime.commands:get("shutdown.extension.command"), nil)

A.truthy(resolver_runtime:shutdown())

-- Structured Backend resolver failures must survive nested require and
-- extension initialization instead of being flattened to BAD_EXTENSION.
local structured_error_runtime = Runtime.new({
  host = FakeHost.new(),
  module_resolver = function(_, module_name)
    if module_name == "init" then
      return [[return { init = function() require("helpers.too_large") end }]]
    end
    error({
      domain = "cdin.runtime",
      code = "LIMIT_EXCEEDED",
      message = "extension source exceeds configured size",
      details = { module = module_name },
    })
  end,
})
structured_error_runtime:start()
local nested_resolver_error = A.error_code(function()
  structured_error_runtime:load_extension("oversized-extension", {})
end, "LIMIT_EXCEEDED")
A.equal(nested_resolver_error.domain, "cdin.runtime")
A.equal(nested_resolver_error.details.module, "helpers.too_large")
A.equal(#structured_error_runtime:list_extensions(), 0)
A.truthy(structured_error_runtime:shutdown())


-- A structured resolver failure while resolving the entry source must retain
-- its Backend code and details before any extension is registered.
local structured_entry_resolver_runtime = Runtime.new({
  host = FakeHost.new(),
  module_resolver = function()
    error({
      domain = "cdin.runtime",
      code = "IO_ERROR",
      message = "extension entry could not be read",
      details = { module = "init" },
    })
  end,
})
structured_entry_resolver_runtime:start()
local entry_resolver_error = A.error_code(function()
  structured_entry_resolver_runtime:load_extension("entry-read-failure", {})
end, "IO_ERROR")
A.equal(entry_resolver_error.domain, "cdin.runtime")
A.equal(entry_resolver_error.details.module, "init")
A.equal(#structured_entry_resolver_runtime:list_extensions(), 0)
A.truthy(structured_entry_resolver_runtime:shutdown())

-- Structured errors raised by the entry chunk and init hook must cross the
-- sandbox boundary unchanged; failed init still rolls back owned contributions.
local structured_entry_runtime = Runtime.new({
  host = FakeHost.new(),
  module_resolver = function()
    return [[error({
      domain = "cdin.runtime",
      code = "IO_ERROR",
      message = "entry execution failed",
      details = { stage = "entry" },
    })]]
  end,
})
structured_entry_runtime:start()
local entry_error = A.error_code(function()
  structured_entry_runtime:load_extension("entry-execution-failure", {})
end, "IO_ERROR")
A.equal(entry_error.details.stage, "entry")
A.equal(#structured_entry_runtime:list_extensions(), 0)
A.truthy(structured_entry_runtime:shutdown())

local structured_init_runtime = Runtime.new({
  host = FakeHost.new(),
  module_resolver = function()
    return [[return {
      init = function(core)
        core.commands:register("structured.init.partial", function() return true end)
        error({
          domain = "cdin.runtime",
          code = "PERMISSION_DENIED",
          message = "extension initialization was denied",
          details = { stage = "init" },
        })
      end,
    }]]
  end,
})
structured_init_runtime:start()
local init_error = A.error_code(function()
  structured_init_runtime:load_extension("init-permission-failure", {})
end, "PERMISSION_DENIED")
A.equal(init_error.details.stage, "init")
A.falsy(structured_init_runtime.commands:get("structured.init.partial"))
A.equal(#structured_init_runtime:list_extensions(), 0)
A.truthy(structured_init_runtime:shutdown())

local missing_resolver_runtime = Runtime.new({
  host = FakeHost.new(),
  module_resolver = function() return nil end,
})
missing_resolver_runtime:start()
A.error_code(function()
  missing_resolver_runtime:load_extension("missing-extension", {})
end, "NOT_FOUND")
A.equal(#missing_resolver_runtime:list_extensions(), 0)
A.truthy(missing_resolver_runtime:shutdown())

-- CDIN Runtime runs in its own Lua state; strict globals are installed before
-- the rest of the runtime modules load.
A.falsy(pcall(function() cdin_runtime_undeclared_global = true end))
A.equal(rawget(_G, "cdin_runtime_undeclared_global"), nil)
A.error_code(function()
  local bad = Runtime.new({ host = FakeHost.new({ kernel_abi = { major = 2, minor = 0, patch = 0 } }) })
  bad:start()
end, "HOST_API_MISMATCH")
A.error_code(function()
  local bad = Runtime.new({ host = FakeHost.new({ features = { documents=true, notifications=true, logging=true } }) })
  bad:start()
end, "HOST_API_MISMATCH")
A.error_code(function()
  local bad = Runtime.new({ host = FakeHost.new({ host_api = { major = 0, minor = 3, patch = 0 } }) })
  bad:start()
end, "HOST_API_MISMATCH")
A.error_code(function()
  local bad = Runtime.new({ host = FakeHost.new({ host_api = { major = 2, minor = 0, patch = 0 } }) })
  bad:start()
end, "HOST_API_MISMATCH")
-- Stable Host API 1.x permits additive minor evolution and rejects older/different majors.
local forward_host_api = Runtime.new({
  host = FakeHost.new({ host_api = { major = 1, minor = 1, patch = 0 } }),
})
forward_host_api:start(); A.equal(forward_host_api.state, "running"); forward_host_api:shutdown()

A.error_code(function()
  local bad = Runtime.new({ host = FakeHost.new({ frontend_protocol = { major = 0, minor = 2, patch = 0 } }) })
  bad:start()
end, "HOST_API_MISMATCH")
-- Spec: ADR-0018 / docs/architecture/protocol-wire.md §6. Stable Protocol
-- minor versions are additive within major 1; a major change is incompatible.
local forward_protocol = Runtime.new({
  host = FakeHost.new({ frontend_protocol = { major = 1, minor = 1, patch = 0 } }),
})
A.truthy(forward_protocol:start())
A.truthy(forward_protocol:shutdown())
A.error_code(function()
  Runtime.new({
    host = FakeHost.new({ frontend_protocol = { major = 2, minor = 0, patch = 0 } }),
  }):start()
end, "HOST_API_MISMATCH")
local incomplete_host = FakeHost.new(); incomplete_host.documents.read_lines = nil
A.error_code(function() Runtime.new({ host = incomplete_host }):start() end, "HOST_API_MISMATCH")

local shutdown_ok = runtime:shutdown(); A.truthy(shutdown_ok); A.equal(runtime.state, "stopped")
A.error_code(function() runtime:open_document("x") end, "SHUTDOWN")
require("integration.document_lifecycle_commands")
require("integration.logging_tests")

A.report("integration tests")
