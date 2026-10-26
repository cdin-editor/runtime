local M = {}

M.codes = {
  INVALID_ARGUMENT = true,
  INVALID_HANDLE = true,
  STALE_VERSION = true,
  OUT_OF_RANGE = true,
  INVALID_POSITION = true,
  INVALID_STATE = true,
  BUSY = true,
  LIMIT_EXCEEDED = true,
  NO_MEMORY = true,
  PATTERN_INVALID = true,
  CANCELLED = true,
  SHUTDOWN = true,
  UNSUPPORTED = true,
  BUFFER_TOO_SMALL = true,
  VERSION_MISMATCH = true,
  INTERNAL = true,
  HOST_API_MISMATCH = true,
  BAD_EXTENSION = true,
  DUPLICATE_REGISTRATION = true,
  NOT_FOUND = true,
  PERMISSION_DENIED = true,
}

function M.new(code, message, details)
  if not M.codes[code] then
    code = "INTERNAL"
  end
  return {
    domain = "cdin.runtime",
    code = code,
    message = message or code,
    details = details or {},
  }
end

function M.raise(code, message, details, level)
  error(M.new(code, message, details), (level or 1) + 1)
end

function M.is(value)
  return type(value) == "table"
    and value.domain == "cdin.runtime"
    and type(value.code) == "string"
    and M.codes[value.code] == true
end

function M.normalize(value, fallback_code, context)
  if M.is(value) then
    if not context then
      return value
    end

    local details = M.copy_details and M.copy_details(value.details) or value.details
    local wrapped = M.new(value.code, value.message, details)
    wrapped.context = context
    return wrapped
  end

  local message = type(value) == "string" and value or tostring(value)
  local result = M.new(fallback_code or "INTERNAL", message, {})
  if context then
    result.context = context
  end
  return result
end

function M.protect(fn, ...)
  local arguments = table.pack(...)
  local results = table.pack(pcall(function()
    return fn(table.unpack(arguments, 1, arguments.n))
  end))
  if not results[1] then
    return false, M.normalize(results[2])
  end
  return true, table.unpack(results, 2, results.n)
end

function M.copy_details(details)
  local copy = {}
  for key, value in pairs(details or {}) do
    copy[key] = value
  end
  return copy
end

return M
