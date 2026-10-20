# Source map: CDIN snapshot → Runtime repository

| Source in CDIN | Target in this repository | Disposition |
|---|---|---|
| `data/core/commands/*` | same path | copied as Runtime-owned commands |
| `data/core/input/*`, `data/core/keymaps/*` | same paths | copied; input policy stays in Lua |
| `data/core/config.lua`, `project.lua`, `plugins.lua`, `themes.lua`, `style.lua` | same paths | copied |
| `data/core/doc/*` | same path | copied for initial extraction; `doc/init.lua` requires M2 rewrite to thin Kernel client |
| `data/core/views/*`, `rootview/*`, `state.lua` | same paths | copied logical view tree; drawing calls need later Frontend/host separation |
| `data/core/syntax/*`, `doc/highlighter.lua` | same paths | copied; highlighting belongs outside Kernel |
| `data/core/text/utf8.lua` | same path | currently copied for runtime use |
| `data/core/text/bidi.lua`, `shaper.lua` | same paths | copied for compatibility, but target ownership is Frontend; future split required |
| `src/lua/*`, `src/api/*` | not copied | C Host/Binding implementation stays in CDIN Backend; only the Host contract is documented here |
| `src/ui/*`, `src/core/window.*`, `src/platform/*` | not copied | Frontend/OS services, not Runtime |
| `src/fs/*`, `src/loop/*`, `src/base/*`, `src/search/*` | not copied | Backend service implementation; Kernel search replaces compatible literal-search paths after integration |
| `mk/*`, `Makefile`, packaging/release scripts | not copied | remain composition-root/build responsibilities in CDIN |
| `docs/**` | `docs/**` | copied in-place to preserve existing relative links |
| Spec docs | `references/spec/docs/**` | read-only reference snapshot; authoritative Spec remains its own repository |
| Kernel `include/cdin/kernel.h`, `docs/abi.md` | `references/kernel/**` | read-only reference snapshot; not a build dependency |

The supplied archive did not include the CDIN Git history. This is a source-level extraction, not a history-preserving Git subtree operation.
