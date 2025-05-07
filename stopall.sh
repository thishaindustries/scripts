#!/bin/bash

# This script stops the Mineru Docker container and any running 'docling' processes.

echo "--- Starting Mineru and Docling Stop Script ---"

# --- Step 1: Stop Mineru Docker Container ---
echo "Stopping Mineru Docker container..."
IMAGE_NAME="mineru-api"
CONTAINER_IDS=$(docker ps | awk -v img="$IMAGE_NAME" '$2 == img { print $1 }')

if [ -n "$CONTAINER_IDS" ]; then
    echo "Found Mineru container IDs: $CONTAINER_IDS"
    if docker stop $CONTAINER_IDS; then
        echo "Successfully stopped Mineru container(s)."
    else
        echo "Error stopping Mineru container(s). You may need to use 'docker kill'."
    fi
else
    echo "No running Mineru containers found."
fi

# --- Step 2: Stop Docling Server ---
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

echo "--- Mineru and Docling Stop Script Finished ---"

