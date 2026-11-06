--!nonstrict
-- Display panel (port of auggment-display for mangowm): resolution, refresh,
-- scale, rotation, on/off and brightness per output. Changes apply live and
-- revert after 15 s unless you press Keep. Kept layouts are saved to
-- ~/.config/mango/cfg/monitors.conf as monitor_rule lines.

local SCRIPT = noctalia.pluginDir() .. "/display/display.py"
local SCALES = { 1, 1.25, 1.5, 1.75, 2, 2.5, 3 }
local ROT = { "0°", "90°", "180°", "270°" }

local data = { displays = {}, pending = {} }
local sel = 1
local brightness = nil
local message = ""
local deadline = 0
local arrangeIdx = 0
local idle = { off = 11, saver = 0 }

-- idle timeouts (minutes, 0 = never), applied through Noctalia's idle behaviours
local OFF_CHOICES = { 0, 5, 10, 15, 30, 60 }
local SAVER_CHOICES = { 0, 2, 5, 10, 15, 30 }

local render

local function py(args, cb, timeout)
  local argv = { "python3", "-I", SCRIPT }
  for _, a in ipairs(args) do table.insert(argv, a) end
  noctalia.runAsync(argv, function(res)
    if cb then cb(res) end
  end, timeout or 20000)
end

local function current()
  return data.displays[sel]
end

local function load()
  py({ "state" }, function(res)
    local doc = res.exitCode == 0 and noctalia.json.decode(res.stdout) or nil
    if doc then
      data = doc
      if sel > #data.displays then sel = 1 end
    else
      message = "wlr-randr failed: " .. noctalia.string.trim(res.stderr or "")
    end
    render()
  end)
  for _, k in ipairs({ { "screen-off", "off" }, { "screensaver", "saver" } }) do
    noctalia.runAsync({ "noctalia", "msg", "config-get", "idle.behavior." .. k[1] .. ".timeout" }, function(res)
      local secs = tonumber(noctalia.string.trim(res.stdout or ""))
      if secs then idle[k[2]] = math.floor(secs / 60 + 0.5); render() end
    end)
  end
  py({ "brightness", "get" }, function(res)
    brightness = tonumber(noctalia.string.trim(res.stdout or ""))
    render()
  end)
end

local function apply(patch)
  local d = current()
  if not d then return end
  py({ "apply", d.name, noctalia.json.encode(patch) }, function(res)
    local r = res.exitCode == 0 and noctalia.json.decode(res.stdout) or nil
    if r and r.ok then
      message = ""
      deadline = noctalia.nowMs() + (data.revert_seconds or 15) * 1000
      noctalia.setUpdateInterval(1000)
    else
      message = "Could not apply: " .. tostring(r and r.error or res.stderr)
    end
    load()
  end)
end

local function minutesLabel(m)
  return m == 0 and "Never" or (m .. " min")
end

local function setIdle(name, minutes)
  noctalia.runAsync({ "noctalia", "msg", "config-set", "idle.behavior." .. name .. ".timeout", tostring(minutes * 60) }, function() end)
end

local function resolutions(d)
  local seen, out = {}, {}
  for _, m in ipairs(d.modes) do
    local k = m.width .. "x" .. m.height
    if not seen[k] then
      seen[k] = true
      table.insert(out, { w = m.width, h = m.height, label = m.width .. " × " .. m.height })
    end
  end
  table.sort(out, function(a, b) return a.w * a.h > b.w * b.h end)
  return out
end

local function rates(d)
  local out = {}
  for _, m in ipairs(d.modes) do
    if m.width == d.width and m.height == d.height then
      table.insert(out, m.hz)
    end
  end
  table.sort(out, function(a, b) return a > b end)
  return out
end

local function labelRow(text, control)
  return ui.row({ gap = 8, align = "center" }, {
    ui.label({ text = text, color = "on_surface_variant", width = 90 }),
    control,
  })
end

local function indexOf(list, pred)
  for i, v in ipairs(list) do
    if pred(v) then return i - 1 end
  end
  return 0
end

render = function()
  local kids = {}
  table.insert(kids, ui.row({ gap = 6, align = "center" }, {
    ui.glyph({ name = "device-desktop", size = 18, color = "primary" }),
    ui.label({ text = "Display", fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
    ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Rescan", onClick = load }),
    ui.button({ glyph = "close", variant = "ghost", controlSize = "sm", onClick = function() panel.close() end }),
  }))

  local d = current()
  if not d then
    table.insert(kids, ui.label({ text = message ~= "" and message or "Looking for displays…", color = "on_surface_variant", maxLines = 4 }))
    panel.render(ui.column({ gap = 10 }, kids))
    return
  end

  if #data.displays > 1 then
    local names = {}
    for _, o in ipairs(data.displays) do table.insert(names, o.name .. " · " .. o.model) end
    table.insert(kids, ui.select({ options = names, selectedIndex = sel - 1, controlSize = "sm", onChange = function(v)
      sel = (tonumber(v) or 0) + 1
      render()
    end }))
  else
    table.insert(kids, ui.label({ text = d.model .. " (" .. d.name .. ")", color = "on_surface_variant" }))
  end

  if next(data.pending) ~= nil then
    local left = math.max(0, math.ceil((deadline - noctalia.nowMs()) / 1000))
    table.insert(kids, ui.row({ gap = 8, align = "center", padding = 10, radius = 10, fill = "surface_container" }, {
      ui.label({ text = "Keep these settings? Reverting in " .. left .. "s", flexGrow = 1 }),
      ui.button({ text = "Keep", variant = "primary", controlSize = "sm", onClick = function()
        py({ "keep" }, function() noctalia.setUpdateInterval(0); load() end)
      end }),
      ui.button({ text = "Revert", controlSize = "sm", onClick = function()
        py({ "revert" }, function() noctalia.setUpdateInterval(0); load() end)
      end }),
    }))
  end

  if not d.enabled then
    table.insert(kids, ui.button({ text = "Turn on", variant = "primary", onClick = function() apply({ enabled = true }) end }))
  else
    local res = resolutions(d)
    local resNames = {}
    for _, r in ipairs(res) do table.insert(resNames, r.label) end
    table.insert(kids, labelRow("Resolution", ui.select({ options = resNames, flexGrow = 1, controlSize = "sm",
      selectedIndex = indexOf(res, function(r) return r.w == d.width and r.h == d.height end),
      onChange = function(v)
        local r = res[(tonumber(v) or 0) + 1]
        if not r then return end
        -- keep the closest refresh rate for the new resolution
        local best, bestDiff = nil, 1e9
        for _, m in ipairs(d.modes) do
          if m.width == r.w and m.height == r.h and math.abs(m.hz - d.hz) < bestDiff then
            best, bestDiff = m.hz, math.abs(m.hz - d.hz)
          end
        end
        apply({ width = r.w, height = r.h, hz = best })
      end })))

    local hz = rates(d)
    local hzNames = {}
    for _, h in ipairs(hz) do table.insert(hzNames, string.format("%.0f Hz", h)) end
    table.insert(kids, labelRow("Refresh", ui.select({ options = hzNames, flexGrow = 1, controlSize = "sm",
      selectedIndex = indexOf(hz, function(h) return math.abs(h - d.hz) < 0.01 end),
      onChange = function(v)
        local h = hz[(tonumber(v) or 0) + 1]
        if h then apply({ hz = h }) end
      end })))

    local scaleNames = {}
    for _, s in ipairs(SCALES) do table.insert(scaleNames, tostring(s) .. "×") end
    table.insert(kids, labelRow("Scale", ui.select({ options = scaleNames, flexGrow = 1, controlSize = "sm",
      selectedIndex = indexOf(SCALES, function(s) return math.abs(s - d.scale) < 0.01 end),
      onChange = function(v)
        local s = SCALES[(tonumber(v) or 0) + 1]
        if s then apply({ scale = s }) end
      end })))

    table.insert(kids, labelRow("Rotation", ui.select({ options = ROT, flexGrow = 1, controlSize = "sm",
      selectedIndex = d.transform % 4,
      onChange = function(v) apply({ transform = tonumber(v) or 0 }) end })))

    if brightness ~= nil and d.internal then
      table.insert(kids, labelRow("Brightness", ui.row({ gap = 8, align = "center", flexGrow = 1 }, {
        ui.slider({ min = 1, max = 100, step = 1, value = brightness, controlSize = "sm", flexGrow = 1,
          onChange = function(v)
            brightness = tonumber(v) or brightness
            py({ "brightness", "set", tostring(math.floor(brightness)) })
          end }),
        ui.label({ text = math.floor(brightness) .. "%", width = 38, textAlign = "end" }),
      })))
    end

    table.insert(kids, labelRow("VRR", ui.button({ text = d.vrr and "On" or "Off", controlSize = "sm",
      variant = d.vrr and "primary" or "ghost", onClick = function() apply({ vrr = not d.vrr }) end })))

    if #data.displays > 1 then
      local others, otherNames = {}, {}
      for _, o in ipairs(data.displays) do
        if o.name ~= d.name then
          table.insert(others, o)
          table.insert(otherNames, o.name)
        end
      end
      if arrangeIdx >= #others then arrangeIdx = 0 end
      local ref = others[arrangeIdx + 1]
      table.insert(kids, ui.separator({}))
      table.insert(kids, ui.label({ text = "Arrange " .. d.name .. " relative to", fontSize = 12, color = "on_surface_variant" }))
      table.insert(kids, ui.select({ options = otherNames, selectedIndex = arrangeIdx, controlSize = "sm",
        onChange = function(v) arrangeIdx = tonumber(v) or 0 end }))
      local sides = { { "Left of", "left" }, { "Right of", "right" }, { "Above", "above" }, { "Below", "below" } }
      local btns = {}
      for _, sd in ipairs(sides) do
        table.insert(btns, ui.button({ text = sd[1], controlSize = "sm", onClick = function()
          py({ "arrange", d.name, ref.name, sd[2] }, function() deadline = noctalia.nowMs() + (data.revert_seconds or 15) * 1000; noctalia.setUpdateInterval(1000); load() end)
        end }))
      end
      table.insert(kids, ui.row({ gap = 6 }, btns))
    end

    if #data.displays > 1 then
      table.insert(kids, ui.button({ text = "Turn off this display", controlSize = "sm", onClick = function()
        apply({ enabled = false })
      end }))
    end
  end

  -- Power: screen-off and screensaver delays
  table.insert(kids, ui.separator({}))
  local offNames, saverNames = {}, {}
  for _, m in ipairs(OFF_CHOICES) do table.insert(offNames, minutesLabel(m)) end
  for _, m in ipairs(SAVER_CHOICES) do table.insert(saverNames, minutesLabel(m)) end
  table.insert(kids, labelRow("Screen off", ui.select({ options = offNames, flexGrow = 1, controlSize = "sm",
    selectedIndex = indexOf(OFF_CHOICES, function(m) return m == idle.off end),
    onChange = function(v)
      local m = OFF_CHOICES[(tonumber(v) or 0) + 1]
      idle.off = m
      setIdle("screen-off", m)
    end })))
  table.insert(kids, labelRow("Screensaver", ui.select({ options = saverNames, flexGrow = 1, controlSize = "sm",
    selectedIndex = indexOf(SAVER_CHOICES, function(m) return m == idle.saver end),
    onChange = function(v)
      local m = SAVER_CHOICES[(tonumber(v) or 0) + 1]
      idle.saver = m
      setIdle("screensaver", m)
    end })))
  table.insert(kids, ui.button({ text = "Forget saved layout", variant = "ghost", controlSize = "sm", onClick = function()
    py({ "forget" }, function() message = "Saved layout forgotten (applies on next login)."; load() end)
  end }))

  if message ~= "" then
    table.insert(kids, ui.label({ text = message, fontSize = 12, color = "error", maxLines = 4 }))
  end
  panel.render(ui.column({ gap = 10 }, kids))
end

-- ticks once a second while a change is waiting to be kept, to update the countdown
function update()
  if next(data.pending) == nil then
    noctalia.setUpdateInterval(0)
    return
  end
  if noctalia.nowMs() > deadline + 1500 then
    load()
  else
    render()
  end
end

function onOpen()
  load()
end
