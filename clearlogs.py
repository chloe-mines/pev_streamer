import os
import shutil
from datetime import datetime

# Get the directory where this script is located
script_dir = os.path.dirname(os.path.abspath(__file__))
log_file = os.path.join(script_dir, "laplogs.txt")

# Archive existing file if present
if os.path.exists(log_file) and os.path.getsize(log_file) > 0:
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    archive_name = f"{timestamp}_laplogs.txt"
    archive_path = os.path.join(script_dir, archive_name)
    shutil.move(log_file, archive_path)
    print(f"Archived existing log to {archive_path}")
else:
    print(f"No existing log to archive at {log_file}")

# Create an empty laplogs.txt
with open(log_file, "w") as f:
    pass

print(f"Cleared {log_file}")
