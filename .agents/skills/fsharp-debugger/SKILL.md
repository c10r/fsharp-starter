---
name: fsharp-debugger
description: Debug and triage common F# compiler warnings and errors in this starter, beginning with FS3511 task/resumable code issues. Use when build/test output includes F# diagnostic codes and you need concrete remediation steps and validation flow.
---

# F# Debugger

Diagnose F# compiler diagnostics and apply targeted fixes with a repeatable workflow.

## Workflow
1. Capture the exact diagnostic code, message, file path, and line from build/test output.
2. Reproduce the issue with the smallest command that still fails (`dotnet build` or a filtered `dotnet test`).
3. Isolate the smallest code shape that triggers the diagnostic.
4. Apply the fix pattern for that diagnostic.
5. Re-run formatting, build, and tests to confirm no regressions.

## FS3511: Task/Resumable Code Warning
`FS3511` means a `task { ... }` state machine was not statically compiled and the compiler fell back to a slower dynamic path.

Apply these fixes:
- Keep `task { ... }` blocks small and move heavy branching into plain helper functions.
- Prefer direct `let!` and `return!` control flow over deeply nested higher-order or local generic lambdas inside `task { ... }`.
- Split complex task expressions into named intermediate steps.

## Validation
Run after changes:
1. `dotnet tool run fantomas .`
2. `dotnet build FsharpStarter.sln -c Release`
3. `dotnet test FsharpStarter.sln`
