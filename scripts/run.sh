#!/bin/bash
# Unified Entry Point
# Usage: run.sh <loop|pipeline|lint|dry-run|status> ...
#
# Everything is a pipeline. A "loop" is just a single-stage pipeline.
#
# Examples:
#   ./run.sh work auth 25             # Run work loop (shortcut for single-stage pipeline)
#   ./run.sh loop work auth 25        # Same as above (explicit)
#   ./run.sh pipeline full-refine.yaml myproject  # Run multi-stage pipeline
#   ./run.sh lint                     # Validate all loops and pipelines
#   ./run.sh lint loop work           # Validate specific loop
#   ./run.sh dry-run loop work auth   # Preview loop execution
#   ./run.sh status auth              # Check session status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

show_help() {
  echo "Usage: run.sh <command> [options]"
  echo ""
  echo "Commands:"
  echo "  <loop-type> [session] [max]     Run a single-stage pipeline (shortcut)"
  echo "  loop <type> [session] [max]     Run a single-stage pipeline (explicit)"
  echo "  pipeline <file> [session]       Run a multi-stage pipeline"
  echo "  lint [loop|pipeline] [name]     Validate configurations"
  echo "  dry-run <loop|pipeline> <name> [session]  Preview execution"
  echo "  status <session>                Check session status"
  echo ""
  echo "Flags:"
  echo "  --force                         Override existing session lock"
  echo "  --resume                        Resume a crashed/failed session"
  echo ""
  echo "Available loops:"
  for dir in "$SCRIPT_DIR"/loops/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    desc=$(grep "^description:" "$dir/loop.yaml" 2>/dev/null | cut -d: -f2- | sed 's/^[[:space:]]*//')
    echo "  $name - $desc"
  done
  echo ""
  echo "Available pipelines:"
  for f in "$SCRIPT_DIR"/pipelines/*.yaml; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .yaml)
    desc=$(grep "^description:" "$f" 2>/dev/null | cut -d: -f2- | sed 's/^[[:space:]]*//')
    echo "  $name - $desc"
  done
}

if [ -z "$1" ]; then
  show_help
  exit 1
fi

case "$1" in
  lint)
    source "$LIB_DIR/validate.sh"
    shift
    lint_all "$@"
    exit $?
    ;;

  dry-run)
    source "$LIB_DIR/validate.sh"
    shift
    if [ -z "$1" ] || [ -z "$2" ]; then
      echo "Usage: run.sh dry-run <loop|pipeline> <name> [session]"
      exit 1
    fi
    target_type=$1
    target_name=$2
    session=${3:-"preview"}

    if [ "$target_type" = "loop" ]; then
      dry_run_loop "$target_name" "$session"
    elif [ "$target_type" = "pipeline" ]; then
      dry_run_pipeline "$target_name" "$session"
    else
      echo "Error: Unknown target type '$target_type'. Use 'loop' or 'pipeline'."
      exit 1
    fi
    exit $?
    ;;

  status)
    shift
    session=$1
    if [ -z "$session" ]; then
      echo "Usage: run.sh status <session>"
      exit 1
    fi
    # All sessions are now in pipeline-runs
    lock_file=".claude/locks/${session}.lock"
    state_file=".claude/pipeline-runs/${session}/state.json"

    if [ ! -f "$lock_file" ] && [ ! -f "$state_file" ]; then
      echo "No session found: $session"
      exit 1
    fi

    if [ -f "$lock_file" ]; then
      pid=$(jq -r '.pid' "$lock_file" 2>/dev/null)
      started=$(jq -r '.started_at' "$lock_file" 2>/dev/null)

      if kill -0 "$pid" 2>/dev/null; then
        echo "Session '$session' is RUNNING"
        echo "  PID: $pid"
        echo "  Started: $started"
      else
        echo "Session '$session' has CRASHED (stale lock)"
        echo "  PID: $pid (dead)"
        echo "  Started: $started"
        echo "  Use --resume to continue"
      fi
    fi

    if [ -f "$state_file" ]; then
      iteration=$(jq -r '.iteration // .current_stage // 0' "$state_file" 2>/dev/null)
      completed=$(jq -r '.iteration_completed // 0' "$state_file" 2>/dev/null)
      status=$(jq -r '.status' "$state_file" 2>/dev/null)
      loop_type=$(jq -r '.loop_type // .stages[0].name // "unknown"' "$state_file" 2>/dev/null)
      echo "  Type: $loop_type"
      echo "  Iteration: $iteration (completed: $completed)"
      echo "  Status: $status"
      echo "  Run dir: .claude/pipeline-runs/$session/"
    fi
    exit 0
    ;;

  loop)
    # Convert loop command to single-stage pipeline
    # Usage: run.sh loop <type> [session] [max] [--force] [--resume]
    shift
    LOOP_TYPE=${1:?"Usage: run.sh loop <type> [session] [max]"}
    shift
    # Pass remaining args to engine.sh pipeline with special marker
    exec "$SCRIPT_DIR/engine.sh" pipeline --single-stage "$LOOP_TYPE" "$@"
    ;;

  pipeline)
    exec "$SCRIPT_DIR/engine.sh" "$@"
    ;;

  -h|--help|help)
    show_help
    exit 0
    ;;

  *)
    # Check if first arg is a valid loop type (shortcut syntax)
    # e.g., ./run.sh work auth 25 → same as ./run.sh loop work auth 25
    if [ -d "$SCRIPT_DIR/loops/$1" ]; then
      LOOP_TYPE=$1
      shift
      exec "$SCRIPT_DIR/engine.sh" pipeline --single-stage "$LOOP_TYPE" "$@"
    fi

    echo "Error: Unknown command '$1'"
    echo ""
    show_help
    exit 1
    ;;
esac
