# Azure Self-Hosted Runner Setup

Complete guide for setting up ephemeral Azure Spot VM runners for IIAB integration tests.

## Overview

This infrastructure provisions on-demand Azure Spot VMs that act as ephemeral GitHub Actions self-hosted runners. Key benefits:

- **Cost-effective**: ~$0.05 per test run with Spot VMs (vs $0 remaining GitHub Actions minutes)
- **No nested VM limitations**: Full access to hypervisor for Multipass VMs
- **Deterministic cleanup**: VMs auto-destroy after job completion
- **Secure**: Service Principal scoped to single resource group

## Prerequisites

1. **Azure Subscription**: Active Azure account
2. **Azure CLI**: Install from https://aka.ms/InstallAzureCLIDeb
3. **GitHub CLI** (optional): For setting secrets automatically
4. **jq**: JSON processor (`sudo apt-get install jq`)

## Quick Start

### Step 1: Measure Resource Requirements

Before provisioning Azure VMs, measure actual resource needs:

```bash
# Run local resource measurement
./scripts/monitoring/measure-resources.sh --ubuntu-version 24.04

# Review recommendations
cat results/resource-measurements/report-*.txt
```

This generates Azure VM size recommendations (typically `Standard_B2s` for $3.29/month Spot pricing).

### Step 2: Azure Authentication

Login and create service principal with minimal permissions:

```bash
./scripts/azure/login.sh
```

This script:
- Logs you into Azure
- Creates resource group `iiab-lokole-tests-rg`
- Creates service principal scoped to that resource group only
- Generates credentials in `.azure-credentials.json`

### Step 3: Configure GitHub Secrets

Add these secrets to your repository:

**Via Web UI:**  
https://github.com/ascoderu/iiab-lokole-tests/settings/secrets/actions

**Or via CLI (automated):**
```bash
# The login script creates this helper
./scripts/azure/set-github-secrets.sh
```

Required secrets:
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_CLIENT_ID`
- `AZURE_CLIENT_SECRET`
- `AZURE_TENANT_ID`
- `INTEGRATION_TEST_PAT` (already configured)

### Step 4: Test Locally

Provision a test VM manually before integrating with CI/CD:

```bash
# Set GitHub token
export GITHUB_TOKEN="${INTEGRATION_TEST_PAT}"

# Provision test VM
./scripts/azure/provision-runner.sh --pr-number 999 --no-cleanup

# Check runner registered
open https://github.com/ascoderu/iiab-lokole-tests/actions/runners

# Cleanup manually when done
az vm delete --resource-group iiab-lokole-tests-rg --name gh-runner-<RUN_ID> --yes
```

### Step 5: Integrate with GitHub Actions

See `.github/workflows/test-on-pr-label-azure.yml` for example workflow that:
1. Provisions Azure VM
2. Waits for runner registration
3. Runs tests on the runner
4. Automatically cleans up VM

## Architecture

```
PR labeled "test-iiab-integration"
    ↓
Trigger workflow runs on GitHub-hosted runner
    ↓
Provision Azure Spot VM (2-3 min)
    ↓
VM boots & registers as ephemeral runner
    ↓
Test job dispatched to Azure runner
    ↓
Runner executes: setup Multipass → install IIAB → verify
    ↓
Test complete → runner unregisters → VM self-destructs
```

## Cost Analysis

### Per-Test Costs (Spot VM)

**Configuration**: Standard_B2s, East US, Spot pricing

| Scenario | Runs/Month | Runtime | Monthly Cost |
|----------|------------|---------|--------------|
| Light usage (PR-triggered) | 10 | 60 min | $0.045 (~5¢) |
| Moderate (PR + scheduled) | 20 | 60 min | $0.09 (~9¢) |
| Heavy development | 50 | 60 min | $0.23 (~23¢) |
| Daily scheduled tests | 30 | 60 min | $0.14 (~14¢) |

**Comparison:**
- GitHub Actions: 2,000 free minutes/month, then $0.008/minute
- Azure Spot: ~$0.0045/hour (ephemeral, only charged when running)
- **Savings**: 60-90% vs regular Azure VMs, infinite vs GitHub minutes

### Spot vs Regular VMs

| Type | Price/Hour | Monthly* | Eviction Rate | Use Case |
|------|------------|----------|---------------|----------|
| **Spot B2s** | $0.0045 | $3.29 | ~5% | **Recommended** for CI/CD |
| Regular B2s | $0.015 | $10.95 | 0% | Production deployments |
| Spot D2s_v3 | $0.029 | $21.02 | ~10% | CPU-intensive tests |

*Full-time pricing (730 hours). Actual costs much lower for ephemeral runners.

## Infrastructure Components

| Component | Purpose | Cost | Lifecycle |
|-----------|---------|------|-----------|
| **VM (Spot)** | Runner host | $0.0045/hr | Created per job, destroyed after |
| **OS Disk (SSD)** | VM boot disk | Included | Deleted with VM |
| **Public IP (Standard)** | SSH access | $0.005/hr | Deleted with VM |
| **Network Interface** | VM network | Free | Deleted with VM |
| **Virtual Network** | Shared network | Free | Persistent |
| **Resource Group** | Container | Free | Persistent |

**Total per test run**: ~$0.0045/hour × 1 hour = **$0.0045** (~0.5¢)

## Security

### Service Principal Permissions

The service principal has **Contributor** role scoped to:
```
/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/iiab-lokole-tests-rg
```

**Can do:**
- Create/delete VMs, disks, NICs in resource group
- Manage network security groups
- Read resource group properties

**Cannot do:**
- Access other resource groups
- Modify subscriptionsubscription settings
- Create/delete resource groups
- Access Key Vaults outside scope
- Modify IAM roles

### Runner Registration

- GitHub PAT (`INTEGRATION_TEST_PAT`) stored as Azure VM extension secret
- Never logged or exposed in VM metadata
- Runner configured as ephemeral (auto-unregister after one job)
- VM self-destructs after runner process exits

### Network Security

Default NSG rules:
- Inbound: SSH (port 22) only - **Restrict to your IP for production**
- Outbound: HTTP/HTTPS only (GitHub, package repos)
- No public services exposed

**Hardening for production:**
```bash
# Edit infrastructure/azure/main.bicep
# Line ~220: Change sourceAddressPrefix from '*' to your IP
sourceAddressPrefix: 'YOUR_IP_ADDRESS/32'
```

## Maintenance

### Cleanup Orphaned VMs

Safety net for VMs that didn't auto-clean up:

```bash
# Dry run - see what would be deleted
./scripts/azure/cleanup-orphaned-vms.sh --dry-run

# Delete VMs older than 2 hours
./scripts/azure/cleanup-orphaned-vms.sh --max-age-hours 2

# Check for any VMs
az vm list --resource-group iiab-lokole-tests-rg --output table
```

### Monitor Costs

```bash
# Get cost-to-date for resource group
az consumption usage list \
    --start-date $(date -d '30 days ago' +%Y-%m-%d) \
    --end-date $(date +%Y-%m-%d) \
    --query "[?contains(instanceName, 'iiab-lokole')].{Name:instanceName, Cost:pretaxCost}" \
    -o table
```

### Rotate Credentials

Service principals should be rotated every 90 days:

```bash
# Delete old service principal
az ad sp delete --id $(az ad sp list --display-name iiab-lokole-github-actions --query '[0].appId' -o tsv)

# Recreate
./scripts/azure/login.sh

# Update GitHub secrets
./scripts/azure/set-github-secrets.sh
```

## Troubleshooting

### VM Provisioning Fails

**Symptoms:** `az deployment group create` errors

**Solutions:**
1. Check quota: `az vm list-usage --location eastus --output table`
2. Try different region: `--location westus2`
3. Try smaller VM: `--vm-size Standard_B1s`
4. Check Spot capacity: Use regular VM temporarily

### Runner Doesn't Register

**Symptoms:** Timeout waiting for runner, VM visible in Azure but not in GitHub

**Debug:**
```bash
# SSH to VM
ssh -i .ssh/azure-runner-key azureuser@<VM_IP>

# Check cloud-init status
cloud-init status

# Check runner logs
sudo journalctl -u actions.runner.* -f

# Check extension logs
sudo cat /var/log/azure/Microsoft.Azure.Extensions.CustomScript/*/extension.log
```

**Common issues:**
- GitHub token expired/invalid
- Runner already registered with same name
- GitHub API rate limit exceeded

### Spot VM Evicted

**Symptoms:** Job fails mid-test with "Runner lost communication"

**Solution:** GitHub Actions automatically retries. If eviction rate is %high (>10%), consider:
1. Setting `--max-spot-price -1` (pay up to regular price = lower eviction)
2. Using regular VM for critical PRs
3. Trying different region

### High Costs

**Symptoms:** Azure bill higher than expected

**Debug:**
```bash
# List all VMs (should be empty between tests)
az vm list --resource-group iiab-lokole-tests-rg --output table

# Check orphaned resources
az resource list --resource-group iiab-lokole-tests-rg --output table

# Review costs
az consumption usage list --start-date $(date -d '7 days ago' +%Y-%m-%d)
```

**Solutions:**
- Run cleanup script: `./scripts/azure/cleanup-orphaned-vms.sh`
- Set up Azure budget alerts
- Use sequential testing (one VM) instead of parallel

## Advanced Configuration

### Use Different VM Sizes Per Ubuntu Version

Edit workflow to pass different `--vm-size` based on matrix:

```yaml
- name: Provision Azure runner
  run: |
    if [ "${{ matrix.ubuntu_version }}" = "26.04" ]; then
      VM_SIZE="Standard_B2ms"  # More RAM for daily builds
    else
      VM_SIZE="Standard_B2s"
    fi
    ./scripts/azure/provision-runner.sh --vm-size "$VM_SIZE"
```

### Private Runners (No Public IP)

Remove public IP from `infrastructure/azure/main.bicep` and use Azure Bastion for access:

```bicep
// Comment out publicIPAddress in network interface
// publicIPAddress: {
//   id: publicIP.id
// }
```

### Sequential Testing on Single VM

Reuse one VM for all Ubuntu versions:

```yaml
jobs:
  provision-vm:
    runs-on: ubuntu-latest
    steps:
      - run: ./scripts/azure/provision-runner.sh
    outputs:
      runner-name: ${{ steps.provision.outputs.runner-name }}
  
  test-all-versions:
    needs: provision-vm
    runs-on: [self-hosted, azure-spot, ${{ needs.provision-vm.outputs.runner-name }}]
    strategy:
      matrix:
        ubuntu_version: ['22.04', '24.04', '26.04']
    steps:
      - run: ./scripts/scenarios/fresh-install.sh --ubuntu-version ${{ matrix.ubuntu_version }}
```

## References

- [Azure VM Pricing](https://azure.microsoft.com/en-us/pricing/details/virtual-machines/linux/)
- [Azure Spot VMs](https://learn.microsoft.com/en-us/azure/virtual-machines/spot-vms)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [GitHub Actions Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Azure CLI Reference](https://learn.microsoft.com/en-us/cli/azure/)

---

**Questions?** Open an issue in this repository or check [docs/AZURE-RUNNER-SIZING.md](./AZURE-RUNNER-SIZING.md) for VM sizing guidance.
