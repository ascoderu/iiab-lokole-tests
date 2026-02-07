# Azure Runner Sizing Guide

This document helps determine the optimal Azure VM size for ephemeral GitHub Actions self-hosted runners based on actual resource measurements.

## Quick Start

Run local resource measurement to get VM sizing recommendations:

```bash
# Measure resources for Ubuntu 24.04 (most common)
./scripts/monitoring/measure-resources.sh --ubuntu-version 24.04

# For Ubuntu 22.04 or 26.04
./scripts/monitoring/measure-resources.sh --ubuntu-version 22.04
./scripts/monitoring/measure-resources.sh --ubuntu-version 26.04

# Review recommendations
cat results/resource-measurements/report-*.txt
```

## Azure VM SKU Reference

### Recommended: B-Series Burstable VMs

Perfect for CI/CD with occasional CPU spikes:

| SKU               | vCPUs | RAM   | Temp Disk | Regular Price\* | Spot Price\* | Notes                    |
| ----------------- | ----- | ----- | --------- | --------------- | ------------ | ------------------------ |
| **Standard_B1s**  | 1     | 1 GB  | 4 GB      | $3.80/mo        | $1.14/mo     | Too small for IIAB       |
| **Standard_B2s**  | 2     | 4 GB  | 8 GB      | $10.95/mo       | $3.29/mo     | **Minimum recommended**  |
| **Standard_B2ms** | 2     | 8 GB  | 16 GB     | $36.50/mo       | $10.95/mo    | If RAM > 4GB needed      |
| **Standard_B4ms** | 4     | 16 GB | 32 GB     | $146.00/mo      | $43.80/mo    | Overkill for single test |

\*Prices for East US region, pay-as-you-go, 730 hours/month. Actual costs much lower for ephemeral runners.

### Alternative: D-Series Compute-Optimized VMs

For CPU-intensive workloads (if B-series CPU credits insufficient):

| SKU                 | vCPUs | RAM   | Temp Disk | Regular Price\* | Spot Price\* |
| ------------------- | ----- | ----- | --------- | --------------- | ------------ |
| **Standard_D2s_v3** | 2     | 8 GB  | 16 GB     | $70.08/mo       | $21.02/mo    |
| **Standard_D4s_v3** | 4     | 16 GB | 32 GB     | $140.16/mo      | $42.05/mo    |

## Cost Calculation Examples

### Scenario 1: PR-triggered tests (on-demand)

**Assumptions:**

- 10 PRs per month with integration test label
- 3 Ubuntu versions tested per PR (sequential on one VM)
- 60 minutes runtime per test sequence
- B2s Spot VM at $0.0045/hour

**Monthly cost:**

```
10 PRs × 1 hour × $0.0045 = $0.045/month (~5 cents)
```

### Scenario 2: Scheduled weekly tests

**Assumptions:**

- 4 scheduled runs per month
- 3 Ubuntu versions in parallel (3 VMs)
- 45 minutes runtime per VM
- B2s Spot VM at $0.0045/hour

**Monthly cost:**

```
4 runs × 3 VMs × 0.75 hours × $0.0045 = $0.04/month (~4 cents)
```

### Scenario 3: Heavy development (worst case)

**Assumptions:**

- 50 test runs per month (daily development)
- 60 minutes per run
- B2s Spot VM

**Monthly cost:**

```
50 runs × 1 hour × $0.0045 = $0.225/month (~23 cents)
```

**Conclusion:** Even heavy usage stays under $1/month with ephemeral Spot VMs.

## Decision Matrix

Use this to choose the right VM size based on your measurements:

| Measured Peak RAM | Measured Peak CPU | Recommended VM  | Price (Spot) | Rationale               |
| ----------------- | ----------------- | --------------- | ------------ | ----------------------- |
| < 3.5 GB          | < 80% (2 cores)   | Standard_B2s    | $3.29/mo     | Cost-effective baseline |
| 3.5 - 6 GB        | < 80% (2 cores)   | Standard_B2ms   | $10.95/mo    | Extra RAM headroom      |
| < 6 GB            | > 80% (sustained) | Standard_D2s_v3 | $21.02/mo    | More CPU credits        |
| 6 - 12 GB         | Any               | Standard_B4ms   | $43.80/mo    | Large IIAB installs     |

**Note:** Our nested VM setup (Multipass inside Azure VM) adds ~1GB RAM overhead.

## Spot VM Eviction Strategy

**What happens if evicted mid-test?**

GitHub Actions automatically handles failures:

1. **Eviction detected**: Runner job fails with exit code (timeout or lost connection)
2. **Automatic retry**: GitHub Actions retries the job (up to 3 attempts)
3. **New VM provisioned**: Fresh Spot VM created for retry
4. **Test resumes**: Job re-runs from scratch on new VM

**Eviction rates by VM type:**

- B-series: ~3-5% (low demand capacity)
- D-series: ~5-10% (more competition)
- Larger VMs: Lower eviction rates

**Best practices:**

- Always use Spot for non-production CI/CD
- Set max spot price to `-1` (pay up to regular price = lowest eviction)
- Use `fail-fast: false` in matrix strategy
- Add timeout to jobs (90 minutes recommended)

## Regional Pricing Differences

Spot VM pricing varies by Azure region. Top choices for US-based workloads:

| Region      | Network | B2s Spot Price | Notes                         |
| ----------- | ------- | -------------- | ----------------------------- |
| **East US** | Good    | $0.0045/hr     | Recommended, lowest price     |
| East US 2   | Good    | $0.0050/hr     | Slightly pricier              |
| Central US  | Medium  | $0.0048/hr     | Middle ground                 |
| West US 2   | Best    | $0.0052/hr     | Fastest GitHub Actions egress |

**Recommendation:** Use **East US** for 20% lower cost unless you need specific region for compliance.

## Performance Tuning

### Baseline: Nested Virtualization Overhead

Running Multipass VMs inside Azure VMs adds overhead:

- **RAM**: +1 GB for Multipass daemon
- **Disk**: +2 GB for Multipass snap
- **CPU**: ~5-10% for virtualization layer

Total: **6 GB host RAM** = 4 GB guest + 1 GB Multipass + 1 GB host OS

### Optimization Strategies

1. **Use cloud-init for faster boot** (~30s savings)
2. **Pre-pull Docker images** if using containers
3. **Enable Azure Accelerated Networking** (no extra cost, 2-3x faster)
4. **Use proximity placement groups** if running multiple VMs in parallel

## Next Steps

After measuring resources locally:

1. **Review reports**: Check `results/resource-measurements/report-*.txt`
2. **Choose VM size**: Use decision matrix above
3. **Setup Azure**: Run `./scripts/azure/login.sh`
4. **Deploy infrastructure**: Run `./scripts/azure/setup-infrastructure.sh --vm-size Standard_B2s`
5. **Test workflow**: Trigger a PR test and monitor

## Troubleshooting

### VM too small

**Symptoms:**

- Test jobs killed with OOM errors
- Multipass fails to create VM
- "No space left on device" errors

**Solution:**

- Upgrade to next VM size tier
- Use Standard_B2ms (8 GB) or Standard_D2s_v3

### VM too large

**Symptoms:**

- Tests complete fine but costs higher than expected
- Resource measurements show <50% utilization

**Solution:**

- Downgrade to Standard_B2s
- Consider longer test sequences (more Ubuntu versions per VM)

### High eviction rate

**Symptoms:**

- Multiple job retries
- "Runner lost communication" errors
- Tests taking much longer than expected

**Solution:**

- Switch to regular VMs (not Spot) for production PRs
- Use Spot only for experimental/scheduled tests
- Set max price to `-1` (lowest eviction rate)

## References

- [Azure VM Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/)
- [Azure Spot VMs Documentation](https://learn.microsoft.com/en-us/azure/virtual-machines/spot-vms)
- [GitHub Actions Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [GitHub Actions Hardware Requirements](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners#hardware-requirements-for-self-hosted-runner-machines)

---

**Last Updated:** February 6, 2026
**Maintained By:** IIAB-Lokole Integration Test Team
