#!/usr/bin/env python3

import argparse
import i3ipc

# minimal code reuse because of weird edge cases in each
# better just to have separate functions imo
# could improve code reuse, but the easy way adds flickering and the hard way
# is probably worse

def shift_up(workspace):
    workspace_num = workspace.num

    # only call from "home row"
    if not (workspace_num >= 1 and workspace_num <= 10):
        return

    stack_num = workspace_num % 10
    stack = (w for w in ipc.get_workspaces() 
             if w.num % 10 == stack_num and w.num != 0)
    sorted_stack = sorted(stack, key=lambda w: w.num, reverse=True)

    if not workspace.leaves():
        # if empty, grab from top instead
        top_num = sorted_stack[0].num
        ipc.command(f"workspace {top_num}")
        ipc.command(f"rename workspace {top_num} to {workspace_num}")
    else:
        # if not empty, push up into stack
        for ws in sorted_stack:
            num = ws.num
            ipc.command(f"rename workspace {num} to {num+10}")
        ipc.command(f"workspace {workspace_num}")


def shift_down(workspace):
    workspace_num = workspace.num

    # only call from "home row"
    if not (workspace_num >= 1 and workspace_num <= 10):
        return

    stack_num = workspace_num % 10
    stack = (w for w in ipc.get_workspaces() 
             if w.num % 10 == stack_num and w.num > 10)
    sorted_stack = sorted(stack, key=lambda w: w.num)

    if workspace.leaves():
        # if workspace not empty, place on the opposite end of the stack
        top_num = sorted_stack[-1].num
        ipc.command(f"rename workspace {workspace_num} to {top_num+10}")
        ipc.command(f"workspace {workspace_num}")
    else:
        bottom_num = sorted_stack[0].num
        ipc.command(f"workspace {bottom_num}")
        # if empty, pop down from the stack
        for ws in sorted_stack:
            num = ws.num
            ipc.command(f"rename workspace {num} to {num-10}")


def rotate_down(workspace):
    workspace_num = workspace.num

    # only call from "home row"
    if not (workspace_num >= 1 and workspace_num <= 10):
        return

    stack_num = workspace_num % 10

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
        description="Workspace stacking! For hoarding workspaces!"
    )
    parser.add_argument(
        "--up",
        action='store_true',
        help="push stack",
    )
    parser.add_argument(
        "--down",
        action='store_true',
        help="pop stack",
    )
    parser.add_argument(
        "--rot-down",
        action='store_true',
        help="pop stack",
    )
    parser.add_argument(
        "--rot-up",
        action='store_true',
        help="pop stack",
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

