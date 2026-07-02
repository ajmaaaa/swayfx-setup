#!/usr/bin/env python3
import subprocess
import json
import sys
import threading
import time

# Prevent concurrent modifications of workspaces
lock = threading.Lock()

# Workspace ranges for each monitor
DEFAULT_DEFINED = {
    "eDP-1": [1, 2, 3, 4, 5],
    "HDMI-A-1": [6, 7, 8, 9, 10]
}

def gap_fill():
    if not lock.acquire(blocking=False):
        return
    try:
        # Give Sway state a brief moment to update after event
        time.sleep(0.05)
        
        # Get workspaces
        res = subprocess.run(["swaymsg", "-t", "get_workspaces"], capture_output=True, text=True)
        if res.returncode != 0:
            return
        
        try:
            workspaces = json.loads(res.stdout)
        except Exception:
            return

        # Group workspaces by output (monitor name)
        output_workspaces = {}
        for ws in workspaces:
            output = ws.get("output")
            num = ws.get("num")
            if output and num is not None and num > 0:
                if output not in output_workspaces:
                    output_workspaces[output] = []
                output_workspaces[output].append(num)

        # Reorder workspaces on each output
        for output, occupied_nums in output_workspaces.items():
            occupied_nums.sort()
            defined_ids = DEFAULT_DEFINED.get(output)
            if not defined_ids:
                # If unknown output, dynamically assign defined_ids based on active workspaces
                defined_ids = list(range(occupied_nums[0], occupied_nums[0] + len(occupied_nums)))
            
            for i, old_num in enumerate(occupied_nums):
                if i < len(defined_ids):
                    new_num = defined_ids[i]
                else:
                    new_num = defined_ids[-1] + (i - len(defined_ids) + 1)
                
                if old_num != new_num:
                    # Rename the workspace
                    subprocess.run(["swaymsg", "rename", "workspace", "number", str(old_num), "to", str(new_num)], capture_output=True)
    except Exception as e:
        print(f"Error in gap_fill: {e}", file=sys.stderr)
    finally:
        lock.release()

def navigate(direction):
    gap_fill()
    res = subprocess.run(["swaymsg", "-t", "get_workspaces"], capture_output=True, text=True)
    if res.returncode != 0:
        return
    try:
        workspaces = json.loads(res.stdout)
    except Exception:
        return
    
    current_ws = None
    for ws in workspaces:
        if ws.get("focused"):
            current_ws = ws.get("num")
            break
            
    if current_ws is None:
        return
        
    target_ws = current_ws
    if direction == "next":
        target_ws = current_ws + 1
    elif direction == "prev":
        if current_ws > 1:
            target_ws = current_ws - 1
        else:
            target_ws = 1
            
    subprocess.run(["swaymsg", "workspace", "number", str(target_ws)], capture_output=True)

def watch_mode():
    # Kill old instances of watch mode
    subprocess.run(["pkill", "-f", "swaymsg -t subscribe"], capture_output=True)
    
    # Do an initial cleanup
    gap_fill()
    
    # Subscribe to workspace events
    proc = subprocess.Popen(["swaymsg", "-t", "subscribe", '["workspace"]'], stdout=subprocess.PIPE, text=True)
    while True:
        line = proc.stdout.readline()
        if not line:
            break
        # Trigger reordering when a workspace event occurs
        threading.Thread(target=gap_fill).start()

def main():
    if len(sys.argv) < 2:
        gap_fill()
        sys.exit(0)
        
    mode = sys.argv[1]
    if mode == "watch":
        watch_mode()
    elif mode == "next":
        navigate("next")
    elif mode == "prev":
        navigate("prev")
    else:
        gap_fill()

if __name__ == "__main__":
    main()
