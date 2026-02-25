# ============================================================================
# Ralph - Autonomous Claude Code Agent Runner
# ============================================================================
# Windows/PowerShell version with infinite retry on rate limits.
# Runs Claude CLI in a loop, automatically handles rate limits and errors.
# Features: UTF-8 support, empty output guard, git state tracking,
#           configurable push frequency, orphan process cleanup.
#
# Parameters:
#   -Max              - Max iterations (0 = unlimited, default: 0)
#   -RetryDelay       - Seconds to wait when rate limited (default: 60)
#   -ErrorRetryDelay  - Seconds to wait on errors (default: 5)
#   -AutoPush         - Auto-push commits after each iteration (default: $true)
#   -PushEveryN       - Push every N iterations (default: 1)
#   -IterationTimeout - Max seconds per Claude invocation (default: 3600)
#   -PromptFiles      - Files to pass to Claude (default: "@prompt.md @progress.txt")
# ============================================================================

param(
    [int]$Max = 0,
    [int]$RetryDelay = 60,
    [int]$ErrorRetryDelay = 5,
    [bool]$AutoPush = $true,
    [int]$PushEveryN = 1,
    [int]$IterationTimeout = 3600,
    [string]$PromptFiles = "@prompt.md @progress.txt"
)

# ============================================================================
# UTF-8 ENCODING (diacritics support)
# ============================================================================
chcp 65001 > $null 2>&1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Prevent ErrorRecord objects from stderr from terminating the script
$ErrorActionPreference = 'Continue'

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] $Message" -ForegroundColor $Color
}

# Kill leftover processes from a previous Claude iteration.
# Customize patterns below for your project's tech stack.
function Stop-OrphanProcesses {
    Write-Log "Cleaning up orphaned processes..." "Cyan"
    # Common patterns - uncomment/modify as needed:
    # Get-Process -Name "dotnet" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "run" } | Stop-Process -Force -ErrorAction SilentlyContinue
    # Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "dev" } | Stop-Process -Force -ErrorAction SilentlyContinue
    # Get-Process -Name "chrome" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# Push commits to remote with proper error handling
function Push-Commits {
    $branch = git branch --show-current 2>&1
    if (-not $branch -or $LASTEXITCODE -ne 0) {
        Write-Log "Cannot determine current branch, skipping push" "Yellow"
        return
    }
    $unpushed = git log "origin/$branch..HEAD" --oneline 2>&1
    if ($unpushed -and $LASTEXITCODE -eq 0) {
        Write-Log "Pushing commits to origin/$branch..." "Cyan"
        git push 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Push successful" "Green"
        } else {
            Write-Log "Push failed" "Yellow"
        }
    } else {
        Write-Log "No new commits to push"
    }
}

# ============================================================================
# STARTUP BANNER
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Ralph - Autonomous Code Agent" -ForegroundColor Cyan
if ($Max -eq 0) {
    Write-Host " Iterations: unlimited" -ForegroundColor Cyan
} else {
    Write-Host " Max iterations: $Max" -ForegroundColor Cyan
}
Write-Host " Iteration timeout: ${IterationTimeout}s" -ForegroundColor Cyan
Write-Host " Auto-push: $AutoPush (every $PushEveryN iterations)" -ForegroundColor Cyan
Write-Host " Prompt files: $PromptFiles" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ----------------------------------------------------------------------------
# Environment Check
# ----------------------------------------------------------------------------

$timestamp = Get-Date -Format "HH:mm:ss"
Write-Host "[$timestamp] Environment:" -ForegroundColor Cyan

$claudeVer = try { claude --version 2>&1 } catch { "NOT INSTALLED" }
$gitVer = try { git --version 2>&1 } catch { "NOT INSTALLED" }
$nodeVer = try { node --version 2>&1 } catch { "NOT INSTALLED" }

Write-Host "  Claude:   $claudeVer"
Write-Host "  Git:      $gitVer"
Write-Host "  Node.js:  $nodeVer"
Write-Host "  User:     $env:USERNAME"
Write-Host "  Workdir:  $(Get-Location)"

# Detect optional tools
foreach ($tool in @("dotnet", "python", "cmake", "docker")) {
    try {
        $ver = & $tool --version 2>&1 | Select-Object -First 1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ${tool}:$((' ' * (8 - $tool.Length)))$ver"
        }
    } catch {}
}
Write-Host ""

# ----------------------------------------------------------------------------
# Authentication Check
# ----------------------------------------------------------------------------

$timestamp = Get-Date -Format "HH:mm:ss"
Write-Host "[$timestamp] Authentication:" -ForegroundColor Cyan

$claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { "$env:USERPROFILE\.claude" }

if ($env:ANTHROPIC_API_KEY) {
    Write-Host "  Claude: API key configured"
} elseif ((Test-Path "$claudeDir\.credentials.json") -or (Test-Path "$claudeDir\credentials.json")) {
    Write-Host "  Claude: Login credentials found"
} else {
    Write-Host "  WARNING: No Claude auth found! Run 'claude login' or set ANTHROPIC_API_KEY" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# MAIN LOOP
# ============================================================================

$rateLimitCount = 0
$emptyCount = 0
$i = 1

while (($Max -eq 0) -or ($i -le $Max)) {
    Write-Host "=====================================================" -ForegroundColor Green
    Write-Host " Iteration $i  ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Green
    Write-Host "=====================================================" -ForegroundColor Green

    # Cleanup orphans from previous iteration
    Stop-OrphanProcesses

    # Record git state BEFORE Claude run
    $headBefore = git rev-parse HEAD 2>&1
    if ($LASTEXITCODE -ne 0) { $headBefore = "unknown" }
    Write-Log "Git HEAD before: $(git log --oneline -1 2>&1)" "Cyan"

    # Run Claude CLI
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] Starting Claude CLI (timeout: ${IterationTimeout}s)..." -ForegroundColor Cyan

    $iterStart = Get-Date
    $result = ""
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        claude --dangerously-skip-permissions -p "$PromptFiles" 2>&1 | ForEach-Object {
            # stderr lines may arrive as ErrorRecord - extract the actual message
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $line = $_.Exception.Message
                if ($line -match '^System\.' -or [string]::IsNullOrWhiteSpace($line)) { return }
            } else {
                $line = "$_"
            }
            Write-Host $line
            $result += "$line`n"
        }
        $exitCode = $LASTEXITCODE
    } catch {
        Write-Host "Pipeline error: $($_.Exception.Message)" -ForegroundColor Yellow
        $exitCode = if ($LASTEXITCODE) { $LASTEXITCODE } else { 1 }
    } finally {
        $ErrorActionPreference = $oldEAP
    }

    $iterDuration = [math]::Round(((Get-Date) - $iterStart).TotalSeconds)

    Write-Host ""
    Write-Log "Exit code: $exitCode (duration: ${iterDuration}s)" "Cyan"

    # Record git state AFTER Claude run
    $headAfter = git rev-parse HEAD 2>&1
    if ($LASTEXITCODE -ne 0) { $headAfter = "unknown" }
    Write-Log "Git HEAD after: $(git log --oneline -1 2>&1)" "Cyan"

    # Show new commits made during this iteration
    if ($headBefore -ne $headAfter -and $headBefore -ne "unknown") {
        $newCommits = git log --oneline "$headBefore..$headAfter" 2>&1
        if ($newCommits) {
            Write-Log "New commits:" "Cyan"
            $newCommits | ForEach-Object { Write-Host "    $_" }
        }
    } else {
        Write-Log "No new commits in this iteration."
    }

    # Cleanup after Claude finishes
    Stop-OrphanProcesses

    # Warn if iteration exceeded timeout (PS can't hard-kill like bash timeout)
    if ($iterDuration -gt $IterationTimeout) {
        Write-Log "WARNING: Iteration exceeded timeout (${iterDuration}s > ${IterationTimeout}s)" "Yellow"
    }

    # ------------------------------------------------------------------------
    # Handle Empty Output (3x = abort)
    # ------------------------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($result) -and $exitCode -eq 0) {
        $emptyCount++
        if ($emptyCount -ge 3) {
            Write-Host "FATAL: Claude produced no output 3 times in a row. Aborting." -ForegroundColor Red
            exit 1
        }
        Write-Log "WARNING: Claude produced no output. Retrying in ${ErrorRetryDelay}s... ($emptyCount/3)" "Yellow"
        Start-Sleep -Seconds $ErrorRetryDelay
        continue
    }
    $emptyCount = 0

    # ------------------------------------------------------------------------
    # Handle Rate Limiting
    # ------------------------------------------------------------------------
    if ($result -match "(?i)(hit your limit|rate limit|resets\s+\d+[ap]m)") {
        $rateLimitCount++

        $resetTime = "unknown"
        if ($result -match "resets\s+(\d+[ap]m\S*)") {
            $resetTime = $Matches[1]
        }

        Write-Host ""
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host " Rate limit hit (#$rateLimitCount)" -ForegroundColor Yellow
        Write-Host " Reset: $resetTime" -ForegroundColor Yellow
        Write-Host " Waiting ${RetryDelay}s..." -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Yellow

        Start-Sleep -Seconds $RetryDelay
        continue
    }

    $rateLimitCount = 0

    # ------------------------------------------------------------------------
    # Handle OAuth Token Expiry
    # ------------------------------------------------------------------------
    if ($result -match "(?i)(OAuth token has expired|authentication_error)") {
        Write-Log "OAuth token expired. Attempting refresh..." "Yellow"
        claude --version 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        continue
    }

    # ------------------------------------------------------------------------
    # Handle Errors
    # ------------------------------------------------------------------------
    if ($exitCode -ne 0) {
        Write-Log "ERROR: Claude exited with code $exitCode. Retrying in ${ErrorRetryDelay}s..." "Red"
        Start-Sleep -Seconds $ErrorRetryDelay
        $i++
        continue
    }

    # ------------------------------------------------------------------------
    # Check for Completion
    # ------------------------------------------------------------------------
    if ($result -match "<promise>COMPLETE</promise>") {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host " All tasks complete!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green

        if ($AutoPush) {
            Write-Log "Pushing final changes..." "Cyan"
            Push-Commits
        }

        exit 0
    }

    # ------------------------------------------------------------------------
    # Auto-Push (every N iterations)
    # ------------------------------------------------------------------------
    if ($AutoPush -and ($i % $PushEveryN -eq 0)) {
        Push-Commits
    }

    $i++
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host " Max iterations ($Max) reached" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

# Final push when max iterations reached
if ($AutoPush) {
    Write-Log "Final push..." "Cyan"
    Push-Commits
}
