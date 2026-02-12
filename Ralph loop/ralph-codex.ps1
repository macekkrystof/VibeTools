# ============================================================================
# Ralph - Autonomous Codex CLI Agent Runner
# ============================================================================
# Windows/PowerShell version with infinite retry on rate limits.
# Runs OpenAI Codex CLI in a loop, automatically handles rate limits and errors.
#
# Parameters:
#   -Max              - Max iterations (0 = unlimited, default: 0)
#   -RetryDelay       - Seconds to wait when rate limited (default: 60)
#   -ErrorRetryDelay  - Seconds to wait on errors (default: 5)
#   -AutoPush         - Auto-push commits after each iteration (default: $true)
#   -Model            - Model to use (default: uses Codex default)
# ============================================================================

param(
    [int]$Max = 0,
    [int]$RetryDelay = 60,
    [int]$ErrorRetryDelay = 5,
    [bool]$AutoPush = $true,
    [string]$Model = ""
)

# ============================================================================
# UTF-8 ENCODING (Czech diacritics support)
# ============================================================================
chcp 65001 > $null 2>&1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

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
Write-Host " Auto-push: $AutoPush" -ForegroundColor Cyan
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

$dotnetVer = try { dotnet --version 2>&1 } catch { "NOT INSTALLED" }
$nodeVer = try { node --version 2>&1 } catch { "NOT INSTALLED" }
$codexVer = try { codex.cmd --version 2>&1 } catch { "NOT INSTALLED" }
$gitVer = try { git --version 2>&1 } catch { "NOT INSTALLED" }

Write-Host "  .NET SDK: $dotnetVer"
Write-Host "  Node.js:  $nodeVer"
Write-Host "  Codex:    $codexVer"
Write-Host "  Git:      $gitVer"
Write-Host "  User:     $env:USERNAME"
Write-Host "  Workdir:  $(Get-Location)"
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
    Write-Host " Iteration $i" -ForegroundColor Green
    Write-Host "=====================================================" -ForegroundColor Green

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
    # --dangerously-bypass-approvals-and-sandbox: full write access (conflicts with --full-auto)
    $codexArgs = @("exec", "--dangerously-bypass-approvals-and-sandbox")
    if ($Model) {
        $codexArgs += @("-m", $Model)
    }
    $codexArgs += "Follow ALL instructions in the file: $tempPrompt"

    # Run Codex via codex.cmd (bypass .ps1 wrapper which fails with
    # StandardOutputEncoding error when stdout is piped)
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] Starting Codex CLI (exec mode)..." -ForegroundColor Cyan

    $result = ""
    & codex.cmd @codexArgs 2>&1 | ForEach-Object {
        Write-Host $_
        $result += "$_`n"
    }
    $exitCode = $LASTEXITCODE

    # Clean up temp prompt
    Remove-Item $tempPrompt -ErrorAction SilentlyContinue

    Write-Host ""
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] Exit code: $exitCode" -ForegroundColor Cyan

    # ------------------------------------------------------------------------
    # Handle Launch Failures
    # ------------------------------------------------------------------------
    if ($result -match "(?i)(StandardOutputEncoding|failed to run|Program.*failed|filename or extension is too long)") {
        Write-Host "FATAL: Codex CLI failed to launch:" -ForegroundColor Red
        Write-Host $result -ForegroundColor Red
        exit 1
    }

    # Guard: if result is empty/whitespace and codex produced no output, something went wrong
    if ([string]::IsNullOrWhiteSpace($result) -and $exitCode -eq 0) {
        $emptyCount++
        if ($emptyCount -ge 3) {
            Write-Host "FATAL: Codex produced no output 3 times in a row. Aborting." -ForegroundColor Red
            exit 1
        }
        Write-Host "WARNING: Codex produced no output. Retrying in ${ErrorRetryDelay}s... ($emptyCount/3)" -ForegroundColor Yellow
        Start-Sleep -Seconds $ErrorRetryDelay
        continue
    }
    $emptyCount = 0

    # ------------------------------------------------------------------------
    # Handle Rate Limiting
    # ------------------------------------------------------------------------
    if ($result -match "(?i)(rate.?limit|too many requests|429|quota exceeded|exceeded.*limit)") {
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

    # ------------------------------------------------------------------------
    # Handle Auth Errors
    # ------------------------------------------------------------------------
    if ($result -match "(?i)(invalid.*api.?key|authentication.?(error|fail)|unauthorized.*api|401.*unauthorized)") {
        Write-Host "Authentication error. Check your OPENAI_API_KEY." -ForegroundColor Red
        exit 1
    }

    # ------------------------------------------------------------------------
    # Handle Errors
    # ------------------------------------------------------------------------
    if ($exitCode -ne 0) {
        Write-Host "ERROR: Codex crashed (exit $exitCode). Retrying in ${ErrorRetryDelay}s..." -ForegroundColor Red
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
