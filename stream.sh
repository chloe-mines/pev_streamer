#!/bin/bash

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
echo "Select audio input:"
for i in "${!AUDIO_DEVICES[@]}"; do
  echo "  [$i] ${AUDIO_DEVICES[$i]}"
done
while true; do
  read -p "Enter audio device index: " AUDIO_INDEX
  if [[ "$AUDIO_INDEX" =~ ^[0-9]+$ ]]; then break; fi
  echo "Please enter a valid number."
done

VIDEO_NAME="${VIDEO_DEVICES[$VIDEO_INDEX]}"
AUDIO_NAME="${AUDIO_DEVICES[$AUDIO_INDEX]}"

echo ""
echo "Choose video resolution:"
RES_OPTIONS=("1920x1080" "1280x720" "1280x1024" "1024x768" "640x480")
for i in "${!RES_OPTIONS[@]}"; do
  echo "  [$i] ${RES_OPTIONS[$i]}"
done
read -p "Enter resolution option index: " RES_INDEX
VIDEO_RES="${RES_OPTIONS[$RES_INDEX]}"


echo ""
echo "Checking /tmp/laptimes.txt..."
if [ ! -f /tmp/laptimes.txt ]; then
  echo "Creating missing /tmp/laptimes.txt..."
  touch /tmp/laptimes.txt
fi

echo ""
echo "Starting ffmpeg stream with camera $VIDEO_INDEX, mic $AUDIO_INDEX, resolution $VIDEO_RES..."

ffmpeg \
  -f avfoundation \
  -framerate 30 \
  -video_size 1280x720 \
  -i "0:0" \
  -i images/tas_circle.png \
  -i images/esra.png \
  -i images/overlay_box.png \
  -filter_complex "
    [3:v]format=rgba[bg];
    [0:v][bg]overlay=80:60[tmp1];
    [1:v]scale=32:32[icon];
    [tmp1][icon]overlay=90:120[tmp2];
    [tmp2]drawtext=
         fontfile=/System/Library/Fonts/Supplemental/Helvetica.ttc:
         textfile=/tmp/laptimes.txt:
         reload=1:
         x=130:y=120:
         fontsize=18:
         fontcolor=white:
         shadowcolor=black:
         shadowx=2:
         shadowy=2:
         box=0
  " \
  -c:v libx264 \
  -preset veryfast \
  -profile:v baseline \
  -level 3.0 \
  -pix_fmt yuv420p \
  -g 60 -keyint_min 60 -sc_threshold 0 \
  -force_key_frames "expr:gte(t,n_forced*2)" \
  -b:v 2000k -maxrate 2000k -bufsize 4000k \
  -vsync cfr \
  -c:a aac -b:a 128k -ar 44100 -ac 2 \
 -f flv "rtmp://$RSTP_IP:$RSTP_Port/$RSTP_Target"
