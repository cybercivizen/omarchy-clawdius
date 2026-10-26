#!/usr/bin/env python3
"""Claude Crab feed: what every running Claude Code session is doing right now.

Prints one JSON snapshot per line on stdout whenever something changes, for
the bar widget to render. Zero config: it reads what Claude Code already
writes under ~/.claude —

  sessions/<pid>.json        one per live CLI process: name, cwd, busy/idle
  jobs/<id>/state.json       background jobs: the current step's description
  projects/*/<sid>.jsonl     transcripts: last tool call, todos/tasks, replies

None of these are a documented API, so every read is defensive: a missing or
reshaped field degrades a row, never the feed.

When a session finishes a turn, or gets stuck waiting on you, the snapshot
carries a toast for the island to show (`toast`, stamped with when). Every bar
(one per monitor) runs its own feed; the bars agree which island shows it.
"""

import json
import os
import re
import subprocess
import sys
import time
from collections import deque
from datetime import datetime

# focus.py is imported from here: a __pycache__ written into the plugin folder
# would make the shell reload the whole plugin.
sys.dont_write_bytecode = True

HOME = os.path.expanduser("~")
CLAUDE_DIR = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(HOME, ".claude")
SESSIONS_DIR = os.path.join(CLAUDE_DIR, "sessions")
JOBS_DIR = os.path.join(CLAUDE_DIR, "jobs")
PROJECTS_DIR = os.path.join(CLAUDE_DIR, "projects")
PLUGIN_DIR = os.path.dirname(os.path.abspath(__file__))

POLL_SEC = float(os.environ.get("CLAWDIUS_POLL", "1.0"))
NOTIFY = os.environ.get("CLAWDIUS_NOTIFY", "1") != "0"
# A turn shorter than this is a quick answer you were watching anyway.
NOTIFY_MIN_BUSY_SEC = float(os.environ.get("CLAWDIUS_NOTIFY_MIN_BUSY", "8"))
TRANSCRIPT_BOOTSTRAP_BYTES = 4 * 1024 * 1024
# Busy with nothing written for this long since the last tool result or
# prompt: the model is thinking rather than waiting on a tool.
THINKING_AFTER_SEC = 8
# A session's status is "waiting" while a dialog blocks it. "dialog open" is
# one you opened yourself (/config and friends), so it doesn't call for you.
SELF_DIALOGS = ("dialog open",)
# Calls that only keep the task list; the list itself shows them.
PLAN_TOOLS = ("TaskCreate", "TaskUpdate", "TaskList", "TaskGet", "TodoWrite")
WAIT_GRACE_SEC = 2.0
# Subagents whose transcript has gone quiet this long, and background shells
# this old, are treated as finished even if the hand-back was never seen.
AGENT_STALE_SEC = 15 * 60
SHELL_STALE_SEC = 6 * 3600
# What a session's context is measured against when the settings don't say:
# Claude Code's auto-compact window (the `autoCompactWindow` setting, per model
# under modelSettings, or CLAUDE_CODE_AUTO_COMPACT_WINDOW).
DEFAULT_CONTEXT_WINDOW = 200_000
# Models with a native 1M window. Transcripts record the bare id, without the
# `[1m]` suffix, so the family has to be recognised by name.
NATIVE_1M_MODEL = re.compile(r"claude-(?:(?:opus|sonnet|fable)-[5-9]|haiku-5-5|opus-4-[7-9])")
SETTINGS_FILE = os.path.join(CLAUDE_DIR, "settings.json")
# What `/model` and `/effort` print into the transcript. opusplan is "Opus Plan Mode" (older) or "Opus in plan mode, else Sonnet".
MODEL_SET = re.compile(r"^<local-command-stdout>(?:Set model to|Kept model as) `([^`]+)`")
EFFORT_SET = re.compile(r"^<local-command-stdout>Set effort level to (\w+)")
CHILD_DONE = re.compile(r"<task-id>([\w-]+)</task-id>|<agent-message from=\"([\w-]+)\"")


_settings = {"mtime": None, "data": {}}


def context_window(model, used):
    """Tokens a session's context fills before it auto-compacts."""
    env = os.environ.get("CLAUDE_CODE_AUTO_COMPACT_WINDOW", "")
    window = int(env) if env.isdigit() else 0
    if not window:
        m = mtime(SETTINGS_FILE)
        if m != _settings["mtime"]:
            _settings["mtime"] = m
            data = read_json(SETTINGS_FILE)
            _settings["data"] = data if isinstance(data, dict) else {}
        data = _settings["data"]
        per_model = (data.get("modelSettings") or {}).get(model) or {}
        for v in (per_model.get("autoCompactWindow"), data.get("autoCompactWindow")):
            if isinstance(v, int) and v > 0:
                window = v
                break
    if not window:
        big = "[1m]" in model or NATIVE_1M_MODEL.search(model)
        if os.environ.get("CLAUDE_CODE_DISABLE_1M_CONTEXT"):
            big = False
        window = 1_000_000 if big else DEFAULT_CONTEXT_WINDOW
    # Past it without compacting: it must be a bigger window than we know.
    return window if used <= window else 1_000_000


_model_settings = {}


def model_setting(cwd):
    """The `model` setting a session in cwd starts on: the project's, then the user's."""
    paths = [os.path.join(cwd, ".claude", name) for name in ("settings.local.json", "settings.json")] if cwd else []
    for path in paths + [SETTINGS_FILE]:
        m = mtime(path)
        if not m:
            continue
        cached = _model_settings.get(path)
        if not cached or cached[0] != m:
            data = read_json(path)
            cached = _model_settings[path] = (m, str(data.get("model") or "") if isinstance(data, dict) else "")
        if cached[1]:
            return cached[1]
    return ""


def flag_value(flags, name):
    """`--model opusplan` (or `--model=opusplan`) out of a job's respawnFlags."""
    flags = [str(f) for f in flags] if isinstance(flags, list) else []
    for i, f in enumerate(flags):
        if f == name and i + 1 < len(flags):
            return flags[i + 1]
        if f.startswith(name + "="):
            return f[len(name) + 1:]
    return ""


def read_json(path):
    try:
        with open(path, "rb") as f:
            return json.loads(f.read())
    except (OSError, ValueError):
        return None


def mtime(path):
    try:
        return os.stat(path).st_mtime_ns
    except OSError:
        return 0


def proc_alive(pid, proc_start):
    """True when pid is running and is the same process the file was written by."""
    try:
        with open("/proc/%d/stat" % int(pid)) as f:
            stat = f.read()
    except (OSError, ValueError, TypeError):
        return False
    if not proc_start:
        return True
    # Field 22 (starttime) comes after the parenthesised comm, which may hold spaces.
    fields = stat[stat.rfind(")") + 2:].split()
    return len(fields) > 19 and fields[19] == str(proc_start)


MARKDOWN = re.compile(r"\*\*|__|`+|^#+\s*|^\s*[-*]\s+|\[([^\]]*)\]\([^)]*\)", re.M)


def plain(text):
    """Markdown down to something readable on one line."""
    return MARKDOWN.sub(lambda m: m.group(1) or "", str(text or ""))


def epoch(stamp):
    """ISO timestamp from a transcript record -> seconds, or 0."""
    try:
        return datetime.fromisoformat(str(stamp).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


def content_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and isinstance(b.get("text"), str))
    return ""


def short(text, limit):
    text = " ".join(str(text or "").split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def tool_detail(name, inp):
    """The call itself, under its description: the command, path or pattern."""
    if not isinstance(inp, dict):
        return ""
    home = lambda p: "~" + p[len(HOME):] if p.startswith(HOME) else p
    if name == "Bash":
        return short(inp.get("command", ""), 160)
    path = inp.get("file_path") or inp.get("notebook_path") or ""
    if path:
        return home(str(path))
    if name in ("Grep", "Glob"):
        where = inp.get("path") or ""
        return short(str(inp.get("pattern", "")) + (" in " + home(str(where)) if where else ""), 120)
    if name in ("WebFetch",):
        return short(inp.get("url", ""), 120)
    return ""


_git = {}


def github_url(gitdir):
    """https://github.com/<owner>/<repo> for a repository whose origin is on
    GitHub (ssh or https), else ""."""
    try:
        with open(os.path.join(gitdir, "config")) as f:
            config = f.read()
    except OSError:
        return ""
    section = re.search(r'^\[remote "origin"\](.*?)(?=^\[|\Z)', config, re.M | re.S)
    url = re.search(r"^\s*url\s*=\s*(\S+)", section.group(1), re.M) if section else None
    m = re.search(r"github\.com[:/]([^/\s]+/[^/\s]+?)(?:\.git)?/?$", url.group(1)) if url else None
    return "https://github.com/" + m.group(1) if m else ""


def git_info(path):
    """Branch, and the worktree when it's a linked one, for a working folder:
    {"branch", "repo", "worktree"} or None outside a repository."""
    d = os.path.abspath(path or "/")
    while True:
        dot = os.path.join(d, ".git")
        if os.path.isdir(dot):
            gitdir, linked = dot, False
            break
        if os.path.isfile(dot):
            try:
                with open(dot) as f:
                    line = f.read().strip()
            except OSError:
                return None
            if not line.startswith("gitdir:"):
                return None
            gitdir, linked = os.path.normpath(os.path.join(d, line[7:].strip())), True
            break
        if d == "/":
            return None
        d = os.path.dirname(d)
    head = os.path.join(gitdir, "HEAD")
    try:
        with open(head) as f:
            ref = f.read().strip()
    except OSError:
        return None
    common = gitdir
    if linked:
        try:
            with open(os.path.join(gitdir, "commondir")) as f:
                common = os.path.normpath(os.path.join(gitdir, f.read().strip()))
        except OSError:
            pass
    branch = ref[16:] if ref.startswith("ref: refs/heads/") else ref[:7]
    pushed = os.path.join(common, "refs", "remotes", "origin", branch)
    # A commit moves the branch's ref, not HEAD: watch both (and packed-refs);
    # a push or a new remote changes the GitHub link.
    tip = os.path.join(common, ref[5:]) if ref.startswith("ref: ") else head
    key = (d, ref, mtime(tip), mtime(os.path.join(common, "packed-refs")),
           mtime(os.path.join(common, "config")), mtime(pushed))
    if _git.get(d, (None,))[0] == key:
        return _git[d][1]
    repo = os.path.basename(os.path.dirname(common)) if linked else os.path.basename(d)
    info = {"branch": branch, "repo": repo, "worktree": os.path.basename(d) if linked else "",
            "commit": "", "commitAt": 0, "github": github_url(common)}
    # The branch itself once it's on GitHub, else the repo's front page.
    if info["github"] and ref.startswith("ref: refs/heads/") and os.path.isfile(pushed):
        info["github"] += "/tree/" + branch
    try:
        out = subprocess.run(["git", "-C", d, "log", "-1", "--format=%ct%x00%s"],
                             capture_output=True, text=True, timeout=2).stdout
        at, _, subject = out.strip().partition("\0")
        info["commit"], info["commitAt"] = short(subject, 120), int(at) * 1000
    except (OSError, subprocess.SubprocessError, ValueError):
        pass   # no commits yet, or no git: just the branch
    _git[d] = (key, info)
    return info


def describe_tool(name, inp):
    """A one-line, human version of a tool call: what the crab is doing."""
    if not isinstance(inp, dict):
        inp = {}
    desc = inp.get("description")
    base = lambda p: os.path.basename(str(p).rstrip("/")) or str(p)
    if name == "Bash":
        return desc or "Running " + short(inp.get("command", ""), 60)
    if name in ("Read", "NotebookRead"):
        return "Reading " + base(inp.get("file_path", inp.get("notebook_path", "")))
    if name in ("Edit", "MultiEdit", "NotebookEdit"):
        return "Editing " + base(inp.get("file_path", inp.get("notebook_path", "")))
    if name == "Write":
        return "Writing " + base(inp.get("file_path", ""))
    if name in ("Grep", "Glob"):
        return "Searching " + short(inp.get("pattern", ""), 50)
    if name in ("WebFetch",):
        return "Fetching " + short(inp.get("url", ""), 60)
    if name in ("WebSearch",):
        return "Searching the web: " + short(inp.get("query", ""), 50)
    if name in ("Agent", "Task"):
        return "Delegating: " + short(desc or inp.get("prompt", ""), 60)
    if name in ("TaskCreate", "TaskUpdate", "TodoWrite"):
        return "Planning tasks"
    if desc:
        return short(desc, 80)
    if name.startswith("mcp__"):
        parts = name.split("__")
        return "Using " + parts[-1].replace("_", " ") + " (" + parts[1].replace("claude_ai_", "") + ")"
    return "Using " + name


class Transcript:
    """Incrementally parsed transcript: only new bytes are read on each change."""

    def __init__(self, path):
        self.path = path
        self.offset = 0
        self.mtime = 0
        self.activity = ""
        self.activity_at = ""
        self.cwd = ""            # where the newest record ran (follows worktree switches)
        self.note = ""           # Claude's latest words this turn, between its tool calls
        self.note_at = 0.0
        self.phase_at = 0.0      # when the model's move or the tool call began
        self.prompt = ""
        self.reply = ""
        self.recap = ""          # the away summary Claude Code writes once a session sits idle
        self.final_text = ""   # the last assistant text in full, for notifications
        self.limit = ""          # the turn ended on the usage limit: Claude Code's line about it
        self.todos = []          # TodoWrite: replaced wholesale
        self.tasks = {}          # TaskCreate/TaskUpdate: id -> {text, status}
        self.task_order = []
        # The turn's last few tool calls, oldest first: what Claude did, for
        # the card's step list when it hasn't written a plan.
        self.actions = deque(maxlen=6)
        self.pending_creates = {}  # tool_use_id -> input, until the result names the id
        self.turn_tokens = {}    # message id -> output tokens, since the last prompt
        self.context = 0         # tokens the newest request sent: the context's size
        self.phase = "model"     # "tool" while a tool call is out, else the model's move
        self.model = ""          # the newest reply's model id
        self.effort = ""         # and the effort it ran at (low … max)
        self.model_setting = ""  # what `/model` last set: an alias ("opusplan") or a name ("Sonnet 5.5")
        self.mode = ""           # permission mode, from its records and the prompts
        self.last_at = 0.0       # epoch of the newest record
        # Work running beside the conversation. Launches are matched to their
        # results by tool_use_id; completions arrive as notifications naming the id.
        self.pending_children = {}  # tool_use_id -> ("agent" | "shell", description, at)
        self.children = {}          # agent / task id -> {"kind", "text", "at"}
        try:
            size = os.path.getsize(path)
        except OSError:
            size = 0
        # Huge transcripts: start near the end. Tasks created before that
        # window are lost, which only matters for very long sessions.
        if size > TRANSCRIPT_BOOTSTRAP_BYTES:
            self.offset = size - TRANSCRIPT_BOOTSTRAP_BYTES

    def update(self):
        m = mtime(self.path)
        if m == self.mtime:
            return False
        self.mtime = m
        try:
            with open(self.path, "rb") as f:
                f.seek(self.offset)
                chunk = f.read()
        except OSError:
            return False
        end = chunk.rfind(b"\n")
        if end < 0:
            return False
        self.offset += end + 1
        for line in chunk[: end + 1].splitlines():
            try:
                self.ingest(json.loads(line))
            except (ValueError, TypeError, AttributeError):
                continue
        return True

    def new_turn(self, text):
        self.prompt = short(text, 140)
        self.reply = self.final_text = self.note = self.limit = self.recap = ""
        self.turn_tokens = {}
        self.pending_children = {}   # a launch still unanswered by now was interrupted
        self.pending_creates = {}
        self.actions.clear()

    def ingest(self, rec):
        if not isinstance(rec, dict) or rec.get("isSidechain"):
            return
        kind = rec.get("type")
        msg = rec.get("message") or {}
        content = msg.get("content")
        if kind in ("user", "assistant"):
            self.last_at = epoch(rec.get("timestamp")) or self.last_at
            if rec.get("cwd"):
                self.cwd = str(rec["cwd"])
        if rec.get("permissionMode"):
            self.mode = str(rec["permissionMode"])
        if kind == "assistant" and msg.get("model") and not str(msg["model"]).startswith("<"):
            self.model = str(msg["model"])
            if rec.get("effort"):
                self.effort = str(rec["effort"])
        if kind == "user" and isinstance(content, str) and content.startswith("<local-command-stdout>"):
            m = MODEL_SET.match(content)
            if m:
                self.model_setting = "opusplan" if re.match(r"Opus Plan|Opus in plan mode", m.group(1)) else m.group(1)
            m = EFFORT_SET.match(content)
            if m:
                self.effort = m.group(1).lower()
        if kind == "system" and rec.get("subtype") == "away_summary":
            self.recap = short(re.sub(r"\s*\(disable recaps in /config\)\s*$", "", str(rec.get("content") or "")), 320)
        if kind == "system" and rec.get("subtype") == "compact_boundary":
            meta = rec.get("compactMetadata") or {}
            self.context = int(meta.get("postTokens") or 0)
        if kind in ("user", "queue-operation"):
            # A finished subagent or background shell announces itself with a
            # message naming its id, delivered (or still queued) to this session.
            text = content_text(rec.get("content") if kind == "queue-operation" else content)
            if "<task-id>" in text or "<agent-message" in text:
                for m in CHILD_DONE.finditer(text):
                    self.children.pop(m.group(1) or m.group(2), None)
        if kind == "user":
            self.phase = "model"
            self.phase_at = self.last_at
            # Skill bodies, reminders and the like are injected as meta user turns.
            human = not rec.get("isMeta")
            if human and isinstance(content, str) and not content.startswith("<"):
                self.new_turn(content)
            result = rec.get("toolUseResult")
            if isinstance(content, list) and self.actions:
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "tool_result":
                        for action in self.actions:
                            if action["id"] == block.get("tool_use_id"):
                                action["status"] = "failed" if block.get("is_error") else "done"
            if isinstance(content, list) and self.pending_children:
                for block in content:
                    if not (isinstance(block, dict) and block.get("type") == "tool_result"):
                        continue
                    launch = self.pending_children.pop(block.get("tool_use_id"), None)
                    if launch is None or not isinstance(result, dict):
                        continue
                    child_id = result.get("agentId") if result.get("status") == "async_launched" else result.get("backgroundTaskId")
                    if child_id:
                        self.children[str(child_id)] = {"kind": launch[0], "text": launch[1], "at": launch[2]}
            if isinstance(result, dict) and isinstance(result.get("task"), dict) and isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "tool_result":
                        inp = self.pending_creates.pop(block.get("tool_use_id"), None)
                        if inp is not None:
                            self.add_task(result["task"].get("id"), inp)
            if human and isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "text":
                        text = block.get("text", "")
                        if text and not text.startswith("<"):
                            self.new_turn(text)
        elif kind == "assistant" and isinstance(content, list):
            usage = msg.get("usage")
            if msg.get("id") and isinstance(usage, dict):
                # One API message is split across records that repeat its usage.
                out = int(usage.get("output_tokens") or 0)
                self.turn_tokens[msg["id"]] = max(out, self.turn_tokens.get(msg["id"], 0))
                self.context = sum(int(usage.get(k) or 0) for k in
                                   ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")) + out
            if rec.get("isApiErrorMessage"):
                text = content_text(content)
                if rec.get("error") == "rate_limit" or LIMIT_TEXT.search(text):
                    self.limit = limit_line(text)
            elif msg.get("id"):
                self.limit = ""   # a real reply since: it got going again
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "text" and block.get("text", "").strip():
                    self.final_text = plain(block["text"])[:4000]
                    self.reply = short(self.final_text, 220)
                    # Its first paragraph is what it's saying it'll do next.
                    self.note = short(self.final_text.strip().split("\n\n")[0], 200)
                    self.note_at = self.last_at
                elif block.get("type") == "tool_use":
                    name = block.get("name", "")
                    inp = block.get("input") or {}
                    self.activity = describe_tool(name, inp)
                    self.activity_at = rec.get("timestamp", "")
                    self.phase = "tool"
                    self.phase_at = self.last_at
                    if name not in PLAN_TOOLS:
                        self.actions.append({"id": block.get("id"), "text": short(self.activity, 80), "status": "running",
                                             "detail": tool_detail(name, inp), "at": int(self.last_at * 1000)})
                    if name in ("Agent", "Task"):
                        self.pending_children[block.get("id")] = ("agent", short(inp.get("description") or inp.get("prompt", ""), 70), self.last_at)
                    elif name == "Bash" and inp.get("run_in_background"):
                        self.pending_children[block.get("id")] = ("shell", short(inp.get("description") or inp.get("command", ""), 70), self.last_at)
                    if name == "TodoWrite" and isinstance(inp.get("todos"), list):
                        self.todos = [
                            {"text": t.get("activeForm") if t.get("status") == "in_progress" and t.get("activeForm") else t.get("content", ""),
                             "status": t.get("status", "pending")}
                            for t in inp["todos"] if isinstance(t, dict)
                        ]
                    elif name == "TaskCreate":
                        self.pending_creates[block.get("id")] = inp
                    elif name == "TaskUpdate":
                        self.update_task(inp)

    def add_task(self, tid, inp):
        if tid is None:
            return
        tid = str(tid)
        self.tasks[tid] = {"subject": inp.get("subject", ""), "active": inp.get("activeForm", ""), "status": "pending"}
        if tid not in self.task_order:
            self.task_order.append(tid)

    def update_task(self, inp):
        tid = str(inp.get("taskId", ""))
        task = self.tasks.get(tid)
        if task is None:
            return
        status = inp.get("status")
        if status == "deleted":
            self.tasks.pop(tid, None)
            self.task_order.remove(tid)
            return
        if status:
            task["status"] = status
        if inp.get("subject"):
            task["subject"] = inp["subject"]
        if inp.get("activeForm"):
            task["active"] = inp["activeForm"]

    def task_list(self):
        if self.task_order:
            out = []
            for tid in self.task_order:
                t = self.tasks[tid]
                text = t["active"] if t["status"] == "in_progress" and t["active"] else t["subject"]
                out.append({"text": short(text, 90), "status": t["status"]})
            return out
        return [{"text": short(t["text"], 90), "status": t["status"]} for t in self.todos]

    def tokens(self):
        return sum(self.turn_tokens.values())

    def action_list(self, idle=False):
        """The turn's last tool calls. Once it's over, one still marked running
        never got its result (interrupted): "stopped"."""
        return [{"text": a["text"], "detail": a.get("detail", ""), "at": a.get("at", 0),
                 "status": "stopped" if idle and a["status"] == "running" else a["status"]}
                for a in self.actions]

    def child_list(self, busy):
        """Subagents and background shells still running, oldest first."""
        now = time.time()
        agents_dir = os.path.join(self.path[: -len(".jsonl")], "subagents")
        out = []
        for cid, c in list(self.children.items()):
            if c["kind"] == "agent":
                seen = mtime(os.path.join(agents_dir, "agent-%s.jsonl" % cid)) / 1e9 or c["at"]
                stale = now - seen > AGENT_STALE_SEC
            else:
                stale = now - c["at"] > SHELL_STALE_SEC
            if stale:
                self.children.pop(cid)
            else:
                out.append(c)
        if busy:
            # A foreground subagent: launched, no result back yet.
            out += [{"kind": k, "text": t, "at": at} for k, t, at in self.pending_children.values() if k == "agent"]
        out.sort(key=lambda c: c["at"])
        return [{"kind": c["kind"], "text": c["text"]} for c in out]


def find_transcript(session_id, cwd, hint):
    if hint and os.path.isfile(hint):
        return hint
    if cwd:
        slug = "".join(c if c.isalnum() else "-" for c in cwd)
        candidate = os.path.join(PROJECTS_DIR, slug, session_id + ".jsonl")
        if os.path.isfile(candidate):
            return candidate
    try:
        for d in os.listdir(PROJECTS_DIR):
            candidate = os.path.join(PROJECTS_DIR, d, session_id + ".jsonl")
            if os.path.isfile(candidate):
                return candidate
    except OSError:
        pass
    return ""


# Background jobs end with a classified line ("result: …", "failed: …",
# "needs input: …"); interactive sessions sometimes do too.
# Claude Code's own line when a turn stops on the usage limit: "You've hit
# your limit · resets 3pm", or the older "Claude AI usage limit reached|<epoch>".
LIMIT_TEXT = re.compile(r"hit your (?:\w+ )*limit|usage limit reached|rate limit", re.I)


def limit_line(text):
    text = " ".join(str(text or "").split())
    m = re.match(r"^(.*usage limit reached)\|(\d{9,})$", text, re.I)
    if m:
        return m.group(1) + " · resets " + datetime.fromtimestamp(int(m.group(2))).strftime("%-I:%M %p").lower()
    return short(text, 120) or "Usage limit reached"


OUTCOME_LINE = re.compile(r"^\s*(result|failed|needs input):\s*(.+)$", re.I | re.M)


def first_sentence(text, limit=72):
    text = " ".join(str(text or "").split())
    m = re.match(r"(.+?[.!?])(?:\s|$)", text)
    sentence = m.group(1) if m else text
    if len(sentence) > limit:
        # Prefer ending on a clause boundary, which reads as a whole thought;
        # failing that, the last word that fits, with an ellipsis.
        window = sentence[: limit + 1]
        cuts = [window.rfind(sep) for sep in (", ", "; ", " — ", " – ", " (", ": ")]
        best = max(cuts)
        if best >= limit * 0.45:
            sentence = window[:best]
        else:
            cut = sentence[: limit - 1]
            if " " in cut:
                cut = cut[: cut.rfind(" ")]
            sentence = cut.rstrip(",;:—-– ") + "…"
    return sentence.rstrip(".")


def duration(sec):
    sec = int(max(0, sec))
    if sec < 60:
        return "%ds" % sec
    m, h = sec // 60, sec // 3600
    if h:
        return "%dh %dm" % (h, m % 60) if m % 60 else "%dh" % h
    return "%dm" % m


def job_result(job):
    out = (job or {}).get("output")
    if isinstance(out, str):
        try:
            out = json.loads(out)
        except ValueError:
            return out
    return out.get("result", "") if isinstance(out, dict) else ""


# Toast headings: what happened in two or three words, so it reads at a glance.
STATUS = {"done": "Done", "failed": "Failed", "input": "Needs input", "limited": "Out of usage"}
WAITING_STATUS = {"permission prompt": "Needs your OK", "sandbox request": "Needs your OK",
                  "worker request": "Needs your OK", "input needed": "Needs input",
                  "goal proposal": "Needs a decision"}


def lead(text, limit=140):
    """As many whole sentences as fit the island's toast line (it elides the
    rest); failing that, the first one cut at a clause."""
    text = " ".join(str(text or "").split())
    out = ""
    for m in re.finditer(r".+?[.!?](?:\s|$)|.+$", text):
        piece = m.group(0).strip()
        if out and len(out) + 1 + len(piece) > limit:
            break
        if not out and len(piece) > limit:
            return first_sentence(piece, limit)
        out = (out + " " + piece).strip()
    return out.rstrip(".")


def tokens_label(n):
    if not n:
        return ""
    return "%d tokens" % n if n < 1000 else "%.1fk tokens" % (n / 1000) if n < 10000 else "%dk tokens" % round(n / 1000)


def toast(kind, status, session, text, meta):
    """The island's notification (BarWidget draws it): the status and session
    up top, the point underneath, a little context on the right."""
    project = session["project"] if session["project"] != session["name"] else ""
    return {"kind": kind, "status": status, "id": session["id"], "name": short(session["name"], 40),
            "text": text, "meta": [m for m in meta + [project] if m]}


def compose(session, job, final_text, busy_for, tokens=0, limit=""):
    """(outcome, headline, toast) for a finished turn."""
    state = str((job or {}).get("state") or "").lower()
    headline = ""
    outcome = "done"
    if limit:
        outcome, headline = "limited", limit
    elif job and state not in ("", "working"):
        headline = job_result(job) or job.get("detail") or ""
        if "fail" in state or "error" in state:
            outcome = "failed"
        elif "input" in state or "block" in state or "wait" in state:
            outcome = "input"
    if not headline and final_text:
        lines = OUTCOME_LINE.findall(final_text)
        if lines:
            kind, headline = lines[-1]
            kind = kind.lower()
            outcome = "failed" if kind == "failed" else "input" if kind == "needs input" else outcome
        else:
            headline = final_text
    headline = " ".join(plain(headline).split())

    note = toast(outcome, STATUS[outcome], session,
                 lead(headline) if headline else "Finished in " + session["project"],
                 [duration(busy_for), tokens_label(tokens)])
    return outcome, headline, note


def compose_waiting(session, now_ms):
    """The toast for a session blocked on you: a permission prompt and the like."""
    reason = session["waitingFor"] or "input needed"
    into = duration((now_ms - session["turnStart"]) / 1000.0) + " into the turn" if session.get("turnStart") else ""
    return toast("waiting", WAITING_STATUS.get(reason, "Needs you"), session,
                 session["activity"] or reason[:1].upper() + reason[1:],
                 [reason if reason not in ("permission prompt", "input needed") else "", into])


def looking_at(session):
    """True when the session's terminal is the focused window, so a toast would
    only repeat what's on screen. A background job counts only when the agent
    view is showing that job (it titles itself after it)."""
    try:
        sys.path.insert(0, PLUGIN_DIR)
        import focus
    except ImportError:
        return False
    finally:
        sys.path.remove(PLUGIN_DIR)
    try:
        out = subprocess.run(["hyprctl", "activewindow", "-j"], capture_output=True, text=True, timeout=3).stdout
        active = json.loads(out)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return False
    if not isinstance(active, dict) or not active.get("address"):
        return False
    if session.get("jobId"):
        return session["name"] in (active.get("title") or "")
    windows = focus.clients()
    window = focus.window_for_process(int(session.get("pid") or 0), session.get("procStart"),
                                      {w.get("pid"): w for w in windows if w.get("pid")})
    return bool(window) and window.get("address") == active["address"]


def announce(note, session, previous):
    """The toast stamped for the snapshot, or the one before it when this one
    would only repeat what's on screen (or toasts are off)."""
    if not NOTIFY or looking_at(session):
        return previous
    note["at"] = int(time.time() * 1000)
    return note


def main():
    transcripts = {}   # session id -> Transcript
    previous = {}      # session id -> (status, since_ms)
    pending = {}       # session id -> {"deadline", "busy_for"}: finished, not yet announced
    latest = {}        # session id -> (session row, job, transcript) from this pass
    turn_start = {}    # session id -> ms the current turn began
    waits = {}         # session id -> when to announce its wait (0: announced)
    event = None       # the last finished turn, for the crab's moods
    note = None        # the last toast, for the island to show
    first_scan = True
    last_line = None

    while True:
        sessions = []
        seen = set()
        try:
            names = sorted(os.listdir(SESSIONS_DIR))
        except OSError:
            names = []
        for fname in names:
            if not fname.endswith(".json"):
                continue
            meta = read_json(os.path.join(SESSIONS_DIR, fname))
            if not isinstance(meta, dict) or not meta.get("sessionId"):
                continue
            if not proc_alive(meta.get("pid"), meta.get("procStart")):
                continue
            sid = meta["sessionId"]
            if sid in seen:
                continue
            seen.add(sid)

            job = None
            if meta.get("jobId"):
                job = read_json(os.path.join(JOBS_DIR, str(meta["jobId"]), "state.json"))
                if not isinstance(job, dict):
                    job = None

            tr = transcripts.get(sid)
            if tr is None:
                path = find_transcript(sid, meta.get("cwd", ""), job.get("linkScanPath") if job else "")
                if path:
                    tr = transcripts[sid] = Transcript(path)
            if tr:
                tr.update()
            elif meta.get("status") != "busy" and not job:
                # A process with no conversation yet has nothing to show; a
                # background job does, its live terminal (Chat / Code open it).
                continue

            status = str(meta.get("status") or "idle")
            waiting_for = str(meta.get("waitingFor") or "") if status == "waiting" else ""
            # Blocked on you mid-turn. A dialog you opened yourself reads as idle.
            waiting = status == "waiting" and waiting_for not in SELF_DIALOGS
            if status == "waiting" and not waiting:
                status = "idle"
            busy = status == "busy"
            since = meta.get("statusUpdatedAt") or meta.get("updatedAt") or 0
            prev = previous.get(sid)
            # The turn's clock runs from the prompt, through any waits on you.
            if status == "idle":
                turn_start.pop(sid, None)
            elif sid not in turn_start or (prev and prev[0] == "idle"):
                turn_start[sid] = int(since)

            activity = ""
            thinking = False
            if busy or waiting:
                if job and job.get("state") == "working" and job.get("detail"):
                    activity = job["detail"]
                elif tr and tr.activity:
                    activity = tr.activity
                else:
                    activity = "Thinking…"
                thinking = busy and bool(tr) and tr.phase == "model" and time.time() - tr.last_at > THINKING_AFTER_SEC
            elif job and job.get("state") not in (None, "", "working", "idle"):
                activity = str(job.get("state"))

            children = tr.child_list(busy) if tr else []
            queued = 0
            if job and isinstance(job.get("inFlight"), dict):
                queued = int(job["inFlight"].get("queued") or 0)

            cwd = meta.get("cwd") or ""
            sessions.append({
                "id": sid,
                "pid": meta.get("pid"),
                "procStart": str(meta.get("procStart") or ""),
                "jobId": str(meta.get("jobId") or ""),
                # An unnamed background job is "named" its id; the folder reads better.
                "name": short(next((n for n in (meta.get("name"), (job or {}).get("name"))
                                    if n and n != meta.get("jobId")), None)
                              or os.path.basename(cwd.rstrip("/")) or "Claude", 60),
                "project": os.path.basename(cwd.rstrip("/")) or cwd,
                "cwd": cwd,
                "kind": meta.get("kind") or "interactive",
                "status": status,
                "busy": busy,
                "waiting": waiting,
                "waitingFor": waiting_for,
                "thinking": thinking,
                "since": since,
                "turnStart": turn_start.get(sid, 0),
                "turnTokens": tr.tokens() if tr and status != "idle" else 0,
                "activity": short(activity, 90),
                "prompt": tr.prompt if tr else short((job or {}).get("intent", ""), 140),
                "reply": tr.reply if tr else "",
                "recap": tr.recap if tr else "",
                "tasks": tr.task_list() if tr else [],
                "actions": tr.action_list(status == "idle") if tr else [],
                "children": children,
                "queued": queued,
                "model": tr.model if tr else "",
                "effort": tr.effort if tr else "",
                "mode": tr.mode if tr else "",
                # The alias it runs under: opusplan swaps Opus (plan mode) for Sonnet.
                "modelSetting": (tr.model_setting if tr else "") or flag_value((job or {}).get("respawnFlags"), "--model")
                                or model_setting(cwd),
                "phase": tr.phase if tr and busy else "",
                "phaseAt": int(tr.phase_at * 1000) if tr and busy else 0,
                "note": tr.note if tr and (busy or waiting) else "",
                "noteAt": int(tr.note_at * 1000) if tr else 0,
                "workdir": (tr.cwd if tr else "") or cwd,
                "git": git_info((tr.cwd if tr else "") or cwd),
                "context": tr.context if tr else 0,
                "contextWindow": context_window(tr.model, tr.context) if tr else DEFAULT_CONTEXT_WINDOW,
            })
            row = sessions[-1]

            latest[sid] = (row, job, tr)
            if status != "idle":
                pending.pop(sid, None)   # picked straight back up: not finished after all
            elif not first_scan and prev and prev[0] != "idle":
                started = prev[2] or prev[1]
                busy_for = (int(since) - int(started)) / 1000.0 if started else NOTIFY_MIN_BUSY_SEC
                if busy_for >= NOTIFY_MIN_BUSY_SEC:
                    # A job's state.json can trail the session flipping idle.
                    pending[sid] = {"deadline": time.time() + (4.0 if job else 1.0), "busy_for": busy_for}

            # Blocked on you: say so once it has stuck for a moment (a prompt
            # answered at once needs no toast), and again only after it clears.
            if not waiting:
                waits.pop(sid, None)
            elif sid not in waits:
                waits[sid] = time.time() + (WAIT_GRACE_SEC if not first_scan else 0)
            previous[sid] = (status, since, row["turnStart"])

        for sid in list(pending):
            if sid not in latest:
                pending.pop(sid)
                continue
            row, job, tr = latest[sid]
            settled = bool(job) and str(job.get("state") or "") not in ("", "working") and bool(job_result(job) or job.get("detail"))
            if settled or time.time() >= pending[sid]["deadline"]:
                busy_for = pending.pop(sid)["busy_for"]
                outcome, headline, finished = compose(row, job, tr.final_text if tr else "", busy_for,
                                                      tr.tokens() if tr else 0, tr.limit if tr else "")
                event = {"id": sid, "kind": outcome, "at": int(time.time() * 1000), "name": row["name"],
                         "text": short(headline, 600), "busyFor": int(busy_for), "tokens": tr.tokens() if tr else 0}
                note = announce(finished, row, note)

        for sid, due in list(waits.items()):
            if due and sid in latest and time.time() >= due:
                waits[sid] = 0   # announced
                if not first_scan:
                    note = announce(compose_waiting(latest[sid][0], int(time.time() * 1000)), latest[sid][0], note)

        # Sessions that are gone, with or without a transcript.
        for table in (transcripts, previous, latest, turn_start, waits):
            for sid in [s for s in table if s not in seen]:
                del table[sid]

        # Waiting on you first, then busy, then most recently changed.
        sessions.sort(key=lambda s: (not s["waiting"], not s["busy"], -int(s["since"] or 0)))
        snapshot = {
            "sessions": sessions,
            "busy": sum(1 for s in sessions if s["busy"]),
            "waiting": sum(1 for s in sessions if s["waiting"]),
            "event": event,
            "toast": note,
        }
        line = json.dumps(snapshot, separators=(",", ":"), ensure_ascii=False)
        if line != last_line:
            last_line = line
            try:
                sys.stdout.write(line + "\n")
                sys.stdout.flush()
            except BrokenPipeError:
                return
        first_scan = False

        if "--once" in sys.argv:
            return
        time.sleep(POLL_SEC)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
