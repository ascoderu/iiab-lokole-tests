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

REPORT_FILE="fresh-install-${UBUNTU_VERSION}-$(date +%Y%m%d-%H%M%S).txt"
${ROOT_DIR}/scripts/verify/verify-installation.sh --vm-name ${VM_NAME} --output-file "${REPORT_FILE}"

# Final Summary
echo ""
echo "🎊 TEST COMPLETE!"
echo "==============================================================================="
echo "VM Name: ${VM_NAME}"
echo "Report: ${REPORT_FILE}"
echo ""
echo "Key Results:"
grep -E "✅|❌|⚠️|🎉" "${REPORT_FILE}" | tail -10
echo ""
echo "💡 Next Steps:"
echo "1. Review full report: cat ${REPORT_FILE}"
echo "2. Access VM: multipass shell ${VM_NAME}"
echo "3. Clean up: multipass delete ${VM_NAME} --purge"
