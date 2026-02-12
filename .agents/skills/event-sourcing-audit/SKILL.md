---
name: event-sourcing-audit
description: Explain and implement backend event sourcing and audit logging patterns across Domain, Application, Infrastructure, and API layers. Use when adding or reviewing domain events, wiring audit log persistence/enrichment, extending audit endpoints, or adding new event/entity types that must appear correctly in audit UI.
---

# Event Sourcing Audit

## Overview
Use this skill to implement or review event sourcing and audit logging with correct hexagonal boundaries and complete wiring.

Treat this as the source-of-truth workflow when changing any of:
- Domain events in `src/<ProjectName>.Domain/src/Events/`
- Event type/entity type registries in `src/<ProjectName>.Domain/src/Entities/Event.fs`
- Event persistence in `src/<ProjectName>.Infrastructure/src/Database/Repositories/EventRepository.fs`
- Audit enrichment/summary logic in `src/<ProjectName>.Application/src/Services/EventEnhancementService.fs`
- Audit API responses in `src/<ProjectName>.Api/src/Controllers/AuditController.fs`

## Architecture Boundaries

### Domain (core business facts)
Own:
- Event contracts (records implementing `IDomainEvent`) in `src/<ProjectName>.Domain/src/Events/*.fs`
- Aggregate event collection via `EventSourcingAggregate<'T>` in `src/<ProjectName>.Domain/src/EventSourcingAggregate.fs`
- Business methods that append uncommitted events (entity modules in `src/<ProjectName>.Domain/src/Entities/*.fs`)
- Type registries (`EventType`, `EntityType`, converters) in `src/<ProjectName>.Domain/src/Entities/Event.fs`

Do not:
- Persist events
- Query repositories
- Build UI-facing text summaries

### Application (orchestration + read-model enrichment)
Own:
- Command handlers invoking domain methods and repositories
- Audit enrichment service (`IEventEnhancementService`) that turns raw `EventData` into user-friendly output
- Event summary text generation and entity name lookup strategy

Do not:
- Define domain invariants in handlers
- Put EF/storage concerns here

### Infrastructure (ports/adapters, persistence)
Own:
- `IEventRepository` implementation in `src/<ProjectName>.Infrastructure/src/Database/Repositories/EventRepository.fs`
- Mapping runtime domain events to `EventData` rows
- Transactional persistence with aggregate repositories
- EF converters for `EventType` / `EntityType` in `src/<ProjectName>.Infrastructure/src/Database/<ProjectName>DbContext.fs`

Do not:
- Generate user-facing summary strings
- Encode business rules that belong in domain methods

### API (transport)
Own:
- Endpoints in `src/<ProjectName>.Api/src/Controllers/AuditController.fs`
- DI wiring in `src/<ProjectName>.Api/src/Program.fs`

Do not:
- Parse or interpret event payloads in controllers

## End-to-End Flow
1. Domain method executes and appends an `IDomainEvent` to `UncommittedEvents`.
2. Application handler calls repository.
3. Aggregate repository saves entity state and events in the same EF unit-of-work, then calls `SaveChangesAsync` once.
4. Audit API reads raw `EventData` via `IEventRepository`.
5. `EventEnhancementService` enriches each row with `EntityName`, `UserName`, and `EventSummary`.

## Core Implementation Pattern

### 1) Domain event contract
```fsharp
// src/<ProjectName>.Domain/src/Events/<Entity>Events.fs
namespace <ProjectName>.Domain.Events

open System
open <ProjectName>.Domain
open <ProjectName>.Domain.ValueObjects

type EntityCreatedEvent =
    { EntityId: EntityId
      Name: EntityName
      OccurredAt: DateTime
      EventId: Guid
      ActorUserId: UserId }
    interface IDomainEvent with
        member this.OccurredAt = this.OccurredAt
        member this.EventId = this.EventId
        member this.UserId = this.ActorUserId
```

### 2) Aggregate appends event
```fsharp
// src/<ProjectName>.Domain/src/Entities/<Entity>.fs
let rename (actorUserId: UserId) (newName: string) (entity: ValidatedEntity) =
    // validate + update state
    let updated = { entity.State with Name = newName; UpdatedAt = DateTime.UtcNow }
    let evt = EntityEvents.entityUpdated actorUserId entity.State.Id [ EntityChange.NameChanged(...) ]

    Ok { State = updated
         UncommittedEvents = entity.UncommittedEvents @ [ evt :> IDomainEvent ] }
```

### 3) Repository persists entity + events atomically
```fsharp
// src/<ProjectName>.Infrastructure/src/Database/Repositories/<Entity>Repository.fs
member _.UpdateAsync(entity: ValidatedEntity) =
    task {
        // update tracked entity
        let events = Entity.getUncommittedEvents entity

        for event in events do
            do! eventRepository.SaveEventAsync event

        let! _ = context.SaveChangesAsync()
        return Ok()
    }
```

### 4) Audit enrichment builds human-readable output
```fsharp
// src/<ProjectName>.Application/src/Services/EventEnhancementService.fs
| EntityEvents entityEvent ->
    match entityEvent with
    | EntityCreatedEvent ->
        let data = JsonSerializer.Deserialize<EntityCreatedEvent>(eventData, jsonOptions)
        return data.Name.Value
    | EntityUpdatedEvent ->
        let data = JsonSerializer.Deserialize<EntityUpdatedEvent>(eventData, jsonOptions)
        let! entity = entityRepository.GetByIdAsync data.EntityId
        return entity |> Option.map Entity.getName |> Option.defaultValue $"Entity {data.EntityId.Value}"
```

## Add a New Event Type (existing entity)
Use this checklist in order.

1. Add event record(s) and constructor helpers in `src/<ProjectName>.Domain/src/Events/<Entity>Events.fs`.
2. Emit the event in domain entity methods in `src/<ProjectName>.Domain/src/Entities/<Entity>.fs`.
3. Register new DU case mapping in `src/<ProjectName>.Domain/src/Entities/Event.fs`:
- `EventType` DU
- `EventTypeConverter.toString`
- `EventTypeConverter.fromString`
4. Update event persistence pattern match in `src/<ProjectName>.Infrastructure/src/Database/Repositories/EventRepository.fs`:
- Add typed case
- Return correct `(entityId, serializedEventData)`
5. Update audit enrichment in `src/<ProjectName>.Application/src/Services/EventEnhancementService.fs`:
- Add entity-name extraction case
- Add `generateEventSummary` case
6. If enrichment needs a new repository, add it to DI in `src/<ProjectName>.Api/src/Program.fs` and constructor args for `EventEnhancementService`.
7. Update frontend unions where event/entity types are represented if they changed.
8. Add tests:
- Domain event emission test
- Event repository serialization/type mapping test
- Event enhancement parsing/name/summary tests

## Add a New Auditable Entity Type
Do everything above plus:
1. Add new event family DU in `src/<ProjectName>.Domain/src/Entities/Event.fs` (for example `| EntityEvents of EntityEvents`).
2. Add new entity type to `EntityType` DU and converter functions.
3. Extend entity type mapping in `EventRepository.SaveEventAsync`:
```fsharp
let entityType =
    match eventType with
    | EntityEvents _ -> EntityType.Entity
    | ...
```
4. Extend EF conversion coverage (usually already generic via converters, but verify in `src/<ProjectName>.Infrastructure/src/Database/<ProjectName>DbContext.fs`).
5. Ensure frontend `EntityType` union includes the new type.

## Gotchas
- `EventTypeConverter.fromString` must match runtime `event.GetType().Name`. If names diverge, save fails with `Unknown event type`.
- Keep `JsonFSharpConverter()` for event payload serialization/deserialization. Removing it breaks F# DU/option parsing.
- Do not omit null option fields during event JSON serialization. Missing fields can break deserialization for historical events.
- For `UpdatedEvent`, resolve current entity name through repository lookup in `EventEnhancementService`.
- For `DeletedEvent`, include entity name inside the event payload itself; repository lookup may fail after deletion.
- Always add `generateEventSummary` cases, or UI summaries become inconsistent.
- Keep transactional semantics: aggregate repositories should call `SaveEventAsync` for each uncommitted event and a single `SaveChangesAsync`.
- Exception pattern: some non-aggregate operations may call `eventRepository.SaveEventAsync` + explicit commit directly. Use this only for standalone events not tied to an aggregate write.
- Update any frontend type unions for new event/entity names, or audit pages may fail type checks.
- If old DB rows contain legacy JSON shapes, enrichment can show parse-error fallback text; handle compatibility or refresh dev data.

## Copy-Paste Plan Template
```markdown
1. Add domain event type(s) in `src/<ProjectName>.Domain/src/Events/<Entity>Events.fs`.
2. Emit event(s) from domain methods in `src/<ProjectName>.Domain/src/Entities/<Entity>.fs`.
3. Register event strings in `src/<ProjectName>.Domain/src/Entities/Event.fs` (`EventType`, `toString`, `fromString`).
4. Extend `src/<ProjectName>.Infrastructure/src/Database/Repositories/EventRepository.fs` mapping:
   - runtime event match
   - entity id extraction
   - entity type assignment
5. Extend `src/<ProjectName>.Application/src/Services/EventEnhancementService.fs`:
   - entity name extraction
   - event summary text
6. Wire any new repositories required by enhancement in `src/<ProjectName>.Api/src/Program.fs`.
7. Update frontend audit type unions wherever event/entity types are modeled.
8. Add or adjust tests in:
   - `src/<ProjectName>.Domain/test/`
   - `src/<ProjectName>.Infrastructure/test/`
   - `src/<ProjectName>.Application/test/`
9. Run tests and lint/format before commit.
```

## Verification Commands
```bash
# Backend tests most relevant to audit/event changes
dotnet test src/<ProjectName>.Application/test/<ProjectName>.Application.Tests.fsproj --filter "FullyQualifiedName~EventEnhancementService"
dotnet test src/<ProjectName>.Infrastructure/test/<ProjectName>.Infrastructure.Tests.fsproj --filter "FullyQualifiedName~EventRepository"

# Full safety pass
dotnet test <ProjectName>.sln
```
