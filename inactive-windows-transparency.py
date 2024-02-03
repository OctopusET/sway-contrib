#!/usr/bin/python

# This script requires i3ipc-python package (install it from a system package manager
# or pip).
# It makes inactive windows transparent. Use `transparency_val` variable to control
# transparency strength in range of 0…1 or use the command line argument -o.

import argparse
import signal
import sys
from functools import partial

import i3ipc


def on_window_focus(inactive_opacity, exception, ipc, event):
    global prev_focused
    global prev_workspace

    focused_workspace = ipc.get_tree().find_focused()

    if focused_workspace is None:
        return

    focused = event.container

    if focused.id != prev_focused.id:  # https://github.com/swaywm/sway/issues/2859
        if exception not in focused.marks: 
            focused.command("opacity 1")
        if exception not in prev_focused.marks:
            prev_focused.command("opacity " + inactive_opacity)
        prev_focused = focused

def on_window_mark(ipc, event):
    global prev_focused
    focused = event.container
    prev_focused = focused


def remove_opacity(ipc):
    for workspace in ipc.get_tree().workspaces():
        for w in workspace:
            w.command("opacity 1")
    ipc.main_quit()
    sys.exit(0)


if __name__ == "__main__":
    transparency_val = "0.80"
    exception_mark = "^"

    parser = argparse.ArgumentParser(
        description="This script allows you to set the transparency of unfocused windows in sway."
    )
    parser.add_argument(
        "--opacity",
        "-o",
        type=str,
        default=transparency_val,
        help="set opacity value in range 0...1",
    )
    parser.add_argument(
        "--exception",
        "-e",
        type=str,
        default=exception_mark,
        help="set window mark that skip opacity",
    )
    args = parser.parse_args()

    ipc = i3ipc.Connection()
    prev_focused = None
    prev_workspace = ipc.get_tree().find_focused().workspace().num

    for window in ipc.get_tree():
        if window.focused:
            prev_focused = window
        elif args.exception not in window.marks:
            window.command("opacity " + args.opacity)
    for sig in [signal.SIGINT, signal.SIGTERM]:
        signal.signal(sig, lambda signal, frame: remove_opacity(ipc))
    ipc.on("window::focus", partial(on_window_focus, args.opacity, args.exception))
    ipc.on("window::mark", on_window_mark)
    ipc.main()
