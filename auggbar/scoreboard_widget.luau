--!nonstrict
-- Scoreboard bar widget: one game at a time, rotated by the scores service.
--   pre-game:  [logo] NEB @ ILL [logo]
--   live/final:[logo] NEB 21:14 ILL [logo]
-- A small dot shows the state (live / today / this week / final).
-- Click: the board.  Scroll: step through games.

local tiles = noctalia.state.get("tiles") or {}
local index = tonumber(noctalia.state.get("index")) or 0
local status = noctalia.state.get("status") or "loading"
local LOGO = 16

local function current()
  if #tiles == 0 then
    return nil
  end
  return tiles[(index % #tiles) + 1]
end

local function sideColor(side)
  if side and side.fav and side.color and side.color ~= "" then
    return side.color
  end
  return nil -- inherit the widget foreground
end

local function logo(side)
  if side and side.logo_path then
    return ui.image({ path = side.logo_path, width = LOGO, height = LOGO, fit = "contain" })
  end
  return nil
end

local function render()
  local t = current()
  local items = {}

  if t == nil then
    local text = status == "error" and "Scores offline" or (status == "loading" and "Scores…" or "Pick teams")
    barWidget.render(ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = "ball-football", size = 14 }),
      ui.label({ text = text }),
    }))
    barWidget.setTooltip("Scoreboard - click to open")
    return
  end

  table.insert(items, ui.box({ width = 7, height = 7, radius = 4, fill = t.color or "primary" }))

  if t.kind == "game" then
    local a, h = t.away or {}, t.home or {}
    local mid = "@"
    if t.state ~= "pre" then
      mid = tostring(a.score or 0) .. ":" .. tostring(h.score or 0)
    end
    local la, lh = logo(a), logo(h)
    if la then table.insert(items, la) end
    table.insert(items, ui.label({ text = a.abbr or "?", fontWeight = "bold", color = sideColor(a) }))
    table.insert(items, ui.label({ text = mid, fontWeight = "bold", color = t.state == "in" and t.color or nil }))
    table.insert(items, ui.label({ text = h.abbr or "?", fontWeight = "bold", color = sideColor(h) }))
    if lh then table.insert(items, lh) end
  else
    table.insert(items, ui.label({ text = t.bar or t.title or "", fontWeight = "bold" }))
  end

  barWidget.render(ui.row({ gap = 5, align = "center" }, items))

  local tip = {
    { t.league_label or "", t.cat_label or "" },
    { t.title or "", t.detail or "" },
  }
  if #tiles > 1 then
    table.insert(tip, { "Game", string.format("%d of %d (scroll to change)", (index % #tiles) + 1, #tiles) })
  end
  barWidget.setTooltip(tip)
end

noctalia.state.watch("tiles", function(v)
  tiles = v or {}
  render()
end)
noctalia.state.watch("index", function(v)
  index = tonumber(v) or 0
  render()
end)
noctalia.state.watch("status", function(v)
  status = v or "loading"
  render()
end)

function onClick()
  noctalia.togglePanel("auggnation/auggbar:board")
end

function onRightClick()
  noctalia.togglePanel("auggnation/auggbar:board")
end

function onScroll(axis, steps, startsGesture)
  if axis ~= "vertical" or not startsGesture or #tiles < 2 then
    return
  end
  index = (index + (steps > 0 and 1 or -1)) % #tiles
  noctalia.state.set("index", index)
  render()
end

render()
