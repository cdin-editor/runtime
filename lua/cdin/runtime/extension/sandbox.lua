local errors = require("cdin.runtime.core.error")

-- The sandbox restricts Lua globals and module loading. It is a capability
-- boundary inside one process, not a substitute for OS-level isolation.
local Sandbox = {}
Sandbox.__index = Sandbox

local function readonly(source, label)
  return setmetatable({}, {
    __index = source,
    __newindex = function(_, key)
      errors.raise("PERMISSION_DENIED", "extension cannot mutate standard library", {
        library = label,
        key = key,
      })
    end,
    __metatable = false,
  })
end

function Sandbox.new(options)
  options = options or {}
  return setmetatable({
    module_resolver = options.module_resolver,
    cache = {},
    active = {},
  }, Sandbox)
end

function Sandbox:_environment(plugin_name)
  local values = {
    assert = assert,
    error = error,
    ipairs = ipairs,
    pairs = pairs,
    next = next,
    pcall = pcall,
    xpcall = xpcall,
    select = select,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    unpack = table.unpack,
    math = readonly(math, "math"),
    string = readonly(string, "string"),
    table = readonly(table, "table"),
    utf8 = utf8 and readonly(utf8, "utf8") or nil,
    _VERSION = _VERSION,
  }
  local environment = {}
  values._G = environment

  values.require = function(module_name)
    if type(module_name) ~= "string" or module_name == "" then
      errors.raise("INVALID_ARGUMENT", "require name must be a string")
    end
    if self.cache[module_name] ~= nil then
      return self.cache[module_name]
    end
    if self.active[module_name] then
      errors.raise("BAD_EXTENSION", "cyclic extension module load", {
        module = module_name,
      })
    end
    if type(self.module_resolver) ~= "function" then
      errors.raise("PERMISSION_DENIED", "extension module loading is disabled", {
        module = module_name,
      })
    end

    local source, chunk_name = self.module_resolver(plugin_name, module_name)
    if type(source) ~= "string" then
      errors.raise("NOT_FOUND", "extension module not found", {
        module = module_name,
      })
    end

    self.active[module_name] = true
    local chunk, compile_error = load(
      source,
      "@" .. tostring(chunk_name or module_name),
      "t",
      environment
    )
    if not chunk then
      self.active[module_name] = nil
      errors.raise("BAD_EXTENSION", "cannot compile extension module", {
        module = module_name,
        reason = compile_error,
      })
    end

    local ok, result = pcall(chunk)
    self.active[module_name] = nil
    if not ok then
      errors.raise("BAD_EXTENSION", "extension module failed", {
        module = module_name,
        cause = tostring(result),
      })
    end
    if result == nil then
      result = true
    end

    self.cache[module_name] = result
    return result
  end

  return setmetatable(environment, {
    __index = function(_, key)
      local value = values[key]
      if value ~= nil then
        return value
      end
      errors.raise("PERMISSION_DENIED", "extension attempted to read an undeclared global", {
        plugin = plugin_name,
        global = key,
      })
    end,
    __newindex = function(_, key)
      errors.raise("PERMISSION_DENIED", "extension attempted to create or replace a global", {
        plugin = plugin_name,
        global = key,
      })
    end,
    __metatable = false,
  })
end

function Sandbox:load(plugin_name, source, core_facade, config, chunk_name)
  if type(source) ~= "string" then
    errors.raise("INVALID_ARGUMENT", "extension entry source must be a string")
  end

  -- A Sandbox instance belongs to one extension load. Reset module state so a
  -- repeated explicit load cannot see cached modules from the previous entry.
  self.cache = {}
  self.active = {}

  local environment = self:_environment(plugin_name)
  local chunk, compile_error = load(
    source,
    "@" .. tostring(chunk_name or plugin_name),
    "t",
    environment
  )
  if not chunk then
    errors.raise("BAD_EXTENSION", "cannot compile extension entry", {
      plugin = plugin_name,
      reason = compile_error,
    })
  end

  local ok, module = pcall(chunk)
  if not ok then
    errors.raise("BAD_EXTENSION", "extension entry failed", {
      plugin = plugin_name,
      cause = tostring(module),
    })
  end
  if type(module) ~= "table" then
    errors.raise("BAD_EXTENSION", "extension entry must return a table", {
      plugin = plugin_name,
    })
  end
  if module.init ~= nil and type(module.init) ~= "function" then
    errors.raise("BAD_EXTENSION", "extension init must be a function", {
      plugin = plugin_name,
    })
  end
  if module.unload ~= nil and type(module.unload) ~= "function" then
    errors.raise("BAD_EXTENSION", "extension unload must be a function", {
      plugin = plugin_name,
    })
  end

  if module.init then
    local init_ok, init_error = pcall(module.init, core_facade, config)
    if not init_ok then
      errors.raise("BAD_EXTENSION", "extension init failed", {
        plugin = plugin_name,
        cause = tostring(init_error),
      })
    end
  end

  return module
end

return Sandbox
