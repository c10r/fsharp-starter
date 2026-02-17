---
name: entity-framework-fsharp
description: Explain and implement end-to-end best practices for F# with Entity Framework Core and SQLite in hexagonal/onion architecture. Use when designing DbContext models, mapping domain types, aligning EF with DBUp SQL schema naming, handling SQLite query translation limits, updating repositories, adding migrations, or troubleshooting runtime persistence/query errors.
---

# Entity Framework Fsharp

## Overview

Use this skill to add or review F# persistence end-to-end: domain invariants, EF model mapping, DBUp schema evolution, repository query translation, and API serialization boundaries.

Prefer strict boundary mapping:
- Domain owns business types and validation.
- Application/API owns HTTP JSON converter behavior.
- Infrastructure owns DB schema mapping, converters, and SQL/SQLite compatibility.

Use this skill for both implementation and debugging:
- `no such table` / `no such column` runtime failures
- EF translation failures in SQLite (`DateTimeOffset`, unsupported expressions)
- DBUp script drift vs EF model drift
- Nullability/option round-trip bugs
- PascalCase model names vs snake_case SQL columns

## Architecture Placement

Keep mapping responsibilities in these layers.

1. Domain (`src/<Project>.Domain/src`)
- Define value objects and discriminated unions.
- Expose canonical parsing/printing APIs (`Create`, `ToString`, helpers).
- Keep persistence-agnostic; do not reference EF or `DbContext` here.

2. Application (`src/<Project>.Application/src`)
- Define `System.Text.Json` converters for API request/response shape.
- Convert primitive JSON tokens to validated domain values.
- Keep converters focused on transport; do not encode SQL/EF concerns.

3. API (`src/<Project>.Api/src/Program.fs`)
- Register all JSON converters globally.
- Keep serializer policy consistent (camelCase, null handling, F# converter).

4. Infrastructure (`src/<Project>.Infrastructure/src`)
- Implement EF `ValueConverter<DomainType, ProviderType>` in `<Project>DbContext.fs`.
- Map property names explicitly when SQL naming differs (`HasColumnName`).
- Serialize complex DB columns (JSON TEXT columns) with stable DTO-like shapes.
- Repositories must use SQLite-translatable query expressions.

5. Repositories (`src/<Project>.Infrastructure/src/Database/Repositories`)
- Persist `*.State` records and events.
- Avoid duplicating conversion logic that belongs in `DbContext` or API converters.
- Keep ordering/filtering expressions provider-safe (SQLite first).

## Workflow

1. Define/extend domain and persistence contract
- Add/adjust `Create`, `ToString`, and invariant checks.
- Decide column type and naming in SQL and keep it stable.

2. Add/adjust DBUp SQL migration
- Add a new numbered `DatabaseUpgradeScripts.DBUP.*.sql` script.
- Do not modify old applied scripts for existing DBs.
- Register new script as `EmbeddedResource` in Infrastructure `.fsproj`.

3. Align EF model with SQL schema
- In `DbContext`, map table names and column names explicitly (`ToTable`, `HasColumnName`).
- When SQL is snake_case, always map EF properties to snake_case columns.
- Add `ValueConverter`s only where representation differs by type.

4. Map API JSON boundary
- Add/update converter in `src/<Project>.Application/src/DTOs/JsonConverters.fs`.
- Register it in `src/<Project>.Api/src/Program.fs`.

5. Validate repository query translation
- Query using domain value objects directly (for EF translation).
- Keep Save/Add/Update code free of ad-hoc string/Guid conversions.
- Avoid SQLite-unsupported constructs in SQL translation:
  - `DateTimeOffset` ordering in SQL (`OrderBy`/`ThenBy`) may fail.
  - prefer numeric/text tie-breakers (`RowVersion`, `created_at_utc` text form) or split to client-side ordering only when safe.

6. Run checks
- `dotnet build <Project>.sln -c Release`
- `dotnet test <Project>.sln`

## Use These Patterns

Load `references/patterns.md` and adapt the templates:
- Value object <-> scalar converter
- `option` <-> nullable converter
- DU <-> string/JSON converter
- Nested record/list <-> JSON TEXT converter
- API `JsonConverter` + `Program.fs` registration
- DBUp snake_case SQL <-> EF PascalCase property mapping
- SQLite query translation-safe ordering/filtering patterns
- SQLite operational limits and migration/query/index guardrails
- Placement rules and anti-patterns

## SQLite Checklist

Before merging EF + SQLite changes, verify:
- DBUp migration is additive and safe for SQLite `ALTER TABLE` limitations.
- Query ordering/filtering translates in SQLite provider (not only in-memory tests).
- Write paths are short transactions; lock contention risk is addressed.
- Precision-sensitive numeric fields (money/rates) use explicit storage strategy.
- `Guid` representation is consistent across SQL and EF mapping.
- String comparison/collation behavior matches product expectations.
- Foreign key enforcement expectations are explicit and tested.
- Indexes match `WHERE` + `ORDER BY` access patterns for hot queries.

## Guardrails

- Treat DBUp SQL as schema source of truth; EF must map to it.
- Never rely on implicit EF naming when SQL naming convention differs.
- Prefer additive DBUp migrations over editing old scripts.
- Prefer failing fast on invalid DB data in EF converters (`failwith` with context).
- Use domain `Create` functions when rebuilding value objects from storage.
- Keep event JSON options explicit when serializing F# options (`JsonFSharpConverter`).
- Do not suppress null fields in stored event payloads that need round-trip deserialization.
- Fail fast at startup if connection string is missing; avoid silent SQLite temp DB behavior.
