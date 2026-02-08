#!/usr/bin/env bash
set -euo pipefail

# Cleanup Orphaned Azure Runner VMs
# Deletes VMs tagged as ephemeral runners that are older than specified age

RESOURCE_GROUP="iiab-lokole-tests-rg"
MAX_AGE_HOURS=2
DRY_RUN=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --max-age-hours)
            MAX_AGE_HOURS="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}🧹 Cleanup Orphaned Runner Resources${NC}"
echo "========================================================"
echo "Resource Group: ${RESOURCE_GROUP}"
echo "Max Age: ${MAX_AGE_HOURS} hours"
echo "Dry Run: ${DRY_RUN}"
echo "========================================================"
echo ""

# Calculate cutoff timestamp
CUTOFF_TIMESTAMP=$(date -u -d "${MAX_AGE_HOURS} hours ago" +%Y-%m-%dT%H:%M:%SZ)

echo "Cutoff time: ${CUTOFF_TIMESTAMP}"
echo ""

# Find orphaned resources (VMs tagged as ephemeral and old)
ORPHANED_VMS=$(az vm list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?tags.ephemeral=='true' && tags.createdAt<'${CUTOFF_TIMESTAMP}'].{name:name, created:tags.createdAt, pr:tags.prNumber, runId:tags.runId}" \
    -o json)

VM_COUNT=$(echo "$ORPHANED_VMS" | jq 'length')

if [ "$VM_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✓${NC} No orphaned VMs found"
    exit 0
fi

echo -e "${YELLOW}Found ${VM_COUNT} orphaned VM(s):${NC}"
echo "$ORPHANED_VMS" | jq -r '.[] | "  • \(.name) (PR #\(.pr // "N/A"), runId: \(.runId // "N/A"), created: \(.created))"'
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}Dry run - no resources will be deleted${NC}"
    exit 0
fi

# Delete all resources for each orphaned VM's runId
echo -e "${BLUE}Deleting resources for orphaned VMs...${NC}"
echo "$ORPHANED_VMS" | jq -r '.[] | "\(.runId)|\(.name)"' | while IFS='|' read -r run_id vm_name; do
    echo ""
    echo "Processing VM: ${vm_name} (runId: ${run_id})"
    
    if [ -z "$run_id" ] || [ "$run_id" = "null" ]; then
        echo -e "${YELLOW}  ⚠️  No runId tag, deleting VM only${NC}"
        az vm delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$vm_name" \
            --yes \
            --no-wait \
            --force-deletion \
            > /dev/null 2>&1 || echo -e "${RED}  ❌ Failed to delete VM${NC}"
    else
        # Get all resources with this runId
        RESOURCE_IDS=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --tag runId="$run_id" \
            --query "[].id" \
            -o tsv)
        
        RESOURCE_COUNT=$(echo "$RESOURCE_IDS" | wc -l)
        echo "  Found ${RESOURCE_COUNT} resource(s) to delete"
        
        # Delete all resources
        echo "$RESOURCE_IDS" | while read -r resource_id; do
            RESOURCE_NAME=$(basename "$resource_id")
            echo "    Deleting: ${RESOURCE_NAME}"
            az resource delete --ids "$resource_id" --no-wait > /dev/null 2>&1 || echo -e "${RED}      Failed${NC}"
        done
    fi
done

echo ""
echo -e "${GREEN}✓${NC} Cleanup initiated for ${VM_COUNT} VM(s)"
echo ""
