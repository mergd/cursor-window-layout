#!/usr/bin/env lua

local HOME = os.getenv("HOME")
local HAMMERSPOON_DIR = HOME .. "/.hammerspoon"
local CONFIG_PATH = HAMMERSPOON_DIR .. "/binding-windows-layouts.lua"
local LEGACY_CONFIG_PATH = HAMMERSPOON_DIR .. "/cursor-layouts.lua"
local MODULE_PATH = HAMMERSPOON_DIR .. "/binding_windows.lua"
local LEGACY_MODULE_PATH = HAMMERSPOON_DIR .. "/cursor_layout.lua"
local INIT_PATH = HAMMERSPOON_DIR .. "/init.lua"
local FIXED_MODS = { "ctrl", "alt", "cmd" }

local function file_exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

local function mkdir_p(path)
  os.execute('mkdir -p "' .. path .. '"')
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

local function write_file(path, content)
  local f = assert(io.open(path, "w"))
  f:write(content)
  f:close()
end

local function shell_escape(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function ping_hammerspoon(event, params)
  local url = "hammerspoon://" .. event
  if params and params.name then
    url = url .. "?name=" .. params.name
  end
  os.execute("open -g " .. shell_escape(url) .. " >/dev/null 2>&1")
end

local function deepcopy(value)
  if type(value) ~= "table" then
    return value
  end
  local copy = {}
  for k, v in pairs(value) do
    copy[k] = deepcopy(v)
  end
  return copy
end

local function default_config()
  return {
    default_layout = "quadrants",
    active_layout = "quadrants",
    auto_apply_on_screen_change = true,
    apply_delay_seconds = 1.0,
    slot_bindings = {
      ["1"] = "quadrants",
      ["2"] = "",
      ["3"] = "",
      ["4"] = "",
      ["5"] = "",
      ["6"] = "",
      ["7"] = "",
      ["8"] = "",
      ["9"] = "",
    },
    layouts = {
      quadrants = {
        description = "Default quadrants layout (configure rules via CLI)",
        screen = "focused",
        rules = {},
      },
    },
  }
end

local LUA_MODULE = [[
local M = {}

local configPath = hs.configdir .. "/binding-windows-layouts.lua"
local hotkeyHandles = {}
local screenWatcher = nil
local fixedMods = { "ctrl", "alt", "cmd" }
local supportedSlots = { "1", "2", "3", "4", "5", "6", "7", "8", "9" }

local function readConfig()
  local ok, conf = pcall(dofile, configPath)
  if not ok or type(conf) ~= "table" then
    hs.notify.new({ title = "Binding Windows", informativeText = "Invalid or missing binding-windows-layouts.lua" }):send()
    return nil
  end
  return conf
end

local function targetScreen(layout)
  if not layout or not layout.screen or layout.screen == "focused" then
    local mouseScreen = hs.mouse.getCurrentScreen()
    if mouseScreen then
      return mouseScreen
    end
    local focusedWindow = hs.window.focusedWindow()
    if focusedWindow then
      local focusedScreen = focusedWindow:screen()
      if focusedScreen then
        return focusedScreen
      end
    end
    return hs.screen.primaryScreen()
  end

  if layout.screen == "primary" then
    return hs.screen.primaryScreen()
  end

  for _, screen in ipairs(hs.screen.allScreens()) do
    if screen:name() == layout.screen then
      return screen
    end
  end

  return hs.screen.primaryScreen()
end

local function screenName(screen)
  if not screen then
    return "nil"
  end
  return screen:name() or "unknown"
end

local function frameForPosition(screenFrame, position)
  local halfW = screenFrame.w / 2
  local halfH = screenFrame.h / 2

  if position == "fullscreen" then
    return { x = screenFrame.x, y = screenFrame.y, w = screenFrame.w, h = screenFrame.h }
  elseif position == "left" then
    return { x = screenFrame.x, y = screenFrame.y, w = halfW, h = screenFrame.h }
  elseif position == "right" then
    return { x = screenFrame.x + halfW, y = screenFrame.y, w = halfW, h = screenFrame.h }
  elseif position == "top_left" then
    return { x = screenFrame.x, y = screenFrame.y, w = halfW, h = halfH }
  elseif position == "top_right" then
    return { x = screenFrame.x + halfW, y = screenFrame.y, w = halfW, h = halfH }
  elseif position == "bottom_left" then
    return { x = screenFrame.x, y = screenFrame.y + halfH, w = halfW, h = halfH }
  elseif position == "bottom_right" then
    return { x = screenFrame.x + halfW, y = screenFrame.y + halfH, w = halfW, h = halfH }
  end

  return nil
end

local function titleMatches(windowTitle, rule)
  if not windowTitle or windowTitle == "" or not rule or not rule.title then
    return false
  end

  local mode = rule.match or "exact"
  if mode == "contains" then
    return string.find(windowTitle, rule.title, 1, true) ~= nil
  elseif mode == "pattern" then
    return string.match(windowTitle, rule.title) ~= nil
  end

  return windowTitle == rule.title
end

local function applyLayout(name)
  local config = readConfig()
  if not config then
    return
  end

  local layoutName = name or config.active_layout or config.default_layout
  if not layoutName then
    hs.notify.new({ title = "Binding Windows", informativeText = "No active layout configured" }):send()
    return
  end

  local layouts = config.layouts or {}
  local layout = layouts[layoutName]
  if not layout then
    hs.notify.new({
      title = "Binding Windows",
      informativeText = "Layout not found: " .. layoutName
    }):send()
    return
  end

  local screen = targetScreen(layout)
  local frame = screen:frame()
  local cursorApp = hs.application.get("Cursor")
  if not cursorApp then
    hs.notify.new({ title = "Binding Windows", informativeText = "Cursor app not running" }):send()
    return
  end

  local windows = cursorApp:allWindows()
  local moved = 0

  for _, rule in ipairs(layout.rules or {}) do
    local targetFrame = frameForPosition(frame, rule.position)
    if targetFrame then
      for _, win in ipairs(windows) do
        local title = win:title()
        if titleMatches(title, rule) then
          win:setFrame(targetFrame)
          moved = moved + 1
          break
        end
      end
    end
  end

  hs.notify.new({
    title = "Binding Windows",
    informativeText = string.format(
      "Applied '%s' on %s (%d window%s)",
      layoutName,
      screenName(screen),
      moved,
      moved == 1 and "" or "s"
    )
  }):send()
end

local function debugTarget(layoutName)
  local config = readConfig()
  if not config then
    return
  end

  local chosenLayout = layoutName or config.active_layout or config.default_layout
  local layout = (config.layouts or {})[chosenLayout]
  if not layout then
    hs.notify.new({
      title = "Binding Windows Debug",
      informativeText = "Layout not found: " .. tostring(chosenLayout)
    }):send()
    return
  end

  local mouseScreen = hs.mouse.getCurrentScreen()
  local focusedWindow = hs.window.focusedWindow()
  local focusedScreen = nil
  if focusedWindow then
    focusedScreen = focusedWindow:screen()
  end
  local chosenScreen = targetScreen(layout)

  local msg = string.format(
    "layout=%s screenMode=%s chosen=%s mouse=%s focused=%s",
    tostring(chosenLayout),
    tostring(layout.screen or "focused"),
    screenName(chosenScreen),
    screenName(mouseScreen),
    screenName(focusedScreen)
  )
  hs.notify.new({ title = "Binding Windows Debug", informativeText = msg }):send()
end

local function clearHotkeys()
  for _, handle in ipairs(hotkeyHandles) do
    handle:delete()
  end
  hotkeyHandles = {}
end

local function bindHotkeys()
  clearHotkeys()

  local config = readConfig()
  if not config then
    return
  end

  local bindings = config.slot_bindings or {}
  for _, slot in ipairs(supportedSlots) do
    local layoutName = bindings[slot]
    if layoutName and layoutName ~= "" then
      local handle = hs.hotkey.bind(fixedMods, slot, function()
        applyLayout(layoutName)
      end)
      table.insert(hotkeyHandles, handle)
    end
  end
end

local function setupScreenWatcher()
  if screenWatcher then
    screenWatcher:stop()
  end

  screenWatcher = hs.screen.watcher.new(function()
    local config = readConfig()
    if not config or not config.auto_apply_on_screen_change then
      return
    end

    local delay = tonumber(config.apply_delay_seconds) or 1.0
    hs.timer.doAfter(delay, function()
      applyLayout(nil)
    end)
  end)

  screenWatcher:start()
end

hs.urlevent.bind("binding-windows-apply", function(_, params)
  local name = nil
  if params then
    name = params.name
  end
  applyLayout(name)
end)

hs.urlevent.bind("binding-windows-reload", function()
  bindHotkeys()
  setupScreenWatcher()
  hs.notify.new({ title = "Binding Windows", informativeText = "Reloaded binding-windows config" }):send()
end)

hs.urlevent.bind("binding-windows-debug-target", function(_, params)
  local name = nil
  if params then
    name = params.name
  end
  debugTarget(name)
end)

layoutCursorWindows = applyLayout
M.apply = applyLayout

bindHotkeys()
setupScreenWatcher()

return M
]]

local function is_identifier(str)
  return type(str) == "string" and string.match(str, "^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

local function sort_keys(tbl)
  local keys = {}
  for k in pairs(tbl) do
    table.insert(keys, k)
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local function serialize(value, indent)
  indent = indent or ""
  local next_indent = indent .. "  "
  local t = type(value)

  if t == "nil" then
    return "nil"
  elseif t == "boolean" then
    return value and "true" or "false"
  elseif t == "number" then
    return tostring(value)
  elseif t == "string" then
    return string.format("%q", value)
  elseif t == "table" then
    local is_array = true
    local count = 0
    for k in pairs(value) do
      count = count + 1
      if type(k) ~= "number" then
        is_array = false
        break
      end
    end
    if is_array then
      for i = 1, #value do
        if value[i] == nil then
          is_array = false
          break
        end
      end
    end

    if count == 0 then
      return "{}"
    end

    local lines = {}
    if is_array then
      for i = 1, #value do
        table.insert(lines, next_indent .. serialize(value[i], next_indent) .. ",")
      end
    else
      for _, k in ipairs(sort_keys(value)) do
        local key
        if is_identifier(k) then
          key = tostring(k)
        else
          key = "[" .. serialize(k, next_indent) .. "]"
        end
        table.insert(lines, next_indent .. key .. " = " .. serialize(value[k], next_indent) .. ",")
      end
    end
    return "{\n" .. table.concat(lines, "\n") .. "\n" .. indent .. "}"
  end

  error("Unsupported type in serializer: " .. t)
end

local function json_escape(str)
  return str
    :gsub("\\", "\\\\")
    :gsub("\"", "\\\"")
    :gsub("\b", "\\b")
    :gsub("\f", "\\f")
    :gsub("\n", "\\n")
    :gsub("\r", "\\r")
    :gsub("\t", "\\t")
end

local function to_json(value)
  local t = type(value)
  if t == "nil" then
    return "null"
  elseif t == "boolean" then
    return value and "true" or "false"
  elseif t == "number" then
    return tostring(value)
  elseif t == "string" then
    return "\"" .. json_escape(value) .. "\""
  elseif t == "table" then
    local is_array = true
    local count = 0
    local max_index = 0
    for k in pairs(value) do
      count = count + 1
      if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
        is_array = false
        break
      end
      if k > max_index then
        max_index = k
      end
    end

    if is_array and max_index ~= count then
      is_array = false
    end

    local parts = {}
    if is_array then
      for i = 1, count do
        table.insert(parts, to_json(value[i]))
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end

    for _, k in ipairs(sort_keys(value)) do
      table.insert(parts, to_json(tostring(k)) .. ":" .. to_json(value[k]))
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end

  error("Unsupported type in JSON encoder: " .. t)
end

local function normalize_config(config)
  if type(config.slot_bindings) ~= "table" then
    config.slot_bindings = {}
  end
  for i = 1, 9 do
    local key = tostring(i)
    if type(config.slot_bindings[key]) ~= "string" then
      config.slot_bindings[key] = ""
    end
  end
  return config
end

local function load_config_from_path(path)
  local ok, conf = pcall(dofile, path)
  if not ok or type(conf) ~= "table" then
    io.stderr:write("Invalid Lua config: " .. path .. "\n")
    os.exit(1)
  end
  return normalize_config(conf)
end

local function load_config()
  if file_exists(CONFIG_PATH) then
    return load_config_from_path(CONFIG_PATH)
  end
  if file_exists(LEGACY_CONFIG_PATH) then
    return load_config_from_path(LEGACY_CONFIG_PATH)
  end
  return default_config()
end

local function save_config(config)
  mkdir_p(HAMMERSPOON_DIR)
  normalize_config(config)
  write_file(CONFIG_PATH, "return " .. serialize(config) .. "\n")
end

local function ensure_init_require()
  mkdir_p(HAMMERSPOON_DIR)
  local marker = 'require("binding_windows")'
  local current = read_file(INIT_PATH)
  if not current then
    write_file(INIT_PATH, marker .. "\n")
    return
  end
  if not string.find(current, marker, 1, true) then
    write_file(INIT_PATH, current:gsub("%s*$", "") .. "\n\n" .. marker .. "\n")
  end
end

local function ensure_module(force)
  mkdir_p(HAMMERSPOON_DIR)
  if not force and file_exists(MODULE_PATH) then
    return
  end
  write_file(MODULE_PATH, LUA_MODULE .. "\n")
end

local function require_layout(config, name)
  if type(name) ~= "string" or name == "" then
    io.stderr:write("Layout name is required.\n")
    os.exit(1)
  end
  if type(config.layouts) ~= "table" or type(config.layouts[name]) ~= "table" then
    io.stderr:write("Layout not found: " .. name .. "\n")
    os.exit(1)
  end
end

local function print_help()
  print([[
binding-windows - Lua CLI for window layouts

Usage:
  binding-windows doctor
  binding-windows init [--force]
  binding-windows list [--json]
  binding-windows show <name> [--json]
  binding-windows create <name> [--copy <layout>]
  binding-windows rename <old-name> <new-name>
  binding-windows rule-list <layout>
  binding-windows rule-set <layout> <position> <exact|contains|pattern> <title>
  binding-windows rule-auto <layout> [exact|contains|pattern] <title-1> [title-2] [title-3] [title-4]
  binding-windows rule-set-json <layout> <json-or-@path>
  binding-windows delete <name>
  binding-windows set-default <name>
  binding-windows set-active <name>
  binding-windows bind <1-9> <layout>
  binding-windows unbind <1-9>
  binding-windows export <path>
  binding-windows import <path>
  binding-windows delay <seconds>
  binding-windows auto-apply <true|false>
  binding-windows debug-target [layout]
  binding-windows apply [name]

Hotkeys are fixed to ctrl+alt(option)+cmd+<number>.
]])
end

local function parse_bool(value)
  local v = string.lower(tostring(value))
  if v == "1" or v == "true" or v == "yes" or v == "on" then
    return true
  end
  if v == "0" or v == "false" or v == "no" or v == "off" then
    return false
  end
  io.stderr:write("Invalid boolean: " .. tostring(value) .. "\n")
  os.exit(1)
end

local function parse_slot(value)
  local num = tonumber(value)
  if not num or num < 1 or num > 9 or math.floor(num) ~= num then
    io.stderr:write("Slot must be an integer between 1 and 9.\n")
    os.exit(1)
  end
  return tostring(num)
end

local function parse_position(value)
  local allowed = {
    fullscreen = true,
    left = true,
    right = true,
    top_left = true,
    top_right = true,
    bottom_left = true,
    bottom_right = true,
  }
  if not allowed[value] then
    io.stderr:write("Position must be one of: fullscreen, left, right, top_left, top_right, bottom_left, bottom_right\n")
    os.exit(1)
  end
  return value
end

local function parse_match_mode(value)
  local allowed = {
    exact = true,
    contains = true,
    pattern = true,
  }
  if not allowed[value] then
    io.stderr:write("Match mode must be one of: exact, contains, pattern\n")
    os.exit(1)
  end
  return value
end

local function inferred_positions(count)
  if count == 1 then
    return { "fullscreen" }
  elseif count == 2 then
    return { "left", "right" }
  elseif count == 3 then
    return { "left", "top_right", "bottom_right" }
  elseif count == 4 then
    return { "top_left", "top_right", "bottom_left", "bottom_right" }
  end
  return nil
end

local function json_decode(input)
  local i = 1
  local n = #input

  local function skip_ws()
    while i <= n do
      local c = input:sub(i, i)
      if c == " " or c == "\n" or c == "\r" or c == "\t" then
        i = i + 1
      else
        break
      end
    end
  end

  local parse_value

  local function parse_string()
    i = i + 1
    local out = {}
    while i <= n do
      local c = input:sub(i, i)
      if c == "\"" then
        i = i + 1
        return table.concat(out)
      end
      if c == "\\" then
        local e = input:sub(i + 1, i + 1)
        if e == "\"" or e == "\\" or e == "/" then
          table.insert(out, e)
          i = i + 2
        elseif e == "b" then
          table.insert(out, "\b")
          i = i + 2
        elseif e == "f" then
          table.insert(out, "\f")
          i = i + 2
        elseif e == "n" then
          table.insert(out, "\n")
          i = i + 2
        elseif e == "r" then
          table.insert(out, "\r")
          i = i + 2
        elseif e == "t" then
          table.insert(out, "\t")
          i = i + 2
        elseif e == "u" then
          local hex = input:sub(i + 2, i + 5)
          if #hex ~= 4 or not hex:match("^[0-9a-fA-F]+$") then
            error("Invalid unicode escape in JSON")
          end
          table.insert(out, "?")
          i = i + 6
        else
          error("Invalid escape in JSON string")
        end
      else
        table.insert(out, c)
        i = i + 1
      end
    end
    error("Unterminated JSON string")
  end

  local function parse_number()
    local start_i = i
    local s = input:sub(i)
    local token = s:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*")
    if not token or token == "" then
      error("Invalid JSON number")
    end
    i = start_i + #token
    local num = tonumber(token)
    if num == nil then
      error("Invalid JSON number token")
    end
    return num
  end

  local function parse_array()
    i = i + 1
    skip_ws()
    local arr = {}
    if input:sub(i, i) == "]" then
      i = i + 1
      return arr
    end
    while true do
      table.insert(arr, parse_value())
      skip_ws()
      local c = input:sub(i, i)
      if c == "," then
        i = i + 1
        skip_ws()
      elseif c == "]" then
        i = i + 1
        return arr
      else
        error("Expected ',' or ']' in JSON array")
      end
    end
  end

  local function parse_object()
    i = i + 1
    skip_ws()
    local obj = {}
    if input:sub(i, i) == "}" then
      i = i + 1
      return obj
    end
    while true do
      if input:sub(i, i) ~= "\"" then
        error("Expected string key in JSON object")
      end
      local key = parse_string()
      skip_ws()
      if input:sub(i, i) ~= ":" then
        error("Expected ':' after JSON object key")
      end
      i = i + 1
      skip_ws()
      obj[key] = parse_value()
      skip_ws()
      local c = input:sub(i, i)
      if c == "," then
        i = i + 1
        skip_ws()
      elseif c == "}" then
        i = i + 1
        return obj
      else
        error("Expected ',' or '}' in JSON object")
      end
    end
  end

  parse_value = function()
    skip_ws()
    local c = input:sub(i, i)
    if c == "\"" then
      return parse_string()
    elseif c == "{" then
      return parse_object()
    elseif c == "[" then
      return parse_array()
    elseif c == "-" or c:match("%d") then
      return parse_number()
    elseif input:sub(i, i + 3) == "true" then
      i = i + 4
      return true
    elseif input:sub(i, i + 4) == "false" then
      i = i + 5
      return false
    elseif input:sub(i, i + 3) == "null" then
      i = i + 4
      return nil
    end
    error("Unexpected token in JSON")
  end

  local result = parse_value()
  skip_ws()
  if i <= n then
    error("Trailing content in JSON input")
  end
  return result
end

local function cmd_init(args)
  local force = false
  for _, arg in ipairs(args) do
    if arg == "--force" then
      force = true
    end
  end

  if force or not file_exists(CONFIG_PATH) then
    save_config(default_config())
    print("Wrote " .. CONFIG_PATH)
  else
    save_config(load_config())
    print("Config already exists: " .. CONFIG_PATH)
  end

  ensure_module(force)
  print("Ensured module: " .. MODULE_PATH)
  ensure_init_require()
  print("Ensured require line in: " .. INIT_PATH)

  ping_hammerspoon("reload")
  print("Requested Hammerspoon config reload.")
end

local function cmd_list()
  local config = load_config()
  local layouts = config.layouts or {}
  local names = sort_keys(layouts)
  if #names == 0 then
    print("No layouts defined.")
    return
  end

  local slots_for_layout = {}
  for slot, layout_name in pairs(config.slot_bindings or {}) do
    if layout_name ~= "" then
      if not slots_for_layout[layout_name] then
        slots_for_layout[layout_name] = {}
      end
      table.insert(slots_for_layout[layout_name], slot)
    end
  end

  for _, name in ipairs(names) do
    local marks = {}
    if name == config.default_layout then
      table.insert(marks, "default")
    end
    if name == config.active_layout then
      table.insert(marks, "active")
    end
    if slots_for_layout[name] then
      table.sort(slots_for_layout[name], function(a, b) return tonumber(a) < tonumber(b) end)
      local keys = {}
      for _, slot in ipairs(slots_for_layout[name]) do
        table.insert(keys, table.concat(FIXED_MODS, "+") .. "+" .. slot)
      end
      table.insert(marks, "keys: " .. table.concat(keys, ", "))
    end

    local suffix = ""
    if #marks > 0 then
      suffix = " (" .. table.concat(marks, "; ") .. ")"
    end
    local desc = layouts[name].description or ""
    print("- " .. name .. suffix .. ": " .. desc)
  end
end

local function cmd_show(args)
  local name = args[1]
  if not name then
    io.stderr:write("Usage: binding-windows show <name>\n")
    os.exit(1)
  end
  local config = load_config()
  require_layout(config, name)
  print("return " .. serialize(config.layouts[name]))
end

local function run_check(command)
  local ok, _, code = os.execute(command)
  if ok == true then
    return true
  end
  if type(ok) == "number" then
    return ok == 0
  end
  return code == 0
end

local function has_hammerspoon_app()
  return run_check(
    "test -d \"/Applications/Hammerspoon.app\" " ..
    "|| test -d \"$HOME/Applications/Hammerspoon.app\" " ..
    "|| open -Ra Hammerspoon >/dev/null 2>&1"
  )
end

local function is_hammerspoon_running()
  return run_check([[
[ "$(osascript -e 'application "Hammerspoon" is running' 2>/dev/null)" = "true" ] ||
pgrep -x Hammerspoon >/dev/null 2>&1
]])
end

local function cmd_doctor()
  local checks = {}

  local function push(name, ok, detail)
    table.insert(checks, { name = name, ok = ok, detail = detail })
  end

  push("lua_runtime", run_check("command -v lua >/dev/null 2>&1"), "lua available on PATH")
  push("hammerspoon_installed", has_hammerspoon_app(), "Hammerspoon app exists")
  push("hammerspoon_running", is_hammerspoon_running(), "Hammerspoon process running")
  push("config_file", file_exists(CONFIG_PATH), CONFIG_PATH)
  push("module_file", file_exists(MODULE_PATH), MODULE_PATH)

  local init_ok = false
  if file_exists(INIT_PATH) then
    local init_content = read_file(INIT_PATH) or ""
    init_ok = string.find(init_content, 'require("binding_windows")', 1, true) ~= nil
      or string.find(init_content, 'require("cursor_layout")', 1, true) ~= nil
  end
  push("init_require", init_ok, 'init.lua includes require("binding_windows")')

  local config_parse_ok = false
  if file_exists(CONFIG_PATH) then
    local ok, conf = pcall(dofile, CONFIG_PATH)
    config_parse_ok = ok and type(conf) == "table"
  end
  push("config_parse", config_parse_ok, "binding-windows-layouts.lua is valid Lua table")

  local failed = 0
  for _, check in ipairs(checks) do
    if check.ok then
      print("OK   " .. check.name .. " - " .. check.detail)
    else
      print("FAIL " .. check.name .. " - " .. check.detail)
      failed = failed + 1
    end
  end

  if failed == 0 then
    print("doctor: all checks passed")
    return
  end

  io.stderr:write("doctor: " .. tostring(failed) .. " check(s) failed\n")
  os.exit(1)
end

local function cmd_create(args)
  local name = args[1]
  if not name then
    io.stderr:write("Usage: binding-windows create <name> [--copy <layout>]\n")
    os.exit(1)
  end

  local copy_name = nil
  for i = 2, #args do
    if args[i] == "--copy" then
      copy_name = args[i + 1]
      break
    end
  end

  local config = load_config()
  local layouts = config.layouts or {}
  config.layouts = layouts

  if layouts[name] then
    io.stderr:write("Layout already exists: " .. name .. "\n")
    os.exit(1)
  end

  if copy_name then
    require_layout(config, copy_name)
    layouts[name] = deepcopy(layouts[copy_name])
    layouts[name].description = "Copy of " .. copy_name
  else
    layouts[name] = {
      description = "New 4-quadrant layout",
      screen = "focused",
      rules = {
        { title = name, position = "top_left", match = "exact" },
        { title = name .. "-1", position = "top_right", match = "exact" },
        { title = name .. "-2", position = "bottom_left", match = "exact" },
        { title = name .. "-3", position = "bottom_right", match = "exact" },
      },
    }
  end

  save_config(config)
  print("Created layout: " .. name)
end

local function cmd_rule_list(args)
  local layout_name = args[1]
  if not layout_name then
    io.stderr:write("Usage: binding-windows rule-list <layout>\n")
    os.exit(1)
  end

  local config = load_config()
  require_layout(config, layout_name)
  local rules = config.layouts[layout_name].rules or {}
  if #rules == 0 then
    print("No rules in layout: " .. layout_name)
    return
  end

  for _, rule in ipairs(rules) do
    local pos = rule.position or "?"
    local mode = rule.match or "exact"
    local title = rule.title or ""
    print("- " .. pos .. " [" .. mode .. "]: " .. title)
  end
end

local function cmd_rule_set(args)
  local layout_name = args[1]
  local position = parse_position(args[2] or "")
  local match_mode = parse_match_mode(args[3] or "")
  local title = args[4]
  if not layout_name or not title then
    io.stderr:write("Usage: binding-windows rule-set <layout> <position> <exact|contains|pattern> <title>\n")
    os.exit(1)
  end

  if #args > 4 then
    for i = 5, #args do
      title = title .. " " .. args[i]
    end
  end

  local config = load_config()
  require_layout(config, layout_name)
  local layout = config.layouts[layout_name]
  if type(layout.rules) ~= "table" then
    layout.rules = {}
  end

  local replaced = false
  for _, rule in ipairs(layout.rules) do
    if rule.position == position then
      rule.match = match_mode
      rule.title = title
      replaced = true
      break
    end
  end

  if not replaced then
    table.insert(layout.rules, {
      position = position,
      match = match_mode,
      title = title,
    })
  end

  save_config(config)
  ping_hammerspoon("binding-windows-reload")
  print("Updated rule in " .. layout_name .. ": " .. position .. " [" .. match_mode .. "] -> " .. title)
end

local function cmd_rule_auto(args)
  local layout_name = args[1]
  if not layout_name then
    io.stderr:write("Usage: binding-windows rule-auto <layout> [exact|contains|pattern] <title-1> [title-2] [title-3] [title-4]\n")
    os.exit(1)
  end

  local match_mode = "exact"
  local title_start = 2
  if args[2] == "exact" or args[2] == "contains" or args[2] == "pattern" then
    match_mode = args[2]
    title_start = 3
  end

  local titles = {}
  for i = title_start, #args do
    table.insert(titles, args[i])
  end

  local count = #titles
  local positions = inferred_positions(count)
  if not positions then
    io.stderr:write("rule-auto supports 1 to 4 titles. For advanced layouts use rule-set-json.\n")
    os.exit(1)
  end

  local config = load_config()
  require_layout(config, layout_name)
  local layout = config.layouts[layout_name]
  layout.rules = {}

  for i, title in ipairs(titles) do
    table.insert(layout.rules, {
      position = positions[i],
      match = match_mode,
      title = title,
    })
  end

  save_config(config)
  ping_hammerspoon("binding-windows-reload")

  print("Auto-set " .. tostring(count) .. " rules in " .. layout_name .. " (" .. match_mode .. ")")
  for i, title in ipairs(titles) do
    print("- " .. positions[i] .. " [" .. match_mode .. "]: " .. title)
  end
end

local function normalize_json_rule(raw)
  if type(raw) ~= "table" then
    io.stderr:write("Invalid rule in JSON: each rule must be an object.\n")
    os.exit(1)
  end

  local position = parse_position(tostring(raw.position or ""))
  local match_mode = parse_match_mode(tostring(raw.match or "exact"))
  local title = raw.title
  if type(title) ~= "string" or title == "" then
    io.stderr:write("Invalid rule in JSON: title must be a non-empty string.\n")
    os.exit(1)
  end

  return {
    position = position,
    match = match_mode,
    title = title,
  }
end

local function cmd_rule_set_json(args)
  local layout_name = args[1]
  local payload = args[2]
  if not layout_name or not payload then
    io.stderr:write("Usage: binding-windows rule-set-json <layout> <json-or-@path>\n")
    os.exit(1)
  end

  if payload:sub(1, 1) == "@" then
    local path = payload:sub(2)
    if not file_exists(path) then
      io.stderr:write("JSON file not found: " .. path .. "\n")
      os.exit(1)
    end
    payload = read_file(path) or ""
  end

  local ok, decoded = pcall(json_decode, payload)
  if not ok then
    io.stderr:write("Invalid JSON payload: " .. tostring(decoded) .. "\n")
    os.exit(1)
  end

  local rule_list = decoded
  if type(decoded) == "table" and type(decoded.rules) == "table" then
    rule_list = decoded.rules
  end
  if type(rule_list) ~= "table" then
    io.stderr:write("JSON payload must be an array of rules or an object with a rules array.\n")
    os.exit(1)
  end

  local normalized = {}
  for i = 1, #rule_list do
    table.insert(normalized, normalize_json_rule(rule_list[i]))
  end
  if #normalized == 0 then
    io.stderr:write("At least one rule is required.\n")
    os.exit(1)
  end

  local config = load_config()
  require_layout(config, layout_name)
  config.layouts[layout_name].rules = normalized
  save_config(config)
  ping_hammerspoon("binding-windows-reload")
  print("Updated rules from JSON for layout: " .. layout_name)
end

local function cmd_rename(args)
  local old_name = args[1]
  local new_name = args[2]
  if not old_name or not new_name then
    io.stderr:write("Usage: binding-windows rename <old-name> <new-name>\n")
    os.exit(1)
  end
  if old_name == new_name then
    io.stderr:write("Old and new names are identical.\n")
    os.exit(1)
  end

  local config = load_config()
  require_layout(config, old_name)
  if config.layouts[new_name] then
    io.stderr:write("Layout already exists: " .. new_name .. "\n")
    os.exit(1)
  end

  config.layouts[new_name] = config.layouts[old_name]
  config.layouts[old_name] = nil
  if config.default_layout == old_name then
    config.default_layout = new_name
  end
  if config.active_layout == old_name then
    config.active_layout = new_name
  end
  for slot, layout_name in pairs(config.slot_bindings) do
    if layout_name == old_name then
      config.slot_bindings[slot] = new_name
    end
  end

  save_config(config)
  ping_hammerspoon("binding-windows-reload")
  print("Renamed layout: " .. old_name .. " -> " .. new_name)
end

local function cmd_delete(args)
  local name = args[1]
  if not name then
    io.stderr:write("Usage: binding-windows delete <name>\n")
    os.exit(1)
  end
  local config = load_config()
  require_layout(config, name)

  config.layouts[name] = nil
  if config.default_layout == name then
    config.default_layout = nil
    for layout_name in pairs(config.layouts) do
      config.default_layout = layout_name
      break
    end
  end
  if config.active_layout == name then
    config.active_layout = config.default_layout
  end
  for slot, layout_name in pairs(config.slot_bindings) do
    if layout_name == name then
      config.slot_bindings[slot] = ""
    end
  end

  save_config(config)
  ping_hammerspoon("binding-windows-reload")
  print("Deleted layout: " .. name)
end

local function cmd_set_default(args)
  local name = args[1]
  if not name then
    io.stderr:write("Usage: binding-windows set-default <name>\n")
    os.exit(1)
  end
  local config = load_config()
  require_layout(config, name)
  config.default_layout = name
  save_config(config)
  print("Default layout set: " .. name)
end

local function cmd_set_active(args)
  local name = args[1]
  if not name then
    io.stderr:write("Usage: binding-windows set-active <name>\n")
    os.exit(1)
  end
  local config = load_config()
  require_layout(config, name)
  config.active_layout = name
  save_config(config)
  print("Active layout set: " .. name)
end

local function cmd_bind(args)
  local slot = parse_slot(args[1])
  local name = args[2]
  if not name then
    io.stderr:write("Usage: binding-windows bind <1-9> <layout>\n")
    os.exit(1)
  end
  local config = load_config()
  require_layout(config, name)
  config.slot_bindings[slot] = name
  save_config(config)
  ping_hammerspoon("binding-windows-reload")
  print("Bound " .. table.concat(FIXED_MODS, "+") .. "+" .. slot .. " -> " .. name)
end

local function cmd_unbind(args)
  local slot = parse_slot(args[1])
  local config = load_config()
  config.slot_bindings[slot] = ""
  save_config(config)
  ping_hammerspoon("binding-windows-reload")
  print("Unbound " .. table.concat(FIXED_MODS, "+") .. "+" .. slot)
end

local function cmd_delay(args)
  local seconds = tonumber(args[1])
  if not seconds then
    io.stderr:write("Usage: binding-windows delay <seconds>\n")
    os.exit(1)
  end
  local config = load_config()
  config.apply_delay_seconds = seconds
  save_config(config)
  ping_hammerspoon("binding-windows-reload")
  print("Apply delay set to " .. tostring(seconds) .. "s")
end

local function cmd_auto_apply(args)
  local enabled = parse_bool(args[1])
  local config = load_config()
  config.auto_apply_on_screen_change = enabled
  save_config(config)
  ping_hammerspoon("binding-windows-reload")
  print("Auto apply on screen change set to " .. tostring(enabled))
end

local function cmd_apply(args)
  local config = load_config()
  local name = args[1] or config.active_layout or config.default_layout
  if not name then
    io.stderr:write("No layout provided and no active/default layout set.\n")
    os.exit(1)
  end
  require_layout(config, name)
  config.active_layout = name
  save_config(config)
  ping_hammerspoon("binding-windows-apply", { name = name })
  print("Requested apply for layout: " .. name)
end

local function cmd_debug_target(args)
  local name = args[1]
  ping_hammerspoon("binding-windows-debug-target", { name = name or "" })
  if name and name ~= "" then
    print("Requested debug target for layout: " .. name)
  else
    print("Requested debug target for active/default layout")
  end
end

local function cmd_export(args)
  local target_path = args[1]
  if not target_path then
    io.stderr:write("Usage: binding-windows export <path>\n")
    os.exit(1)
  end
  local config = load_config()
  write_file(target_path, "return " .. serialize(config) .. "\n")
  print("Exported config to: " .. target_path)
end

local function cmd_import(args)
  local source_path = args[1]
  if not source_path then
    io.stderr:write("Usage: binding-windows import <path>\n")
    os.exit(1)
  end
  if not file_exists(source_path) then
    io.stderr:write("Import file not found: " .. source_path .. "\n")
    os.exit(1)
  end

  local imported = load_config_from_path(source_path)
  save_config(imported)
  ping_hammerspoon("binding-windows-reload")
  print("Imported config from: " .. source_path)
end

local function main()
  local args = {}
  for i = 1, #arg do
    table.insert(args, arg[i])
  end

  local command = args[1]
  if not command or command == "-h" or command == "--help" or command == "help" then
    print_help()
    return
  end
  table.remove(args, 1)

  if command == "init" then
    cmd_init(args)
  elseif command == "doctor" then
    cmd_doctor()
  elseif command == "list" then
    if args[1] == "--json" then
      local config = load_config()
      print(to_json(config.layouts or {}))
    else
      cmd_list()
    end
  elseif command == "show" then
    if args[2] == "--json" then
      local config = load_config()
      local name = args[1]
      require_layout(config, name)
      print(to_json(config.layouts[name]))
    else
      cmd_show(args)
    end
  elseif command == "create" then
    cmd_create(args)
  elseif command == "rename" then
    cmd_rename(args)
  elseif command == "rule-list" then
    cmd_rule_list(args)
  elseif command == "rule-set" then
    cmd_rule_set(args)
  elseif command == "rule-auto" then
    cmd_rule_auto(args)
  elseif command == "rule-set-json" then
    cmd_rule_set_json(args)
  elseif command == "delete" then
    cmd_delete(args)
  elseif command == "set-default" then
    cmd_set_default(args)
  elseif command == "set-active" then
    cmd_set_active(args)
  elseif command == "bind" then
    cmd_bind(args)
  elseif command == "unbind" then
    cmd_unbind(args)
  elseif command == "export" then
    cmd_export(args)
  elseif command == "import" then
    cmd_import(args)
  elseif command == "delay" then
    cmd_delay(args)
  elseif command == "auto-apply" then
    cmd_auto_apply(args)
  elseif command == "debug-target" then
    cmd_debug_target(args)
  elseif command == "apply" then
    cmd_apply(args)
  else
    io.stderr:write("Unknown command: " .. tostring(command) .. "\n\n")
    print_help()
    os.exit(1)
  end
end

main()
