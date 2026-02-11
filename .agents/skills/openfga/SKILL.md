---
name: openfga
description: Use when adding or modifying relationship-based authorization with OpenFGA.
---

# OpenFGA Hexagonal Architecture (Template)

## Overview
Use this skill to implement OpenFGA in `FsharpStarter` without breaking Domain/Application/Infrastructure/API boundaries.

This starter does not currently include OpenFGA. Treat the snippets below as templates to instantiate in this repo.

## Workflow
1. Add application auth port + typed auth language.
2. Add infrastructure OpenFGA adapter.
3. Wire DI + settings in API startup.
4. Add request-path permission checks in controllers/handlers.
5. Add tests for allow/deny and tuple writes.

## Read First
- `src/FsharpStarter.Api/src/Program.fs`
- `src/FsharpStarter.Api/src/Controllers/ExamplesController.fs`
- `src/FsharpStarter.Application/src/Handlers/ExampleHandler.fs`
- `src/FsharpStarter.Domain/src/Ports/IExampleRepository.fs`
- `src/FsharpStarter.Infrastructure/src/Database/Persistence.fs`

## Layer Mapping (Best Practice)
- API layer: authenticate caller, map route/resource to auth object, enforce request-level checks via application port.
- Application layer: define `IAuthorizationService` and typed auth unions; orchestrate use-case permission reads/writes.
- Infrastructure layer: own OpenFGA SDK usage, tuple serialization, check/write/list calls, retry/logging.
- Domain layer: no OpenFGA SDK, no tuple string literals, no infrastructure dependencies.

## Implement Here vs Do Not Implement Here

### Implement Here
- Add auth port in Application: `src/FsharpStarter.Application/src/Ports/IAuthorizationService.fs`.
- Add OpenFGA adapter in Infrastructure: `src/FsharpStarter.Infrastructure/src/Services/OpenFgaService.fs`.
- Register adapter + options in API startup: `src/FsharpStarter.Api/src/Program.fs`.
- Do endpoint permission checks in controllers and use-case-level tuple updates in handlers.

### Do Not Implement Here
- Do not call OpenFGA SDK from controllers, handlers, or domain.
- Do not scatter raw tuple strings (`"user:123"`, `"can_edit"`) outside auth mapping helpers.
- Do not place policy logic inside domain entities.

## Templated Code Samples

### 1) Application Port + Typed Auth Language
`src/FsharpStarter.Application/src/Ports/IAuthorizationService.fs` (new file)
```fsharp
namespace {{ProjectName}}.Application.Ports

open System.Threading.Tasks

type AuthSubject =
    | User of string
    | ServiceAccount of string

type AuthRelation =
    | {{ReadRelationCase}}
    | {{WriteRelationCase}}
    | {{AdminRelationCase}}

type AuthObject =
    | {{ResourceTypeA}} of string
    | {{ResourceTypeB}} of string

type RelationshipTuple =
    { Subject: AuthSubject
      Relation: AuthRelation
      Object: AuthObject }

type RelationshipUpdate =
    { TuplesToAdd: RelationshipTuple list
      TuplesToRemove: RelationshipTuple list }

type IAuthorizationService =
    abstract member CheckPermissionAsync:
        subject: AuthSubject * relation: AuthRelation * ``object``: AuthObject -> Task<bool>

    abstract member CreateRelationshipsAsync: RelationshipTuple list -> Task<unit>
    abstract member UpdateRelationshipsAsync: RelationshipUpdate -> Task<unit>
```

### 2) Infrastructure Adapter Owns OpenFGA SDK
`src/FsharpStarter.Infrastructure/src/Services/OpenFgaService.fs` (new file)
```fsharp
namespace {{ProjectName}}.Infrastructure.Services

open System.Threading.Tasks
open Microsoft.Extensions.Logging
open OpenFga.Sdk.Client
open {{ProjectName}}.Application.Ports

type OpenFgaOptions =
    { ApiUrl: string
      StoreId: string
      AuthorizationModelId: string option }

module private AuthTypes =
    let subjectToString = function
        | User id -> $"user:{id}"
        | ServiceAccount id -> $"service_account:{id}"

    let relationToString = function
        | {{ReadRelationCase}} -> "{{read_relation}}"
        | {{WriteRelationCase}} -> "{{write_relation}}"
        | {{AdminRelationCase}} -> "{{admin_relation}}"

    let objectToString = function
        | {{ResourceTypeA}} id -> "{{resource_a}}:{id}"
        | {{ResourceTypeB}} id -> "{{resource_b}}:{id}"

type OpenFgaService(options: OpenFgaOptions, logger: ILogger<OpenFgaService>) =
    interface IAuthorizationService with
        member _.CheckPermissionAsync(subject, relation, ``object``) : Task<bool> =
            task {
                use client = OpenFgaClient(options.ApiUrl, options.StoreId)

                let body =
                    ClientCheckRequest(
                        User = AuthTypes.subjectToString subject,
                        Relation = AuthTypes.relationToString relation,
                        Object = AuthTypes.objectToString ``object``
                    )

                let! response = client.Check(body)
                return response.Allowed.GetValueOrDefault(false)
            }

        member _.CreateRelationshipsAsync(tuples) : Task<unit> =
            task { return () } // map tuples -> ClientWriteRequest and call Write

        member _.UpdateRelationshipsAsync(update) : Task<unit> =
            task { return () } // map add/remove lists and call Write atomically
```

### 3) API DI Wiring Uses Port Abstraction
`src/FsharpStarter.Api/src/Program.fs`
```fsharp
open {{ProjectName}}.Application.Ports
open {{ProjectName}}.Infrastructure.Services

type AuthorizationMode =
    | AllowAll
    | OpenFga

type AuthorizationSettings =
    { Mode: AuthorizationMode
      OpenFga: OpenFgaOptions option }

let authSettings = builder.Configuration.GetSection("Authorization").Get<AuthorizationSettings>()

match authSettings.Mode with
| AllowAll ->
    builder.Services.AddScoped<IAuthorizationService, AllowAllAuthorizationService>() |> ignore
| OpenFga ->
    let options = authSettings.OpenFga.Value
    builder.Services.AddSingleton(options) |> ignore
    builder.Services.AddScoped<IAuthorizationService, OpenFgaService>() |> ignore
```

### 4) Controller Request Check via `IAuthorizationService`
`src/FsharpStarter.Api/src/Controllers/ExamplesController.fs`
```fsharp
[<HttpPost("{exampleId}/{{action_name}}")>]
member _.{{ActionName}}(exampleId: string) =
    task {
        let subject = User(httpContext.User.FindFirst("sub").Value)
        let relation = {{WriteRelationCase}}
        let resource = {{ResourceTypeA}}(exampleId)

        let! allowed = authorizationService.CheckPermissionAsync(subject, relation, resource)

        if not allowed then
            return this.Forbid() :> IActionResult
        else
            // continue use case
            return this.Ok() :> IActionResult
    }
```

### 5) Handler Tuple Diff + Atomic Update
`src/FsharpStarter.Application/src/Handlers/ExampleHandler.fs`
```fsharp
let! existing = repository.GetAsync(command.Id)
let tuplesToAdd, tuplesToRemove = computePermissionDiff existing command

if (not tuplesToAdd.IsEmpty) || (not tuplesToRemove.IsEmpty) then
    do!
        authorizationService.UpdateRelationshipsAsync
            { TuplesToAdd = tuplesToAdd
              TuplesToRemove = tuplesToRemove }
```

## Repo Conversion Plan (`FsharpStarter` -> OpenFGA-enabled)
1. Create new application auth contract file:
   - `src/FsharpStarter.Application/src/Ports/IAuthorizationService.fs`
2. Create infrastructure OpenFGA adapter + options:
   - `src/FsharpStarter.Infrastructure/src/Services/OpenFgaService.fs`
3. Add starter fallback implementation:
   - `src/FsharpStarter.Infrastructure/src/Services/AllowAllAuthorizationService.fs`
4. Register new files in `.fsproj` compile order:
   - `src/FsharpStarter.Application/FsharpStarter.Application.fsproj`
   - `src/FsharpStarter.Infrastructure/FsharpStarter.Infrastructure.fsproj`
   - `src/FsharpStarter.Api/FsharpStarter.Api.fsproj` (if new API files are added)
5. Wire DI and settings in API:
   - Update `src/FsharpStarter.Api/src/Program.fs`
   - Add `Authorization` config section to `src/FsharpStarter.Api/appsettings.json`
6. Add endpoint-level permission checks where needed:
   - Update `src/FsharpStarter.Api/src/Controllers/ExamplesController.fs`
7. Add use-case-level tuple orchestration:
   - Update `src/FsharpStarter.Application/src/Handlers/ExampleHandler.fs`
8. Add tests:
   - Application tests for permission orchestration in `src/FsharpStarter.Application/test`
   - Infrastructure tests for OpenFGA adapter behavior in `src/FsharpStarter.Infrastructure/test`
   - API tests for `403`/`200` paths in `src/FsharpStarter.Infrastructure/test/ExamplesControllerTests.fs`

## Anti-Patterns to Flag in Review
- `open OpenFga.Sdk.*` outside infrastructure.
- Raw relation/object tuple strings outside auth mapping helpers.
- Domain references to `IAuthorizationService`.
- Controllers mutating tuples directly instead of using application handlers/services.

## Fast Verification Commands
```bash
rg -n "IAuthorizationService|OpenFgaService|AllowAllAuthorizationService|CheckPermissionAsync|UpdateRelationshipsAsync" src --glob '*.fs'
```

```bash
dotnet tool run fantomas .
dotnet build FsharpStarter.sln -c Release
dotnet test FsharpStarter.sln
```
