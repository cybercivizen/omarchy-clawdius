#!/usr/bin/env python3
"""Bring a Claude Code session's terminal to the front.

Run when the island's notification, or a session's row, is clicked:

    focus.py --pid PID [--proc-start N] [--name NAME] [--job JOB_ID]

1. Walk up from the session's process to the first ancestor that owns a
   Hyprland window: that's its terminal. Background jobs hang off whichever
   terminal started the jobs daemon, which is where the agent view lives.
2. Failing that, a window whose title carries the session name (the agent
   view titles itself after the session it's showing).
3. A background job with no window left: open it in a new terminal with
   `claude attach`.
"""

import argparse
import json
import subprocess


def clients():
    try:
        out = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=3).stdout
        return json.loads(out)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return []


def stat(pid):
    """(ppid, starttime) from /proc, or None once the process is gone."""
    try:
        with open("/proc/%d/stat" % pid) as f:
            text = f.read()
    except (OSError, ValueError):
        return None
    fields = text[text.rfind(")") + 2:].split()
    return int(fields[1]), fields[19]


def window_for_process(pid, proc_start, by_pid):
    first = stat(pid)
    if first is None or (proc_start and first[1] != str(proc_start)):
        return None   # gone, or the pid now belongs to something else
    seen = set()
    while pid > 1 and pid not in seen:
        seen.add(pid)
        if pid in by_pid:
            return by_pid[pid]
        info = stat(pid)
        if info is None:
            return None
        pid = info[0]
    return None


def window_for_name(name, windows):
    if not name:
        return None
    matches = [w for w in windows if name in (w.get("title") or "")]
    # The agent view first: it's the one that shows a background session.
    matches.sort(key=lambda w: w.get("class") != "org.omarchy.agent")
    return matches[0] if matches else None


def focus(window):
    addr = window["address"]
    ok = subprocess.run(["hyprctl", "dispatch", 'hl.dsp.focus({ window = "address:%s" })' % addr],
                        capture_output=True, text=True).returncode == 0
    if not ok:
        subprocess.run(["hyprctl", "dispatch", "focuswindow", "address:" + addr], capture_output=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pid", type=int, default=0)
    ap.add_argument("--proc-start", default="")
    ap.add_argument("--name", default="")
    ap.add_argument("--job", default="")
    ap.add_argument("--dry-run", action="store_true", help="print the choice instead of acting")
    args = ap.parse_args()

    windows = clients()
    by_pid = {w.get("pid"): w for w in windows if w.get("pid")}

    window = window_for_process(args.pid, args.proc_start, by_pid) if args.pid else None
    window = window or window_for_name(args.name, windows)
    if args.dry_run:
        print("focus %s (%s, %r)" % (window["address"], window.get("class"), window.get("title")) if window
              else "attach %s" % args.job if args.job else "nothing")
    elif window:
        focus(window)
    elif args.job:
        subprocess.Popen(["omarchy-launch-tui", "--app-id=org.omarchy.agent", "claude", "attach", args.job],
                         start_new_session=True)


if __name__ == "__main__":
    main()
