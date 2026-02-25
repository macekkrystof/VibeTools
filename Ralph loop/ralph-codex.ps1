# ============================================================================
# Ralph - Autonomous Codex CLI Agent Runner
# ============================================================================
# Windows/PowerShell version with infinite retry on rate limits.
# Runs OpenAI Codex CLI in a loop, automatically handles rate limits and errors.
# Features: UTF-8 support, empty output guard, git state tracking,
#           launch failure detection, configurable push frequency.
#
# Parameters:
#   -Max              - Max iterations (0 = unlimited, default: 0)
#   -RetryDelay       - Seconds to wait when rate limited (default: 60)
#   -ErrorRetryDelay  - Seconds to wait on errors (default: 5)
#   -AutoPush         - Auto-push commits after each iteration (default: $true)
#   -PushEveryN       - Push every N iterations (default: 1)
#   -Model            - Model to use (default: uses Codex default)
# ============================================================================

param(
    [int]$Max = 0,
    [int]$RetryDelay = 60,
    [int]$ErrorRetryDelay = 5,
    [bool]$AutoPush = $true,
    [int]$PushEveryN = 1,
    [string]$Model = ""
)

# ============================================================================
# UTF-8 ENCODING (diacritics support)
# ============================================================================
chcp 65001 > $null 2>&1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Prevent ErrorRecord objects from stderr (RemoteException) from terminating the script
$ErrorActionPreference = 'Continue'

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] $Message" -ForegroundColor $Color
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
Write-Host " Ralph - Autonomous Code Agent (Codex)" -ForegroundColor Cyan
if ($Max -eq 0) {
    Write-Host " Iterations: unlimited" -ForegroundColor Cyan
} else {
    Write-Host " Max iterations: $Max" -ForegroundColor Cyan
}
Write-Host " Auto-push: $AutoPush (every $PushEveryN iterations)" -ForegroundColor Cyan
if ($Model) {
    Write-Host " Model: $Model" -ForegroundColor Cyan
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ----------------------------------------------------------------------------
# Environment Check
# ----------------------------------------------------------------------------

$timestamp = Get-Date -Format "HH:mm:ss"
Write-Host "[$timestamp] Environment:" -ForegroundColor Cyan

$nodeVer = try { node --version 2>&1 } catch { "NOT INSTALLED" }
$codexVer = try { codex.cmd --version 2>&1 } catch { "NOT INSTALLED" }
$gitVer = try { git --version 2>&1 } catch { "NOT INSTALLED" }

Write-Host "  Codex:    $codexVer"
Write-Host "  Node.js:  $nodeVer"
Write-Host "  Git:      $gitVer"
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

if ($env:OPENAI_API_KEY) {
    Write-Host "  Codex: OPENAI_API_KEY configured"
} elseif ((Test-Path (Join-Path $env:USERPROFILE ".codex\auth.json")) -or
          (Test-Path (Join-Path $env:APPDATA "codex\auth.json"))) {
    Write-Host "  Codex: Signed in via ChatGPT account"
} else {
    Write-Host "  WARNING: No auth found. Run 'codex' to sign in or set OPENAI_API_KEY" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# BUILD PROMPT
# ============================================================================

$promptFile = Join-Path (Get-Location) "prompt.md"
$progressFile = Join-Path (Get-Location) "progress.txt"

if (-not (Test-Path $promptFile)) {
    Write-Host "ERROR: prompt.md not found in $(Get-Location)" -ForegroundColor Red
    exit 1
}

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

    # Record git state BEFORE
    $headBefore = git rev-parse HEAD 2>&1
    if ($LASTEXITCODE -ne 0) { $headBefore = "unknown" }
    Write-Log "Git HEAD before: $(git log --oneline -1 2>&1)" "Cyan"

    # Build the prompt from files and write to temp file
    # (avoids Windows ~8191 char command-line length limit)
    $prompt = Get-Content $promptFile -Raw
    if (Test-Path $progressFile) {
        $prompt += "`n`n" + (Get-Content $progressFile -Raw)
    }
    $tempPrompt = Join-Path ([System.IO.Path]::GetTempPath()) "ralph-codex-prompt.md"
    # Write with UTF-8 BOM so child processes reliably detect encoding
    [System.IO.File]::WriteAllText($tempPrompt, $prompt, [System.Text.UTF8Encoding]::new($true))

    # Build Codex CLI arguments using "codex exec" (headless mode, no TTY needed)
    # --dangerously-bypass-approvals-and-sandbox: full write access
    $codexArgs = @("exec", "--dangerously-bypass-approvals-and-sandbox")
    if ($Model) {
        $codexArgs += @("-m", $Model)
    }
    $codexArgs += "Follow ALL instructions in the file: $tempPrompt"

    # Run Codex via codex.cmd (bypass .ps1 wrapper which fails with
    # StandardOutputEncoding error when stdout is piped)
    Write-Log "Starting Codex CLI (exec mode)..." "Cyan"

    $iterStart = Get-Date

    # Capture output, converting ErrorRecord objects (RemoteException) to plain strings
    $result = ""
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        & codex.cmd @codexArgs 2>&1 | ForEach-Object {
            # stderr lines arrive as ErrorRecord - extract the actual message
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $line = $_.Exception.Message
                # Skip bare type names that carry no useful info
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

    # Clean up temp prompt
    Remove-Item $tempPrompt -ErrorAction SilentlyContinue

    $iterDuration = [math]::Round(((Get-Date) - $iterStart).TotalSeconds)

    Write-Host ""
    Write-Log "Exit code: $exitCode (duration: ${iterDuration}s)" "Cyan"

    # Record git state AFTER
    $headAfter = git rev-parse HEAD 2>&1
    if ($LASTEXITCODE -ne 0) { $headAfter = "unknown" }
    Write-Log "Git HEAD after: $(git log --oneline -1 2>&1)" "Cyan"

    # Show new commits
    if ($headBefore -ne $headAfter -and $headBefore -ne "unknown") {
        $newCommits = git log --oneline "$headBefore..$headAfter" 2>&1
        if ($newCommits) {
            Write-Log "New commits:" "Cyan"
            $newCommits | ForEach-Object { Write-Host "    $_" }
        }
    } else {
        Write-Log "No new commits in this iteration."
    }

    # ------------------------------------------------------------------------
    # Handle Launch Failures
    # ------------------------------------------------------------------------
    if ($result -match "(?i)(StandardOutputEncoding|failed to run|Program.*failed|filename or extension is too long)") {
        Write-Host "FATAL: Codex CLI failed to launch:" -ForegroundColor Red
        Write-Host $result -ForegroundColor Red
        exit 1
    }

    # ------------------------------------------------------------------------
    # Handle Empty Output (3x = abort)
    # ------------------------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($result) -and $exitCode -eq 0) {
        $emptyCount++
        if ($emptyCount -ge 3) {
            Write-Host "FATAL: Codex produced no output 3 times in a row. Aborting." -ForegroundColor Red
            exit 1
        }
        Write-Log "WARNING: Codex produced no output. Retrying in ${ErrorRetryDelay}s... ($emptyCount/3)" "Yellow"
        Start-Sleep -Seconds $ErrorRetryDelay
        continue
    }
    $emptyCount = 0

    # ------------------------------------------------------------------------
    # Handle Errors (only when Codex actually failed)
    # ------------------------------------------------------------------------
    if ($exitCode -ne 0) {
        # Rate Limiting
        if ($result -match "(?i)(rate.?limit|too many requests|HTTP[/ ]429|status[:\s]429|quota exceeded|exceeded your.*quota)") {
            $rateLimitCount++

            Write-Host ""
            Write-Host "========================================" -ForegroundColor Yellow
            Write-Host " Rate limit hit (#$rateLimitCount)" -ForegroundColor Yellow
            Write-Host " Waiting ${RetryDelay}s..." -ForegroundColor Yellow
            Write-Host "========================================" -ForegroundColor Yellow

            Start-Sleep -Seconds $RetryDelay
            continue
        }

        $rateLimitCount = 0

        # Auth Errors
        if ($result -match "(?i)(invalid.*api.?key|authentication.?(error|fail)|unauthorized.*api|401.*unauthorized)") {
            Write-Host "Authentication error. Check your OPENAI_API_KEY." -ForegroundColor Red
            exit 1
        }

        # Other Errors
        Write-Log "ERROR: Codex exited with code $exitCode. Retrying in ${ErrorRetryDelay}s..." "Red"
        Start-Sleep -Seconds $ErrorRetryDelay
        $i++
        continue
    }

    $rateLimitCount = 0

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
