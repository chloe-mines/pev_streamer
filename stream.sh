#!/bin/bash

# Exact copy of your working configuration but with dynamic device selection
# This should work since it mirrors the exact settings that work for you

# RTMP configuration
RSTP_IP="xxx.xxx.xxx.xxx"
RSTP_Port="1935"
RSTP_Target="live/cam0_overlay"

#Riders
RIDER_22="Luke"  
IMAGE_22="images/22.jpg"
RIDER_33="Anakin"
IMAGE_33="images/33.jpg"
RIDER_79="Ventress"
IMAGE_79="images/79.jpg"

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
  if [[ "$VIDEO_INDEX" =~ ^[0-9]+$ ]]; then break; fi
  echo "Please enter a valid number."
done

VIDEO_NAME="${VIDEO_DEVICES[$VIDEO_INDEX]}"
AUDIO_NAME="${AUDIO_DEVICES[$AUDIO_INDEX]}"

# Force to 1920x1080 to match your working example exactly
VIDEO_RES="1920x1080"
echo "Using resolution: $VIDEO_RES (matching your working config)"

echo ""
echo "Checking /tmp/laptimes.txt..."
if [ ! -f /tmp/laptimes.txt ]; then
  echo "Creating missing /tmp/laptimes.txt..."
  touch /tmp/laptimes.txt
fi

echo ""
echo "Starting ffmpeg stream - EXACT copy of your working settings..."

ffmpeg \
  -f avfoundation \
  -framerate 30 \
  -pixel_format nv12 \
  -video_size "$VIDEO_RES" \
  -probesize 100M \
  -i "$VIDEO_INDEX:$AUDIO_INDEX" \
  -i images/22.jpg \
  -i images/33.jpg \
  -i images/79.jpg \
  -i images/esra.png \
  -i images/overlay_box.png \
  -filter_complex "
    [5:v]scale=iw*1.0:ih[bg_wide];
    [bg_wide]format=rgba[bg];
    [0:v][bg]overlay=80:60[tmp1];
    [4:v]scale=60:60,format=rgba,colorchannelmixer=aa=0.5[esra_watermark];
    [1:v]scale=24:24[icon22_scaled];
    [2:v]scale=24:24[icon33_scaled];
    [3:v]scale=24:24[icon79_scaled];
    [icon22_scaled]pad=26:26:1:1:black[icon22];
    [icon33_scaled]pad=26:26:1:1:black[icon33];
    [icon79_scaled]pad=26:26:1:1:black[icon79];
    [tmp1][icon22]overlay=100:120[tmp2];
    [tmp2][icon33]overlay=100:142[tmp3];
    [tmp3][icon79]overlay=100:164[tmp4];
    [tmp4][esra_watermark]overlay=main_w-overlay_w-20:main_h-overlay_h-20[tmp5];
    [tmp5]drawtext=
         fontfile=/System/Library/Fonts/Supplemental/Helvetica.ttc:
         textfile=/tmp/laptimes.txt:
         reload=1:
         x=135:y=120:
         fontsize=16:
         fontcolor=white:
         shadowcolor=black:
         shadowx=2:
         shadowy=2:
         line_spacing=6:
         box=0
  " \
  -c:v libx264 \
  -preset veryfast \
  -profile:v main \
  -level 4.2 \
  -pix_fmt yuv420p \
  -g 60 -keyint_min 60 -sc_threshold 0 \
  -force_key_frames "expr:gte(t,n_forced*2)" \
  -b:v 3500k -maxrate 3500k -bufsize 7000k \
  -x264opts vbv-init=0.9 \
  -fps_mode cfr \
  -c:a aac -b:a 128k -ar 44100 -ac 2 \
  -f flv "rtmp://$RSTP_IP:$RSTP_Port/$RSTP_Target"
