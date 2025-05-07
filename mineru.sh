#!/bin/bash

# This script stops the Mineru Docker container and any running 'docling' processes,
# and then starts the Mineru Docker container again.

echo "--- Starting Mineru Stop/Start Script ---"

# --- Step 1: Stop Mineru and Docling ---
# (Reusing the stop logic from the previous script)

echo "Stopping Mineru and Docling..."

# --- Step 1a: Stop Mineru Docker Container ---
echo "Stopping Mineru Docker container..."
IMAGE_NAME="mineru-api"
CONTAINER_IDS=$(docker ps | awk -v img="$IMAGE_NAME" '$2 == img { print $1 }')

if [ -n "$CONTAINER_IDS" ]; then
    echo "Found Mineru container IDs: $CONTAINER_IDS"
    if docker stop $CONTAINER_IDS; then
        echo "Successfully stopped Mineru container(s)."
    else
        echo "Error stopping Mineru container(s). You may need to use 'docker kill'."
        exit 1 # Exit if stopping Mineru fails
    fi
else
    echo "No running Mineru containers found."
fi

# --- Step 1b: Stop Docling Server ---
echo "Stopping Docling server..."
PIDS_TO_KILL=$(pgrep -f "docling" | grep -v $$ || true)

if [ -n "$PIDS_TO_KILL" ]; then
    echo "Found Docling PIDs: $PIDS_TO_KILL"
    echo "$PIDS_TO_KILL" | while read -r PID; do
        echo "Killing PID $PID..."
        kill -9 "$PID" || echo "Warning: Could not force-kill Docling PID $PID"
        echo "PID $PID kill attempt finished."
    done
    echo "Successfully stopped (or attempted to stop) all 'docling' processes."
else
    echo "No 'docling' processes found to stop."
fi

# --- Step 2: Start Mineru Docker Container ---
echo "Starting Mineru Docker container..."
# Define the full docker run command to start the container
#  Make sure this matches the command you use to start mineru
RUN_COMMAND="docker run -d --rm --gpus=all -p 8000:8000 $IMAGE_NAME"

echo "Running command: $RUN_COMMAND"
if $RUN_COMMAND; then
    echo "Successfully started Mineru container."
else
    echo "Error starting Mineru container."
    exit 1 # Exit if starting Mineru fails
fi

echo "--- Mineru Stop/Start Script Finished ---"

