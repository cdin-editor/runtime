local errors = require("cdin.runtime.core.error")
local tablex = require("cdin.runtime.util.tablex")

-- Keeps lightweight project identity only. File discovery and disk access are
-- provided by the Backend or an extension with the right capability.
local Context = {}
Context.__index = Context

function Context.new(event_bus)
  return setmetatable({
    root = nil,
    name = nil,
    metadata = {},
    event_bus = event_bus,
  }, Context)
end

function Context:set(root, options)
  options = options or {}

  if root ~= nil and (type(root) ~= "string" or root == "") then
    errors.raise("INVALID_ARGUMENT", "project root must be a non-empty path")
  end
  if options.name ~= nil and (type(options.name) ~= "string" or options.name == "") then
    errors.raise("INVALID_ARGUMENT", "project name must be a non-empty string")
  end
  if options.metadata ~= nil and type(options.metadata) ~= "table" then
    errors.raise("INVALID_ARGUMENT", "project metadata must be a table")
  end

  local before = {
    root = self.root,
    name = self.name,
  }
  self.root = root
  self.name = options.name or (root and root:match("([^/\\]+)[/\\]*$"))
  self.metadata = tablex.copy(options.metadata or {})

  if self.event_bus then
    self.event_bus:emit("project.changed", {
      before = before,
      after = {
        root = self.root,
        name = self.name,
      },
    })
  end
end

function Context:snapshot()
  return {
    root = self.root,
    name = self.name,
    metadata = tablex.copy(self.metadata),
  }
end

return Context
