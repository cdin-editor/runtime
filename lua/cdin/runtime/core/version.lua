-- Runtime version resolution.
--
-- Normal source checkouts derive the version from Git tags. Release archives
-- receive a tiny generated release_metadata.lua module during packaging because
-- source archives intentionally do not include the .git directory.

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
  local redirect = command_error_redirect()
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

  -- Release archives have no .git metadata, so the release workflow generates
  -- this module from the tag. It is deliberately not committed to the repo.
  local ok, packaged = pcall(require, "cdin.runtime.core.release_metadata")
  if ok and type(packaged) == "string" and packaged ~= "" then
    return packaged
  end

  return "0.0.0-dev"
end

return {
  runtime = resolve_runtime_version(),
  host_api = { major = 0, minor = 1, patch = 0 },
  kernel_abi = { major = 1, minor = 0, patch = 0 },
  frontend_protocol = { major = 0, minor = 1, patch = 0 },
  extension_contract = { major = 1, minor = 0 },
  -- The Frontend Protocol is still provisional. Backend negotiates transport;
  -- Runtime validates the negotiated version and never owns the wire protocol.
}
