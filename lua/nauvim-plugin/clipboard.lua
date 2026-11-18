local rpc = require("nauvim-plugin._rpc")

local M = {}

local function encode_copy(opts)
  return opts.register, opts.text
end

--- Sends text to the system clipboard in the client environment.
---@param opts { register: '+'|'*', text: string }
function M.copy(opts)
  rpc.notify("clipboard.copy", opts, encode_copy)
  return nil
end

local function copy(selected_register)
  return function(lines, _regtype)
    if rpc.ready() then
      -- Neovim supplies a trailing empty line when the register ends in LF.
      M.copy({ register = selected_register, text = table.concat(lines, "\n") })
    end
    return nil
  end
end

local function paste()
  return { {}, "v" }
end

--- Clipboard provider suitable for direct assignment to vim.g.clipboard.
M.provider = {
  name = "Nauvim",
  copy = { ["+"] = copy("+"), ["*"] = copy("*") },
  paste = { ["+"] = paste, ["*"] = paste },
  cache_enabled = 0,
}

return M
