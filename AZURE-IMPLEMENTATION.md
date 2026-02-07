# Azure Ephemeral Runner Implementation - Complete

✅ **Implementation Status**: All components ready for testing

This document provides an overview of the Azure ephemeral self-hosted runner infrastructure implementation and next steps.

## What Was Implemented

### Phase 1: Local Resource Measurement ✅

**Created:**

- `scripts/monitoring/measure-resources.sh` - Monitors CPU, RAM, disk, and I/O during test execution
- `docs/AZURE-RUNNER-SIZING.md` - Comprehensive VM sizing guide with cost analysis
- `results/resource-measurements/` - Directory for measurement outputs

**Purpose:** Measure actual resource requirements before provisioning Azure VMs to ensure cost-optimal sizing.

**Next Step:** Run measurement:

```bash
./scripts/monitoring/measure-resources.sh --ubuntu-version 24.04
```

### Phase 2: Azure Authentication & Setup ✅

**Created:**

- `scripts/azure/login.sh` - Interactive Azure login and service principal creation
- `.azure-credentials.json` - Generated credentials file (gitignored)
- `scripts/azure/set-github-secrets.sh` - Auto-generated helper for setting GitHub secrets

**Purpose:** Secure Azure authentication with minimal permissions (scoped to single resource group).

**Next Step:** Setup Azure:

```bash
./scripts/azure/login.sh
```

### Phase 3: Infrastructure as Code (Bicep) ✅

**Created:**

- `infrastructure/azure/main.bicep` - Complete VM provisioning template (400+ lines)
  - Spot VM configuration with 70% cost savings
  - Network security group with SSH + HTTPS
  - Cloud-init for GitHub runner installation
  - Auto-cleanup after job completion
- `infrastructure/azure/cleanup.bicep` - Cleanup template
- `infrastructure/azure/parameters.example.json` - Parameter file template

**Features:**

- Ephemeral runners (self-destruct after one job)
- Spot VM pricing (~$0.0045/hour vs $0.015/hour regular)
- Automatic resource deletion (VM, disk, NIC all deleted together)
- Support for Ubuntu 22.04 and 24.04 LTS

**Next Step:** Validate Bicep locally:

```bash
az deployment group what-if \
  --resource-group iiab-lokole-tests-rg \
  --template-file infrastructure/azure/main.bicep
```

### Phase 4: VM Lifecycle Orchestration ✅

**Created:**

- `scripts/azure/provision-runner.sh` - End-to-end VM provisioning and cleanup
  - Deploy Bicep template
  - Wait for runner registration
  - Monitor runner health
  - Cleanup on exit
- `scripts/azure/cleanup-orphaned-vms.sh` - Safety net for orphaned VMs
- SSH key generation (`.ssh/azure-runner-key`)

**Purpose:** Automated VM lifecycle management for GitHub Actions.

**Next Step:** Test local provisioning:

```bash
export GITHUB_TOKEN="${INTEGRATION_TEST_PAT}"
./scripts/azure/provision-runner.sh --pr-number 999 --no-cleanup
```

### Phase 5: GitHub Actions Integration ✅

**Created:**

- `.github/workflows/test-on-azure-runner.example.yml` - Complete workflow example
  - Job 1: Provision VM on GitHub-hosted runner
  - Job 2: Run tests on Azure runner
  - Job 3: Cleanup (always runs)

**Purpose:** Demonstrates integration pattern for replacing existing workflows.

**Next Step:** After local testing succeeds, adapt existing workflows to use Azure runners.

### Phase 6: Cost Monitoring & Security ✅

**Created:**

- `scripts/azure/cost-report.sh` - Cost analysis and projections
- Comprehensive security documentation
- Service principal with minimal permissions (Contributor on single resource group only)

**Security Features:**

- No access outside resource group
- Ephemeral runners (no state persistence)
- Auto-cleanup prevents cost leaks
- Network security group restricts access

**Next Step:** Monitor costs:

```bash
./scripts/azure/cost-report.sh
```

### Documentation ✅

**Created:**

- `docs/AZURE-SETUP.md` - Complete setup and usage guide (400+ lines)
- `docs/AZURE-RUNNER-SIZING.md` - VM sizing recommendations (300+ lines)
- This file - Implementation summary

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│ PR Labeling (lokole repo)                                       │
│  └─> repository_dispatch event                                  │
└──────────────────────────────┬──────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│ GitHub Actions (iiab-lokole-tests)                              │
│                                                                  │
│  Job 1: Provision (GitHub-hosted runner)                        │
│    ├─> Azure Login                                              │
│    ├─> Deploy Bicep template                                    │
│    ├─> Wait for runner registration                             │
│    └─> Output: VM name, runner labels                           │
│                                                                  │
│  Job 2: Test  (Azure self-hosted runner)                        │
│    ├─> Checkout code                                            │
│    ├─> Setup Multipass (no nested VM issues!)                   │
│    ├─> Run IIAB integration tests                               │
│    ├─> Generate reports                                         │
│    └─> Post PR comments                                         │
│                                                                  │
│  Job 3: Cleanup (GitHub-hosted runner, always runs)             │
│    ├─> Delete VM                                                │
│    └─> Cleanup orphaned resources                               │
└──────────────────────────────────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│ Azure Infrastructure                                             │
│                                                                  │
│  Resource Group: iiab-lokole-tests-rg                           │
│    ├─> Virtual Network (shared, persistent)                     │
│    └─> Ephemeral Resources (per test):                          │
│         ├─> Spot VM (Standard_B2s, 2 vCPU, 4 GB RAM)            │
│         ├─> OS Disk (32 GB SSD, auto-delete)                    │
│         ├─> Network Interface (auto-delete)                     │
│         ├─> Public IP (auto-delete)                             │
│         └─> Network Security Group                              │
│                                                                  │
│  VM Lifecycle: Create → Register → Test → Self-destruct         │
│  Cost: ~$0.0045/hour × 1 hour = ~$0.005 per test run            │
└──────────────────────────────────────────────────────────────────┘
```

## Cost Analysis

### Expected Monthly Costs

| Scenario                                | Runs/Month | Runtime | Monthly Cost     |
| --------------------------------------- | ---------- | ------- | ---------------- |
| **Light usage** (10 PR-triggered tests) | 10         | 60 min  | **$0.05** (~5¢)  |
| **Moderate** (20 tests + scheduled)     | 20         | 60 min  | **$0.09** (~9¢)  |
| **Heavy development** (50 tests)        | 50         | 60 min  | **$0.23** (~23¢) |
| **Daily scheduled** (30 tests)          | 30         | 60 min  | **$0.14** (~14¢) |

**Comparison:**

- Current: GitHub Actions (2,000 free minutes, then $0.008/min)
- Proposed: Azure Spot VMs ($0.0045/hour when running, $0 when not)
- **Savings**: ~60-90% vs regular Azure VMs, better resource control

### Cost Controls

1. **Ephemeral VMs**: Only exist during test execution
2. **Automatic cleanup**: VM self-destructs after job
3. **Orphan cleanup**: Safety net script removes stuck VMs
4. **Cost monitoring**: `cost-report.sh` tracks spending
5. **Spot pricing**: 70% discount vs regular VMs

## File Structure

```
iiab-lokole-tests/
├── .github/workflows/
│   ├── test-on-pr-label.yml              # Current (uses GitHub-hosted runners)
│   └── test-on-azure-runner.example.yml  # NEW: Example Azure integration
├── docs/
│   ├── AZURE-SETUP.md                    # NEW: Complete setup guide
│   ├── AZURE-RUNNER-SIZING.md            # NEW: VM sizing recommendations
│   └── VERIFICATION.md                   # Existing verification docs
├── infrastructure/azure/                  # NEW: Infrastructure as Code
│   ├── main.bicep                        # VM provisioning template
│   ├── cleanup.bicep                     # Cleanup template
│   └── parameters.example.json           # Parameter file template
├── scripts/
│   ├── azure/                            # NEW: Azure orchestration scripts
│   │   ├── login.sh                      # Setup authentication
│   │   ├── provision-runner.sh           # VM lifecycle management
│   │   ├── cleanup-orphaned-vms.sh       # Safety net cleanup
│   │   ├── cost-report.sh                # Cost monitoring
│   │   └── set-github-secrets.sh         # Auto-generated secrets helper
│   ├── monitoring/
│   │   └── measure-resources.sh          # NEW: Resource measurement
│   ├── scenarios/                        # Existing test scenarios
│   └── verify/                           # Existing verification scripts
└── results/resource-measurements/         # NEW: Measurement outputs
```

## Next Steps

### 1. Local Resource Measurement (5-60 minutes)

**Purpose:** Determine optimal VM size before spending money.

```bash
# Measure resources for Ubuntu 24.04
./scripts/monitoring/measure-resources.sh --ubuntu-version 24.04

# Review recommendations
cat results/resource-measurements/report-*.txt

# Expected outcome: Confirms Standard_B2s is sufficient
```

### 2. Azure Setup (10 minutes)

**Purpose:** Configure Azure authentication and resource group.

```bash
# Login and create service principal
./scripts/azure/login.sh

# This creates:
# - Resource group: iiab-lokole-tests-rg
# - Service principal: iiab-lokole-github-actions (scoped to RG only)
# - Credentials: .azure-credentials.json

# Set GitHub secrets (requires GitHub CLI)
./scripts/azure/set-github-secrets.sh

# Or manually add secrets at:
# https://github.com/ascoderu/iiab-lokole-tests/settings/secrets/actions
```

### 3. Local VM Test (15 minutes)

**Purpose:** Verify provisioning works before integrating with CI/CD.

```bash
# Load GitHub token
export GITHUB_TOKEN="${INTEGRATION_TEST_PAT}"  # Or from .env

# Provision test VM (keep running for debugging)
./scripts/azure/provision-runner.sh \
  --pr-number 999 \
  --no-cleanup

# Verify runner registered:
# https://github.com/ascoderu/iiab-lokole-tests/actions/runners

# SSH to VM (optional)
ssh -i .ssh/azure-runner-key azureuser@<VM_IP>

# Cleanup manually when done
az vm delete \
  --resource-group iiab-lokole-tests-rg \
  --name gh-runner-<RUN_ID> \
  --yes
```

### 4. Integrate with CI/CD (30 minutes)

**Option A: Test with example workflow**

```bash
# Trigger example workflow manually
gh workflow run test-on-azure-runner.example.yml \
  -f pr_number=610 \
  -f pr_ref=feature/add-integration-test-trigger \
  -f ubuntu_version=24.04

# Monitor: https://github.com/ascoderu/iiab-lokole-tests/actions
```

**Option B: Adapt existing workflow**

Replace `.github/workflows/test-on-pr-label.yml` with Azure runner version:

- Keep Job 1 (provision) as-is from example
- Update Job 2 `runs-on: [self-hosted, azure-spot]`
- Add Job 3 (cleanup) from example

### 5. Monitor and Optimize (Ongoing)

```bash
# Check costs weekly
./scripts/azure/cost-report.sh

# Cleanup orphaned VMs daily (cron job or scheduled workflow)
./scripts/azure/cleanup-orphaned-vms.sh --max-age-hours 2

# Review runner efficiency
# https://github.com/ascoderu/iiab-lokole-tests/actions/runners
```

## Troubleshooting

### Common Issues

**1. "Azure CLI not found"**

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

**2. "Not logged in to Azure"**

```bash
./scripts/azure/login.sh
```

**3. "GITHUB_TOKEN required"**

```bash
# Add to .env file
echo "INTEGRATION_TEST_PAT=ghp_your_token_here" >> .env

# Or export directly
export GITHUB_TOKEN="ghp_your_token_here"
```

**4. "VM provisioning fails"**

- Check quota: `az vm list-usage --location eastus --output table`
- Try smaller VM: `--vm-size Standard_B1s`
- Try different region: Edit `LOCATION` in `provision-runner.sh`

**5. "Runner doesn't register"**

- SSH to VM: `ssh -i .ssh/azure-runner-key azureuser@<VM_IP>`
- Check logs: `sudo journalctl -u actions.runner.* -f`
- Verify token: `curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/ascoderu/iiab-lokole-tests`

**6. "High costs"**

- List VMs: `az vm list --resource-group iiab-lokole-tests-rg --output table`
- Cleanup: `. /scripts/azure/cleanup-orphaned-vms.sh`
- Review: `/scripts/azure/cost-report.sh`

## References

- **Setup Guide**: [docs/AZURE-SETUP.md](docs/AZURE-SETUP.md)
- **Sizing Guide**: [docs/AZURE-RUNNER-SIZING.md](docs/AZURE-RUNNER-SIZING.md)
- **Example Workflow**: [.github/workflows/test-on-azure-runner.example.yml](.github/workflows/test-on-azure-runner.example.yml)
- **Azure Pricing**: https://azure.microsoft.com/en-us/pricing/details/virtual-machines/linux/
- **GitHub Actions**: https://docs.github.com/en/actions/hosting-your-own-runners

## Questions?

Open an issue or check the comprehensive documentation in `docs/AZURE-SETUP.md`.

---

**Implementation Date**: February 6, 2026  
**Status**: ✅ Ready for testing  
**Estimated Setup Time**: 30-60 minutes  
**Expected Monthly Cost**: $0.05-$0.25 (5-25¢)
