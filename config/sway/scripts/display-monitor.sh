#!/bin/bash

# █▀▄ █ █▀ █▀█ █░░ ▄▀█ █▄█
# █▄▀ █ ▄█ █▀▀ █▄▄ █▀█ ░█░
# ==========================================================
# Adapted from sway display-monitor.sh → use swaymsg & Rofi Applet

# --- CONFIGURATION ---
LAPTOP="eDP-1"       
EXTERNAL="HDMI-A-1"

# Notification ID (Arbitrary unique number to replace previous notification)
NOTIF_ID="1005"
TIMEOUT="3000"

# --- NOTIFICATION FUNCTION (OSD STYLE) ---
send_notif() {
    notify-send -r "$NOTIF_ID" -t "$TIMEOUT" \
    -h string:x-canonical-private-synchronous:display \
    -u low -i video-display "$1"
}

# --- MODES LOGIC ---
apply_mode() {
    case "$1" in
        "💻 Laptop Only")
            swaymsg output "$EXTERNAL" disable
            swaymsg output "$LAPTOP" enable
            send_notif "Mode: Laptop Only"
            ;;
        "📽️ Projector Only")
            swaymsg output "$LAPTOP" disable
            swaymsg output "$EXTERNAL" enable resolution 1920x1080
            send_notif "Mode: Projector Only (1080p)"
            ;;
        "🖥️ Extend (Dual)")
            swaymsg output "$LAPTOP" enable
            swaymsg output "$EXTERNAL" enable pos 1920 0 resolution 1920x1080
            send_notif "Mode: Extended Display"
            ;;
        "🪞 Mirror (Clone)")
            # Mirroring in Sway = Putting both screens at pos 0 0 with same res
            swaymsg output "$LAPTOP" enable resolution 1920x1080 pos 0 0
            swaymsg output "$EXTERNAL" enable resolution 1920x1080 pos 0 0
            send_notif "Mode: Mirror / Clone"
            ;;
        *)
            # Do nothing if cancelled
            exit 0
            ;;
    esac
}

# --- ROFI APPLET CONFIGURATION ---
if [ -f "$HOME/.config/rofi/applets/shared/theme.bash" ]; then
    source "$HOME"/.config/rofi/applets/shared/theme.bash
    theme="$type/$style"
fi

# Theme Elements
prompt="Display Mode"
mesg="Select a display configuration"

if [ -n "$theme" ] && [ -f "$theme" ]; then
    if [[ "$theme" == *'type-1'* ]]; then
        list_col='1'
        list_row='4'
        win_width='400px'
    elif [[ "$theme" == *'type-3'* ]]; then
        list_col='1'
        list_row='4'
        win_width='120px'
    elif [[ "$theme" == *'type-5'* ]]; then
        list_col='1'
        list_row='4'
        win_width='425px'
    elif [[ ( "$theme" == *'type-2'* ) || ( "$theme" == *'type-4'* ) ]]; then
        list_col='4'
        list_row='1'
        win_width='550px'
    fi

    # Options
    layout=$(cat "${theme}" | grep 'USE_ICON' | cut -d'=' -f2)
    if [[ "$layout" == 'NO' ]]; then
        option_1="💻 Laptop Only"
        option_2="📽️ Projector Only"
        option_3="🖥️ Extend (Dual)"
        option_4="🪞 Mirror (Clone)"
    else
        option_1="💻"
        option_2="📽️"
        option_3="🖥️"
        option_4="🪞"
    fi

    rofi_cmd() {
        rofi -theme-str "window {width: $win_width;}" \
            -theme-str "listview {columns: $list_col; lines: $list_row;}" \
            -theme-str 'textbox-prompt-colon {str: "🖥️";}' \
            -dmenu \
            -p "$prompt" \
            -mesg "$mesg" \
            -markup-rows \
            -theme "${theme}"
    }
else
    # Fallback if theme doesn't exist
    option_1="💻 Laptop Only"
    option_2="📽️ Projector Only"
    option_3="🖥️ Extend (Dual)"
    option_4="🪞 Mirror (Clone)"
    
    rofi_cmd() {
        rofi -dmenu -i -p 'Display Mode' -theme-str 'window {width: 25%;}'
    }
fi

# Pass options to rofi dmenu
run_rofi() {
    echo -e "$option_1\n$option_2\n$option_3\n$option_4" | rofi_cmd
}

choice="$(run_rofi)"

# --- EXECUTION ---
case "$choice" in
    *"Laptop Only"*|*"💻"*)
        apply_mode "💻 Laptop Only"
        ;;
    *"Projector Only"*|*"📽️"*)
        apply_mode "📽️ Projector Only"
        ;;
    *"Extend"*|*"🖥️"*)
        apply_mode "🖥️ Extend (Dual)"
        ;;
    *"Mirror"*|*"🪞"*)
        apply_mode "🪞 Mirror (Clone)"
        ;;
esac
