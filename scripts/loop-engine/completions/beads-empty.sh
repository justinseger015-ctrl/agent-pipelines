#!/bin/bash
# Completion strategy: beads-empty
# Returns 0 (complete) when no beads remain for this session

check_completion() {
  local session=$1
  local state_file=$2
  local output=$3

  # Check if any work remains
  local remaining=$(bd ready --label="loop/$session" 2>/dev/null | grep -c "^" || echo "0")

  if [ "$remaining" -eq 0 ]; then
    echo "All beads complete"
    return 0
  fi

  return 1
}

# Also check for explicit completion signal in output
check_output_signal() {
  local output=$1

  if echo "$output" | grep -q "<promise>COMPLETE</promise>"; then
    return 0
  fi

  return 1
}
