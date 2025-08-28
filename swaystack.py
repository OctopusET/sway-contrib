#!/usr/bin/env python3

# This script requires i3ipc-python package (install it from a system package
# manager or pip).
# The script "stacks" numbered workspaces 1-10 onto 11-20, 21-30, etc, where
# each workspace number 1-10 has it's own stack
# Useful to declutter your workspaces if you need to switch focus to another
# task
# This script doesn't proivde a way to view workspaces in the stack, nor does it
# expect you to provide one in your sway config. The stack is for storage; pop
# workspaces onto the "home row" (1-10) to view them.

# Example sway config:
#
# set $mod Mod4
# set $alt Mod1
# bindsym $mod+$alt+s exec /path/to/swaystack.py --push
# bindsym $mod+$alt+d exec /path/to/swaystack.py --pop
# bindsym $mod+$alt+r exec /path/to/swaystack.py --pop-rotate
# bindsym $mod+$alt+e exec /path/to/swaystack.py --push-rotate

import argparse

import i3ipc


def get_stack_top(stack_num):
    num = stack_num % 10
    return max(w.num for w in ipc.get_workspaces()
               if w.num % 10 == num and w.num != 0)


def workspace_push(workspace):
    workspace_num = workspace.num
    top_num = get_stack_top(workspace_num)

    # if not empty, push onto stack
    if workspace.leaves():
        ipc.command(f"rename workspace {workspace_num} to {top_num+10}")
        ipc.command(f"workspace {workspace_num}")


def workspace_pop(workspace):
    workspace_num = workspace.num
    top_num = get_stack_top(workspace_num)

    # if empty, pop from stack
    if not workspace.leaves():
        ipc.command(f"workspace {top_num}")
        ipc.command(f"rename workspace {top_num} to {workspace_num}")


def workspace_pop_rotate(workspace):
    workspace_num = workspace.num
    top_num = get_stack_top(workspace_num)

    # if workspace not empty, rotate stack before pop
    if workspace.leaves():
        for n in range(top_num, workspace_num-1, -10):
            ipc.command(f"rename workspace {n} to {n+10}")

        top_num += 10

    # pop
    ipc.command(f"workspace {top_num}")
    ipc.command(f"rename workspace {top_num} to {workspace_num}")


def workspace_push_rotate(workspace):
    workspace_num = workspace.num
    top_num = get_stack_top(workspace_num)

    # if workspace not empty, push before rotate
    if workspace.leaves():
        ipc.command(f"rename workspace {workspace_num} to {top_num+10}")
        top_num += 10

    # rotate
    ipc.command(f"workspace {workspace_num+10}")
    for n in range(workspace_num+10, top_num+1, 10):
        ipc.command(f"rename workspace {n} to {n-10}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Workspace stacking, for hoarding workspaces. Requires "
        "numerical workspaces 1-10."
    )
    action = parser.add_mutually_exclusive_group()
    action.add_argument(
        "--push", "--up",
        action="store_true",
        help="Push non-empty focused workspace onto stack (default)",
    )
    action.add_argument(
        "--pop", "--down",
        action="store_true",
        help="Pop top of stack onto empty focused workspace",
    )
    action.add_argument(
        "--pop-rotate", "--rot-down",
        action="store_true",
        help="Rotate down along the focused workspace stack",
    )
    action.add_argument(
        "--push-rotate", "--rot-up",
        action="store_true",
        help="Rotate up along the focused workspace stack",
    )
    args = parser.parse_args()

    ipc = i3ipc.Connection()
    focused = ipc.get_tree().find_focused().workspace()

    # only call from "home row"
    if not (focused.num >= 1 and focused.num <= 10):
        exit(1)

    if args.pop:
        workspace_pop(focused)
    elif args.pop_rotate:
        workspace_pop_rotate(focused)
    elif args.push_rotate:
        workspace_push_rotate(focused)
    else:
        workspace_push(focused)
