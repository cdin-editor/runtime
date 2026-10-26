# Build and test

## Requirements

- Lua 5.4
- `make`

Run commands from the repository root.

## Commands

```sh
make unit         # test individual modules
make integration  # test modules together using a simulated Host
make test         # run unit and integration tests
make check        # run the complete local check target
```

If Lua 5.4 is installed under a different command name, pass it to `make`:

```sh
make check LUA=lua
```

Use this only if `lua` is Lua 5.4. Other Lua versions may be useful for a quick
smoke test, but Lua 5.4 is the supported target.

## What do these tests cover?

Unit tests check modules on their own. Integration tests check that modules
work together with a simulated Host, including document operations, views,
snapshots, transactions, notifications, saving and extension cleanup.

The simulated Host does not replace the real Backend. These tests do not prove
Kernel ABI compatibility, native resource ownership, real file I/O or Frontend
Protocol integration. Those parts need to be tested when the production
adapter is added.

For a first run, see the [User Guide](../user-guide.md).
