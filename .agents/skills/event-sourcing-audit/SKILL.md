---
name: event-sourcing-audit
description: Use when adding or changing domain events and audit log behavior.
---

# Skill: event-sourcing-audit

Use this when adding/changing domain events and audit log behavior.

## Checklist
1. Add/adjust domain event types.
2. Update event type/entity type converters.
3. Persist event in repository transaction with business data.
4. Keep event payloads display-safe (for example include `Name` on created/deleted events when UI needs it).
5. Add audit enhancement parsing and lookup-based enrichment for update events when payloads do not include display fields.
6. Treat historical events as immutable contracts; keep deserialization/enhancement tolerant to older payload shapes.
7. Add/update frontend event type unions if exposed.

## Regression Discipline
- Pair every event/audit bug fix with a test at the layer where it escaped (domain/application/infrastructure).
- Use realistic payload variants in tests (legacy shape, missing fields, malformed-but-recoverable data).

## Verification Commands
1. `dotnet tool run fantomas .`
2. `dotnet test src/FsharpStarter.Domain/test/FsharpStarter.Domain.Tests.fsproj --filter "FullyQualifiedName~Event"`
3. `dotnet test src/FsharpStarter.Application/test/FsharpStarter.Application.Tests.fsproj --filter "FullyQualifiedName~EventEnhancementServiceTests"`
4. `dotnet test src/FsharpStarter.Infrastructure/test/FsharpStarter.Infrastructure.Tests.fsproj --filter "FullyQualifiedName~EventRepositoryTests|FullyQualifiedName~AuditControllerTests"`
5. `dotnet test FsharpStarter.sln`
