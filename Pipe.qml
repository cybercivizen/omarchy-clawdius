import QtQuick
import Quickshell.Io

// A Process that hands `input` to its command on stdin, never in argv, where
// other accounts' `ps` would read it. Written once started: a write before
// that is lost and the command never gets its EOF.
Process {
  property string input: ""
  stdinEnabled: true
  onStarted: { if (input) write(input); stdinEnabled = false }
  onExited: stdinEnabled = true
}
