-- Logger and Host-contract logging checks. Loaded from tests/unit/run.lua.
local A = require("support.assert")
local FakeHost = require("support.fake_host")
local Log = require("cdin.runtime.core.log")
local Contract = require("cdin.runtime.host.contract")

-- Level names and values must match CDIN_LOG_* in Kernel ABI 1.1.0.
A.equal(#Log.levels, 6)
A.equal(Log.kernel_value.error, 0); A.equal(Log.kernel_value.warn, 1); A.equal(Log.kernel_value.info, 2)
A.equal(Log.kernel_value.debug, 3); A.equal(Log.kernel_value.trace, 4); A.equal(Log.kernel_value.fatal, 5)

-- Records reach the Host with the logger-owned component.
local host = FakeHost.new()
local root = Log.new(host)
A.truthy(root:info("hello", { n = 1, ok = true, name = "x" }))
A.equal(#host.logs, 1)
A.equal(host.logs[1].level, "info"); A.equal(host.logs[1].message, "hello")
A.equal(host.logs[1].fields.component, "cdin-runtime"); A.equal(host.logs[1].fields.n, 1)
for _, level in ipairs(Log.levels) do A.truthy(root:log(level, "m")) end
A.equal(#host.logs, 7)

-- Child components compose and sanitize external names; callers cannot spoof the component.
local child = root:child("documents")
child:debug("d", { component = "kernel" })
A.equal(host.logs[#host.logs].fields.component, "cdin-runtime.documents")
-- Dots are replaced too, so a name cannot forge hierarchy.
root:child("bad name/../x"):info("e")
A.equal(host.logs[#host.logs].fields.component, "cdin-runtime.bad_name____x")
root:child(""):info("e")
A.equal(host.logs[#host.logs].fields.component, "cdin-runtime.unnamed")

-- Field sanitizing: scalars only, bounded count, bounded string size.
local before = root:stats().fields_dropped
local many = { nested = { 1 }, fn = print }
for i = 1, 30 do many["k" .. string.format("%02d", i)] = i end
root:info("fields", many)
local sent = host.logs[#host.logs].fields
local count = 0
for key in pairs(sent) do if key ~= "component" then count = count + 1 end end
A.equal(count, 16); A.equal(sent.nested, nil); A.equal(sent.fn, nil)
A.truthy(root:stats().fields_dropped > before)
root:info("long", { v = string.rep("a", 1000) })
A.equal(#host.logs[#host.logs].fields.v, 256)

-- Message truncation never splits a UTF-8 sequence and respects the limit.
local small = Log.new(FakeHost.new(), { max_message_bytes = 10 })
local small_host = small.core.host
small:info(string.rep("\u{00e9}", 10)) -- 20 bytes of two-byte characters
local cut = small_host.logs[1].message
A.truthy(#cut <= 10); A.equal(cut:sub(-3), "...")
A.truthy(utf8.len(cut:sub(1, -4)) ~= nil, "truncated text must stay valid UTF-8")
A.equal(small:stats().truncated, 1)
A.error_code(function() Log.new(host, { max_message_bytes = 0 }) end, "INVALID_ARGUMENT")
A.error_code(function() Log.new(host, { max_message_bytes = Log.max_message_bytes_limit + 1 }) end, "INVALID_ARGUMENT")
A.error_code(function() Log.new(host, { min_level = "loud" }) end, "INVALID_ARGUMENT")

-- A non-string message is converted; an unknown level becomes a warning.
root:info(42); A.equal(host.logs[#host.logs].message, "42")
root:log("loud", "odd")
A.equal(host.logs[#host.logs].level, "warn"); A.equal(host.logs[#host.logs].fields.requested_level, "loud")

-- Local pre-filter uses severity order, not CDIN_LOG_* numeric order.
local filtered_host = FakeHost.new()
local filtered = Log.new(filtered_host, { min_level = "warn" })
A.falsy(filtered:enabled("info")); A.truthy(filtered:enabled("error")); A.truthy(filtered:enabled("fatal"))
filtered:info("no"); filtered:debug("no"); filtered:warn("yes"); filtered:error("yes"); filtered:fatal("yes")
A.equal(#filtered_host.logs, 3); A.equal(filtered:stats().filtered, 2)

-- Kernel-side drops are counted, not raised; Host failures never escape.
local dropping_host = FakeHost.new({ log_min_level = "error" })
local dropping = Log.new(dropping_host)
A.falsy(dropping:info("below the Kernel threshold")); A.equal(dropping:stats().dropped, 1)
A.truthy(dropping:error("kept"))
local failing = Log.new(FakeHost.new({ log_fails = true }))
A.falsy(failing:error("boom")); A.equal(failing:stats().failed, 1)
A.falsy(Log.null():info("nowhere"))

-- Logging never writes to stdout/stderr by itself.
local real_print, real_write = print, io.write
local leaked = false
print = function() leaked = true end
io.write = function() leaked = true end
root:info("quiet"); failing:error("quiet"); Log.null():info("quiet")
print, io.write = real_print, real_write
A.falsy(leaked)

-- Host contract: the logging descriptor is mandatory and must name the Kernel logger.
local function mismatch(options) A.error_code(function() Contract.validate(FakeHost.new(options)) end, "HOST_API_MISMATCH") end
A.truthy(Contract.validate(FakeHost.new()).logging)
mismatch({ kernel_abi = { major = 1, minor = 0, patch = 0 } }) -- ABI 1.0.0 has no logging API
mismatch({ host_api = { major = 0, minor = 1, patch = 0 } })
mismatch({ logging = false })
mismatch({ logging = { provider = "other", levels = Log.levels, max_message_bytes = 1024 } })
mismatch({ logging = { provider = "cdin-kernel", levels = { "error", "warn", "info" }, max_message_bytes = 1024 } })
mismatch({ logging = { provider = "cdin-kernel", levels = Log.levels, max_message_bytes = 0 } })
mismatch({ logging = { provider = "cdin-kernel", levels = Log.levels, max_message_bytes = 2 ^ 21 } })
