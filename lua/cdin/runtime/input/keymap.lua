local errors = require("cdin.runtime.core.error")

local Keymap = {}
Keymap.__index = Keymap

local modifier_order = { "ctrl", "alt", "altgr", "shift" }
local modifier_rank = { ctrl = 1, alt = 2, altgr = 3, shift = 4 }
local foreign_modifiers = {
  cmd = true,
  command = true,
  meta = true,
  super = true,
  win = true,
  windows = true,
  control = true,
  option = true,
  opt = true,
  hyper = true,
}

local function validate_stroke(stroke)
  if type(stroke) ~= "string" or stroke == "" then
    return nil, "stroke must be a non-empty string"
  end

  local parts = {}
  local start = 1
  while true do
    local separator = stroke:find("+", start, true)
    local part = separator and stroke:sub(start, separator - 1) or stroke:sub(start)
    parts[#parts + 1] = part
    if not separator then
      break
    end
    start = separator + 1
  end

  for _, part in ipairs(parts) do
    if part == "" then
      return nil, "empty stroke segment"
    end
  end

  local previous_rank = 0
  local key_count = 0
  for index, part in ipairs(parts) do
    local rank = modifier_rank[part]
    if rank then
      if rank <= previous_rank then
        return nil, "modifiers repeated or out of order"
      end
      previous_rank = rank
    else
      key_count = key_count + 1
      if index == 1 and #parts > 1 and foreign_modifiers[part] then
        return nil, "unsupported modifier: " .. part
      end
      if part:find("%u") then
        return nil, "key names must be lower-case"
      end
    end
  end

  if key_count ~= 1 then
    return nil, "stroke must contain exactly one key name"
  end
  return true
end

local function sequence_key(sequence)
  return table.concat(sequence, "\31")
end

local function copy_sequence(sequence)
  local copy = {}
  for index, value in ipairs(sequence) do
    copy[index] = value
  end
  return copy
end

local function copy_commands(contributions)
  local commands = {}
  for _, contribution in ipairs(contributions) do
    commands[#commands + 1] = contribution.command
  end
  return commands
end

function Keymap.new()
  return setmetatable({
    bindings = {},
    tokens = {},
    next_id = 0,
    pending = {},
  }, Keymap)
end

function Keymap:_prune_tokens()
  local referenced = {}
  for _, entry in pairs(self.bindings) do
    for _, contribution in ipairs(entry.contributions) do
      referenced[contribution.token.id] = true
    end
  end

  for id, token in pairs(self.tokens) do
    if not referenced[id] then
      token.active = false
      self.tokens[id] = nil
    end
  end
end

function Keymap:bind(sequence, commands, options)
  options = options or {}
  if type(sequence) == "string" then
    sequence = { sequence }
  end
  if type(sequence) ~= "table" or #sequence == 0 then
    errors.raise("INVALID_ARGUMENT", "key binding sequence is empty")
  end
  if type(commands) == "string" then
    commands = { commands }
  end
  if type(commands) ~= "table" or #commands == 0 then
    errors.raise("INVALID_ARGUMENT", "key binding commands are empty")
  end

  for _, stroke in ipairs(sequence) do
    local valid, reason = validate_stroke(stroke)
    if not valid then
      errors.raise("INVALID_ARGUMENT", "invalid key stroke", {
        stroke = stroke,
        reason = reason,
      })
    end
  end
  for _, command_name in ipairs(commands) do
    if type(command_name) ~= "string" or command_name == "" then
      errors.raise("INVALID_ARGUMENT", "command names must be non-empty strings")
    end
  end

  local key = sequence_key(sequence)
  self.next_id = self.next_id + 1
  local token = {
    id = self.next_id,
    key = key,
    sequence = copy_sequence(sequence),
    owner = options.owner or "core",
    active = true,
  }
  local entry = self.bindings[key] or {
    sequence = copy_sequence(sequence),
    contributions = {},
  }

  local incoming = {}
  for _, command_name in ipairs(commands) do
    incoming[#incoming + 1] = {
      command = command_name,
      token = token,
    }
  end

  if options.overwrite then
    entry.contributions = incoming
  else
    local merged = {}
    for _, contribution in ipairs(incoming) do
      merged[#merged + 1] = contribution
    end

    -- A reload replaces the same owner's contribution instead of leaking
    -- another token for each registration cycle.
    for _, existing in ipairs(entry.contributions) do
      local replaced = false
      for _, fresh in ipairs(incoming) do
        if existing.command == fresh.command and existing.token.owner == token.owner then
          replaced = true
          break
        end
      end
      if not replaced then
        merged[#merged + 1] = existing
      end
    end
    entry.contributions = merged
  end

  self.bindings[key] = entry
  self.tokens[token.id] = token
  self:_prune_tokens()
  return token
end

function Keymap:remove(token, names)
  if type(token) ~= "table" or not token.active then
    return false
  end

  local remove_names
  if names ~= nil then
    if type(names) == "string" then
      names = { names }
    end
    if type(names) ~= "table" then
      errors.raise("INVALID_ARGUMENT", "keymap removal names must be a string or array")
    end

    remove_names = {}
    for _, name in ipairs(names) do
      remove_names[name] = true
    end
  end

  local removed = false
  for key, entry in pairs(self.bindings) do
    local kept = {}
    for _, contribution in ipairs(entry.contributions) do
      local same_token = contribution.token == token
      local selected_name = not remove_names or remove_names[contribution.command]
      if same_token and selected_name then
        removed = true
      else
        kept[#kept + 1] = contribution
      end
    end

    if #kept == 0 then
      self.bindings[key] = nil
    else
      entry.contributions = kept
    end
  end

  self:_prune_tokens()
  return removed
end

function Keymap:remove_owner(owner)
  local owned_tokens = {}
  for _, token in pairs(self.tokens) do
    if token.owner == owner then
      owned_tokens[#owned_tokens + 1] = token
    end
  end

  for _, token in ipairs(owned_tokens) do
    self:remove(token)
  end
  return #owned_tokens
end

function Keymap:get_binding(command_name)
  for _, entry in pairs(self.bindings) do
    for _, contribution in ipairs(entry.contributions) do
      if contribution.command == command_name then
        return copy_sequence(entry.sequence)
      end
    end
  end
  return nil
end

function Keymap:reset_pending()
  self.pending = {}
end

function Keymap:feed(stroke)
  local valid, reason = validate_stroke(stroke)
  if not valid then
    errors.raise("INVALID_ARGUMENT", "invalid input stroke", {
      stroke = stroke,
      reason = reason,
    })
  end

  local candidate = copy_sequence(self.pending)
  candidate[#candidate + 1] = stroke
  local key = sequence_key(candidate)
  local exact = self.bindings[key]
  local has_longer = false

  for _, entry in pairs(self.bindings) do
    if #entry.sequence > #candidate then
      local is_prefix = true
      for index, value in ipairs(candidate) do
        if entry.sequence[index] ~= value then
          is_prefix = false
          break
        end
      end
      if is_prefix then
        has_longer = true
        break
      end
    end
  end

  if exact and not has_longer then
    self.pending = {}
    return {
      status = "matched",
      commands = copy_commands(exact.contributions),
      sequence = candidate,
    }
  end

  if exact and has_longer then
    self.pending = candidate
    return {
      status = "pending",
      fallback = copy_commands(exact.contributions),
      sequence = candidate,
    }
  end

  if has_longer then
    self.pending = candidate
    return { status = "pending", sequence = candidate }
  end

  self.pending = {}
  return { status = "unbound", sequence = candidate }
end

function Keymap:expire()
  local exact = self.bindings[sequence_key(self.pending)]
  local sequence = copy_sequence(self.pending)
  self.pending = {}

  if exact then
    local commands = copy_commands(exact.contributions)
    if #commands > 0 then
      return { status = "matched", commands = commands, sequence = sequence }
    end
  end
  return { status = "unbound", sequence = sequence }
end

function Keymap:list()
  local result = {}
  for _, entry in pairs(self.bindings) do
    result[#result + 1] = {
      sequence = copy_sequence(entry.sequence),
      commands = copy_commands(entry.contributions),
    }
  end
  table.sort(result, function(a, b)
    return sequence_key(a.sequence) < sequence_key(b.sequence)
  end)
  return result
end

Keymap.validate_stroke = validate_stroke
return Keymap
