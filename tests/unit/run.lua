package.path = "lua/?.lua;lua/?/init.lua;tests/?.lua;tests/?/init.lua;" .. package.path
local A = require("support.assert")
local Error = require("cdin.runtime.core.error")
local EventBus = require("cdin.runtime.core.event_bus")
local Commands = require("cdin.runtime.command.registry")
local Keymap = require("cdin.runtime.input.keymap")
local Stroke = require("cdin.runtime.input.stroke")
local Config = require("cdin.runtime.config.defaults")
local ConfigStore = require("cdin.runtime.config.store")
local Saver = require("cdin.runtime.document.saver")
local DocumentClient = require("cdin.runtime.document.client")
local ProjectContext = require("cdin.runtime.workspace.project")
local Selection = require("cdin.runtime.presentation.ui.selection")
local PaneTree = require("cdin.runtime.presentation.ui.pane_tree")
local UIModel = require("cdin.runtime.presentation.ui.model")
local View = require("cdin.runtime.presentation.ui.view")
local Styles = require("cdin.runtime.presentation.style.registry")
local Themes = require("cdin.runtime.presentation.theme.registry")
local Syntax = require("cdin.runtime.presentation.syntax.registry")
local Highlighter = require("cdin.runtime.presentation.syntax.highlighter")
local Sandbox = require("cdin.runtime.extension.sandbox")
local ExtensionManager = require("cdin.runtime.extension.manager")
local Log = require("cdin.runtime.core.log")
local Strict = require("cdin.runtime.core.strict")

local bus = EventBus.new(); local hits = 0
local token = bus:on("tick", function() hits = hits + 1 end, "test")
bus:emit("tick", {}); A.equal(hits, 1)
bus:off(token); bus:emit("tick", {}); A.equal(hits, 1)
local removed = bus:on("x", function() error("expected") end)
local failures = bus:emit("x", {}); A.equal(#failures, 1); bus:off(removed)
for _ = 1, 2000 do
  local churn = bus:on("churn", function() end, "temporary")
  bus:off(churn)
end
A.equal(bus.listeners.churn, nil)
for _ = 1, 100 do bus:on("owned", function() end, "owner-x") end
A.equal(bus:off_owner("owner-x"), 100)
A.equal(bus.listeners.owned, nil)

local commands = Commands.new()
commands:register("test.one", function(_, args) return args.value end)
local ok, result = commands:execute("test.one", {}, { value = 7 }); A.truthy(ok); A.equal(result, 7)
A.error_code(function() commands:register("test.one", function() end) end, "DUPLICATE_REGISTRATION")
commands:register("test.hidden", function() end, { available = function() return false end })
A.falsy(commands:can_execute("test.hidden", {}, {}))
A.equal(commands:remove_owner("core"), 2)

local stroke = Stroke.from_event({ kind = "key_down", key = "S", modifiers = { shift = true, ctrl = true } })
A.equal(stroke, "ctrl+shift+s")
local altgr = Stroke.from_event({ kind = "key_down", key = "q", modifiers = { ctrl = true, alt = true, altgr = true } })
A.equal(altgr, "altgr+q")
local ignored, reason = Stroke.from_event({ kind = "key_down", key = "left ctrl", modifiers = { ctrl = true } })
A.equal(ignored, nil); A.equal(reason, "modifier-only")

local keymap = Keymap.new()
local t1 = keymap:bind({ "ctrl+k", "ctrl+c" }, "test.one", { owner = "p1" })
A.equal(keymap:feed("ctrl+k").status, "pending")
local key_result = keymap:feed("ctrl+c"); A.equal(key_result.status, "matched"); A.equal(key_result.commands[1], "test.one")
keymap:bind("ctrl+k", "test.short", { owner = "p1" })
A.equal(keymap:feed("ctrl+k").status, "pending")
A.equal(keymap:expire().commands[1], "test.short")
A.truthy(keymap:remove(t1)); A.falsy(keymap:get_binding("test.one"))
local owner_one = keymap:bind("ctrl+x", "shared.command", { owner = "one" })
keymap:bind("ctrl+x", "shared.command", { owner = "two" })
A.truthy(keymap:remove(owner_one, { "shared.command" }))
A.equal(keymap:feed("ctrl+x").commands[1], "shared.command")
A.error_code(function() keymap:bind("SHIFT+X", "x") end, "INVALID_ARGUMENT")
-- Rebinding the same owner/command replaces its token instead of leaking stale tokens.
for _ = 1, 2000 do keymap:bind("alt+x", "reload.command", { owner = "reload" }) end
local reload_tokens = 0
for _, token in pairs(keymap.tokens) do if token.owner == "reload" then reload_tokens = reload_tokens + 1 end end
A.equal(reload_tokens, 1)
A.equal(#keymap:list(), 3) -- ctrl+k, ctrl+x, and alt+x
A.equal(keymap:remove_owner("reload"), 1)
for _, token in pairs(keymap.tokens) do A.falsy(token.owner == "reload") end

local config = Config.new_store()
A.equal(config:get("editor.tab_width"), 4)
config:set("user", "editor.tab_width", 2)
config:set("project", "editor.tab_width", 8)
A.equal(config:get("editor.tab_width"), 8)
config:set("session", "editor.tab_width", 6)
A.equal(config:get("editor.tab_width"), 6)
A.error_code(function() config:set("user", "editor.tab_width", 0) end, "INVALID_ARGUMENT")
A.error_code(function() config:set("user", "editor.unknown", true) end, "INVALID_ARGUMENT")
A.error_code(function() config:unset("user", "editor.unknown") end, "INVALID_ARGUMENT")
A.error_code(function()
  ConfigStore.new({ ["test.positive"] = {
    default = 0,
    validate = function(value) return type(value) == "number" and value > 0, "must be positive" end,
  } })
end, "INVALID_ARGUMENT")
local project = ProjectContext.new(bus)
local metadata = { root_id = "root-1" }
project:set("/workspace/demo", { metadata = metadata })
metadata.root_id = "mutated"
A.equal(project:snapshot().metadata.root_id, "root-1")
A.error_code(function() project:set("/workspace/demo", { metadata = "invalid" }) end, "INVALID_ARGUMENT")
local snapshot = config:snapshot(); config:set("session", "editor.tab_width", 9); config:restore(snapshot)
A.equal(config:get("editor.tab_width"), 6)
A.error_code(function()
  config:load("session", {
    ["editor.tab_width"] = 12,
    ["editor.unknown"] = true,
  })
end, "INVALID_ARGUMENT")
A.equal(config:get("editor.tab_width"), 6) -- failed loads must be atomic
A.error_code(function() Saver.new({}, { chunk_size = 0 }) end, "INVALID_ARGUMENT")
A.error_code(function() DocumentClient.new({ host = {}, handle = {}, id = "" }) end, "INVALID_ARGUMENT")

local blob = Selection.encode(Selection.new(4, 9), 12)
local decoded, decoded_scroll = Selection.decode(blob)
A.equal(decoded.anchor, 4); A.equal(decoded.caret, 9); A.equal(decoded_scroll, 12)
-- V1 snapshots remain readable after adding scroll-anchor metadata.
local legacy_selection, legacy_scroll = Selection.decode("CDINSEL1;3;8")
A.equal(legacy_selection.anchor, 3); A.equal(legacy_selection.caret, 8); A.equal(legacy_scroll, 0)
local view_snapshot = View.new({ id = "snapshot-view", document_id = "doc-a" })
view_snapshot:set_selection(2, 5); view_snapshot.scroll_anchor = 17
local saved_view_state = view_snapshot:selection_blob()
view_snapshot:set_selection(0, 0); view_snapshot.scroll_anchor = 0
view_snapshot:restore_selection_blob(saved_view_state)
A.equal(view_snapshot.selection.anchor, 2); A.equal(view_snapshot.selection.caret, 5)
A.equal(view_snapshot.scroll_anchor, 17)
local range_start, range_end = Selection.range(decoded); A.equal(range_start, 4); A.equal(range_end, 9)
A.error_code(function() Selection.decode("bad") end, "INVALID_ARGUMENT")
local strict_env = { allowed_value = 9 }
Strict.install(strict_env)
local allowed_chunk = assert(load("return allowed_value", "strict-allowed", "t", strict_env))
A.equal(allowed_chunk(), 9)
local forbidden_write = assert(load("leak = 1", "strict-write", "t", strict_env))
A.falsy(pcall(forbidden_write))
local forbidden_read = assert(load("return missing_value", "strict-read", "t", strict_env))
A.falsy(pcall(forbidden_read))
local pane_tree = PaneTree.new(); pane_tree:add_view("v1"); pane_tree:add_view("v2")
A.equal(#pane_tree:list_views(), 2); pane_tree:focus("v1"); pane_tree:split("v1", "v3", "horizontal", 0.6)
A.equal(#pane_tree:list_views(), 3)
local outer_split = pane_tree:snapshot().root
A.equal(outer_split.ratio, 0.6)
A.truthy(pane_tree:set_split_ratio(outer_split.id, 0.7))
A.equal(pane_tree:snapshot().root.ratio, 0.7)
A.error_code(function() pane_tree:set_split_ratio(outer_split.id, 0.1) end, "INVALID_ARGUMENT")
A.error_code(function() pane_tree:set_split_ratio(outer_split.id, 0.9) end, "INVALID_ARGUMENT")
A.error_code(function() pane_tree:set_split_ratio(outer_split.id, 0 / 0) end, "INVALID_ARGUMENT")
A.error_code(function() pane_tree:set_split_ratio("missing-split", 0.5) end, "NOT_FOUND")
A.error_code(function() pane_tree:set_split_ratio("", 0.5) end, "INVALID_ARGUMENT")
A.equal(pane_tree:snapshot().root.ratio, 0.7) -- rejected mutations are atomic

-- Nested updates identify the selected split by its stable semantic ID.
pane_tree:split("v1", "v4", "vertical", 0.4)
local nested = pane_tree:snapshot().root.first
A.equal(nested.kind, "split")
A.truthy(pane_tree:set_split_ratio(nested.id, 0.55))
local nested_snapshot = pane_tree:snapshot().root
A.equal(nested_snapshot.ratio, 0.7)
A.equal(nested_snapshot.first.ratio, 0.55)
A.equal(#pane_tree:list_views(), 4)
A.truthy(pane_tree:remove_view("v3")); A.equal(#pane_tree:list_views(), 3)
A.error_code(function() pane_tree:split("v1", "v5", "bad", 0.5) end, "INVALID_ARGUMENT")

local model = UIModel.new()
model:add_view(View.new({ id = "view-a", document_id = "doc-a" }))
A.error_code(function()
  model:add_view(View.new({ id = "view-b", document_id = "doc-a" }), {
    split_with = "view-a",
    axis = "diagonal",
  })
end, "INVALID_ARGUMENT")
A.equal(model.views["view-b"], nil)
A.equal(#model.pane_tree:list_views(), 1)

local styles = Styles.new(); styles:define("text.default")
local themes = Themes.new(styles); themes:register("default", { ["text.default"] = { foreground = "#ffffff" } })
A.equal(themes:activate("default").name, "default")
A.error_code(function() themes:register("bad", { missing = {} }) end, "INVALID_ARGUMENT")
local syntax = Syntax.new(); syntax:register("toy", { extensions = { "toy" }, tokenize = function(text) return { { start = 0, finish = #text, role = "syntax.keyword" } } end })
A.error_code(function()
  syntax:register("other-toy", { extensions = { "toy" }, tokenize = function() return {} end })
end, "DUPLICATE_REGISTRATION")
A.equal(syntax:get("other-toy"), nil)
local highlighter = Highlighter.new(syntax)
local highlighted = highlighter:highlight("toy", "abc", 3); A.equal(highlighted.version, 3); A.equal(highlighted.spans[1].finish, 3)
A.error_code(function() highlighter:highlight("toy", 12, 3) end, "INVALID_ARGUMENT")
local invalid_syntax = Syntax.new(); invalid_syntax:register("bad", { tokenize = function() return { { start = 0.5, finish = 2, role = "syntax.keyword" } } end })
local invalid_highlighter = Highlighter.new(invalid_syntax)
A.error_code(function() invalid_highlighter:highlight("bad", "abc", 1) end, "INTERNAL")

local sandbox = Sandbox.new()
local module = sandbox:load("safe", "return { init = function(core, config) core.commands:register('safe.ok', function() return true end) end }", {
  commands = { register = function(_, name) A.equal(name, "safe.ok") end }, keymap = {}, events = {}, log = function() end, ui = {},
}, {})
A.equal(type(module.init), "function")
-- Accessing a forbidden global is a capability denial, not a generic malformed
-- extension. Preserve the sandbox's stable authorization error code.
A.error_code(function() sandbox:load("unsafe", "return { init = function() return os.execute('x') end }", {}, {}) end, "PERMISSION_DENIED")
A.error_code(function() sandbox:load("global", "leak = true; return {}", {}, {}) end, "PERMISSION_DENIED")

-- RT-013 | Extension sandbox denies ambient capabilities without making
-- ordinary capability probes themselves fail extension initialization.
local capability_probe = sandbox:load("capability-probe", [[
return {
  probe = function()
    local denied = { "io", "os", "debug", "package", "dofile", "loadfile" }
    for _, name in ipairs(denied) do
      if pcall(function() return _G[name] end) then return false, "ambient:" .. name end
    end
    local original_pi = math.pi
    if pcall(function() math.pi = 0 end) then return false, "mutable-math" end
    if math.pi ~= original_pi then return false, "math-mutated" end
    if pcall(require, "unapproved.module") then return false, "require-without-resolver" end
    if pcall(function() _G.cdin_test_escape = true end) then return false, "global-write" end
    return true
  end,
}
]], {}, {})
local capability_ok, capability_reason = capability_probe.probe()
A.truthy(capability_ok, capability_reason)

-- RT-013 | Extension failure isolation and owner-scoped rollback.
local extension_commands = Commands.new()
local extension_keymap = Keymap.new()
local extension_events = EventBus.new()
local extension_manager = ExtensionManager.new({
  commands = extension_commands,
  keymap = extension_keymap,
  events = extension_events,
  logger = Log.null(),
})
A.error_code(function()
  extension_manager:load("failed-init", [[
    return {
      init = function(core)
        core.commands:register("extension.failed.init", function() return true end)
        core.keymap:bind("ctrl+alt+i", "extension.failed.init")
        core.events:on("extension_tick", function() end)
        error("intentional init failure")
      end,
      unload = function() error("unload must not run after failed init") end,
    }
  ]], {}, {})
end, "BAD_EXTENSION")
A.equal(extension_manager.plugins["failed-init"], nil)
A.equal(extension_commands:get("extension.failed.init"), nil)
A.equal(#extension_keymap:list(), 0)
A.equal(extension_events.listeners.extension_tick, nil)

extension_manager:load("runtime-failure", [[
  return {
    init = function(core)
      core.commands:register("extension.runtime.fail", function() error("intentional command failure") end)
      core.commands:register("extension.runtime.ok", function() return "still alive" end)
      core.events:on("extension_tick", function() error("intentional event failure") end)
    end,
    unload = function() error("intentional unload failure") end,
  }
]], {}, {})
A.error_code(function()
  extension_commands:execute("extension.runtime.fail", {}, {})
end, "INTERNAL")
local command_ok, command_result = extension_commands:execute("extension.runtime.ok", {}, {})
A.truthy(command_ok); A.equal(command_result, "still alive")
local extension_event_failures = extension_events:emit("extension_tick", {})
A.equal(#extension_event_failures, 1)
A.equal(extension_manager.plugins["runtime-failure"].state, "active")
A.error_code(function() extension_manager:unload("runtime-failure") end, "BAD_EXTENSION")
A.equal(extension_manager.plugins["runtime-failure"], nil)
A.equal(extension_commands:get("extension.runtime.fail"), nil)
A.equal(extension_commands:get("extension.runtime.ok"), nil)
A.equal(#extension_keymap:list(), 0)
A.equal(extension_events.listeners.extension_tick, nil)

require("unit.log_tests")

A.report("unit tests")
