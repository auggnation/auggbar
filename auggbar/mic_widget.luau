--!nonstrict
-- Microphone: shows the Framework hardware privacy switch (published by the
-- auggment-privacy-switches system service at /run/auggment/privacy.json) and
-- the PipeWire mute state of the default microphone, which Noctalia's own volume
-- widget cannot see. Click: toggle mute. Right-click: open the Sound panel.
--   mic            = live
--   microphone-off = muted, or the hardware switch is off (red when the switch is off)

local PRIVACY = "/run/auggment/privacy.json"
local hwOn = nil      -- nil = unknown (service not installed)
local camOn = nil
local camInUse = false
local muted = false
local volume = 1.0

local function readPrivacy()
  local raw = noctalia.readFile(PRIVACY)
  local doc = raw and noctalia.json.decode(raw) or nil
  if type(doc) == "table" then
    hwOn = doc.mic_on
    camOn = doc.cam_on
    camInUse = doc.cam_in_use == true
  else
    hwOn = nil
  end
end

local function render()
  local off = muted or hwOn == false
  if hwOn == false then
    barWidget.setGlyph("microphone-off")
    barWidget.setGlyphColor("error")
  elseif muted then
    barWidget.setGlyph("microphone-off")
    barWidget.setGlyphColor("on_surface_variant")
  else
    barWidget.setGlyph("microphone")
    barWidget.setGlyphColor("on_surface")
  end
  barWidget.setText("")
  local rows = {}
  table.insert(rows, { "Microphone", off and "off" or "on" })
  if hwOn == false then
    table.insert(rows, { "Hardware switch", "OFF (privacy engaged)" })
  elseif hwOn == true then
    table.insert(rows, { "Hardware switch", "on" })
  end
  table.insert(rows, { "Software", muted and "muted" or string.format("%d%%", math.floor(volume * 100 + 0.5)) })
  if camOn == false then
    table.insert(rows, { "Camera switch", "OFF" })
  elseif camInUse then
    table.insert(rows, { "Camera", "in use" })
  end
  table.insert(rows, { "Click", "toggle mute" })
  barWidget.setTooltip(rows)
end

local function refresh()
  readPrivacy()
  noctalia.runAsync({ "wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@" }, function(res)
    if res.exitCode == 0 then
      muted = string.find(res.stdout or "", "MUTED", 1, true) ~= nil
      volume = tonumber(string.match(res.stdout or "", "Volume:%s*([%d%.]+)")) or volume
    end
    render()
  end)
end

function update()
  refresh()
  noctalia.setUpdateInterval(1000)
end

function onClick()
  noctalia.runAsync({ "wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle" }, function()
    refresh()
  end)
end

function onRightClick()
  noctalia.runAsync({ "noctalia", "msg", "panel-toggle", "control-center", "audio" })
end

refresh()
noctalia.setUpdateInterval(1000)
