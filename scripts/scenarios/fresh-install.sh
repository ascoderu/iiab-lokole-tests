#!/bin/bash
# Fresh Install Test Scenario
# Tests complete IIAB installation with Lokole from scratch
# Usage: ./fresh-install.sh [OPTIONS]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Defaults
UBUNTU_VERSION="24.04"
USE_DAILY=false
VM_NAME="iiab-lokole-test-$(date +%Y%m%d-%H%M%S)"
IIAB_PR=""
LOKOLE_COMMIT=""
LOKOLE_VERSION=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ubuntu-version)
            UBUNTU_VERSION="$2"
            shift 2
            ;;
        --use-daily)
            USE_DAILY=true
            shift
            ;;
        --vm-name)
            VM_NAME="$2"
            shift 2
            ;;
        --iiab-pr)
            IIAB_PR="$2"
            shift 2
            ;;
        --lokole-commit)
            LOKOLE_COMMIT="$2"
            shift 2
            ;;
        --lokole-version)
            LOKOLE_VERSION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "🎯 Fresh Install Test Scenario"
echo "==============================================================================="
echo "Ubuntu Version: ${UBUNTU_VERSION}"
echo "Use Daily: ${USE_DAILY}"
echo "VM Name: ${VM_NAME}"
[ -n "$IIAB_PR" ] && echo "IIAB PR: #${IIAB_PR}"
[ -n "$LOKOLE_COMMIT" ] && echo "Lokole Commit: ${LOKOLE_COMMIT}"
[ -n "$LOKOLE_VERSION" ] && echo "Lokole Version: ${LOKOLE_VERSION}"
echo "==============================================================================="
echo ""

# Phase 1: VM Setup
echo "🚀 PHASE 1: Setting up VM..."
echo "==============================================================================="

SETUP_CMD="${ROOT_DIR}/scripts/vm/multipass/setup-vm.sh --vm-name ${VM_NAME} --ubuntu-version ${UBUNTU_VERSION}"
[ "$USE_DAILY" = true ] && SETUP_CMD="${SETUP_CMD} --use-daily"

$SETUP_CMD

echo "⏳ Waiting 30 seconds for VM to stabilize..."
sleep 30

# Phase 2: IIAB Installation
echo ""
echo "🏗️  PHASE 2: Installing IIAB..."
echo "==============================================================================="

INSTALL_CMD="${ROOT_DIR}/scripts/vm/multipass/install-iiab.sh --vm-name ${VM_NAME}"
[ -n "$IIAB_PR" ] && INSTALL_CMD="${INSTALL_CMD} --iiab-pr ${IIAB_PR}"
[ -n "$LOKOLE_COMMIT" ] && INSTALL_CMD="${INSTALL_CMD} --lokole-commit ${LOKOLE_COMMIT}"
[ -n "$LOKOLE_VERSION" ] && INSTALL_CMD="${INSTALL_CMD} --lokole-version ${LOKOLE_VERSION}"

$INSTALL_CMD

echo "⏳ Waiting 60 seconds for services to start..."
sleep 60

# Phase 3: Verification
echo ""
echo "🔍 PHASE 3: Verifying installation..."
echo "==============================================================================="

JSON_REPORT="/tmp/lokole-verification-${VM_NAME}.json"
TEXT_REPORT="fresh-install-${UBUNTU_VERSION}-$(date +%Y%m%d-%H%M%S).txt"
MD_REPORT="/tmp/pr-comment-${VM_NAME}.md"

# Run comprehensive verification
${ROOT_DIR}/scripts/verify/comprehensive-check.sh ${VM_NAME} ${JSON_REPORT}
VERIFY_EXIT=$?

# Generate markdown PR comment
${ROOT_DIR}/scripts/verify/generate-pr-comment.sh ${JSON_REPORT} ${MD_REPORT}

# Create text report for artifacts
{
    echo "IIAB-Lokole Integration Test Report"
    echo "===================================="
    echo ""
    echo "VM Name: ${VM_NAME}"
    echo "Ubuntu Version: ${UBUNTU_VERSION}"
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    cat ${MD_REPORT}
} > "${TEXT_REPORT}"

# Final Summary
echo ""
if [ $VERIFY_EXIT -eq 0 ]; then
    echo "🎊 TEST COMPLETE! ✅"
else
    echo "⚠️  TEST COMPLETED WITH ISSUES"
fi
echo "==============================================================================="
echo "VM Name: ${VM_NAME}"
echo "Reports:"
echo "  - JSON: ${JSON_REPORT}"
echo "  - Markdown: ${MD_REPORT}"
echo "  - Text: ${TEXT_REPORT}"
echo ""
echo "Summary:"
jq -r '.summary' ${JSON_REPORT}
echo ""
echo "Checks:"
jq -r '"  Passed:   \(.checks.passed)/\(.checks.total)"' ${JSON_REPORT}
jq -r '"  Failed:   \(.checks.failed)/\(.checks.total)"' ${JSON_REPORT}
jq -r '"  Warnings: \(.checks.warnings)/\(.checks.total)"' ${JSON_REPORT}
echo ""
echo "💡 Next Steps:"
echo "1. Review full report: cat ${TEXT_REPORT}"
echo "2. Review JSON report: cat ${JSON_REPORT}"
echo "3. Access VM: multipass shell ${VM_NAME}"
echo "4. Clean up: multipass delete ${VM_NAME} --purge"

exit $VERIFY_EXIT
