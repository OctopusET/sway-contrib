#!/usr/bin/env python

# This script keeps track of the active layout for each window.
# Optional argument defines numeric layout index for new windows (counted from 0)
#
# This script requires i3ipc-python package (install it from a system package
# manager or pip).

import sys
from typing import Optional

import i3ipc


def on_window_focus(ipc: i3ipc.connection.Connection, event: i3ipc.events.WindowEvent):
    global windows, prev_focused, default_layout

    # Get current layouts
    layouts = {
        input.identifier: input.xkb_active_layout_index for input in ipc.get_inputs()
    }

    # Save layouts for previous window
    windows[prev_focused] = layouts

    # Restore layout of the newly focused known window
    if event.container.id in windows:
        for kdb_id, layout_index in windows[event.container.id].items():
            if layout_index != layouts[kdb_id]:
                ipc.command(f'input "{kdb_id}" xkb_switch_layout {layout_index}')
                break

    # Set default layout for a fresh window
    elif default_layout is not None:
        for kdb_id, layout_index in layouts.items():
            if layout_index is not None and layout_index != default_layout:
                ipc.command(f'input "{kdb_id}" xkb_switch_layout {default_layout}')
                break

    prev_focused = event.container.id


def on_window_close(ipc: i3ipc.connection.Connection, event: i3ipc.events.WindowEvent):
    global windows
    if event.container.id in windows:
        del windows[event.container.id]


def on_window(ipc: i3ipc.connection.Connection, event: i3ipc.events.WindowEvent):
    if event.change == "focus":
        on_window_focus(ipc, event)
    elif event.change == "close":
        on_window_close(ipc, event)


if __name__ == "__main__":
    default_layout: Optional[int] = None
    if len(sys.argv) == 2:
        if sys.argv[1].isnumeric():
            default_layout = int(sys.argv[1])
        else:
            print(f"Expected an integer, got: {sys.argv[1]}", file=sys.stderr)
            sys.exit(2)
    elif len(sys.argv) > 2:
        print("Too many arguments", file=sys.stderr)
        sys.exit(2)

    ipc = i3ipc.Connection()
    focused = ipc.get_tree().find_focused()
    if focused:
        prev_focused = focused.id
    else:
        prev_focused = None
    windows: dict = {}

    ipc.on("window", on_window)
    ipc.main()
