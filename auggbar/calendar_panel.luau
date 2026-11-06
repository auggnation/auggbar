--!nonstrict
-- Calendar panel: month grid, the selected day's events, and calendar setup
-- (iCal / webcal feeds, Google Calendar sign-in). Backend: gcal/gcal.py.
-- Opened by the bar's calendar widget or Super+Ctrl+C.

local SCRIPT = noctalia.pluginDir() .. "/gcal/gcal.py"
local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
local DOW = { "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" }

local today = { y = 2026, m = 1, d = 1 }
local view = { y = 2026, m = 1 }
local sel = { y = 2026, m = 1, d = 1 }
local data = { linked = false, events = {}, errors = {} }
local status = { accounts = {}, feeds = {}, configured = false }
local showSetup = false
local message = ""
local loading = false
local draft = { url = "", id = "", secret = "" }
local render

local CELL = 48
local function pad(n) return string.format("%02d", n) end
local function iso(y, m, d) return string.format("%04d-%02d-%02d", y, m, d) end

local function daysIn(y, m)
  local t = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  if m == 2 and ((y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0) then return 29 end
  return t[m]
end

-- 0 = Sunday (Sakamoto)
local function dow(y, m, d)
  local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
  if m < 3 then y = y - 1 end
  return (y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) + t[m] + d) % 7
end

local function gcal(args, cb, timeout)
  local argv = { "python3", "-I", SCRIPT }
  for _, a in ipairs(args) do table.insert(argv, a) end
  noctalia.runAsync(argv, function(res)
    local doc = res.exitCode == 0 and noctalia.json.decode(res.stdout) or nil
    cb(doc, res)
  end, timeout or 30000)
end

local function loadStatus()
  gcal({ "status" }, function(doc)
    if doc then status = doc end
    render()
  end, 10000)
end

local function loadEvents(force)
  loading = true
  render()
  local args = { "events", "--month", string.format("%04d-%02d", view.y, view.m) }
  if force then table.insert(args, "--force") end
  gcal(args, function(doc, res)
    loading = false
    if doc then
      data = doc
      message = ""
    else
      message = "Calendar backend failed: " .. noctalia.string.trim(res.stderr or "")
    end
    render()
  end)
end

local function shiftMonth(delta)
  local m = view.m + delta
  local y = view.y
  if m < 1 then m = 12; y = y - 1 elseif m > 12 then m = 1; y = y + 1 end
  view.y, view.m = y, m
  loadEvents(false)
end

local function eventsOn(day)
  local out = {}
  for _, e in ipairs(data.events or {}) do
    if e.d0 and e.d1 and e.d0 <= day and day <= e.d1 then table.insert(out, e) end
  end
  return out
end

local function hasEvents(day)
  for _, e in ipairs(data.events or {}) do
    if e.d0 and e.d1 and e.d0 <= day and day <= e.d1 then return true end
  end
  return false
end

local function isLinked()
  return (data.linked == true) or #(status.accounts or {}) > 0 or #(status.feeds or {}) > 0
end

local function grid()
  local rows = {}
  local head = {}
  for _, n in ipairs(DOW) do
    table.insert(head, ui.label({ text = n, width = CELL, flexGrow = 1, textAlign = "center", fontSize = 11, color = "on_surface_variant" }))
  end
  table.insert(rows, ui.row({ gap = 2 }, head))

  local first = dow(view.y, view.m, 1)
  local n = daysIn(view.y, view.m)
  local day = 1 - first
  for _ = 1, 6 do
    if day > n then break end
    local cells = {}
    for _ = 1, 7 do
      if day < 1 or day > n then
        table.insert(cells, ui.label({ text = "", width = CELL, flexGrow = 1, height = 32 }))
      else
        local d = day
        local key = iso(view.y, view.m, d)
        local isSel = sel.y == view.y and sel.m == view.m and sel.d == d
        local isToday = today.y == view.y and today.m == view.m and today.d == d
        table.insert(cells, ui.button({
          text = tostring(d),
          width = CELL,
          flexGrow = 1,
          controlSize = "sm",
          tooltip = isToday and "Today" or nil,
          variant = isSel and "primary" or ((isToday or hasEvents(key)) and "secondary" or "ghost"),
          onClick = function()
            sel = { y = view.y, m = view.m, d = d }
            render()
          end,
        }))
      end
      day = day + 1
    end
    table.insert(rows, ui.row({ gap = 2 }, cells))
  end
  return rows
end

local function eventList()
  local key = iso(sel.y, sel.m, sel.d)
  local list = eventsOn(key)
  local kids = {}
  table.insert(kids, ui.label({
    text = string.format("%s %d, %d", MONTHS[sel.m], sel.d, sel.y),
    fontWeight = "bold",
  }))
  if not isLinked() then
    table.insert(kids, ui.label({ text = "No calendar is linked yet.", color = "on_surface_variant" }))
  elseif loading then
    table.insert(kids, ui.label({ text = "Loading…", color = "on_surface_variant" }))
  elseif #list == 0 then
    table.insert(kids, ui.label({ text = "No events.", color = "on_surface_variant" }))
  else
    local rows = {}
    for _, e in ipairs(list) do
      local when = e.allday and "All day" or ((e.t0 or "") .. " – " .. (e.t1 or ""))
      table.insert(rows, ui.row({ gap = 8, align = "center" }, {
        ui.box({ width = 4, height = 30, radius = 2, fill = "primary" }),
        ui.column({ gap = 0, flexGrow = 1 }, {
          ui.label({ text = e.title or "", maxLines = 2 }),
          ui.label({ text = when .. ((e.calName and e.calName ~= "") and ("  ·  " .. e.calName) or ""), fontSize = 11, color = "on_surface_variant", maxLines = 1 }),
        }),
      }))
    end
    table.insert(kids, ui.scroll({ gap = 8, height = math.min(200, 40 * #list) }, rows))
  end
  return kids
end

local function setup()
  local kids = {}
  table.insert(kids, ui.separator({}))
  table.insert(kids, ui.label({ text = "Calendars", fontWeight = "bold" }))

  for _, a in ipairs(status.accounts or {}) do
    local email = type(a) == "table" and a.email or tostring(a)
    table.insert(kids, ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "brand-google", size = 16 }),
      ui.label({ text = email, flexGrow = 1, maxLines = 1 }),
      ui.button({ text = "Sign out", variant = "ghost", controlSize = "sm", onClick = function()
        gcal({ "logout", "--account", email }, function() loadStatus(); loadEvents(true) end)
      end }),
    }))
  end
  for _, f in ipairs(status.feeds or {}) do
    table.insert(kids, ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "calendar", size = 16 }),
      ui.label({ text = f.name or f.id or "feed", flexGrow = 1, maxLines = 1 }),
      ui.button({ glyph = "trash", variant = "ghost", controlSize = "sm", tooltip = "Remove", onClick = function()
        gcal({ "feed-remove", "--id", f.id }, function() loadStatus(); loadEvents(true) end)
      end }),
    }))
  end

  table.insert(kids, ui.label({ text = "Add an iCal / webcal address (Google: Settings → calendar → Secret address in iCal format)", fontSize = 11, color = "on_surface_variant", maxLines = 3 }))
  table.insert(kids, ui.row({ gap = 8, align = "center" }, {
    ui.input({ key = "feedurl", value = draft.url, placeholder = "https://…/basic.ics", controlSize = "sm", flexGrow = 1,
      onChange = function(v) draft.url = v end,
      onSubmit = function(v) draft.url = v end }),
    ui.button({ text = "Add", variant = "primary", controlSize = "sm", onClick = function()
      if draft.url == "" then return end
      gcal({ "feed-add", "--url", draft.url }, function(doc)
        if doc and doc.ok then
          draft.url = ""; message = ""
          loadStatus(); loadEvents(true)
        else
          message = "Could not add: " .. tostring(doc and doc.error or "backend error")
          render()
        end
      end)
    end }),
  }))

  table.insert(kids, ui.label({ text = "Google sign-in (needs your own Google Cloud 'Desktop app' OAuth client)", fontSize = 11, color = "on_surface_variant", maxLines = 3 }))
  table.insert(kids, ui.input({ key = "gid", value = draft.id, placeholder = "Client ID", controlSize = "sm",
    onChange = function(v) draft.id = v end, onSubmit = function(v) draft.id = v end }))
  table.insert(kids, ui.input({ key = "gsecret", value = draft.secret, placeholder = "Client secret", controlSize = "sm",
    onChange = function(v) draft.secret = v end, onSubmit = function(v) draft.secret = v end }))
  table.insert(kids, ui.row({ gap = 8 }, {
    ui.button({ text = "Save client", controlSize = "sm", onClick = function()
      if draft.id == "" or draft.secret == "" then message = "Enter both the client ID and secret."; render(); return end
      gcal({ "set-client", "--id", draft.id, "--secret", draft.secret }, function(doc)
        message = (doc and doc.ok) and "Client saved." or ("Could not save: " .. tostring(doc and doc.error or "error"))
        draft.id, draft.secret = "", ""
        loadStatus()
      end)
    end }),
    ui.button({ text = "Sign in with Google", variant = "primary", controlSize = "sm", onClick = function()
      message = "Finish signing in in your browser…"
      render()
      gcal({ "login" }, function(doc)
        message = (doc and doc.ok) and "Signed in." or ("Sign-in failed: " .. tostring(doc and doc.error or "timed out"))
        loadStatus(); loadEvents(true)
      end, 310000)
    end }),
  }))
  return kids
end

render = function()
  local kids = {}
  table.insert(kids, ui.row({ gap = 6, align = "center" }, {
    ui.glyph({ name = "calendar", size = 18, color = "primary" }),
    ui.label({ text = MONTHS[view.m] .. " " .. view.y, fontSize = 16, fontWeight = "bold", flexGrow = 1, maxLines = 1 }),
    ui.button({ glyph = "settings", variant = showSetup and "primary" or "ghost", controlSize = "sm", tooltip = "Calendars", onClick = function()
      showSetup = not showSetup
      render()
    end }),
    ui.button({ glyph = "close", variant = "ghost", controlSize = "sm", onClick = function() panel.close() end }),
  }))
  table.insert(kids, ui.row({ gap = 6, align = "center" }, {
    ui.button({ glyph = "chevron-left", variant = "ghost", controlSize = "sm", onClick = function() shiftMonth(-1) end }),
    ui.button({ text = "Today", variant = "ghost", controlSize = "sm", onClick = function()
      view = { y = today.y, m = today.m }
      sel = { y = today.y, m = today.m, d = today.d }
      loadEvents(false)
    end }),
    ui.button({ glyph = "chevron-right", variant = "ghost", controlSize = "sm", onClick = function() shiftMonth(1) end }),
    ui.label({ text = "", flexGrow = 1 }),
    ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Refresh", onClick = function() loadEvents(true) end }),
  }))
  for _, r in ipairs(grid()) do table.insert(kids, r) end
  table.insert(kids, ui.separator({}))
  for _, k in ipairs(eventList()) do table.insert(kids, k) end
  if showSetup or not isLinked() then
    for _, k in ipairs(setup()) do table.insert(kids, k) end
  end
  if message ~= "" then
    table.insert(kids, ui.label({ text = message, fontSize = 12, color = "error", maxLines = 4 }))
  end
  panel.render(ui.column({ gap = 8 }, kids))
end

function onOpen()
  noctalia.runAsync({ "date", "+%Y %m %d" }, function(res)
    local y, m, d = string.match(res.stdout or "", "(%d+)%s+(%d+)%s+(%d+)")
    if y then
      today = { y = tonumber(y), m = tonumber(m), d = tonumber(d) }
      view = { y = today.y, m = today.m }
      sel = { y = today.y, m = today.m, d = today.d }
    end
    loadStatus()
    loadEvents(false)
  end, 3000)
end
