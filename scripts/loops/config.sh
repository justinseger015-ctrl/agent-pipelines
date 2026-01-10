#!/bin/bash
# Configuration loader for loop engine
# Reads loop.yaml and exports variables

load_config() {
  local loop_type=$1
  local config_file="$LOOPS_DIR/$loop_type/loop.yaml"

  if [ ! -f "$config_file" ]; then
    echo "Error: Config not found: $config_file" >&2
    exit 1
  fi

  # Parse YAML (simple key: value format)
  # For complex configs, would need yq, but keeping it simple
  while IFS=': ' read -r key value; do
    # Skip comments and empty lines
    [[ "$key" =~ ^#.*$ ]] && continue
    [[ -z "$key" ]] && continue

    # Remove quotes from value
    value=$(echo "$value" | sed 's/^["'\'']//' | sed 's/["'\'']$//')

    # Export as uppercase variable
    local var_name=$(echo "$key" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    export "$var_name=$value"
  done < "$config_file"
}

# Get prompt file path
get_prompt_file() {
  local loop_type=$1
  local prompt_name=${2:-"prompt"}

  local prompt_file="$LOOPS_DIR/$loop_type/prompts/${prompt_name}.md"

  # Fallback to single prompt.md
  if [ ! -f "$prompt_file" ]; then
    prompt_file="$LOOPS_DIR/$loop_type/prompt.md"
  fi

  if [ ! -f "$prompt_file" ]; then
    echo "Error: Prompt not found for $loop_type" >&2
    exit 1
  fi

  echo "$prompt_file"
}

# Substitute variables in prompt
substitute_prompt() {
  local prompt_file=$1
  local session=$2
  local progress_file=$3
  local extra_vars=$4  # "VAR1=val1 VAR2=val2"

  local content=$(cat "$prompt_file")

  # Standard substitutions
  content=$(echo "$content" | sed "s|\${SESSION_NAME}|$session|g")
  content=$(echo "$content" | sed "s|\${PROGRESS_FILE}|$progress_file|g")

  # Extra substitutions
  for var in $extra_vars; do
    local name="${var%%=*}"
    local value="${var#*=}"
    content=$(echo "$content" | sed "s|\${$name}|$value|g")
  done

  echo "$content"
}
