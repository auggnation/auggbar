--!nonstrict
-- Scores service: runs the python backend, caches team logos locally (ui.image
-- only loads local files), rotates through the tiles, and publishes all of it
-- on noctalia.state for the bar widget and the board panel.
--
-- State it publishes:   tiles, index, updated, status ("loading"|"ok"|"error"), error, config
-- State it listens to:  index (set by the widget's scroll), refreshReq (any new value = refetch now)

local SCRIPT = noctalia.pluginDir() .. "/scoreboard/noctalia-json.py"
local logoDir = noctalia.pluginDataDir() .. "/logos"
noctalia.mkdirAll(logoDir)

local tiles = {}
local index = 0
local rotateSeconds = 10
local refreshSeconds = 60
local fetching = false
local lastFetchMs = 0
local lastRotateMs = noctalia.nowMs()
local pendingLogos = {}

local function logoPath(url)
  if url == nil or url == "" then
    return nil
  end
  local name = string.gsub(url, "^https?://", "")
  name = string.gsub(name, "[^%w%.]", "_")
  return logoDir .. "/" .. name
end

local function publish()
  noctalia.state.set("tiles", tiles)
  noctalia.state.set("index", index)
end

-- Attach a local logo path to each side once the file exists; download missing ones.
local function attachLogos()
  local missing = false
  for _, t in ipairs(tiles) do
    for _, side in ipairs({ "away", "home" }) do
      local s = t[side]
      if type(s) == "table" and s.logo then
        local path = logoPath(s.logo)
        if path and noctalia.fileExists(path) then
          s.logo_path = path
        elseif path and not pendingLogos[path] then
          pendingLogos[path] = true
          missing = true
          noctalia.download(s.logo, path, function(ok)
            pendingLogos[path] = nil
            if ok then
              attachLogos()
              publish()
            end
          end)
        end
      end
    end
  end
  return missing
end

local function refresh(force)
  if fetching then
    return
  end
  fetching = true
  if #tiles == 0 then
    noctalia.state.set("status", "loading")
  end
  local argv = { "python3", "-I", SCRIPT }
  if force then
    table.insert(argv, "--force")
  end
  noctalia.runAsync(argv, function(res)
    fetching = false
    lastFetchMs = noctalia.nowMs()
    local doc = nil
    if res.exitCode == 0 then
      doc = noctalia.json.decode(res.stdout)
    end
    if doc == nil then
      noctalia.log("scoreboard fetch failed: " .. tostring(res.stderr))
      noctalia.state.set("status", "error")
      noctalia.state.set("error", noctalia.string.trim(res.stderr or ""))
      return
    end
    tiles = doc.tiles or {}
    local cfg = doc.config or {}
    rotateSeconds = math.max(2, tonumber(cfg.rotate_seconds) or 10)
    refreshSeconds = math.max(15, tonumber(cfg.refresh_seconds) or 60)
    if #tiles == 0 then
      index = 0
    else
      index = index % #tiles
    end
    attachLogos()
    noctalia.state.set("config", cfg)
    noctalia.state.set("updated", doc.updated or "")
    noctalia.state.set("status", "ok")
    publish()
  end, 60000) -- ESPN fetches for several leagues can exceed the default 5 s
end

-- The widget's scroll wheel writes a new index; restart the rotation timer so
-- the game you scrolled to stays up for a full cycle.
noctalia.state.watch("index", function(v)
  v = tonumber(v)
  if v ~= nil and v ~= index then
    index = v
    lastRotateMs = noctalia.nowMs()
  end
end)

noctalia.state.watch("refreshReq", function()
  refresh(true)
end)

noctalia.setUpdateInterval(1000)

function update()
  local now = noctalia.nowMs()
  if now - lastFetchMs >= refreshSeconds * 1000 then
    refresh(false)
  end
  if #tiles > 1 and now - lastRotateMs >= rotateSeconds * 1000 then
    lastRotateMs = now
    index = (index + 1) % #tiles
    noctalia.state.set("index", index)
  end
end

function onResume()
  lastFetchMs = 0
end

function onIpc(event)
  if event == "refresh" then
    refresh(true)
  elseif event == "next" and #tiles > 0 then
    index = (index + 1) % #tiles
    lastRotateMs = noctalia.nowMs()
    noctalia.state.set("index", index)
  elseif event == "prev" and #tiles > 0 then
    index = (index - 1) % #tiles
    lastRotateMs = noctalia.nowMs()
    noctalia.state.set("index", index)
  end
end

refresh(false)
