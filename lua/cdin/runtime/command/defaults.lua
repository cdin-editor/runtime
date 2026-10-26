local errors = require("cdin.runtime.core.error")
local Selection = require("cdin.runtime.presentation.ui.selection")

local M = {}

local function active_document(runtime, context)
  return context.document or runtime:focused_document()
end

local function active_view(runtime, context)
  return context.view or runtime.ui:focused_view()
end

function M.register(runtime)
  local commands = runtime.commands

  commands:register("runtime.noop", function()
    return true
  end, {
    description = "Do nothing",
  })

  commands:register("document.undo", function(context, args)
    local document = active_document(runtime, context)
    if not document then
      return false, "no active document"
    end

    local result = document:undo({
      blob_capacity = args.blob_capacity or 4096,
    })
    if result.selection_blob and context.view then
      context.view:restore_selection_blob(result.selection_blob)
    end
    return result
  end, {
    description = "Undo the latest Kernel history unit",
    available = function(context)
      return context.document ~= nil or runtime:focused_document() ~= nil
    end,
  })

  commands:register("document.redo", function(context, args)
    local document = active_document(runtime, context)
    if not document then
      return false, "no active document"
    end

    local result = document:redo({
      blob_capacity = args.blob_capacity or 4096,
    })
    if result.selection_blob and context.view then
      context.view:restore_selection_blob(result.selection_blob)
    end
    return result
  end, {
    description = "Redo the latest Kernel history unit",
    available = function(context)
      return context.document ~= nil or runtime:focused_document() ~= nil
    end,
  })

  commands:register("document.save", function(context, args)
    local document = active_document(runtime, context)
    if not document then
      return false, "no active document"
    end
    return runtime:save_document(document.id, args.path or document.path, args)
  end, {
    description = "Save a document snapshot atomically through Backend filesystem services",
    available = function(context, args)
      local document = active_document(runtime, context)
      local has_path = document ~= nil
        and (document.path ~= nil or (args and args.path ~= nil))
      local has_atomic_writer = type(runtime.host.fs) == "table"
        and type(runtime.host.fs.begin_atomic_write) == "function"
      return has_path and has_atomic_writer
    end,
  })

  commands:register("document.replace", function(context, args)
    local document = active_document(runtime, context)
    if not document then
      return false, "no active document"
    end
    if type(args.start) ~= "number"
        or type(args.finish) ~= "number"
        or type(args.bytes) ~= "string" then
      errors.raise("INVALID_ARGUMENT", "document.replace requires start, finish and bytes")
    end

    local view = active_view(runtime, context)
    local selection_before = view and view:selection_blob() or ""
    local cursor_after = args.start + #args.bytes
    local selection_after = view and Selection.encode({
      anchor = cursor_after,
      caret = cursor_after,
    }) or ""

    local result = document:replace(args.start, args.finish, args.bytes, {
      expected_version = args.expected_version,
      coalesce_key = args.coalesce_key or 0,
      undo_blob_before = args.undo_blob_before or selection_before,
      undo_blob_after = args.undo_blob_after or selection_after,
    })
    if view then
      view:set_cursor(cursor_after)
    end
    return result
  end, {
    description = "Replace a byte range through the document Host API",
  })
end

return M
