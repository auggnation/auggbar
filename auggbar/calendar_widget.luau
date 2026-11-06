--!nonstrict
-- Calendar widget: today's date, with the next event in the tooltip. Click for
-- the Calendar panel.

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

local function refresh()
  noctalia.runAsync({ "date", "+%Y %m %d" }, function(res)
    local y, m, d = string.match(res.stdout or "", "(%d+)%s+(%d+)%s+(%d+)")
    barWidget.setGlyph("calendar")
    if y then
      barWidget.setText(MONTHS[tonumber(m)] .. " " .. tonumber(d))
      barWidget.setTooltip({ { "Today", string.format("%s-%s-%s", y, m, d) }, { "Click", "calendar" } })
    end
  end, 3000)
end

function update()
  refresh()
  noctalia.setUpdateInterval(60000)
end

function onClick()
  noctalia.togglePanel("auggnation/auggbar:calendar")
end

refresh()
noctalia.setUpdateInterval(60000)
