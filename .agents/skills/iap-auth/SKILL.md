---
name: iap-auth
description: Use when implementing Google Cloud IAP-backed authentication and identity provisioning in this starter.
---

# Skill: iap-auth

Use this when an app needs Google Cloud IAP-backed authentication and identity provisioning.

## Goal
Add IAP auth as an optional outer-layer capability without polluting domain logic.
Baseline `FsharpStarter` has no IAP middleware enabled by default.

## Architecture Placement
- Domain (`src/FsharpStarter.Domain`): no IAP code.
- Application (`src/FsharpStarter.Application`): identity/authorization interfaces only.
- Infrastructure (`src/FsharpStarter.Infrastructure`): external clients and adapters for Google APIs.
- API (`src/FsharpStarter.Api`): middleware for IAP headers/JWT, controller endpoints for provisioning.

## Implementation Flow
1. Add/confirm app settings keys for IAP issuer, audience, cert URL.
2. Add IAP middleware in API layer and wire in pipeline before controllers.
3. Keep user provisioning in application service interfaces; implement adapters in infrastructure/API services.
4. Register every new auth/provisioning dependency in `src/FsharpStarter.Api/src/Program.fs` in the same PR.
5. Add dev-mode fallback middleware for local non-IAP usage.
6. Add integration tests for:
   - Valid IAP header/JWT -> authenticated request.
   - Missing/invalid assertion -> 401.
   - Provisioning failures -> controlled error path.
7. Add startup/integration coverage that fails fast on missing DI registrations.

## Code Mapping (create these modules when enabling IAP)
- Middleware: `src/FsharpStarter.Api/src/Middleware/IapAuthMiddleware.fs`
- Optional dev fallback middleware: `src/FsharpStarter.Api/src/Middleware/DevAuthMiddleware.fs`
- Provisioning: `src/FsharpStarter.Api/src/Services/IdentityProvisioningService.fs`
- Google directory adapter: `src/FsharpStarter.Api/src/Services/GoogleDirectoryIdentityService.fs`

## Verification Commands
Run after each step:
1. `dotnet tool run fantomas .`
2. `dotnet build src/FsharpStarter.Api/FsharpStarter.Api.fsproj`
3. `dotnet test src/FsharpStarter.Infrastructure/test/FsharpStarter.Infrastructure.Tests.fsproj --filter "FullyQualifiedName~Middleware|FullyQualifiedName~IdentityProvisioning"`
4. `dotnet test FsharpStarter.sln`
