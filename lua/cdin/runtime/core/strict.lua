-- Strict global environment for the trusted Runtime modules.
-- Standard Lua globals are read through a private allowlist; the actual _G
-- table is made empty so both new global reads and all global writes fail.
local safe_pairs = pairs
local safe_rawset = rawset
local safe_getmetatable = getmetatable
local safe_setmetatable = setmetatable
local safe_tostring = tostring
local safe_error = error
local installed = setmetatable({}, { __mode = "k" })
local M = {}

function M.install(environment)
  environment = environment or _G
  if installed[environment] then return false end
  local allowed = {}
  for key, value in safe_pairs(environment) do
    allowed[key] = value
    safe_rawset(environment, key, nil)
  end
  local prior = safe_getmetatable(environment)
  safe_setmetatable(environment, {
    __index = function(_, key)
      local value = allowed[key]
      if value ~= nil then return value end
      safe_error("strict runtime: read of undeclared global '" .. safe_tostring(key) .. "'", 2)
    end,
    __newindex = function(_, key)
      safe_error("strict runtime: write to global '" .. safe_tostring(key) .. "' is forbidden", 2)
    end,
    __metatable = prior or false,
  })
  installed[environment] = true
  return true
end

return M
