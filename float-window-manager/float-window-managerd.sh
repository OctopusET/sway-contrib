#!/usr/bin/env bash

# $HOME/.local/bin/float-window-managerd.sh

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


version=$(swaymsg -t get_version | jq -r '.human_readable')
if [[ "$version" < "1.6" ]]; then
	echo This version of Sway is earlier than supports moving windows with percentages.
	echo Version is \'"$version"\'. Version needed: \'1.6\'.
	exit 1
fi


winpath="$HOME/.config/sway/float_window_store/"
[ -d "$winpath" ] || mkdir -p -v "$winpath"	# " -p no error if existing, make parent directories as needed"

# https://stackoverflow.com/questions/15783701/which-characters-need-to-be-escaped-when-using-bash
doublequote=\"
singlequote=\'
# I noticed that the GIMP main window ends with '– GIMP', where the dash is not '-'. but '–', so I have added it to "special", in case it's a problem for regexp
special=$'`!@#$%^&*()-–_+={}|[]\\;\:,.<>?/ '$doublequote$singlequote		# featherpad's syntax highlighting seems to get messed up with these actual quotes in the special string...
backslash=$'\\'

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
	unset orig_win_x["$con_id"]
	unset orig_win_y["$con_id"]
	unset ws_x["$con_id"]
	unset ws_y["$con_id"]
	unset win_deco_height["$con_id"]
	unset ignore_me["$con_id"]
	echo Arrays unset...
}

# Make a Sway for_window  rule for each file in $winpath, using the filename as title, and the contents as x and y percentages
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
		echo winname= \'"$winname"\' --\> \"Ignore Me\"
		continue
	fi
	if [[ ( ("$xperc" != "") && ("$yperc" != "") ) &&
			( ! ("$xperc" =~ ^[+-]?[0-9]{1,2}$) && ("$yperc" =~ ^[+-]?[0-9]{1,2}$) )  ]]; then	# sign (or not) plus 1-2 digits
		echo Window \'"$winname"\' has invalid percentage[s]. Ignoring.
		continue
	fi
	if [[ ( "$xperc" -lt 0 ) || ( "$xperc" -gt 100 ) || ( "$yperc" -lt 0 ) || ( "$yperc" -gt 100 ) ]]; then 
		echo Window \'"$winname"\' has percentage[s] outside 0-100. Ignoring.
		continue
	fi

	winname="$(escape_bad_chars_in_winname "$winname")"

	swaymsg_output=$(swaymsg -- for_window \[title="$doublequote$winname$doublequote"\] "move position "$xperc" ppt "$yperc" ppt")
	result=$?
#	"swaymsg_output" is always non-blank, as a jq result with {  "success": true  } is printed if we are successful.
	if [[ ! "$result" == 0 ]]; then
		echo Window \'"$winname"\':  for_window fails with message: \'"$swaymsg_output"\'
	fi
done




declare -i  con_id  opw  oph
declare -a  PIDarray  we_array  outputwidth  outputheight orig_win_x  orig_win_y  ignore_me
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

#PS=$(pgrep -f -d ' ' "float-window-placement[0-9]*d.sh")  #instead of \n, -d elimit with a space.
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
			
			# $con.name is sometimes null, and messes up the read; we change null to bogus name here, and will deal with it later...
			IFS=$'\t' read -r event_type  con_id  event_win_name  event_win_type  event_win_x  event_win_y  \
						  < <(echo "$we"  | jq -r '. as $root | 
											$root.container as $con | [$root.change, $con.id, $con.name // "NuLlnUlLNuLlnUlL",
											$con.type, $con.rect.x, $con.rect.y]  | @tsv ')

			event_win_name=${event_win_name//NuLlnUlLNuLlnUlL/}

			if [[ "$event_type" == "floating" ]]; then
				if [[ "$event_win_type" == "floating_con" ]]; then
					event_type="to_floating"
					echo event_type "floating" ---> "to_floating"
				else 
					event_type="to_tiling"
					echo event_type "floating" ---> "to_tiling"
				fi
			else
				# handle a closed originally-tiling window as if it reverted to tiling
				if [[ ("$event_type" == "close") && ("${was_tiling["$con_id"]}" == "yes") ]]; then
					event_type="to_tiling"
					echo event_type "close" ---> "to_tiling"
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
					IFS=$'\t' read -r  win_name  win_type  win_x  win_y  win_deco_height  ws_name  ws_x  ws_y  output_width  output_height < <(swaymsg -t get_tree |  \
						jq -r --arg CONID "$con_id" '. as $root | $root.nodes[] as $output | $output.nodes[] as $ws |
						$ws.floating_nodes[] as $win | select ( $win.id == ($CONID | tonumber) ) | 
						[$win.name // "NuLlnUlLNuLlnUlL", $win.type, $win.rect.x, $win.rect.y, $win.deco_rect.height, $ws.name,
						 $ws.rect.x, $ws.rect.y, $output.rect.width, $output.rect.height] | @tsv')
					result=$?
					if [[ "$result" != 0 ]]; then
						echo result=\'"$result"\'  ...apparently window matching con_id=\'"$con_id"\' is not floating  -  aborting this event...
						unset_arrays
						continue  # for we in "${we_array[@]}"
					fi
					win_name=${win_name//NuLlnUlLNuLlnUlL/}		# change bogus "name" back into empty string
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
									( ("$xperc" =~ ^[+-]?[0-9]{1,2}$) && ("$yperc" =~ ^[+-]?[0-9]{1,2}$) )  ]]; then	# sign (or not) plus 1-2 digits
								if [[ ( "$xperc" -ge 0 ) || ( "$xperc" -le 100 ) || ( "$yperc" -ge 0 ) || ( "$yperc" -le 100 ) ]]; then 
									echo  '---> percentages present and valid.'
									if [[ "$event_type" == "to_floating" ]]; then	# we have to move the window ourselves.
										swaymsg_output=$(swaymsg -- \[con_id=$con_id\] "move position "$xperc" ppt "$yperc" ppt")
										result=$?
#			"swaymsg_output" is always non-blank, as a jq result with {  "success": true  } is printed if we are successful.
										if [[ "$result" != 0 ]]; then
											echo Window \'"$wn"\':  \"move position\" fails with message: \'"$swaymsg_output"\'
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
						echo 'Not a floating-con...'
						continue   # for we in "${we_array[@]}"
					fi
					
					opw=${outputwidth["$con_id"]}
					oph=${outputheight["$con_id"]}
					
					echo \(i.m.: ${ignore_me["$con_id"]}\)  \(x: new:$event_win_x : old:${orig_win_x["$con_id"]}\)  \(y: new:$event_win_y : old:${orig_win_y["$con_id"]}\)
					echo outputwidth of "$con_id" is: $opw     outputheight of "$con_id" is: $oph
					if [[ ($event_win_x -ge 0 ) ]]; then echo event-win-x IS GE 0; else echo event-win-x IS NOT GE 0; fi
					if [[ ($event_win_y -ge 0 ) ]]; then echo event-win-y IS GE 0; else echo event-win-y IS NOT GE 0; fi
					if [[ ($event_win_x -lt $opw) ]]; then echo event-win-x IS LT outputwidth;  else echo event-win-x IS NOT LT outputwidth; fi
					if [[ ($event_win_y -lt $oph) ]]; then echo event-win-y IS LT outputheight; else echo event-win-y IS NOT LT outputheight; fi


					if [[ (${ignore_me["$con_id"]} == "no") &&
							(($event_win_x != ${orig_win_x["$con_id"]}) || ($event_win_y != ${orig_win_y["$con_id"]})) &&
							(($event_win_x -ge 0 )   && ($event_win_y -ge 0 )) &&
							(($event_win_x -lt $opw) && ($event_win_y -lt $oph)) ]]; then

#NOTE: We now store percentage as 0-100 so we multiply by 100, and round to the nearest pixel by adding .5 and truncating ("scale=0")
# We have to do scale=4, and then take the result and do scale=0 to truncate, as bc won't do it all in one, for some reason... 
# (and won't do scale=0 if no division in calc, so " / 1")

# sway does not use the whole output width/height when it performs its percentage window placement, but offsets by the workspace x/y 
# and deco-rect height.  Currently, only ws_y and win-deco-height seem not to be non-zero, but ...

						opw_m_wsx=$(echo "$opw-${ws_x["$con_id"]}" | bc -l)
						xperc=$(echo "scale=4; $event_win_x / $opw_m_wsx * 100 + .5" | bc -l)
						xperc=$(echo "scale=0; $xperc / 1" | bc -l)

						oph_m_wsy_m_wdh=$(echo "($oph-${ws_y["$con_id"]})-${win_deco_height["$con_id"]}" | bc -l)
						yperc=$(echo "scale=4; $event_win_y / $oph_m_wsy_m_wdh * 100 + .5" | bc -l)
						yperc=$(echo "scale=0; $yperc / 1" | bc -l)
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

								swaymsg_output=$(swaymsg -- for_window \[title="$doublequote$event_win_name$doublequote"\] "move position "$xperc" ppt "$yperc" ppt")
								result=$?
#		"swaymsg_output" is always non-blank, as a jq result with {  "success": true  } is printed if we are successful.
								if [[ "$result" != 0 ]]; then
									echo Window \'"$event_win_name"\':  for_window fails with message: \'"$swaymsg_output"\'
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

