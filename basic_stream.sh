#!/bin/bash

# Basic streaming script - no overlays

# RTMP configuration
RSTP_IP="xxx.xxx.xxx.xxx"
RSTP_Port="1935"
RSTP_Target="live/cam0_overlay"

echo "RSTP_IP is: $RSTP_IP"
echo "RSTP_Port is: $RSTP_Port"
echo "RSTP_Target is: $RSTP_Target"

echo "Detecting available video and audio devices..."
DEVICE_LOG=$(mktemp)
ffmpeg -f avfoundation -list_devices true -i "" 2> "$DEVICE_LOG"

# Parse device list with careful filtering and formatting
VIDEO_DEVICES=()
AUDIO_DEVICES=()
parsing_video=false
parsing_audio=false
while IFS= read -r line; do
  # Clean leading/trailing whitespace and strip FFmpeg prefixes
  stripped=$(echo "$line" | sed -E 's/.*\] //' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  if [[ "$line" =~ AVFoundation\ video\ devices ]]; then
    parsing_video=true
    parsing_audio=false
  elif [[ "$line" =~ AVFoundation\ audio\ devices ]]; then
    parsing_video=false
    parsing_audio=true
  elif [[ "$line" =~ ^\[.*\] ]]; then
    if [ "$parsing_video" = true ]; then
      VIDEO_DEVICES+=("$stripped")
    elif [ "$parsing_audio" = true ]; then
      AUDIO_DEVICES+=("$stripped")
    fi
  fi
done < "$DEVICE_LOG"

echo ""
echo "Select video input:"
for i in "${!VIDEO_DEVICES[@]}"; do
  echo "  [$i] ${VIDEO_DEVICES[$i]}"
done
while true; do
  read -p "Enter video device index: " VIDEO_INDEX
  if [[ "$VIDEO_INDEX" =~ ^[0-9]+$ ]]; then break; fi
  echo "Please enter a valid number."
done

echo ""
echo "Select video resolution:"
RESOLUTIONS=("640x480" "800x600" "1024x768" "1280x720" "1920x1080" "2560x1440" "3840x2160")
RESOLUTION_NAMES=("VGA (640x480)" "SVGA (800x600)" "XGA (1024x768)" "HD (1280x720)" "Full HD (1920x1080)" "2K (2560x1440)" "4K (3840x2160)")
for i in "${!RESOLUTIONS[@]}"; do
  echo "  [$i] ${RESOLUTION_NAMES[$i]}"
done
while true; do
  read -p "Enter resolution index: " RES_INDEX
  if [[ "$RES_INDEX" =~ ^[0-9]+$ ]] && [ "$RES_INDEX" -lt "${#RESOLUTIONS[@]}" ]; then break; fi
  echo "Please enter a valid number (0-$((${#RESOLUTIONS[@]}-1)))."
done

VIDEO_RES="${RESOLUTIONS[$RES_INDEX]}"
echo "Selected resolution: ${RESOLUTION_NAMES[$RES_INDEX]}"

echo ""
echo "Select audio input:"
echo "  [n] NO AUDIO (video only - reduces bandwidth)"
for i in "${!AUDIO_DEVICES[@]}"; do
  echo "  [$i] ${AUDIO_DEVICES[$i]}"
done
while true; do
  read -p "Enter audio device index (or 'n' for no audio): " AUDIO_INDEX
  if [[ "$AUDIO_INDEX" == "n" ]] || [[ "$AUDIO_INDEX" =~ ^[0-9]+$ ]]; then break; fi
  echo "Please enter a valid number or 'n'."
done

# Check for recording option
RECORD_STREAM="no"
if [ -d "/Volumes/ESRA_FOOTAGE" ]; then
  echo ""
  echo "ESRA_FOOTAGE volume detected!"
  echo "Do you wish to record this stream?"
  echo "  [y] Yes - Record to /Volumes/ESRA_FOOTAGE"
  echo "  [n] No - Stream only"
  while true; do
    read -p "Record stream? (y/n): " RECORD_CHOICE
    if [[ "$RECORD_CHOICE" == "y" ]] || [[ "$RECORD_CHOICE" == "n" ]]; then
      RECORD_STREAM="$RECORD_CHOICE"
      break
    fi
    echo "Please enter 'y' or 'n'."
  done
fi

echo ""
echo "Starting basic stream (no overlays)..."

# Generate timestamp for recording filename
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RECORD_FILE="/Volumes/ESRA_FOOTAGE/race_stream_$TIMESTAMP.mp4"

# Set up trap to handle Ctrl-C gracefully
cleanup() {
  echo ""
  echo "Stopping stream gracefully..."
  echo q
  sleep 2
  echo "Stream stopped."
  exit 0
}
trap cleanup SIGINT SIGTERM

if [ "$AUDIO_INDEX" = "n" ]; then
  echo "Streaming VIDEO ONLY (no audio)"
  
  if [ "$RECORD_STREAM" = "y" ]; then
    echo "Also recording to: $RECORD_FILE"
    ffmpeg \
      -f avfoundation \
      -framerate 30 \
      -pixel_format nv12 \
      -video_size "$VIDEO_RES" \
      -i "$VIDEO_INDEX" \
      -c:v libx264 \
      -preset fast \
      -profile:v baseline \
      -level 3.1 \
      -pix_fmt yuv420p \
      -r 30 \
      -g 30 -keyint_min 15 \
      -b:v 2500k -maxrate 2500k -bufsize 5000k \
      -x264opts "keyint=30:min-keyint=15:no-scenecut" \
      -f flv "rtmp://$RSTP_IP:$RSTP_Port/$RSTP_Target" \
      -c:v libx264 \
      -preset fast \
      -profile:v baseline \
      -level 3.1 \
      -pix_fmt yuv420p \
      -r 30 \
      -g 30 -keyint_min 15 \
      -b:v 2500k -maxrate 2500k -bufsize 5000k \
      -x264opts "keyint=30:min-keyint=15:no-scenecut" \
      -movflags +frag_keyframe+empty_moov+default_base_moof \
      -f mp4 "$RECORD_FILE"
  else
    ffmpeg \
      -f avfoundation \
      -framerate 30 \
      -pixel_format nv12 \
      -video_size "$VIDEO_RES" \
      -i "$VIDEO_INDEX" \
      -c:v libx264 \
      -preset fast \
      -profile:v baseline \
      -level 3.1 \
      -pix_fmt yuv420p \
      -r 30 \
      -g 30 -keyint_min 15 \
      -b:v 2500k -maxrate 2500k -bufsize 5000k \
      -x264opts "keyint=30:min-keyint=15:no-scenecut" \
      -f flv "rtmp://$RSTP_IP:$RSTP_Port/$RSTP_Target"
  fi
else
  echo "Streaming with audio"
  
  if [ "$RECORD_STREAM" = "y" ]; then
    echo "Also recording to: $RECORD_FILE"
    ffmpeg \
      -f avfoundation \
      -framerate 30 \
      -pixel_format nv12 \
      -video_size "$VIDEO_RES" \
      -i "$VIDEO_INDEX:$AUDIO_INDEX" \
      -c:v libx264 \
      -preset fast \
      -profile:v baseline \
      -level 3.1 \
      -pix_fmt yuv420p \
      -r 30 \
      -g 30 -keyint_min 15 \
      -b:v 2500k -maxrate 2500k -bufsize 5000k \
      -x264opts "keyint=30:min-keyint=15:no-scenecut" \
      -c:a aac -b:a 128k -ar 44100 -ac 2 \
      -f flv "rtmp://$RSTP_IP:$RSTP_Port/$RSTP_Target" \
      -c:v libx264 \
      -preset fast \
      -profile:v baseline \
      -level 3.1 \
      -pix_fmt yuv420p \
      -r 30 \
      -g 30 -keyint_min 15 \
      -b:v 2500k -maxrate 2500k -bufsize 5000k \
      -x264opts "keyint=30:min-keyint=15:no-scenecut" \
      -c:a aac -b:a 128k -ar 44100 -ac 2 \
      -movflags +frag_keyframe+empty_moov+default_base_moof \
      -f mp4 "$RECORD_FILE"
  else
    ffmpeg \
      -f avfoundation \
      -framerate 30 \
      -pixel_format nv12 \
      -video_size "$VIDEO_RES" \
      -i "$VIDEO_INDEX:$AUDIO_INDEX" \
      -c:v libx264 \
      -preset fast \
      -profile:v baseline \
      -level 3.1 \
      -pix_fmt yuv420p \
      -r 30 \
      -g 30 -keyint_min 15 \
      -b:v 2500k -maxrate 2500k -bufsize 5000k \
      -x264opts "keyint=30:min-keyint=15:no-scenecut" \
      -c:a aac -b:a 128k -ar 44100 -ac 2 \
      -f flv "rtmp://$RSTP_IP:$RSTP_Port/$RSTP_Target"
  fi
fi