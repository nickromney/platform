#!/usr/bin/env bash
# Debug Azure Easy Auth and Managed Identity Configuration
# This script runs diagnostic checks for Web App + Function App authentication

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration (update these for your environment)
WEBAPP_NAME="${WEBAPP_NAME:-web-subnet-calc-react-easyauth-proxied}"
FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-subnet-calc-react-easyauth-proxied-api}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-subnet-calc}"

# Function to print section headers
print_section() {
  echo ""
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}========================================${NC}"
}

# Function to print success
print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

# Function to print error
print_error() {
  echo -e "${RED}✗ $1${NC}"
}

# Function to print warning
print_warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

# Check if required commands exist
check_dependencies() {
  print_section "Checking Dependencies"

  if ! command -v az &> /dev/null; then
    print_error "Azure CLI not found. Install from: https://aka.ms/install-azure-cli"
    exit 1
  fi
  print_success "Azure CLI installed"

  if ! command -v jq &> /dev/null; then
    print_warning "jq not found. Install for better JSON parsing: brew install jq"
  else
    print_success "jq installed"
  fi
}

# Check Azure login status
check_az_login() {
  print_section "Checking Azure Login"

  if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure CLI. Run: az login"
    exit 1
  fi

  SUBSCRIPTION=$(az account show --query name -o tsv)
  print_success "Logged in to subscription: $SUBSCRIPTION"
}

# Check Entra ID App Registrations
check_app_registrations() {
  print_section "Checking Entra ID App Registrations"

  echo "Looking for apps with 'Subnet Calculator React EasyAuth' in name..."
  az ad app list --display-name "Subnet Calculator React EasyAuth" \
    --query "[].{displayName:displayName, appId:appId, identifierUris:identifierUris}" \
    -o json

  echo ""
  print_warning "Verify you have TWO apps: one for frontend (user auth) and one for API (service auth)"
}

# Check Web App Managed Identity
check_webapp_identity() {
  print_section "Checking Web App Managed Identity"

  echo "Web App: $WEBAPP_NAME"
  echo ""

  IDENTITY=$(az webapp identity show \
    --name "$WEBAPP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "{type:type, userAssignedIdentities:userAssignedIdentities}" \
    -o json 2>&1)

  if echo "$IDENTITY" | grep -q "UserAssigned"; then
    print_success "User-Assigned Managed Identity found"
    echo "$IDENTITY"

    # Extract client ID
    CLIENT_ID=$(echo "$IDENTITY" | grep -o '"clientId": "[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$CLIENT_ID" ]; then
      print_success "Client ID: $CLIENT_ID"
      export WEBAPP_UAMI_CLIENT_ID="$CLIENT_ID"
    fi
  else
    print_error "No User-Assigned Managed Identity found"
    echo "$IDENTITY"
  fi
}

# Check Web App Configuration
check_webapp_config() {
  print_section "Checking Web App Configuration"

  echo "App Settings:"
  az webapp config appsettings list \
    --name "$WEBAPP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?name=='PROXY_FORWARD_EASYAUTH_HEADERS' || name=='PROXY_API_URL' || name=='API_PROXY_ENABLED' || name=='AZURE_CLIENT_ID' || name=='EASYAUTH_RESOURCE_ID'].{name:name, value:value}" \
    -o table

  echo ""
  print_warning "Verify:"
  echo "  - API_PROXY_ENABLED = true"
  echo "  - PROXY_FORWARD_EASYAUTH_HEADERS = false (for Managed Identity)"
  echo "  - AZURE_CLIENT_ID matches UAMI client ID"
  echo "  - EASYAUTH_RESOURCE_ID ends with /.default"
}

# Check Function App Easy Auth
check_function_auth() {
  print_section "Checking Function App Easy Auth"

  echo "Function App: $FUNCTION_APP_NAME"
  echo ""

  AUTH_CONFIG=$(az webapp auth show \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    -o json 2>&1 | head -80)

  if echo "$AUTH_CONFIG" | grep -q '"enabled": true'; then
    print_success "Easy Auth is enabled"
  else
    print_error "Easy Auth is NOT enabled"
  fi

  echo "$AUTH_CONFIG"

  echo ""
  print_warning "Verify:"
  echo "  - clientId matches API app registration"
  echo "  - allowedAudiences includes identifier URI and frontend app ID"
  echo "  - enabled = true"
}

# Check App Role Assignments
check_app_role_assignments() {
  print_section "Checking App Role Assignments"

  echo "Enter the API App ID (or press Enter to skip): "
  read -r API_APP_ID

  if [ -z "$API_APP_ID" ]; then
    print_warning "Skipped - no API App ID provided"
    return
  fi

  echo ""
  echo "Getting service principal for API app..."
  SP_DETAILS=$(az ad sp show --id "$API_APP_ID" \
    --query "{displayName:displayName, appId:appId, appRoles:appRoles[].{value:value, id:id}}" \
    -o json)

  echo "$SP_DETAILS"

  echo ""
  echo "Getting app role assignments..."
  SP_OBJECT_ID=$(az ad sp show --id "$API_APP_ID" --query "id" -o tsv)

  az rest --method GET \
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_OBJECT_ID/appRoleAssignedTo" \
    --query "value[].{principalDisplayName:principalDisplayName, principalId:principalId, appRoleId:appRoleId}" \
    -o json

  echo ""
  print_warning "Verify your Web App's UAMI appears in the list above"
}

# Check Logging Configuration
check_logging() {
  print_section "Checking Logging Configuration"

  echo "Web App logging config:"
  az webapp log show \
    --name "$WEBAPP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "{applicationLogs:applicationLogs, httpLogs:httpLogs}" \
    -o json

  echo ""
  print_warning "To enable logging, run:"
  echo "  az webapp log config --name $WEBAPP_NAME --resource-group $RESOURCE_GROUP \\"
  echo "    --application-logging filesystem --level information"
}

# Stream logs
stream_logs() {
  print_section "Streaming Logs (Ctrl+C to stop)"

  echo "Streaming logs from $WEBAPP_NAME..."
  echo "Make a request to the app in another terminal or browser"
  echo ""

  timeout 30 az webapp log tail \
    --name "$WEBAPP_NAME" \
    --resource-group "$RESOURCE_GROUP" 2>&1 | \
    grep -i --color=always "token\|error\|managed\|identity\|server" || true

  echo ""
  print_warning "Logs streamed for 30 seconds"
}

# Test API endpoint
test_api() {
  print_section "Testing API Endpoint"

  FUNC_URL="https://$FUNCTION_APP_NAME.azurewebsites.net/api/v1/health"

  echo "Testing: $FUNC_URL"
  echo ""

  RESPONSE=$(curl -I "$FUNC_URL" 2>&1 || true)
  echo "$RESPONSE"

  if echo "$RESPONSE" | grep -q "401"; then
    print_warning "Got 401 - Easy Auth is working (requires authentication)"
  elif echo "$RESPONSE" | grep -q "200"; then
    print_success "Got 200 - Endpoint is accessible"
  else
    print_error "Unexpected response"
  fi
}

# Restart Web App
restart_webapp() {
  print_section "Restarting Web App"

  read -p "Restart $WEBAPP_NAME? (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    az webapp restart \
      --name "$WEBAPP_NAME" \
      --resource-group "$RESOURCE_GROUP"
    print_success "Web App restarted"
    echo "Waiting 30 seconds for restart to complete..."
    sleep 30
  else
    print_warning "Restart skipped"
  fi
}

# Main menu
show_menu() {
  echo ""
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}Easy Auth Diagnostics Menu${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo "1) Check all (run all diagnostics)"
  echo "2) Check Entra ID app registrations"
  echo "3) Check Web App managed identity"
  echo "4) Check Web App configuration"
  echo "5) Check Function App Easy Auth"
  echo "6) Check app role assignments"
  echo "7) Check logging configuration"
  echo "8) Stream logs (30 seconds)"
  echo "9) Test API endpoint"
  echo "10) Restart Web App"
  echo "11) Exit"
  echo ""
}

# Run all checks
run_all_checks() {
  check_dependencies
  check_az_login
  check_app_registrations
  check_webapp_identity
  check_webapp_config
  check_function_auth
  check_logging
  test_api

  echo ""
  print_success "All checks completed!"
  echo ""
  print_warning "Next steps:"
  echo "  - Review any errors or warnings above"
  echo "  - Run option 6 to check app role assignments (requires API App ID)"
  echo "  - Run option 8 to stream logs while testing"
  echo "  - Run option 10 to restart if you made config changes"
}

# Main script
main() {
  clear
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}Azure Easy Auth Debug Tool${NC}"
  echo -e "${GREEN}========================================${NC}"
  echo ""
  echo "Web App: $WEBAPP_NAME"
  echo "Function App: $FUNCTION_APP_NAME"
  echo "Resource Group: $RESOURCE_GROUP"
  echo ""
  echo "Set environment variables to override:"
  echo "  WEBAPP_NAME, FUNCTION_APP_NAME, RESOURCE_GROUP"

  if [ "${1:-}" = "--all" ] || [ "${1:-}" = "-a" ]; then
    run_all_checks
    exit 0
  fi

  while true; do
    show_menu
    read -r -p "Select option: " choice

    case $choice in
      1) run_all_checks ;;
      2) check_app_registrations ;;
      3) check_webapp_identity ;;
      4) check_webapp_config ;;
      5) check_function_auth ;;
      6) check_app_role_assignments ;;
      7) check_logging ;;
      8) stream_logs ;;
      9) test_api ;;
      10) restart_webapp ;;
      11) echo "Goodbye!"; exit 0 ;;
      *) print_error "Invalid option" ;;
    esac

    echo ""
    read -r -p "Press Enter to continue..."
  done
}

# Run main script
main "$@"
