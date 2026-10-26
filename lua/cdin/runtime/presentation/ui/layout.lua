local errors = require("cdin.runtime.core.error")
local tablex = require("cdin.runtime.util.tablex")
local Layout = {}
Layout.__index = Layout

local function leaf(id, view_id)
  return { kind = "leaf", id = id, views = { view_id }, active_view = view_id }
end

function Layout.new()
  return setmetatable({ root = nil, next_id = 0, active_leaf = nil }, Layout)
end

function Layout:_id(prefix)
  self.next_id = self.next_id + 1
  return (prefix or "node") .. "-" .. self.next_id
end

local function find_leaf(node, view_id)
  if not node then return nil end
  if node.kind == "leaf" then
    for _, id in ipairs(node.views) do if id == view_id then return node end end
    return nil
  end
  return find_leaf(node.first, view_id) or find_leaf(node.second, view_id)
end

local function insert_split(node, target, split_node)
  if node == target then return split_node end
  if not node or node.kind == "leaf" then return node end
  node.first = insert_split(node.first, target, split_node)
  node.second = insert_split(node.second, target, split_node)
  return node
end

local function remove_from(node, view_id)
  if not node then return nil, false end
  if node.kind == "leaf" then
    for index, id in ipairs(node.views) do
      if id == view_id then
        table.remove(node.views, index)
        if node.active_view == view_id then node.active_view = node.views[1] end
        if #node.views == 0 then return nil, true end
        return node, true
      end
    end
    return node, false
  end
  local first, removed_first = remove_from(node.first, view_id)
  node.first = first
  if removed_first then
    if not node.first then return node.second, true end
    return node, true
  end
  local second, removed_second = remove_from(node.second, view_id)
  node.second = second
  if removed_second then
    if not node.second then return node.first, true end
    return node, true
  end
  return node, false
end

function Layout:add_view(view_id)
  if type(view_id) ~= "string" or view_id == "" then errors.raise("INVALID_ARGUMENT", "layout view id is required") end
  if find_leaf(self.root, view_id) then errors.raise("DUPLICATE_REGISTRATION", "view is already present in layout", { view_id = view_id }) end
  if not self.root then
    self.root = leaf(self:_id("leaf"), view_id)
    self.active_leaf = self.root.id
  else
    local target = self.active_leaf and self:_find_leaf_id(self.active_leaf) or self.root
    if not target then target = self.root end
    target.views[#target.views + 1] = view_id
    target.active_view = view_id
  end
end

function Layout:_find_leaf_id(id, node)
  node = node or self.root
  if not node then return nil end
  if node.kind == "leaf" and node.id == id then return node end
  if node.kind == "split" then return self:_find_leaf_id(id, node.first) or self:_find_leaf_id(id, node.second) end
  return nil
end

function Layout:focus(view_id)
  local target = find_leaf(self.root, view_id)
  if not target then errors.raise("NOT_FOUND", "view is not in layout", { view_id = view_id }) end
  target.active_view = view_id
  self.active_leaf = target.id
  return true
end

function Layout:split(target_view_id, new_view_id, axis, ratio)
  if type(target_view_id) ~= "string" or type(new_view_id) ~= "string" or target_view_id == new_view_id then
    errors.raise("INVALID_ARGUMENT", "split requires two distinct view ids")
  end
  axis = axis or "vertical"; ratio = ratio or 0.5
  if axis ~= "vertical" and axis ~= "horizontal" then errors.raise("INVALID_ARGUMENT", "split axis must be vertical or horizontal") end
  if type(ratio) ~= "number" or ratio <= 0.1 or ratio >= 0.9 then errors.raise("INVALID_ARGUMENT", "split ratio must be between 0.1 and 0.9") end
  if find_leaf(self.root, new_view_id) then errors.raise("DUPLICATE_REGISTRATION", "new split view already exists", { view_id = new_view_id }) end
  local target = find_leaf(self.root, target_view_id)
  if not target then errors.raise("NOT_FOUND", "split target view is not in layout", { view_id = target_view_id }) end
  local old = tablex.copy(target)
  local new_leaf = leaf(self:_id("leaf"), new_view_id)
  local split = { kind = "split", id = self:_id("split"), axis = axis, ratio = ratio, first = old, second = new_leaf }
  self.root = insert_split(self.root, target, split)
  self.active_leaf = new_leaf.id
  return true
end

local function first_leaf(node)
  if not node then return nil end
  if node.kind == "leaf" then return node end
  return first_leaf(node.first) or first_leaf(node.second)
end

function Layout:remove_view(view_id)
  local root, removed = remove_from(self.root, view_id)
  if not removed then return false end
  self.root = root
  if not root then
    self.active_leaf = nil
  elseif not self:_find_leaf_id(self.active_leaf) then
    local fallback = first_leaf(root)
    self.active_leaf = fallback and fallback.id or nil
  end
  return true
end

function Layout:list_views()
  local result = {}
  local function visit(node)
    if not node then return end
    if node.kind == "leaf" then
      for _, id in ipairs(node.views) do result[#result + 1] = id end
    else visit(node.first); visit(node.second) end
  end
  visit(self.root)
  return result
end

function Layout:snapshot()
  return { root = tablex.copy(self.root), active_leaf = self.active_leaf }
end

return Layout
