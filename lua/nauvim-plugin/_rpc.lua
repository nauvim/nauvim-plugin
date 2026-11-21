local M = {}
local channel, client_id

function M.ready()
  return channel ~= nil and client_id ~= nil
end

function M.error_message(value, fallback)
  if value ~= nil then
    local ok, message = pcall(tostring, value)
    if ok and message ~= "" then
      return message
    end
  end
  return fallback
end

local function select_client(opts)
  local id = opts.client_id
  -- Lua's negative zero denotes the same ID but %.0f would retain its sign.
  if id == 0 then
    id = 0
  end
  local name = "nauvim-client-" .. string.format("%.0f", id)
  for _, ui in ipairs(vim.api.nvim_list_uis()) do
    local info = vim.api.nvim_get_chan_info(ui.chan)
    if info.client and info.client.name == name then
      return ui.chan, id
    end
  end
end

function M.setup(opts)
  channel, client_id = nil, nil
  local ok, selected, id = pcall(select_client, opts)
  if ok and selected ~= nil and id ~= nil then
    channel, client_id = selected, id
  else
    channel, client_id = nil, nil
  end
end

local function request(chan, id, method, opts, encode)
  return vim.rpcrequest(chan, "nauvim-plugin/" .. method, id, encode(opts))
end

-- Return the components of the specification's (ret, err) tuple separately.
function M.request(method, opts, encode)
  if not M.ready() then
    return nil, nil
  end
  local ok, ret = pcall(request, channel, client_id, method, opts, encode)
  if not ok then
    return nil, M.error_message(ret, "Nauvim RPC request failed")
  end
  if ret == vim.NIL then
    ret = nil
  end
  return ret, nil
end

local function notify(chan, id, method, opts, encode)
  -- Native vim.rpcnotify() returns no values on success and raises on failure.
  if vim.rpcnotify(chan, "nauvim-plugin/" .. method, id, encode(opts)) == false then
    error("Nauvim RPC notification could not be sent", 0)
  end
end

-- The send outcome is internal: public notification functions return only nil.
function M.notify(method, opts, encode)
  if not M.ready() then
    return nil, nil
  end
  local ok, err = pcall(notify, channel, client_id, method, opts, encode)
  if not ok then
    return nil, M.error_message(err, "Nauvim RPC notification failed")
  end
  return true, nil
end

local group = vim.api.nvim_create_augroup("NauvimPluginDestination", { clear = true })
vim.api.nvim_create_autocmd("UILeave", {
  group = group,
  desc = "Forget the detached Nauvim RPC destination",
  callback = function()
    if vim.v.event.chan == channel then
      channel, client_id = nil, nil
    end
  end,
})

return M
