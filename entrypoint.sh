#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

echo "Captain Docker's Supervisor Entrypoint Initializing..."

# Dynamically determine and export TESSDATA_PREFIX for processes started by supervisor
# This ensures supervisor inherits the correct, dynamically found path.
# It will override the TESSDATA_PREFIX set by ENV in Dockerfile for the supervisor environment.
TESS_PREFIX_PATH_RUNTIME=$(dpkg -L tesseract-ocr-eng | grep 'tessdata$' | head -n 1 || true)
if [ -n "$TESS_PREFIX_PATH_RUNTIME" ]; then
    export TESSDATA_PREFIX="${TESS_PREFIX_PATH_RUNTIME}/"
    echo "Runtime TESSDATA_PREFIX set to: $TESSDATA_PREFIX for supervisor environment"
else
    echo "Warning: Could not determine TESSDATA_PREFIX automatically at runtime. Using fallback from Dockerfile ENV: ${TESSDATA_PREFIX}"
fi

# Activate Python virtual environment for this script's context if any Python commands were to be run here.
# Not strictly necessary if only exec'ing supervisord, as supervisor program definitions handle venv.
# if [ -f "/home/ubuntu/venv/bin/activate" ]; then
#     source /home/ubuntu/venv/bin/activate
# fi

echo "All pre-supervisor setup complete. Starting supervisord..."
# The -n flag runs supervisord in the foreground.
# The -c flag specifies the main configuration file. Supervisord will include conf.d.
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
