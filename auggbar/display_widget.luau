--!nonstrict
-- Display widget: shows the focused output's resolution and refresh rate.
-- Click for the Display panel.

local SCRIPT = noctalia.pluginDir() .. "/display/display.py"

local function refresh()
  noctalia.runAsync({ "python3", "-I", SCRIPT, "state" }, function(res)
    local doc = res.exitCode == 0 and noctalia.json.decode(res.stdout) or nil
    if not doc or #doc.displays == 0 then
      barWidget.setGlyph("device-desktop-off")
      barWidget.setText("")
      barWidget.setTooltip("No displays found (wlr-randr)")
      return
    end
    local d = doc.displays[1]
    barWidget.setGlyph(#doc.displays > 1 and "devices" or "device-desktop")
    barWidget.setText(string.format("%d×%d @%.0f", d.width, d.height, d.hz))
    local rows = {}
    for _, o in ipairs(doc.displays) do
      table.insert(rows, { o.name, string.format("%d×%d @%.0f · %s× · %s", o.width, o.height, o.hz, tostring(o.scale), o.enabled and "on" or "off") })
    end
    barWidget.setTooltip(rows)
  end)
end

function update()
  refresh()
  noctalia.setUpdateInterval(30000)
end

function onClick()
  noctalia.togglePanel("auggnation/auggbar:displaypanel")
end

refresh()
noctalia.setUpdateInterval(30000)
