#!/usr/bin/env bash
set -euo pipefail

# Minimal C# Test - Prove Easy Auth + MI works
# This script creates minimal C# Function App + Web App to test authentication patterns

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-subnet-calc}"
LOCATION="${LOCATION:-uksouth}"
PLAN_NAME="${PLAN_NAME:-plan-subnetcalc-dev-easyauth-proxied}"
SUFFIX=$(openssl rand -hex 3)

# Names
STORAGE_NAME="stcsharptest${SUFFIX}"
FUNC_NAME="func-csharp-test-${SUFFIX}"
WEB_NAME="web-csharp-test-${SUFFIX}"

echo "========================================"
echo "Creating Minimal C# Test Environment"
echo "========================================"
echo "Resource Group: ${RESOURCE_GROUP}"
echo "Location: ${LOCATION}"
echo "App Service Plan: ${PLAN_NAME} (existing P0v3)"
echo "Suffix: ${SUFFIX}"
echo ""
echo "Resources to create:"
echo "  Storage Account: ${STORAGE_NAME}"
echo "  Function App: ${FUNC_NAME}"
echo "  Web App: ${WEB_NAME}"
echo ""

# Create Storage Account for Function App
echo "Creating Storage Account..."
az storage account create \
  --name "${STORAGE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --sku Standard_LRS

# Create Function App (C#, .NET 8)
echo "Creating Function App..."
az functionapp create \
  --name "${FUNC_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --plan "${PLAN_NAME}" \
  --storage-account "${STORAGE_NAME}" \
  --runtime dotnet-isolated \
  --runtime-version 8 \
  --functions-version 4 \
  --os-type Linux

# Create Web App (C#, .NET 8)
echo "Creating Web App..."
az webapp create \
  --name "${WEB_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --plan "${PLAN_NAME}" \
  --runtime "DOTNETCORE:8.0"

# Enable System-Assigned Managed Identity on Web App
echo "Enabling Managed Identity on Web App..."
az webapp identity assign \
  --name "${WEB_NAME}" \
  --resource-group "${RESOURCE_GROUP}"

echo ""
echo "========================================"
echo "Resources Created!"
echo "========================================"
echo "Function App: https://${FUNC_NAME}.azurewebsites.net"
echo "Web App: https://${WEB_NAME}.azurewebsites.net"
echo ""
echo "Next steps:"
echo "1. Deploy minimal C# code to both apps"
echo "2. Configure Easy Auth on Function App"
echo "3. Configure Easy Auth on Web App"
echo "4. Grant Web App MI permission to call Function App"
echo "5. Test both authentication patterns"
echo ""
echo "Save these names for next steps:"
echo "export FUNC_NAME='${FUNC_NAME}'"
echo "export WEB_NAME='${WEB_NAME}'"
