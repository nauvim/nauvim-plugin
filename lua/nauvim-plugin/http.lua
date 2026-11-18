local rpc = require("nauvim-plugin._rpc")
local validate = require("nauvim-plugin._validate")

local M = {}

---@class NauvimServeFileOptions
---@field client_file string Path relative to Nauvim's process temporary directory.
---@field client_port integer Zero requests an operating-system-assigned port.
---@field https boolean Whether to use TLS with a self-signed certificate.
---@field http2 boolean Whether to use HTTP/2 rather than HTTP/1.1.

---@class NauvimWebviewPosition
---@field grid integer Neovim UI grid identifier.
---@field top integer Vertical offset in grid cells.
---@field left integer Horizontal offset in grid cells.
---@field height integer Height in grid cells.
---@field width integer Width in grid cells.

---@class NauvimWebviewOptions
---@field url string HTTP(S) URL resolved in the client environment.
---@field position NauvimWebviewPosition

local function encode_serve(opts)
  return opts.client_file, opts.client_port, opts.https, opts.http2
end

local function encode_webview(opts)
  return opts.url, opts.position
end

local function encode_handle(opts)
  return opts.handle
end

--- Starts serving a client-side file or directory over loopback HTTP(S).
---@param opts NauvimServeFileOptions
---@return integer? handle
---@return string? err
function M.serve_file(opts)
  return rpc.request("http.serve_file", opts, encode_serve)
end

--- Waits for server binding and returns the assigned client port.
---@param opts { handle: integer }
---@return integer? port
---@return string? err
function M.get_port(opts)
  return rpc.request("http.get_port", opts, encode_handle, validate.port)
end

--- Starts opening an HTTP(S) GUI window positioned in Neovim grid cells.
---@param opts NauvimWebviewOptions
---@return integer? handle
---@return string? err
function M.open_webview(opts)
  return rpc.request("http.open_webview", opts, encode_webview)
end

--- Cancels server startup or closes an existing server or GUI window.
---@param opts { handle: integer }
function M.clear(opts)
  rpc.notify("http.clear", opts, encode_handle)
  return nil
end

return M
