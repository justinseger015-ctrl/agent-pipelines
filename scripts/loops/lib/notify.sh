#!/bin/bash
# Desktop notifications for loop engine

notify() {
  local title=$1
  local message=$2

  if command -v osascript &> /dev/null; then
    # macOS
    osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
  elif command -v notify-send &> /dev/null; then
    # Linux
    notify-send "$title" "$message" 2>/dev/null || true
  fi
}

# Record completion to JSON log
record_completion() {
  local status=$1
  local session=$2
  local loop_type=${3:-"unknown"}
  local file="$PROJECT_ROOT/.claude/loop-completions.json"
  local timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  mkdir -p "$PROJECT_ROOT/.claude"

  local entry="{\"session\": \"$session\", \"loop_type\": \"$loop_type\", \"status\": \"$status\", \"completed_at\": \"$timestamp\"}"

  if [ -f "$file" ]; then
    if command -v jq &> /dev/null; then
      jq ". += [$entry]" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    else
      local existing=$(cat "$file" | tr -d '\n' | sed 's/]$//')
      echo "$existing, $entry]" > "$file"
    fi
  else
    echo "[$entry]" > "$file"
  fi

  notify "Loop Agent" "Loop $session ($loop_type): $status"
}
