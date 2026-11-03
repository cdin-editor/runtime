local errors = require("cdin.runtime.core.error")

-- Runtime logging facade.
--
-- CDIN has exactly one logger: the Kernel's (m-mdy-m/log.c, reached through
-- `cdin_kernel_log`). Runtime never links, loads or configures a logger of its
-- own. It hands records to Host API `host:log(level, message, fields)`, and the
-- Backend forwards them to the Kernel. This module only shapes records so they
-- are valid on that path and makes sure logging can never break an operation.
--
-- Runtime does not write to stdout/stderr; the Kernel logger decides where a
-- record goes and which severities are kept.

local M = {}

-- Level names and their numeric values mirror CDIN_LOG_* in
-- include/cdin/kernel.h (Kernel ABI 1.1.0). The Backend maps names to values.
M.levels = { "error", "warn", "info", "debug", "trace", "fatal" }
M.kernel_value = { error = 0, warn = 1, info = 2, debug = 3, trace = 4, fatal = 5 }

-- CDIN_LOG_* numbers are not ordered by severity (FATAL is 5, ERROR is 0), so
-- threshold checks use this ranking instead of the numeric values.
local rank = { trace = 1, debug = 2, info = 3, warn = 4, error = 5, fatal = 6 }

-- The only logger provider Runtime accepts, as reported by `host:info()`.
M.provider = "cdin-kernel"
M.default_component = "cdin-runtime"

-- CDIN_LOG_DEFAULT_MAX_MESSAGE_BYTES and CDIN_LOG_MAX_MESSAGE_BYTES.
M.default_max_message_bytes = 16 * 1024
M.max_message_bytes_limit = 1024 * 1024

-- Field limits keep one record bounded no matter what a caller passes.
local MAX_FIELDS = 16
local MAX_KEY_BYTES = 64
local MAX_VALUE_BYTES = 256
local MAX_COMPONENT_PART_BYTES = 64
local ELLIPSIS = "..."

function M.is_level(name)
  return rank[name] ~= nil
end

function M.valid_max_message_bytes(value)
  return type(value) == "number"
    and value % 1 == 0
    and value >= 1
    and value <= M.max_message_bytes_limit
end

-- Cut `text` to at most `limit` bytes without splitting a UTF-8 sequence.
local function truncate(text, limit)
  if #text <= limit then
    return text, false
  end
  if limit <= #ELLIPSIS then
    return text:sub(1, limit), true
  end

  local cut = limit - #ELLIPSIS
  -- If the byte after the cut is a continuation byte (10xxxxxx), the cut falls
  -- inside a sequence: step back until it lands on a sequence boundary.
  while cut > 0 do
    local following = text:byte(cut + 1)
    if following and following >= 0x80 and following < 0xC0 then
      cut = cut - 1
    else
      break
    end
  end
  return text:sub(1, cut) .. ELLIPSIS, true
end

-- Keep only flat scalar fields. Nested tables, functions and userdata are
-- dropped rather than stringified so a record never leaks addresses or large
-- structures. `component` is owned by the logger, never by the caller.
local function sanitize_fields(fields, component, stats)
  local clean, count = {}, 0
  if type(fields) == "table" then
    local keys = {}
    for key in pairs(fields) do
      if type(key) == "string" and key ~= "" and key ~= "component" then
        keys[#keys + 1] = key
      end
    end
    table.sort(keys)

    for _, key in ipairs(keys) do
      local value = fields[key]
      local kind = type(value)
      local scalar = kind == "string" or kind == "number" or kind == "boolean"
      if not scalar or #key > MAX_KEY_BYTES or count >= MAX_FIELDS then
        stats.fields_dropped = stats.fields_dropped + 1
      else
        if kind == "string" then
          value = truncate(value, MAX_VALUE_BYTES)
        end
        clean[key] = value
        count = count + 1
      end
    end
  end
  clean.component = component
  return clean
end

local Logger = {}
Logger.__index = Logger

local function validate_min_level(level)
  if rank[level] == nil then
    errors.raise("INVALID_ARGUMENT", "unknown log level", { level = tostring(level) })
  end
  return rank[level]
end

-- Create a root logger. `host` may be nil to build a logger that discards
-- everything (see M.null). `min_level` is only a local pre-filter that avoids
-- work for records nobody wants; the Kernel threshold stays authoritative.
function M.new(host, options)
  options = options or {}
  if host ~= nil and type(host) ~= "table" then
    errors.raise("INVALID_ARGUMENT", "logger host must be a table")
  end

  local max_bytes = options.max_message_bytes or M.default_max_message_bytes
  if not M.valid_max_message_bytes(max_bytes) then
    errors.raise("INVALID_ARGUMENT", "max_message_bytes must be an integer from 1 to 1 MiB", {
      max_message_bytes = tostring(max_bytes),
    })
  end

  local core = {
    host = host,
    min_rank = validate_min_level(options.min_level or "trace"),
    max_message_bytes = max_bytes,
    stats = {
      sent = 0,       -- accepted by the Host
      dropped = 0,    -- the Host reported the record was not accepted
      failed = 0,     -- the Host raised or the record could not be built
      filtered = 0,   -- removed by the local min_level pre-filter
      truncated = 0,  -- message shortened to max_message_bytes
      fields_dropped = 0,
    },
  }
  return setmetatable({
    core = core,
    component = options.component or M.default_component,
  }, Logger)
end

-- A logger that accepts calls and discards them. Used where no Host exists.
function M.null()
  return M.new(nil)
end

-- Change shared settings, for example after the Host reports its message limit.
function Logger:configure(options)
  options = options or {}
  local core = self.core
  if options.max_message_bytes ~= nil then
    if not M.valid_max_message_bytes(options.max_message_bytes) then
      errors.raise("INVALID_ARGUMENT", "max_message_bytes must be an integer from 1 to 1 MiB")
    end
    core.max_message_bytes = options.max_message_bytes
  end
  if options.min_level ~= nil then
    core.min_rank = validate_min_level(options.min_level)
  end
  return self
end

-- Derive a logger for a sub-component, for example "cdin-runtime.documents".
-- The name often comes from outside (an extension name), so it is sanitized
-- instead of rejected: creating a logger must never fail.
function Logger:child(name)
  local part = tostring(name):gsub("[^%w_%-]", "_")
  if part == "" then
    part = "unnamed"
  end
  part = part:sub(1, MAX_COMPONENT_PART_BYTES)
  return setmetatable({
    core = self.core,
    component = self.component .. "." .. part,
  }, Logger)
end

function Logger:enabled(level)
  local value = rank[level]
  return value ~= nil and value >= self.core.min_rank
end

function Logger:stats()
  local copy = {}
  for key, value in pairs(self.core.stats) do
    copy[key] = value
  end
  return copy
end

local function emit(self, level, message, fields)
  local core = self.core
  local stats = core.stats

  -- A bad level from a caller (typically an extension) is still worth seeing,
  -- so it is recorded as a warning instead of being discarded.
  local requested
  if rank[level] == nil then
    requested = tostring(level)
    level = "warn"
  end

  if rank[level] < core.min_rank then
    stats.filtered = stats.filtered + 1
    return false
  end
  if core.host == nil then
    stats.dropped = stats.dropped + 1
    return false
  end

  if type(message) ~= "string" then
    message = tostring(message)
  end
  local shortened
  message, shortened = truncate(message, core.max_message_bytes)
  if shortened then
    stats.truncated = stats.truncated + 1
  end

  local clean = sanitize_fields(fields, self.component, stats)
  if requested then
    clean.requested_level = truncate(requested, MAX_VALUE_BYTES)
  end

  local accepted = core.host:log(level, message, clean)
  if accepted == false then
    stats.dropped = stats.dropped + 1
    return false
  end
  stats.sent = stats.sent + 1
  return true
end

-- Send one record. Returns true when the Host accepted it. Never raises: a
-- logging failure must not mask the operation being reported (Host API 0.3).
function Logger:log(level, message, fields)
  local ok, result = pcall(emit, self, level, message, fields)
  if ok then
    return result
  end
  local stats = self.core.stats
  stats.failed = stats.failed + 1
  return false
end

for _, name in ipairs(M.levels) do
  Logger[name] = function(self, message, fields)
    return self:log(name, message, fields)
  end
end

return M
