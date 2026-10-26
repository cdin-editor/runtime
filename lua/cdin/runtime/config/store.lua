local errors = require("cdin.runtime.core.error")
local tablex = require("cdin.runtime.util.tablex")

local Store = {}
Store.__index = Store

-- Higher layers override lower ones when a value is read.
local layers = {
  defaults = 1,
  user = 2,
  project = 3,
  session = 4,
}

local lookup_order = { "session", "project", "user", "defaults" }
local merge_order = { "defaults", "user", "project", "session" }

local function validate_layer(layer, allow_defaults)
  if not layers[layer] or (layer == "defaults" and not allow_defaults) then
    errors.raise("INVALID_ARGUMENT", "invalid mutable config layer", {
      layer = layer,
    })
  end
end

function Store.new(schema, defaults)
  if schema ~= nil and type(schema) ~= "table" then
    errors.raise("INVALID_ARGUMENT", "configuration schema must be a table")
  end
  if defaults ~= nil and type(defaults) ~= "table" then
    errors.raise("INVALID_ARGUMENT", "configuration defaults must be a table")
  end

  local self = setmetatable({
    schema = tablex.copy(schema or {}),
    values = {
      defaults = {},
      user = {},
      project = {},
      session = {},
    },
  }, Store)

  for path, definition in pairs(self.schema) do
    if type(path) ~= "string" or path == "" or type(definition) ~= "table" then
      errors.raise(
        "INVALID_ARGUMENT",
        "configuration schema entries must map string paths to tables"
      )
    end
  end

  for path, value in pairs(defaults or {}) do
    if not self.schema[path] then
      self.schema[path] = { default = tablex.copy(value) }
    end
    self.values.defaults[path] = self:_validate(path, value)
  end

  for path, definition in pairs(self.schema) do
    if definition.default ~= nil and self.values.defaults[path] == nil then
      self.values.defaults[path] = self:_validate(path, definition.default)
    end
  end

  return self
end

function Store:define(path, validator, default_value, options)
  options = options or {}

  if type(path) ~= "string" or path == "" then
    errors.raise("INVALID_ARGUMENT", "config path is required")
  end
  if self.schema[path] and not options.overwrite then
    errors.raise("DUPLICATE_REGISTRATION", "configuration key already exists: " .. path)
  end
  if validator ~= nil and type(validator) ~= "function" then
    errors.raise("INVALID_ARGUMENT", "configuration validator must be a function")
  end
  if default_value ~= nil and validator then
    local valid = validator(default_value)
    if not valid then
      errors.raise("INVALID_ARGUMENT", "invalid configuration default", {
        path = path,
      })
    end
  end

  local new_rule = {
    validate = validator,
    default = tablex.copy(default_value),
  }
  for layer, values in pairs(self.values) do
    if values[path] ~= nil and new_rule.validate then
      local valid, reason = new_rule.validate(values[path])
      if not valid then
        errors.raise("INVALID_ARGUMENT", "new validator rejects an existing configuration value", {
          path = path,
          layer = layer,
          reason = reason,
        })
      end
    end
  end

  self.schema[path] = new_rule
  if default_value ~= nil then
    self.values.defaults[path] = tablex.copy(default_value)
  end
end

function Store:_validate(path, value)
  local rule = self.schema[path]
  if not rule then
    errors.raise("INVALID_ARGUMENT", "unknown configuration key: " .. path, {
      path = path,
    })
  end

  if rule.validate then
    local valid, reason = rule.validate(value)
    if not valid then
      errors.raise("INVALID_ARGUMENT", "invalid configuration value", {
        path = path,
        reason = reason,
      })
    end
  end

  return tablex.copy(value)
end

function Store:set(layer, path, value)
  validate_layer(layer, false)
  self.values[layer][path] = self:_validate(path, value)
end

function Store:unset(layer, path)
  validate_layer(layer, false)
  if not self.schema[path] then
    errors.raise("INVALID_ARGUMENT", "unknown configuration key: " .. tostring(path), {
      path = path,
    })
  end

  self.values[layer][path] = nil
end

function Store:load(layer, values)
  validate_layer(layer, false)
  if type(values) ~= "table" then
    errors.raise("INVALID_ARGUMENT", "configuration layer must be a table")
  end

  -- Validate into a copy first so a single bad value cannot partially apply
  -- the incoming layer.
  local next_values = tablex.copy(self.values[layer])
  for path, value in pairs(values) do
    next_values[path] = self:_validate(path, value)
  end
  self.values[layer] = next_values
end

function Store:get(path)
  for _, layer in ipairs(lookup_order) do
    local value = self.values[layer][path]
    if value ~= nil then
      return tablex.copy(value)
    end
  end
  return nil
end

function Store:effective()
  local result = {}
  for _, layer in ipairs(merge_order) do
    for path, value in pairs(self.values[layer]) do
      result[path] = tablex.copy(value)
    end
  end
  return result
end

function Store:snapshot()
  return tablex.copy(self.values)
end

function Store:restore(snapshot)
  if type(snapshot) ~= "table" then
    errors.raise("INVALID_ARGUMENT", "configuration snapshot must be a table")
  end

  for layer in pairs(layers) do
    if type(snapshot[layer]) ~= "table" then
      errors.raise("INVALID_ARGUMENT", "invalid configuration snapshot", {
        layer = layer,
      })
    end
    for path, value in pairs(snapshot[layer]) do
      self:_validate(path, value)
    end
  end

  self.values = tablex.copy(snapshot)
end

return Store
