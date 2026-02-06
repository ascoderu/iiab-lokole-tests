#!/bin/bash
# Test specific PR branch
# Usage: ./test-pr-branch.sh [OPTIONS]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Defaults
UBUNTU_VERSION="24.04"
VM_NAME="iiab-lokole-pr-test-$(date +%Y%m%d-%H%M%S)"
PR_REPO=""
PR_REF=""
PR_SHA=""
PR_NUMBER=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ubuntu-version)
            UBUNTU_VERSION="$2"
            shift 2
            ;;
        --vm-name)
            VM_NAME="$2"
            shift 2
            ;;
        --pr-repo)
            PR_REPO="$2"
            shift 2
            ;;
        --pr-ref)
            PR_REF="$2"
            shift 2
            ;;
        --pr-sha)
            PR_SHA="$2"
            shift 2
            ;;
        --pr-number)
            PR_NUMBER="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ -z "$PR_REPO" ] || [ -z "$PR_SHA" ]; then
    echo "Error: --pr-repo and --pr-sha are required"
    exit 1
fi

echo "🔬 Testing PR Branch"
echo "==============================================================================="
echo "PR Repository: ${PR_REPO}"
echo "PR Reference: ${PR_REF}"
echo "PR SHA: ${PR_SHA}"
[ -n "$PR_NUMBER" ] && echo "PR Number: #${PR_NUMBER}"
echo "Ubuntu Version: ${UBUNTU_VERSION}"
echo "==============================================================================="
echo ""

# Determine if this is Lokole or IIAB PR
if [[ "$PR_REPO" == *"lokole"* ]] && [[ "$PR_REPO" != *"iiab"* ]]; then
    echo "🔧 Testing Lokole PR"
    LOKOLE_COMMIT="$PR_SHA"
    IIAB_PR=""
elif [[ "$PR_REPO" == *"iiab"* ]]; then
    echo "🔧 Testing IIAB PR"
    LOKOLE_COMMIT=""
    IIAB_PR="${PR_NUMBER}"
else
    echo "❌ Unknown repository type: ${PR_REPO}"
    exit 1
fi

# Run fresh install scenario with PR-specific config
SCENARIO_CMD="${ROOT_DIR}/scripts/scenarios/fresh-install.sh"
SCENARIO_CMD="${SCENARIO_CMD} --vm-name ${VM_NAME}"
SCENARIO_CMD="${SCENARIO_CMD} --ubuntu-version ${UBUNTU_VERSION}"
[ -n "$LOKOLE_COMMIT" ] && SCENARIO_CMD="${SCENARIO_CMD} --lokole-commit ${LOKOLE_COMMIT}"
[ -n "$IIAB_PR" ] && SCENARIO_CMD="${SCENARIO_CMD} --iiab-pr ${IIAB_PR}"

$SCENARIO_CMD

echo ""
echo "✅ PR test complete!"
echo "VM preserved for manual inspection: ${VM_NAME}"
echo "Clean up when done: multipass delete ${VM_NAME} --purge"
