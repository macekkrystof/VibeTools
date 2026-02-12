#!/bin/bash
# ============================================================================
# Ralph - Autonomous Claude Code Agent Runner
# ============================================================================
# Linux/Docker version with infinite retry on rate limits.
# Runs Claude CLI in a loop, automatically handles rate limits and errors.
#
# Environment Variables:
#   MAX_ITERATIONS    - Max iterations (0 = unlimited, default: 0)
#   RETRY_DELAY       - Seconds to wait when rate limited (default: 60)
#   ERROR_RETRY_DELAY - Seconds to wait on errors (default: 5)
#   AUTO_PUSH         - Auto-push commits after each iteration (default: true)
#   CLAUDE_CONFIG_DIR - Path to Claude config directory
#   ANTHROPIC_API_KEY - API key (alternative to Claude login)
# ============================================================================

set -e

# ============================================================================
# INITIALIZATION
# ============================================================================

# Create HOME directory if needed
mkdir -p "$HOME" 2>/dev/null || true

# ----------------------------------------------------------------------------
# Claude Configuration
# ----------------------------------------------------------------------------
if [ -n "$CLAUDE_CONFIG_DIR" ] && [ -d "$CLAUDE_CONFIG_DIR" ] && [ ! -e "$HOME/.claude" ]; then
    ln -sf "$CLAUDE_CONFIG_DIR" "$HOME/.claude" 2>/dev/null || true
fi

# ----------------------------------------------------------------------------
# SSH Configuration (for git push)
# ----------------------------------------------------------------------------
# SSH ignores $HOME and uses path from /etc/passwd, so we need to:
# 1. Copy keys to $HOME/.ssh (symlinks don't work reliably)
# 2. Set GIT_SSH_COMMAND to explicitly use the correct key
if [ -d "/.ssh" ]; then
    # Completely remove any existing .ssh (symlink, directory, whatever)
    rm -rf "$HOME/.ssh" 2>/dev/null || true
    
    # Create fresh .ssh directory with correct permissions
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    
    # Copy SSH keys and known_hosts
    cp /.ssh/id_* "$HOME/.ssh/" 2>/dev/null || true
    cp /.ssh/known_hosts "$HOME/.ssh/" 2>/dev/null || true
    
    # Set correct permissions (required by SSH)
    chmod 600 "$HOME/.ssh/id_"* 2>/dev/null || true
    chmod 644 "$HOME/.ssh/"*.pub 2>/dev/null || true
    
    # Create SSH config for GitHub using echo (more reliable than heredoc)
    {
        echo "Host github.com"
        echo "    HostName github.com"
        echo "    User git"
        echo "    IdentityFile $HOME/.ssh/id_ed25519"
        echo "    IdentitiesOnly yes"
        echo "    StrictHostKeyChecking accept-new"
    } > "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
    
    # Force git to use the correct SSH key
    export GIT_SSH_COMMAND="ssh -i $HOME/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new"
fi

# ----------------------------------------------------------------------------
# Git Configuration
# ----------------------------------------------------------------------------
# Disable credential helper (gh CLI not installed, blocks push)
# Force SSH for GitHub (not HTTPS)
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

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# STARTUP BANNER
# ============================================================================

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN} Ralph - Autonomous Code Agent${NC}"
if [ $MAX_ITERATIONS -eq 0 ]; then
    echo -e "${CYAN} Iterations: unlimited${NC}"
else
    echo -e "${CYAN} Max iterations: ${MAX_ITERATIONS}${NC}"
fi
echo -e "${CYAN} Auto-push: ${AUTO_PUSH}${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# ----------------------------------------------------------------------------
# Environment Check
# ----------------------------------------------------------------------------
echo -e "${CYAN}[$(date '+%H:%M:%S')] Environment:${NC}"
echo -e "  .NET SDK: $(dotnet --version 2>/dev/null || echo 'NOT INSTALLED')"
echo -e "  Node.js:  $(node --version 2>/dev/null || echo 'NOT INSTALLED')"
echo -e "  Claude:   $(claude --version 2>/dev/null || echo 'NOT INSTALLED')"
echo -e "  Git:      $(git --version 2>/dev/null || echo 'NOT INSTALLED')"
echo -e "  User:     $(whoami) (UID: $(id -u))"
echo -e "  Workdir:  $(pwd)"
echo ""

# ----------------------------------------------------------------------------
# Authentication Check
# ----------------------------------------------------------------------------
echo -e "${CYAN}[$(date '+%H:%M:%S')] Authentication:${NC}"
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo -e "  Claude: API key configured"
elif [ -f "$claude_dir/.credentials.json" ] || [ -f "$claude_dir/credentials.json" ] || [ -f "/.claude/.credentials.json" ]; then
    echo -e "  Claude: Login credentials found"
else
    echo -e "${YELLOW}  WARNING: No Claude auth found! Run 'claude login' or set ANTHROPIC_API_KEY${NC}"
fi
echo ""

# ============================================================================
# MAIN LOOP
# ============================================================================

rate_limit_count=0
i=1

while [ $MAX_ITERATIONS -eq 0 ] || [ $i -le $MAX_ITERATIONS ]; do
    echo -e "${GREEN}=====================================================${NC}"
    echo -e "${GREEN} Iteration $i${NC}"
    echo -e "${GREEN}=====================================================${NC}"

    # Run Claude CLI
    echo -e "${CYAN}[$(date '+%H:%M:%S')] Starting Claude CLI...${NC}"
    
    set +e
    output=$(claude --dangerously-skip-permissions -p "@prompt.md @progress.txt" 2>&1)
    exit_code=$?
    set -e
    
    echo ""
    echo "$output"
    echo ""
    echo -e "${CYAN}[$(date '+%H:%M:%S')] Exit code: $exit_code${NC}"
    
    # ------------------------------------------------------------------------
    # Handle Rate Limiting
    # ------------------------------------------------------------------------
    if echo "$output" | grep -qi "hit your limit\|rate limit\|resets.*am\|resets.*pm"; then
        rate_limit_count=$((rate_limit_count + 1))
        reset_time=$(echo "$output" | grep -oP 'resets \K[0-9]+[ap]m.*' | head -1 || echo "unknown")
        
        echo ""
        echo -e "${YELLOW}========================================${NC}"
        echo -e "${YELLOW} Rate limit hit (#${rate_limit_count})${NC}"
        echo -e "${YELLOW} Reset: ${reset_time}${NC}"
        echo -e "${YELLOW} Waiting ${RETRY_DELAY}s...${NC}"
        echo -e "${YELLOW}========================================${NC}"
        
        sleep $RETRY_DELAY
        continue
    fi
    
    rate_limit_count=0
    
    # ------------------------------------------------------------------------
    # Handle Errors
    # ------------------------------------------------------------------------

    if echo "$output" | grep -qi "OAuth token has expired\|authentication_error"; then
        echo -e "${YELLOW}OAuth token expired. Attempting refresh...${NC}"
        claude --version 2>&1  # Trigger token refresh
        sleep 2
        continue
    fi
    
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}ERROR: Claude crashed (exit $exit_code). Retrying in ${ERROR_RETRY_DELAY}s...${NC}"
        sleep $ERROR_RETRY_DELAY
        continue
    fi
    
    # ------------------------------------------------------------------------
    # Check for Completion
    # ------------------------------------------------------------------------
    if echo "$output" | grep -q "<promise>COMPLETE</promise>"; then
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN} All tasks complete!${NC}"
        echo -e "${GREEN}========================================${NC}"
        
        if [ "$AUTO_PUSH" = "true" ]; then
            echo -e "${CYAN}Pushing final changes...${NC}"
            git push || echo -e "${YELLOW}Push failed or nothing to push${NC}"
        fi
        
        exit 0
    fi
    
    # ------------------------------------------------------------------------
    # Auto-Push
    # ------------------------------------------------------------------------
    if [ "$AUTO_PUSH" = "true" ]; then
        if git log origin/$(git branch --show-current)..HEAD --oneline 2>/dev/null | grep -q .; then
            echo -e "${CYAN}Pushing commits...${NC}"
            git push || echo -e "${YELLOW}Push failed${NC}"
        fi
    fi
    
    i=$((i + 1))
done

echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW} Max iterations ($MAX_ITERATIONS) reached${NC}"
echo -e "${YELLOW}========================================${NC}"
