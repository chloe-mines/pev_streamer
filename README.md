# Race Streamer System - Setup and Usage Guide

## Installation

To get this system working on your Mac, follow the steps below carefully.

### 1. Install Homebrew
If you don’t already have [Homebrew](https://brew.sh/), open Terminal and run:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Follow the on-screen instructions to finish installation.
### 2. Install Python3 with Homebrew
```bash
brew install python
```

This gives you `python3` and `pip3`.
### 3. Create and Activate a Virtual Environment (Recommended)
```bash
python3 -m venv venv
source venv/bin/activate
```

### 4. Install Required Python Packages
Install the following using pip:
```bash
pip install bleak asyncio
```

These libraries are used for Bluetooth lap monitor integration. You’ll also need:
```python
import asyncio, json, binascii, datetime as dt, time, os
from typing import Optional
from bleak import BleakScanner, BleakClient
```

### 5. Install FFmpeg and Playwright
```bash
brew install ffmpeg
brew install pipx
pipx install playwright
playwright install
```

OR....

just run the install.sh script ;-)

## Using the System

### Step 1: Do you want to include **Live Lap Monitor Times**?
If yes:
1. **Start a LapMonitor session using the official app.**
2. Begin the race from the app as normal (choose your duration, racers, etc).
3. Once the race has started, **fully close the LapMonitor app on your phone or tablet** (not just hide it).
4. In Terminal, run:

```bash
python3 hijack_lapmonitor.py
```

This script will now start collecting real-time lap data.
---



If you **do not need LapMonitor integration**, or have already completed the above:



### Step 2: Start a Camera Stream
1. In Terminal, run:

```bash
./stream.sh
```

2. You’ll be shown a list of available **cameras and microphones**.
3. Select your desired video and audio input by number.
4. Then, choose a resolution.
5. Your video stream with lap times and overlays will now start and be pushed to the configured RTMP (e.g., NGINX) endpoint.

> **Repeat these steps in a new terminal tab** for each additional camera stream you want to push.

---

This project uses only **free and open source** tools and is intended to be easy to use for the PEV racing community.
