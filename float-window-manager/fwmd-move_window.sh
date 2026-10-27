#!/usr/bin/env bash

# $HOME/.local/bin/fwmd-move_window.sh

# This script is called from a for_window call set up from the main float-window-managerd script
# swaymsg -- [con_mark="blork1"] move position  2000 px 1000 px		also moves to the workspace from which the command came
# so apparently we'll have to get the whole tree, so that we can "move to workspace xxx" as well...

if [[ "$#" != "1" ]]; then
	echo One parameter needed: \<mark\>.
	echo
	exit 1
fi

mark="$1"
winpath="$HOME/.config/sway/float_window_store/"
percent_regex="^[0-9]{1,2}(\.{1}[0-9]+)?$"

echo mark= \'"$mark"\'

declare -i xpos  ypos  opx  opy  opw  oph  scale

sgt_jq=$(swaymsg -t get_tree |  \
			jq -r --arg MARK "$mark"  '. as $root | $root.nodes[] as $o | $o.nodes[] as $ws | 
			$ws.floating_nodes[] as $win | select ( $win.marks[] == $MARK  ) |
			[$o.rect.x, $o.rect.y, $o.rect.width, $o.rect.height, $ws.name, $win.type] | @tsv')
result=$?
if [[ "$result" != 0 ]]; then
	echo result=\'"$result"\' problem with swaymsg/jq finding \'"$mark"\'...
	echo sway/jq returned: \'"$sgt_jq"\'
	exit 1
fi

IFS=$'\t' read -r  opx opy opw oph ws win_type <<<"$sgt_jq"
result=$?
if [[ "$result" != 0 ]]; then
	echo result=\'"$result"\' problem with read \'"$mark"\'...
	exit 1
fi

echo \'"$win_type"\'
if [[ "$win_type" != "floating_con" ]]; then	# must be a tiling window that HAS sometimes been floating...
	str=$(swaymsg -- \[con_mark="$mark"\]  unmark "$mark")
	result=$?
	if [[ "$result" != 0 ]]; then
		echo result=\'"$result"\' for swaymsg \'un mark non-floating window.\'...
		exit 1
	fi
	echo Window not floating... aborting move.
	exit 1
fi

winname=$(swaymsg -t get_tree | jq -r --arg MARK "$mark" '.. | select(.marks? | index($MARK)) | .name')
read -r xperc yperc < "$winpath$winname"
echo winname= \'"$winname"\'  xperc= \'"$xperc"\'  yperc= \'"$yperc"\'
if [[ ! ("$xperc" =~ $percent_regex && "$yperc" =~ $percent_regex) ]]; then
	echo No valid percentages saved, not moving.
	swaymsg -- \[con_mark="$mark"\] unmark "$mark"
	exit 0
fi

echo output position: \'"$opx"\' , \'"$opy"\'
echo output size    : \'"$opw"\' x \'"$oph"\'
echo workspace: \'"$ws"\'

scale=6

xposr=$(echo "scale=$scale; $xperc / 100 * $opw + .5" | bc -l)
echo xposr= \'"$xposr"\'
xpos=$(echo "scale=0; $xposr / 1 + $opx" | bc -l)
echo xpos= \'"$xpos"\'

yposr=$(echo "scale=$scale; $yperc / 100 * $oph + .5" | bc -l)
echo yposr= \'"$yposr"\'
ypos=$(echo "scale=0; $yposr / 1 + $opy" | bc -l)
echo ypos= \'"$ypos"\'

# swaymsg -- [con_mark="blork1"] move position  2000 px 1000 px		also moves window to the workspace from which the command came,
# so apparently we'll have to get the whole tree, so that we can "move to workspace xxx" as well...
# AND ...apparently, the "move to workspace" needs to be at the end...

# Quote the workspace name for sway, which would split it at commas.
str=$(swaymsg -- \[con_mark="$mark"\] move absolute position  "$xpos" px  "$ypos" px, move --no-auto-back-and-forth window to workspace "\"$ws\"", unmark "$mark")
result=$?
if [[ "$result" != 0 ]]; then
	echo result=\'"$result"\' for swaymsg \'move window\'...
	echo Sway returns \'"$str"\'
	exit 1
fi


exit


