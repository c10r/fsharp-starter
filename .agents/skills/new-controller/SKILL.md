---
name: new-controller
description: Add or update an ASP.NET Core F# controller flow end-to-end across Domain, Application, Infrastructure, and API layers with consistent DTO contracts, error mapping, DI wiring, and validation.
---

# New Controller Authoring

Use this skill when introducing a new endpoint flow (or expanding an existing controller) in this starter template.

## Workflow

1. Define or update DTOs in `src/<ProductName>.Application/src/DTOs/`.
2. Add/update command + handler logic in Application.
3. Implement controller endpoints in `src/<ProductName>.Api/src/Controllers/`.
4. Register handler + `ICommandHandler<_, _>` wiring in `src/<ProductName>.Api/src/Program.fs`.
5. Register JSON converters when needed in `Program.fs` and `DTOs/JsonConverters.fs`.
6. Add file order entries in the relevant `.fsproj` files.

## Controller Pattern

### 1) Class shape

Use this structure for command-driven controllers:

```fsharp
namespace Product.Api.Controllers

open System.Threading.Tasks
open Microsoft.AspNetCore.Mvc
open Microsoft.AspNetCore.Http
open Product.Domain
open Product.Application.DTOs
open Product.Application.Commands
open Product.Application.Interfaces

[<ApiController>]
[<Route("api/widgets")>]
type WidgetsController
    (
        commandHandler: ICommandHandler<WidgetCommand, WidgetCommandResult>,
        authorizationService: IAuthorizationService
    ) =
    inherit AuthenticatedControllerBase()
```

Use `AuthenticatedControllerBase` when endpoint logic needs `CurrentUserId`.

### 2) Endpoint shape

Use this template for most mutating endpoints:

```fsharp
[<HttpPost>]
[<ProducesResponseType(typeof<WidgetDto>, StatusCodes.Status201Created)>]
[<ProducesResponseType(StatusCodes.Status400BadRequest)>]
[<ProducesResponseType(StatusCodes.Status403Forbidden)>]
[<ProducesResponseType(StatusCodes.Status500InternalServerError)>]
member this.Create([<FromBody>] dto: CreateWidgetDto) : Task<IActionResult> =
    task {
        let userId = this.CurrentUserId

        let! hasPermission =
            authorizationService.CheckPermissionAsync(userId, "widget:create", dto.ScopeId)

        if not hasPermission then
            return
                this.StatusCode(
                    403,
                    {| error = "Forbidden"
                       message = "You do not have permission for this action" |}
                )
                :> IActionResult
        else
            let! result = commandHandler.HandleCommand(CreateWidget(userId, dto))

            return
                match result with
                | Ok(WidgetResult created) ->
                    this.CreatedAtAction(nameof this.GetById, {| id = created.Id |}, created)
                    :> IActionResult
                | Ok _ -> this.StatusCode(500, "Unexpected result type") :> IActionResult
                | Error error -> this.HandleDomainError(error)
    }
```

### 3) DomainError mapping

Keep a local helper (`HandleDomainError`) that maps all relevant `DomainError` cases:

```fsharp
member private this.HandleDomainError(error: DomainError) : IActionResult =
    match error with
    | ValidationError message ->
        this.BadRequest
            {| error = "Validation failed"
               message = message |}
        :> IActionResult
    | NotFound message ->
        this.NotFound
            {| error = "Resource not found"
               message = message |}
        :> IActionResult
    | Conflict message ->
        this.Conflict
            {| error = "Conflict"
               message = message |}
        :> IActionResult
    | InvalidOperation message ->
        this.UnprocessableEntity
            {| error = "Invalid operation"
               message = message |}
        :> IActionResult
```

### 4) ID parsing and pagination

Follow consistent conventions:
- Validate string IDs early (`Guid.TryParse` or dedicated parser) and return a validation error on bad format.
- Normalize paging bounds consistently at the API boundary.
- Keep paging defaults and max limits shared across API, Application, and frontend contracts.

### 5) Authorization conventions

- Check permissions at the controller edge.
- Keep permission checks explicit per action (`Create`, `Read`, `Update`, `Delete`, etc.).
- Return `403` with a structured error body:

```fsharp
{| error = "Forbidden"; message = "..." |}
```

- Use small helper methods when checks repeat across endpoints.

### 6) Response sanitization pattern

If entities include sensitive fields, sanitize DTOs before returning:

```fsharp
let sanitized = ResponseSanitizer.sanitizeWidget widgetDto
return this.Ok(sanitized) :> IActionResult
```

## DTO Expectations

DTOs are transport contracts only (API boundary), not domain models.

### Required rules

- Place DTOs in `src/<ProductName>.Application/src/DTOs/*.fs`.
- Use validation attributes (`[<Required>]`, `[<StringLength>]`, etc.) for request DTOs.
- Keep incoming IDs as transport-safe types (`string`), then map/parse at the boundary.
- Use `option` for optional transport fields.
- Keep response DTOs serializable with primitive/DTO fields, not domain aggregates.

### DTO examples

```fsharp
type RenameWidgetDto =
    { [<Required>]
      [<StringLength(100, MinimumLength = 2)>]
      Name: string }
```

```fsharp
type CreateWidgetDto =
    { [<Required>]
      Name: string

      [<Required>]
      ScopeId: string

      Description: string option }
```

## JSON Converter Expectations

### When to add a converter

Add converters when API wire format should differ from default serializer behavior, especially for:
- Value objects and constrained types.
- Discriminated unions requiring stable JSON shape.
- Option/null/empty-string normalization requirements.

### Where to add converter logic

1. Implement converter in `src/<ProductName>.Application/src/DTOs/JsonConverters.fs`.
2. Register converter in `src/<ProductName>.Api/src/Program.fs` under `AddJsonOptions`.
3. Optionally use property-level `[<JsonConverter(typeof<...>)>]` for targeted fields.

### Example registration

```fsharp
options.JsonSerializerOptions.Converters.Add(CustomValueObjectConverter())
options.JsonSerializerOptions.Converters.Add(JsonFSharpConverter(allowOverride = true))
```

## DI + Tracing Wiring Checklist

For command-backed controllers, wire handler + optional tracing in `src/<ProductName>.Api/src/Program.fs`:

```fsharp
builder.Services.AddScoped<WidgetHandler>() |> ignore

builder.Services.AddScoped<ICommandHandler<WidgetCommand, WidgetCommandResult>>(fun sp ->
    let handler = sp.GetRequiredService<WidgetHandler>()
    let activitySource = sp.GetRequiredService<ActivitySource>()
    AutoTracing.createTracingDecorator "widget" handler activitySource)
|> ignore
```

Also register any repositories/services required by the handler.

## F# File Ordering Checklist

When adding files, update compile order in:
- `src/<ProductName>.Api/<ProductName>.Api.fsproj`
- `src/<ProductName>.Application/<ProductName>.Application.fsproj`
- `src/<ProductName>.Infrastructure/<ProductName>.Infrastructure.fsproj` (if needed)

Keep dependencies before dependents.

## Pre-merge Verification

```bash
dotnet tool run fantomas .
dotnet build <ProductName>.sln -c Release
dotnet test <ProductName>.sln
cd www && npm run check && npm run lint && npm test
```

For API contract changes, regenerate and commit OpenAPI/spec-derived frontend types.
