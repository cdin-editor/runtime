local errors = require("cdin.runtime.core.error")

local P = {
  MAX_STYLE_BYTES = 32768, MAX_STYLE_ROLES = 256, MAX_PANELS = 16,
  MAX_WIDGETS_PER_PANEL = 128, MAX_WIDGET_DEPTH = 16, MAX_TOTAL_WIDGETS = 1024,
  MAX_TEXT_BYTES = 16384, MAX_PRESENTATION_BYTES = 131072,
  DEFAULT_INPUT_BYTES = 4096, MAX_INPUT_BYTES = 16384,
}

local attributes = {
  foreground = "rgba", background = "rgba", bold = "bool", italic = "bool",
  underline = "bool", strikethrough = "bool", dim = "bool", inverse = "bool",
}

local function invalid(field, message, details)
  details = details or {}; details.field = field
  errors.raise("INVALID_ARGUMENT", message, details)
end

local function text(value, field, limit, empty)
  if type(value) ~= "string" or (not empty and value == "") then
    invalid(field, field .. " must be " .. (empty and "text" or "non-empty text"))
  end
  if #value > limit then invalid(field, field .. " exceeds its byte limit", { limit = limit, actual = #value }) end
  local _, position = utf8.len(value)
  if position then invalid(field, field .. " must contain valid UTF-8", { byte = position }) end
  return true
end

local function bool(value, field)
  if value ~= nil and type(value) ~= "boolean" then invalid(field, field .. " must be boolean") end
end

local function integer(value, field, minimum, maximum)
  if type(value) ~= "number" or value % 1 ~= 0 or value < minimum or value > maximum then
    invalid(field, field .. " is outside its integer range", { minimum = minimum, maximum = maximum })
  end
end

local function array(value, field)
  if type(value) ~= "table" or getmetatable(value) ~= nil then invalid(field, field .. " must be an array") end
  local count, maximum = 0, 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then invalid(field, field .. " must be a dense array") end
    count = count + 1; if key > maximum then maximum = key end
  end
  if count ~= maximum then invalid(field, field .. " must be a dense array") end
  return count
end

local function estimate(value, depth)
  depth = depth or 0
  if depth > 24 then invalid("presentation", "presentation data is too deeply nested") end
  local kind = type(value)
  if kind == "nil" then return 1 end
  if kind == "boolean" or kind == "number" then return 8 end
  if kind == "string" then return #value + 8 end
  if kind ~= "table" or getmetatable(value) ~= nil then invalid("presentation", "presentation data must be serializable") end
  local total = 8
  for key, item in pairs(value) do
    if type(key) ~= "string" and (type(key) ~= "number" or key < 1 or key % 1 ~= 0) then
      invalid("presentation", "presentation map keys must be text")
    end
    if type(key) == "string" then total = total + #key end
    total = total + estimate(item, depth + 1)
    if total > P.MAX_PRESENTATION_BYTES then errors.raise("LIMIT_EXCEEDED", "presentation snapshot exceeds its byte limit", { limit = P.MAX_PRESENTATION_BYTES }) end
  end
  return total
end

function P.validate_style_role(name)
  text(name, "style role", 64, false)
  if not name:match("^[A-Za-z0-9][A-Za-z0-9._%-]*$") then invalid("style role", "invalid style-role identifier") end
end

local function rgba(value, field)
  if type(value) ~= "table" or getmetatable(value) ~= nil then invalid(field, field .. " must be an RGBA map") end
  for _, channel in ipairs({ "r", "g", "b", "a" }) do integer(value[channel], field .. "." .. channel, 0, 255) end
  for key in pairs(value) do
    if key ~= "r" and key ~= "g" and key ~= "b" and key ~= "a" then invalid(field, "unknown RGBA channel", { channel = tostring(key) }) end
  end
end

function P.validate_style(style, field)
  field = field or "style"
  if type(style) ~= "table" or getmetatable(style) ~= nil then invalid(field, "style must be a map") end
  for key, value in pairs(style) do
    local expected = attributes[key]
    if not expected then invalid(field, "unsupported style attribute", { attribute = tostring(key) }) end
    if expected == "rgba" then rgba(value, field .. "." .. key) else bool(value, field .. "." .. key) end
  end
end

function P.validate_style_table(styles)
  if type(styles) ~= "table" or getmetatable(styles) ~= nil then invalid("styles", "style table must be a map") end
  local count = 0
  for role, style in pairs(styles) do
    count = count + 1; P.validate_style_role(role); P.validate_style(style, "styles." .. role)
  end
  if count > P.MAX_STYLE_ROLES then errors.raise("LIMIT_EXCEEDED", "style-role count exceeds its limit", { limit = P.MAX_STYLE_ROLES }) end
  if estimate(styles) > P.MAX_STYLE_BYTES then errors.raise("LIMIT_EXCEEDED", "style table exceeds its byte limit", { limit = P.MAX_STYLE_BYTES }) end
end

local function action(value, field, reserve_value)
  if type(value) ~= "table" or getmetatable(value) ~= nil then invalid(field, "action must be a map") end
  text(value.command, field .. ".command", 128, false)
  if value.arguments ~= nil then
    if type(value.arguments) ~= "table" or getmetatable(value.arguments) ~= nil then invalid(field .. ".arguments", "arguments must be a map") end
    for key in pairs(value.arguments) do if type(key) ~= "string" then invalid(field .. ".arguments", "argument keys must be text") end end
    if reserve_value and value.arguments.value ~= nil then invalid(field .. ".arguments.value", "input actions reserve the value argument") end
    estimate(value.arguments)
  end
end

local function common(widget, field, state)
  if type(widget) ~= "table" or getmetatable(widget) ~= nil then invalid(field, "widget must be a map") end
  text(widget.id, field .. ".id", 128, false); text(widget.kind, field .. ".kind", 64, false)
  bool(widget.enabled, field .. ".enabled"); bool(widget.visible, field .. ".visible")
  if widget.accessible_label ~= nil then text(widget.accessible_label, field .. ".accessible_label", P.MAX_TEXT_BYTES, true) end
  if state.ids[widget.id] then invalid(field .. ".id", "duplicate widget ID", { id = widget.id }) end
  state.ids[widget.id] = true; state.total = state.total + 1
end

local function tree_node(node, field, depth, state, seen)
  if depth > P.MAX_WIDGET_DEPTH then errors.raise("LIMIT_EXCEEDED", "tree widget nesting exceeds its limit", { limit = P.MAX_WIDGET_DEPTH }) end
  if type(node) ~= "table" or getmetatable(node) ~= nil then invalid(field, "tree node must be a map") end
  text(node.id, field .. ".id", 128, false); text(node.label, field .. ".label", P.MAX_TEXT_BYTES, true)
  if seen[node.id] then invalid(field .. ".id", "duplicate tree-node ID", { id = node.id }) end
  seen[node.id] = true; state.total = state.total + 1
  bool(node.expanded, field .. ".expanded"); bool(node.enabled, field .. ".enabled")
  if node.activate ~= nil then action(node.activate, field .. ".activate") end
  if node.children ~= nil then
    local count = array(node.children, field .. ".children")
    for i = 1, count do tree_node(node.children[i], field .. ".children[" .. i .. "]", depth + 1, state, seen) end
  end
end

local function widget(value, field, depth, state)
  if depth > P.MAX_WIDGET_DEPTH then errors.raise("LIMIT_EXCEEDED", "widget nesting exceeds its limit", { limit = P.MAX_WIDGET_DEPTH }) end
  common(value, field, state)
  local kind = value.kind
  if kind == "label" then
    text(value.text, field .. ".text", P.MAX_TEXT_BYTES, true)
    if value.role ~= nil then P.validate_style_role(value.role) end
  elseif kind == "text" then
    local count = array(value.runs, field .. ".runs")
    for i = 1, count do
      local run = value.runs[i]
      if type(run) ~= "table" or getmetatable(run) ~= nil then invalid(field .. ".runs", "text run must be a map") end
      text(run.text, field .. ".runs[" .. i .. "].text", P.MAX_TEXT_BYTES, true)
      if run.role ~= nil then P.validate_style_role(run.role) end
    end
  elseif kind == "list" then
    local count = array(value.items, field .. ".items"); local seen = {}
    for i = 1, count do
      local item, name = value.items[i], field .. ".items[" .. i .. "]"
      if type(item) ~= "table" or getmetatable(item) ~= nil then invalid(name, "list item must be a map") end
      text(item.id, name .. ".id", 128, false); text(item.label, name .. ".label", P.MAX_TEXT_BYTES, true)
      if seen[item.id] then invalid(name .. ".id", "duplicate list item ID") end
      seen[item.id] = true
      if item.detail ~= nil then text(item.detail, name .. ".detail", P.MAX_TEXT_BYTES, true) end
      bool(item.enabled, name .. ".enabled"); if item.activate ~= nil then action(item.activate, name .. ".activate") end
      state.total = state.total + 1
    end
    if value.selected_id ~= nil then text(value.selected_id, field .. ".selected_id", 128, false) end
  elseif kind == "tree" then
    local count = array(value.nodes, field .. ".nodes"); local seen = {}
    for i = 1, count do tree_node(value.nodes[i], field .. ".nodes[" .. i .. "]", 1, state, seen) end
  elseif kind == "button" then
    text(value.label, field .. ".label", P.MAX_TEXT_BYTES, true); action(value.activate, field .. ".activate")
  elseif kind == "input" then
    text(value.value, field .. ".value", P.MAX_TEXT_BYTES, true)
    if value.placeholder ~= nil then text(value.placeholder, field .. ".placeholder", P.MAX_TEXT_BYTES, true) end
    local limit = value.max_bytes == nil and P.DEFAULT_INPUT_BYTES or value.max_bytes
    integer(limit, field .. ".max_bytes", 1, P.MAX_INPUT_BYTES)
    if #value.value > limit then invalid(field .. ".value", "input value exceeds max_bytes", { limit = limit }) end
    bool(value.multiline, field .. ".multiline"); action(value.submit, field .. ".submit", true)
  else
    -- Unknown kinds are preserved for the Frontend's static, non-interactive fallback.
    if value.label ~= nil then text(value.label, field .. ".label", P.MAX_TEXT_BYTES, true) end
    if value.text ~= nil then text(value.text, field .. ".text", P.MAX_TEXT_BYTES, true) end
  end
  if state.total > P.MAX_TOTAL_WIDGETS then errors.raise("LIMIT_EXCEEDED", "presentation widget count exceeds its limit", { limit = P.MAX_TOTAL_WIDGETS }) end
end

local function widgets(list, field, state)
  local count = array(list, field)
  if count > P.MAX_WIDGETS_PER_PANEL then errors.raise("LIMIT_EXCEEDED", field .. " exceeds its widget limit", { limit = P.MAX_WIDGETS_PER_PANEL }) end
  for i = 1, count do widget(list[i], field .. "[" .. i .. "]", 1, state) end
end

function P.validate_panel(panel_id, panel)
  text(panel_id, "panel_id", 128, false)
  if type(panel) ~= "table" or getmetatable(panel) ~= nil then invalid("panel", "panel must be a map") end
  if panel.id ~= nil and panel.id ~= panel_id then invalid("panel.id", "panel.id must match its outer ID") end
  text(panel.kind, "panel.kind", 64, false) -- unknown kinds degrade to content in compatible Frontends
  text(panel.title, "panel.title", P.MAX_TEXT_BYTES, true)
  bool(panel.visible, "panel.visible"); bool(panel.focusable, "panel.focusable"); bool(panel.scrollable, "panel.scrollable")
  if panel.selected_widget_id ~= nil then text(panel.selected_widget_id, "panel.selected_widget_id", 128, false) end
  local state = { total = 0, ids = {} }; widgets(panel.widgets, "panel.widgets", state)
  estimate(panel)
end

function P.validate_prompt(prompt)
  if prompt == nil then return end
  if type(prompt) ~= "table" or getmetatable(prompt) ~= nil then invalid("prompt", "prompt must be a map") end
  text(prompt.id, "prompt.id", 128, false); text(prompt.title, "prompt.title", P.MAX_TEXT_BYTES, true)
  if prompt.message ~= nil then text(prompt.message, "prompt.message", P.MAX_TEXT_BYTES, true) end
  bool(prompt.visible, "prompt.visible"); if prompt.cancel ~= nil then action(prompt.cancel, "prompt.cancel") end
  state = state or { total = 0, ids = {} }; widgets(prompt.widgets, "prompt.widgets", state)
  estimate(prompt)
  return state
end

function P.validate_snapshot(panels, prompt, styles)
  local count, total_widgets, total_bytes = 0, 0, 0
  for id, panel in pairs(panels or {}) do
    count = count + 1
    if count > P.MAX_PANELS then errors.raise("LIMIT_EXCEEDED", "panel count exceeds its limit", { limit = P.MAX_PANELS }) end
    local state = P.validate_panel(id, panel, { total = total_widgets, ids = {} })
    total_widgets = state.total
    total_bytes = total_bytes + estimate(panel)
  end
  local prompt_state = P.validate_prompt(prompt, { total = total_widgets, ids = {} })
  total_widgets = prompt_state and prompt_state.total or total_widgets
  P.validate_style_table(styles or {})
  total_bytes = total_bytes + estimate(prompt) + estimate(styles or {})
  if total_widgets > P.MAX_TOTAL_WIDGETS then
    errors.raise("LIMIT_EXCEEDED", "presentation widget count exceeds its limit", { limit = P.MAX_TOTAL_WIDGETS })
  end
  if total_bytes > P.MAX_PRESENTATION_BYTES then
    errors.raise("LIMIT_EXCEEDED", "presentation exceeds its aggregate byte limit", { limit = P.MAX_PRESENTATION_BYTES })
  end
end

return P
