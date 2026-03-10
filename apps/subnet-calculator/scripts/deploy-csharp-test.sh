#!/usr/bin/env bash
set -euo pipefail

FUNC_NAME="${FUNC_NAME:-func-csharp-test-f6fe93}"
WEB_NAME="${WEB_NAME:-web-csharp-test-f6fe93}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-subnet-calc}"

echo "========================================"
echo "Deploying C# Test Apps"
echo "========================================"
echo "Function App: ${FUNC_NAME}"
echo "Web App: ${WEB_NAME}"
echo ""

# Deploy Function App
echo "Building and deploying Function App..."
cd csharp-test/function-app
dotnet publish -c Release -o ./publish
cd publish
zip -r ../deploy.zip .
cd ..
az functionapp deployment source config-zip \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${FUNC_NAME}" \
  --src deploy.zip
cd ../..

# Deploy Web App
echo "Building and deploying Web App..."
cd csharp-test/web-app
dotnet publish -c Release -o ./publish
cd publish
zip -r ../deploy.zip .
cd ..
az webapp deployment source config-zip \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${WEB_NAME}" \
  --src deploy.zip
cd ../..

echo ""
echo "========================================"
echo "Deployments Complete!"
echo "========================================"
echo "Function App: https://${FUNC_NAME}.azurewebsites.net"
echo "Web App: https://${WEB_NAME}.azurewebsites.net"
