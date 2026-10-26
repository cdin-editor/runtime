local errors = require("cdin.runtime.core.error")
local tablex = require("cdin.runtime.util.tablex")
local PaneTree = require("cdin.runtime.presentation.ui.pane_tree")

-- Model the editor state shared with a frontend. This is semantic state only:
-- it contains no pixel positions, rendering objects or document text.
local Model = {}
Model.__index = Model

function Model.new()
  return setmetatable({
    revision = 0,
    views = {},
    panels = {},
    focus = nil,
    prompt = nil,
    status = {},
    theme = "default",
    pane_tree = PaneTree.new(),
  }, Model)
end

function Model:add_view(view, options)
  options = options or {}
  if self.views[view.id] then
    errors.raise("DUPLICATE_REGISTRATION", "view already exists: " .. view.id)
  end
  if options.split_with ~= nil and not self.views[options.split_with] then
    errors.raise("NOT_FOUND", "split target view does not exist", {
      view_id = options.split_with,
    })
  end

  -- Update both structures as one operation. A rejected pane operation must
  -- not leave a view registered in the model without a pane-tree entry.
  self.views[view.id] = view
  local ok, failure = pcall(function()
    if options.split_with then
      self.pane_tree:split(
        options.split_with,
        view.id,
        options.axis or "vertical",
        options.ratio or 0.5
      )
    else
      self.pane_tree:add_view(view.id)
    end
  end)

  if not ok then
    self.views[view.id] = nil
    error(errors.normalize(failure), 0)
  end

  if options.split_with or not self.focus then
    self:set_focus(view.id)
  else
    self:_touch()
  end
  return true
end

function Model:remove_view(view_id)
  if not self.views[view_id] then
    return false
  end

  self.views[view_id] = nil
  self.pane_tree:remove_view(view_id)

  if self.focus == view_id then
    self.focus = nil
    for _, candidate_id in ipairs(self.pane_tree:list_views()) do
      if self.views[candidate_id] then
        self.focus = candidate_id
        break
      end
    end

    if self.focus then
      self.views[self.focus].focused = true
      self.pane_tree:focus(self.focus)
    end
  end

  self:_touch()
  return true
end

function Model:set_focus(view_id)
  if view_id ~= nil and not self.views[view_id] then
    errors.raise("NOT_FOUND", "cannot focus missing view", { view_id = view_id })
  end

  for _, view in pairs(self.views) do
    view.focused = false
  end

  self.focus = view_id
  if view_id then
    self.views[view_id].focused = true
    self.pane_tree:focus(view_id)
  end
  self:_touch()
end

function Model:focused_view()
  if not self.focus then
    return nil
  end
  return self.views[self.focus]
end

function Model:split_view(target_view_id, new_view_id, axis, ratio)
  if not self.views[target_view_id] or not self.views[new_view_id] then
    errors.raise("NOT_FOUND", "both views must exist before splitting", {
      target = target_view_id,
      new_view = new_view_id,
    })
  end

  self.pane_tree:split(target_view_id, new_view_id, axis, ratio)
  self:set_focus(new_view_id)
end

function Model:set_status(key, value)
  self.status[key] = value
  self:_touch()
end

function Model:set_prompt(prompt)
  self.prompt = prompt and tablex.copy(prompt) or nil
  self:_touch()
end

function Model:set_panel(name, panel)
  self.panels[name] = panel and tablex.copy(panel) or nil
  self:_touch()
end

function Model:set_theme(name)
  self.theme = name
  self:_touch()
end

function Model:_touch()
  self.revision = self.revision + 1
end

function Model:snapshot()
  local views = {}
  for view_id, view in pairs(self.views) do
    views[view_id] = view:snapshot()
  end

  return {
    schema = "cdin.ui-model.v1",
    revision = self.revision,
    views = views,
    -- The published name is retained for schema compatibility. It contains
    -- logical pane relationships, never frontend pixel geometry.
    layout = self.pane_tree:snapshot(),
    panels = tablex.copy(self.panels),
    focus = self.focus,
    prompt = tablex.copy(self.prompt),
    status = tablex.copy(self.status),
    theme = self.theme,
  }
end

return Model
