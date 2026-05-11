#!/bin/bash
# Installation Verification Script
# Usage: ./verify-installation.sh [OPTIONS]
# Options:
#   --vm-name NAME              VM name (default: iiab-lokole-test)
#   --output-file PATH          Path to save report (default: test-report.txt)

set -e

VM_NAME="iiab-lokole-test"
OUTPUT_FILE="test-report.txt"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --vm-name)
            VM_NAME="$2"
            shift 2
            ;;
        --output-file)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "🔍 Verifying Lokole services on ${VM_NAME}"
echo "==============================================================================="

echo "📊 System Information Check..."
multipass exec ${VM_NAME} -- bash -c '
echo "=== SYSTEM INFO ==="
cat /etc/os-release | grep -E "^(NAME|VERSION)"
echo ""
echo "Python Version: $(python3 --version)"
echo "Python Path: $(which python3)"
echo ""
'

echo "🔐 Checking socket permissions..."
multipass exec ${VM_NAME} -- bash -c '
echo "=== SOCKET PERMISSION VERIFICATION ==="
echo "1. Checking if www-data is in lokole group:"
if groups www-data 2>/dev/null | grep -q lokole || groups apache 2>/dev/null | grep -q lokole; then
    echo "✅ Web server user is in lokole group - SOCKET FIX WORKING"
else
    echo "❌ Web server user NOT in lokole group - SOCKET FIX FAILED"
fi
echo ""

echo "2. Checking lokole home directory permissions:"
if [ -d /home/lokole ]; then
    ls -ld /home/lokole
else
    echo "⚠️  /home/lokole directory not found"
fi
echo ""

echo "3. Checking gunicorn TCP port:"
if ss -tlnp 2>/dev/null | grep -q ":8084"; then
    echo "✅ Gunicorn listening on TCP port 8084"
    ss -tlnp 2>/dev/null | grep ":8084"
else
    echo "⚠️  Gunicorn not listening on port 8084 (service may not be started)"
fi
echo ""
'

echo "🐍 Checking Python version in Lokole environment..."
multipass exec ${VM_NAME} -- bash -c '
echo "=== PYTHON VERSION VERIFICATION ==="
if [ -f /library/lokole/venv/bin/python ]; then
    echo "Lokole Python environment:"
    sudo -u lokole /library/lokole/venv/bin/python --version
    echo ""
    echo "Key dependencies:"
    sudo -u lokole /library/lokole/venv/bin/pip list | grep -E "(Pillow|celery|Babel|Flask)" | head -10
else
    echo "⚠️  Lokole venv not found at /library/lokole/venv"
fi
echo ""
'

echo "📈 Checking Lokole systemd services..."
multipass exec ${VM_NAME} -- bash -c '
echo "=== LOKOLE SERVICES STATUS ==="
echo "Systemd services:"
sudo systemctl status lokole-gunicorn.service lokole-celery-beat.service lokole-celery-worker.service lokole-restarter.service --no-pager | grep -E "(Loaded|Active|Main PID)" || echo "No lokole services found in systemd"
echo ""
'

echo "🌐 Testing web access..."
multipass exec ${VM_NAME} -- bash -c '
echo "=== WEB ACCESS VERIFICATION ==="
echo "1. Testing lokole web access:"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/lokole/ || echo "000")
echo "HTTP Response Code: $HTTP_CODE"

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ HTTP 200 - Web access successful"
elif [ "$HTTP_CODE" = "502" ]; then
    echo "❌ HTTP 502 Bad Gateway - Socket issue detected"
elif [ "$HTTP_CODE" = "000" ]; then
    echo "⚠️  Connection failed - service may not be running yet"
else
    echo "⚠️  Unexpected HTTP code: $HTTP_CODE"
fi
echo ""

echo "2. NGINX error log check:"
if sudo tail -20 /var/log/nginx/error.log 2>/dev/null | grep -i "permission denied"; then
    echo "❌ Found permission denied errors in NGINX log"
else
    echo "✅ No permission denied errors in NGINX log"
fi
echo ""
'

echo "📝 Generating test report..."
multipass exec ${VM_NAME} -- bash -c '
echo "=== TEST REPORT ==="
echo "Date: $(date)"
echo "System: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d \")"
echo "Python: $(python3 --version)"
echo ""

echo "Socket Fix Status:"
if groups www-data 2>/dev/null | grep -q lokole || groups apache 2>/dev/null | grep -q lokole; then
    echo "  ✅ Web server user in lokole group"
else  
    echo "  ❌ Web server user not in lokole group"
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/lokole/ || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo "  ✅ HTTP 200 response"
elif [ "$HTTP_CODE" = "502" ]; then
    echo "  ❌ HTTP 502 Bad Gateway error"
else
    echo "  ⚠️  HTTP $HTTP_CODE"
fi

echo ""
echo "Lokole Python Environment:"
if [ -f /library/lokole/venv/bin/python ]; then
    LOKOLE_PYTHON=$(sudo -u lokole /library/lokole/venv/bin/python --version 2>&1)
    echo "  ✅ $LOKOLE_PYTHON"
else
    echo "  ❌ Python environment not found"
fi

SERVICES=$(sudo systemctl is-active lokole-gunicorn.service lokole-celery-beat.service lokole-celery-worker.service lokole-restarter.service 2>/dev/null | grep -c "^active$")
echo "  📊 Lokole services running: $SERVICES/4 expected"

echo ""
echo "Overall Status:"
if groups www-data 2>/dev/null | grep -q lokole && [ "$HTTP_CODE" = "200" ]; then
    echo "  🎉 ALL CHECKS PASSED"
else
    echo "  ⚠️  Issues detected - see details above"
fi
' > /tmp/test-report.txt

# Copy report to host
multipass transfer ${VM_NAME}:/tmp/test-report.txt ./${OUTPUT_FILE}

echo ""
echo "✅ Verification complete! Test report saved to ${OUTPUT_FILE}"
echo ""
echo "📄 Test Report Summary:"
cat ./${OUTPUT_FILE}
