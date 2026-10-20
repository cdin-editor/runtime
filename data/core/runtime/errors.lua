-- Stable Lua error records for Runtime/Host boundaries; independent of C/Lua globals.
local M = {}

local MESSAGES = {
  INVALID_ARGUMENT = "Invalid argument",
  INVALID_HANDLE = "Invalid or closed handle",
  STALE_VERSION = "Document version is stale",
  OUT_OF_RANGE = "Range is outside the available data",
  INVALID_POSITION = "Position is not valid UTF-8 boundary",
  INVALID_STATE = "Operation is invalid in the current state",
  BUSY = "Resource is busy",
  LIMIT_EXCEEDED = "Configured limit exceeded",
  NO_MEMORY = "Allocation failed",
  PATTERN_INVALID = "Search pattern is invalid",
  CANCELLED = "Operation cancelled",
  SHUTDOWN = "Service is shutting down",
  UNSUPPORTED = "Operation or feature is unsupported",
  BUFFER_TOO_SMALL = "Output buffer is too small",
  VERSION_MISMATCH = "Version is incompatible",
  INTERNAL = "Internal component error",
  HOST_UNAVAILABLE = "Runtime host is unavailable",
  HOST_VERSION_MISMATCH = "Runtime host API version is incompatible",
  KERNEL_ABI_MISMATCH = "Kernel ABI version is incompatible",
  MISSING_SERVICE = "Required host service is missing",
  DUPLICATE_REGISTRATION = "Name is already registered",
  UNKNOWN_STATUS = "Unknown status returned by host",
}

function M.new(code, message, details)
  assert(type(code) == "string" and code ~= "", "error code must be a non-empty string")
  return { code = code, message = message or MESSAGES[code] or code, details = details }
end

function M.is(value)
  return type(value) == "table"
    and type(value.code) == "string"
    and type(value.message) == "string"
end

function M.from_status(status, details, message_overrides)
  if type(status) ~= "string" then
    return M.new("UNKNOWN_STATUS", nil, { status = status, source = details })
  end
  local code = status:gsub("^CDIN_", "")
  if not MESSAGES[code] then
    return M.new("UNKNOWN_STATUS", nil, { status = status, source = details })
  end
  local override = type(message_overrides) == "table" and message_overrides[code] or nil
  return M.new(code, override or MESSAGES[code], details)
end

function M.raise(err, level)
  assert(M.is(err), "expected a Runtime error record")
  error(err, (level or 1) + 1)
end

M.messages = MESSAGES
return M
