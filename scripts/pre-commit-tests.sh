#!/bin/bash
set -e

# Detect staged file types
STAGED_FS_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(fs|fsx|fsi)$' || true)
STAGED_TS_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(ts|tsx)$' || true)
STAGED_API_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '(Controller|Dto)\.fs$' || true)

EXIT_CODE=0

# Run F# tests if F# files changed
if [ -n "$STAGED_FS_FILES" ]; then
  echo "F# files changed, running format, build, and tests..."
  dotnet tool run fantomas .
  dotnet build FsharpStarter.sln -c Release || EXIT_CODE=$?
  dotnet test FsharpStarter.sln || EXIT_CODE=$?
fi

# Warn about API changes that may require type regeneration
if [ -n "$STAGED_API_FILES" ]; then
  echo ""
  echo "⚠️  API files changed (Controllers/DTOs). Remember to regenerate types:"
  echo "   1. Start backend: docker compose up -d"
  echo "   2. Run: curl http://localhost:5001/swagger/v1/swagger.json > openapi.spec.json"
  echo "   3. Run: cd www && npm run generate-api-types"
  echo ""
fi

# Run frontend type check and tests if TypeScript files changed
if [ -n "$STAGED_TS_FILES" ]; then
  echo "TypeScript files changed, running strict frontend checks..."
  cd www && npm run check && npm run lint && npx tsc --noEmit && npm test || EXIT_CODE=$?
fi

exit $EXIT_CODE
