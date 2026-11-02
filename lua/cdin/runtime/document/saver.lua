local errors = require("cdin.runtime.core.error")
local Log = require("cdin.runtime.core.log")

-- Save a version-pinned Kernel snapshot through the Backend's atomic writer.
-- Chunking bounds temporary memory use for large documents.
local Saver = {}
Saver.__index = Saver

-- `deps.logger` is optional. Save records contain sizes and versions only; the
-- destination path is the caller's data and is not written to the shared log.
function Saver.new(host, options, deps)
  options = options or {}
  deps = deps or {}
  if type(options) ~= "table" then
    errors.raise("INVALID_ARGUMENT", "saver options must be a table")
  end

  local chunk_size = options.chunk_size or 65536
  if type(chunk_size) ~= "number" or chunk_size < 1 or chunk_size % 1 ~= 0 then
    errors.raise("INVALID_ARGUMENT", "save chunk size must be a positive integer")
  end

  return setmetatable({
    host = host,
    chunk_size = chunk_size,
    log = deps.logger or Log.null(),
  }, Saver)
end

function Saver:save(document, path, options)
  options = options or {}
  if type(path) ~= "string" or path == "" then
    errors.raise("INVALID_ARGUMENT", "save path is required")
  end
  if type(self.host.fs) ~= "table"
      or type(self.host.fs.begin_atomic_write) ~= "function" then
    errors.raise("UNSUPPORTED", "host does not provide atomic filesystem writes")
  end

  local snapshot = document:snapshot()
  local saved_version = snapshot.version
  local total = snapshot.length
  local writer
  local ok, result = pcall(function()
    writer = self.host.fs:begin_atomic_write(path, {
      overwrite = options.overwrite ~= false,
    })
    if writer == nil then
      errors.raise("INTERNAL", "filesystem returned no atomic writer")
    end

    local offset = 0
    while offset < total do
      local amount = math.min(self.chunk_size, total - offset)
      local bytes = snapshot:read(offset, amount)
      if #bytes == 0 then
        errors.raise("INTERNAL", "snapshot ended before its declared length", {
          offset = offset,
          total = total,
        })
      end
      if #bytes > amount then
        errors.raise("INTERNAL", "snapshot returned more data than requested", {
          requested = amount,
          returned = #bytes,
        })
      end

      self.host.fs:write_chunk(writer, bytes)
      offset = offset + #bytes
    end

    self.host.fs:commit_atomic_write(writer)
    writer = nil
    local clean = self.host.documents:mark_clean_if_version(document.handle, saved_version)
    document.path = path

    return {
      path = path,
      version = saved_version,
      bytes_written = total,
      clean = clean == true,
    }
  end)

  if writer ~= nil then
    pcall(self.host.fs.abort_atomic_write, self.host.fs, writer)
  end
  local close_ok, close_error = pcall(snapshot.close, snapshot)
  if not ok then
    local failure = errors.normalize(result, "INTERNAL", "save document")
    self.log:error("document save failed", { document_id = document.id, code = failure.code })
    error(failure, 0)
  end
  if not close_ok then
    error(errors.normalize(close_error, "INTERNAL", "release save snapshot"), 0)
  end
  self.log:info("document saved", {
    document_id = document.id,
    version = result.version,
    bytes = result.bytes_written,
    clean = result.clean,
  })
  return result
end

return Saver
