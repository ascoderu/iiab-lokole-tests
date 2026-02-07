#!/bin/bash
# Comprehensive verification for Lokole installation
# Outputs JSON report for CI/CD and PR commenting
# Supports Python 3.12, 3.13, 3.14+

set -euo pipefail

# Configuration
VM_NAME="${1:-}"
OUTPUT_FILE="${2:-/tmp/lokole-verification.json}"
LOKOLE_URL="http://localhost/lokole/"

if [ -z "$VM_NAME" ]; then
    echo "Usage: $0 <vm_name> [output_file]"
    exit 1
fi

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Print functions
print_pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; }
print_fail() { echo -e "${RED}❌ FAIL${NC}: $1"; }
print_warn() { echo -e "${YELLOW}⚠️  WARN${NC}: $1"; }
print_info() { echo -e "${BLUE}ℹ️  INFO${NC}: $1"; }
print_header() { echo -e "\n${BOLD}${BLUE}═══ $1 ═══${NC}"; }

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
    "ansible": {
        "iiab_complete": false,
        "lokole_role_applied": false,
        "lokole_stage": ""
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

# Check if Ansible installed IIAB and Lokole
check_ansible_status() {
    local iiab_complete=$(vm_exec "[ -f /etc/iiab/install-flags/iiab-complete ] && echo true || echo false")
    local lokole_applied=$(vm_exec "[ -f /etc/iiab/install-flags/lokole-installed ] && echo true || echo false")
    local lokole_stage=$(vm_exec "[ -f /etc/iiab/iiab_state.yml ] && grep lokole_installed /etc/iiab/iiab_state.yml | awk '{print \$2}' || echo 'unknown'")
    
    jq --argjson iiab "$iiab_complete" \
       --argjson lokole "$lokole_applied" \
       --arg stage "$lokole_stage" \
       '.ansible.iiab_complete = $iiab |
        .ansible.lokole_role_applied = $lokole |
        .ansible.lokole_stage = $stage' \
       "$OUTPUT_FILE" > "$OUTPUT_FILE.tmp" && mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
}

# Check individual service status
check_service() {
    local service_name="$1"
    local status=$(timeout 10 multipass exec "$VM_NAME" -- sudo supervisorctl status "$service_name" 2>/dev/null || echo "")
    
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
    local services=("lokole_gunicorn" "lokole_celery_beat" "lokole_celery_worker" "lokole_restarter")
    for service in "${services[@]}"; do
        check_service "$service"
    done
}

# Check socket permissions
check_socket() {
    local socket_path="/home/lokole/state/lokole_gunicorn.sock"
    local exists=$(timeout 10 multipass exec "$VM_NAME" -- sudo bash -c "[ -S $socket_path ] && echo true || echo false" 2>/dev/null || echo "false")
    
    if [ "$exists" = "true" ]; then
        local owner=$(timeout 10 multipass exec "$VM_NAME" -- sudo stat -c '%U' "$socket_path" 2>/dev/null || echo "")
        local group=$(timeout 10 multipass exec "$VM_NAME" -- sudo stat -c '%G' "$socket_path" 2>/dev/null || echo "")
        local perms=$(timeout 10 multipass exec "$VM_NAME" -- sudo stat -c '%a' "$socket_path" 2>/dev/null || echo "")
        local www_data_check=$(timeout 10 multipass exec "$VM_NAME" -- sudo bash -c "getent group lokole | grep -q www-data && echo true || echo false" 2>/dev/null || echo "false")
        
        # Ensure www_data_check is a valid boolean
        [[ "$www_data_check" != "true" && "$www_data_check" != "false" ]] && www_data_check="false"
        
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
    
    # Ensure response_time is a valid number
    [[ ! "$response_time" =~ ^[0-9]+$ ]] && response_time=0
    
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
    
    # Ensure all values are numbers (defaulting to 0 if empty or invalid)
    nginx_errors=${nginx_errors:-0}
    nginx_perm_errors=${nginx_perm_errors:-0}
    supervisor_errors=${supervisor_errors:-0}
    lokole_exceptions=${lokole_exceptions:-0}
    
    # Strip any whitespace
    nginx_errors=$(echo "$nginx_errors" | tr -d '[:space:]')
    nginx_perm_errors=$(echo "$nginx_perm_errors" | tr -d '[:space:]')
    supervisor_errors=$(echo "$supervisor_errors" | tr -d '[:space:]')
    lokole_exceptions=$(echo "$lokole_exceptions" | tr -d '[:space:]')
    
    # Validate they're numbers
    [[ ! "$nginx_errors" =~ ^[0-9]+$ ]] && nginx_errors=0
    [[ ! "$nginx_perm_errors" =~ ^[0-9]+$ ]] && nginx_perm_errors=0
    [[ ! "$supervisor_errors" =~ ^[0-9]+$ ]] && supervisor_errors=0
    [[ ! "$lokole_exceptions" =~ ^[0-9]+$ ]] && lokole_exceptions=0
    
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
    
    # Ansible checks (2 checks: iiab complete + lokole role applied)
    # Note: For minimal installs (stage 1-3), these flags may not exist
    # Treat as warnings rather than failures
    total=$((total + 1))
    local iiab_complete=$(jq -r '.ansible.iiab_complete' "$OUTPUT_FILE")
    if [ "$iiab_complete" = "true" ]; then
        passed=$((passed + 1))
    else
        warnings=$((warnings + 1))
    fi
    
    total=$((total + 1))
    local lokole_applied=$(jq -r '.ansible.lokole_role_applied' "$OUTPUT_FILE")
    if [ "$lokole_applied" = "true" ]; then
        passed=$((passed + 1))
    else
        warnings=$((warnings + 1))
    fi
    
    # Service checks (4 services)
    local services=(lokole_gunicorn lokole_celery_beat lokole_celery_worker lokole_restarter)
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
    print_header "COMPREHENSIVE VERIFICATION FOR $VM_NAME"
    
    # Initialize
    init_json
    
    # Add timestamp and VM name
    jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       --arg vm "$VM_NAME" \
       '.timestamp = $ts | .vm_name = $vm' \
       "$OUTPUT_FILE" > "$OUTPUT_FILE.tmp" && mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
    
    # Run all checks
    print_header "SYSTEM INFORMATION"
    get_system_info
    local py_version=$(jq -r '.system.python_version' "$OUTPUT_FILE")
    local os_version=$(jq -r '.system.os_version' "$OUTPUT_FILE")
    print_info "OS: Ubuntu $os_version"
    print_info "Python: $py_version"
    if [[ "$py_version" =~ ^3\.(1[2-9]|[2-9][0-9]) ]]; then
        print_pass "Python version is 3.12+"
    else
        print_fail "Python version should be 3.12+ (found $py_version)"
    fi
    
    print_header "ANSIBLE ROLE STATUS"
    check_ansible_status
    local iiab_complete=$(jq -r '.ansible.iiab_complete' "$OUTPUT_FILE")
    local lokole_applied=$(jq -r '.ansible.lokole_role_applied' "$OUTPUT_FILE")
    if [ "$iiab_complete" = "true" ]; then
        print_pass "IIAB installation completed"
    else
        print_warn "IIAB installation flag not found (OK for minimal installs)"
    fi
    if [ "$lokole_applied" = "true" ]; then
        print_pass "Lokole role applied by Ansible"
    else
        print_warn "Lokole role install flag not found (OK for minimal installs)"
    fi
    
    print_header "SERVICE STATUS"
    check_all_services
    for service in lokole_gunicorn lokole_celery_beat lokole_celery_worker lokole_restarter; do
        local state=$(jq -r ".services[\"$service\"].status" "$OUTPUT_FILE")
        case "$state" in
            running)
                local pid=$(jq -r ".services[\"$service\"].pid" "$OUTPUT_FILE")
                print_pass "$service is running (PID: $pid)"
                ;;
            stopped) print_warn "$service is stopped" ;;
            fatal) print_fail "$service has fatal error" ;;
            not_found) print_fail "$service not found in supervisor" ;;
            *) print_warn "$service status unknown: $state" ;;
        esac
    done
    
    print_header "SOCKET PERMISSIONS"
    check_socket
    local socket_exists=$(jq -r '.socket.exists' "$OUTPUT_FILE")
    if [ "$socket_exists" = "true" ]; then
        print_pass "Gunicorn socket exists"
        local owner=$(jq -r '.socket.owner' "$OUTPUT_FILE")
        local group=$(jq -r '.socket.group' "$OUTPUT_FILE")
        local perms=$(jq -r '.socket.permissions' "$OUTPUT_FILE")
        print_info "Owner: $owner, Group: $group, Perms: $perms"
        local www_data_check=$(jq -r '.socket.www_data_in_group' "$OUTPUT_FILE")
        if [ "$www_data_check" = "true" ]; then
            print_pass "www-data is in $group group (PR #4259 fix working)"
        else
            print_fail "www-data is NOT in $group group"
        fi
    else
        print_fail "Gunicorn socket not found at /home/lokole/state/lokole_gunicorn.sock"
    fi
    
    print_header "WEB ACCESS TEST"
    check_web_access
    local http_code=$(jq -r '.web_access.http_code' "$OUTPUT_FILE")
    local web_status=$(jq -r '.web_access.status' "$OUTPUT_FILE")
    case "$web_status" in
        accessible) print_pass "Web interface accessible (HTTP $http_code)" ;;
        bad_gateway) print_fail "Bad gateway (HTTP $http_code) - Gunicorn not responding" ;;
        service_unavailable) print_fail "Service unavailable (HTTP $http_code)" ;;
        connection_failed) print_fail "Connection failed - nginx may not be running" ;;
        *) print_warn "Unknown web status: $web_status (HTTP $http_code)" ;;
    esac
    
    print_header "LOG ANALYSIS"
    analyze_logs
    local nginx_errors=$(jq -r '.logs.nginx_errors' "$OUTPUT_FILE")
    local nginx_perm=$(jq -r '.logs.nginx_permission_errors' "$OUTPUT_FILE")
    local supervisor_errors=$(jq -r '.logs.supervisor_errors' "$OUTPUT_FILE")
    print_info "Nginx errors: $nginx_errors (permission: $nginx_perm)"
    print_info "Supervisor errors: $supervisor_errors"
    if [ "$nginx_perm" -eq 0 ]; then
        print_pass "No nginx permission errors"
    else
        print_fail "Found $nginx_perm nginx permission errors"
    fi
    
    print_header "CALCULATING RESULTS"
    calculate_checks
    
    echo "Verification complete. Results saved to $OUTPUT_FILE"
    
    # Display summary
    local summary=$(jq -r '.summary' "$OUTPUT_FILE")
    local passed=$(jq -r '.checks.passed' "$OUTPUT_FILE")
    local failed=$(jq -r '.checks.failed' "$OUTPUT_FILE")
    local warnings=$(jq -r '.checks.warnings' "$OUTPUT_FILE")
    local total=$(jq -r '.checks.total' "$OUTPUT_FILE")
    
    print_header "FINAL SUMMARY"
    case "$summary" in
        PASSED)
            echo -e "${GREEN}${BOLD}✅ ALL CHECKS PASSED${NC}"
            ;;
        FAILED)
            echo -e "${RED}${BOLD}❌ VERIFICATION FAILED${NC}"
            ;;
        WARNING)
            echo -e "${YELLOW}${BOLD}⚠️  VERIFICATION PASSED WITH WARNINGS${NC}"
            ;;
    esac
    echo -e "  ${GREEN}Passed:   $passed/$total${NC}"
    echo -e "  ${RED}Failed:   $failed/$total${NC}"
    echo -e "  ${YELLOW}Warnings: $warnings/$total${NC}"
    echo ""
    
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
