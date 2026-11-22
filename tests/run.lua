-- Run with: nvim --headless -u NONE -i NONE -l tests/run.lua
local real_vim = vim
local root = real_vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local calls, notices, attached, channels = {}, {}, {}, {}
local ui_leave, response, request_failure, notification_failure
local request_throws, notification_throws, list_failure, info_failure = false, false, false, false
local notify_result, list_reads, info_reads = nil, 0, 0

local function pack(...)
  return { n = select("#", ...), ... }
end

local function record(kind, channel, method, ...)
  calls[#calls + 1] = { kind, channel, method, pack(...) }
end

local function detach()
  calls[#calls + 1] = { "command", "detach" }
end

vim = {
  NIL = real_vim.NIL,
  v = { event = {} },
  api = {
    nvim_create_augroup = function() return 41 end,
    nvim_create_autocmd = function(event, opts)
      assert(event == "UILeave")
      ui_leave = opts.callback
    end,
    nvim_list_uis = function()
      list_reads = list_reads + 1
      if list_failure then error("list UIs failed", 0) end
      return attached
    end,
    nvim_get_chan_info = function(chan)
      info_reads = info_reads + 1
      if info_failure then error("channel lookup failed", 0) end
      return channels[chan] or {}
    end,
  },
  rpcrequest = function(channel, method, ...)
    record("request", channel, method, ...)
    if request_throws then error(request_failure, 0) end
    return response
  end,
  rpcnotify = function(channel, method, ...)
    record("notification", channel, method, ...)
    if notification_throws then error(notification_failure, 0) end
    return notify_result
  end,
  notify = function(message, level)
    notices[#notices + 1] = { message, level }
  end,
  cmd = setmetatable({ detach = detach }, { __call = function(_, command)
    assert(command == "detach", "unexpected command: " .. tostring(command))
    detach()
  end }),
}
setmetatable(vim, { __index = real_vim })
setmetatable(vim.api, { __index = real_vim.api })

local plugin = require("nauvim-plugin")
local client, forward = plugin.client, plugin["local-forward"]
local filesystem, http, clipboard = plugin.filesystem, plugin.http, plugin.clipboard

local function eq(expected, actual)
  assert(real_vim.deep_equal(expected, actual),
    "expected " .. real_vim.inspect(expected) .. ", got " .. real_vim.inspect(actual))
end

local function error_string(err)
  assert(type(err) == "string" and #err > 0, "expected a nonempty error string")
end

local function setup(id, channel)
  attached = { { chan = 1 }, { chan = channel } }
  channels = {
    [1] = { client = { name = "another-ui" } },
    [channel] = { client = { name = "nauvim-client-" .. string.format("%.0f", id) } },
  }
  local calls_before, notices_before = #calls, #notices
  eq(nil, client.setup({ client_id = id }))
  eq(calls_before, #calls); eq(notices_before, #notices)
end

local requests = {
  forward.open_tcp, forward.open_socket, forward.get_port, filesystem.copy,
  http.serve_file, http.get_port, http.open_webview,
}
local notifications = { forward.clear, filesystem.clear, http.clear, http.focus_webview, clipboard.copy, client.connect }

local function empty_paste()
  for _, register in ipairs({ "+", "*" }) do
    local first = clipboard.provider.paste[register]()
    eq({ {}, "v" }, first)
    first[1][1], first[2] = "mutated", "V"
    eq({ {}, "v" }, clipboard.provider.paste[register]())
  end
end

local function no_destination()
  calls, notices = {}, {}
  local explosive = setmetatable({}, { __index = function() error("input was inspected") end })
  for _, f in ipairs(requests) do
    for _, opts in ipairs({ false, explosive }) do
      eq({ n = 2 }, pack(f(opts)))
    end
    eq({ n = 2 }, pack(f()))
  end
  for _, f in ipairs(notifications) do
    eq({ n = 1 }, pack(f(explosive))); eq({ n = 1 }, pack(f()))
  end
  for _, register in ipairs({ "+", "*" }) do
    eq(nil, clipboard.provider.copy[register](nil, nil))
    eq(nil, clipboard.provider.copy[register](explosive, nil))
  end
  empty_paste()
  eq({}, calls); eq({}, notices)
end

no_destination()
assert(type(ui_leave) == "function")
eq(0, clipboard.provider.cache_enabled)
eq(nil, clipboard.paste)

local position = { grid = 2, top = 1, left = 2, height = 3, width = 4 }
local request_cases = {
  { forward.open_tcp, { client_port = 0, host_addr = "127.0.0.1", host_port = 8080 },
    "local-forward.open_tcp", { n = 4, 4294967295, 0, "127.0.0.1", 8080 }, 79 },
  { forward.open_socket, { client_socket_path = "///client.sock", host_socket_path = "/tmp/host.sock" },
    "local-forward.open_socket", { n = 3, 4294967295, "///client.sock", "/tmp/host.sock" }, 80 },
  { forward.get_port, { handle = 7 }, "local-forward.get_port", { n = 2, 4294967295, 7 }, 12345 },
  { filesystem.copy, { client_file = "/preview", host_file = "/host/日本語", override = false },
    "filesystem.copy", { n = 4, 4294967295, "/preview", "/host/日本語", false }, 81 },
  { http.serve_file, { client_file = "preview", client_port = 0, https = false, http2 = false },
    "http.serve_file", { n = 5, 4294967295, "preview", 0, false, false }, 82 },
  { http.serve_file, { client_file = "preview", client_port = 0, https = true, http2 = false },
    "http.serve_file", { n = 5, 4294967295, "preview", 0, true, false }, 82 },
  { http.serve_file, { client_file = "preview", client_port = 0, https = true, http2 = true },
    "http.serve_file", { n = 5, 4294967295, "preview", 0, true, true }, 82 },
  { http.get_port, { handle = 8 }, "http.get_port", { n = 2, 4294967295, 8 }, 23456 },
  { http.open_webview, { url = "https://localhost/#fragment", position = position },
    "http.open_webview", { n = 5, 4294967295, "https://localhost/#fragment", position }, 83 },
  { http.open_webview, { url = "https://localhost", position = position, focus = false },
    "http.open_webview", { n = 5, 4294967295, "https://localhost", position, false }, 83 },
  { http.open_webview, { url = "https://localhost", position = position, focusable = false },
    "http.open_webview", { n = 5, 4294967295, "https://localhost", position, nil, false }, 83 },
  { http.open_webview, { url = "https://localhost", position = position, focus = true, focusable = false },
    "http.open_webview", { n = 5, 4294967295, "https://localhost", position, true, false }, 83 },
}

setup(4294967295, 22)
local before_lists, before_infos = list_reads, info_reads
for _, case in ipairs(request_cases) do
  calls, response = {}, case[5]
  local opts_before = real_vim.deepcopy(case[2])
  eq({ n = 2, case[5] }, pack(case[1](case[2])))
  eq(opts_before, case[2])
  eq({ { "request", 22, "nauvim-plugin/" .. case[3], case[4] } }, calls)
end
eq(before_lists, list_reads); eq(before_infos, info_reads)

-- Core rejects plain HTTP/2 before startup. The plugin forwards it and returns
-- the request error as the second Lua result.
calls, request_throws, request_failure = {}, true, "HTTP/2 requires HTTPS"
eq({ n = 2, [2] = request_failure }, pack(http.serve_file({
  client_file = "preview", client_port = 0, https = false, http2 = true,
})))
eq({ { "request", 22, "nauvim-plugin/http.serve_file", { n = 5, 4294967295, "preview", 0, false, true } } }, calls)
request_throws = false

-- A core policy denial uses the request's error return slot.
calls, notices, request_throws, request_failure = {}, {}, true, "Webview access denied by host policy"
eq({ n = 2, [2] = request_failure }, pack(http.open_webview({ url = "https://localhost", position = position })))
eq({ { "request", 22, "nauvim-plugin/http.open_webview", { n = 5, 4294967295, "https://localhost", position } } }, calls)
eq({}, notices)
request_throws = false

-- No-effect and cancellation replies preserve both Lua return slots.
for _, case in ipairs(request_cases) do
  response = real_vim.NIL
  eq({ n = 2 }, pack(case[1](case[2])))
  response = nil
  eq({ n = 2 }, pack(case[1](case[2])))
end
for _, f in ipairs({ forward.get_port, http.get_port }) do
  for _, value in ipairs({ 1, 65535 }) do
    response = value
    eq({ n = 2, value }, pack(f({ handle = 1 })))
  end
end
for _, case in ipairs(request_cases) do
  if case[1] ~= forward.get_port and case[1] ~= http.get_port then
    for _, value in ipairs({ -1, 0 }) do
      response = value
      eq({ n = 2, value }, pack(case[1](case[2])))
    end
  end
end

-- Locally raised Lua errors need a nonempty message. RPC text rules apply to
-- wire responses, so locally generated strings keep their original contents.
request_throws = true
for _, case in ipairs({
  { "RPC failure", "RPC failure" },
  { "", "Nauvim RPC request failed" },
  { "\0", "\0" },
  { "\239\187\191", "\239\187\191" },
  { "\255", "\255" },
  { false, "false" },
  { setmetatable({}, { __tostring = function() return "custom RPC error" end }), "custom RPC error" },
  { setmetatable({}, { __tostring = function() error("bad error formatter") end }), "Nauvim RPC request failed" },
}) do
  request_failure = case[1]
  eq({ n = 2, [2] = case[2] }, pack(forward.get_port({ handle = 1 })))
end
request_throws = false

-- Core validates inputs. The plugin forwards their field values unchanged.
local invalid_position = { grid = "grid", top = -1, left = false, height = 65536, width = 1, extra = true }
local passthrough_cases = {
  { forward.open_tcp, { client_port = -1, host_addr = false, host_port = "80" },
    "local-forward.open_tcp", { n = 4, 4294967295, -1, false, "80" } },
  { forward.open_socket, { client_socket_path = false, host_socket_path = false },
    "local-forward.open_socket", { n = 3, 4294967295, false, false } },
  { forward.get_port, { handle = false, client_id = 3 },
    "local-forward.get_port", { n = 2, 4294967295, false } },
  { filesystem.copy, { client_file = false, host_file = false, override = 0 },
    "filesystem.copy", { n = 4, 4294967295, false, false, 0 } },
  { http.serve_file, { client_file = false, client_port = 65536, https = false, http2 = false },
    "http.serve_file", { n = 5, 4294967295, false, 65536, false, false } },
  { http.get_port, { handle = "not a handle" },
    "http.get_port", { n = 2, 4294967295, "not a handle" } },
  { http.open_webview, { url = "ftp://localhost", position = invalid_position, focus = "false", focusable = 0 },
    "http.open_webview", { n = 5, 4294967295, "ftp://localhost", invalid_position, "false", 0 } },
}
response = 84
for _, case in ipairs(passthrough_cases) do
  calls = {}
  eq({ n = 2, 84 }, pack(case[1](case[2])))
  eq({ { "request", 22, "nauvim-plugin/" .. case[3], case[4] } }, calls)
end

local passthrough_strings = {
  "prefix\0suffix", "\239\187\191prefix", "prefix\239\187\191suffix", "\128", "\192\128", "\193\191",
  "\194", "\224\159\191", "\237\160\128", "\240\143\191\191",
  "\244\144\128\128", "\245\128\128\128", "\255",
}
for _, s in ipairs(passthrough_strings) do
  calls, response = {}, 84
  eq({ n = 2, 84 }, pack(forward.open_tcp({ client_port = 0, host_addr = s, host_port = 1 })))
  eq({ { "request", 22, "nauvim-plugin/local-forward.open_tcp", { n = 4, 4294967295, 0, s, 1 } } }, calls)
  calls = {}
  eq(nil, clipboard.copy({ register = "invalid register", text = s }))
  eq({ { "notification", 22, "nauvim-plugin/clipboard.copy", { n = 3, 4294967295, "invalid register", s } } }, calls)
end

-- Host paths use the current window's local directory; client paths stay raw.
local cwd, temp = real_vim.fn.getcwd(), real_vim.fn.tempname()
assert(real_vim.fn.mkdir(temp .. "/日本 語", "p") == 1)
real_vim.cmd("lcd " .. real_vim.fn.fnameescape(temp .. "/日本 語"))
calls, response = {}, 85
local ret, err = filesystem.copy({ client_file = "///preview/%2e%2e/file", host_file = "source.txt", override = true })
eq(85, ret); eq(nil, err)
eq({ n = 4, 4294967295, "///preview/%2e%2e/file", temp .. "/日本 語/source.txt", true }, calls[1][4])
calls = {}
ret, err = forward.open_socket({ client_socket_path = "relative.sock", host_socket_path = "host.sock" })
eq(85, ret); eq(nil, err)
eq({ n = 3, 4294967295, "relative.sock", temp .. "/日本 語/host.sock" }, calls[1][4])
real_vim.cmd("lcd " .. real_vim.fn.fnameescape(cwd))
real_vim.fn.delete(temp, "rf")

calls = {}
eq(nil, forward.clear({ handle = 1 }))
eq(nil, filesystem.clear({ handle = 2 }))
eq(nil, http.clear({ handle = 3 }))
eq({ n = 1 }, pack(http.focus_webview({ handle = 4 })))
eq({ n = 1 }, pack(http.focus_webview({ handle = "not a handle" })))
eq(nil, clipboard.copy({ register = "+", text = "first\n日本語\n" }))
eq({
  { "notification", 22, "nauvim-plugin/local-forward.clear", { n = 2, 4294967295, 1 } },
  { "notification", 22, "nauvim-plugin/filesystem.clear", { n = 2, 4294967295, 2 } },
  { "notification", 22, "nauvim-plugin/http.clear", { n = 2, 4294967295, 3 } },
  { "notification", 22, "nauvim-plugin/http.focus_webview", { n = 2, 4294967295, 4 } },
  { "notification", 22, "nauvim-plugin/http.focus_webview", { n = 2, 4294967295, "not a handle" } },
  { "notification", 22, "nauvim-plugin/clipboard.copy", { n = 3, 4294967295, "+", "first\n日本語\n" } },
}, calls)
notification_throws, notification_failure = true, "stale channel"
for _, f in ipairs({ forward.clear, filesystem.clear, http.clear, http.focus_webview }) do
  eq(nil, f({ handle = 1 }))
end
eq(nil, clipboard.copy({ register = "+", text = "text" }))
notification_throws = false

-- Provider callbacks preserve text and newlines and never fetch client text.
for _, case in ipairs({
  { { "one", "two" }, "v", "one\ntwo" },
  { { "one", "two", "" }, "V", "one\ntwo\n" },
  { { "ab", "c", "" }, "b", "ab\nc\n" },
  { {}, "v", "" }, { { "" }, "v", "" }, { { "", "" }, "V", "\n" },
}) do
  for _, register in ipairs({ "+", "*" }) do
    calls, notices = {}, {}
    eq(nil, clipboard.provider.copy[register](case[1], case[2]))
    eq({ { "notification", 22, "nauvim-plugin/clipboard.copy", { n = 3, 4294967295, register, case[3] } } }, calls)
    eq({}, notices)
  end
end
calls, notices = {}, {}
request_throws, request_failure = true, "paste must not send requests"
notification_throws, notification_failure = true, "paste must not send notifications"
empty_paste()
eq({}, calls); eq({}, notices)
request_throws, notification_throws = false, false

-- Successful notification precedes detachment; failure keeps the destination.
calls, notices = {}, {}
eq(nil, client.connect({ host = "another-host" }))
eq({
  { "notification", 22, "nauvim-plugin/client.connect", { n = 2, 4294967295, "another-host" } },
  { "command", "detach" },
}, calls)
eq({}, notices)
for _, throws in ipairs({ false, true }) do
  calls, notices = {}, {}
  notify_result, notification_throws = false, throws
  notification_failure = "notification failure"
  eq(nil, client.connect({ host = "another-host" }))
  eq({ { "notification", 22, "nauvim-plugin/client.connect", { n = 2, 4294967295, "another-host" } } }, calls)
  eq(1, #notices); error_string(notices[1][1])
  notification_throws, notify_result = false, nil
  calls = {}
  forward.clear({ handle = 9 })
  eq({ { "notification", 22, "nauvim-plugin/local-forward.clear", { n = 2, 4294967295, 9 } } }, calls)
end

calls, notices = {}, {}
setup(0, 33)
eq({}, calls); eq({}, notices)
eq(nil, client.setup({ client_id = -1 / math.huge }))
forward.clear({ handle = 1 })
eq({ { "notification", 33, "nauvim-plugin/local-forward.clear", { n = 2, 0, 1 } } }, calls)
eq(math.huge, 1 / calls[1][4][1])
calls = {}
vim.v.event = { chan = 22 }; ui_leave()
forward.clear({ handle = 2 })
eq({ { "notification", 33, "nauvim-plugin/local-forward.clear", { n = 2, 0, 2 } } }, calls)
vim.v.event = { chan = 33 }; ui_leave()
no_destination()

-- Setup discovery and operational failures stay silent and clear both IDs.
local function failed_setup(opts)
  calls, notices = {}, {}
  eq(nil, client.setup(opts))
  eq({}, calls); eq({}, notices)
  no_destination()
end
setup(1, 22); failed_setup(nil)
setup(1, 22); failed_setup(false)
setup(1, 22); failed_setup({})
setup(1, 22); failed_setup({ client_id = 2 })
setup(1, 22)
list_failure = true; failed_setup({ client_id = 1 }); list_failure = false
setup(1, 22)
info_failure = true; failed_setup({ client_id = 1 }); info_failure = false
setup(1, 22)
attached = { { chan = 1 } }
channels[22] = { client = { name = "nauvim-client-1" } }
failed_setup({ client_id = 1 })

-- Earlier no-destination calls are not replayed by setup.
setup(3, 44)
eq({}, calls); eq({}, notices)

vim = real_vim
print("nauvim-plugin: RPC adaptation, clipboard and destination tests passed")
