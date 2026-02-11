---
name: entity-framework-fsharp
description: Use when implementing or changing EF Core + SQLite persistence patterns in F#.
---

# Skill: entity-framework-fsharp

Use this for EF Core + SQLite persistence in F# with option/DU/result-heavy domain models.

## Baseline
This starter assumes EF Core + SQLite for all apps.

## Layer Placement
- Domain: strongly typed value objects + DUs + pure behavior.
- Application: DTO mapping and parse/validation at boundaries.
- Infrastructure: all EF model configuration, converters, and repository transaction logic.

## Non-Negotiable EF Patterns
1. Every `option` property must have explicit conversion in DbContext.
2. Every discriminated union must have deterministic converter (string or JSON) and round-trip tests.
3. Never persist raw domain `Result` types; map to persistence DTO/state first.
4. Always configure owned types/value converters for custom IDs and VOs.
5. Keep EF entities and domain entities separate if mapping gets complex.
6. Normalize nullable list/collection fields before mapping or iterating; do not assume DB materialization initializes collections.
7. Prefer explicit option equality in EF predicates (`field = None` / `field = Some(...)`) over fragile shape-dependent accessors.
8. When an entity is already tracked, update tracked instances (`Entry(existing).CurrentValues.SetValues(...)`) instead of attaching a new instance and calling `Update`.

## Edge Cases Checklist
- `string option`/`int option`/`bool option` null handling.
- DUs with payloads (tag + payload schema evolution).
- Collections of DUs serialized as JSON columns.
- Legacy null rows from older migrations.
- Unlinked relationships (for example, member rows whose user rows were deleted).
- Soft-delete + unique index interactions.

## Migrations Must Stay In Lockstep
- Every schema change requires both migration SQL and project registration (for example `EmbeddedResource`).
- Ensure new required columns include safe defaults for existing rows.
- Add or keep a startup/integration check that fails fast if expected columns are missing.

## Required Tests
- Converter round-trip tests for each DU/value object.
- Repository tests with real SQLite in-memory DB.
- Null/legacy row hydration tests.
- Migration compatibility tests for new DBUp scripts.
- Regression tests for the exact bug shape being fixed (tracking conflict, null collection hydration, legacy row shape).

## Verification Commands
After each data model change:
1. `dotnet tool run fantomas .`
2. `dotnet build src/FsharpStarter.Infrastructure/FsharpStarter.Infrastructure.fsproj`
3. `dotnet test src/FsharpStarter.Infrastructure/test/FsharpStarter.Infrastructure.Tests.fsproj --filter "FullyQualifiedName~DbContextConfigurationTests|FullyQualifiedName~Repository"`
4. `dotnet test FsharpStarter.sln`
5. `cd www && npm run check && npm run lint && npm test`
