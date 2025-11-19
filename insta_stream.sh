#!/bin/bash

# Exact copy of your working configuration but with dynamic device selection
# This should work since it mirrors the exact settings that work for you

# RTMP configuration
RSTP_IP="xxx.xxx.xxx.xxx"
RSTP_Port="1935"
RSTP_Target="live/cam0_overlay"

# Rider name mapping - device number to name
declare -A RIDER_NAMES=(
  [79]="Aaron Watson"
  [38]="Jeff Cameron (EUC)"
  [33]="Matthew Kwan"
  [41]="Shai Moffatt"
  [22]="Simon Franklin"
)

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

VIDEO_NAME="${VIDEO_DEVICES[$VIDEO_INDEX]}"
if [ "$AUDIO_INDEX" = "n" ]; then
  AUDIO_NAME="NO AUDIO"
  FFMPEG_INPUT="-i \"$VIDEO_INDEX\""
  AUDIO_CODEC=""
else
  AUDIO_NAME="${AUDIO_DEVICES[$AUDIO_INDEX]}"
  FFMPEG_INPUT="-i \"$VIDEO_INDEX:$AUDIO_INDEX\""
  AUDIO_CODEC="-c:a aac -b:a 128k -ar 44100 -ac 2"
fi

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
echo "Checking /tmp/laptimes.txt..."
if [ ! -f /tmp/laptimes.txt ]; then
  echo "Creating missing /tmp/laptimes.txt..."
  touch /tmp/laptimes.txt
fi

# Get all unique device numbers from RIDER_NAMES (sorted)
ALL_DEVICES=($(printf '%s\n' "${!RIDER_NAMES[@]}" | sort -n | uniq))

echo "Found ${#ALL_DEVICES[@]} total riders configured"

# Build arrays for all riders
IMAGE_INPUTS=()
DEVICE_NUMS=()

for device_num in "${ALL_DEVICES[@]}"; do
  if [ -f "images/$device_num.jpg" ]; then
    IMAGE_INPUTS+=("$device_num")
    DEVICE_NUMS+=("$device_num")
    echo "Found: images/$device_num.jpg (${RIDER_NAMES[$device_num]:-Unknown})"
  else
    IMAGE_INPUTS+=("unknown")
    DEVICE_NUMS+=("$device_num")
    echo "Warning: images/$device_num.jpg not found, using unknown.jpg (${RIDER_NAMES[$device_num]:-Unknown})"
  fi
done

echo "Will display ${#IMAGE_INPUTS[@]} rider icons"

echo ""
echo "Starting ffmpeg stream with all riders..."

# Generate timestamp for recording filename
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RECORD_FILE="/Volumes/ESRA_FOOTAGE/race_stream_$TIMESTAMP.mp4"

# Set up trap to handle Ctrl-C gracefully
cleanup() {
  echo ""
  echo "Stopping stream gracefully..."
  # Send 'q' to ffmpeg to quit properly
  echo q
  sleep 2
  echo "Stream stopped. Recording should be playable."
  exit 0
}
trap cleanup SIGINT SIGTERM

if [ "$AUDIO_INDEX" = "n" ]; then
  echo "Streaming VIDEO ONLY (no audio)"
  
  # Build the input file list
  INPUT_ARGS="-i $VIDEO_INDEX"
  for img in "${IMAGE_INPUTS[@]}"; do
    INPUT_ARGS="$INPUT_ARGS -i images/$img.jpg"
  done
  INPUT_ARGS="$INPUT_ARGS -i images/esra.png -i images/overlay_box.png"
  
  # Calculate input indices
  ESRA_IDX=$((${#IMAGE_INPUTS[@]} + 1))
  BOX_IDX=$((${#IMAGE_INPUTS[@]} + 2))
  
  # Build filter complex dynamically
  FILTER_COMPLEX="[${BOX_IDX}:v]scale=iw*1.0:ih*1.8[bg_wide];[bg_wide]format=rgba[bg];[0:v][bg]overlay=80:120[tmp1];[${ESRA_IDX}:v]scale=60:60,format=rgba,colorchannelmixer=aa=0.5[esra_watermark];[${ESRA_IDX}:v]scale=40:40,format=rgba[esra_header];"
  
  # Add icon scaling for each rider
  for i in "${!IMAGE_INPUTS[@]}"; do
    input_idx=$((i + 1))
    FILTER_COMPLEX="${FILTER_COMPLEX}[${input_idx}:v]scale=24:24[icon${i}_scaled];[icon${i}_scaled]pad=26:26:1:1:black[icon${i}];"
  done
  
  # Add overlays for header and icons
  FILTER_COMPLEX="${FILTER_COMPLEX}[tmp1][esra_header]overlay=160:135[tmp2];"
  
  Y_POS=180
  prev_tmp="tmp2"
  for i in "${!IMAGE_INPUTS[@]}"; do
    next_tmp="tmp$((i + 3))"
    FILTER_COMPLEX="${FILTER_COMPLEX}[${prev_tmp}][icon${i}]overlay=100:${Y_POS}[${next_tmp}];"
    Y_POS=$((Y_POS + 22))
    prev_tmp="$next_tmp"
  done
  
  # Add watermark and text
  final_tmp="$prev_tmp"
  text_tmp="tmp$((${#IMAGE_INPUTS[@]} + 3))"
  
  if [ "$RECORD_STREAM" = "y" ]; then
    split_tmp="tmp$((${#IMAGE_INPUTS[@]} + 4))"
    FILTER_COMPLEX="${FILTER_COMPLEX}[${final_tmp}][esra_watermark]overlay=main_w-overlay_w-20:main_h-overlay_h-20[${text_tmp}];[${text_tmp}]drawtext=fontfile=/System/Library/Fonts/Supplemental/Helvetica.ttc:textfile=/tmp/laptimes.txt:reload=1:x=135:y=180:fontsize=16:fontcolor=white:shadowcolor=black:shadowx=2:shadowy=2:line_spacing=6:box=0[${split_tmp}];[${split_tmp}]split=2[out1][out2]"
  else
    FILTER_COMPLEX="${FILTER_COMPLEX}[${final_tmp}][esra_watermark]overlay=main_w-overlay_w-20:main_h-overlay_h-20[${text_tmp}];[${text_tmp}]drawtext=fontfile=/System/Library/Fonts/Supplemental/Helvetica.ttc:textfile=/tmp/laptimes.txt:reload=1:x=135:y=180:fontsize=16:fontcolor=white:shadowcolor=black:shadowx=2:shadowy=2:line_spacing=6:box=0"
  fi
  
  if [ "$RECORD_STREAM" = "y" ]; then
    echo "Also recording DIRECTLY to: $RECORD_FILE"
    ffmpeg \
      -f avfoundation \
      -framerate 30 \
      -pixel_format nv12 \
      -video_size "$VIDEO_RES" \
      -probesize 100M \
      $INPUT_ARGS \
      -filter_complex "$FILTER_COMPLEX" \
      -map "[out1]" \
      -c:v libx264 \
      -preset fast \
      -profile:v baseline \
      -level 3.1 \
      -pix_fmt yuv420p \
      -r 30 \
      -g 30 -keyint_min 15 \
      -b:v 2500k -maxrate 2500k -bufsize 5000k \
      -x264opts "keyint=30:min-keyint=15:no-scenecut" \
      -fps_mode cfr \
      -f flv "rtmp://$RSTP_IP:$RSTP_Port/$RSTP_Target" \
      -map "[out2]" \
      -c:v libx264 \
      -preset fast \
      -profile:v baseline \
      -level 3.1 \
      -pix_fmt yuv420p \
      -r 30 \
      -g 30 -keyint_min 15 \
      -b:v 2500k -maxrate 2500k -bufsize 5000k \
      -x264opts "keyint=30:min-keyint=15:no-scenecut" \
      -fps_mode cfr \
      -movflags +frag_keyframe+empty_moov+default_base_moof \
      -f mp4 "$RECORD_FILE"
  else
    ffmpeg \
      -f avfoundation \
      -framerate 30 \
      -pixel_format nv12 \
      -video_size "$VIDEO_RES" \
      -probesize 100M \
      $INPUT_ARGS \
      -filter_complex "$FILTER_COMPLEX" \
      -c:v libx264 \
      -preset fast \
      -profile:v baseline \
      -level 3.1 \
      -pix_fmt yuv420p \
      -r 30 \
      -g 30 -keyint_min 15 \
      -b:v 2500k -maxrate 2500k -bufsize 5000k \
      -x264opts "keyint=30:min-keyint=15:no-scenecut" \
      -fps_mode cfr \
      -an \
      -f flv "rtmp://$RSTP_IP:$RSTP_Port/$RSTP_Target"
  fi
else
  echo "Streaming with audio: $AUDIO_NAME"
  
  # Build the input file list
  INPUT_ARGS="-i $VIDEO_INDEX:$AUDIO_INDEX"
  for img in "${IMAGE_INPUTS[@]}"; do
    INPUT_ARGS="$INPUT_ARGS -i images/$img.jpg"
  done
  INPUT_ARGS="$INPUT_ARGS -i images/esra.png -i images/overlay_box.png"
  
  # Calculate input indices
  ESRA_IDX=$((${#IMAGE_INPUTS[@]} + 1))
  BOX_IDX=$((${#IMAGE_INPUTS[@]} + 2))
  
  # Build filter complex (same as above)
  FILTER_COMPLEX="[${BOX_IDX}:v]scale=iw*1.0:ih*1.8[bg_wide];[bg_wide]format=rgba[bg];[0:v][bg]overlay=80:120[tmp1];[${ESRA_IDX}:v]scale=60:60,format=rgba,colorchannelmixer=aa=0.5[esra_watermark];[${ESRA_IDX}:v]scale=40:40,format=rgba[esra_header];"
  
  for i in "${!IMAGE_INPUTS[@]}"; do
    input_idx=$((i + 1))
    FILTER_COMPLEX="${FILTER_COMPLEX}[${input_idx}:v]scale=24:24[icon${i}_scaled];[icon${i}_scaled]pad=26:26:1:1:black[icon${i}];"
  done
  
  FILTER_COMPLEX="${FILTER_COMPLEX}[tmp1][esra_header]overlay=160:135[tmp2];"
  
  Y_POS=180
  prev_tmp="tmp2"
  for i in "${!IMAGE_INPUTS[@]}"; do
    next_tmp="tmp$((i + 3))"
    FILTER_COMPLEX="${FILTER_COMPLEX}[${prev_tmp}][icon${i}]overlay=100:${Y_POS}[${next_tmp}];"
    Y_POS=$((Y_POS + 22))
    prev_tmp="$next_tmp"
  done
  
  final_tmp="$prev_tmp"
  text_tmp="tmp$((${#IMAGE_INPUTS[@]} + 3))"
  
  if [ "$RECORD_STREAM" = "y" ]; then
    split_tmp="tmp$((${#IMAGE_INPUTS[@]} + 4))"
    FILTER_COMPLEX="${FILTER_COMPLEX}[${final_tmp}][esra_watermark]overlay=main_w-overlay_w-20:main_h-overlay_h-20[${text_tmp}];[${text_tmp}]drawtext=fontfile=/System/Library/Fonts/Supplemental/Helvetica.ttc:textfile=/tmp/laptimes.txt:reload=1:x=135:y=180:fontsize=16:fontcolor=white:shadowcolor=black:shadowx=2:shadowy=2:line_spacing=6:box=0[${split_tmp}];[${split_tmp}]split=2[out1][out2]"
  else
    FILTER_COMPLEX="${FILTER_COMPLEX}[${final_tmp}][esra_watermark]overlay=main_w-overlay_w-20:main_h-overlay_h-20[${text_tmp}];[${text_tmp}]drawtext=fontfile=/System/Library/Fonts/Supplemental/Helvetica.ttc:textfile=/tmp/laptimes.txt:reload=1:x=135:y=180:fontsize=16:fontcolor=white:shadowcolor=black:shadowx=2:shadowy=2:line_spacing=6:box=0"
  fi
  
  if [ "$RECORD_STREAM" = "y" ]; then
    echo "Also recording DIRECTLY to: $RECORD_FILE"
    ffmpeg \
      -f avfoundation \
      -framerate 30 \
      -pixel_format nv12 \
      -video_size "$VIDEO_RES" \
      -probesize 100M \
      $INPUT_ARGS \
      -filter_complex "$FILTER_COMPLEX" \
      -map "[out1]" -map "0:a" \
      -c:v libx264 \
      -preset fast \
      -profile:v baseline \
      -level 3.1 \
      -pix_fmt yuv420p \
      -r 30 \
      -g 30 -keyint_min 15 \
      -b:v 2500k -maxrate 2500k -bufsize 5000k \
      -x264opts "keyint=30:min-keyint=15:no-scenecut" \
      -fps_mode cfr \
      -c:a aac -b:a 128k -ar 44100 -ac 2 \
      -f flv "rtmp://$RSTP_IP:$RSTP_Port/$RSTP_Target" \
      -map "[out2]" -map "0:a" \
      -c:v libx264 \
      -preset fast \
      -profile:v baseline \
      -level 3.1 \
      -pix_fmt yuv420p \
      -r 30 \
      -g 30 -keyint_min 15 \
      -b:v 2500k -maxrate 2500k -bufsize 5000k \
      -x264opts "keyint=30:min-keyint=15:no-scenecut" \
      -fps_mode cfr \
      -c:a aac -b:a 128k -ar 44100 -ac 2 \
      -movflags +frag_keyframe+empty_moov+default_base_moof \
      -f mp4 "$RECORD_FILE"
  else
    ffmpeg \
      -f avfoundation \
      -framerate 30 \
      -pixel_format nv12 \
      -video_size "$VIDEO_RES" \
      -probesize 100M \
      $INPUT_ARGS \
      -filter_complex "$FILTER_COMPLEX" \
      -c:v libx264 \
      -preset fast \
      -profile:v baseline \
      -level 3.1 \
      -pix_fmt yuv420p \
      -r 30 \
      -g 30 -keyint_min 15 \
      -b:v 2500k -maxrate 2500k -bufsize 5000k \
      -x264opts "keyint=30:min-keyint=15:no-scenecut" \
      -fps_mode cfr \
      -c:a aac -b:a 128k -ar 44100 -ac 2 \
      -f flv "rtmp://$RSTP_IP:$RSTP_Port/$RSTP_Target"
  fi
fi