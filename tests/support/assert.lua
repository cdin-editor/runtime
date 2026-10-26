local M = {}
M.count = 0
function M.truthy(value, message)
  M.count = M.count + 1
  if not value then error(message or "expected truthy value", 2) end
end
function M.falsy(value, message) M.truthy(not value, message or "expected falsy value") end
function M.equal(actual, expected, message)
  M.count = M.count + 1
  if actual ~= expected then error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end
function M.same(actual, expected, message) M.equal(actual, expected, message) end
function M.error_code(fn, expected)
  M.count = M.count + 1
  local ok, err = pcall(fn)
  if ok then error("expected structured error " .. expected, 2) end
  if type(err) ~= "table" or err.code ~= expected then
    error("expected error code " .. expected .. ", got " .. tostring(type(err) == "table" and err.code or err), 2)
  end
  return err
end
function M.report(label) io.write("PASS ", label, " (", M.count, " assertions)\n") end
return M
