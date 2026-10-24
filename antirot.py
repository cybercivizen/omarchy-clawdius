#!/usr/bin/env python3
"""Anti-rot: small exercises written by hand, from Exercism's tracks, a few a day.

  antirot.py today                  pick today's challenge if there isn't one (and refresh the info)
  antirot.py start                  copy today's challenge into its folder; prints the file to open
  antirot.py check                  run its tests; all passing counts the day
  antirot.py hint                   a nudge from Claude (Sonnet, no tools) towards the next step, never code
  antirot.py explain [again]        the task in plain words with worked examples; again for a plainer take
  antirot.py easier | skip          another one for today: a level down, or the same level
  antirot.py next                   chain another challenge once today's is passed
  antirot.py timebox N              minutes a challenge should take: 0 (off), 15, 25 or 45; passes
                                    over it, or many tries, come back as a re-do a week later
  antirot.py often N              challenges a day, 1-3 (the streak counts days the quota was met)
  antirot.py set LANG on|off        a language in or out of the rotation (on sets it up)
  antirot.py level LANG N           its level, 1-10 (Exercism's difficulty)
  antirot.py setup LANG             clone its track (TypeScript: install jest once)
  antirot.py add TRACK [NAME NEEDS TEST]
                                add an Exercism track; a preset (python, go, ruby, elixir)
                                needs only the name. NEEDS is a comma-separated list of
                                tools, TEST the shell command run in a rep's folder
                                (its exit code is the result unless the output is parsed)
  antirot.py remove TRACK           take an added track out again
  antirot.py editor NAME|default    the editor reps open in (default: Omarchy's)

Everything lands in $XDG_STATE_HOME/clawdius/antirot.json, which the widget
watches; nothing else writes it. Tracks are shallow clones of
github.com/exercism/<lang> under $XDG_DATA_HOME/clawdius/tracks, challenges go to
~/Work/antirot/<lang>/<slug> ($CLAWDIUS_ANTIROT_ROOT moves it). A rep is the
exercise's stub, tests and instructions, never its example solution, and
every test runs (Exercism skips all but the first).
"""
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import date, timedelta

STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "clawdius")
STATE = os.path.join(STATE_DIR, "antirot.json")
TRACKS = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "clawdius", "tracks")
REPS = os.path.expanduser(os.environ.get("CLAWDIUS_ANTIROT_ROOT") or "~/Work/antirot")
OLD_STATE = os.path.join(STATE_DIR, "gym.json")
OLD_REPS = os.path.expanduser("~/Work/gym")
START_LEVEL = 2
PASSES_TO_LEVEL_UP = 2
MAX_PER_DAY = 3
TIME_BOXES = (0, 15, 25, 45)
REDO_DAYS = 7
MAX_REDOS = 3
SKIP_DAYS = 30
TEST_TIMEOUT = 180
HINT_TIMEOUT = 90
HINT_CODE_BYTES = 8000
HINT_TEST_BYTES = 6000
MAX_HINTS = 6
EXPLAIN_PROMPT = ("You explain programming exercises to someone who finds the task itself confusing. Given the "
                  "task text and its tests, restate the problem in plain words, define any term it assumes the "
                  "reader knows, and give one or two small worked examples (input, then expected output) in fenced "
                  "code blocks, taking them from the tests where they fit. Use short paragraphs, no headings. "
                  "Never suggest an approach or algorithm for solving it and never write solution code. If a "
                  "previous explanation is included, it didn't land: be plainer and more concrete, with a "
                  "different example.")
# Each hint counts as this many checks towards a pass worth doing again.
HINT_WEIGHT = 2
HINT_PROMPT = ("You tutor someone who is relearning to code by hand. They are stuck on an Exercism exercise. "
               "Given the task, their current code and the last test output, give a hint of one or two sentences "
               "that points at the concept to think about, the failing case, or where the bug is. Never write code, "
               "never give the solution or the exact fix, never praise or preamble. If earlier hints are listed, "
               "go one step more concrete than the last, still without code.")
# The TypeScript reps share one jest install: these, at the versions the
# track's exercises ask for.
JEST_DEPS = ("@exercism/babel-preset-typescript", "@jest/globals", "@types/node", "babel-jest", "core-js",
             "expect", "jest", "typescript")

LANGS = {
    "typescript": {"name": "TypeScript", "needs": ["node", "npm"],
                   "install": "sudo pacman -S nodejs npm", "parser": "jest"},
    "rust": {"name": "Rust", "needs": ["cargo"],
             "install": "sudo pacman -S rustup && rustup default stable", "parser": "cargo"},
}

# Tracks Settings offers to add. "parser" reads the test output for a count;
# without one the command's exit code is the result.
PRESETS = {
    "python": {"name": "Python", "needs": ["python3"], "install": "sudo pacman -S python python-pytest",
               "test": "python3 -m pytest", "parser": "pytest"},
    "go": {"name": "Go", "needs": ["go"], "install": "sudo pacman -S go",
           "test": "go test -v ./...", "parser": "go"},
    "ruby": {"name": "Ruby", "needs": ["ruby"], "install": "sudo pacman -S ruby",
             "test": "ruby *_test.rb", "parser": "minitest"},
    "elixir": {"name": "Elixir", "needs": ["mix"], "install": "sudo pacman -S elixir",
               "test": "mix test", "parser": "mix"},
}

# Exercism tracks ship their tests with all but the first skipped: what turns
# that off, per track.
UNSKIPS = {
    "typescript": (r"\bx(it|test|describe)\(", r"\1("),
    "rust": (r"^[ \t]*#\[ignore\][ \t]*\n", ""),
    "ruby": (r"^[ \t]*skip\b.*\n", ""),
    "elixir": (r"^[ \t]*@tag :pending[ \t]*\n", ""),
}


def today_str():
    return date.today().isoformat()


def track_dir(lang):
    return os.path.join(TRACKS, lang)


def read_json(path, fallback):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return fallback


def migrate():
    """Daily reps kept its state and folder under gym: move them over once."""
    if not os.path.exists(STATE) and os.path.exists(OLD_STATE):
        os.replace(OLD_STATE, STATE)
    if not os.path.exists(REPS) and os.path.isdir(OLD_REPS) and "CLAWDIUS_ANTIROT_ROOT" not in os.environ:
        shutil.move(OLD_REPS, REPS)
        state = read_json(STATE, {})
        t = state.get("today")
        if t:
            for key in ("dir", "file", "docs"):
                if t.get(key, "").startswith(OLD_REPS):
                    t[key] = REPS + t[key][len(OLD_REPS):]
            with open(STATE, "w") as f:
                json.dump(state, f, indent=1)


def load():
    migrate()
    state = read_json(STATE, {})
    state.setdefault("custom", {})
    LANGS.update(state["custom"])
    state.setdefault("langs", {})
    state.setdefault("today", None)
    state.setdefault("done", [])
    state.setdefault("skipped", {})
    state.setdefault("streak", {"count": 0, "last": ""})
    state.setdefault("editor", "")
    state.setdefault("perDay", 1)
    state.setdefault("timeBox", 0)
    state.setdefault("redo", {})
    # A language that's gone (JavaScript became TypeScript) can't be worked on.
    if state.get("today") and state["today"].get("lang") not in LANGS:
        state["today"] = None
    for lang in [l for l in state["langs"] if l not in LANGS]:
        del state["langs"][lang]
    for lang in LANGS:
        state["langs"].setdefault(lang, {"on": False, "level": START_LEVEL, "passes": 0})
    return state


def info(lang):
    missing = [tool for tool in LANGS[lang]["needs"] if not shutil.which(tool)]
    cloned = os.path.isfile(os.path.join(track_dir(lang), "config.json"))
    installed = lang != "typescript" or os.path.isdir(os.path.join(REPS, "typescript", "node_modules"))
    return {"name": LANGS[lang]["name"], "missing": missing, "install": LANGS[lang]["install"],
            "setUp": cloned and installed, "ready": not missing and cloned and installed,
            "custom": lang not in ("typescript", "rust")}


def save(state):
    # What the widget shows but can't work out itself, refreshed on every save.
    state["info"] = {lang: info(lang) for lang in LANGS}
    state["presets"] = {k: v["name"] for k, v in PRESETS.items() if k not in LANGS}
    last = state["streak"].get("last", "")
    alive = last in (today_str(), (date.today() - timedelta(days=1)).isoformat())
    state["streakNow"] = state["streak"].get("count", 0) if alive else 0
    state["reps"] = REPS
    state["doneToday"] = done_today(state)
    state["passesToLevel"] = PASSES_TO_LEVEL_UP
    # Median solve time of the last five and of the five before, per language.
    by_lang = {}
    for l in LANGS:
        times = solve_times(state, l)
        last, before = times[-5:], times[-10:-5]
        by_lang[l] = {"median": median(last) if len(last) >= 3 else None,
                      "before": median(before) if len(before) >= 3 else None}
    state["stats"] = {"total": len(state["done"]), "byLang": by_lang,
                      "redos": sum(1 for v in state["redo"].values() if v["due"] <= today_str()),
                      "recent": [dict(d, name=d.get("name") or d["slug"]) for d in state["done"][-20:][::-1]]}
    os.makedirs(STATE_DIR, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=STATE_DIR, prefix=".antirot-")
    with os.fdopen(fd, "w") as f:
        json.dump(state, f, indent=1)
    os.replace(tmp, STATE)


def catalogue(lang):
    config = read_json(os.path.join(track_dir(lang), "config.json"), {})
    out = []
    for e in config.get("exercises", {}).get("practice", []):
        if e.get("status") == "deprecated" or e.get("slug") == "hello-world":
            continue
        if os.path.isdir(os.path.join(track_dir(lang), "exercises", "practice", e["slug"])):
            out.append(e)
    return out


def exercise_meta(lang, slug):
    return read_json(os.path.join(track_dir(lang), "exercises", "practice", slug, ".meta", "config.json"), {})


def rotation(state):
    return sorted(l for l in LANGS if state["langs"][l]["on"] and info(l)["ready"])


def done_today(state):
    return sum(1 for d in state["done"] if d["date"] == today_str())


def due_redo(state, langs, lang=None):
    """The oldest re-do due today (of lang, when one's asked for) whose
    language is in the rotation, as "lang/slug"; None when there isn't one."""
    due = [(v["due"], k) for k, v in state["redo"].items()
           if v["due"] <= today_str() and k.split("/", 1)[0] in langs and (lang not in langs or k.startswith(lang + "/"))]
    return min(due)[1] if due else None


def median(values):
    values = sorted(values)
    n = len(values)
    return None if not n else values[n // 2] if n % 2 else (values[n // 2 - 1] + values[n // 2]) / 2


def solve_times(state, lang):
    return [d["secs"] for d in state["done"] if d["lang"] == lang and d.get("secs")]


def shaky(state, lang, secs, checks):
    """A pass worth doing again: over the time box, or (without one) well past
    the language's usual time, or it took many tries."""
    box = state["timeBox"] * 60
    times = solve_times(state, lang)
    slow = secs > box if box else len(times) >= 3 and secs > 1.5 * median(times)
    return slow or checks >= 4


def pick(state, lang=None):
    """Today's rep: the language rotates by day, the exercise is the unsolved,
    not lately skipped one nearest the language's level. The same day always
    picks the same."""
    langs = rotation(state)
    if not langs:
        state["today"] = None
        return
    # A re-do that's due comes before anything new.
    redo = due_redo(state, langs, lang)
    e = None
    if redo:
        lang = redo.split("/", 1)[0]
        e = next((x for x in catalogue(lang) if lang + "/" + x["slug"] == redo), None)
        if not e:
            del state["redo"][redo]
            return pick(state, lang)
    elif lang not in langs:
        lang = langs[(date.today().toordinal() * MAX_PER_DAY + done_today(state)) % len(langs)]
    level = state["langs"][lang]["level"]
    if not e:
        done = {d["slug"] for d in state["done"] if d["lang"] == lang}
        cutoff = (date.today() - timedelta(days=SKIP_DAYS)).isoformat()
        skipped = {k for k, day in state["skipped"].items() if day >= cutoff}
        exercises = catalogue(lang)
        fresh = [e for e in exercises if e["slug"] not in done and lang + "/" + e["slug"] not in skipped]
        pool = fresh or [e for e in exercises if lang + "/" + e["slug"] not in skipped] or exercises
        if not pool:
            state["today"] = None
            return
        salt = today_str() + str(len(state["skipped"])) + str(done_today(state))

        def rank(e):
            tie = hashlib.md5((salt + e["slug"]).encode()).hexdigest()
            return (abs(e.get("difficulty", 1) - level), tie)

        e = min(pool, key=rank)
    meta = exercise_meta(lang, e["slug"])
    # The track's own solution, for Claude's review to compare against.
    example = meta.get("files", {}).get("example", [])
    example = os.path.join(track_dir(lang), "exercises", "practice", e["slug"], example[0]) if example else ""
    state["today"] = {"date": today_str(), "lang": lang, "slug": e["slug"], "name": e.get("name", e["slug"]),
                      "blurb": meta.get("blurb", ""), "difficulty": e.get("difficulty", 1), "level": level,
                      "example": example, "dir": "", "file": "", "startedAt": 0, "passedAt": 0, "check": None,
                      "checks": 0, "redo": bool(redo), "round": state["redo"][redo]["round"] if redo else 0}


def ensure_today(state):
    t = state["today"]
    stale = not t or t.get("date") != today_str()
    # Its language taken out of the rotation before it was started.
    dropped = t and not t.get("startedAt") and t.get("lang") not in rotation(state)
    if stale or dropped:
        pick(state)


def unskip(lang, path):
    with open(path) as f:
        text = f.read()
    if lang in UNSKIPS:
        text = re.sub(UNSKIPS[lang][0], UNSKIPS[lang][1], text, flags=re.M)
    with open(path, "w") as f:
        f.write(text)


def start(state):
    t = state["today"]
    if not t:
        sys.stderr.write("no challenge today: turn a language on in Settings\n")
        return 1
    lang, slug = t["lang"], t["slug"]
    # A re-do starts from a blank stub beside the first attempt.
    dest = os.path.join(REPS, lang, slug + (".redo%d" % t["round"] if t.get("redo") else ""))
    files =exercise_meta(lang, slug).get("files", {})
    if not os.path.isdir(dest):
        # A rep started on an earlier day keeps what was written in it.
        src = os.path.join(track_dir(lang), "exercises", "practice", slug)
        shutil.copytree(src, dest, ignore=shutil.ignore_patterns(".meta"))
        for test in files.get("test", []):
            unskip(lang, os.path.join(dest, test))
    solution = [f for f in files.get("solution", []) if not f.endswith(".toml")]
    docs = os.path.join(dest, ".docs", "instructions.md")
    t["dir"] = dest
    t["docs"] = docs if os.path.isfile(docs) else ""
    t["file"] = os.path.join(dest, solution[0]) if solution else dest
    t["startedAt"] = t.get("startedAt") or int(time.time() * 1000)
    save(state)
    print(t["file"])
    print(t["docs"])
    return 0


ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def tail(text, n=12):
    lines = [ANSI.sub("", l).rstrip() for l in text.splitlines()]
    return "\n".join([l for l in lines if l.strip()][-n:])


def run_tests(lang, folder):
    """(passed, total, output) for the rep in folder."""
    env = dict(os.environ, FORCE_COLOR="0", NO_COLOR="1", CARGO_TERM_COLOR="never")
    parser = LANGS[lang].get("parser")
    if parser == "jest":
        jest = os.path.join(REPS, lang, "node_modules", ".bin", "jest")
        with tempfile.NamedTemporaryFile(suffix=".json") as report:
            p = subprocess.run([jest, "--ci", "--json", "--outputFile", report.name], cwd=folder, env=env,
                               capture_output=True, text=True, timeout=TEST_TIMEOUT)
            result = read_json(report.name, {})
        out = re.sub(r"^Test results written to.*$", "", p.stdout + p.stderr, flags=re.M)
        return result.get("numPassedTests", 0), result.get("numTotalTests", 0), out
    command = "cargo test" if parser == "cargo" else LANGS[lang]["test"]
    p = subprocess.run(command, shell=True, cwd=folder, env=env, capture_output=True, text=True, timeout=TEST_TIMEOUT)
    out = p.stdout + p.stderr
    passed = failed = 0
    if parser == "cargo":
        for m in re.finditer(r"test result: \w+\. (\d+) passed; (\d+) failed", out):
            passed += int(m.group(1))
            failed += int(m.group(2))
    elif parser == "pytest":
        passed = sum(int(n) for n in re.findall(r"(\d+) passed", out))
        failed = sum(int(n) for n in re.findall(r"(\d+) (?:failed|error)", out))
    elif parser == "go":
        passed = len(re.findall(r"^\s*--- PASS", out, flags=re.M))
        failed = len(re.findall(r"^\s*--- FAIL", out, flags=re.M))
    elif parser == "minitest":
        m = re.search(r"(\d+) runs, \d+ assertions, (\d+) failures, (\d+) errors", out)
        if m:
            failed = int(m.group(2)) + int(m.group(3))
            passed = int(m.group(1)) - failed
    elif parser == "mix":
        m = re.search(r"(\d+) tests?, (\d+) failures?", out)
        if m:
            failed = int(m.group(2))
            passed = int(m.group(1)) - failed
    if passed + failed == 0:
        # Nothing to count: the whole run is one test (a build error is a fail).
        passed, failed = (1, 0) if p.returncode == 0 else (0, 1)
    return passed, passed + failed, out


def check(state):
    t = state["today"]
    if not t or not t.get("dir"):
        sys.stderr.write("start today's challenge first\n")
        return 1
    try:
        passed, total, out = run_tests(t["lang"], t["dir"])
    except subprocess.TimeoutExpired:
        passed, total, out = 0, 0, "The tests took over %ds and were stopped." % TEST_TIMEOUT
    t["check"] = {"passed": passed, "total": total, "at": int(time.time() * 1000), "tail": tail(out)}
    t["checks"] = t.get("checks", 0) + 1
    if total and passed == total and not t.get("passedAt"):
        t["passedAt"] = t["check"]["at"]
        # Wall clock, Start to the passing Check.
        secs = max(1, (t["passedAt"] - t["startedAt"]) // 1000) if t.get("startedAt") else 0
        key = t["lang"] + "/" + t["slug"]
        if secs and shaky(state, t["lang"], secs, t["checks"] + HINT_WEIGHT * t.get("hintCount", 0)):
            n = t.get("round", 0) + 1
            if n <= MAX_REDOS:
                state["redo"][key] = {"due": (date.today() + timedelta(days=REDO_DAYS)).isoformat(), "round": n}
            else:
                state["redo"].pop(key, None)
        else:
            state["redo"].pop(key, None)
        state["done"].append({"date": today_str(), "lang": t["lang"], "slug": t["slug"], "name": t.get("name", ""),
                              "secs": secs, "checks": t["checks"], "level": t.get("level", 0), "redo": bool(t.get("redo"))})
        t["secs"] = secs
        lang = state["langs"][t["lang"]]
        # A re-do doesn't count toward the next level.
        if not t.get("redo"):
            lang["passes"] = lang.get("passes", 0) + 1
        if lang["passes"] >= PASSES_TO_LEVEL_UP and lang["level"] < 10:
            lang["level"] += 1
            lang["passes"] = 0
        streak = state["streak"]
        if done_today(state) >= state["perDay"] and streak.get("last") != today_str():
            yesterday = (date.today() - timedelta(days=1)).isoformat()
            streak["count"] = streak.get("count", 0) + 1 if streak.get("last") == yesterday else 1
            streak["last"] = today_str()
    save(state)
    return 0


def read_text(path, limit=HINT_CODE_BYTES):
    try:
        with open(path, errors="replace") as f:
            return f.read(limit)
    except OSError:
        return ""


def ask(kind, again=False):
    """Ask Claude about today's rep: a `hint`, or an `explain`ation of the task
    (`again` for a plainer one). The slow call runs outside the lock, so Check
    and Skip aren't held up; the answer is kept only if it's still the same rep."""
    with open(os.path.join(STATE_DIR, "antirot.lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        t = load()["today"]
        if not t or not t.get("dir") or t.get("passedAt"):
            sys.stderr.write("start today's challenge first\n")
            return 1
        key, lang = t["lang"] + "/" + t["slug"], t["lang"]
        material = ["# Task\n" + read_text(t.get("docs", ""))]
        if kind == "explain":
            tests = exercise_meta(lang, t["slug"]).get("files", {}).get("test", [])
            material.append("# Its tests\n" + "\n".join(read_text(os.path.join(t["dir"], f), HINT_TEST_BYTES) for f in tests))
            if again and t.get("explain"):
                material.append("# Your last explanation, which didn't land\n" + t["explain"])
        else:
            material += ["# Their code (%s)\n%s" % (lang, read_text(t.get("file", ""))),
                         "# Last test output\n" + (t.get("check") or {}).get("tail", "(not run yet)")]
            if t.get("hints"):
                material.append("# Earlier hints, oldest first\n" + "\n".join("- " + h for h in t["hints"]))
    prompt = EXPLAIN_PROMPT if kind == "explain" else HINT_PROMPT
    try:
        with tempfile.TemporaryDirectory() as cwd:
            p = subprocess.run(["claude", "-p", "--model", "sonnet", "--tools", "", "--no-session-persistence",
                                "--system-prompt", prompt], input="\n\n".join(material), cwd=cwd,
                               capture_output=True, text=True, timeout=HINT_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired) as e:
        sys.stderr.write("no %s: %s\n" % (kind, e if isinstance(e, OSError) else "Claude took over %ds" % HINT_TIMEOUT))
        return 1
    text = p.stdout.strip()
    if p.returncode != 0 or not text:
        sys.stderr.write("no %s: %s\n" % (kind, tail(p.stderr, 1) or "empty answer"))
        return 1
    with open(os.path.join(STATE_DIR, "antirot.lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = load()
        t = state["today"]
        if t and t["lang"] + "/" + t["slug"] == key:
            if kind == "explain":
                t["explain"] = text
            else:
                t["hints"] = (t.get("hints", []) + [text])[-MAX_HINTS:]
                t["hintCount"] = t.get("hintCount", 0) + 1
            save(state)
    return 0


def setup(lang):
    track = track_dir(lang)
    if not os.path.isfile(os.path.join(track, "config.json")):
        os.makedirs(TRACKS, exist_ok=True)
        shutil.rmtree(track, ignore_errors=True)
        p = subprocess.run(["git", "clone", "-q", "--depth", "1", "https://github.com/exercism/" + lang, track],
                           capture_output=True, text=True)
        if p.returncode != 0:
            sys.stderr.write("couldn't get the %s track: %s\n" % (LANGS[lang]["name"], p.stderr.strip()))
            return 1
    if lang == "typescript":
        root = os.path.join(REPS, "typescript")
        if not os.path.isdir(os.path.join(root, "node_modules")):
            sample = read_json(os.path.join(track, "exercises", "practice", "two-fer", "package.json"), {})
            deps = {k: v for k, v in sample.get("devDependencies", {}).items() if k in JEST_DEPS}
            os.makedirs(root, exist_ok=True)
            with open(os.path.join(root, "package.json"), "w") as f:
                json.dump({"name": "clawdius-reps", "private": True, "devDependencies": deps}, f, indent=2)
            p = subprocess.run(["npm", "install", "--no-audit", "--no-fund", "--loglevel=error"], cwd=root,
                               capture_output=True, text=True)
            if p.returncode != 0:
                shutil.rmtree(os.path.join(root, "node_modules"), ignore_errors=True)
                sys.stderr.write("npm install failed: %s\n" % tail(p.stderr, 3))
                return 1
    return 0


def add(state, track, rest):
    """Register an Exercism track and turn it on. 2 for a bad call, 1 if the
    track can't be fetched (then it isn't kept)."""
    if track in PRESETS and not rest:
        entry = dict(PRESETS[track])
    elif len(rest) == 3 and rest[2].strip():
        entry = {"name": rest[0], "needs": [t for t in rest[1].split(",") if t.strip()],
                 "install": "install " + (rest[1] or "its toolchain"), "test": rest[2]}
    else:
        sys.stderr.write(__doc__)
        return 2
    state["custom"][track] = entry
    LANGS[track] = entry
    state["langs"][track] = {"on": True, "level": START_LEVEL, "passes": 0}
    code = 0 if info(track)["missing"] else setup(track)
    if code:
        del state["custom"][track], state["langs"][track], LANGS[track]
        return code
    ensure_today(state)
    return 0


def main(args):
    if not args:
        sys.stderr.write(__doc__)
        return 2
    cmd = args[0]
    lang = args[1] if len(args) > 1 else ""
    os.makedirs(STATE_DIR, exist_ok=True)
    if cmd in ("hint", "explain"):
        return ask(cmd, args[1:] == ["again"])
    with open(os.path.join(STATE_DIR, "antirot.lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = load()
        code = 0
        if cmd in ("set", "level", "setup", "remove") and lang not in LANGS:
            sys.stderr.write("unknown language %r (%s)\n" % (lang, ", ".join(LANGS)))
            return 2
        if cmd == "today":
            ensure_today(state)
        elif cmd == "start":
            ensure_today(state)
            return start(state)
        elif cmd == "check":
            return check(state)
        elif cmd in ("easier", "skip"):
            t = state["today"]
            if t and t.get("redo"):
                # A re-do is put off a day, not marked skipped or made easier.
                key = t["lang"] + "/" + t["slug"]
                state["redo"][key]["due"] = (date.today() + timedelta(days=1)).isoformat()
                pick(state, t["lang"])
            elif t:
                if cmd == "easier":
                    l = state["langs"][t["lang"]]
                    l["level"] = max(1, l["level"] - 1)
                    l["passes"] = 0
                else:
                    state["skipped"][t["lang"] + "/" + t["slug"]] = today_str()
                pick(state, t["lang"])
        elif cmd == "next":
            t = state["today"]
            if t and t.get("passedAt"):
                # The pass moved the language and the tie-break on.
                pick(state)
        elif cmd == "timebox" and len(args) == 2 and lang.isdigit() and int(lang) in TIME_BOXES:
            state["timeBox"] = int(lang)
        elif cmd == "often" and len(args) == 2 and lang.isdigit():
            state["perDay"] = max(1, min(MAX_PER_DAY, int(lang)))
        elif cmd == "set" and len(args) == 3 and args[2] in ("on", "off"):
            state["langs"][lang]["on"] = args[2] == "on"
            if args[2] == "on" and not info(lang)["missing"]:
                code = setup(lang)
            ensure_today(state)
        elif cmd == "level" and len(args) == 3 and args[2].isdigit():
            state["langs"][lang]["level"] = max(1, min(10, int(args[2])))
            state["langs"][lang]["passes"] = 0
            t = state["today"]
            if t and t["lang"] == lang and not t.get("startedAt"):
                pick(state, lang)
        elif cmd == "editor" and len(args) == 2 and (lang == "default" or re.fullmatch(r"[\w.+-]+", lang)):
            state["editor"] = "" if lang == "default" else lang
        elif cmd == "add" and re.fullmatch(r"[a-z0-9][a-z0-9-]*", lang) and lang not in LANGS:
            code = add(state, lang, args[2:])
            if code == 2:
                return 2
        elif cmd == "remove" and lang in state["custom"]:
            del state["custom"][lang]
            del LANGS[lang]
            state["langs"].pop(lang, None)
            ensure_today(state)
        elif cmd == "setup":
            code = setup(lang)
            ensure_today(state)
        else:
            sys.stderr.write(__doc__)
            return 2
        save(state)
        return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
