#!/bin/bash
#
# Direct IIAB Installation Script for Azure CI/CD
# Installs IIAB directly on the host system (no nested VMs)
# Usage: ./direct-install.sh [OPTIONS]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Defaults
IIAB_PR=""
LOKOLE_COMMIT=""
LOKOLE_VERSION=""
PR_REPO="ascoderu/lokole"
PR_REF="master"
PR_SHA=""
PR_NUMBER=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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

echo "🚀 Direct IIAB Installation (Azure CI/CD)"
echo "==============================================================================="
echo "System: $(uname -a)"
echo "PR Repo: ${PR_REPO}"
echo "PR Ref: ${PR_REF}"
[ -n "$PR_SHA" ] && echo "PR SHA: ${PR_SHA}"
[ -n "$PR_NUMBER" ] && echo "PR Number: #${PR_NUMBER}"
[ -n "$IIAB_PR" ] && echo "IIAB PR: #${IIAB_PR}"
[ -n "$LOKOLE_COMMIT" ] && echo "Lokole Commit: ${LOKOLE_COMMIT}"
[ -n "$LOKOLE_VERSION" ] && echo "Lokole Version: ${LOKOLE_VERSION}"
echo "==============================================================================="

#
# STEP 1: System Preparation
#
echo ""
echo "📦 Step 1: Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y git curl wget build-essential

#
# STEP 2: Clone IIAB (optionally from PR branch)
#
echo ""
echo "  Step 2: Cloning IIAB repository..."

if [ -n "$IIAB_PR" ]; then
    echo "Using IIAB PR #${IIAB_PR}"
    # Clone and fetch PR
    sudo git clone https://github.com/iiab/iiab.git /opt/iiab/iiab
    cd /opt/iiab/iiab
    sudo git fetch origin pull/${IIAB_PR}/head:pr-${IIAB_PR}
    sudo git checkout pr-${IIAB_PR}
else
    echo "Using IIAB master branch"
    sudo git clone --depth 1 https://github.com/iiab/iiab.git /opt/iiab/iiab
fi

#
# STEP 3: Configure IIAB with Lokole settings
#
echo ""
echo "🔧 Step 3: Configuring IIAB..."

sudo mkdir -p /etc/iiab

# Determine Lokole configuration
LOKOLE_CONFIG=""
if [ -n "$LOKOLE_COMMIT" ]; then
    echo "Configuring Lokole from commit: ${LOKOLE_COMMIT}"
    LOKOLE_CONFIG="lokole_commit: '${LOKOLE_COMMIT}'"
    LOKOLE_CONFIG="${LOKOLE_CONFIG}\nlokole_repo: 'https://github.com/${PR_REPO}.git'"
elif [ -n "$LOKOLE_VERSION" ]; then
    echo "Configuring Lokole version: ${LOKOLE_VERSION}"
    LOKOLE_CONFIG="lokole_version: '${LOKOLE_VERSION}'"
else
    echo "Using latest Lokole from PyPI"
fi

# Create local_vars.yml
sudo bash -c "cat > /etc/iiab/local_vars.yml" << EOF
# IIAB Configuration for Lokole Integration Testing (Azure CI/CD)
# Generated: $(date)

# Admin credentials
iiab_admin_user: iiab-admin
iiab_admin_published_pwd: admin

# Enable all installation stages
stage1: True
stage2: True
stage3: True
stage4: True
stage5: True
stage6: True
stage7: True
stage8: True
stage9: True

# Lokole-specific configuration
lokole_install: True
lokole_enabled: True
${LOKOLE_CONFIG}

# Minimal services for testing
mysql_install: True
mysql_enabled: True
postgresql_install: False
apache_install: True
apache_enabled: True
nginx_install: True
nginx_enabled: True

# Disable unnecessary services to speed up installation
kiwix_install: False
calibre_install: False
kalite_install: False
kolibri_install: False
nodered_install: False
mosquitto_install: False
EOF

echo "Configuration written to /etc/iiab/local_vars.yml"
cat /etc/iiab/local_vars.yml

#
# STEP 4: Run IIAB Installation
#
echo ""
echo "🛠️  Step 4: Running IIAB installation..."
echo "This may take 10-15 minutes..."

cd /opt/iiab/iiab

# Run installation with logging
sudo ./iiab-install 2>&1 | tee /tmp/iiab-install.log

#
# STEP 5: Verify Installation
#
echo ""
echo "✅ Step 5: Verifying installation..."

# Check if IIAB services are running
if ! systemctl is-active --quiet iiab-cmdsrv; then
    echo "❌ ERROR: IIAB command server not running!"
    exit 1
fi

# Check if Lokole is installed
if [ ! -d /usr/local/lib/python*/dist-packages/opwen_email_client ]; then
    echo "❌ ERROR: Lokole (opwen_email_client) not installed!"
    exit 1
fi

# Check Lokole systemd services
if ! systemctl is-active --quiet opwen_cloudserver; then
    echo "⚠️  WARNING: Lokole cloudserver service not running"
fi

if ! systemctl is-active --quiet opwen_webapp; then
    echo "⚠️  WARNING: Lokole webapp service not running"
fi

#
# STEP 6: Run Comprehensive Verification
#
echo ""
echo "🔍 Step 6: Running comprehensive verification..."

if [ -f "${ROOT_DIR}/scripts/verify/comprehensive-check.sh" ]; then
    ${ROOT_DIR}/scripts/verify/comprehensive-check.sh
else
    echo "⚠️  Verification script not found, skipping"
fi

#
# STEP 7: Generate Report
#
echo ""
echo "📝 Step 7: Generating test report..."

# Save installation log
cp /tmp/iiab-install.log "${ROOT_DIR}/iiab-install-log.txt" || true

# Get system info
{
    echo "# IIAB Installation Test Report"
    echo ""
    echo "- **Date:** $(date)"
    echo "- **System:** $(lsb_release -d | cut -f2)"
    echo "- **Python:** $(python3 --version)"
    echo "- **PR Repo:** ${PR_REPO}"
    echo "- **PR Ref:** ${PR_REF}"
    [ -n "$PR_NUMBER" ] && echo "- **PR Number:** #${PR_NUMBER}"
    [ -n "$LOKOLE_COMMIT" ] && echo "- **Lokole Commit:** ${LOKOLE_COMMIT}"
    [ -n "$LOKOLE_VERSION" ] && echo "- **Lokole Version:** ${LOKOLE_VERSION}"
    echo ""
    echo "## Services Status"
    echo ""
    echo "```"
    systemctl status opwen_* --no-pager || true
    echo "```"
    echo ""
    echo "## Lokole Version"
    echo ""
    echo "```"
    pip3 show opwen-email-client || true
    echo "```"
} > "${ROOT_DIR}/pr-comment-direct-install.md"

echo ""
echo "✅ Direct IIAB installation complete!"
echo ""
echo "Test results: ${ROOT_DIR}/pr-comment-direct-install.md"
echo "Installation log: ${ROOT_DIR}/iiab-install-log.txt"
