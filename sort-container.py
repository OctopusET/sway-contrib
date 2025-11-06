#!/usr/bin/env python3

# Sorts the focused container
# You'll usually want to focus the parent container first

# Example sway config:
#
# bindsym $mod+a focus parent # from default sway config
# bindsym $mod+Shift+s exec sort-container.py

import re

import i3ipc


def str_compare(str1, str2):
    split1 = re.split("([0-9]+)", str1)
    split2 = re.split("([0-9]+)", str2)

    for i, item in enumerate(split1):
        try:
            split1[i] = int(item)
        except ValueError:
            pass

    for i, item in enumerate(split2):
        try:
            split2[i] = int(item)
        except ValueError:
            pass

    return split1 < split2


if __name__ == "__main__":
    ipc = i3ipc.Connection()

    focused = ipc.get_tree().find_focused()

    layout = focused.layout

    if layout == "splitv" or layout == "stacked":
        move_prev = "move up"
    elif layout == "splith" or layout == "tabbed":
        move_prev = "move left"
    else:
        exit()

    leaves = focused.leaves()
    commands = []

    # insertion sort
    for i in range(1, len(leaves)):
        # focus leaf i
        commands.append(f'[con_id="{leaves[i].id}"] focus')

        # insert leaf i into sorted section
        for j in reversed(range(0, i)):
            if str_compare(leaves[j].name, leaves[j+1].name):
                break
            leaves[j+1], leaves[j] = leaves[j], leaves[j+1]
            commands.append(move_prev)

    commands.append(f'[con_id="{leaves[0].id}"] focus')

    for cmd in commands:
        ipc.command(cmd)
