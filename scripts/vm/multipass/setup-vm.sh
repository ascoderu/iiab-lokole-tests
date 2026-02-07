#!/bin/bash
# VM Setup Script for IIAB-Lokole Integration Testing
# Usage: ./setup-vm.sh [OPTIONS]
# Options:
#   --ubuntu-version VERSION    Ubuntu version (e.g., 24.04, 26.04)
#   --use-daily                 Use daily pre-release build
#   --vm-name NAME              VM name (default: iiab-lokole-test)

set -e

# Default values
UBUNTU_VERSION="24.04"
USE_DAILY=false
VM_NAME="iiab-lokole-test"

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
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "🚀 Setting up Ubuntu ${UBUNTU_VERSION} VM for IIAB-Lokole testing"
echo "==============================================================================="
echo "VM Name: ${VM_NAME}"
echo "Ubuntu Version: ${UBUNTU_VERSION}"
echo "Use Daily: ${USE_DAILY}"
echo "==============================================================================="

# Clean up existing VM
echo "📦 Cleaning up existing VM (if any)..."
multipass delete ${VM_NAME} --purge 2>/dev/null || true

# Determine image name
if [ "$USE_DAILY" = true ]; then
    case "$UBUNTU_VERSION" in
        26.04)
            IMAGE="daily:26.04"
            ;;
        *)
            IMAGE="daily:${UBUNTU_VERSION}"
            ;;
    esac
else
    IMAGE="${UBUNTU_VERSION}"
fi

echo "📦 Creating Ubuntu ${UBUNTU_VERSION} VM with image: ${IMAGE}..."
if multipass launch --name ${VM_NAME} --disk 15G --memory 2G --cpus 2 ${IMAGE}; then
    echo "✅ VM created successfully"
else
    echo "❌ Failed to create VM. Available images:"
    multipass find
    exit 1
fi

echo "⏳ Waiting for VM to be ready..."
sleep 10

echo "🐧 Checking VM system info..."
multipass exec ${VM_NAME} -- bash -c '
echo "System Information:"
cat /etc/os-release | head -5
echo ""
echo "Python Version:"
python3 --version
echo ""
echo "System Resources:"
free -h
df -h /
'

echo ""
echo "✅ VM setup complete!"
echo "VM Name: ${VM_NAME}"
echo "Next: Run install-iiab.sh to install IIAB"
