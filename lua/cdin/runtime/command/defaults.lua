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

  commands:register("document.new", function(_, args)
    local initial_bytes = args.initial_bytes
    if initial_bytes == nil then initial_bytes = "" end
    if type(initial_bytes) ~= "string" then
      errors.raise("INVALID_ARGUMENT", "document.new initial_bytes must be a byte string")
    end
    if args.path ~= nil and (type(args.path) ~= "string" or args.path == "") then
      errors.raise("INVALID_ARGUMENT", "document.new path must be a non-empty string")
    end
    local document = runtime:open_document(initial_bytes, { path = args.path })
    local ok, view = pcall(runtime._create_view, runtime, document.id, nil, false)
    if not ok then
      pcall(runtime.close_document, runtime, document.id)
      error(errors.normalize(view, "INTERNAL", "create document view"), 0)
    end
    return { document_id = document.id, view_id = view.id, version = document.version }
  end, {
    description = "Create an empty or byte-initialized document and focus its first view",
  })

  commands:register("document.open", function(_, args)
    if type(args.path) ~= "string" or args.path == "" then
      errors.raise("INVALID_ARGUMENT", "document.open requires a non-empty path")
    end
    local fs = runtime.host.fs
    if type(fs) ~= "table" or type(fs.read_file) ~= "function" then
      errors.raise("UNSUPPORTED", "Backend Host does not provide bounded file reads")
    end
    local bytes = fs:read_file(args.path, { max_bytes = args.max_bytes })
    if type(bytes) ~= "string" then
      errors.raise("INTERNAL", "Backend Host file read did not return a byte string")
    end
    local document = runtime:open_document(bytes, { path = args.path })
    local ok, view = pcall(runtime.create_view, runtime, document.id)
    if not ok then
      pcall(runtime.close_document, runtime, document.id)
      error(errors.normalize(view, "INTERNAL", "create opened document view"), 0)
    end
    runtime.log:info("document opened", {
      document_id = document.id,
      version = document.version,
      bytes = document.length,
    })
    return { document_id = document.id, view_id = view.id, version = document.version }
  end, {
    description = "Open exact file bytes through the optional Backend Host filesystem service",
  })

  commands:register("document.close", function(context)
    local document = active_document(runtime, context)
    if not document then
      return false, "no active document"
    end
    return runtime:_close_document(document.id, false)
  end, {
    description = "Close the focused document and remove its views",
    available = function(context)
      return context.document ~= nil or runtime:focused_document() ~= nil
    end,
  })

  -- FE-016 / PROTO-041: default editing shortcuts are Runtime policy. The
  -- Frontend emits raw key events and never duplicates or interprets bindings.
  runtime.keymap:bind("ctrl+n", "document.new", { owner = "core" })
  runtime.keymap:bind("ctrl+s", "document.save", { owner = "core" })
  runtime.keymap:bind("ctrl+z", "document.undo", { owner = "core" })
  runtime.keymap:bind("ctrl+shift+z", "document.redo", { owner = "core" })
  runtime.keymap:bind("ctrl+w", "document.close", { owner = "core" })

end

return M
