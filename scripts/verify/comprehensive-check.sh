#!/bin/bash
# Comprehensive verification for Lokole installation
# Outputs JSON report for CI/CD and PR commenting
# Supports Python 3.12, 3.13, 3.14+

set -euo pipefail

# Configuration
VM_NAME="${1:-}"
OUTPUT_FILE="${2:-/tmp/lokole-verification.json}"
LOKOLE_URL="http://localhost:8080"

if [ -z "$VM_NAME" ]; then
    echo "Usage: $0 <vm_name> [output_file]"
    exit 1
fi

# Initialize JSON structure
init_json() {
    cat > "$OUTPUT_FILE" << 'EOF'
{
    "timestamp": "",
    "vm_name": "",
    "system": {
        "os_version": "",
        "os_codename": "",
        "kernel": "",
        "python_version": "",
        "python_major_minor": ""
    },
    "services": {},
    "socket": {
        "exists": false,
        "owner": "",
        "group": "",
        "permissions": "",
        "www_data_in_group": false
    },
    "web_access": {
        "http_code": "",
        "status": "",
        "response_time_ms": 0
    },
    "logs": {
        "nginx_errors": 0,
        "nginx_permission_errors": 0,
        "supervisor_errors": 0,
        "lokole_exceptions": 0
    },
    "checks": {
        "total": 0,
        "passed": 0,
        "failed": 0,
        "warnings": 0
    },
    "summary": ""
}
EOF
}

# Execute command in VM
vm_exec() {
    multipass exec "$VM_NAME" -- bash -c "$1" 2>/dev/null || echo ""
}

# Get system information
get_system_info() {
    local os_version=$(vm_exec "grep VERSION_ID /etc/os-release | cut -d= -f2 | tr -d '\"'")
    local os_codename=$(vm_exec "grep VERSION_CODENAME /etc/os-release | cut -d= -f2 | tr -d '\"'")
    local kernel=$(vm_exec "uname -r")
    local python_full=$(vm_exec "python3 --version 2>&1 | grep -oP 'Python \K[0-9.]+' || echo 'unknown'")
    local python_major_minor=$(echo "$python_full" | grep -oP '^[0-9]+\.[0-9]+' || echo "unknown")

    jq --arg os "$os_version" \
       --arg codename "$os_codename" \
       --arg kernel "$kernel" \
       --arg pyfull "$python_full" \
       --arg pymm "$python_major_minor" \
       '.system.os_version = $os |
        .system.os_codename = $codename |
        .system.kernel = $kernel |
        .system.python_version = $pyfull |
        .system.python_major_minor = $pymm' \
       "$OUTPUT_FILE" > "$OUTPUT_FILE.tmp" && mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
}

# Check individual service status
check_service() {
    local service_name="$1"
    local status=$(vm_exec "supervisorctl status $service_name 2>&1")
    
    local state="unknown"
    local pid=""
    local uptime=""
    
    if echo "$status" | grep -q "RUNNING"; then
        state="running"
        pid=$(echo "$status" | grep -oP 'pid \K[0-9]+' || echo "")
        uptime=$(echo "$status" | grep -oP 'uptime \K[^,]+' || echo "")
    elif echo "$status" | grep -q "STOPPED"; then
        state="stopped"
    elif echo "$status" | grep -q "FATAL"; then
        state="fatal"
    elif echo "$status" | grep -q "no such process"; then
        state="not_found"
    elif echo "$status" | grep -q "ERROR"; then
        state="error"
    fi
    
    jq --arg name "$service_name" \
       --arg state "$state" \
       --arg pid "$pid" \
       --arg uptime "$uptime" \
       '.services[$name] = {
           "status": $state,
           "pid": $pid,
           "uptime": $uptime
       }' \
       "$OUTPUT_FILE" > "$OUTPUT_FILE.tmp" && mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
}

# Check all Lokole services
check_all_services() {
    local services=("lokole-gunicorn" "lokole-celery-beat" "lokole-celery-worker" "lokole-restarter")
    for service in "${services[@]}"; do
        check_service "$service"
    done
}

# Check socket permissions
check_socket() {
    local socket_path="/var/lib/lokole/gunicorn.sock"
    local exists=$(vm_exec "[ -S $socket_path ] && echo true || echo false")
    
    if [ "$exists" = "true" ]; then
        local owner=$(vm_exec "stat -c '%U' $socket_path")
        local group=$(vm_exec "stat -c '%G' $socket_path")
        local perms=$(vm_exec "stat -c '%a' $socket_path")
        local www_data_check=$(vm_exec "groups www-data | grep -q $group && echo true || echo false")
        
        jq --argjson exists true \
           --arg owner "$owner" \
           --arg group "$group" \
           --arg perms "$perms" \
           --argjson www_data "$www_data_check" \
           '.socket.exists = $exists |
            .socket.owner = $owner |
            .socket.group = $group |
            .socket.permissions = $perms |
            .socket.www_data_in_group = $www_data' \
           "$OUTPUT_FILE" > "$OUTPUT_FILE.tmp" && mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
    else
        jq '.socket.exists = false' \
           "$OUTPUT_FILE" > "$OUTPUT_FILE.tmp" && mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
    fi
}

# Check web access
check_web_access() {
    local start_time=$(date +%s%3N)
    local http_response=$(vm_exec "curl -s -o /dev/null -w '%{http_code}' --max-time 5 $LOKOLE_URL")
    local end_time=$(date +%s%3N)
    local response_time=$((end_time - start_time))
    
    local status="unknown"
    case "$http_response" in
        200) status="accessible" ;;
        502) status="bad_gateway" ;;
        503) status="service_unavailable" ;;
        000) status="connection_failed" ;;
        *) status="error" ;;
    esac
    
    jq --arg code "$http_response" \
       --arg status "$status" \
       --argjson time "$response_time" \
       '.web_access.http_code = $code |
        .web_access.status = $status |
        .web_access.response_time_ms = $time' \
       "$OUTPUT_FILE" > "$OUTPUT_FILE.tmp" && mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
}

# Analyze logs for errors
analyze_logs() {
    local nginx_errors=$(vm_exec "grep -c 'error' /var/log/nginx/error.log 2>/dev/null || echo 0")
    local nginx_perm_errors=$(vm_exec "grep -c 'Permission denied' /var/log/nginx/error.log 2>/dev/null || echo 0")
    local supervisor_errors=$(vm_exec "grep -c 'ERROR' /var/log/supervisor/supervisord.log 2>/dev/null || echo 0")
    local lokole_exceptions=$(vm_exec "grep -c 'Exception' /var/log/lokole/*.log 2>/dev/null || echo 0")
    
    jq --argjson nginx "$nginx_errors" \
       --argjson nginx_perm "$nginx_perm_errors" \
       --argjson supervisor "$supervisor_errors" \
       --argjson lokole "$lokole_exceptions" \
       '.logs.nginx_errors = $nginx |
        .logs.nginx_permission_errors = $nginx_perm |
        .logs.supervisor_errors = $supervisor |
        .logs.lokole_exceptions = $lokole' \
       "$OUTPUT_FILE" > "$OUTPUT_FILE.tmp" && mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
}

# Calculate check results
calculate_checks() {
    local total=0
    local passed=0
    local failed=0
    local warnings=0
    
    # Python version check
    total=$((total + 1))
    local py_version=$(jq -r '.system.python_major_minor' "$OUTPUT_FILE")
    if [[ "$py_version" =~ ^3\.(1[2-9]|[2-9][0-9])$ ]]; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fi
    
    # Service checks (4 services)
    local services=(lokole-gunicorn lokole-celery-beat lokole-celery-worker lokole-restarter)
    for service in "${services[@]}"; do
        total=$((total + 1))
        local state=$(jq -r ".services[\"$service\"].status" "$OUTPUT_FILE")
        if [ "$state" = "running" ]; then
            passed=$((passed + 1))
        elif [ "$state" = "not_found" ] || [ "$state" = "unknown" ]; then
            failed=$((failed + 1))
        else
            warnings=$((warnings + 1))
        fi
    done
    
    # Socket check
    total=$((total + 1))
    local socket_exists=$(jq -r '.socket.exists' "$OUTPUT_FILE")
    if [ "$socket_exists" = "true" ]; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fi
    
    # Socket permissions check
    total=$((total + 1))
    local www_data_ok=$(jq -r '.socket.www_data_in_group' "$OUTPUT_FILE")
    if [ "$www_data_ok" = "true" ]; then
        passed=$((passed + 1))
    elif [ "$socket_exists" = "true" ]; then
        warnings=$((warnings + 1))
    else
        failed=$((failed + 1))
    fi
    
    # Web access check
    total=$((total + 1))
    local web_status=$(jq -r '.web_access.status' "$OUTPUT_FILE")
    if [ "$web_status" = "accessible" ]; then
        passed=$((passed + 1))
    elif [ "$web_status" = "connection_failed" ]; then
        failed=$((failed + 1))
    else
        warnings=$((warnings + 1))
    fi
    
    # Log error checks
    total=$((total + 1))
    local perm_errors=$(jq -r '.logs.nginx_permission_errors' "$OUTPUT_FILE")
    if [ "$perm_errors" -eq 0 ]; then
        passed=$((passed + 1))
    elif [ "$perm_errors" -lt 5 ]; then
        warnings=$((warnings + 1))
    else
        failed=$((failed + 1))
    fi
    
    # Generate summary
    local summary="PASSED"
    if [ "$failed" -gt 0 ]; then
        summary="FAILED"
    elif [ "$warnings" -gt 2 ]; then
        summary="WARNING"
    fi
    
    jq --argjson total "$total" \
       --argjson passed "$passed" \
       --argjson failed "$failed" \
       --argjson warnings "$warnings" \
       --arg summary "$summary" \
       '.checks.total = $total |
        .checks.passed = $passed |
        .checks.failed = $failed |
        .checks.warnings = $warnings |
        .summary = $summary' \
       "$OUTPUT_FILE" > "$OUTPUT_FILE.tmp" && mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
}

# Main execution
main() {
    echo "Starting comprehensive verification for $VM_NAME"
    
    # Initialize
    init_json
    
    # Add timestamp and VM name
    jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       --arg vm "$VM_NAME" \
       '.timestamp = $ts | .vm_name = $vm' \
       "$OUTPUT_FILE" > "$OUTPUT_FILE.tmp" && mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
    
    # Run all checks
    echo "  Checking system information..."
    get_system_info
    
    echo "  Checking services..."
    check_all_services
    
    echo "  Checking socket permissions..."
    check_socket
    
    echo "  Checking web access..."
    check_web_access
    
    echo "  Analyzing logs..."
    analyze_logs
    
    echo "  Calculating results..."
    calculate_checks
    
    echo "Verification complete. Results saved to $OUTPUT_FILE"
    
    # Display summary
    local summary=$(jq -r '.summary' "$OUTPUT_FILE")
    local passed=$(jq -r '.checks.passed' "$OUTPUT_FILE")
    local failed=$(jq -r '.checks.failed' "$OUTPUT_FILE")
    local warnings=$(jq -r '.checks.warnings' "$OUTPUT_FILE")
    local total=$(jq -r '.checks.total' "$OUTPUT_FILE")
    
    echo ""
    echo "Summary: $summary"
    echo "  Passed:   $passed/$total"
    echo "  Failed:   $failed/$total"
    echo "  Warnings: $warnings/$total"
    
    # Exit with appropriate code
    if [ "$summary" = "FAILED" ]; then
        exit 1
    elif [ "$summary" = "WARNING" ]; then
        exit 0
    else
        exit 0
    fi
}

main "$@"
