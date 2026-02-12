# ============================================================================
# Ralph - Autonomous Claude Code Agent Runner
# ============================================================================
# Windows/PowerShell version with infinite retry on rate limits.
# Runs Claude CLI in a loop, automatically handles rate limits and errors.
#
# Parameters:
#   -Max              - Max iterations (0 = unlimited, default: 0)
#   -RetryDelay       - Seconds to wait when rate limited (default: 60)
#   -ErrorRetryDelay  - Seconds to wait on errors (default: 5)
#   -AutoPush         - Auto-push commits after each iteration (default: $true)
# ============================================================================

param(
    [int]$Max = 0,
    [int]$RetryDelay = 60,
    [int]$ErrorRetryDelay = 5,
    [bool]$AutoPush = $true
)

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
Write-Host " Auto-push: $AutoPush" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ----------------------------------------------------------------------------
# Environment Check
# ----------------------------------------------------------------------------

$timestamp = Get-Date -Format "HH:mm:ss"
Write-Host "[$timestamp] Environment:" -ForegroundColor Cyan

$dotnetVer = try { dotnet --version 2>&1 } catch { "NOT INSTALLED" }
$nodeVer = try { node --version 2>&1 } catch { "NOT INSTALLED" }
$claudeVer = try { claude --version 2>&1 } catch { "NOT INSTALLED" }
$gitVer = try { git --version 2>&1 } catch { "NOT INSTALLED" }

Write-Host "  .NET SDK: $dotnetVer"
Write-Host "  Node.js:  $nodeVer"
Write-Host "  Claude:   $claudeVer"
Write-Host "  Git:      $gitVer"
Write-Host "  User:     $env:USERNAME"
Write-Host "  Workdir:  $(Get-Location)"
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
$i = 1

while (($Max -eq 0) -or ($i -le $Max)) {
    Write-Host "=====================================================" -ForegroundColor Green
    Write-Host " Iteration $i" -ForegroundColor Green
    Write-Host "=====================================================" -ForegroundColor Green

    # Run Claude CLI
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] Starting Claude CLI..." -ForegroundColor Cyan

    $result = ""
    claude --dangerously-skip-permissions -p "@prompt.md @progress.txt" 2>&1 | ForEach-Object {
        Write-Host $_
        $result += "$_`n"
    }
    $exitCode = $LASTEXITCODE

    Write-Host ""
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] Exit code: $exitCode" -ForegroundColor Cyan

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
        Write-Host "OAuth token expired. Attempting refresh..." -ForegroundColor Yellow
        claude --version 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        continue
    }

    # ------------------------------------------------------------------------
    # Handle Errors
    # ------------------------------------------------------------------------
    if ($exitCode -ne 0) {
        Write-Host "ERROR: Claude crashed (exit $exitCode). Retrying in ${ErrorRetryDelay}s..." -ForegroundColor Red
        Start-Sleep -Seconds $ErrorRetryDelay
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
            Write-Host "Pushing final changes..." -ForegroundColor Cyan
            git push 2>&1 | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Push failed or nothing to push" -ForegroundColor Yellow
            }
        }

        exit 0
    }

    # ------------------------------------------------------------------------
    # Auto-Push
    # ------------------------------------------------------------------------
    if ($AutoPush) {
        $currentBranch = git branch --show-current 2>&1
        $unpushed = git log "origin/$currentBranch..HEAD" --oneline 2>&1
        if ($unpushed -and $LASTEXITCODE -eq 0) {
            Write-Host "Pushing commits..." -ForegroundColor Cyan
            git push 2>&1 | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Push failed" -ForegroundColor Yellow
            }
        }
    }

    $i++
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host " Max iterations ($Max) reached" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
