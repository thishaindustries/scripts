#!/bin/bash

# Script to get GPU and CPU utilization

# Get GPU utilization and memory info
gpu_info=$(nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.total,memory.free --format=csv,noheader,nounits | sed 's/, /,/g')

# Get CPU idle percentage
cpu_idle=$(mpstat | awk '/all/ {print $13}')

# Combine and print the information
if [ -n "$gpu_info" ] && [ -n "$cpu_idle" ]; then
  echo "$gpu_info,$cpu_idle"
elif [ -n "$gpu_info" ]; then
  echo "$gpu_info," # Add a trailing comma if only GPU info is available
elif [ -n "$cpu_idle" ]; then
  echo ",$cpu_idle" # Add a leading comma if only CPU info is available
else
  echo "Could not retrieve GPU or CPU information."
fi
