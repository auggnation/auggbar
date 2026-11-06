--!nonstrict
-- Sound widget: speaker volume + mute for the default output. Click for the
-- Sound panel, right-click to mute, scroll to change the volume.

local volume, muted = 0, false

local function render()
  local pct = math.floor(volume * 100 + 0.5)
  local glyph = "volume"
  if muted or pct == 0 then
    glyph = "volume-off"
  elseif pct < 34 then
    glyph = "volume-3"
  elseif pct < 67 then
    glyph = "volume-2"
  end
  barWidget.setGlyph(glyph)
  barWidget.setGlyphColor(muted and "on_surface_variant" or "on_surface")
  barWidget.setText("")
  barWidget.setTooltip({ { "Output", muted and "muted" or (pct .. "%") }, { "Click", "sound panel" }, { "Right-click", "mute" } })
end

local function refresh()
  noctalia.runAsync({ "wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@" }, function(res)
    if res.exitCode == 0 then
      muted = string.find(res.stdout or "", "MUTED", 1, true) ~= nil
      volume = tonumber(string.match(res.stdout or "", "Volume:%s*([%d%.]+)")) or volume
    end
    render()
  end, 3000)
end

function update()
  refresh()
  noctalia.setUpdateInterval(1500)
end

function onClick()
  noctalia.togglePanel("auggnation/auggbar:soundpanel")
end

function onRightClick()
  noctalia.runAsync({ "wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle" }, function() refresh() end, 3000)
end

function onScrollUp()
  noctalia.runAsync({ "wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", "3%+" }, function() refresh() end, 3000)
end

function onScrollDown()
  noctalia.runAsync({ "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "3%-" }, function() refresh() end, 3000)
end

refresh()
noctalia.setUpdateInterval(1500)
