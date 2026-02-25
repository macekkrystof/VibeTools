#!/bin/bash
# ============================================================================
# Ralph - Autonomous Codex CLI Agent Runner
# ============================================================================
# Linux/Docker version with infinite retry on rate limits.
# Runs OpenAI Codex CLI in a loop. No budget/schedule tracking.
# Features: persistent logging, iteration timeout, git state tracking,
#           orphan process cleanup, configurable push frequency.
#
# Environment Variables:
#   MAX_ITERATIONS    - Max iterations (0 = unlimited, default: 0)
#   RETRY_DELAY       - Seconds to wait when rate limited (default: 60)
#   ERROR_RETRY_DELAY - Seconds to wait on errors (default: 5)
#   AUTO_PUSH         - Auto-push commits after each iteration (default: true)
#   PUSH_EVERY_N      - Push every N iterations instead of every one (default: 1)
#   ITERATION_TIMEOUT - Max seconds per Codex invocation (default: 3600)
#   OPENAI_API_KEY    - OpenAI API key (alternative to OAuth login)
#   CODEX_CONFIG_DIR  - Path to Codex config directory (for OAuth credentials)
#   CODEX_MODEL       - Model to use (optional, uses Codex default)
#   LOGDIR            - Directory for log files (default: /app/.claude/logs)
# ============================================================================

set -e

# ============================================================================
# INITIALIZATION
# ============================================================================

# Create HOME directory if needed
mkdir -p "$HOME" 2>/dev/null || true

# ----------------------------------------------------------------------------
# User Identity Fix (required by SSH and git in Docker)
# ----------------------------------------------------------------------------
if ! whoami &>/dev/null; then
    echo "ralph:x:$(id -u):$(id -g):Ralph Agent:${HOME}:/bin/bash" >> /etc/passwd 2>/dev/null || true
fi

# ----------------------------------------------------------------------------
# Auto-Update Codex CLI
# ----------------------------------------------------------------------------
if command -v npm >/dev/null 2>&1; then
    echo -e "[$(date '+%H:%M:%S')] Updating Codex CLI..."
    npm install -g @openai/codex 2>&1 | tail -1 || echo "  Update failed (will use existing version)"
fi

# ----------------------------------------------------------------------------
# Codex Configuration (OAuth credentials)
# ----------------------------------------------------------------------------
if [ -n "$CODEX_CONFIG_DIR" ] && [ -d "$CODEX_CONFIG_DIR" ] && [ ! -e "$HOME/.codex" ]; then
    ln -sf "$CODEX_CONFIG_DIR" "$HOME/.codex" 2>/dev/null || true
fi

# ----------------------------------------------------------------------------
# SSH Configuration (for git push)
# ----------------------------------------------------------------------------
if [ -d "/.ssh" ]; then
    rm -rf "$HOME/.ssh" 2>/dev/null || true
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    cp /.ssh/id_* "$HOME/.ssh/" 2>/dev/null || true
    cp /.ssh/known_hosts "$HOME/.ssh/" 2>/dev/null || true
    chmod 600 "$HOME/.ssh/id_"* 2>/dev/null || true
    chmod 644 "$HOME/.ssh/"*.pub 2>/dev/null || true
    ssh-keyscan -t ed25519,rsa github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
    {
        echo "Host github.com"
        echo "    HostName github.com"
        echo "    User git"
        echo "    IdentityFile $HOME/.ssh/id_ed25519"
        echo "    IdentitiesOnly yes"
        echo "    StrictHostKeyChecking accept-new"
    } > "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
    export GIT_SSH_COMMAND="ssh -i $HOME/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$HOME/.ssh/known_hosts"
fi

# ----------------------------------------------------------------------------
# Git Configuration
# ----------------------------------------------------------------------------
git config --global credential.helper "" 2>/dev/null || true
git config --global url."git@github.com:".insteadOf "https://github.com/" 2>/dev/null || true
git config --global --add safe.directory /app 2>/dev/null || true

if [ -f "/.gitconfig" ] && [ ! -e "$HOME/.gitconfig" ]; then
    ln -sf /.gitconfig "$HOME/.gitconfig" 2>/dev/null || true
fi

# ============================================================================
# CONFIGURATION
# ============================================================================

MAX_ITERATIONS=${MAX_ITERATIONS:-0}
RETRY_DELAY=${RETRY_DELAY:-60}
ERROR_RETRY_DELAY=${ERROR_RETRY_DELAY:-5}
AUTO_PUSH=${AUTO_PUSH:-true}
PUSH_EVERY_N=${PUSH_EVERY_N:-1}
ITERATION_TIMEOUT=${ITERATION_TIMEOUT:-3600}
CODEX_MODEL=${CODEX_MODEL:-}

# Logging
LOGDIR=${LOGDIR:-/app/.claude/logs}
mkdir -p "$LOGDIR" 2>/dev/null || true
LOGFILE="${LOGDIR}/ralph-codex.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$ts] $*"
    echo "[$ts] $(echo -e "$*" | sed 's/\x1b\[[0-9;]*m//g')" >> "$LOGFILE"
}

log_file() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] $*" >> "$LOGFILE"
}

cleanup_orphans() {
    log "Cleaning up orphaned processes..."
    # Customize for your project:
    # pkill -f "dotnet run" 2>/dev/null || true
    # pkill -f "node.*dev" 2>/dev/null || true
    true
}

try_push() {
    local branch
    branch=$(git branch --show-current 2>/dev/null)
    if [ -z "$branch" ]; then
        log "${YELLOW}Cannot determine current branch, skipping push${NC}"
        return
    fi
    if git log "origin/${branch}..HEAD" --oneline 2>/dev/null | grep -q .; then
        log "Pushing commits to origin/${branch}..."
        if git push 2>&1; then
            log "${GREEN}Push successful${NC}"
        else
            log "${YELLOW}Push failed${NC}"
        fi
    else
        log "No new commits to push"
    fi
}

# ============================================================================
# STARTUP BANNER
# ============================================================================

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN} Ralph - Autonomous Code Agent (Codex)${NC}"
if [ $MAX_ITERATIONS -eq 0 ]; then
    echo -e "${CYAN} Iterations: unlimited${NC}"
else
    echo -e "${CYAN} Max iterations: ${MAX_ITERATIONS}${NC}"
fi
echo -e "${CYAN} Iteration timeout: ${ITERATION_TIMEOUT}s${NC}"
echo -e "${CYAN} Auto-push: ${AUTO_PUSH} (every ${PUSH_EVERY_N} iterations)${NC}"
echo -e "${CYAN} Log file: ${LOGFILE}${NC}"
if [ -n "$CODEX_MODEL" ]; then
    echo -e "${CYAN} Model: ${CODEX_MODEL}${NC}"
fi
echo -e "${CYAN}========================================${NC}"
echo ""

# ----------------------------------------------------------------------------
# Environment Check
# ----------------------------------------------------------------------------
echo -e "${CYAN}[$(date '+%H:%M:%S')] Environment:${NC}"
echo -e "  Codex:    $(codex --version 2>/dev/null || echo 'NOT INSTALLED')"
echo -e "  Git:      $(git --version 2>/dev/null || echo 'NOT INSTALLED')"
echo -e "  Node.js:  $(node --version 2>/dev/null || echo 'NOT INSTALLED')"
echo -e "  User:     $(whoami 2>/dev/null || echo "UID $(id -u)") (UID: $(id -u))"
echo -e "  HOME:     $HOME"
echo -e "  Workdir:  $(pwd)"

for tool in dotnet cmake g++ docker python3; do
    ver=$($tool --version 2>/dev/null | head -1) && echo -e "  $(printf '%-9s' "$tool") $ver" || true
done
echo ""

# ----------------------------------------------------------------------------
# Authentication Check
# ----------------------------------------------------------------------------
echo -e "${CYAN}[$(date '+%H:%M:%S')] Authentication:${NC}"
codex_dir="${CODEX_CONFIG_DIR:-$HOME/.codex}"

if [ -n "$OPENAI_API_KEY" ]; then
    echo -e "  Codex: OPENAI_API_KEY configured"
elif [ -f "$codex_dir/auth.json" ] || [ -f "/.codex/auth.json" ]; then
    echo -e "  Codex: OAuth credentials found (ChatGPT account)"
else
    echo -e "${YELLOW}  WARNING: No Codex auth found! Run 'codex' to sign in or set OPENAI_API_KEY${NC}"
fi
echo ""

# ============================================================================
# MAIN LOOP
# ============================================================================

rate_limit_count=0
empty_count=0
i=1
tmpfile=$(mktemp /tmp/ralph-codex-output.XXXXXX)
trap 'rm -f "$tmpfile" /tmp/ralph-codex-prompt.md' EXIT

log "Ralph (Codex) started. Log file: $LOGFILE"
log "Iteration timeout: ${ITERATION_TIMEOUT}s"

while [ $MAX_ITERATIONS -eq 0 ] || [ $i -le $MAX_ITERATIONS ]; do
    echo -e "${GREEN}=====================================================${NC}"
    echo -e "${GREEN} Iteration $i  ($(date '+%Y-%m-%d %H:%M:%S'))${NC}"
    echo -e "${GREEN}=====================================================${NC}"

    cleanup_orphans

    # Build prompt from files (codex doesn't support @file references)
    prompt_file="/tmp/ralph-codex-prompt.md"
    : > "$prompt_file"
    if [ -f "prompt.md" ]; then
        cat "prompt.md" >> "$prompt_file"
    else
        log "${RED}ERROR: prompt.md not found!${NC}"
        exit 1
    fi
    if [ -f "progress.txt" ]; then
        echo -e "\n\n" >> "$prompt_file"
        cat "progress.txt" >> "$prompt_file"
    fi

    # Record git state BEFORE
    head_before=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    log "--- Iteration $i START ---"
    log "Git HEAD before: $(git log --oneline -1 2>/dev/null || echo 'unknown')"

    # Build codex command
    codex_args="exec --dangerously-bypass-approvals-and-sandbox"
    if [ -n "$CODEX_MODEL" ]; then
        codex_args="$codex_args -m $CODEX_MODEL"
    fi

    log "Starting Codex CLI (timeout: ${ITERATION_TIMEOUT}s)..."

    set +e
    : > "$tmpfile"
    if [ "$ITERATION_TIMEOUT" -gt 0 ] 2>/dev/null; then
        timeout --kill-after=60 "$ITERATION_TIMEOUT" \
            codex $codex_args "Follow ALL instructions in the file: $prompt_file" </dev/null 2>&1 | tee "$tmpfile"
        exit_code=${PIPESTATUS[0]}
    else
        codex $codex_args "Follow ALL instructions in the file: $prompt_file" </dev/null 2>&1 | tee "$tmpfile"
        exit_code=${PIPESTATUS[0]}
    fi
    set -e

    output=$(cat "$tmpfile" 2>/dev/null || echo "")

    # Record git state AFTER
    head_after=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    log "Exit code: $exit_code"
    log "Git HEAD after: $(git log --oneline -1 2>/dev/null || echo 'unknown')"

    # Show new commits
    if [ "$head_before" != "$head_after" ] && [ "$head_before" != "unknown" ]; then
        new_commits=$(git log --oneline "$head_before".."$head_after" 2>/dev/null || echo "")
        if [ -n "$new_commits" ]; then
            log "New commits in this iteration:"
            echo "$new_commits" | while IFS= read -r line; do
                log "  $line"
            done
        fi
    else
        log "No new commits in this iteration."
    fi

    cleanup_orphans

    # Handle Timeout
    if [ "$exit_code" -eq 124 ] || [ "$exit_code" -eq 137 ]; then
        log "${YELLOW}TIMEOUT: Codex exceeded ${ITERATION_TIMEOUT}s (exit $exit_code). Moving to next iteration.${NC}"
        if [ "$AUTO_PUSH" = "true" ] && [ "$head_before" != "$head_after" ] && [ "$head_before" != "unknown" ]; then
            log "Pushing commits from timed-out iteration..."
            try_push
        fi
        i=$((i + 1))
        continue
    fi

    # Empty output guard
    if [ -z "$(echo "$output" | tr -d '[:space:]')" ] && [ "$exit_code" -eq 0 ]; then
        empty_count=$((empty_count + 1))
        if [ "$empty_count" -ge 3 ]; then
            log "${RED}FATAL: Codex produced no output 3 times in a row. Aborting.${NC}"
            exit 1
        fi
        log "${YELLOW}WARNING: Codex produced no output. Retrying in ${ERROR_RETRY_DELAY}s... ($empty_count/3)${NC}"
        sleep "$ERROR_RETRY_DELAY"
        continue
    fi
    empty_count=0

    # Rate Limiting
    if echo "$output" | grep -qiE "rate.?limit|too many requests|HTTP[/ ]429|status[: ]429|quota exceeded|exceeded your.*quota"; then
        rate_limit_count=$((rate_limit_count + 1))
        log "${YELLOW}Rate limit hit (#${rate_limit_count}). Waiting ${RETRY_DELAY}s...${NC}"
        sleep $RETRY_DELAY
        continue
    fi

    rate_limit_count=0

    # Auth Errors
    if echo "$output" | grep -qiE "invalid.*api.?key|authentication.?(error|fail)|unauthorized.*api|401.*unauthorized"; then
        log "${RED}Authentication error. Check your OPENAI_API_KEY.${NC}"
        exit 1
    fi

    # Other Errors
    if [ $exit_code -ne 0 ]; then
        log "${RED}ERROR: Codex exited with code $exit_code. Retrying in ${ERROR_RETRY_DELAY}s...${NC}"
        log_file "Last 20 lines of output: $(tail -20 "$tmpfile" 2>/dev/null)"
        sleep $ERROR_RETRY_DELAY
        i=$((i + 1))
        continue
    fi

    # Check for Completion
    if echo "$output" | grep -q "<promise>COMPLETE</promise>"; then
        log "${GREEN}All tasks complete!${NC}"
        if [ "$AUTO_PUSH" = "true" ]; then
            log "Pushing final changes..."
            try_push
        fi
        exit 0
    fi

    # Auto-Push (every N iterations)
    if [ "$AUTO_PUSH" = "true" ] && [ $((i % PUSH_EVERY_N)) -eq 0 ]; then
        try_push
    fi

    log "--- Iteration $i END ---"
    i=$((i + 1))
done

log "${YELLOW}Max iterations ($MAX_ITERATIONS) reached${NC}"

if [ "$AUTO_PUSH" = "true" ]; then
    log "Final push..."
    try_push
fi
