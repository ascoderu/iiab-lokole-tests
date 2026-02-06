#!/bin/bash
# IIAB Installation Script for Integration Testing
# Usage: ./install-iiab.sh [OPTIONS]
# Options:
#   --vm-name NAME              VM name (default: iiab-lokole-test)
#   --iiab-pr NUMBER            IIAB PR number to test
#   --lokole-commit SHA         Lokole commit SHA to test
#   --lokole-version VERSION    Lokole PyPI version to test
#   --config-template PATH      Path to local_vars.yml template

set -e

# Defaults
VM_NAME="iiab-lokole-test"
IIAB_PR=""
LOKOLE_COMMIT=""
LOKOLE_VERSION=""
CONFIG_TEMPLATE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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
        --config-template)
            CONFIG_TEMPLATE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "🔧 Installing IIAB on ${VM_NAME}"
echo "==============================================================================="
[ -n "$IIAB_PR" ] && echo "IIAB PR: #${IIAB_PR}"
[ -n "$LOKOLE_COMMIT" ] && echo "Lokole Commit: ${LOKOLE_COMMIT}"
[ -n "$LOKOLE_VERSION" ] && echo "Lokole Version: ${LOKOLE_VERSION}"
echo "==============================================================================="

echo "📋 Configuring IIAB..."
multipass exec ${VM_NAME} -- sudo bash -c '
# Update system
apt update && apt upgrade -y
apt install -y git curl wget build-essential

# Create IIAB configuration directory
mkdir -p /etc/iiab
'

# Generate or copy local_vars.yml
if [ -n "$CONFIG_TEMPLATE" ]; then
    echo "Using config template: ${CONFIG_TEMPLATE}"
    multipass transfer "${CONFIG_TEMPLATE}" ${VM_NAME}:/tmp/local_vars.yml
    multipass exec ${VM_NAME} -- sudo mv /tmp/local_vars.yml /etc/iiab/local_vars.yml
else
    echo "Creating default local_vars.yml..."
    multipass exec ${VM_NAME} -- sudo bash -c 'cat > /etc/iiab/local_vars.yml << "EOF"
# IIAB Configuration for Lokole Integration Testing
iiab_admin_user: iiab-admin
iiab_admin_published_pwd: admin

# Core services
nginx_install: True
nginx_enabled: True

# Lokole configuration
lokole_install: True
lokole_enabled: True
lokole_sim_type: LocalOnly

# Minimal config for testing
network_enabled: False
wifi_install: False
hostapd_enabled: False
captiveportal_install: False
common_install: True
common_enabled: True
EOF
'
fi

# Add Lokole-specific config if provided
if [ -n "$LOKOLE_COMMIT" ]; then
    echo "Configuring Lokole commit: ${LOKOLE_COMMIT}..."
    multipass exec ${VM_NAME} -- sudo bash -c "cat >> /etc/iiab/local_vars.yml << EOF
lokole_commit: ${LOKOLE_COMMIT}
lokole_repo: https://github.com/ascoderu/lokole.git
EOF
"
elif [ -n "$LOKOLE_VERSION" ]; then
    echo "Configuring Lokole version: ${LOKOLE_VERSION}..."
    multipass exec ${VM_NAME} -- sudo bash -c "echo 'lokole_version: ${LOKOLE_VERSION}' >> /etc/iiab/local_vars.yml"
fi

echo "📄 Configuration:"
multipass exec ${VM_NAME} -- sudo cat /etc/iiab/local_vars.yml

echo ""
echo "🏗️  Installing IIAB..."
if [ -n "$IIAB_PR" ]; then
    echo "Installing from IIAB PR #${IIAB_PR}..."
    multipass exec ${VM_NAME} -- bash -c "curl -fsSL iiab.io/install.txt | sudo bash -s ${IIAB_PR} 2>&1 | tee /tmp/iiab-install.log"
else
    echo "Installing from IIAB master..."
    multipass exec ${VM_NAME} -- bash -c "curl -fsSL download.iiab.io | sudo bash 2>&1 | tee /tmp/iiab-install.log"
fi

echo ""
echo "✅ IIAB installation complete!"
echo "Installation log saved to /tmp/iiab-install.log on VM"
echo "Next: Run verify-installation.sh to check services"
