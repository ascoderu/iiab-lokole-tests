#!/bin/bash
#
# Test GitHub Actions workflows with a local self-hosted runner
#
# This script helps you set up a temporary self-hosted runner on your machine
# or in a local multipass VM to test workflows without Azure.

set -e

RUNNER_NAME="local-test-runner"
RUNNER_LABELS="self-hosted,ubuntu-24.04,local-test"
VM_NAME="gh-runner-test"

echo "🏃 Local GitHub Actions Runner Setup"
echo "====================================="
echo ""
echo "Choose an option:"
echo ""
echo "1. 📦 Set up runner in a local Multipass VM (RECOMMENDED)"
echo "   - Isolated from your host system"
echo "   - Can test full workflow including VM setup"
echo "   - Requires: multipass installed"
echo ""
echo "2. 💻 Set up runner directly on host (QUICK TEST)"
echo "   - Faster setup"
echo "   - No VM overhead"
echo "   - May install packages on your system"
echo ""
echo "3. 🧹 Clean up existing local runner/VM"
echo ""

read -p "Select option (1-3): " OPTION

case $OPTION in
  1)
    echo ""
    echo "📦 Setting up runner in Multipass VM..."
    echo "========================================"
    
    # Check if multipass is installed
    if ! command -v multipass &> /dev/null; then
        echo "❌ Multipass not installed. Install with:"
        echo "   sudo snap install multipass"
        exit 1
    fi
    
    # Check if VM already exists
    if multipass list | grep -q "$VM_NAME"; then
        echo "⚠️  VM $VM_NAME already exists"
        read -p "Delete and recreate? (y/n): " RECREATE
        if [ "$RECREATE" = "y" ]; then
            multipass delete "$VM_NAME"
            multipass purge
        else
            echo "Using existing VM..."
        fi
    fi
    
    # Create VM if needed
    if ! multipass list | grep -q "$VM_NAME"; then
        echo "🚀 Creating Ubuntu 24.04 VM..."
        multipass launch 24.04 \
            --name "$VM_NAME" \
            --cpus 2 \
            --memory 4G \
            --disk 20G
    fi
    
    echo ""
    echo "📋 Next steps:"
    echo ""
    echo "1. Get a GitHub runner token:"
    echo "   https://github.com/ascoderu/iiab-lokole-tests/settings/actions/runners/new"
    echo ""
    echo "2. Copy the token and run these commands in the VM:"
    echo ""
    echo "   multipass shell $VM_NAME"
    echo ""
    echo "   # Inside VM:"
    echo "   mkdir actions-runner && cd actions-runner"
    echo "   curl -o actions-runner-linux-x64.tar.gz -L https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64-2.319.1.tar.gz"
    echo "   tar xzf actions-runner-linux-x64.tar.gz"
    echo "   ./config.sh --url https://github.com/ascoderu/iiab-lokole-tests --token YOUR_TOKEN --labels $RUNNER_LABELS"
    echo "   ./run.sh"
    echo ""
    echo "3. In another terminal, trigger a workflow to use this runner:"
    echo "   gh workflow run test-on-pr-label.yml --field pr_number=999 --field pr_ref=main"
    echo ""
    ;;
    
  2)
    echo ""
    echo "💻 Setting up runner on host..."
    echo "==============================="
    echo ""
    echo "⚠️  WARNING: This will install the GitHub Actions runner on your host machine."
    echo "It may install packages and modify your system during test runs."
    echo ""
    read -p "Continue? (y/n): " CONTINUE
    if [ "$CONTINUE" != "y" ]; then
        exit 0
    fi
    
    RUNNER_DIR="$HOME/.local/share/github-actions-runner"
    mkdir -p "$RUNNER_DIR"
    cd "$RUNNER_DIR"
    
    if [ ! -f "run.sh" ]; then
        echo "📥 Downloading GitHub Actions runner..."
        curl -o actions-runner-linux-x64.tar.gz -L \
            https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64-2.319.1.tar.gz
        tar xzf actions-runner-linux-x64.tar.gz
    fi
    
    echo ""
    echo "📋 Next steps:"
    echo ""
    echo "1. Get a GitHub runner token:"
    echo "   https://github.com/ascoderu/iiab-lokole-tests/settings/actions/runners/new"
    echo ""
    echo "2. Configure the runner:"
    echo "   cd $RUNNER_DIR"
    echo "   ./config.sh --url https://github.com/ascoderu/iiab-lokole-tests --token YOUR_TOKEN --labels $RUNNER_LABELS --name $RUNNER_NAME"
    echo ""
    echo "3. Start the runner:"
    echo "   ./run.sh"
    echo ""
    echo "4. In another terminal, trigger a workflow:"
    echo "   gh workflow run test-on-pr-label.yml --field pr_number=999 --field pr_ref=main"
    echo ""
    ;;
    
  3)
    echo ""
    echo "🧹 Cleaning up..."
    echo "================"
    
    # Clean up VM
    if command -v multipass &> /dev/null; then
        if multipass list | grep -q "$VM_NAME"; then
            echo "Deleting VM $VM_NAME..."
            multipass delete "$VM_NAME"
            multipass purge
        fi
    fi
    
    # Clean up host runner
    RUNNER_DIR="$HOME/.local/share/github-actions-runner"
    if [ -d "$RUNNER_DIR" ]; then
        echo "Removing runner from host..."
        cd "$RUNNER_DIR"
        if [ -f "run.sh" ]; then
            ./svc.sh uninstall || true
            ./config.sh remove --token YOUR_TOKEN || echo "Manual removal may be needed"
        fi
        cd ..
        rm -rf "$RUNNER_DIR"
    fi
    
    echo "✅ Cleanup complete!"
    ;;
    
  *)
    echo "Invalid option"
    exit 1
    ;;
esac
