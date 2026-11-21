local rpc = require("nauvim-plugin._rpc")

local M = {}

---@class NauvimTcpForwardOptions
---@field client_port integer Port in 0..65535. Zero requests a system-assigned port.
---@field host_addr string Address reached from the host environment.
---@field host_port integer Port in 1..65535.

---@class NauvimSocketForwardOptions
---@field client_socket_path string Path relative to Nauvim's process temporary directory.
---@field host_socket_path string Path in the host Neovim's current directory.

local function encode_tcp(opts)
  return opts.client_port, opts.host_addr, opts.host_port
end

local function encode_socket(opts)
  local host_socket_path = opts.host_socket_path
  if type(host_socket_path) == "string" then
    -- Capture Neovim's effective current directory without resolving symlinks.
    host_socket_path = vim.fn.fnamemodify(host_socket_path, ":p")
  end
  return opts.client_socket_path, host_socket_path
end

local function encode_handle(opts)
  return opts.handle
end

--- Starts forwarding client IPv4 loopback connections to the host environment.
---@param opts NauvimTcpForwardOptions
---@return integer? handle
---@return string? err
function M.open_tcp(opts)
  return rpc.request("local-forward.open_tcp", opts, encode_tcp)
end

--- Starts forwarding a client Unix domain socket to a host Unix domain socket.
---@param opts NauvimSocketForwardOptions
---@return integer? handle
---@return string? err
function M.open_socket(opts)
  return rpc.request("local-forward.open_socket", opts, encode_socket)
end

--- Waits for TCP binding and returns the assigned client port (1..65535).
---@param opts { handle: integer }
---@return integer? port
---@return string? err
function M.get_port(opts)
  return rpc.request("local-forward.get_port", opts, encode_handle)
end

--- Cancels a pending forward or closes an established forward.
---@param opts { handle: integer }
function M.clear(opts)
  rpc.notify("local-forward.clear", opts, encode_handle)
  return nil
end

return M
