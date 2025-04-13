#!/usr/bin/env python3

# This script requires i3ipc-python package (install it from a system package
# manager or pip).
# The script "stacks" numbered workspaces 1-10 onto 11-20, 21-30, etc
# Useful for hoarding workspaces, or if you're working on a project and need
# to focus on something else, but don't wanna close your workspaces
# This script doesn't proivde a way to view workspaces in the stack, nor does it
# expect you to provide one in your sway config. The stack is for storage; pop
# workspaces onto the "home row" (1-10) to view them.

# Example sway config:
#
# set $mod Mod4
# set $alt Mod1
# bindsym $mod+$alt+s exec /path/to/swaystack.py --up
# bindsym $mod+$alt+d exec /path/to/swaystack.py --down
# bindsym $mod+$alt+r exec /path/to/swaystack.py --rot-down
# bindsym $mod+$alt+e exec /path/to/swaystack.py --rot-up

import argparse

import i3ipc


def shift_up(workspace):
    workspace_num = workspace.num

    # only call from "home row"
    if not (workspace_num >= 1 and workspace_num <= 10):
        return

    stack_num = workspace_num % 10
    stack = (w for w in ipc.get_workspaces() 
             if w.num % 10 == stack_num and w.num != 0)
    sorted_stack = sorted(stack, key=lambda w: w.num, reverse=True)

    if workspace.leaves():
        # if not empty, push up into stack
        for ws in sorted_stack:
            num = ws.num
            ipc.command(f"rename workspace {num} to {num+10}")
        ipc.command(f"workspace {workspace_num}")
    # else, do nothing


def shift_down(workspace):
    workspace_num = workspace.num

    # only call from "home row"
    if not (workspace_num >= 1 and workspace_num <= 10):
        return

    stack_num = workspace_num % 10
    stack = (w for w in ipc.get_workspaces() 
             if w.num % 10 == stack_num and w.num > 10)
    sorted_stack = sorted(stack, key=lambda w: w.num)

    if not workspace.leaves():
        bottom_num = sorted_stack[0].num
        ipc.command(f"workspace {bottom_num}")
        # if empty, pop down from the stack
        for ws in sorted_stack:
            num = ws.num
            ipc.command(f"rename workspace {num} to {num-10}")
    # else, do nothing


def rotate_down(workspace):
    workspace_num = workspace.num

    # only call from "home row"
    if not (workspace_num >= 1 and workspace_num <= 10):
        return

    stack_num = workspace_num % 10

    # TODO: cleanup repeat code
    if workspace.leaves():
        # if workspace not empty, place on opposite end of stack
        stack = (w for w in ipc.get_workspaces() 
                 if w.num % 10 == stack_num and w.num != 0)
        top_stack = max(stack, key=lambda w: w.num)
        top_num = top_stack.num

        ipc.command(f"rename workspace {workspace_num} to {top_num+10}")

    stack = (w for w in ipc.get_workspaces() 
             if w.num % 10 == stack_num and w.num > 10)
    sorted_stack = sorted(stack, key=lambda w: w.num)

    bottom_num = sorted_stack[0].num
    ipc.command(f"workspace {bottom_num}")
    for ws in sorted_stack:
        num = ws.num
        ipc.command(f"rename workspace {num} to {num-10}")


def rotate_up(workspace):
    workspace_num = workspace.num

    # only call from "home row"
    if not (workspace_num >= 1 and workspace_num <= 10):
        return

    stack_num = workspace_num % 10

    # TODO: cleanup repeat code
    if workspace.leaves():
        stack = (w for w in ipc.get_workspaces() 
                 if w.num % 10 == stack_num and w.num != 0)
        sorted_stack = sorted(stack, key=lambda w: w.num, reverse=True)

        for ws in sorted_stack:
            num = ws.num
            ipc.command(f"rename workspace {num} to {num+10}")

    stack = (w for w in ipc.get_workspaces() 
             if w.num % 10 == stack_num and w.num > 10)
    top_stack = max(stack, key=lambda w: w.num)
    top_num = top_stack.num

    ipc.command(f"workspace {top_num}")
    ipc.command(f"rename workspace {top_num} to {workspace_num}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Workspace stacking, for hoarding workspaces. Requires "
        "numerical workspaces 1-10."
    )
    action = parser.add_mutually_exclusive_group()
    action.add_argument(
        "--up",
        action="store_true",
        help="Push non-empty focused workspace onto stack (default)",
    )
    action.add_argument(
        "--down",
        action="store_true",
        help="Pop top of stack onto empty focused workspace",
    )
    action.add_argument(
        "--rot-down",
        action="store_true",
        help="Rotate down along the focused workspace stack",
    )
    action.add_argument(
        "--rot-up",
        action="store_true",
        help="Rotate up along the focused workspace stack",
    )
    args = parser.parse_args()

    ipc = i3ipc.Connection()
    focused = ipc.get_tree().find_focused().workspace()

    if args.down:
        shift_down(focused)
    elif args.rot_down:
        rotate_down(focused)
    elif args.rot_up:
        rotate_up(focused)
    else:
        shift_up(focused)
