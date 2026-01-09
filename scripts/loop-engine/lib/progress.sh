#!/bin/bash
# Progress file management for loop engine

# Initialize progress file
init_progress() {
  local session=$1
  local progress_dir="$PROJECT_ROOT/.claude/loop-progress"
  local progress_file="$progress_dir/progress-${session}.txt"

  mkdir -p "$progress_dir"

  if [ ! -f "$progress_file" ]; then
    cat > "$progress_file" << EOF
# Progress: $session

Verify: (none)

## Codebase Patterns
(Add patterns discovered during implementation here)

---

EOF
  fi

  echo "$progress_file"
}

# Append to progress file
append_progress() {
  local progress_file=$1
  local content=$2

  echo "$content" >> "$progress_file"
  echo "---" >> "$progress_file"
  echo "" >> "$progress_file"
}
