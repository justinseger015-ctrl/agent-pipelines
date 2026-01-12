#!/bin/bash
# Completion strategy: fixed-n (v3)
# Complete after exactly N iterations, OR if agent writes decision: stop
#
# This allows agents to exit early when work is done, while still
# enforcing a maximum iteration limit.

source "$(dirname "${BASH_SOURCE[0]}")/../status.sh"

check_completion() {
  local session=$1
  local state_file=$2
  local status_file=$3

  local iteration=$(get_state "$state_file" "iteration")
  local target=${FIXED_ITERATIONS:-$MAX_ITERATIONS}

  # Check if agent requested stop
  if [ -n "$status_file" ] && [ -f "$status_file" ]; then
    local decision=$(get_status_decision "$status_file")
    if [ "$decision" = "stop" ]; then
      echo "Agent requested stop at iteration $iteration"
      return 0
    fi
    if [ "$decision" = "error" ]; then
      echo "Agent reported error at iteration $iteration"
      return 0
    fi
  fi

  # Check if we've hit the iteration limit
  if [ "$iteration" -ge "$target" ]; then
    echo "Completed $iteration iterations (max: $target)"
    return 0
  fi

  return 1
}
