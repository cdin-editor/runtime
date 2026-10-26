-- Public CDIN Runtime entry point. Keep bootstrapping here so all application
-- modules are loaded only after undeclared globals have been disabled.
local strict = require("cdin.runtime.core.strict")
strict.install(_G)

return require("cdin.runtime.application")
