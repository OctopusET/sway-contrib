#!/usr/bin/env bash

# $HOME/.local/bin/fwmd-move_window.sh
# this script is called from the version of fwm called "...-new"
# "...-newest" incorporates the gist of it into itself, so the script itself is no longer used.

# This script is called from a for_window call set up from the main float-window-managerd script
# swaymsg -- [con_mark="blork1"] move position  2000 px 1000 px		also moves to the workspace from which the command came
# so apparently we'll have to get the whole tree, so that we can "move to workspace xxx" as well...

if [[ "$#" != "3" ]]; then
	echo Three parameters needed: \<mark\>  \<xpercent\>  \<ypercent\>.
	echo
	exit 1
fi

mark="$1"
xperc="$2"
yperc="$3"

echo mark= \'"$mark"\'
echo xperc= \'"$xperc"\'
echo yperc= \'"$yperc"\'
notify-send "'$mark' $xperc $yperc"

declare -i xpos  ypos  opx  opy  opw  oph  scale

# ... for some reason, breaking the following up into two commands works, and not doing so, doesn't...
#IFS=$'\t' read -r  opx opy opw oph ws win_type < <(swaymsg -t get_tree |  \
#			jq -r --arg MARK "$mark"  '. as $root | $root.nodes[] as $o | $o.nodes[] as $ws | 
#			$ws.floating_nodes[] as $win | select ( $win.marks[] == $MARK  ) |
#			[$o.rect.x, $o.rect.y, $o.rect.width, $o.rect.height, $ws.name, $win.type] | @tsv')

sgt_jq=$(swaymsg -t get_tree |  \
			jq -r --arg MARK "$mark"  '. as $root | $root.nodes[] as $o | $o.nodes[] as $ws | 
			$ws.floating_nodes[] as $win | select ( $win.marks[] == $MARK  ) |
			[$o.rect.x, $o.rect.y, $o.rect.width, $o.rect.height, $ws.name, $win.type] | @tsv')
result=$?
if [[ "$result" != 0 ]]; then
	echo result=\'"$result"\' problem with swaymsg/jq finding \'"$mark"\'...
	echo sway/jq returned: \'"$sgt_jq"\'
	notify-send "Couldn't find '$mark'"
	exit 1
fi

IFS=$'\t' read -r  opx opy opw oph ws win_type <<<"$sgt_jq"
result=$?
if [[ "$result" != 0 ]]; then
	echo result=\'"$result"\' problem with read \'"$mark"\'...
	notify-send "Problem with reading return from finding '$mark'"
	exit 1
fi

echo \'"$win_type"\'
if [[ "$win_type" != "floating_con" ]]; then	# must be a tiling window that HAS sometimes been floating...
#	str=$(swaymsg -- \[con_mark="$mark"\]  mark --toggle "$mark")
	str=$(swaymsg -- \[con_mark="$mark"\]  unmark "$mark")
	result=$?
	if [[ "$result" != 0 ]]; then
		echo result=\'"$result"\' for swaymsg \'un mark non-floating window.\'...
		exit 1
	fi
	notify-send  "Window not floating... aborting move."
	exit 1
fi


notify-send "fwmd-move_window: $1 $2 $3"


echo output position: \'"$opx"\' , \'"$opy"\'
echo output size    : \'"$opw"\' x \'"$oph"\'
echo workspace: \'"$ws"\'

scale=6

xposr=$(echo "scale=$scale; $xperc / 100 * $opw + .5" | bc -l)
echo xposr= \'"$xposr"\'
#xpos=$(echo "scale=0; $xposr / 1" | bc -l)
xpos=$(echo "scale=0; $xposr / 1 + $opx" | bc -l)
#echo xpos= \'"$xpos"\'
#xpos=$(echo "scale=0; $xpos + $opx" | bc -l)
echo xpos= \'"$xpos"\'

yposr=$(echo "scale=$scale; $yperc / 100 * $oph + .5" | bc -l)
echo yposr= \'"$yposr"\'
#ypos=$(echo "scale=0; $yposr / 1" | bc -l)
ypos=$(echo "scale=0; $yposr / 1 + $opy" | bc -l)
#echo ypos= \'"$ypos"\'
#ypos=$(echo "scale=0; $ypos + $opy" | bc -l)
echo ypos= \'"$ypos"\'

# swaymsg -- [con_mark="blork1"] move position  2000 px 1000 px		also moves window to the workspace from which the command came,
# so apparently we'll have to get the whole tree, so that we can "move to workspace xxx" as well...
# AND ...apparently, the "move to workspace" needs to be at the end...

#str=$(swaymsg -- \[con_mark="$mark"\] move window to workspace "$ws", move absolute position  "$xpos" px  "$ypos" px, mark --toggle "$mark")
#str=$(swaymsg -- \[con_mark="$mark"\] move absolute position  "$xpos" px  "$ypos" px, move window to workspace "$ws", mark --toggle "$mark")
 str=$(swaymsg -- \[con_mark="$mark"\] move absolute position  "$xpos" px  "$ypos" px, move window to workspace "$ws", unmark "$mark")
result=$?
if [[ "$result" != 0 ]]; then
	echo result=\'"$result"\' for swaymsg \'move window\'...
	echo Sway returns \'"$str"\'
	notify-send "result='$result' for swaymsg 'move window'..."
	notify-send "Sway returns '$str'"
	exit 1
fi


exit


