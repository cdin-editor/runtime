local errors = require("cdin.runtime.core.error")
local tablex = require("cdin.runtime.util.tablex")

-- PaneTree stores logical view relationships shared by all frontends.
-- Pixel geometry, wrapping, font metrics, bidi and rendering belong elsewhere.
local PaneTree = {}
PaneTree.__index = PaneTree

local function make_leaf(id, view_id)
  return {
    kind = "leaf",
    id = id,
    views = { view_id },
    active_view = view_id,
  }
end

function PaneTree.new()
  return setmetatable({
    root = nil,
    next_id = 0,
    active_leaf = nil,
  }, PaneTree)
end

function PaneTree:_next_id(prefix)
  self.next_id = self.next_id + 1
  return (prefix or "node") .. "-" .. self.next_id
end

local function find_leaf_for_view(node, view_id)
  if not node then
    return nil
  end

  if node.kind == "leaf" then
    for _, candidate_id in ipairs(node.views) do
      if candidate_id == view_id then
        return node
      end
    end
    return nil
  end

  return find_leaf_for_view(node.first, view_id)
    or find_leaf_for_view(node.second, view_id)
end

local function find_leaf_by_id(node, leaf_id)
  if not node then
    return nil
  end

  if node.kind == "leaf" then
    if node.id == leaf_id then
      return node
    end
    return nil
  end

  return find_leaf_by_id(node.first, leaf_id)
    or find_leaf_by_id(node.second, leaf_id)
end

local function replace_node(node, target, replacement)
  if node == target then
    return replacement
  end
  if not node or node.kind == "leaf" then
    return node
  end

  node.first = replace_node(node.first, target, replacement)
  node.second = replace_node(node.second, target, replacement)
  return node
end

local function remove_view_from(node, view_id)
  if not node then
    return nil, false
  end

  if node.kind == "leaf" then
    for index, candidate_id in ipairs(node.views) do
      if candidate_id == view_id then
        table.remove(node.views, index)

        if node.active_view == view_id then
          node.active_view = node.views[1]
        end
        if #node.views == 0 then
          return nil, true
        end
        return node, true
      end
    end
    return node, false
  end

  local first, removed_first = remove_view_from(node.first, view_id)
  node.first = first
  if removed_first then
    if not node.first then
      return node.second, true
    end
    return node, true
  end

  local second, removed_second = remove_view_from(node.second, view_id)
  node.second = second
  if removed_second then
    if not node.second then
      return node.first, true
    end
    return node, true
  end

  return node, false
end

local function first_leaf(node)
  if not node then
    return nil
  end
  if node.kind == "leaf" then
    return node
  end
  return first_leaf(node.first) or first_leaf(node.second)
end

function PaneTree:add_view(view_id)
  if type(view_id) ~= "string" or view_id == "" then
    errors.raise("INVALID_ARGUMENT", "pane view id is required")
  end
  if find_leaf_for_view(self.root, view_id) then
    errors.raise("DUPLICATE_REGISTRATION", "view is already present in pane tree", {
      view_id = view_id,
    })
  end

  if not self.root then
    self.root = make_leaf(self:_next_id("leaf"), view_id)
    self.active_leaf = self.root.id
    return true
  end

  local target = find_leaf_by_id(self.root, self.active_leaf) or self.root
  target.views[#target.views + 1] = view_id
  target.active_view = view_id
  return true
end

function PaneTree:focus(view_id)
  local target = find_leaf_for_view(self.root, view_id)
  if not target then
    errors.raise("NOT_FOUND", "view is not in pane tree", { view_id = view_id })
  end

  target.active_view = view_id
  self.active_leaf = target.id
  return true
end

function PaneTree:split(target_view_id, new_view_id, axis, ratio)
  if type(target_view_id) ~= "string"
      or type(new_view_id) ~= "string"
      or target_view_id == new_view_id then
    errors.raise("INVALID_ARGUMENT", "split requires two distinct view ids")
  end

  axis = axis or "vertical"
  ratio = ratio or 0.5
  if axis ~= "vertical" and axis ~= "horizontal" then
    errors.raise("INVALID_ARGUMENT", "split axis must be vertical or horizontal")
  end
  if type(ratio) ~= "number" or ratio <= 0.1 or ratio >= 0.9 then
    errors.raise("INVALID_ARGUMENT", "split ratio must be between 0.1 and 0.9")
  end
  if find_leaf_for_view(self.root, new_view_id) then
    errors.raise("DUPLICATE_REGISTRATION", "new split view already exists", {
      view_id = new_view_id,
    })
  end

  local target = find_leaf_for_view(self.root, target_view_id)
  if not target then
    errors.raise("NOT_FOUND", "split target view is not in pane tree", {
      view_id = target_view_id,
    })
  end

  -- Copy the old leaf because it becomes the first child of a new split node.
  local previous_leaf = tablex.copy(target)
  local next_leaf = make_leaf(self:_next_id("leaf"), new_view_id)
  local split_node = {
    kind = "split",
    id = self:_next_id("split"),
    axis = axis,
    ratio = ratio,
    first = previous_leaf,
    second = next_leaf,
  }

  self.root = replace_node(self.root, target, split_node)
  self.active_leaf = next_leaf.id
  return true
end

function PaneTree:remove_view(view_id)
  local next_root, removed = remove_view_from(self.root, view_id)
  if not removed then
    return false
  end

  self.root = next_root
  if not self.root then
    self.active_leaf = nil
  elseif not find_leaf_by_id(self.root, self.active_leaf) then
    local fallback = first_leaf(self.root)
    self.active_leaf = fallback and fallback.id or nil
  end
  return true
end

function PaneTree:list_views()
  local result = {}

  local function visit(node)
    if not node then
      return
    end
    if node.kind == "leaf" then
      for _, view_id in ipairs(node.views) do
        result[#result + 1] = view_id
      end
      return
    end

    visit(node.first)
    visit(node.second)
  end

  visit(self.root)
  return result
end

function PaneTree:snapshot()
  return {
    root = tablex.copy(self.root),
    active_leaf = self.active_leaf,
  }
end

return PaneTree
