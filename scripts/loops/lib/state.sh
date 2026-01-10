#!/bin/bash
# State management for loop engine

# Initialize state file for a session
init_state() {
  local session=$1
  local loop_type=$2
  local state_file="$PROJECT_ROOT/.claude/loop-state-${session}.json"

  mkdir -p "$PROJECT_ROOT/.claude"

  if [ ! -f "$state_file" ]; then
    cat > "$state_file" << EOF
{
  "session": "$session",
  "loop_type": "$loop_type",
  "started_at": "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)",
  "status": "running",
  "iteration": 0,
  "history": []
}
EOF
  fi

  echo "$state_file"
}

# Update state after iteration
update_state() {
  local state_file=$1
  local iteration=$2
  local output_vars=$3  # JSON object like {"changes": 5, "summary": "..."}

  if command -v jq &> /dev/null; then
    local timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
    jq --argjson iter "$iteration" \
       --argjson vars "$output_vars" \
       --arg ts "$timestamp" \
       '.iteration = $iter | .history += [{"iteration": $iter, "timestamp": $ts} + $vars]' \
       "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
  fi
}

# Get state value
get_state() {
  local state_file=$1
  local key=$2

  if command -v jq &> /dev/null; then
    jq -r ".$key // empty" "$state_file"
  fi
}

# Get history array for completion checks
get_history() {
  local state_file=$1

  if command -v jq &> /dev/null; then
    jq -c '.history' "$state_file"
  else
    echo "[]"
  fi
}

# Mark session complete
mark_complete() {
  local state_file=$1
  local reason=$2

  if command -v jq &> /dev/null; then
    local timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
    jq --arg status "complete" \
       --arg reason "$reason" \
       --arg ts "$timestamp" \
       '.status = $status | .completed_at = $ts | .completion_reason = $reason' \
       "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
  fi
}
