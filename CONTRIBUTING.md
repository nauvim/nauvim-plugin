# Developing nauvim-plugin

The plugin is pure Lua for Neovim v0.12.6. The public modules encode dictionaries
into positional RPC arguments. The internal module `_rpc.lua` selects and stores
the destination and adapts Neovim RPC replies and failures to Lua return values.
The core validates RPC arguments and ensures its responses conform to the spec.

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
calls without a destination, argument forwarding, HTTP protocol selection, exact
request return counts, error propagation, host paths, clipboard callbacks,
registration replacement and notification failures. The live suite checks actual
RPC replies, Webview argument slots, focus and navigation notifications,
client registration, `UILeave`, clipboard copy notifications, empty
clipboard-register reads and `client.connect()` detachment.

## Wire protocol

The operation methods and arguments follow Table 7 of the Nauvim specification.
Every RPC starts with the stored process client ID. Client paths remain unchanged
for interpretation and confinement in `nauvim-core`. Relative host paths are
expanded against Neovim's effective current directory before transmission.

The Webview and clipboard methods use these argument lists.

| Method | Message kind | Positional arguments |
| --- | --- | --- |
| `nauvim-plugin/http.open_webview` | Request | `client_id, url, position, focus, focusable, close_on_blur` |
| `nauvim-plugin/http.focus_webview` | Notification | `client_id, handle` |
| `nauvim-plugin/http.navigate_webview` | Notification | `client_id, handle, url, replace_history, focus` |
| `nauvim-plugin/clipboard.copy` | Notification | `client_id, register, text` |

`http.open_webview()` and `http.navigate_webview()` send a MessagePack nil in
each omitted flag's slot. The plugin forwards explicit values, including
`false`, to the core. The core validates the flags and supplies their defaults.
The core looks up the window for focus and navigation notifications. The
notification functions return `nil`, and the client reports operation failures.

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

Successful request results are integer resource handles, assigned ports in
1..65535, or nil for no-effect and cancellation responses. The plugin maps the
RPC nil sentinel to Lua nil and returns two values for every request. The core
supplies RPC error text as nonempty UTF-8 without NUL or an initial U+FEFF. If a
Neovim exception cannot be formatted as a nonempty string, the plugin supplies a
fallback message.

The core applies the selected host's permissions before performing a governed
operation or allocating its handle. Omitted permissions grant no access. The
core returns an RPC error for a denied request, which the plugin exposes as
`nil, err`. For a denied notification, the core reports a client-side Nauvim
error and sends no RPC response. See [host-specific policy checks](https://github.com/nauvim/nauvim-spec/blob/v1.2.0/specification.md#host-specific-policy-checks).

Destination checks do not query channel liveness. Send failures use ordinary RPC
handling. Tests use isolated Neovim processes so Lua module caches do not carry
destination state between suites.
