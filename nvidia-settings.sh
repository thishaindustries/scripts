#!/bin/bash

# Set Persistence Mode
sudo nvidia-smi -pm 1
if [ $? -eq 0 ]; then
  echo "Successfully set Persistence Mode to Enabled."
else
  echo "Error setting Persistence Mode."
fi

echo ""

# Set Compute Mode to Exclusive Process
sudo nvidia-smi -c 0
if [ $? -eq 0 ]; then
  echo "Successfully set Compute Mode to Exclusive Process."
else
  echo "Error setting Compute Mode."
fi

echo ""

echo "Attempting to set fan speed is not directly supported on this GPU via nvidia-smi."
echo "Relying on the driver's automatic fan control."
echo ""

# Obtain the maximum supported clocks
supported_clocks=$(nvidia-smi --query-supported-clocks=memory,graphics --format=csv,noheader,nounits | head -1)

# Check if the command was successful and we got a valid output
if [ $? -eq 0 ] && [[ -n "$supported_clocks" ]]; then
  echo "Maximum supported clocks found: $supported_clocks"

  # Execute the command to set the application clocks
  sudo nvidia-smi -ac "$supported_clocks"

  # Check if the set command was successful
  if [ $? -eq 0 ]; then
    echo "Successfully set application clocks to: $supported_clocks"
  else
    echo "Error setting application clocks."
  fi
else
  echo "Error retrieving maximum supported clocks."
fi

echo ""

# Obtain Power Information
power_info=$(nvidia-smi -q -d POWER)

# Extract Maximum Power Limit
max_power_limit=$(echo "$power_info" | grep "Max Power Limit" | awk '{print $5}')

# Check if Maximum Power Limit was found
if [[ -n "$max_power_limit" ]]; then
  echo "Maximum Power Limit found: $max_power_limit Watts"

  # Set the Power Limit to the Maximum (you can change this value if needed)
  set_power_limit="$max_power_limit"
  echo "Setting Power Limit to: $set_power_limit Watts"
  sudo nvidia-smi -i 0 -pl "$set_power_limit"

  # Check if setting the power limit was successful
  if [ $? -eq 0 ]; then
    echo "Successfully set Power Limit to $set_power_limit Watts."
  else
    echo "Error setting Power Limit."
  fi
else
  echo "Could not retrieve Maximum Power Limit."
fi

echo ""
echo "Verifying Settings:"
nvidia-smi -q | grep "Persistence Mode"
nvidia-smi -q | grep "Compute Mode"
nvidia-smi -q -d CLOCK | grep "Graphics Clock"
nvidia-smi -q -d CLOCK | grep "Memory Clock"
nvidia-smi -q -d POWER | grep "Power Limit"
nvidia-smi -q -d FAN | grep "Fan Speed"

exit 0
