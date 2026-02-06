#!/bin/bash
# Generate PR comment from JSON verification results
# Converts comprehensive-check.sh JSON output to Markdown

set -euo pipefail

INPUT_FILE="${1:-/tmp/lokole-verification.json}"
OUTPUT_FILE="${2:-/tmp/pr-comment.md}"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file $INPUT_FILE not found"
    exit 1
fi

# Read JSON data
SUMMARY=$(jq -r '.summary' "$INPUT_FILE")
VM_NAME=$(jq -r '.vm_name' "$INPUT_FILE")
TIMESTAMP=$(jq -r '.timestamp' "$INPUT_FILE")
OS_VERSION=$(jq -r '.system.os_version' "$INPUT_FILE")
OS_CODENAME=$(jq -r '.system.os_codename' "$INPUT_FILE")
PYTHON_VERSION=$(jq -r '.system.python_version' "$INPUT_FILE")
PYTHON_MM=$(jq -r '.system.python_major_minor' "$INPUT_FILE")
HTTP_CODE=$(jq -r '.web_access.http_code' "$INPUT_FILE")
WEB_STATUS=$(jq -r '.web_access.status' "$INPUT_FILE")
PASSED=$(jq -r '.checks.passed' "$INPUT_FILE")
FAILED=$(jq -r '.checks.failed' "$INPUT_FILE")
WARNINGS=$(jq -r '.checks.warnings' "$INPUT_FILE")
TOTAL=$(jq -r '.checks.total' "$INPUT_FILE")

# Determine status emoji and message
if [ "$SUMMARY" = "PASSED" ]; then
    STATUS_EMOJI="✅"
    STATUS_MESSAGE="All checks passed"
elif [ "$SUMMARY" = "WARNING" ]; then
    STATUS_EMOJI="⚠️"
    STATUS_MESSAGE="Some warnings detected"
else
    STATUS_EMOJI="❌"
    STATUS_MESSAGE="Installation failed"
fi

# Start generating comment
cat > "$OUTPUT_FILE" << EOF
## ${STATUS_EMOJI} IIAB-Lokole Integration Test Results

**Status:** ${STATUS_MESSAGE}  
**Ubuntu:** ${OS_VERSION} (${OS_CODENAME})  
**Python:** ${PYTHON_VERSION}  
**VM:** ${VM_NAME}  
**Timestamp:** ${TIMESTAMP}

### 📊 Test Summary

| Status | Count |
|--------|-------|
| ✅ Passed | ${PASSED}/${TOTAL} |
| ❌ Failed | ${FAILED}/${TOTAL} |
| ⚠️ Warnings | ${WARNINGS}/${TOTAL} |

EOF

# Python version assessment
cat >> "$OUTPUT_FILE" << EOF
### 🐍 Python Version

EOF

if [[ "$PYTHON_MM" =~ ^3\.(1[2-9]|[2-9][0-9])$ ]]; then
    cat >> "$OUTPUT_FILE" << EOF
✅ **Python ${PYTHON_VERSION}** - Supported version (3.12+)

EOF
elif [[ "$PYTHON_MM" =~ ^3\.1[01]$ ]]; then
    cat >> "$OUTPUT_FILE" << EOF
⚠️ **Python ${PYTHON_VERSION}** - Older version (3.10-3.11), consider upgrading

EOF
else
    cat >> "$OUTPUT_FILE" << EOF
❌ **Python ${PYTHON_VERSION}** - Unsupported version (requires 3.12+)

EOF
fi

# Services section
cat >> "$OUTPUT_FILE" << EOF
### 🔧 Services

| Service | Status | Details |
|---------|--------|---------|
EOF

SERVICES=("lokole-gunicorn" "lokole-celery-beat" "lokole-celery-worker" "lokole-restarter")
for service in "${SERVICES[@]}"; do
    STATUS=$(jq -r ".services[\"$service\"].status" "$INPUT_FILE")
    PID=$(jq -r ".services[\"$service\"].pid" "$INPUT_FILE")
    UPTIME=$(jq -r ".services[\"$service\"].uptime" "$INPUT_FILE")
    
    case "$STATUS" in
        running)
            EMOJI="✅"
            DETAILS="PID: ${PID}, Uptime: ${UPTIME}"
            ;;
        stopped)
            EMOJI="⚠️"
            DETAILS="Service is stopped"
            ;;
        fatal)
            EMOJI="❌"
            DETAILS="Fatal error"
            ;;
        not_found)
            EMOJI="❌"
            DETAILS="Service not installed"
            ;;
        *)
            EMOJI="❓"
            DETAILS="Unknown status"
            ;;
    esac
    
    echo "| ${service} | ${EMOJI} ${STATUS} | ${DETAILS} |" >> "$OUTPUT_FILE"
done

# Socket permissions section
SOCKET_EXISTS=$(jq -r '.socket.exists' "$INPUT_FILE")
if [ "$SOCKET_EXISTS" = "true" ]; then
    SOCKET_OWNER=$(jq -r '.socket.owner' "$INPUT_FILE")
    SOCKET_GROUP=$(jq -r '.socket.group' "$INPUT_FILE")
    SOCKET_PERMS=$(jq -r '.socket.permissions' "$INPUT_FILE")
    WWW_DATA_OK=$(jq -r '.socket.www_data_in_group' "$INPUT_FILE")
    
    cat >> "$OUTPUT_FILE" << EOF

### 🔌 Socket Configuration

| Check | Status | Details |
|-------|--------|---------|
| Socket exists | ✅ Yes | /var/lib/lokole/gunicorn.sock |
| Owner/Group | ℹ️ | ${SOCKET_OWNER}:${SOCKET_GROUP} |
| Permissions | ℹ️ | ${SOCKET_PERMS} |
EOF
    
    if [ "$WWW_DATA_OK" = "true" ]; then
        echo "| www-data access | ✅ Configured | www-data is in ${SOCKET_GROUP} group |" >> "$OUTPUT_FILE"
    else
        echo "| www-data access | ⚠️ Issue | www-data not in ${SOCKET_GROUP} group |" >> "$OUTPUT_FILE"
    fi
else
    cat >> "$OUTPUT_FILE" << EOF

### 🔌 Socket Configuration

❌ **Socket not found** at /var/lib/lokole/gunicorn.sock

EOF
fi

# Web access section
cat >> "$OUTPUT_FILE" << EOF

### 🌐 Web Access

EOF

case "$WEB_STATUS" in
    accessible)
        cat >> "$OUTPUT_FILE" << EOF
✅ **Accessible** - HTTP ${HTTP_CODE}

The Lokole webapp is responding correctly at http://localhost:8080

EOF
        ;;
    bad_gateway)
        cat >> "$OUTPUT_FILE" << EOF
⚠️ **Bad Gateway** - HTTP ${HTTP_CODE}

NGINX is running but cannot connect to the Lokole backend. Check:
- Gunicorn service status
- Socket permissions
- NGINX configuration

EOF
        ;;
    service_unavailable)
        cat >> "$OUTPUT_FILE" << EOF
⚠️ **Service Unavailable** - HTTP ${HTTP_CODE}

The service is temporarily unavailable. This may be normal during startup.

EOF
        ;;
    connection_failed)
        cat >> "$OUTPUT_FILE" << EOF
❌ **Connection Failed** - HTTP ${HTTP_CODE}

Could not connect to http://localhost:8080. Check:
- NGINX service status
- Port 8080 configuration
- Firewall settings

EOF
        ;;
    *)
        cat >> "$OUTPUT_FILE" << EOF
❓ **Unknown Status** - HTTP ${HTTP_CODE}

Unexpected response code. Further investigation needed.

EOF
        ;;
esac

# Log errors section
NGINX_ERRORS=$(jq -r '.logs.nginx_errors' "$INPUT_FILE")
NGINX_PERM_ERRORS=$(jq -r '.logs.nginx_permission_errors' "$INPUT_FILE")
SUPERVISOR_ERRORS=$(jq -r '.logs.supervisor_errors' "$INPUT_FILE")
LOKOLE_EXCEPTIONS=$(jq -r '.logs.lokole_exceptions' "$INPUT_FILE")

if [ "$NGINX_ERRORS" -gt 0 ] || [ "$SUPERVISOR_ERRORS" -gt 0 ] || [ "$LOKOLE_EXCEPTIONS" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << EOF

<details>
<summary>⚠️ Log Errors Detected (click to expand)</summary>

| Log Type | Error Count | Severity |
|----------|-------------|----------|
EOF
    
    if [ "$NGINX_PERM_ERRORS" -gt 0 ]; then
        echo "| NGINX Permission Errors | ${NGINX_PERM_ERRORS} | ❌ Critical |" >> "$OUTPUT_FILE"
    fi
    if [ "$NGINX_ERRORS" -gt "$NGINX_PERM_ERRORS" ]; then
        echo "| NGINX Other Errors | $((NGINX_ERRORS - NGINX_PERM_ERRORS)) | ⚠️ Warning |" >> "$OUTPUT_FILE"
    fi
    if [ "$SUPERVISOR_ERRORS" -gt 0 ]; then
        echo "| Supervisor Errors | ${SUPERVISOR_ERRORS} | ⚠️ Warning |" >> "$OUTPUT_FILE"
    fi
    if [ "$LOKOLE_EXCEPTIONS" -gt 0 ]; then
        echo "| Lokole Exceptions | ${LOKOLE_EXCEPTIONS} | ⚠️ Warning |" >> "$OUTPUT_FILE"
    fi
    
    cat >> "$OUTPUT_FILE" << EOF

**Note:** Review log files for details:
- NGINX: /var/log/nginx/error.log
- Supervisor: /var/log/supervisor/supervisord.log
- Lokole: /var/log/lokole/*.log

</details>

EOF
fi

# Recommendations section
if [ "$SUMMARY" != "PASSED" ]; then
    cat >> "$OUTPUT_FILE" << EOF

### 🔍 Troubleshooting Steps

EOF
    
    if [ "$FAILED" -gt 0 ]; then
        cat >> "$OUTPUT_FILE" << EOF
1. **Check service status**: \`multipass exec ${VM_NAME} -- supervisorctl status\`
2. **Review IIAB logs**: \`multipass exec ${VM_NAME} -- sudo journalctl -u iiab-*\`
3. **Verify Lokole installation**: \`multipass exec ${VM_NAME} -- pip3 list | grep opwen\`
4. **Check NGINX configuration**: \`multipass exec ${VM_NAME} -- sudo nginx -t\`

EOF
    fi
    
    if [ "$NGINX_PERM_ERRORS" -gt 0 ]; then
        cat >> "$OUTPUT_FILE" << EOF
**Socket Permission Fix:**
\`\`\`bash
multipass exec ${VM_NAME} -- sudo usermod -a -G lokole www-data
multipass exec ${VM_NAME} -- sudo systemctl restart nginx
\`\`\`

EOF
    fi
fi

# Footer
cat >> "$OUTPUT_FILE" << EOF

---

<sub>Generated by [iiab-lokole-tests](https://github.com/ascoderu/iiab-lokole-tests) | ${TIMESTAMP}</sub>
EOF

echo "PR comment generated: $OUTPUT_FILE"

# Display summary to console
echo ""
echo "Comment Preview:"
echo "================"
head -20 "$OUTPUT_FILE"
echo "..."
echo "================"
echo ""
echo "Full comment saved to: $OUTPUT_FILE"
