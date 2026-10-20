-- Narrow, injectable Runtime Host adapter. The old CDIN globals remain in use
-- by the copied compatibility core; this adapter is for the staged host API.
local Contracts = require "core.runtime.contracts"
local Errors = require "core.runtime.errors"

local Host = {}
Host.__index = Host

local function valid_triplet(v)
  return type(v) == "table"
    and type(v.major) == "number" and v.major >= 0 and v.major % 1 == 0
    and type(v.minor) == "number" and v.minor >= 0 and v.minor % 1 == 0
    and type(v.patch) == "number" and v.patch >= 0 and v.patch % 1 == 0
end

function Host.connect(raw, options)
  options = options or {}
  if type(raw) ~= "table" then
    return nil, Errors.new("HOST_UNAVAILABLE", "host must be a table")
  end
  local api_version = raw.api_version
  if not valid_triplet(api_version) then
    return nil, Errors.new("HOST_VERSION_MISMATCH", "host.api_version must contain integer major/minor/patch fields")
  end
  local required_api = options.required_api_version or Contracts.HOST_API_VERSION
  if not valid_triplet(required_api) or api_version.major ~= required_api.major
     or api_version.minor ~= required_api.minor or api_version.patch < required_api.patch then
    return nil, Errors.new("HOST_VERSION_MISMATCH", "Runtime Host API version is incompatible", {
      provided = Contracts.format_version(api_version),
      required = Contracts.format_version(required_api),
    })
  end

  local kernel_abi = raw.kernel_abi
  local required_major = options.required_kernel_abi_major or Contracts.REQUIRED_KERNEL_ABI_MAJOR
  if type(kernel_abi) ~= "table" or kernel_abi.major ~= required_major then
    return nil, Errors.new("KERNEL_ABI_MISMATCH", "Host does not provide the required Kernel ABI major", {
      provided = type(kernel_abi) == "table" and kernel_abi.major or nil,
      required = required_major,
    })
  end

  if type(raw.services) ~= "table" then
    return nil, Errors.new("HOST_UNAVAILABLE", "host.services must be a table")
  end
  local required_services = options.required_services or { "doc", "fs", "path", "system" }
  for _, name in ipairs(required_services) do
    if type(raw.services[name]) ~= "table" then
      return nil, Errors.new("MISSING_SERVICE", "Missing host service: " .. tostring(name), { service = name })
    end
  end

  local caps = raw.capabilities or {}
  if type(caps) ~= "table" then
    return nil, Errors.new("INVALID_ARGUMENT", "host.capabilities must be a table")
  end
  return setmetatable({
    api_version = api_version,
    kernel_abi = kernel_abi,
    services = raw.services,
    capabilities = caps,
    metadata = raw.metadata or {},
  }, Host)
end

function Host:service(name)
  return self.services[name]
end

function Host:has_capability(name)
  return self.capabilities[name] == true
end

function Host:require_capability(name)
  if self:has_capability(name) then return true end
  return nil, Errors.new("UNSUPPORTED", "Host capability is unavailable: " .. tostring(name), { capability = name })
end

return Host
