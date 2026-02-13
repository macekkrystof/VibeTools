# VibeTools

**Put an AI in a loop. Watch it code. Go grab a coffee.**

VibeTools is a framework for running autonomous AI coding agents in an iterative loop. You give it a task list (PRD), a prompt, and a runner script. It does the rest — implementing features, writing tests, committing code, handling rate limits, recovering from errors, and pushing to git — all while you pretend to be productive elsewhere.

## Meet Ralph

Ralph is the autonomous agent at the heart of VibeTools. Named after... honestly, we don't remember. But Ralph shows up, picks up the next task from the backlog, writes the code, writes the tests, and if everything passes — commits and moves on. If something breaks, Ralph writes down what went wrong, takes a deep breath (well, waits 5 seconds), and tries again.

If the same problem stumps Ralph for 2 iterations in a row, Ralph does what any senior engineer would do: **skips it and moves on**. Life's too short. Tokens aren't free.

When every task is done, Ralph outputs `<promise>COMPLETE</promise>` — which is the AI equivalent of dropping the mic.

### The Ralph Loop

```
┌─────────────────────────────────────────┐
│          Ralph Loop (simplified)         │
├─────────────────────────────────────────┤
│                                         │
│   ┌──→ Pick next task from PRD          │
│   │    Implement it                     │
│   │    Write tests                      │
│   │    Run tests                        │
│   │         │                           │
│   │    ┌────┴────┐                      │
│   │    │ Pass?   │                      │
│   │    └────┬────┘                      │
│   │     Yes │  No                       │
│   │      │  └──→ Log failure            │
│   │      │       Try again next loop    │
│   │      ▼                              │
│   │    Commit & push                    │
│   │    All done? ──Yes──→ 🎤⬇️          │
│   │      │                              │
│   │      No                             │
│   └──────┘                              │
│                                         │
│   Meanwhile: rate limits, crashes,      │
│   OAuth expiry — Ralph handles it all.  │
└─────────────────────────────────────────┘
```

## Features

- **Autonomous iteration** — runs the AI agent in a loop until all tasks are complete (or the heat death of the universe, whichever comes first)
- **Multi-agent support** — works with [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) and [OpenAI Codex CLI](https://github.com/openai/codex)
- **Cross-platform** — PowerShell scripts for Windows, Bash script for Linux/Docker
- **Rate limit resilience** — detects rate limits, waits, retries automatically (Ralph is very patient)
- **Error recovery** — handles crashes, OAuth token expiry, empty outputs, and other fun surprises
- **Auto-push** — commits and pushes to git after each successful task
- **Progress memory** — Ralph learns from previous iterations via `progress.txt`, so it doesn't repeat the same mistakes (unlike some of us)
- **Completion detection** — knows when to stop via the `<promise>COMPLETE</promise>` marker
- **Failure strategy** — skips tasks after 2 failed attempts to prevent infinite loops and wallet drain

## Project Structure

```
Ralph loop/
├── prompt.md           # Agent instructions (Ralph's job description)
├── prd.md              # Task list with pass/fail tracking (Ralph's TODO list)
├── progress.txt        # Iteration log & learnings (Ralph's diary)
├── activity.md         # Audit trail (Ralph's timesheet)
├── ralph-claude.ps1    # Windows runner for Claude CLI
├── ralph-codex.ps1     # Windows runner for Codex CLI
└── ralph.sh            # Linux/Docker runner for Claude CLI
```

## Quick Start

### 1. Set up your PRD

Edit `Ralph loop/prd.md` with your project description and task list:

```json
[
  {
    "id": 1,
    "title": "Add user authentication",
    "description": "Implement JWT-based auth with login/register endpoints.",
    "passes": false
  },
  {
    "id": 2,
    "title": "Create dashboard page",
    "description": "Build a responsive dashboard showing user stats.",
    "passes": false
  }
]
```

### 2. Customize the prompt

Edit `Ralph loop/prompt.md` to match your project's tech stack and conventions. The default is geared toward .NET / Blazor / NUnit / Playwright, but Ralph is flexible.

### 3. Run Ralph

**Windows (Claude):**
```powershell
cd "Ralph loop"
.\ralph-claude.ps1
```

**Windows (Codex):**
```powershell
cd "Ralph loop"
.\ralph-codex.ps1 -Model "o4-mini"
```

**Linux / Docker (Claude):**
```bash
cd "Ralph loop"
./ralph.sh
```

### 4. Go do something else

Ralph will iterate through tasks, test, commit, push, and handle errors. Come back when it's done. Or don't. Ralph doesn't need supervision. Ralph doesn't need encouragement. Ralph just works.

## Configuration

### Claude Runner (`ralph-claude.ps1`)

| Parameter | Default | Description |
|---|---|---|
| `-Max` | `0` | Max iterations (0 = unlimited) |
| `-RetryDelay` | `60` | Seconds to wait on rate limit |
| `-ErrorRetryDelay` | `5` | Seconds to wait on error |
| `-AutoPush` | `$true` | Auto-push commits to remote |

### Codex Runner (`ralph-codex.ps1`)

All of the above, plus:

| Parameter | Default | Description |
|---|---|---|
| `-Model` | *(Codex default)* | OpenAI model to use |

### Bash Runner (`ralph.sh`)

Uses environment variables: `MAX_ITERATIONS`, `RETRY_DELAY`, `ERROR_RETRY_DELAY`, `AUTO_PUSH`, `CLAUDE_CONFIG_DIR`, `ANTHROPIC_API_KEY`.

## How It Works

1. **Ralph reads the PRD** — finds the next task marked `"passes": false`
2. **Ralph implements it** — writes code, writes unit tests, writes UI tests
3. **Ralph runs the tests** — build, unit tests, UI tests, visual checks
4. **If tests pass** — marks the task complete, commits with `feat: [description]`, updates progress log
5. **If tests fail** — logs what went wrong in `progress.txt`, does NOT commit, tries again next iteration
6. **If stuck for 2 iterations** — skips the task, moves on (pragmatism > perfectionism)
7. **If all tasks pass** — outputs `<promise>COMPLETE</promise>` and Ralph clocks out

The runner scripts handle everything around this loop: rate limits, retries, auth refresh, git push, and graceful shutdown.

## Prerequisites

- **Claude CLI** (`claude`) or **Codex CLI** (`codex`) installed and authenticated
- **Git** configured with push access to your remote
- Your project's build tools (e.g., `dotnet`, `node`, etc.)

## FAQ

**Q: Why "Ralph"?**
A: Every autonomous agent deserves a name. Ralph felt right. Ralph is dependable. Ralph doesn't complain about code reviews. Ralph is the coworker we all wish we had.

**Q: What if Ralph gets stuck in an infinite loop?**
A: Ralph has a 2-iteration rule. If the same task fails twice, Ralph skips it. Also, you can set `-Max` to cap the total number of iterations. Ralph respects boundaries.

**Q: What if I hit API rate limits?**
A: Ralph waits patiently and retries. Ralph has been rate-limited more times than it can count (it actually does count — check the logs). Ralph doesn't take it personally.

**Q: Can Ralph work on any project?**
A: The default prompt is tuned for .NET/Blazor/NUnit/Playwright, but you can customize `prompt.md` for any stack. Ralph is adaptable. Ralph contains multitudes.

**Q: Is this vibe coding?**
A: This is *autonomous* vibe coding. You set the vibe. Ralph does the coding.

## License

Do whatever you want with it. Ralph doesn't care. Ralph just wants to code.
