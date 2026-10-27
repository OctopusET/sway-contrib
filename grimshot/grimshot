#!/bin/sh

## Grimshot: a helper for screenshots within sway
## Requirements:
##  - `grim`: screenshot utility for wayland
##  - `slurp`: to select an area
##  - `swaymsg`: to read properties of current window
##  - `wl-copy`: clipboard utility
##  - `jq`: json utility to parse swaymsg output
##  - `notify-send`: to show notifications
##  - `xdg-open`: optional, to open saved files from notifications
##  - `wayfreeze`: optional, to freeze displays with --freeze
## Those are needed to be installed, if unsure, run `grimshot check`
##
## See `man 1 grimshot` or `grimshot usage` for further details.

# Override standard echo to avoid confusing errors if, for example, a user
# provides options like "-w -n" to the program.
echo() {
  printf '%s\n' "$*"
}

NOTIFY=no
CURSOR=
FREEZE=no
WAIT=no

getTargetDirectory() {
  # The environment takes precedence over user-dirs.dirs, per variable.
  screenshots=$XDG_SCREENSHOTS_DIR
  pictures=$XDG_PICTURES_DIR
  test -f "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs" &&
    . "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"

  echo "${screenshots:-${XDG_SCREENSHOTS_DIR:-${pictures:-${XDG_PICTURES_DIR:-$HOME}}}}"
}

parseArgs() {
  # Count down instead of "for arg" so that -w can consume its value.
  n=$#
  while [ "$n" -gt 0 ]; do
    arg=$1
    shift
    n=$((n - 1))
    case "$arg" in
    -n | --notify)
      NOTIFY=yes
      ;;
    -c | --cursor)
      CURSOR=yes
      ;;
    -f | --freeze)
      FREEZE=yes
      ;;
    -w | --wait)
      WAIT=
      if [ "$n" -gt 0 ]; then
        WAIT="$1"
        shift
        n=$((n - 1))
      fi
      if echo "$WAIT" | grep -q "[^0-9]"; then
        echo "invalid value for wait '$WAIT'" >&2
        exit 3
      fi
      WAIT=${WAIT:-no}
      ;;
    *)                   # Treat anything else as a positional argument
      set -- "$@" "$arg" # Re-append to arguments.
      ;;
    esac
  done

  ACTION=${1:-usage}
  SUBJECT=${2:-screen}
  if [ -n "$GRIMSHOT_FILENAME_FORMAT" ]; then
    FILENAME=$(date +"$GRIMSHOT_FILENAME_FORMAT")
  else
    FILENAME=$(date -Ins)
  fi
  FILE=${3:-$(getTargetDirectory)/$FILENAME.png}

}

printUsageMsg() {
  echo "Usage:"
  echo "  grimshot [--notify] [--cursor] [--freeze] [--wait N] (copy|save) [active|screen|output|area|window|anything] [FILE|-]"
  echo "  grimshot check"
  echo "  grimshot usage"
  echo ""
  echo "Commands:"
  echo "  copy: Copy the screenshot data into the clipboard."
  echo "  save: Save the screenshot to a regular file or '-' to pipe to STDOUT."
  echo "  savecopy: Save the screenshot to a regular file and copy the data into the clipboard."
  echo "  check: Verify if required tools are installed and exit."
  echo "  usage: Show this message and exit."
  echo ""
  echo "Targets:"
  echo "  active: Currently active window."
  echo "  screen: All visible outputs."
  echo "  output: Currently active output."
  echo "  area: Manually select a region."
  echo "  window: Manually select a window."
  echo "  anything: Manually select an area, window, or output."
  exit
}

notify() {
  notify-send -t 3000 -a grimshot "$@"
}

# --action implies --wait, so run detached to not block the caller.
notifyWithActions() {
  (
    action=$(notify-send -t 3000 -a grimshot --action=file='Open File' --action=dir='Open Directory' "$@")
    case "$action" in
    file) xdg-open "$FILE" ;;
    dir) xdg-open "$(dirname "$FILE")" ;;
    esac
  ) </dev/null >/dev/null 2>&1 &
}

notifyOk() {
  notify_disabled='[ "$NOTIFY" = "no" ]'

  if eval $notify_disabled; then
    return
  fi

  TITLE=${2:-"Screenshot"}
  MESSAGE=${1:-"OK"}

  if [ "$ACTION" = "save" ] || [ "$ACTION" = "savecopy" ]; then
    if [ "$FILE" != "-" ] && command -v xdg-open >/dev/null 2>&1 &&
      notify-send --help 2>/dev/null | grep -q -- --action; then
      notifyWithActions "$TITLE" "$MESSAGE" -i "$FILE"
    else
      notify "$TITLE" "$MESSAGE" -i "$FILE"
    fi
  else
    notify "$TITLE" "$MESSAGE"
  fi
}

notifyError() {
  TITLE=${2:-"Screenshot"}
  errorMssg=$1
  MESSAGE=${errorMssg:-"Error taking screenshot with grim"}

  if [ "$NOTIFY" = "yes" ]; then
    notify "$TITLE" "$MESSAGE" -u critical
  else
    echo "$errorMssg"
  fi
}

die() {
  MSG=${1:-Bye}
  notifyError "Error: $MSG"
  exit 2
}

check() {
  COMMAND=$1

  if command -v "$COMMAND" > /dev/null 2>&1; then
    RESULT="OK"
  else
    RESULT="NOT FOUND"
  fi

  echo "   $COMMAND: $RESULT"
}

takeScreenshot() {
  FILE=$1
  GEOM=$2
  OUTPUT=$3

  if [ -n "$OUTPUT" ]; then
    grim ${CURSOR:+-c} -o "$OUTPUT" "$FILE" || die "Unable to invoke grim"
  elif [ -z "$GEOM" ]; then
    grim ${CURSOR:+-c} "$FILE" || die "Unable to invoke grim"
  else
    grim ${CURSOR:+-c} -g "$GEOM" "$FILE" || die "Unable to invoke grim"
  fi
}

checkRequiredTools() {
  echo "Checking if required tools are installed. If something is missing, install it to your system and make it available in PATH..."
  check grim
  check slurp
  check swaymsg
  check wl-copy
  check jq
  check notify-send
  check xdg-open
  check wayfreeze
  exit
}

selectArea() {
  GEOM=$(slurp -d)
  [ -z "$GEOM" ] && exit 1
  WHAT="Area"
}

selectActiveWindow() {
  FOCUSED=$(swaymsg -t get_tree | jq -r 'recurse(.nodes[]?, .floating_nodes[]?) | select(.focused)')
  GEOM=$(echo "$FOCUSED" | jq -r '.rect | "\(.x),\(.y) \(.width)x\(.height)"')
  APP_ID=$(echo "$FOCUSED" | jq -r '.app_id')
  WHAT="$APP_ID window"
}

selectScreen() {
  GEOM=""
  WHAT="Screen"
}

selectOutput() {
  GEOM=""
  OUTPUT=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused)' | jq -r '.name')
  WHAT="$OUTPUT"
}

selectWindow() {
  GEOM=$(swaymsg -t get_tree | jq -r '.. | select(.pid? and .visible?) | .rect | "\(.x),\(.y) \(.width)x\(.height)"' | slurp -r)
  [ -z "$GEOM" ] && exit 1
  WHAT="Window"
}

selectAnything() {
  GEOM=$(swaymsg -t get_tree | jq -r '.. | select(.pid? and .visible?) | .rect | "\(.x),\(.y) \(.width)x\(.height)"' | slurp -o)
  [ -z "$GEOM" ] && exit 1
  WHAT="Selection"
}

handleSaveCopy() {
  wl-copy --type image/png <"$FILE" || die "Clipboard error"
  MESSAGE="$MESSAGE and clipboard"
}

handleScreenshotSuccess() {
  TITLE="Screenshot of $SUBJECT"
  MESSAGE=$(basename "$FILE")
  [ "$ACTION" = "savecopy" ] && handleSaveCopy
  notifyOk "$MESSAGE" "$TITLE"
  echo "$FILE"
}

handleScreenshotFailure() {
  notifyError "Error taking screenshot with grim"
}

handleCopy() {
  takeScreenshot - "$GEOM" "$OUTPUT" | wl-copy --type image/png || die "Clipboard error"
  notifyOk "$WHAT copied to clipboard"
}

handleSave() {
  if takeScreenshot "$FILE" "$GEOM" "$OUTPUT"; then
    handleScreenshotSuccess
  else
    handleScreenshotFailure
  fi
}

handleUnknownSubject() {
  die "Unknown subject to take a screenshot from" "$SUBJECT"
}

handleFreeze() {
  command -v wayfreeze >/dev/null 2>&1 || die "wayfreeze not found"
  if [ -z "$CURSOR" ]; then
    notCursor="--hide-cursor"
  fi
  # Must not hold the caller's stdio open, e.g. $(grimshot save area) or "save area -".
  wayfreeze $notCursor </dev/null >/dev/null 2>&1 &
  FREEZE_PID=$!
  trap 'kill $FREEZE_PID 2>/dev/null' EXIT
  trap 'exit 1' HUP INT TERM
  sleep .1;
}

handleScreenshot() {
  case "$ACTION" in
    check)
      checkRequiredTools ;;
    save | copy | savecopy) : ;; # nothing
    *)
      printUsageMsg ;;
  esac

  [ "$FREEZE" != "no" ] && handleFreeze

  case "$SUBJECT" in
    area)
      selectArea ;;
    active)
      selectActiveWindow ;;
    screen)
      selectScreen ;;
    output)
      selectOutput ;;
    window)
      selectWindow ;;
    anything)
      selectAnything ;;
    *)
      handleUnknownSubject ;;
  esac

  [ "$WAIT" != "no" ] && sleep "$WAIT"

  if [ "$ACTION" = "copy" ]; then
    handleCopy
  else
    handleSave
  fi
}

parseArgs "$@"
handleScreenshot
