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


def on_window_focus(args, ipc, event):
    global prev_focused
    global prev_workspace

    focused_workspace = ipc.get_tree().find_focused()

    if focused_workspace is None:
        return

    focused = event.container
    workspace = focused_workspace.workspace().num

    if focused.id != prev_focused.id:  # https://github.com/swaywm/sway/issues/2859
        focused.command("opacity " + args.focused)
        if workspace == prev_workspace:
            prev_focused.command("opacity " + args.opacity)
        prev_focused = focused
        prev_workspace = workspace


def remove_opacity(ipc, focused_opacity):
    for workspace in ipc.get_tree().workspaces():
        for w in workspace:
            w.command("opacity " + focused_opacity)
    ipc.main_quit()
    sys.exit(0)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="This script allows you to set the transparency of unfocused windows in sway."
    )
    parser.add_argument(
        "--opacity",
        "-o",
        type=str,
        default="0.80",
        help="set inactive opacity value in range 0...1",
    )
    parser.add_argument(
        "--focused",
        "-f",
        type=str,
        default="1.0",
        help="set focused opacity value in range 0...1",
    )
    args = parser.parse_args()

    ipc = i3ipc.Connection()
    prev_focused = None
    prev_workspace = ipc.get_tree().find_focused().workspace().num

    for window in ipc.get_tree():
        if window.focused:
            prev_focused = window
        else:
            window.command("opacity " + args.opacity)
    for sig in [signal.SIGINT, signal.SIGTERM]:
        signal.signal(sig, lambda signal, frame: remove_opacity(ipc, args.focused))
    ipc.on("window::focus", partial(on_window_focus, args))
    ipc.main()
