local errors = require("cdin.runtime.core.error")

local Registry = {}
Registry.__index = Registry

function Registry.new()
  return setmetatable({
    languages = {},
    extensions = {},
  }, Registry)
end

function Registry:register(name, definition, options)
  options = options or {}

  if type(name) ~= "string" or name == "" or type(definition) ~= "table" then
    errors.raise("INVALID_ARGUMENT", "syntax definition requires name and table")
  end
  if type(definition.tokenize) ~= "function" then
    errors.raise("INVALID_ARGUMENT", "syntax definition requires tokenize(bytes)")
  end
  if self.languages[name] and not options.overwrite then
    errors.raise("DUPLICATE_REGISTRATION", "syntax already exists: " .. name)
  end

  local extensions = {}
  local seen = {}
  for _, extension in ipairs(definition.extensions or {}) do
    if type(extension) ~= "string" then
      errors.raise("INVALID_ARGUMENT", "syntax extensions must be strings")
    end

    local normalized = extension:lower():gsub("^%.", "")
    if normalized == "" then
      errors.raise("INVALID_ARGUMENT", "syntax extension cannot be empty")
    end
    if seen[normalized] then
      errors.raise("INVALID_ARGUMENT", "syntax extension is repeated", {
        extension = normalized,
      })
    end
    seen[normalized] = true

    local existing_language = self.extensions[normalized]
    if existing_language and existing_language ~= name and not options.overwrite then
      errors.raise("DUPLICATE_REGISTRATION", "syntax extension already belongs to another language", {
        extension = normalized,
        language = existing_language,
      })
    end
    extensions[#extensions + 1] = normalized
  end

  if options.overwrite and self.languages[name] then
    for extension, language in pairs(self.extensions) do
      if language == name then
        self.extensions[extension] = nil
      end
    end
  end

  self.languages[name] = {
    name = name,
    tokenize = definition.tokenize,
    owner = options.owner or "core",
    extensions = extensions,
  }
  for _, extension in ipairs(extensions) do
    self.extensions[extension] = name
  end
  return true
end

function Registry:get(name)
  return self.languages[name]
end

function Registry:for_path(path)
  local value = tostring(path or "")
  local filename = value:match("([^/\\]+)$") or value
  local extension = filename:match("%.([^%.]+)$")
  if not extension then
    return nil
  end
  return self.languages[self.extensions[extension:lower()]]
end

function Registry:list()
  local result = {}
  for name in pairs(self.languages) do
    result[#result + 1] = name
  end
  table.sort(result)
  return result
end

return Registry
