--!nonstrict
-- RunViking: a viking that runs faster the harder the CPU works.
-- Inspired by RunCat for GNOME Shell by Sergei Kolesnikov (win0err),
-- https://github.com/win0err/gnome-runcat - credit for the idea goes there.
-- Click: open the system monitor in a terminal.

local FRAMES = {
  "viking/active-0.png",
  "viking/active-1.png",
  "viking/active-2.png",
  "viking/active-3.png",
  "viking/active-4.png",
}
local IDLE = "viking/idle.png"

local idleThreshold = noctalia.getConfig("idle_threshold") or 0
local displayMode = noctalia.getConfig("display_mode") or "character"
local invert = noctalia.getConfig("invert_speed") == true
local smooth = noctalia.getConfig("smooth_speed") ~= false
local size = noctalia.getConfig("size") or 20
local monitorCommand = noctalia.getConfig("monitor_command") or "btop"

local dir = noctalia.pluginDir()
local cpu = 0
local shown = 0
local frame = 1
local lastSampleMs = 0

local function sample()
  local stats = noctalia.systemStats()
  if stats and stats.cpu and stats.cpu.usagePercent then
    cpu = math.clamp(stats.cpu.usagePercent, 0, 100)
  end
end

local function frameMs()
  local eff = invert and (100 - shown) or shown
  return math.max(90, math.floor(420 - eff * 3.5))
end

local function render()
  local running = shown > idleThreshold
  local kids = {}
  if displayMode ~= "percentage" then
    local img = running and FRAMES[frame] or IDLE
    table.insert(kids, ui.image({ path = dir .. "/" .. img, width = size, height = size, fit = "contain" }))
  end
  if displayMode ~= "character" then
    table.insert(kids, ui.label({ text = string.format("%d%%", math.floor(shown + 0.5)) }))
  end
  barWidget.render(ui.row({ gap = 4, align = "center" }, kids))
end

function update()
  local now = noctalia.nowMs()
  if now - lastSampleMs >= 1000 then
    lastSampleMs = now
    sample()
    barWidget.setTooltip({ { "CPU", string.format("%d%%", math.floor(cpu + 0.5)) }, { "Click", "open " .. monitorCommand } })
  end
  if smooth then
    shown = shown + (cpu - shown) * 0.25
  else
    shown = cpu
  end
  if shown > idleThreshold then
    frame = (frame % #FRAMES) + 1
  end
  render()
  noctalia.setUpdateInterval(frameMs())
end

function onClick()
  noctalia.runInTerminal(monitorCommand)
end

sample()
shown = cpu
noctalia.setUpdateInterval(frameMs())
render()
