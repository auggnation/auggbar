--!nonstrict
-- Updater: pending pacman updates via checkupdates (pacman-contrib), which
-- syncs into a private db copy so it needs no root. Click to update in a
-- terminal; right-click to check again now.

local checkMinutes = noctalia.getConfig("check_minutes") or 30
local hideWhenCurrent = noctalia.getConfig("hide_when_current") ~= false
local updateCommand = noctalia.getConfig("update_command") or "sudo pacman -Syu"

local count = 0
local packages = {}
local checking = false
local failed = false
local nextCheckMs = 0
local fastChecks = 0 -- after an update starts, re-check every minute for a while

local function render()
  if checking and count == 0 then
    barWidget.setVisible(not hideWhenCurrent)
    barWidget.setGlyph("refresh")
    barWidget.setText("")
    barWidget.setTooltip("Checking for updates…")
    return
  end
  if count == 0 then
    barWidget.setVisible(not hideWhenCurrent)
    barWidget.setGlyph(failed and "cloud-off" or "circle-check")
    barWidget.setGlyphColor("on_surface")
    barWidget.setText("")
    barWidget.setTooltip(failed and "Update check failed (offline?)" or "System is up to date")
    return
  end
  barWidget.setVisible(true)
  barWidget.setGlyph("package")
  barWidget.setGlyphColor("primary")
  barWidget.setText(tostring(count))
  local rows = { { "Updates", tostring(count) } }
  for i = 1, math.min(#packages, 12) do
    table.insert(rows, { packages[i], "" })
  end
  if #packages > 12 then
    table.insert(rows, { string.format("…and %d more", #packages - 12), "" })
  end
  table.insert(rows, { "Click", "update  ·  right-click: re-check" })
  barWidget.setTooltip(rows)
end

local function check()
  if checking then
    return
  end
  if not noctalia.commandExists("checkupdates") then
    failed = true
    count = 0
    render()
    barWidget.setVisible(true)
    barWidget.setTooltip("Install pacman-contrib for checkupdates")
    return
  end
  checking = true
  render()
  noctalia.runAsync({ "checkupdates" }, function(res)
    checking = false
    -- checkupdates: 0 = updates listed, 2 = none, anything else = error
    if res.exitCode == 0 or res.exitCode == 2 then
      failed = false
      packages = {}
      for line in string.gmatch(res.stdout or "", "[^\n]+") do
        local name, from, to = string.match(line, "^(%S+)%s+(%S+)%s+%->%s+(%S+)")
        if name then
          table.insert(packages, name .. "  " .. from .. " → " .. to)
        end
      end
      count = #packages
    else
      failed = true
      noctalia.log("checkupdates failed: " .. tostring(res.stderr))
    end
    render()
  end, 60000) -- checkupdates syncs a db copy; the default 5 s timeout is too short
end

noctalia.setUpdateInterval(10000)

function update()
  local now = noctalia.nowMs()
  if now >= nextCheckMs then
    if fastChecks > 0 then
      fastChecks = fastChecks - 1
      nextCheckMs = now + 60 * 1000
    else
      nextCheckMs = now + checkMinutes * 60 * 1000
    end
    check()
  end
end

function onClick()
  noctalia.runInTerminal(updateCommand .. "; printf '\\nDone - press Enter to close.'; read _")
  fastChecks = 20
  nextCheckMs = noctalia.nowMs() + 60 * 1000
end

function onRightClick()
  nextCheckMs = 0
  update()
end

function onResume()
  nextCheckMs = noctalia.nowMs() + 30 * 1000
end

render()
