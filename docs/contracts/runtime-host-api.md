# Runtime Host API 0.1.0

**Status:** provisional development contract; not a stable public API.

This API is the only route from `cdin-runtime` to the Backend. The Backend owns
the native Kernel adapter, OS services and frontend transport. Runtime must not
load the Kernel shared library, call C ABI symbols, inspect Kernel structs or
keep a shadow copy of document bytes/history.

The contract is aligned with CDIN Kernel C ABI `1.0.0` (Kernel package `1.1.0`)
and CDIN Spec `1.1.0` / compatibility baseline `1.0.0`. It does not claim that
the production Backend adapter already exists.

## 1. Host descriptor and version negotiation

`host:info()` returns data equivalent to:

```lua
{
  host_api = { major = 0, minor = 1, patch = 0 },
  kernel_abi = { major = 1, minor = 0, patch = 0 },
  extension_contract = { major = 1, minor = 0 },
  frontend_protocol = { major = 0, minor = 1, patch = 0 },
  features = {
    documents = true, notifications = true, snapshots = true,
    transactions = true, batch_edits = true, literal_search = true,
    ui_model = true, logging = true,
  },
  kernel_features = {
    transactions = true, snapshots = true, notifications = true,
    batch = true, search_literal = true, search_bytes = true,
    search_regex = false,
  },
}
```

Because Host API `0.x` is provisional, the runtime requires an exact host
major/minor match (`0.1`). Kernel ABI requires major `1`, minor `>= 0`; the
extension contract requires major `1`. The runtime accepts only a frontend
protocol version compatible with its configured major/minor floor and relies
on Backend capability negotiation for optional transports.

The Backend must query `cdin_abi_version()` and `cdin_features()` before
creating the Lua Runtime and report the negotiated result accurately. For
Kernel ABI 1.0.0, `search_regex` must be `false`; advertising unsupported regex
is a contract violation. Runtime never performs native version queries itself.

## 2. Calling conventions and error mapping

Services are Lua objects called with `:`. Success values are documented below.
Failures throw a structured table:

```lua
{
  domain = "cdin.runtime",
  code = "STALE_VERSION",
  message = "document version changed",
  details = { expected = 4, current = 5 },
}
```

`code` is stable and machine-readable; `message` is diagnostic text. The
Backend must preserve Kernel status identities and details, including:

| Kernel status | Lua `code` |
|---|---|
| `CDIN_OK` | success; no exception |
| `CDIN_INVALID_ARGUMENT` | `INVALID_ARGUMENT` |
| `CDIN_INVALID_HANDLE` | `INVALID_HANDLE` |
| `CDIN_STALE_VERSION` | `STALE_VERSION` |
| `CDIN_OUT_OF_RANGE` | `OUT_OF_RANGE` |
| `CDIN_INVALID_POSITION` | `INVALID_POSITION` |
| `CDIN_INVALID_STATE` | `INVALID_STATE` |
| `CDIN_BUSY` | `BUSY` |
| `CDIN_LIMIT_EXCEEDED` | `LIMIT_EXCEEDED` |
| `CDIN_NO_MEMORY` | `NO_MEMORY` |
| `CDIN_PATTERN_INVALID` | `PATTERN_INVALID` |
| `CDIN_CANCELLED` | `CANCELLED` |
| `CDIN_SHUTDOWN` | `SHUTDOWN` |
| `CDIN_UNSUPPORTED` | `UNSUPPORTED` |
| `CDIN_BUFFER_TOO_SMALL` | `BUFFER_TOO_SMALL` |
| `CDIN_VERSION_MISMATCH` | `VERSION_MISMATCH` |
| `CDIN_INTERNAL` | `INTERNAL` |

The Backend must preserve `expected/current`, `requested/length`, `required`,
`limit_id` and other relevant details. Numeric `CDIN_LIMIT_*` values pass
through unchanged: `0` none, `1` documents, `2` document size, `3` edit size,
`4` undo memory, `5` blob size, `6` snapshots, `7` subscribers, `8` search
steps, `9` transaction memory, `10` batch edits, `11` version, `12` sequence.

No C pointer or Kernel handle is exposed to extensions. Host handles are opaque
Backend-created Lua values and may be userdata.

## 3. Required `host.documents` service

The service must implement these methods. The runtime assumes Kernel mutations
are synchronous for ABI 1.0.0.

### Document lifecycle and reads

- `create(initial_bytes, metadata?) -> { handle, version, length }`
- `close(handle) -> true`
- `read(handle, { start, length, expected_version? }) -> { bytes, version, total_length, flags? }`
- `acquire_snapshot(handle) -> { handle, version, length }`
- `read_snapshot(snapshot_handle, { start, length }) -> { bytes, version }`
- `release_snapshot(snapshot_handle) -> true`

When `expected_version` is omitted or `nil`, `read` returns metadata for the
latest version; `start = 0, length = 0` is the metadata-only resync path. Reads
return caller-owned transient strings. `DocumentClient` must not store those
strings on itself. Snapshot handles are pinned leases and must be released.

### Mutations and history

- `replace(handle, request) -> edit_result`
- `replace_batch(handle, request) -> edit_result`
- `undo(handle, { expected_version, blob_capacity }) -> edit_result`
- `redo(handle, { expected_version, blob_capacity }) -> edit_result`
- `begin_transaction(handle, { expected_version }) -> { handle, base_version }`
- `transaction_replace(transaction_handle, edit) -> result`
- `transaction_read(transaction_handle, { start, length }) -> { bytes, total_length }`
- `commit_transaction(transaction_handle, { undo_blob_before, undo_blob_after }) -> edit_result`
- `abort_transaction(transaction_handle) -> true`
- `mark_clean(handle) -> true`
- `mark_clean_if_version(handle, saved_version) -> boolean`
- `is_clean(handle) -> boolean`

`replace` requests use zero-based half-open byte ranges `[start, finish)`, the
expected current version, optional `coalesce_key`, and opaque selection blobs
before/after the edit. Batch edits are ascending, non-overlapping ranges in the
same pre-edit version and form one undo unit. Returned `accepted_seq` indicates
the Kernel accepted the operation; it does not promise later notifications
cannot report an issue.

For transactions, tentative content is owned by Kernel. Runtime retains only the
opaque transaction handle and offset metadata needed for view transformation.
It must explicitly commit or abort. On close, outstanding transactions are
aborted best-effort before the document is closed.

The Kernel ABI's `mark_clean` has no expected-version argument. Backend must
implement `mark_clean_if_version` as a serialized version comparison plus
`cdin_doc_mark_clean` in one critical section. It returns `false` if the
current document version differs from `saved_version`.

### Notifications

- `subscribe(handle) -> { handle, version }`
- `unsubscribe(subscription_handle) -> true`
- `drain(subscription_handle, max_events) -> array of normalized notifications`

Notifications are scoped to their subscribed document and use Kernel event
kinds: `EDIT`, `BATCH`, `TRANSACTION`, `UNDO`, `REDO`, `RELOAD`, `CLOSED`,
`HISTORY_EVICTED`, `RESYNC`, and `SAVED_STATE_CHANGED` where applicable. Preserve
`from_version`, `to_version`, `current_version`, `edit_count`, `edits_stored`,
`edits_truncated` and `edits`. Each edit is `{ start, removed, inserted }`; for
sequential operations, each `start` refers to the content state immediately
before that edit. If edit data is truncated, or the version chain has a gap,
Runtime refreshes metadata and discards incremental assumptions. It never
replays a partial edit list.

Kernel wakeup callbacks may signal the Backend event loop only. They must never
call Lua from a non-owner thread. Backend calls `runtime:pump_notifications()`
on the Lua owner thread.

### Search

`search(handle, { pattern, mode, direction, from, bound, limit, expected_version, case_insensitive, any_newline, step_limit }) -> result`

Supported modes are `literal` and `bytes`. `regex` must return `UNSUPPORTED`
for Kernel ABI 1.0.0. Kernel resource-limit failures are recoverable outcomes,
not internal Runtime crashes.

## 4. Required `host.ui` service

`host.ui:publish(model_snapshot) -> true`

The model is serializable semantic state. Backend translates it to Frontend
Protocol messages; Runtime does not know which frontends are attached and does
not draw. The current model schema is `cdin.ui-model.v1` and remains provisional.

## 5. Required logging service

`host:log(level, message, fields?) -> true`

Runtime does not write to stdout/stderr on its own initiative. Logging failures
must not be used to mask a more important operation failure.

## 6. Optional atomic-save service

`host.fs` may provide:

- `begin_atomic_write(path, options) -> writer_handle`
- `write_chunk(writer_handle, bytes) -> true`
- `commit_atomic_write(writer_handle) -> true`
- `abort_atomic_write(writer_handle) -> true`

The runtime writes a version-pinned snapshot in bounded chunks, commits the
atomic replacement, then calls `mark_clean_if_version`. This service is optional
at startup but required for the built-in `document.save` command.

## 7. Kernel ABI mapping

| Runtime operation | Kernel ABI 1.0.0 symbol family |
|---|---|
| `create` / `close` | `cdin_doc_create` / `cdin_doc_close` |
| `read` | `cdin_text_version`, `cdin_text_len`, `cdin_text_read` |
| snapshot lease | `cdin_snapshot_acquire`, `cdin_snapshot_release`, `cdin_text_*` via `cdin_src_snap` |
| replace / batch | `cdin_doc_replace`, `cdin_doc_replace_batch` |
| transaction | `cdin_txn_begin`, `cdin_txn_replace`, `cdin_txn_len`, `cdin_txn_read`, `cdin_txn_commit`, `cdin_txn_abort` |
| undo / redo | `cdin_doc_undo`, `cdin_doc_redo` |
| dirty state | `cdin_doc_mark_clean`, `cdin_doc_is_clean` plus Backend-side conditional operation |
| notification | `cdin_notif_subscribe`, `cdin_notif_unsubscribe`, `cdin_notif_drain` |
| search | `cdin_search`; literal/bytes only |

The Backend adapter must use only the public `include/cdin/kernel.h` header and
must run the Kernel's conformance vectors through the adapter before declaring
this integration complete.

## 8. Stability gate

Host API `0.1.0` is not a stable external contract. A reviewed stability decision
requires a complete Backend/C adapter, ABI-to-Lua status mapping tests, live
create/edit/read/notify/undo/redo/close tests against the real Kernel, lifecycle
failure injection, Lua 5.4 tests, headless Frontend Protocol integration, and an
accepted Spec decision for versioning/compatibility.
