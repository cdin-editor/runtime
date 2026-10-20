-- Lua Language Server type declarations shared by Runtime modules.
-- This file deliberately contains annotations only; runtime records remain plain tables.

---@alias RuntimeStatus string

---@class RuntimeVersion
---@field major integer
---@field minor integer
---@field patch integer
---@field stage? string

---@class RuntimeError
---@field code string Stable machine-readable code.
---@field message string Human-readable diagnostic; never use it for branching.
---@field details? table<string, any> Structured, status-specific context.

---@class DocumentHandle
---@field id integer Opaque Runtime handle; never a Kernel pointer.

---@class DocumentSnapshot
---@field document DocumentHandle
---@field version integer
---@field byte_length integer
---@field lines? table Integer line metadata only, not canonical document bytes.

---@class DocumentEditRequest
---@field expected_version integer
---@field start_byte integer
---@field delete_bytes integer
---@field insert_bytes string
---@field selection_before? string Opaque selection state for history integration.
---@field selection_after? string Opaque selection state for history integration.

---@class DocumentEditResult
---@field version integer
---@field accepted_seq integer
---@field byte_length integer
---@field status? RuntimeStatus

---@class RuntimeCapabilities
---@field ui_model boolean
---@field filesystem boolean
---@field search_literal boolean
---@field notifications boolean

---@class RuntimeServiceTable
---@field doc table
---@field fs table
---@field path table
---@field system table
---@field search? table
---@field ui? table

---@class RuntimeHostDescriptor
---@field api_version RuntimeVersion
---@field kernel_abi RuntimeVersion
---@field services RuntimeServiceTable
---@field capabilities table<string, boolean>
---@field metadata? table<string, any>

---@class CommandDescriptor
---@field name string
---@field predicate? any
---@field perform function
---@field description? string

---@class KeyStroke
---@field key string
---@field modifiers table<string, boolean>

---@class ViewState
---@field id integer
---@field document DocumentHandle
---@field selection_start integer
---@field selection_end integer
---@field scroll_anchor integer

---@class StyleRole
---@field foreground? string|table
---@field background? string|table
---@field bold? boolean
---@field italic? boolean

---@class PluginModule
---@field init fun(core: table, config: table)
---@field unload? fun()

---@class PluginContext
---@field core table
---@field config table
---@field capabilities table<string, boolean>

return {}
