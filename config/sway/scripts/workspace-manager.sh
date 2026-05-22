#!/bin/bash

# █░█░█ █▀█ █▀█ █▄▀ █▀ █▀█ ▄▀█ █▀▀ █▀▀
# ▀▄▀▄▀ █▄█ █▀▄ █▀▄ ▄█ █▀▀ █▀█ █▄▄ ██▄
# ==========================================================

# Dependency Check
if ! command -v jq &> /dev/null; then
    notify-send "Error" "Install 'jq' first: sudo pacman -S jq"
    exit 1
fi

# --- FUNCTION 1: GAP FILLING (Organize Sequence) ---
gap_fill() {
    # Get workspace list, sort numerically, and rename if there are number gaps
    existing_workspaces=$(swaymsg -t get_workspaces | jq -r '.[].num' | sort -n)
    counter=1

    for ws in $existing_workspaces; do
        if [ "$ws" -ne "$counter" ]; then
            swaymsg rename workspace number "$ws" to "$counter"
        fi
        ((counter++))
    done
}

# --- FUNCTION 2: NAVIGATION (Next/Prev) ---
navigate() {
    DIRECTION=$1
    # Ensure workspaces are organized before switching
    gap_fill 
    
    current_ws=$(swaymsg -t get_workspaces | jq '.[] | select(.focused==true).num')
    target_ws=$current_ws

    if [ "$DIRECTION" == "next" ]; then
        target_ws=$((current_ws + 1))
    elif [ "$DIRECTION" == "prev" ]; then
        if [ "$current_ws" -gt 1 ]; then
            target_ws=$((current_ws - 1))
        else
            target_ws=1
        fi
    fi
    
    swaymsg workspace number "$target_ws"
}

# --- FUNCTION 3: WATCHER (Daemon) ---
watch_mode() {
    # Kill old instances to prevent duplicates
    pkill -f "swaymsg -t subscribe -m \[\"workspace\"\]"
    
    # Listen to workspace events, then run gap_fill
    swaymsg -t subscribe -m '["workspace"]' | while read -r event; do
        gap_fill
    done
}

# --- MAIN EXECUTION LOGIC ---
case "$1" in
    "watch")
        watch_mode
        ;;
    "next")
        navigate "next"
        ;;
    "prev")
        navigate "prev"
        ;;
    *)
        gap_fill
        ;;
esac
