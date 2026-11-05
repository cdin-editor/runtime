local A = require("support.assert")
local FakeHost = require("support.fake_host")
local Runtime = require("cdin.runtime")

local path = "workspace/binary-document.cdin"
local original = "\239\187\191A\0B\255\r\nline-two\nline-three\r"
local after_text = "\239\187\191X" .. original:sub(4)
local expected = "\239\187\191X\0P\255" .. original:sub(4)

local host = FakeHost.new()
host.fs:write_test_file(path, original)
local runtime = Runtime.new({ host = host })
runtime:start()

-- request.command -> Runtime -> optional Backend Host fs read -> Kernel document.
local opened = runtime:handle_frontend_event({
  type = "request.command",
  name = "document.open",
  arguments = { path = path },
})
A.equal(opened.status, "executed")
local document_id = opened.result.document_id
local document = runtime.documents:get(document_id)
local view = runtime:focused_view()
A.equal(view.document_id, document_id)
local bytes = document:read(0, #original + 8)
A.equal(bytes, original)

-- Raw key/text and paste events use the ordinary Frontend event path. Paste is
-- deliberately binary: NUL and invalid UTF-8 must remain document bytes.
view:set_cursor(3) -- immediately after the UTF-8 BOM
local typed = runtime:handle_frontend_event({ type = "input.text", text = "X" })
A.equal(typed.status, "inserted")
local pasted = runtime:handle_frontend_event({ type = "input.paste", bytes = "\0P\255" })
A.equal(pasted.status, "inserted")
A.equal(document:read(0, #expected + 8), expected)

-- Undo/redo are triggered by physical key events and resolved by Runtime's
-- default keymap, not interpreted by the Frontend.
local undo_paste = runtime:handle_frontend_event({
  type = "input.key", key = "z", action = "press", modifiers = { "ctrl" },
})
A.equal(undo_paste.status, "executed")
A.equal(document:read(0, #after_text + 8), after_text)
local undo_text = runtime:handle_frontend_event({
  type = "input.key", key = "z", action = "press", modifiers = { "ctrl" },
})
A.equal(undo_text.status, "executed")
A.equal(document:read(0, #original + 8), original)
local redo_text = runtime:handle_frontend_event({
  type = "input.key", key = "z", action = "press", modifiers = { "ctrl", "shift" },
})
A.equal(redo_text.status, "executed")
A.equal(document:read(0, #after_text + 8), after_text)
local redo_paste = runtime:handle_frontend_event({
  type = "input.key", key = "z", action = "press", modifiers = { "ctrl", "shift" },
})
A.equal(redo_paste.status, "executed")
A.equal(document:read(0, #expected + 8), expected)

-- The default save keymap invokes the version-pinned snapshot / atomic writer.
local saved = runtime:handle_frontend_event({
  type = "input.key", key = "s", action = "press", modifiers = { "ctrl" },
})
A.equal(saved.status, "executed")
A.equal(host.fs:read_test_file(path), expected)
A.truthy(document:is_clean())

-- Close and reopen through the same request.command surface. The reopened
-- canonical document must equal the exact file bytes, including invalid UTF-8.
local closed = runtime:handle_frontend_event({
  type = "request.command", name = "document.close", arguments = {},
})
A.equal(closed.status, "executed")
A.equal(runtime.documents.documents[document_id], nil)
A.equal(runtime.ui.views[view.id], nil)

local reopened = runtime:handle_frontend_event({
  type = "request.command",
  name = "document.open",
  arguments = { path = path },
})
A.equal(reopened.status, "executed")
A.equal(runtime.ui.focus, reopened.result.view_id)
local reopened_document = runtime.documents:get(reopened.result.document_id)
A.equal(reopened_document:read(0, #expected + 8), expected)
local latest_model = host.published[#host.published]
A.equal(latest_model.schema, "cdin.ui-model.v1")
A.equal(latest_model.focus, reopened.result.view_id)
local rendered_document_version
for _, view_model in pairs(latest_model.views) do
  if view_model.document_id == reopened_document.id then
    rendered_document_version = view_model.document_version
  end
end
A.equal(rendered_document_version, reopened_document.version)

-- Runtime owns default lifecycle shortcuts. Ctrl+N creates and focuses an
-- empty document; Ctrl+W closes only the currently focused one.
local created = runtime:handle_frontend_event({
  type = "input.key", key = "n", action = "press", modifiers = { "ctrl" },
})
A.equal(created.status, "executed")
A.equal(created.command, "document.new")
A.equal(runtime.ui.focus, created.result.view_id)
local new_document = runtime:focused_document()
A.equal(new_document.id, created.result.document_id)
A.truthy(new_document ~= nil)
A.equal(new_document.length, 0)
local new_id = new_document.id
local close_key = runtime:handle_frontend_event({
  type = "input.key", key = "w", action = "press", modifiers = { "ctrl" },
})
A.equal(close_key.status, "executed")
A.equal(runtime.documents.documents[new_id], nil)

runtime:close_document(reopened_document.id)
A.truthy(runtime:shutdown())

-- Missing/unsupported Host read capabilities fail closed without creating
-- document handles or publishing phantom UI views.
local no_reader = FakeHost.new({ read_file = false })
local no_reader_runtime = Runtime.new({ host = no_reader })
no_reader_runtime:start()
A.error_code(function()
  no_reader_runtime:handle_frontend_event({
    type = "request.command", name = "document.open", arguments = { path = path },
  })
end, "UNSUPPORTED")
A.equal(#no_reader_runtime.documents:list(), 0)
A.equal(next(no_reader_runtime.ui.views), nil)
no_reader_runtime:shutdown()

local missing_file_host = FakeHost.new()
local missing_file_runtime = Runtime.new({ host = missing_file_host })
missing_file_runtime:start()
A.error_code(function()
  missing_file_runtime:handle_frontend_event({
    type = "request.command", name = "document.open", arguments = { path = "missing.bin" },
  })
end, "NOT_FOUND")
A.equal(#missing_file_runtime.documents:list(), 0)
missing_file_runtime:shutdown()

local limited_host = FakeHost.new()
limited_host.fs:write_test_file(path, "0123456789")
local limited_runtime = Runtime.new({ host = limited_host })
limited_runtime:start()
A.error_code(function()
  limited_runtime:handle_frontend_event({
    type = "request.command", name = "document.open",
    arguments = { path = path, max_bytes = 4 },
  })
end, "LIMIT_EXCEEDED")
A.equal(#limited_runtime.documents:list(), 0)
limited_runtime:shutdown()

-- An interrupted save must abort the temporary writer, retain the prior target
-- bytes, leave the document dirty, and release its version-pinned snapshot.
local failing_host = FakeHost.new({ fail_file_write_after_chunks = 1 })
failing_host.fs:write_test_file(path, "previous destination")
local failing_runtime = Runtime.new({
  host = failing_host,
  saver = { chunk_size = 4 },
})
failing_runtime:start()
local failing_document = failing_runtime:open_document("new payload that spans chunks", { path = path })
A.error_code(function()
  failing_runtime:save_document(failing_document.id, path)
end, "IO_ERROR")
A.equal(failing_host.fs:read_test_file(path), "previous destination")
A.equal(failing_host.fs.aborted_writers, 1)
A.falsy(failing_document:is_clean())
A.equal(next(failing_host.snapshots), nil)
failing_runtime:close_document(failing_document.id)
failing_runtime:shutdown()

-- A failed publish/commit also leaves the old target untouched and aborts the
-- writer rather than leaking its temporary buffer/handle.
local commit_host = FakeHost.new({ fail_file_commit = true })
commit_host.fs:write_test_file(path, "old")
local commit_runtime = Runtime.new({ host = commit_host, saver = { chunk_size = 2 } })
commit_runtime:start()
local commit_document = commit_runtime:open_document("replacement", { path = path })
A.error_code(function() commit_runtime:save_document(commit_document.id, path) end, "IO_ERROR")
A.equal(commit_host.fs:read_test_file(path), "old")
A.equal(commit_host.fs.aborted_writers, 1)
A.equal(next(commit_host.snapshots), nil)
commit_runtime:close_document(commit_document.id)
commit_runtime:shutdown()

