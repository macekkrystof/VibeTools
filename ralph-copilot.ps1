param(
  [int]$Max = 10,
  [string]$Model = "claude-opus-4.5"
)

Write-Host "Starting Ralph (Copilot CLI + $Model) - Max $MAX iterations"
Write-Host ""

for ($i = 1; $i -le $MAX; $i++) {
  Write-Host "====================================================="
  Write-Host " Iteration $i of $MAX"
  Write-Host "====================================================="

  $prompt = @"
@PROMPT.md @progress.txt
You are Ralph, an autonomous coding agent.
## Steps

1. Read PRD.md and find the next tasks that are NOT complete (marked [ ]).
2. Read progress.txt - check the Learnings section first for patterns from previous iterations.
3. Implement the next pending task(s). You may complete multiple tasks if they are small and related, but stop if you encounter complexity or need user feedback.
4. Run tests/typecheck to verify it works.

## Critical: Only Complete If Tests Pass

If tests PASS:
- Update PRD.md to mark completed task(s) as [x]
- Commit your changes with message: feat: [task description] 
- Append what worked to progress.txt

If tests FAIL:
- Do NOT mark the task complete
- Do NOT commit broken code
- Append what went wrong to progress.txt (so next iteration can learn)

## Progress Notes Format

Append to progress.txt:
'''
## Iteration [N] - [Task Name]
- What was implemented
- Files changed
- Learnings for future iterations:
  - Patterns discovered
  - Gotchas encountered
  - Useful context
---
'''
## End Condition

After completing your work, check PRD.md:
- If ALL tasks in the Development Checklist are [x], output exactly: <promise>COMPLETE</promise>
- If tasks remain [ ], just end your response (next iteration will continue)
"@

  $result = ""
  copilot -p $prompt --model $Model --yolo 2>&1 | ForEach-Object {
    Write-Host $_
    $result += $_ + "`n"
  }
  if ($result -match "<promise>COMPLETE</promise>") {
    Write-Host "Ralph has finished all tasks."
    break
  }
}
