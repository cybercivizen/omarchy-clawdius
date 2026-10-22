# To do

Suggestions for the island, kept in order of when they came in. Tick them off as
they land; add new ones at the bottom. "Not hand-tested" means it loads and
renders, but nobody has clicked or typed through it yet.

## Summoned island (Super+Alt+C)

- [x] Opening it with the shortcut glitches for a split second as it appears.
      (The popup window resized ~0.4s in and Hyprland showed one squashed
      frame; the window now keeps its size and only the island morphs.
      Checked with a 60fps recording.)
- [x] Peek crab sits at the left of the island, not the right.
- [x] The peek crab's two eyes aren't identical. (Fractional pixel size; every
      crab now snaps to whole pixels.)
- [x] The new-chat input behaves like a real input: I-beam cursor over it, text
      can be selected with the mouse. (Not hand-tested.)

## Header and home

- [x] A chat icon next to the home icon, opening the new chat view.
- [x] Replace the big Code / Chat / Web tiles in the middle with a "New chat"
      button that opens the new chat view. (Home's idle card; the + menu
      keeps its tiles.)
- [x] The new chat view remembers the mode used last time (Chat or Code).
- [x] When the island opens by mouse hover, a small hint that you can start
      typing (the shortcut). (Later taken out again, both the new chat and
      the search keys.)
- [x] Remove "Pick up again", or replace it with something more useful.
      (Removed; earlier sessions are under Sessions → Recent.)

## Sessions

- [x] A distinct look for a session that hit its usage limit, instead of the
      normal "done" effect. (Not seen on a real limit yet.)
- [x] Answer prompts that need a choice from the user directly in the popup.
      (AskUserQuestion and plan approval, through the approval hook. Not
      tried in a real session yet.)

## Search / launcher

- [x] A search icon in the header that expands into a search bar; the island
      gets shorter and shows a row of suggested apps from recent use.
- [x] Typing searches installed apps.
- [x] `/` then space turns into a terminal chip; typing a command and Enter
      runs it in a terminal. (Not hand-tested.)
- [x] `/g` then space turns into a Google chip; Enter opens a Google search in
      the default browser. (Not hand-tested.)
- [x] Backspace on an empty chip removes it and leaves `/` or `/g` typed with
      the cursor after it, back to app search. (Not hand-tested.)
- [x] Alt+Space opens the island straight into the search view.
- [x] Arithmetic straight from the search bar: a sum gets a row with its
      result above the apps; Enter copies it. (`Calc.js`. Seen on screen;
      Enter copying not hand-tested.)
- [x] When no app matches, offer a Google search for what's typed instead
      of the "No apps match" line. (Seen on screen; Enter not hand-tested.)
- [x] More recent tabs than fit beside the apps: up to five, the ones past
      the edge faded, a › arrow to page to them and a ‹ that comes up to
      page back. (`searchTabs <1|-1>` over IPC. Paging seen on screen both
      ways; clicking the arrows and the wheel not hand-tested.)

## Bar

- [x] Make the hover area at the top of the screen wider, so the island is
      easy to trigger. (560 px of the bar's middle, `hoverZoneWidth`. Not
      hand-tested.)

## Fixes

- [x] The custom "Jump to bottom" is sometimes replaced by Claude's own, also
      when new messages come in. (Claude's pill turns into "3 new messages
      (ctrl+End) ↓" while scrolled up, which wasn't recognised. Both forms
      are stripped now and ours shows the count.)
- [x] The search view jumps back to the first result while picking with the
      keyboard. (The results rebuild on every clock tick, which reset the
      pick, and rebuilt rows under a resting pointer took it too. The pick
      now stays on the same app until the query changes, and only a moving
      pointer picks. Not hand-tested.)
- [x] Scrolled to the top of a conversation, a big black block showed under
      the text. (The welcome banner is dropped from the frame, which left 18
      of 26 lines. The hidden pane is now 14 rows taller than the card, so
      the frame stays full; Claude's pinned prompt stays on the top row.
      Checked by paging an idle session top to bottom: every frame full, no
      lines skipped between pages.)
- [x] The search view's tilted crab has jagged edges. (His shell and legs
      ran to the edge of the texture he's turned as, and the 3x texture
      wasn't mipmapped. It now has a clear margin and mipmaps; the margin
      also stops his thoughts being cut off on the `/ ` and `/g ` chips.
      Checked in screenshots, both states.)
- [x] A quick double-click on Search or Chat closed the island. (Those two
      views prime the key window, an Exclusive layer for 75 ms, which takes
      the pointer off the card; a second click in that time held it there
      till the button came up, long enough for the hover close. A pointer
      leave now only counts once the prime has settled, 450 ms. Not
      hand-tested.)

## Notifications

- [x] Drop the desktop notification and show it in the island instead.
      Closed, the island opens just enough for the note and a mood icon
      (✓ done, ✗ failed, ! needs you, gauge out of usage); open, the note
      sits up top above the nav. (`Toast.qml`; `testToast <kind>` over IPC.
      Both seen on screen, and a peek growing into the full island. Clicking
      a note, and the peek waiting for an open calendar, not hand-tested.)
- [x] The notification's icon is the little crab again, badge on his corner,
      as the old desktop notifications had; no border on the open island's
      note. (Seen on screen for all four moods, peek and open.)
- [x] Scrolled to the top of a conversation, its first line or two were
      still cut off, under a fade. (The card was `rows` × lineSpacing high,
      17.14 px at 13 px, but rich text lays each line out at a whole 18 px:
      26 lines ran 22 px over, bottom-aligned, so the top went, and the
      overflow switched on the top-edge fade. The line height is now probed
      from a two-line page in the same font. Measured: 26 lines are exactly
      the card at 13–16 px; the top frame from live.py starts on the ❯
      prompt. Not seen scrolled to the top on screen.)

## Corner card: Timer and Posture

- [x] The right-hand Limits card is switchable: Limits, Timer, Posture.
      (Seen on screen: the setter, the list with a draining bar, a timer
      ringing as a toast and leaving the list, the posture pane with its
      countdown. Not hand-tested: clicking the buttons, the chime's sound,
      the crab's slump in the last two minutes, a two-monitor bar.)
- [ ] Reminders take their note from a short list; typing one (and a time)
      into the Alt+Space search, e.g. `remind 14:30 call mom`, would need no
      new input in the island.
- [ ] The nav's Timers icon from the mockups (clock with a dot while
      something runs) isn't built; the corner card is the only way in.
- [ ] The Music and Note corner modes from the mockups.
