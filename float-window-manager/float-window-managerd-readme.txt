FloatWindowManager is designed to remember where you put floating windows, so that they appear
there the next time they appear - thus they are not always appearing dead center in the screen.

This is accomplished by subscribing to swaymsg's window events, and storing all window events that
are new, close, or float.
When a float window is opened, its position is stored.  When it closes, if the position is different,
the window's position as a percentage is stored in a file, the filename being the window title.
Percentages in move commands started in Sway version 1.6, so this script will not work
with Sway versions before that.

When floatwindowmanager starts up, it looks through all files in a specified directory
("$HOME/.config/sway/float_window_store/"), and creates "for_window" rules for each one 
instructing sway to move the window to x and y percentages of the output's width/height.
Thus Sway itself moves the windows.

FloatWindowManager also remembers where you place windows that HAD BEEN tiling, but that
you have converted to floating.
Since a window that changes from tiling to floating (or from floating to tiling) is not
a new window, Sway will not automatically move the windows; the script does that "manually".

If a window was moved accidentally, that you would rather just leave centered, you can delete
the file from the above directory, or leave it there and erase the percentages within.

This script uses 4 commands (at least) that must be present in order to run:
swaymsg, inotifywait, jq, and notify-send.

If you're using Sway, then you'll have swaymsg, but the others may need to be installed.
On Debian, inotifywait is available in the package inotify-tools,
jq is from the identically-named package jq, and notify-send is from libnotify-bin
(for notifications, I use  emersion's mako, from the mako-notifier package on Debian)

How to use:

Move/copy the script to somewhere on your path.
Add a line to the config file similar to the following, which I use:
exec float-window-managerd.sh > $LOGS/$(date +"%Y%m%d:%H%M%S_")float-window-managerd.log 2>&1
(I don't know if there would be any advantage with using exec_always - I don't know if
Sway throws out all existing for_window rules for a config-reload.)
If you wish to look at the log file, then use the re-directs, and define $LOGS to be where
you want to find logs, or use an already defined location.
Presumably, you'll want to have the line earlier in the config than when where you call the
first app that has a floating window that you want to move... (cannot rule out possible
race conditions, of course...), 'though after Mako (or similar notification app).

I have NOT included a command to turn FloatWindowManager off.
While I could call the same process-killing code that is part of the program, Sway's 
for_window rules would still be in play.  I don't know of any way to remove for_window rules,
and while I could issue new for_window rules with "move position center", the old rules will
still be there.  If there are a lot, it could be slow, maybe ending up with the window moving
twice.
Turning it off can be done with commenting-out/deleting the config-file line, and logging
out/in again.

How it works:
FloatWindowManager is a daemon (I believe how it works qualifies for that term) that sits
and waits for a certain things to happen.
inotifywait is called to notify when a certain file changes.
A request is made to subscribe to Sway's window events, and only new/close/floating events are
added to a file - the file that inotifywait is monitoring.
This file is '/tmp/sway_win_events.txt', and (being in /tmp) will be deleted when rebooting;
On startup, if the file is found, it is reset to empty.
Those window events are read and handled, and then a different inotifywait call is used to
wait until the first inotifywait notices again that are new events.  Then the new events are
handled, etc.
This system ensures that no events are missed while earlier events are being handled.
