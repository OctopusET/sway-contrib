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


def on_window(args, ipc, event):
    global focused_set

    # To get the workspace for a container, we need to have received its
    # parents, so fetch the whole tree
    tree = ipc.get_tree()

    focused = tree.find_focused()
    if focused is None:
        return

    focused_workspace = focused.workspace()

    focused.command("opacity " + args.focused)
    focused_set.add(focused.id)

    to_remove = set()
    for window_id in focused_set:
        if window_id == focused.id:
            continue
        window = tree.find_by_id(window_id)
        if window is None:
            to_remove.add(window_id)
        elif args.global_focus or window.workspace() == focused_workspace:
            window.command("opacity " + args.opacity)
            to_remove.add(window_id)

    focused_set -= to_remove

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
    parser.add_argument(
        "--global-focus",
        "-g",
        action="store_true",
        help="only have one opaque window across all workspaces",
    )
    args = parser.parse_args()

    ipc = i3ipc.Connection()
    focused_set = set()

    for window in ipc.get_tree():
        if window.focused:
            focused_set.add(window.id)
            window.command("opacity " + args.focused)
        else:
            window.command("opacity " + args.opacity)
    for sig in [signal.SIGINT, signal.SIGTERM]:
        signal.signal(sig, lambda signal, frame: remove_opacity(ipc, args.focused))
    ipc.on("window", partial(on_window, args))
    ipc.main()
