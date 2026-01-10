#!/bin/bash
# Convenience wrapper for loop engine
# Usage: run.sh <loop_type> [session_name] [max_iterations]
#
# Examples:
#   ./run.sh work auth 25        # Run work loop for 'auth' session
#   ./run.sh refine planning 10  # Run refine loop for 10 iterations max
#   ./run.sh review security     # Run review loop

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$1" ]; then
  echo "Usage: run.sh <loop_type> [session_name] [max_iterations]"
  echo ""
  echo "Available loop types:"
  for dir in "$SCRIPT_DIR"/*/; do
    name=$(basename "$dir")
    desc=$(grep "^description:" "$dir/loop.yaml" 2>/dev/null | cut -d: -f2- | sed 's/^[[:space:]]*//')
    echo "  $name - $desc"
  done
  exit 1
fi

exec "$SCRIPT_DIR/engine.sh" "$@"
