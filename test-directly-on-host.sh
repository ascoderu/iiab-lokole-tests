#!/bin/bash
#
# Run IIAB-Lokole tests directly on host (bypass GitHub Actions)
#
# This simulates what the workflow does but runs directly on your machine.
# Use this for quick testing without setting up runners or VMs.

set -e

echo "🧪 Direct Host Testing (No GitHub Actions)"
echo "=========================================="
echo ""
echo "This script:"
echo "  📋 Uses test framework from: iiab-lokole-tests (current directory)"
echo "  🔬 Tests Lokole changes from: ../lokole (detected branch)"
echo ""
echo "⚠️  WARNING: This will:"
echo "   - Create multipass VMs on your system"
echo "   - Install IIAB and Lokole in the VM"
echo "   - May take 30-60 minutes to complete"
echo ""

# Auto-detect lokole branch and commit from workspace
LOKOLE_BRANCH=""
LOKOLE_SHA=""
LOKOLE_PR_NUMBER=""
if [ -d "../lokole/.git" ]; then
    LOKOLE_BRANCH=$(cd ../lokole && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    LOKOLE_SHA=$(cd ../lokole && git rev-parse HEAD 2>/dev/null || echo "")
    
    if [ -n "$LOKOLE_BRANCH" ]; then
        echo "📍 Detected lokole branch in workspace: $LOKOLE_BRANCH"
        echo "   Commit: ${LOKOLE_SHA:0:12}"
        
        # Try to detect PR number from branch name or git remote
        LOKOLE_PR_NUMBER=$(cd ../lokole && gh pr view --json number -q .number 2>/dev/null || echo "")
        if [ -n "$LOKOLE_PR_NUMBER" ]; then
            echo "   PR: #$LOKOLE_PR_NUMBER"
        fi
    fi
fi

# Default values - use detected values from lokole workspace
PR_REPO="${PR_REPO:-ascoderu/lokole}"
PR_REF="${PR_REF:-${LOKOLE_BRANCH:-master}}"
PR_SHA="${PR_SHA:-${LOKOLE_SHA:-HEAD}}"
PR_NUMBER="${PR_NUMBER:-${LOKOLE_PR_NUMBER:-local-test}}"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04}"
PYTHON_EXPECTED="${PYTHON_EXPECTED:-3.12}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Test Framework (iiab-lokole-tests)"
echo "   Location: $(pwd)"
echo "   Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
echo ""
echo "🔬 Testing Lokole PR/Branch"
echo "   Repository: $PR_REPO"
echo "   Branch: $PR_REF"
echo "   Commit: ${PR_SHA:0:12}..."
echo "   PR Number: #$PR_NUMBER"
echo ""
echo "🖥️  Test Environment"
echo "   Ubuntu Version: $UBUNTU_VERSION"
echo "   Expected Python: $PYTHON_EXPECTED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -n "$LOKOLE_BRANCH" ]; then
    echo "✅ Auto-detected lokole workspace branch: $LOKOLE_BRANCH"
    echo "   The test will install Lokole from GitHub branch: $PR_REF"
    echo ""
fi

read -p "Continue with these settings? (y/n): " CONTINUE
if [ "$CONTINUE" != "y" ]; then
    echo ""
    echo "To customize, set environment variables:"
    echo "  export PR_REPO=ascoderu/lokole"
    echo "  export PR_REF=feature/my-branch"
    echo "  export UBUNTU_VERSION=22.04"
    echo "  export PYTHON_EXPECTED=3.10"
    echo "  ./test-directly-on-host.sh"
    echo ""
    echo "⚠️  Note: The test will clone from GitHub, so make sure your"
    echo "   changes are committed and pushed to the remote branch!"
    exit 0
fi

echo ""
echo "🚀 Starting test execution..."
echo "============================="

# Create test environment
export PR_REPO PR_REF PR_SHA PR_NUMBER
export UBUNTU_VERSION PYTHON_EXPECTED

# Run the test scenario
cd "$(dirname "$0")"

if [ ! -f "scripts/scenarios/test-pr-branch.sh" ]; then
    echo "❌ Test scripts not found. Are you in iiab-lokole-tests directory?"
    exit 1
fi

echo ""
echo "📝 Test logs will be saved to: test-results-$(date +%Y%m%d-%H%M%S).log"
LOG_FILE="test-results-$(date +%Y%m%d-%H%M%S).log"

# Run the actual test with required parameters
./scripts/scenarios/test-pr-branch.sh \
    --pr-repo "$PR_REPO" \
    --pr-ref "$PR_REF" \
    --pr-sha "$PR_SHA" \
    --pr-number "$PR_NUMBER" \
    --ubuntu-version "$UBUNTU_VERSION" \
    2>&1 | tee "$LOG_FILE"

EXIT_CODE=${PIPESTATUS[0]}

echo ""
echo "============================="
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Test completed successfully!"
else
    echo "❌ Test failed with exit code $EXIT_CODE"
fi

echo ""
echo "📋 Results:"
echo "  Log file: $LOG_FILE"

# Generate PR comment if verification script exists
if [ -f "scripts/verify/generate-pr-comment.sh" ] && [ -f "test-results.json" ]; then
    echo "  Generating PR comment..."
    ./scripts/verify/generate-pr-comment.sh
    if [ -f "*pr-comment*.md" ]; then
        echo "  PR comment: $(ls *pr-comment*.md)"
        echo ""
        echo "📄 PR Comment Preview:"
        echo "======================"
        cat *pr-comment*.md
    fi
fi

echo ""
echo "🧹 Cleanup:"
echo "  To remove test VM: multipass delete <vm-name> && multipass purge"
echo "  List VMs: multipass list"

exit $EXIT_CODE
