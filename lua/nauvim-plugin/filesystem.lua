local rpc = require("nauvim-plugin._rpc")

local M = {}

---@class NauvimCopyOptions
---@field client_file string Path relative to Nauvim's process temporary directory.
---@field host_file string Path in the host Neovim's current directory.
---@field override boolean Whether to replace an existing destination of the same type.

local function encode_copy(opts)
  local host_file = opts.host_file
  if type(host_file) == "string" then
    -- Capture Neovim's effective current directory without resolving symlinks.
    host_file = vim.fn.fnamemodify(host_file, ":p")
  end
  return opts.client_file, host_file, opts.override
end

local function encode_handle(opts)
  return opts.handle
end

--- Starts copying a host path into Nauvim's process temporary directory.
---@param opts NauvimCopyOptions
---@return integer? handle
---@return string? err
function M.copy(opts)
  return rpc.request("filesystem.copy", opts, encode_copy)
end

--- Stops copying and requests cleanup of the associated client destination.
---@param opts { handle: integer }
function M.clear(opts)
  rpc.notify("filesystem.clear", opts, encode_handle)
  return nil
end

return M
