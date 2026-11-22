-- Exercises the plugin over real RPC connections to Neovim v0.12.6.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local uv = vim.uv
local stdin, stdout, stderr = assert(uv.new_pipe(false)), assert(uv.new_pipe(false)), assert(uv.new_pipe(false))
local diagnostics, exited = {}, false
local messages, result, response_error = {}, 81, vim.NIL
local process = assert(uv.spawn(vim.v.progpath, {
  args = { "--embed", "--headless", "-u", "NONE", "-i", "NONE" },
  stdio = { stdin, stdout, stderr },
}, function() exited = true end))

local function rpc_client(wtr, rdr)
  local unpacker, responses, next_id, failure = vim.mpack.Unpacker(), {}, 0, nil
  assert(rdr:read_start(function(err, data)
    if err then failure = err; return end
    if not data then failure = "RPC stream closed"; return end
    local pos = 1
    while pos <= #data do
      local message
      message, pos = unpacker(data, pos)
      if message then
        if message[1] == 1 then
          responses[message[2]] = message
        elseif message[1] == 0 then
          messages[#messages + 1] = { "request", message[3], message[4] }
          assert(wtr:write(vim.mpack.encode({ 1, message[2], response_error, result })))
        elseif message[1] == 2 and message[2]:find("nauvim-plugin/", 1, true) == 1 then
          messages[#messages + 1] = { "notification", message[2], message[3] }
        end
      end
    end
  end))
  local function request(method, ...)
    next_id = next_id + 1
    local id = next_id
    assert(wtr:write(vim.mpack.encode({ 0, id, method, { ... } })))
    assert(vim.wait(5000, function() return responses[id] ~= nil or failure ~= nil end, 1), "RPC timeout: " .. method)
    assert(not failure, failure)
    local message = responses[id]
    responses[id] = nil
    assert(message[3] == vim.NIL, vim.inspect(message[3]))
    return message[4]
  end
  local function notify(method, ...)
    assert(wtr:write(vim.mpack.encode({ 2, method, { ... } })))
  end
  return request, notify
end

assert(stderr:read_start(function(_, data)
  if data then diagnostics[#diagnostics + 1] = data end
end))
local request = rpc_client(stdin, stdout)
local function lua(src, ...)
  return request("nvim_exec_lua", src, { ... })
end
local function eq(expected, actual)
  assert(vim.deep_equal(expected, actual),
    "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end

local function webview_rpc()
  local url = "https://example.com/preview"
  local position = { grid = 1, top = 2, left = 3, height = 4, width = 5 }
  local open = [[
    local function reply(...)
      local ret, err = ...
      return { select("#", ...), ret or vim.NIL, err or vim.NIL }
    end
    return reply(require("nauvim-plugin.http").open_webview(...))
  ]]

  result = 81
  for _, flags in ipairs({
    { vim.NIL, vim.NIL, vim.NIL },
    { false, vim.NIL, true },
    { vim.NIL, false, vim.NIL },
    { true, false, false },
    { "invalid focus", 0, "invalid close_on_blur" },
  }) do
    local opts = { url = url, position = position }
    if flags[1] ~= vim.NIL then opts.focus = flags[1] end
    if flags[2] ~= vim.NIL then opts.focusable = flags[2] end
    if flags[3] ~= vim.NIL then opts.close_on_blur = flags[3] end

    messages = {}
    eq({ 2, 81, vim.NIL }, lua(open, opts))
    eq({ { "request", "nauvim-plugin/http.open_webview", { 4294967295, url, position, flags[1], flags[2], flags[3] } } }, messages)
  end

  messages = {}
  response_error, result = "host policy denied Webview access", vim.NIL
  local denied = lua(open, { url = url, position = position })
  eq(2, denied[1])
  eq(vim.NIL, denied[2])
  assert(type(denied[3]) == "string" and denied[3]:find(response_error, 1, true), vim.inspect(denied))
  eq({ { "request", "nauvim-plugin/http.open_webview", { 4294967295, url, position, vim.NIL, vim.NIL, vim.NIL } } }, messages)
  response_error = vim.NIL

  messages = {}
  eq({ 1, true }, lua([[
    local function reply(...)
      return { select("#", ...), ... == nil }
    end
    return reply(require("nauvim-plugin.http").focus_webview({ handle = 81 }))
  ]]))
  eq({ { "notification", "nauvim-plugin/http.focus_webview", { 4294967295, 81 } } }, messages)

  messages = {}
  eq({ 1, true }, lua([[
    local function reply(...)
      return { select("#", ...), ... == nil }
    end
    return reply(require("nauvim-plugin.http").navigate_webview({
      handle = 81, url = "https://example.com/preview#next", focus = false,
    }))
  ]]))
  eq({ { "notification", "nauvim-plugin/http.navigate_webview",
    { 4294967295, 81, "https://example.com/preview#next", vim.NIL, false } } }, messages)
end

local function empty_register_reads()
  local before = lua("return vim.api.nvim_exec2('messages', { output = true }).output")
  messages = {}
  for _, register in ipairs({ "+", "*" }) do
    local ret = lua([[
      local register = ...
      return { vim.fn.getreg(register, 1, true), vim.fn.getregtype(register) }
    ]], register)
    eq({ {}, "v" }, ret)
  end
  eq({}, messages)
  eq(before, lua("return vim.api.nvim_exec2('messages', { output = true }).output"))
end

local secondary
local ok, err = xpcall(function()
  lua("vim.opt.runtimepath:prepend(...)", root)
  request("nvim_set_client_info", "nauvim-client-4294967295", vim.empty_dict(), "ui", vim.empty_dict(), vim.empty_dict())
  request("nvim_ui_attach", 80, 24, { rgb = true, ext_linegrid = true })
  lua([[
    require("nauvim-plugin.client").setup({ client_id = 4294967295 })
    require("nauvim-plugin.local-forward").clear({ handle = 72 })
  ]])
  eq({ { "notification", "nauvim-plugin/local-forward.clear", { 4294967295, 72 } } }, messages)

  local ret = lua([[
    local ret, err = require("nauvim-plugin.local-forward").open_tcp({
      client_port = 0, host_addr = "localhost", host_port = 8080,
    })
    return { ret, err or vim.NIL }
  ]])
  eq({ 81, vim.NIL }, ret)
  eq({ "request", "nauvim-plugin/local-forward.open_tcp", { 4294967295, 0, "localhost", 8080 } }, messages[2])

  response_error, result = "intentional engine error", vim.NIL
  ret = lua([[
    local ret, err = require("nauvim-plugin.local-forward").get_port({ handle = 81 })
    return { ret or vim.NIL, err or vim.NIL }
  ]])
  eq(vim.NIL, ret[1])
  assert(type(ret[2]) == "string" and ret[2]:find("intentional engine error", 1, true))
  response_error = vim.NIL
  ret = lua([[
    local ret, err = require("nauvim-plugin.local-forward").get_port({ handle = 81 })
    return { ret == nil, err == nil }
  ]])
  eq({ true, true }, ret)

  webview_rpc()

  -- Neovim supplies the linewise/blockwise trailing empty callback line.
  -- The provider turns those callback lines into exactly one text string.
  lua('vim.g.clipboard = require("nauvim-plugin.clipboard").provider')
  for _, case in ipairs({
    { { "first", "日本語" }, "v", "first\n日本語" },
    { { "first", "日本語" }, "V", "first\n日本語\n" },
    { { "ab", "c" }, "\22" .. "2", "ab\nc\n" },
    { {}, "v", "" }, { { "" }, "v", "" }, { { "" }, "V", "\n" },
  }) do
    for _, register in ipairs({ "+", "*" }) do
      messages = {}
      lua([[
        local register, lines, regtype = ...
        vim.fn.setreg(register, lines, regtype)
      ]], register, case[1], case[2])
      eq({ { "notification", "nauvim-plugin/clipboard.copy", { 4294967295, register, case[3] } } }, messages)
    end
  end
  empty_register_reads()
  result, messages = 81, {}

  local socket = lua("return vim.fn.serverstart(vim.fn.tempname() .. '.sock')")
  secondary = assert(uv.new_pipe(false))
  local connected, connect_error = false, nil
  secondary:connect(socket, function(e) connected, connect_error = true, e end)
  assert(vim.wait(5000, function() return connected end, 1), "second UI connection timeout")
  assert(not connect_error, connect_error)
  local second_request, second_notify = rpc_client(secondary, secondary)
  second_request("nvim_set_client_info", "nauvim-client-0", vim.empty_dict(), "ui", vim.empty_dict(), vim.empty_dict())
  second_request("nvim_ui_attach", 80, 24, { rgb = true, ext_linegrid = true })
  second_request("nvim_ui_detach")
  lua('require("nauvim-plugin.local-forward").clear({ handle = 73 })')
  eq({ { "notification", "nauvim-plugin/local-forward.clear", { 4294967295, 73 } } }, messages)
  messages = {}

  second_request("nvim_ui_attach", 80, 24, { rgb = true, ext_linegrid = true })
  lua([[
    require("nauvim-plugin.client").setup({ client_id = -1 / math.huge })
    require("nauvim-plugin.local-forward").clear({ handle = 74 })
  ]])
  eq({ { "notification", "nauvim-plugin/local-forward.clear", { 0, 74 } } }, messages)
  messages = {}
  request("nvim_ui_detach")
  lua('require("nauvim-plugin.local-forward").clear({ handle = 75 })')
  eq({ { "notification", "nauvim-plugin/local-forward.clear", { 0, 75 } } }, messages)

  -- A matching name on a channel without an attached UI cannot be selected.
  messages = {}
  lua([[
    require("nauvim-plugin.client").setup({ client_id = 4294967295 })
    require("nauvim-plugin.local-forward").clear({ handle = 76 })
  ]])
  eq({}, messages)
  empty_register_reads()
  lua('require("nauvim-plugin.client").setup({ client_id = 0 })')
  second_request("nvim_ui_detach")
  local before = lua("return vim.api.nvim_exec2('messages', { output = true }).output")
  lua([[
    require("nauvim-plugin.local-forward").clear({ handle = 77 })
    local http = require("nauvim-plugin.http")
    local ret, err = http.open_webview(false)
    assert(ret == nil and err == nil)
    assert(http.focus_webview(false) == nil)
    assert(http.navigate_webview(false) == nil)
  ]])
  eq({}, messages)
  eq(before, lua("return vim.api.nvim_exec2('messages', { output = true }).output"))

  second_request("nvim_ui_attach", 80, 24, { rgb = true, ext_linegrid = true })
  lua('require("nauvim-plugin.client").setup({ client_id = 0 })')
  -- :detach closes its invoking UI channel. A notification lets the UI
  -- initiate switching without awaiting a response on that closing channel.
  second_notify("nvim_exec_lua", 'require("nauvim-plugin.client").connect({ host = "next-host" })', {})
  assert(vim.wait(5000, function() return #messages > 0 end, 1), "connect notification timeout")
  eq({ { "notification", "nauvim-plugin/client.connect", { 0, "next-host" } } }, messages)
  local remaining = lua("return vim.api.nvim_list_uis()")
  assert(#remaining == 0, "UI remained attached after connect: "
    .. lua("return vim.api.nvim_exec2('messages', { output = true }).output"))
  messages = {}
  lua('require("nauvim-plugin.local-forward").clear({ handle = 78 })')
  eq({}, messages)
end, debug.traceback)

if secondary and not secondary:is_closing() then secondary:close() end
process:kill("sigterm")
assert(vim.wait(3000, function() return exited end, 1), "child process did not exit")
for _, pipe in ipairs({ stdin, stdout, stderr }) do
  if not pipe:is_closing() then pipe:close() end
end
process:close()
if not ok then error(err .. "\n" .. table.concat(diagnostics)) end
print("nauvim-plugin: live RPC, clipboard-provider and UI lifecycle tests passed")
