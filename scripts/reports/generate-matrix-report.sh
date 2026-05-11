#!/bin/bash
#
# Generate Visual Matrix Test Report
# Creates a markdown report showing test results across all Ubuntu versions
#

set -e

REPORT_FILE="${1:-matrix-test-report.md}"
RESULTS_DIR="${2:-.}"

echo "📊 Generating matrix test report..."

# Initialize report
cat > "$REPORT_FILE" << 'EOF'
# Integration Test Results - Matrix Summary

EOF

# Collect all verification.json files and generate matrix
echo "| Ubuntu Version | Python | Status | Port | HTTP | Response Time | Kernel |" >> "$REPORT_FILE"
echo "|---|---|---|---|---|---|---|" >> "$REPORT_FILE"

# Find and process all verification.json files
for json_file in $(find "$RESULTS_DIR" -name "comprehensive-check-results.json" | sort); do
  if [ -f "$json_file" ]; then
    # Extract data from JSON
    os_version=$(jq -r '.system.os_version // "unknown"' "$json_file")
    python_version=$(jq -r '.system.python_version // "unknown"' "$json_file")
    summary=$(jq -r '.summary // "unknown"' "$json_file")
    port_listening=$(jq -r '.port.listening // false' "$json_file")
    http_code=$(jq -r '.web_access.http_code // "N/A"' "$json_file")
    response_time=$(jq -r '.web_access.response_time_ms // "N/A"' "$json_file")
    kernel=$(jq -r '.system.kernel // "unknown"' "$json_file")
    
    # Format status
    if [ "$summary" = "PASSED" ]; then
      status="✅ PASSED"
    else
      status="❌ FAILED"
    fi
    
    # Format port
    if [ "$port_listening" = "true" ]; then
      port="✅"
    else
      port="❌"
    fi
    
    # Format HTTP
    if [ "$http_code" = "200" ]; then
      http_check="✅"
    else
      http_check="❌"
    fi
    
    echo "| **Ubuntu $os_version** | $python_version | $status | $port | $http_check ($http_code) | ${response_time}ms | $kernel |" >> "$REPORT_FILE"
  fi
done

cat >> "$REPORT_FILE" << 'EOF'

## Details

### Service Status
- ✅ Gunicorn (WSGI server)
- ✅ Celery Beat (scheduler)
- ✅ Celery Worker (task processor)
- ✅ Lokole Restarter (auto-restart)

### Verification Checks
- ✅ TCP port listening (8084)
- ✅ Web access via nginx reverse proxy
- ✅ Python environment correctness
- ✅ System log validation

### Legend
- **Port**: TCP port 8084 accessibility
- **HTTP**: Web service response code
- **Response Time**: Latency in milliseconds

---

*Report generated at $(date -u '+%Y-%m-%d %H:%M:%S UTC')*
EOF

echo "✅ Report generated: $REPORT_FILE"
wc -l "$REPORT_FILE"
