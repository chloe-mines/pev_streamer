#!/bin/bash

echo "Starting Race Streamer System installation..."

# Step 1: Install Homebrew if not installed
if ! command -v brew &> /dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo "Homebrew already installed."
fi

# Step 2: Install Python3
echo "Installing Python3..."
brew install python

# Step 3: Create and activate virtual environment
echo "Creating virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Step 4: Install Python dependencies
echo "Installing Python dependencies..."
pip install bleak asyncio

# Step 5: Install FFmpeg and Playwright
echo "Installing FFmpeg and Playwright..."
brew install ffmpeg
brew install pipx
pipx install playwright
playwright install

echo "Installation complete."
