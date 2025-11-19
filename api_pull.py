import requests
import time
import json

API_URL = "https://xxxxxxxx.com/get_rankings.php"
OUTPUT_FILE = "/tmp/laptimes.txt"

def fetch_and_write_rankings():
    try:
        # Fetch data from API
        response = requests.get(API_URL)
        response.raise_for_status()
        rankings = response.json()
        
        # Sort by id (device number) to match icon order in stream
        rankings_sorted = sorted(rankings, key=lambda x: x['id'])
        
        # Format and write to file
        with open(OUTPUT_FILE, 'w') as f:
            for entry in rankings_sorted:
                name = entry['name']
                time_seconds = entry['timeMS'] / 1000  # Convert ms to seconds
                
                line = f"{name}: Best: {time_seconds:.3f}s\n"
                f.write(line)
        
        print(f"Updated {OUTPUT_FILE} with {len(rankings_sorted)} entries")
        
    except Exception as e:
        print(f"Error: {e}")

# Run continuously every 15 seconds
while True:
    fetch_and_write_rankings()
    
    # Countdown display
    for remaining in range(15, 0, -1):
        print(f"Next update in {remaining} seconds...", end='\r')
        time.sleep(1)
    print()  # New line after countdown
