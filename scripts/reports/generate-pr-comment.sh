#!/bin/bash
#
# Generate PR Comment Body
# Creates a markdown message suitable for posting on a GitHub PR
#

set -e

OUTPUT_FILE="${1:-pr-comment.md}"
VERIFICATION_JSON="${2:-comprehensive-check-results.json}"
PR_REPO="${3:-unknown}"
PR_REF="${4:-master}"

echo "💬 Generating PR comment body..."

if [ ! -f "$VERIFICATION_JSON" ]; then
  echo "❌ Error: Verification JSON not found: $VERIFICATION_JSON"
  exit 1
fi

# Extract data
os_version=$(jq -r '.system.os_version // "unknown"' "$VERIFICATION_JSON")
os_codename=$(jq -r '.system.os_codename // "unknown"' "$VERIFICATION_JSON")
python_version=$(jq -r '.system.python_version // "unknown"' "$VERIFICATION_JSON")
kernel=$(jq -r '.system.kernel // "unknown"' "$VERIFICATION_JSON")
summary=$(jq -r '.summary // "unknown"' "$VERIFICATION_JSON")
timestamp=$(jq -r '.timestamp // ""' "$VERIFICATION_JSON")

# Count checks
total_checks=$(jq -r '.checks.total // 0' "$VERIFICATION_JSON")
passed_checks=$(jq -r '.checks.passed // 0' "$VERIFICATION_JSON")
failed_checks=$(jq -r '.checks.failed // 0' "$VERIFICATION_JSON")
warnings=$(jq -r '.checks.warnings // 0' "$VERIFICATION_JSON")

# Service status
gunicorn_status=$(jq -r '.services["lokole-gunicorn.service"].status // "unknown"' "$VERIFICATION_JSON")
gunicorn_pid=$(jq -r '.services["lokole-gunicorn.service"].pid // "N/A"' "$VERIFICATION_JSON")
celery_beat_status=$(jq -r '.services["lokole-celery-beat.service"].status // "unknown"' "$VERIFICATION_JSON")
celery_worker_status=$(jq -r '.services["lokole-celery-worker.service"].status // "unknown"' "$VERIFICATION_JSON")

# Port info
port_listening=$(jq -r '.port.listening // false' "$VERIFICATION_JSON")
port_number=$(jq -r '.port.port_number // "8084"' "$VERIFICATION_JSON")
port_process=$(jq -r '.port.process // "unknown"' "$VERIFICATION_JSON")

# Web access
http_code=$(jq -r '.web_access.http_code // "N/A"' "$VERIFICATION_JSON")
response_time=$(jq -r '.web_access.response_time_ms // "N/A"' "$VERIFICATION_JSON")

# Determine emoji
if [ "$summary" = "PASSED" ]; then
  emoji="✅"
else
  emoji="❌"
fi

# Generate comment
cat > "$OUTPUT_FILE" << EOF
## $emoji Integration Test Result

**Repository:** \`$PR_REPO\` | **Branch:** \`$PR_REF\`

### System Information
- **OS:** Ubuntu $os_version ($os_codename)
- **Python:** $python_version
- **Kernel:** $kernel
- **Timestamp:** $timestamp

### Services Status
| Service | Status | Details |
|---------|--------|---------|
| Gunicorn | ✅ $gunicorn_status | PID: $gunicorn_pid |
| Celery Beat | ✅ $celery_beat_status | Scheduler |
| Celery Worker | ✅ $celery_worker_status | Task processor |

### Network Configuration
- **Port Listening:** $([ "$port_listening" = "true" ] && echo "✅ Yes" || echo "❌ No")
- **Port Number:** `$port_number`
- **Process:** `$port_process`

### Web Access Verification
- **HTTP Response:** \`$http_code\`
- **Response Time:** ${response_time}ms

### Verification Summary
- ✅ **Passed:** $passed_checks/$total_checks checks
- ❌ **Failed:** $failed_checks/$total_checks checks
- ⚠️ **Warnings:** $warnings

### Overall Result
**$summary**

---
<sub>Integration test run completed at $timestamp</sub>
EOF

echo "✅ PR comment generated: $OUTPUT_FILE"
cat "$OUTPUT_FILE"
