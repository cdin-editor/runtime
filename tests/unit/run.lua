local root = (arg and arg[0] or "tests/unit/run.lua"):match("^(.*)[/\\]tests[/\\]unit[/\\][^/\\]+$") or "."
package.path = root .. "/data/?.lua;" .. root .. "/data/?/init.lua;" .. package.path

local passed, failed = 0, {}
local function check(condition, message)
  passed = passed + 1
  if not condition then failed[#failed + 1] = message end
end
local function eq(actual, expected, message)
  check(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function is_error(err, code, message)
  check(type(err) == "table" and err.code == code, message .. ": expected error " .. code)
end

local Registry = require "core.runtime.registry"
local Errors = require "core.runtime.errors"
local Host = require "core.runtime.host"
local Contracts = require "core.runtime.contracts"

-- Registry: registration, duplicate safety, explicit replacement, stable order.
local reg = Registry.new({ label = "test command" })
eq(reg:count(), 0, "empty registry count")
eq(reg:register("beta", 2), true, "register beta")
eq(reg:register("alpha", 1), true, "register alpha")
eq(reg:get("alpha"), 1, "get alpha")
eq(reg:has("beta"), true, "has beta")
local ok, err = reg:register("alpha", 9)
eq(ok, nil, "duplicate rejected")
is_error(err, "DUPLICATE_REGISTRATION", "duplicate error")
eq(reg:get("alpha"), 1, "duplicate preserves original")
eq(reg:register("alpha", 3, true), true, "explicit overwrite")
eq(reg:get("alpha"), 3, "overwrite visible")
eq(table.concat(reg:names(), ","), "alpha,beta", "names sorted")
eq(reg:unregister("beta"), true, "unregister beta")
eq(reg:unregister("beta"), false, "missing unregister")
eq(reg:count(), 1, "count after unregister")
local bad, bad_err = reg:register("", {})
eq(bad, nil, "empty name rejected")
is_error(bad_err, "INVALID_ARGUMENT", "empty name error")
reg:clear(); eq(reg:count(), 0, "clear resets count")

-- Errors: stable codes, status mapping and safe treatment of unknown values.
local e = Errors.new("CUSTOM", "custom message", { field = "x" })
eq(Errors.is(e), true, "error record recognized")
eq(e.details.field, "x", "error details retained")
eq(Errors.from_status("CDIN_STALE_VERSION", { expected = 2 }).code, "STALE_VERSION", "Kernel status prefix stripped")
eq(Errors.from_status("NO_SUCH_STATUS").code, "UNKNOWN_STATUS", "unknown status stays failure")
eq(Errors.from_status(nil).code, "UNKNOWN_STATUS", "non-string status stays failure")

-- Version helpers reject malformed versions and retain the draft API boundary.
eq(Contracts.version_at_least({major=0,minor=1,patch=1}, {major=0,minor=1,patch=0}), true, "newer patch accepted")
eq(Contracts.version_at_least({major=0,minor=2,patch=0}, {major=0,minor=1,patch=0}), true, "newer minor accepted by helper")
eq(Contracts.version_at_least({major=1,minor=0,patch=0}, {major=0,minor=1,patch=0}), true, "newer major helper comparison")
eq(Contracts.version_at_least({major=-1,minor=0,patch=0}, {major=0,minor=0,patch=0}), false, "negative version rejected")
eq(Contracts.format_version({major=1,minor=2,patch=3}), "1.2.3", "version formatting")

-- Host validation: fully injected descriptor; no globals/SDL/Kernel linking.
local host_desc = {
  api_version = { major=0, minor=1, patch=0 },
  kernel_abi = { major=1, minor=0, patch=0 },
  capabilities = { notifications=true, ui_model=false },
  services = { doc={}, fs={}, path={}, system={}, search={} },
}
local host, host_err = Host.connect(host_desc)
check(host ~= nil, "valid host connects: " .. tostring(host_err and host_err.code))
eq(host:has_capability("notifications"), true, "capability true")
eq(host:has_capability("ui_model"), false, "capability false")
eq(host:service("doc"), host_desc.services.doc, "service injected")
local cap_ok, cap_err = host:require_capability("canvas")
eq(cap_ok, nil, "missing capability rejected")
is_error(cap_err, "UNSUPPORTED", "missing capability error")
local no_host, no_host_err = Host.connect(nil)
eq(no_host, nil, "nil host rejected")
is_error(no_host_err, "HOST_UNAVAILABLE", "nil host error")
local old_api = { api_version={major=0,minor=0,patch=9}, kernel_abi={major=1}, services={doc={},fs={},path={},system={}} }
local old, old_err = Host.connect(old_api)
eq(old, nil, "older Host API rejected")
is_error(old_err, "HOST_VERSION_MISMATCH", "old Host API error")
local newer_minor = { api_version={major=0,minor=2,patch=0}, kernel_abi={major=1}, services={doc={},fs={},path={},system={}} }
local nm, nm_err = Host.connect(newer_minor)
eq(nm, nil, "unreviewed v0 minor rejected")
is_error(nm_err, "HOST_VERSION_MISMATCH", "unreviewed v0 minor error")
local wrong_kernel = { api_version={major=0,minor=1,patch=0}, kernel_abi={major=2}, services={doc={},fs={},path={},system={}} }
local wk, wk_err = Host.connect(wrong_kernel)
eq(wk, nil, "wrong Kernel ABI rejected")
is_error(wk_err, "KERNEL_ABI_MISMATCH", "wrong Kernel ABI error")
local missing = { api_version={major=0,minor=1,patch=0}, kernel_abi={major=1}, services={doc={},fs={},path={}} }
local ms, ms_err = Host.connect(missing)
eq(ms, nil, "missing service rejected")
is_error(ms_err, "MISSING_SERVICE", "missing service error")

if #failed > 0 then
  io.stderr:write("Runtime unit tests FAILED (", #failed, "/", passed, ")\n")
  for _, msg in ipairs(failed) do io.stderr:write(" - ", msg, "\n") end
  os.exit(1)
end
print("Runtime unit tests: " .. passed .. " assertions passed")
