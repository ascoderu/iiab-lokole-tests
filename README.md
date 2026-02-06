# IIAB-Lokole Integration Tests

[![Test Ubuntu LTS](https://github.com/ascoderu/iiab-lokole-tests/workflows/test-ubuntu-lts/badge.svg)](https://github.com/ascoderu/iiab-lokole-tests/actions)

Automated integration testing suite for [Lokole](https://github.com/ascoderu/lokole) offline email integration with [Internet-in-a-Box (IIAB)](https://github.com/iiab/iiab) across multiple Ubuntu LTS releases and deployment scenarios.

## What This Tests

- **Fresh IIAB Installations**: Complete installation with Lokole from scratch
- **Lokole Upgrades**: Testing upgrade paths from older versions
- **Ubuntu LTS Releases**: 22.04, 24.04, 26.04 (stable + daily pre-releases)
- **Python Compatibility**: Validating Python 3.9-3.13 support
- **Hardware Platforms**: VMs (Multipass/GitHub Actions) and physical Raspberry Pi

## Quick Start

```bash
# Clone repository
git clone --recursive https://github.com/ascoderu/iiab-lokole-tests.git
cd iiab-lokole-tests

# Run complete test suite on Ubuntu 24.04
./scripts/scenarios/fresh-install.sh --ubuntu-version 24.04

# Or run all phases automatically
./run-complete-test.sh
```

## Repository Structure

```
iiab-lokole-tests/
├── scripts/
│   ├── vm/               # VM provisioning (Multipass, Vagrant)
│   ├── monitoring/       # Installation monitoring and progress tracking
│   ├── verify/           # Post-installation verification
│   ├── scenarios/        # Complete test scenarios
│   └── analyze/          # Log analysis and reporting
├── environments/
│   ├── multipass/        # Multipass cloud-init configs
│   ├── vagrant/          # Vagrantfiles
│   └── iiab-configs/     # IIAB local_vars.yml templates
├── .github/
│   ├── workflows/        # GitHub Actions CI/CD
│   └── actions/          # Re usable composite actions
├── docs/                 # Documentation
└── roles/                # Git submodule: ansible-role-lokole
```

## Test Scenarios

### 1. Fresh Install
Tests complete IIAB installation with Lokole on clean system:
```bash
./scripts/scenarios/fresh-install.sh --ubuntu-version 24.04
```

### 2. Upgrade Path
Tests Lokole upgrade on existing IIAB:
```bash
./scripts/scenarios/upgrade-lokole.sh --from-version 0.5.9 --to-version 0.5.10
```

### 3. PR Testing
Tests Lokole or IIAB Pull Request:
```bash
./scripts/scenarios/test-pr-branch.sh \
  --pr-repo ascoderu/lokole \
  --pr-ref feature/upgrade-client-python-3.12 \
  --pr-sha abc123def456
```

### 4. Release Validation
Validates new releases work with IIAB:
```bash
./scripts/scenarios/validate-release.sh --lokole-version 0.5.10
```

## Automated Testing (GitHub Actions)

### PR-Triggered Tests
Label PRs with `test-iiab-integration` to trigger integration tests:
1. Go to Lokole or IIAB PR
2. Add label: `test-iiab-integration`
3. GitHub Actions automatically runs tests
4. Results posted as comment on PR

### Scheduled Tests
- **Ubuntu Daily**: Weekly check for new Multipass images
- **Release Validation**: Automatic on Lokole/IIAB releases
- **Post-Merge**: After every merge to master

### Manual Triggers
```bash
# Trigger workflow via GitHub CLI
gh workflow run test-ubuntu-lts.yml -f ubuntu_version=26.04 -f use_daily=true
```

## Documentation

- [**Setup Guide**](docs/SETUP.md) - Repository configuration and secrets
- [**Running Tests**](docs/RUNNING_TESTS.md) - Local and CI test execution
- [**Adding Tests**](docs/ADDING_TESTS.md) - Contributing new test scenarios
- [**Troubleshooting**](docs/TROUBLESHOOTING.md) - Common issues and solutions
- [**Integration Points**](docs/INTEGRATION_POINTS.md) - Technical details of Lokole ↔ IIAB

## Test Results & Reports

Test results are generated in multiple formats:
- **Markdown**: `results/test-report-YYYYMMDD.md` (human-readable)
- **JSON**: `results/test-summary-YYYYMMDD.json` (machine-readable, for badges)
- **JUnit XML**: `results/junit-YYYYMMDD.xml` (CI dashboards)

### Compatibility Matrix

View the latest compatibility matrix at: https://ascoderu.github.io/iiab-lokole-tests

## Requirements

### For Local Testing
- **Multipass**: VM management (or Vagrant/Docker)
- **Ansible**: >= 2.11
- **Python**: >= 3.9
- **Bash**: >= 4.0

### For CI/CD
- GitHub Actions (included)
- Secrets: `INTEGRATION_TEST_PAT` (Personal Access Token)

## Cross-Repository Integration

This repository integrates with:
- [`ascoderu/lokole`](https://github.com/ascoderu/lokole) - Lokole email software
- [`ascoderu/ansible-role-lokole`](https://github.com/ascoderu/ansible-role-lokole) - Canonical Ansible role
- [`iiab/iiab`](https://github.com/iiab/iiab) - Internet-in-a-Box platform

### Webhook Setup for Remote PRs

**In `ascoderu/lokole` repository**, add `.github/workflows/trigger-integration-tests.yml`:
```yaml
on:
  pull_request:
    types: [labeled]
jobs:
  dispatch:
    if: github.event.label.name == 'test-iiab-integration'
    steps:
      - uses: peter-evans/repository-dispatch@v2
        with:
          token: ${{ secrets.INTEGRATION_TEST_PAT }}
          repository: ascoderu/iiab-lokole-tests
          event-type: test-integration-lokole
          client-payload: '{"pr_number":"${{github.event.pull_request.number}}","ref":"${{github.event.pull_request.head.ref}}","sha":"${{github.event.pull_request.head.sha}}"}'
```

Similar webhook needed in `iiab/iiab` repository.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

### Adding New Tests

1. Create test script in `scripts/verify/`
2. Add to scenario in `scripts/scenarios/`
3. Document in `docs/ADDING_TESTS.md`
4. Submit PR with test results

### Reporting Issues

- **Test framework issues**: [iiab-lokole-tests/issues](https://github.com/ascoderu/iiab-lokole-tests/issues)
- **Lokole bugs**: [lokole/issues](https://github.com/ascoderu/lokole/issues)
- **IIAB bugs**: [iiab/issues](https://github.com/iiab/iiab/issues)

## License

Apache License 2.0

## Maintainers

- [Ascoderu](https://ascoderu.ca) - Lokole maintainers
- [IIAB Community](https://wiki.iiab.io) - IIAB contributors

## Acknowledgments

This testing framework was developed to ensure reliable integration between Lokole and IIAB across diverse platforms and Ubuntu releases, supporting education and communication in low-bandwidth communities worldwide.
