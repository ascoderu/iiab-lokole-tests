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

# Stage installations
1-prep_install: True
1-prep_enabled: True
2-common_install: True
2-common_enabled: True
3-base-server_install: True
3-base-server_enabled: True

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
echo "🏗️  Installing IIAB minimal setup (stages 0-3 + Lokole only)..."
echo "This targeted install takes ~10-15 minutes instead of the full 60 minutes"
echo ""

# First, download IIAB repository
echo "📦 Downloading IIAB repository..."
multipass exec ${VM_NAME} -- sudo bash -c 'apt update && apt install -y git'
multipass exec ${VM_NAME} -- sudo bash -c 'mkdir -p /opt/iiab && cd /opt/iiab && if [ ! -d iiab ]; then git clone https://github.com/iiab/iiab; fi'

# Apply IIAB PR if specified
if [ -n "$IIAB_PR" ]; then
    echo "📦 Applying IIAB PR #${IIAB_PR}..."
    multipass exec ${VM_NAME} -- sudo bash -c "cd /opt/iiab/iiab && git fetch origin pull/${IIAB_PR}/head:pr-${IIAB_PR} && git checkout pr-${IIAB_PR}"
fi

echo "✅ IIAB repository ready at /opt/iiab/iiab"

# Install Ansible (required by runrole)
echo "📦 Installing Ansible..."
multipass exec ${VM_NAME} -- sudo bash -c 'cd /opt/iiab/iiab && ./scripts/ansible 2>&1 | tee /tmp/iiab-ansible-install.log'
echo "✅ Ansible installed"

# Run minimal stages needed for Lokole
echo "▶️  Stage 0-1: Running 1-prep (basic preparation)..."
multipass exec ${VM_NAME} -- sudo bash -c 'cd /opt/iiab/iiab && ./runrole 1-prep 2>&1 | tee /tmp/iiab-stage1-prep.log'

echo "▶️  Stage 2: Running 2-common (common packages)..."
multipass exec ${VM_NAME} -- sudo bash -c 'cd /opt/iiab/iiab && ./runrole 2-common 2>&1 | tee /tmp/iiab-stage2-common.log'

echo "▶️  Stage 3: Running 3-base-server (nginx + base server)..."
multipass exec ${VM_NAME} -- sudo bash -c 'cd /opt/iiab/iiab && ./runrole 3-base-server 2>&1 | tee /tmp/iiab-stage3-base.log'

echo "▶️  Installing Lokole..."
multipass exec ${VM_NAME} -- sudo bash -c 'cd /opt/iiab/iiab && ./runrole lokole 2>&1 | tee /tmp/iiab-lokole.log'

echo "▶️  Running network configuration..."
multipass exec ${VM_NAME} -- sudo bash -c 'cd /opt/iiab/iiab && ./iiab-network 2>&1 | tee /tmp/iiab-network.log'

echo ""
echo "✅ IIAB minimal installation complete!"
echo "Logs available on VM:"
echo "  - /tmp/iiab-download.log"
echo "  - /tmp/iiab-ansible-install.log"
echo "  - /tmp/iiab-stage1-prep.log"
echo "  - /tmp/iiab-stage2-common.log"
echo "  - /tmp/iiab-stage3-base.log"
echo "  - /tmp/iiab-lokole.log"
echo "  - /tmp/iiab-network.log"
