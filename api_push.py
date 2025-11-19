#!/usr/bin/env python3
"""
Extract best lap times from laplogs.txt
Parses lap time logs and finds the fastest lap for each device/rider.
Runs continuously, updating every 20 seconds.
"""

import re
import os
import requests
import json
import threading
import time
import sys
from typing import Dict, Optional

# API configuration
API_KEY = "3WSY-2E4K-XA7D-45ST-V52K-JW1V"
API_URL = "https://electricracing.life/api.php"

# Global flag to control the main loop
running = True

def parse_lap_time(time_str: str) -> Optional[int]:
    """
    Parse lap time string like '0:25.199' or '1:23.456' into milliseconds
    Returns None if parsing fails
    """
    try:
        # Match format like "0:25.199" or "1:23.456"
        match = re.match(r'^(\d+):(\d{2})\.(\d{3})$', time_str)
        if not match:
            return None
        
        minutes = int(match.group(1))
        seconds = int(match.group(2))
        milliseconds = int(match.group(3))
        
        total_ms = (minutes * 60 * 1000) + (seconds * 1000) + milliseconds
        return total_ms
    except (ValueError, AttributeError):
        return None

def format_lap_time(ms: int) -> str:
    """Convert milliseconds back to readable format like '0:25.199'"""
    minutes = ms // (60 * 1000)
    remaining_ms = ms % (60 * 1000)
    seconds = remaining_ms // 1000
    milliseconds = remaining_ms % 1000
    return f"{minutes}:{seconds:02d}.{milliseconds:03d}"

def extract_best_times(log_file: str) -> Dict[str, int]:
    """
    Extract best lap times for each device from the log file
    Returns dict of {device_name: best_time_ms}
    """
    best_times = {}
    
    if not os.path.exists(log_file):
        print(f"Log file {log_file} not found!")
        return best_times
    
    with open(log_file, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            
            # Parse line format: "2025-10-04T20:47:02.048 Aaron | Lap 24 | Lap Time 0:25.199 | ..."
            try:
                # Split by first space to separate timestamp from the rest
                parts = line.split(' ', 1)
                if len(parts) < 2:
                    continue
                
                timestamp = parts[0]
                rest = parts[1]
                
                # Find the device/rider name (everything before the first " | Lap")
                lap_split = rest.split(' | Lap ')
                if len(lap_split) < 2:
                    continue
                
                device_name = lap_split[0]
                
                # Extract lap time using regex
                lap_time_match = re.search(r'Lap Time (\d+:\d{2}\.\d{3})', rest)
                if not lap_time_match:
                    continue
                
                lap_time_str = lap_time_match.group(1)
                lap_time_ms = parse_lap_time(lap_time_str)
                
                if lap_time_ms is None:
                    print(f"Warning: Could not parse lap time '{lap_time_str}' on line {line_num}")
                    continue
                
                # Update best time for this device
                if device_name not in best_times or lap_time_ms < best_times[device_name]:
                    best_times[device_name] = lap_time_ms
                    
            except Exception as e:
                print(f"Warning: Error parsing line {line_num}: {e}")
                continue
    
    return best_times

def send_best_times_to_api(best_times: Dict[str, int]) -> bool:
    """
    Send best lap times to the API
    Returns True if successful, False otherwise
    """
    try:
        # Prepare data for API
        api_data = []
        for device_name, time_ms in best_times.items():
            # Extract device number if it's in "Device X" format, otherwise use the full name
            device_id = device_name
            if device_name.startswith("Device "):
                try:
                    device_id = int(device_name.replace("Device ", ""))
                except ValueError:
                    # If conversion fails, use the original name
                    device_id = device_name
            
            api_data.append({
                "device": device_id,
                "best_time_ms": time_ms,
                "best_time_formatted": format_lap_time(time_ms)
            })
        
        payload = {
            "api_key": API_KEY,
            "action": "submit_best_times",
            "data": api_data
        }
        
        print("\nSending best times to API...")
        response = requests.post(API_URL, json=payload, timeout=30)
        
        if response.status_code == 200:
            print("Successfully sent best times to API")
            try:
                response_data = response.json()
                if "message" in response_data:
                    print(f"API Response: {response_data['message']}")
            except json.JSONDecodeError:
                print(f"API Response: {response.text}")
            return True
        else:
            print(f"API request failed with status {response.status_code}")
            print(f"Response: {response.text}")
            return False
            
    except requests.exceptions.RequestException as e:
        print(f"Error sending to API: {e}")
        return False
    except Exception as e:
        print(f"Unexpected error: {e}")
        return False

def monitor_user_input():
    """Monitor for user input to stop the program"""
    global running
    while running:
        try:
            user_input = input().strip().lower()
            if user_input in ['q', 'quit', 'stop', 'exit']:
                print("\nStopping race streamer...")
                running = False
                break
        except (EOFError, KeyboardInterrupt):
            print("\nStopping race streamer...")
            running = False
            break

def process_lap_times():
    """Process lap times once - extracted from main for reuse"""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    log_file = os.path.join(script_dir, "laplogs.txt")
    
    best_times = extract_best_times(log_file)
    
    if not best_times:
        print("No lap times found in the log file.")
        return False
    
    # Sort by lap time (fastest first)
    sorted_times = sorted(best_times.items(), key=lambda x: x[1])
    
    print(f"\n{'Rank':<4} {'Device/Rider':<15} {'Best Lap Time':<12}")
    print("-" * 35)
    
    for rank, (device_name, time_ms) in enumerate(sorted_times, 1):
        formatted_time = format_lap_time(time_ms)
        print(f"{rank:<4} {device_name:<15} {formatted_time:<12}")
    
    print("-" * 35)
    print(f"Total devices/riders: {len(best_times)}")
    
    if sorted_times:
        fastest_device, fastest_time = sorted_times[0]
        print(f"Fastest overall: {fastest_device} with {format_lap_time(fastest_time)}")
    
    # Send results to API
    return send_best_times_to_api(best_times)

def main():
    """Main function to continuously extract and send best lap times"""
    global running
    
    print("Race Streamer - Continuous Best Lap Time Monitor")
    print("=" * 55)
    print("Updates every 20 seconds")
    print("Type 'q', 'quit', 'stop', or 'exit' to stop")
    print("Starting continuous monitoring...")
    print("=" * 55)
    
    # Start the input monitor thread
    input_thread = threading.Thread(target=monitor_user_input, daemon=True)
    input_thread.start()
    
    cycle_count = 0
    
    try:
        while running:
            cycle_count += 1
            current_time = time.strftime("%Y-%m-%d %H:%M:%S")
            print(f"\nCycle #{cycle_count} - {current_time}")
            print("-" * 50)
            
            try:
                process_lap_times()
            except Exception as e:
                print(f"Error processing lap times: {e}")
            
            # Countdown timer for next run
            if running:
                print(f"\nNext update in: ", end="", flush=True)
                for seconds_remaining in range(20, 0, -1):
                    if not running:
                        break
                    
                    # Clear the countdown and show new value
                    print(f"\rNext update in: {seconds_remaining:2d} seconds", end="", flush=True)
                    time.sleep(1)
                
                # Clear the countdown line when done
                if running:
                    print(f"\rNext update in:  0 seconds - Running now!", flush=True)
                
    except KeyboardInterrupt:
        print("\nStopping race streamer...")
        running = False
    
    print("Race streamer stopped. Goodbye!")

if __name__ == "__main__":
    main()
