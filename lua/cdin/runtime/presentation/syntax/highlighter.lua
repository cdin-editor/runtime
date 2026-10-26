local errors = require("cdin.runtime.core.error")

local Highlighter = {}
Highlighter.__index = Highlighter

function Highlighter.new(registry, styles)
  return setmetatable({
    registry = registry,
    styles = styles,
  }, Highlighter)
end

function Highlighter:highlight(language_name, transient_bytes, document_version, options)
  if type(transient_bytes) ~= "string" then
    errors.raise("INVALID_ARGUMENT", "highlighter input must be transient bytes")
  end

  local definition = self.registry:get(language_name)
  if not definition then
    return {
      version = document_version,
      spans = {},
      language = nil,
    }
  end

  local spans = definition.tokenize(transient_bytes, options or {})
  if type(spans) ~= "table" then
    errors.raise("INTERNAL", "syntax tokenizer must return spans")
  end

  for index, span in ipairs(spans) do
    local valid = type(span) == "table"
      and type(span.start) == "number"
      and type(span.finish) == "number"
      and type(span.role) == "string"
      and span.start >= 0
      and span.finish >= span.start
      and span.finish <= #transient_bytes
      and span.start % 1 == 0
      and span.finish % 1 == 0
    if not valid then
      errors.raise("INTERNAL", "syntax tokenizer returned invalid span", {
        index = index,
      })
    end

    if self.styles and not self.styles:has(span.role) then
      errors.raise("INTERNAL", "syntax tokenizer returned an unknown style role", {
        index = index,
        role = span.role,
      })
    end
  end

  return {
    version = document_version,
    spans = spans,
    language = language_name,
  }
end

return Highlighter
