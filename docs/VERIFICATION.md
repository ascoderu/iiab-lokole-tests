# Comprehensive Verification System

This document describes the comprehensive verification system that validates Lokole installations on IIAB.

## Overview

The verification system consists of two main components:

1. **comprehensive-check.sh** - Performs detailed checks and outputs JSON
2. **generate-pr-comment.sh** - Converts JSON to formatted Markdown for PR comments

## comprehensive-check.sh

Located at: `scripts/verify/comprehensive-check.sh`

### Usage

```bash
./scripts/verify/comprehensive-check.sh <vm_name> [output_file]
```

**Example:**
```bash
./scripts/verify/comprehensive-check.sh iiab-lokole-test /tmp/verification.json
```

### What It Checks

#### 1. System Information
- OS version (Ubuntu 22.04, 24.04, 26.04+)
- OS codename (jammy, noble, etc.)
- Kernel version
- Python version (full: 3.12.3, major.minor: 3.12)

#### 2. Service Status
Checks all 4 Lokole services individually:
- **lokole-gunicorn** - Web application server
- **lokole-celery-beat** - Task scheduler
- **lokole-celery-worker** - Background job processor
- **lokole-restarter** - Auto-restart monitor

For each service:
- Status: running/stopped/fatal/not_found/error
- PID (if running)
- Uptime (if running)

#### 3. Socket Permissions
- Socket existence: `/var/lib/lokole/gunicorn.sock`
- Owner and group
- Permissions (octal)
- www-data group membership check

#### 4. Web Access
- HTTP response code (200/502/503/000)
- Response time in milliseconds
- Status interpretation

#### 5. Log Analysis
Scans logs for errors:
- NGINX error count
- NGINX permission denial count
- Supervisor error count
- Lokole exception count

#### 6. Check Summary
- Total checks performed
- Passed checks
- Failed checks
- Warning checks
- Overall summary: PASSED/WARNING/FAILED

### Output Format

JSON structure:
```json
{
    "timestamp": "2026-02-06T15:30:00Z",
    "vm_name": "iiab-lokole-test-20260206-153000",
    "system": {
        "os_version": "26.04",
        "os_codename": "unreleased",
        "kernel": "6.11.0-13-generic",
        "python_version": "3.13.11",
        "python_major_minor": "3.13"
    },
    "services": {
        "lokole-gunicorn": {
            "status": "running",
            "pid": "1234",
            "uptime": "0:05:23"
        }
    },
    "socket": {
        "exists": true,
        "owner": "lokole",
        "group": "lokole",
        "permissions": "660",
        "www_data_in_group": true
    },
    "web_access": {
        "http_code": "200",
        "status": "accessible",
        "response_time_ms": 145
    },
    "logs": {
        "nginx_errors": 2,
        "nginx_permission_errors": 0,
        "supervisor_errors": 0,
        "lokole_exceptions": 0
    },
    "checks": {
        "total": 9,
        "passed": 8,
        "failed": 0,
        "warnings": 1
    },
    "summary": "PASSED"
}
```

### Exit Codes

- **0**: All checks passed or warnings only
- **1**: One or more checks failed

## generate-pr-comment.sh

Located at: `scripts/verify/generate-pr-comment.sh`

### Usage

```bash
./scripts/verify/generate-pr-comment.sh <json_input> [markdown_output]
```

**Example:**
```bash
./scripts/verify/generate-pr-comment.sh /tmp/verification.json /tmp/pr-comment.md
```

### Output Features

The generated Markdown includes:

#### Header with Overall Status
- ✅ for PASSED
- ⚠️ for WARNING  
- ❌ for FAILED

#### System Information
- Ubuntu version and codename
- Python version with compatibility assessment
- VM name and timestamp

#### Check Summary Table
Pass/fail/warning counts in tabular format

#### Python Version Assessment
- ✅ Python 3.12+ (supported)
- ⚠️ Python 3.10-3.11 (older, recommend upgrade)
- ❌ Python <3.10 (unsupported)

#### Service Status Table
All services with status icons and details

#### Socket Configuration
Socket existence, permissions, and www-data access

#### Web Access
HTTP status with interpretation and troubleshooting hints

#### Log Errors (Collapsible)
Expandable section with error counts and severity when errors detected

#### Troubleshooting Steps
Auto-generated based on failure types:
- Service issues → Check supervisorctl
- Permission issues → usermod commands
- Web issues → NGINX configuration

### Example Output

```markdown
## ✅ IIAB-Lokole Integration Test Results

**Status:** All checks passed  
**Ubuntu:** 24.04 (noble)  
**Python:** 3.12.3  
**VM:** iiab-lokole-test-20260206-153000  
**Timestamp:** 2026-02-06T15:30:00Z

### 📊 Test Summary

| Status | Count |
|--------|-------|
| ✅ Passed | 8/9 |
| ❌ Failed | 0/9 |
| ⚠️ Warnings | 1/9 |

### 🐍 Python Version

✅ **Python 3.12.3** - Supported version (3.12+)

### 🔧 Services

| Service | Status | Details |
|---------|--------|---------|
| lokole-gunicorn | ✅ running | PID: 1234, Uptime: 0:05:23 |
| lokole-celery-beat | ✅ running | PID: 1235, Uptime: 0:05:20 |
| lokole-celery-worker | ✅ running | PID: 1236, Uptime: 0:05:18 |
| lokole-restarter | ⚠️ stopped | Service is stopped |

...
```

## Integration with Test Scenarios

The comprehensive verification is automatically called by test scenarios:

### fresh-install.sh
```bash
# Run comprehensive verification
${ROOT_DIR}/scripts/verify/comprehensive-check.sh ${VM_NAME} ${JSON_REPORT}

# Generate markdown PR comment
${ROOT_DIR}/scripts/verify/generate-pr-comment.sh ${JSON_REPORT} ${MD_REPORT}
```

### test-pr-branch.sh
Inherits comprehensive verification from `fresh-install.sh`

## GitHub Actions Integration

### Workflow Usage

Workflows automatically:
1. Run comprehensive verification
2. Upload JSON/Markdown/Text reports as artifacts
3. Post formatted comment to PR (test-on-pr-label.yml)
4. Create detailed issue on failure (test-ubuntu-lts.yml)

### Matrix Testing

All PR tests run across multiple Ubuntu versions:
- **22.04** (Python 3.10)
- **24.04** (Python 3.12)
- **26.04** (Python 3.13+, daily images)

Each matrix job posts a separate comment with its results.

## Python Version Support

### Current Support Matrix

| Python Version | Ubuntu | Support Status |
|----------------|--------|----------------|
| 3.10           | 22.04  | ✅ Supported |
| 3.11           | -      | ⚠️ Not in LTS but supported |
| 3.12           | 24.04  | ✅ Supported (recommended) |
| 3.13           | 26.04  | ✅ Supported (pre-release) |
| 3.14           | 26.04  | 🔮 Future (auto-supported) |

### Detection Logic

```bash
# Python version check
local py_version=$(jq -r '.system.python_major_minor' "$OUTPUT_FILE")
if [[ "$py_version" =~ ^3\.(1[2-9]|[2-9][0-9])$ ]]; then
    # Matches 3.12-3.99 (3.12+)
    passed=$((passed + 1))
else
    failed=$((failed + 1))
fi
```

This regex ensures automatic support for Python 3.14, 3.15, and beyond.

## Local Testing

### Quick Test
```bash
cd iiab-lokole-tests/

# Create VM and install
./scripts/scenarios/fresh-install.sh --ubuntu-version 24.04

# View JSON report
cat /tmp/lokole-verification-*.json | jq

# View Markdown report
cat /tmp/pr-comment-*.md
```

### Testing Specific Python Versions
```bash
# Python 3.10 (Ubuntu 22.04)
./scripts/scenarios/fresh-install.sh --ubuntu-version 22.04

# Python 3.12 (Ubuntu 24.04)
./scripts/scenarios/fresh-install.sh --ubuntu-version 24.04

# Python 3.13+ (Ubuntu 26.04 daily)
./scripts/scenarios/fresh-install.sh --ubuntu-version 26.04 --use-daily
```

## Troubleshooting

### JSON Report Not Generated

**Symptom**: No JSON file after test
**Cause**: comprehensive-check.sh failed early
**Solution**: 
```bash
# Run with debugging
bash -x scripts/verify/comprehensive-check.sh <vm_name> /tmp/test.json
```

### Wrong Python Version Detected

**Symptom**: Python version doesn't match expected
**Cause**: Multiple Python versions installed
**Solution**: Check `python3 --version` in VM:
```bash
multipass exec <vm_name> -- python3 --version
```

### Services Show as not_found

**Symptom**: All services report "not_found"
**Cause**: Supervisor not installed or Lokole installation failed
**Solution**: Check IIAB installation logs:
```bash
multipass exec <vm_name> -- sudo journalctl -u iiab-install
```

### Permission Errors in Logs

**Symptom**: nginx_permission_errors > 0
**Cause**: www-data not in lokole group
**Solution**: Auto-suggested in PR comment:
```bash
multipass exec <vm_name> -- sudo usermod -a -G lokole www-data
multipass exec <vm_name> -- sudo systemctl restart nginx
```

## Future Enhancements

- [ ] Add Celery task queue depth check
- [ ] Monitor memory usage of services
- [ ] Check email send/receive functionality
- [ ] Validate SSL certificate if HTTPS enabled
- [ ] Test offline sync functionality
- [ ] Benchmark web response times
- [ ] Add database integrity checks

## See Also

- [SETUP.md](SETUP.md) - Repository setup
- [WEBHOOKS.md](WEBHOOKS.md) - Cross-repository integration
- [README.md](../README.md) - Main documentation
