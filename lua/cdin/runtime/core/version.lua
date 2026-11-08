-- Runtime version resolution.
--
-- Normal source checkouts derive the version from Git tags. Registry-collected
-- source snapshots and release archives also carry release_metadata.lua because
-- they may not include usable .git history and must report their package version.

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function read_command(command)
  if not (io and io.popen) then
    return nil
  end

  local ok, pipe = pcall(io.popen, command, "r")
  if not ok or not pipe then
    return nil
  end

  local read_ok, output = pcall(function()
    return pipe:read("*a")
  end)
  pcall(function()
    pipe:close()
  end)

  if not read_ok or type(output) ~= "string" then
    return nil
  end

  output = trim(output)
  return output ~= "" and output or nil
end

local function command_error_redirect()
  local separator = package and package.config and package.config:sub(1, 1)
  return separator == "\\" and " 2>NUL" or " 2>/dev/null"
end

local function repository_root()
  if not (debug and debug.getinfo) then
    return nil
  end

  local info = debug.getinfo(1, "S")
  local source = info and info.source
  if type(source) ~= "string" then
    return nil
  end

  source = source:gsub("^@", ""):gsub("\\", "/")
  if source:match("^lua/cdin/runtime/core/version%.lua$") then
    return "."
  end

  local root = source:gsub("/lua/cdin/runtime/core/version%.lua$", "")
  if root ~= source then
    return root ~= "" and root or "/"
  end
  return nil
end

local function git_command(arguments)
  local root = repository_root()
  if not root then
    return "git " .. arguments
  end

  local separator = package and package.config and package.config:sub(1, 1)
  if separator == "\\" then
    root = root:gsub('"', '\\"')
    return 'git -C "' .. root .. '" ' .. arguments
  end

  root = root:gsub("'", "'\\''")
  return "git -C '" .. root .. "' " .. arguments
end

local function from_git()
  local root = repository_root()
  if not root then
    return nil
  end

  local redirect = command_error_redirect()
  local git_top = read_command(git_command("rev-parse --show-toplevel") .. redirect)
  if not git_top then
    return nil
  end

  -- Installed Runtime modules may live inside another Git checkout (for
  -- example, CDIN's share/cdin/lua tree). Git walks upward from -C and would
  -- otherwise report the host application's version as the Runtime version.
  -- An empty --show-prefix means root is the top-level of the Git repository;
  -- a non-empty prefix means this is only a nested installation directory.
  local git_prefix = read_command(git_command("rev-parse --show-prefix") .. redirect)
  if git_prefix ~= nil then
    return nil
  end

  local describe = read_command(
    git_command('describe --tags --long --dirty --match "v[0-9]*"') .. redirect
  )

  if describe then
    local dirty = describe:sub(-6) == "-dirty"
    if dirty then
      describe = describe:sub(1, -7)
    end

    local tag, distance, hash = describe:match("^(v?.+)%-(%d+)%-g([%da-fA-F]+)$")
    if tag then
      tag = tag:gsub("^v", "")
      distance = tonumber(distance)

      if distance == 0 and not dirty then
        return tag
      end

      local base, prerelease = tag:match("^([^%-]+)%-(.+)$")
      local version
      if distance == 0 then
        if prerelease then
          version = base .. "-" .. prerelease .. ".dirty"
        else
          version = tag .. "-dev"
        end
      elseif prerelease then
        version = base .. "-" .. prerelease .. ".next." .. distance
      else
        version = tag .. "-dev." .. distance
      end

      version = version .. "+g" .. hash
      if dirty then
        version = version .. ".dirty"
      end
      return version
    end
  end

  -- A repository without any version tags still gets a useful, unique dev ID.
  local hash = read_command(git_command("rev-parse --short=12 HEAD") .. redirect)
  if hash then
    local status = read_command(git_command("status --porcelain --untracked-files=no") .. redirect)
    local suffix = status and status ~= "" and ".dirty" or ""
    return "0.0.0-dev+g" .. hash .. suffix
  end

  return nil
end

local function resolve_runtime_version()
  -- Explicit overrides are useful in packaging and downstream build systems.
  local override = os and os.getenv and os.getenv("CDIN_RUNTIME_VERSION")
  if override and override ~= "" then
    return override:gsub("^v", "")
  end

  -- Git tags are authoritative in source checkouts, so a stale generated
  -- metadata module can never override a newer tag.
  local detected = from_git()
  if detected then
    return detected
  end

  -- Registry-collected source snapshots and release archives may not contain
  -- usable .git metadata; their embedded module binds the immutable package version.
  local ok, packaged = pcall(require, "cdin.runtime.core.release_metadata")
  if ok and type(packaged) == "string" and packaged ~= "" then
    return packaged
  end

  return "0.0.0-dev"
end

return {
  runtime = resolve_runtime_version(),
  -- Stable Host API 1.0.0 freezes the Backend-to-Runtime Lua boundary.
  host_api = { major = 1, minor = 0, patch = 0 },
  -- Kernel ABI 1.1.0 is the first release with the logging API
  -- (`cdin_kernel_log`, `cdin_log_options`) that the Host API relies on.
  kernel_abi = { major = 1, minor = 1, patch = 0 },
  frontend_protocol = { major = 1, minor = 0, patch = 0 },
  extension_contract = { major = 1, minor = 0 },
  -- Frontend Protocol 1.0.0 is the stable wire contract. Backend owns transport
  -- negotiation; Runtime validates the reported version and owns no wire codec.
}
