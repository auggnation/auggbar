--!nonstrict
-- Sound panel: default output / input, volume and mute for each, and a volume
-- slider per playing app. Backed by wpctl (PipeWire) through sound/audio.py.
-- Opened by the bar's sound widget or Super+S.

local SCRIPT = noctalia.pluginDir() .. "/sound/audio.py"

local graph = { sinks = {}, sources = {}, streams = {} }
local lastTouch = 0
local render

local function load()
  noctalia.runAsync({ "python3", "-I", SCRIPT }, function(res)
    local doc = res.exitCode == 0 and noctalia.json.decode(res.stdout) or nil
    if doc then graph = doc end
    render()
  end, 8000)
end

local function touch()
  lastTouch = noctalia.nowMs()
end

local function wp(args, then_reload)
  local argv = { "wpctl" }
  for _, a in ipairs(args) do table.insert(argv, a) end
  noctalia.runAsync(argv, function()
    if then_reload then load() end
  end, 5000)
end

local function setVolume(id, pct)
  touch()
  wp({ "set-volume", "-l", "1.0", tostring(id), string.format("%.2f", pct / 100) }, false)
end

local function toggleMute(id)
  touch()
  wp({ "set-mute", tostring(id), "toggle" }, true)
end

local function indexOfDefault(list)
  for i, v in ipairs(list) do
    if v.default then return i - 1 end
  end
  return 0
end

local function volumeRow(item, glyph)
  local pct = math.floor((item.volume or 0) * 100 + 0.5)
  return ui.row({ gap = 8, align = "center" }, {
    ui.button({
      glyph = item.muted and (glyph .. "-off") or glyph,
      variant = item.muted and "primary" or "ghost",
      controlSize = "sm",
      tooltip = item.muted and "Unmute" or "Mute",
      onClick = function() toggleMute(item.id) end,
    }),
    ui.slider({ min = 0, max = 100, step = 1, value = pct, controlSize = "sm", flexGrow = 1,
      onChange = function(v) setVolume(item.id, tonumber(v) or pct) end }),
    ui.label({ text = pct .. "%", width = 40, textAlign = "end", color = item.muted and "on_surface_variant" or "on_surface" }),
  })
end

local function deviceSection(title, list, glyph, micGlyph)
  local kids = {}
  table.insert(kids, ui.label({ text = title, fontSize = 12, color = "on_surface_variant" }))
  if #list == 0 then
    table.insert(kids, ui.label({ text = "None found", color = "on_surface_variant" }))
    return kids
  end
  local names = {}
  for _, d in ipairs(list) do table.insert(names, d.name) end
  if #list > 1 then
    table.insert(kids, ui.select({ options = names, selectedIndex = indexOfDefault(list), controlSize = "sm", onChange = function(v)
      local d = list[(tonumber(v) or 0) + 1]
      if d then touch(); wp({ "set-default", tostring(d.id) }, true) end
    end }))
  else
    table.insert(kids, ui.label({ text = list[1].name, maxLines = 2 }))
  end
  local current = list[indexOfDefault(list) + 1]
  table.insert(kids, volumeRow(current, glyph))
  return kids
end

render = function()
  local kids = {}
  table.insert(kids, ui.row({ gap = 6, align = "center" }, {
    ui.glyph({ name = "volume", size = 18, color = "primary" }),
    ui.label({ text = "Sound", fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
    ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Refresh", onClick = load }),
    ui.button({ glyph = "close", variant = "ghost", controlSize = "sm", onClick = function() panel.close() end }),
  }))

  for _, k in ipairs(deviceSection("Output", graph.sinks or {}, "volume", "volume")) do table.insert(kids, k) end
  table.insert(kids, ui.separator({}))
  for _, k in ipairs(deviceSection("Input", graph.sources or {}, "microphone", "microphone")) do table.insert(kids, k) end

  local streams = graph.streams or {}
  table.insert(kids, ui.separator({}))
  table.insert(kids, ui.label({ text = "Apps", fontSize = 12, color = "on_surface_variant" }))
  if #streams == 0 then
    table.insert(kids, ui.label({ text = "Nothing is playing", color = "on_surface_variant" }))
  else
    local rows = {}
    for _, s in ipairs(streams) do
      table.insert(rows, ui.label({ text = s.name or "Stream", maxLines = 1 }))
      table.insert(rows, volumeRow(s, "volume"))
    end
    table.insert(kids, ui.scroll({ gap = 6, height = math.min(220, 54 * #streams) }, rows))
  end

  table.insert(kids, ui.separator({}))
  table.insert(kids, ui.row({ gap = 8 }, {
    ui.button({ text = "EasyEffects", controlSize = "sm", glyph = "adjustments", onClick = function()
      noctalia.runAsync({ "easyeffects" }, function() end, 2000)
      panel.close()
    end }),
  }))
  panel.render(ui.column({ gap = 10 }, kids))
end

-- Keep levels fresh while open, but never redraw under a slider that is being dragged.
function update()
  if noctalia.nowMs() - lastTouch > 3000 then load() end
end

function onOpen()
  noctalia.setUpdateInterval(3000)
  load()
end
