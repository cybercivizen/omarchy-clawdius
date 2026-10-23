#!/usr/bin/env python3
"""Background Claude sessions for the crab: start them, and mirror them live.

    live.py launch [claude args...]
        Start the session in the background (`claude --bg`), then attach this
        terminal to it. Closing the window only detaches: the session carries
        on in Claude Code's own daemon, and `claude attach <id>` (or the crab)
        picks it back up.

        Where Claude won't start a background session because the folder
        isn't trusted (always the case for the home folder), it runs plain
        interactive `claude` in this terminal instead.

    live.py start [claude args...]
        Same, but only prints the job id (or the error, exit 1) so the card
        can show the session in its own live terminal. On "not trusted" the
        card opens the session in a terminal window (`launch`) instead.

    live.py reap JOB_ID...
        Stop the background sessions that never got a prompt: no transcript,
        nothing attached (a terminal or the card's view), and older than a
        few seconds. Chat / Code start one per click, so the card drops the
        ones you walk away from.

    live.py sweep [--idle-min 30] [--keep 5] [--protect JOB_ID...] [--dry-run]
        Stop idle background sessions so they don't pile up in memory (each
        is ~400 MB). Of the idle ones, newest first, keep `keep` running and
        stop the rest, plus any idle for `idle-min` minutes. Never touched:
        anything busy or waiting on you (a permission prompt, a question),
        attached (a terminal, the card's view), named in --protect, still
        running background work, with a wakeup / monitor pending from its
        last turn or a cron job it set up, idle under two minutes, or a
        terminal session (plain `claude`). The conversation is kept:
        resuming picks it straight back up. Prints {"stopped": [...]} and
        notes them in $XDG_STATE_HOME/clawdius/asleep.json (session id →
        when). Runs at most every 30s, under a lock (one bar per monitor).

    live.py chat JOB_ID
        The card's conversation view: the session as chat bubbles instead of
        a terminal. The same hidden tmux pane as `view` (it takes the replies
        in and notices when Claude is asking something), but what goes out
        is read from the transcript, one JSON line per message:
            {"history": [{"key": "…", "role": "user", "text": "hi", "at": 1.7e9}, …]}
            {"msg": {"key": "…", "role": "assistant", "text": "Hello!", "at": 1.7e9}}
            {"state": {"alive": true, "asking": false}}
        role is "user", "assistant" or "tool" (a one-line label for a call).
        Commands come in on stdin as for `view` ("submit", "keys", "clip").
        The screen is only looked at now and then, never drawn.

    live.py history DIR
        The prompts given in DIR, newest first, as a JSON list: the card's
        Up / Down go through them in its own prompt.

    live.py stop JOB_ID
        `claude stop` that one (the card's Stop button).

    live.py trust DIR
        Save Claude Code's workspace trust for DIR (and so everything in it),
        as accepting its trust dialog there would: `projects[DIR]
        .hasTrustDialogAccepted` in ~/.claude.json. The card asks first, then
        starts the session it couldn't. Never the home folder (Claude doesn't
        save that one either), nor /.

    live.py view JOB_ID COLS ROWS [FG BG DIM]
        The card's live terminal. A hidden tmux pane (own socket, no user
        config) runs `claude attach JOB_ID`, so tmux does the terminal
        emulation; its screen goes out as JSON lines whenever it changes:
            {"html": "<pre>…</pre>", "alive": true, "model": "Opus 5.5", "mode": "auto", "effort": "high",
             "scrolled": false, "prompt": true,
             "attachments": ["[Image #1]"], "suggestion": "run the tests"}
        The banner, status line and mode line are cut out of the picture; the
        model and mode they showed come along as fields instead. "prompt" is
        true while Claude's prompt is empty and cut out too: the card draws
        its own input then. "suggestion" is Claude's predicted next prompt,
        the gray text it draws in that empty prompt. A background session only
        makes one for a focused viewer, so the pane says it has focus.
        Commands come in on stdin, one JSON object per line:
            {"submit": "hello"}         pasted, then Enter
            {"clip": true}              attach the clipboard's image, if any
            {"text": "hello"}           typed literally (pasted if multi-line)
            {"keys": ["Enter", "C-c"]}  tmux key names
            {"wheel": 3}                scroll back 3 lines (negative: forward)
            {"clear": 40}               delete up to 40 characters around the caret in Claude's box
            {"size": [cols, rows]}
        Closing stdin (the card collapsing the view) kills the pane, which only
        detaches that viewer. Attached clients share one size, so a terminal
        attached at the same time draws at the card's size until it closes.
"""

import fcntl
import glob
import html
import json
import os
import re
import select
import shutil
import signal
import subprocess
import sys
import time

SOCKET = "clawdius"
FRAME_SEC = 0.12
FAST_FRAME_SEC = 0.03
FAST_FOR_SEC = 1.5
SUBMIT_PAUSE_SEC = 0.15
CLEAR_BATCH = 16
CLEAR_PAUSE_SEC = 0.01
# The pane is taller than the card shows: the prompt box and status lines
# under it go, and so does the welcome banner once scrolled up to it, and the
# card should still have a full screen of conversation left.
EXTRA_ROWS = 14


def start(args):
    claude = shutil.which("claude") or "claude"
    # Not a terminal, Claude waits ~3s for a prompt piped on stdin; the card's
    # Process leaves its pipe open, so hand it nothing.
    out = subprocess.run([claude, "--bg"] + args, capture_output=True, text=True, stdin=subprocess.DEVNULL)
    text = out.stdout + out.stderr
    return claude, text, re.search(r"backgrounded\W+([0-9a-f]{6,})", text)


def launch_job(args):
    claude, text, match = start(args)
    if not match:
        sys.stdout.write(text or "claude --bg failed\n")
        return 1
    sys.stdout.write(match.group(1) + "\n")
    return 0


def launch(args):
    claude, text, match = start(args)
    if not match and "not trusted" in text:
        # Claude only starts background sessions where the folder's trust is
        # saved, which it never is for the home folder: run it right here
        # instead, where Claude can ask.
        os.execvp(claude, [claude] + args)
    if not match:
        # Bad flag…: show why instead of a window that just closes.
        sys.stdout.write(text or "claude --bg failed\n")
        sys.stdout.write("\nPress Enter to close.")
        sys.stdout.flush()
        sys.stdin.readline()
        return 1
    os.execvp(claude, [claude, "attach", match.group(1)])


CLAUDE_JSON = os.path.expanduser("~/.claude.json")
LOCK_WAIT_SEC = 5
LOCK_STALE_SEC = 10


def trust(folder):
    """Save trust for folder, under the lock Claude takes to save its config
    (a ~/.claude.json.lock directory), written whole and swapped in."""
    folder = os.path.realpath(os.path.expanduser(folder))
    if not os.path.isdir(folder) or folder in ("/", os.path.realpath(os.path.expanduser("~"))):
        sys.stderr.write("won't trust %s\n" % folder)
        return 1
    lock = CLAUDE_JSON + ".lock"
    deadline = time.monotonic() + LOCK_WAIT_SEC
    while True:
        try:
            os.mkdir(lock)
            break
        except FileExistsError:
            try:
                if time.time() - os.stat(lock).st_mtime > LOCK_STALE_SEC:
                    os.rmdir(lock)
                    continue
            except OSError:
                continue
            if time.monotonic() > deadline:
                sys.stderr.write("~/.claude.json is locked\n")
                return 1
            time.sleep(0.05)
    try:
        with open(CLAUDE_JSON) as f:
            config = json.load(f)
        project = config.setdefault("projects", {}).setdefault(folder, {})
        if project.get("hasTrustDialogAccepted") is True:
            return 0
        project["hasTrustDialogAccepted"] = True
        tmp = "%s.crab-%d" % (CLAUDE_JSON, os.getpid())
        with open(tmp, "w") as f:
            os.fchmod(f.fileno(), os.stat(CLAUDE_JSON).st_mode & 0o777)
            json.dump(config, f, indent=2)
        os.replace(tmp, CLAUDE_JSON)
        return 0
    finally:
        os.rmdir(lock)


REAP_AFTER_SEC = 20


def attached_jobs():
    jobs = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open("/proc/%s/cmdline" % pid, "rb") as f:
                argv = f.read().decode(errors="replace").split("\0")
        except OSError:
            continue
        if "attach" in argv:
            i = argv.index("attach")
            if i + 1 < len(argv):
                jobs.add(argv[i + 1])
    return jobs


def reap_empty(jobs):
    home = os.path.expanduser("~/.claude")
    attached = attached_jobs()
    claude = shutil.which("claude") or "claude"
    for job in jobs:
        if not re.fullmatch(r"[0-9a-f]{6,}", job) or job in attached:
            continue
        state_path = os.path.join(home, "jobs", job, "state.json")
        try:
            with open(state_path) as f:
                state = json.load(f)
            age = time.time() - os.stat(os.path.dirname(state_path)).st_mtime
        except (OSError, ValueError):
            continue
        sid = state.get("sessionId") or ""
        if not sid or age < REAP_AFTER_SEC:
            continue
        if any(os.path.exists(os.path.join(home, "projects", d, sid + ".jsonl"))
               for d in os.listdir(os.path.join(home, "projects"))):
            continue
        subprocess.run([claude, "stop", job], capture_output=True)
    return 0


# ---- Sweeping idle sessions

CLAUDE_HOME = os.path.expanduser("~/.claude")
STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "clawdius")
ASLEEP_PATH = os.path.join(STATE_DIR, "asleep.json")
AWAKE_PATH = os.path.join(STATE_DIR, "awake.json")
SWEEP_STAMP = os.path.join(STATE_DIR, "sweep.stamp")
SWEEP_EVERY_SEC = 30
SWEEP_GRACE_SEC = 120
ASLEEP_FOR_SEC = 7 * 86400
# Left pending by a turn, these die with the process.
PENDING_TOOLS = ("ScheduleWakeup", "Monitor")


def read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def proc_alive(pid, proc_start):
    """True when pid is running and is the same process the file was written by."""
    try:
        with open("/proc/%d/stat" % int(pid)) as f:
            stat = f.read()
    except (OSError, ValueError, TypeError):
        return False
    if not proc_start:
        return True
    fields = stat[stat.rfind(")") + 2:].split()
    return len(fields) > 19 and fields[19] == str(proc_start)


def is_prompt(rec):
    """A user record that starts a turn: typed text, not a tool result or a notification."""
    content = (rec.get("message") or {}).get("content")
    if isinstance(content, str):
        return not content.lstrip().startswith("<")
    if isinstance(content, list):
        return any(isinstance(b, dict) and b.get("type") == "text" and not b.get("text", "").lstrip().startswith("<")
                   for b in content)
    return False


def has_pending(transcript):
    """A wakeup or monitor from the last turn, or a cron job never deleted."""
    pending_turn = False
    crons = 0
    try:
        with open(transcript, errors="replace") as f:
            for line in f:
                if '"tool_use"' not in line and '"user"' not in line:
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if rec.get("isSidechain"):
                    continue
                if rec.get("type") == "user" and is_prompt(rec):
                    pending_turn = False
                elif rec.get("type") == "assistant":
                    for block in (rec.get("message") or {}).get("content") or []:
                        if not isinstance(block, dict) or block.get("type") != "tool_use":
                            continue
                        name = block.get("name")
                        if name in PENDING_TOOLS:
                            pending_turn = True
                        elif name == "CronCreate":
                            crons += 1
                        elif name == "CronDelete":
                            crons -= 1
    except OSError:
        return False
    return pending_turn or crons > 0


def sweep(args):
    idle_min, keep, protect, dry = 30.0, 5, set(), False
    i = 0
    while i < len(args):
        if args[i] == "--idle-min" and i + 1 < len(args):
            idle_min = float(args[i + 1]); i += 2
        elif args[i] == "--keep" and i + 1 < len(args):
            keep = int(args[i + 1]); i += 2
        elif args[i] == "--protect":
            i += 1
            while i < len(args) and not args[i].startswith("--"):
                protect.add(args[i]); i += 1
        elif args[i] == "--dry-run":
            dry = True; i += 1
        else:
            sys.stderr.write("sweep: unknown argument %r\n" % args[i])
            return 2

    os.makedirs(STATE_DIR, exist_ok=True)
    lock = open(os.path.join(STATE_DIR, "sweep.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        emit({"stopped": [], "skipped": "locked"})
        return 0
    now = time.time()
    if not dry:
        try:
            if now - os.stat(SWEEP_STAMP).st_mtime < SWEEP_EVERY_SEC:
                emit({"stopped": [], "skipped": "recent"})
                return 0
        except OSError:
            pass
        open(SWEEP_STAMP, "w").close()

    attached = attached_jobs()
    idle = []
    for path in glob.glob(os.path.join(CLAUDE_HOME, "sessions", "*.json")):
        meta = read_json(path)
        if not isinstance(meta, dict) or meta.get("kind") != "bg" or not meta.get("jobId"):
            continue
        if meta.get("status") != "idle" or not proc_alive(meta.get("pid"), meta.get("procStart")):
            continue
        sid, job = meta.get("sessionId") or "", str(meta["jobId"])
        transcripts = glob.glob(os.path.join(CLAUDE_HOME, "projects", "*", sid + ".jsonl")) if sid else []
        if not transcripts:
            continue   # never prompted: `reap` deals with those
        since = (meta.get("statusUpdatedAt") or meta.get("updatedAt") or 0) / 1000.0
        state = read_json(os.path.join(CLAUDE_HOME, "jobs", job, "state.json")) or {}
        in_flight = state.get("inFlight") if isinstance(state.get("inFlight"), dict) else {}
        why = ("protected" if job in protect
               else "attached" if job in attached
               else "background work" if in_flight.get("tasks") or in_flight.get("queued") or state.get("children")
               else "pending wakeup / monitor / cron" if has_pending(transcripts[0])
               else "")
        idle.append({"job": job, "id": sid, "name": meta.get("name") or state.get("name") or job,
                     "idle": now - since, "keep": why})
    idle.sort(key=lambda r: r["idle"])   # newest first

    kept = sum(1 for r in idle if r["keep"])
    report = []
    for r in idle:
        if r["keep"]:
            report.append(dict(r, action="keep"))
            continue
        if r["idle"] < SWEEP_GRACE_SEC or (r["idle"] < idle_min * 60 and kept < keep):
            kept += 1
            report.append(dict(r, action="keep", keep="recent"))
            continue
        report.append(dict(r, action="stop", keep="idle %dm" % (r["idle"] // 60) if r["idle"] >= idle_min * 60 else "over the cap"))

    stopped = [r for r in report if r["action"] == "stop"]
    if dry:
        emit({"stopped": [], "plan": report})
        return 0
    # Why each one left running is still up, for the Sessions rows.
    tmp = AWAKE_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"at": int(now * 1000), "jobs": {r["job"]: r["keep"] for r in report if r["action"] == "keep"}}, f)
    os.replace(tmp, AWAKE_PATH)
    claude = shutil.which("claude") or "claude"
    asleep = read_json(ASLEEP_PATH) or {}
    for r in stopped:
        subprocess.run([claude, "stop", r["job"]], capture_output=True)
        asleep[r["id"]] = int(now * 1000)
    if stopped:
        asleep = {k: v for k, v in asleep.items() if now - v / 1000.0 < ASLEEP_FOR_SEC}
        tmp = ASLEEP_PATH + ".tmp"
        with open(tmp, "w") as f:
            json.dump(asleep, f)
        os.replace(tmp, ASLEEP_PATH)
    emit({"stopped": [{"job": r["job"], "id": r["id"], "name": r["name"], "why": r["keep"]} for r in stopped]})
    return 0


def stop_job(job):
    if not re.fullmatch(r"[0-9a-f]{6,}", job):
        return 2
    subprocess.run([shutil.which("claude") or "claude", "stop", job], capture_output=True)
    return 0


# ---- tmux's screen (SGR escapes only) → Qt rich text

BASE16 = ["#000000", "#cd3131", "#0dbc79", "#e5e510", "#2472c8", "#bc3fbc", "#11a8cd", "#e5e5e5",
          "#666666", "#f14c4c", "#23d18b", "#f5f543", "#3b8eea", "#d670d6", "#29b8db", "#ffffff"]


def color256(n):
    if n < 16:
        return BASE16[n]
    if n < 232:
        n -= 16
        steps = [0, 95, 135, 175, 215, 255]
        return "#%02x%02x%02x" % (steps[n // 36], steps[n // 6 % 6], steps[n % 6])
    v = 8 + (n - 232) * 10
    return "#%02x%02x%02x" % (v, v, v)


class Style:
    def __init__(self):
        self.reset()

    def reset(self):
        self.fg = self.bg = None
        self.bold = self.dim = self.italic = self.under = self.inverse = False

    def apply(self, params):
        codes = [int(p) if p.isdigit() else 0 for p in re.split(r"[;:]", params)] if params else [0]
        i = 0
        while i < len(codes):
            c = codes[i]
            if c == 0:
                self.reset()
            elif c == 1:
                self.bold = True
            elif c == 2:
                self.dim = True
            elif c == 3:
                self.italic = True
            elif c == 4:
                self.under = True
            elif c == 7:
                self.inverse = True
            elif c == 22:
                self.bold = self.dim = False
            elif c == 23:
                self.italic = False
            elif c == 24:
                self.under = False
            elif c == 27:
                self.inverse = False
            elif 30 <= c <= 37 or 90 <= c <= 97:
                self.fg = BASE16[c - 30 if c < 90 else c - 82]
            elif 40 <= c <= 47 or 100 <= c <= 107:
                self.bg = BASE16[c - 40 if c < 100 else c - 92]
            elif c == 39:
                self.fg = None
            elif c == 49:
                self.bg = None
            elif c in (38, 48) and i + 1 < len(codes):
                if codes[i + 1] == 5 and i + 2 < len(codes):
                    value, i = color256(codes[i + 2] & 255), i + 2
                elif codes[i + 1] == 2 and i + 4 < len(codes):
                    value, i = "#%02x%02x%02x" % tuple(min(255, x) for x in codes[i + 2:i + 5]), i + 4
                else:
                    value = None
                if c == 38:
                    self.fg = value
                else:
                    self.bg = value
            i += 1

    def css(self):
        fg, bg = self.fg, self.bg
        if self.inverse:
            fg, bg = bg or "@BG@", fg or "@FG@"
        parts = []
        if fg:
            parts.append("color:" + fg)
        if bg:
            parts.append("background-color:" + bg)
        if self.bold:
            parts.append("font-weight:bold")
        if self.italic:
            parts.append("font-style:italic")
        if self.under:
            parts.append("text-decoration:underline")
        return ";".join(parts), self.dim


SGR = re.compile(r"\x1b\[([0-9;:]*)m")
# Everything else tmux may pass through: OSC (hyperlinks: ESC ] 8 ; … ESC \)
# and any non-SGR CSI. The text between a link's ends stays.
NOISE = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-9;:?<=>]*[A-Za-ln-z@`]")


RULE = re.compile(r"^─{8,}")
# Scrolled up, Claude lays a pill over a line of the conversation: "Jump to
# bottom (ctrl+End) ↓", or "3 new messages (ctrl+End) ↓" once more arrives.
# The card draws its own over the screen instead, so the pill goes (with its
# colors) and the frame says "scrolled" and how many are unread. The pill
# always opens with its colors, which keeps the conversation quoting it safe.
JUMP = re.compile(r"(?:\x1b\[[0-9;:]*m)+ ?(?:Jump to bottom|(\d+) new messages?)(?: \([^)\x1b]*\))? ↓ ?")
IMAGE_TOKEN = re.compile(r"\[Image #\d+\]")


def trim(raws, rows, cursor, scrolled=False):
    """The lines worth showing in the card, and what the dropped chrome said.

    The card draws model, mode and folder itself, so this drops the welcome
    banner (reading the model off it), update notices, and everything under
    the prompt box: the status line and the mode line (reading the mode).
    While the prompt is empty the box goes too: the card draws its own, so
    typing doesn't wait on a round trip through the terminal.
    The card shows the last `rows` of them, or the first once scrolled back
    to the banner: the pane's extra rows would hide the conversation's start.
    Text in Claude's box that the card didn't put there (a prompt given back
    after an interrupt) comes out as the draft, for the card to take over.
    Returns (line indexes to keep, model or None, mode or None, prompt ready,
    attachments, effort or None, suggestion, draft)."""
    plain = [SGR.sub("", raw) for raw in raws]
    keep = list(range(len(plain)))
    model = mode = effort = None
    ready = False
    attachments = []
    suggestion = ""
    draft = ""
    banner = False
    for i, text in enumerate(plain[:6]):
        if "Claude Code v" in text:
            # "▝▜██████▀  Opus 5.5 with medium effort · Claude Pro"
            info = re.sub(r"^[\s\u2580-\u259f]+", "", plain[i + 1] if i + 1 < len(plain) else "")
            model = info.split(" · ")[0].split(" with ")[0].strip() or None
            m = re.search(r" with (\w+) effort", info)
            effort = m.group(1) if m else None
            end = i + 3
            while end < len(plain) and not plain[end].strip():
                end += 1
            keep = [k for k in keep if k >= end]
            banner = True
            break
    # The prompt box: two rules with the ❯ line between, the footer under it.
    rules = [i for i, text in enumerate(plain) if RULE.match(text.strip())]
    if len(rules) >= 2:
        top, bottom = rules[-2], rules[-1]
        # The ❯ opens the box's first line. A question dialog has ❯ on its
        # selected option ("❯ 4. typed answer") or under a rule ("❯ Chat about
        # this"), which isn't a prompt: its text must not become the draft.
        first = plain[top + 1].lstrip() if top + 1 < bottom else ""
        if bottom - top <= 12 and len(plain) - bottom <= 6 \
                and first.startswith("❯") and not re.match(r"❯\s*\d+\.", first):
            mode = "default"
            for text in plain[bottom + 1:]:
                m = re.search(r"([a-z][a-z ]*?) on \(shift\+tab", text)
                if m:
                    mode = m.group(1).replace(" mode", "").strip()
            # Empty: one ❯ line with nothing typed (a dim placeholder sits
            # after the cursor, so the cursor still at the start counts too).
            line = top + 1
            typed = plain[line].strip().lstrip("❯").strip()
            # Pasted images sit in Claude's box as [Image #1]: the card shows
            # them as attachments and keeps its own prompt.
            attachments = IMAGE_TOKEN.findall(typed)
            rest = IMAGE_TOKEN.sub("", typed).strip()
            # A cursor still at the start: what follows is the gray suggestion,
            # however many lines it wraps to.
            at_start = cursor is not None and cursor[1] == line and cursor[0] <= 3
            ready = (bottom - top == 2 and (not typed or (attachments and not rest))) or at_start
            if ready and rest and not attachments:
                suggestion = rest if bottom - top == 2 else box_text(plain[top:bottom])
            if not ready:
                draft = box_text(plain[top:bottom])
            keep = [k for k in keep if k < (top if ready else bottom)]
            # The TUI pads short conversations down to the prompt: close the gap.
            gap = top - 1
            while gap >= 0 and (not plain[gap].strip() or "Update available!" in plain[gap]):
                gap -= 1
            keep = [k for k in keep if not gap < k < top]
    keep = [k for k in keep if "Update available!" not in plain[k]]
    # The TUI pads down to the prompt box wherever it likes, above the spinner
    # mid-turn too, and the padding shrinks as the reply streams in, so the
    # view would hold a block of black and then jump. Claude separates blocks
    # with one blank line; any more is padding.
    keep = [k for n, k in enumerate(keep)
            if plain[k].strip() or (n > 0 and plain[keep[n - 1]].strip())]
    while keep and not plain[keep[0]].strip():
        keep.pop(0)
    while keep and not plain[keep[-1]].strip():
        keep.pop()
    shown = keep[:rows] if banner and scrolled else keep[-rows:]
    # Scrolled into a long conversation, Claude pins the prompt being answered
    # to the top row: keep it there when the pane's extra rows push it out.
    if rows > 1 and keep and keep[0] == 0 and plain[0].startswith("❯") and shown[0] != 0:
        shown = [0] + keep[-(rows - 1):]
    return shown, model, mode, ready, attachments if ready else [], effort, suggestion, draft


def box_text(box):
    """The text in Claude's prompt box (its top rule, then the ❯ line and
    the lines under it), images left out. The box wraps long lines at a
    space: a line that ran near the edge carries on with a space, any other
    break was a newline."""
    width = len(box[0].rstrip())
    text = ""
    for n, line in enumerate(box[1:]):
        part = line.rstrip()
        part = part.lstrip()[1:] if n == 0 else part
        part = IMAGE_TOKEN.sub("", part[2:] if part.startswith("  ") else part.lstrip())
        if n:
            text += " " if len(box[n].rstrip()) >= width - 12 else "\n"
        text += part.strip() if n == 0 else part.rstrip()
    return text.strip()


# Glyphs Claude draws that the card's monospace font (JetBrains Mono) lacks.
# Qt borrows them from other fonts, wider or taller ones, so the spinner
# (· ✢ ✳ ✶ ✻ ✽) changed width and line height every frame and the screen
# shook; these stand-ins are all in the font.
GLYPHS = str.maketrans({
    "✢": "+", "✳": "×", "✻": "*", "✽": "✶",
    "⏺": "●", "⎿": "└", "⎯": "─",
    "☐": "□", "☒": "■", "◻": "□", "◼": "■", "✔": "✓", "✘": "✗",
    "◐": "○", "◑": "○", "◒": "○", "◓": "○",
})


def to_html(raws, keep, cursor):
    """A block per line, a span per style run. The cursor cell is drawn inverted.

    tmux doesn't restate the style at a line start (it carries on from the
    line before), so every line is parsed, dropped ones too. Lines are blocks
    rather than one <pre>: Qt gives a newline the background of the span
    before it and paints that to the right edge, so a highlighted prompt
    would bleed over the reply under it."""
    style = Style()
    shown = set(keep)
    lines = []
    for y, raw in enumerate(raws):
        raw = raw.translate(GLYPHS)
        cells = []   # (char, css, dim)
        pos = 0
        for m in SGR.finditer(raw):
            for ch in raw[pos:m.start()]:
                cells.append((ch,) + style.css())
            style.apply(m.group(1))
            pos = m.end()
        for ch in raw[pos:]:
            cells.append((ch,) + style.css())
        if y not in shown:
            continue
        if cursor and cursor[1] == y:
            x = cursor[0]
            while len(cells) <= x:
                cells.append((" ",) + Style().css())
            cells[x] = (cells[x][0], "background-color:@FG@;color:@BG@", False)
        out, run, key = [], [], None
        for ch, css, dim in cells:
            if (css, dim) != key:
                if run:
                    out.append(span(key, "".join(run)))
                run, key = [], (css, dim)
            run.append(ch)
        if run:
            out.append(span(key, "".join(run)))
        lines.append('<p style="margin:0;white-space:pre">%s</p>' % ("".join(out) or " "))
    return "".join(lines)


def span(key, text):
    css, dim = key
    text = html.escape(text, quote=False)
    if dim and "color:" not in css.replace("background-color:", ""):
        css = (css + ";" if css else "") + "color:@DIM@"
    return '<span style="%s">%s</span>' % (css, text) if css else text


# ---- the hidden pane

def tmux(*args, check=False):
    return subprocess.run(["tmux", "-L", SOCKET, "-f", "/dev/null"] + list(args),
                          capture_output=True, text=True, check=check)


def reap():
    """Panes left by viewers that are gone (named live-<job>-<viewer pid>)."""
    for name in tmux("list-sessions", "-F", "#{session_name}").stdout.split():
        pid = name.rsplit("-", 1)[-1]
        if name.startswith("live-") and pid.isdigit() and not os.path.exists("/proc/" + pid):
            tmux("kill-session", "-t", name)


CURSOR_FORMAT = "#{pane_dead} #{cursor_x} #{cursor_y} #{cursor_flag}"
# With nothing drawn, still a look now and then (a pane dying draws nothing).
IDLE_LOOK_SEC = 1.0
BLOCK_END = re.compile(rb"^%(end|error) \d+ (\d+) \d+$")


class Control:
    """A tmux control-mode client on the pane. It says when the pane draws
    (%output), so an unchanged screen is never captured, and it runs the
    captures without starting a tmux process for each one."""

    def __init__(self, name):
        self.proc = subprocess.Popen(["tmux", "-L", SOCKET, "-f", "/dev/null", "-C", "attach", "-t", name],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.fd = self.proc.stdout.fileno()
        os.set_blocking(self.fd, False)
        self.buf = b""
        self.block = None      # the reply being read: (number, ours, lines)
        self.replies = []      # finished replies to our commands: (ok, text), oldest first
        self.dirty = True
        self.closed = False

    def send(self, *commands):
        try:
            self.proc.stdin.write("".join(c + "\n" for c in commands).encode())
            self.proc.stdin.flush()
        except (OSError, ValueError):
            self.closed = True

    def read(self):
        try:
            chunk = os.read(self.fd, 1 << 16)
        except BlockingIOError:
            return
        except OSError:
            chunk = b""
        if not chunk:
            self.closed = True
            return
        *lines, self.buf = (self.buf + chunk).split(b"\n")
        for line in lines:
            if self.block is not None:
                end = BLOCK_END.match(line)
                if end and end.group(2) == self.block[0]:
                    if self.block[1]:
                        self.replies.append((end.group(1) == b"end", b"\n".join(self.block[2]).decode(errors="replace")))
                    self.block = None
                else:
                    self.block[2].append(line)
            elif line.startswith(b"%begin "):
                parts = line.split()
                # Flag 1: a command this client sent (attaching answers one of its own).
                ours = len(parts) > 3 and parts[3].isdigit() and int(parts[3]) & 1
                self.block = (parts[2] if len(parts) > 2 else b"", bool(ours), [])
            elif line.startswith(b"%output "):
                self.dirty = True
            elif line.startswith(b"%exit"):
                self.closed = True

    def close(self):
        try:
            self.proc.stdin.close()
        except OSError:
            pass
        try:
            self.proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            self.proc.kill()


PASTE_DIR = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "clawdius", "paste")
# Pasted images live in RAM (the runtime dir is a tmpfs); a day is long past
# Claude having read them.
PASTE_KEEP_SEC = 86400


def clean_pastes():
    try:
        names = os.listdir(PASTE_DIR)
    except OSError:
        return
    cutoff = time.time() - PASTE_KEEP_SEC
    for n in names:
        path = os.path.join(PASTE_DIR, n)
        try:
            if os.stat(path).st_mtime < cutoff:
                os.remove(path)
        except OSError:
            pass


def view(job, cols, rows, theme):
    claude = shutil.which("claude") or "claude"
    name = "live-%s-%d" % (re.sub(r"[^0-9A-Za-z]", "", job), os.getpid())
    env = ["-e", "COLORTERM=truecolor"]
    reap()
    clean_pastes()
    tmux("new-session", "-d", "-s", name, "-x", str(cols), "-y", str(rows + EXTRA_ROWS), *env, claude, "attach", job, check=True)
    for opt in (("status", "off"), ("window-size", "manual"), ("remain-on-exit", "on")):
        tmux("set-option", "-t", name, *opt)
    tmux("set-option", "-g", "default-terminal", "tmux-256color")
    # The shell may SIGKILL us when the card closes: a detached watchdog takes
    # the pane down once this process is gone (tail waits without a process a second).
    subprocess.Popen(["sh", "-c", 'tail --pid="$1" -f /dev/null 2>/dev/null; tmux -L "$2" -f /dev/null kill-session -t "$3"',
                      "watchdog", str(os.getpid()), SOCKET, name],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

    def cleanup(*_):
        if focused:
            focus(False)
        tmux("kill-session", "-t", name)
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGHUP, cleanup)

    last = None
    last_input = 0.0
    model = mode = effort = None
    focused = False

    # Focus in / out reports (CSI I / CSI O), as a terminal sends them: a
    # background session only predicts the next prompt while a viewer has focus.
    def focus(on):
        tmux("send-keys", "-t", name, "-H", "1b", "5b", "49" if on else "4f")

    def show(info, screen):
        """Emit the frame if it changed; False once the pane is gone."""
        nonlocal last, model, mode, effort, focused
        if len(info) < 4:
            emit({"html": "", "alive": False})
            return False
        dead = info[0] == "1"
        cursor = (int(info[1]), int(info[2])) if info[3] == "1" and not dead else None
        frame = (screen, cursor, dead)
        if frame == last:
            return True
        last = frame
        raws = NOISE.sub("", screen).split("\n")
        scrolled = False
        unread = 0
        for n, raw in enumerate(raws):
            pill = JUMP.search(raw)
            if pill:
                raws[n] = raw[:pill.start()] + "\x1b[0m" + " " * len(SGR.sub("", pill.group(0))) + raw[pill.end():]
                scrolled = True
                unread = int(pill.group(1) or 0)
        keep, seen_model, seen_mode, ready, attachments, seen_effort, suggestion, draft = trim(raws, rows, cursor, scrolled)
        model, mode, effort = seen_model or model, seen_mode or mode, seen_effort or effort
        # Once Claude's prompt box is up, it's listening for the focus report.
        if seen_mode and not focused and not dead:
            focus(True)
            focused = True
        page = to_html(raws, keep, None if ready else cursor)
        for token, color in zip(("@FG@", "@BG@", "@DIM@"), theme):
            page = page.replace(token, color)
        emit({"html": page, "alive": not dead, "model": model or "", "mode": mode or "", "prompt": ready,
              "attachments": attachments, "effort": effort or "", "scrolled": scrolled, "unread": unread,
              "suggestion": suggestion, "draft": draft})
        return True

    # Without a control client (it failed, or went away), the old way: two
    # tmux processes a frame.
    try:
        ctl = Control(name)
    except OSError:
        ctl = None
    asked = False        # a look is out: waiting on its two replies
    last_look = 0.0
    try:
        while True:
            # Quicker frames for a moment after input, so its effect shows fast.
            now = time.monotonic()
            gap = FAST_FRAME_SEC if now - last_input < FAST_FOR_SEC else FRAME_SEC
            if ctl is None or asked:
                wait = gap
            else:
                wait = max(0.0, last_look + (gap if ctl.dirty else IDLE_LOOK_SEC) - now)
            ready, _, _ = select.select([sys.stdin] + ([ctl.fd] if ctl else []), [], [], wait)
            if sys.stdin in ready:
                line = sys.stdin.readline()
                if not line:
                    break   # the card let go
                handle(name, line)
                last_input = time.monotonic()
                # Drain whatever else is queued before drawing, so typing stays snappy.
                while True:
                    more, _, _ = select.select([sys.stdin], [], [], 0)
                    if not more:
                        break
                    line = sys.stdin.readline()
                    if not line:
                        return
                    handle(name, line)
                if ctl:
                    ctl.dirty = True
            if ctl and ctl.fd in ready:
                ctl.read()
            if ctl and ctl.closed:
                ctl.close()
                ctl = None
                asked = False
            if ctl is None:
                info = tmux("display-message", "-p", "-t", name, CURSOR_FORMAT).stdout.split()
                screen = tmux("capture-pane", "-p", "-e", "-t", name).stdout.rstrip("\n") if len(info) >= 4 else ""
                if not show(info, screen):
                    break
                continue
            if not asked and time.monotonic() >= last_look + (gap if ctl.dirty else IDLE_LOOK_SEC):
                ctl.dirty = False
                last_look = time.monotonic()
                ctl.send("display-message -p -t %s '%s'" % (name, CURSOR_FORMAT), "capture-pane -p -e -t %s" % name)
                asked = True
            if asked and len(ctl.replies) >= 2:
                (info_ok, info), (screen_ok, screen) = ctl.replies[:2]
                del ctl.replies[:2]
                asked = False
                if not show(info.split() if info_ok else [], screen.rstrip("\n") if screen_ok else ""):
                    break
    finally:
        if ctl:
            ctl.close()
        if focused:
            focus(False)
        tmux("kill-session", "-t", name)


# ---- Conversation view

CHAT_BOOTSTRAP_BYTES = 1 << 20
CHAT_BOOTSTRAP_MSGS = 60
# How often the screen is looked at for "is Claude asking something".
CHAT_LOOK_SEC = 0.5
CHAT_BUSY_POLL_SEC = 0.3
CHAT_IDLE_POLL_SEC = 1.0
CHAT_QUIET_AFTER_SEC = 8.0
# Bookkeeping calls that mean nothing in a conversation.
CHAT_HIDDEN_TOOLS = ("ToolSearch", "TaskCreate", "TaskUpdate", "TodoWrite")


def tool_label(name, inp):
    """A one-line version of a tool call, for the chip between bubbles."""
    inp = inp if isinstance(inp, dict) else {}
    base = lambda p: os.path.basename(str(p).rstrip("/")) or str(p)
    if name == "WebSearch":
        return "Searched the web: " + " ".join(str(inp.get("query", "")).split())[:60]
    if name == "WebFetch":
        return "Fetched " + " ".join(str(inp.get("url", "")).split())[:60]
    if name == "Read":
        return "Read " + base(inp.get("file_path", ""))
    if name.startswith("mcp__"):
        return "Used " + name.split("__")[-1].replace("_", " ")
    return "Used " + name


class ChatLog:
    """The transcript, read incrementally into chat messages."""

    def __init__(self, job):
        self.job = job
        self.path = ""
        self.offset = 0
        self.mtime = 0.0
        self.started = False

    def find(self):
        state = read_json(os.path.join(CLAUDE_HOME, "jobs", self.job, "state.json")) or {}
        sid = state.get("sessionId") or ""
        found = glob.glob(os.path.join(CLAUDE_HOME, "projects", "*", sid + ".jsonl")) if sid else []
        self.path = found[0] if found else ""

    def read(self):
        """New messages since the last call (the recent ones on the first)."""
        if not self.path:
            self.find()
            if not self.path:
                return [], False
        try:
            st = os.stat(self.path)
        except OSError:
            return [], False
        if st.st_mtime == self.mtime and self.started:
            return [], False
        first = not self.started
        if first:
            self.started = True
            self.offset = max(0, st.st_size - CHAT_BOOTSTRAP_BYTES)
        self.mtime = st.st_mtime
        try:
            with open(self.path, "rb") as f:
                f.seek(self.offset)
                chunk = f.read()
        except OSError:
            return [], first
        end = chunk.rfind(b"\n")
        if end < 0:
            return [], first
        lines = chunk[: end + 1].splitlines()
        if first and self.offset > 0:
            lines = lines[1:]   # starts mid-record
        self.offset += end + 1
        msgs = []
        for line in lines:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            msgs += self.messages(rec)
        return (msgs[-CHAT_BOOTSTRAP_MSGS:] if first else msgs), first

    @staticmethod
    def messages(rec):
        if not isinstance(rec, dict) or rec.get("isSidechain") or rec.get("isMeta"):
            return []
        kind = rec.get("type")
        msg = rec.get("message") or {}
        content = msg.get("content")
        at = 0.0
        stamp = str(rec.get("timestamp") or "")
        try:
            at = time.mktime(time.strptime(stamp[:19], "%Y-%m-%dT%H:%M:%S")) - time.timezone
        except ValueError:
            pass
        uid = str(rec.get("uuid") or "")
        out = []
        if kind == "user":
            parts = [content] if isinstance(content, str) else \
                [b.get("text", "") for b in content or [] if isinstance(b, dict) and b.get("type") == "text"]
            text = "\n".join(p for p in parts if isinstance(p, str) and p.strip() and not p.lstrip().startswith("<")).strip()
            if text:
                out.append({"key": uid, "role": "user", "text": IMAGE_TOKEN.sub("", text).strip() or text, "at": at})
        elif kind == "assistant" and isinstance(content, list):
            for i, block in enumerate(content):
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "text" and str(block.get("text") or "").strip():
                    out.append({"key": "%s:%d" % (uid, i), "role": "assistant", "text": block["text"].strip(), "at": at})
                elif block.get("type") == "tool_use" and block.get("name") not in CHAT_HIDDEN_TOOLS:
                    out.append({"key": "%s:%d" % (uid, i), "role": "tool",
                                "text": tool_label(str(block.get("name") or ""), block.get("input")), "at": at})
        return out


def chat(job):
    claude = shutil.which("claude") or "claude"
    name = "live-%s-%d" % (re.sub(r"[^0-9A-Za-z]", "", job), os.getpid())
    reap()
    clean_pastes()
    tmux("new-session", "-d", "-s", name, "-x", "100", "-y", str(30 + EXTRA_ROWS), "-e", "COLORTERM=truecolor", claude, "attach", job, check=True)
    for opt in (("status", "off"), ("window-size", "manual"), ("remain-on-exit", "on")):
        tmux("set-option", "-t", name, *opt)
    tmux("set-option", "-g", "default-terminal", "tmux-256color")
    subprocess.Popen(["sh", "-c", 'tail --pid="$1" -f /dev/null 2>/dev/null; tmux -L "$2" -f /dev/null kill-session -t "$3"',
                      "watchdog", str(os.getpid()), SOCKET, name],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

    def cleanup(*_):
        tmux("kill-session", "-t", name)
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGHUP, cleanup)

    log = ChatLog(job)
    state = None
    seen_box = False     # Claude's prompt box has been up: before, it's just starting
    missing = 0          # looks in a row that found no prompt box
    active_at = time.monotonic()
    try:
        ctl = Control(name)
    except OSError:
        ctl = None
    asked = False
    last_look = 0.0
    last_poll = 0.0

    def look(info, screen):
        nonlocal state, seen_box, missing
        dead = bool(info) and info[0] == "1"
        raws = NOISE.sub("", screen).split("\n")
        ready = trim(raws, 30, None)[3]
        # A prompt box, or text left in it, both mean Claude listens to us.
        box = any(RULE.match(SGR.sub("", r).strip()) for r in raws) and any(SGR.sub("", r).lstrip().startswith("❯") for r in raws)
        seen_box = seen_box or box
        missing = 0 if (box or ready) else missing + 1
        now_state = {"alive": not dead, "asking": seen_box and missing >= 2 and not dead}
        if now_state != state:
            state = now_state
            emit({"state": state})
        return not dead

    try:
        while True:
            now = time.monotonic()
            busy = now - active_at < CHAT_QUIET_AFTER_SEC
            poll = CHAT_BUSY_POLL_SEC if busy else CHAT_IDLE_POLL_SEC
            wait = max(0.0, last_poll + poll - now)
            ready, _, _ = select.select([sys.stdin] + ([ctl.fd] if ctl else []), [], [], wait)
            if sys.stdin in ready:
                line = sys.stdin.readline()
                if not line:
                    break
                handle(name, line)
                active_at = time.monotonic()
                if ctl:
                    ctl.dirty = True
            if ctl and ctl.fd in ready:
                ctl.read()
                if ctl.dirty:
                    active_at = time.monotonic()
            if ctl and ctl.closed:
                ctl.close()
                ctl = None
                asked = False
            now = time.monotonic()
            if now - last_poll >= poll:
                last_poll = now
                msgs, first = log.read()
                if first:
                    emit({"history": msgs})
                else:
                    for m in msgs:
                        emit({"msg": m})
            if ctl is None:
                if now - last_look >= CHAT_LOOK_SEC * 2:
                    last_look = now
                    info = tmux("display-message", "-p", "-t", name, CURSOR_FORMAT).stdout.split()
                    screen = tmux("capture-pane", "-p", "-e", "-t", name).stdout.rstrip("\n") if len(info) >= 4 else ""
                    if not look(info, screen) and len(info) < 4:
                        break
                continue
            if not asked and now - last_look >= (CHAT_LOOK_SEC if ctl.dirty else IDLE_LOOK_SEC * 3):
                ctl.dirty = False
                last_look = now
                ctl.send("display-message -p -t %s '%s'" % (name, CURSOR_FORMAT), "capture-pane -p -e -t %s" % name)
                asked = True
            if asked and len(ctl.replies) >= 2:
                (info_ok, info), (screen_ok, screen) = ctl.replies[:2]
                del ctl.replies[:2]
                asked = False
                if not info_ok:
                    break
                look(info.split(), screen.rstrip("\n") if screen_ok else "")
    finally:
        if ctl:
            ctl.close()
        tmux("kill-session", "-t", name)


def handle(name, line):
    try:
        cmd = json.loads(line)
    except ValueError:
        return
    if cmd.get("clip"):
        attach_clipboard_image(name)
    if cmd.get("submit"):
        # Pasted whole, then Enter on its own: an Enter in the same burst
        # reads as part of the paste and doesn't send.
        tmux("set-buffer", "-b", "crab", "--", str(cmd["submit"]))
        tmux("paste-buffer", "-p", "-d", "-b", "crab", "-t", name)
        time.sleep(SUBMIT_PAUSE_SEC)
        tmux("send-keys", "-t", name, "Enter")
    if cmd.get("text"):
        text = str(cmd["text"])
        if "\n" in text:
            # Typed as keys, a newline would submit; a bracketed paste keeps it whole.
            tmux("set-buffer", "-b", "crab", "--", text)
            tmux("paste-buffer", "-p", "-d", "-b", "crab", "-t", name)
        else:
            tmux("send-keys", "-t", name, "-l", "--", text)
    for key in cmd.get("keys") or []:
        tmux("send-keys", "-t", name, str(key))
    # Mouse-wheel steps (SGR, near the top-left, in the conversation): Claude
    # scrolls a line for each, where PageUp / PageDown jump a page.
    wheel = int(cmd.get("wheel") or 0)
    if wheel:
        step = "\x1b[<%d;2;2M" % (64 if wheel > 0 else 65)
        tmux("send-keys", "-t", name, "-l", "--", step * min(abs(wheel), 60))
    # Empties Claude's box: deletes forward, then back, so the caret's place
    # doesn't matter (keys that only edit, unlike Ctrl+C, which can interrupt).
    # A few at a time: a long burst reads as a paste and is mostly dropped.
    clear = min(int(cmd.get("clear") or 0), 4000)
    for key in ("DC", "BSpace") if clear else ():
        for done in range(0, clear, CLEAR_BATCH):
            tmux("send-keys", "-t", name, "-N", str(min(CLEAR_BATCH, clear - done)), key)
            time.sleep(CLEAR_PAUSE_SEC)
    size = cmd.get("size")
    if isinstance(size, list) and len(size) == 2:
        tmux("resize-window", "-t", name, "-x", str(max(20, int(size[0]))), "-y", str(max(5, int(size[1])) + EXTRA_ROWS))


def attach_clipboard_image(name):
    """An image on the clipboard: save it and paste its path, which Claude
    turns into [Image #n]. (Its own Ctrl+V would read the clipboard from the
    background daemon, which may not see this Wayland session.)"""
    try:
        types = subprocess.run(["wl-paste", "--list-types"], capture_output=True, text=True, timeout=2).stdout.split()
    except (OSError, subprocess.TimeoutExpired):
        return
    images = [t for t in types if t.startswith("image/")]
    if not images:
        return
    kind = "image/png" if "image/png" in images else images[0]
    os.makedirs(PASTE_DIR, exist_ok=True)
    path = os.path.join(PASTE_DIR, "clip-%d.%s" % (time.time() * 1000, kind.split("/")[1].split("+")[0]))
    try:
        with open(path, "wb") as out:
            subprocess.run(["wl-paste", "--no-newline", "--type", kind], stdout=out, timeout=5, check=True)
    except (OSError, subprocess.SubprocessError):
        return
    tmux("set-buffer", "-b", "crab", "--", path)
    tmux("paste-buffer", "-p", "-d", "-b", "crab", "-t", name)


# ---- Prompt history

PASTED = re.compile(r"\[Pasted text #(\d+)(?: \+\d+ lines)?\]")


def history(project, limit=200):
    """The prompts given in PROJECT (or the repository whose worktree it is), newest first and each once, as Claude's
    own Up arrow goes through them (~/.claude/history.jsonl): pasted text put
    back in place of its [Pasted text #1], images left out. Prints a JSON list."""
    project = os.path.realpath(os.path.expanduser(project))
    # A session in one of Claude's worktrees counts as its repository's.
    projects = {project, project.split("/.claude/worktrees/")[0]}
    entries = []
    try:
        with open(os.path.join(CLAUDE_HOME, "history.jsonl"), encoding="utf-8") as f:
            for line in f:
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                if isinstance(entry, dict) and entry.get("project") in projects:
                    entries.append(entry)
    except OSError:
        pass
    prompts = []
    for entry in reversed(entries):
        pasted = entry.get("pastedContents") or {}
        missing = []

        def fill(m):
            content = (pasted.get(m.group(1)) or {}).get("content")
            if not isinstance(content, str):
                missing.append(m.group(0))
                return m.group(0)
            return content

        text = IMAGE_TOKEN.sub("", PASTED.sub(fill, str(entry.get("display") or ""))).strip()
        if text and not missing and text not in prompts:
            prompts.append(text)
            if len(prompts) >= limit:
                break
    emit(prompts)


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "reap":
        return reap_empty(sys.argv[2:])
    if len(sys.argv) >= 2 and sys.argv[1] == "sweep":
        return sweep(sys.argv[2:])
    if len(sys.argv) == 3 and sys.argv[1] == "trust":
        return trust(sys.argv[2])
    if len(sys.argv) == 3 and sys.argv[1] == "stop":
        return stop_job(sys.argv[2])
    if len(sys.argv) == 3 and sys.argv[1] == "history":
        return history(sys.argv[2])
    if len(sys.argv) == 3 and sys.argv[1] == "chat":
        return chat(sys.argv[2])
    if len(sys.argv) >= 2 and sys.argv[1] == "start":
        return launch_job(sys.argv[2:])
    if len(sys.argv) >= 2 and sys.argv[1] == "launch":
        return launch(sys.argv[2:])
    if len(sys.argv) in (5, 8) and sys.argv[1] == "view":
        theme = sys.argv[5:8] or ["#e5e5e5", "#101010", "#808080"]
        return view(sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), theme)
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main() or 0)
