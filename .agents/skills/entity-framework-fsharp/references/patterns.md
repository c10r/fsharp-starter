# EF Core + F# Mapping Patterns

## Table of Contents
- Value object to scalar mapping
- Option to nullable/null mapping
- Complex list to JSON TEXT mapping
- Discriminated union mapping patterns
- API JSON converters for domain types
- Event payload serialization/deserialization
- Repository usage pattern
- DBUp schema naming alignment (snake_case vs PascalCase)
- SQLite query translation guardrails
- SQLite DDL and migration constraints
- SQLite locking and transaction behavior
- Decimal precision strategy
- Guid storage strategy
- Collation and case-sensitivity
- Foreign key enforcement
- Index design and query plan checks
- SQLite JSON TEXT guidance
- Placement map and anti-patterns
- Implementation checklist for new complex types

## Value Object to Scalar Mapping

Reference: `src/<Project>.Infrastructure/src/Database/<Project>DbContext.fs`

```fsharp
let aggregateIdConverter =
    ValueConverter<Domain.ValueObjects.AggregateId, System.Guid>(
        (fun aggregateId -> aggregateId.Value),
        (fun guid -> Domain.ValueObjects.AggregateId(guid))
    )

entity.Property(fun row -> row.Id).HasConversion(aggregateIdConverter) |> ignore
```

Use this for ID wrappers and value objects with a single primitive backing value.

## Option to Nullable/Null Mapping

```fsharp
let optionStringConverter =
    ValueConverter<string option, string>(
        (fun opt -> match opt with | Some s -> s | None -> null),
        (fun str -> if isNull str then None else Some str)
    )

let optionDateTimeConverter =
    ValueConverter<DateTime option, System.Nullable<DateTime>>(
        (fun opt -> match opt with | Some dt -> System.Nullable(dt) | None -> System.Nullable()),
        (fun nullable -> if nullable.HasValue then Some(nullable.Value) else None)
    )
```

Use this for optional fields persisted in scalar columns.

## Complex List to JSON TEXT Mapping

```fsharp
let metadataListConverter =
    ValueConverter<Domain.ValueObjects.KeyValuePair list, string>(
        (fun pairs ->
            let serializable = pairs |> List.map (fun p -> {| Key = p.Key; Value = p.Value |})
            System.Text.Json.JsonSerializer.Serialize(serializable)),
        (fun json ->
            let deserialized =
                System.Text.Json.JsonSerializer.Deserialize<{| Key: string; Value: string |} list>(json)

            deserialized
            |> List.map (fun item ->
                match Domain.ValueObjects.KeyValuePair.Create(item.Key, item.Value) with
                | Ok pair -> pair
                | Error _ -> failwith $"Invalid KeyValuePair in database: {item.Key}={item.Value}"))
    )

entity.Property(fun row -> row.Metadata).HasConversion(metadataListConverter) |> ignore
```

Use explicit serializable intermediary shapes; avoid serializing domain records directly when they may evolve.

## Discriminated Union Mapping Patterns

### Pattern A: DU <-> string via canonical `ToString` and parser

```fsharp
let serializeStatus (status: Domain.Types.Status) = status.ToString()

let deserializeStatus (str: string) =
    match str with
    | "Active" -> Domain.Types.Status.Active
    | "Inactive" -> Domain.Types.Status.Inactive
    | value when value.StartsWith("Paused(") && value.EndsWith(")") ->
        let reason = value.Substring(7, value.Length - 8)
        Domain.Types.Status.Paused reason
    | _ -> failwith $"Unknown Status format in database: {str}"

let statusConverter = ValueConverter<Domain.Types.Status, string>(serializeStatus, deserializeStatus)
```

### Pattern B: DU-containing record <-> JSON TEXT with explicit enum string conversions

```fsharp
let modeToString (mode: Domain.Types.QueryMode) =
    match mode with
    | Domain.Types.QueryMode.Gui -> "gui"
    | Domain.Types.QueryMode.Raw -> "raw"

let modeFromString (value: string) =
    match value.Trim().ToLowerInvariant() with
    | "gui" -> Domain.Types.QueryMode.Gui
    | "raw" -> Domain.Types.QueryMode.Raw
    | _ -> failwith $"Invalid QueryMode in database: {value}"

let queryConfigConverter =
    ValueConverter<Domain.Types.QueryConfig option, string>(
        (fun configOpt ->
            match configOpt with
            | None -> null
            | Some config ->
                let serialized =
                    {| Mode = modeToString config.Mode
                       Table = config.Table
                       Columns = config.Columns |}
                System.Text.Json.JsonSerializer.Serialize(serialized)),
        (fun json ->
            if System.String.IsNullOrWhiteSpace(json) then None
            else
                let deserialized =
                    System.Text.Json.JsonSerializer.Deserialize<{| Mode: string; Table: string option; Columns: string list |}>(json)

                Some
                    { Mode = modeFromString deserialized.Mode
                      Table = deserialized.Table
                      Columns = deserialized.Columns
                      Filters = []
                      Limit = None
                      OrderBy = [] })
    )
```

## API JSON Converters for Domain Types

Reference: `src/<Project>.Application/src/DTOs/JsonConverters.fs` and `src/<Project>.Api/src/Program.fs`

```fsharp
type HttpMethodConverter() =
    inherit JsonConverter<Domain.ValueObjects.HttpMethod>()

    override _.Read(reader: byref<Utf8JsonReader>, _typeToConvert: Type, _options: JsonSerializerOptions) =
        let methodStr = reader.GetString()
        match Domain.ValueObjects.HttpMethod.Create(methodStr) with
        | Ok httpMethod -> httpMethod
        | Error _ -> raise (JsonException($"Invalid HTTP method: {methodStr}"))

    override _.Write(writer: Utf8JsonWriter, value: Domain.ValueObjects.HttpMethod, _options: JsonSerializerOptions) =
        writer.WriteStringValue(value.ToString())
```

Registration:

```fsharp
options.JsonSerializerOptions.Converters.Add(HttpMethodConverter())
options.JsonSerializerOptions.Converters.Add(JsonFSharpConverter(allowOverride = true))
```

## Event Payload Serialization/Deserialization

```fsharp
let jsonOptions = JsonSerializerOptions()
jsonOptions.Converters.Add(JsonFSharpConverter())

// Important: do not omit null option fields when storing events.
let payload = JsonSerializer.Serialize(domainEvent, jsonOptions)
```

When reading:

```fsharp
let evt = JsonSerializer.Deserialize<Domain.Events.AggregateUpdatedEvent>(eventData, jsonOptions)
```

## Repository Usage Pattern

```fsharp
// Query using domain types directly; EF ValueConverter handles translation.
let! row = context.Aggregates.FirstOrDefaultAsync(fun a -> a.Id = aggregateId)

let! relatedIds =
    context.RelatedRows
        .Where(fun r -> parentIds.Contains(r.ParentId))
        .Select(fun r -> r.Id)
        .ToListAsync()
```

Avoid converting IDs to `Guid` in queries unless required by SQL expression translation.

## DBUp Schema Naming Alignment (snake_case vs PascalCase)

Use this whenever DBUp SQL uses snake_case and EF entity properties use PascalCase.

```fsharp
let users = modelBuilder.Entity<UserRecord>()
users.ToTable("users") |> ignore
users.HasKey("Id") |> ignore
users.Property(fun row -> row.Id).HasColumnName("id") |> ignore
users.Property(fun row -> row.Email).HasColumnName("email").IsRequired() |> ignore
users.Property(fun row -> row.DisplayName).HasColumnName("display_name") |> ignore
users.Property(fun row -> row.AvatarUrl).HasColumnName("avatar_url") |> ignore
users.Property(fun row -> row.UpdatedAtUtc).HasColumnName("updated_at_utc") |> ignore
```

Rules:
- Treat DBUp SQL as source of truth for table/column names.
- Map every non-matching property with `HasColumnName`.
- Do not depend on EF implicit naming when conventions differ.
- Add new DBUp scripts for schema changes; do not rewrite already-applied scripts.

## SQLite Query Translation Guardrails

SQLite provider can reject expressions that other providers accept. Keep repository queries translation-safe.

Problematic pattern:

```fsharp
query
    .OrderByDescending(fun row -> row.VisitCount)
    .ThenByDescending(fun row -> row.UpdatedAtUtc) // DateTimeOffset may fail in SQLite translation
```

Safer alternatives:

```fsharp
query
    .OrderByDescending(fun row -> row.VisitCount)
    .ThenByDescending(fun row -> row.RowVersion)
```

or persist sortable UTC text and order by mapped property when appropriate.

Rules:
- Prefer numeric/int/long columns for tie-break ordering in SQL.
- Be cautious with `DateTimeOffset` in `OrderBy` and complex expressions.
- If provider translation fails, simplify expression, then only fallback to client-side ordering when result size is bounded.
- Confirm translation with integration tests against SQLite, not only in-memory providers.

## SQLite DDL and Migration Constraints

SQLite supports limited `ALTER TABLE` operations. Favor additive and rebuild-safe migrations.

Recommended DBUp flow for structural changes:
1. Add new nullable/defaulted column.
2. Backfill data.
3. Switch reads/writes in app code.
4. Rebuild table only when strictly required (create new table, copy data, swap names) in a dedicated migration script.

Rules:
- Do not assume SQL Server/Postgres DDL features exist.
- Keep migrations idempotent where possible.
- Never edit previously-applied DBUp scripts; add new numbered scripts.

## SQLite Locking and Transaction Behavior

SQLite permits many readers but only one writer at a time.

Rules:
- Keep write transactions short.
- Avoid long-running transactions around network or heavy CPU work.
- Expect transient `database is locked` under contention and add bounded retries where appropriate.
- Prefer WAL mode for concurrent read/write workloads when operationally acceptable.

## Decimal Precision Strategy

SQLite has dynamic typing; precision can drift if storage is not explicit.

Rules:
- For money/precise values, prefer scaled integers (for example cents) or explicit canonical string format.
- Keep EF converter and DBUp column contract aligned.
- Add round-trip tests for boundary precision values.

## Guid Storage Strategy

Choose one representation and keep it consistent across SQL + EF mappings.

Options:
- `TEXT` GUID (human-readable, common in mixed tooling).
- `BLOB` GUID (compact, requires stricter conversion handling).

Rules:
- Do not mix `TEXT` and `BLOB` for the same logical key.
- Ensure joins and indexes use the same representation on both sides.

## Collation and Case-Sensitivity

Default SQLite collation and comparison semantics may not match business rules.

Rules:
- Define whether lookup/uniqueness is case-sensitive per field.
- Normalize values at write-time when case-insensitive behavior is required (for example lowercased email).
- Add matching indexes for normalized lookup columns.

## Foreign Key Enforcement

SQLite foreign keys are runtime-config sensitive.

Rules:
- Make FK expectations explicit in schema and runtime.
- Verify FK behavior in integration tests (insert/update/delete constraints).
- Do not assume FK checks are enabled unless validated in your runtime setup.

## Index Design and Query Plan Checks

SQLite benefits from indexes shaped to actual predicates and ordering.

Rules:
- Create composite indexes that match common `WHERE` + `ORDER BY`.
- Re-check index coverage when query shape changes.
- Validate critical query plans with SQLite tooling (`EXPLAIN QUERY PLAN`) during performance-sensitive changes.

## SQLite JSON TEXT Guidance

When persisting JSON in TEXT columns:

Rules:
- Store explicit, version-tolerant serialized shapes.
- Keep serializer options stable for event/audit payloads.
- Validate compatibility if SQLite JSON functions are used; do not assume extension availability across environments.

## Placement Map and Anti-Patterns

Do:
- Put DB conversion logic in `<Project>DbContext.fs`.
- Put HTTP JSON conversion logic in `Application/DTOs/JsonConverters.fs` and register in `Api/Program.fs`.
- Keep validation in domain `Create` functions.
- Keep repository code thin and type-safe.

Do not:
- Put `ValueConverter` logic in Domain.
- Parse ad-hoc JSON inside controllers for domain models.
- Duplicate conversion logic in multiple repositories.
- Store unvalidated strings when a domain constructor exists.

## Implementation Checklist for New Complex Types

1. Define/extend domain type with `Create` and `ToString` (or stable structured representation).
2. Add DB migration for new column(s) if needed.
3. Add EF `ValueConverter` and `entity.Property(...).HasConversion(...)` in `<Project>DbContext.fs`.
4. Map table/column names explicitly when SQL naming differs (for example snake_case).
5. Add API `JsonConverter` if type appears in requests/responses.
6. Register API converter in `Program.fs`.
7. Update repositories only if query/use-case logic changed.
8. Add tests:
- round-trip domain value -> DB -> domain value
- invalid DB payload behavior
- API JSON serialization and deserialization for the type
- SQLite translation regression tests for ordering/filtering
 - migration safety test/verification for altered schema paths
 - precision and collation behavior tests when relevant
9. Run:
- `dotnet build <Project>.sln -c Release`
- `dotnet test <Project>.sln`
