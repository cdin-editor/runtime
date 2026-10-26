# Integration tests

The active suite runs against the fake Runtime Host API. It covers the Lua
policy path from raw key input through command dispatch, document clients,
notification handling and semantic UI publication. It does not emulate a real
C ABI binding and is not proof of Kernel integration.

```sh
make unit
make integration
make check
```

Run commands from the repository root with Lua 5.4 installed. The fake host is
`tests/support/fake_host.lua`; it deliberately owns the canonical bytes and
history because it models the Kernel/Backend boundary for tests. Production Lua
modules do not import that fake and do not store document bytes or history.
