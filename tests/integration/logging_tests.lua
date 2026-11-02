-- End-to-end logging behaviour. Loaded from tests/integration/run.lua.
-- Runtime must send everything through host:log (the Kernel logger), keep
-- document content and paths out of records, and survive a broken logger.
local A = require("support.assert")
local FakeHost = require("support.fake_host")
local Runtime = require("cdin.runtime")

local function find(host, predicate)
  for _, record in ipairs(host.logs) do
    if predicate(record) then return record end
  end
end

local host = FakeHost.new()
local runtime = Runtime.new({ host = host })
runtime:start()

-- Startup record: info, runtime component, versions as plain strings.
local started = find(host, function(r) return r.message == "runtime started" end)
A.truthy(started); A.equal(started.level, "info")
A.equal(started.fields.component, "cdin-runtime")
A.equal(started.fields.host_api, "0.2.0"); A.equal(started.fields.kernel_abi, "1.1.0")

-- Document lifecycle is logged by id/version/size, never by content or path.
local document = runtime:open_document("TOP-SECRET-CONTENT", { path = "/home/user/private-notes.txt" })
local opened = find(host, function(r) return r.message == "document opened" end)
A.truthy(opened); A.equal(opened.level, "debug")
A.equal(opened.fields.component, "cdin-runtime.documents"); A.equal(opened.fields.length, 18)
document:replace(0, 3, "x")
runtime.saver:save(document, "/home/user/private-notes.txt")
A.truthy(find(host, function(r) return r.message == "document saved" end))
for _, record in ipairs(host.logs) do
  local text = record.message
  for _, value in pairs(record.fields) do text = text .. tostring(value) end
  A.falsy(text:find("SECRET", 1, true), "document content leaked into a log record")
  A.falsy(text:find("private-notes", 1, true), "document path leaked into a log record")
end

-- Extension records get the extension's own component and cannot spoof another.
runtime.plugins:load("logger-sample", [[return { init = function(core)
  core:log("info", "from extension", { component = "cdin-kernel", answer = 42 })
  core:log("loud", "bad level")
end }]], {})
local ext = find(host, function(r) return r.message == "from extension" end)
A.equal(ext.fields.component, "cdin-runtime.extension.logger-sample"); A.equal(ext.fields.answer, 42)
A.equal(find(host, function(r) return r.message == "bad level" end).level, "warn")
A.truthy(find(host, function(r) return r.message == "extension loaded" end))

-- Every record Runtime sent was valid for the Kernel logger (FakeHost rejects bad levels/messages).
A.equal(runtime:log_stats().failed, 0); A.truthy(runtime:log_stats().sent > 5)

A.truthy(runtime:shutdown())
A.truthy(find(host, function(r) return r.message == "runtime stopped" end))

-- A Host whose logger raises must not break any operation.
local broken = FakeHost.new({ log_fails = true })
local quiet = Runtime.new({ host = broken })
quiet:start()
local doc = quiet:open_document("abc")
doc:replace(0, 1, "z")
A.truthy(quiet:shutdown())
A.truthy(quiet:log_stats().failed > 0); A.equal(#broken.logs, 0)

-- Startup failure is logged as an error with its code (the logger is still usable).
local old_abi = FakeHost.new({ kernel_abi = { major = 1, minor = 0, patch = 0 } })
local rejected = Runtime.new({ host = old_abi })
A.error_code(function() rejected:start() end, "HOST_API_MISMATCH")
A.equal(rejected.state, "failed")
local failure = find(old_abi, function(r) return r.message == "runtime startup failed" end)
A.truthy(failure); A.equal(failure.level, "error"); A.equal(failure.fields.code, "HOST_API_MISMATCH")

-- The message limit reported by the Host is honoured.
local tight = FakeHost.new({ max_message_bytes = 32 })
local tight_runtime = Runtime.new({ host = tight })
tight_runtime:start()
tight_runtime.log:info(string.rep("m", 100))
for _, record in ipairs(tight.logs) do A.truthy(#record.message <= 32) end
tight_runtime:shutdown()
