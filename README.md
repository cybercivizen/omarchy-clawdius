# Clawdius

Clawdius is a tiny pixel crab beside the bar clock. He types while any Claude
Code session is busy and waves when one needs you: orange while Claude is
doing something, gray when nothing is. Hover the middle of the bar (the
clock, the crab) and an island drops from the bar; click the crab to pin it.
When a turn that ran ≥ 8s finishes, or a session gets stuck waiting on you,
the island says so (no desktop notification): closed, it opens just far enough for the note; open, the note
sits up top above the nav. Not when that session's terminal is the window
you're looking at. Clicking the note focuses its terminal (a background
session opens up close in the island).

A community plugin for [Omarchy](https://omarchy.org). Not made by or
affiliated with Anthropic; Claude and Clawd are theirs.

## Install

```bash
omarchy plugin add https://github.com/cybercivizen/omarchy-clawdius.git --enable
```

Pick `center` when it asks where on the bar: the crab sits beside the clock.

### What it needs

- Omarchy with the Quickshell bar (Quattro). Everything else the crab uses
  (Python, `tmux`, `git`, `wl-copy`) comes with Omarchy.
- [Claude Code](https://claude.com/claude-code), the `claude` command,
  signed in. Omarchy doesn't install it for you. Without it the crab just
  sits there with nothing to show.
- Optional: `gh` for the GitHub button on a session, `code` for the VS Code
  button.

It works with any clock, or none: hovering the middle of the bar opens the
island.

The plugin installs nothing and leaves your settings alone. The only thing it
makes outside its own folder is `~/chat`, the first time you start a Chat.

### Set it up

- **Keyboard.** Omarchy plugins can't add key bindings, so add these to
  `~/.config/hypr/bindings.lua`:

  ```lua
  o.bind("SUPER + ALT + C", "Claude island", "omarchy-shell -q clawdius summon")
  o.bind("ALT + SPACE", "Claude island search", "omarchy-shell -q clawdius search")
  ```

  Super+Alt+C pulls the island down with the keyboard on it, and Alt+Space
  opens it on the search.
- **Approvals from the island** (optional). Run
  `python3 ~/.config/omarchy/plugins/cybercivizen.clawdius/approvals.py install`.
  It adds a `PermissionRequest` hook to `~/.claude/settings.json`, after
  saving a dated backup. Without it, the island still tells you when a
  session needs you; you answer in the terminal. See [Approvals](#approvals).
- **Chat and Code.** Nothing to do. **Code** starts Claude Code in `~/Work`,
  the folder Omarchy sets up for your projects, in auto mode. **Chat** starts
  a talk-only session in `~/chat`: Claude can't run commands or edit files
  there, and answers the way it does on claude.ai (`chat.md`). The
  `--chat` at the end of the *Chat command* setting does that, so keep it if
  you change the command. Claude Code asks once whether to trust each
  folder; the island shows that question for you.
- **Frosted glass** (optional). The island is see-through so Hyprland can
  blur what's behind it. Turn on `blur_popups` for the `omarchy-bar` layer to
  get the effect.

### Remove

```bash
python3 ~/.config/omarchy/plugins/cybercivizen.clawdius/approvals.py uninstall  # only if you installed the hook
omarchy plugin remove cybercivizen.clawdius
```

Take out the two key bindings too, if you added them. The crab keeps a
little state in `clawdius/` folders under `$XDG_STATE_HOME`
(`~/.local/state`), `$XDG_CACHE_HOME` (`~/.cache`) and `$XDG_RUNTIME_DIR`.
Delete those to clear it.

### Moods

The crab shows the most pressing thing going on, in this order:

| Mood | When | Crab | Card |
|---|---|---|---|
| waiting | a session is blocked on you (permission prompt, sandbox request, input needed…) | waves a claw, `!` badge | "!" bits, row lit |
| done | a ≥ 8s turn just finished (3.5s) | claws up, hopping | sparkles |
| typing | busy, running tools | taps the keys | code bits |
| thinking | busy, nothing written for 8s since the last tool result | claw at chin, eyes up | "?" |
| failed | a turn ended `failed:` (15s, when nothing is busy) | claws down, eyes shut | "…" |
| sleep | idle between midnight and 6am | eyes shut | z's |

It sweats (a drop runs down its side) once the 5-hour limit is 90% spent.

### The island

Near-black, hung straight off the bar,
with an icon nav: **Home**, **Chat** (a new chat), **Sessions**, **Search**
(the icon stretches into a search bar), the status ("1 needs you · 2
working"), and **+** for a new session from any view. Opened by hovering,
the nav also shows the two shortcuts (hidden when the status leaves no room).
The island opens from anywhere in the middle 560 px of the bar
(`hoverZoneWidth`), not only the clock and crab: a passive `HoverHandler` on
the bar window, so the widgets under it keep their own hover and clicks.

Every view is 948 px wide, however it was opened (only a notification peek
is narrower). The popup window stays at the widest and tallest size and
only the drawn island morphs between sizes: resizing the Wayland popup showed one frame of the old
buffer squashed into the new size.

- **Home** shows one *moment* at a time, the most pressing first: a
  permission prompt (Deny / Always / Allow, or Terminal), one of Claude's
  questions (its options to click; several questions or a multi-pick send
  together) or a plan to approve (the plan, Keep planning / Approve plan), a
  session blocked on you some other way, a turn that just finished or failed
  (until OK, or 30s), one stopped by the **usage limit** (purple: the crab
  asleep with z's, when the spent limit resets and a bar filling toward it),
  the session being watched, or nothing running. Each has a big crab with a
  status badge (amber `!`, green ✓, red ✗, purple z, orange dots while working) and a
  faint glow in the state's color. The watched session shows its last three
  steps: Claude's plan when it wrote one (`tasks`), else its last tool calls
  from the transcript (`actions`: ✓ done, spinner running, ✗ failed). It is
  sticky, so two busy sessions don't trade places every second. While it's
  busy the last row is always what it's doing now, lit up with a clock:
  the tool call that's out with its command or path under it, or
  "Thinking…" between calls; under the list, Claude's latest words this
  turn in quotes.
  With nothing running: **New chat**, into the chat view. (Earlier sessions
  are under Sessions → Recent.)
  Other running sessions sit on a **rail** of small crabs on the right, each
  with a bubble on its corner saying how long ago it last moved (since its
  turn started while it works or waits, since it went idle otherwise).
  Hovering one peeks at it (state, folder, current step, Deny / Allow if it's
  waiting); a click pins it to the card, a double-click opens its terminal.
  On the working and idle moments the **Limits** glance sits beside it (the
  5-hour window and the week, with a pace tick); clicking it opens **Stats**.
- **Sessions**: **Live** (every running session: small crab, name, `bg` tag,
  folder, then its state on the right; waiting rows amber), **Recent** (every
  conversation that isn't running, newest 8 first then 25 at a time, with
  the cache hint; the old Resume + History) and **Folders** (the 20 folders
  Claude worked in most recently, not the Chat / Code ones nor scratch dirs;
  click one to list its sessions, **+ New session** on hover starts Code
  there).
  Background sessions that never got a prompt are hidden and stopped
  (`live.py reap`) once nothing is attached to them.
- **Detail**: clicking a background session opens it up close. On the left:
  a back arrow beside its crab, its name and folder (where it's working now, so it follows a
  switch into a worktree), its git branch and, for a linked worktree, which
  repository it belongs to, then its steps (ACTIONS, or PLAN; an idle
  session keeps its last turn's, ■ for one cut off), and at the foot how
  full its **context** is (against Claude Code's auto-compact window: the
  `autoCompactWindow` setting, per model under `modelSettings`, else 200k),
  and Open in terminal. On the right: chips for mode and folder
  (eliding its middle when long), the terminal live in a dark well at its
  full height from the start (Chat / Code open this view at once, saying
  "Starting Claude…" until the session is up), a rounded composer with a send button (amber while
  Claude's asking and keys go straight to the terminal; its text selects
  with the mouse or Shift+arrows, Ctrl+C copies), and key hints (Esc and
  ⇧Tab clickable) with the model and effort (the latest turn's, from the
  transcript) on the right. Scrolled back, the screen holds its height and a
  floating **Jump to bottom** stands in for Claude's own label.
- **Closing**: opened by hovering, the island goes when the pointer leaves,
  whatever you clicked inside it. Pinned (the crab clicked), it stays until
  you click outside it. While it shows a live terminal, or there's a chat
  message or search half typed, it stays put, and
  closes when the keyboard moves to another window (a click on it, or
  Hyprland's follow-mouse focusing the window under the pointer). It can't
  use Hyprland's focus grab there: the terminal's key window taking the
  keyboard clears the grab, so every click in the terminal closed it.
  The working moment on Home shows the context percentage too.
- **Chat** (the nav's chat icon, Home's New chat, or **Super+Alt+C**): a
  composer with Clawd peeking up from the island's bottom-left edge. Chat or
  Code, whichever you used last (`~/.local/state/clawdius/prefs.json`;
  Tab or a click switches): Enter starts that session with the message as
  its first prompt (`claude --bg -- '<message>'`) and goes straight to its
  live view; Shift+Enter is a new line, Esc clears it (or closes the island
  when empty). The text behaves like an input: an I-beam over it, click to
  place the caret, drag or double-click to select, Ctrl+C / Ctrl+V.
- **Search** (the nav's search icon, **Alt+Space**, or just start typing on
  Home; Esc there closes the island): with nothing typed,
  a row of apps you've used lately (launches from here, and every window
  that comes to the front, counted in `~/.local/state/clawdius/apps.json`;
  then what's open, then a browser, terminal, file manager and editor).
  Past a divider, the default browser's five most recent tabs as chips, in
  two rows filled a column at a time; what doesn't fit fades out at the
  edge, and › (or the wheel) pages a column on, ‹ back (`tabs.py`: Firefox and its forks' open tabs from the
  session store, newest first; Chromium-likes' last visited pages from
  History; favicons cached in `~/.cache/clawdius/favicons`). A click
  opens the page in the browser again. The bar has no placeholder: the
  line under the apps says what to type. Typing lists the installed apps that match (↑↓ / Tab to pick, Enter or a
  click opens it with `uwsm-app -- gtk-launch`). A sum (`12*(3+4)`,
  `2^10`, `sqrt(2)`, `10/3`: `+ - * / % ^`, brackets, `pi`, `e`, `sqrt abs
  round floor ceil ln log sin cos tan`; `Calc.js`, nothing is eval'd) is
  worked out in a row above the apps, picked first: Enter copies the result
  (`wl-copy`). When no app matches, a Google row takes their place: Enter
  searches Google for what's typed. `/` then a space turns into
  a **Terminal** chip: Enter runs the text in a new terminal
  (`omarchy-launch-terminal bash -ic '<cmd>; exec bash'`). `/g` then a space
  turns into a **Google** chip: Enter opens the search in the default
  browser. Backspace at the start of the text takes the chip back to `/` or
  `/g`, the caret right after it. Esc clears, then drops the chip, then
  closes.
- **Super+Alt+C** / **Alt+Space** (`summon` / `search`, bound in
  `~/.config/hypr/bindings.lua`) pull the island down on the focused monitor
  on that view with the keyboard on it; again closes it. Summoned, typing on
  the other views opens the chatbox over them. The key window then covers
  the screen, see-through, with the bar and the island cut out of its input
  (as Omarchy's KeyboardPanel does): going OnDemand would otherwise hand the
  keyboard to the window under the pointer, and a click outside lands on it
  and closes the island.
- **+** opens Code (`~/Work`, auto mode) or Chat (`~/chat`, talk only) in the
  live view, Web in the browser, or Code in one of the three most recent
  folders (All folders… goes to Sessions → Folders). **Open folder…** picks
  any folder with a file chooser (zenity, starting in `~/Work`); **New
  folder…** asks for a name and makes it in `~/Work` (or wherever a full or
  `~/` path says), then starts Code there. **Clone repo…** asks for a
  GitHub `owner/repo` (or any git URL), clones it into `~/Work` and starts
  Code in it; a private one asks to log in to GitHub first (`gh auth login`
  in a terminal), then clones. A new folder under `~/Work`
  inherits its trust, so it opens in the card. Claude Code won't start
  background sessions in a folder whose trust isn't saved, so the card asks
  its trust question itself ("Do you trust the files in this folder?"): Yes
  saves it as accepting Claude's dialog would (`live.py trust`, which sets
  `projects[dir].hasTrustDialogAccepted` in `~/.claude.json` under Claude's
  lock) and the session starts in the card; Terminal opens it in a terminal
  window, where Claude asks. Claude never saves trust for the home folder,
  so that one always opens in a terminal (plain interactive `claude`).
- **Stats** — Claude usage, replacing the old `cybercivizen.agents` bar icon:
  plan, 5-hour and weekly limits (orange when ahead of the pace tick, red at
  90%), today's tokens / prompts / sessions, tokens per model, last 7 days.

Colors come from the theme's ink and paper (`Colors.qml`), so Solitude and
Solitude Light both read: orange `#D97757` (`#C15F3C` on light) means Claude
is doing something, amber needs you, green / red are done / failed, and
everything else is gray.

### Clock hover

The bar only lets a plugin look up its *own* widgets, so the clock can't reach
the crab directly. `Link.js` (`.pragma library`, one shared instance per
shell) is the meeting point: crabs register with their bar window, and the
clock clone (`cybercivizen.clock/BarWidget.qml`) loads `ClockLink.qml` through
a `Loader` and reports its `HoverHandler` there. If this plugin is removed the
Loader stays empty and the clock carries on.

Omarchy's own clock doesn't do this, so with it, hovering the bar's middle
(`hoverZoneWidth`) or the crab opens the island instead. A clock of your own
can join in: load `../cybercivizen.clawdius/ClockLink.qml` in a `Loader`
and call its `hover(window, hovered)`.

## Stack

| Layer | What | Why |
|---|---|---|
| UI | Omarchy shell plugin (Quickshell / QML), `BarWidget.qml` | Lives in the same process as the bar, inherits theme, hot-reloads on save |
| Sprite | `Sprite.js` + `Clawd.qml`, rectangles on an 18×10 grid | Clawd decoded from the CLI's `▐▛███▜▌` block art; crisp at any scale |
| Island | `Moment.qml` (Home), `Glance.qml`, `Sessions.qml` / `Resume.qml` / `Folders.qml`, `Detail.qml`, `NewMenu.qml` | One moment at a time; the rail and its peek live in `Moment.qml` |
| Parts | `Crab.qml` (Clawd + badge), `Pill.qml`, `Steps.qml`, `Chip.qml`, `Icon.qml` + `Icons.js` (SVG line icons via QtQuick.Shapes), `Format.js` | Shared by the views |
| Colors | `Colors.qml` | Theme-aware palette; the `color` setting overrides the orange |
| Data | `feed.py` (Python stdlib), spawned by the widget, JSON lines on stdout | Zero config; polls cheap mtimes once a second |
| Usage | `Usage.qml` reading `~/.local/state/omarchy/agents/usage/claude.json` (FileView, live) | Omarchy's own collector; the widget runs `omarchy-agent-usage-update claude` every 15 min and on card open when >1 min stale |
| Notifications | `feed.py`'s `toast` in the snapshot → `Toast.qml` in the island | Every bar's feed sends its own copy; only the open island, else the focused monitor's, shows it |
| Card | `FrostCard.qml`, a reworked `PopupCard` | `island: true`: square corners on the bar, 30 px on the free ones; opens by growing out of the bar (a sliver widens, drops to full height, then the content fades in) and folds back into it on close; see-through enough that Hyprland frosts it (`blur_popups` on the `omarchy-bar` layer rule); animates height between views |
| Approvals | `approvals.py` (`PermissionRequest` hook) + `Approval.qml` | Allow / Always / Deny from the card; the terminal dialog stays up alongside |
| Resume | `resumable.py` + `Resume.qml` | Past sessions, with whether resuming hits the prompt cache |

### Background sessions & live terminal

**Chat**, **Code** and **Resume** (a row in Sessions → Recent, or a pick-up chip on Home) start Claude
with `claude --bg` (`live.py start`) and show it in the card's live terminal.
The command settings say `{live} launch`, which attaches a terminal window
instead (`live.py launch`); the card swaps that for `start`. Closing the window only detaches: the session keeps working in
Claude Code's own daemon, and the crab keeps tracking it. A plain `claude`
typed in a terminal still ends with its window. For the same behavior from a
shell: `alias cc='python3 -I ~/.config/omarchy/plugins/cybercivizen.clawdius/live.py launch'`.

Clicking a background (`bg`) row in Tasks shows that session live at the top
of the tab. `live.py view` runs `claude attach` in a hidden tmux pane
(`tmux -L clawdius`, no user config) and streams the rendered screen as
rich text, minus the banner, status line and mode line (the card shows model,
mode and folder as chips). The prompt is the card's own, so typing is
instant; Enter pastes it in one piece, then presses Enter. Claude's suggested
next prompt (the gray text in its empty prompt) shows in the card's empty
composer, and Tab or → types it in. A background session only makes one while
a viewer has focus, so the pane sends a focus-in report once Claude's prompt is
up, and a focus-out before it closes. Dragging over text in
the view selects it and copies it on release (wl-copy); Ctrl+C with a
selection copies too, instead of interrupting Claude. Frames are held back
mid-drag so the screen updating doesn't drop the selection. The card is a popup of the bar, which never takes the keyboard, so
the text field really lives on
`KeyWindow.qml`: a 1×1 click-through overlay layer that takes keyboard focus
while the live view is open (an Exclusive prime, then OnDemand, like the
shell's KeyboardPanel). Clicking the view takes focus back after you've
clicked elsewhere. While a live view is up the card ignores clicks
elsewhere (no focus grab), so you can copy from another window; click the
crab or the back arrow to let it go. **Ctrl+V** with an image on the clipboard
saves it under `$XDG_RUNTIME_DIR/clawdius/paste/` and pastes the path into
Claude's box, which attaches it as `[Image #n]`; the card shows those as
chips over its prompt and sends them with your next message (Backspace on an
empty prompt removes the last one). Text size: the `terminalFontSize`
setting (13px default).
While Claude shows a dialog instead of its prompt and the card's prompt is
empty, keys go straight to the terminal so you can answer it. The card pins itself so it gets the
keyboard, then widens. **Open in terminal** focuses the session's window, or
attaches a new one. The **back arrow** (or closing the card) only detaches the
viewer. A watchdog removes the pane even if the shell kills the viewer.
Attached clients share one size, so a terminal attached at the same time
draws at the card's size while it's open.

### Idle sessions go to sleep

Every background session stays loaded until stopped (~400 MB: the Claude
process plus its terminal host), so they pile up. Once a minute the card runs
`live.py sweep`, which stops idle background sessions that have been idle for
`idleStopMinutes` (30), plus the oldest beyond `idleKeepRunning` (5) running
idle. It leaves alone anything busy or waiting on you, anything attached (a
terminal, the card's live view), anything idle under two minutes, sessions
still running background shells, subagents or queued work, ones whose last
turn left a `ScheduleWakeup` / `Monitor` pending or that set up a cron job,
and terminal sessions (plain `claude`). The conversation is kept: Folders
marks them *asleep*, and clicking one there (or in Resume) resumes it in the
card. The status line counts what went to sleep in the last 12 hours.
`$XDG_STATE_HOME/clawdius/asleep.json` records them; try the rule with
`live.py sweep --dry-run`. Hovering an idle background row in Tasks shows
**■ Stop** to end one now. `idleStopMinutes: 0` turns the sweep off.

### Approvals

`approvals.py install` adds a `PermissionRequest` hook to `~/.claude/settings.json`
(dated backup first; `uninstall` takes it out). When Claude is about to ask for
a permission, the hook writes the request to
`$XDG_RUNTIME_DIR/clawdius/requests/<id>.json` and polls for `<id>.answer`;
`approvals.py watch` (run by the widget) streams the pending ones, and the
crab on the focused monitor drops its card open with the request on top.

Claude Code shows its own dialog at the same time, and whichever answers
first wins. Answering in the terminal doesn't stop the hook, so it watches the
transcript for that tool call's `tool_result` and bows out. It also returns
right away (no decision, so the terminal prompt carries on) when no widget is
watching, after 5 minutes, or on any error.

`AskUserQuestion` comes through the same hook: the card shows the questions
and options, and the answer goes back as an allow whose `updatedInput` adds
`answers` (question → label, several picks joined with ", "), the way the
Agent SDK answers it. `ExitPlanMode` shows the plan: Approve plan allows it,
Keep planning denies it with a note to ask what to change. Test:
`approvals.py answer <id> answer '{"Which database?": "Postgres"}'`. Test it without Claude: start `approvals.py watch`, pipe a payload into
`approvals.py hook`, then `approvals.py answer <id> allow`.

### Notifications

Drawn in the island (`Toast.qml`), built to read at a glance:

- **Where** — island closed: it opens just enough for the note (FrostCard's
  `passive` mode: no popout slot, so an open calendar stays open, and the
  note waits for it to close; no focus grab, no keyboard). Island open: the
  note slides in above the nav, unless Home's moment already shows that
  session's news. Hovering the bar's middle as usual opens the island
  around it.
- **Icon** — a little Clawd in the state's pose (`Crab.qml`), the status
  badge on his corner: green ✓ done (hopping), red ✗ failed (gray, slumped),
  amber ! needs you (waving), purple z out of usage (gray, asleep). On the
  open island the note is a borderless card faintly tinted with that color.
- **Title** — the status, then the session: `Done · work-e9`, `Failed · …`,
  `Needs your OK · …` (permission / sandbox prompts), `Needs input · …`,
  `Out of usage · …` (the turn ended on Claude Code's usage-limit error:
  an `isApiErrorMessage` record with `error: rate_limit` or "You've hit
  your limit" text).
- **Text** — the result (whole sentences when they fit, elided on one line),
  and on the right how long it ran, the turn's output tokens, the project.
- **How long** — 6s for done, 10s for the rest; held while the pointer's on
  it; × puts it away. A "needs you" note goes once the session isn't
  waiting any more. A permission prompt the approval hook holds gets no
  note: it opens the island with its buttons instead.
- **Click** — a background session opens up close in the island; any other
  focuses its terminal (`focus.py`).

Try one: `qs -p /usr/share/omarchy/shell ipc call clawdius testToast done`
(`failed`, `input`, `limited`, `waiting`).

`feed.py` reads what Claude Code already writes under `~/.claude`:

- `sessions/<pid>.json` — live sessions, `busy`/`idle`/`waiting` (+ `waitingFor`), name, cwd (pid + start time checked).
  `waitingFor: "dialog open"` is a dialog you opened yourself and reads as idle.
- `jobs/<id>/state.json` — background jobs' current step description
- `projects/*/<session>.jsonl` — parsed incrementally: last tool call, TodoWrite / TaskCreate+TaskUpdate tasks, last prompt and reply,
  the turn's output tokens (per message id, records repeat usage), and children: an `Agent` result with
  `status: async_launched` + `agentId`, or a `Bash` result with `backgroundTaskId`, until a `<task-id>` /
  `<agent-message from=…>` notification names it (or the subagent's transcript goes quiet for 15 min)

These are internal formats, so every read degrades gracefully. If they ever
change, the fallback is Claude Code hooks (`PreToolUse`, `Stop`,
`Notification`) writing the same snapshot fields.

## Knobs

`shell.json` entry settings: `alwaysShow` (on; off hides the crab while nothing's going on), `maxIdleSessions`, `hoverDelayMs`, `closeDelayMs` (grace after the pointer leaves), `hoverZoneWidth` (0 = clock and crab only), `color`, `usageRefreshSec`, `chatCommand`, `codeCommand`, `webCommand`, `frostOpacity` (20–100), `idleStopMinutes` (0 = off), `idleKeepRunning`.
Feed env: `CLAWDIUS_NOTIFY=0`, `CLAWDIUS_NOTIFY_MIN_BUSY` (seconds), `CLAWDIUS_POLL`.

IPC: `omarchy-shell clawdius open|close|toggle|debug|hoverClock <bool>`,
`setView <home|quick|sessions|search|stats|detail>`, `setTab <0|1|2|4>` (the old tabs: Live, Stats, Recent, Folders; `3` lands on Recent too), `openFolder <n>`,
`live <jobId>`, `start <chat|code>`, `startIn <dir>`, `trust <yes|no|terminal>` (the folder trust card), `summon` / `search` (Super+Alt+C / Alt+Space), `quickType <text>` / `quickSend` (the chat view's text, and Enter), `searchType <text>`, `searchTabs <1|-1>` (the recent tabs' › and ‹), `testKeys <bool>` (false: the views never take the keyboard, for screenshots), `resume <n>`, `answer <allow|always|deny|terminal>` (the oldest prompt), `answerQuestion '<json>'`, `dismiss` (the finished moment), `pin <n>` (a rail crab), `newMenu`,
`setMood <idle|typing|thinking|waiting|done|failed|sleep|listening|searching|found|"">` to try a mood (`""` back to live),
`fireEvent <done|failed|limited>`, `snapshot '<feed json line>'` to render a hand-made state
(pause the feed first, `kill -STOP` its pid, or its next line replaces yours),
`themePreview <light|dark|"">` to draw the island in Solitude Light / Dark without switching the desktop's theme;
`omarchy-shell omarchy.clock crabLinks` should print 1. After a hot reload that
changes the IpcHandler, the old handler can keep the target until
`omarchy restart shell`; `debug` missing from `quickshell ipc -p /usr/share/omarchy/shell show` means you're talking to a stale one.
Debug the feed alone: `CLAWDIUS_NOTIFY=0 python3 -I feed.py --once | jq`.

## Ideas for next iterations

- Quick reply to an idle session from the card
- Limit fill on the bar glyph (ring or color shift as the 5-hour window fills)
- Hyprland bind for `clawdius toggle`; 1–9 to jump to session N
