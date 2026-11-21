# nauvim-plugin

The host-side Lua interface to Nauvim. Nauvim plugins use it to request client-side
forwarding, temporary file copies, HTTP previews, clipboard copying and session
switches. It requires Neovim **v0.12.6**, with no other host dependencies. Use the
latest versions of both `nauvim-plugin` and `nauvim-core` together.

This implementation targets `nauvim-spec` commit
[`cc51d1ecc51869d8eafb68f243cf0adff6f390bb`](https://github.com/nauvim/nauvim-spec/tree/cc51d1ecc51869d8eafb68f243cf0adff6f390bb).

For releases with Git tags, a change to the referenced `nauvim-spec` commit hash
requires a minor or major version increase. If the hash stays the same, the patch
version increases. Breaking changes or other release requirements may require
exceptions to these rules. In all cases, tagged releases with the same minor
version are guaranteed to reference the same `nauvim-spec` commit hash. There is
no guarantee that every release receives a Git tag.

## Install

Install this repository with a Neovim plugin manager or add the checkout to your
runtime path in `init.lua`:

```lua
vim.opt.runtimepath:prepend("/absolute/path/to/nauvim-plugin")
```

For clipboard integration, also set:

```lua
vim.g.clipboard = require("nauvim-plugin.clipboard").provider
```

The provider copies host register contents to the client clipboard. Its register
reads supply no text. GUI paste is a separate client operation that sends text to
Neovim as paste input.

Nauvim registers the destination automatically after UI attachment. No user
`setup()` call is needed. Without a selected Nauvim destination, operations
quietly return immediately. The provider's paste callbacks always supply no
text, so the same configuration can load in a terminal.

## Use

This example runs inside Neovim with this plugin on its runtime path. With Nauvim
attached, it forwards an available client port to host port 8080:

```lua
local forward = require("nauvim-plugin.local-forward")

local handle, err = forward.open_tcp({
  client_port = 0,
  host_addr = "127.0.0.1",
  host_port = 8080,
})

if err ~= nil then
  vim.notify(err, vim.log.levels.ERROR)
elseif handle ~= nil then
  local port, port_err = forward.get_port({ handle = handle })

  if port_err ~= nil then
    vim.notify(port_err, vim.log.levels.ERROR)
  elseif port ~= nil then
    print("Client port: " .. port)
  end

  forward.clear({ handle = handle })
end
```

All operation functions take one dictionary. Lua requests return two separate
values, `ret, err`. Check `err == nil` for the absence of a request error. A
handle identifies asynchronous work that may still be in progress. Notifications,
including `clear()`, `clipboard.copy()` and `client.connect()`, return `nil`.
`nauvim-core` validates operation arguments and ensures its RPC responses conform
to the specification.

The root module also exposes each interface:

```lua
local nauvim = require("nauvim-plugin")

assert(nauvim.http == require("nauvim-plugin.http"))
```

See [the help reference](doc/nauvim-plugin.txt) (`:help nauvim-plugin`) for
operations, path rules and destination lifecycle. The available client operations
depend on the features and policies of `nauvim-core`.

For tests and the clipboard wire protocol, see [CONTRIBUTING.md](CONTRIBUTING.md).

Licensed under MIT OR Apache-2.0.
