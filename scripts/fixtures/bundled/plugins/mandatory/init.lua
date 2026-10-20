local M = { inits = 0 }
function M.init(core, config)
  M.inits = M.inits + 1
  M.saw_core = type(core) == "table"
  M.saw_config = type(config) == "table"
end
return M
