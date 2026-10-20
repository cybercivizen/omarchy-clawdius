#!/usr/bin/env bash
# + → Clone repo…: asks for a repository, clones it into BASE (the Code
# folder) and prints where, for the card to start Code in it.
#
#     clone.sh BASE SHOWN
#
# owner/repo and github.com links clone through the GitHub CLI once it's
# logged in, so private repos work. Not logged in, a public repo still clones
# with plain git; one that won't (private, or no such repo) asks to log in:
# `gh auth login` opens in a terminal, this waits for it, then tries again.
# A folder that's already there is offered as is. Prints nothing (exit 1)
# when cancelled or failed.

base=$1 shown=$2
title="Clone a repo for Claude"
[ -d "$base" ] || { base=$HOME; shown="~"; }

repo=$(zenity --entry --title="$title" --width=420 \
  --text="GitHub owner/repo, or any git URL (cloned into $shown):") || exit 1
repo=$(printf %s "$repo" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//")
[ -n "$repo" ] || exit 1

url=$repo
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && url=https://github.com/$repo
[[ $repo =~ ^(www\.)?github\.com/ ]] && url=https://$repo
# Any GitHub link (a web page's too: …/tree/main) → owner/repo.
gh_repo=""
if [[ $url =~ ^(https?://(www\.)?|ssh://git@|git@)github\.com[:/]([^/]+)/([^/?#]+) ]]; then
  gh_repo=${BASH_REMATCH[3]}/${BASH_REMATCH[4]%.git}
  url=https://github.com/$gh_repo.git
fi

name=$(basename -- "${url%/}" .git)
name=${name##*:}
[ -n "$name" ] && [ "$name" != . ] && [ "$name" != .. ] || {
  zenity --error --no-markup --title="$title" --text="Not a repository: $repo"; exit 1; }
dir=$base/$name

if [ -e "$dir" ]; then
  zenity --question --no-markup --title="$title" --ok-label="Open it" \
    --text="$shown/$name is already there. Start Claude in it?" || exit 1
  realpath -- "$dir"
  exit 0
fi

have_gh() { command -v gh >/dev/null; }
gh_in() { have_gh && gh auth status --hostname github.com >/dev/null 2>&1; }

log=$(mktemp)
trap 'rm -f "$log"' EXIT

# The clone, under a pulsing dialog; Cancel stops it and drops the folder.
clone() {
  if [ -n "$gh_repo" ] && gh_in; then
    gh repo clone "$gh_repo" "$dir" >"$log" 2>&1 &
  else
    GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" git clone -- "$url" "$dir" >"$log" 2>&1 &
  fi
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do echo "# Cloning $name into $shown…"; sleep 0.5; done \
    | zenity --progress --pulsate --auto-close --title="$title" --text="Cloning $name…" --width=420
  if [ "${PIPESTATUS[1]}" != 0 ]; then
    pkill -TERM -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; wait "$pid"
    rm -rf -- "$dir"
    exit 1
  fi
  wait "$pid"
}

fail() {
  zenity --error --no-markup --title="$title" --width=420 \
    --text="Couldn't clone $repo:

$(tail -n 6 "$log")"
  exit 1
}

if ! clone; then
  # Private (or no such repo): GitHub says the same either way. Log in, retry.
  [ -n "$gh_repo" ] && ! gh_in || fail
  have_gh || {
    zenity --error --no-markup --title="$title" --width=420 \
      --text="Couldn't clone $gh_repo: it's private, or doesn't exist. Install the GitHub CLI (gh) to log in to GitHub."
    exit 1
  }
  zenity --question --no-markup --title="$title" --ok-label="Log in" --width=420 \
    --text="Couldn't clone $gh_repo: it's private, or doesn't exist.

Log in to GitHub and try again?" || exit 1
  omarchy-launch-tui --app-id=org.omarchy.agent bash -c \
    'gh auth login --hostname github.com --git-protocol https --web || read -rp "Login failed. Press Enter to close."'
  for _ in $(seq 600); do gh_in && break; echo "# Log in to GitHub in the terminal…"; sleep 1; done \
    | zenity --progress --pulsate --auto-close --title="$title" --text="Waiting for GitHub login…" --width=420
  [ "${PIPESTATUS[1]}" = 0 ] && gh_in || exit 1
  clone || fail
fi

realpath -- "$dir"
