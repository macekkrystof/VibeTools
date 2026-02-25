#!/bin/bash
# ============================================================================
# Run Ralph with Claude Code
# ============================================================================
# Builds (if needed) and starts the Ralph agent with Claude CLI.
#
# Usage:
#   ./run-ralph-claude.sh              # start (builds if needed)
#   ./run-ralph-claude.sh --build      # force rebuild image
#   ./run-ralph-claude.sh --detach     # run in background
#   ./run-ralph-claude.sh down         # stop
# ============================================================================

set -e
cd "$(dirname "$0")"

if [ "$1" = "down" ] || [ "$1" = "stop" ]; then
    docker compose -f docker-compose.ralph.yml stop ralph-claude
    exit 0
fi

docker compose -f docker-compose.ralph.yml up "$@" ralph-claude
