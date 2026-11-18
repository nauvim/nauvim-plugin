local rpc = require("nauvim-plugin._rpc")

local M = {}

local function encode_connect(opts)
  return opts.host
end

--- Selects an attached Nauvim client. Called internally by nauvim-core.
--- An unsuccessful selection quietly clears the previous destination.
---@param opts { client_id: integer }
function M.setup(opts)
  rpc.setup(opts)
end

--- Requests a client-side host switch and immediately detaches the host UI.
---@param opts { host: string } Client-side Nauvim host alias.
function M.connect(opts)
  local sent, err = rpc.notify("client.connect", opts, encode_connect)
  if err ~= nil then
    vim.notify(err, vim.log.levels.ERROR)
  elseif sent then
    local ok, detach_err = pcall(vim.cmd, "detach")
    if not ok then
      vim.notify(rpc.error_message(detach_err, "Nauvim host detachment failed"), vim.log.levels.ERROR)
    end
  end
  return nil
end

return M
