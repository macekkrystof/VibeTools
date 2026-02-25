# PRD

## Overview
*(Brief description of the project or feature.)*

## Target Audience
*(Who is this application/feature for.)*

## Key Features
*(List of key requirements and functionalities.)*

## Tech Stack
- Backend: *e.g., ASP.NET Core 9 (C#), EF Core / Node.js, Express / C++, CMake*
- Frontend: *e.g., Blazor WASM / React / Vue.js*
- Testing: *e.g., NUnit, xUnit / Jest, Vitest / CTest*
- Other: *e.g., SignalR, Docker, PostgreSQL...*

## Build Commands

```bash
# Build
# dotnet build -c Debug
# npm run build
# cmake --build build

# Test
# dotnet test
# npm test
# ctest --test-dir build

# Run (development)
# dotnet run --project src/MyApp
# npm run dev
```

## Constraints & Assumptions
- Tasks must be small enough to complete in a single agent iteration.
- All verification must be runnable locally (e.g., `dotnet build`, `dotnet test`, `npm test`).
- UI changes must be verified visually in a browser (automated UI tests / Playwright QA).
- Code should be designed with testability in mind (separation of concerns, dependency injection).

## Success Criteria
- All defined tasks have status `done` (i.e., completed including tests).
- All relevant tests (unit + UI) pass.
- The user interface is responsive and the design matches the specification.
- Agent outputs exactly `<promise>COMPLETE</promise>` at the end.

---

## Task List

### Section 1: Planned Features (human-readable)

*(Describe planned tasks here. Each task should have a TASK-XXX ID.)*

- **TASK-001**: Describe the task here
- **TASK-002**: Another task description

### Section 2: Task Backlog (structured)

```json
[
  {
    "id": "TASK-001",
    "title": "Describe the task here",
    "description": "Detailed description and acceptance criteria.",
    "priority": "high",
    "status": "planned",
    "created": "2025-01-01",
    "completed": null
  },
  {
    "id": "TASK-002",
    "title": "Another task",
    "description": "Detailed description and acceptance criteria.",
    "priority": "medium",
    "status": "planned",
    "created": "2025-01-01",
    "completed": null
  }
]
```

**Status values:** `planned` → `in_progress` → `done`
