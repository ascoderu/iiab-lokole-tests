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
LOKOLE_REPO="ascoderu/lokole"
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
        --lokole-repo)
            LOKOLE_REPO="$2"
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
[ -n "$LOKOLE_REPO" ] && [ "$LOKOLE_REPO" != "ascoderu/lokole" ] && echo "Lokole Repo: ${LOKOLE_REPO}"
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
if [ -n "$LOKOLE_COMMIT" ]; then
    echo "Configuring Lokole from commit: ${LOKOLE_COMMIT} (repo: ${LOKOLE_REPO})"
elif [ -n "$LOKOLE_VERSION" ]; then
    echo "Configuring Lokole version: ${LOKOLE_VERSION}"
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

# MINIMAL mode: Install ONLY what's needed for Lokole
# Disable all stages to prevent automatic installation of unnecessary packages
stage1: False
stage2: False
stage3: False
stage4: False
stage5: False
stage6: False
stage7: False
stage8: False
stage9: False

# Explicitly install only what Lokole needs
nginx_install: True
nginx_enabled: True
lokole_install: True
lokole_enabled: True
EOF

# Add Lokole commit/version config conditionally
if [ -n "$LOKOLE_COMMIT" ]; then
    sudo bash -c "cat >> /etc/iiab/local_vars.yml" << EOF
lokole_commit: '${LOKOLE_COMMIT}'
lokole_repo: 'https://github.com/${LOKOLE_REPO}.git'
EOF
elif [ -n "$LOKOLE_VERSION" ]; then
    sudo bash -c "cat >> /etc/iiab/local_vars.yml" << EOF
lokole_version: '${LOKOLE_VERSION}'
EOF
fi

# Continue with rest of config
sudo bash -c "cat >> /etc/iiab/local_vars.yml" << EOF

# Disable all other services (explicit False to be clear)
network_install: False
network_enabled: False
EOF

echo "Configuration written to /etc/iiab/local_vars.yml"
cat /etc/iiab/local_vars.yml

#
# STEP 4: Install Ansible (required by IIAB)
#
echo ""
echo "📦 Step 4a: Installing Ansible..."
echo "This is required by IIAB before running iiab-install"

cd /opt/iiab/iiab

# Install Ansible using IIAB's script
sudo ./scripts/ansible 2>&1 | tee /tmp/ansible-install.log

echo "✅ Ansible installed successfully"

#
# STEP 5: Run IIAB Installation (minimal - only roles needed for Lokole)
#
echo ""
echo "🛠️  Step 5: Running minimal IIAB installation for Lokole..."
echo "This installs only: 0-init + nginx + lokole"
echo "This may take 3-5 minutes..."

# Create state file first (required by roles)
sudo mkdir -p /etc/iiab
sudo touch /etc/iiab/iiab_state.yml

# Initialize IIAB (required first step)
echo ""
echo "Step 5a: Running 0-init role..."
sudo ./runrole 0-init 2>&1 | tee /tmp/iiab-init.log

# Install nginx (required for Lokole)
echo ""
echo "Step 5b: Installing nginx..."
sudo ./runrole nginx 2>&1 | tee -a /tmp/iiab-install.log

# Install lokole (our target)
echo ""
echo "Step 5c: Installing lokole..."
sudo ./runrole lokole 2>&1 | tee -a /tmp/iiab-install.log

echo ""
echo "✅ Minimal IIAB installation completed"

#
# STEP 6: Verify Installation
#
echo ""
echo "✅ Step 6: Verifying installation..."

# Check if IIAB completed successfully
if [ ! -f /etc/iiab/iiab_state.yml ]; then
    echo "❌ ERROR: IIAB state file not found - installation may have failed"
    exit 1
fi

# Check if lokole_installed is True in iiab_state.yml
if ! grep -q "^lokole_installed: True" /etc/iiab/iiab_state.yml; then
    echo "❌ ERROR: lokole_installed not set to True in /etc/iiab/iiab_state.yml"
    echo "Contents of iiab_state.yml:"
    cat /etc/iiab/iiab_state.yml
    exit 1
fi

echo "✅ IIAB installation completed - lokole_installed: True"

# Check if Lokole virtualenv exists
if [ ! -d /library/lokole/venv ]; then
    echo "❌ ERROR: Lokole virtualenv not found at /library/lokole/venv"
    ls -la /library/lokole/ 2>&1 || echo "  /library/lokole directory not found"
    exit 1
fi

echo "✅ Lokole virtualenv exists at /library/lokole/venv"

# Check if supervisor config files exist
LOKOLE_SUPERVISOR_CONFS=(
    "lokole_gunicorn.conf"
    "lokole_celery_beat.conf"
    "lokole_celery_worker.conf"
    "lokole_restarter.conf"
)

for conf in "${LOKOLE_SUPERVISOR_CONFS[@]}"; do
    if [ ! -f "/etc/supervisor/conf.d/${conf}" ]; then
        echo "❌ ERROR: Supervisor config not found: /etc/supervisor/conf.d/${conf}"
        exit 1
    fi
done

echo "✅ All 4 Lokole supervisor configs found"

# Try to import opwen_email_client from the venv
echo ""
echo "Checking Lokole package installation:"
if /library/lokole/venv/bin/python -c "import opwen_email_client; print('  Version:', opwen_email_client.__version__)" 2>&1; then
    echo "✅ Lokole package successfully imported"
else
    echo "❌ ERROR: Could not import opwen_email_client from virtualenv"
    exit 1
fi

# Check supervisor service status (informational)
echo ""
echo "Supervisor status:"
if systemctl is-active --quiet supervisor; then
    echo "  ✅ Supervisor service is running"
    
    # Check lokole processes via supervisorctl
    echo ""
    echo "Lokole processes (via supervisorctl):"
    sudo supervisorctl status | grep lokole || echo "  ⚠️  No lokole processes found (they may start on-demand)"
else
    echo "  ⚠️  Supervisor service not running (this might be OK for minimal installs)"
fi

#
# STEP 7: Run Comprehensive Verification
#
echo ""
echo "🔍 Step 7: Running comprehensive verification..."

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
