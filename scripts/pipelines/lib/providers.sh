#!/bin/bash
# Provider Execution
# Executes prompts via AI providers (currently Claude Code only)
#
# Future: Add Codex, Gemini when their CLIs are stable

# Execute a prompt and capture output
# Usage: execute_prompt "$prompt" "$provider" "$model" "$output_file"
execute_prompt() {
  local prompt=$1
  local provider=${2:-"claude-code"}
  local model=${3:-"sonnet"}
  local output_file=$4

  case "$provider" in
    claude-code|claude)
      _execute_claude "$prompt" "$model" "$output_file"
      ;;
    *)
      echo "Error: Unknown provider: $provider" >&2
      echo "Currently supported: claude-code" >&2
      return 1
      ;;
  esac
}

# Execute via Claude Code CLI
_execute_claude() {
  local prompt=$1
  local model=${2:-"sonnet"}
  local output_file=$3

  # Normalize model names
  case "$model" in
    opus|claude-opus|opus-4|opus-4.5)
      model="opus"
      ;;
    sonnet|claude-sonnet|sonnet-4)
      model="sonnet"
      ;;
    haiku|claude-haiku)
      model="haiku"
      ;;
  esac

  # Execute and capture output
  local output
  if [ -n "$output_file" ]; then
    output=$(printf '%s' "$prompt" | claude --model "$model" --dangerously-skip-permissions 2>&1 | tee "$output_file")
  else
    output=$(printf '%s' "$prompt" | claude --model "$model" --dangerously-skip-permissions 2>&1)
  fi

  echo "$output"
}
