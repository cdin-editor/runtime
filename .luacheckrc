-- Runtime targets Lua 5.4. The only global bootstrap is encapsulated by
-- lua/cdin/runtime.lua; application modules receive standard Lua libraries.
std = "lua54"
exclude_files = {
  "tests/**",
}
