#!/bin/bash
# Pipeline YAML Parser
# Parses pipeline definitions into queryable format using yq
#
# Requires: yq (https://github.com/mikefarah/yq)

# Parsed pipeline data (associative arrays require bash 4+)
declare -A PIPELINE_DATA

# Convert YAML to JSON (uses yq if available, falls back to Python)
_yaml_to_json() {
  local file=$1

  if command -v yq &>/dev/null; then
    yq -o=json "$file"
  elif command -v python3 &>/dev/null; then
    python3 -c "
import sys, json
try:
    import yaml
    with open('$file') as f:
        print(json.dumps(yaml.safe_load(f)))
except ImportError:
    # PyYAML not installed, try simple parsing
    sys.exit(1)
"
  else
    echo "Error: Need yq or python3 with PyYAML" >&2
    return 1
  fi
}

# Parse a pipeline YAML file
parse_pipeline() {
  local file=$1

  # Convert YAML to JSON - store in temp file to handle multiline strings properly
  local tmpfile=$(mktemp)
  _yaml_to_json "$file" > "$tmpfile"

  PIPELINE_DATA["name"]=$(jq -r '.name // empty' "$tmpfile")
  PIPELINE_DATA["description"]=$(jq -r '.description // empty' "$tmpfile")
  PIPELINE_DATA["version"]=$(jq -r '.version // empty' "$tmpfile")
  PIPELINE_DATA["defaults.provider"]=$(jq -r '.defaults.provider // empty' "$tmpfile")
  PIPELINE_DATA["defaults.model"]=$(jq -r '.defaults.model // empty' "$tmpfile")

  # Parse stages
  local stage_count=$(jq '.stages | length' "$tmpfile")
  PIPELINE_DATA["stage_count"]="$stage_count"

  for i in $(seq 0 $((stage_count - 1))); do
    PIPELINE_DATA["stage.${i}.name"]=$(jq -r ".stages[$i].name // empty" "$tmpfile")
    PIPELINE_DATA["stage.${i}.description"]=$(jq -r ".stages[$i].description // empty" "$tmpfile")
    PIPELINE_DATA["stage.${i}.runs"]=$(jq -r ".stages[$i].runs // empty" "$tmpfile")
    PIPELINE_DATA["stage.${i}.model"]=$(jq -r ".stages[$i].model // empty" "$tmpfile")
    PIPELINE_DATA["stage.${i}.provider"]=$(jq -r ".stages[$i].provider // empty" "$tmpfile")
    PIPELINE_DATA["stage.${i}.completion"]=$(jq -r ".stages[$i].completion // empty" "$tmpfile")
    PIPELINE_DATA["stage.${i}.parallel"]=$(jq -r ".stages[$i].parallel // empty" "$tmpfile")
    PIPELINE_DATA["stage.${i}.prompt"]=$(jq -r ".stages[$i].prompt // empty" "$tmpfile")

    # Parse perspectives array (pipe-delimited for easy iteration)
    local perspectives=$(jq -r ".stages[$i].perspectives // [] | join(\"|\")" "$tmpfile")
    PIPELINE_DATA["stage.${i}.perspectives"]="$perspectives"
  done

  rm -f "$tmpfile"
}

# Get a pipeline-level value
get_pipeline_value() {
  local key=$1
  local default=${2:-""}

  local value="${PIPELINE_DATA[$key]}"
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    echo "$default"
  else
    echo "$value"
  fi
}

# Get the number of stages
get_stage_count() {
  echo "${PIPELINE_DATA[stage_count]:-0}"
}

# Get a stage-level value
get_stage_value() {
  local stage_idx=$1
  local key=$2
  local default=${3:-""}

  local value="${PIPELINE_DATA[stage.${stage_idx}.${key}]}"
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    echo "$default"
  else
    echo "$value"
  fi
}

# Get stage prompt
get_stage_prompt() {
  local stage_idx=$1
  echo "${PIPELINE_DATA[stage.${stage_idx}.prompt]}"
}

# Get stage array (pipe-delimited)
get_stage_array() {
  local stage_idx=$1
  local key=$2
  echo "${PIPELINE_DATA[stage.${stage_idx}.${key}]}"
}

# Get item from pipe-delimited array
get_array_item() {
  local array=$1
  local index=$2

  if [ -z "$array" ]; then
    echo ""
    return
  fi

  echo "$array" | tr '|' '\n' | sed -n "$((index + 1))p"
}

# Update state file with stage status
update_state_stage() {
  local state_file=$1
  local stage_idx=$2
  local stage_name=$3
  local status=$4

  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Use jq to safely update state
  if jq -e ".stages[$stage_idx]" "$state_file" &>/dev/null; then
    jq --arg status "$status" --arg ts "$timestamp" --argjson idx "$stage_idx" \
      '.stages[$idx].status = $status | .stages[$idx].timestamp = $ts | .current_stage = $idx' \
      "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
  else
    jq --arg name "$stage_name" --arg status "$status" --arg ts "$timestamp" --argjson idx "$stage_idx" \
      '.stages += [{"index": $idx, "name": $name, "status": $status, "timestamp": $ts}] | .current_stage = $idx' \
      "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
  fi
}
