#!/usr/bin/env bash
set -euo pipefail

# Azure Login and Service Principal Setup Script
# Sets up Azure authentication for GitHub Actions self-hosted runners

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_GROUP_NAME="iiab-lokole-tests-rg"
LOCATION="eastus"
SP_NAME="iiab-lokole-github-actions"
OUTPUT_FILE="${ROOT_DIR}/.azure-credentials.json"

echo -e "${BLUE}🔐 Azure Setup for GitHub Actions Runners${NC}"
echo "========================================================"
echo ""

# Check Azure CLI
if ! command -v az &> /dev/null; then
    echo -e "${RED}❌ Azure CLI not found${NC}"
    echo ""
    echo "Install with:"
    echo "  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
    echo ""
    echo "Or visit: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

echo -e "${GREEN}✓${NC} Azure CLI found: $(az version --query '\"azure-cli\"' -o tsv)"
echo ""

# Login to Azure
echo -e "${BLUE}📝 Step 1: Azure Login${NC}"
echo "----------------------------------------"

if az account show &> /dev/null; then
    echo -e "${GREEN}✓${NC} Already logged in as: $(az account show --query 'user.name' -o tsv)"
    echo ""
    read -p "Use this account? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Logging out..."
        az logout
        echo ""
        echo "Please log in:"
        az login
    fi
else
    echo "Please log in to Azure:"
    echo ""
    az login
fi

echo ""

# Select subscription
echo -e "${BLUE}📋 Step 2: Select Subscription${NC}"
echo "----------------------------------------"

SUBSCRIPTION_COUNT=$(az account list --query 'length(@)' -o tsv)

if [ "$SUBSCRIPTION_COUNT" -eq 0 ]; then
    echo -e "${RED}❌ No Azure subscriptions found${NC}"
    exit 1
elif [ "$SUBSCRIPTION_COUNT" -eq 1 ]; then
    SUBSCRIPTION_ID=$(az account show --query 'id' -o tsv)
    SUBSCRIPTION_NAME=$(az account show --query 'name' -o tsv)
    echo -e "${GREEN}✓${NC} Using subscription: ${SUBSCRIPTION_NAME}"
else
    echo "Available subscriptions:"
    az account list --output table
    echo ""
    read -p "Enter subscription ID or name: " SUB_INPUT
    az account set --subscription "$SUB_INPUT"
    SUBSCRIPTION_ID=$(az account show --query 'id' -o tsv)
    SUBSCRIPTION_NAME=$(az account show --query 'name' -o tsv)
    echo -e "${GREEN}✓${NC} Selected: ${SUBSCRIPTION_NAME}"
fi

echo "  Subscription ID: ${SUBSCRIPTION_ID}"
echo ""

# Create or verify resource group
echo -e "${BLUE}🏗️  Step 3: Resource Group${NC}"
echo "----------------------------------------"

if az group show --name "$RESOURCE_GROUP_NAME" &> /dev/null; then
    echo -e "${GREEN}✓${NC} Resource group '${RESOURCE_GROUP_NAME}' already exists"
    RG_LOCATION=$(az group show --name "$RESOURCE_GROUP_NAME" --query 'location' -o tsv)
    echo "  Location: ${RG_LOCATION}"
else
    echo "Creating resource group '${RESOURCE_GROUP_NAME}' in ${LOCATION}..."
    az group create \
        --name "$RESOURCE_GROUP_NAME" \
        --location "$LOCATION" \
        --tags purpose=github-actions project=iiab-lokole-tests
    echo -e "${GREEN}✓${NC} Resource group created"
fi

echo ""

# Create Service Principal
echo -e "${BLUE}🔑 Step 4: Service Principal${NC}"
echo "----------------------------------------"
echo "Creating service principal with minimal permissions..."
echo ""

# Check if SP already exists
SP_APP_ID=$(az ad sp list --display-name "$SP_NAME" --query '[0].appId' -o tsv 2>/dev/null || echo "")

if [ -n "$SP_APP_ID" ] && [ "$SP_APP_ID" != "null" ]; then
    echo -e "${YELLOW}⚠️  Service Principal '${SP_NAME}' already exists${NC}"
    echo "  App ID: ${SP_APP_ID}"
    echo ""
    read -p "Delete and recreate? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing service principal..."
        az ad sp delete --id "$SP_APP_ID"
        SP_APP_ID=""
    fi
fi

if [ -z "$SP_APP_ID" ]; then
    echo "Creating new service principal..."
    
    # Create SP with contributor role scoped to resource group
    SP_OUTPUT=$(az ad sp create-for-rbac \
        --name "$SP_NAME" \
        --role "Contributor" \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP_NAME}" \
        --sdk-auth)
    
    SP_APP_ID=$(echo "$SP_OUTPUT" | jq -r '.clientId')
    SP_CLIENT_SECRET=$(echo "$SP_OUTPUT" | jq -r '.clientSecret')
    SP_TENANT_ID=$(echo "$SP_OUTPUT" | jq -r '.tenantId')
    
    echo -e "${GREEN}✓${NC} Service Principal created"
    echo "  App ID: ${SP_APP_ID}"
    echo "  Scope: Resource Group '${RESOURCE_GROUP_NAME}' only"
    echo ""
    
    # Save credentials to file
    echo "$SP_OUTPUT" > "$OUTPUT_FILE"
    chmod 600 "$OUTPUT_FILE"
    echo -e "${GREEN}✓${NC} Credentials saved to: ${OUTPUT_FILE}"
    echo -e "${YELLOW}⚠️  Keep this file secure - it contains secrets!${NC}"
    echo ""
else
    echo "Using existing service principal"
    echo ""
    echo -e "${YELLOW}⚠️  Cannot retrieve existing secret${NC}"
    echo "If you need the secret, delete and recreate the service principal"
    echo ""
    
    # Try to get tenant ID
    SP_TENANT_ID=$(az account show --query 'tenantId' -o tsv)
    SP_CLIENT_SECRET="<existing-secret-not-retrievable>"
fi

# Display GitHub Secrets configuration
echo -e "${BLUE}📤 Step 5: GitHub Secrets Configuration${NC}"
echo "----------------------------------------"
echo "Add these secrets to your GitHub repository:"
echo ""
echo "  Repository: https://github.com/ascoderu/iiab-lokole-tests/settings/secrets/actions"
echo ""
echo -e "${YELLOW}AZURE_SUBSCRIPTION_ID:${NC}"
echo "  ${SUBSCRIPTION_ID}"
echo ""
echo -e "${YELLOW}AZURE_CLIENT_ID:${NC}"
echo "  ${SP_APP_ID}"
echo ""
echo -e "${YELLOW}AZURE_CLIENT_SECRET:${NC}"
if [ "$SP_CLIENT_SECRET" != "<existing-secret-not-retrievable>" ]; then
    echo "  ${SP_CLIENT_SECRET}"
else
    echo "  <retrieve from ${OUTPUT_FILE} if recreated>"
fi
echo ""
echo -e "${YELLOW}AZURE_TENANT_ID:${NC}"
echo "  ${SP_TENANT_ID}"
echo ""

# Create a convenient script to set secrets
SECRET_SCRIPT="${ROOT_DIR}/scripts/azure/set-github-secrets.sh"
cat > "$SECRET_SCRIPT" << EOF
#!/usr/bin/env bash
# Auto-generated script to set GitHub secrets
# Usage: ./set-github-secrets.sh

gh secret set AZURE_SUBSCRIPTION_ID --body "${SUBSCRIPTION_ID}"
gh secret set AZURE_CLIENT_ID --body "${SP_APP_ID}"
gh secret set AZURE_TENANT_ID --body "${SP_TENANT_ID}"

EOF

if [ "$SP_CLIENT_SECRET" != "<existing-secret-not-retrievable>" ]; then
    echo "gh secret set AZURE_CLIENT_SECRET --body \"${SP_CLIENT_SECRET}\"" >> "$SECRET_SCRIPT"
fi

chmod +x "$SECRET_SCRIPT"

echo -e "${GREEN}✓${NC} Helper script created: ${SECRET_SCRIPT}"
echo ""
echo "Run this to automatically set secrets (requires GitHub CLI):"
echo "  cd /home/hagag/workspace/lokole-org/iiab-lokole-tests"
echo "  ./scripts/azure/set-github-secrets.sh"
echo ""

# Verification
echo -e "${BLUE}✅ Step 6: Verification${NC}"
echo "----------------------------------------"
echo "Testing service principal permissions..."
echo ""

# Test listing VMs (should work even if empty)
if az vm list --resource-group "$RESOURCE_GROUP_NAME" &> /dev/null; then
    echo -e "${GREEN}✓${NC} Service Principal can access resource group"
else
    echo -e "${RED}❌ Service Principal permission test failed${NC}"
    echo "Wait a few seconds for permissions to propagate, then try:"
    echo "  az vm list --resource-group ${RESOURCE_GROUP_NAME}"
fi

echo ""
echo -e "${GREEN}✅ Azure setup complete!${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Set GitHub secrets (run ${SECRET_SCRIPT})"
echo "  2. Review sizing recommendations: docs/AZURE-RUNNER-SIZING.md"
echo "  3. Deploy infrastructure: ./scripts/azure/setup-infrastructure.sh"
echo ""
echo -e "${YELLOW}Security Reminders:${NC}"
echo "  • Service Principal scope: Limited to '${RESOURCE_GROUP_NAME}' only"
echo "  • Rotate secrets every 90 days"
echo "  • Never commit ${OUTPUT_FILE} to git (already in .gitignore)"
echo "  • Review permissions: az role assignment list --assignee ${SP_APP_ID}"
echo ""
