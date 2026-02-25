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
│   │    All done? ──Yes──→ COMPLETE      │
│   │      │                              │
│   │      No                             │
│   └──────┘                              │
│                                         │
│   Meanwhile: rate limits, crashes,      │
│   timeouts, OAuth expiry, orphan        │
│   processes — Ralph handles it all.     │
└─────────────────────────────────────────┘
```

## Features

- **Autonomous iteration** — runs the AI agent in a loop until all tasks are complete (or the heat death of the universe, whichever comes first)
- **Multi-agent support** — works with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [OpenAI Codex CLI](https://github.com/openai/codex)
- **Cross-platform** — PowerShell scripts for Windows, Bash scripts for Linux/Docker
- **Docker-ready** — Dockerfile + docker-compose templates with auto-updating CLIs on every start
- **Rate limit resilience** — detects rate limits, waits, retries automatically (Ralph is very patient)
- **Error recovery** — handles crashes, OAuth token expiry, empty outputs, and other fun surprises
- **Iteration timeout** — kills stuck iterations after a configurable limit (default: 1 hour)
- **Orphan process cleanup** — kills leftover processes (dev servers, browsers) between iterations
- **Persistent logging** — logs to both stdout and a persistent log file for post-mortem analysis
- **Git state tracking** — records HEAD before/after each iteration, shows new commits
- **Auto-push** — commits and pushes to git, with configurable frequency (every N iterations)
- **QA subagent** — launches a separate Playwright-based visual QA agent for UI verification
- **Progress memory** — Ralph learns from previous iterations via `progress.txt`, so it doesn't repeat the same mistakes (unlike some of us)
- **Completion detection** — knows when to stop via the `<promise>COMPLETE</promise>` marker
- **Failure strategy** — skips tasks after 2 failed attempts to prevent infinite loops and wallet drain

## Project Structure

```
Ralph loop/
├── prompt.md               # Agent instructions (Ralph's job description)
├── prd.md                  # Task list with status tracking (Ralph's TODO list)
├── progress.txt            # Iteration log & learnings (Ralph's diary)
├── activity.md             # Audit trail (Ralph's timesheet)
│
├── ralph-claude.ps1        # Windows runner — Claude Code
├── ralph-codex.ps1         # Windows runner — OpenAI Codex
├── ralph.sh                # Linux/Docker runner — Claude Code
├── ralph-codex.sh          # Linux/Docker runner — OpenAI Codex
│
├── Dockerfile.ralph        # Docker image template (customize per project)
├── docker-compose.ralph.yml # Docker Compose with claude + codex services
├── run-ralph-claude.sh     # Convenience: build & start Claude container
├── run-ralph-codex.sh      # Convenience: build & start Codex container
│
└── tasks.md                # (Optional) detailed audit/reference notes
```

## Quick Start

### 1. Set up your PRD

Edit `Ralph loop/prd.md` with your project description and task list:

```json
[
  {
    "id": "TASK-001",
    "title": "Add user authentication",
    "description": "Implement JWT-based auth with login/register endpoints.",
    "priority": "high",
    "status": "planned",
    "created": "2025-01-01",
    "completed": null
  },
  {
    "id": "TASK-002",
    "title": "Create dashboard page",
    "description": "Build a responsive dashboard showing user stats.",
    "priority": "medium",
    "status": "planned",
    "created": "2025-01-01",
    "completed": null
  }
]
```

### 2. Customize the prompt

Edit `Ralph loop/prompt.md` to match your project's tech stack and conventions. Fill in the Build Commands section, adjust the QA verification steps, and set project-specific notes. Ralph is flexible — works with any stack.

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

**Linux / Docker (Codex):**
```bash
cd "Ralph loop"
./ralph-codex.sh
```

**Docker Compose:**
```bash
cd "Ralph loop"
./run-ralph-claude.sh                # build & start Claude agent
./run-ralph-codex.sh                 # build & start Codex agent
./run-ralph-claude.sh --detach       # run in background
./run-ralph-claude.sh down           # stop
```

### 4. Go do something else

Ralph will iterate through tasks, test, commit, push, and handle errors. Come back when it's done. Or don't. Ralph doesn't need supervision. Ralph doesn't need encouragement. Ralph just works.

## Configuration

### Claude Runners

**PowerShell** (`ralph-claude.ps1`):

| Parameter | Default | Description |
|---|---|---|
| `-Max` | `0` | Max iterations (0 = unlimited) |
| `-RetryDelay` | `60` | Seconds to wait on rate limit |
| `-ErrorRetryDelay` | `5` | Seconds to wait on error |
| `-AutoPush` | `$true` | Auto-push commits to remote |
| `-PushEveryN` | `1` | Push every N iterations |
| `-IterationTimeout` | `3600` | Max seconds per iteration (warning only on PS) |
| `-PromptFiles` | `@prompt.md @progress.txt` | Files to pass to Claude |

**Bash** (`ralph.sh`):

| Environment Variable | Default | Description |
|---|---|---|
| `MAX_ITERATIONS` | `0` | Max iterations (0 = unlimited) |
| `RETRY_DELAY` | `60` | Seconds to wait on rate limit |
| `ERROR_RETRY_DELAY` | `5` | Seconds to wait on error |
| `AUTO_PUSH` | `true` | Auto-push commits to remote |
| `PUSH_EVERY_N` | `1` | Push every N iterations |
| `ITERATION_TIMEOUT` | `3600` | Max seconds per iteration (hard kill) |
| `PROMPT_FILES` | `@prompt.md @progress.txt` | Files to pass to Claude |
| `LOGDIR` | `/app/.claude/logs` | Log file directory |
| `CLAUDE_CONFIG_DIR` | — | Path to Claude credentials |
| `ANTHROPIC_API_KEY` | — | API key (alternative to login) |

### Codex Runners

Same parameters as above, plus:

| Parameter / Env Var | Default | Description |
|---|---|---|
| `-Model` / `CODEX_MODEL` | *(Codex default)* | OpenAI model to use |

### Docker

| Variable | Default | Description |
|---|---|---|
| `HOST_UID` | `1000` | Host user UID (for volume permissions) |
| `HOST_GID` | `1000` | Host user GID |
| `GIT_AUTHOR_NAME` | `Ralph Agent` | Git commit author |
| `GIT_AUTHOR_EMAIL` | `ralph@localhost` | Git commit email |

CLIs are **auto-updated on every container start** via npm, so you always get the latest version without rebuilding the image.

## How It Works

1. **Ralph reads the PRD** — finds the next task with status `planned`
2. **Ralph checks progress.txt** — reads learnings from previous iterations
3. **Ralph implements it** — writes code, writes tests, does one task per iteration
4. **Ralph runs the tests** — build, unit tests, UI tests, visual QA via subagent
5. **If tests pass** — marks the task `done`, commits with `feat: [description]`, updates progress log
6. **If tests fail** — logs what went wrong in `progress.txt`, does NOT commit, tries again next iteration
7. **If stuck for 2 iterations** — skips the task, moves on (pragmatism > perfectionism)
8. **If all tasks are done** — outputs `<promise>COMPLETE</promise>` and Ralph clocks out

The runner scripts handle everything around this loop: rate limits, retries, auth refresh, timeouts, orphan cleanup, git push, and graceful shutdown.

## Docker Setup

1. **Customize `Dockerfile.ralph`** — change the base image for your stack, add project dependencies
2. **Customize `docker-compose.ralph.yml`** — add database services, adjust env vars, set volume mounts
3. **Run:**
   ```bash
   ./run-ralph-claude.sh --build     # first run (builds image)
   ./run-ralph-claude.sh             # subsequent runs
   ./run-ralph-claude.sh --detach    # background mode
   ```

The Dockerfile uses a user-writable npm prefix, so the CLI auto-updates on each start without needing root.

## Prerequisites

- **Claude Code** (`claude`) or **Codex CLI** (`codex`) installed and authenticated
- **Git** configured with push access to your remote
- Your project's build tools (e.g., `dotnet`, `node`, `cmake`, etc.)
- **Docker** (optional, for containerized runs)

## FAQ

**Q: Why "Ralph"?**
A: Every autonomous agent deserves a name. Ralph felt right. Ralph is dependable. Ralph doesn't complain about code reviews. Ralph is the coworker we all wish we had.

**Q: What if Ralph gets stuck in an infinite loop?**
A: Ralph has a 2-iteration rule. If the same task fails twice, Ralph skips it. Plus, `ITERATION_TIMEOUT` kills stuck iterations after 1 hour. You can also set `-Max` to cap total iterations. Ralph respects boundaries.

**Q: What if I hit API rate limits?**
A: Ralph waits patiently and retries. Ralph has been rate-limited more times than it can count (it actually does count — check the logs). Ralph doesn't take it personally.

**Q: Can Ralph work on any project?**
A: Yes. Customize `prompt.md` and `prd.md` for your stack. Ralph has been battle-tested on .NET, Node.js, C++, and Python projects. Ralph contains multitudes.

**Q: What about leftover processes (dev servers, browsers)?**
A: `cleanup_orphans()` in `ralph.sh` kills them between iterations. Uncomment and customize the patterns for your stack.

**Q: Does the Docker container auto-update the CLI?**
A: Yes. On every container start, `npm install -g` runs to pull the latest version. No image rebuild needed.

**Q: Is this vibe coding?**
A: This is *autonomous* vibe coding. You set the vibe. Ralph does the coding.

## License

Do whatever you want with it. Ralph doesn't care. Ralph just wants to code.
