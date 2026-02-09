#!/bin/bash
set -ux

echo "=== GitHub Actions Runner Registration Launcher ==="
echo "Launcher started at: $(date)"

# Create the runner setup script
cat > /tmp/runner-setup.sh << 'RUNNER_SCRIPT_EOF'
#!/bin/bash
set -ux

echo "=== GitHub Actions Runner Registration Script ==="
echo "Script started at: $(date)"

# Wait for cloud-init to complete
echo "Waiting for cloud-init..."
cloud-init status --wait
CLOUD_INIT_EXIT=$?

# Exit codes: 0=success, 1=error, 2=warnings/recoverable errors
if [ $CLOUD_INIT_EXIT -eq 0 ] || [ $CLOUD_INIT_EXIT -eq 2 ]; then
  echo "cloud-init completed (exit code: $CLOUD_INIT_EXIT)"
else
  echo "ERROR: cloud-init failed with exit code $CLOUD_INIT_EXIT"
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

# These variables will be replaced by Bicep
GITHUB_TOKEN="__GITHUB_TOKEN__"
GITHUB_REPO="__GITHUB_REPO__"
RUNNER_LABELS="__RUNNER_LABELS__"

echo "Configuration:"
echo "  Repository: $GITHUB_REPO"
echo "  Labels: $RUNNER_LABELS"

# Verify jq is installed
if ! command -v jq > /dev/null 2>&1; then
  echo "ERROR: jq not found, installing..."
  apt-get update && apt-get install -y jq
fi

# Get registration token
echo "Getting runner registration token from GitHub API..."
RESPONSE_BODY=$(curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$GITHUB_REPO/actions/runners/registration-token")

echo "API Response: $RESPONSE_BODY"

REGISTRATION_TOKEN=$(echo "$RESPONSE_BODY" | jq -r .token)

if [ -z "$REGISTRATION_TOKEN" ] || [ "$REGISTRATION_TOKEN" = "null" ]; then
  echo "ERROR: Failed to get registration token"
  echo "Response: $RESPONSE_BODY"
  exit 1
fi

echo "Registration token obtained successfully"

# Configure runner
cd /home/runner/actions-runner || {
  echo "ERROR: Cannot cd to /home/runner/actions-runner"
  exit 1
}

echo "Configuring runner as user runner..."
sudo -u runner ./config.sh \
  --url "https://github.com/$GITHUB_REPO" \
  --token "$REGISTRATION_TOKEN" \
  --name "$(hostname)" \
  --labels "$RUNNER_LABELS" \
  --work _work \
  --ephemeral \
  --unattended || {
  echo "ERROR: Runner configuration failed"
  exit 1
}

# Install and start runner service
echo "Installing runner service..."
./svc.sh install runner || {
  echo "ERROR: Service installation failed"
  exit 1
}

echo "Starting runner service..."
./svc.sh start || {
  echo "ERROR: Service start failed"
  exit 1
}

echo "✓ GitHub Actions runner registered and started successfully"
echo "  Repository: $GITHUB_REPO"
echo "  Labels: $RUNNER_LABELS"
echo "  Hostname: $(hostname)"
echo "Script completed at: $(date)"
RUNNER_SCRIPT_EOF

# Make it executable
chmod +x /tmp/runner-setup.sh

# Start as systemd service to persist after this script exits
echo "Starting runner setup as systemd service..."
systemd-run --unit=runner-setup \
  --description="GitHub Actions Runner Setup" \
  --remain-after-exit \
  /tmp/runner-setup.sh > /var/log/runner-setup.log 2>&1

echo "✓ Runner setup service started"
echo "Check service: systemctl status runner-setup"
echo "Check logs: journalctl -u runner-setup -f"
echo "Or: tail -f /var/log/runner-setup.log"
echo "Launcher completed at: $(date)"
exit 0
