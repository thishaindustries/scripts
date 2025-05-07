#!/bin/bash

# This script stops any running 'docling' processes,
# removes old PNG files, changes directory, activates
# the 'docling' conda environment, and restarts the
# docling server in the background.

# --- Configuration ---
DOCLING_DIR="/home/ubuntu/easy"
CONDA_ENV_NAME="docling"
SERVER_PORT="8000"
OUTPUT_LOG="out.log"

# Define the target Docker image name
IMAGE_NAME="mineru-api"

echo "--- Docker Stop Script for $IMAGE_NAME ---"

# --- Step 1: Find and Stop Running Containers ---
echo "Searching for running Docker containers using image: $IMAGE_NAME (parsing ps output)..."

# Find the IDs of running containers using the specified image by parsing 'docker ps' output
# Using awk for compatibility with potentially older Docker versions that don't support -f image=
CONTAINER_IDS=$(docker ps | awk -v img="$IMAGE_NAME" '$2 == img { print $1 }')

# Check if any containers were found
if [ -z "$CONTAINER_IDS" ]; then
    echo "No running containers found for image '$IMAGE_NAME'."
else
    echo "Found running containers with IDs:"
    # Print each ID on a new line for readability
    echo "$CONTAINER_IDS" | tr ' ' '\n'
    echo "Attempting to stop these containers gracefully..."

    # Stop the containers
    # docker stop sends SIGTERM (graceful shutdown), waits for a timeout (default 10s),
    # then sends SIGKILL (force kill) if the container hasn't stopped.
    # Command substitution passes the found IDs as arguments to docker stop.
    if docker stop $CONTAINER_IDS; then
        echo "Successfully stopped containers for image '$IMAGE_NAME'."
    else
        # docker stop failed for some reason (e.g., container is stuck)
        echo "Error stopping containers for image '$IMAGE_NAME'."
        echo "You might need to manually force stop them using:"
        echo "docker kill $CONTAINER_IDS"
    fi
fi

# Exit immediately if a command exits with a non-zero status.
set -e

echo "--- Starting Docling Restart Script ---"

# Step 1: Stop any running 'docling' processes
echo "Attempting to stop any running processes containing 'docling'..."

# Find PIDs, excluding the script's own pgrep process
PIDS_TO_KILL=$(pgrep -f "docling" | grep -v $$ || true)

if [ -n "$PIDS_TO_KILL" ]; then
    echo "Found PIDs: $PIDS_TO_KILL"
    echo "$PIDS_TO_KILL" | while read -r PID; do
        echo "Killing PID $PID..."
        kill -9 "$PID" || echo "Warning: Could not force-kill PID $PID"
        echo "PID $PID kill attempt finished."
    done
else
    echo "No 'docling' processes found to kill."
fi

echo "Finished attempting to stop processes."


# Step 2: Remove old .png files
echo "Removing old .png files from ${DOCLING_DIR}..."
# rm -rf removes recursively and forcefully.
# "${DOCLING_DIR}"/*.png targets all files ending in .png in that directory.
# || true is added so the script doesn't exit if no .png files are found.
rm -rf "${DOCLING_DIR}"/*.png || true
echo "Finished removing files."

# Step 3: Change directory to the docling project directory
echo "Changing directory to ${DOCLING_DIR}..."
# cd attempts to change directory. If it fails, print an error and exit.
cd "${DOCLING_DIR}" || { echo "Error: Failed to change directory to ${DOCLING_DIR}. Exiting."; exit 1; }
echo "Current directory: $(pwd)"


# Step 4: Initialize and activate the conda environment
echo "Initializing and activating conda environment: ${CONDA_ENV_NAME}..."

# Find the base conda installation path dynamically or assume a common location
# `conda info --base` is the most reliable way if conda command is in PATH
# Fallback to common user home directory locations if `conda` command isn't found initially
CONDA_BASE=$(conda info --base 2>/dev/null || echo "$HOME/anaconda3") # Use anaconda3 as suggested by your PATH
if [ ! -d "$CONDA_BASE" ]; then
    CONDA_BASE="$HOME/miniconda3" # Try miniconda if anaconda3 not found
fi


CONDA_PROFILE_SCRIPT="${CONDA_BASE}/etc/profile.d/conda.sh"

if [ -f "$CONDA_PROFILE_SCRIPT" ]; then
    echo "Sourcing conda initialization script: $CONDA_PROFILE_SCRIPT"
    # Source the script into the current shell session
    source "$CONDA_PROFILE_SCRIPT" || { echo "Error: Failed to source conda initialization script at $CONDA_PROFILE_SCRIPT. Exiting."; exit 1; }
else
    echo "Error: Conda initialization script not found at $CONDA_PROFILE_SCRIPT."
    echo "Please check your conda installation path and update CONDA_BASE in the script if necessary."
    exit 1
fi

# Now that conda is initialized in the script's shell, activate the environment
# This command modifies the script's environment
conda activate "${CONDA_ENV_NAME}" || { echo "Error: Failed to activate conda environment '${CONDA_ENV_NAME}'. Ensure it exists and is accessible. Exiting."; exit 1; }
echo "Conda environment activated."

# Step 5: Run the docling server using nohup in the background
echo "Starting docling-serve on port ${SERVER_PORT} with reload enabled..."
echo "Output redirected to ${OUTPUT_LOG}"
# nohup runs the command so it continues even if the terminal is closed.
# > ${OUTPUT_LOG} redirects standard output to the log file.
# 2>&1 redirects standard error to standard output (so errors go to the log file too).
# & runs the command in the background.
nohup docling-serve run --reload --port="${SERVER_PORT}" > "${OUTPUT_LOG}" 2>&1 &

# Get the Process ID (PID) of the background command
# $! is the PID of the last background command
SERVER_PID=$!
echo "Docling server started in the background. PID: ${SERVER_PID}"

echo "--- Docling Restart Script Finished ---"
# You can check the server status with 'tail -f out.log' or 'pgrep -f docling'
