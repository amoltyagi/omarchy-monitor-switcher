-- Reads Omarchy's shell.json and reports whether a plugin id is enabled.
--
-- Mirrors PluginRegistry.isEnabled()/findEntryLocation(): an id is enabled when
-- it appears as the active bar option (`bar.id`), as an exact id in a
-- `bar.layout.left|center|right` entry (entries are a plain id string or an
-- object with `.id`), or as a `plugins[].id`, unless it is listed in
-- `disabledPlugins`. Matching is exact: `case.monitor-switcher-extra` is a
-- different plugin.
--
-- The generated Hyprland toggle file loads this module with dofile() so it can
-- go inert when this plugin is disabled or removed. Self-contained on purpose:
-- no require(), so it resolves nothing through package.path.

local M = {}

-- --- Minimal RFC 8259 JSON decoder -----------------------------------------

local function skip_ws(s, i)
  while i <= #s do
    local c = s:sub(i, i)
    if c ~= " " and c ~= "\t" and c ~= "\n" and c ~= "\r" then break end
    i = i + 1
  end
  return i
end

local parse_value

local function parse_string(s, i)
  local out = {}
  i = i + 1 -- opening quote
  while i <= #s do
    local c = s:sub(i, i)
    if c == '"' then
      return table.concat(out), i + 1
    elseif c == "\\" then
      local e = s:sub(i + 1, i + 1)
      if e == '"' or e == "\\" or e == "/" then
        out[#out + 1] = e
        i = i + 2
      elseif e == "b" then out[#out + 1] = "\b"; i = i + 2
      elseif e == "f" then out[#out + 1] = "\f"; i = i + 2
      elseif e == "n" then out[#out + 1] = "\n"; i = i + 2
      elseif e == "r" then out[#out + 1] = "\r"; i = i + 2
      elseif e == "t" then out[#out + 1] = "\t"; i = i + 2
      elseif e == "u" then
        local code = tonumber(s:sub(i + 2, i + 5), 16)
        if not code then error("invalid \\u escape") end
        if code < 0x80 then
          out[#out + 1] = string.char(code)
        elseif code < 0x800 then
          out[#out + 1] = string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
        else
          out[#out + 1] = string.char(
            0xE0 + math.floor(code / 0x1000),
            0x80 + math.floor(code / 0x40) % 0x40,
            0x80 + code % 0x40)
        end
        i = i + 6
      else
        error("invalid escape")
      end
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  error("unterminated string")
end

local function parse_number(s, i)
  local j = i
  while j <= #s and s:sub(j, j):match("[0-9eE%.%+%-]") do j = j + 1 end
  local n = tonumber(s:sub(i, j - 1))
  if not n then error("invalid number") end
  return n, j
end

local function parse_array(s, i)
  local out = {}
  i = skip_ws(s, i + 1)
  if s:sub(i, i) == "]" then return out, i + 1 end
  while true do
    local value
    value, i = parse_value(s, i)
    out[#out + 1] = value
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == "," then
      i = skip_ws(s, i + 1)
    elseif c == "]" then
      return out, i + 1
    else
      error("invalid array")
    end
  end
end

local function parse_object(s, i)
  local out = {}
  i = skip_ws(s, i + 1)
  if s:sub(i, i) == "}" then return out, i + 1 end
  while true do
    local key
    key, i = parse_string(s, skip_ws(s, i))
    i = skip_ws(s, i)
    if s:sub(i, i) ~= ":" then error("invalid object") end
    local value
    value, i = parse_value(s, skip_ws(s, i + 1))
    out[key] = value
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == "," then
      i = skip_ws(s, i + 1)
    elseif c == "}" then
      return out, i + 1
    else
      error("invalid object")
    end
  end
end

parse_value = function(s, i)
  i = skip_ws(s, i)
  local c = s:sub(i, i)
  if c == "{" then return parse_object(s, i) end
  if c == "[" then return parse_array(s, i) end
  if c == '"' then return parse_string(s, i) end
  if s:sub(i, i + 3) == "true" then return true, i + 4 end
  if s:sub(i, i + 4) == "false" then return false, i + 5 end
  if s:sub(i, i + 3) == "null" then return nil, i + 4 end
  return parse_number(s, i)
end

function M.decode(text)
  local value = parse_value(text, 1)
  return value
end

-- --- Enablement ------------------------------------------------------------

local SECTIONS = { "left", "center", "right" }

local function entry_id(entry)
  if type(entry) == "table" then return entry.id end
  return entry
end

local function contains_id(list, id)
  if type(list) ~= "table" then return false end
  for i = 1, #list do
    if entry_id(list[i]) == id then return true end
  end
  return false
end

local function is_disabled(config, id)
  return contains_id(config.disabledPlugins, id)
end

function M.enabled(shell_path, plugin_id)
  if type(plugin_id) ~= "string" or plugin_id == "" then return false end
  local file = io.open(shell_path, "r")
  if not file then return false end
  local text = file:read("a")
  file:close()
  if not text or text == "" then return false end

  local ok, config = pcall(M.decode, text)
  if not ok or type(config) ~= "table" then return false end
  if is_disabled(config, plugin_id) then return false end

  local bar = config.bar
  if type(bar) == "table" then
    if bar.id == plugin_id then return true end
    local layout = bar.layout
    if type(layout) == "table" then
      for _, section in ipairs(SECTIONS) do
        if contains_id(layout[section], plugin_id) then return true end
      end
    end
  end

  return contains_id(config.plugins, plugin_id)
end

return M
