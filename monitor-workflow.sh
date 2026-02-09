#!/bin/bash
set -e

cd "$(dirname "$0")"
source .env

RUN_ID=${1:-21839020215}

echo "🚀 Monitoring workflow run: $RUN_ID (iiab-merged)"
echo "URL: https://github.com/ascoderu/iiab-lokole-tests/actions/runs/$RUN_ID"
echo ""

while true; do
  clear
  echo "=== Workflow Run: $RUN_ID (iiab-merged) ==="
  echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  
  # Get overall run status
  run_info=$(curl -s -H "Authorization: token ${INTEGRATION_TEST_PAT}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/ascoderu/iiab-lokole-tests/actions/runs/$RUN_ID")
  
  run_status=$(echo "$run_info" | jq -r '.status')
  run_conclusion=$(echo "$run_info" | jq -r '.conclusion // "in_progress"')
  
  echo "Overall status: $run_status | Conclusion: $run_conclusion"
  echo ""
  
  # Get job details
  curl -s -H "Authorization: token ${INTEGRATION_TEST_PAT}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/ascoderu/iiab-lokole-tests/actions/runs/$RUN_ID/jobs" | \
    jq -r '.jobs[] | "[\(.status)] \(.name)\n  Started: \(.started_at // "not started")\n  Conclusion: \(.conclusion // "running")\n"'
  
  if [ "$run_status" = "completed" ]; then
    echo ""
    echo "✅ Workflow completed with conclusion: $run_conclusion"
    break
  fi
  
  echo "Refreshing in 30 seconds... (Ctrl+C to stop)"
  sleep 30
done
