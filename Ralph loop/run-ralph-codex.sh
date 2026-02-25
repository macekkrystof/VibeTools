#!/bin/bash
# ============================================================================
# Run Ralph with OpenAI Codex
# ============================================================================
# Builds (if needed) and starts the Ralph agent with Codex CLI.
#
# Usage:
#   ./run-ralph-codex.sh              # start (builds if needed)
#   ./run-ralph-codex.sh --build      # force rebuild image
#   ./run-ralph-codex.sh --detach     # run in background
#   ./run-ralph-codex.sh down         # stop
#
# Authentication (one of):
#   1. OAuth login:    run 'codex' locally first to sign in (~/.codex/auth.json)
#   2. API key:        set OPENAI_API_KEY in shell or .env file
#
# Environment:
#   CODEX_MODEL      - Optional. Override default model.
# ============================================================================

set -e
cd "$(dirname "$0")"

if [ "$1" = "down" ] || [ "$1" = "stop" ]; then
    docker compose -f docker-compose.ralph.yml stop ralph-codex
    exit 0
fi

# Check for any form of auth
if [ -z "$OPENAI_API_KEY" ] && \
   [ ! -f "$HOME/.codex/auth.json" ] && \
   ! grep -q "OPENAI_API_KEY" .env 2>/dev/null; then
    echo "WARNING: No Codex auth found. Run 'codex' locally to sign in, or set OPENAI_API_KEY."
fi

# Create codex config dir if it doesn't exist (for volume mount)
mkdir -p "$HOME/.codex" 2>/dev/null || true

docker compose -f docker-compose.ralph.yml up "$@" ralph-codex
