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

echo -e "${BLUE}🧹 Cleanup Orphaned Runner VMs${NC}"
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

# Find orphaned VMs
ORPHANED_VMS=$(az vm list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?tags.ephemeral=='true' && tags.createdAt<'${CUTOFF_TIMESTAMP}'].{name:name, created:tags.createdAt, pr:tags.prNumber}" \
    -o json)

VM_COUNT=$(echo "$ORPHANED_VMS" | jq 'length')

if [ "$VM_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✓${NC} No orphaned VMs found"
    exit 0
fi

echo -e "${YELLOW}Found ${VM_COUNT} orphaned VM(s):${NC}"
echo "$ORPHANED_VMS" | jq -r '.[] | "  • \(.name) (PR #\(.pr // "N/A"), created: \(.created))"'
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}Dry run - no VMs will be deleted${NC}"
    exit 0
fi

# Delete VMs
echo -e "${BLUE}Deleting VMs...${NC}"
echo "$ORPHANED_VMS" | jq -r '.[].name' | while read -r vm_name; do
    echo "  Deleting: ${vm_name}"
    az vm delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$vm_name" \
        --yes \
        --no-wait \
        > /dev/null 2>&1 || {
        echo -e "${RED}  ❌ Failed to delete: ${vm_name}${NC}"
    }
done

echo ""
echo -e "${GREEN}✓${NC} Cleanup initiated for ${VM_COUNT} VM(s)"
echo ""
