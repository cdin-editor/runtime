local errors = require("cdin.runtime.core.error")
local Log = require("cdin.runtime.core.log")
local compatibility = require("cdin.runtime.host.contract")
local EventBus = require("cdin.runtime.core.event_bus")
local CommandRegistry = require("cdin.runtime.command.registry")
local Keymap = require("cdin.runtime.input.keymap")
local Stroke = require("cdin.runtime.input.stroke")
local DocumentManager = require("cdin.runtime.document.manager")
local ConfigDefaults = require("cdin.runtime.config.defaults")
local ProjectContext = require("cdin.runtime.workspace.project")
local StyleRegistry = require("cdin.runtime.presentation.style.registry")
local ThemeRegistry = require("cdin.runtime.presentation.theme.registry")
local SyntaxRegistry = require("cdin.runtime.presentation.syntax.registry")
local Highlighter = require("cdin.runtime.presentation.syntax.highlighter")
local UIModel = require("cdin.runtime.presentation.ui.model")
local View = require("cdin.runtime.presentation.ui.view")
local DefaultCommands = require("cdin.runtime.command.defaults")
local Table = require("cdin.runtime.util.tablex")
local Saver = require("cdin.runtime.document.saver")
local PluginManager = require("cdin.runtime.extension.manager")
-- Composition root for the Lua policy layer. Keep modules independent and
-- pass them the Host/services they need instead of importing native code here.
local Runtime = {}
Runtime.__index = Runtime

local function format_version(value)
  return string.format("%d.%d.%d", value.major, value.minor, value.patch or 0)
end

-- Construct an inert Runtime. Host validation and core registration happen in
-- start(), so a failed start can roll back without exposing a half-ready app.
--
-- Logging: Runtime has no logger of its own. `self.log` forwards records to the
-- Host, which forwards them to the Kernel's logger. `options.log_level` is only
-- a local pre-filter; the Kernel threshold remains authoritative.
function Runtime.new(options)
  options = options or {}
  if type(options.host) ~= "table" then errors.raise("INVALID_ARGUMENT", "Runtime.new requires a host object") end
  local host = options.host
  local self = setmetatable({ host = host, state = "created", info = nil,
    events = EventBus.new(), commands = CommandRegistry.new(), keymap = Keymap.new(),
    config = options.config or ConfigDefaults.new_store(), next_view_id = 0,
    options = options }, Runtime)
  self.log = Log.new(host, { component = Log.default_component, min_level = options.log_level })
  self.documents = DocumentManager.new(host, self.events, { logger = self.log:child("documents") })
  self.saver = Saver.new(host, options.saver, { logger = self.log:child("saver") })
  self.project = ProjectContext.new(self.events)
  self.styles = StyleRegistry.new()
  self.themes = ThemeRegistry.new(self.styles)
  self.syntax = SyntaxRegistry.new()
  self.highlighter = Highlighter.new(self.syntax, self.styles)
  self.ui = UIModel.new()
  self.plugins = PluginManager.new({
    commands = self.commands,
    keymap = self.keymap,
    events = self.events,
    config = self.config,
    logger = self.log:child("extension"),
    ui = host.ui,
    styles = self.styles,
    themes = self.themes,
    syntax = self.syntax,
    module_resolver = options.module_resolver,
  })
  self.events:on("document.changed", function(payload)
    self:_on_document_change(payload)
  end, "runtime")
  self.events:on("document.notification", function(payload)
    self:_on_document_notification(payload)
  end, "runtime")
  self.events:on("document.resync_required", function(payload)
    self:_on_document_resync(payload)
  end, "runtime")
  self.events:on("document.closed_external", function(payload)
    self:_on_external_document_closed(payload)
  end, "runtime")
  return self
end

-- Validate every required boundary before registering commands or publishing
-- the first UI model. A failed startup moves the instance to `failed`.
function Runtime:start()
  if self.state == "running" then
    return self
  end
  if self.state ~= "created" then
    errors.raise("INVALID_STATE", "Runtime cannot start from state " .. self.state, {
      state = self.state,
    })
  end
  self.state = "starting"
  local ok, result = pcall(function()
    self.info = compatibility.validate(self.host)
    -- Message bounds come from the Kernel logger through the Host descriptor.
    self.log:configure({ max_message_bytes = self.info.logging.max_message_bytes })
    self.styles:define("text.default", { description = "Default text", category = "text" })
    self.styles:define("text.selection", { description = "Selected text", category = "text" })
    self.styles:define("syntax.keyword", { description = "Language keyword", category = "syntax" })
    self.styles:define("syntax.string", { description = "Language string", category = "syntax" })
    self.styles:define("syntax.comment", { description = "Language comment", category = "syntax" })
    self.themes:register("default", {
      ["text.default"] = { role = "text.default" },
      ["text.selection"] = { role = "text.selection" },
      ["syntax.keyword"] = { role = "syntax.keyword" },
      ["syntax.string"] = { role = "syntax.string" },
      ["syntax.comment"] = { role = "syntax.comment" },
    })
    self.syntax:register("plain", require("cdin.runtime.presentation.syntax.plain"))
    DefaultCommands.register(self)
    self:_publish_ui()
    self.state = "running"
    local runtime_version = require("cdin.runtime.core.version").runtime
    self.events:emit("runtime.started", {
      version = runtime_version,
      host_api = self.info.host_api,
    })
    self.log:info("runtime started", {
      version = runtime_version,
      host_api = format_version(self.info.host_api),
      kernel_abi = format_version(self.info.kernel_abi),
    })
    return self
  end)
  if not ok then
    local failure = errors.normalize(result, "INTERNAL", "runtime startup")
    -- Startup is transactional: no partially registered core is left usable.
    pcall(self.plugins.shutdown, self.plugins)
    pcall(self.documents.shutdown, self.documents)
    pcall(self.commands.close, self.commands)
    pcall(self.events.close, self.events)
    self.state = "failed"
    self.log:error("runtime startup failed", {
      error = failure.message,
      code = failure.code,
    })
    error(failure, 0)
  end
  return result
end

function Runtime:_assert_running()
  if self.state == "running" then
    return
  end

  local code = (self.state == "shutting_down" or self.state == "stopped")
    and "SHUTDOWN"
    or "INVALID_STATE"
  errors.raise(code, "Runtime is not running", { state = self.state })
end

function Runtime:open_document(bytes, options)
  self:_assert_running()
  return self.documents:open(bytes, options)
end

function Runtime:save_document(id, path, options)
  self:_assert_running()
  local document = self.documents:get(id)
  if not path then path = document.path end
  if not path then
    errors.raise("INVALID_ARGUMENT", "save requires a path", { document_id = id })
  end
  local result = self.saver:save(document, path, options)
  return result
end

-- Extension lifecycle is a trusted embedding API, not a Frontend
-- Protocol command. A caller must already have local application authority;
-- remote Frontend sessions cannot use this method to load local code.
function Runtime:load_extension(name, config, options)
  self:_assert_running()
  if config ~= nil and type(config) ~= "table" then
    errors.raise("INVALID_ARGUMENT", "extension config must be a table")
  end
  local record = self.plugins:load_resolved(name, config or {}, options)
  return {
    name = record.name,
    state = record.state,
    source = record.source,
  }
end

function Runtime:unload_extension(name)
  self:_assert_running()
  return self.plugins:unload(name)
end

function Runtime:list_extensions()
  self:_assert_running()
  return self.plugins:list()
end

function Runtime:_close_document(id, publish)
  self:_assert_running()
  self.documents:get(id) -- Fail before mutating the UI for an unknown identifier.
  -- Detach views first so a close error cannot leave UI references to a dead handle.
  local to_remove = {}
  for view_id, view in pairs(self.ui.views) do
    if view.document_id == id then to_remove[#to_remove + 1] = view_id end
  end
  for _, view_id in ipairs(to_remove) do
    self.ui:remove_view(view_id)
  end
  local ok, result = pcall(self.documents.close, self.documents, id)
  if publish ~= false then self:_publish_ui() end
  if not ok then
    error(errors.normalize(result, "INTERNAL", "close document"), 0)
  end
  return result
end

function Runtime:close_document(id)
  return self:_close_document(id, true)
end

function Runtime:_create_view(document_id, options, publish)
  self:_assert_running()
  self.documents:get(document_id)
  if options ~= nil and type(options) ~= "table" then
    errors.raise("INVALID_ARGUMENT", "view options must be a table")
  end
  options = options or {}
  self.next_view_id = self.next_view_id + 1
  local view = View.new({
    id = options.id or ("view-" .. self.next_view_id),
    document_id = document_id,
  })
  self.ui:add_view(view, options)
  if publish ~= false then self:_publish_ui() end
  return view
end

function Runtime:create_view(document_id, options)
  return self:_create_view(document_id, options, true)
end

function Runtime:focused_view() return self.ui:focused_view() end
function Runtime:focused_document()
  local view = self:focused_view()
  return view and self.documents:get(view.document_id) or nil
end

local function copy_edits(edits)
  local copy = {}
  for index, edit in ipairs(edits or {}) do
    copy[index] = { start = edit.start, removed = edit.removed, inserted = edit.inserted }
  end
  return copy
end

-- Apply only offset transformations to views. The canonical bytes remain in
-- the Kernel; this method never reads or caches document content.
function Runtime:_apply_document_edits(document_id, edits, coordinate, length)
  local normalized = copy_edits(edits)
  if coordinate == "original" then
    -- Batch edit ranges refer to the same pre-edit version. Applying from the
    -- highest offset down preserves the coordinates of all remaining ranges.
    table.sort(normalized, function(a, b) return a.start > b.start end)
  end
  for _, view in pairs(self.ui.views) do
    if view.document_id == document_id then
      if #normalized > 0 then
        for _, edit in ipairs(normalized) do view:apply_edit(edit) end
      elseif type(length) == "number" then
        view:clamp_selection(length)
      end
    end
  end
  self.ui:_touch()
end

function Runtime:_on_document_change(payload)
  if type(payload) ~= "table" then return end
  local edits = payload.edits
  if edits == nil and type(payload.result) == "table" then
    local result = payload.result
    if result.edit_count == 1 and type(result.start) == "number"
        and type(result.removed) == "number" and type(result.inserted) == "number" then
      edits = { { start = result.start, removed = result.removed, inserted = result.inserted } }
    end
  end
  local document = self.documents.documents[payload.document_id]
  self:_apply_document_edits(payload.document_id, edits, payload.edits_coordinate,
    document and document.length or (payload.result and payload.result.new_length))
end

function Runtime:_on_document_notification(payload)
  local event = payload and payload.event
  if type(event) ~= "table" then return end
  local edit_kind = event.kind == "EDIT" or event.kind == "BATCH" or event.kind == "TRANSACTION"
    or event.kind == "UNDO" or event.kind == "REDO" or event.kind == "RELOAD"
  if not edit_kind then return end
  local document = self.documents.documents[payload.document_id]
  self:_apply_document_edits(payload.document_id, payload.edits, payload.edits_coordinate,
    document and document.length or event.new_length)
end

function Runtime:_on_document_resync(payload)
  if type(payload) ~= "table" then return end
  local document = self.documents.documents[payload.document_id]
  self:_apply_document_edits(payload.document_id, nil, nil, (document and document.length) or payload.length)
end

function Runtime:_on_external_document_closed(payload)
  if type(payload) ~= "table" then return end
  local ids = {}
  for view_id, view in pairs(self.ui.views) do
    if view.document_id == payload.document_id then ids[#ids + 1] = view_id end
  end
  for _, view_id in ipairs(ids) do self.ui:remove_view(view_id) end
  self.documents:forget_closed(payload.document_id)
  if self.state == "running" then self:_publish_ui() end
end

-- Run on the Lua owner thread after the Backend signals Kernel notifications.
-- Notification draining is deliberately explicit; this method starts no worker.
function Runtime:pump_notifications(max_events_per_document)
  self:_assert_running()
  local total, failures = 0, {}
  for _, item in ipairs(self.documents:list()) do
    local document = self.documents.documents[item.id]
    if document and document.state == "open" then
      local ok, events = pcall(document.drain_notifications, document, max_events_per_document or 64)
      if not ok then
        failures[#failures + 1] = errors.normalize(events, "INTERNAL", "drain notifications:" .. item.id)
      else
        total = total + #events
      end
    end
  end
  if total > 0 then self:_publish_ui() end
  return total, failures
end

-- Publish data describing the editor, not draw commands or pixel geometry.
-- The Backend is responsible for forwarding this model to attached frontends.
function Runtime:_publish_ui()
  local snapshot = self.ui:snapshot()
  -- The Frontend renders against an exact document version. Keep only metadata
  -- here; canonical bytes remain owned by the Kernel.
  for _, view_snapshot in pairs(snapshot.views) do
    local document = self.documents.documents[view_snapshot.document_id]
    if not document or document.state ~= "open" then
      errors.raise("INVALID_HANDLE", "UI view references a document that is not open", {
        view_id = view_snapshot.id,
      })
    end
    view_snapshot.document_version = document.version
    view_snapshot.document_length = document.length
  end
  snapshot.theme = self.themes.active
  snapshot.styles = self.themes:snapshot().styles

  local failures = self.events:emit("ui.model_changed", Table.copy(snapshot))
  for _, failure in ipairs(failures) do
    self.log:error(failure.message, { code = failure.code, event = "ui.model_changed" })
  end
  return self.host.ui:publish(snapshot)
end

-- Lifecycle commands may return the view they created. Runtime applies that
-- semantic focus transition centrally before the single final UI publication.
-- Frontends and transport handlers never infer focus from command names.
function Runtime:_focus_command_result(result)
  if type(result) == "table" and type(result.view_id) == "string"
      and self.ui.views[result.view_id] ~= nil and self.ui.focus ~= result.view_id then
    self.ui:set_focus(result.view_id)
  end
end

function Runtime:dispatch(name, args, context)
  self:_assert_running()
  local supplied = context or {}
  context = {}
  for key, value in pairs(supplied) do context[key] = value end
  context.runtime = self
  context.document = context.document or self:focused_document()
  context.view = context.view or self:focused_view()
  local ok, result = self.commands:execute(name, context, args or {})
  if ok then
    self:_focus_command_result(result)
    self:_publish_ui()
  end
  return ok, result
end

function Runtime:_dispatch_chain(names)
  local context = { runtime = self, document = self:focused_document(), view = self:focused_view() }
  for _, name in ipairs(names or {}) do
    if self.commands:can_execute(name, context, {}) then
      local ok, result = self.commands:execute(name, context, {})
      if ok then
        self:_focus_command_result(result)
        self:_publish_ui()
        return { status = "executed", command = name, result = result }
      end
    end
  end
  return { status = "unhandled", commands = names or {} }
end

function Runtime:handle_key(raw_event)
  self:_assert_running()
  local stroke, reason = Stroke.from_event(raw_event)
  if not stroke then return { status = "ignored", reason = reason } end
  return self:handle_stroke(stroke)
end

-- Low-level method for unit tests and trusted embedded callers. Frontends must
-- call handle_key(raw_event), never pre-resolve key bindings themselves.
function Runtime:handle_stroke(stroke)
  self:_assert_running()
  local result = self.keymap:feed(stroke)
  if result.status == "matched" then return self:_dispatch_chain(result.commands) end
  return result
end

function Runtime:expire_key_sequence()
  self:_assert_running()
  local result = self.keymap:expire()
  if result.status == "matched" then return self:_dispatch_chain(result.commands) end
  return result
end

-- Emit non-document frontend events on the Runtime owner thread. Frontend
-- geometry remains frontend-owned; resize and mouse coordinates are not
-- converted into document offsets here.
function Runtime:_emit_frontend_event(name, payload)
  local failures = self.events:emit(name, payload)
  for _, failure in ipairs(failures) do
    self.log:error(failure.message, { code = failure.code, event = name })
  end
  return #failures == 0
end

function Runtime:_insert_frontend_bytes(bytes)
  if type(bytes) ~= "string" then
    errors.raise("INVALID_ARGUMENT", "frontend text payload must be a byte string")
  end
  local view = self:focused_view()
  local document = self:focused_document()
  if not view or not document then
    errors.raise("INVALID_STATE", "text input requires a focused document view")
  end
  local result = view:replace_selection(document, bytes, {
    expected_version = document.version,
  })
  self:_publish_ui()
  return { status = "inserted", version = result.version, byte_count = #bytes }
end

-- Version-pinned line reads are a pull service. The returned strings are
-- transient exact bytes; this method never stores them on Runtime or View.
function Runtime:read_view_lines(view_id, first_line, line_count, expected_version)
  self:_assert_running()
  if type(view_id) ~= "string" or view_id == "" then
    errors.raise("INVALID_ARGUMENT", "view_id is required")
  end
  local view = self.ui.views[view_id]
  if not view then errors.raise("NOT_FOUND", "view does not exist", { view_id = view_id }) end
  local document = self.documents:get(view.document_id)
  local changed, previous
  previous = { version = document.version, length = document.length }
  changed = document:refresh_metadata()
  if changed then
    -- External mutations may not have reached the notification pump yet. We
    -- cannot infer their edit sequence, so clamp offsets and invalidate all
    -- visible content at the newly observed version instead of guessing.
    self:_apply_document_edits(document.id, nil, nil, document.length)
    self:_publish_ui()
    self.log:debug("document metadata refreshed for line request", {
      document_id = document.id, previous_version = previous.version,
      current_version = document.version, length = document.length,
    })
  end
  return document:read_lines(first_line, line_count, expected_version)
end

-- Called only by the Backend's Lua owner-thread dispatcher. Raw key policy
-- remains in Runtime; frontends do not resolve key bindings or hit-test text.
function Runtime:handle_frontend_event(event)
  self:_assert_running()
  if type(event) ~= "table" or type(event.type) ~= "string" then
    errors.raise("INVALID_ARGUMENT", "frontend event must have a type")
  end

  local event_type = event.type
  if event_type == "input.key" then
    if event.action == "release" then return { status = "ignored", reason = "key-release" } end
    if event.action ~= "press" and event.action ~= "repeat" then
      errors.raise("INVALID_ARGUMENT", "unsupported key action", { action = tostring(event.action) })
    end
    return self:handle_key({ kind = "key_down", key = event.key, modifiers = event.modifiers })
  elseif event_type == "input.text" then
    return self:_insert_frontend_bytes(event.text)
  elseif event_type == "input.paste" then
    return self:_insert_frontend_bytes(event.bytes)
  elseif event_type == "input.mouse" then
    if event.target ~= nil then
      if type(event.target) ~= "string" or not self.ui.views[event.target] then
        errors.raise("NOT_FOUND", "mouse target view does not exist", { view_id = event.target })
      end
      if self.ui.focus ~= event.target then
        self.ui:set_focus(event.target)
        self:_publish_ui()
      end
    end
    self:_emit_frontend_event("frontend.mouse", event)
    return { status = "observed" }
  elseif event_type == "view.set_position" then
    if type(event.view_id) ~= "string" then errors.raise("INVALID_ARGUMENT", "view_id is required") end
    local view = self.ui.views[event.view_id]
    if not view then errors.raise("NOT_FOUND", "view does not exist", { view_id = event.view_id }) end
    local document = self.documents:get(view.document_id)
    -- Refresh without pinning to the stale client version. External Kernel edits
    -- must invalidate view state before the Frontend's byte offsets are accepted.
    local changed = document:refresh_metadata()
    if changed then
      self:_apply_document_edits(document.id, nil, nil, document.length)
      self:_publish_ui()
    end
    if type(event.version) ~= "number" or event.version ~= document.version then
      errors.raise("STALE_VERSION", "view position uses a stale document version", {
        expected = event.version, current = document.version,
      })
    end
    local anchor, caret = event.anchor, event.caret
    if type(anchor) ~= "number" or type(caret) ~= "number"
        or anchor < 0 or caret < 0 or anchor % 1 ~= 0 or caret % 1 ~= 0
        or anchor > document.length or caret > document.length then
      errors.raise("OUT_OF_RANGE", "view position is outside the document", {
        length = document.length,
      })
    end
    self.ui:set_focus(event.view_id)
    view:set_selection(anchor, caret)
    self:_publish_ui()
    return { status = "position-set", version = document.version }
  elseif event_type == "request.command" then
    local ok, result = self:dispatch(event.name, event.arguments or {})
    if not ok then
      errors.raise("NOT_FOUND", "frontend command is not registered or cannot execute", {
        command = tostring(event.name),
      })
    end
    return { status = "executed", result = result }
  elseif event_type == "window.resize" then
    self:_emit_frontend_event("frontend.window_resized", event)
    return { status = "observed" }
  elseif event_type == "focus" then
    self:_emit_frontend_event("frontend.focus_changed", event)
    return { status = "observed" }
  end

  errors.raise("UNSUPPORTED", "frontend event type is not supported by Runtime", {
    event_type = event_type,
  })
end

function Runtime:publish_ui()
  self:_assert_running()
  return self:_publish_ui()
end

-- Stop accepting work, release Runtime-owned clients and close registries.
-- Cleanup continues after individual failures and returns them to the caller.
function Runtime:shutdown()
  if self.state == "stopped" then return true end
  if self.state == "created" or self.state == "failed" then self.state = "stopped"; return true end
  if self.state ~= "running" then errors.raise("INVALID_STATE", "Runtime cannot shutdown from " .. self.state) end
  self.state = "shutting_down"
  local failures = {}
  local function collect(label, callback)
    local ok, value = pcall(callback)
    if not ok then failures[#failures + 1] = { operation = label, error = errors.normalize(value) }
    elseif type(value) == "table" then
      for _, item in ipairs(value) do failures[#failures + 1] = item end
    end
  end
  collect("plugins.shutdown", function() return self.plugins:shutdown() end)
  collect("documents.shutdown", function() return self.documents:shutdown() end)
  pcall(self.events.emit, self.events, "runtime.stopping", { failures = #failures })
  pcall(self.commands.close, self.commands)
  pcall(self.events.close, self.events)
  self.state = "stopped"
  if #failures > 0 then
    self.log:error("runtime shutdown completed with failures", { count = #failures })
    -- Cap the detail lines so a large session cannot flood the shared logger.
    for index = 1, math.min(#failures, 10) do
      local failure = failures[index]
      local detail = failure.error or failure
      self.log:error("runtime shutdown failure", {
        operation = failure.operation,
        code = detail.code,
      })
    end
    return false, failures
  end
  self.log:info("runtime stopped")
  return true
end

-- Counters for records sent, dropped, filtered or failed, so the Backend can
-- notice a Host logger that has stopped accepting records.
function Runtime:log_stats()
  return self.log:stats()
end

return { new = Runtime.new, Runtime = Runtime }
