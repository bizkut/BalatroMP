-- json.lua
--
-- Copyright (c) 2020 rxi
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

local json = { _version = "0.1.2" }

local encode_value -- Forward declaration
local encode_string
local encode_array
local encode_object
local encode_nil
local parse_value -- Forward declaration
local parse_array
local parse_object
local parse_string
local parse_number
local parse_literal

local escape_map = {
  [ "\\" ] = "\\\\",
  [ "\"" ] = "\\\"",
  [ "\b" ] = "\\b",
  [ "\f" ] = "\\f",
  [ "\n" ] = "\\n",
  [ "\r" ] = "\\r",
  [ "\t" ] = "\\t",
}

local escape_char_map = {
  [ "\\" ] = "\\",
  [ "\"" ] = "\"",
  [ "b"  ] = "\b",
  [ "f"  ] = "\f",
  [ "n"  ] = "\n",
  [ "r"  ] = "\r",
  [ "t"  ] = "\t",
}


encode_nil = function()
  return "null"
end


encode_string = function(val)
  local res = {}
  res[#res + 1] = "\""
  for i = 1, #val do
    local c = val:sub(i, i)
    res[#res + 1] = escape_map[c] or c
  end
  res[#res + 1] = "\""
  return table.concat(res)
end


local function is_array(val)
  local n = 0
  for _ in pairs(val) do
    n = n + 1
  end
  for i = 1, n do
    if val[i] == nil then return false end
  end
  return true
end


encode_array = function(val, stack)
  local res = {}
  stack = stack or {}
  stack[val] = true
  res[#res + 1] = "["
  local first = true
  for i = 1, #val do
    if not first then
      res[#res + 1] = ","
    end
    first = false
    res[#res + 1] = encode_value(val[i], stack)
  end
  res[#res + 1] = "]"
  stack[val] = false
  return table.concat(res)
end


encode_object = function(val, stack)
  local res = {}
  stack = stack or {}
  stack[val] = true
  res[#res + 1] = "{"
  local first = true
  for k, v in pairs(val) do
    if type(k) ~= "string" then
      error("invalid object key type: " .. type(k))
    end
    if not first then
      res[#res + 1] = ","
    end
    first = false
    res[#res + 1] = encode_string(k)
    res[#res + 1] = ":"
    res[#res + 1] = encode_value(v, stack)
  end
  res[#res + 1] = "}"
  stack[val] = false
  return table.concat(res)
end


encode_value = function(val, stack)
  local fn = json.type_map[type(val)]
  if not fn then error("invalid value type: " .. type(val)) end
  if stack and stack[val] then error("circular reference") end
  return fn(val, stack)
end


json.type_map = {
  [ "string"  ] = encode_string,
  [ "table"   ] = function(val, stack)
    if is_array(val) then
      return encode_array(val, stack)
    else
      return encode_object(val, stack)
    end
  end,
  [ "number"  ] = function(val) return tostring(val) end,
  [ "boolean" ] = function(val) return tostring(val) end,
  [ "nil"     ] = encode_nil,
}


function json.encode(val, stack)
  return encode_value(val, stack)
end



local parse_error = function(str, idx, msg)
  local line = 1
  local col = 1
  for i = 1, idx -1 do
    col = col + 1
    if str:sub(i, i) == "\n" then
      line = line + 1
      col = 1
    end
  end
  error( string.format("%s at line %d col %d (char %d)", msg, line, col, idx) )
end


local skip_whitespace = function(str, idx)
  local s = str:sub(idx, idx)
  while s == " " or s == "\t" or s == "\n" or s == "\r" do
    idx = idx + 1
    s = str:sub(idx, idx)
  end
  return idx
end


parse_string = function(str, idx)
  local res = {}
  local s = str:sub(idx, idx)
  if s ~= "\"" then parse_error(str, idx, "expected '\"'") end
  idx = idx + 1
  while true do
    s = str:sub(idx, idx)
    if s == "\\" then
      idx = idx + 1
      s = str:sub(idx, idx)
      res[#res + 1] = escape_char_map[s] or s
    elseif s == "\"" then
      idx = idx + 1
      return table.concat(res), idx
    elseif s == "" then
      parse_error(str, idx, "expected '\"', got EOF")
    else
      res[#res + 1] = s
    end
    idx = idx + 1
  end
end


parse_number = function(str, idx)
  local x = str:match("^-?%d+%.?%d*[eE]?[+-]?%d*", idx)
  if not x then parse_error(str, idx, "expected number") end
  return tonumber(x), idx + #x
end


parse_literal = function(str, idx)
  if str:sub(idx, idx + 3) == "true" then
    return true, idx + 4
  elseif str:sub(idx, idx + 4) == "false" then
    return false, idx + 5
  elseif str:sub(idx, idx + 3) == "null" then
    return nil, idx + 4
  end
  parse_error(str, idx, "expected 'true', 'false' or 'null'")
end


parse_array = function(str, idx)
  local res = {}
  local s = str:sub(idx, idx)
  if s ~= "[" then parse_error(str, idx, "expected '['") end
  idx = idx + 1
  idx = skip_whitespace(str, idx)
  s = str:sub(idx, idx)
  if s == "]" then
    return res, idx + 1
  end
  while true do
    local val
    val, idx = parse_value(str, idx)
    res[#res + 1] = val
    idx = skip_whitespace(str, idx)
    s = str:sub(idx, idx)
    if s == "]" then
      return res, idx + 1
    elseif s == "," then
      idx = idx + 1
    else
      parse_error(str, idx, "expected ']' or ','")
    end
  end
end


parse_object = function(str, idx)
  local res = {}
  local s = str:sub(idx, idx)
  if s ~= "{" then parse_error(str, idx, "expected '{'") end
  idx = idx + 1
  idx = skip_whitespace(str, idx)
  s = str:sub(idx, idx)
  if s == "}" then
    return res, idx + 1
  end
  while true do
    local key, val
    key, idx = parse_string(str, idx)
    idx = skip_whitespace(str, idx)
    s = str:sub(idx, idx)
    if s ~= ":" then parse_error(str, idx, "expected ':'") end
    idx = idx + 1
    val, idx = parse_value(str, idx)
    res[key] = val
    idx = skip_whitespace(str, idx)
    s = str:sub(idx, idx)
    if s == "}" then
      return res, idx + 1
    elseif s == "," then
      idx = idx + 1
    else
      parse_error(str, idx, "expected '}' or ','")
    end
  end
end


parse_value = function(str, idx)
  idx = skip_whitespace(str, idx)
  local s = str:sub(idx, idx)
  if s == "\"" then
    return parse_string(str, idx)
  elseif s == "[" then
    return parse_array(str, idx)
  elseif s == "{" then
    return parse_object(str, idx)
  elseif s == "-" or (s >= "0" and s <= "9") then
    return parse_number(str, idx)
  else
    return parse_literal(str, idx)
  end
end


function json.decode(str)
  if type(str) ~= "string" then error("expected string") end
  local val, idx = parse_value(str, 1)
  idx = skip_whitespace(str, idx)
  if idx <= #str then
    parse_error(str, idx, "unexpected trailing character")
  end
  return val
end


return json
