--!nonstrict
-- Scoreboard board: every game for your teams, plus a Teams tab to add or
-- remove favourites. Teams are saved to ~/.config/auggment/scoreboard.json,
-- the same file the Quickshell auggbar used, so both stay in sync.

local CONFIG = noctalia.expandPath("~/.config/auggment/scoreboard.json")

local LEAGUES = {
  { "football/nfl", "NFL" },
  { "football/college-football", "NCAA Football" },
  { "basketball/nba", "NBA" },
  { "basketball/wnba", "WNBA" },
  { "basketball/mens-college-basketball", "NCAA Men's Basketball" },
  { "basketball/womens-college-basketball", "NCAA Women's Basketball" },
  { "baseball/mlb", "MLB" },
  { "baseball/college-baseball", "NCAA Baseball" },
  { "hockey/nhl", "NHL" },
  { "hockey/mens-college-hockey", "NCAA Hockey" },
  { "soccer/usa.1", "MLS" },
  { "soccer/usa.nwsl", "NWSL" },
  { "soccer/eng.1", "Premier League" },
  { "soccer/esp.1", "La Liga" },
  { "soccer/ger.1", "Bundesliga" },
  { "soccer/ita.1", "Serie A" },
  { "soccer/fra.1", "Ligue 1" },
  { "soccer/mex.1", "Liga MX" },
  { "soccer/uefa.champions", "Champions League" },
  { "football/cfl", "CFL" },
}

local tab = "games"
local leagueIdx = 0
local abbrDraft = ""
local message = ""

local function leagueLabel(path)
  for _, l in ipairs(LEAGUES) do
    if l[1] == path then
      return l[2]
    end
  end
  return string.upper(string.match(path, "[^/]+$") or path)
end

local function readConfig()
  local raw = noctalia.readFile(CONFIG)
  local cfg = raw and noctalia.json.decode(raw) or nil
  if type(cfg) ~= "table" then
    cfg = { timezone = "America/Chicago", leagues = {}, teams = {}, rotate_seconds = 10, refresh_seconds = 60 }
  end
  cfg.teams = cfg.teams or {}
  cfg.leagues = cfg.leagues or {}
  return cfg
end

local function writeConfig(cfg)
  noctalia.mkdirAll(noctalia.expandPath("~/.config/auggment"))
  local ok, err = noctalia.writeFile(CONFIG, noctalia.json.encode(cfg, true))
  if not ok then
    noctalia.notifyError("Scoreboard", "Could not save teams: " .. tostring(err))
  end
  noctalia.state.set("refreshReq", noctalia.nowMs())
end

local render -- forward

local function sideRow(side, isLive)
  side = side or {}
  local kids = {}
  if side.logo_path then
    table.insert(kids, ui.image({ path = side.logo_path, width = 22, height = 22, fit = "contain" }))
  else
    table.insert(kids, ui.box({ width = 22, height = 22 }))
  end
  table.insert(kids, ui.label({
    text = side.short_name or side.name or side.abbr or "?",
    fontWeight = side.fav and "bold" or "normal",
    color = side.winner and "primary" or "on_surface",
    flexGrow = 1,
    maxLines = 1,
  }))
  if isLive then
    table.insert(kids, ui.label({ text = tostring(side.score or 0), fontSize = 15, fontWeight = "bold" }))
  end
  return ui.row({ gap = 8, align = "center" }, kids)
end

local function gameCard(t, i)
  local showScore = t.kind == "game" and t.state ~= "pre"
  local body = {}
  table.insert(body, ui.row({ gap = 6, align = "center" }, {
    ui.box({ width = 8, height = 8, radius = 4, fill = t.color or "primary" }),
    ui.label({ text = (t.league_label or "") .. "  ·  " .. (t.cat_label or ""), fontSize = 11, color = "on_surface_variant", flexGrow = 1 }),
    ui.label({ text = t.detail or "", fontSize = 11, color = "on_surface_variant" }),
  }))
  if t.kind == "game" then
    table.insert(body, sideRow(t.away, showScore))
    table.insert(body, sideRow(t.home, showScore))
  else
    table.insert(body, ui.label({ text = t.title or t.bar or "", fontWeight = "bold" }))
  end
  return ui.column({
    key = "g" .. i,
    gap = 6,
    padding = 10,
    radius = 10,
    fill = "surface_container",
    tooltip = t.link and "Open on ESPN" or nil,
    onClick = function()
      if t.link and t.link ~= "" then
        noctalia.runAsync({ "xdg-open", t.link })
        panel.close()
      end
    end,
  }, body)
end

local function gamesTab()
  local tiles = noctalia.state.get("tiles") or {}
  local status = noctalia.state.get("status") or "loading"
  if #tiles == 0 then
    local msg = status == "error" and ("Could not load scores.\n" .. tostring(noctalia.state.get("error") or ""))
      or (status == "loading" and "Loading scores…" or "No games in the next week. Add teams in the Teams tab.")
    return { ui.label({ text = msg, color = "on_surface_variant", maxLines = 6 }) }
  end
  local cards = {}
  for i, t in ipairs(tiles) do
    table.insert(cards, gameCard(t, i))
  end
  return { ui.scroll({ gap = 8, flexGrow = 1, height = 470 }, cards) }
end

local function teamsTab()
  local cfg = readConfig()
  local rows = {}
  for i, key in ipairs(cfg.teams) do
    local path, abbr = string.match(key, "^(.-):(.+)$")
    table.insert(rows, ui.row({ key = "t" .. key, gap = 8, align = "center", padding = 6, radius = 8, fill = "surface_container" }, {
      ui.label({ text = abbr or key, fontWeight = "bold", width = 64 }),
      ui.label({ text = leagueLabel(path or ""), color = "on_surface_variant", flexGrow = 1 }),
      ui.button({
        glyph = "trash",
        variant = "ghost",
        controlSize = "sm",
        tooltip = "Remove",
        onClick = function()
          local c = readConfig()
          table.remove(c.teams, i)
          writeConfig(c)
          message = "Removed " .. (abbr or key)
          render()
        end,
      }),
    }))
  end
  if #rows == 0 then
    table.insert(rows, ui.label({ text = "No favourite teams yet.", color = "on_surface_variant" }))
  end

  local names = {}
  for _, l in ipairs(LEAGUES) do
    table.insert(names, l[2])
  end

  local out = {
    ui.scroll({ gap = 6, height = 300 }, rows),
    ui.separator({}),
    ui.label({ text = "Add a team (ESPN abbreviation, e.g. KC, BOS, LAD)", fontSize = 12, color = "on_surface_variant" }),
    ui.row({ gap = 8, align = "center" }, {
      ui.select({ options = names, selectedIndex = leagueIdx, controlSize = "sm", flexGrow = 1, onChange = function(v)
        leagueIdx = tonumber(v) or 0
      end }),
      ui.input({ key = "abbr", value = "", placeholder = "Abbr", controlSize = "sm", width = 90, onChange = function(v)
        abbrDraft = v
      end, onSubmit = function(v)
        abbrDraft = v
        addTeam()
      end }),
      ui.button({ text = "Add", variant = "primary", controlSize = "sm", onClick = function()
        addTeam()
      end }),
    }),
  }
  if message ~= "" then
    table.insert(out, ui.label({ text = message, fontSize = 12, color = "primary" }))
  end
  return out
end

function addTeam()
  local abbr = string.upper(noctalia.string.trim(abbrDraft or ""))
  if abbr == "" then
    message = "Type a team abbreviation first."
    render()
    return
  end
  local path = LEAGUES[leagueIdx + 1][1]
  local key = path .. ":" .. abbr
  local cfg = readConfig()
  for _, k in ipairs(cfg.teams) do
    if k == key then
      message = abbr .. " is already a favourite."
      render()
      return
    end
  end
  table.insert(cfg.teams, key)
  local hasLeague = false
  for _, l in ipairs(cfg.leagues) do
    if l == path then hasLeague = true end
  end
  if not hasLeague then
    table.insert(cfg.leagues, path)
  end
  writeConfig(cfg)
  message = "Added " .. abbr .. " (" .. LEAGUES[leagueIdx + 1][2] .. "). Games show after the next refresh."
  render()
end

render = function()
  local updated = noctalia.state.get("updated") or ""
  local header = ui.row({ gap = 6, align = "center" }, {
    ui.glyph({ name = "trophy", size = 18, color = "primary" }),
    ui.label({ text = "Scoreboard", fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
    ui.label({ text = updated ~= "" and ("Updated " .. updated) or "", fontSize = 11, color = "on_surface_variant" }),
    ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Refresh now", onClick = function()
      noctalia.state.set("refreshReq", noctalia.nowMs())
    end }),
    ui.button({ glyph = "close", variant = "ghost", controlSize = "sm", onClick = function()
      panel.close()
    end }),
  })
  local tabs = ui.row({ gap = 6 }, {
    ui.button({ text = "Games", glyph = "calendar-event", controlSize = "sm", selected = tab == "games",
      variant = tab == "games" and "primary" or "ghost", onClick = function() tab = "games"; render() end }),
    ui.button({ text = "Teams", glyph = "star", controlSize = "sm", selected = tab == "teams",
      variant = tab == "teams" and "primary" or "ghost", onClick = function() tab = "teams"; message = ""; render() end }),
  })
  local children = { header, tabs }
  local body = tab == "games" and gamesTab() or teamsTab()
  for _, c in ipairs(body) do
    table.insert(children, c)
  end
  panel.render(ui.column({ gap = 10 }, children))
end

noctalia.state.watch("tiles", function() render() end)
noctalia.state.watch("status", function() render() end)

function onOpen()
  render()
end
