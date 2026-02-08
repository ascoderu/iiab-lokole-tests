#!/bin/bash
#
# Direct IIAB Installation Script for Azure CI/CD
# Installs IIAB directly on the host system (no nested VMs)
# Usage: ./direct-install.sh [OPTIONS]
#
# Options:
#   --vm-name <name>         Name identifier for verification (default: direct-install)
#   --pr-repo <repo>         PR repository (e.g., iiab/iiab)
#   --pr-ref <ref>           PR branch/ref
#   --pr-number <number>     PR number
#   --iiab-pr <number>       IIAB PR number to test
#   --lokole-commit <sha>    Lokole git commit to install
#   --lokole-repo <repo>     Lokole git repository (default: ascoderu/lokole)
#   --lokole-version <ver>   Lokole PyPI version to install

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Defaults
VM_NAME="direct-install"
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

echo "🚀 Direct IIAB Installation (Azure CI/CD)"
echo "==============================================================================="
echo "VM Name: ${VM_NAME}"
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

# Determine if this is an IIAB PR by checking PR_REPO
if [[ "$PR_REPO" == iiab/iiab* ]] && [ -n "$PR_NUMBER" ]; then
    echo "Using IIAB PR #${PR_NUMBER} (from ${PR_REPO})"
    # Clone and fetch PR
    sudo git clone https://github.com/iiab/iiab.git /opt/iiab/iiab
    cd /opt/iiab/iiab
    sudo git fetch origin pull/${PR_NUMBER}/head:pr-${PR_NUMBER}
    sudo git checkout pr-${PR_NUMBER}
    echo "Checked out PR branch: $(git branch --show-current)"
    echo "Latest commit: $(git log -1 --oneline)"
elif [ -n "$IIAB_PR" ]; then
    # Legacy support for --iiab-pr parameter
    echo "Using IIAB PR #${IIAB_PR}"
    sudo git clone https://github.com/iiab/iiab.git /opt/iiab/iiab
    cd /opt/iiab/iiab
    sudo git fetch origin pull/${IIAB_PR}/head:pr-${IIAB_PR}
    sudo git checkout pr-${IIAB_PR}
    echo "Checked out PR branch: $(git branch --show-current)"
    echo "Latest commit: $(git log -1 --oneline)"
else
    echo "Using IIAB master branch"
    sudo git clone --depth 1 https://github.com/iiab/iiab.git /opt/iiab/iiab
    cd /opt/iiab/iiab
    echo "Latest commit: $(git log -1 --oneline)"
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
# STEP 6: Run Comprehensive Verification
#
echo ""
echo "🔍 Step 6: Running comprehensive verification..."

if [ -f "${ROOT_DIR}/scripts/verify/comprehensive-check.sh" ]; then
    # Run comprehensive check - it will verify:
    # - IIAB state file and lokole_installed flag
    # - Lokole virtualenv and package installation
    # - Supervisor configs and services
    # - Socket permissions and nginx configuration
    ${ROOT_DIR}/scripts/verify/comprehensive-check.sh "${VM_NAME}" || {
        echo "❌ Comprehensive verification failed"
        exit 1
    }
    echo ""
    echo "✅ All verification checks passed"
else
    echo "⚠️  Comprehensive verification script not found, using basic checks"
    
    # Fallback: Basic verification
    if [ ! -f /etc/iiab/iiab_state.yml ]; then
        echo "❌ ERROR: IIAB state file not found"
        exit 1
    fi
    
    if ! grep -q "^lokole_installed: True" /etc/iiab/iiab_state.yml; then
        echo "❌ ERROR: lokole_installed not True"
        exit 1
    fi
    
    if [ ! -d /library/lokole/venv ]; then
        echo "❌ ERROR: Lokole virtualenv not found"
        exit 1
    fi
    
    echo "✅ Basic verification passed"
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
