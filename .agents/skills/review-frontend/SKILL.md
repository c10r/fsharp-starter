---
name: review-frontend
description: Review frontend changes after generating or modifying React/TypeScript code in `www/`. Use when reviewing state/rendering behavior, pagination UX/data flow, API type-sync with OpenAPI, permission-driven rendering, and frontend regression tests before merge.
---

# Review Frontend

Review frontend code for rendering/state regressions, API type drift, and missing coverage before merge.

## Review Workflow
1. Scan changed files in `www/src`, `www/openapi.spec.json`, and generated frontend schema/type files.
2. List findings first, ordered by severity, with file references.
3. Prioritize behavior regressions, stale UI state, parsing bugs, and authorization/permission rendering issues.
4. Add a short summary only after findings.

## Frontend Review Checklist
- Verify API contract sync.
- Ensure API-impacting backend changes regenerate and commit `openapi.spec.json` plus frontend schema/types.
- Flag client code that hides schema drift with `any`, casts, or temporary compatibility shims.

- Verify pagination behavior is consistent.
- Ensure one shared pagination model (`skip`, `take`, `totalCount`) across hooks/components/API calls.
- Ensure defaults and bounds match backend conventions.
- Ensure invalid/edge values are handled consistently in UI and request composition.

- Verify state and rendering patterns are shared and predictable.
- Prefer reusable hooks/helpers for form and pagination state.
- Flag ad-hoc per-component state transitions that can drift.
- Check rerender-sensitive code for stale closures, missing dependencies, and derived-state mismatches.

- Verify permission-driven UI behavior.
- Ensure authorization state changes produce expected rendering and action availability.
- Flag controls that are only visually hidden but still functionally callable.

- Verify regression tests accompany fixes.
- Require targeted tests for rerender behavior, input parsing, pagination boundaries, and permission-driven rendering.
- Ensure tests cover the exact bug class that escaped.

## Quality Gates
Run before merge:
1. `cd www && npm run check`
2. `cd www && npm run lint`
3. `cd www && npm test`
4. `dotnet build FsharpStarter.sln -c Release`
5. `dotnet test FsharpStarter.sln`
