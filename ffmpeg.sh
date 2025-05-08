#!/bin/bash

# --- Input Parameters ---
IMAGE_FILE_PATH="$1"
AUDIO_DIR_PATH="$2"
LOG_DIR_PATH="$3"
INPUT_FOLDER_NAME="$4" # Used for temporary files
DURATION="$5"
USE_OVERLAY="$6"      # "yes" or "no"
OVERLAY_FILE_PATH="$7" # Required if USE_OVERLAY is "yes"
OS_TYPE="$8"          # "mac", "linux", "win"
VIDEO_ENCODER="$9"    # Optional: e.g., "libx264", "h264_videotoolbox"

# --- Validate Required Parameters ---
if [ -z "$IMAGE_FILE_PATH" ]; then
    echo "Error: Image file path (IMAGE_FILE_PATH) is required."
    exit 1
fi
if [ ! -f "$IMAGE_FILE_PATH" ]; then
    echo "Error: Image file not found at '$IMAGE_FILE_PATH'."
    exit 1
fi

if [ -z "$AUDIO_DIR_PATH" ]; then
    echo "Error: Audio directory path (AUDIO_DIR_PATH) is required."
    exit 1
fi
if [ ! -d "$AUDIO_DIR_PATH" ]; then
    echo "Error: Audio directory not found at '$AUDIO_DIR_PATH'."
    exit 1
fi

if [ -z "$LOG_DIR_PATH" ]; then
    echo "Error: Log directory path (LOG_DIR_PATH) is required."
    exit 1
fi
# Attempt to create log directory if it doesn't exist
mkdir -p "$LOG_DIR_PATH"
if [ ! -d "$LOG_DIR_PATH" ]; then
    echo "Error: Could not create or find log directory at '$LOG_DIR_PATH'."
    exit 1
fi

if [ -z "$INPUT_FOLDER_NAME" ]; then
    echo "Error: Input folder name (INPUT_FOLDER_NAME) for temporary files is required."
    exit 1
fi

if [ -z "$USE_OVERLAY" ]; then
    echo "Error: USE_OVERLAY parameter ('yes' or 'no') is required."
    exit 1
fi

if [ "$USE_OVERLAY" = "yes" ] && [ -z "$OVERLAY_FILE_PATH" ]; then
    echo "Error: OVERLAY_FILE_PATH is required when USE_OVERLAY is 'yes'."
    exit 1
fi
if [ "$USE_OVERLAY" = "yes" ] && [ ! -f "$OVERLAY_FILE_PATH" ]; then
    echo "Error: Overlay file not found at '$OVERLAY_FILE_PATH'."
    exit 1
fi

if [ -z "$OS_TYPE" ]; then
    echo "Error: OS_TYPE ('mac', 'linux', 'win') is required."
    exit 1
fi
if [[ "$OS_TYPE" != "mac" && "$OS_TYPE" != "linux" && "$OS_TYPE" != "win" ]]; then
    echo "Error: Invalid OS_TYPE. Must be 'mac', 'linux', or 'win'."
    exit 1
fi

# Set video duration (default 4800 seconds)
if [ -z "$DURATION" ]; then
    DURATION=4800
fi

# --- Setup Temporary Directory & Log File ---
TMP_DIR="/tmp/$INPUT_FOLDER_NAME"
mkdir -p "$TMP_DIR/result"
LOG_FILE="$LOG_DIR_PATH/render_log.txt"

# Initialize log
echo "Video Render Log - $(date)" > "$LOG_FILE"
echo "----------------------------------------" >> "$LOG_FILE"
echo "Image File: $IMAGE_FILE_PATH" >> "$LOG_FILE"
echo "Audio Directory: $AUDIO_DIR_PATH" >> "$LOG_FILE"
echo "Log Directory: $LOG_DIR_PATH" >> "$LOG_FILE"
echo "Temp Directory: $TMP_DIR" >> "$LOG_FILE"
echo "Duration: $DURATION seconds" >> "$LOG_FILE"
echo "Use Overlay: $USE_OVERLAY" >> "$LOG_FILE"
if [ "$USE_OVERLAY" = "yes" ]; then
    echo "Overlay File: $OVERLAY_FILE_PATH" >> "$LOG_FILE"
fi
echo "OS Type: $OS_TYPE" >> "$LOG_FILE"
echo "Video Encoder (User Specified): ${VIDEO_ENCODER:-N/A}" >> "$LOG_FILE"
echo "----------------------------------------" >> "$LOG_FILE"
echo >> "$LOG_FILE"


# --- Determine Video Encoder and Preset ---
FFMPEG_VIDEO_ENCODER=""
FFMPEG_PRESET_ARGS=() # Array for preset arguments

if [ -n "$VIDEO_ENCODER" ]; then
    FFMPEG_VIDEO_ENCODER="$VIDEO_ENCODER"
    # Users might need to specify preset if they override encoder
    echo "Using user-specified video encoder: $FFMPEG_VIDEO_ENCODER" >> "$LOG_FILE"
    if [ "$FFMPEG_VIDEO_ENCODER" = "libx264" ]; then
        FFMPEG_PRESET_ARGS=("-preset" "medium")
    fi
    # For other user-specified encoders, we assume they know best or will add preset via other means
else
    case "$OS_TYPE" in
        "mac")
            # Check for videotoolbox support here if possible, otherwise default
            # For M3, h264_videotoolbox is preferred.
            # Add check 'ffmpeg -encoders | grep videotoolbox' later if needed
            FFMPEG_VIDEO_ENCODER="h264_videotoolbox"
            # videotoolbox has different quality/speed settings, e.g. -profile:v main -level:v 4.0 or -q:v 65
            # For simplicity, let's start without specific preset for videotoolbox
            # FFMPEG_PRESET_ARGS=("-profile:v" "main") # Example
            echo "OS is Mac. Defaulting to videotoolbox (h264_videotoolbox)." >> "$LOG_FILE"
            ;;
        "linux")
            FFMPEG_VIDEO_ENCODER="libx264"
            FFMPEG_PRESET_ARGS=("-preset" "medium")
            echo "OS is Linux. Defaulting to libx264 with medium preset." >> "$LOG_FILE"
            ;;
        "win")
            FFMPEG_VIDEO_ENCODER="libx264" # Safest default for Windows without hardware checks
            FFMPEG_PRESET_ARGS=("-preset" "medium")
            echo "OS is Windows. Defaulting to libx264 with medium preset." >> "$LOG_FILE"
            # Could later add checks for h264_qsv, h264_nvenc, h264_amf
            ;;
        *)
            echo "Error: Unknown OS_TYPE '$OS_TYPE'. Defaulting to libx264." >> "$LOG_FILE"
            FFMPEG_VIDEO_ENCODER="libx264"
            FFMPEG_PRESET_ARGS=("-preset" "medium")
            ;;
    esac
fi
echo "Selected FFMPEG Video Encoder: $FFMPEG_VIDEO_ENCODER" >> "$LOG_FILE"
if [ ${#FFMPEG_PRESET_ARGS[@]} -gt 0 ]; then
    echo "Selected FFMPEG Preset Args: ${FFMPEG_PRESET_ARGS[*]}" >> "$LOG_FILE"
fi
echo >> "$LOG_FILE"


# Create temporary lists for images and music
# Image is now a single file, no list needed for images.
find "$AUDIO_DIR_PATH" -maxdepth 1 -type f \( -iname "*.mp3" -o -iname "*.m4a" \) > "$TMP_DIR/audio.txt" 2>/dev/null

# Check if audio files were found
if [ ! -s "$TMP_DIR/audio.txt" ]; then
    echo "Error: No audio files found in $AUDIO_DIR_PATH." >> "$LOG_FILE"
    echo "Error: No audio files found in $AUDIO_DIR_PATH."
    exit 1
fi

# Clean up temporary files on exit
trap 'rm -f "$TMP_DIR/audio.txt" "$TMP_DIR/intro_video.mp4" "$TMP_DIR/loop_video.mp4"' EXIT


echo "Processing Video..." >> "$LOG_FILE"

# Create 1-second intro and loop videos from the image
INTRO_VIDEO="$TMP_DIR/intro_video.mp4"
LOOP_VIDEO="$TMP_DIR/loop_video.mp4"

echo "Creating 1-second intro video from $IMAGE_FILE_PATH..." >> "$LOG_FILE"
ffmpeg -y -loop 1 -i "$IMAGE_FILE_PATH" -c:v "$FFMPEG_VIDEO_ENCODER" "${FFMPEG_PRESET_ARGS[@]}" -r 30 -b:v 5000k -t 1 "$INTRO_VIDEO" >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to create intro video." >> "$LOG_FILE"
    exit 1
fi

echo "Creating loop video from $IMAGE_FILE_PATH..." >> "$LOG_FILE"
ffmpeg -y -loop 1 -i "$IMAGE_FILE_PATH" -c:v "$FFMPEG_VIDEO_ENCODER" "${FFMPEG_PRESET_ARGS[@]}" -r 30 -b:v 5000k -t 1 "$LOOP_VIDEO" >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to create loop video." >> "$LOG_FILE"
    exit 1
fi
echo "Successfully created intro and loop videos." >> "$LOG_FILE"


AUDIO_INPUTS=()
AUDIO_FILES_TO_DELETE=() # Not strictly needed anymore as we read from a list

# We'll take all audio files found for concatenation
AUDIO_BASENAMES=$(cat "$TMP_DIR/audio.txt")

if [ -z "$AUDIO_BASENAMES" ]; then
    echo "Error: No audio files listed in $TMP_DIR/audio.txt despite earlier check. This should not happen." >> "$LOG_FILE"
    exit 1
fi

# Convert the multiline string to an array of filenames
readarray -t SELECTED_AUDIO_BASENAMES <<< "$AUDIO_BASENAMES"

# Build the ffmpeg input arguments for audio
for audio_basename in "${SELECTED_AUDIO_BASENAMES[@]}"; do
    AUDIO_INPUTS+=("-i" "$audio_basename")
done

if [ ${#AUDIO_INPUTS[@]} -eq 0 ]; then
    echo "Warning: No audio inputs prepared for ffmpeg. Check audio files and $TMP_DIR/audio.txt." >> "$LOG_FILE"
    # Decide if this should be a fatal error
fi

OUTPUT_VIDEO="$TMP_DIR/result/final_video.mp4" # Simplified output name

echo "Number of audio files to concatenate: ${#SELECTED_AUDIO_BASENAMES[@]}" >> "$LOG_FILE"

if [ -n "$INTRO_VIDEO" ] && [ -f "$INTRO_VIDEO" ] && [ -n "$LOOP_VIDEO" ] && [ -f "$LOOP_VIDEO" ] && [ ${#AUDIO_INPUTS[@]} -gt 0 ]; then
    echo "Rendering $OUTPUT_VIDEO..." >> "$LOG_FILE"

    # Base ffmpeg command arguments
    ffmpeg_cmd=(
        ffmpeg -y
        -i "$INTRO_VIDEO"
        -i "$LOOP_VIDEO"
    )

    # Add overlay inputs if USE_OVERLAY is "yes"
    if [ "$USE_OVERLAY" = "yes" ]; then
        ffmpeg_cmd+=("-i" "$OVERLAY_FILE_PATH") # For the main overlay
        ffmpeg_cmd+=("-i" "$OVERLAY_FILE_PATH") # For the smaller scaled overlay
    fi

    # Add audio inputs
    ffmpeg_cmd+=("${AUDIO_INPUTS[@]}")

    # --- Build filter_complex string ---
    filter_complex_str=""
    video_streams_offset=2 # 0: intro, 1: loop
    audio_streams_offset=0 # This will be dynamic based on number of overlay inputs

    # Video chain: scale, pad, concat intro and loop
    filter_complex_str+="[0:v]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1:1[v0];"
    filter_complex_str+="[1:v]loop=loop=-1:size=10000,scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1:1[v1];"
    filter_complex_str+="[v0][v1]concat=n=2:v=1:a=0[mainv];"

    last_video_stream_label="[mainv]"

    if [ "$USE_OVERLAY" = "yes" ]; then
        # Overlay 1 (large, centered)
        filter_complex_str+="[${video_streams_offset}:v]loop=loop=-1:size=10000[ov1];"
        filter_complex_str+="${last_video_stream_label}[ov1]overlay=(main_w-overlay_w)/2:(main_h-overlay_h-20)[tempv];"
        last_video_stream_label="[tempv]"
        video_streams_offset=$((video_streams_offset + 1))

        # Overlay 2 (smaller, fixed position)
        filter_complex_str+="[${video_streams_offset}:v]scale=560:378[ov2];"
        filter_complex_str+="${last_video_stream_label}[ov2]overlay=120:120[outv];"
        last_video_stream_label="[outv]"
        # video_streams_offset is not incremented here as outv is the final video map
        audio_streams_offset=4 # After intro, loop, 2x overlay
    else
        filter_complex_str+="${last_video_stream_label}copy[outv];" # No overlay, just pass mainv to outv
        audio_streams_offset=2 # After intro, loop
    fi
    
    # Audio chain: concat all audio inputs twice
    audio_concat_inputs_str=""
    num_audio_files=${#SELECTED_AUDIO_BASENAMES[@]}
    for i in $(seq 0 $((num_audio_files - 1))); do
        audio_idx=$((audio_streams_offset + i))
        audio_concat_inputs_str+="[${audio_idx}:a]"
    done
    # Repeat the audio concatenation string to double the audio length (as in original script)
    # The original script had [4:a]...[13:a] then [4:a]...[13:a] meaning 10 audio inputs repeated.
    # This now dynamically creates the [X:a][Y:a]... string for all found audio files.
    # And then repeats that string.
    
    # Ensure there's at least one audio stream for concat
    if [ $num_audio_files -gt 0 ]; then
        filter_complex_str+="${audio_concat_inputs_str}${audio_concat_inputs_str}concat=n=$((num_audio_files * 2)):v=0:a=1[audio]"
        ffmpeg_cmd+=("-map" "[outv]" "-map" "[audio]")
    else
        # If no audio files, map only video
        ffmpeg_cmd+=("-map" "[outv]" "-an") # -an for no audio
        echo "Warning: No audio files found or processed. Video will be silent." >> "$LOG_FILE"
    fi


    # Add remaining ffmpeg options
    ffmpeg_cmd+=(
        -filter_complex "$filter_complex_str"
        -c:v "$FFMPEG_VIDEO_ENCODER"
        "${FFMPEG_PRESET_ARGS[@]}" # Add preset arguments if any
        -c:a aac
        -r 30
        -b:v 5000k
        -b:a 128k
        -shortest
        -t "$DURATION"
        "$OUTPUT_VIDEO"
    )

    # Execute the ffmpeg command
    echo "Executing ffmpeg command:" >> "$LOG_FILE"
    # Print the command in a more readable way, escaping for safety if needed
    # but for log, simple echo should be fine.
    printf "%q " "${ffmpeg_cmd[@]}" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    "${ffmpeg_cmd[@]}" >> "$LOG_FILE" 2>&1
    ffmpeg_exit_code=$?

    if [ $ffmpeg_exit_code -ne 0 ]; then
        echo "Error: ffmpeg command failed with exit code $ffmpeg_exit_code." >> "$LOG_FILE"
        echo "Error: ffmpeg processing failed. Check $LOG_FILE for details."
        # Optional: copy failed log to result folder or print more details
        exit 1
    else
        echo "Successfully rendered $OUTPUT_VIDEO." >> "$LOG_FILE"
        echo "Video successfully rendered to $OUTPUT_VIDEO"
        # Optionally, copy the log file to the same directory as the video
        cp "$LOG_FILE" "$TMP_DIR/result/render_log.txt"
    fi

    # Clean up temporary video files (intro and loop)
    rm -f "$INTRO_VIDEO" "$LOOP_VIDEO"
else
    echo "Warning: Missing intro video, loop video, or audio. Skipping main rendering." >> "$LOG_FILE"
    if [ ! -f "$INTRO_VIDEO" ]; then echo "Missing: Intro Video ($INTRO_VIDEO)" >> "$LOG_FILE"; fi
    if [ ! -f "$LOOP_VIDEO" ]; then echo "Missing: Loop Video ($LOOP_VIDEO)" >> "$LOG_FILE"; fi
    if [ ${#AUDIO_INPUTS[@]} -eq 0 ]; then echo "Missing: Audio Inputs" >> "$LOG_FILE"; fi
    echo >> "$LOG_FILE"
    # Clean up temporary intro/loop videos if they were created but not used
    if [ -f "$INTRO_VIDEO" ]; then rm -f "$INTRO_VIDEO"; fi
    if [ -f "$LOOP_VIDEO" ]; then rm -f "$LOOP_VIDEO"; fi
    exit 1 # Exit if prerequisites for rendering aren't met
fi

echo "Finished processing." >> "$LOG_FILE"
echo "See $LOG_FILE for details."
# read -p "Press Enter to continue..."
