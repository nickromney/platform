# C# Azure Web App and Function App Deployment Notes

## Overview

This document captures the learnings from deploying minimal .NET 9.0 Web App and Function App to Azure for testing Easy Auth with Managed Identity patterns.

## Summary of Deployments

### Function App

- **Name**: `func-csharp-test-f6fe93`
- **Runtime**: .NET 9.0 (isolated worker)
- **Status**: Working
- **Endpoints**: `/api/health`, `/api/test`
- **Deployment Method**: Zip deployment via Azure CLI

### Web App

- **Name**: `web-csharp-test-f6fe93`
- **Runtime**: .NET 9.0 (ASP.NET Core minimal API)
- **Status**: Working
- **Endpoints**: `/`, `/health`, `/test` (proxies to Function App)
- **Deployment Method**: `az webapp deploy --type zip`

## Key Learnings

### 1. Stack Configuration Issue (CRITICAL)

**Problem**: Even though `az webapp config set --linux-fx-version "DOTNET|9.0"` was run, the Azure Portal showed the Stack dropdown as **empty**.

**Symptoms**:

- Deployment reported "successful"
- Logs showed: `/opt/startup/startup.sh: dotnet: not found`
- Container was using a generic Linux image without .NET runtime
- PHP-FPM was starting instead of the .NET app
- All endpoints returned nginx 403/404 errors

**Root Cause**: The CLI command sets the `linuxFxVersion` property but doesn't fully provision the .NET runtime stack in the same way the portal does.

**Solution**: Manually configure via Azure Portal:

1. Go to Configuration > General Settings
2. Set **Stack**: `.NET`
3. Set **Major version**: `.NET 9 (STS)`
4. Set **Minor version**: `.NET 9 (STS)`
5. Save and redeploy the application

**After Fix**: The app immediately worked on the next deployment.

### 2. Deployment Method

**What Works**: `az webapp deploy --type zip`

```bash
# Build
dotnet publish -c Release -o ./publish

# Create zip
cd publish && zip -r ../deploy.zip . && cd ..

# Deploy
az webapp deploy \
  --resource-group rg-subnet-calc \
  --name web-csharp-test-f6fe93 \
  --src-path deploy.zip \
  --type zip
```

**What Doesn't Work Well**: `az webapp deployment source config-zip`

- Older method
- Less reliable for .NET apps
- Doesn't always trigger proper runtime detection

### 3. App Settings for .NET Web Apps

**Critical settings** (different from Node.js/Python):

- `SCM_DO_BUILD_DURING_DEPLOYMENT=false` - We deploy pre-compiled binaries
- `WEBSITE_RUN_FROM_PACKAGE=0` - Allow extraction and execution
- **Do NOT set** `ENABLE_ORYX_BUILD=true` - Not needed for .NET

### 4. Local Testing Pattern

**Dockerfile approach works perfectly**:

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY *.csproj ./
RUN dotnet restore
COPY . ./
RUN dotnet publish -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:9.0
WORKDIR /app
COPY --from=build /app/publish .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "TestWebApp.dll"]
```

**Benefits**:

- Validates code works before Azure deployment
- Tests both local and remote Function App connectivity
- Faster iteration cycle

### 5. Function App vs Web App Differences

**Function App**:

- Runtime sets correctly via `az functionapp config set`
- Deployment just works
- No Stack configuration issues

**Web App**:

- Requires manual Stack configuration in portal
- CLI commands don't fully provision the stack
- More prone to configuration drift

## Testing Results

### Local Testing

Function App → localhost:7071
Web App → localhost:8080
Web App → Local Function App
Web App → Remote Function App (Azure)

### Azure Testing

Function App endpoints (/api/health, /api/test)
Web App root endpoint (/)
Web App health endpoint (/health)
Web App proxy endpoint (/test → Function App)

## Authentication Patterns (To Test)

### Pattern 1: No Authentication (COMPLETED)

- Web App → Function App
- **Status**: Working
- **Use case**: Internal services

### Pattern 2: Easy Auth with Managed Identity (TODO)

- User → Web App (Easy Auth)
- Web App MI → Function App (Easy Auth)
- **Status**: 🔄 Not yet implemented
- **Use case**: Production secured applications

### Pattern 3: Direct Function App Access (TODO)

- User → Function App (Easy Auth)
- **Status**: 🔄 Not yet implemented
- **Use case**: API-only scenarios

## Deployment Checklist

For future .NET 9.0 Web App deployments:

1. Create Web App via CLI
2. **Immediately** configure Stack in Azure Portal
   - Stack: .NET
   - Major: .NET 9 (STS)
   - Minor: .NET 9 (STS)
3. Set app settings if needed
4. Build: `dotnet publish -c Release -o ./publish`
5. Package: `cd publish && zip -r ../deploy.zip .`
6. Deploy: `az webapp deploy --type zip`
7. Test endpoints

## Resources

- Function App: <https://func-csharp-test-f6fe93.azurewebsites.net>
- Web App: <https://web-csharp-test-f6fe93.azurewebsites.net>
- Resource Group: rg-subnet-calc
- App Service Plan: plan-subnetcalc-dev-easyauth-proxied (P0v3)

## Next Steps

1. Configure Easy Auth on Function App
2. Configure Easy Auth on Web App
3. Create Managed Identity for Web App
4. Grant Web App MI access to Function App
5. Test authenticated patterns
6. Document findings
7. Replicate in Terraform if patterns work
