---
name: domain-driven-design
description: Apply Domain-Driven Design in F# across Domain, Application, Infrastructure, and API layers with explicit invariants, opaque/domain-specific types, Result-based error flow, domain events, aggregate boundaries, and transaction-safe persistence. Use when creating or refactoring domain models, handlers, repositories, event-sourced flows, DTO/domain mappers, or API boundaries in F# codebases.
---

# Domain-Driven Design (F#)

## Overview
Model the domain first. Keep business rules in Domain types and methods, keep orchestration in Application, keep persistence concerns in Infrastructure, and keep transport concerns in API.

## Workflow
1. Define ubiquitous language and aggregate boundaries.
2. Model IDs and value objects as domain-specific opaque types.
3. Encode invariants in constructors or domain methods that return `Result`.
4. Use explicit `DomainError` unions for all business failures.
5. Raise domain events from aggregate behavior.
6. Orchestrate in Application handlers using repository interfaces.
7. Persist aggregate state and emitted events in one transaction.
8. Map DTOs to domain types only at boundaries.
9. Return typed results from command/query handlers.
10. Keep nulls out of Domain and Application models.

## Non-Negotiable Rules

### 1) Ban Nulls in Domain
- Never use `null` for domain state.
- Use `option` for missing values.
- Use `Result<'ok, DomainError>` for validation and business failures.
- Keep EF/serializer null handling in Infrastructure or API mapping layers.

### 2) Use Opaque Domain Types
- Create one type per concept (`AppId`, `UserId`, `Email`, etc.).
- Use those types in repository and domain APIs.
- Parse raw strings/Guids once at the boundary and convert immediately.

```fsharp
[<Struct>]
type AppId =
    | AppId of Guid
    static member FromGuid(id: Guid) = AppId id
```

### 3) Enforce Invariants Inside Domain Methods
- Validate at construction and mutation points.
- Reject invalid state transitions with explicit domain errors.

```fsharp
match newName with
| None -> Error (ValidationError "User name cannot be null")
| Some value when System.String.IsNullOrWhiteSpace value ->
    Error (ValidationError "User name cannot be empty")
| Some value -> Ok ({ user with Name = value })
```

### 4) Use an Explicit Domain Error Model
- Keep one discriminated union for domain-level failures.
- Thread it through all domain and application workflows.

```fsharp
type DomainError =
    | ValidationError of string
    | NotFound of string
    | Conflict of string
    | InvalidOperation of string
```

### 5) Treat Domain Events as Business Facts
- Emit events from aggregate methods when state changes.
- Include event identity, timestamp, actor, and aggregate identifiers.
- Avoid ad-hoc logs as replacements for domain events.

### 6) Keep Application Layer as Orchestrator
- Application handlers coordinate: load aggregate, call domain method, persist, map output.
- Do not duplicate business rules in handlers.

### 7) Split Repository Contract and Implementation
- Define repository interfaces in Application.
- Implement repositories in Infrastructure.
- Keep EF/SQL concerns out of Domain and Application.

### 8) Persist Aggregate + Events Atomically
- Save updated aggregate state and uncommitted domain events in one transaction boundary.
- Do not allow state updates without corresponding events (or vice versa).

### 9) Keep DTO/Domain Mapping Explicit
- Map transport DTOs to domain types in dedicated mappers.
- Return `Result` from mappers when conversion can fail.
- Do not leak DTO types into Domain.

### 10) Standardize Command Handler Contracts
- Prefer a generic handler contract for consistency.
- Return `Task<Result<'TResult, DomainError>>` from commands.

```fsharp
type ICommandHandler<'TCommand, 'TResult> =
    abstract member HandleCommand: 'TCommand -> Task<Result<'TResult, DomainError>>
```

## Boundary Pattern
Use parse-once conversion at API/Application boundaries:

```fsharp
match Guid.TryParse appIdText with
| true, guid ->
    let appId = AppId.FromGuid guid
    let! app = appRepository.GetByIdAsync appId
| false, _ ->
    return Error (ValidationError "Invalid app id")
```

## Review Checklist
- Are all domain concepts represented with domain types rather than primitives?
- Are `null` and mutable invalid states excluded from Domain?
- Do domain methods protect invariants and return `Result`?
- Are domain events emitted for meaningful state changes?
- Are repository interfaces in Application and implementations in Infrastructure?
- Are aggregate updates and event persistence in the same transaction?
- Are DTO mappings explicit and boundary-only?
- Are handlers orchestrating instead of owning business logic?

## Resources
- For fuller examples aligned to the Freetool-style layering, read `references/freetool-ddd-examples.md`.
- Use that file when implementing handlers, repositories, mapper layers, and event persistence patterns.
- Keep this file concise; move large examples to referenced files.
