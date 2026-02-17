---
name: init
description: Convert this starter repository into a real internal-tooling B2B SaaS project while preserving the Domain/Application/Infrastructure/API architecture. Use when a user asks to initialize or de-template the repo, define project-specific scope, write a new CURRENT_PLAN.md from scratch, and execute phased migration with validation checkpoints. This skill must ask 3-5 clarifying questions before planning and must place removal of all Example references as the final plan step.
---

# Init

## Execution Contract

- Treat this skill as a one-time repository initialization workflow.
- Ask 3-5 clarifying questions before writing the plan.
- Create `CURRENT_PLAN.md` from scratch for this run.
- Start implementation from the Domain layer first and require explicit user confirmation before progressing to later layers.
- Preserve the existing architecture layers and boundaries:
  - API -> Application -> Domain
  - API -> Infrastructure -> Domain
  - API -> Domain
- Do not collapse layers or move responsibilities across layers during initialization.

## Clarifying Questions

Ask 3-5 targeted questions that remove ambiguity for naming, scope, and rollout.

Cover these areas unless already answered:
1. Product identity: project name, short description, and target internal users.
2. Core first workflow: the first business capability to replace starter behavior.
3. Domain language: key entities, commands, and events to introduce first.
4. Operational constraints: auth, environment, compliance, or deployment constraints.
5. Non-goals for initial conversion to prevent scope creep.

If the user already provided some answers, ask only the missing questions and stay within 3-5 total.

## Planning Protocol

After collecting clarifications, write `CURRENT_PLAN.md` from scratch.

Use this structure:

1. **Context**
   - Project name, purpose, and initial scope.
   - Architecture guardrails and explicit out-of-scope items.

2. **Phased Plan**
   - Define sequential phases with concrete deliverables.
   - Include a validation checklist after every phase.
   - Keep steps actionable and verifiable.
   - Make the first implementation phase Domain-first and add a "user approval gate" before Application/Infrastructure/API work.
   - In Phase 1, explicitly reference `domain-driven-design` skill as required guidance for modeling aggregates, invariants, errors, and domain events.
   - Include an explicit phase to add an audit log controller, using `event-sourcing-audit` skill guidance.

3. **Final Step Requirement**
   - The last step in the phased plan must be:
     - Remove all references to `Example`/`Examples` in code, comments, docs, endpoints, DTO names, tests, and generated artifacts.
   - Do not place any step after this removal step.

## Required Phase Checklist Pattern

For each phase in `CURRENT_PLAN.md`, include:

- Deliverables
  - Files or components to create/update.
- Validation
  - `dotnet tool run fantomas .`
  - `dotnet build FsharpStarter.sln -c Release`
  - `dotnet test FsharpStarter.sln`
  - `cd www && npm run check && npm run lint && npm test`
  - For backend changes, run `review-backend`, fix all findings, and re-run until no unresolved findings remain.
  - For frontend changes, run `review-frontend`, fix all findings, and re-run until no unresolved findings remain.

If a phase has only backend changes, still list frontend checks and mark them as "run if frontend changed".

If a phase has only frontend changes, still list backend checks and mark them as "run if backend changed".

## Architecture-Preserving Migration Rules

- Keep Domain pure and framework-free.
- Keep Application as orchestration/contracts/interfaces.
- Keep Infrastructure for EF Core/SQLite and integrations.
- Keep API for controllers, middleware, and DI composition.
- Do not start Application/Infrastructure/API implementation until the user confirms Domain modeling is acceptable.
- Preserve compile-order correctness in `.fsproj` files when adding files.
- Regenerate OpenAPI/types when controller or DTO contracts change.

## Mandatory Audit Log Planning

- Always plan audit logging for day-1 B2B SaaS readiness, even if the user does not request it.
- Add an explicit `CURRENT_PLAN.md` phase to introduce or finalize `AuditController` and related audit/event flow wiring.
- Use `event-sourcing-audit` skill as the implementation guideline for:
  - domain event coverage
  - repository persistence mapping
  - enrichment service behavior
  - API controller/DI wiring

## Example-Removal Sweep Guidance

The final plan step must include a repository-wide sweep that removes starter-example naming and references from:

- Backend source (`src/`)
- Frontend source (`www/`)
- Tests
- README and docs
- OpenAPI artifacts and generated API client types
- Scripts and configuration comments where applicable

Use case-sensitive and case-insensitive searches to catch variants (`Example`, `Examples`, `example`, `examples`).

## Completion Criteria

Consider initialization complete only when:

1. Clarifying questions were asked (3-5) and answered.
2. `CURRENT_PLAN.md` was created from scratch.
3. Every phase includes a concrete validation checklist.
4. The final listed step in `CURRENT_PLAN.md` is the Example-reference removal step.
5. No remaining Example references exist after execution.
