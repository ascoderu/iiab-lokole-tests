#!/usr/bin/env bash
set -euo pipefail

# Azure Cost Monitoring Script
# Reports costs for IIAB integration test infrastructure

RESOURCE_GROUP="iiab-lokole-tests-rg"
DAYS_BACK=30

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}💰 Azure Cost Report${NC}"
echo "========================================================"
echo "Resource Group: ${RESOURCE_GROUP}"
echo "Period: Last ${DAYS_BACK} days"
echo "========================================================"
echo ""

# Check Azure CLI
if ! command -v az &> /dev/null; then
    echo -e "${RED}❌ Azure CLI not found${NC}"
    exit 1
fi

# Check login
if ! az account show &> /dev/null; then
    echo -e "${RED}❌ Not logged in to Azure${NC}"
    echo "Run: az login"
    exit 1
fi

START_DATE=$(date -d "${DAYS_BACK} days ago" +%Y-%m-%d)
END_DATE=$(date +%Y-%m-%d)

echo "Fetching cost data from ${START_DATE} to ${END_DATE}..."
echo ""

# Get cost-to-date
COSTS=$(az consumption usage list \
    --start-date "$START_DATE" \
    --end-date "$END_DATE" \
    2>/dev/null | jq -r '
        map(select(.instanceName | contains("iiab-lokole") or contains("gh-runner"))) |
        group_by(.meterCategory) |
        map({
            category: .[0].meterCategory,
            cost: (map(.pretaxCost | tonumber) | add),
            usage: (map(.quantity | tonumber) | add)
        }) |
        sort_by(.cost) | reverse
    ')

TOTAL_COST=$(echo "$COSTS" | jq -r 'map(.cost) | add // 0')

if [ "$(echo "$TOTAL_COST == 0" | bc)" -eq 1 ]; then
    echo -e "${GREEN}✓ No costs incurred in the last ${DAYS_BACK} days${NC}"
    echo ""
    echo "This is expected if:"
    echo "  • Infrastructure not yet deployed"
    echo "  • No tests run recently"
    echo "  • Billing data not yet available (can take 24-48h)"
    exit 0
fi

echo -e "${BLUE}Cost Breakdown:${NC}"
echo "$COSTS" | jq -r '.[] | "  • \(.category): $\(.cost | tonumber | . * 100 | round / 100)"'
echo ""
echo -e "${YELLOW}Total Cost: $$(printf "%.2f" $TOTAL_COST)${NC}"
echo ""

# Calculate projected monthly cost
DAYS_ELAPSED=$(( ($(date +%s) - $(date -d "$START_DATE" +%s)) / 86400 ))
if [ "$DAYS_ELAPSED" -gt 0 ]; then
    DAILY_AVERAGE=$(echo "scale=4; $TOTAL_COST / $DAYS_ELAPSED" | bc)
    PROJECTED_MONTHLY=$(echo "scale=2; $DAILY_AVERAGE * 30" | bc)
    
    echo -e "${BLUE}Projections:${NC}"
    echo "  Daily Average: \$$(printf "%.4f" $DAILY_AVERAGE)"
    echo "  Projected Monthly: \$$(printf "%.2f" $PROJECTED_MONTHLY)"
    echo ""
fi

# Cost alerts
MONTHLY_THRESHOLD=20.00
if [ "$(echo "$PROJECTED_MONTHLY > $MONTHLY_THRESHOLD" | bc)" -eq 1 ]; then
    echo -e "${RED}⚠️  WARNING: Projected monthly cost exceeds \$${MONTHLY_THRESHOLD}${NC}"
    echo ""
    echo "Recommendations:"
    echo "  1. Check for orphaned VMs: ./scripts/azure/cleanup-orphaned-vms.sh --dry-run"
    echo "  2. Review VM sizes: Consider using smaller VMs"
    echo "  3. Use sequential testing: One VM for all Ubuntu versions"
    echo ""
else
    echo -e "${GREEN}✓ Costs within expected range${NC}"
    echo ""
fi

# List current resources
echo -e "${BLUE}Current Resources:${NC}"
CURRENT_VMS=$(az vm list --resource-group "$RESOURCE_GROUP" --query 'length(@)' -o tsv 2>/dev/null || echo "0")
if [ "$CURRENT_VMS" -eq 0 ]; then
    echo "  ✓ No VMs currently running"
else
    echo -e "  ${YELLOW}⚠️  $CURRENT_VMS VM(s) running${NC}"
    az vm list --resource-group "$RESOURCE_GROUP" --output table
    echo ""
    echo "  These VMs are incurring costs. Cleanup:"
    echo "    ./scripts/azure/cleanup-orphaned-vms.sh"
fi

echo ""
echo -e "${BLUE}Detailed cost analysis:${NC}"
echo "  Azure Portal: https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/costanalysis"
echo "  Resource Group: ${RESOURCE_GROUP}"
echo ""
