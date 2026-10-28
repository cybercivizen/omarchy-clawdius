import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Link.js" as Link
import "Format.js" as Format
import "Icons.js" as Icons
import "Timers.js" as Timers
import "Weather.js" as Weather

// A tiny Clawd beside the clock that types while any Claude Code session is
// busy: orange while Claude is doing something, gray when it isn't. Hovering
// it — or the clock itself — drops an island from the bar:
//
//   Home      the main card (Moment.qml) is one of three, picked by the
//             switch in its corner: Agents (one moment at a time, the most
//             pressing: a permission prompt to answer, a finished turn, the
//             session you're watching and its steps, or New chat), Today
//             (Today.qml: a month and the weather) or Anti-rot (today's rep,
//             ChallengeCard.qml, antirot.py). Anything that needs you shows
//             Agents until it's dealt with. Other running sessions sit on a
//             rail of small crabs; the corner card beside it (Limits, Timer,
//             Move) has the Limits glance that opens Stats.
//   Chat      a new chat: type, Enter starts Chat or Code with it (QuickChat).
//   Sessions  Live · Recent · Folders.
//   Search    the nav's search bar: apps, sums, `/ ` a terminal command, `/g ` Google.
//   Detail    one background session up close, its terminal live.
//   Settings  the gear: the daily reps' languages and levels (Settings.qml).
//
// + starts a new session from any view. Click the crab to pin the island.
// Super+Alt+C pulls it down on the chat view, Alt+Space on search.
// When Claude asks for a permission, it drops open with Allow / Deny right
// there (approvals.py is the hook on the other end).
//
// Notifications (a turn finished or failed, a session stuck on you) show in
// the island too, not on the desktop: closed, it opens just enough for the
// note (Toast.qml); open, the note sits up top above the nav.
//
// While nothing is busy the crab tucks away and only peeks out with the other
// center indicators when the clock is hovered.
//
// feed.py does the reading (and decides what's worth a notification); this
// file only draws its snapshots.
BarWidget {
  id: root
  moduleName: "cybercivizen.clawdius"

  // Theme-aware colors (Colors.qml); the `color` setting overrides the orange.
  Colors {
    id: theme
    fg: root.previewTheme === "light" ? "#101315" : root.previewTheme === "dark" ? "#cacccc" : root.fg
    bg: root.previewTheme === "light" ? "#ffffff" : root.previewTheme === "dark" ? "#101315" : Color.background
    crabOverride: String(root.setting("color", "") || "")
    look: root.islandLook
    barColor: root.previewTheme === "" && root.bar ? root.bar.background : "transparent"
  }
  readonly property color crabColor: theme.crab
  // The bar crab types, bobs and blinks. Every step redraws the bar, which
  // a low-power laptop's GPU can't afford for as long as Claude works: with
  // "Animate the bar crab" off it holds one pose and only changes color.
  readonly property bool still: setting("animateCrab", true) !== true
  // IPC themePreview: draw the island in Solitude Light / Dark without
  // switching the desktop's theme.
  property string previewTheme: ""
  readonly property int maxIdle: setting("maxIdleSessions", 4)
  readonly property bool alwaysShow: setting("alwaysShow", true) === true
  readonly property real hoverDelay: setting("hoverDelayMs", 200)
  // Hovering only opens the island once the pointer has touched the screen
  // edge; brushing past the bar isn't enough. Off: any hover opens it.
  readonly property bool edgeOpen: setting("edgeOpen", true) === true
  property bool edgeArmed: false
  readonly property bool edgeReady: !edgeOpen || edgeArmed
  // Grace after the pointer leaves, so overshooting the edge doesn't close it.
  readonly property real closeDelay: setting("closeDelayMs", 400)

  // Background sessions that never got a prompt (a Chat you walked away
  // from) are left out, except the one showing live, and reaped below.
  property var feedSessions: []
  readonly property var sessions: feedSessions.filter(function(s) { return !root.isEmpty(s) || s.jobId === root.liveId })
  readonly property var emptyJobs: feedSessions.filter(function(s) { return root.isEmpty(s) && s.jobId !== root.liveId })
    .map(function(s) { return s.jobId })

  function isEmpty(s) {
    return s.kind === "bg" && !!s.jobId && !s.prompt && !s.reply && !s.busy && !s.waiting
  }
  property int busyCount: 0
  property int waitingCount: 0
  property bool feedOk: false
  property double now: Date.now()

  readonly property bool working: busyCount > 0
  readonly property var activeSessions: sessions.filter(function(s) { return s.busy || s.waiting })
  readonly property int idleCount: sessions.length - activeSessions.length
  // "+ N more idle" in Sessions → Live toggles this: all idle sessions, or the first maxIdle.
  property bool idleExpanded: false
  // The live one always makes the cut, even a fresh Chat with no prompt yet.
  readonly property var idleSessions: {
    var idle = sessions.filter(function(s) { return !s.busy && !s.waiting })
    var shown = idleExpanded ? idle.slice() : idle.slice(0, maxIdle)
    var live = idle.filter(function(s) { return s.jobId && s.jobId === liveId })
    if (live.length && shown.indexOf(live[0]) < 0) shown.push(live[0])
    return shown
  }
  readonly property var liveSession: {
    if (!liveId) return null
    for (var i = 0; i < sessions.length; i++)
      if (sessions[i].jobId === liveId) return sessions[i]
    return pendingSession && pendingSession.jobId === liveId ? pendingSession : null
  }
  // The live session has a prompt waiting: its card (Detail) is taller for a plan.
  readonly property bool liveAsk: !!liveSession && requests.some(function(r) { return r.sessionId === liveSession.id && r.tool === "ExitPlanMode" })
  // Starred (pinned) sessions: ids kept in prefs.json. Named "starred" because
  // pinnedId/pinSession already mean the card's transient focus.
  property var starredIds: []
  function isStarred(id) { return starredIds.indexOf(id) >= 0 }
  function toggleStar(s) {
    if (!s || !s.id) return
    starredIds = isStarred(s.id) ? starredIds.filter(function(i) { return i !== s.id }) : starredIds.concat([s.id])
  }
  readonly property var pinnedLive: sessions.filter(function(s) { return isStarred(s.id) })
  readonly property var pinnedResumable: notRunning.filter(function(r) { return isStarred(r.id) })
  // Stable: starred first, the rest keep their order.
  function starFirst(list) {
    return list.filter(function(s) { return isStarred(s.id) }).concat(list.filter(function(s) { return !isStarred(s.id) }))
  }
  readonly property int hiddenIdle: Math.max(0, sessions.length - activeSessions.length - idleSessions.length)

  // ---- Moods. The crab shows the most pressing thing going on:
  //      waving you over > celebrating a finish > typing / thinking >
  //      deflated after a failure > asleep at night > idle.
  property string eventMood: ""     // "done" for a few seconds, "failed" a while longer
  property double lastEventAt: 0
  property string forcedMood: ""    // IPC, for trying moods out
  property int hour: new Date().getHours()

  readonly property bool allThinking: busyCount > 0 && sessions.every(function(s) { return !s.busy || s.thinking })
  readonly property bool night: hour < 6
  // Sessions the feed sees waiting, or prompts the approval hook is holding.
  readonly property int needsYou: Math.max(waitingCount, requests.length)

  readonly property string mood: forcedMood !== "" ? forcedMood
    : needsYou > 0 ? "waiting"
    : eventMood === "done" ? "done"
    : working ? (allThinking ? "thinking" : "typing")
    : eventMood === "failed" ? "failed"
    : night ? "sleep"
    : "idle"
  readonly property bool lively: mood !== "idle" && mood !== "sleep"

  // Sweating once the 5-hour window is 90% spent.
  readonly property bool sweating: {
    var limits = (usage && usage.limits) || []
    for (var i = 0; i < limits.length; i++)
      if (/5-hour|session/i.test(limits[i].label || "") && Number(limits[i].percent) >= 0.9) return true
    return false
  }

  function noteEvent(event) {
    if (!event || !event.at || event.at === root.lastEventAt) return
    root.lastEventAt = event.at
    if (Date.now() - event.at > 10000) return   // from before this bar started
    if (event.kind !== "done" && event.kind !== "failed" && event.kind !== "limited") return
    // Out of usage reads as a failure on the bar; the island says which.
    root.eventMood = event.kind === "limited" ? "failed" : event.kind
    eventTimer.interval = event.kind === "done" ? 3500 : 15000
    eventTimer.restart()
    // The island's "finished" moment stays until dismissed, or 30s.
    root.finished = event
    finishedTimer.restart()
  }

  readonly property bool centerPeek: bar ? (bar.centerSectionRevealHeld === true && bar.centerHoverRevealSuppressed !== true) : false
  readonly property bool revealed: lively || alwaysShow || centerPeek || glyphArea.containsMouse || card.open

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color mutedFg: theme.muted
  // The crab's idle gray and the count beside it sit on the bar: the
  // wallpaper-matched text color, until the island is down over them.
  readonly property color barInk: bar && !cardDown ? bar.barForeground : fg
  readonly property color idleBarCrab: bar && !cardDown ? theme.mix(barInk, theme.bg, 0.35) : theme.idleCrab
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ---- Card lifecycle. The bar's popout coordinator calls close() when
  //      another panel takes over.
  property bool pinned: false
  // The island proper: open, and not just peeking out with a notification.
  readonly property bool islandOpen: card.open && !peeking
  readonly property bool opened: islandOpen
  // The card is down over the bar: the island, or just a notification or
  // prompt peeking out of the crab. Either way it is the light surface the
  // clock and crab sit on.
  readonly property bool cardDown: card.open
  onCardDownChanged: Link.islandCover(root.barWindow, root.cardDown)

  function open() { peeking = false; card.open = true }
  function close() { viewHold = false; pinned = false; autoOpened = false; quickWanted = false; summoned = false; searchChip = ""; toast = null; card.open = false }
  function toggle() { if (card.open && pinned) close(); else { pinned = true; open() } }

  function maybeClose() { closeTimer.restart() }

  // A live terminal on show (or one starting) holds the card while the
  // pointer is elsewhere (you may be typing), and so does a half-typed chat
  // message or search; clicking another window still closes it, see
  // liveFocus below.
  readonly property bool terminalUp: (liveId !== "" || startingLabel !== "") && view === "detail"
  // The live terminal's (or the chat view's) file chooser is up: it has the keyboard, the island waits for it.
  readonly property bool livePicking: (!!detailLoader.item && detailLoader.item.picking) || quickChat.picking
  readonly property bool holdOpen: pinned || terminalUp || livePicking || (keysView && liveKeys.field.text !== "")

  // The clock (cybercivizen.clock) reports its hover here, so pointing at the
  // time is enough to bring the card up. Not while another panel (the
  // calendar, say) is already open.
  property bool clockHovered: false
  readonly property var barWindow: root.QsWindow.window

  Component.onCompleted: Link.register(root)
  Component.onDestruction: Link.unregister(root)
  // The clock's click goes to the crab on the same bar window (Link.clockClick).
  function clockClick() { openToday() }
  function setClockHover(hovered) {
    clockHovered = hovered
    hoverChanged(hovered)
  }
  // The clock's hover, or the hover zone's (below): either one opens it.
  function hoverChanged(hovered) {
    if (hovered) {
      var other = root.bar && root.bar.activePopout && root.bar.activePopout !== root
      if (!other && root.edgeReady && !openTimer.running) openTimer.restart()
    } else if (!root.clockHovered && !root.zoneHovered && !glyphArea.containsMouse) {
      root.edgeArmed = false
      openTimer.stop()
      maybeClose()
    }
  }
  // The pointer in the bar window, whose outer row is the screen edge.
  function checkEdge(winX, winY) {
    if (!edgeOpen || edgeArmed || !barWindow) return
    var bottom = root.bar && root.bar.position === "bottom"
    if (bottom ? winY < barWindow.height - 2 : winY > 1) return
    edgeArmed = true
    if (!card.open) edgeRipple.play(winX, bottom)
    if (glyphArea.containsMouse || clockHovered || zoneHovered) hoverChanged(true)
  }

  function applySnapshot(line) {
    var snap
    try { snap = JSON.parse(line) } catch (e) { return }
    if (!snap || !snap.sessions) return
    root.feedSessions = snap.sessions
    root.busyCount = snap.busy || 0
    root.waitingCount = snap.waiting || 0
    root.feedOk = true
    root.noteEvent(snap.event)
    root.noteToast(snap.toast)
  }

  // ---- Notifications. The feed's toast shows on one island: the one that's
  //      open, else the focused monitor's (every bar's feed sends its own
  //      copy). Closed, the island peeks out just far enough for it; open,
  //      it sits above the nav. Either way it goes after a few seconds (held
  //      while the pointer's on it), or when its session moves on.
  property var toast: null
  // What the banner draws: the last toast, kept while it folds away.
  property var toastDrawn: null
  property double lastToastAt: 0
  // Open only for the toast (FrostCard's passive mode: no popout slot, no
  // focus grab). Cleared once the island has folded back into the bar.
  property bool peeking: false
  readonly property bool otherPanel: !!root.bar && !!root.bar.activePopout && root.bar.activePopout !== root
  // Not when Home's moment is already that session's news.
  readonly property bool toastShown: toast !== null
    && !(islandOpen && view === "home" && moment.session && moment.session.id === toast.id
         && moment.kind !== "working" && moment.kind !== "idle")

  onToastChanged: if (toast) toastDrawn = toast

  function noteToast(t) {
    if (!t || !t.at || t.at === root.lastToastAt) return
    root.lastToastAt = t.at
    if (Date.now() - t.at > 10000) return   // from before this bar started
    var focused = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    if ((Link.openCrab() || Link.approvalCrab(focused)) !== root) return
    // A prompt the approval hook holds opens the island itself, buttons and all.
    if (t.kind === "waiting" && root.requests.some(function(r) { return r.sessionId === t.id })) return
    root.toast = t
    toastTimer.interval = t.kind === "done" ? 6000 : 10000
    toastTimer.restart()
    root.showPeek()
  }

  // Not over another panel: the peek waits for it to close.
  function showPeek() {
    if (!root.toast || card.open || root.otherPanel || !root.drawn()) return
    root.peeking = true
    card.open = true
  }

  function hideToast() {
    root.toast = null
    if (root.peeking) card.open = false
  }

  // A click: a background session up close in the island, else its terminal.
  function activateToast() {
    // A timer or nudge has no session to go to; a click puts it away.
    if (root.toastDrawn && (root.toastDrawn.kind === "timer" || root.toastDrawn.kind === "posture" || root.toastDrawn.kind === "walk")) { hideToast(); return }
    var s = root.toastDrawn ? root.sessionById(root.toastDrawn.id) : null
    root.toast = null
    if (!s) { if (root.peeking) card.open = false; return }
    if (s.jobId) { root.pinned = true; root.open(); root.openSession(s) }
    else root.focusSession(s)
  }

  Timer {
    id: toastTimer
    onTriggered: if (toastBanner.hovered) restart(); else root.hideToast()
  }

  Connections {
    target: card
    function onVisibleChanged() { if (!card.visible) root.peeking = false }
  }

  Connections {
    target: root.bar
    ignoreUnknownSignals: true
    function onActivePopoutChanged() {
      if (!root.otherPanel) root.showPeek()
      else if (root.peeking && card.open) card.open = false
    }
  }

  readonly property string focusPath: decodeURIComponent(String(Qt.resolvedUrl("focus.py")).replace(/^file:\/\//, ""))

  // Same as clicking its notification: bring the session's terminal forward.
  function focusSession(s) {
    var argv = ["python3", "-I", root.focusPath, "--pid", String(s.pid || 0), "--name", s.name || ""]
    if (s.procStart) argv.push("--proc-start", s.procStart)
    if (s.jobId) argv.push("--job", s.jobId)
    root.close()
    Quickshell.execDetached(argv)
  }

  readonly property string feedPath: decodeURIComponent(String(Qt.resolvedUrl("feed.py")).replace(/^file:\/\//, ""))

  // ---- Usage. Omarchy's collector writes the record; this widget now owns
  //      the refresh schedule the agents panel used to run.
  readonly property int usageRefreshSec: Math.max(60, Number(setting("usageRefreshSec", 900)))
  readonly property string usagePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/agents/usage/claude.json"
  property var usage: null

  function applyUsage(text) {
    try { root.usage = JSON.parse(text) } catch (e) { console.warn("clawdius usage parse", e) }
  }

  function refreshUsage(onlyIfStaleMs) {
    if (usageProcess.running) return
    if (onlyIfStaleMs && root.usage && root.usage.updatedAt
        && Date.now() - new Date(root.usage.updatedAt).getTime() < onlyIfStaleMs) return
    usageProcess.running = true
  }

  implicitWidth: revealed ? button.implicitWidth : 0
  implicitHeight: barSize
  clip: true

  Behavior on implicitWidth { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

  Process {
    id: feed
    command: ["python3", "-I", root.feedPath]
    running: true
    stdout: SplitParser {
      onRead: function(data) { root.applySnapshot(data) }
    }
    onExited: function(code) {
      root.feedOk = false
      restartFeed.start()
    }
  }

  Timer {
    id: restartFeed
    interval: 3000
    onTriggered: feed.running = true
  }

  FileView {
    path: root.usagePath
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.applyUsage(text())
  }

  Process {
    id: usageProcess
    command: ["omarchy-agent-usage-update", "claude"]
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("clawdius usage:", text.trim())
    }
  }

  Timer {
    interval: root.usageRefreshSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshUsage(0)
  }

  Connections {
    target: root
    // Opening also picks today's rep when the day has turned.
    function onIslandOpenChanged() { if (root.islandOpen) { root.refreshUsage(60000); root.runAntirot(["today"], ""); root.fetchWeather(30 * 60000) } }
  }

  Timer {
    // Keeps the "working 3m12s" timers ticking while the card is up.
    running: card.open
    interval: root.activeSessions.length || root.timers.length || root.nudging ? 1000 : 5000
    repeat: true
    triggeredOnStart: true
    onTriggered: root.now = Date.now()
  }

  Timer {
    // For the night-time nap.
    running: true
    interval: 60000
    repeat: true
    onTriggered: root.hour = new Date().getHours()
  }

  Timer {
    id: eventTimer
    onTriggered: root.eventMood = ""
  }

  Timer {
    id: openTimer
    interval: root.hoverDelay
    onTriggered: if (root.edgeReady && (glyphArea.containsMouse || root.clockHovered || root.zoneHovered)) root.open()
  }

  Timer {
    id: closeTimer
    interval: root.closeDelay
    onTriggered: if (!root.peeking && !root.holdOpen && !root.viewHold && !liveKeys.settling && !glyphArea.containsMouse && !root.clockHovered && !root.zoneHovered && !card.containsMouse) card.open = false
  }

  // Switching views from inside the island (New chat on Home, say) can
  // shrink it out from under a pointer that hasn't moved. That isn't a
  // leave: it stays till the pointer is back on it, or a click elsewhere
  // (the views that take the keyboard), or a few seconds (the others).
  property bool viewHold: false
  Timer {
    id: viewHoldCheck
    interval: 450
    onTriggered: if (card.containsMouse) root.viewHold = false; else if (!root.keysView) viewHoldEnd.restart()
  }
  Timer {
    id: viewHoldEnd
    interval: 3000
    onTriggered: { root.viewHold = false; root.maybeClose() }
  }

  Connections {
    target: card
    // Back on it while it's still folding away: open it again.
    function onContainsMouseChanged() {
      if (card.containsMouse) { root.viewHold = false; viewHoldEnd.stop() }
      if (!card.containsMouse) root.maybeClose()
      else if (!card.open && card.progress > 0 && !root.peeking) card.open = true
    }
  }

  IpcHandler {
    target: "clawdius"
    function open(): void { root.pinned = true; root.open() }
    // Alt+Space: the island on its search view, keyboard on it; again closes.
    function search(): void { focusedCrab().summon("search") }
    // As if typed into the search bar (testing); "/ " and "/g " set the chips.
    function searchType(text: string): void { (Link.openCrab() || focusedCrab()).quickType(text) }
    // Pages the search view's tab chips, as › (1) and ‹ (-1) do.
    function searchTabs(delta: int): void { (Link.openCrab() || focusedCrab()).pageTabs(delta) }
    function close(): void { Link.closeAll() }
    function toggle(): void { root.toggle() }
    function debug(): string {
      return JSON.stringify({ usage: !!root.usage, usageUpdated: root.usage ? root.usage.updatedAt : null,
        sessions: root.sessions.length, cardOpen: card.open, pinned: root.pinned, triggerMode: card.triggerMode, keysFocused: liveKeys.field.activeFocus,
        clockHovered: root.clockHovered, linkedCrabs: Link.count(), crabs: Link.states(), feedOk: root.feedOk,
        view: root.view, sessionsTab: root.sessionsTab, moment: root.moment.kind, main: root.mainShown, weather: root.weather ? root.weather.temp + " " + root.weather.place : null, focusId: root.focusId,
        pinnedId: root.pinnedId, rail: root.railSessions.length, lightTheme: theme.light,
        colors: { fg: String(theme.fg), bg: String(theme.bg), primary: String(theme.primary), primaryInk: String(theme.primaryInk), island: String(theme.island), islandAlpha: card.frostAlpha, bar: root.bar ? String(root.bar.background) : "" },
        mood: root.mood, waiting: root.waitingCount, sweating: root.sweating,
        requests: root.requests.length, autoOpened: root.autoOpened,
        liveId: root.liveId, keysWanted: liveKeys.wanted, keysPrimed: liveKeys.primed,
        searchChip: root.searchChip, quickMode: root.quickMode, appsTracked: Object.keys(root.appUsage).length,
        activeApp: ToplevelManager.activeToplevel ? String(ToplevelManager.activeToplevel.appId) : "",
        activeEntry: ToplevelManager.activeToplevel && DesktopEntries.heuristicLookup(ToplevelManager.activeToplevel.appId || "")
          ? DesktopEntries.heuristicLookup(ToplevelManager.activeToplevel.appId || "").id : "",
        appsLeader: Link.isLeader(root), zone: root.zoneHovered, edgeArmed: root.edgeArmed,
        toast: root.toast ? root.toast.kind : "", toastShown: root.toastShown, peeking: root.peeking, otherPanel: root.otherPanel,
        keysFocused: liveKeys.field.activeFocus,
        idleStopMinutes: root.idleStopMinutes, idleKeepRunning: root.idleKeepRunning, asleep: root.asleepCount,
        antirot: root.antirot ? { today: root.antirot.today ? root.antirot.today.lang + "/" + root.antirot.today.slug : "", streak: root.antirot.streakNow } : null,
        antirotBusy: root.antirotBusy })
    }
    // Same path the clock's HoverHandler takes, for testing without a pointer.
    function hoverClock(on: bool): void { Link.clockHover(root.barWindow, on) }
    function testKeys(on: bool): void { root.keysOff = !on }
    // The old tab numbers: 0 Tasks (Sessions → Live), 1 Stats, 2 and 3
    // Resume / History (Sessions → Recent), 4 Folders.
    function setTab(index: int): void {
      if (index === 1) root.view = "stats"
      else { root.view = "sessions"; root.sessionsTab = index === 4 ? "folders" : index >= 2 ? "recent" : "live" }
    }
    // home | quick | sessions | search | stats | detail | settings
    function setView(name: string): void { root.view = name }
    // A rep card button: start | open | check | easier | skip | next | review | settings.
    function challenge(action: string): void { root.challengeAction(action) }
    // Home's corner card: limits | timer | posture (the Move tab).
    function setCorner(mode: string): void { root.pickCorner(mode) }
    // Home's main card: agents | today | antirot.
    function setMain(mode: string): void { root.pickMain(mode) }
    // The clock's click, for testing: pinned on Today.
    function today(): void { root.openToday() }
    // Show a background session live, by its job id ("" hides it).
    function live(jobId: string): void { root.liveId = jobId; root.view = jobId ? "detail" : "home"; root.pinned = true; root.open() }
    // Clicking the index-th Recent row.
    function resume(index: int): void {
      if (index >= 0 && index < root.resumableIdle.length) { root.open(); root.resumeSession(root.resumableIdle[index]) }
    }
    // Clicking the index-th folder in Sessions → Folders (lists its sessions).
    function openFolder(index: int): void {
      if (index < 0 || index >= root.recentFolders.length) return
      root.view = "sessions"
      root.sessionsTab = "folders"
      root.open()
      foldersView.expanded = foldersView.flip(foldersView.expanded, root.recentFolders[index].cwd)
    }
    // Answer the oldest permission prompt: allow | always | deny | terminal.
    function answer(choice: string): void { if (root.requests.length) root.answerRequest(root.requests[0], choice, null) }
    // Answer the oldest question: {"question": "label", ...}.
    function answerQuestion(answers: string): void { if (root.requests.length) root.answerRequest(root.requests[0], "answer", JSON.parse(answers)) }
    // OK on the finished moment.
    function dismiss(): void { root.finished = null }
    // light | dark | "" (the theme's own): the island's colors only.
    // On every monitor's crab: the handler's own may not be the open one.
    function themePreview(name: string): void { Link.crabs.forEach(function(c) { c.previewTheme = name }) }
    // The + menu, open or shut.
    function newMenu(): void { root.pinned = true; root.open(); root.newMenuOpen = !root.newMenuOpen }
    // Pin the index-th rail crab to the main card.
    function pin(index: int): void { if (index >= 0 && index < root.railSessions.length) root.pinSession(root.railSessions[index]) }
    // What the + menu's Chat / Code tiles do: "chat" or "code".
    function start(which: string): void {
      root.open()
      root.launchInCard(which === "code" ? root.codeCommand : root.chatCommand, which === "code" ? "Code" : "Chat")
    }
    // Super+Alt+C: open with the keyboard (typing opens the chatbox); again closes.
    // One handler answers for every bar: the island opens on the focused monitor.
    function summon(): void { focusedCrab().summon("quick") }
    function focusedCrab() {
      var focused = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
      return Link.approvalCrab(focused) || root
    }
    // As if typed into the summoned chatbox / Enter on it (testing).
    function quickType(text: string): void { (Link.openCrab() || focusedCrab()).quickType(text) }
    function quickSend(): void { (Link.openCrab() || focusedCrab()).sendQuick() }
    // Code in that folder, as the + menu's folders start it.
    function startIn(cwd: string): void { root.pinned = true; root.open(); root.startInFolder(cwd) }
    // Answer the folder trust question: yes | no | terminal.
    function trust(choice: string): void { root.answerTrust(choice) }
    // idle | typing | thinking | waiting | done | failed | sleep; "" goes back to live.
    function setMood(name: string): void { root.forcedMood = name }
    function fireEvent(kind: string): void { root.noteEvent({ kind: kind, at: Date.now() }) }
    // A made-up notification: done | failed | input | limited | waiting.
    function testToast(kind: string): void {
      var crab = Link.openCrab() || focusedCrab()
      var s = crab.sessions.length ? crab.sessions[0] : { id: "", name: "Claude", project: "" }
      var status = { done: "Done", failed: "Failed", input: "Needs input", limited: "Out of usage", waiting: "Needs your OK" }
      crab.noteToast({ kind: kind, status: status[kind] || "Done", id: s.id, name: s.name, at: Date.now(),
                       text: kind === "waiting" ? "Bash: npm run build" : "Moved the notification into the island, so it reads at a glance",
                       meta: kind === "waiting" ? [s.project] : ["2m 14s", "12k tokens", s.project] })
    }
    // Render a hand-written feed line (until the feed's next change replaces it).
    function snapshot(line: string): void { root.applySnapshot(line) }
  }

  Item {
    id: button
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: row.implicitWidth + Style.spaceReal(8) * 2
    height: root.barSize

    Row {
      id: row
      anchors.centerIn: parent
      spacing: Style.spaceReal(4)

      // Orange while Claude is doing something; gray (at full strength, so
      // it still reads on a light bar) when idle or asleep. A failure stays
      // orange: with no red badge on the bar yet, gray would read as idle.
      Clawd {
        id: glyph
        anchors.verticalCenter: parent.verticalCenter
        unit: Math.max(1, Math.round(Style.bar.iconFont / 12))
        color: root.mood === "idle" || root.mood === "sleep" ? root.idleBarCrab : root.crabColor
        mood: root.mood
        sweat: root.sweating
        animate: root.revealed && !root.still
        Behavior on color { ColorAnimation { duration: 200 } }

        transform: Translate {
          y: !glyph.animate ? 0
            : glyph.mood === "typing" && glyph.step % 2 === 1 ? -glyph.unit * 0.5
            : glyph.mood === "done" && glyph.step % 2 === 0 ? -glyph.unit
            : 0
        }
      }

      // "!" while a session waits on you, else how many are busy.
      Text {
        visible: root.needsYou > 0 || root.busyCount > 1
        anchors.verticalCenter: parent.verticalCenter
        text: root.needsYou > 0 ? "!" + (root.needsYou > 1 ? root.needsYou : "") : root.busyCount
        textFormat: Text.PlainText
        color: root.needsYou > 0 ? theme.needsYou : root.barInk
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    MouseArea {
      id: glyphArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.edgeReady) openTimer.restart()
      onPositionChanged: mouse => {
        var p = mapToItem(root.barWindow.contentItem, mouse.x, mouse.y)
        root.checkEdge(p.x, p.y)
      }
      onExited: { if (!root.zoneHovered && !root.clockHovered) { root.edgeArmed = false; openTimer.stop() } root.maybeClose() }
      onClicked: root.toggle()
    }
  }

  // ---- The hover zone: the clock and crab are small targets, so a wider
  //      stretch of the bar's middle opens the island too. A HoverHandler is
  //      passive and non-blocking: the bar's widgets under it keep their own
  //      hover and clicks.
  readonly property real hoverZoneWidth: Math.max(0, Number(setting("hoverZoneWidth", 560)))
  property bool zoneHovered: false

  //      Only the empty stretches count: over another module (the tray's
  //      arrows, the media title) the pointer is after that widget, not us.
  function overOtherModule(item, pos) {
    var kids = item.children
    for (var i = kids.length - 1; i >= 0; i--) {
      var c = kids[i]
      if (c === hoverZone || !c.visible || c.width <= 0 || c.height <= 0) continue
      var p = item.mapToItem(c, pos.x, pos.y)
      if (p.x < 0 || p.y < 0 || p.x >= c.width || p.y >= c.height) continue
      if (c.moduleName !== undefined && !/clock/.test(c.moduleName) && !root.isDescendantOf(c)) return true
      if (overOtherModule(c, p)) return true
    }
    return false
  }
  function isDescendantOf(item) {
    for (var o = root; o; o = o.parent) if (o === item) return true
    return false
  }
  function updateZone(handler) {
    var wp = hoverZone.mapToItem(root.barWindow.contentItem, handler.point.position.x, handler.point.position.y)
    if (handler.hovered) root.checkEdge(wp.x, wp.y)
    var on = handler.hovered && !(root.barWindow && overOtherModule(root.barWindow.contentItem, wp))
    if (on === root.zoneHovered) return
    root.zoneHovered = on
    root.hoverChanged(on)
  }

  Item {
    id: hoverZone
    parent: root.barWindow ? root.barWindow.contentItem : null
    visible: root.hoverZoneWidth > 0 && !!root.bar && !root.vertical
    x: parent ? (parent.width - width) / 2 : 0
    width: Style.space(root.hoverZoneWidth)
    height: parent ? parent.height : 0
    z: 100

    HoverHandler {
      blocking: false   // let the modules under it (the tray drawer) get their hover
      onHoveredChanged: root.updateZone(this)
      onPointChanged: root.updateZone(this)
    }
  }

  // The island hangs below the bar; with a see-through bar that leaves a gap
  // to the screen's edge. Fill the bar's strip under the island so it reads
  // as growing out of the edge: over the other modules (the window title),
  // under the clock and the crab. The clock and the crab sit in different
  // parts of the bar, so no one z fits between them and the title; three
  // strips that meet edge to edge do (no overlap, so the alpha doesn't double).
  property rect keepRect: Qt.rect(0, 0, 0, 0)
  function findModule(item, re) {
    var kids = item.children
    for (var i = 0; i < kids.length; i++) {
      var c = kids[i]
      if (!c.visible || c.width <= 0 || c.height <= 0) continue
      if (c.moduleName !== undefined && re.test(c.moduleName)) return c
      var found = findModule(c, re)
      if (found) return found
    }
    return null
  }
  function updateKeepRect() {
    if (!root.barWindow) return
    var win = root.barWindow.contentItem
    var r = root.mapToItem(win, 0, 0, root.width, root.height)
    var clock = findModule(win, /clock/)
    if (clock) {
      var c = clock.mapToItem(win, 0, 0, clock.width, clock.height)
      var left = Math.min(r.x, c.x)
      var right = Math.max(r.x + r.width, c.x + c.width)
      r = Qt.rect(left, 0, right - left, win.height)
    }
    keepRect = r
  }
  Connections {
    target: card
    function onVisibleChanged() { if (card.visible) root.updateKeepRect() }
    function onOpenChanged() { if (card.open) root.updateKeepRect() }
  }

  readonly property bool bridgeOn: card.visible && !card.tucked && !!root.bar && !root.vertical && keepRect.width > 0
  readonly property color bridgeColor: Qt.rgba(card.tint.r, card.tint.g, card.tint.b, card.frostAlpha)
  readonly property real bridgeOpacity: Math.min(1, card.progress * 5)
  readonly property real surfLeft: Math.round(card.surfaceRect.x)
  readonly property real surfRight: Math.round(card.surfaceRect.x + card.surfaceRect.width)
  readonly property real keepLeft: Math.round(keepRect.x)
  readonly property real keepRight: Math.round(keepRect.x + keepRect.width)

  Rectangle {   // under the clock and the crab
    parent: root.barWindow ? root.barWindow.contentItem : null
    visible: root.bridgeOn
    x: Math.max(root.surfLeft, root.keepLeft)
    width: Math.max(0, Math.min(root.surfRight, root.keepRight) - x)
    height: parent ? parent.height : 0
    z: -1
    color: root.bridgeColor
    opacity: root.bridgeOpacity
  }

  Rectangle {   // over whatever is left of them
    parent: root.barWindow ? root.barWindow.contentItem : null
    visible: root.bridgeOn
    x: root.surfLeft
    width: Math.max(0, Math.min(root.keepLeft, root.surfRight) - root.surfLeft)
    height: parent ? parent.height : 0
    z: 50
    color: root.bridgeColor
    opacity: root.bridgeOpacity
  }

  Rectangle {   // and right of them
    parent: root.barWindow ? root.barWindow.contentItem : null
    visible: root.bridgeOn
    x: Math.max(root.surfLeft, root.keepRight)
    width: Math.max(0, root.surfRight - x)
    height: parent ? parent.height : 0
    z: 50
    color: root.bridgeColor
    opacity: root.bridgeOpacity
  }

  EdgeRipple {
    id: edgeRipple
    parent: root.barWindow ? root.barWindow.contentItem : null
    z: 101
    color: theme.fg
  }

  // ---- Approvals. approvals.py watch streams the prompts the hook is holding;
  //      answering writes the file the hook is polling for.
  readonly property string approvalsPath: decodeURIComponent(String(Qt.resolvedUrl("approvals.py")).replace(/^file:\/\//, ""))
  property var requests: []
  property var answeredIds: ({})
  // True while the card is up only because a prompt opened it: it closes
  // again once the last one is answered, and it doesn't grab focus from
  // whatever you were typing in.
  property bool autoOpened: false

  function applyRequests(line) {
    var data
    try { data = JSON.parse(line) } catch (e) { return }
    var fresh = (data.requests || []).filter(function(r) { return !root.answeredIds[r.id] })
    var grew = fresh.length > root.requests.length
    root.requests = fresh
    // The prompt is answered on Home (the live view shows it in place).
    if (grew && root.view !== "detail") root.view = "home"
    var focused = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    if (grew && !root.islandOpen && Link.approvalCrab(focused) === root) {
      root.autoOpened = true
      root.pinned = true
      root.open()
    } else if (fresh.length === 0 && root.autoOpened) {
      root.autoOpened = false
      root.close()
    }
  }

  // For Link.approvalCrab: is this copy actually on a bar, and which monitor.
  function drawn() {
    var slot = root.parent
    return root.visible && root.height > 0 && (!slot || (slot.visible && slot.height > 0))
  }
  function quickType(text) { liveKeys.field.text = text; liveKeys.field.cursorPosition = liveKeys.field.text.length }

  function state() {
    return { screen: screenName(), drawn: drawn(), cardOpen: card.open, pinned: root.pinned, view: root.view,
             quick: root.quickActive, search: root.searchActive, keysWanted: liveKeys.wanted, keysFocused: liveKeys.field.activeFocus,
             keyHandler: liveKeys.handler === root.quickKey ? "quick" : liveKeys.handler === root.searchKey ? "search"
               : liveKeys.handler === root.homeKey ? "home" : liveKeys.handler ? "other" : "none" }
  }
  function screenName() {
    return root.barWindow && root.barWindow.screen ? String(root.barWindow.screen.name || "") : ""
  }

  function sessionLabel(r) {
    for (var i = 0; i < sessions.length; i++)
      if (sessions[i].id === r.sessionId) return sessions[i].name
    var parts = (r.cwd || "").split("/")
    return parts[parts.length - 1] || ""
  }

  // answers: a question's, question → label(s).
  function answerRequest(r, choice, answers, inPlace) {
    var ids = root.answeredIds
    ids[r.id] = true
    root.answeredIds = ids
    // The answers (typed text, maybe) on stdin, out of argv.
    pipeOnce.createObject(root, { command: ["python3", "-I", root.approvalsPath, "answer", r.id, choice].concat(choice === "answer" ? ["-"] : []),
                                  input: choice === "answer" ? JSON.stringify(answers || {}) : "" })
    // Answered here, so take it off the card now rather than on the next poll.
    root.applyRequests(JSON.stringify({ requests: root.requests }))
    if (choice === "terminal" && !inPlace) {
      for (var i = 0; i < sessions.length; i++)
        if (sessions[i].id === r.sessionId) { root.focusSession(sessions[i]); break }
    }
  }

  Process {
    id: approvalsWatch
    command: ["python3", "-I", root.approvalsPath, "watch"]
    running: true
    stdout: SplitParser {
      onRead: function(data) { root.applyRequests(data) }
    }
    onExited: restartApprovals.start()
  }

  Timer {
    id: restartApprovals
    interval: 3000
    onTriggered: approvalsWatch.running = true
  }

  // ---- Launchers, as the old agents right-click menu had them: a talk-only
  //      chat (~/chat denies the file tools) or Claude Code in ~/Work.
  readonly property string chatCommand: setting("chatCommand", "cd ~/chat && omarchy-launch-tui --app-id=org.omarchy.agent {live} launch --chat")
  readonly property string codeCommand: setting("codeCommand", "cd ~/Work && omarchy-launch-tui --app-id=org.omarchy.agent {live} launch --permission-mode auto")
  readonly property string webCommand: setting("webCommand", "omarchy-launch-browser https://claude.ai")

  // {live} in a command is live.py: `{live} launch` starts Claude in the
  // background and attaches the window, so closing it leaves Claude working.
  readonly property string livePath: decodeURIComponent(String(Qt.resolvedUrl("live.py")).replace(/^file:\/\//, ""))

  // Makes the folder a leading `cd <dir> &&` goes to (~/chat on a first run).
  function withDir(command) {
    var dir = root.commandDir(command)
    return dir ? "mkdir -p '" + dir.replace(/'/g, "'\\''") + "' && " + command : command
  }

  function launch(command) {
    root.close()
    if (root.bar) root.bar.run(root.withDir(command).split("{live}").join("python3 -I '" + root.livePath + "'"))
  }

  // Chat / Code: start the session in the background and show it in the
  // card's live terminal instead of a terminal window. Commands without
  // {live} (a custom setting) still open as before.
  property string startingLabel: ""
  property string pendingLiveId: ""
  // Stands in for the new session until the feed lists it (about a second),
  // so the live terminal attaches straight away.
  property var pendingSession: null
  // The command being started, for the terminal fallback below.
  property string pendingCommand: ""
  property string pendingStdin: ""
  // Why the last start didn't make it into the card, shown for a while.
  property string startNotice: ""
  // The start a folder's missing trust stopped, while the card asks about
  // it: { dir, command, label, title }.
  property var trustAsk: null
  property string pendingLabel: ""
  property string pendingTitle: ""
  // The whole first prompt, for the conversation view to show while the session starts.
  property string pendingPrompt: ""

  // The folder a command's leading `cd <dir> &&` goes to, "" without one.
  readonly property var cdPrefix: /^\s*cd\s+(?:'([^']*)'|(\S+))\s*&&\s*/
  function commandDir(command) {
    var dir = command.match(root.cdPrefix)
    if (!dir) return ""
    return (dir[1] !== undefined ? dir[1] : dir[2].replace(/^~/, Quickshell.env("HOME"))).replace(/(.)\/+$/, "$1")
  }

  // label: the button showing its spinner meanwhile; title: the terminal's name until the feed has one.
  // Runs once with `input` on stdin, then goes (see Pipe.qml).
  Component { id: pipeOnce; Pipe { running: true; onRunningChanged: if (!running) destroy() } }

  // prompt: the first message, sent over stdin (never in a command line, where
  // other accounts' `ps` would read it).
  function launchInCard(command, label, title, prompt) {
    var re = /(omarchy-launch-tui\s+(--app-id=\S+\s+)?)?\{live\}\s+launch/
    if (!re.test(command)) { launch(command); return }
    if (root.terminalOutside) { root.openInTerminal(command, prompt); return }
    if (startProcess.running) return
    root.startingLabel = label
    root.autoOpened = false
    root.pendingSession = { name: title || label, cwd: root.commandDir(command), kind: "bg" }
    // Straight to the session's view, its terminal saying it's starting.
    root.newMenuOpen = false
    root.view = "detail"
    root.pendingCommand = command
    root.pendingStdin = prompt || ""
    root.pendingLabel = label
    root.pendingTitle = title || ""
    startProcess.command = ["bash", "-lc", root.withDir(command).replace(re, "python3 -I '" + root.livePath + "' start" + (prompt ? " --stdin-prompt" : ""))]
    startProcess.input = prompt || ""
    startProcess.running = true
  }

  Pipe {
    id: startProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var id = text.trim().split("\n").pop()
        root.startingLabel = ""
        if (!/^[0-9a-f]{6,}$/.test(id)) {
          console.warn("clawdius start", text)
          root.pendingSession = null
          root.pendingPrompt = ""
          if (root.view === "detail" && !root.liveId) root.view = root.detailFrom
          root.startFailed(text)
          return
        }
        // The feed needs a moment to list the new job; keep it open till then.
        var pending = root.pendingSession || {}
        root.pendingSession = { id: id, jobId: id, name: pending.name || "Claude", cwd: pending.cwd || "", kind: "bg" }
        root.pendingLiveId = id
        pendingClear.restart()
        root.liveId = id
        root.view = "detail"
        root.autoOpened = false
      }
    }
  }

  // Claude won't start a background session in a folder whose trust isn't
  // saved, so the card asks (Trust.qml) and saves it. Claude never saves it
  // for the home folder, so that one opens in a terminal window instead,
  // where Claude can ask. Anything else: say why.
  function startFailed(text) {
    var trust = /not trusted/i.test(text)
    var command = root.pendingCommand
    var prompt = root.pendingStdin
    var dir = root.commandDir(command)
    if (trust && dir !== "" && dir !== Quickshell.env("HOME")) {
      root.trustAsk = { dir: dir, command: command, prompt: prompt, label: root.pendingLabel, title: root.pendingTitle }
      root.pinned = true
      root.open()
      return
    }
    root.startNotice = trust
      ? "Claude Code won't run sessions in the home folder in the background, so it opened in a terminal."
      : "Couldn't start: " + (text.trim().split("\n")[0] || "claude --bg failed")
    noticeClear.restart()
    if (trust) root.openInTerminal(command, prompt)
  }

  function openInTerminal(command, prompt) {
    // Resume rows' commands have no terminal of their own.
    if (!/omarchy-launch-tui/.test(command))
      command = command.replace(/\{live\}\s+launch/, "omarchy-launch-tui --app-id=org.omarchy.agent {live} launch")
    if (!prompt) { root.launch(command); return }
    // A terminal window takes no stdin: the prompt waits in a private file.
    stashProcess.command = ["python3", "-I", root.livePath, "stash"]
    stashProcess.pendingCommand = command
    stashProcess.input = prompt
    stashProcess.running = true
  }

  Pipe {
    id: stashProcess
    property string pendingCommand: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = text.trim()
        if (path) root.launch(stashProcess.pendingCommand.replace(/\{live\}\s+launch/, "{live} launch --prompt-file " + root.shellQuote(path)))
      }
    }
  }

  // Trust.qml's answer: save the trust and start again, or not.
  function answerTrust(choice) {
    var ask = root.trustAsk
    if (!ask || trustProcess.running) return
    if (choice === "yes") {
      trustProcess.command = ["python3", "-I", root.livePath, "trust", ask.dir]
      trustProcess.running = true
      return
    }
    root.trustAsk = null
    if (choice === "terminal") root.openInTerminal(ask.command, ask.prompt)
  }

  Process {
    id: trustProcess
    stderr: StdioCollector { id: trustErr }
    onExited: function(code) {
      var ask = root.trustAsk
      root.trustAsk = null
      if (!ask) return
      if (code === 0) { root.launchInCard(ask.command, ask.label, ask.title, ask.prompt); return }
      root.startNotice = "Couldn't save the folder's trust: " + (trustErr.text.trim() || "live.py trust failed")
      noticeClear.restart()
    }
  }

  Timer {
    id: noticeClear
    interval: 15000
    onTriggered: root.startNotice = ""
  }

  Timer {
    id: pendingClear
    interval: 15000
    onTriggered: { root.pendingLiveId = ""; root.pendingSession = null; root.pendingPrompt = "" }
  }

  // Stop the empty ones. live.py leaves alone anything attached (a terminal,
  // the card's view) or only seconds old, so this can run on a timer.
  Timer {
    running: root.emptyJobs.length > 0
    interval: 25000
    repeat: true
    onTriggered: root.reapEmpty()
  }

  function reapEmpty() {
    if (root.emptyJobs.length && !reapProcess.running) {
      reapProcess.command = ["python3", "-I", root.livePath, "reap"].concat(root.emptyJobs)
      reapProcess.running = true
    }
  }

  Process { id: reapProcess }

  // ---- Sleep: idle background sessions are ~400 MB each, so live.py sweep
  //      stops the ones idle past idleStopMinutes, and the oldest beyond
  //      idleKeepRunning, unless something is still going on in them. The
  //      conversation stays: clicking one resumes it.
  readonly property int idleStopMinutes: Math.max(0, Number(setting("idleStopMinutes", 30)))
  readonly property int idleKeepRunning: Math.max(0, Number(setting("idleKeepRunning", 5)))
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/clawdius"
  // Everything the plugin keeps (prompts, replies, searches, reminders) is for
  // this account only: its folders are 0700, an older install's too.
  Process {
    running: true
    command: ["sh", "-c", 'umask 077; for d in "$@"; do mkdir -p "$d" && chmod -R go-rwx "$d"; done', "clawdius-private",
      root.stateDir,
      (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/clawdius",
      (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/clawdius",
      (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/clawdius"]
  }
  // Session id → ms it was put to sleep (live.py writes it).
  property var asleep: ({})
  // Put to sleep in the last 12 hours and not running again since.
  readonly property int asleepCount: {
    var n = 0
    var cutoff = root.now - 12 * 3600 * 1000
    for (var id in asleep) if (asleep[id] > cutoff && !runningStates[id]) n++
    return n
  }

  FileView {
    path: root.stateDir + "/asleep.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.asleep = JSON.parse(text()) || {} } catch (e) { root.asleep = {} } }
  }

  // Job id → why the last sweep left it running (live.py writes it); stale
  // once the sweep has stopped running, or is turned off.
  property var awakeRecord: ({})
  readonly property var awake: root.idleStopMinutes > 0 && root.now - (awakeRecord.at || 0) < 180000 ? awakeRecord.jobs || {} : ({})

  FileView {
    path: root.stateDir + "/awake.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.awakeRecord = JSON.parse(text()) || {} } catch (e) { root.awakeRecord = {} } }
  }

  Timer {
    running: root.idleStopMinutes > 0
    interval: 60000
    repeat: true
    onTriggered: root.sweepIdle()
  }

  function sweepIdle() {
    if (sweepProcess.running) return
    // The feed sees background shells and subagents in the transcript;
    // live.py checks the rest (attached, the job's own work, wakeups).
    var protect = root.liveId ? [root.liveId] : []
    for (var i = 0; i < feedSessions.length; i++) {
      var s = feedSessions[i]
      if (s.jobId && ((s.children || []).length || s.queued)) protect.push(s.jobId)
    }
    var argv = ["python3", "-I", root.livePath, "sweep", "--idle-min", String(root.idleStopMinutes), "--keep", String(root.idleKeepRunning)]
    if (protect.length) argv = argv.concat(["--protect"], protect)
    sweepProcess.command = argv
    sweepProcess.running = true
  }

  Process {
    id: sweepProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out
        try { out = JSON.parse(text) } catch (e) { if (text.trim()) console.warn("clawdius sweep", text); return }
        if (out.stopped && out.stopped.length)
          console.log("clawdius sweep stopped", out.stopped.map(function(r) { return r.name + " (" + r.why + ")" }).join(", "))
      }
    }
  }

  // Stop on an idle background row in Sessions → Live.
  function stopSession(s) {
    if (!s.jobId) return
    if (root.liveId === s.jobId) root.liveId = ""
    Quickshell.execDetached(["python3", "-I", root.livePath, "stop", s.jobId])
  }

  // Leaving an empty session: drop it once its viewer has let go. Its
  // detail view goes with it.
  onLiveIdChanged: {
    reapSoon.restart()
    if (!liveId && view === "detail") view = detailFrom
  }

  Timer {
    id: reapSoon
    interval: 2000
    onTriggered: root.reapEmpty()
  }

  // ---- Live terminal: one background session mirrored in the detail view.
  //      Showing it pins the card, since only a pinned card takes the keyboard.
  property string liveId: ""
  readonly property int terminalFontSize: Math.max(8, Number(setting("terminalFontSize", 13)))

  // A session clicked anywhere: a background one opens up close, live; a
  // terminal one comes forward.
  function openSession(s) {
    if (!s) return
    if (!s.jobId || root.terminalOutside) { root.focusSession(s); return }
    root.liveId = s.jobId
    root.view = "detail"
    root.autoOpened = false
  }

  // Every session opens as a conversation unless the terminal was chosen last
  // (the Detail view's button, kept in prefs.json). "Answer in terminal" shows
  // the terminal for that session only.
  property bool detailTerminal: false
  // Settings → Island: sessions open (and start) in a terminal window, never in the island.
  property bool terminalOutside: false
  // Settings → Island → Theme: "soft", "dev" (compact) or "dense"; Colors.look carries it to every view.
  property string islandLook: "soft"
  property var chatOverride: ({})
  readonly property bool detailChat: {
    var o = chatOverride[root.liveId || "starting"]
    return o !== undefined ? o : !root.detailTerminal
  }
  readonly property bool detailIsChatFolder: {
    var s = root.liveSession || root.pendingSession
    var dir = s ? String(s.workdir || s.cwd || "").replace(/(.)\/+$/, "$1") : ""
    return dir !== "" && dir === root.commandDir(root.chatCommand)
  }
  function toggleDetailChat() {
    root.chatOverride = ({})
    root.detailTerminal = root.detailChat
  }
  function answerInTerminal() {
    var next = Object.assign({}, root.chatOverride)
    next[root.liveId || "starting"] = false
    root.chatOverride = next
  }

  function collapseLive() {
    root.liveId = ""
    root.view = root.detailFrom
  }

  // Where the live terminal's typing actually lands (the card can't take keys).
  // Also the summoned island's, for its chatbox. Held while a session starts
  // too, so the focus doesn't drop (and close the card) on the way in.
  KeyWindow {
    id: liveKeys
    screen: root.barWindow ? root.barWindow.screen : null
    wanted: root.islandOpen && !root.keysOff && !root.livePicking && (root.terminalUp || root.quickActive || root.searchActive || root.homeKeys)
    cover: root.summoned
    hole: card.surfaceRect
    floatHole: card.floatRect
    barHeight: root.barWindow ? root.barWindow.height : 0
    onOutsideClicked: root.close()
    onEscapePressed: root.close()
  }

  // ---- The chat and search views take the keyboard (the key window holds
  //      it; what's typed is drawn by QuickChat / the nav's search bar).
  //      Summoned (Super+Alt+C, Alt+Space), the island opens on one of them;
  //      on the other views typing then opens the chatbox over them.
  //      Enter starts Chat or Code with the message as its first prompt and
  //      goes to its live view.
  property bool quickWanted: false
  // IPC testKeys(false): the views draw as usual but never take the keyboard
  // (screenshots while someone is typing elsewhere).
  property bool keysOff: false
  // Opened from the keyboard: the key window covers the screen around the
  // card (KeyWindow.qml), so it keeps the keyboard and a click outside closes.
  property bool summoned: false
  readonly property bool searchActive: view === "search"
  readonly property bool quickActive: view === "quick" || (quickWanted && view !== "detail" && view !== "search")
  // Chat or Code: whichever was used last (prefs.json, below).
  property string quickMode: "chat"
  // The model new Chat / Code sessions start on ("" = Claude's default), picked in the chat view.
  property string quickModel: ""
  // And the effort ("" = Claude's default), from the chip beside it.
  property string quickEffort: ""
  // Code's permission mode from the chat view; Opus Plan picks plan.
  property string quickPermission: "auto"
  // The folder Code starts in from the chat view ("" = the Code folder); not kept across restarts.
  property string quickDir: ""
  // Images pasted into the chat view (paths), sent along with its message.
  property var quickImages: []
  readonly property bool quickShown: quickActive && (liveKeys.field.text !== "" || quickImages.length > 0)
  // Home holds the keyboard too: typing there goes straight to Search. Only
  // with the pointer on it: opened on its own (a prompt, say) or from the
  // keyboard, it would take the keys from the window you're in. Let go a
  // moment late, so crossing from the crab to the card doesn't flicker it.
  readonly property bool homeKeys: islandOpen && view === "home" && pointerNear
  readonly property bool pointerHere: card.containsMouse || glyphArea.containsMouse || clockHovered || zoneHovered
  property bool pointerNear: false
  onPointerHereChanged: if (pointerHere) { pointerNear = true; pointerGone.stop() } else pointerGone.restart()
  Timer { id: pointerGone; interval: 300; onTriggered: root.pointerNear = false }
  // The search bar's chip: "" | "terminal" (`/ `) | "google" (`/g `).
  property string searchChip: ""

  function summon(which) {
    which = which || "quick"
    if (card.open && root.pinned && liveKeys.field.activeFocus && root.view === which) { root.close(); return }
    root.newMenuOpen = false
    // The view first, so opening doesn't reset it to Home.
    root.summoned = true
    root.view = which
    root.pinned = true
    root.quickWanted = true
    root.open()
    liveKeys.prime()
  }

  // The nav's chat icon, Home's New chat, the search icon. A click inside
  // doesn't pin: opened by hovering, it still goes when the pointer leaves.
  function openView(which) {
    root.newMenuOpen = false
    root.autoOpened = false
    root.view = which
  }

  function routeKeys() {
    if (root.searchActive) liveKeys.handler = root.searchKey
    else if (root.quickActive) liveKeys.handler = root.quickKey
    else if (root.homeKeys) liveKeys.handler = root.homeKey
  }
  onQuickActiveChanged: routeKeys()
  onHomeKeysChanged: routeKeys()
  onSearchActiveChanged: {
    routeKeys()
    if (searchActive && !tabsProcess.running) tabsProcess.running = true
  }

  function shellQuote(text) { return "'" + String(text).replace(/'/g, "'\\''") + "'" }

  function quickKey(event) {
    var plain = !(event.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier))
    var field = liveKeys.field
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && plain) { root.sendQuick(); return true }
    // An image on the clipboard joins the message; text still pastes as usual.
    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) { if (!quickGrab.running) quickGrab.running = true; return false }
    if (event.key === Qt.Key_Backspace && field.text === "" && root.quickImages.length > 0) {
      root.quickImages = root.quickImages.slice(0, -1)
      return true
    }
    // Tab switches Chat / Code; ⇧Tab cycles Code's permission mode, as in the CLI.
    if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
      if (root.quickMode === "code" && (field.text !== "" || root.view === "quick")) quickChat.cyclePermission()
      return true
    }
    if (event.key === Qt.Key_Tab) {
      if (field.text !== "" || root.view === "quick") root.quickMode = root.quickMode === "chat" ? "code" : "chat"
      return true
    }
    return false
  }

  // A character (or a paste) on Home starts a fresh search with it; the
  // rest is eaten so nothing collects in the field unseen.
  function homeKey(event) {
    var mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)
    var paste = event.matches(StandardKey.Paste)
    var typed = !mods && /^[^\x00-\x20\x7f]/.test(event.text)
    if (!typed && !paste) return true
    root.openView("search")
    root.searchChip = ""
    liveKeys.field.text = typed ? event.text : ""
    liveKeys.field.cursorPosition = liveKeys.field.text.length
    return typed
  }

  Process {
    id: quickGrab
    command: ["python3", "-I", root.livePath, "grab"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = text.trim()
        if (path[0] === "/") root.quickImages = root.quickImages.concat([path])
      }
    }
  }

  function sendQuick() {
    var text = liveKeys.field.text.trim()
    var images = root.quickImages
    if ((!text && !images.length) || startProcess.running) return
    var code = root.quickMode === "code"
    var model = /^[\w.\-\[\]]+$/.test(root.quickModel) ? " --model " + root.quickModel : ""
    var effort = /^(low|medium|high|xhigh|max)$/.test(root.quickEffort) ? " --effort " + root.quickEffort : ""
    var base = code ? root.codeCommand : root.chatCommand
    if (code) base = /--permission-mode\s+\S+/.test(base) ? base.replace(/--permission-mode\s+\S+/, "--permission-mode " + root.quickPermission) : base + " --permission-mode " + root.quickPermission
    if (code && root.quickDir) base = "cd " + root.shellQuote(root.quickDir) + " && " + base.replace(root.cdPrefix, "")
    // Claude attaches an @-mentioned image as it does a pasted one.
    var prompt = images.map(function(p) { return "@" + p + " " }).join("") + text
    var shown = text || (images.length > 1 ? images.length + " images" : "Image")
    var command = base + model + effort
    liveKeys.field.text = ""
    root.quickImages = []
    root.pendingPrompt = code ? "" : shown
    root.launchInCard(command, code ? "Code" : "Chat", shown.split("\n")[0].slice(0, 60), prompt)
  }

  // ---- Search. Typing `/ ` or `/g ` at the start turns it into a chip;
  //      Backspace at the start of the text takes the chip back to what was
  //      typed, the caret just after it.
  Connections {
    target: liveKeys.field
    enabled: root.searchActive
    function onTextChanged() { root.checkChip() }
  }

  function checkChip() {
    if (root.searchChip !== "") return
    var field = liveKeys.field
    var m = field.text.match(/^\/(g)? /)
    if (!m) return
    root.searchChip = m[1] ? "google" : "terminal"
    field.text = field.text.slice(m[0].length)
    field.cursorPosition = field.text.length
  }

  function searchKey(event) {
    var field = liveKeys.field
    var key = event.key
    if (key === Qt.Key_Return || key === Qt.Key_Enter) { searchView.activate(); return true }
    if (key === Qt.Key_Down || key === Qt.Key_Tab || (key === Qt.Key_Right && searchView.suggesting)) { searchView.move(1); return true }
    if (key === Qt.Key_Up || key === Qt.Key_Backtab || (key === Qt.Key_Left && searchView.suggesting)) { searchView.move(-1); return true }
    if (key === Qt.Key_Backspace && root.searchChip !== "" && field.cursorPosition === 0 && field.selectionStart === field.selectionEnd) {
      var typed = root.searchChip === "google" ? "/g" : "/"
      root.searchChip = ""
      field.insert(0, typed)
      field.cursorPosition = typed.length
      return true
    }
    return false
  }

  function launchApp(entry) {
    if (!entry || !entry.id) return
    root.noteApp(entry.id)
    root.close()
    liveKeys.field.text = ""
    Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", entry.id + ".desktop"])
  }

  // `/ ls -la`: in a new terminal, which stays open on a shell afterwards.
  function runCommand(text) {
    root.noteSearch("terminal", text)
    root.close()
    liveKeys.field.text = ""
    // The command stays out of the terminal's command line: a private file, run once.
    runStash.input = text
    runStash.running = true
  }

  Pipe {
    id: runStash
    command: ["python3", "-I", root.livePath, "stash"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = text.trim()
        if (path) Quickshell.execDetached(["omarchy-launch-terminal", "bash", "-ic", '. "$0"; rm -f -- "$0"; exec bash', path])
      }
    }
  }

  // ---- The default browser's recent tabs, beside the apps (tabs.py), read
  //      each time the search view opens.
  readonly property string tabsPath: decodeURIComponent(String(Qt.resolvedUrl("tabs.py")).replace(/^file:\/\//, ""))
  property var browserTabs: []

  Process {
    id: tabsProcess
    command: ["python3", "-I", root.tabsPath, "5"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.browserTabs = JSON.parse(text) } catch (e) { console.warn("clawdius tabs parse", e) }
      }
    }
  }

  // Opens it again in the browser: there's no reaching an open tab from here.
  function openTab(tab) {
    root.close()
    liveKeys.field.text = ""
    Quickshell.execDetached(["omarchy-launch-browser", tab.url])
  }

  function pageTabs(delta) { searchView.pageTabs(delta) }

  // A sum's result, Enter on it: to the clipboard, the island closed.
  function copyResult(text) {
    root.close()
    liveKeys.field.text = ""
    pipeOnce.createObject(root, { command: ["wl-copy"], input: text })
  }

  function googleSearch(text) {
    root.noteSearch("google", text)
    root.close()
    liveKeys.field.text = ""
    Quickshell.execDetached(["omarchy-launch-browser", "https://www.google.com/search?q=" + encodeURIComponent(text)])
  }

  // ---- Recent searches: the commands and Google searches that were run,
  //      newest first, as chips at the search bar's right (prefs.json).
  property var recentSearches: []

  function noteSearch(kind, text) {
    text = String(text || "").trim()
    if (!text) return
    var list = [{ kind: kind, text: text }]
    for (var i = 0; i < root.recentSearches.length && list.length < 8; i++) {
      var r = root.recentSearches[i]
      if (r.kind !== kind || r.text !== text) list.push(r)
    }
    root.recentSearches = list
  }

  // A chip puts the search back in the bar, chip and text, for Enter to run
  // (a command isn't run on a click).
  function reuseSearch(r) {
    root.searchChip = r.kind
    liveKeys.field.text = r.text
    liveKeys.field.cursorPosition = r.text.length
    liveKeys.prime()
  }

  // ---- App usage, for the search view's suggestions: launches from search,
  //      and every window that comes to the front (one crab records it).
  property var appUsage: ({})

  FileView {
    id: appsFile
    path: root.stateDir + "/apps.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.appUsage = JSON.parse(text()) || {} } catch (e) { root.appUsage = {} } }
  }

  function noteApp(id) {
    if (!id) return
    var usage = {}
    for (var k in root.appUsage) usage[k] = root.appUsage[k]
    var u = usage[id] || { n: 0, t: 0 }
    usage[id] = { n: (u.n || 0) + 1, t: Date.now() }
    // Keep the 150 most recent.
    var ids = Object.keys(usage).sort(function(a, b) { return usage[b].t - usage[a].t })
    for (var i = 150; i < ids.length; i++) delete usage[ids[i]]
    root.appUsage = usage
    appsSave.restart()
  }

  Timer {
    id: appsSave
    interval: 1500
    onTriggered: appsFile.setText(JSON.stringify(root.appUsage))
  }

  // ---- Timers, alarms and the posture check (Corner.qml). The
  //      list lives in timers.json; every crab shows it, only the leader
  //      rings what's due, so a two-monitor bar doesn't ring twice.
  property var timers: []           // {id, kind: timer | alarm, label, at, len}
  property var posture: ({ on: false, everyMin: 30, nextAt: 0, awaySince: 0, pausedLeft: 0, rested: false })
  // The stand-up-and-walk nudge: the same shape, a longer wait.
  property var walk: ({ on: false, everyMin: 60, nextAt: 0, awaySince: 0, pausedLeft: 0, rested: false })
  property string cornerMode: "limits"
  // The corner mode to come back to from Stuck, which isn't remembered.
  property string lastCornerMode: "limits"
  readonly property bool repInProgress: !!root.antirot && !!root.antirot.today && !!root.antirot.today.startedAt && !root.antirot.today.passedAt
  // Stuck's help, asked for with the rep's "Stuck?" pill. It shows over the
  // corner while Anti-rot is the main card; another main tab or corner tab
  // hides it (helpAway), and Anti-rot coming back brings it back.
  property bool helpOpen: false
  property bool helpAway: false
  readonly property bool stuckShown: helpOpen && repInProgress && mainShown === "antirot" && !helpAway
  readonly property string cornerShown: stuckShown ? "stuck" : cornerMode
  onRepInProgressChanged: if (!repInProgress) helpOpen = false
  // Home's main card: agents | today | antirot. What needs you shows Agents
  // whatever was picked; the pick comes back after. A finished turn doesn't
  // force it: the Agents tab wears a green dot instead.
  property string mainMode: "agents"
  readonly property string mainShown: ["approval", "waiting", "failed", "limited"].indexOf(root.moment.kind) >= 0 ? "agents" : root.mainMode
  property int postureRings: 0
  property int walkRings: 0
  readonly property bool nudging: root.posture.on || root.walk.on

  FileView {
    id: timersFile
    path: root.stateDir + "/timers.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var d = JSON.parse(text()) || {}
        root.timers = d.timers || []
        root.posture = Object.assign({ on: false, everyMin: 30, nextAt: 0, awaySince: 0, pausedLeft: 0, rested: false }, d.posture || {})
        root.walk = Object.assign({ on: false, everyMin: 60, nextAt: 0, awaySince: 0, pausedLeft: 0, rested: false }, d.walk || {})
        // The Anti-rot tab moved to the main card.
        root.lastCornerMode = !d.mode || d.mode === "antirot" || d.mode === "stuck" ? "limits" : d.mode
        root.cornerMode = root.lastCornerMode
        root.mainMode = d.main || "agents"
      } catch (e) { console.warn("clawdius timers parse", e) }
    }
  }

  Timer {
    id: timersSave
    interval: 300
    onTriggered: timersFile.setText(JSON.stringify({ timers: root.timers, posture: root.posture, walk: root.walk, mode: root.lastCornerMode, main: root.mainMode }))
  }

  function addTimer(kind, label, at, len) {
    root.timers = root.timers.concat([{ id: Timers.id(), kind: kind, label: label, at: at, len: len }])
    timersSave.restart()
  }

  function cancelTimer(id) {
    root.timers = root.timers.filter(function(t) { return t.id !== id })
    timersSave.restart()
  }

  // key: "posture" | "walk".
  function setNudge(key, patch) {
    var p = Object.assign({}, root[key], patch)
    // Turning it on, or changing how often, counts from now.
    if ((patch.on && !root[key].on) || (patch.everyMin && p.on)) {
      p.nextAt = Date.now() + p.everyMin * 60000
      p.awaySince = 0
      p.pausedLeft = 0
      p.rested = false
    }
    if (patch.on === false) { p.awaySince = 0; p.pausedLeft = 0; p.rested = false }
    root[key] = p
    timersSave.restart()
  }

  function pickCorner(mode) {
    if (mode === "stuck") { root.helpAway = false; return }
    root.cornerMode = mode
    root.lastCornerMode = mode
    root.helpAway = true
    timersSave.restart()
  }

  function pickMain(mode) {
    root.mainMode = mode
    if (mode === "antirot") root.helpAway = false
    timersSave.restart()
  }

  // The clock's click: the island, pinned, on Today.
  function openToday() {
    root.view = "home"
    root.pickMain("today")
    root.pinned = true
    root.open()
  }

  // ---- Weather (wttr.in, the place from Omarchy's weather setting, else the
  //      IP's): one report in stateDir/weather.json, fetched by whichever crab
  //      sees it stale, read by every crab. Today shows it.
  property var weather: null
  property double weatherAt: 0
  property string weatherPlace: ""
  readonly property string weatherPath: root.stateDir + "/weather.json"

  FileView {
    id: weatherFile
    path: root.weatherPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var d = JSON.parse(text())
        root.weatherAt = d.at || 0
        root.weather = Weather.parse(JSON.stringify(d.report), Weather.imperial(Qt.locale().name), new Date().getHours())
      } catch (e) { console.warn("clawdius weather parse", e) }
    }
  }

  // The configured place's path segment: "lat,lon", else the name; blank asks the IP.
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var d = JSON.parse(text())
        var lat = parseFloat(d.latitude), lon = parseFloat(d.longitude)
        root.weatherPlace = !isNaN(lat) && !isNaN(lon) ? lat + "," + lon : encodeURIComponent(String(d.name || "").trim())
      } catch (e) { root.weatherPlace = "" }
    }
  }

  function fetchWeather(maxAgeMs) {
    if (weatherProcess.running || Date.now() - root.weatherAt < maxAgeMs) return
    // The place is the user's location: curl reads the URL from stdin.
    weatherProcess.command = ["curl", "-fsS", "--max-time", "10", "-K", "-"]
    weatherProcess.input = 'url = "https://wttr.in/' + root.weatherPlace + '?format=j1"\n'
    weatherProcess.running = true
  }

  Pipe {
    id: weatherProcess
    stdout: StdioCollector { id: weatherOut }
    onExited: function(code) {
      if (code !== 0) return
      try { weatherFile.setText(JSON.stringify({ at: Date.now(), report: JSON.parse(weatherOut.text) })) } catch (e) {}
    }
  }

  Timer {
    interval: 30 * 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (Link.isLeader(root)) root.fetchWeather(25 * 60000)
  }

  // The leader's check, once a second while anything is set.
  function ringDue() {
    if (!Link.isLeader(root)) return
    // Left frozen by a shell restart while away: back now, so pick it up.
    if ((root.posture.awaySince > 0 || root.walk.awaySince > 0) && !idleMonitor.isIdle) root.postureIdle(false)
    var t = Date.now()
    var due = root.timers.filter(function(x) { return x.at <= t })
    var posturing = root.posture.on && !root.posture.awaySince && root.posture.nextAt > 0 && root.posture.nextAt <= t
    var walking = root.walk.on && !root.walk.awaySince && root.walk.nextAt > 0 && root.walk.nextAt <= t
    if (!due.length && !posturing && !walking) return
    if (due.length) root.timers = root.timers.filter(function(x) { return x.at > t })
    if (posturing) {
      var p = Object.assign({}, root.posture)
      p.nextAt = t + p.everyMin * 60000
      p.rested = false
      root.posture = p
      root.postureRings++
    }
    if (walking) {
      var w = Object.assign({}, root.walk)
      w.nextAt = t + w.everyMin * 60000
      w.rested = false
      root.walk = w
      root.walkRings++
    }
    timersSave.restart()
    var focused = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    var crab = Link.openCrab() || Link.approvalCrab(focused) || root
    if (due.length) {
      var first = due[0]
      var late = t - first.at > 90000
      crab.ring({ kind: "timer", status: Timers.ringName(first.kind), name: first.label,
        text: late ? "Was due " + Qt.formatDateTime(new Date(first.at), "HH:mm") : "Time's up.",
        meta: due.length > 1 ? ["+" + (due.length - 1) + " more"] : [], at: t, id: "" })
    } else if (posturing) {
      crab.ring({ kind: "posture", status: "Posture check", name: "Sit up", text: Timers.postureLine(root.postureRings), meta: ["next in " + Timers.span(root.posture.everyMin)], at: t, id: "" })
    } else {
      crab.ring({ kind: "walk", status: "Move break", name: "Stand up", text: Timers.walkLine(root.walkRings), meta: ["next in " + Timers.span(root.walk.everyMin)], at: t, id: "" })
    }
  }

  // Away from the keyboard (2 minutes without input, a playing video counts
  // as there): the nudge count waits, from when you left. Back after a real
  //  break (5 minutes), it starts over; after a short one it carries on.
  function postureIdle(idle) {
    if (!Link.isLeader(root) || !root.nudging) return
    var t = Date.now()
    var changed = false
    ;["posture", "walk"].forEach(function(key) {
      if (!root[key].on) return
      var p = Object.assign({}, root[key])
      if (idle && !p.awaySince) {
        p.awaySince = t - 120000
        p.pausedLeft = Math.max(0, p.nextAt - p.awaySince)
      } else if (!idle && p.awaySince) {
        var rested = t - p.awaySince >= 300000
        p.nextAt = t + (rested ? p.everyMin * 60000 : p.pausedLeft)
        p.rested = rested
        p.awaySince = 0
        p.pausedLeft = 0
      } else return
      root[key] = p
      changed = true
    })
    if (changed) timersSave.restart()
  }

  IdleMonitor {
    id: idleMonitor
    enabled: root.nudging
    timeout: 120
    respectInhibitors: true
    onIsIdleChanged: root.postureIdle(isIdle)
  }

  // A timer or nudge going off: a toast in the island, and a sound.
  function ring(t) {
    root.lastToastAt = t.at
    root.toast = t
    toastTimer.interval = 15000
    toastTimer.restart()
    root.showPeek()
    if (setting("timerSound", true)) {
      chime.command = ["pw-play", "/usr/share/sounds/freedesktop/stereo/" + (t.kind === "posture" || t.kind === "walk" ? "bell" : "alarm-clock-elapsed") + ".oga"]
      chime.running = true
    }
  }

  Process {
    id: chime
    onExited: running = false
  }

  Timer {
    running: root.timers.length > 0 || root.nudging
    interval: 1000
    repeat: true
    onTriggered: root.ringDue()
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() {
      var top = ToplevelManager.activeToplevel
      if (!top || !Link.isLeader(root)) return
      var entry = DesktopEntries.heuristicLookup(top.appId || "")
      if (entry && entry.id) root.noteApp(entry.id)
    }
  }

  // ---- Prefs: the chat view's last mode.
  FileView {
    id: prefsFile
    path: root.stateDir + "/prefs.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var prefs = JSON.parse(text()) || {}
        if (prefs.quickMode === "chat" || prefs.quickMode === "code") root.quickMode = prefs.quickMode
        root.detailTerminal = prefs.detailView === "terminal"
        root.terminalOutside = prefs.terminalOutside === true
        root.islandLook = prefs.islandLook === "dev" || prefs.islandLook === "dense" ? prefs.islandLook : "soft"
        if (typeof prefs.quickModel === "string") root.quickModel = prefs.quickModel
        if (typeof prefs.quickEffort === "string") root.quickEffort = prefs.quickEffort
        if (/^(auto|plan|acceptEdits|default)$/.test(prefs.quickPermission)) root.quickPermission = prefs.quickPermission
        if (Array.isArray(prefs.starredIds)) root.starredIds = prefs.starredIds.filter(function(i) { return typeof i === "string" })
        if (Array.isArray(prefs.recentSearches)) root.recentSearches = prefs.recentSearches.filter(function(r) {
          return r && (r.kind === "terminal" || r.kind === "google") && typeof r.text === "string" && r.text !== ""
        }).slice(0, 8)
      } catch (e) {}
    }
  }
  onDetailTerminalChanged: prefsSave.restart()
  onTerminalOutsideChanged: prefsSave.restart()
  onIslandLookChanged: prefsSave.restart()
  onQuickModeChanged: prefsSave.restart()
  onQuickModelChanged: prefsSave.restart()
  onQuickEffortChanged: prefsSave.restart()
  onQuickPermissionChanged: prefsSave.restart()
  onRecentSearchesChanged: prefsSave.restart()
  onStarredIdsChanged: prefsSave.restart()
  Timer {
    id: prefsSave
    interval: 300
    onTriggered: prefsFile.setText(JSON.stringify({ detailView: root.detailTerminal ? "terminal" : "chat", terminalOutside: root.terminalOutside, islandLook: root.islandLook, quickMode: root.quickMode, quickModel: root.quickModel, quickEffort: root.quickEffort, quickPermission: root.quickPermission, recentSearches: root.recentSearches, starredIds: root.starredIds }))
  }

  // ---- Daily reps (antirot.py): today's exercise on Home's idle moment, the
  //      languages in Settings. antirot.py is the only writer of antirot.json; every
  //      crab watches it. Its actions run one at a time.
  readonly property string antirotPath: decodeURIComponent(String(Qt.resolvedUrl("antirot.py")).replace(/^file:\/\//, ""))
  property var antirot: null
  property var antirotQueue: []
  // The action running ("" when none) and its language, for the spinners.
  property string antirotBusy: ""
  property string antirotBusyLang: ""

  FileView {
    path: root.stateDir + "/antirot.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.antirot = JSON.parse(text()) } catch (e) { console.warn("clawdius antirot parse", e) } }
  }

  function runAntirot(args, lang) {
    // Opening the island twice needn't check the day twice.
    if (args[0] === "today" && (root.antirotBusy === "today" || root.antirotQueue.some(function(q) { return q.args[0] === "today" }))) return
    root.antirotQueue = root.antirotQueue.concat([{ args: args, lang: lang }])
    root.nextAntirot()
  }

  function nextAntirot() {
    if (antirotProcess.running || !root.antirotQueue.length) return
    var job = root.antirotQueue[0]
    root.antirotQueue = root.antirotQueue.slice(1)
    root.antirotBusy = job.args[0]
    root.antirotBusyLang = job.lang
    antirotProcess.command = ["python3", "-I", root.antirotPath].concat(job.args)
    antirotProcess.running = true
  }

  Process {
    id: antirotProcess
    stdout: StdioCollector { id: antirotOut }
    stderr: StdioCollector { id: antirotErr }
    onExited: function(code) {
      var action = root.antirotBusy
      root.antirotBusy = ""
      root.antirotBusyLang = ""
      if (code !== 0) {
        root.startNotice = antirotErr.text.trim().split("\n").pop() || "antirot.py " + action + " failed"
        noticeClear.restart()
      } else if (action === "start") {
        var lines = antirotOut.text.split("\n")
        if (lines[0]) root.openChallenge(lines[0], lines[1])
      }
      root.nextAntirot()
    }
  }

  // Open a rep file in the editor chosen in Settings, else Omarchy's default.
  // Terminal editors get a window of their own, as omarchy-launch-editor does.
  // The task's instructions open beside the solution: the card only has the blurb.
  function openChallenge(file, docs) {
    var files = (docs ? root.shellQuote(docs) + " " : "") + root.shellQuote(file)
    var editor = root.antirot && root.antirot.editor ? root.antirot.editor : ""
    if (!editor) { root.launch("omarchy-launch-editor " + files); return }
    var tui = ["nvim", "vim", "nano", "micro", "hx", "helix"].indexOf(editor) >= 0
    var split = docs && (editor === "nvim" || editor === "vim") ? " -O" : ""
    root.launch((tui ? "omarchy-launch-tui " : "setsid uwsm-app -- ") + editor + split + " -- " + files)
  }

  // The rep card's buttons.
  function challengeAction(action) {
    var rep = root.antirot ? root.antirot.today : null
    if (action === "settings") root.view = "settings"
    else if (action === "open" && rep && rep.file) root.openChallenge(rep.file, rep.docs || (rep.dir ? rep.dir + "/.docs/instructions.md" : ""))
    else if (action === "review" && rep && rep.dir) root.reviewChallenge(rep)
    else if (action === "stuck") {
      root.helpOpen = !root.stuckShown
      root.helpAway = false
    }
    else if (["start", "check", "easier", "skip", "next"].indexOf(action) >= 0) root.runAntirot([action], rep ? rep.lang : "")
  }

  // Claude looks over the passed rep in the live terminal, read only. A new
  // rep folder isn't trusted yet: answerTrust saves that, then starts it.
  function reviewChallenge(rep) {
    var lang = root.antirot.info && root.antirot.info[rep.lang] ? root.antirot.info[rep.lang].name : rep.lang
    var prompt = "Review my solution to the Exercism exercise \"" + rep.name + "\" in " + lang
      + " (this folder; the task is in .docs/). I wrote it by hand to get my skills back, so teach rather than fix:"
      + " what's idiomatic and what isn't, edge cases the tests miss, and what a senior " + lang + " developer would change."
      + " Short snippets at most, never a whole rewrite."
      + (rep.example ? " After your own review, compare it with Exercism's reference solution at " + rep.example + "." : "")
    var command = "cd " + root.shellQuote(rep.dir) + " && {live} launch"
      + (rep.example ? " --add-dir " + root.shellQuote(rep.example.replace(/\/[^\/]*\/[^\/]*$/, "")) : "")
      + " --disallowedTools Edit,Write,MultiEdit,NotebookEdit -- " + root.shellQuote(prompt)
    root.trustAsk = { dir: rep.dir, command: command, label: "Review", title: "Review: " + rep.name }
    root.answerTrust("yes")
  }

  readonly property bool keysView: root.quickActive || root.searchActive
  // RestoreNone: the live terminal's own bindings (LiveTerm) set these too,
  // and a binding let go puts back whatever it found, which can be the other
  // view's size. The caret is placed from what's drawn either way (MirrorInput).
  Binding { target: liveKeys; property: "fieldWidth"; value: root.searchActive ? searchInput.width : quickChat.inputWidth; when: root.keysView; restoreMode: Binding.RestoreNone }
  Binding { target: liveKeys; property: "fontSize"; value: root.searchActive ? Style.font.subtitle : root.terminalFontSize; when: root.keysView; restoreMode: Binding.RestoreNone }
  Binding { target: liveKeys; property: "fieldWrap"; value: !root.searchActive; when: root.keysView; restoreMode: Binding.RestoreNone }

  // The key window holds the keyboard while the terminal shows; clicks in
  // the card leave it there (the bar never takes the keyboard). Losing it
  // means you clicked or switched to another window: close, unless the
  // pointer is still on the card.
  Connections {
    target: liveKeys.field
    function onActiveFocusChanged() {
      if (!liveKeys.field.activeFocus && (root.terminalUp || root.keysView || root.homeKeys) && root.islandOpen) liveFocusLost.restart()
    }
  }

  Timer {
    id: liveFocusLost
    interval: 180
    onTriggered: if (!liveKeys.settling && !root.livePicking && !liveKeys.field.activeFocus && (root.terminalUp || root.keysView || root.homeKeys) && root.islandOpen && !card.containsMouse) root.close()
  }

  // A quick second click on Search or Chat lands while the key window is
  // priming, and the pointer reads as gone from the card for a moment (see
  // KeyWindow's settling). Only once it has settled does a leave count.
  Connections {
    target: liveKeys
    function onSettlingChanged() {
      if (liveKeys.settling) return
      root.maybeClose()
      liveFocusLost.restart()
    }
  }

  // Drop it once the session is gone.
  // (Against the feed's own list: `sessions` depends on liveId.)
  onFeedSessionsChanged: {
    if (pendingSession && feedSessions.some(function(s) { return s.jobId === root.pendingLiveId })) pendingSession = null
    if (liveId && liveId !== pendingLiveId && !feedSessions.some(function(s) { return s.jobId === liveId })) liveId = ""
  }

  // ---- Views: home | quick (new chat) | sessions | search | stats | detail | settings.
  //      Opening goes back to Home, unless a live terminal is up or it was
  //      summoned onto a view.
  property string view: "home"
  property string lastView: "home"
  // What was typed in the chat and search views, kept apart: they share the
  // key window's one field.
  property var drafts: ({ quick: "", search: "" })
  // Sessions' segments: live | recent | folders.
  property string sessionsTab: "live"
  // Where Collapse goes back to from the detail view.
  property string detailFrom: "home"
  property bool newMenuOpen: false
  onViewChanged: {
    var from = lastView
    lastView = view
    // First, so the island's height eases whatever the switch resizes. Only
    // into and out of the live view: the popup itself resizes when it ends.
    if (view === "detail" || from === "detail") viewMorph.restart()
    if (from !== view && (from === "quick" || from === "search" || view === "quick" || view === "search")) {
      var d = drafts
      if (from === "quick" || from === "search") d[from] = liveKeys.field.text
      liveKeys.field.text = view === "quick" || view === "search" ? d[view] || "" : ""
      liveKeys.field.cursorPosition = liveKeys.field.text.length
      drafts = d
      if (from === "search") searchChip = ""
    }
    if (card.open && card.containsMouse) { viewHold = true; viewHoldEnd.stop(); viewHoldCheck.restart() }
    if (view !== "detail") detailFrom = view
    else if (!liveId && !startingLabel) view = detailFrom
    tallView = view === "detail"
    newMenuOpen = false
    if (card.visible) viewEnter.restart()
  }

  // The live view's taller cap, switched only once the morph is armed.
  property bool tallView: false

  Timer {
    id: viewMorph
    interval: 420
  }

  // The new view eases up into place while the island grows or folds to it.
  ParallelAnimation {
    id: viewEnter
    NumberAnimation { target: body; property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
    NumberAnimation { target: body; property: "scale"; from: 0.985; to: 1; duration: 380; easing.type: Easing.OutQuint }
    NumberAnimation { target: bodyShift; property: "y"; from: Style.space(14); to: 0; duration: 380; easing.type: Easing.OutQuint }
  }

  // ---- Resume: recent sessions that are not running, newest first.
  //      History: every other conversation on disk, older ones and those
  //      whose folder is gone included.
  readonly property string resumablePath: decodeURIComponent(String(Qt.resolvedUrl("resumable.py")).replace(/^file:\/\//, ""))
  property var resumable: []
  readonly property var notRunning: {
    var live = {}
    for (var i = 0; i < feedSessions.length; i++) live[feedSessions[i].id] = true
    return resumable.filter(function(r) { return !live[r.id] })
  }
  readonly property var resumableIdle: notRunning.filter(function(r) { return !r.missing }).slice(0, 8)
  readonly property var history: {
    var inResume = {}
    for (var i = 0; i < resumableIdle.length; i++) inResume[resumableIdle[i].id] = true
    return notRunning.filter(function(r) { return !inResume[r.id] })
  }

  function refreshResumable() {
    if (!resumeProcess.running) resumeProcess.running = true
  }

  // ---- Folders: where the conversations on disk ran, newest first, one row
  //      each. Not the Chat / Code folders (their buttons open there), nor
  //      folders that are gone, nor scratch ones (background jobs' /tmp
  //      scratchpads, ~/.claude job dirs and worktrees).
  readonly property var recentFolders: {
    var skip = {}
    skip[root.commandDir(root.chatCommand)] = true
    skip[root.commandDir(root.codeCommand)] = true
    var scratch = new RegExp("^(/tmp/|" + Quickshell.env("HOME") + "/\\.claude/)")
    var seen = {}
    var out = []
    for (var i = 0; i < resumable.length; i++) {
      var r = resumable[i]
      if (r.missing || !r.cwd || skip[r.cwd] || scratch.test(r.cwd)) continue
      var f = seen[r.cwd]
      if (!f) {
        f = seen[r.cwd] = { cwd: r.cwd, mtime: r.mtime, count: 0, title: r.title, sessions: [] }
        out.push(f)
      }
      f.count++
      f.sessions.push(r)
    }
    return out.slice(0, 20)
  }

  // Session id → busy / waiting / idle, for the ones running now.
  readonly property var runningStates: {
    var states = {}
    for (var i = 0; i < feedSessions.length; i++) {
      var s = feedSessions[i]
      states[s.id] = s.waiting ? "waiting" : s.busy ? "busy" : "idle"
    }
    return states
  }

  // A session listed under a folder: a running background one shows live,
  // a running terminal one comes forward, anything else resumes in the card.
  function openFolderSession(r) {
    for (var i = 0; i < feedSessions.length; i++) {
      var s = feedSessions[i]
      if (s.id !== r.id) continue
      root.openSession(s)
      return
    }
    root.resumeSession(r, r.id)
  }

  // A new session in that folder: the Code command, with its `cd` swapped.
  function startInFolder(cwd) {
    var dir = "cd '" + String(cwd).replace(/'/g, "'\\''") + "' && "
    var parts = cwd.split("/")
    root.launchInCard(dir + root.codeCommand.replace(root.cdPrefix, ""), cwd, parts[parts.length - 1] || cwd)
  }

  // + → Open folder… / New folder…: zenity picks a folder (starting in the
  // Code folder) or asks for a new one's name (made there unless it's a full
  // path), then Code starts in it like any other folder. One under a trusted
  // folder (~/Work) runs in the card; elsewhere startFailed's terminal asks.
  function browseFolder(how) {
    if (pickProcess.running) return
    var base = root.commandDir(root.codeCommand) || Quickshell.env("HOME")
    pickProcess.command = ["bash", "-c", [
      'how=$1 base=$2 shown=$3',
      'command -v zenity >/dev/null || { notify-send -a Clawdius "File pickers need zenity" "Install it: sudo pacman -S zenity"; exit 1; }',
      '[ -d "$base" ] || base=$HOME shown="~"',
      'if [ "$how" = new ]; then',
      '  name=$(zenity --entry --title="New folder for Claude" --text="Name (made in $shown), or a full path:") || exit 1',
      '  name=$(printf %s "$name" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//")',
      '  case $name in "") exit 1;; "~") name=$HOME;; "~/"*) name=$HOME/${name:2};; esac',
      '  case $name in /*) dir=$name;; *) dir=$base/$name;; esac',
      '  err=$(mkdir -p -- "$dir" 2>&1) || { zenity --error --title="New folder for Claude" --text="$err"; exit 1; }',
      'else',
      '  dir=$(zenity --file-selection --directory --title="Open Claude in a folder" --filename="$base/") || exit 1',
      'fi',
      'realpath -- "$dir"'
    ].join("\n"), "clawdius-pick", how, base, Format.folder(base, Quickshell.env("HOME"))]
    pickProcess.running = true
  }

  // + → Clone repo…: clone.sh asks for the repo (logging in to GitHub first
  // when it's private), clones it into the Code folder, and Code starts there.
  readonly property string clonePath: decodeURIComponent(String(Qt.resolvedUrl("clone.sh")).replace(/^file:\/\//, ""))
  function cloneRepo() {
    if (pickProcess.running) return
    var base = root.commandDir(root.codeCommand) || Quickshell.env("HOME")
    pickProcess.command = ["bash", root.clonePath, base, Format.folder(base, Quickshell.env("HOME"))]
    pickProcess.running = true
  }

  Process {
    id: pickProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var cwd = text.trim()
        if (!cwd || cwd[0] !== "/") return
        root.pinned = true
        root.open()
        root.startInFolder(cwd)
      }
    }
  }

  // Back in the card's live terminal, like Chat / Code. label: what shows
  // "opening…" meanwhile (Folders and the pick-up chips pass the session id).
  function resumeSession(r, label) {
    var dir = "'" + String(r.cwd).replace(/'/g, "'\\''") + "'"
    root.launchInCard("cd " + dir + " && {live} launch --resume " + r.id, label || "", r.title)
  }

  Process {
    id: resumeProcess
    command: ["python3", "-I", root.resumablePath, "100000", "--all"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.resumable = JSON.parse(text) } catch (e) { console.warn("clawdius resume parse", e) }
      }
    }
  }

  // Recent and Folders list these.
  Connections {
    target: root
    function onIslandOpenChanged() {
      // Folded away: its notification went with it.
      if (!root.islandOpen) { root.newMenuOpen = false; quickChat.picker = ""; if (!root.peeking) root.toast = null; return }
      root.refreshResumable()
      if (root.summoned) return
      if (root.view !== "detail" || (!root.liveId && !root.startingLabel)) root.view = "home"
    }
  }

  // A new view starts at its top.
  property int shownSessionsTab: 0
  onSessionsTabChanged: {
    cardFlick.contentY = 0
    var i = ["live", "pinned", "recent", "folders"].indexOf(sessionsTab)
    var slide = sessionsTab === "live" ? liveSlide : sessionsTab === "pinned" ? pinnedSlide : sessionsTab === "recent" ? recentSlide : foldersSlide
    if (card.visible && i !== shownSessionsTab) {
      slide.dx = (i > shownSessionsTab ? 1 : -1) * Style.space(14)
      slide.restart()
    }
    shownSessionsTab = i
  }
  Slide { id: liveSlide; target: liveList }
  Slide { id: pinnedSlide; target: pinnedView }
  Slide { id: recentSlide; target: recentList }
  Slide { id: foldersSlide; target: foldersView }

  // ---- Home's moment: the one most pressing thing (Moment.qml shows it).
  //      1 a permission prompt (oldest first), 2 a session blocked on you
  //      some other way, 3 a turn that just finished or failed, 4 the
  //      session being watched while it works, 5 nothing running.
  //
  //      The watched session is sticky: once in the card it stays until it
  //      goes idle or closes, so two busy sessions don't trade places every
  //      second. Clicking a rail crab pins one instead. An alert taking over
  //      doesn't change either, so answering it lands back where you were.
  property var finished: null       // the feed's event: {id, kind (done | failed | limited), name, text, busyFor, tokens}
  property string focusId: ""
  property string pinnedId: ""

  Timer {
    id: finishedTimer
    interval: 30000
    onTriggered: root.finished = null
  }

  function sessionById(id) {
    if (!id) return null
    for (var i = 0; i < sessions.length; i++)
      if (sessions[i].id === id) return sessions[i]
    return null
  }

  function updateFocus() {
    var pin = sessionById(pinnedId)
    if (pinnedId && (!pin || (!pin.busy && !pin.waiting))) pinnedId = ""
    if (pinnedId) { focusId = pinnedId; return }
    var current = sessionById(focusId)
    if (current && current.busy) return
    var busy = sessions.filter(function(s) { return s.busy })
    focusId = busy.length ? busy[0].id : ""
  }

  function pinSession(s) {
    root.pinnedId = s.id
    root.focusId = s.id
  }

  onSessionsChanged: {
    updateFocus()
    // A finished session that's straight back at work is no longer finished.
    var f = finished ? sessionById(finished.id) : null
    if (f && (f.busy || f.waiting)) finished = null
    // "Needs you", answered in the terminal.
    var w = toast && toast.kind === "waiting" ? sessionById(toast.id) : null
    if (w && !w.waiting) hideToast()
  }
  onPinnedIdChanged: updateFocus()

  readonly property var moment: {
    if (requests.length) {
      var r = requests[0]
      return { kind: "approval", request: r, session: sessionById(r.sessionId), name: sessionLabel(r), more: requests.length - 1 }
    }
    var waiting = sessions.filter(function(s) { return s.waiting })
    if (waiting.length) return { kind: "waiting", session: waiting[0] }
    if (finished) return { kind: finished.kind, event: finished, session: sessionById(finished.id) }
    var f = sessionById(focusId)
    if (f && (f.busy || f.waiting)) return { kind: "working", session: f }
    return { kind: "idle" }
  }

  // Every other running session, waiting first, then busy, then idle (the
  // feed's order). Four fit; "+N" opens Sessions.
  readonly property var railAll: {
    var main = moment.session ? moment.session.id : ""
    return starFirst(sessions.filter(function(s) { return s.id !== main }))
  }
  readonly property var railSessions: railAll.slice(0, 4)

  readonly property string statusText: {
    var parts = []
    if (needsYou) parts.push(needsYou + " need" + (needsYou > 1 ? "" : "s") + " you")
    if (busyCount) parts.push(busyCount + " working")
    var idle = sessions.length - busyCount - waitingCount
    if (idle > 0) parts.push(idle + " idle")
    return parts.length ? parts.join(" · ") : "nothing running"
  }

  // The launchers, from the + menu.
  function startNew(which) {
    root.newMenuOpen = false
    if (which === "web") root.launch(root.webCommand)
    else root.launchInCard(which === "code" ? root.codeCommand : root.chatCommand, which === "code" ? "Code" : "Chat")
  }

  // ---- The island's parts
  component NavButton: Rectangle {
    id: navButton
    property string icon: ""
    property bool current: false
    property bool dot: false
    property string tip: ""
    signal clicked()
    width: theme.dense ? Style.space(32) : theme.dev ? Style.space(36) : Style.space(40)
    height: theme.dense ? Style.space(26) : theme.dev ? Style.space(30) : Style.space(36)
    radius: theme.pill(height)
    color: current ? theme.alpha(theme.fg, 0.14) : navMouse.containsMouse ? theme.alpha(theme.fg, 0.07) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }

    Icon {
      anchors.centerIn: parent
      d: navButton.icon
      size: Style.space(17)
      color: navButton.current ? theme.strong : navMouse.containsMouse ? theme.fg : theme.muted
    }

    Rectangle {
      visible: navButton.dot
      x: parent.width - Style.space(13)
      y: Style.space(7)
      width: Style.space(6)
      height: width
      radius: width / 2
      color: theme.needsYou
    }

    MouseArea {
      id: navMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: navButton.clicked()
    }
  }

  component Segment: Rectangle {
    id: segment
    property string label: ""
    property bool current: false
    signal clicked()
    width: segmentText.implicitWidth + (theme.dense ? Style.space(16) : theme.dev ? Style.space(20) : Style.space(28))
    height: theme.dense ? Style.space(22) : theme.dev ? Style.space(24) : Style.space(30)
    radius: theme.pill(height)
    color: !current && segmentMouse.containsMouse ? theme.alpha(theme.fg, 0.06) : "transparent"

    Text {
      id: segmentText
      anchors.centerIn: parent
      text: segment.label
      textFormat: Text.PlainText
      color: segment.current ? theme.strong : theme.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: segment.current
    }

    MouseArea {
      id: segmentMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: segment.clicked()
    }
  }

  // A card in the island: one step lighter, a hairline edge.
  component IslandCard: Rectangle {
    radius: theme.rad(Style.space(24))
    color: theme.card
    border.width: 1
    border.color: theme.hairline
  }

  FrostCard {
    id: card
    anchorItem: button
    bar: root.bar
    owner: root
    centerOnBar: true
    island: true
    islandRadius: theme.dense ? Style.space(10) : theme.dev ? Style.space(12) : Style.space(30)
    padding: theme.dense ? Style.space(8) : theme.dev ? Style.space(12) : Style.spacing.popupPadding
    barPadding: theme.dev ? Style.space(4) : Style.space(4)
    tint: theme.island
    // Pinned (the crab clicked): a click outside closes it. Otherwise it
    // goes when the pointer leaves, whatever was clicked inside. With a live
    // terminal up, Hyprland's focus grab can't be used: the terminal's key
    // window taking the keyboard clears it, so every click in the terminal
    // closed the card. That case (and the summoned chatbox's) closes on the
    // key window losing focus.
    passive: root.peeking
    triggerMode: root.peeking ? "hover" : root.summoned || root.terminalUp || root.keysView || root.homeKeys ? "sticky" : root.pinned && !root.autoOpened ? "click" : "hover"
    grabWindows: liveKeys.visible ? [liveKeys] : []
    // The chat view's open menu hangs past the island's bottom.
    floatMask: quickChat.picker !== "" ? quickChat.menuItem : null
    // A file chooser is up (the live view's, the chat view's, the + menu's):
    // no window goes over the bar's layer, so the island gets out of its way.
    tucked: root.livePicking || pickProcess.running
    // Settled on the live view, the terminal resizes all the time; easing
    // after it only clips. Switching views morphs, into the live view too.
    animateHeight: root.view !== "detail" || viewMorph.running
    heightDuration: viewMorph.running ? 340 : 240
    // The bar's opacity too, so the island blends into it; frostOpacity only
    // for a theme preview.
    frostAlpha: theme.barColor.a > 0 ? theme.barColor.a
      : Math.max(0.2, Math.min(1, Number(setting("frostOpacity", 92)) / 100))
    // Every view is full width, summoned or not (narrower in the dense
    // look). Peeking with a notification, only as wide as the note.
    readonly property int fullWidth: Style.space(theme.dense ? 780 : 948)
    contentWidth: root.peeking ? card.fittedContentWidth(toastBanner.implicitWidth + card.padding * 2)
      : card.fittedContentWidth(fullWidth)
    maxContentWidth: card.fittedContentWidth(fullWidth)
    // The nav keeps its height; the view under it takes what the island has
    // left and scrolls. The + menu can reach past a short view.
    readonly property real cap: Style.space(root.tallView || (root.view === "home" && momentCard.tall) || (root.view === "detail" && root.liveAsk) ? 900 : 680)
    contentHeight: root.peeking ? card.fittedContentHeight(toastBanner.implicitHeight)
      : card.fittedContentHeight(Math.max(toastSlot.height + nav.height + content.spacing + body.implicitHeight,
                                          root.newMenuOpen ? newMenu.y + newMenu.height + Style.space(8) : 0), cap)
    // The window stays tall till the island has folded down out of the live view.
    maxContentHeight: card.fittedContentHeight(100000, root.tallView || viewMorph.running ? Style.space(900) : cap)

    Item {
      id: islandRoot
      width: parent.width
      height: parent.height

      // The chat view's Clawd, peeking up from the island's bottom-left edge
      // (the card clips the rest of him); he types along while you do.
      Clawd {
        id: peekCrab
        visible: root.view === "quick" && !root.peeking
        z: 5
        unit: Style.spaceReal(5)
        color: theme.crab
        // Listens while there's nothing to read yet, types along, and waits
        // out the session starting.
        mood: startProcess.running || (root.view === "detail" && !!(root.liveSession || {}).busy) ? "thinking"
            : liveKeys.field.text !== "" ? "typing" : "listening"
        // Its thoughts keep drifting up while the session starts.
        thoughts: root.view === "quick" && (mood === "listening" || mood === "thinking")
        animate: card.open
        anchors.left: parent.left
        anchors.leftMargin: Style.space(14)
        y: islandRoot.height + card.padding - height * 0.6
      }

      // The search view's, in the bottom-right corner: tilted, so it doesn't
      // read as the chat view's.
      Item {
        id: searchCrab
        visible: root.view === "search" && !root.peeking
        z: 5
        // Turned as plain rectangles, the pixel edges come out jagged, so
        // he's drawn to a texture at 3x and that's turned instead, smoothed
        // and mipmapped (shrinking it back blends the steps instead of
        // skipping texels). The texture runs a grid unit past him on every
        // side, and up over his thoughts, so the turned quad's own edges
        // fall on clear pixels rather than on his shell and legs.
        readonly property real pad: searchClawd.px
        readonly property real headroom: 18 * pad
        width: searchClawd.width + pad * 2
        height: searchClawd.height + headroom + pad
        anchors.right: parent.right
        anchors.rightMargin: Style.space(26) - pad
        y: islandRoot.height + card.padding - searchClawd.height * 0.6 - headroom
        // About his own middle, not the padded box's.
        transform: Rotation {
          origin.x: searchCrab.width / 2
          origin.y: searchCrab.headroom + searchClawd.height / 2
          angle: -14
        }
        layer.enabled: true
        layer.smooth: true
        layer.mipmap: true
        layer.textureSize: Qt.size(width * 3, height * 3)

        Clawd {
          id: searchClawd
          x: searchCrab.pad
          y: searchCrab.headroom
          unit: Style.spaceReal(5)
          color: theme.crab
          // Looks around until there's a query; then it points at what it
          // found, or shrugs when nothing matches. A command or Google chip
          // has no results to point at: it types along.
          mood: root.searchChip !== "" ? (liveKeys.field.text !== "" ? "typing" : "listening")
            : liveKeys.field.text.trim() === "" || searchView.commandHint ? "searching"
            : searchView.found ? "found" : "failed"
          animate: card.open
        }
      }

      // ---- The notification: all there is while peeking, else up top over
      //      the nav, sliding it down while it's up.
      Item {
        id: toastSlot
        width: parent.width
        height: root.peeking ? toastBanner.implicitHeight
          : root.toastShown ? toastBanner.implicitHeight + Style.space(6) : 0
        visible: height > 0
        clip: true
        Behavior on height {
          enabled: root.islandOpen
          NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
        }

        Toast {
          id: toastBanner
          width: parent.width
          height: implicitHeight
          pal: theme
          fontFamily: root.fontFamily
          toast: root.toastDrawn
          framed: !root.peeking
          maxWidth: Style.space(640)
          opacity: root.peeking || root.toastShown ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 180 } }
          onActivated: root.activateToast()
          onDismissed: root.hideToast()
        }
      }

      Column {
        id: content
        y: toastSlot.height
        visible: !root.peeking
        width: parent.width
        spacing: theme.dense ? Style.space(4) : theme.dev ? Style.space(5) : Style.space(8)

        // ---- Nav: views on the left; status, + and back-to-top on the right
        Item {
          id: nav
          width: parent.width
          height: theme.dense ? Style.space(34) : Style.space(48)

          Row {
            id: navLeft
            anchors.verticalCenter: parent.verticalCenter
            x: Style.space(4)
            spacing: Style.space(4)

            NavButton {
              icon: Icons.home
              current: root.view === "home"
              onClicked: root.view = "home"
            }
            NavButton {
              icon: Icons.chat
              current: root.view === "quick"
              onClicked: root.openView("quick")
            }
            NavButton {
              icon: Icons.sessions
              current: root.view === "sessions" || root.view === "detail"
              dot: root.needsYou > 0 && root.view !== "home"
              onClicked: { root.view = "sessions"; root.sessionsTab = "live" }
            }

            // The search icon, which stretches into the search bar.
            Rectangle {
              id: searchBar
              readonly property bool expanded: root.view === "search"
              anchors.verticalCenter: parent.verticalCenter
              readonly property real iconSlot: theme.dense ? Style.space(32) : Style.space(40)
              width: expanded ? nav.width - navLeft.x - x - Style.space(4) : iconSlot
              height: theme.dense ? Style.space(28) : Style.space(36)
              radius: theme.pill(height)
              color: expanded ? theme.raised : searchMouse.containsMouse ? theme.alpha(theme.fg, 0.07) : "transparent"
              border.width: expanded ? 1 : 0
              border.color: theme.alpha(theme.crab, 0.5)
              clip: true
              Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
              Behavior on color { ColorAnimation { duration: 120 } }

              Icon {
                x: (searchBar.iconSlot - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                d: Icons.search
                size: Style.space(17)
                color: searchBar.expanded ? theme.crab : searchMouse.containsMouse ? theme.fg : theme.muted
              }

              // `/ ` or `/g `, turned into a chip.
              Rectangle {
                id: searchChipBox
                visible: searchBar.expanded && root.searchChip !== ""
                x: Style.space(38)
                anchors.verticalCenter: parent.verticalCenter
                width: chipRow.implicitWidth + Style.space(10) * 2
                height: Style.space(24)
                radius: theme.pill(height)
                color: theme.alpha(theme.fg, 0.10)
                border.width: 1
                border.color: theme.alpha(theme.fg, 0.14)

                Row {
                  id: chipRow
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  Icon {
                    visible: root.searchChip === "terminal"
                    anchors.verticalCenter: parent.verticalCenter
                    d: Icons.terminal
                    size: Style.space(13)
                    stroke: 2.4
                    color: theme.strong
                  }
                  GoogleMark {
                    visible: root.searchChip === "google"
                    anchors.verticalCenter: parent.verticalCenter
                    size: Style.space(13)
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.searchChip === "google" ? "Google" : "Terminal"
                    textFormat: Text.PlainText
                    color: theme.strong
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }

              MirrorInput {
                id: searchInput
                visible: searchBar.expanded
                x: searchChipBox.visible ? searchChipBox.x + searchChipBox.width + Style.space(8) : Style.space(40)
                width: Math.max(0, parent.width - x - Style.space(16) - (recentChips.visible ? recentChips.width + Style.space(12) : 0))
                anchors.verticalCenter: parent.verticalCenter
                wrap: false
                pal: theme
                field: liveKeys.field
                focused: liveKeys.field.activeFocus
                fontSize: Style.font.subtitle
                fontFamily: root.fontFamily
                // No placeholder: the hint under the apps says what to type.
                onFocusRequested: liveKeys.prime()
              }

              // Recent commands and Google searches, at the far right while
              // nothing is typed; as many as fit.
              Row {
                id: recentChips
                readonly property int fit: Math.max(0, Math.min(root.recentSearches.length, 4,
                  Math.floor((searchBar.width - Style.space(200)) / Style.space(150))))
                visible: searchBar.expanded && fit > 0 && liveKeys.field.text === ""
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Repeater {
                  model: recentChips.fit
                  Rectangle {
                    id: recent
                    readonly property var entry: root.recentSearches[index]
                    width: recentRow.implicitWidth + Style.space(10) * 2
                    height: Style.space(24)
                    radius: theme.pill(height)
                    color: recentMouse.containsMouse ? theme.alpha(theme.fg, 0.14) : theme.alpha(theme.fg, 0.07)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Row {
                      id: recentRow
                      anchors.centerIn: parent
                      spacing: Style.space(6)

                      Icon {
                        visible: recent.entry.kind === "terminal"
                        anchors.verticalCenter: parent.verticalCenter
                        d: Icons.terminal
                        size: Style.space(13)
                        stroke: 2.4
                        color: theme.muted
                      }
                      GoogleMark {
                        visible: recent.entry.kind === "google"
                        anchors.verticalCenter: parent.verticalCenter
                        size: Style.space(13)
                      }
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, Style.space(110))
                        text: recent.entry.text
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: theme.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    MouseArea {
                      id: recentMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.reuseSearch(recent.entry)
                    }
                  }
                }
              }

              MouseArea {
                id: searchMouse
                enabled: !searchBar.expanded
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openView("search")
              }
            }
          }

          Row {
            id: navRight
            visible: !searchBar.expanded
            anchors.right: parent.right
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            // Scrolled down: an arrow back to the top of the view.
            NavButton {
              visible: cardFlick.contentY > 1
              icon: "M12 19V5M6 11l6-6 6 6"
              onClicked: backToTop.restart()

              NumberAnimation {
                id: backToTop
                target: cardFlick
                property: "contentY"
                to: 0
                duration: 260
                easing.type: Easing.OutCubic
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: !root.feedOk ? "looking for Claude…" : root.statusText
              textFormat: Text.PlainText
              color: root.needsYou ? theme.needsYouText : theme.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            NavButton {
              icon: Icons.gear
              current: root.view === "settings"
              onClicked: root.view = "settings"
            }

            NavButton {
              id: plusButton
              icon: Icons.plus
              current: root.newMenuOpen
              onClicked: root.newMenuOpen = !root.newMenuOpen
            }
          }
        }

        // ---- The view, scrolling under the nav
        Item {
          width: parent.width
          height: cardFlick.height

          Flickable {
            id: cardFlick
            width: parent.width
            height: Math.max(0, Math.min(body.implicitHeight, card.maxContentHeight - card.verticalContentInset - toastSlot.height - nav.height - content.spacing))
            contentWidth: width
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // A drag over the live terminal selects text there.
            interactive: !(detailLoader.item && detailLoader.item.holdsPointer)

            Column {
              id: body
              width: parent.width
              spacing: theme.dense ? Style.space(4) : theme.dev ? Style.space(6) : Style.space(10)
              transformOrigin: Item.Top
              transform: Translate { id: bodyShift }

              Text {
                visible: root.startNotice !== ""
                width: parent.width
                leftPadding: Style.space(10)
                rightPadding: Style.space(10)
                text: root.startNotice
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: theme.needsYouText
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.startNotice = ""
                }
              }

              QuickChat {
                id: quickChat
                visible: root.view === "quick" || root.quickShown
                compact: root.view === "quick"
                focused: liveKeys.field.activeFocus
                // The chat view leaves Clawd his corner.
                x: compact ? peekCrab.width + Style.space(28) : 0
                width: parent.width - x
                pal: theme
                fontFamily: root.fontFamily
                field: liveKeys.field
                mode: root.quickMode
                chatDir: root.commandDir(root.chatCommand)
                codeDir: root.commandDir(root.codeCommand)
                fontSize: root.terminalFontSize
                model: root.quickModel
                effort: root.quickEffort
                dir: root.quickDir
                recentDir: root.recentFolders.length ? root.recentFolders[0].cwd : ""
                menuLayer: card.floatLayer
                onPicked: function(which) { root.quickMode = which; liveKeys.prime() }
                permission: root.quickPermission
                onModelPicked: function(which) { root.quickModel = which; if (which === "opusplan") root.quickPermission = "plan" }
                onPermissionPicked: function(which) { root.quickPermission = which }
                onEffortPicked: function(which) { root.quickEffort = which }
                onDirPicked: function(dir) { root.quickDir = dir }
                images: root.quickImages
                onImageRemoved: function(i) { root.quickImages = root.quickImages.filter(function(p, j) { return j !== i }); liveKeys.prime() }
                onSend: root.sendQuick()
                onFocusRequested: liveKeys.prime()
              }

              SearchView {
                id: searchView
                visible: root.view === "search"
                width: parent.width
                pal: theme
                fontFamily: root.fontFamily
                query: visible ? liveKeys.field.text : ""
                chip: root.searchChip
                usage: root.appUsage
                now: root.now
                onLaunched: function(entry) { root.launchApp(entry) }
                onCommand: function(text) { root.runCommand(text) }
                onGoogle: function(text) { root.googleSearch(text) }
                onCopied: function(text) { root.copyResult(text) }
                tabs: root.browserTabs
                onTabOpened: function(tab) { root.openTab(tab) }
              }

              Trust {
                visible: root.trustAsk !== null
                width: parent.width
                pal: theme
                fontFamily: root.fontFamily
                dir: root.trustAsk ? root.trustAsk.dir : ""
                saving: trustProcess.running
                onAnswered: function(choice) { root.answerTrust(choice) }
              }

              // ---- Home: the moment, and the Limits glance beside it
              Item {
                id: home
                visible: root.view === "home"
                width: parent.width
                readonly property bool glanceShown: ["working", "idle", "done"].indexOf(root.moment.kind) >= 0
                // Dense: always the corner card's height, so Home keeps one size
                // whatever the main card shows.
                // Help showing: the dense look grows to fit a good amount of it.
                property real helpExtra: theme.dense && root.stuckShown ? Style.space(110) : 0
                Behavior on helpExtra { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                height: visible ? Math.max(momentCard.implicitHeight, glanceShown || theme.dense ? glance.implicitHeight : 0) + helpExtra : 0

                Moment {
                  id: momentCard
                  width: home.glanceShown ? parent.width - glance.width - theme.sp(12) : parent.width
                  height: parent.height
                  pal: theme
                  fontFamily: root.fontFamily
                  moment: root.moment
                  now: root.now
                  active: card.visible && home.visible
                  night: root.night
                  sweat: root.sweating
                  railSessions: root.railSessions
                  railMore: Math.max(0, root.railAll.length - root.railSessions.length)
                  requests: root.requests
                  sessionCount: root.sessions.length
                  usage: root.usage
                  antirot: root.antirot
                  challengeBusy: root.antirotBusy === "today" ? "" : root.antirotBusy
                  mode: root.mainShown
                  stuckOpen: root.stuckShown
                  terminalOutside: root.terminalOutside
                  weather: root.weather
                  onModePicked: function(mode) { root.pickMain(mode) }
                  onChallenge: function(action) { root.challengeAction(action) }
                  timers: root.timers
                  onAnswered: function(request, choice, answers) { root.answerRequest(request, choice, answers) }
                  onDismissed: root.finished = null
                  onAlarmRequested: function(at, label) { root.addTimer("alarm", label, at, at - Date.now()) }
                  onOpened: function(s) { root.openSession(s) }
                  onTerminal: function(s) { root.focusSession(s) }
                  onNewChat: root.openView("quick")
                  onPinned: function(s) { root.pinSession(s) }
                  onStarToggled: function(s) { root.toggleStar(s) }
                  starredIds: root.starredIds
                  onMoreSessions: { root.view = "sessions"; root.sessionsTab = "live" }
                }

                Corner {
                  id: glance
                  visible: home.glanceShown
                  anchors.right: parent.right
                  width: Style.space(root.stuckShown ? (theme.dense ? 300 : 340) : (theme.dense ? 232 : 268))
                  Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                  height: parent.height
                  pal: theme
                  record: root.usage
                  now: root.now
                  fontFamily: root.fontFamily
                  mode: root.cornerShown
                  rep: root.antirot ? root.antirot.today : null
                  antirotBusy: root.antirotBusy
                  onExplainAsked: function(again) { root.runAntirot(again ? ["explain", "again"] : ["explain"], root.antirot.today.lang) }
                  onHintAsked: root.runAntirot(["hint"], root.antirot.today.lang)
                  timers: root.timers
                  posture: root.posture
                  walk: root.walk
                  onModePicked: function(mode) { root.pickCorner(mode) }
                  onStatsOpened: root.view = "stats"
                  onTimerAdded: function(kind, label, at, len) { root.addTimer(kind, label, at, len) }
                  onTimerCancelled: function(id) { root.cancelTimer(id) }
                  onNudgeEdited: function(key, patch) { root.setNudge(key, patch) }
                  onNudged: function(key) {
                    if (key === "walk") root.ring({ kind: "walk", status: "Move break", name: "Stand up", text: Timers.walkLine(++root.walkRings), meta: ["next in " + Timers.span(root.walk.everyMin)], at: Date.now(), id: "" })
                    else root.ring({ kind: "posture", status: "Posture check", name: "Sit up", text: Timers.postureLine(++root.postureRings), meta: ["next in " + Timers.span(root.posture.everyMin)], at: Date.now(), id: "" })
                  }
                }
              }

              // ---- Sessions: Live · Recent · Folders
              IslandCard {
                visible: root.view === "sessions"
                width: parent.width
                height: visible ? sessionsColumn.implicitHeight + theme.sp(16) + theme.sp(14) : 0

                Column {
                  id: sessionsColumn
                  x: theme.sp(14)
                  y: theme.sp(16)
                  width: parent.width - theme.sp(28)
                  spacing: theme.dense ? Style.space(4) : theme.dev ? Style.space(6) : Style.space(10)

                  Rectangle {
                    x: Style.space(4)
                    width: segments.implicitWidth + Style.space(6)
                    height: segments.implicitHeight + Style.space(6)
                    radius: theme.pill(height)
                    color: theme.alpha(theme.fg, 0.06)

                    TabMark {
                      pal: theme
                      over: root.sessionsTab === "live" ? segLive : root.sessionsTab === "pinned" ? segPinned : root.sessionsTab === "recent" ? segRecent : segFolders
                    }

                    Row {
                      id: segments
                      anchors.centerIn: parent
                      spacing: Style.space(2)
                      Segment {
                        id: segLive
                        label: "Live" + (root.sessions.length ? "  " + root.sessions.length : "")
                        current: root.sessionsTab === "live"
                        onClicked: root.sessionsTab = "live"
                      }
                      Segment {
                        id: segPinned
                        readonly property int count: root.pinnedLive.length + root.pinnedResumable.length
                        label: "Pinned" + (count ? "  " + count : "")
                        current: root.sessionsTab === "pinned"
                        onClicked: root.sessionsTab = "pinned"
                      }
                      Segment { id: segRecent; label: "Recent"; current: root.sessionsTab === "recent"; onClicked: root.sessionsTab = "recent" }
                      Segment { id: segFolders; label: "Folders"; current: root.sessionsTab === "folders"; onClicked: root.sessionsTab = "folders" }
                    }
                  }

                  Sessions {
                    id: liveList
                    visible: root.sessionsTab === "live"
                    width: parent.width
                    pal: theme
                    sessions: root.activeSessions.concat(root.idleSessions)
                    hiddenIdle: root.hiddenIdle
                    idleCount: root.idleCount
                    idleLimit: root.maxIdle
                    idleExpanded: root.idleExpanded
                    onIdleToggled: root.idleExpanded = !root.idleExpanded
                    now: root.now
                    active: card.visible && visible
                    fontFamily: root.fontFamily
                    liveId: root.liveId
                    awake: root.awake
                    idleStopMinutes: root.idleStopMinutes
                    onOpened: function(s) { root.openSession(s) }
                    onStopRequested: function(s) { root.stopSession(s) }
                    onStarRequested: function(s) { root.toggleStar(s) }
                    starredIds: root.starredIds
                  }

                  // Resume and History were one list over the same data; the
                  // newest 8 show first, then 25 at a time.
                  Resume {
                    id: recentList
                    pal: theme
                    visible: root.sessionsTab === "recent"
                    width: parent.width
                    sessions: root.notRunning
                    starredIds: root.starredIds
                    emptyText: root.resumable.length ? "No earlier conversations." : "No conversations found."
                    firstPage: 8
                    pageSize: 25
                    now: root.now
                    fg: theme.fg
                    mutedFg: theme.muted
                    accent: theme.done
                    fontFamily: root.fontFamily
                    onActivated: function(r) { root.resumeSession(r) }
                    onStarRequested: function(r) { root.toggleStar(r) }
                  }

                  // Pinned: the pinned sessions, running ones first, then the
                  // ones that aren't running.
                  Column {
                    id: pinnedView
                    visible: root.sessionsTab === "pinned"
                    width: parent.width
                    spacing: Style.space(2)

                    Text {
                      visible: root.pinnedLive.length + root.pinnedResumable.length === 0
                      width: parent.width
                      topPadding: Style.space(14)
                      bottomPadding: Style.space(14)
                      horizontalAlignment: Text.AlignHCenter
                      text: "Nothing pinned yet.\nHover a session and click ☆."
                      textFormat: Text.PlainText
                      color: theme.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    Sessions {
                      visible: root.pinnedLive.length > 0
                      width: parent.width
                      pal: theme
                      sessions: root.pinnedLive
                      emptyText: ""
                      hiddenIdle: 0
                      idleCount: 0
                      idleLimit: 1000
                      now: root.now
                      active: card.visible && pinnedView.visible
                      fontFamily: root.fontFamily
                      liveId: root.liveId
                      awake: root.awake
                      idleStopMinutes: root.idleStopMinutes
                      onOpened: function(s) { root.openSession(s) }
                      onStopRequested: function(s) { root.stopSession(s) }
                      onStarRequested: function(s) { root.toggleStar(s) }
                      starredIds: root.starredIds
                    }

                    Resume {
                      visible: root.pinnedResumable.length > 0
                      pal: theme
                      width: parent.width
                      sessions: root.pinnedResumable
                      starredIds: root.starredIds
                      emptyText: ""
                      now: root.now
                      fg: theme.fg
                      mutedFg: theme.muted
                      accent: theme.done
                      fontFamily: root.fontFamily
                      onActivated: function(r) { root.resumeSession(r) }
                      onStarRequested: function(r) { root.toggleStar(r) }
                    }
                  }

                  Folders {
                    pal: theme
                    id: foldersView
                    visible: root.sessionsTab === "folders"
                    width: parent.width
                    folders: root.recentFolders
                    running: root.runningStates
                    asleep: root.asleep
                    starting: root.startingLabel !== "Chat" && root.startingLabel !== "Code" ? root.startingLabel : ""
                    now: root.now
                    fg: theme.fg
                    mutedFg: theme.muted
                    accent: root.crabColor
                    fontFamily: root.fontFamily
                    onActivated: function(cwd) { root.startInFolder(cwd) }
                    onSessionActivated: function(r) { root.openFolderSession(r) }
                  }
                }
              }

              // ---- Stats: Claude usage in full
              IslandCard {
                visible: root.view === "stats"
                width: parent.width
                height: visible ? statsColumn.implicitHeight + theme.sp(22) * 2 : 0

                Column {
                  id: statsColumn
                  x: theme.sp(24)
                  y: theme.sp(22)
                  width: parent.width - theme.sp(48)

                  Usage {
                    pal: theme
                    visible: !!root.usage
                    width: parent.width
                    record: root.usage
                    now: root.now
                    fg: theme.fg
                    mutedFg: theme.muted
                    accent: root.crabColor
                    urgent: theme.failed
                    fontFamily: root.fontFamily
                  }

                  Text {
                    visible: !root.usage
                    width: parent.width
                    text: "No usage data yet — refreshing…"
                    textFormat: Text.PlainText
                    color: theme.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }

              // ---- Settings: the gear's view
              IslandCard {
                visible: root.view === "settings"
                width: parent.width
                height: visible ? settingsView.implicitHeight + theme.sp(22) * 2 : 0

                Settings {
                  id: settingsView
                  x: theme.sp(24)
                  y: theme.sp(22)
                  width: parent.width - theme.sp(48)
                  pal: theme
                  fontFamily: root.fontFamily
                  antirot: root.antirot
                  posture: root.posture
                  walk: root.walk
                  terminalOutside: root.terminalOutside
                  onTerminalOutsideSet: function(on) { root.terminalOutside = on }
                  onLookSet: function(look) { root.islandLook = look }
                  busy: root.antirotBusy === "today" ? "" : root.antirotBusy
                  busyLang: root.antirotBusyLang
                  onNudgeSet: function(key, min) { root.setNudge(key, { everyMin: min }) }
                  onLangToggled: function(lang, on) { root.runAntirot(["set", lang, on ? "on" : "off"], lang) }
                  onLevelSet: function(lang, level) { root.runAntirot(["level", lang, String(level)], lang) }
                  onSetupAsked: function(lang) { root.runAntirot(["setup", lang], lang) }
                  onLangAdded: function(track) { root.runAntirot(["add", track], track) }
                  onLangRemoved: function(lang) { root.runAntirot(["remove", lang], lang) }
                  onEditorSet: function(editor) { root.runAntirot(["editor", editor || "default"], "") }
                  onOftenSet: function(n) { root.runAntirot(["often", String(n)], "") }
                  onTimeBoxSet: function(n) { root.runAntirot(["timebox", String(n)], "") }
                }
              }

              // ---- Detail: one background session, live
              Loader {
                id: detailLoader
                active: root.view === "detail" && (root.liveId !== "" || root.startingLabel !== "")
                visible: active
                width: parent.width

                sourceComponent: Detail {
                  width: detailLoader.width
                  pal: theme
                  fontFamily: root.fontFamily
                  jobId: root.liveId
                  session: root.liveSession || (root.startingLabel !== "" ? root.pendingSession : null)
                  keyWindow: liveKeys
                  terminalFontSize: root.terminalFontSize
                  chatStyle: root.detailChat
                  chatSession: root.detailIsChatFolder
                  pendingPrompt: root.startingLabel !== "" ? root.pendingPrompt : ""
                  now: root.now
                  active: root.islandOpen || (card.visible && !root.peeking)
                  onGrabbed: root.autoOpened = false
                  requests: root.requests
                  onAnswered: function(request, choice, answers) { root.answerRequest(request, choice, answers, true) }
                  onToggleChat: root.toggleDetailChat()
                  onAnswerInTerminal: root.answerInTerminal()
                  onOpenTerminal: if (root.liveSession) root.focusSession(root.liveSession)
                  onOpenEditor: dir => {
                    root.close()
                    Quickshell.execDetached(["uwsm-app", "--", "code", dir])
                  }
                  onNewSession: dir => root.startInFolder(dir)
                  onOpenLink: url => {
                    root.close()
                    Quickshell.execDetached(["omarchy-launch-browser", url])
                  }
                  onCollapse: root.collapseLive()
                }
              }
            }
          }

          // A slim thumb on the right edge, shown only when there is more to scroll.
          Rectangle {
            visible: cardFlick.contentHeight > cardFlick.height + 1
            anchors.right: parent.right
            anchors.rightMargin: -Style.space(8)
            y: cardFlick.visibleArea.yPosition * cardFlick.height
            width: Style.space(3)
            height: Math.max(Style.space(24), cardFlick.visibleArea.heightRatio * cardFlick.height)
            radius: width / 2
            color: theme.alpha(theme.fg, 0.3)
          }
        }
      }

      // ---- The chat view's open menu (model, effort, folder, link) drops
      //      into here; a click elsewhere closes it.
      MouseArea {
        visible: quickChat.picker !== "" && quickChat.visible
        anchors.fill: parent
        z: 19
        onClicked: quickChat.picker = ""
      }

      // ---- The + menu, over whatever view is showing; a click elsewhere closes it.
      MouseArea {
        visible: root.newMenuOpen
        anchors.fill: parent
        z: 19
        onClicked: root.newMenuOpen = false
      }

      NewMenu {
        id: newMenu
        visible: root.newMenuOpen
        z: 20
        x: parent.width - width - Style.space(4)
        y: content.y + nav.height + Style.space(2)
        pal: theme
        fontFamily: root.fontFamily
        codeDir: root.commandDir(root.codeCommand)
        chatDir: root.commandDir(root.chatCommand)
        folders: root.recentFolders
        now: root.now
        onLaunched: function(which) { root.startNew(which) }
        onFolderPicked: function(cwd) { root.newMenuOpen = false; root.startInFolder(cwd) }
        onAllFolders: { root.newMenuOpen = false; root.view = "sessions"; root.sessionsTab = "folders" }
        onBrowse: function(how) { root.newMenuOpen = false; root.browseFolder(how) }
        onCloneRepo: { root.newMenuOpen = false; root.cloneRepo() }
      }
    }
  }
}
