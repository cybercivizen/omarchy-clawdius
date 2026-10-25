#!/usr/bin/env python3
"""Answer Claude Code permission prompts from the crab card.

  approvals.py hook                      PermissionRequest hook (Claude Code runs it)
  approvals.py watch                     stream pending requests as JSON lines (the widget runs it)
  approvals.py answer ID allow|always|deny|terminal
  approvals.py answer ID answer '{"question": "label", ...}'   (AskUserQuestion)
  approvals.py install | uninstall       add / remove the hook in ~/.claude/settings.json

The hook drops the request into $XDG_RUNTIME_DIR/clawdius/requests and
waits for an answer file next to it. It never holds Claude up for nothing: if
no widget is watching it returns at once, and "terminal", a timeout or any
error all fall back to Claude's own prompt in the terminal.
"""
import json
import os
import shutil
import signal
import sys
import time
import uuid

RUNTIME = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "clawdius")
REQUESTS = os.path.join(RUNTIME, "requests")
WATCHER_PID = os.path.join(RUNTIME, "watcher.pid")
HOOK_LOG = os.path.join(RUNTIME, "hook.log")   # one line per hook call: which prompts reach the hook
SETTINGS = os.path.expanduser("~/.claude/settings.json")
WAIT_SEC = 300          # then the terminal prompt takes over
POLL_SEC = 0.15
EDIT_TOOLS = ("Edit", "MultiEdit", "Write", "NotebookEdit")
# Claude asking you to pick: the card shows the questions and their options,
# and the answer goes back as the tool's `answers` (question -> label).
QUESTION_TOOL = "AskUserQuestion"
# Claude asking to leave plan mode: the card shows the plan.
PLAN_TOOL = "ExitPlanMode"


def pid_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except (OSError, ValueError):
        return False


def read_json(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_atomic(path, data, indent=None):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=indent)
        if indent:
            f.write("\n")
    os.replace(tmp, path)


def clip(text, limit):
    text = str(text or "")
    return text if len(text) <= limit else text[: limit - 1] + "…"


def lines(text, sign, limit):
    out = [sign + l for l in str(text or "").splitlines()[:limit]]
    return out or [sign]


# ---------------------------------------------------------------- describing

def describe(tool, inp):
    """What the card shows: a verb, the one thing it acts on, and a diff."""
    diff = []
    if tool == "Bash":
        verb, detail = "Run a command", inp.get("command", "")
        if inp.get("description"):
            verb = clip(inp["description"], 70)
    elif tool in ("Edit", "MultiEdit"):
        verb, detail = "Edit a file", inp.get("file_path", "")
        edits = inp.get("edits") or [inp]
        for e in edits[:3]:
            diff += lines(e.get("old_string"), "-", 6) + lines(e.get("new_string"), "+", 6)
    elif tool == "Write":
        verb, detail = "Write a file", inp.get("file_path", "")
        diff = lines(inp.get("content"), "+", 10)
    elif tool == "NotebookEdit":
        verb, detail = "Edit a notebook", inp.get("notebook_path", "")
    elif tool in ("WebFetch", "WebSearch"):
        verb, detail = ("Fetch a page", inp.get("url", "")) if tool == "WebFetch" else ("Search the web", inp.get("query", ""))
    elif tool == QUESTION_TOOL:
        qs = inp.get("questions") or []
        verb = "Asks you " + ("a question" if len(qs) == 1 else "%d questions" % len(qs))
        detail = ""
    elif tool == PLAN_TOOL:
        verb, detail = "Wants to leave plan mode", ""
    elif tool.startswith("mcp__"):
        parts = tool.split("__")
        verb = "Use " + (parts[2] if len(parts) > 2 else tool) + " (" + (parts[1] if len(parts) > 1 else "mcp") + ")"
        detail = json.dumps(inp, ensure_ascii=False)
    else:
        verb, detail = "Use " + tool, json.dumps(inp, ensure_ascii=False)
    return clip(verb, 80), clip(detail, 600), [clip(l, 160) for l in diff[:16]]


def always_option(tool, suggestions):
    """The permission update behind "Always", and how to label it."""
    if suggestions:
        dest = suggestions[0].get("destination", "session")
        return suggestions, "For session" if dest == "session" else "Always"
    if tool in EDIT_TOOLS:
        return [{"type": "addRules", "rules": [{"toolName": tool}], "behavior": "allow",
                 "destination": "session"}], "For session"
    return None, ""


PLACES = {"session": "this session", "localSettings": "this project, just you",
          "projectSettings": "this project, shared with the repo", "userSettings": "everywhere",
          "cliArg": "this run"}


def always_rule(updates):
    """What "Always" adds, in one line: each rule, then where it's kept."""
    home = os.path.expanduser("~")
    parts = []
    for u in updates or []:
        kind = u.get("type")
        if kind in ("addRules", "replaceRules"):
            what = ", ".join(r.get("toolName", "") + ("(%s)" % r["ruleContent"] if r.get("ruleContent") else "")
                             for r in u.get("rules") or [])
        elif kind == "setMode":
            what = "mode " + str(u.get("mode", ""))
        elif kind == "addDirectories":
            what = "access " + ", ".join(d.replace(home, "~", 1) if d.startswith(home) else d
                                         for d in u.get("directories") or [])
        else:
            continue
        dest = u.get("destination") or "session"
        parts.append(what + " · " + PLACES.get(dest, dest))
    return clip("; ".join(parts), 200)


def questions(inp):
    """AskUserQuestion's questions, trimmed for the card."""
    out = []
    for q in (inp.get("questions") or [])[:4]:
        if not isinstance(q, dict):
            continue
        out.append({
            "question": str(q.get("question", "")),
            "header": clip(q.get("header", ""), 24),
            "multiSelect": bool(q.get("multiSelect")),
            "options": [{"label": str(o.get("label", "")), "description": clip(o.get("description", ""), 600)}
                        for o in (q.get("options") or []) if isinstance(o, dict)][:6],
        })
    return out


# --------------------------------------------------------------------- hook

def pending_tool_use(transcript, tool, inp):
    """The id of the tool call this prompt is about, from the transcript tail.

    Claude shows its own dialog alongside the hook, and answering there does
    not stop the hook. The call's tool_result landing in the transcript is how
    the hook learns it has been answered elsewhere.
    """
    try:
        with open(transcript, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - 262144))
            tail = f.read().decode("utf-8", "replace")
    except OSError:
        return None, 0
    found = None
    for line in tail.splitlines():
        if '"tool_use"' not in line:
            continue
        try:
            content = json.loads(line).get("message", {}).get("content")
        except ValueError:
            continue
        for block in content if isinstance(content, list) else []:
            if block.get("type") == "tool_use" and block.get("name") == tool and block.get("input") == inp:
                found = block.get("id")
    return found, size


def answered_elsewhere(transcript, tool_use_id, offset):
    try:
        if os.path.getsize(transcript) <= offset:
            return False
        with open(transcript, "rb") as f:
            f.seek(offset)
            fresh = f.read().decode("utf-8", "replace")
    except OSError:
        return False
    if tool_use_id:
        return '"tool_use_id":"%s"' % tool_use_id in fresh
    # No id to match on: any new turn means the dialog is gone.
    return '"tool_result"' in fresh or '"type":"user"' in fresh


def hook():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    tool = payload.get("tool_name", "")
    event = payload.get("hook_event_name") or "PermissionRequest"
    try:
        os.makedirs(RUNTIME, exist_ok=True)
        with open(HOOK_LOG, "a") as f:
            f.write("%s %s %s\n" % (time.strftime("%H:%M:%S"), event, tool))
        if os.path.getsize(HOOK_LOG) > 20000:
            os.replace(HOOK_LOG, HOOK_LOG + ".old")
    except OSError:
        pass
    # A PermissionRequest answer leaves the plan dialog open in the terminal, so
    # the plan card goes through PreToolUse; everything else stays PermissionRequest.
    if (event == "PreToolUse") != (tool == PLAN_TOOL):
        return
    pid = read_json(WATCHER_PID)
    if not isinstance(pid, int) or not pid_alive(pid):
        return   # nobody is watching: Claude asks in the terminal as usual

    inp = payload.get("tool_input") or {}
    transcript = payload.get("transcript_path") or ""
    tool_use_id, offset = pending_tool_use(transcript, tool, inp) if transcript else (None, 0)
    verb, detail, diff = describe(tool, inp)
    updates, always_label = always_option(tool, payload.get("permission_suggestions") or [])
    rid = uuid.uuid4().hex[:12]
    req_path = os.path.join(REQUESTS, rid + ".json")
    ans_path = os.path.join(REQUESTS, rid + ".answer")

    def cleanup(*_):
        for p in (req_path, ans_path):
            try:
                os.remove(p)
            except OSError:
                pass

    def bail(*_):
        cleanup()
        sys.exit(0)

    signal.signal(signal.SIGTERM, bail)
    signal.signal(signal.SIGHUP, bail)
    os.makedirs(REQUESTS, exist_ok=True)
    write_atomic(req_path, {
        "id": rid, "pid": os.getpid(), "at": int(time.time() * 1000),
        "sessionId": payload.get("session_id", ""), "cwd": payload.get("cwd", ""),
        "tool": tool, "verb": verb, "detail": detail, "diff": diff,
        "alwaysLabel": "" if tool in (QUESTION_TOOL, PLAN_TOOL) else always_label,
        "alwaysRule": "" if tool in (QUESTION_TOOL, PLAN_TOOL) else always_rule(updates),
        "questions": questions(inp) if tool == QUESTION_TOOL else [],
        "plan": clip(inp.get("plan", ""), 40000) if tool == PLAN_TOOL else "",
    })

    answer = None
    try:
        deadline = time.time() + WAIT_SEC
        while time.time() < deadline:
            answer = read_json(ans_path)
            if answer:
                break
            if not pid_alive(pid):     # the widget went away mid-wait
                break
            if transcript and answered_elsewhere(transcript, tool_use_id, offset):
                return                 # answered in the terminal: nothing to say
            time.sleep(POLL_SEC)
    finally:
        cleanup()

    choice = (answer or {}).get("choice")
    if event == "PreToolUse":
        if choice in ("allow", "always"):
            out = {"permissionDecision": "allow", "updatedInput": inp}
        elif choice == "deny":
            out = {"permissionDecision": "deny",
                   "permissionDecisionReason": "The user wants to keep planning. Ask them what to change."}
        else:
            return   # "terminal", timeout or no widget: the normal dialog
        print(json.dumps({"hookSpecificOutput": dict(out, hookEventName="PreToolUse")}))
        return
    if choice == "answer" and tool == QUESTION_TOOL and isinstance(answer.get("answers"), dict):
        decision = {"behavior": "allow", "updatedInput": dict(inp, answers=answer["answers"])}
    elif choice == "deny" and tool == PLAN_TOOL:
        decision = {"behavior": "deny", "message": "The user wants to keep planning. Ask them what to change."}
    elif choice in ("allow", "always"):
        decision = {"behavior": "allow"}
        if choice == "always" and updates:
            decision["updatedPermissions"] = updates
    elif choice == "deny":
        decision = {"behavior": "deny", "message": "The user denied this from the crab widget."}
    else:
        return   # "terminal", timeout or no widget: the normal prompt
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": decision}}))


# -------------------------------------------------------------------- watch

def watch():
    os.makedirs(REQUESTS, exist_ok=True)
    write_atomic(WATCHER_PID, os.getpid())
    last = None
    while True:
        pending = []
        for name in os.listdir(REQUESTS):
            if not name.endswith(".json"):
                continue
            req = read_json(os.path.join(REQUESTS, name))
            if not req:
                continue
            if not pid_alive(req.get("pid", 0)):   # answered in the terminal, or Claude gave up
                try:
                    os.remove(os.path.join(REQUESTS, name))
                except OSError:
                    pass
                continue
            if not os.path.exists(os.path.join(REQUESTS, req["id"] + ".answer")):
                pending.append(req)
        pending.sort(key=lambda r: r["at"])
        line = json.dumps({"requests": pending})
        if line != last:
            print(line, flush=True)
            last = line
        time.sleep(0.25)


def answer(rid, choice, answers=None):
    if choice not in ("allow", "always", "deny", "terminal", "answer") or not rid.isalnum():
        sys.exit("usage: approvals.py answer ID allow|always|deny|terminal|answer [ANSWERS_JSON]")
    data = {"choice": choice}
    if choice == "answer":
        try:
            data["answers"] = {str(k): str(v) for k, v in json.loads(answers or "{}").items()}
        except (ValueError, AttributeError):
            sys.exit("answer: ANSWERS_JSON must be an object of question -> label")
    if os.path.exists(os.path.join(REQUESTS, rid + ".json")):
        write_atomic(os.path.join(REQUESTS, rid + ".answer"), data)


# ------------------------------------------------------------------ install

def hook_command():
    return "python3 -I " + os.path.abspath(__file__) + " hook"


def is_ours(entry):
    return any("approvals.py hook" in h.get("command", "") for h in entry.get("hooks", []))


def install(remove=False):
    settings = read_json(SETTINGS, {})
    backup = SETTINGS + ".bak-" + time.strftime("%Y%m%d-%H%M%S")
    shutil.copy2(SETTINGS, backup)
    for event, matcher in (("PermissionRequest", None), ("PreToolUse", PLAN_TOOL)):
        entries = [e for e in settings.setdefault("hooks", {}).get(event, []) if not is_ours(e)]
        if not remove:
            # Our own wait ends at WAIT_SEC; Claude's timeout sits just above it.
            entry = {"hooks": [{"type": "command", "command": hook_command(), "timeout": WAIT_SEC + 30}]}
            if matcher:
                entry["matcher"] = matcher
            entries.append(entry)
        if entries:
            settings["hooks"][event] = entries
        else:
            settings["hooks"].pop(event, None)
    if not settings["hooks"]:
        settings.pop("hooks")
    write_atomic(SETTINGS, settings, indent=2)
    print(("Removed" if remove else "Installed") + " the crab approval hook. Backup: " + backup)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "hook":
        try:
            hook()
        except Exception:
            pass   # never break Claude: fall back to the terminal prompt
    elif cmd == "watch":
        watch()
    elif cmd == "answer" and len(sys.argv) in (4, 5):
        answer(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) == 5 else None)
    elif cmd in ("install", "uninstall"):
        install(remove=cmd == "uninstall")
    else:
        sys.exit(__doc__)
