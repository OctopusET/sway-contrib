#!/usr/bin/env python3
import time

import evdev
import i3ipc
from evdev import UInput, categorize, ecodes

focus_width = 61

# trying to fix issue preventing "exec focus" from working as a config entry
sway = None

time.sleep(2)

sway = i3ipc.Connection(auto_reconnect=True)

# window_id : original width
width_states: dict[int, int] = {}

# get total window count on a workspace
# find split fraction based on window count
# set all windows widths back to split fraction


def restore_default_split():
    global sway, width_states

    tree = sway.get_tree()
    focused = tree.find_focused()
    if not focused:
        return

    workspace = focused.workspace()
    leaves = workspace.leaves()

    window_count = len(leaves)
    if window_count <= 1:
        return

    width_px = workspace.rect.width
    width_target_px = int(width_px / window_count)

    for win in leaves:
        sway.command(f'[con_id="{win.id}"] resize set width {width_target_px} px')


def toggle_focus():
    global sway, width_states

    # get tree & focused window from sway
    tree = sway.get_tree()
    focused = tree.find_focused()

    # safety check
    if not focused or focused.type != "con":
        return

    window_id = focused.id

    # if the id has been seen before, restore; else resize to 67%
    if window_id in width_states:
        original_width = width_states.pop(window_id)
        sway.command(f"resize set width {original_width} px")
    else:
        width_states[window_id] = focused.rect.width
        sway.command(f"resize set width {focus_width} ppt")


def find_keyboard():
    while True:
        devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
        for device in devices:
            keys = device.capabilities().get(ecodes.EV_KEY, [])
            if ecodes.KEY_A in keys and ecodes.KEY_ENTER in keys:
                if "keyboard" in device.name.lower():
                    return device
        time.sleep(1)


dev = find_keyboard()

# This is straight from gemini, not gonna lie
uinput = UInput.from_device(dev, name="hotkey-monitor")

time.sleep(0.5)

# grab keyboard to prevent keypress from going into window
dev.grab()

# End gemini lmfao

# set() stores only unique items! this is nifty.
active_keys = set()

# handle keyboard input
for event in dev.read_loop():
    if event.type == ecodes.EV_KEY:
        key = categorize(event)

        if key.keystate == key.key_down:
            active_keys.add(key.scancode)
        elif key.keystate == key.key_up:
            active_keys.discard(key.scancode)

        if (
            ecodes.KEY_LEFTMETA in active_keys
            and ecodes.KEY_LEFTSHIFT in active_keys
            and ecodes.KEY_F in active_keys
            and key.keystate == key.key_down
        ):
            toggle_focus()
            continue

        if (
            ecodes.KEY_LEFTMETA in active_keys
            and ecodes.KEY_LEFTSHIFT in active_keys
            and ecodes.KEY_R in active_keys
            and key.keystate == key.key_down
        ):
            restore_default_split()
            continue

        uinput.write_event(event)
        uinput.syn()
