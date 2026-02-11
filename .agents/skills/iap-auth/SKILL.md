---
name: iap-auth
description: Implement and review Google Cloud IAP-backed authentication, identity provisioning, and authorization layering in this starter with concrete architecture checks and F# code samples.
---

# Skill: iap-auth

Use this when an app needs Google Cloud IAP-backed authentication and identity provisioning with clean hexagonal boundaries.

## Overview
Analyze, implement, or refactor IAP auth in `FsharpStarter` with file-level decisions and small F# snippets.
Baseline starter has no IAP middleware enabled by default, so treat this as an opt-in capability.

## Workflow
1. Locate auth entry points and current middleware order.
2. Map each auth component to API/Application/Infrastructure/Domain layers.
3. Enforce strict hexagonal boundaries (identity provisioning orchestration in Application).
4. Implement or adjust middleware, ports, adapters, and DI wiring.
5. Validate with build/tests and explicit failure-path checks.

## Step 1: Locate Entry Points
Read these files first:
- `src/FsharpStarter.Api/src/Program.fs`
- `src/FsharpStarter.Api/src/Middleware/IapAuthMiddleware.fs` (if present)
- `src/FsharpStarter.Api/src/Middleware/DevAuthMiddleware.fs` (if present)
- `src/FsharpStarter.Api/src/Controllers/*`

Confirm:
- Middleware registration order in `Program.fs`.
- Dev-vs-prod execution path.
- Where authenticated identity is written (for example `HttpContext.Items["UserId"]` or claims principal).
- How controllers read current user context.

## Step 2: Layer Mapping (Strict Hexagonal)
Use this mapping model explicitly:
- API layer: inbound adapters only (middleware/controllers). No business orchestration.
- Application layer: identity provisioning use cases + authorization ports/interfaces.
- Infrastructure layer: Google/OpenFGA/IdP clients, repository adapters.
- Domain layer: entities/value objects/events/rules only.

If identity provisioning orchestration is currently in API, move it.

Required purity decision:
- Keep `IapAuthMiddleware` in API (correct).
- Place `IdentityProvisioningService` in Application (not API), consuming ports such as repository and authorization abstractions.
- Keep middleware thin: validate identity token/header, call application use case, set request user context.

## Step 3: Canonical File Mapping
Use or create modules in these locations:
- API middleware: `src/FsharpStarter.Api/src/Middleware/IapAuthMiddleware.fs`
- API dev middleware (optional): `src/FsharpStarter.Api/src/Middleware/DevAuthMiddleware.fs`
- Application provisioning service: `src/FsharpStarter.Application/src/Identity/IdentityProvisioningService.fs`
- Application ports: `src/FsharpStarter.Application/src/Interfaces/IIdentityProvisioningService.fs`
- Infrastructure identity adapter(s): `src/FsharpStarter.Infrastructure/src/Services/*`

Avoid placing provisioning orchestration in:
- `src/FsharpStarter.Api/src/Services/IdentityProvisioningService.fs` (anti-pattern for strict purity).

## Step 4: Runtime Request Flow
Document or implement this order:
1. Request enters `IapAuthMiddleware`.
2. Middleware extracts IAP assertion/header and validates JWT/signature/audience.
3. Middleware builds an identity DTO and calls application provisioning service.
4. Provisioning service loads/creates/updates local user and optional authorization tuples via ports.
5. Middleware writes resolved user id/context to request (`HttpContext.Items` or claims).
6. Controllers/handlers perform permission checks through application ports.

## Step 5: Config Keys to Standardize
Use strongly-typed options and confirm these keys exist:
- `Auth:IAP:Enabled`
- `Auth:IAP:ValidateJwt`
- `Auth:IAP:JwtAudience`
- `Auth:IAP:Issuer`
- `Auth:IAP:JwksUrl` (or cert URL)
- `Auth:IAP:EmailHeader`

## F# Sample: Pipeline Registration (`Program.fs`)
```fsharp
let app = builder.Build()

if app.Environment.IsDevelopment() then
    app.UseMiddleware<DevAuthMiddleware>() |> ignore
else
    app.UseMiddleware<IapAuthMiddleware>() |> ignore

app.MapControllers()
```

## F# Sample: Thin API Middleware
```fsharp
type IapAuthMiddleware(next: RequestDelegate) =
    member _.InvokeAsync(ctx: HttpContext, provisioning: IIdentityProvisioningService) =
        task {
            let iapEmail = ctx.Request.Headers["X-Goog-Authenticated-User-Email"].ToString()

            if String.IsNullOrWhiteSpace(iapEmail) then
                ctx.Response.StatusCode <- StatusCodes.Status401Unauthorized
            else
                let! user = provisioning.ProvisionAsync({ Email = iapEmail })
                ctx.Items["UserId"] <- user.Id
                do! next.Invoke(ctx)
        }
```

## F# Sample: Application Service (Correct Layer)
```fsharp
type IdentityProvisioningService
    (
        userRepository: IUserRepository,
        authorizationService: IAuthorizationService
    ) =
    interface IIdentityProvisioningService with
        member _.ProvisionAsync(identity: ProvisionIdentityRequest) =
            task {
                let! user = userRepository.GetByEmailAsync(identity.Email)
                match user with
                | Some existing -> return existing
                | None ->
                    let! created = userRepository.CreateAsync(identity.Email)
                    do! authorizationService.EnsureDefaultAccessAsync(created.Id)
                    return created
            }
```

## F# Sample: Controller User Context Access
```fsharp
member this.CurrentUserId
    with get () =
        match this.HttpContext.Items.TryGetValue("UserId") with
        | true, value -> value :?> Guid
        | _ -> Guid.Empty
```

## F# Sample: Authorization Port Boundary
```fsharp
type IAuthorizationService =
    abstract member CheckPermissionAsync: userId: Guid * relation: string * objectId: string -> Task<bool>
```

## Output Requirements (when answering architecture questions)
- Lead with direct answer on layer placement.
- Include a compact "Layer Mapping" section.
- Include a compact "Request Flow" section.
- Include file paths for all major claims.
- Include small, concrete F# snippets (not pseudocode).
- Call out caveats and refactor targets if orchestration leaks into API.

## Fast Search Commands
```bash
rg -n "IapAuthMiddleware|DevAuthMiddleware|UseMiddleware|IdentityProvisioningService|UserId" src --glob '*.fs'
```

```bash
rg -n "Auth:IAP|JwtAudience|Issuer|JwksUrl|X-Goog-Authenticated-User-Email" src --glob '*.fs' --glob '*.json'
```

## Validation Checklist
Run after each meaningful change:
1. `dotnet tool run fantomas .`
2. `dotnet build FsharpStarter.sln -c Release`
3. `dotnet test FsharpStarter.sln`
4. `cd www && npm run check && npm run lint && npm test`
5. Run `review-backend` skill for backend-auth changes.
