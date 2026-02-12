# EF Core + F# Mapping Patterns

## Table of Contents
- Value object to scalar mapping
- Option to nullable/null mapping
- Complex list to JSON TEXT mapping
- Discriminated union mapping patterns
- API JSON converters for domain types
- Event payload serialization/deserialization
- Repository usage pattern
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
4. Add API `JsonConverter` if type appears in requests/responses.
5. Register API converter in `Program.fs`.
6. Update repositories only if query/use-case logic changed.
7. Add tests:
- round-trip domain value -> DB -> domain value
- invalid DB payload behavior
- API JSON serialization and deserialization for the type
8. Run:
- `dotnet build <Project>.sln -c Release`
- `dotnet test <Project>.sln`
