#!/bin/bash
#
# Test GitHub Actions workflows locally using gh act
# 
# Requirements:
#   - Docker running
#   - gh act extension installed (gh extension install nektos/gh-act)

set -e

echo "🧪 Testing GitHub Actions Workflows Locally"
echo "============================================"
echo ""

# Check if example workflow needs to be temporarily disabled
if [ -f .github/workflows/test-on-azure-runner.example.yml ]; then
    echo "📝 Temporarily disabling test-on-azure-runner.example.yml (incompatible with act)..."
    mv .github/workflows/test-on-azure-runner.example.yml .github/workflows/test-on-azure-runner.example.yml.disabled
    RESTORE_EXAMPLE=1
elif [ -f .github/workflows/test-on-azure-runner.example.yml.skip ]; then
    echo "ℹ️  Example workflow already disabled (.skip extension)"
fi

echo ""
echo "📋 Available workflows:"
echo "----------------------"
gh act --list

echo ""
echo "🔍 Choose a test option:"
echo ""
echo "1. Dry-run PR workflow (test-on-pr-label.yml)"
echo "   gh act repository_dispatch -j test-pr --dryrun"
echo ""
echo "2. Dry-run scheduled workflow (test-ubuntu-lts.yml)" 
echo "   gh act workflow_dispatch -j test-version --dryrun"
echo ""
echo "3. Dry-run merge workflow (test-on-merge.yml)"
echo "   gh act repository_dispatch -j test-merged-version --dryrun"
echo ""
echo "4. Run PR workflow for one matrix job (Ubuntu 24.04)"
echo "   gh act repository_dispatch -j test-pr --matrix ubuntu_version:24.04"
echo ""
echo "⚠️  Note: Full runs require multipass and will likely fail on act."
echo "    These workflows are designed to run on GitHub-hosted runners or Azure VMs."
echo ""

# Restore example file if we temporarily disabled it
if [ -n "$RESTORE_EXAMPLE" ]; then
    echo "📝 Restoring test-on-azure-runner.example.yml..."
    mv .github/workflows/test-on-azure-runner.example.yml.disabled .github/workflows/test-on-azure-runner.example.yml
fi

echo ""
echo "✅ Workflow validation complete!"
echo ""
echo "To run a test, copy one of the commands above, e.g.:"
echo "  gh act repository_dispatch -j test-pr --dryrun"
