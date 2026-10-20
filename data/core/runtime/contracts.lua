-- Provisional Runtime/Host contract metadata. Not the Kernel ABI itself.
-- The Runtime version is deliberately pre-1.0 while host bindings are in migration.
local M = {}

M.RUNTIME_VERSION = { major = 0, minor = 1, patch = 0, stage = "dev" }
M.HOST_API_VERSION = { major = 0, minor = 1, patch = 0, stage = "provisional" }
M.REQUIRED_KERNEL_ABI_MAJOR = 1
M.EXTENSION_ENTRYPOINT = "init"
M.EXTENSION_INIT_SIGNATURE = "init(core, config)"
M.EXTENSION_UNLOAD_NAME = "unload"

function M.version_at_least(actual, required)
  if type(actual) ~= "table" or type(required) ~= "table" then return false end
  for _, key in ipairs({ "major", "minor", "patch" }) do
    if type(actual[key]) ~= "number" or actual[key] < 0 or actual[key] % 1 ~= 0 then
      return false
    end
    if type(required[key]) ~= "number" or required[key] < 0 or required[key] % 1 ~= 0 then
      return false
    end
  end
  if actual.major ~= required.major then return actual.major > required.major end
  if actual.minor ~= required.minor then return actual.minor > required.minor end
  return actual.patch >= required.patch
end

function M.format_version(v)
  if type(v) ~= "table" then return "unknown" end
  return string.format("%s.%s.%s", tostring(v.major), tostring(v.minor), tostring(v.patch))
end

return M
