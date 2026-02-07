#!/usr/bin/env bash
set -euo pipefail

# Resource Measurement Script for Azure VM Sizing
# Monitors system resources during IIAB test execution to determine optimal Azure VM size

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MEASUREMENT_INTERVAL=5  # seconds between measurements
OUTPUT_DIR="${ROOT_DIR}/results/resource-measurements"
MONITOR_PID=""

# Usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Measure system resources during IIAB integration test execution

OPTIONS:
    --test-scenario SCENARIO    Test scenario to run (default: fresh-install)
    --ubuntu-version VERSION    Ubuntu version to test (22.04, 24.04, 26.04)
    --interval SECONDS         Measurement interval in seconds (default: 5)
    --output-dir DIR           Output directory for results
    --help                     Show this help message

EXAMPLES:
    # Measure resources for Ubuntu 24.04 fresh install
    $0 --test-scenario fresh-install --ubuntu-version 24.04

    # Measure with 10-second intervals
    $0 --ubuntu-version 22.04 --interval 10

EOF
    exit 1
}

# Parse arguments
TEST_SCENARIO="fresh-install"
UBUNTU_VERSION="24.04"

while [[ $# -gt 0 ]]; do
    case $1 in
        --test-scenario)
            TEST_SCENARIO="$2"
            shift 2
            ;;
        --ubuntu-version)
            UBUNTU_VERSION="$2"
            shift 2
            ;;
        --interval)
            MEASUREMENT_INTERVAL="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Output files
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RAW_DATA_FILE="${OUTPUT_DIR}/raw-data-${UBUNTU_VERSION}-${TIMESTAMP}.csv"
SUMMARY_FILE="${OUTPUT_DIR}/summary-${UBUNTU_VERSION}-${TIMESTAMP}.json"
REPORT_FILE="${OUTPUT_DIR}/report-${UBUNTU_VERSION}-${TIMESTAMP}.txt"

echo -e "${BLUE}📊 Resource Measurement Tool${NC}"
echo "========================================================"
echo "Test Scenario: ${TEST_SCENARIO}"
echo "Ubuntu Version: ${UBUNTU_VERSION}"
echo "Measurement Interval: ${MEASUREMENT_INTERVAL}s"
echo "Output Directory: ${OUTPUT_DIR}"
echo "========================================================"
echo ""

# Check dependencies
check_dependencies() {
    local missing=()
    
    for cmd in multipass iostat free nproc; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}❌ Missing dependencies: ${missing[*]}${NC}"
        echo ""
        echo "Install with:"
        echo "  sudo apt-get install -y sysstat procps"
        echo "  sudo snap install multipass"
        exit 1
    fi
}

# Get system baseline
capture_baseline() {
    echo -e "${BLUE}📋 Capturing system baseline...${NC}"
    
    local total_ram=$(free -m | awk '/^Mem:/{print $2}')
    local available_ram=$(free -m | awk '/^Mem:/{print $7}')
    local total_disk=$(df -h / | awk 'NR==2{print $2}')
    local available_disk=$(df -h / | awk 'NR==2{print $4}')
    local cpu_cores=$(nproc)
    local cpu_info=$(lscpu | grep "Model name" | cut -d ':' -f 2 | xargs)
    
    cat > "${OUTPUT_DIR}/baseline-${TIMESTAMP}.txt" << EOF
System Baseline - $(date)
================================================

Host System:
- CPU Cores: ${cpu_cores}
- CPU Model: ${cpu_info}
- Total RAM: ${total_ram} MB
- Available RAM: ${available_ram} MB
- Total Disk: ${total_disk}
- Available Disk: ${available_disk}

Test Configuration:
- Ubuntu Version: ${UBUNTU_VERSION}
- Test Scenario: ${TEST_SCENARIO}
- VM Resources: 2 CPUs, 4096 MB RAM, 15 GB disk

EOF
    
    echo "  ✓ CPU Cores: ${cpu_cores}"
    echo "  ✓ Total RAM: ${total_ram} MB"
    echo "  ✓ Available RAM: ${available_ram} MB"
    echo ""
}

# Background monitoring process
start_monitoring() {
    echo -e "${BLUE}🔬 Starting resource monitoring...${NC}"
    echo "  Interval: ${MEASUREMENT_INTERVAL}s"
    echo "  Output: ${RAW_DATA_FILE}"
    echo ""
    
    # CSV header
    echo "timestamp,cpu_percent,ram_used_mb,ram_percent,disk_used_gb,disk_percent,io_read_kbs,io_write_kbs,net_rx_kbs,net_tx_kbs" > "$RAW_DATA_FILE"
    
    # Background monitoring loop
    (
        while true; do
            local timestamp=$(date +%s)
            
            # CPU usage (1-second sample)
            local cpu_percent=$(top -bn2 -d 1 | grep "Cpu(s)" | tail -1 | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
            
            # Memory usage
            local mem_line=$(free -m | awk '/^Mem:/')
            local ram_used=$(echo "$mem_line" | awk '{print $3}')
            local ram_total=$(echo "$mem_line" | awk '{print $2}')
            local ram_percent=$(awk "BEGIN {printf \"%.1f\", ($ram_used/$ram_total)*100}")
            
            # Disk usage
            local disk_line=$(df -BG / | awk 'NR==2')
            local disk_used=$(echo "$disk_line" | awk '{print $3}' | sed 's/G//')
            local disk_percent=$(echo "$disk_line" | awk '{print $5}' | sed 's/%//')
            
            # Disk I/O (KB/s)
            local io_stats=$(iostat -d -k 1 2 | tail -n 2 | head -n 1)
            local io_read=$(echo "$io_stats" | awk '{print $3}')
            local io_write=$(echo "$io_stats" | awk '{print $4}')
            
            # Network I/O (KB/s) - sum all interfaces
            local net_stats=$(cat /proc/net/dev | tail -n +3 | awk '{rx+=$2; tx+=$10} END {print rx/1024, tx/1024}')
            local net_rx=$(echo "$net_stats" | awk '{print $1}')
            local net_tx=$(echo "$net_stats" | awk '{print $2}')
            
            # Store measurement
            echo "$timestamp,$cpu_percent,$ram_used,$ram_percent,$disk_used,$disk_percent,$io_read,$io_write,$net_rx,$net_tx" >> "$RAW_DATA_FILE"
            
            sleep "$MEASUREMENT_INTERVAL"
        done
    ) &
    
    MONITOR_PID=$!
    echo "  Monitor PID: ${MONITOR_PID}"
}

# Stop monitoring and cleanup
stop_monitoring() {
    if [ -n "$MONITOR_PID" ] && kill -0 "$MONITOR_PID" 2>/dev/null; then
        echo ""
        echo -e "${BLUE}⏹️  Stopping resource monitoring...${NC}"
        kill "$MONITOR_PID" 2>/dev/null || true
        wait "$MONITOR_PID" 2>/dev/null || true
        echo "  ✓ Monitoring stopped"
    fi
}

# Analyze results and generate recommendations
analyze_results() {
    echo ""
    echo -e "${BLUE}📈 Analyzing resource usage...${NC}"
    
    if [ ! -f "$RAW_DATA_FILE" ] || [ $(wc -l < "$RAW_DATA_FILE") -le 1 ]; then
        echo -e "${RED}  ❌ No measurement data collected${NC}"
        return 1
    fi
    
    # Calculate statistics using awk
    local stats=$(awk -F',' '
        NR > 1 {
            count++
            cpu_sum += $2; cpu_max = ($2 > cpu_max ? $2 : cpu_max)
            ram_sum += $3; ram_max = ($3 > ram_max ? $3 : ram_max)
            ram_pct_sum += $4; ram_pct_max = ($4 > ram_pct_max ? $4 : ram_pct_max)
            disk_sum += $5; disk_max = ($5 > disk_max ? $5 : disk_max)
            io_read_sum += $7; io_read_max = ($7 > io_read_max ? $7 : io_read_max)
            io_write_sum += $8; io_write_max = ($8 > io_write_max ? $8 : io_write_max)
        }
        END {
            printf "%.1f %.1f %.0f %.0f %.1f %.1f %.0f %.0f %.0f %.0f %d",
                cpu_sum/count, cpu_max,
                ram_sum/count, ram_max,
                ram_pct_sum/count, ram_pct_max,
                disk_sum/count, disk_max,
                io_read_sum/count, io_read_max,
                count
        }
    ' "$RAW_DATA_FILE")
    
    read -r cpu_avg cpu_peak ram_avg ram_peak ram_pct_avg ram_pct_peak disk_avg disk_peak io_read_avg io_read_peak sample_count <<< "$stats"
    
    # Determine Azure VM recommendations
    local recommended_vm="Standard_B2s"
    local recommended_spot_vm="Standard_B2s"
    local estimated_cost_regular=10.95
    local estimated_cost_spot=3.29
    
    if (( $(echo "$ram_peak > 4096" | bc -l) )); then
        recommended_vm="Standard_B2ms"
        recommended_spot_vm="Standard_B2ms"
        estimated_cost_regular=36.50
        estimated_cost_spot=10.95
    fi
    
    if (( $(echo "$cpu_peak > 75" | bc -l) )); then
        recommended_vm="Standard_D2s_v3"
        recommended_spot_vm="Standard_D2s_v3"
        estimated_cost_regular=70.08
        estimated_cost_spot=21.02
    fi
    
    # Generate JSON summary
    cat > "$SUMMARY_FILE" << EOF
{
  "metadata": {
    "test_scenario": "${TEST_SCENARIO}",
    "ubuntu_version": "${UBUNTU_VERSION}",
    "timestamp": "${TIMESTAMP}",
    "sample_count": ${sample_count},
    "interval_seconds": ${MEASUREMENT_INTERVAL}
  },
  "measurements": {
    "cpu": {
      "average_percent": ${cpu_avg},
      "peak_percent": ${cpu_peak}
    },
    "ram": {
      "average_mb": ${ram_avg},
      "peak_mb": ${ram_peak},
      "average_percent": ${ram_pct_avg},
      "peak_percent": ${ram_pct_peak}
    },
    "disk": {
      "average_gb": ${disk_avg},
      "peak_gb": ${disk_peak}
    },
    "io": {
      "average_read_kbs": ${io_read_avg},
      "peak_read_kbs": ${io_read_peak}
    }
  },
  "azure_recommendations": {
    "regular_vm": {
      "sku": "${recommended_vm}",
      "estimated_monthly_cost_usd": ${estimated_cost_regular},
      "notes": "Standard pricing, 730 hours/month"
    },
    "spot_vm": {
      "sku": "${recommended_spot_vm}",
      "estimated_monthly_cost_usd": ${estimated_cost_spot},
      "eviction_rate": "~5%",
      "notes": "Spot pricing at 70% discount, ephemeral workloads"
    }
  }
}
EOF
    
    # Generate human-readable report
    cat > "$REPORT_FILE" << EOF
Resource Measurement Report
================================================================================
Test Scenario: ${TEST_SCENARIO}
Ubuntu Version: ${UBUNTU_VERSION}
Date: $(date)
Samples Collected: ${sample_count} (${MEASUREMENT_INTERVAL}s intervals)

Resource Usage Summary
--------------------------------------------------------------------------------
CPU:
  • Average: ${cpu_avg}%
  • Peak: ${cpu_peak}%
  
Memory:
  • Average: ${ram_avg} MB (${ram_pct_avg}%)
  • Peak: ${ram_peak} MB (${ram_pct_peak}%)
  
Disk:
  • Average: ${disk_avg} GB
  • Peak: ${disk_peak} GB
  
Disk I/O (Read):
  • Average: ${io_read_avg} KB/s
  • Peak: ${io_read_peak} KB/s

Azure VM Recommendations
--------------------------------------------------------------------------------
For CI/CD runners with ${UBUNTU_VERSION} IIAB tests:

Regular VM (Guaranteed Capacity):
  • SKU: ${recommended_vm}
  • Monthly Cost: ~\$${estimated_cost_regular} USD
  • Use Case: Production, time-critical deployments
  
Spot VM (Cost-Optimized, Recommended):
  • SKU: ${recommended_spot_vm}
  • Monthly Cost: ~\$${estimated_cost_spot} USD (70% discount)
  • Eviction Rate: ~5% for short-lived CI/CD workloads
  • Use Case: Integration tests, non-critical builds
  
RECOMMENDATION: Use Spot VMs for massive cost savings with acceptable 
                 reliability for test workloads.

Next Steps
--------------------------------------------------------------------------------
1. Review this report and verify recommendations match your needs
2. Run: ./scripts/azure/setup-infrastructure.sh --vm-size ${recommended_spot_vm}
3. Test with a single VM before scaling to matrix strategy

Files Generated
--------------------------------------------------------------------------------
  • Raw data: ${RAW_DATA_FILE}
  • JSON summary: ${SUMMARY_FILE}
  • This report: ${REPORT_FILE}

EOF
    
    # Display summary
    echo ""
    echo -e "${GREEN}✅ Analysis Complete${NC}"
    echo "========================================================"
    echo "CPU Usage:     Avg ${cpu_avg}% | Peak ${cpu_peak}%"
    echo "RAM Usage:     Avg ${ram_avg} MB | Peak ${ram_peak} MB (${ram_pct_peak}%)"
    echo "Disk Usage:    Avg ${disk_avg} GB | Peak ${disk_peak} GB"
    echo ""
    echo -e "${YELLOW}💡 Azure VM Recommendation:${NC}"
    echo "  Regular: ${recommended_vm} (~\$${estimated_cost_regular}/month)"
    echo "  Spot:    ${recommended_spot_vm} (~\$${estimated_cost_spot}/month) ⭐ RECOMMENDED"
    echo ""
    echo "Reports saved:"
    echo "  📊 JSON: ${SUMMARY_FILE}"
    echo "  📄 Text: ${REPORT_FILE}"
    echo "  📈 Raw:  ${RAW_DATA_FILE}"
    echo ""
}

# Trap to ensure monitoring stops on exit
trap stop_monitoring EXIT INT TERM

# Main execution
main() {
    check_dependencies
    capture_baseline
    start_monitoring
    
    echo -e "${BLUE}🚀 Starting test execution...${NC}"
    echo "  Script: ${TEST_SCENARIO}"
    echo "  Ubuntu: ${UBUNTU_VERSION}"
    echo ""
    echo "  (Test output follows below)"
    echo "========================================================"
    echo ""
    
    # Run the actual test
    if [ "${TEST_SCENARIO}" = "fresh-install" ]; then
        cd "$ROOT_DIR"
        ./scripts/scenarios/fresh-install.sh --ubuntu-version "$UBUNTU_VERSION" || true
    else
        echo -e "${YELLOW}⚠️  Test scenario '${TEST_SCENARIO}' not implemented${NC}"
        echo "  Simulating 60-second test..."
        sleep 60
    fi
    
    # Stop monitoring (also triggered by trap)
    stop_monitoring
    
    # Analyze results
    analyze_results
}

# Run main
main
