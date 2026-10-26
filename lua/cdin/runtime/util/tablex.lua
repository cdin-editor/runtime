local M = {}

function M.copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local result = {}
  seen[value] = result
  for key, item in pairs(value) do
    result[M.copy(key, seen)] = M.copy(item, seen)
  end
  return result
end

function M.merge(base, override)
  local result = M.copy(base or {})
  for key, value in pairs(override or {}) do
    if type(value) == "table" and type(result[key]) == "table" then
      result[key] = M.merge(result[key], value)
    else
      result[key] = M.copy(value)
    end
  end
  return result
end

function M.is_array(value)
  if type(value) ~= "table" then return false end
  local count, highest = 0, 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
    count = count + 1
    if key > highest then highest = key end
  end
  return count == highest
end

function M.sorted_keys(value)
  local keys = {}
  for key in pairs(value or {}) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

function M.get_path(value, path)
  local current = value
  for segment in tostring(path):gmatch("[^%.]+") do
    if type(current) ~= "table" then return nil end
    current = current[segment]
  end
  return current
end

function M.set_path(value, path, item)
  local segments = {}
  for segment in tostring(path):gmatch("[^%.]+") do segments[#segments + 1] = segment end
  assert(#segments > 0, "path cannot be empty")
  local current = value
  for index = 1, #segments - 1 do
    local segment = segments[index]
    if type(current[segment]) ~= "table" then current[segment] = {} end
    current = current[segment]
  end
  current[segments[#segments]] = item
end

return M
