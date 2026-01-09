#!/bin/bash
# Completion strategy: plateau
# Returns 0 (complete) when changes plateau (2+ consecutive low-change rounds)

# Config (can be overridden by loop.yaml)
PLATEAU_THRESHOLD=${PLATEAU_THRESHOLD:-2}
MIN_ITERATIONS=${MIN_ITERATIONS:-3}
LOW_CHANGE_MAX=${LOW_CHANGE_MAX:-1}

check_completion() {
  local session=$1
  local state_file=$2
  local output=$3

  # Get current iteration
  local iteration=$(get_state "$state_file" "iteration")

  # Don't check plateau until minimum iterations reached
  if [ "$iteration" -lt "$MIN_ITERATIONS" ]; then
    return 1
  fi

  # Get history and check for plateau
  local history=$(get_history "$state_file")

  if command -v jq &> /dev/null; then
    # Get last N changes values
    local recent_changes=$(echo "$history" | jq -r "[.[-${PLATEAU_THRESHOLD}:][].changes // 999] | map(tonumber)")

    # Check if all recent changes are <= LOW_CHANGE_MAX
    local all_low=$(echo "$recent_changes" | jq "all(. <= $LOW_CHANGE_MAX)")

    if [ "$all_low" = "true" ]; then
      echo "Plateau detected at iteration $iteration"
      return 0
    fi
  fi

  return 1
}
