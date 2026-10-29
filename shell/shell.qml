import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Bluetooth
import Quickshell.Networking
import "components"
import "widgets"

ShellRoot {
    id: root

    // Shared palette singleton (Theme.qml); widgets/ files read it directly.
    readonly property QtObject theme: Theme

    readonly property string home: Quickshell.env("HOME")
    readonly property string sbBin: root.home + "/.config/quickshell/quickshell-scripts/auggment-scoreboard/auggment-scoreboard"
    readonly property string dispBin: root.home + "/.config/quickshell/quickshell-scripts/auggment-display/auggment-display"
    readonly property string palettePath: root.home + "/.local/state/auggment/palette.toml"

    property bool displayOpen: false
    property bool sbOpen: false
    property bool sbSetOpen: false
    property bool powerOpen: false

    // The launcher plugin (components/LauncherButton.qml). Kept here so the
    // "launcher" IPC target can drive the very same button.
    property var launcherPlugin: null
    function launcherCommand() {
        if (root.launcherPlugin && root.launcherPlugin.command)
            return root.launcherPlugin.command
        return root.home + "/.local/bin/augment-launcher"
    }
    function launcherToggle() {
        root.run("'" + root.launcherCommand() + "'")
    }

    // On-screen display, driven by the hardware volume / brightness / mic keys.
    property bool osdVisible: false
    property string osdMode: "volume"

    // Full scoreboard config + team catalogue, used by the settings window.
    property var sbFull: ({})
    property var sbTeamOptions: []
    property bool sbTeamsLoading: false
    property bool sbTeamsError: false

    readonly property string sbDir: root.home + "/.config/quickshell/quickshell-scripts/auggment-scoreboard"
    readonly property string dispDir: root.home + "/.config/quickshell/quickshell-scripts/auggment-display"

    // League catalogue (mirrors scoreboard_model.py) for the settings window.
    readonly property var sbLeagues: [
        { path: "football/nfl", label: "NFL", group: "Football" },
        { path: "football/college-football", label: "NCAA Football", group: "Football" },
        { path: "football/cfl", label: "CFL", group: "Football" },
        { path: "football/xfl", label: "XFL", group: "Football" },
        { path: "basketball/nba", label: "NBA", group: "Basketball" },
        { path: "basketball/wnba", label: "WNBA", group: "Basketball" },
        { path: "basketball/mens-college-basketball", label: "NCAA Men's Basketball", group: "Basketball" },
        { path: "basketball/womens-college-basketball", label: "NCAA Women's Basketball", group: "Basketball" },
        { path: "basketball/euroleague", label: "EuroLeague", group: "Basketball" },
        { path: "baseball/mlb", label: "MLB", group: "Baseball" },
        { path: "baseball/college-baseball", label: "NCAA Baseball", group: "Baseball" },
        { path: "baseball/milb", label: "MiLB", group: "Baseball" },
        { path: "hockey/nhl", label: "NHL", group: "Hockey" },
        { path: "hockey/mens-college-hockey", label: "NCAA Hockey", group: "Hockey" },
        { path: "soccer/usa.1", label: "MLS", group: "Soccer" },
        { path: "soccer/usa.nwsl", label: "NWSL", group: "Soccer" },
        { path: "soccer/eng.1", label: "Premier League", group: "Soccer" },
        { path: "soccer/esp.1", label: "La Liga", group: "Soccer" },
        { path: "soccer/ger.1", label: "Bundesliga", group: "Soccer" },
        { path: "soccer/ita.1", label: "Serie A", group: "Soccer" },
        { path: "soccer/fra.1", label: "Ligue 1", group: "Soccer" },
        { path: "soccer/mex.1", label: "Liga MX", group: "Soccer" },
        { path: "soccer/uefa.champions", label: "UEFA Champions League", group: "Soccer" },
        { path: "soccer/fifa.world", label: "FIFA World Cup", group: "Soccer" },
        { path: "racing/nascar-cup", label: "NASCAR Cup", group: "Racing" },
        { path: "racing/irl", label: "IndyCar", group: "Racing" },
        { path: "racing/f1", label: "Formula 1", group: "Racing" },
        { path: "golf/pga", label: "PGA Tour", group: "Golf" }
    ]
    readonly property var sbGroups: ["Football", "Basketball", "Baseball", "Hockey", "Soccer", "Racing", "Golf"]
    readonly property var sbColorPresets: ["#22C55E", "#F59E0B", "#60A5FA", "#9CA3AF", "#EF4444", "#F97316", "#A855F7", "#14B8A6", "#EAB308", "#EC4899", "#FFFFFF"]

    function run(cmd) { Quickshell.execDetached(["bash", "-lc", cmd]) }

    Component.onCompleted: {
        root.auggRead()
        root.refreshSystem()
        if (!sbCfgRead.running) sbCfgRead.running = true
    }

    // ------------------------------------------------------------------ theme
    // One payload: colors.toml, =====PALETTE=====, palette.toml,
    // =====SHELL=====, shell.toml. Re-read periodically so the bar follows the
    // wallpaper palette and any theme change.
    Process {
        id: themeProc
        command: ["bash", "-c",
            "cat '" + theme.themeDir + "/colors.toml' 2>/dev/null; " +
            "echo '=====PALETTE====='; " +
            "cat '" + root.palettePath + "' 2>/dev/null; " +
            "echo '=====SHELL====='; " +
            "cat '" + theme.themeDir + "/shell.toml' 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: theme.applyTheme(this.text) }
    }
    Timer {
        interval: 6000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!themeProc.running) themeProc.running = true
    }

    // --------------------------------------------------------------- updates
    // CachyOS update indicator.
    //
    // arch-update is the same tool that backs Plasma's native update icon. It
    // records the icon it wants to show in ~/.local/state/arch-update/tray_icon:
    //   cachy-update-blue                    -> system is up to date
    //   cachy-update_updates-available-blue  -> updates are pending
    // The indicator follows that file and hides itself completely whenever
    // there is nothing to apply.
    property string updateIconName: ""
    property int updateCount: 0
    property bool updatesChecking: false
    readonly property bool updatesPending: root.updateIconName.indexOf("_updates-available") !== -1

    // The CachyOS icons ship in light/dark/blue variants. Pick the one that
    // reads against the current bar background.
    readonly property bool barIsDark:
        (0.2126 * theme.barBackground.r + 0.7152 * theme.barBackground.g + 0.0722 * theme.barBackground.b) < 0.5
    readonly property string updateIcon: {
        if (!root.updateIconName) return ""
        var name = root.updateIconName
        // arch-update appends "-cb" when colourblind mode is on.
        var cb = /-cb$/.test(name)
        if (cb) name = name.slice(0, -3)
        name = name.replace(/-(blue|light|dark)$/, "")
        return name + (root.barIsDark ? "-light" : "-dark") + (cb ? "-cb" : "")
    }
    // The icons live in the hicolor theme, so point straight at the file.
    readonly property string updateIconPath: root.updateIcon
        ? "/usr/share/icons/hicolor/scalable/apps/" + root.updateIcon + ".svg"
        : ""

    // Right-clicking the indicator forces an immediate re-check.
    function forceUpdateCheck() {
        root.updatesChecking = true
        updatesCheckingTimer.restart()
        root.run("systemctl --user start --no-block arch-update.service")
    }

    // Trigger for the state reader below. The watcher only reports that the
    // file changed - its text() may still hold the previous contents - so it
    // is used purely to kick off a fresh read.
    FileView {
        id: updateIconFile
        path: root.home + "/.local/state/arch-update/tray_icon"
        watchChanges: true
        printErrors: false
        onLoaded: updateStateRead.running = true
        onFileChanged: updateStateRead.running = true
    }

    // Reads the state files directly. arch-update replaces
    // last_updates_check with a rename and rewrites tray_icon in place, so
    // reading the files ourselves is the only way to be sure the indicator
    // matches reality.
    Process {
        id: updateStateRead
        command: ["bash", "-c",
            "s=\"$HOME/.local/state/arch-update\"; " +
            "icon=$(tr -d '\\n' < \"$s/tray_icon\" 2>/dev/null); " +
            "n=$(grep -c . \"$s/last_updates_check\" 2>/dev/null | head -n1); " +
            "printf 'icon=%s\\ncount=%s\\n' \"$icon\" \"${n:-0}\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = String(this.text).match(/icon=(.*)\ncount=(\d+)/)
                if (!m) return
                var icon = m[1].trim()
                if (icon !== "") root.updateIconName = icon
                root.updateCount = parseInt(m[2], 10)
            }
        }
    }
    Timer {
        interval: 2 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!updateStateRead.running) updateStateRead.running = true
    }

    // Refresh the recorded update state. arch-update --check downloads a
    // throwaway pacman database, so it is not free: only re-check once the
    // recorded state has gone stale (6h). The daily arch-update.timer is the
    // backstop, and right-clicking the icon forces an immediate check.
    Process {
        id: updateCheck
        command: ["bash", "-c",
            "state=\"$HOME/.local/state/arch-update\"; " +
            "last=$(head -n1 \"$state/last_updates_check_time\" 2>/dev/null); " +
            "now=$(date +%s); " +
            "if [ -z \"$last\" ] || [ $((now - last)) -gt 21600 ]; then " +
            "systemctl --user start --no-block arch-update.service; " +
            "fi"]
    }
    Timer {
        interval: 30 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!updateCheck.running) updateCheck.running = true
    }
    Timer {
        id: updatesCheckingTimer
        interval: 4000
        onTriggered: root.updatesChecking = false
    }

    // ------------------------------------------------------------- scoreboard
    property var sbTiles: []
    property var sbCfg: ({})
    property int sbIndex: 0
    readonly property int sbTotal: root.sbTiles ? root.sbTiles.length : 0
    readonly property var sbDefaultColors: ({ live: "#22C55E", today: "#F59E0B", this_week: "#60A5FA", final: "#9CA3AF" })
    property string sbTeamQuery: ""
    property string sbColorEditKey: ""

    Process {
        id: sbProc
        command: [root.sbBin, "json"]
        stdout: StdioCollector { onStreamFinished: root.loadSb(this.text) }
    }
    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!sbProc.running) sbProc.running = true
    }
    Timer {
        id: sbRotTimer
        interval: root.sbRotateSeconds() * 1000
        running: root.sbTotal > 1
        repeat: true
        onTriggered: root.sbStep(1)
    }

    function loadSb(txt) {
        try {
            var d = JSON.parse(txt)
            root.sbTiles = d.tiles || []
            root.sbCfg = d.config || {}
            root.sbIndex = d.index || 0
        } catch (e) {
            console.log("scoreboard json: " + e)
        }
    }
    function sbStep(d) {
        if (root.sbTotal > 0)
            root.sbIndex = ((root.sbIndex + d) % root.sbTotal + root.sbTotal) % root.sbTotal
        // Restart the rotation so a manual step gets a full interval.
        if (sbRotTimer) sbRotTimer.restart()
    }
    function sbCurrent() {
        if (!root.sbTiles || root.sbTotal === 0) return null
        return root.sbTiles[((root.sbIndex % root.sbTotal) + root.sbTotal) % root.sbTotal]
    }
    function sbCat(t) {
        if (!t) return "this_week"
        if (t.kind === "game")
            return t.state === "in" ? "live" : (t.state === "post" ? "final" : "this_week")
        if (t.kind === "league")
            return (t.live > 0) ? "live" : "this_week"
        return t.state === "in" ? "live" : (t.state === "post" ? "final" : "this_week")
    }
    function sbColor(t) {
        var cat = root.sbCat(t)
        var custom = (root.sbCfg && root.sbCfg.state_colors) || {}
        return custom[cat] || root.sbDefaultColors[cat] || theme.muted
    }
    // A score is only meaningful once the game has actually started.
    function sbStarted(t) {
        if (!t || t.kind !== "game") return false
        return t.state === "in" || t.state === "post"
    }
    function sbHasScore(t) {
        if (!root.sbStarted(t)) return false
        var a = t.away || {}, h = t.home || {}
        function ok(v) { return v !== undefined && v !== null && v !== "" }
        return ok(a.score) && ok(h.score)
    }
    function sbLabel(t) {
        if (!t) return (root.sbCfg && root.sbCfg.has_teams) ? "\u2014" : "Pick teams"
        if (t.kind === "game") {
            var a = t.away || {}
            var h = t.home || {}
            if (root.sbHasScore(t))
                return (a.abbr || "?") + " " + a.score + "\u2013" + h.score + " " + (h.abbr || "?")
            return (a.abbr || "?") + " @ " + (h.abbr || "?")
        }
        if (t.kind === "league") {
            var n = t.games ? t.games.length : 0
            return (t.league_label || "") + " \u00b7 " + (t.live > 0 ? (t.live + " live") : (n + " games"))
        }
        return (t.league_label || "") + " " + (t.detail || "")
    }
    function sbStatus(t) {
        if (!t) return ""
        if (t.kind === "game") {
            if (t.state === "in") return t.detail || "LIVE"
            if (t.state === "post") return "Final"
            return t.start_full || t.start_local || t.detail || ""
        }
        return t.detail || ""
    }

    // ------------------------------------------------ scoreboard settings
    Process {
        id: sbCfgRead
        command: ["bash", "-lc", "cat $HOME/.config/auggment/scoreboard.json 2>/dev/null || echo '{}'"]
        stdout: StdioCollector { onStreamFinished: root.loadSbFull(this.text) }
    }
    Process {
        id: sbTeamsRead
        command: ["bash", "-lc", root.sbTeamsCmd()]
        stdout: StdioCollector { onStreamFinished: root.loadTeams(this.text) }
    }
    Process {
        id: sbWrite
        // The JSON is handed over as an argument (not via a stdin pipe) so a
        // write never depends on the pipe being flushed/closed first.
        command: ["python3", root.sbDir + "/scoreboard-write.py", "--data", "{}"]
        stdout: StdioCollector { onStreamFinished: root.afterSbWrite() }
    }

    function loadSbFull(txt) {
        try { root.sbFull = JSON.parse(txt) } catch (e) { root.sbFull = ({}) }
    }
    function sbTeamsCmd() {
        var leagues = (root.sbFull && root.sbFull.leagues) ? root.sbFull.leagues : []
        var args = ""
        for (var i = 0; i < leagues.length; i++) args += "'" + leagues[i] + "' "
        return "python3 '" + root.sbDir + "/list-all-teams.py' " + args + "2>/dev/null"
    }
    function loadTeams(txt) {
        root.sbTeamsLoading = false
        try {
            var a = JSON.parse(txt)
            if (a && a.length) { root.sbTeamOptions = a; root.sbTeamsError = false }
            else { root.sbTeamOptions = []; root.sbTeamsError = true }
        } catch (e) { root.sbTeamOptions = []; root.sbTeamsError = true }
    }
    function openSbSet() {
        root.sbSetOpen = true
        root.sbOpen = false
        root.displayOpen = false
        sbCfgRead.running = true
        root.sbTeamsLoading = true
        root.sbTeamsError = false
        sbTeamsRead.running = true
    }
    function saveSb(patch) {
        var cfg = ({})
        for (var k in root.sbFull) cfg[k] = root.sbFull[k]
        for (var k2 in patch) cfg[k2] = patch[k2]
        root.sbFull = cfg
        sbWrite.command = ["python3", root.sbDir + "/scoreboard-write.py", "--data", JSON.stringify(cfg)]
        sbWrite.running = true
        if (!sbProc.running) sbProc.running = true
    }
    function afterSbWrite() { if (!sbProc.running) sbProc.running = true }
    function cfgVal(key, dflt) {
        if (root.sbFull && root.sbFull[key] !== undefined && root.sbFull[key] !== null) return root.sbFull[key]
        return dflt
    }
    function sbLeagueOn(path) {
        var ls = (root.sbFull && root.sbFull.leagues) ? root.sbFull.leagues : []
        return ls.indexOf(path) >= 0
    }
    function sbToggleLeague(path) {
        var ls = (root.sbFull && root.sbFull.leagues) ? root.sbFull.leagues.slice() : []
        var i = ls.indexOf(path)
        if (i >= 0) ls.splice(i, 1); else ls.push(path)
        var ordered = []
        for (var j = 0; j < root.sbLeagues.length; j++)
            if (ls.indexOf(root.sbLeagues[j].path) >= 0) ordered.push(root.sbLeagues[j].path)
        var teams = (root.sbFull && root.sbFull.teams) ? root.sbFull.teams.slice() : []
        teams = teams.filter(function (t) { return ordered.indexOf(String(t).split(":")[0]) >= 0 })
        root.saveSb({ leagues: ordered, teams: teams })
        root.sbTeamsLoading = true
        sbTeamsRead.running = true
    }
    function sbLeaguesIn(group) {
        var out = []
        for (var i = 0; i < root.sbLeagues.length; i++)
            if (root.sbLeagues[i].group === group) out.push(root.sbLeagues[i])
        return out
    }
    function sbFavCount() { return (root.sbFull && root.sbFull.teams) ? root.sbFull.teams.length : 0 }
    function sbFavValues() { return (root.sbFull && root.sbFull.teams) ? root.sbFull.teams : [] }
    function sbStateColor(key) {
        var sc = (root.sbFull && root.sbFull.state_colors) ? root.sbFull.state_colors : ({})
        return sc[key] || root.sbDefaultColors[key] || theme.muted
    }
    function sbSetStateColor(key, value) {
        var sc = ({})
        var cur = (root.sbFull && root.sbFull.state_colors) ? root.sbFull.state_colors : ({})
        for (var k in cur) sc[k] = cur[k]
        if (value === "") delete sc[key]; else sc[key] = value
        root.saveSb({ state_colors: sc })
    }
    function sbLabelShort(value) {
        var parts = String(value).split(":")
        return parts.length > 1 ? parts[1] : String(value)
    }
    function sbRotateSeconds() {
        var v = parseInt(root.cfgVal("rotate_seconds", 6))
        if (isNaN(v) || v < 2) v = 6
        return v
    }
    function sbShowBarLogos() { return !!root.cfgVal("bar_logos", true) }
    function sbTeamKey(t, side) {
        if (!t || !t[side] || !t[side].abbr) return ""
        return (t.league_path || "") + ":" + t[side].abbr
    }
    function sbTeamColor(value, fallback) {
        var tc = (root.sbFull && root.sbFull.team_colors) ? root.sbFull.team_colors : ({})
        if (value && tc[value]) return tc[value]
        return fallback || theme.accent
    }
    // The team's own ESPN colour, looked up from the current tiles.
    function sbTeamRealColor(value) {
        var parts = String(value).split(":")
        var lp = parts[0], ab = parts[1]
        for (var i = 0; i < root.sbTiles.length; i++) {
            var t = root.sbTiles[i]
            if (!t || t.kind !== "game" || (t.league_path || "") !== lp) continue
            var sides = [t.away, t.home]
            for (var j = 0; j < sides.length; j++)
                if (sides[j] && sides[j].abbr === ab && sides[j].color) return sides[j].color
        }
        return theme.textMuted
    }
    function sbRemoveTeam(value) {
        var ts = (root.sbFull && root.sbFull.teams) ? root.sbFull.teams.slice() : []
        var i = ts.indexOf(value)
        if (i >= 0) ts.splice(i, 1)
        root.saveSb({ teams: ts })
    }
    function sbFavTeams() {
        var ts = (root.sbFull && root.sbFull.teams) ? root.sbFull.teams : []
        var out = []
        for (var i = 0; i < ts.length; i++)
            out.push({ value: ts[i], label: root.sbLabelShort(ts[i]), league: root.sbLeagueLabelFor(ts[i]) })
        return out
    }
    function sbLeagueLabelFor(value) {
        var lp = String(value).split(":")[0]
        for (var i = 0; i < root.sbLeagues.length; i++)
            if (root.sbLeagues[i].path === lp) return root.sbLeagues[i].label
        return lp
    }
    // Persist the selected favourites, dropping look-ahead overrides for any
    // team that was removed (mirrors the reference panel's removeTeam()).
    function sbSetTeams(v) {
        var overrides = {}
        var existing = (root.sbFull && root.sbFull.days_ahead_teams) ? root.sbFull.days_ahead_teams : {}
        for (var k in existing) if (v.indexOf(k) >= 0) overrides[k] = existing[k]
        root.saveSb({ teams: v, days_ahead_teams: overrides })
    }
    function sbTeamAhead(key) {
        var o = (root.sbFull && root.sbFull.days_ahead_teams) ? root.sbFull.days_ahead_teams : ({})
        var v = o[key]
        if (v === undefined || v === null || v === "") return root.cfgVal("days_ahead", 7)
        return v
    }
    function sbSetTeamAhead(key, value) {
        var o = ({})
        var cur = (root.sbFull && root.sbFull.days_ahead_teams) ? root.sbFull.days_ahead_teams : ({})
        for (var k in cur) o[k] = cur[k]
        o[key] = value
        root.saveSb({ days_ahead_teams: o })
    }
    function sbNormalizeHex(t) {
        var s = String(t || "").trim()
        if (s === "") return ""
        if (s.charAt(0) !== "#") s = "#" + s
        return /^#[0-9a-fA-F]{6}$/.test(s) ? s.toUpperCase() : null
    }
    function sbSetColorMap(configKey, mapKey, text) {
        var n = root.sbNormalizeHex(text)
        if (n === null) return
        var colors = ({})
        var existing = (root.sbFull && root.sbFull[configKey]) ? root.sbFull[configKey] : ({})
        for (var k in existing) colors[k] = existing[k]
        if (n === "") delete colors[mapKey]
        else colors[mapKey] = n
        var patch = ({})
        patch[configKey] = colors
        root.saveSb(patch)
    }
    function sbFmtTime(s) {
        s = parseInt(s)
        if (isNaN(s)) return "\u2014"
        if (s >= 3600) return (s / 3600) + "h"
        if (s >= 60) return (s / 60) + "m"
        return s + "s"
    }
    function numberOpts(a, b) {
        var o = []
        for (var i = a; i <= b; i++) o.push({ value: String(i), label: String(i) })
        return o
    }
    function listOpts(arr, suffix) {
        var o = []
        for (var i = 0; i < arr.length; i++) o.push({ value: String(arr[i]), label: String(arr[i]) + (suffix || "") })
        return o
    }
    function sbColorRows() {
        return [{ k: "live", label: "Live" }, { k: "today", label: "Today" },
                { k: "this_week", label: "This week" }, { k: "final", label: "Final" }]
    }

    // ------------------------------------------------------- system telemetry
    // NetworkManager/pipewire state is polled rather than read once, so the bar
    // stays correct when the daemons come up after the shell does.
    property bool netConnected: false
    property real netDown: 0
    property real netUp: 0
    property string netIface: ""
    property real sinkVolume: 0
    property bool sinkMuted: false
    property bool micMuted: false
    property bool micPresent: true
    property bool micAlive: true
    // Framework hardware mic switch (read from the EC `mic_sw` GPIO).
    property bool micHwOn: true
    property bool micHwKnown: false
    property bool btOn: false
    property int brightness: 60

    function refreshSystem() {
        // connectivity tracks the real state even if the device list is empty.
        var c = Networking.connectivity
        root.netConnected = (c >= 3)
        if (!sinkProc.running) sinkProc.running = true
        if (!micProc.running) micProc.running = true
        root.btOn = Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.enabled : false
    }
    function parseSink(t) {
        var m = String(t).match(/Volume:\s*([0-9.]+)/)
        if (m) root.sinkVolume = parseFloat(m[1])
        root.sinkMuted = /MUTED/i.test(String(t))
    }
    function parseMic(t) {
        try {
            var d = JSON.parse(String(t))
            root.micPresent = !!d.present
            root.micMuted = !!d.muted
            if (d.hw_on === true || d.hw_on === false) { root.micHwOn = d.hw_on; root.micHwKnown = true }
        } catch (e) {
            root.micMuted = /MUTED/i.test(String(t))
        }
    }

    Process {
        id: sinkProc
        command: ["bash", "-lc", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.parseSink(this.text) }
    }
    Process {
        id: micProc
        command: ["bash", "-lc", root.home + "/.local/bin/auggment-mic status 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.parseMic(this.text) }
    }
    Process {
        id: micProbeProc
        command: ["bash", "-lc", root.home + "/.local/bin/auggment-mic probe 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var v = JSON.parse(String(this.text)).alive
                    if (v === true || v === false) root.micAlive = v
                } catch (e) { /* keep last known state */ }
            }
        }
    }
    Timer {
        id: micProbeTimer
        interval: 8000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!micProbeProc.running) micProbeProc.running = true
    }
    Timer { id: volRefresh; interval: 180; repeat: false; onTriggered: root.refreshSystem() }
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        // readBrightness() too: the bar's Display button shows the current
        // brightness as its label, so it has to stay fresh without waiting for
        // the Display panel to be opened.
        onTriggered: { root.refreshSystem(); root.readBrightness() }
    }

    function netGlyph() { return root.netConnected ? "\uf1eb" : "\uf05e" }
    function volGlyph() {
        if (root.sinkMuted || root.sinkVolume <= 0.001) return "\uf026"
        if (root.sinkVolume < 0.34) return "\uf027"
        if (root.sinkVolume < 0.67) return "\uf028"
        return "\uf028"
    }
    function volPct() { return Math.round(root.sinkVolume * 100) }

    // ---- on-screen display (volume / brightness / microphone) -------------
    // The hardware keys are bound to the bar's IPC (see hyprland.conf), so the
    // OSD, the real change and the meter all stay in lock-step. Values are
    // nudged locally for instant feedback, then confirmed by a poll.
    Timer { id: osdHide; interval: 1600; repeat: false; onTriggered: root.osdVisible = false }
    Timer { id: osdSync; interval: 90; repeat: false; onTriggered: root.osdSyncNow() }
    function osdSyncNow() { root.refreshSystem(); root.readBrightness() }
    function showOsd(mode) {
        root.osdMode = mode
        root.osdVisible = true
        osdHide.restart()
        osdSync.restart()
    }
    function osdGlyph() {
        if (root.osdMode === "brightness") return "\uf185"
        if (root.osdMode === "mic") return root.micMuted ? "\uf131" : "\uf130"
        return root.volGlyph()
    }
    function osdTitle() {
        if (root.osdMode === "brightness") return "BRIGHTNESS"
        // The mic key mutes/unmutes the internal DMIC. When the hardware privacy
        // switch is engaged the mute is moot, so surface that beside the label.
        if (root.osdMode === "mic")
            return (root.micHwKnown && !root.micHwOn) ? "MICROPHONE (HW OFF)" : "MICROPHONE"
        return "VOLUME"
    }
    function osdFill() {
        if (root.osdMode === "brightness") return Math.max(0, Math.min(1, root.brightness / 100))
        if (root.osdMode === "mic") return root.micMuted ? 0 : 1
        return Math.max(0, Math.min(1, root.sinkVolume))
    }
    function osdText() {
        if (root.osdMode === "brightness") return root.brightness + "%"
        if (root.osdMode === "mic") {
            if (!root.micPresent) return "UNAVAILABLE"
            return root.micMuted ? "MUTED" : "ON"
        }
        return root.sinkMuted ? "MUTED" : (root.volPct() + "%")
    }
    function osdAlarm() {
        if (root.osdMode === "brightness") return root.brightness <= 2
        if (root.osdMode === "mic") return root.micMuted
        return root.sinkMuted
    }

    function volumeUp() {
        // Raising the volume always clears mute (the usual desktop behaviour).
        root.run("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ && wpctl set-mute @DEFAULT_AUDIO_SINK@ 0")
        root.sinkMuted = false
        root.sinkVolume = Math.min(1.5, root.sinkVolume + 0.05)
        root.showOsd("volume")
    }
    function volumeDown() {
        root.run("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")
        root.sinkVolume = Math.max(0, root.sinkVolume - 0.05)
        root.showOsd("volume")
    }
    function volumeMute() {
        root.run("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
        root.sinkMuted = !root.sinkMuted
        root.showOsd("volume")
    }
    function brightnessStep(delta) {
        // brightnessctl wants a trailing sign ("5%-"), not a leading one ("-5%").
        var arg = delta > 0 ? ("+" + delta + "%") : (Math.abs(delta) + "%-")
        root.run("brightnessctl set " + arg)
        root.brightness = Math.max(1, Math.min(100, root.brightness + delta))
        root.showOsd("brightness")
    }
    function brightnessAbs(pct) {
        var v = Math.max(1, Math.min(100, Math.round(pct)))
        root.run("brightnessctl set " + v + "%")
        root.brightness = v
        root.showOsd("brightness")
    }
    function micToggle() {
        root.run(root.home + "/.local/bin/auggment-mic toggle")
        root.micMuted = !root.micMuted
        root.showOsd("mic")
    }
    // The hardware switch is authoritative. When it is off the mic cannot be
    // enabled from software, and a capture probe cannot see it at all (the
    // switch swaps the microphone data line for a silent dummy). Only fall back
    // to the probe when the EC GPIO is unreadable.
    function micOn() {
        if (!root.micPresent || root.micMuted) return false
        if (root.micHwKnown) return root.micHwOn
        return root.micAlive
    }
    function micGlyph() { return root.micOn() ? "\uf130" : "\uf131" }

    // ---- network throughput (default-route interface, wired or wireless) ----
    Process {
        id: netSpeedProc
        command: ["bash", "-lc", root.home + "/.local/bin/auggment-netspeed 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.parseNetSpeed(this.text) }
    }
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!netSpeedProc.running) netSpeedProc.running = true
    }
    function parseNetSpeed(t) {
        var p = String(t).trim().split(/\s+/)
        if (p.length >= 3) {
            root.netDown = parseFloat(p[0]) || 0
            root.netUp = parseFloat(p[1]) || 0
            root.netIface = p[2]
        }
    }
    // Compact rate: at most 4 characters ("999B", "9.5K", "12K", "1.2M").
    // One decimal below 10, whole numbers above; a value that would need a
    // 5th character moves up a unit (1000B -> "1.0K").
    function fmtBps(v) {
        if (!v || v <= 0) return "0B"
        var units = ["B", "K", "M", "G"], i = 0
        while (i < units.length - 1 && v >= 999.5) { v /= 1024; i++ }
        if (i > 0 && v < 9.95) return v.toFixed(1) + units[i]
        return Math.round(v) + units[i]
    }
    // The network readout must never resize the bar, so both rates are
    // padded to a fixed-width field (the bar font is monospaced, so the
    // number of characters is the width).
    readonly property int netSpeedFieldWidth: 4
    function fmtBpsFixed(v) {
        var s = root.fmtBps(v)
        while (s.length < root.netSpeedFieldWidth) s = " " + s
        return s
    }
    function netSpeedText() {
        if (!root.netIface || root.netIface === "-") return ""
        return "\uf063" + root.fmtBpsFixed(root.netDown) + " \uf062" + root.fmtBpsFixed(root.netUp)
    }
    // Widest possible readout, used to give the bar item a fixed width.
    function netSpeedSample() {
        return "\uf063" + root.fmtBpsFixed(0) + " \uf062" + root.fmtBpsFixed(0)
    }
    FontMetrics {
        id: netSpdMetrics
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSize - 3
    }
    function btGlyph() { return root.btOn ? "\uf293" : "\uf294" }
    function btConnectedCount() {
        var a = Bluetooth.defaultAdapter
        if (!a || !a.devices) return 0
        var ds = a.devices.values || []
        var n = 0
        for (var i = 0; i < ds.length; i++) if (ds[i] && ds[i].connected) n++
        return n
    }

    // ------------------------------------------------------- wifi + sound
    property bool netOpen: false
    property bool sndOpen: false
    property int netRevision: 0
    property var audioState: ({ sinks: [], sources: [], streams: [], default_sink: null, default_source: null })
    property var wifiTarget: null
    property string wifiPsk: ""
    property string eeCurrent: ""
    property var eePresets: []
    property bool eeOpen: false

    function closePanels() {
        root.displayOpen = false
        root.sbOpen = false
        root.sbSetOpen = false
        root.netOpen = false
        root.sndOpen = false
        root.powerOpen = false
        root.wxOpen = false
        root.wxSetOpen = false
        root.btOpen = false
        root.btSettings = false
        root.calOpen = false
        root.calAuthOpen = false
        root.barSetOpen = false
        root.pluginSetOpen = false
    }
    function openNet() {
        var was = root.netOpen
        root.closePanels()
        root.netOpen = !was
        if (root.netOpen) { root.netRevision++; root.wifiNmRefreshNow() }
    }
    function openSnd() {
        var was = root.sndOpen
        root.closePanels()
        root.sndOpen = !was
        if (root.sndOpen) { root.refreshAudio(); root.refreshEe() }
    }

    // ------------------------------------------------------------- power
    function togglePower() {
        var was = root.powerOpen
        root.closePanels()
        root.powerOpen = !was
    }
    function powerAction(a) {
        root.powerOpen = false
        if (a === "reboot") root.run("systemctl reboot")
        else if (a === "poweroff") root.run("systemctl poweroff")
        else if (a === "suspend") root.run("systemctl suspend")
        else if (a === "restart-bar") root.run("'" + root.home + "/.local/bin/auggment-bar-restart' >/dev/null 2>&1 &")
    }

    // ---- audio (wpctl, parsed by auggment-audio) ----
    Process {
        id: audioProc
        command: [root.home + "/.local/bin/auggment-audio"]
        stdout: StdioCollector { onStreamFinished: root.loadAudio(this.text) }
    }
    Timer { id: audioRefresh; interval: 200; repeat: false; onTriggered: root.refreshAudio() }
    Timer {
        interval: 2500
        running: root.sndOpen
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshAudio()
    }
    Timer {
        interval: 4000
        running: root.netOpen
        repeat: true
        triggeredOnStart: true
        onTriggered: { root.netRevision++; root.wifiNmRefreshNow() }
    }

    function refreshAudio() { if (!audioProc.running) audioProc.running = true }
    function loadAudio(txt) {
        try { root.audioState = JSON.parse(txt) } catch (e) { console.log("audio: " + e) }
    }
    function audioSinks() { return root.audioState.sinks || [] }
    function audioSources() { return root.audioState.sources || [] }
    function audioStreams() { return root.audioState.streams || [] }
    function audioPct(v) { return Math.round(Math.max(0, Math.min(1, v || 0)) * 100) }
    function audioSetVolume(id, pct) {
        root.run("wpctl set-volume " + id + " " + Math.max(0, Math.min(150, Math.round(pct))) + "%")
        audioRefresh.restart(); volRefresh.restart()
    }
    function audioMute(id) {
        root.run("wpctl set-mute " + id + " toggle")
        audioRefresh.restart(); volRefresh.restart()
    }
    function audioSetDefault(id) {
        root.run("wpctl set-default " + id)
        audioRefresh.restart(); volRefresh.restart()
    }

    // ---- EasyEffects presets (output profile) ----
    Process {
        id: eeProc
        command: [root.home + "/.local/bin/auggment-easyeffects", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(String(this.text))
                    root.eeCurrent = d.current || ""
                    root.eePresets = d.presets || []
                } catch (e) { console.log("easyeffects: " + e) }
            }
        }
    }
    Timer { id: eeReload; interval: 1500; repeat: false; onTriggered: if (!eeProc.running) eeProc.running = true }
    function refreshEe() { if (!eeProc.running) eeProc.running = true }
    // Loads a preset without going through a shell string (preset names are
    // passed as argv, so no quoting/injection concerns).
    Process { id: eeLoadProc }
    function eeLoad(name) {
        if (eeLoadProc.running) return
        eeLoadProc.command = [root.home + "/.local/bin/auggment-easyeffects", "load", name]
        eeLoadProc.running = true
        eeReload.restart()
    }

    // ---- wifi (Quickshell Networking, NetworkManager backend) ----
    // The NetworkManager backend builds its device list asynchronously. When the
    // bar autostarts before NetworkManager is ready, the list can stay empty for
    // the whole session, which used to leave the popup stuck on "Scanning…".
    // We therefore mirror the same information through nmcli and fall back to it
    // whenever Quickshell reports nothing.
    property var wifiNmRows: []
    property var wifiKnown: ({})

    Process {
        id: wifiScanProc
        command: ["nmcli", "-m", "multiline", "-c", "no",
            "-f", "IN-USE,SSID,SIGNAL,SECURITY,FREQ,DEVICE", "dev", "wifi", "list", "--rescan", "no"]
        stdout: StdioCollector { onStreamFinished: root.parseWifiScan(this.text) }
    }
    Process {
        id: wifiProfProc
        command: ["nmcli", "-t", "-c", "no", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector { onStreamFinished: root.parseWifiProfiles(this.text) }
    }
    Process {
        id: wifiCmdProc
        onExited: { root.netRevision++; wifiNmRefresh.restart() }
    }
    Timer {
        id: wifiNmRefresh
        interval: 900
        repeat: false
        onTriggered: {
            if (!wifiScanProc.running) wifiScanProc.running = true
            if (!wifiProfProc.running) wifiProfProc.running = true
        }
    }

    function wifiNmRefreshNow() { wifiNmRefresh.restart() }
    function wifiNmCmd(args) {
        wifiCmdProc.command = ["nmcli"].concat(args)
        if (!wifiCmdProc.running) wifiCmdProc.running = true
        root.netRevision++
    }

    // nmcli's multiline mode pads each value to a fixed column and does not
    // always emit a blank line between records, so split on the first field and
    // trim the padding off every value.
    function parseWifiScan(txt) {
        var seen = ({})
        var out = []
        var chunks = String(txt).replace(/\r/g, "").split(/\n(?=IN-USE:)/)
        for (var i = 0; i < chunks.length; i++) {
            var lines = chunks[i].split("\n")
            var rec = ({})
            for (var j = 0; j < lines.length; j++) {
                var k = lines[j].indexOf(":")
                if (k > 0) rec[lines[j].slice(0, k).trim()] = lines[j].slice(k + 1).trim()
            }
            var ssid = rec["SSID"] || ""
            if (ssid === "" || ssid === "--") continue
            var sig = parseFloat(rec["SIGNAL"] || "0") || 0
            var conn = (rec["IN-USE"] || "").indexOf("*") >= 0
            var sec = rec["SECURITY"] || ""
            var mhz = parseInt(rec["FREQ"] || "0") || 0
            var band = mhz <= 0 ? "" : (mhz < 3000 ? "2.4" : (mhz < 5925 ? "5" : "6"))
            // One row per SSID (a strong AP may repeat across BSSIDs and bands).
            if (seen[ssid] === undefined) {
                seen[ssid] = out.length
                out.push({
                    name: ssid, signalStrength: sig, connected: conn,
                    secure: sec !== "" && sec !== "--",
                    device: rec["DEVICE"] || "wlan0",
                    bands: band ? [band] : []
                })
            } else {
                var p = out[seen[ssid]]
                p.signalStrength = Math.max(p.signalStrength, sig)
                p.connected = p.connected || conn
                if (band && p.bands.indexOf(band) < 0) p.bands.push(band)
            }
        }
        root.wifiNmRows = out
        root.netRevision++
    }
    function parseWifiProfiles(txt) {
        var known = ({})
        var lines = String(txt).split("\n")
        for (var i = 0; i < lines.length; i++) {
            var k = lines[i].lastIndexOf(":")
            if (k <= 0 || lines[i].slice(k + 1) !== "802-11-wireless") continue
            known[lines[i].slice(0, k).replace(/\\:/g, ":")] = true
        }
        root.wifiKnown = known
        root.netRevision++
    }

    function wifiDevice() {
        var ds = (Networking.devices && Networking.devices.values) ? Networking.devices.values : []
        // Pick the wifi device by type — ethernet exposes a (always empty)
        // network list too, so matching on `networks` alone can select it.
        for (var i = 0; i < ds.length; i++)
            if (ds[i] && ds[i].type === DeviceType.Wifi) return ds[i]
        // Backends that report no device type: keep the old heuristic.
        for (var j = 0; j < ds.length; j++)
            if (ds[j] && ds[j].networks !== undefined) return ds[j]
        return null
    }
    // Wi-Fi scans only happen when the user presses Scan in the panel. Every
    // scan takes the MT7925 off-channel, which stalls traffic (video buffers
    // until Wi-Fi is toggled), so nothing scans on its own: the panel shows
    // NetworkManager's last results ("--rescan no").
    property bool wifiScanning: false
    // "--rescan yes" waits until the scan has finished on every band (2.4,
    // 5 and 6 GHz; 6 GHz alone is ~90 channels) and then prints the full
    // list. A fixed wait after "rescan" read the list half-way and showed
    // only the 5 GHz results.
    Process {
        id: wifiRescanProc
        command: ["nmcli", "-m", "multiline", "-c", "no",
            "-f", "IN-USE,SSID,SIGNAL,SECURITY,FREQ,DEVICE", "dev", "wifi", "list", "--rescan", "yes"]
        stdout: StdioCollector { onStreamFinished: root.parseWifiScan(this.text) }
        onExited: { root.wifiScanning = false; root.netRevision++; root.wifiNmRefreshNow() }
    }
    function wifiScanNow() {
        if (root.wifiScanning) return
        root.wifiScanning = true
        wifiRescanProc.running = true
    }
    function wifiQsNetworks() {
        var d = root.wifiDevice()
        if (!d || !d.networks || !d.networks.values) return []
        var arr = d.networks.values.slice()
        arr.sort(function (a, b) {
            if (!!a.connected !== !!b.connected) return a.connected ? -1 : 1
            if (!!a.known !== !!b.known) return a.known ? -1 : 1
            return (b.signalStrength || 0) - (a.signalStrength || 0)
        })
        return arr
    }
    // nmcli rows exposed with the same shape/methods the popup expects from a
    // Quickshell `Network`, so the delegate works against either source.
    function wifiNmNetworks() {
        var rows = root.wifiNmRows.slice()
        rows.sort(function (a, b) {
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            if (!!root.wifiKnown[a.name] !== !!root.wifiKnown[b.name])
                return root.wifiKnown[a.name] ? -1 : 1
            return (b.signalStrength || 0) - (a.signalStrength || 0)
        })
        return rows.map(function (r) {
            return {
                name: r.name,
                signalStrength: r.signalStrength,
                connected: r.connected,
                known: !!root.wifiKnown[r.name],
                security: r.secure ? 1 : 0,
                bands: (r.bands || []).slice().sort(function (x, y) { return parseFloat(x) - parseFloat(y) }),
                stateChanging: false,
                nm: true,
                connect: function () { root.wifiNmCmd(["dev", "wifi", "connect", r.name]) },
                connectWithPsk: function (psk) {
                    root.wifiNmCmd(["dev", "wifi", "connect", r.name, "password", psk])
                },
                disconnect: function () { root.wifiNmCmd(["dev", "disconnect", r.device]) }
            }
        })
    }
    // nmcli's list first: it is what Scan refreshes and it covers every band.
    // Quickshell's own list only updates while its background scanner runs,
    // which is kept off (scans stall the MT7925), so it goes stale.
    function wifiNetworks() {
        var arr = root.wifiNmNetworks()
        if (arr.length > 0) return arr
        return root.wifiQsNetworks()
    }
    function wifiConnectedName() {
        var arr = root.wifiNetworks()
        for (var i = 0; i < arr.length; i++) if (arr[i].connected) return arr[i].name
        return ""
    }
    function wifiOpen(n) {
        if (!n) return false
        if (n.nm === true) return !n.security
        return n.security === WifiSecurityType.Open
    }
    function wifiPct(n) {
        var s = n ? (n.signalStrength || 0) : 0
        return Math.round(s > 1 ? s : s * 100)
    }
    function wifiPick(n) {
        if (!n) return
        if (n.connected) { n.disconnect(); root.netRevision++; return }
        if (n.known || root.wifiOpen(n)) { n.connect(); root.netRevision++; return }
        root.wifiTarget = n
        root.wifiPsk = ""
    }
    function wifiSubmit() {
        if (!root.wifiTarget) return
        root.wifiTarget.connectWithPsk(root.wifiPsk)
        root.wifiTarget = null
        root.wifiPsk = ""
        root.netRevision++
    }
    function wifiCancel() { root.wifiTarget = null; root.wifiPsk = "" }


    readonly property var battery: UPower.displayDevice
    readonly property int batPct: (root.battery && root.battery.isPresent) ? Math.round(root.battery.percentage * 100) : -1
    function batGlyph() {
        if (!root.battery || !root.battery.isPresent) return ""
        if (root.battery.state === UPowerDeviceState.Charging || root.battery.state === UPowerDeviceState.FullyCharged)
            return "\uf376"
        var g = ["\uf244", "\uf243", "\uf242", "\uf241", "\uf240", "\uf240"]
        return g[Math.min(5, Math.max(0, Math.round(root.batPct / 20)))]
    }

    // --------------------------------------------------------- display state
    property var dispState: ({})
    property int dispSeconds: 0

    Process {
        id: dispProbe
        command: [root.dispBin, "state"]
        stdout: StdioCollector { onStreamFinished: root.loadDisplay(this.text) }
    }
    Timer {
        id: dispRefreshTimer
        interval: 900
        repeat: false
        onTriggered: { root.refreshDisplay(); root.readBrightness() }
    }
    Process {
        id: brightProc
        command: ["bash", "-lc", "brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseInt(this.text)
                if (!isNaN(v)) root.brightness = v
            }
        }
    }
    // Applies a dragged display position without going through a shell string.
    Process {
        id: dispMoveProc
        stdout: StdioCollector { onStreamFinished: dispRefreshTimer.restart() }
    }
    Timer {
        interval: 1000
        running: root.displayOpen && root.dispHasPending()
        repeat: true
        triggeredOnStart: true
        onTriggered: root.tickCountdown()
    }

    function refreshDisplay() { if (!dispProbe.running) dispProbe.running = true }
    function loadDisplay(txt) {
        try { root.dispState = JSON.parse(txt) } catch (e) { console.log("display state: " + e) }
    }
    function readBrightness() { if (!brightProc.running) brightProc.running = true }
    function dispDisplays() { return (root.dispState && root.dispState.displays) ? root.dispState.displays : [] }
    function dispPending() { return (root.dispState && root.dispState.pending) ? root.dispState.pending : ({}) }
    function dispHasPending() { var p = root.dispPending(); for (var k in p) return true; return false }
    function tickCountdown() {
        var p = root.dispPending(), d = 0
        for (var k in p) d = Math.max(d, p[k].deadline || 0)
        root.dispSeconds = Math.max(0, Math.round(d - Date.now() / 1000))
    }
    function dispSelected() {
        var list = root.dispDisplays()
        var name = root.dispState ? root.dispState.selected : ""
        for (var i = 0; i < list.length; i++) if (list[i].name === name) return list[i]
        for (var j = 0; j < list.length; j++) if (list[j].focused) return list[j]
        return list.length ? list[0] : null
    }
    function dispResolutions(m) {
        if (!m) return []
        var seen = {}, out = [], ms = m.modes || []
        for (var i = 0; i < ms.length; i++) {
            var k = ms[i].width + "x" + ms[i].height
            if (seen[k]) continue
            seen[k] = true
            out.push({ value: k, label: ms[i].width + " \u00d7 " + ms[i].height, width: ms[i].width, height: ms[i].height })
        }
        out.sort(function (a, b) { return (b.width * b.height) - (a.width * a.height) })
        return out
    }
    function dispRefreshes(m, w, h) {
        var out = [], ms = (m && m.modes) || []
        for (var i = 0; i < ms.length; i++)
            if (ms[i].width === w && ms[i].height === h) {
                var s = ms[i].hz.toFixed(2)
                out.push({ value: s, label: s + " Hz", hz: ms[i].hz })
            }
        out.sort(function (a, b) { return b.hz - a.hz })
        return out
    }
    function dispGcd(a, b) { a = Math.abs(a); b = Math.abs(b); while (b) { var t = b; b = a % b; a = t } return a }
    function dispCleanScale(s, w, h) {
        var req = parseFloat(s)
        if (!(req > 0) || w <= 0 || h <= 0) return ""
        var div = root.dispGcd(Math.round(w * 120), Math.round(h * 120))
        var units = Math.round(req * 120)
        if (units > div) units = div
        if (units < 1) return ""
        // Hyprland keeps only scales where both dimensions stay whole pixels
        // (scale*120 must divide 120*gcd(w,h)) and rounds to the NEAREST such
        // value — 1.8 -> 1.875 on a 2880x1920 panel.  Match that exactly so
        // what the menu shows is what actually gets applied.
        if (div % units !== 0) {
            var lo = units - 1
            while (lo > 0 && div % lo !== 0) lo--
            var hi = units + 1
            while (hi <= div && div % hi !== 0) hi++
            units = (lo < 1) ? hi : (hi > div) ? lo
                                              : ((units - lo) <= (hi - units) ? lo : hi)
        }
        return String(Math.round(units / 120 * 100) / 100)
    }
    function dispScales(w, h) {
        // Step ladder the user picks from, 1x..3x.  Deduped on the effective
        // value, because a preset may snap to the same real scale as another.
        var presets = ["1", "1.25", "1.5", "1.6", "1.75", "1.8", "2", "2.25",
                       "2.5", "2.75", "3"]
        var seen = {}, out = []
        for (var i = 0; i < presets.length; i++) {
            var e = root.dispCleanScale(presets[i], w, h)
            if (e === "" || seen[e]) continue
            seen[e] = true
            out.push({ value: e, label: e + "\u00d7" })
        }
        return out
    }
    function dispMirrors(m) {
        var out = [{ value: "", label: "Off" }]
        var list = root.dispDisplays()
        for (var i = 0; i < list.length; i++)
            if (list[i].name !== (m ? m.name : "")) out.push({ value: list[i].name, label: list[i].name })
        return out
    }

    // ---- arrangement (drag canvas) ------------------------------------------
    // Ported from the Auggment Display plugin's Model.js so the bar can lay the
    // monitors out the same way the standalone "Arrange displays" window does.
    function dispParsePosition(t) {
        var m = /^(-?\d+)x(-?\d+)$/.exec(String(t || ""))
        return m ? { x: parseInt(m[1]), y: parseInt(m[2]) } : null
    }
    function dispLogicalRect(s) {
        var p = root.dispParsePosition(s ? s.position : "")
        if (!p) return null
        var rot = (parseInt(s.transform) || 0) % 2 === 1
        var sc = parseFloat(s.scale) || 1
        return { x: p.x, y: p.y,
                 w: Math.round((rot ? s.height : s.width) / sc),
                 h: Math.round((rot ? s.width : s.height) / sc) }
    }
    function dispBounds(rects) {
        if (!rects || !rects.length) return { x: 0, y: 0, w: 1, h: 1 }
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
        for (var i = 0; i < rects.length; i++) {
            minX = Math.min(minX, rects[i].x); minY = Math.min(minY, rects[i].y)
            maxX = Math.max(maxX, rects[i].x + rects[i].w); maxY = Math.max(maxY, rects[i].y + rects[i].h)
        }
        return { x: minX, y: minY, w: maxX - minX, h: maxY - minY }
    }
    function dispSettingsFor(d) {
        var p = root.dispPending()[d.name]
        if (p && p.after) return p.after
        return { output: d.name, disabled: !d.enabled,
                 width: d.width, height: d.height, hz: d.hz,
                 position: d.enabled ? (d.x + "x" + d.y) : "auto",
                 scale: d.scale, transform: d.transform,
                 mirror: d.mirrorOf, vrr: d.vrr, hdr: d.hdr }
    }
    function dispLayoutRects() {
        var list = root.dispDisplays(), out = []
        for (var i = 0; i < list.length; i++) {
            var s = root.dispSettingsFor(list[i])
            if (s.disabled || s.mirror) continue
            var r = root.dispLogicalRect(s)
            if (r) out.push({ name: list[i].name, model: list[i].model || list[i].name,
                              x: r.x, y: r.y, w: r.w, h: r.h })
        }
        return out
    }
    function dispOverlaps(a, b) {
        return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
    }
    function dispNearest(v, cands, th) {
        var best = v, bd = th
        for (var i = 0; i < cands.length; i++) {
            var dd = Math.abs(cands[i] - v)
            if (dd < bd) { best = cands[i]; bd = dd }
        }
        return best
    }
    function dispTouches(a, b) {
        var px = a.x < b.x + b.w && b.x < a.x + a.w
        var py = a.y < b.y + b.h && b.y < a.y + a.h
        var xt = a.x + a.w === b.x || b.x + b.w === a.x
        var yt = a.y + a.h === b.y || b.y + b.h === a.y
        return (xt && py) || (yt && px)
    }
    function dispCloseGap(rect, other) {
        var px = rect.x < other.x + other.w && other.x < rect.x + rect.w
        var py = rect.y < other.y + other.h && other.y < rect.y + rect.h
        var cx = rect.x > other.x ? other.x + other.w : other.x - rect.w
        var cy = rect.y > other.y ? other.y + other.h : other.y - rect.h
        var moves = []
        if (py) moves.push({ x: cx, y: rect.y })
        if (px) moves.push({ x: rect.x, y: cy })
        if (!px && !py) moves.push({ x: cx, y: other.y }, { x: other.x, y: cy })
        var best = null
        for (var i = 0; i < moves.length; i++) {
            var cost = Math.abs(moves[i].x - rect.x) + Math.abs(moves[i].y - rect.y)
            if (!best || cost < best.cost) best = { x: moves[i].x, y: moves[i].y, cost: cost }
        }
        return best
    }
    function dispSnapPosition(moving, others, threshold) {
        var xs = [], ys = []
        for (var i = 0; i < others.length; i++) {
            var o = others[i]
            xs.push(o.x + o.w, o.x - moving.w, o.x, o.x + o.w - moving.w)
            ys.push(o.y + o.h, o.y - moving.h, o.y, o.y + o.h - moving.h)
        }
        var rect = { x: root.dispNearest(moving.x, xs, threshold),
                     y: root.dispNearest(moving.y, ys, threshold),
                     w: moving.w, h: moving.h }
        for (var pass = 0; pass < 8; pass++) {
            var pushed = false
            for (var j = 0; j < others.length; j++) {
                var other = others[j]
                if (!root.dispOverlaps(rect, other)) continue
                var moves = [
                    { x: other.x + other.w, y: rect.y },
                    { x: other.x - rect.w, y: rect.y },
                    { x: rect.x, y: other.y + other.h },
                    { x: rect.x, y: other.y - rect.h }
                ]
                var best = null
                for (var k = 0; k < moves.length; k++) {
                    var cost = Math.abs(moves[k].x - rect.x) + Math.abs(moves[k].y - rect.y)
                    if (!best || cost < best.cost) best = { x: moves[k].x, y: moves[k].y, cost: cost }
                }
                rect.x = best.x; rect.y = best.y
                pushed = true
            }
            if (!pushed) break
        }
        var touching = false
        for (var t = 0; t < others.length; t++) if (root.dispTouches(rect, others[t])) touching = true
        if (!touching && others.length) {
            var closest = null
            for (var c = 0; c < others.length; c++) {
                var cand = root.dispCloseGap(rect, others[c])
                if (!closest || cand.cost < closest.cost) closest = cand
            }
            rect.x = closest.x; rect.y = closest.y
        }
        return { x: Math.round(rect.x), y: Math.round(rect.y) }
    }
    // Snap a dragged display into place and apply it (revertable like any change).
    function dispMoveDisplay(name, x, y) {
        var rects = root.dispLayoutRects(), moving = null, others = []
        for (var i = 0; i < rects.length; i++) {
            if (rects[i].name === name) moving = { x: x, y: y, w: rects[i].w, h: rects[i].h }
            else others.push(rects[i])
        }
        if (!moving) return
        var snapped = root.dispSnapPosition(moving, others, 60)
        dispMoveProc.command = [root.dispBin, "change", "--monitor", name,
                                JSON.stringify({ position: snapped.x + "x" + snapped.y })]
        dispMoveProc.running = true
    }
    function dispApply(patch) {
        // argv, not a shell string — no injection surface from monitor data.
        dispMoveProc.command = [root.dispBin, "change", JSON.stringify(patch)]
        dispMoveProc.running = true
    }
    function dispSetRes(m, v) {
        var parts = v.split("x")
        var w = parseInt(parts[0]), h = parseInt(parts[1])
        var rs = root.dispRefreshes(m, w, h)
        var hz = rs.length ? rs[0].hz : m.hz
        root.dispApply({ width: w, height: h, hz: hz })
    }
    function dispSetPos(m, axis, delta) {
        var x = m.x, y = m.y
        if (axis === "x") x += delta; else y += delta
        root.dispApply({ position: x + "x" + y })
    }
    function dispSelect(name) { dispMoveProc.command = [root.dispBin, "select", name]; dispMoveProc.running = true }
    function dispKeep() { root.run(root.dispBin + " keep"); dispRefreshTimer.restart() }
    function dispRevert() { root.run(root.dispBin + " revert"); dispRefreshTimer.restart() }
    function dispForget() { root.run(root.dispBin + " forget"); dispRefreshTimer.restart() }
    function setBrightness(delta) { root.run("brightnessctl set " + delta); dispRefreshTimer.restart() }
    function setBrightnessAbs(v) { root.run("brightnessctl set " + Math.round(v) + "%"); root.brightness = Math.round(v) }

    // ------------------------------------------------ auggment display extras
    property int auggBgIndex: 2
    property int auggSsIndex: 3
    property int auggScreenOffIndex: 2
    property bool auggAutoColor: false
    // Dark mode is the shell-side mirror of ~/.config/auggment/theme_mode.
    // auggment-theme-sync owns that file and rebuilds the whole system theme
    // (bar palette, KDE/Qt scheme, GTK, terminals, borders) from it, so the
    // toggle here just flips the file and asks the engine to re-run.
    property bool auggDarkMode: true
    readonly property var auggBgIntervals: [60, 120, 300, 600, 900, 1800, 3600]
    readonly property var auggSsTimes: [60, 120, 180, 300, 600, 900, 1800]
    readonly property var auggScreenOffTimes: [120, 300, 600, 900, 1800, 3600]

    Process {
        id: auggBgRead
        command: ["bash", "-lc", "cat $HOME/.config/auggment/bg_interval 2>/dev/null || echo 300"]
        stdout: StdioCollector { onStreamFinished: root.syncAuggIndex("bg", this.text) }
    }
    Process {
        id: auggSsRead
        command: ["bash", "-lc", "cat $HOME/.config/auggment/screensaver_timeout 2>/dev/null || echo 300"]
        stdout: StdioCollector { onStreamFinished: root.syncAuggIndex("ss", this.text) }
    }
    Process {
        id: auggScreenOffRead
        command: ["bash", "-lc", "cat $HOME/.config/auggment/screen_off_timeout 2>/dev/null || echo 600"]
        stdout: StdioCollector { onStreamFinished: root.syncAuggIndex("off", this.text) }
    }
    Process {
        id: auggColorRead
        command: ["bash", "-lc", "cat $HOME/.config/auggment/auto_color_match 2>/dev/null || echo 1"]
        stdout: StdioCollector { onStreamFinished: root.auggAutoColor = (String(this.text).trim() === "1") }
    }
    Process {
        id: auggModeRead
        command: ["bash", "-lc", "cat $HOME/.config/auggment/theme_mode 2>/dev/null || echo dark"]
        stdout: StdioCollector { onStreamFinished: root.auggDarkMode = (String(this.text).trim() !== "light") }
    }
    // After a Dark/Light flip, give auggment-theme-sync a moment to finish
    // writing colors.toml, then re-read the theme so the bar repaints at once.
    Timer {
        id: auggThemeApply
        interval: 1500
        onTriggered: if (!themeProc.running) themeProc.running = true
    }

    function syncAuggIndex(which, txt) {
        var v = parseInt(txt)
        var arr = which === "bg" ? root.auggBgIntervals : (which === "ss" ? root.auggSsTimes : root.auggScreenOffTimes)
        for (var i = 0; i < arr.length; i++)
            if (arr[i] === v) {
                if (which === "bg") root.auggBgIndex = i
                else if (which === "ss") root.auggSsIndex = i
                else root.auggScreenOffIndex = i
                break
            }
    }
    function auggRead() {
        auggBgRead.running = true
        auggSsRead.running = true
        auggScreenOffRead.running = true
        auggColorRead.running = true
        auggModeRead.running = true
    }
    function auggTimeOpts(arr) {
        var o = []
        for (var i = 0; i < arr.length; i++) o.push({ value: String(i), label: root.sbFmtTime(arr[i]) })
        return o
    }
    function auggSetBg(i) {
        root.auggBgIndex = i
        var v = root.auggBgIntervals[i]
        root.run("mkdir -p $HOME/.config/auggment && echo " + v + " > $HOME/.config/auggment/bg_interval")
        root.run("N=$(printf 'auggment-wallpaper-%s' rotate); pkill -f \"$N\" >/dev/null 2>&1 || true; sleep 0.3; setsid \"$N\" " + v + " >/dev/null 2>&1 &")
    }
    function auggRotateNow() { root.run("auggment-wallpaper-rotate --once") }
    function auggSetSs(i) {
        root.auggSsIndex = i
        var v = root.auggSsTimes[i]
        root.run("mkdir -p $HOME/.config/auggment && echo " + v + " > $HOME/.config/auggment/screensaver_timeout && '" + root.dispDir + "/set-screensaver.sh' " + v)
    }
    function auggSetScreenOff(i) {
        root.auggScreenOffIndex = i
        var v = root.auggScreenOffTimes[i]
        root.run("mkdir -p $HOME/.config/auggment && echo " + v + " > $HOME/.config/auggment/screen_off_timeout && '" + root.dispDir + "/auggment-idle-sync.sh'")
    }
    function auggSetAutoColor(v) {
        root.auggAutoColor = v
        root.run("mkdir -p $HOME/.config/auggment && echo " + (v ? 1 : 0) + " > $HOME/.config/auggment/auto_color_match")
    }
    function auggSetDarkMode(v) {
        root.auggDarkMode = v
        var mode = v ? "dark" : "light"
        // Persist the choice, then rebuild the whole system theme (bar palette,
        // KDE/Qt colour scheme, GTK, terminals, Hyprland borders) around it.
        // auggment-theme-sync with no argument re-themes the current wallpaper.
        root.run("mkdir -p $HOME/.config/auggment && echo " + mode + " > $HOME/.config/auggment/theme_mode && auggment-theme-sync")
        // Repaint the bar promptly rather than waiting for the next 6s poll.
        auggThemeApply.restart()
    }
    function dispToggleEnabled(m) {
        if (!m) return
        var list = root.dispDisplays()
        var enabledCount = 0
        for (var i = 0; i < list.length; i++) if (list[i].enabled) enabledCount++
        if (m.enabled && enabledCount <= 1) return
        root.dispApply({ disabled: m.enabled })
    }
    function brightnessName(p) {
        p = Math.round(p)
        if (p >= 95) return "Sun blast"
        if (p >= 80) return "Solar flare"
        if (p >= 65) return "Golden hour"
        if (p >= 45) return "Even day"
        if (p >= 30) return "Soft glow"
        if (p >= 20) return "Lamp light"
        if (p >= 10) return "Candlelit"
        return "Night owl"
    }

    // ------------------------------------------------------- now playing (MPRIS)
    property bool npActive: false
    property bool npPlaying: false
    property string npTitle: ""
    property string npArtist: ""

    Process {
        id: npProc
        command: [root.home + "/.local/bin/auggment-nowplaying", "status"]
        stdout: StdioCollector { onStreamFinished: root.parseNowPlaying(this.text) }
    }
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!npProc.running) npProc.running = true
    }
    function parseNowPlaying(txt) {
        try {
            var d = JSON.parse(String(txt))
            root.npActive = !!d.active
            root.npPlaying = !!d.playing
            root.npTitle = d.title || ""
            root.npArtist = d.artist || ""
        } catch (e) {
            root.npActive = false
        }
    }
    function npCmd(a) {
        root.run("'" + root.home + "/.local/bin/auggment-nowplaying' " + a)
        npProc.running = true
    }
    function npText() {
        if (root.npArtist !== "" && root.npTitle !== "")
            return root.npTitle + "  \u2014  " + root.npArtist
        return root.npTitle !== "" ? root.npTitle : "Apple Music"
    }

    // ---------------------------------------------------------------- weather
    // Current temperature + condition for the far-left of the bar, with a
    // 5-hour outlook (left click) and a location picker (right click). The
    // heavy lifting (wttr.in + Open-Meteo fetch, glyph mapping, caching) lives
    // in auggment-weather.
    property bool wxOk: false
    property bool wxOpen: false
    property bool wxSetOpen: false
    property string wxTemp: ""
    property string wxCond: ""
    property string wxIcon: ""
    property string wxPlace: ""
    property var wxHours: []
    property string wxLocText: ""

    Process {
        id: wxProc
        command: [root.home + "/.local/bin/auggment-weather"]
        stdout: StdioCollector { onStreamFinished: root.parseWx(this.text) }
    }
    Timer {
        interval: 600000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.wxRefresh()
    }
    // Re-armed until the single weather process is free, then forces a fetch.
    Timer { id: wxForceTimer; interval: 300; repeat: false; onTriggered: root.wxForceRun() }
    Process { id: wxLocProc }
    function wxRefresh() {
        if (wxProc.running) return
        wxProc.command = [root.home + "/.local/bin/auggment-weather"]
        wxProc.running = true
    }
    function wxForceRun() {
        if (wxProc.running) { wxForceTimer.restart(); return }
        wxProc.command = [root.home + "/.local/bin/auggment-weather", "--force"]
        wxProc.running = true
    }
    function wxToggle() {
        var was = root.wxOpen
        root.closePanels()
        root.wxOpen = !was
        if (root.wxOpen) root.wxRefresh()
    }
    function wxToggleSet() {
        var was = root.wxSetOpen
        root.closePanels()
        root.wxSetOpen = !was
    }
    function wxSetLocation(name) {
        var n = String(name || "").trim()
        if (n === "") return
        root.wxLocText = ""
        root.wxSetOpen = false
        wxLocProc.command = [root.home + "/.local/bin/auggment-weather-location", "--set", n]
        wxLocProc.running = true
        wxForceTimer.start()
    }
    function wxClearLocation() {
        root.wxSetOpen = false
        wxLocProc.command = [root.home + "/.local/bin/auggment-weather-location", "--clear"]
        wxLocProc.running = true
        wxForceTimer.start()
    }
    function parseWx(txt) {
        try {
            var d = JSON.parse(String(txt))
            root.wxOk = !!d.ok
            root.wxTemp = d.temp || ""
            root.wxCond = d.cond || ""
            root.wxIcon = d.icon || ""
            root.wxPlace = d.place || ""
            root.wxHours = Array.isArray(d.hourly) ? d.hourly : []
        } catch (e) { root.wxOk = false }
    }

    // -------------------------------------------------------------- calendar
    // Read-only Google Calendar via the calendar's private iCal address (or any
    // other iCalendar feed). `auggment-calendar` fetches those feeds and answers
    // with one JSON object per call, the same contract auggment-weather uses.
    //
    //   left click on the clock       month grid + the selected day's agenda
    //   right click / alt+left click  add/remove calendars, per-calendar toggles
    property bool calOpen: false
    property bool calAuthOpen: false
    property bool calLinked: false
    property bool calLoaded: false
    property bool calLoading: false
    property string calErr: ""
    property string calNotice: ""
    property string calStatusMsg: ""
    property string calAuthErr: ""
    property string calMonth: ""
    property string calSelKey: ""
    property string calUrl: ""
    property int calAgendaDays: 14
    property int calTick: 0
    property var calEvents: []
    property var calCalendars: []

    // Bumped each minute so "today", the grid and the agenda stay honest.
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.calTick++ }
    // Keep an open panel fresh; the backend caches for 5 minutes either way.
    Timer { interval: 300000; running: root.calOpen; repeat: true; onTriggered: root.calRefresh(false) }

    function calBin() { return root.home + "/.local/bin/auggment-calendar" }
    function calPad(n) { return (n < 10 ? "0" : "") + n }
    function calDateKey(d) { return d.getFullYear() + "-" + root.calPad(d.getMonth() + 1) + "-" + root.calPad(d.getDate()) }
    function calNowKey() { return root.calDateKey(new Date()) }
    function calThisMonth() { return root.calNowKey().slice(0, 7) }

    Process {
        id: calProc
        stdout: StdioCollector { onStreamFinished: root.calParseEvents(this.text) }
    }
    Process {
        id: calCalsProc
        stdout: StdioCollector { onStreamFinished: root.calParseCalendars(this.text) }
    }
    Process {
        id: calAddProc
        stdout: StdioCollector { onStreamFinished: root.calParseAdd(this.text) }
    }
    Process {
        id: calMutateProc
        stdout: StdioCollector { onStreamFinished: root.calParseMutate(this.text) }
    }

    function calJson(txt) {
        try { return JSON.parse(String(txt)) } catch (e) { return null }
    }
    function calRefresh(force) {
        if (calProc.running) return
        if (root.calMonth === "") root.calMonth = root.calThisMonth()
        if (root.calSelKey === "") root.calSelKey = root.calNowKey()
        root.calLoading = true
        var cmd = [root.calBin(), "events", "--month", root.calMonth, "--agenda-days", String(root.calAgendaDays)]
        if (force) cmd.push("--force")
        calProc.command = cmd
        calProc.running = true
    }
    function calParseEvents(txt) {
        root.calLoading = false
        root.calLoaded = true
        var d = root.calJson(txt)
        if (!d) { root.calErr = "the calendar backend returned something unparseable"; return }
        root.calLinked = !!d.linked
        root.calNotice = d.error ? String(d.error) : ""
        root.calErr = (Array.isArray(d.errors) && d.errors.length) ? d.errors.join("  ·  ") : ""
        root.calCalendars = Array.isArray(d.calendars) ? d.calendars : []
        root.calEvents = Array.isArray(d.events) ? d.events : []
    }
    function calLoadCalendars(force) {
        if (calCalsProc.running) return
        var cmd = [root.calBin(), "calendars"]
        if (force) cmd.push("--force")
        calCalsProc.command = cmd
        calCalsProc.running = true
    }
    function calParseCalendars(txt) {
        var d = root.calJson(txt)
        if (!d) return
        root.calCalendars = Array.isArray(d.calendars) ? d.calendars : []
        if (Array.isArray(d.errors) && d.errors.length) root.calAuthErr = d.errors.join("  ·  ")
    }
    function calAddFeed() {
        var u = String(root.calUrl).trim()
        if (u === "") { root.calAuthErr = "Paste the calendar's iCal address first."; return }
        if (calAddProc.running) return
        root.calAuthErr = ""
        root.calStatusMsg = "Fetching the feed…"
        calAddProc.command = [root.calBin(), "feed-add", "--url", u]
        calAddProc.running = true
    }
    function calParseAdd(txt) {
        var d = root.calJson(txt)
        if (d && d.ok) {
            root.calUrl = ""
            root.calAuthErr = ""
            var n = (d.upcoming !== undefined && d.upcoming !== null) ? d.upcoming : 0
            root.calStatusMsg = "Added " + d.feed.name + (n > 0 ? " · " + n + " events in the next 30 days" : "")
            root.calLoadCalendars(true)
            root.calRefresh(true)
        } else {
            root.calStatusMsg = ""
            root.calAuthErr = (d && d.error) ? String(d.error) : "could not add that calendar"
        }
    }
    function calToggleCal(acct, id) {
        if (calMutateProc.running) return
        calMutateProc.command = [root.calBin(), "toggle", "--account", acct, "--id", id]
        calMutateProc.running = true
    }
    function calRemoveFeed(id) {
        if (calMutateProc.running) return
        calMutateProc.command = [root.calBin(), "feed-remove", "--id", id]
        calMutateProc.running = true
    }
    function calParseMutate(txt) {
        var d = root.calJson(txt)
        if (!d || !d.ok) { root.calAuthErr = (d && d.error) ? String(d.error) : "that did not work"; return }
        root.calAuthErr = ""
        root.calLoadCalendars(true)
        root.calRefresh(true)
    }
    function calOpenPanel() {
        var was = root.calOpen
        root.closePanels()
        root.calOpen = !was
        if (!root.calOpen) return
        root.calMonth = root.calThisMonth()
        root.calSelKey = root.calNowKey()
        root.calRefresh(false)
    }
    function calOpenAuth() {
        var was = root.calAuthOpen
        root.closePanels()
        root.calAuthOpen = !was
        if (!root.calAuthOpen) return
        root.calLoadCalendars(false)
    }
    function calShiftMonth(delta) {
        var y = parseInt(root.calMonth.slice(0, 4))
        var m = parseInt(root.calMonth.slice(5, 7)) - 1 + delta
        root.calMonth = root.calDateKey(new Date(y, m, 1)).slice(0, 7)
        // Default the agenda to the 1st of the month we just landed on.
        root.calSelKey = root.calMonth + "-01"
        root.calRefresh(false)
    }
    function calGoToday() {
        root.calMonth = root.calThisMonth()
        root.calSelKey = root.calNowKey()
        root.calRefresh(false)
    }
    function calMonthLabel() {
        var y = parseInt(root.calMonth.slice(0, 4))
        var m = parseInt(root.calMonth.slice(5, 7))
        if (!y || !m) return ""
        return Qt.formatDate(new Date(y, m - 1, 1), "MMMM yyyy")
    }
    function calDayLabel(key) {
        if (!key) return ""
        var d = new Date(key + "T00:00:00")
        if (isNaN(d.getTime())) return key
        return Qt.formatDate(d, "dddd d MMMM")
    }
    // 6 weeks of cells (Monday-first) with up to three calendar colours per day.
    function calBuildCells() {
        var y = parseInt(root.calMonth.slice(0, 4))
        var m = parseInt(root.calMonth.slice(5, 7))
        if (!y || !m) return []
        var lead = (new Date(y, m - 1, 1).getDay() + 6) % 7
        var byDay = {}
        for (var i = 0; i < root.calEvents.length; i++) {
            var ev = root.calEvents[i]
            var cur = new Date(String(ev.d0) + "T00:00:00")
            var end = new Date(String(ev.d1 || ev.d0) + "T00:00:00")
            if (isNaN(cur.getTime()) || isNaN(end.getTime())) continue
            for (var g = 0; cur <= end && g < 400; g++) {
                var k = root.calDateKey(cur)
                var bucket = byDay[k]
                if (!bucket) { bucket = []; byDay[k] = bucket }
                if (bucket.indexOf(ev.color) < 0 && bucket.length < 3) bucket.push(ev.color)
                cur = new Date(cur.getFullYear(), cur.getMonth(), cur.getDate() + 1)
            }
        }
        var today = root.calNowKey()
        var cells = []
        for (var j = 0; j < 42; j++) {
            var dd = new Date(y, m - 1, 1 - lead + j)
            var key = root.calDateKey(dd)
            cells.push({
                key: key,
                day: dd.getDate(),
                inMonth: dd.getMonth() === m - 1,
                today: key === today,
                dots: byDay[key] || []
            })
        }
        return cells
    }
    readonly property var calCells: { root.calTick; return root.calBuildCells() }
    function calEventsOn(key) {
        var out = []
        if (!key) return out
        for (var i = 0; i < root.calEvents.length; i++) {
            var ev = root.calEvents[i]
            if (key >= String(ev.d0) && key <= String(ev.d1 || ev.d0)) out.push(ev)
        }
        out.sort(function (a, b) {
            if (!!a.allday !== !!b.allday) return a.allday ? -1 : 1
            return (a.sort || 0) - (b.sort || 0)
        })
        return out
    }
    readonly property var calAgenda: { root.calTick; return root.calEventsOn(root.calSelKey) }

    // ------------------------------------------------------------- bluetooth
    // Left click opens the connected-device list; right (alternate) click opens
    // the fuller connection manager. Read-only bindings over the Quickshell
    // Bluetooth model, sorted connected-first.
    property bool btOpen: false
    property bool btSettings: false
    property var btShown: {
        var s = []
        for (var i = 0; i < btDevList.length; i++) {
            var d = btDevList[i]
            if (btSettings || d.connected) s.push(d)
        }
        return s
    }
    property int btSel: 0
    function btSelClamp() {
        if (btShown.length <= 0) { btSel = 0; return }
        if (btSel >= btShown.length) btSel = btShown.length - 1
        if (btSel < 0) btSel = 0
    }
    readonly property var btDevList: {
        var a = Bluetooth.defaultAdapter
        if (!a || !a.devices) return []
        var out = []
        var ds = a.devices.values || []
        for (var i = 0; i < ds.length; i++) {
            var d = ds[i]
            if (d && !d.blocked) out.push(d)
        }
        out.sort(function (x, y) {
            if (x.connected !== y.connected) return x.connected ? -1 : 1
            if (x.paired !== y.paired) return x.paired ? -1 : 1
            return root.btName(x).localeCompare(root.btName(y))
        })
        return out
    }
    function btName(d) {
        if (!d) return ""
        return (d.name && d.name !== "") ? d.name : ((d.deviceName && d.deviceName !== "") ? d.deviceName : d.address)
    }
    function btSub(d) {
        if (!d) return ""
        if (d.connected) return (d.batteryAvailable ? ("Connected · " + Math.round(d.battery) + "%") : "Connected")
        if (d.pairing) return "Pairing…"
        if (d.paired || d.bonded) return "Paired"
        return "Available"
    }
    function btIconGlyph(d) {
        var ic = d ? String(d.icon || "") : ""
        if (ic.indexOf("headset") >= 0 || ic.indexOf("audio") >= 0) return "\uf025"
        if (ic.indexOf("phone") >= 0) return "\uf3cd"
        if (ic.indexOf("keyboard") >= 0) return "\uf11c"
        if (ic.indexOf("mouse") >= 0) return "\uf8cc"
        if (ic.indexOf("gaming") >= 0) return "\uf11b"
        if (ic.indexOf("printer") >= 0) return "\uf02f"
        return "\uf293"
    }
    function btToggle(settings) {
        var was = root.btOpen && root.btSettings === !!settings
        root.closePanels()
        root.btOpen = !was
        root.btSettings = !!settings
        root.btSel = 0
        root.btSelClamp()
    }

    // ------------------------------------------------------------- components
    component Btn: Rectangle {
        id: b
        property string glyph: ""
        property string label: ""
        property color fg: theme.barText
        property color glyphColor: b.fg
        property int glyphSize: 15
        property bool highlight: false
        property color bgColor: "transparent"
        property color borderColor: "transparent"
        property int hPad: 8
        signal clicked()
        signal rightClicked()
        signal scrolled(int dir)

        implicitWidth: row.implicitWidth + b.hPad * 2
        implicitHeight: theme.barHeight - 8
        radius: theme.radius
        color: (hover.hovered || b.highlight) ? theme.hoverFill : b.bgColor
        border.width: b.borderColor.a > 0.001 ? 1 : 0
        border.color: b.borderColor
        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 5
            Text {
                visible: b.glyph !== ""
                text: b.glyph
                color: b.glyphColor
                font.family: theme.fontFamily
                font.pixelSize: b.glyphSize
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: b.label !== ""
                text: b.label
                color: b.fg
                font.family: theme.fontFamily
                font.pixelSize: theme.fontSize
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: function (m) {
                if (m.button === Qt.RightButton) b.rightClicked()
                else if (m.button === Qt.LeftButton) b.clicked()
            }
            onWheel: function (w) { b.scrolled(w.angleDelta.y > 0 ? 1 : -1) }
        }
    }


    // Left/right stepper for enumerated choices.
    component Stepper: Rectangle {
        id: st
        property var options: []
        property string value: ""
        property color fg: theme.barText
        signal picked(string value)
        implicitHeight: 28
        implicitWidth: stRow.implicitWidth + 12
        radius: 7
        color: theme.normalFill
        border.width: 1
        border.color: theme.cardBorder
        function curIndex() {
            for (var i = 0; i < st.options.length; i++)
                if (String(st.options[i].value) === String(st.value)) return i
            return -1
        }
        function curLabel() {
            var i = st.curIndex()
            if (i >= 0) return st.options[i].label
            return st.options.length ? st.options[0].label : "\u2014"
        }
        Row {
            id: stRow
            anchors.centerIn: parent
            spacing: 2
            Btn {
                glyph: "\uf104"; glyphSize: 12; hPad: 4
                onClicked: {
                    if (!st.options.length) return
                    var i = st.curIndex(); if (i < 0) i = 0
                    st.picked(String(st.options[(i - 1 + st.options.length) % st.options.length].value))
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(implicitWidth, 84)
                text: st.curLabel()
                color: st.fg
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.family: theme.fontFamily
                font.pixelSize: theme.fontSize
            }
            Btn {
                glyph: "\uf105"; glyphSize: 12; hPad: 4
                onClicked: {
                    if (!st.options.length) return
                    var i = st.curIndex()
                    st.picked(String(st.options[(i + 1) % st.options.length].value))
                }
            }
        }
    }

    // Segmented control (e.g. rotation).
    component Segmented: Rectangle {
        id: seg
        property var options: []
        property string value: ""
        signal picked(string value)
        implicitHeight: 28
        implicitWidth: segRow.implicitWidth + 8
        radius: 7
        color: theme.normalFill
        border.width: 1
        border.color: theme.cardBorder
        Row {
            id: segRow
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: seg.options
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: String(modelData.value) === String(seg.value)
                    width: Math.max(34, txt.implicitWidth + 14)
                    height: 22
                    radius: 5
                    color: on ? theme.accent : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        id: txt
                        anchors.centerIn: parent
                        text: modelData.label
                        color: on ? theme.barBackground : theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                        font.bold: on
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.picked(String(modelData.value))
                    }
                }
            }
        }
    }

    component Toggle: Rectangle {
        id: tg
        property bool on: false
        signal toggled(bool on)
        width: 38; height: 20; radius: 10
        color: tg.on ? theme.accent : theme.normalFill
        border.width: 1
        border.color: tg.on ? theme.accent : theme.cardBorder
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle {
            width: 16; height: 16; radius: 8
            color: tg.on ? theme.barBackground : theme.textMuted
            y: 1
            x: tg.on ? tg.width - width - 2 : 2
            Behavior on x { NumberAnimation { duration: 120 } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled(!tg.on) }
    }

    component Slider: Item {
        id: sl
        property real value: 0
        signal moved(real v)
        implicitHeight: 22
        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 6
            radius: 3
            color: theme.normalFill
            Rectangle {
                width: track.width * Math.max(0, Math.min(1, sl.value / 100))
                height: parent.height
                radius: parent.radius
                color: theme.accent
            }
        }
        Rectangle {
            width: 14; height: 14; radius: 7
            color: theme.barText
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(sl.width - width, track.width * (sl.value / 100) - width / 2))
        }
        MouseArea {
            anchors.fill: parent
            onClicked: function (m) { sl.moved(Math.round(100 * m.x / sl.width)) }
            onPositionChanged: function (m) { if (pressed) sl.moved(Math.round(100 * m.x / sl.width)) }
        }
    }

    // ------------------------------------------------------ audio node row
    component AudioRow: Column {
        id: ar
        property var node: ({})
        property bool isDefault: false
        property bool selectable: true
        spacing: 5

        Rectangle {
            width: parent.width
            height: 30
            radius: 8
            color: ar.isDefault ? theme.accentSoft
                 : (arHover.hovered && ar.selectable ? theme.hoverFill : "transparent")
            Behavior on color { ColorAnimation { duration: 120 } }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 7
                Rectangle {
                    width: 7; height: 7; radius: 4
                    color: (ar.node && ar.node.muted) ? theme.urgent : theme.accent
                    opacity: ar.isDefault ? 1 : 0.35
                    Layout.alignment: Qt.AlignVCenter
                }
                Text {
                    text: ar.node ? ar.node.name : ""
                    color: theme.barText
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    font.family: theme.fontFamily
                    font.pixelSize: theme.fontSize
                }
                Text {
                    visible: ar.isDefault
                    text: "DEFAULT"
                    color: theme.textMuted
                    font.family: theme.fontFamily
                    font.pixelSize: theme.fontSize - 3
                    font.letterSpacing: 1
                    Layout.alignment: Qt.AlignVCenter
                }
            }
            HoverHandler { id: arHover }
            MouseArea {
                anchors.fill: parent
                enabled: ar.selectable
                cursorShape: Qt.PointingHandCursor
                onClicked: root.audioSetDefault(ar.node.id)
            }
        }
        RowLayout {
            width: parent.width
            spacing: 8
            Slider {
                Layout.fillWidth: true
                value: root.audioPct(ar.node ? ar.node.volume : 0)
                onMoved: function (v) { root.audioSetVolume(ar.node.id, v) }
            }
            Text {
                text: root.audioPct(ar.node ? ar.node.volume : 0) + "%"
                color: theme.accent
                font.family: theme.fontFamily
                font.pixelSize: theme.fontSize
                horizontalAlignment: Text.AlignRight
                Layout.preferredWidth: 40
            }
            Btn {
                glyph: (ar.node && ar.node.muted) ? "\uf131" : "\uf028"
                glyphSize: 13
                hPad: 6
                glyphColor: (ar.node && ar.node.muted) ? theme.urgent : theme.barText
                onClicked: root.audioMute(ar.node.id)
            }
        }
    }

    // One team inside the scoreboard card: logo (falling back to the
    // abbreviation), abbreviation, name and - only once the game has started -
    // the score.
    component TeamCol: Column {
        id: tc
        property var team: ({})
        property bool showScore: false
        property int logoSize: 42
        property int colWidth: 128
        spacing: 5

        Item {
            width: tc.logoSize
            height: tc.logoSize
            anchors.horizontalCenter: parent.horizontalCenter
            Image {
                id: logoImg
                anchors.fill: parent
                source: tc.team && tc.team.logo ? tc.team.logo : ""
                sourceSize.width: tc.logoSize * 2
                sourceSize.height: tc.logoSize * 2
                fillMode: Image.PreserveAspectFit
                smooth: true
                asynchronous: true
                visible: status === Image.Ready
            }
            Text {
                anchors.centerIn: parent
                visible: logoImg.status !== Image.Ready
                text: (tc.team && tc.team.abbr) ? tc.team.abbr : "?"
                color: tc.team && tc.team.fav ? theme.accent : theme.barText
                font.family: theme.fontFamily
                font.pixelSize: 15
                font.bold: true
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (tc.team && tc.team.abbr) ? tc.team.abbr : "?"
            color: tc.team && tc.team.fav ? theme.accent : theme.barText
            font.family: theme.fontFamily
            font.pixelSize: theme.fontSize + 3
            font.bold: true
        }

        Text {
            width: tc.colWidth
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: (tc.team && tc.team.name) ? tc.team.name : ""
            color: theme.textMuted
            font.family: theme.fontFamily
            font.pixelSize: theme.fontSize - 1
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: tc.showScore
            text: (tc.team && tc.team.score !== undefined && tc.team.score !== "") ? String(tc.team.score) : ""
            color: theme.barText
            font.family: theme.fontFamily
            font.pixelSize: theme.fontSize + 10
            font.bold: true
        }
    }

    // Searchable multi-select, ported from the reference scoreboard panel's
    // MultiSelect: a collapsed "label + N selected" trigger that expands into a
    // search field and a filterable checklist.
    component MultiSelect: Column {
        id: ms
        property string label: ""
        property var values: []
        property var options: []
        property string placeholderText: "Search\u2026"
        property string emptyText: "No options"
        property string noSelectionText: "None selected"
        property bool open: false
        property string query: ""
        signal changed(var values)

        width: parent.width
        spacing: 4

        function filtered() {
            var q = String(ms.query || "").trim().toLowerCase()
            var out = []
            for (var i = 0; i < ms.options.length; i++) {
                var o = ms.options[i]
                if (!q
                        || String(o.value).toLowerCase().indexOf(q) >= 0
                        || String(o.label || "").toLowerCase().indexOf(q) >= 0
                        || String(o.description || "").toLowerCase().indexOf(q) >= 0) {
                    out.push(o)
                    if (out.length >= 200) break
                }
            }
            return out
        }
        function toggle(value) {
            var v = ms.values.slice()
            var i = v.indexOf(value)
            if (i >= 0) v.splice(i, 1); else v.push(value)
            // Keep the catalogue order for stability.
            var ordered = []
            for (var j = 0; j < ms.options.length; j++)
                if (v.indexOf(ms.options[j].value) >= 0) ordered.push(ms.options[j].value)
            for (var k = 0; k < v.length; k++)
                if (ordered.indexOf(v[k]) < 0) ordered.push(v[k])
            ms.changed(ordered)
        }

        Rectangle {
            width: ms.width
            height: 30
            radius: 6
            color: theme.normalFill
            border.width: 1
            border.color: ms.open ? theme.accent : theme.cardBorder
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                spacing: 6
                Text {
                    text: ms.label
                    color: theme.textMuted
                    font.family: theme.fontFamily
                    font.pixelSize: theme.fontSize
                    Layout.alignment: Qt.AlignVCenter
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: ms.values.length > 0 ? (ms.values.length + " selected") : ms.noSelectionText
                    color: theme.barText
                    font.family: theme.fontFamily
                    font.pixelSize: theme.fontSize - 1
                    Layout.alignment: Qt.AlignVCenter
                }
                Text {
                    text: ms.open ? "\uf077" : "\uf078"
                    color: theme.textMuted
                    font.family: theme.fontFamily
                    font.pixelSize: theme.fontSize - 2
                    Layout.alignment: Qt.AlignVCenter
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { ms.open = !ms.open; if (ms.open) ms.query = "" }
            }
        }

        Column {
            visible: ms.open
            width: ms.width
            spacing: 4

            Rectangle {
                width: parent.width
                height: 28
                radius: 6
                color: theme.normalFill
                border.width: 1
                border.color: theme.cardBorder
                TextInput {
                    id: msSearch
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    verticalAlignment: TextInput.AlignVCenter
                    color: theme.barText
                    font.family: theme.fontFamily
                    font.pixelSize: theme.fontSize
                    selectByMouse: true
                    clip: true
                    text: ms.query
                    onTextEdited: ms.query = text
                    Keys.onPressed: function (ev) {
                        if (ev.key === Qt.Key_V && (ev.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) {
                            msSearch.insert(Quickshell.clipboardText)
                            ev.accepted = true
                        }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 9
                    visible: msSearch.text === ""
                    text: ms.placeholderText
                    color: theme.textMuted
                    font.family: theme.fontFamily
                    font.pixelSize: theme.fontSize
                }
            }

            Text {
                visible: ms.filtered().length === 0
                text: ms.emptyText
                color: theme.textMuted
                font.family: theme.fontFamily
                font.pixelSize: theme.fontSize - 1
            }

            Flickable {
                width: ms.width
                height: Math.min(msList.implicitHeight, 220)
                contentWidth: width
                contentHeight: msList.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: msList
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: ms.filtered()
                        delegate: Rectangle {
                            id: msRow
                            required property var modelData
                            readonly property bool on: ms.values.indexOf(msRow.modelData.value) >= 0
                            width: msList.width
                            height: 27
                            radius: 5
                            color: msRow.on ? theme.accentSoft : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8
                                Rectangle {
                                    width: 13; height: 13; radius: 3
                                    color: msRow.on ? theme.accent : "transparent"
                                    border.width: 1
                                    border.color: msRow.on ? theme.accent : theme.cardBorder
                                    Layout.alignment: Qt.AlignVCenter
                                    Text {
                                        anchors.centerIn: parent
                                        visible: msRow.on
                                        text: "\uf00c"
                                        color: theme.barBackground
                                        font.family: theme.fontFamily
                                        font.pixelSize: 9
                                    }
                                }
                                Text {
                                    text: msRow.modelData.label || root.sbLabelShort(msRow.modelData.value)
                                    color: msRow.on ? theme.accent : theme.barText
                                    font.family: theme.fontFamily
                                    font.pixelSize: theme.fontSize
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Text {
                                    text: msRow.modelData.description || ""
                                    color: theme.textMuted
                                    font.family: theme.fontFamily
                                    font.pixelSize: theme.fontSize - 1
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ms.toggle(msRow.modelData.value)
                            }
                        }
                    }
                }
                WheelHandler {
                    onWheel: function (event) {
                        var max = Math.max(0, msList.implicitHeight - parent.height)
                        parent.contentY = Math.max(0, Math.min(max, parent.contentY - event.angleDelta.y))
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------- bar
    // ------------------------------------------------------------ bar layout
    // Plugins: which ones the bar shows, where, in what order, and their
    // options. Stored in ~/.config/auggbar/settings.json, reloaded live when
    // the file changes, and written back by the settings menus.
    //   widgets: [{ id, enabled, section, order, label, options: {...} }]
    // Sections: left, center-left, center (pinned to the middle),
    // center-right, right, system (inside the grouped card).
    readonly property string barSettingsPath: root.home + "/.config/auggbar/settings.json"
    readonly property var barWidgetFiles: ({
        launcher: "Launcher", weather: "Weather", workspaces: "Workspaces",
        title: "WindowTitle", cava: "Visualizer", power: "Power", clock: "Clock",
        nowplaying: "NowPlaying", scoreboard: "Scoreboard", display: "Display",
        separator: "Separator", system: "SystemGroup", netspeed: "NetSpeed",
        network: "Network", audio: "Audio", mic: "Mic", camera: "Camera", bluetooth: "Bluetooth",
        battery: "Battery", viking: "Viking", updater: "Updater", tray: "Tray"
    })
    readonly property var barLabels: ({
        launcher: "Launcher", weather: "Weather", workspaces: "Workspaces",
        title: "Window title", cava: "Visualizer", power: "Power", clock: "Clock",
        nowplaying: "Now playing", scoreboard: "Scoreboard", display: "Display",
        separator: "Divider", system: "System card", netspeed: "Network speed",
        network: "Wi-Fi", audio: "Audio", mic: "Microphone", camera: "Camera", bluetooth: "Bluetooth",
        battery: "Battery", viking: "Viking", updater: "Updater", tray: "Tray"
    })
    readonly property var barSections: [
        { value: "left",         label: "Left" },
        { value: "center-left",  label: "Left of clock" },
        { value: "center",       label: "Center" },
        { value: "center-right", label: "Right of clock" },
        { value: "right",        label: "Right" },
        { value: "system",       label: "System card" }
    ]
    readonly property var barDefaults: [
        { id: "launcher",   enabled: true, section: "left",         order: 0 },
        { id: "weather",    enabled: true, section: "left",         order: 1 },
        { id: "workspaces", enabled: true, section: "left",         order: 2 },
        { id: "title",      enabled: true, section: "left",         order: 3 },
        { id: "cava",       enabled: true, section: "center-left",  order: 0 },
        { id: "power",      enabled: true, section: "center-left",  order: 1 },
        { id: "clock",      enabled: true, section: "center",       order: 0 },
        { id: "nowplaying", enabled: true, section: "center-right", order: 0 },
        { id: "scoreboard", enabled: true, section: "right",        order: 0 },
        { id: "display",    enabled: true, section: "right",        order: 1 },
        { id: "separator",  enabled: true, section: "right",        order: 2 },
        { id: "system",     enabled: true, section: "right",        order: 3 },
        { id: "viking",     enabled: true, section: "right",        order: 4 },
        { id: "updater",    enabled: true, section: "right",        order: 5 },
        { id: "tray",       enabled: true, section: "right",        order: 6 },
        { id: "netspeed",   enabled: true, section: "system",       order: 0 },
        { id: "network",    enabled: true, section: "system",       order: 1 },
        { id: "audio",      enabled: true, section: "system",       order: 2 },
        { id: "mic",        enabled: true, section: "system",       order: 3 },
        { id: "camera",     enabled: true, section: "system",       order: 4 },
        { id: "bluetooth",  enabled: true, section: "system",       order: 5 },
        { id: "battery",    enabled: true, section: "system",       order: 6 }
    ]
    // Layout (which drives the Repeaters) and options are kept apart, so
    // changing an option never rebuilds the widgets. barWidgets stays empty
    // until settings.json is read, so widgets are only built once.
    property var barWidgets: []
    property var barOptions: ({})
    property string barLayoutKey: ""
    // id -> loaded widget item (filled by PluginSlot; last screen wins).
    property var barItems: ({})

    FileView {
        id: barSettingsFile
        path: root.barSettingsPath
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: root.loadBarSettings(text())
        onLoadFailed: root.applyBarSettings(root.barCopy(root.barDefaults), {})
    }
    function loadBarSettings(txt) {
        var j
        try { j = JSON.parse(txt) } catch (e) {
            console.warn("auggbar: settings.json is not valid JSON, keeping the current layout: " + e)
            return
        }
        var list = (j && Array.isArray(j.widgets)) ? j.widgets : []
        var dflt = {}
        root.barDefaults.forEach(function (d) { dflt[d.id] = d })
        var out = [], opts = {}, seen = {}
        list.forEach(function (w) {
            if (!w || !w.id || seen[w.id]) return
            if (!root.barWidgetFiles[w.id]) { console.warn("auggbar: unknown plugin id '" + w.id + "'"); return }
            seen[w.id] = true
            var d = dflt[w.id] || {}
            var sec = root.barSectionValid(w.section) ? w.section : (d.section || "right")
            if (w.id === "system" && sec === "system") sec = "right"
            out.push({
                id: w.id,
                enabled: w.enabled !== false,
                section: sec,
                order: (typeof w.order === "number") ? w.order : (d.order || 0)
            })
            if (w.options && typeof w.options === "object") opts[w.id] = w.options
        })
        // Plugins missing from the file still show up in the menu, switched off.
        root.barDefaults.forEach(function (d) {
            if (!seen[d.id]) out.push({ id: d.id, enabled: false, section: d.section, order: 99 })
        })
        root.applyBarSettings(out, opts)
    }
    function applyBarSettings(list, opts) {
        root.barOptions = opts
        var key = JSON.stringify(list)
        if (key !== root.barLayoutKey) {
            root.barLayoutKey = key
            root.barWidgets = list
        }
    }
    function barSectionValid(s) {
        for (var i = 0; i < root.barSections.length; i++)
            if (root.barSections[i].value === s) return true
        return false
    }
    function barSectionIndex(s) {
        for (var i = 0; i < root.barSections.length; i++)
            if (root.barSections[i].value === s) return i
        return 99
    }
    function barCopy(list) {
        return (list || root.barWidgets).map(function (w) { return Object.assign({}, w) })
    }
    // Every plugin, enabled or not, in section then bar order (for the menu).
    function barAll() {
        return root.barCopy().sort(function (a, b) {
            return (root.barSectionIndex(a.section) - root.barSectionIndex(b.section)) || (a.order - b.order)
        })
    }
    function barSection(name) {
        return root.barWidgets.filter(function (w) {
            return w.enabled !== false && w.section === name
        }).sort(function (a, b) { return a.order - b.order })
    }
    function barEntry(id) {
        for (var i = 0; i < root.barWidgets.length; i++)
            if (root.barWidgets[i].id === id) return root.barWidgets[i]
        return null
    }
    function barWidgetUrl(id) {
        return Qt.resolvedUrl("widgets/" + root.barWidgetFiles[id] + ".qml")
    }
    function barSave() {
        var out = root.barAll().map(function (w) {
            var e = { id: w.id, enabled: w.enabled !== false, section: w.section, order: w.order,
                      label: root.barLabels[w.id] || w.id }
            var o = root.barOptions[w.id]
            if (o && Object.keys(o).length > 0) e.options = o
            return e
        })
        barSettingsFile.setText(JSON.stringify({
            _help: "Bar plugins. Right-click or Alt+click empty bar space for the plugin menu, or a plugin for its settings. Each entry: enabled, section (left, center-left, center, center-right, right, system), order (low = further left), options.",
            widgets: out
        }, null, 2) + "\n")
    }
    function barCommit(list) {
        root.applyBarSettings(list, root.barOptions)
        root.barSave()
    }
    function barOpt(id, key, dflt) {
        var o = root.barOptions[id]
        return (o && o[key] !== undefined) ? o[key] : dflt
    }
    function barSetOpt(id, key, value) {
        var all = Object.assign({}, root.barOptions)
        all[id] = Object.assign({}, all[id] || {})
        all[id][key] = value
        root.barOptions = all
        root.barSave()
    }
    function barSetEnabled(id, on) {
        var l = root.barCopy()
        l.forEach(function (w) { if (w.id === id) w.enabled = on })
        root.barCommit(l)
    }
    function barMove(id, dir) {
        var l = root.barCopy()
        var me = l.find(function (w) { return w.id === id })
        if (!me) return
        var peers = l.filter(function (w) { return w.section === me.section })
                     .sort(function (a, b) { return a.order - b.order })
        var i = peers.indexOf(me), j = i + dir
        if (j < 0 || j >= peers.length) return
        peers.splice(i, 1)
        peers.splice(j, 0, me)
        peers.forEach(function (w, k) { w.order = k })
        root.barCommit(l)
    }
    function barSetSection(id, section) {
        if (id === "system" && section === "system") return
        var l = root.barCopy()
        var me = l.find(function (w) { return w.id === id })
        if (!me || me.section === section) return
        var max = -1
        l.forEach(function (w) { if (w.section === section && w.id !== id) max = Math.max(max, w.order) })
        me.section = section
        me.order = max + 1
        root.barCommit(l)
    }
    function barResetDefaults() {
        root.barOptions = ({})
        root.barCommit(root.barCopy(root.barDefaults))
    }

    // ---- settings menus ----
    property bool barSetOpen: false
    property real barSetX: 0
    property bool barResetArmed: false
    property bool pluginSetOpen: false
    property string pluginSetId: ""
    property real pluginSetX: 0

    function barItem(id) {
        var it = root.barItems[id]
        try { if (it && it.shell !== undefined) return it } catch (e) {}
        return null
    }
    function pluginSchema(id) {
        var it = root.barItem(id)
        return (it && it.settingsSchema) ? it.settingsSchema : []
    }
    function pluginAction(id, key) {
        var it = root.barItem(id)
        if (it && typeof it.settingsAction === "function") it.settingsAction(key)
    }
    function openBarSettings(x) {
        var was = root.barSetOpen
        root.closePanels()
        root.barSetX = x
        root.barResetArmed = false
        root.barSetOpen = !was
    }
    // Plugins with a settings panel of their own open it; the rest get the
    // generic plugin settings popup.
    function openPluginSettings(id, x) {
        var was = root.pluginSetOpen && root.pluginSetId === id
        root.closePanels()
        if (was) return
        var it = root.barItem(id)
        if (it && typeof it.openSettings === "function") { it.openSettings(); return }
        root.pluginSetId = id
        root.pluginSetX = (x !== undefined) ? x : root.barSetX
        root.pluginSetOpen = true
    }
    function pluginRangeOpts(s) {
        var out = [], step = s.step || 1
        for (var v = s.min; v <= s.max + 1e-9; v += step)
            out.push({ value: String(v), label: v + (s.suffix || "") })
        return out
    }

    // Small hooks the widget files call (they cannot reach ids in here).
    function volRefreshSoon() { volRefresh.restart() }
    function micProbeSoon() { micProbeTimer.restart() }

    component BarSection: RowLayout {
        id: sec
        property string section
        spacing: 6
        Repeater {
            model: root.barSection(sec.section)
            delegate: PluginSlot {
                required property var modelData
                Layout.alignment: Qt.AlignVCenter
                shell: root
                pluginId: modelData.id
                catchClicks: modelData.id !== "system"
            }
        }
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: barWin
            required property var modelData
            screen: modelData
            anchors { top: true; left: true; right: true }
            exclusiveZone: theme.barHeight
            implicitHeight: theme.barHeight
            color: theme.barBackground
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell-bar"

            // Subtle vertical sheen + accent hairline so the bar reads less flat.
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.06) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.28)
            }

            // Widgets come from ~/.config/auggbar/settings.json (see
            // barWidgets below). The clock section stays pinned to the centre;
            // center-left hangs off its left edge, center-right off its right.
            Item {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8

                // Empty bar space: right-click / Alt+click opens the plugin
                // menu. Plain left-clicks fall through.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: function (m) {
                        if (!(m.button === Qt.RightButton || (m.modifiers & Qt.AltModifier))) m.accepted = false
                    }
                    onClicked: function (m) { root.openBarSettings(m.x) }
                }

                BarSection {
                    section: "left"
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }
                BarSection {
                    id: centerSec
                    section: "center"
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                }
                BarSection {
                    section: "center-left"
                    anchors.right: centerSec.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                }
                BarSection {
                    section: "center-right"
                    anchors.left: centerSec.right
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                }
                BarSection {
                    section: "right"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // ---------------------------------------------------------- display popup
    PanelWindow {
        id: displayPopup
        visible: root.displayOpen
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true; right: true }
        margins { top: theme.barHeight + 6; right: 8 }
        implicitWidth: 388
        implicitHeight: dispCol.implicitHeight + 28
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        focusable: true
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay

        Rectangle {
            anchors.fill: parent
            radius: theme.popupRadius
            color: theme.barBackground
            border.width: 2
            border.color: theme.popupBorder

            Column {
                id: dispCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 10
                readonly property var sel: root.dispSelected()

                RowLayout {
                    width: parent.width
                    spacing: 8
                    Rectangle { width: 8; height: 8; radius: 4; color: theme.accent; Layout.alignment: Qt.AlignVCenter }
                    Text {
                        text: "DISPLAYS"
                        color: theme.barText
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                        font.letterSpacing: 1.5
                        font.bold: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root.dispDisplays().length + (root.dispHasPending() ? "  \u00b7  unsaved" : "")
                        color: root.dispHasPending() ? theme.urgent : theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize - 1
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                // Monitor selector chips.
                RowLayout {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: root.dispDisplays()
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool on: root.dispSelected() && modelData.name === root.dispSelected().name
                            implicitWidth: chipTxt.implicitWidth + 22
                            height: 26
                            radius: 7
                            color: on ? theme.accentSoft : theme.normalFill
                            border.width: 1
                            border.color: on ? theme.accent : theme.cardBorder
                            Text {
                                id: chipTxt
                                anchors.centerIn: parent
                                text: modelData.name
                                color: modelData.enabled ? (on ? theme.accent : theme.barText) : theme.textMuted
                                font.family: theme.fontFamily
                                font.pixelSize: theme.fontSize
                                font.strikeout: !modelData.enabled
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.dispSelect(modelData.name) }
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                // ---------------------------------------------------- arrange
                // Drag a display to move it; edges snap to neighbours. Applies
                // through the same revertable change flow as the controls below.
                Rectangle {
                    id: dispCanvas
                    width: parent.width
                    height: visible ? 178 : 0
                    // Show the layout whenever at least one monitor is
                    // recognised — >1 hid this whole screen on a single
                    // display, which is why it never appeared for you.
                    visible: dispCanvas.rects.length > 0
                    radius: theme.radius
                    color: theme.normalFill
                    border.width: 1
                    border.color: theme.cardBorder

                    readonly property var rects: root.dispLayoutRects()
                    readonly property var box: root.dispBounds(rects)
                    readonly property real padL: 16
                    readonly property real padT: 26
                    readonly property real padR: 16
                    readonly property real padB: 16
                    readonly property real fit: Math.max(0.01, Math.min((width - padL - padR) / box.w, (height - padT - padB) / box.h))
                    readonly property real originX: padL + (width - padL - padR - box.w * fit) / 2
                    readonly property real originY: padT + (height - padT - padB - box.h * fit) / 2

                    Text {
                        anchors { left: parent.left; top: parent.top; margins: 8 }
                        text: "DRAG TO ARRANGE"
                        color: theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize - 3
                        font.letterSpacing: 1
                    }
                    Text {
                        anchors { right: parent.right; top: parent.top; margins: 8 }
                        text: "edges snap"
                        color: theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize - 3
                    }

                    Repeater {
                        model: dispCanvas.rects
                        delegate: Item {
                            id: slot
                            required property var modelData
                            x: dispCanvas.originX + (modelData.x - dispCanvas.box.x) * dispCanvas.fit
                            y: dispCanvas.originY + (modelData.y - dispCanvas.box.y) * dispCanvas.fit
                            width: modelData.w * dispCanvas.fit
                            height: modelData.h * dispCanvas.fit
                            z: mouse.drag.active ? 10 : 1

                            // Drag moves the tile, so the slot's bindings survive.
                            Rectangle {
                                id: tile
                                width: parent.width
                                height: parent.height
                                radius: 6
                                color: slot.modelData.name === root.dispState.selected ? theme.accentSoft : theme.barBackground
                                border.width: slot.modelData.name === root.dispState.selected ? 2 : 1
                                border.color: slot.modelData.name === root.dispState.selected ? theme.accent : theme.cardBorder

                                Column {
                                    anchors.centerIn: parent
                                    width: Math.max(0, parent.width - 8)
                                    Text {
                                        width: parent.width
                                        text: slot.modelData.name
                                        color: theme.barText
                                        font.family: theme.fontFamily
                                        font.pixelSize: theme.fontSize - 1
                                        font.bold: true
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: slot.modelData.w + "\u00d7" + slot.modelData.h
                                        color: theme.textMuted
                                        font.family: theme.fontFamily
                                        font.pixelSize: theme.fontSize - 3
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: mouse
                                    anchors.fill: parent
                                    cursorShape: Qt.SizeAllCursor
                                    drag.target: tile
                                    drag.axis: Drag.XAndYAxis
                                    drag.threshold: 2
                                    onClicked: root.dispSelect(slot.modelData.name)
                                    onReleased: {
                                        var lx = slot.modelData.x + tile.x / dispCanvas.fit
                                        var ly = slot.modelData.y + tile.y / dispCanvas.fit
                                        tile.x = 0
                                        tile.y = 0
                                        if (Math.abs(lx - slot.modelData.x) + Math.abs(ly - slot.modelData.y) < 1) return
                                        root.dispMoveDisplay(slot.modelData.name, lx, ly)
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                // ---------------------------------------------------- controls
                GridLayout {
                    width: parent.width
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 8
                    visible: dispCol.sel !== null

                    // Resolution
                    Text { text: "RESOLUTION"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; Layout.alignment: Qt.AlignVCenter }
                    Stepper {
                        Layout.alignment: Qt.AlignRight
                        enabled: dispCol.sel && dispCol.sel.enabled
                        opacity: enabled ? 1 : 0.5
                        options: root.dispResolutions(dispCol.sel)
                        value: dispCol.sel ? (dispCol.sel.width + "x" + dispCol.sel.height) : ""
                        onPicked: function (v) { root.dispSetRes(dispCol.sel, v) }
                    }

                    // Refresh
                    Text { text: "REFRESH RATE"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; Layout.alignment: Qt.AlignVCenter }
                    Stepper {
                        Layout.alignment: Qt.AlignRight
                        enabled: dispCol.sel && dispCol.sel.enabled
                        opacity: enabled ? 1 : 0.5
                        options: root.dispRefreshes(dispCol.sel, dispCol.sel ? dispCol.sel.width : 0, dispCol.sel ? dispCol.sel.height : 0)
                        value: dispCol.sel ? Number(dispCol.sel.hz).toFixed(2) : ""
                        onPicked: function (v) { root.dispApply({ hz: parseFloat(v) }) }
                    }

                    // Scale
                    Text { text: "SCALE"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; Layout.alignment: Qt.AlignVCenter }
                    Stepper {
                        Layout.alignment: Qt.AlignRight
                        enabled: dispCol.sel && dispCol.sel.enabled
                        opacity: enabled ? 1 : 0.5
                        options: root.dispScales(dispCol.sel ? dispCol.sel.width : 0, dispCol.sel ? dispCol.sel.height : 0)
                        value: dispCol.sel ? String(dispCol.sel.scale) : ""
                        onPicked: function (v) { root.dispApply({ scale: v }) }
                    }

                    // Rotation
                    Text { text: "ROTATION"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; Layout.alignment: Qt.AlignVCenter }
                    Segmented {
                        Layout.alignment: Qt.AlignRight
                        enabled: dispCol.sel && dispCol.sel.enabled
                        opacity: enabled ? 1 : 0.5
                        options: [{ value: "0", label: "0\u00b0" }, { value: "1", label: "90\u00b0" }, { value: "2", label: "180\u00b0" }, { value: "3", label: "270\u00b0" }]
                        value: dispCol.sel ? String(dispCol.sel.transform) : "0"
                        onPicked: function (v) { root.dispApply({ transform: parseInt(v) }) }
                    }

                    // VRR
                    Text { text: "VRR"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; Layout.alignment: Qt.AlignVCenter }
                    Stepper {
                        Layout.alignment: Qt.AlignRight
                        enabled: dispCol.sel && dispCol.sel.enabled
                        opacity: enabled ? 1 : 0.5
                        options: [{ value: "0", label: "Off" }, { value: "1", label: "On" }, { value: "2", label: "Fullscreen" }]
                        value: dispCol.sel ? String(dispCol.sel.vrr) : "0"
                        onPicked: function (v) { root.dispApply({ vrr: parseInt(v) }) }
                    }

                    // Mirror
                    Text { text: "MIRROR"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; Layout.alignment: Qt.AlignVCenter }
                    Stepper {
                        Layout.alignment: Qt.AlignRight
                        enabled: dispCol.sel && dispCol.sel.enabled
                        opacity: enabled ? 1 : 0.5
                        options: root.dispMirrors(dispCol.sel)
                        value: dispCol.sel ? dispCol.sel.mirrorOf : ""
                        onPicked: function (v) { root.dispApply({ mirror: v }) }
                    }

                    // HDR
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 6
                        Text { text: "HDR"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1 }
                        Text { text: "\u00b7 10-bit"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 2 }
                    }
                    Toggle {
                        Layout.alignment: Qt.AlignRight
                        on: dispCol.sel ? !!dispCol.sel.hdr : false
                        onToggled: function (v) { root.dispApply({ hdr: v }) }
                    }

                    // Position
                    Text { text: "POSITION"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; Layout.alignment: Qt.AlignVCenter }
                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 6
                        Btn { glyph: "\uf060"; glyphSize: 12; hPad: 6; enabled: dispCol.sel && dispCol.sel.enabled; opacity: enabled ? 1 : 0.5; onClicked: root.dispSetPos(dispCol.sel, "x", -40) }
                        Text {
                            text: dispCol.sel ? (dispCol.sel.x + ", " + dispCol.sel.y) : ""
                            color: theme.barText
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize
                            horizontalAlignment: Text.AlignHCenter
                            width: 84
                        }
                        Btn { glyph: "\uf061"; glyphSize: 12; hPad: 6; enabled: dispCol.sel && dispCol.sel.enabled; opacity: enabled ? 1 : 0.5; onClicked: root.dispSetPos(dispCol.sel, "x", 40) }
                        Btn { glyph: "\uf062"; glyphSize: 12; hPad: 6; enabled: dispCol.sel && dispCol.sel.enabled; opacity: enabled ? 1 : 0.5; onClicked: root.dispSetPos(dispCol.sel, "y", -40) }
                        Btn { glyph: "\uf063"; glyphSize: 12; hPad: 6; enabled: dispCol.sel && dispCol.sel.enabled; opacity: enabled ? 1 : 0.5; onClicked: root.dispSetPos(dispCol.sel, "y", 40) }
                    }

                    // Brightness
                    Text { text: "BRIGHTNESS"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; Layout.alignment: Qt.AlignVCenter }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignRight
                        spacing: 8
                        Slider {
                            Layout.fillWidth: true
                            value: root.brightness
                            onMoved: function (v) { root.setBrightnessAbs(v) }
                        }
                        Text {
                            text: root.brightness + "%"
                            color: theme.accent
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: 42
                        }
                    }
                    Text {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignRight
                        text: root.brightnessName(root.brightness).toUpperCase()
                        color: theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize - 2
                        font.letterSpacing: 1
                    }
                }

                // -------------------------------------------- enable + auggment
                RowLayout {
                    width: parent.width
                    visible: dispCol.sel !== null
                    spacing: 8
                    Text {
                        text: "ENABLED"
                        color: theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize - 1
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    Toggle {
                        Layout.alignment: Qt.AlignVCenter
                        on: dispCol.sel ? !!dispCol.sel.enabled : false
                        onToggled: function (v) { root.dispToggleEnabled(dispCol.sel) }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                Text {
                    text: "AUGGMENT"
                    color: theme.barText
                    font.family: theme.fontFamily
                    font.pixelSize: theme.fontSize
                    font.letterSpacing: 1.5
                    font.bold: true
                }

                GridLayout {
                    width: parent.width
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 8

                    Text { text: "BACKGROUND"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; Layout.alignment: Qt.AlignVCenter }
                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 6
                        Stepper {
                            options: root.auggTimeOpts(root.auggBgIntervals)
                            value: String(root.auggBgIndex)
                            onPicked: function (v) { root.auggSetBg(parseInt(v)) }
                        }
                        Btn { glyph: "\uf021"; glyphSize: 12; hPad: 6; onClicked: root.auggRotateNow() }
                    }

                    Text { text: "SCREENSAVER"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; Layout.alignment: Qt.AlignVCenter }
                    Stepper {
                        Layout.alignment: Qt.AlignRight
                        options: root.auggTimeOpts(root.auggSsTimes)
                        value: String(root.auggSsIndex)
                        onPicked: function (v) { root.auggSetSs(parseInt(v)) }
                    }

                    Text { text: "SCREEN OFF"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; Layout.alignment: Qt.AlignVCenter }
                    Stepper {
                        Layout.alignment: Qt.AlignRight
                        options: root.auggTimeOpts(root.auggScreenOffTimes)
                        value: String(root.auggScreenOffIndex)
                        onPicked: function (v) { root.auggSetScreenOff(parseInt(v)) }
                    }

                    Text { text: "AUTO COLOR MATCH"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; Layout.alignment: Qt.AlignVCenter }
                    Toggle {
                        Layout.alignment: Qt.AlignRight
                        on: root.auggAutoColor
                        onToggled: function (v) { root.auggSetAutoColor(v) }
                    }

                    Text { text: "DARK MODE"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; Layout.alignment: Qt.AlignVCenter }
                    Toggle {
                        Layout.alignment: Qt.AlignRight
                        on: root.auggDarkMode
                        onToggled: function (v) { root.auggSetDarkMode(v) }
                    }
                }

                // --------------------------------------------------- apply bar
                Rectangle {
                    width: parent.width
                    height: 1
                    color: theme.cardBorder
                }

                Rectangle {
                    visible: root.dispHasPending()
                    width: parent.width
                    radius: theme.radius
                    color: Qt.rgba(theme.urgent.r, theme.urgent.g, theme.urgent.b, 0.14)
                    border.width: 1
                    border.color: Qt.rgba(theme.urgent.r, theme.urgent.g, theme.urgent.b, 0.45)
                    implicitHeight: applyRow.implicitHeight + 20
                    RowLayout {
                        id: applyRow
                        anchors.centerIn: parent
                        width: parent.width - 24
                        spacing: 8
                        Text {
                            text: "Keep these settings? Reverting in " + root.dispSeconds + "s"
                            color: theme.barText
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Btn { label: "Keep"; bgColor: theme.accent; fg: theme.barBackground; onClicked: root.dispKeep() }
                        Btn { label: "Revert"; borderColor: theme.urgent; fg: theme.urgent; onClicked: root.dispRevert() }
                    }
                }

                RowLayout {
                    width: parent.width
                    spacing: 8
                    Btn {
                        Layout.fillWidth: true
                        glyph: "\uf021"; glyphSize: 13
                        label: "Re-probe displays"
                        onClicked: root.refreshDisplay()
                    }
                    Btn {
                        glyph: "\uf2ed"; glyphSize: 13
                        label: "Forget saved layout"
                        onClicked: root.dispForget()
                    }
                }
            }
        }
    }

    // ------------------------------------------------------- scoreboard popup
    PanelWindow {
        id: sbPopup
        visible: root.sbOpen
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true; right: true }
        margins { top: theme.barHeight + 6; right: 8 }
        implicitWidth: 388
        implicitHeight: sbCol.implicitHeight + 28
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        focusable: true
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay

        Rectangle {
            anchors.fill: parent
            radius: theme.popupRadius
            color: theme.barBackground
            border.width: 2
            border.color: theme.popupBorder

            Column {
                id: sbCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 12

                RowLayout {
                    width: parent.width
                    spacing: 8
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: root.sbColor(root.sbCurrent())
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text {
                        text: root.sbCurrent() ? (root.sbCat(root.sbCurrent()).toUpperCase() + (root.sbCurrent().league_label ? "  \u00b7  " + root.sbCurrent().league_label : "")) : "SCOREBOARD"
                        color: theme.barText
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                        font.letterSpacing: 1.5
                        font.bold: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: (root.sbTotal > 0 ? (root.sbIndex + 1) : 0) + " / " + root.sbTotal
                        color: theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize - 1
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                Rectangle {
                    width: parent.width
                    radius: theme.radius
                    color: theme.cardFill
                    border.width: 1
                    border.color: theme.cardBorder
                    height: matchCol.implicitHeight + 24

                    Column {
                        id: matchCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 12

                        Item {
                            width: matchCol.width
                            height: vsRow.implicitHeight
                            visible: root.sbCurrent() && root.sbCurrent().kind === "game"

                            RowLayout {
                                id: vsRow
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 14

                                TeamCol {
                                    Layout.alignment: Qt.AlignVCenter
                                    team: (root.sbCurrent() && root.sbCurrent().away) ? root.sbCurrent().away : ({})
                                    showScore: root.sbHasScore(root.sbCurrent())
                                }
                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "VS"
                                    color: theme.textMuted
                                    font.family: theme.fontFamily
                                    font.pixelSize: theme.fontSize + 2
                                    font.bold: true
                                }
                                TeamCol {
                                    Layout.alignment: Qt.AlignVCenter
                                    team: (root.sbCurrent() && root.sbCurrent().home) ? root.sbCurrent().home : ({})
                                    showScore: root.sbHasScore(root.sbCurrent())
                                }
                            }
                        }

                        Text {
                            visible: root.sbCurrent() && root.sbCurrent().kind !== "game"
                            width: matchCol.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: root.sbLabel(root.sbCurrent())
                            color: theme.barText
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize + 2
                        }

                        Text {
                            width: matchCol.width
                            horizontalAlignment: Text.AlignHCenter
                            text: root.sbStatus(root.sbCurrent())
                            color: root.sbColor(root.sbCurrent())
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize
                        }
                    }
                }

                RowLayout {
                    width: parent.width
                    spacing: 8
                    Btn { glyph: "\uf104"; glyphSize: 15; onClicked: root.sbStep(-1) }
                    Btn {
                        Layout.fillWidth: true
                        glyph: "\uf021"; glyphSize: 14
                        label: "Refresh"
                        onClicked: if (!sbProc.running) sbProc.running = true
                    }
                    Btn { glyph: "\uf105"; glyphSize: 15; onClicked: root.sbStep(1) }
                    Btn { glyph: "\uf013"; glyphSize: 14; highlight: root.sbSetOpen; onClicked: root.openSbSet() }
                }
            }
        }
    }

    // ------------------------------------------------- scoreboard settings
    PanelWindow {
        id: sbSetPopup
        visible: root.sbSetOpen
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true; right: true }
        margins { top: theme.barHeight + 6; right: 8 }
        implicitWidth: 440
        implicitHeight: Math.min(sbSetCol.implicitHeight + 28, 820)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        focusable: true
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay

        Rectangle {
            anchors.fill: parent
            radius: theme.popupRadius
            color: theme.barBackground
            border.width: 2
            border.color: theme.popupBorder

            Flickable {
                id: sbSetFlick
                anchors.fill: parent
                anchors.margins: 14
                contentWidth: width
                contentHeight: sbSetCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: sbSetCol
                    width: sbSetFlick.width
                    spacing: 12

                    RowLayout {
                        width: parent.width
                        spacing: 8
                        Rectangle { width: 8; height: 8; radius: 4; color: theme.accent; Layout.alignment: Qt.AlignVCenter }
                        Text {
                            text: "SCOREBOARD SETTINGS"
                            color: theme.barText
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize
                            font.letterSpacing: 1.5
                            font.bold: true
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Item { Layout.fillWidth: true }
                        Btn { glyph: "\uf00d"; glyphSize: 12; hPad: 6; onClicked: root.sbSetOpen = false }
                    }

                    Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                    // ------------------------------------------------ basics
                    Text { text: "BAR POSITION"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1 }
                    Segmented {
                        options: [{ value: "left", label: "Left" }, { value: "center", label: "Center" }, { value: "right", label: "Right" }]
                        value: root.cfgVal("position", "right")
                        onPicked: function (v) { root.saveSb({ position: v, positioned: true }) }
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 8
                        Text { text: "BAR LOGOS"; color: theme.barText; font.family: theme.fontFamily; font.pixelSize: theme.fontSize; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
                        Toggle { Layout.alignment: Qt.AlignVCenter; on: !!root.cfgVal("bar_logos", true); onToggled: function (v) { root.saveSb({ bar_logos: v }) } }
                    }
                    RowLayout {
                        width: parent.width
                        spacing: 8
                        Text { text: "LEAGUE LAST IN CYCLE"; color: theme.barText; font.family: theme.fontFamily; font.pixelSize: theme.fontSize; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
                        Toggle { Layout.alignment: Qt.AlignVCenter; on: !!root.cfgVal("league_in_cycle", false); onToggled: function (v) { root.saveSb({ league_in_cycle: v }) } }
                    }

                    GridLayout {
                        width: parent.width
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 8
                        Text { text: "DAYS AHEAD"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; Layout.alignment: Qt.AlignVCenter }
                        Stepper {
                            Layout.alignment: Qt.AlignRight
                            options: root.numberOpts(0, 30)
                            value: String(root.cfgVal("days_ahead", 7))
                            onPicked: function (v) { root.saveSb({ days_ahead: parseInt(v) }) }
                        }
                        Text { text: "DAYS BACK"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; Layout.alignment: Qt.AlignVCenter }
                        Stepper {
                            Layout.alignment: Qt.AlignRight
                            options: root.numberOpts(0, 14)
                            value: String(root.cfgVal("days_back", 1))
                            onPicked: function (v) { root.saveSb({ days_back: parseInt(v) }) }
                        }
                        Text { text: "ROTATE"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; Layout.alignment: Qt.AlignVCenter }
                        Stepper {
                            Layout.alignment: Qt.AlignRight
                            options: root.listOpts([2, 3, 4, 5, 6, 8, 10, 15, 20, 30, 45, 60], "s")
                            value: String(root.cfgVal("rotate_seconds", 6))
                            onPicked: function (v) { root.saveSb({ rotate_seconds: parseInt(v) }) }
                        }
                        Text { text: "REFRESH"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; Layout.alignment: Qt.AlignVCenter }
                        Stepper {
                            Layout.alignment: Qt.AlignRight
                            options: root.listOpts([15, 30, 45, 60, 90, 120, 180, 300, 600], "s")
                            value: String(root.cfgVal("refresh_seconds", 60))
                            onPicked: function (v) { root.saveSb({ refresh_seconds: parseInt(v) }) }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                    // ----------------------------------------------- leagues
                    Text { text: "LEAGUES"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; font.letterSpacing: 1 }

                    Repeater {
                        model: root.sbGroups
                        delegate: Column {
                            required property var modelData
                            width: sbSetCol.width
                            spacing: 4
                            Text {
                                text: modelData.toUpperCase()
                                color: theme.textMuted
                                font.family: theme.fontFamily
                                font.pixelSize: theme.fontSize - 2
                                font.letterSpacing: 1
                            }
                            Flow {
                                width: parent.width
                                spacing: 5
                                Repeater {
                                    model: root.sbLeaguesIn(modelData)
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool on: root.sbLeagueOn(modelData.path)
                                        implicitWidth: lbTxt.implicitWidth + 16
                                        height: 22
                                        radius: 6
                                        color: on ? theme.accentSoft : theme.normalFill
                                        border.width: 1
                                        border.color: on ? theme.accent : theme.cardBorder
                                        Text {
                                            id: lbTxt
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            color: on ? theme.accent : theme.textMuted
                                            font.family: theme.fontFamily
                                            font.pixelSize: theme.fontSize - 1
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.sbToggleLeague(modelData.path)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                    // ------------------------------------------- favourites
                    RowLayout {
                        width: parent.width
                        spacing: 8
                        Text { text: "FAVOURITE TEAMS"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; font.letterSpacing: 1; Layout.alignment: Qt.AlignVCenter }
                        Item { Layout.fillWidth: true }
                        Btn {
                            visible: root.sbFavCount() > 0
                            glyph: "\uf2ed"; glyphSize: 12; hPad: 8
                            label: "Clear all"
                            onClicked: root.saveSb({ teams: [], days_ahead_teams: ({}) })
                        }
                    }

                    MultiSelect {
                        label: "Teams"
                        values: root.sbFavValues()
                        options: root.sbTeamOptions
                        placeholderText: "Search teams\u2026"
                        emptyText: (root.cfgVal("leagues", []).length === 0) ? "Pick leagues above first" : "No teams found"
                        noSelectionText: "None selected"
                        onChanged: function (v) { root.sbSetTeams(v) }
                    }

                    Text {
                        visible: root.sbTeamsLoading
                        text: "Loading teams\u2026"
                        color: theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                    }
                    Text {
                        visible: root.sbTeamsError && !root.sbTeamsLoading
                        width: sbSetCol.width
                        wrapMode: Text.WordWrap
                        text: "Could not load teams (pick leagues first, or check the network)."
                        color: theme.urgent
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                    }

                    // One row per favourite: colour, name, look-ahead window, remove.
                    Repeater {
                        model: root.sbFavTeams()
                        delegate: Column {
                            id: favRow
                            required property var modelData
                            readonly property string key: favRow.modelData.value
                            width: sbSetCol.width
                            spacing: 4

                            RowLayout {
                                width: parent.width
                                spacing: 8
                                // Click the swatch to edit this team's colour.
                                Rectangle {
                                    width: 18; height: 18; radius: 9
                                    color: root.sbTeamColor(favRow.key, root.sbTeamRealColor(favRow.key))
                                    border.width: 1
                                    border.color: root.sbColorEditKey === favRow.key ? theme.accent : theme.cardBorder
                                    Layout.alignment: Qt.AlignVCenter
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.sbColorEditKey = (root.sbColorEditKey === favRow.key ? "" : favRow.key)
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: favRow.modelData.label
                                    color: theme.barText
                                    font.family: theme.fontFamily
                                    font.pixelSize: theme.fontSize
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "ahead"
                                    color: theme.textMuted
                                    font.family: theme.fontFamily
                                    font.pixelSize: theme.fontSize - 2
                                }
                                Stepper {
                                    Layout.alignment: Qt.AlignVCenter
                                    options: root.numberOpts(0, 30)
                                    value: String(root.sbTeamAhead(favRow.key))
                                    onPicked: function (v) { root.sbSetTeamAhead(favRow.key, parseInt(v)) }
                                }
                                Btn {
                                    Layout.alignment: Qt.AlignVCenter
                                    glyph: "\uf2ed"; glyphSize: 12; hPad: 7
                                    onClicked: root.sbRemoveTeam(favRow.key)
                                }
                            }

                            // Inline colour editor for this favourite.
                            Column {
                                visible: root.sbColorEditKey === favRow.key
                                width: parent.width
                                spacing: 5

                                RowLayout {
                                    width: parent.width
                                    spacing: 8
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 26
                                        radius: 6
                                        color: theme.normalFill
                                        border.width: 1
                                        border.color: theme.cardBorder
                                        TextInput {
                                            id: teamHex
                                            anchors.fill: parent
                                            anchors.leftMargin: 7
                                            anchors.rightMargin: 7
                                            verticalAlignment: TextInput.AlignVCenter
                                            color: theme.barText
                                            font.family: theme.fontFamily
                                            font.pixelSize: theme.fontSize - 1
                                            selectByMouse: true
                                            clip: true
                                            text: (root.cfgVal("team_colors", ({}))[favRow.key]) || ""
                                            onEditingFinished: root.sbSetColorMap("team_colors", favRow.key, text)
                                            Keys.onPressed: function (ev) {
                                                if (ev.key === Qt.Key_V && (ev.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) {
                                                    teamHex.insert(Quickshell.clipboardText)
                                                    ev.accepted = true
                                                }
                                            }
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            anchors.leftMargin: 7
                                            visible: teamHex.text === ""
                                            text: "#RRGGBB"
                                            color: theme.textMuted
                                            font.family: theme.fontFamily
                                            font.pixelSize: theme.fontSize - 1
                                        }
                                    }
                                    Btn {
                                        Layout.alignment: Qt.AlignVCenter
                                        glyph: "\uf12d"; glyphSize: 12; hPad: 8
                                        label: "Default"
                                        onClicked: root.sbSetColorMap("team_colors", favRow.key, "")
                                    }
                                }

                                Flow {
                                    width: parent.width
                                    spacing: 5
                                    Repeater {
                                        model: root.sbColorPresets
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: 18; height: 18; radius: 9
                                            color: modelData
                                            border.width: 1
                                            border.color: theme.cardBorder
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: root.sbSetColorMap("team_colors", favRow.key, modelData)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                    // --------------------------------------------- colours
                    Text { text: "GAME STATE COLOURS"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1; font.letterSpacing: 1 }

                    Repeater {
                        model: root.sbColorRows()
                        delegate: RowLayout {
                            id: stateRow
                            required property var modelData
                            width: sbSetCol.width
                            spacing: 8
                            Text {
                                text: modelData.label
                                color: theme.barText
                                font.family: theme.fontFamily
                                font.pixelSize: theme.fontSize
                                Layout.preferredWidth: 76
                                Layout.alignment: Qt.AlignVCenter
                            }
                            Rectangle {
                                width: 18; height: 18; radius: 9
                                color: root.sbStateColor(stateRow.modelData.k)
                                border.width: 1
                                border.color: theme.cardBorder
                                Layout.alignment: Qt.AlignVCenter
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 5
                                Repeater {
                                    model: root.sbColorPresets
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: 16; height: 16; radius: 8
                                        color: modelData
                                        border.width: 1
                                        border.color: theme.cardBorder
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.sbSetStateColor(stateRow.modelData.k, modelData)
                                        }
                                    }
                                }
                                Rectangle {
                                    width: resetTxt.implicitWidth + 14
                                    height: 16
                                    radius: 5
                                    color: "transparent"
                                    border.width: 1
                                    border.color: theme.cardBorder
                                    Text {
                                        id: resetTxt
                                        anchors.centerIn: parent
                                        text: "default"
                                        color: theme.textMuted
                                        font.family: theme.fontFamily
                                        font.pixelSize: theme.fontSize - 3
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.sbSetStateColor(stateRow.modelData.k, "")
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                    RowLayout {
                        width: parent.width
                        spacing: 8
                        Btn {
                            Layout.fillWidth: true
                            glyph: "\uf021"; glyphSize: 13
                            label: "Refresh scores"
                            onClicked: { if (!sbProc.running) sbProc.running = true }
                        }
                        Btn {
                            Layout.fillWidth: true
                            glyph: "\uf00d"; glyphSize: 13
                            label: "Close"
                            onClicked: root.sbSetOpen = false
                        }
                    }
                }

                WheelHandler {
                    onWheel: function (event) {
                        var max = Math.max(0, sbSetFlick.contentHeight - sbSetFlick.height)
                        sbSetFlick.contentY = Math.max(0, Math.min(max, sbSetFlick.contentY - event.angleDelta.y))
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------ wifi popup
    PanelWindow {
        id: netPopup
        visible: root.netOpen
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true; right: true }
        margins { top: theme.barHeight + 6; right: 8 }
        implicitWidth: 384
        implicitHeight: Math.min(netCol.implicitHeight + 28, 720)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        focusable: true
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay

        Rectangle {
            anchors.fill: parent
            radius: theme.popupRadius
            color: theme.barBackground
            border.width: 2
            border.color: theme.popupBorder

            Flickable {
                id: netFlick
                anchors.fill: parent
                anchors.margins: 14
                contentWidth: width
                contentHeight: netCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: netCol
                    width: netFlick.width
                    spacing: 10

                    RowLayout {
                        width: parent.width
                        spacing: 8
                        Rectangle { width: 8; height: 8; radius: 4; color: theme.accent; Layout.alignment: Qt.AlignVCenter }
                        Text {
                            text: "WI-FI"
                            color: theme.barText
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize
                            font.letterSpacing: 1.5
                            font.bold: true
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Item { Layout.fillWidth: true }
                        Btn {
                            glyph: "\uf021"; glyphSize: 12; hPad: 6
                            label: root.wifiScanning ? "Scanning\u2026" : "Scan"
                            highlight: root.wifiScanning
                            onClicked: root.wifiScanNow()
                        }
                        Btn { glyph: "\uf00d"; glyphSize: 12; hPad: 6; onClicked: root.netOpen = false }
                    }

                    Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                    RowLayout {
                        width: parent.width
                        spacing: 8
                        Text {
                            text: "WI-FI RADIO"
                            color: theme.barText
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Text {
                            text: Networking.wifiEnabled ? "On" : "Off"
                            color: Networking.wifiEnabled ? theme.accent : theme.textMuted
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize - 1
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Toggle {
                            Layout.alignment: Qt.AlignVCenter
                            on: Networking.wifiEnabled
                            onToggled: function (v) { Networking.wifiEnabled = v; root.netRevision++ }
                        }
                    }

                    Text {
                        visible: !Networking.wifiHardwareEnabled
                        text: "Hardware switch is off"
                        color: theme.urgent
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize - 1
                    }

                    Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                    RowLayout {
                        width: parent.width
                        spacing: 8
                        Text {
                            text: "NETWORKS"
                            color: theme.textMuted
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize - 1
                            Layout.fillWidth: true
                        }
                        Text {
                            text: root.wifiConnectedName() !== "" ? ("Connected: " + root.wifiConnectedName()) : "Not connected"
                            color: root.wifiConnectedName() !== "" ? theme.accent : theme.textMuted
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize - 2
                            elide: Text.ElideRight
                            Layout.maximumWidth: 220
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    Text {
                        width: parent.width
                        visible: root.wifiNetworks().length === 0
                        text: Networking.wifiEnabled ? "Scanning\u2026" : "Wi-Fi is off"
                        color: theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize - 1
                    }

                    Repeater {
                        model: { root.netRevision; return root.wifiNetworks() }
                        delegate: Column {
                            required property var modelData
                            width: netCol.width
                            spacing: 6
                            readonly property bool open: root.wifiOpen(modelData)
                            readonly property bool prompt: root.wifiTarget !== null && root.wifiTarget.name === modelData.name

                            Rectangle {
                                width: parent.width
                                height: 36
                                radius: 8
                                color: modelData.connected ? theme.accentSoft
                                     : (netRowHover.hovered ? theme.hoverFill : theme.cardFill)
                                border.width: 1
                                border.color: modelData.connected ? theme.accent : theme.cardBorder
                                Behavior on color { ColorAnimation { duration: 120 } }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8
                                    Text {
                                        text: modelData.known ? "\uf023" : "\uf09c"
                                        color: theme.textMuted
                                        font.family: theme.fontFamily
                                        font.pixelSize: 11
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Text {
                                        text: modelData.name
                                        color: theme.barText
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        font.family: theme.fontFamily
                                        font.pixelSize: theme.fontSize
                                        font.bold: modelData.connected
                                    }
                                    Text {
                                        visible: modelData.stateChanging
                                        text: "\uf110"
                                        color: theme.accent
                                        font.family: theme.fontFamily
                                        font.pixelSize: 12
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Text {
                                        visible: modelData.connected && !modelData.stateChanging
                                        text: "\uf00c"
                                        color: theme.accent
                                        font.family: theme.fontFamily
                                        font.pixelSize: 12
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    // Band(s) this network broadcasts on, e.g. "2.4 · 5 GHz".
                                    Text {
                                        visible: !!modelData.bands && modelData.bands.length > 0
                                        text: visible ? modelData.bands.join(" \u00b7 ") + " GHz" : ""
                                        color: theme.textMuted
                                        opacity: 0.75
                                        font.family: theme.fontFamily
                                        font.pixelSize: theme.fontSize - 2
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Text {
                                        text: root.wifiPct(modelData) + "%"
                                        color: theme.textMuted
                                        font.family: theme.fontFamily
                                        font.pixelSize: theme.fontSize - 1
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }
                                HoverHandler { id: netRowHover }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.wifiPick(modelData)
                                }
                            }

                            RowLayout {
                                width: parent.width
                                spacing: 6
                                visible: parent.prompt
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    radius: 7
                                    color: theme.normalFill
                                    border.width: 1
                                    border.color: theme.accent
                                    TextInput {
                                        id: netPsk
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: theme.barText
                                        echoMode: TextInput.Password
                                        font.family: theme.fontFamily
                                        font.pixelSize: theme.fontSize
                                        selectByMouse: true
                                        focus: root.wifiTarget !== null && root.wifiTarget.name === modelData.name
                                        onTextChanged: root.wifiPsk = netPsk.text
                                        onAccepted: root.wifiSubmit()
                                        Keys.onEscapePressed: root.wifiCancel()
                                        Keys.onPressed: function (ev) {
                                            if (ev.key === Qt.Key_V && (ev.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) {
                                                netPsk.insert(Quickshell.clipboardText)
                                                ev.accepted = true
                                            }
                                        }
                                    }
                                }
                                Btn {
                                    glyph: "\uf00c"; glyphSize: 12; hPad: 8
                                    bgColor: theme.accent; glyphColor: theme.barBackground
                                    onClicked: root.wifiSubmit()
                                }
                                Btn { glyph: "\uf00d"; glyphSize: 12; hPad: 8; onClicked: root.wifiCancel() }
                            }
                        }
                    }
                }
            }
        }
    }

    // ----------------------------------------------------------- sound popup
    PanelWindow {
        id: sndPopup
        visible: root.sndOpen
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true; right: true }
        margins { top: theme.barHeight + 6; right: 8 }
        implicitWidth: 384
        implicitHeight: Math.min(sndCol.implicitHeight + 28, 720)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        focusable: true
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay

        Rectangle {
            anchors.fill: parent
            radius: theme.popupRadius
            color: theme.barBackground
            border.width: 2
            border.color: theme.popupBorder

            Flickable {
                id: sndFlick
                anchors.fill: parent
                anchors.margins: 14
                contentWidth: width
                contentHeight: sndCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: sndCol
                    width: sndFlick.width
                    spacing: 10

                    RowLayout {
                        width: parent.width
                        spacing: 8
                        Rectangle { width: 8; height: 8; radius: 4; color: theme.accent; Layout.alignment: Qt.AlignVCenter }
                        Text {
                            text: "SOUND"
                            color: theme.barText
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize
                            font.letterSpacing: 1.5
                            font.bold: true
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Item { Layout.fillWidth: true }
                        Btn { glyph: "\uf00d"; glyphSize: 12; hPad: 6; onClicked: root.sndOpen = false }
                    }

                    Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                    Text { text: "OUTPUT"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1 }
                    Repeater {
                        model: root.audioSinks()
                        delegate: AudioRow {
                            width: sndCol.width
                            node: modelData
                            isDefault: !!(modelData && modelData.default)
                            selectable: true
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                    Text { text: "INPUT"; color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize - 1 }
                    Repeater {
                        model: root.audioSources()
                        delegate: AudioRow {
                            width: sndCol.width
                            node: modelData
                            isDefault: !!(modelData && modelData.default)
                            selectable: true
                        }
                    }

                    Rectangle {
                        width: parent.width; height: 1; color: theme.cardBorder
                        visible: root.audioStreams().length > 0
                    }
                    Text {
                        visible: root.audioStreams().length > 0
                        text: "PLAYBACK"
                        color: theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize - 1
                    }
                    Repeater {
                        model: root.audioStreams()
                        delegate: AudioRow {
                            width: sndCol.width
                            node: modelData
                            isDefault: false
                            selectable: false
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                    RowLayout {
                        width: parent.width
                        spacing: 8
                        Text {
                            text: "EFFECTS"
                            color: theme.textMuted
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize - 1
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Text {
                            text: root.eeCurrent !== "" ? root.eeCurrent : "(none)"
                            color: theme.accent
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize - 1
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignRight
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Btn {
                            glyph: "\uf1de"; glyphSize: 12; hPad: 6
                            onClicked: root.run("easyeffects")
                        }
                        Btn {
                            glyph: root.eeOpen ? "\uf077" : "\uf078"; glyphSize: 12; hPad: 6
                            onClicked: root.eeOpen = !root.eeOpen
                        }
                    }
                    Flickable {
                        width: parent.width
                        visible: root.eeOpen
                        height: visible ? eeList.implicitHeight : 0
                        contentHeight: eeList.implicitHeight
                        interactive: false
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: eeList
                            width: parent.width
                            Repeater {
                                model: root.eePresets
                                delegate: Rectangle {
                                    required property string modelData
                                    width: eeList.width
                                    height: 26
                                    radius: 6
                                    color: modelData === root.eeCurrent ? theme.accentSoft
                                         : (eeHover.hovered ? theme.hoverFill : "transparent")
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Text {
                                        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                        width: parent.width - 16
                                        elide: Text.ElideRight
                                        text: modelData
                                        color: modelData === root.eeCurrent ? theme.accent : theme.barText
                                        font.family: theme.fontFamily
                                        font.pixelSize: theme.fontSize - 1
                                    }
                                    HoverHandler { id: eeHover }
                                    MouseArea {
                                        anchors.fill: parent
                                        preventStealing: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.eeLoad(modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- OSD (bottom-centre; volume / brightness / microphone) --------------
    PanelWindow {
        id: osdWin
        visible: root.osdVisible
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { bottom: true }
        margins { bottom: 72 }
        implicitWidth: 340
        implicitHeight: 68
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        focusable: false
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-osd"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // Fully click-through: the OSD pops up on keypress but must never steal a
        // click from whatever is beneath it. An empty Region = empty input region
        // (pixels still render; clicks fall through).
        mask: Region {}

        Rectangle {
            anchors.fill: parent
            radius: theme.popupRadius
            color: theme.barBackground
            border.width: 2
            border.color: theme.popupBorder

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 14

                Text {
                    text: root.osdGlyph()
                    color: root.osdAlarm() ? theme.urgent : theme.accent
                    font.family: theme.fontFamily
                    font.pixelSize: 24
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 7

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: root.osdTitle()
                            color: theme.textMuted
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize - 1
                            font.letterSpacing: 1.4
                            font.bold: true
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: root.osdText()
                            color: root.osdAlarm() ? theme.urgent : theme.barText
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize
                            font.bold: true
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 8
                        radius: 4
                        color: theme.normalFill
                        border.width: 1
                        border.color: theme.cardBorder

                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            anchors.margins: 1
                            width: Math.max(0, (parent.width - 2) * root.osdFill())
                            radius: 3
                            color: root.osdAlarm() ? theme.urgent : theme.accent
                            Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------ power menu
    PanelWindow {
        id: powerPopup
        visible: root.powerOpen
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true }
        margins { top: theme.barHeight + 6 }
        implicitWidth: 236
        implicitHeight: powerCol.implicitHeight + 28
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        focusable: true
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay

        Rectangle {
            anchors.fill: parent
            radius: theme.popupRadius
            color: theme.barBackground
            border.width: 2
            border.color: theme.popupBorder

            Column {
                id: powerCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 10

                RowLayout {
                    width: parent.width
                    spacing: 8
                    Rectangle { width: 8; height: 8; radius: 4; color: theme.accent; Layout.alignment: Qt.AlignVCenter }
                    Text {
                        text: "POWER"
                        color: theme.barText
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                        font.letterSpacing: 1.5
                        font.bold: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    Btn { glyph: "\uf00d"; glyphSize: 12; hPad: 6; onClicked: root.powerOpen = false }
                }

                Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                ColumnLayout {
                    width: parent.width
                    spacing: 6

                    Btn {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        glyph: "\uf021"; glyphSize: 14
                        label: "Reboot"
                        onClicked: root.powerAction("reboot")
                    }
                    Btn {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        glyph: "\uf01e"; glyphSize: 14
                        label: "Restart bar"
                        onClicked: root.powerAction("restart-bar")
                    }
                    Btn {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        glyph: "\uf011"; glyphSize: 14
                        label: "Shutdown"
                        onClicked: root.powerAction("poweroff")
                    }
                    Btn {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        glyph: "\uf186"; glyphSize: 14
                        label: "Sleep"
                        onClicked: root.powerAction("suspend")
                    }
                }
            }
        }
    }

    // ------------------------------------------------------- calendar popup
    // Month grid + the selected day's agenda, fed by auggment-calendar.
    // Left click on the clock opens it.
    PanelWindow {
        id: calPopup
        visible: root.calOpen
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true }
        margins { top: theme.barHeight + 6 }
        implicitWidth: 348
        implicitHeight: Math.min(calCol.implicitHeight + 28, 760)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        focusable: true
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay

        Rectangle {
            anchors.fill: parent
            radius: theme.popupRadius
            color: theme.barBackground
            border.width: 2
            border.color: theme.popupBorder

            Column {
                id: calCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 14
                spacing: 9

                RowLayout {
                    width: parent.width
                    spacing: 8
                    Rectangle { width: 8; height: 8; radius: 4; color: theme.accent; Layout.alignment: Qt.AlignVCenter }
                    Text {
                        text: "CALENDAR"
                        color: theme.barText
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                        font.letterSpacing: 1.5
                        font.bold: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    Btn { glyph: "\uf021"; glyphSize: 12; hPad: 6; onClicked: root.calRefresh(true) }
                    Btn { glyph: "\uf013"; glyphSize: 12; hPad: 6; onClicked: function () { root.calOpen = false; root.calOpenAuth() } }
                    Btn { glyph: "\uf00d"; glyphSize: 12; hPad: 6; onClicked: root.calOpen = false }
                }

                Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                // ------------------------------------------------ not linked yet
                Column {
                    width: parent.width
                    spacing: 8
                    visible: root.calLoaded && !root.calLinked
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "No calendar is linked yet. Right-click the clock (or use the button below) and paste a calendar's private iCal address — no sign-in, no password."
                        color: theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                    }
                    Btn {
                        glyph: "\uf067"; glyphSize: 12
                        label: "Add a calendar"
                        bgColor: theme.accentSoft
                        onClicked: function () { root.calOpen = false; root.calOpenAuth() }
                    }
                }

                // -------------------------------------------- grid + agenda
                Column {
                    width: parent.width
                    spacing: 9
                    visible: root.calLinked

                    RowLayout {
                        width: parent.width
                        spacing: 4
                        Btn { glyph: "\uf104"; glyphSize: 12; hPad: 8; onClicked: root.calShiftMonth(-1) }
                        Text {
                            Layout.fillWidth: true
                            text: root.calMonthLabel()
                            color: theme.barText
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize + 1
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Btn { label: "Today"; glyphSize: 11; hPad: 8; onClicked: root.calGoToday() }
                        Btn { glyph: "\uf105"; glyphSize: 12; hPad: 8; onClicked: root.calShiftMonth(1) }
                    }

                    Row {
                        spacing: 2
                        Repeater {
                            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                            delegate: Text {
                                required property var modelData
                                width: 44
                                text: modelData
                                color: theme.textMuted
                                font.family: theme.fontFamily
                                font.pixelSize: theme.fontSize - 2
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    Grid {
                        columns: 7
                        spacing: 2
                        Repeater {
                            model: root.calCells
                            delegate: Rectangle {
                                id: calCell
                                required property var modelData
                                property bool isSel: calCell.modelData.key === root.calSelKey
                                width: 44
                                height: 30
                                radius: 7
                                color: isSel ? theme.accentSoft : (cellHover.hovered ? theme.hoverFill : "transparent")
                                border.width: calCell.modelData.today ? 1 : 0
                                border.color: theme.accent
                                opacity: calCell.modelData.inMonth ? 1.0 : 0.32
                                Behavior on color { ColorAnimation { duration: 100 } }
                                HoverHandler { id: cellHover }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 3
                                    text: calCell.modelData.day
                                    color: calCell.modelData.today ? theme.accent : theme.barText
                                    font.family: theme.fontFamily
                                    font.pixelSize: theme.fontSize
                                    font.bold: calCell.modelData.today
                                }
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 3
                                    spacing: 2
                                    Repeater {
                                        model: calCell.modelData.dots
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: 4; height: 4; radius: 2
                                            color: modelData
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.calSelKey = calCell.modelData.key
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                    Text {
                        width: parent.width
                        text: root.calDayLabel(root.calSelKey).toUpperCase()
                        color: theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize - 2
                        font.letterSpacing: 1.2
                        elide: Text.ElideRight
                    }

                    Flickable {
                        id: calAgendaFlick
                        width: parent.width
                        height: Math.min(calAgendaCol.implicitHeight, 200)
                        contentHeight: calAgendaCol.implicitHeight
                        clip: true
                        interactive: contentHeight > height
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: calAgendaCol
                            width: calAgendaFlick.width
                            spacing: 5
                            Repeater {
                                model: root.calAgenda
                                delegate: Rectangle {
                                    id: calEventRow
                                    required property var modelData
                                    width: calAgendaCol.width
                                    height: 34
                                    radius: 8
                                    color: evHover.hovered ? theme.hoverFill : theme.cardFill
                                    border.width: 1
                                    border.color: theme.cardBorder
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8
                                        Rectangle {
                                            width: 3; height: 22; radius: 2
                                            color: calEventRow.modelData.color
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Text {
                                            Layout.preferredWidth: 46
                                            Layout.alignment: Qt.AlignVCenter
                                            text: calEventRow.modelData.allday ? "ALL DAY" : calEventRow.modelData.t0
                                            color: theme.textMuted
                                            font.family: theme.fontFamily
                                            font.pixelSize: theme.fontSize - 1
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 1
                                            Text {
                                                Layout.fillWidth: true
                                                text: calEventRow.modelData.title
                                                color: theme.barText
                                                font.family: theme.fontFamily
                                                font.pixelSize: theme.fontSize
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                visible: String(calEventRow.modelData.location || "") !== ""
                                                text: calEventRow.modelData.location
                                                color: theme.textMuted
                                                font.family: theme.fontFamily
                                                font.pixelSize: theme.fontSize - 2
                                                elide: Text.ElideRight
                                            }
                                        }
                                        Text {
                                            Layout.maximumWidth: 96
                                            Layout.alignment: Qt.AlignVCenter
                                            text: calEventRow.modelData.calName
                                            color: theme.textMuted
                                            font.family: theme.fontFamily
                                            font.pixelSize: theme.fontSize - 2
                                            elide: Text.ElideRight
                                        }
                                    }
                                    HoverHandler { id: evHover }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var u = String(calEventRow.modelData.url || "")
                                            if (u !== "") Quickshell.execDetached(["xdg-open", u])
                                        }
                                    }
                                }
                            }
                            Text {
                                width: parent.width
                                visible: root.calAgenda.length === 0
                                text: "Nothing on this day."
                                color: theme.textMuted
                                font.family: theme.fontFamily
                                font.pixelSize: theme.fontSize
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        visible: root.calErr !== "" || root.calNotice !== ""
                        text: root.calErr !== "" ? root.calErr : root.calNotice
                        color: root.calErr !== "" ? theme.urgent : theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize - 2
                    }
                }
            }
        }
    }

    // ----------------------------------------------- calendar settings popup
    // Right-click (or alt+left click) on the clock. Paste a calendar's private
    // iCal address — read-only, no sign-in, no 2FA — and switch each calendar
    // on or off.
    PanelWindow {
        id: calAuthPopup
        visible: root.calAuthOpen
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true }
        margins { top: theme.barHeight + 6 }
        implicitWidth: 452
        implicitHeight: Math.min(calAuthCol.implicitHeight + 28, 780)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        focusable: true
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay

        Rectangle {
            anchors.fill: parent
            radius: theme.popupRadius
            color: theme.barBackground
            border.width: 2
            border.color: theme.popupBorder

            Flickable {
                id: calAuthFlick
                anchors.fill: parent
                anchors.margins: 14
                contentHeight: calAuthCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: calAuthCol
                    width: calAuthFlick.width
                    spacing: 9

                    RowLayout {
                        width: parent.width
                        spacing: 8
                        Rectangle { width: 8; height: 8; radius: 4; color: theme.accent; Layout.alignment: Qt.AlignVCenter }
                        Text {
                            text: "CALENDARS"
                            color: theme.barText
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize
                            font.letterSpacing: 1.5
                            font.bold: true
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Item { Layout.fillWidth: true }
                        Btn {
                            glyph: "\uf021"; glyphSize: 12; hPad: 6
                            onClicked: function () { root.calLoadCalendars(true); root.calRefresh(true) }
                        }
                        Btn { glyph: "\uf00d"; glyphSize: 12; hPad: 6; onClicked: root.calAuthOpen = false }
                    }

                    Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Paste a calendar's private iCal address. It is read-only and needs no sign-in, password or two-factor step."
                        color: theme.barText
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize - 1
                    }

                    // ------------------------------------------- add a calendar
                    Rectangle {
                        width: parent.width
                        height: 32
                        radius: 7
                        color: theme.normalFill
                        border.width: 1
                        border.color: calUrlField.activeFocus ? theme.accent : theme.cardBorder
                        TextInput {
                            id: calUrlField
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 9
                            verticalAlignment: TextInput.AlignVCenter
                            color: theme.barText
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize - 1
                            selectByMouse: true
                            clip: true
                            text: root.calUrl
                            onTextEdited: root.calUrl = text
                            onAccepted: root.calAddFeed()
                            Keys.onPressed: function (ev) {
                                if (ev.key === Qt.Key_V && (ev.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) {
                                    calUrlField.insert(Quickshell.clipboardText)
                                    ev.accepted = true
                                }
                            }
                        }
                    }
                    RowLayout {
                        width: parent.width
                        spacing: 8
                        Btn {
                            glyph: "\uf067"; glyphSize: 12
                            label: "Add calendar"
                            bgColor: theme.accentSoft
                            onClicked: root.calAddFeed()
                        }
                        Btn {
                            visible: root.calUrl !== ""
                            label: "Clear"
                            onClicked: root.calUrl = ""
                        }
                        Item { Layout.fillWidth: true }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize - 2
                        text: "Google Calendar: Settings \u2192 pick the calendar \u2192 \u201cSecret address in iCal format\u201d. " +
                              "It looks like calendar.google.com/calendar/ical/\u2026/basic.ics. " +
                              "Every calendar and every Google account has its own address, so add as many as you like."
                    }

                    Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                    // ------------------------------------------- linked list
                    Text {
                        text: "CALENDARS SHOWN IN THE BAR"
                        color: theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize - 2
                        font.letterSpacing: 1.2
                    }
                    Repeater {
                        model: root.calCalendars
                        delegate: Rectangle {
                            id: calCalRow
                            required property var modelData
                            width: calAuthCol.width
                            height: 30
                            radius: 7
                            color: "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 2
                                anchors.rightMargin: 2
                                spacing: 8
                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    color: calCalRow.modelData.color
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: calCalRow.modelData.summary
                                    color: theme.barText
                                    font.family: theme.fontFamily
                                    font.pixelSize: theme.fontSize
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.maximumWidth: 110
                                    text: calCalRow.modelData.account === "ical" ? "iCal" : calCalRow.modelData.account
                                    color: theme.textMuted
                                    font.family: theme.fontFamily
                                    font.pixelSize: theme.fontSize - 2
                                    elide: Text.ElideRight
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Toggle {
                                    Layout.alignment: Qt.AlignVCenter
                                    on: !!calCalRow.modelData.enabled
                                    onToggled: function () { root.calToggleCal(calCalRow.modelData.account, calCalRow.modelData.id) }
                                }
                                Btn {
                                    glyph: "\uf1f8"; glyphSize: 11; hPad: 6
                                    visible: calCalRow.modelData.kind === "feed"
                                    onClicked: root.calRemoveFeed(calCalRow.modelData.id)
                                }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        visible: root.calCalendars.length === 0
                        text: root.calLoaded ? "Nothing added yet — paste an address above." : "Loading\u2026"
                        color: theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        visible: root.calAuthErr !== "" || root.calStatusMsg !== ""
                        text: root.calAuthErr !== "" ? root.calAuthErr : root.calStatusMsg
                        color: root.calAuthErr !== "" ? theme.urgent : theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize - 2
                    }
                }
                WheelHandler {
                    onWheel: function (event) {
                        var max = Math.max(0, calAuthFlick.contentHeight - calAuthFlick.height)
                        calAuthFlick.contentY = Math.max(0, Math.min(max, calAuthFlick.contentY - event.angleDelta.y))
                    }
                }
            }
        }
    }

    // ------------------------------------------------------ weather popups
    // Left click: next 5 hours. Right click: set the location.
    PanelWindow {
        id: wxPopup
        visible: root.wxOpen
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true; left: true }
        margins { top: theme.barHeight + 6; left: 8 }
        implicitWidth: 286
        implicitHeight: Math.min(wxCol.implicitHeight + 28, 660)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        focusable: true
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay

        Rectangle {
            anchors.fill: parent
            radius: theme.popupRadius
            color: theme.barBackground
            border.width: 2
            border.color: theme.popupBorder

            Column {
                id: wxCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    width: parent.width
                    spacing: 8
                    Rectangle { width: 8; height: 8; radius: 4; color: theme.accent; Layout.alignment: Qt.AlignVCenter }
                    Text {
                        text: "WEATHER"
                        color: theme.barText
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                        font.letterSpacing: 1.5
                        font.bold: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    Btn { glyph: "\uf021"; glyphSize: 12; hPad: 6; onClicked: root.wxRefresh() }
                    Btn { glyph: "\uf00d"; glyphSize: 12; hPad: 6; onClicked: root.wxOpen = false }
                }

                Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                RowLayout {
                    width: parent.width
                    spacing: 12
                    Text {
                        text: root.wxIcon
                        color: theme.accent
                        font.family: theme.fontFamily
                        font.pixelSize: 36
                        Layout.alignment: Qt.AlignVCenter
                    }
                    ColumnLayout {
                        spacing: 1
                        Text {
                            text: root.wxTemp
                            color: theme.barText
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize + 10
                            font.bold: true
                        }
                        Text {
                            text: root.wxCond
                            color: theme.textMuted
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize
                        }
                        Text {
                            text: root.wxPlace
                            color: theme.textMuted
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize - 1
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                Text {
                    text: "NEXT 5 HOURS"
                    color: theme.textMuted
                    font.family: theme.fontFamily
                    font.pixelSize: theme.fontSize - 1
                    font.letterSpacing: 1.0
                }

                Column {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: root.wxHours
                        delegate: Rectangle {
                            required property var modelData
                            width: wxCol.width
                            height: 30
                            radius: 7
                            color: wxHourHover.hovered ? theme.hoverFill : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8
                                Text {
                                    text: modelData.time
                                    color: theme.textMuted
                                    font.family: theme.fontFamily
                                    font.pixelSize: theme.fontSize
                                    Layout.preferredWidth: 64
                                }
                                Text {
                                    text: modelData.icon
                                    color: theme.accent
                                    font.family: theme.fontFamily
                                    font.pixelSize: 16
                                    Layout.preferredWidth: 22
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                Text {
                                    text: modelData.temp
                                    color: theme.barText
                                    font.family: theme.fontFamily
                                    font.pixelSize: theme.fontSize
                                    Layout.fillWidth: true
                                }
                            }
                            HoverHandler { id: wxHourHover }
                        }
                    }
                    Text {
                        visible: root.wxHours.length === 0
                        text: "Forecast unavailable"
                        color: theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                    }
                }
            }
        }
    }

    PanelWindow {
        id: wxSetPopup
        visible: root.wxSetOpen
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true; left: true }
        margins { top: theme.barHeight + 6; left: 8 }
        implicitWidth: 306
        implicitHeight: wxSetCol.implicitHeight + 28
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        focusable: true
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay

        Rectangle {
            anchors.fill: parent
            radius: theme.popupRadius
            color: theme.barBackground
            border.width: 2
            border.color: theme.popupBorder

            Column {
                id: wxSetCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    width: parent.width
                    spacing: 8
                    Rectangle { width: 8; height: 8; radius: 4; color: theme.accent; Layout.alignment: Qt.AlignVCenter }
                    Text {
                        text: "LOCATION"
                        color: theme.barText
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                        font.letterSpacing: 1.5
                        font.bold: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    Btn { glyph: "\uf00d"; glyphSize: 12; hPad: 6; onClicked: root.wxSetOpen = false }
                }

                Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                Text {
                    text: root.wxPlace !== "" ? ("Current: " + root.wxPlace) : "Set a city or place name."
                    color: theme.textMuted
                    font.family: theme.fontFamily
                    font.pixelSize: theme.fontSize
                    width: parent.width
                    elide: Text.ElideRight
                }

                Rectangle {
                    width: parent.width
                    implicitHeight: 32
                    radius: 7
                    color: theme.normalFill
                    border.width: 1
                    border.color: wxInput.activeFocus ? theme.accent : theme.cardBorder
                    TextInput {
                        id: wxInput
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: theme.barText
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                        selectByMouse: true
                        selectionColor: theme.accent
                        selectedTextColor: theme.barBackground
                        text: root.wxLocText
                        focus: root.wxSetOpen
                        onTextChanged: root.wxLocText = text
                        onAccepted: root.wxSetLocation(root.wxLocText)
                        Keys.onEscapePressed: root.wxSetOpen = false
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: wxInput.text === ""
                            text: "City or place name…"
                            color: theme.textMuted
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize
                        }
                    }
                    MouseArea { anchors.fill: parent; enabled: !wxInput.activeFocus; onClicked: wxInput.forceActiveFocus() }
                }

                RowLayout {
                    width: parent.width
                    spacing: 8
                    Btn {
                        label: "Set"
                        bgColor: theme.accent
                        fg: theme.barBackground
                        glyphColor: theme.barBackground
                        implicitHeight: 30
                        hPad: 14
                        onClicked: root.wxSetLocation(root.wxLocText)
                    }
                    Btn {
                        label: "Use auto-detected"
                        implicitHeight: 30
                        hPad: 12
                        borderColor: theme.cardBorder
                        onClicked: root.wxClearLocation()
                    }
                    Item { Layout.fillWidth: true }
                }

                Text {
                    text: "Tip: include a region for ambiguous names, e.g. \"Paris, TX\"."
                    color: theme.textMuted
                    font.family: theme.fontFamily
                    font.pixelSize: theme.fontSize - 1
                    width: parent.width
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ------------------------------------------------------ bluetooth popup
    // Left click: what it is connected to. Right click: connection manager.
    PanelWindow {
        id: btPopup
        visible: root.btOpen
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true; right: true }
        margins { top: theme.barHeight + 6; right: 8 }
        implicitWidth: 364
        implicitHeight: Math.min(btCol.implicitHeight + 28, 640)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        focusable: true
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay
        onVisibleChanged: { if (visible) { btSel = 0; btSelClamp() } }

        Rectangle {
            id: btBox
            anchors.fill: parent
            radius: theme.popupRadius
            color: theme.barBackground
            border.width: 2
            border.color: theme.popupBorder
            focus: btPopup.visible
            Keys.onUpPressed: { btSel--; btSelClamp() }
            Keys.onDownPressed: { btSel++; btSelClamp() }
            Keys.onReturnPressed: { var s = btShown; if (s[btSel]) { var d = s[btSel]; if (d.connected) d.disconnect(); else if (d.paired || d.bonded) d.connect(); else d.pair() } }
            Keys.onEscapePressed: { root.btOpen = false }

            Column {
                id: btCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    width: parent.width
                    spacing: 8
                    Rectangle { width: 8; height: 8; radius: 4; color: root.btOn ? theme.accent : theme.textMuted; Layout.alignment: Qt.AlignVCenter }
                    Text {
                        text: "BLUETOOTH"
                        color: theme.barText
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                        font.letterSpacing: 1.5
                        font.bold: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    Btn {
                        glyph: root.btOn ? "\uf293" : "\uf294"
                        glyphSize: 13
                        glyphColor: root.btOn ? theme.accent : theme.textMuted
                        hPad: 6
                        onClicked: { var a = Bluetooth.defaultAdapter; if (a) a.enabled = !a.enabled }
                    }
                    Btn {
                        glyph: root.btSettings ? "\uf00d" : "\uf0c9"
                        glyphSize: 12
                        hPad: 6
                        glyphColor: root.btSettings ? theme.accent : theme.barText
                        onClicked: root.btToggle(!root.btSettings)
                    }
                    Btn { glyph: "\uf00d"; glyphSize: 12; hPad: 6; onClicked: root.btOpen = false }
                }

                RowLayout {
                    width: parent.width
                    spacing: 8
                    Text {
                        text: root.btOn ? (root.btConnectedCount() + (root.btConnectedCount() === 1 ? " connected" : " connected")) : "Bluetooth off"
                        color: theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    Btn {
                        visible: root.btOn
                        glyph: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering ? "\uf00d" : "\uf002"
                        glyphSize: 12
                        hPad: 8
                        label: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering ? "Stop" : "Scan"
                        glyphColor: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering ? theme.accent : theme.barText
                        onClicked: { var a = Bluetooth.defaultAdapter; if (a) a.discovering = !a.discovering }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                Text {
                    text: root.btSettings ? "ALL DEVICES" : "CONNECTED"
                    color: theme.textMuted
                    font.family: theme.fontFamily
                    font.pixelSize: theme.fontSize - 1
                    font.letterSpacing: 1.0
                }

                Column {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: root.btShown
                        delegate: Rectangle {
                            required property int index
                            required property var modelData
                            width: btCol.width
                            height: 42
                            radius: 8
                            color: (index === root.btSel && btPopup.activeFocus) ? theme.hoverFill : (btDevHover.hovered ? theme.hoverFill : theme.cardFill)
                            border.width: 1
                            border.color: (index === root.btSel && btPopup.activeFocus) ? theme.accent : theme.cardBorder
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 9
                                anchors.rightMargin: 9
                                spacing: 8
                                Text {
                                    text: root.btIconGlyph(modelData)
                                    color: modelData.connected ? theme.accent : theme.textMuted
                                    font.family: theme.fontFamily
                                    font.pixelSize: 16
                                    Layout.preferredWidth: 20
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text {
                                        text: root.btName(modelData)
                                        color: theme.barText
                                        font.family: theme.fontFamily
                                        font.pixelSize: theme.fontSize
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: root.btSub(modelData)
                                        color: modelData.connected ? theme.accent : theme.textMuted
                                        font.family: theme.fontFamily
                                        font.pixelSize: theme.fontSize - 1
                                        Layout.fillWidth: true
                                    }
                                }
                                Btn {
                                    label: modelData.connected ? "Disconnect" : (modelData.paired ? "Connect" : "Pair")
                                    hPad: 8
                                    implicitHeight: 26
                                    borderColor: theme.cardBorder
                                    onClicked: {
                                        if (modelData.connected) modelData.disconnect()
                                        else if (modelData.paired || modelData.bonded) modelData.connect()
                                        else modelData.pair()
                                    }
                                }
                            }
                            HoverHandler { id: btDevHover }
                        }
                    }
                    Text {
                        visible: root.btShown.length === 0
                        text: root.btSettings ? "No devices found." : "Nothing connected."
                        color: theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                    }
                }

                Text {
                    visible: !root.btSettings
                    text: "Right click for connection settings."
                    color: theme.textMuted
                    font.family: theme.fontFamily
                    font.pixelSize: theme.fontSize - 1
                }
            }
        }
    }

    // ---------------------------------------------------- bar plugins menu
    // Right-click / Alt+click on empty bar space. Every plugin with an on/off
    // switch, move left/right, section, and a gear for its own settings.
    PanelWindow {
        id: barSetPopup
        visible: root.barSetOpen
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true; left: true }
        margins {
            top: theme.barHeight + 6
            left: Math.max(8, Math.min((barSetPopup.screen ? barSetPopup.screen.width : 1600) - implicitWidth - 8,
                                       root.barSetX - implicitWidth / 2))
        }
        implicitWidth: 470
        implicitHeight: Math.min(barSetCol.implicitHeight + 28,
                                 (barSetPopup.screen ? barSetPopup.screen.height : 900) - theme.barHeight - 40)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        focusable: true
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay

        Rectangle {
            anchors.fill: parent
            radius: theme.popupRadius
            color: theme.barBackground
            border.width: 2
            border.color: theme.popupBorder

            Flickable {
                anchors.fill: parent
                anchors.margins: 14
                contentHeight: barSetCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: barSetCol
                    width: parent.width
                    spacing: 8

                    RowLayout {
                        width: parent.width
                        spacing: 8
                        Rectangle { width: 8; height: 8; radius: 4; color: theme.accent; Layout.alignment: Qt.AlignVCenter }
                        Text {
                            text: "BAR PLUGINS"
                            color: theme.barText
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize
                            font.letterSpacing: 1.5
                            font.bold: true
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Item { Layout.fillWidth: true }
                        Btn { glyph: ""; glyphSize: 12; hPad: 6; onClicked: root.barSetOpen = false }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Right-click or Alt+click any plugin on the bar for its own settings."
                        color: theme.textMuted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize - 1
                    }
                    Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                    Repeater {
                        model: root.barSections
                        delegate: Column {
                            id: secCol
                            required property var modelData
                            readonly property var plugins: root.barAll().filter(function (w) { return w.section === secCol.modelData.value })
                            visible: plugins.length > 0
                            width: barSetCol.width
                            spacing: 4

                            Text {
                                text: secCol.modelData.label.toUpperCase()
                                color: theme.accent
                                font.family: theme.fontFamily
                                font.pixelSize: theme.fontSize - 2
                                font.letterSpacing: 1.2
                                font.bold: true
                                topPadding: 4
                            }
                            Repeater {
                                model: secCol.plugins
                                delegate: RowLayout {
                                    id: plRow
                                    required property var modelData
                                    required property int index
                                    width: secCol.width
                                    spacing: 6
                                    Toggle {
                                        Layout.alignment: Qt.AlignVCenter
                                        on: plRow.modelData.enabled
                                        onToggled: function (on) { root.barSetEnabled(plRow.modelData.id, on) }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        text: root.barLabels[plRow.modelData.id] || plRow.modelData.id
                                        elide: Text.ElideRight
                                        color: plRow.modelData.enabled ? theme.barText : theme.textMuted
                                        font.family: theme.fontFamily
                                        font.pixelSize: theme.fontSize
                                    }
                                    Btn {
                                        glyph: ""; glyphSize: 12; hPad: 5
                                        opacity: plRow.index > 0 ? 1 : 0.3
                                        onClicked: root.barMove(plRow.modelData.id, -1)
                                    }
                                    Btn {
                                        glyph: ""; glyphSize: 12; hPad: 5
                                        opacity: plRow.index < secCol.plugins.length - 1 ? 1 : 0.3
                                        onClicked: root.barMove(plRow.modelData.id, 1)
                                    }
                                    Stepper {
                                        Layout.alignment: Qt.AlignVCenter
                                        options: plRow.modelData.id === "system"
                                                 ? root.barSections.filter(function (s) { return s.value !== "system" })
                                                 : root.barSections
                                        value: plRow.modelData.section
                                        onPicked: function (v) { root.barSetSection(plRow.modelData.id, v) }
                                    }
                                    Btn {
                                        glyph: ""; glyphSize: 13; hPad: 6
                                        onClicked: root.openPluginSettings(plRow.modelData.id, root.barSetX)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: theme.cardBorder }
                    RowLayout {
                        width: parent.width
                        spacing: 8
                        Btn {
                            glyph: ""; glyphSize: 13
                            label: root.barResetArmed ? "Click again to reset" : "Reset to defaults"
                            fg: root.barResetArmed ? theme.urgent : theme.barText
                            bgColor: theme.normalFill
                            borderColor: theme.cardBorder
                            onClicked: {
                                if (root.barResetArmed) { root.barResetArmed = false; root.barResetDefaults() }
                                else root.barResetArmed = true
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Btn {
                            glyph: ""; glyphSize: 13
                            label: "Restart bar"
                            bgColor: theme.normalFill
                            borderColor: theme.cardBorder
                            onClicked: root.powerAction("restart-bar")
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------ single plugin settings
    // Right-click / Alt+click on a plugin that has no settings panel of its
    // own: show/hide, position, section, plus the plugin's settingsSchema.
    PanelWindow {
        id: pluginSetPopup
        visible: root.pluginSetOpen
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true; left: true }
        margins {
            top: theme.barHeight + 6
            left: Math.max(8, Math.min((pluginSetPopup.screen ? pluginSetPopup.screen.width : 1600) - implicitWidth - 8,
                                       root.pluginSetX - 20))
        }
        implicitWidth: 320
        implicitHeight: plSetCol.implicitHeight + 28
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        focusable: true
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay

        readonly property var entry: root.barEntry(root.pluginSetId) || ({ enabled: false, section: "right" })
        readonly property var schema: root.pluginSetOpen ? root.pluginSchema(root.pluginSetId) : []

        Rectangle {
            anchors.fill: parent
            radius: theme.popupRadius
            color: theme.barBackground
            border.width: 2
            border.color: theme.popupBorder

            Column {
                id: plSetCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 10

                RowLayout {
                    width: parent.width
                    spacing: 8
                    Rectangle { width: 8; height: 8; radius: 4; color: theme.accent; Layout.alignment: Qt.AlignVCenter }
                    Text {
                        text: (root.barLabels[root.pluginSetId] || root.pluginSetId).toUpperCase()
                        color: theme.barText
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                        font.letterSpacing: 1.5
                        font.bold: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    Btn {
                        glyph: ""; glyphSize: 12; hPad: 6
                        onClicked: root.openBarSettings(root.pluginSetX)
                    }
                    Btn { glyph: ""; glyphSize: 12; hPad: 6; onClicked: root.pluginSetOpen = false }
                }
                Rectangle { width: parent.width; height: 1; color: theme.cardBorder }

                RowLayout {
                    width: parent.width
                    Text {
                        Layout.fillWidth: true
                        text: "Show on bar"
                        color: theme.barText
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                    }
                    Toggle {
                        on: pluginSetPopup.entry.enabled !== false
                        onToggled: function (on) { root.barSetEnabled(root.pluginSetId, on) }
                    }
                }
                RowLayout {
                    width: parent.width
                    Text {
                        Layout.fillWidth: true
                        text: "Section"
                        color: theme.barText
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                    }
                    Stepper {
                        options: root.pluginSetId === "system"
                                 ? root.barSections.filter(function (s) { return s.value !== "system" })
                                 : root.barSections
                        value: pluginSetPopup.entry.section
                        onPicked: function (v) { root.barSetSection(root.pluginSetId, v) }
                    }
                }
                RowLayout {
                    width: parent.width
                    Text {
                        Layout.fillWidth: true
                        text: "Position"
                        color: theme.barText
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSize
                    }
                    Btn {
                        glyph: ""; label: "Left"; glyphSize: 12
                        bgColor: theme.normalFill; borderColor: theme.cardBorder
                        onClicked: root.barMove(root.pluginSetId, -1)
                    }
                    Btn {
                        glyph: ""; label: "Right"; glyphSize: 12
                        bgColor: theme.normalFill; borderColor: theme.cardBorder
                        onClicked: root.barMove(root.pluginSetId, 1)
                    }
                }

                Rectangle {
                    visible: pluginSetPopup.schema.length > 0
                    width: parent.width; height: 1; color: theme.cardBorder
                }
                Repeater {
                    model: pluginSetPopup.schema
                    delegate: RowLayout {
                        id: optRow
                        required property var modelData
                        readonly property var cur: root.barOpt(root.pluginSetId, optRow.modelData.key, optRow.modelData.default)
                        width: plSetCol.width
                        spacing: 8
                        Text {
                            visible: optRow.modelData.type !== "action"
                            Layout.fillWidth: true
                            text: optRow.modelData.label
                            color: theme.barText
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize
                        }
                        Toggle {
                            visible: optRow.modelData.type === "bool"
                            on: !!optRow.cur
                            onToggled: function (on) { root.barSetOpt(root.pluginSetId, optRow.modelData.key, on) }
                        }
                        Stepper {
                            visible: optRow.modelData.type === "number"
                            options: optRow.modelData.type === "number" ? root.pluginRangeOpts(optRow.modelData) : []
                            value: String(optRow.cur)
                            onPicked: function (v) { root.barSetOpt(root.pluginSetId, optRow.modelData.key, Number(v)) }
                        }
                        Btn {
                            visible: optRow.modelData.type === "action"
                            Layout.fillWidth: true
                            label: optRow.modelData.label
                            glyph: ""; glyphSize: 12
                            bgColor: theme.normalFill; borderColor: theme.cardBorder
                            onClicked: { var id = root.pluginSetId; root.pluginSetOpen = false; root.pluginAction(id, optRow.modelData.key) }
                        }
                    }
                }
                Text {
                    visible: pluginSetPopup.schema.length === 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "This plugin has no extra options."
                    color: theme.textMuted
                    font.family: theme.fontFamily
                    font.pixelSize: theme.fontSize - 1
                }
            }
        }
    }

    HyprlandFocusGrab {
        id: grab
        windows: [displayPopup, sbPopup, sbSetPopup, netPopup, sndPopup, powerPopup, wxPopup, wxSetPopup, btPopup, calPopup, calAuthPopup, barSetPopup, pluginSetPopup]
        active: root.displayOpen || root.sbOpen || root.sbSetOpen || root.netOpen || root.sndOpen || root.powerOpen || root.wxOpen || root.wxSetOpen || root.btOpen || root.calOpen || root.calAuthOpen || root.barSetOpen || root.pluginSetOpen
        onCleared: root.closePanels()
    }

    IpcHandler {
        target: "launcher"
        function toggle() { root.launcherToggle() }
        function open() { root.launcherToggle() }
    }

    IpcHandler {
        target: "bar"
        // Plugin menus: `qs ipc call bar settings` / `... bar pluginSettings cava`.
        function settings() { root.openBarSettings(400) }
        function pluginSettings(id: string) { root.openPluginSettings(id, 400) }
        function togglePlugin(id: string) {
            var e = root.barEntry(id)
            if (e) root.barSetEnabled(id, e.enabled === false)
        }
        function movePlugin(id: string, dir: int) { root.barMove(id, dir) }
        function wifiScan() { if (!root.netOpen) root.openNet(); root.wifiScanNow() }
        // Set a plugin option; value is JSON (true, 24, "text").
        function setOption(id: string, key: string, value: string) {
            var v
            try { v = JSON.parse(value) } catch (e) { v = value }
            root.barSetOpt(id, key, v)
        }
        // Diagnostic: shows what the network-speed readout currently holds
        // and how wide the fixed field is.
        function netInfo() {
            var s = "NETINFO iface=" + root.netIface + " down=" + root.netDown + " up=" + root.netUp
                + " text='" + root.netSpeedText() + "' len=" + root.netSpeedText().length
                + " sampleLen=" + root.netSpeedSample().length
                + " width=" + netSpdMetrics.advanceWidth(root.netSpeedSample())
            console.log(s)
            return s
        }
        function toggleDisplay() { root.sbOpen = false; root.sbSetOpen = false; root.displayOpen = !root.displayOpen; if (root.displayOpen) { root.refreshDisplay(); root.readBrightness(); root.auggRead() } }
        function toggleScoreboard() { root.displayOpen = false; root.sbSetOpen = false; root.sbOpen = !root.sbOpen }
        function toggleScoreboardSettings() { root.openSbSet() }
        function toggleWifi() { root.openNet() }
        function toggleSound() { root.openSnd() }
        function toggleWeather() { root.wxToggle() }
        function toggleWeatherLocation() { root.wxToggleSet() }
        function toggleBluetooth() { root.btToggle(false) }
        function toggleBluetoothSettings() { root.btToggle(true) }
        function toggleCalendar() { root.calOpenPanel() }
        function toggleCalendarAuth() { root.calOpenAuth() }
        function togglePower() { root.togglePower() }
        function volumeUp() { root.volumeUp() }
        function volumeDown() { root.volumeDown() }
        function volumeMute() { root.volumeMute() }
        function brightnessUp() { root.brightnessStep(5) }
        function brightnessDown() { root.brightnessStep(-5) }
        function brightnessUpPrecise() { root.brightnessStep(1) }
        function brightnessDownPrecise() { root.brightnessStep(-1) }
        function brightnessMax() { root.brightnessAbs(100) }
        function brightnessMin() { root.brightnessAbs(1) }
        function micToggle() { root.micToggle() }
        function close() { root.closePanels() }
        function refreshScores() { if (!sbProc.running) sbProc.running = true }
        function nextScore() { root.sbStep(1) }
        function prevScore() { root.sbStep(-1) }
        function refreshDisplays() { root.refreshDisplay() }
    }
}