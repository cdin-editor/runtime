local errors = require("cdin.runtime.core.error")
local Sandbox = require("cdin.runtime.extension.sandbox")
local Log = require("cdin.runtime.core.log")

-- RT-013 | Reference: https://github.com/cdin-editor/spec
-- Extension contributions are owner-scoped and removed at unload/failure.
local Manager = {}
Manager.__index = Manager

function Manager.new(options)
  options = options or {}
  return setmetatable({
    commands = options.commands,
    keymap = options.keymap,
    events = options.events,
    config = options.config,
    logger = options.logger or Log.null(),
    ui = options.ui,
    styles = options.styles,
    themes = options.themes,
    syntax = options.syntax,
    module_resolver = options.module_resolver,
    plugins = {},
    closed = false,
  }, Manager)
end

function Manager:_facade(name)
  local manager = self
  -- Records written by an extension carry its own component and cannot name
  -- another one: the logger owns the `component` field.
  local logger = self.logger:child(name)

  return {
    commands = {
      register = function(_, command_name, handler, options)
        options = options or {}
        local existing = manager.commands:get(command_name)
        if existing and existing.owner ~= name then
          errors.raise("PERMISSION_DENIED", "extension cannot replace a command owned by another component", {
            command = command_name,
            owner = existing.owner,
            requester = name,
          })
        end

        options.owner = name
        return manager.commands:register(command_name, handler, options)
      end,
      remove = function(_, command_name)
        return manager.commands:remove(command_name, name)
      end,
    },
    keymap = {
      bind = function(_, sequence, commands, options)
        options = options or {}
        if options.overwrite then
          errors.raise("PERMISSION_DENIED", "extensions cannot clear other owners' keymap contributions")
        end

        options.owner = name
        return manager.keymap:bind(sequence, commands, options)
      end,
    },
    events = {
      on = function(_, event_name, callback)
        return manager.events:on(event_name, callback, name)
      end,
    },
    log = function(_, level, message, fields)
      return logger:log(level, message, fields)
    end,
    error = function(_, message, fields)
      return logger:error(message, fields)
    end,
    unload_plugin = function(_, plugin_name)
      return manager:unload(plugin_name)
    end,
    ui = {
      publish = function(_, model)
        return manager.ui:publish(model)
      end,
    },
    styles = {
      define = function(_, role, options)
        options = options or {}; options.owner = name
        return manager.styles:define(role, options)
      end,
    },
    themes = {
      register = function(_, theme_name, theme)
        return manager.themes:register(theme_name, theme, { owner = name })
      end,
      activate = function(_, theme_name)
        local entry = manager.themes.themes[theme_name]
        if not entry or entry.owner ~= name then
          errors.raise("PERMISSION_DENIED", "extension may activate only its own theme", {
            theme = theme_name, requester = name,
          })
        end
        return manager.themes:activate(theme_name)
      end,
    },
    syntax = {
      register = function(_, syntax_name, definition)
        return manager.syntax:register(syntax_name, definition, { owner = name })
      end,
    },
  }
end

function Manager:load(name, source, config, options)
  options = options or {}
  if self.closed then
    errors.raise("SHUTDOWN", "plugin manager is closed")
  end
  if type(name) ~= "string" or name == "" then
    errors.raise("INVALID_ARGUMENT", "plugin name is required")
  end
  if self.plugins[name] then
    return self.plugins[name]
  end

  local sandbox = Sandbox.new({ module_resolver = self.module_resolver })
  local ok, module = pcall(
    sandbox.load,
    sandbox,
    name,
    source,
    self:_facade(name),
    config or {},
    options.chunk_name
  )
  if not ok then
    -- Roll back registrations after a failed init. The extension contract does
    -- not call unload() for an entry whose initialization did not complete.
    self.commands:remove_owner(name)
    self.keymap:remove_owner(name)
    self.events:off_owner(name)
    if self.themes then self.themes:remove_owner(name) end
    if self.syntax then self.syntax:remove_owner(name) end
    if self.styles then self.styles:remove_owner(name) end
    local failure = errors.normalize(module, "BAD_EXTENSION", "load plugin:" .. name)
    self.logger:child(name):error("extension failed to load", { code = failure.code })
    error(failure, 0)
  end

  local record = {
    name = name,
    module = module,
    sandbox = sandbox,
    state = "active",
    source = options.source or "explicit",
  }
  self.plugins[name] = record
  self.logger:child(name):info("extension loaded", { source = record.source })
  return record
end

-- Load the entry module through the Backend-provided, extension-scoped
-- resolver. The resolver must enforce source-root confinement and bounded
-- reads; Runtime never resolves paths or touches the filesystem itself.
function Manager:load_resolved(name, config, options)
  options = options or {}
  if self.closed then
    errors.raise("SHUTDOWN", "plugin manager is closed")
  end
  if type(name) ~= "string" or name == "" then
    errors.raise("INVALID_ARGUMENT", "plugin name is required")
  end
  if self.plugins[name] then
    return self.plugins[name]
  end
  if type(self.module_resolver) ~= "function" then
    errors.raise("UNSUPPORTED", "extension loading requires an approved module resolver", {
      capability = "extension_module_resolver",
    })
  end

  local ok, source, chunk_name = pcall(self.module_resolver, name, "init")
  if not ok then
    local failure = errors.normalize(source, "IO_ERROR", "resolve extension:" .. name)
    error(failure, 0)
  end
  if type(source) ~= "string" then
    errors.raise("NOT_FOUND", "extension entry module was not found", {
      extension = name,
      module = "init",
    })
  end
  if chunk_name ~= nil and (type(chunk_name) ~= "string" or chunk_name == "") then
    errors.raise("BAD_EXTENSION", "extension resolver returned an invalid chunk name", {
      extension = name,
    })
  end

  local load_options = {}
  for key, value in pairs(options) do load_options[key] = value end
  load_options.source = "resolver"
  load_options.chunk_name = chunk_name or ("@" .. name .. "/init.lua")
  return self:load(name, source, config, load_options)
end

function Manager:unload(name)
  local record = self.plugins[name]
  if not record then
    return false
  end

  -- The current extension contract calls unload() for explicit unloads, but
  -- not implicitly during Runtime shutdown or failed initialization.
  local ok, failure = true, nil
  if record.module.unload then
    ok, failure = pcall(record.module.unload)
  end

  self.commands:remove_owner(name)
  self.keymap:remove_owner(name)
  self.events:off_owner(name)
  if self.themes then self.themes:remove_owner(name) end
  if self.syntax then self.syntax:remove_owner(name) end
  if self.styles then self.styles:remove_owner(name) end
  self.plugins[name] = nil

  if not ok then
    local normalized = errors.normalize(failure, "BAD_EXTENSION", "plugin unload:" .. name)
    self.logger:child(name):error("extension unload failed", { code = normalized.code })
    error(normalized, 0)
  end
  self.logger:child(name):info("extension unloaded")
  return true
end

function Manager:list()
  local result = {}
  for name, record in pairs(self.plugins) do
    result[#result + 1] = {
      name = name,
      state = record.state,
      source = record.source,
    }
  end
  table.sort(result, function(a, b)
    return a.name < b.name
  end)
  return result
end

function Manager:shutdown()
  self.closed = true

  -- Preserve the current contract: don't call module.unload() on process exit.
  -- The Runtime owns final cleanup of these registries.
  for name in pairs(self.plugins) do
    self.commands:remove_owner(name)
    self.keymap:remove_owner(name)
    self.events:off_owner(name)
    if self.themes then self.themes:remove_owner(name) end
    if self.syntax then self.syntax:remove_owner(name) end
    if self.styles then self.styles:remove_owner(name) end
  end
  self.plugins = {}
end

return Manager
