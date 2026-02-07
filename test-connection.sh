#!/bin/bash
set -euo pipefail

# Test Connection Script for INTEGRATION_TEST_PAT
# This script tests if the GitHub PAT can trigger repository_dispatch events

# Load .env file if it exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    echo "📦 Loading environment from .env file..."
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

echo "🔍 Testing INTEGRATION_TEST_PAT connection..."
echo ""

# Check if PAT is provided
if [ -z "${INTEGRATION_TEST_PAT:-}" ]; then
    echo "❌ ERROR: INTEGRATION_TEST_PAT environment variable not set"
    echo ""
    echo "Usage:"
    echo "  export INTEGRATION_TEST_PAT='your_github_pat_here'"
    echo "  ./test-connection.sh"
    exit 1
fi

# Test endpoint
API_URL="https://api.github.com/repos/ascoderu/iiab-lokole-tests/dispatches"

# Test payload (simulating PR #610)
PAYLOAD='{
  "event_type": "test-integration-lokole",
  "client_payload": {
    "pr_number": 610,
    "ref": "feature/add-integration-test-trigger",
    "sha": "725c7d6dd69d22ab38f74224164ae14bbaf4a977",
    "repo": "ascoderu/lokole"
  }
}'

echo "📡 Sending repository_dispatch event to:"
echo "   $API_URL"
echo ""
echo "📦 Payload:"
echo "$PAYLOAD" | jq '.'
echo ""

# Send request
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL" \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $INTEGRATION_TEST_PAT" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -d "$PAYLOAD")

# Extract status code (last line)
HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | head -n -1)

echo "📊 Response:"
echo "   HTTP Status: $HTTP_CODE"

if [ "$HTTP_CODE" = "204" ]; then
    echo "   ✅ SUCCESS - Event dispatched successfully!"
    echo ""
    echo "🎯 Next steps:"
    echo "   1. Visit: https://github.com/ascoderu/iiab-lokole-tests/actions"
    echo "   2. Look for 'Test on PR Label' workflow run (takes ~30s to appear)"
    echo "   3. Workflow will test all 3 Ubuntu versions in parallel"
    echo "   4. Results will be posted to PR #610 as comments"
    echo ""
    echo "⏱️  Expected timeline:"
    echo "   - Workflow appears: ~30 seconds"
    echo "   - Tests complete: ~30-60 minutes (VM setup + IIAB install)"
    echo "   - PR comments posted: After each matrix job completes"
    exit 0
elif [ "$HTTP_CODE" = "401" ]; then
    echo "   ❌ AUTHENTICATION FAILED"
    echo ""
    echo "   Error: Invalid or expired PAT"
    echo "   Please check:"
    echo "   - PAT is correctly copied (no extra spaces)"
    echo "   - PAT has 'repo' + 'workflow' scopes"
    echo "   - PAT has not expired"
    exit 1
elif [ "$HTTP_CODE" = "403" ]; then
    echo "   ❌ AUTHORIZATION FAILED"
    echo ""
    echo "   Error: PAT lacks required permissions"
    echo "   Please ensure PAT has:"
    echo "   - 'repo' scope (full repository access)"
    echo "   - 'workflow' scope (trigger workflows)"
    echo ""
    if [ -n "$BODY" ]; then
        echo "   GitHub says:"
        echo "$BODY" | jq '.'
    fi
    exit 1
elif [ "$HTTP_CODE" = "404" ]; then
    echo "   ❌ NOT FOUND"
    echo ""
    echo "   Error: Repository not found or PAT lacks access"
    echo "   Please check:"
    echo "   - Repository name is correct: ascoderu/iiab-lokole-tests"
    echo "   - PAT has access to the repository"
    exit 1
else
    echo "   ❌ UNEXPECTED ERROR"
    echo ""
    echo "   Response body:"
    if [ -n "$BODY" ]; then
        echo "$BODY" | jq '.' || echo "$BODY"
    else
        echo "   (empty)"
    fi
    exit 1
fi
