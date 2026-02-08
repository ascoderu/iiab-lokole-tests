#!/usr/bin/env bash
set -euo pipefail

# Azure VM Lifecycle Orchestration for GitHub Actions Runners
# Provisions ephemeral Spot VMs, waits for runner registration, and ensures cleanup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_GROUP="iiab-lokole-tests-rg"
LOCATION="eastus"
BICEP_TEMPLATE="${ROOT_DIR}/infrastructure/azure/main.bicep"
VM_NAME=""
VM_SIZE="Standard_D2s_v3"
UBUNTU_VERSION="22.04-LTS"
IMAGE_OFFER="0001-com-ubuntu-server-jammy"
IMAGE_SKU="22_04-lts-gen2"
USE_SPOT=true
PR_NUMBER=""
RUN_ID="${GITHUB_RUN_ID:-$(date +%s)}"
CLEANUP_ON_EXIT=true
MAX_WAIT_SECONDS=300  # 5 minutes to wait for runner registration

# Usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Provision ephemeral Azure VM for GitHub Actions self-hosted runner

OPTIONS:
    --vm-size SIZE           Azure VM size (default: Standard_B2s)
    --ubuntu-version VER     Ubuntu version: 22.04-LTS or 24.04-LTS (default: 22.04-LTS)
    --image-offer OFFER      Azure Marketplace image offer
    --image-sku SKU          Azure Marketplace image SKU
    --regular-vm             Use regular VM instead of Spot (higher cost, no eviction)
    --pr-number NUMBER       PR number for tagging
    --no-cleanup             Don't delete VM on script exit (for debugging)
    --resource-group NAME    Resource group name (default: ${RESOURCE_GROUP})
    --help                   Show this help message

EXAMPLES:
    # Provision Spot VM for PR #610
    $0 --pr-number 610

    # Use larger VM with regular pricing
    $0 --vm-size Standard_B2ms --regular-vm

    # Keep VM running for debugging
    $0 --no-cleanup

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --vm-size)
            VM_SIZE="$2"
            shift 2
            ;;
        --ubuntu-version)
            UBUNTU_VERSION="$2"
            shift 2
            ;;
        --image-offer)
            IMAGE_OFFER="$2"
            shift 2
            ;;
        --image-sku)
            IMAGE_SKU="$2"
            shift 2
            ;;
        --regular-vm)
            USE_SPOT=false
            shift
            ;;
        --pr-number)
            PR_NUMBER="$2"
            shift 2
            ;;
        --no-cleanup)
            CLEANUP_ON_EXIT=false
            shift
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Generate unique VM name
VM_NAME="gh-runner-${RUN_ID}"

echo -e "${BLUE}🚀 Azure Runner Provisioning${NC}"
echo "========================================================"
echo "VM Name: ${VM_NAME}"
echo "VM Size: ${VM_SIZE}"
echo "Ubuntu: ${UBUNTU_VERSION}"
echo "Image: ${IMAGE_OFFER} / ${IMAGE_SKU}"
echo "Spot VM: ${USE_SPOT}"
echo "PR Number: ${PR_NUMBER:-N/A}"
echo "Resource Group: ${RESOURCE_GROUP}"
echo "Cleanup on exit: ${CLEANUP_ON_EXIT}"
echo "========================================================"
echo ""

# Check prerequisites
check_prerequisites() {
    echo -e "${BLUE}🔍 Checking prerequisites...${NC}"
    
    local missing=()
    
    if ! command -v az &> /dev/null; then
        missing+=("azure-cli")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}❌ Missing dependencies: ${missing[*]}${NC}"
        exit 1
    fi
    
    # Check Azure login
    if ! az account show &> /dev/null; then
        echo -e "${RED}❌ Not logged in to Azure${NC}"
        echo "Run: ./scripts/azure/login.sh"
        exit 1
    fi
    
    # Check GitHub token
    if [ -z "${GITHUB_TOKEN:-}" ]; then
        echo -e "${YELLOW}⚠️  GITHUB_TOKEN not set${NC}"
        echo "Set with: export GITHUB_TOKEN=\$INTEGRATION_TEST_PAT"
        
        # Try to load from .env
        if [ -f "${ROOT_DIR}/.env" ]; then
            echo "Loading from .env..."
            # shellcheck disable=SC1091
            set -a
            source "${ROOT_DIR}/.env"
            set +a
            export GITHUB_TOKEN="${INTEGRATION_TEST_PAT:-}"
        fi
        
        if [ -z "${GITHUB_TOKEN:-}" ]; then
            echo -e "${RED}❌ GITHUB_TOKEN required${NC}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}✓${NC} Prerequisites OK"
    echo ""
}

# Generate SSH key pair for VM access
generate_ssh_key() {
    local key_file="${ROOT_DIR}/.ssh/azure-runner-key"
    
    if [ ! -f "$key_file" ]; then
        echo -e "${BLUE}🔑 Generating SSH key pair...${NC}"
        mkdir -p "$(dirname "$key_file")"
        ssh-keygen -t rsa -b 4096 -f "$key_file" -N "" -C "azure-runner" > /dev/null
        echo -e "${GREEN}✓${NC} SSH key generated: $key_file"
    else
        echo -e "${GREEN}✓${NC} Using existing SSH key: $key_file"
    fi
    
    SSH_PUBLIC_KEY=$(cat "${key_file}.pub")
    SSH_PRIVATE_KEY="$key_file"
    echo ""
}

# Deploy VM using Bicep
deploy_vm() {
    echo -e "${BLUE}☁️  Deploying Azure VM...${NC}"
    
    # Strip -LTS suffix from Ubuntu version for runner labels (22.04-LTS -> 22.04)
    local ubuntu_label="${UBUNTU_VERSION//-LTS/}"
    local runner_labels="self-hosted,azure-spot,ubuntu-${ubuntu_label}"
    
    echo "Runner labels: ${runner_labels}"
    
    local deployment_output
    # Add timestamp to deployment name to avoid conflicts from retries
    local deployment_timestamp=$(date +%s)
    deployment_output=$(az deployment group create \
        --name "deploy-$VM_NAME-$deployment_timestamp" \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$BICEP_TEMPLATE" \
        --parameters \
            vmName="$VM_NAME" \
            vmSize="$VM_SIZE" \
            useSpotInstance="$USE_SPOT" \
            imageOffer="$IMAGE_OFFER" \
            imageSku="$IMAGE_SKU" \
            adminUsername="azureuser" \
            sshPublicKey="$SSH_PUBLIC_KEY" \
            githubRepository="ascoderu/iiab-lokole-tests" \
            githubToken="$GITHUB_TOKEN" \
            runnerLabels="$runner_labels" \
            prNumber="$PR_NUMBER" \
            runId="$RUN_ID" \
        --query 'properties.outputs' \
        -o json 2>&1) || {
        echo -e "${RED}❌ VM deployment failed${NC}"
        echo "$deployment_output"
        exit 1
    }
    
    VM_PUBLIC_IP=$(echo "$deployment_output" | jq -r '.publicIP.value')
    VM_FQDN=$(echo "$deployment_output" | jq -r '.fqdn.value')
    
    echo -e "${GREEN}✓${NC} VM deployed successfully"
    echo "  Public IP: ${VM_PUBLIC_IP}"
    echo "  FQDN: ${VM_FQDN}"
    echo ""
}

# Wait for runner to register with GitHub
wait_for_runner() {
    echo -e "${BLUE}⏳ Waiting for runner to register...${NC}"
    
    local start_time=$(date +%s)
    local timeout=$MAX_WAIT_SECONDS
    
    while true; do
        local elapsed=$(($(date +%s) - start_time))
        
        if [ $elapsed -gt $timeout ]; then
            echo -e "${RED}❌ Timeout waiting for runner registration${NC}"
            return 1
        fi
        
        # Check if runner is registered
        local runner_status=$(curl -s \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/ascoderu/iiab-lokole-tests/actions/runners" \
            | jq -r ".runners[] | select(.name == \"$VM_NAME\") | .status")
        
        if [ "$runner_status" = "online" ]; then
            echo -e "${GREEN}✓${NC} Runner registered and online"
            echo "  Elapsed: ${elapsed}s"
            echo ""
            return 0
        elif [ -n "$runner_status" ]; then
            echo "  Runner status: ${runner_status} (waiting...)"
        else
            echo "  Runner not found yet (${elapsed}s elapsed)"
        fi
        
        sleep 10
    done
}

# Cleanup VM on exit
cleanup_vm() {
    local exit_code=$?  # Capture original exit code before any commands
    
    if [ "$CLEANUP_ON_EXIT" = false ]; then
        echo -e "${YELLOW}⚠️  Skipping cleanup (--no-cleanup specified)${NC}"
        echo "  VM: ${VM_NAME}"
        echo "  Manual cleanup: az vm delete --resource-group ${RESOURCE_GROUP} --name ${VM_NAME} --yes"
        return $exit_code
    fi
    
    echo ""
    echo -e "${BLUE}🧹 Cleaning up VM...${NC}"
    
    if [ -z "$VM_NAME" ]; then
        echo "No VM to clean up"
        return $exit_code
    fi
    
    # Delete VM (all associated resources have deleteOption: Delete)
    az vm delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_NAME" \
        --yes \
        --no-wait \
        > /dev/null 2>&1 || {
        echo -e "${YELLOW}⚠️  VM deletion initiated (may take a few minutes)${NC}"
    }
    
    echo -e "${GREEN}✓${NC} Cleanup initiated for VM: ${VM_NAME}"
    return $exit_code  # Preserve original exit code
}

# Trap to ensure cleanup on exit
trap 'cleanup_vm' EXIT INT TERM

# Main execution
main() {
    check_prerequisites
    generate_ssh_key
    deploy_vm
    wait_for_runner
    
    echo -e "${GREEN}✅ Runner provisioned successfully!${NC}"
    echo ""
    echo "Runner details:"
    echo "  Name: ${VM_NAME}"
    echo "  IP: ${VM_PUBLIC_IP}"
    echo "  SSH: ssh -i ${SSH_PRIVATE_KEY} azureuser@${VM_PUBLIC_IP}"
    echo ""
    echo "Monitor runner:"
    echo "  https://github.com/ascoderu/iiab-lokole-tests/actions/runners"
    echo ""
    echo -e "${YELLOW}Note: VM will auto-cleanup after runner job completes${NC}"
    echo ""
}

# Run
main
