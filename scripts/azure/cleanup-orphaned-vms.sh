#!/usr/bin/env bash
set -euo pipefail

# Cleanup Orphaned Azure Runner Resources
# Deletes all resources (VMs, NSGs, NICs, PIPs, disks, etc.) tagged with runId
# that are older than the specified age

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

# Find all resources with runId tags (grouped by runId)
ALL_RUN_IDS=$(az resource list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?tags.runId!=null].{runId:tags.runId, created:tags.createdAt}" \
    -o json | jq -r 'group_by(.runId) | .[] | {runId: .[0].runId, created: .[0].created, count: length}')

# Filter to only orphaned runs (old enough)
ORPHANED_RUNS=$(echo "$ALL_RUN_IDS" | jq -c "select(.created < \"${CUTOFF_TIMESTAMP}\")")

if [ -z "$ORPHANED_RUNS" ]; then
    echo -e "${GREEN}✓${NC} No orphaned resources found"
    exit 0
fi

RUN_COUNT=$(echo "$ORPHANED_RUNS" | wc -l)
echo -e "${YELLOW}Found ${RUN_COUNT} orphaned run(s):${NC}"
echo "$ORPHANED_RUNS" | jq -r '"  • runId: \(.runId) (\(.count) resource(s), created: \(.created))"'
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}Dry run - no resources will be deleted${NC}"
    exit 0
fi

# Delete all resources for each orphaned runId
echo -e "${BLUE}Deleting resources for orphaned runs...${NC}"
DELETED_COUNT=0

echo "$ORPHANED_RUNS" | jq -r '.runId' | while read -r run_id; do
    echo ""
    echo "Processing runId: ${run_id}"
    
    # Get all resources with this runId using query filter
    RESOURCE_IDS=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?tags.runId=='$run_id'].id" \
        -o tsv)
    
    RESOURCE_COUNT=$(echo "$RESOURCE_IDS" | grep -c . || echo 0)
    
    if [ "$RESOURCE_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}  ⚠️  No resources found${NC}"
        continue
    fi
    
    echo "  Found ${RESOURCE_COUNT} resource(s) to delete"
    
    # Delete all resources
    if [ -n "$RESOURCE_IDS" ]; then
        echo "$RESOURCE_IDS" | while read -r resource_id; do
            RESOURCE_NAME=$(basename "$resource_id")
            RESOURCE_TYPE=$(echo "$resource_id" | grep -oP '/providers/[^/]+/[^/]+' | tail -1)
            echo "    Deleting: ${RESOURCE_NAME} (${RESOURCE_TYPE})"
            az resource delete --ids "$resource_id" --no-wait > /dev/null 2>&1 || echo -e "${RED}      Failed${NC}"
        done
        DELETED_COUNT=$((DELETED_COUNT + RESOURCE_COUNT))
    fi
done

echo ""
echo -e "${GREEN}✓${NC} Cleanup initiated for ${RUN_COUNT} run(s) (${DELETED_COUNT} resource(s))"
echo ""
