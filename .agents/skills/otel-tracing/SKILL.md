---
name: otel-tracing
description: Use when introducing commands/controllers and maintaining OpenTelemetry trace coverage.
---

# Skill: otel-tracing

Use this when introducing new commands/controllers and keeping trace coverage complete.

## Checklist
1. Ensure handler is wrapped with tracing decorator in DI.
2. Verify span naming remains consistent (`entity.command_name`).
3. Ensure sensitive fields are filtered from span attributes.
4. Verify OTEL exporter/env config in target environment.
5. Register any new tracing decorators/services in `src/FsharpStarter.Api/src/Program.fs` in the same PR.
6. Add startup/integration coverage that fails on missing tracing DI registration.

## Verification Commands
1. `dotnet tool run fantomas .`
2. `dotnet build src/FsharpStarter.Api/FsharpStarter.Api.fsproj`
3. `dotnet test src/FsharpStarter.Infrastructure/test/FsharpStarter.Infrastructure.Tests.fsproj --filter "FullyQualifiedName~AutoTracingTests"`
4. Run API locally and inspect traces in collector/Jaeger.
