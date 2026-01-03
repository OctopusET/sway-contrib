#!/usr/bin/env bash

# $HOME/.local/bin/float-window-managerd.sh
# This version, called -new, utilizes an auxilliary script: fwmd-move_window.sh

# (11/2025) New version (at least to try...)
# Since Sway does not allow floating-point percentages in its move window command, I will try to get around that by
# using Sway's ability to mark a window uniquely within a for_window command.
# Instead of immediately moving the window with percentages, we will mark the window, and then call a script that will
# move it with pixel positioning by using the desired floating-point percentages against the currently-focussed output's
# dimensions and position.
# The script will take as parameters the mark and the x and y percentages.
# The mark needs to be unique, and it could be that several for_window s would be called closely enough together to cause a race
# situation, so I will use the date command with whatever option causes a single date/time (or just time) to be output.
# The script will call swaymsg -t get_tree 

# I have just (10/2025) found that FWM does not work on a second output.  The rect.x and .y values are apparently GLOBAL.
# To get the output-relative rect.x and .y values, we must subtract the output's rect.x/.y values from the window's rect.x/.y values.
# There are tests for x and y being less than output width (to make sure window is onscreen).  This will not work without alteration,
# as the values of x/y are global. We'll have to get output-relative x/y values to compare here (and we would need them anyway,
# for use in calculating the percentages.)
# We don't need to use the relative x/y until we are trying to figure out if a closing window is off the screen, and to calculate
# the closing window's position percentage. However, a closing window event means we cannot get the window to find out the output
# and its position, as the window is gone. Therefore, we must make new arrays for the output x/y, so that we can reference them at close.

# This version will attempt to also handle windows that were tiling, but are now floating.
# The type of window event is: "change": "floating"
# This is the same whether changing to floating, or changing from floating to tiling.
# The "container" "type" is what the window is changing TO: "floating_con" if changing to floating, "con" if changing to tiling
# Since this does not involve a window's creation, one cannot use a for_window to automatically move the window.
# The event's container's rect.x and rect.y appear to be the position of the floating window, whether it is just becoming floating
# or just becoming tiling.  This means we DO have the ability to see the original position when floating, and the last position
# before tiling.


cmds_all_found=true
for cmd in swaymsg inotifywait jq notify-send; do
	output=$(command -v "$cmd")
	if [[ "$output" =~ ^alias ]]; then
		echo cmd \'"$cmd"\' found as an alias.
	else
		if [[ "$output" == "" ]]; then
			echo cmd \'"$cmd"\' not found.
			cmds_all_found=false
		else
			if  ! [[ -x "$output" ]]; then
				echo cmd \'"$cmd"\' found, but is not executable.
				cmds_all_found=false
			else
				echo cmd \'"$cmd"\' found and is executable.
			fi
		fi
	fi
	
done
if ! "$cmds_all_found"; then
	echo Not all commands were found.
	notify-send "Not all required commands for float-window-manager were found."
	exit 1
else
	echo All commands were found.
fi

# This new version-compare authored by: https://github.com/sakarie9
#min_version="1.6"		# first Sway with 'move <xx> ppt' ("percentage points").
 min_version="0.13.0"	# first Sway with window marks.
version=$(swaymsg -t get_version | jq -r '.human_readable')
# sort can sort by version -V;  head -n NUM --> print the first NUM lines to standard output
if [ "$(echo -e "$version\n$min_version" | sort -V | head -n 1)" != "$min_version" ]; then
#   True if $version is less than $min_version
#	echo This version of Sway is earlier than supports moving windows with percentages.
	echo This version of Sway is earlier than supports \'mark\'-ing windows.
	echo Version is \'"$version"\'. Version needed: \'"$min_version"\'.
	notify-send "Sway version is too old for float-window-manager."
	notify-send "Version is '"$version"'. Version needed: '"$min_version"'."
	exit 1
fi

move_window_script_path="$HOME/.local/bin"
if [[ ! -f "$move_window_script_path/fwmd-move_window.sh" ]]; then
	echo "float-window-manager: move window script:"
	echo \'"$move_window_script_path/fwmd-move_window.sh"\' not found.
	notify-send "float-window-manager: move window script:"
	notify-send "'"$move_window_script_path/fwmd-move_window.sh"' not found."
fi



winpath="$HOME/.config/sway/float_window_store/"

[ -d "$winpath" ] || mkdir -p -v "$winpath"	# " -p no error if existing, make parent directories as needed"

# https://stackoverflow.com/questions/15783701/which-characters-need-to-be-escaped-when-using-bash
doublequote=\"
singlequote=\'
# I noticed that the GIMP main window ends with '– GIMP', where the dash is not '-'. but '–', so I have added it to "special", in case it's a problem for regexp
special=$'`!@#$%^&*()-–_+={}|[]\\;\:,.<>?/ '$doublequote$singlequote		# featherpad's syntax highlighting seems to get messed up with these actual quotes in the special string...
backslash=$'\\'
caret=$'^'
dollar=$'$'

escape_bad_chars_in_winname() {
	local winname="$1"
	
	winname_escape=""
	for ((i=0; i<"${#winname}"; i++)); do
		c="${winname:i:1}"
  		if [[ $special =~ "$c" ]]; then		# if not in quotes, some are missed, like '*'
#		if [[ $special == *"$c"* ]]; then 	# another way to do this (like with case statements)
			c1="$backslash$c"
		else
			c1="$c"
		fi
		winname_escape+="$c1"
	done
	echo "$winname_escape"
}


unset_arrays() {
	unset already_processed["$con_id"]
	unset was_tiling["$con_id"]
	unset outputwidth["$con_id"]
	unset outputheight["$con_id"]
	unset outputx["$con_id"]
	unset outputy["$con_id"]
	unset orig_win_x["$con_id"]
	unset orig_win_y["$con_id"]
	unset ws_x["$con_id"]
	unset ws_y["$con_id"]
	unset win_deco_height["$con_id"]
	unset ignore_me["$con_id"]
	echo Arrays unset...
}

old_percent_regex="^[+-]?[0-9]{1,2}$"					# integer -> +/- plus 1 or 2 digits 0-9
		 percent_regex="^[0-9]{1,2}(\.{1}[0-9]+)?$"		# float   -> above, plus 0 or 1 ("?") "single dot + 1 or more ("+") digits"
# (Why were we accepting negative percentages here, when we were disallowing them below...?)


# Make a Sway for_window rule for each file in $winpath, using the filename as title, and the contents as x and y percentages
for file in $winpath/*; do
	filename=$(basename "$file")
	winname="$filename"
	
	read -r xperc yperc < "$file" > /dev/null  2>&1
	result=$?
	if (( "$result" != 0 )); then 
		echo file \'"$file"\' could not be read...
		continue
	fi
	
	echo winname= \'"$winname"\'        xperc= \'"$xperc"\'  yperc= \'"$yperc"\'
	
	if [[ ("$xperc" == "") && ("$yperc" == "") ]]; then		# "ignore me"
		echo "   --\> \"Ignore Me\""
		continue
	fi
	if [[ ("$xperc" == "") || ("$yperc" == "") ]]; then		# missing a percent
		echo "   --\> has a missing percentage. Ignoring."
		continue
	fi
	if [[ ( ! ("$xperc" =~ $percent_regex) || ! ("$yperc" =~ $percent_regex) )  ]]; then
		echo "   --\> has invalid percentage[s]. Ignoring."
		continue
	fi
	if (( $(echo "$xperc < 0" |bc -l) || $(echo "$xperc > 100" |bc -l) || 
		  $(echo "$yperc < 0" |bc -l) || $(echo "$yperc > 100" |bc -l) )); then 
		echo Window \'"$winname"\' has percentage[s] outside 0-100. Ignoring.
		continue
	fi
	echo "   --\> percentages OK."

	winname="$(escape_bad_chars_in_winname "$winname")"
	fw_winname="$caret""$winname""$dollar"	# make sure title begins and ends with winname, not just contains it
	
	datestr="$(date +%Y%m%d:%H%M%S:%N)"	# format (+) date as "nanoseconds (000000000..999999999)" (%N)
	mark="fmwd_""$datestr"
	swaymsg_output=$(swaymsg -- for_window \[title=$doublequote$fw_winname$doublequote\] mark "$mark")
	result=$?
	if [[ ! "$result" == 0 ]]; then
		echo Window \'"$winname"\':  for_window mark $mark fails with message: \'"$swaymsg_output"\'
	fi
#	swaymsg_output=$(swaymsg -- for_window \[title=$doublequote$winname$doublequote\] exec "$move_window_script_path/fwmd-move_window.sh $mark $xperc $yperc")
	swaymsg_output=$(swaymsg -- for_window \[title=$doublequote$fw_winname$doublequote\] exec "$move_window_script_path/fwmd-move_window.sh $mark $xperc $yperc >> $LOGS/$(date +"%Y%m%d:%H%M%S_")${winname}_$mark.log 2>&1")
	result=$?
	if [[ ! "$result" == 0 ]]; then
		echo Window \'"$winname"\':  for_window exec move_window_script fails with message: \'"$swaymsg_output"\'
	fi
done




declare -i  con_id  opw  oph  opx  opy  rel_x  rel_y  event_win_x  event_win_y  opw_m_wsx  oph_m_wsy_m_wdh  scale
declare -a  PIDarray  we_array  outputwidth  outputheight  outputx  outputy  orig_win_x  orig_win_y  ignore_me
declare -a  already_processed  was_tiling  ws_x  ws_y  win_deco_height

we_file='/tmp/sway_win_events.txt'
if [[ -s "$we_file" ]]; then	# ...if we find "$we_file", and it has non-zero size...
	truncate -s 0 "$we_file"
else touch "$we_file"
fi

echo
echo
echo '============================================================='
echo Now killing any other window-placement processes...


echo BASHPID= \'"$BASHPID"\'
BASH_SID=$(ps -p "$BASHPID" -o sid=)
echo BASH_SID= \'"$BASH_SID"\'

PS=$(pgrep -f -d ' ' "float-window-managerd.sh")  #instead of \n, -d elimit with a space.
#	-f "match against the ...full command line, not just the process name."
echo PS= \'"$PS"\'
IFS=" " read -r -a PIDarray <<< "$PS"
for PID in "${PIDarray[@]}"
do
	echo PID= \'"$PID"\'
	SID=$(ps -p "$PID" -o sid=)
	if [[ $SID == "" ]]; then  #...already killed this one...
		echo ...must already have killed the SID for PID= \'"$PID"\'
		continue
	fi
	if [[ "$SID" != "$BASH_SID" ]]; then
		echo killing session ID \'$SID\'
		pkill -s $SID  #not quoted, as $SID as generated by PS has a space at the beginning... 
	else
		echo oops!  That\'s OUR SID! \($BASH_SID\)  Not killing...
	fi

done
echo '============================================================='
echo
echo
notify-send "...starting Float Window Manager..."

scale=4
echo scale=\'"$scale"\'
zeros="000000000"
round='.'${zeros:0:$scale}"5"
echo round=\'"$round"\'

# We will constantly monitor (-m) we_file, and when it changes, write stuff (we don't care what) to inw_file
# Later, instead of constantly looping to see if we_file has had more lines added to it (and thus use 20-25% CPU),
# we will call inotifywait again (but NOT with -m) and have it wake us when something changes. 
inw_file='/tmp/sway_win_events_inotifywait.txt'
inotifywait -m -e modify "$we_file" > "$inw_file" 2>&1  & 


swaymsg  -t subscribe -m '[ "window" ]' | grep --line-buffered -E '"change": "new"|"change": "close"|"change": "floating"' >> "$we_file" &

echo now starting to read window new and close events from file

# We will read events from we_file until we cannot, and then inotifywait until there are events again

i=1
while true; do
	while true; do
		IFS=$'\n' read -d '\n' -a we_array < <(tail -n +"$i" "$we_file" )  # read from line $i to [current] EOF
		num_events="${#we_array[@]}"
		if [[ "$num_events" == 0 ]]; then
 			break;  # while true - inner loop - go back to waiting in outer 'while true' loop
		fi
		echo
		echo i=$i read $num_events events
		
		
		for we in "${we_array[@]}"; do 
			echo '=================================================================================='
    		echo \'"$we"\'
    		echo
    		

   			IFS=$'\t' read -r event_type  con_id  event_win_type  event_win_x  event_win_y  event_win_name  \
   						  < <(echo "$we"  | jq -r '. as $root | 
  											$root.container as $con | [$root.change, $con.id,
  											$con.type, $con.rect.x, $con.rect.y, $con.name // "NuLlnUlLNuLlnUlL"]  | @tsv ')
			echo \'"$event_win_name"\'
			event_win_name=${event_win_name//NuLlnUlLNuLlnUlL/}
			echo \'"$event_win_name"\'

			if [[ "$event_type" == "floating" ]]; then
				if [[ "$event_win_type" == "floating_con" ]]; then
					event_type="to_floating"
					echo event_type "floating--->to_floating"
				else 
					event_type="to_tiling"
					echo event_type "floating--->to_tiling"
				fi
			else
				# handle a closed originally-tiling window as if it reverted to tiling
				if [[ ("$event_type" == "close") && ("${was_tiling["$con_id"]}" == "yes") ]]; then
					event_type="to_tiling"
					echo event_type "close--->to_tiling"
				fi
			fi

			echo \'"$event_type"\'   \'"$con_id"\'   \'"$event_win_type"\'   \'"$event_win_name"\'
			echo Window position: "$event_win_x" , "$event_win_y"


			case "$event_type" in
			
		 	 	*"new"* | *"to_floating"*)

					if [[ "$event_type" == "new" ]]; then
						sleep 1   # delay long enough for name to get into win_name, and win_type to be set to "floating_con" (or not) 
					else	# "to_floating"
						if [[ -v  already_processed["$con_id"] ]]; then
							echo We already processed a \'new\' event for window \'"$con_id"\'
							echo
							continue  # for we in "${we_array[@]}"
						fi
					fi
					
					# $win.name is sometimes null, and messes up the read; we change null to bogus name here, and will deal with it later...
    		    	IFS=$'\t' read -r   win_type  win_x  win_y  win_deco_height  ws_name  ws_x  ws_y  \
    		    						output_width  output_height  output_x  output_y  win_name  < <(swaymsg -t get_tree |  \
						jq -r --arg CONID "$con_id" '. as $root | $root.nodes[] as $output | $output.nodes[] as $ws |
				 		$ws.floating_nodes[] as $win | select ( $win.id == ($CONID | tonumber) ) | 
				  		[$win.type, $win.rect.x, $win.rect.y, $win.deco_rect.height, $ws.name, $ws.rect.x, $ws.rect.y,
				  		  $output.rect.width, $output.rect.height, $output.rect.x, $output.rect.y, $win.name // "NuLlnUlLNuLlnUlL"] | @tsv')
				  	result=$?
				  	if [[ "$result" != 0 ]]; then
					  	echo result=\'"$result"\'  ...apparently window matching con_id=\'"$con_id"\' is not floating  -  aborting this event...
					  	unset_arrays
					  	continue  # for we in "${we_array[@]}"
				  	fi
					echo \'"$win_name"\'
				  	win_name=${win_name//NuLlnUlLNuLlnUlL/}		# change bogus "name" back into empty string
					echo \'"$win_name"\'
				    echo \'$event_type\'   \'$con_id\'   \'$win_name\'
					echo \'"$win_name"\' type=\'"$win_type"\'  x:y $win_x : $win_y  win_deco_height=$win_deco_height  ws:$ws_name x:$ws_x y:$ws_y $output_width x $output_height

					already_processed["$con_id"]="yes"	# this will never be "no" - we just test for set/unset ...
					if [[ "$event_type" == "new" ]]; then
						was_tiling["$con_id"]="no"
					else
						was_tiling["$con_id"]="yes"
					fi
					outputwidth["$con_id"]="$output_width"
					outputheight["$con_id"]="$output_height"
					outputx["$con_id"]="$output_x"
					outputy["$con_id"]="$output_y"
					orig_win_x["$con_id"]="$win_x"
					orig_win_y["$con_id"]="$win_y"
					ws_x["$con_id"]="$ws_x"
					ws_y["$con_id"]="$ws_y"
					win_deco_height["$con_id"]="$win_deco_height"
					ignore_me["$con_id"]="no"

					if [[ "$win_name" != "" ]]; then	# $win_name often 'null'-->"" for 'to_floating'
						wn="$win_name"
					else
						wn="$event_win_name"
					fi
					file="$winpath""$wn"
					read -r xperc yperc < "$file" > /dev/null  2>&1
					result=$?
					echo file-read result: \'$result\'
					if (( "$result" == 0 )); then 
						echo -n 'xperc:yperc' \'"$xperc"\' : \'"$yperc"\'	# echo line finished with the below '--->' \"Ignore me\", or with other text.
						if [[ ("$xperc" == "") && ("$yperc" == "") ]]; then
							ignore_me["$con_id"]="yes"
							notify-send "Position of window \"$wn\" ignored."
							echo  '--->' \"Ignore me\"
						else
							if [[ ( ("$xperc" != "") && ("$yperc" != "") ) &&
									( ("$xperc" =~ $percent_regex) && ("$yperc" =~ $percent_regex) )  ]]; then
								if (( $(echo "$xperc >= 0" |bc -l) && $(echo "$xperc <= 100" |bc -l) && 
									  $(echo "$yperc >= 0" |bc -l) && $(echo "$yperc <= 100" |bc -l) )); then 
									echo  '---> percentages present and valid.'
									
									if [[ "$event_type" == "to_floating" ]]; then	# we have to move the window ourselves.
										datestr="$(date +%Y%m%d:%H%M%S:%N)"	# format (+) date as "nanoseconds (000000000..999999999)" (%N)
										mark="fmwd_""$datestr"
										swaymsg_output=$(swaymsg -- \[con_id=$con_id\] mark "$mark")
										result=$?
										if [[ "$result" != 0 ]]; then
											echo Window \'"$wn"\':  \"mark "$mark"\" fails with message: \'"$swaymsg_output"\'
											unset_arrays
											continue  # for we in "${we_array[@]}"
										fi
										swaymsg_output=$(swaymsg -- \[con_id=$con_id\] exec "$move_window_script_path/fwmd-move_window.sh $mark $xperc $yperc  >> $LOGS/$(date +"%Y%m%d:%H%M%S_")${wn}_$mark.log 2>&1")
										result=$?
										if [[ "$result" != 0 ]]; then
											echo Window \'"$wn"\':  \"move position\" fails with \'"$result"\' and message: \'"$swaymsg_output"\'
											unset_arrays
											continue  # for we in "${we_array[@]}"
										fi

# Now, we'll have to get the window from swaymsg, as the position changed, and we will need to know later for "close"/"to_tiling
# if its position later changed from the saved position.
					    				IFS=$'\t' read -r  win_x  win_y < <(swaymsg -t get_tree |  \
											jq -r --arg CONID "$con_id" '. as $root | $root.nodes[] as $output | $output.nodes[] as $ws |
											$ws.floating_nodes[] as $win | select ( $win.id == ($CONID | tonumber) ) | 
					  						[$win.rect.x, $win.rect.y] | @tsv')
										result=$?
										if [[ "$result" != 0 ]]; then
											echo result=\'"$result"\'  ...apparently window matching con_id=\'"$con_id"\' is not floating  -  aborting this event...
											unset_arrays
											continue  # for we in "${we_array[@]}"
										fi

										orig_win_x["$con_id"]="$win_x"
										orig_win_y["$con_id"]="$win_y"
										echo window moved to "$win_x" "$win_y"
										echo window moved to $xperc % $yperc %
										notify-send "Position of window \"$wn\" moved."
									fi	# "$event_type" == "to_floating"
								else
									echo  '---> percentage[s] out of bounds.  Will fix later, if moved.'
								fi	# xperc/yperc present and correctly formed, but out of bounds ?
							else
								echo  '---> missing/malformed percentage[s].  Will fix later, if moved.'
							fi  # xperc/yperc present and valid ?
						
						fi  # xperc AND yperc present ? ?
					fi  # file read successful ?

 					;;




	 		*"close"* | *"to_tiling"*)

					echo \'"$event_type"\'   \'"$con_id"\'   \'"$event_win_name"\'
					
					if [[ ("$event_type" == "close") && ("$event_win_type" != "floating_con") ]]; then
						echo Not a floating_con... aborting...
						continue   # for we in "${we_array[@]}"
					fi

					if [[ ! -v  already_processed["$con_id"]  ]]; then
						echo Somehow this \'close\' never had an \'open\'...aborting...
						continue   # for we in "${we_array[@]}"
					fi

					
					opw=${outputwidth["$con_id"]}
					oph=${outputheight["$con_id"]}
					opx=${outputx["$con_id"]}
					opy=${outputy["$con_id"]}

					echo \(i.m.: ${ignore_me["$con_id"]}\)  \(x: new:$event_win_x : old:${orig_win_x["$con_id"]}\)  \(y: new:$event_win_y : old:${orig_win_y["$con_id"]}\)
					echo outputwidth of "$con_id" is: $opw     outputheight of "$con_id" is: $oph
					echo outputx of "$con_id" is: $opx
					echo outputy of "$con_id" is: $opy
					echo ws_x of "$con_id" is: ${ws_x["$con_id"]}
					echo ws_y of "$con_id" is: ${ws_y["$con_id"]}
					echo win_deco_height is: ${win_deco_height["$con_id"]}
# we here get the window x/y positions relative to the output's x/y
					rel_x=$(("$event_win_x"-"$opx"))
					rel_y=$(("$event_win_y"-"$opy"))
					echo rel_x= \'"$rel_x"\'       rel_y= \'"$rel_y"\'
					if [[ ($rel_x -ge 0 ) ]]; then echo rel_x IS GE 0; else echo rel_x IS NOT GE 0; fi
					if [[ ($rel_y -ge 0 ) ]]; then echo rel_y IS GE 0; else echo rel_y IS NOT GE 0; fi
					if [[ ($rel_x -lt $opw) ]]; then echo rel_x IS LT outputwidth;  else echo rel_x IS NOT LT outputwidth; fi
					if [[ ($rel_y -lt $oph) ]]; then echo rel_y IS LT outputheight; else echo rel_y IS NOT LT outputheight; fi


					if [[ (${ignore_me["$con_id"]} == "no") &&
							(($event_win_x != ${orig_win_x["$con_id"]}) || ($event_win_y != ${orig_win_y["$con_id"]})) &&
							(($rel_x -ge 0 )   && ($rel_y -ge 0 )) &&
							(($rel_x -lt $opw) && ($rel_y -lt $oph)) ]]; then

# We WERE offsetting by ws_x/ws_y and win_deco_height, Currently, only ws_y and win-deco-height seem not to be non-zero, but ...
# Actually, ws_x seems on other outputs to be non-zero, and equal to the opx, so , so we do NOT want to offset by ws_x...
# I STILL do not know why ws_y seems to be universally "38", as my bar height is set to "20" ("14" on laptop)

						xperc=$(echo "$rel_x / $opw * 100" | bc -l)
						xperc=$(echo "scale=$scale; ($xperc + $round) / 1" | bc -l)

# With my new percentage system, the window's position at close equals its position when next open, EXCEPT for border="normal"
# windows, whose x position is as saved, but y position is too low by 27, which is win_deco_height.  So BEFORE calculating percentages,
# we will subtract win_deco_height from the ypos.  win_deco_height is zero, except for "normal" windows, so we can do it for all windows.
						rel_y=$(("$rel_y"-"${win_deco_height["$con_id"]}"))
						yperc=$(echo "$rel_y / $oph * 100" | bc -l)
						yperc=$(echo "scale=$scale; ($yperc + $round) / 1" | bc -l)

						echo xperc: $xperc,  yperc: $yperc
						file="$winpath""$event_win_name"
						echo  $xperc  $yperc > "$file"
						result=$?
						if [[ "$result" != 0 ]]; 	then
							notify-send "Could not save window \"$event_win_name\" position.";
						else
							notify-send "Window \"$event_win_name\" position saved."

							if [[ "$event_type" == "close" ]]; then
								echo window \"$event_win_name\" - position saved.
								echo Making new/changed "for_window"  for \'"$event_win_name"\' ...
								echo wn before: \'"$event_win_name"\'        xperc= \'"$xperc"\'  yperc= \'"$yperc"\'
								event_win_name="$(escape_bad_chars_in_winname "$event_win_name")"
								echo wn after:  \'"$event_win_name"\'
								fw_event_win_name="$caret""$event_win_name""$dollar"	# make sure title begins and ends with winname, not just contains it

								datestr="$(date +%Y%m%d:%H%M%S:%N)"	# format (+) date as "nanoseconds (000000000..999999999)" (%N)
								mark="fmwd_""$datestr"
								swaymsg_output=$(swaymsg -- for_window \[title=$doublequote$fw_event_win_name$doublequote\] mark "$mark")
								result=$?
								if [[ "$result" != 0 ]]; then
									echo Window \'"$event_win_name"\':  for_window mark "$mark" fails with message: \'"$swaymsg_output"\'
								fi
								swaymsg_output=$(swaymsg -- for_window \[title=$doublequote$fw_event_win_name$doublequote\] exec "$move_window_script_path/fwmd-move_window.sh $mark $xperc $yperc  >> $LOGS/$(date +"%Y%m%d:%H%M%S_")${winname}_$mark.log 2>&1")
								result=$?
								if [[ "$result" != 0 ]]; then
									echo Window \'"$event_win_name"\':  for_window exec move_window_script fails with message: \'"$swaymsg_output"\'
								fi
							else
								echo originally-tiled window \"$event_win_name\" - position saved.
							fi
						fi	# file write successful ?
					else
					  notify-send "Window \"$event_win_name\" ignored (or not moved)."
					  echo Nothing changed here for \'"$event_win_name"\', or we are ignoring it, or it is offscreen.
					fi  # ignore?/unchanged?/off-screen?

					unset_arrays

					;;


		 	 	*)
 	 	
		  			;;
			esac  # "$event_type"
			
			echo
			
		done  # for  we in "${we_array[@]}"
		
		((i+="$num_events"))
		
	done  # while true - inner loop - read from we_file until num_events == 0
	
	echo nothing to read, so we go to sleep with inotifywait

	inotifywait -e modify "$inw_file"
done  # while true - inotifywait

exit 0	# probably never reached, but ...

############################
doublequote=\"
caret=$'^'
dollar=$'$'
#	winname="$(escape_bad_chars_in_winname "$winname")"
	winname="blork"
	fw_winname="$caret""$winname""$dollar"	# make sure title begins and ends with winname, not just contains it
	
	datestr="$(date +%Y%m%d:%H%M%S:%N)"	# format (+) date as "nanoseconds (000000000..999999999)" (%N)
	mark="fmwd_""$datestr"
	echo winname=\'"$winname"\'
	redir="$LOGS/$(date +"%Y%m%d:%H%M%S_")${winname}_$mark.log"
	echo redir=\'"$redir"\'
str="for_window \[title=$doublequote$fw_winname$doublequote\] exec $move_window_script_path/fwmd-move_window.sh $mark $xperc $yperc > $redir 2>&1"
echo str= \'"$str"\'
perl -E 'say shift'  "$str"
