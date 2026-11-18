# Developing nauvim-plugin

The plugin is pure Lua for Neovim v0.12.6. The public modules encode dictionaries
into positional RPC arguments. `_rpc.lua` owns the single destination and converts
request failures into `nil, err`. `_validate.lua` checks request results and error
text without adding external dependencies. These two modules are internal
interfaces. The core validates RPC arguments. The plugin checks whether its
destination is selected, encodes arguments and validates RPC-request return values.

## Checks

Run from the repository root with Neovim v0.12.6:

```sh
nvim --headless -u NONE -i NONE -l tests/run.lua
nvim --headless -u NONE -i NONE -l tests/live.lua
```

For an AppImage without FUSE, set `APPIMAGE_EXTRACT_AND_RUN=1`. The live suite
starts an embedded Neovim and connects two UI channels over local pipes and a
temporary Unix socket. It needs permission to create that socket. All test RPC
waits are bounded and the child process and transports are closed after testing.

The first suite checks every operation's RPC method and argument order, silent
calls without a destination, argument forwarding, return-value validation and
error conversion, host paths, clipboard callbacks, registration replacement and
notification failures. The live suite checks actual RPC replies, client
registration, `UILeave`, clipboard copy notifications, empty clipboard-register
reads and `client.connect()` detachment.

## Wire protocol

The operation methods and arguments follow Table 7 of the Nauvim specification.
Every RPC starts with the stored process client ID. Client paths remain unchanged
for interpretation and confinement in `nauvim-core`. Relative host paths are
expanded against Neovim's effective current directory before transmission.

The clipboard copy protocol follows specification 11.6:

| Method | Message kind | Positional arguments |
| --- | --- | --- |
| `nauvim-plugin/clipboard.copy` | Notification | `client_id, register, text` |

`register` is `"+"` or `"*"`. `text` is a single UTF-8 string with LF separators
and an optional trailing LF. The provider's copy callbacks join Neovim's lines
with `"\n"`. A trailing empty line already represents a trailing LF, so they do
not use the `regtype` callback argument. Without a destination, they return
before joining the lines. Copy functions return `nil`; clipboard backend errors
are reported in the client.

Each provider paste callback returns a fresh `{ {}, "v" }` pair. These callbacks
supply no text and issue no RPC, with or without a selected destination. GUI
paste is a separate core operation: the core obtains backend text and sends it
to Neovim with `nvim_paste()` or an equivalent paste-input operation. See Neovim's
[clipboard-provider and paste interfaces](https://neovim.io/doc/user/provider/).

All current request results are integer resource handles or assigned ports.
Non-nil handle results must be finite integers; port results must be integers in
1..65535. Nil results are accepted for no-effect and cancellation responses.
Malformed results return `nil, err`. Error text is checked as complete UTF-8
without NUL or BOM; invalid or empty error text is replaced with a nonempty ASCII
message.

Destination checks do not query channel liveness. Send failures use ordinary RPC
handling. Tests use isolated Neovim processes so Lua module caches do not carry
destination state between suites.
