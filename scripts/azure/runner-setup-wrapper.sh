#!/usr/bin/env bash
set -euo pipefail

# Restrict permissions for files created by this launcher.
umask 077

echo "=== GitHub Actions Runner Registration Launcher ==="
echo "Launcher started at: $(date)"

# Create a root-only directory for the temporary setup script.
install -d -m 700 /run/runner-setup

SETUP_SCRIPT="/run/runner-setup/runner-setup.sh"

# Create the runner setup script.
# The quoted heredoc prevents expansion by the outer shell.
cat > "$SETUP_SCRIPT" << 'RUNNER_SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail

# Remove the temporary script and clear the token when this script exits.
trap 'unset RUNNER_REGISTRATION_TOKEN; rm -f -- "$0"; rmdir /run/runner-setup 2>/dev/null || true' EXIT

echo "=== GitHub Actions Runner Registration Script ==="
echo "Script started at: $(date)"

# These variables are replaced by Bicep.
RUNNER_REGISTRATION_TOKEN="__RUNNER_REGISTRATION_TOKEN__"
GITHUB_REPO="__GITHUB_REPO__"
RUNNER_LABELS="__RUNNER_LABELS__"

# Validate the injected configuration without displaying the token.
if [[ -z "$RUNNER_REGISTRATION_TOKEN" || \
      "$RUNNER_REGISTRATION_TOKEN" == "__RUNNER_REGISTRATION_TOKEN__" ]]; then
    echo "ERROR: Runner registration token is missing."
    exit 1
fi

if [[ -z "$GITHUB_REPO" || "$GITHUB_REPO" == "__GITHUB_REPO__" ]]; then
    echo "ERROR: GitHub repository configuration is missing."
    exit 1
fi

if [[ -z "$RUNNER_LABELS" || "$RUNNER_LABELS" == "__RUNNER_LABELS__" ]]; then
    echo "ERROR: Runner labels configuration is missing."
    exit 1
fi

echo "Configuration:"
echo "  Repository: $GITHUB_REPO"
echo "  Labels: $RUNNER_LABELS"

# Wait for cloud-init to complete.
echo "Waiting for cloud-init..."

if cloud-init status --wait; then
    CLOUD_INIT_EXIT=0
else
    CLOUD_INIT_EXIT=$?
fi

# Exit codes: 0=success, 2=warnings/recoverable errors.
if [[ "$CLOUD_INIT_EXIT" -eq 0 || "$CLOUD_INIT_EXIT" -eq 2 ]]; then
    echo "Cloud-init completed (exit code: $CLOUD_INIT_EXIT)"
else
    echo "ERROR: Cloud-init failed with exit code $CLOUD_INIT_EXIT"
    echo ""
    echo "Cloud-init status:"
    cloud-init status --long || true
    echo ""
    echo "Cloud-init result:"
    cat /run/cloud-init/result.json 2>/dev/null || echo "No result.json found"
    echo ""
    echo "Last 50 lines of cloud-init log:"
    tail -50 /var/log/cloud-init.log 2>/dev/null || echo "No cloud-init.log found"
    echo ""
    echo "Last 50 lines of cloud-init-output log:"
    tail -50 /var/log/cloud-init-output.log 2>/dev/null || echo "No cloud-init-output.log found"
    exit 1
fi

# Configure the runner using the short-lived token supplied by Azure.
cd /home/runner/actions-runner || {
    echo "ERROR: Cannot cd to /home/runner/actions-runner"
    exit 1
}

echo "Configuring runner as user runner..."

if sudo -u runner ./config.sh \
    --url "https://github.com/$GITHUB_REPO" \
    --token "$RUNNER_REGISTRATION_TOKEN" \
    --name "$(hostname)" \
    --labels "$RUNNER_LABELS" \
    --work _work \
    --ephemeral \
    --unattended; then
    echo "Runner configuration completed."
else
    unset RUNNER_REGISTRATION_TOKEN
    echo "ERROR: Runner configuration failed."
    exit 1
fi

# The registration token is no longer needed.
unset RUNNER_REGISTRATION_TOKEN

# Install and start the runner service.
echo "Installing runner service..."

./svc.sh install runner || {
    echo "ERROR: Service installation failed."
    exit 1
}

echo "Starting runner service..."

./svc.sh start || {
    echo "ERROR: Service start failed."
    exit 1
}

echo "Runner registered and started successfully."
echo "  Repository: $GITHUB_REPO"
echo "  Labels: $RUNNER_LABELS"
echo "  Hostname: $(hostname)"
echo "Script completed at: $(date)"
RUNNER_SCRIPT_EOF

# Explicitly restrict the setup script to root.
chmod 700 "$SETUP_SCRIPT"

# Create a root-only log file.
install -m 600 /dev/null /var/log/runner-setup.log

# Start setup as a systemd service so it continues after the launcher exits.
echo "Starting runner setup as systemd service..."

systemd-run --unit=runner-setup \
    --description="GitHub Actions Runner Setup" \
    --remain-after-exit \
    "$SETUP_SCRIPT" > /var/log/runner-setup.log 2>&1

echo "Runner setup service started."
echo "Check service: systemctl status runner-setup"
echo "Check logs: journalctl -u runner-setup"
echo "Launcher completed at: $(date)"
