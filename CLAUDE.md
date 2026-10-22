# Clawdius (Omarchy bar plugin)

QML + Python plugin for the Omarchy shell (Quickshell). A pixel crab beside the clock; hover opens an "island" (approvals, new chat, live/recent sessions, usage, Alt+Space app search). Entry point: `BarWidget.qml`. Manifest and settings schema: `manifest.json`.

## Where things are
- `BarWidget.qml` (~2400 lines): the bar widget and island shell. Don't read it whole; grep for the section you need.
- Views: `Approval`, `Sessions`, `Folders`, `Resume`, `Usage`, `Detail`, `Moment`, `SearchView`, `NewMenu`, `QuickChat`, `Glance`.
- Live terminal: `LiveTerm.qml` + `live.py`. Session feed: `feed.py`. Permission hook: `approvals.py`. Past sessions: `resumable.py`. Browser tabs: `tabs.py`.
- Look: `Colors.qml`, `FrostCard.qml`, `Clawd.qml`/`Crab.qml`/`Sprite.js` (pixel art, whole-pixel sizes only). Animations: `Throb.qml`/`Spin.qml` (stepped timers, never per-frame).
- Helpers: `Link.js` (cross-instance calls), `Format.js`, `Icons.js`, `Apps.js`, `Calc.js`.
- Design notes and behaviour: `README.md` (read only the relevant section). Open work: `TODO.md` (tick items off, add new at the bottom).

## Gotchas
- Each bar has 2 crab instances (real + zero-size placeholder). Anything that auto-opens must go through `Link.approvalCrab()`.
- Hot reload leaves a stale instance that can keep IPC and stay the one drawn. After QML edits run `omarchy-restart-shell`.
- Frosting needs `blur_popups = true` on the `omarchy-bar` layer rule.
- Theme colors come from `qs.Commons` (`Color`, `Style`); don't hardcode colors.
- feed.py changes need the feed process restarted (restarting the shell does it).
- Keep animations stepped (see `Throb.qml`): a per-frame change redraws the whole island and keeps the GPU busy.

## Test loop
```
omarchy-restart-shell
qs -p /usr/share/omarchy/shell ipc call clawdius setTab 2   # pick a tab
qs -p /usr/share/omarchy/shell ipc call clawdius open
omarchy-shell clawdius debug                                 # state as JSON
grim -g "<region>" $CLAUDE_JOB_DIR/tmp/crab.png             # then Read the png
```
Summon shortcut: `omarchy-shell -q clawdius summon`. Python: `python -I -m py_compile <file>`. Crop screenshots tightly to the bar/island; other windows can be private.

## Working rules (cost)
- One task per session. Finish, then stop; don't add unrequested features.
- Grep, then Read with offset/limit. Never cat a whole large file.
- Match surrounding code: same comment density, naming, idiom.
- Verify with the test loop once, not repeatedly. Report what you saw.
- Keep replies short: what changed, which file, how to reload.
- Plan first for anything touching more than ~2 files or any new view; list files and steps before editing.
- Work on a branch and open a PR; main is merged via PR. Update the README when behaviour changes.
