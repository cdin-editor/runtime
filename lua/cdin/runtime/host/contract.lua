local version = require("cdin.runtime.core.version")
local errors = require("cdin.runtime.core.error")

-- Validate the provisional Backend-to-Runtime boundary once at startup.
-- This is not the Kernel ABI: the Backend owns the native adapter and exposes
-- only these Lua services to the Runtime.
local M = {}

local function parse_version(value, label)
  if type(value) ~= "table" then
    errors.raise("HOST_API_MISMATCH", label .. " version is missing or malformed", { field = label })
  end
  for _, part in ipairs({ "major", "minor", "patch" }) do
    local number = value[part]
    if type(number) ~= "number" or number < 0 or number % 1 ~= 0 then
      errors.raise("HOST_API_MISMATCH", label .. " version is missing or malformed", { field = label, part = part })
    end
  end
  return value
end

local function require_compatible(provided, required, label)
  -- The Kernel ABI has a published compatibility contract: a newer minor
  -- version with the same major remains compatible with this Runtime.
  if provided.major ~= required.major or provided.minor < required.minor then
    errors.raise("HOST_API_MISMATCH", label .. " version is incompatible", {
      provided = provided, required = required,
    })
  end
end

local function require_provisional_match(provided, required, label)
  -- The Host API and Frontend Protocol are still 0.x contracts. Do not guess
  -- that a different minor version is compatible before the Spec says so.
  if provided.major ~= required.major or provided.minor ~= required.minor then
    errors.raise("HOST_API_MISMATCH", label .. " provisional major/minor must match exactly", {
      provided = provided, required = required,
    })
  end
end

function M.validate(host)
  if type(host) ~= "table" or type(host.info) ~= "function" then
    errors.raise("INVALID_ARGUMENT", "host must implement info()")
  end
  local info = host:info()
  if type(info) ~= "table" then errors.raise("HOST_API_MISMATCH", "host:info() must return a table") end
  local provided_host_api = parse_version(info.host_api, "host_api")
  -- Host API 0.x is deliberately provisional: no minor-version compatibility
  -- promise is made until a reviewed 1.0 contract is accepted.
  require_provisional_match(provided_host_api, version.host_api, "Runtime Host API")
  require_compatible(parse_version(info.kernel_abi, "kernel_abi"), version.kernel_abi, "Kernel ABI")
  require_provisional_match(
    parse_version(info.frontend_protocol, "frontend_protocol"),
    version.frontend_protocol,
    "Frontend Protocol"
  )
  if type(info.extension_contract) ~= "table"
      or type(info.extension_contract.major) ~= "number"
      or info.extension_contract.major ~= version.extension_contract.major then
    errors.raise("HOST_API_MISMATCH", "extension contract major version is incompatible", {
      provided = info.extension_contract,
      required = version.extension_contract,
    })
  end

  local features = info.features or {}
  if type(features) ~= "table" then
    errors.raise("HOST_API_MISMATCH", "host features must be a table")
  end
  local required_host_features = {
    "documents",
    "notifications",
    "snapshots",
    "transactions",
    "batch_edits",
    "literal_search",
    "ui_model",
    "logging",
  }
  for _, name in ipairs(required_host_features) do
    if features[name] ~= true then
      errors.raise("HOST_API_MISMATCH", "required host capability is unavailable", { capability = name })
    end
  end
  local kernel_features = info.kernel_features or {}
  if type(kernel_features) ~= "table" then
    errors.raise("HOST_API_MISMATCH", "kernel_features must be a table")
  end
  local required_kernel_features = {
    "transactions",
    "snapshots",
    "notifications",
    "batch",
    "search_literal",
    "search_bytes",
  }
  for _, name in ipairs(required_kernel_features) do
    if kernel_features[name] ~= true then
      errors.raise("HOST_API_MISMATCH", "required Kernel ABI feature is unavailable through Backend", {
        feature = name,
      })
    end
  end
  if kernel_features.search_regex == true then
    errors.raise("HOST_API_MISMATCH", "Backend advertised regex under Kernel ABI 1.0.0, where it is unsupported")
  end
  if type(host.documents) ~= "table" then
    errors.raise("HOST_API_MISMATCH", "host.documents service is missing")
  end
  for _, method in ipairs({
    "create", "close", "read", "replace", "replace_batch", "undo", "redo",
    "acquire_snapshot", "read_snapshot", "release_snapshot", "begin_transaction",
    "transaction_replace", "transaction_read", "commit_transaction", "abort_transaction",
    "mark_clean", "mark_clean_if_version", "is_clean", "subscribe", "unsubscribe", "drain", "search",
  }) do
    if type(host.documents[method]) ~= "function" then
      errors.raise("HOST_API_MISMATCH", "required document Host API method is missing", {
        method = method,
      })
    end
  end
  if type(host.ui) ~= "table" or type(host.ui.publish) ~= "function" then
    errors.raise("HOST_API_MISMATCH", "host.ui.publish(model) is required")
  end
  if type(host.log) ~= "function" then
    errors.raise("HOST_API_MISMATCH", "host.log(level, message, fields) is required")
  end
  return info
end

return M
