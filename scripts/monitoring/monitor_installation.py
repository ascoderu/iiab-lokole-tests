#!/usr/bin/env python3
"""
Automated monitoring script for IIAB installation.
Polls until installation completes, then runs verification.
Usage: python3 monitor_installation.py [VM_NAME]
"""

import subprocess
import time
import sys
from datetime import datetime
import argparse

DEFAULT_VM_NAME = "iiab-lokole-test"
POLL_INTERVAL = 120  # 2 minutes
MAX_POLLS = 90  # 3 hours max

def log(message, log_file):
    """Log message to both console and file."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_message = f"[{timestamp}] {message}"
    print(log_message)
    with open(log_file, 'a') as f:
        f.write(log_message + '\n')

def run_command(cmd, timeout=30):
    """Run command and return output."""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "Command timed out"
    except Exception as e:
        return -2, "", str(e)

def check_installation_complete(vm_name):
    """Check if IIAB installation is complete."""
    cmd = f'multipass exec {vm_name} -- bash -c "grep -q RECAP /opt/iiab/iiab/iiab-install.log 2>/dev/null"'
    returncode, _, _ = run_command(cmd, timeout=30)
    return returncode == 0

def check_process_running(vm_name):
    """Check if ansible/installation process is still running."""
    cmd = f'multipass exec {vm_name} -- bash -c "pgrep -f ansible-playbook > /dev/null"'
    returncode, _, _ = run_command(cmd, timeout=30)
    return returncode == 0

def get_vm_status(vm_name):
    """Get VM status."""
    cmd = f'multipass list | grep {vm_name}'
    _, stdout, _ = run_command(cmd)
    if stdout:
        parts = stdout.split()
        if len(parts) >= 2:
            return parts[1]
    return "Unknown"

def main():
    """Main monitoring loop."""
    parser = argparse.ArgumentParser(description='Monitor IIAB installation')
    parser.add_argument('vm_name', nargs='?', default=DEFAULT_VM_NAME,
                        help=f'VM name (default: {DEFAULT_VM_NAME})')
    args = parser.parse_args()
    
    vm_name = args.vm_name
    log_file = f"installation-monitor-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log"
    
    log("\ud83d\udd04 Starting automated monitoring and testing cycle", log_file)
    log("=" * 80, log_file)
    log(f"VM: {vm_name}", log_file)
    log(f"Log file: {log_file}", log_file)
    log("=" * 80, log_file)
    
    # Monitor installation
    log("\n\ud83d\udcca Phase 1: Monitoring IIAB installation...", log_file)
    log(f"Polling every {POLL_INTERVAL/60:.0f} minutes for completion...", log_file)
    
    poll_count = 0
    installation_complete = False
    
    while poll_count < MAX_POLLS:
        poll_count += 1
        log(f"\n⏱️ Poll #{poll_count}: Checking installation status...", log_file)
        
        if check_installation_complete(vm_name):
            log("\u2705 Installation COMPLETE!", log_file)
            installation_complete = True
            break
        
        if check_process_running(vm_name):
            log("   \u23f3 Installation still in progress...", log_file)
        else:
            log("   \u26a0️ Installation process not detected", log_file)
        
        vm_status = get_vm_status(vm_name)
        log(f"   VM Status: {vm_status}", log_file)
        
        if poll_count < MAX_POLLS:
            time.sleep(POLL_INTERVAL)
    
    if not installation_complete:
        log("\n\u274c Maximum polling time reached", log_file)
    
    log("\n\u2705 Monitoring complete!", log_file)
    log(f"\ud83d\udcc1 Full log saved to: {log_file}", log_file)
    
    return 0 if installation_complete else 1

if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n\u26a0️ Monitoring interrupted by user")
        sys.exit(1)
