-- RPC response checks. Argument validation belongs to nauvim-core.
local M = {}

function M.integer(value, name, min, max)
  if type(value) ~= "number"
    or value ~= value
    or value == math.huge
    or value == -math.huge
    or value ~= math.floor(value)
    or (min and value < min)
    or (max and value > max)
  then
    error(name .. " must be an integer in the permitted range", 0)
  end
end

function M.port(value)
  M.integer(value, "RPC port result", 1, 65535)
end

return M
