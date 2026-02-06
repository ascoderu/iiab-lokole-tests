# Integration Test Setup Guide

This guide explains how to set up cross-repository webhook triggers for automated integration testing.

## Overview

The integration test suite in `ascoderu/iiab-lokole-tests` is triggered by events in other repositories:

1. **Lokole repository** (`ascoderu/lokole`) - triggers on PR labels and merges
2. **IIAB repository** (`iiab/iiab`) - triggers on PR labels and merges

## Repository Dispatch Flow

```
┌─────────────────────────────────────────────────────────────┐
│  Lokole/IIAB Repository                                     │
│  PR labeled 'test-iiab-integration'                         │
│  └── Workflow: .github/workflows/trigger-integration.yml    │
│      └── repository_dispatch → iiab-lokole-tests            │
└─────────────────────────────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────┐
│  iiab-lokole-tests Repository                               │
│  Receives repository_dispatch event                         │
│  └── Workflow: .github/workflows/test-on-pr-label.yml       │
│      └── Runs tests, posts results back to original PR      │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### 1. Personal Access Token (PAT)

Create a GitHub PAT with the following scopes:
- `repo` (full control)
- `workflow` (update workflows)

Store this token as:
- **In lokole repo**: Secret named `INTEGRATION_TEST_PAT`
- **In IIAB repo**: Secret named `INTEGRATION_TEST_PAT`
- **In iiab-lokole-tests repo**: Secret named `INTEGRATION_TEST_PAT`

### 2. Repository Access

The PAT owner must have:
- Write access to `ascoderu/iiab-lokole-tests`
- Read access to `ascoderu/lokole` and `iiab/iiab`

## Setup Steps

### Step 1: Add Trigger Workflow to Lokole Repository

Create `.github/workflows/trigger-integration-tests.yml` in the `ascoderu/lokole` repository:

```yaml
name: Trigger Integration Tests

on:
  pull_request:
    types: [labeled, synchronize]
  push:
    branches:
      - master

jobs:
  trigger-on-label:
    if: github.event_name == 'pull_request' && contains(github.event.pull_request.labels.*.name, 'test-iiab-integration')
    runs-on: ubuntu-latest
    
    steps:
      - name: Trigger integration tests
        uses: peter-evans/repository-dispatch@v2
        with:
          token: ${{ secrets.INTEGRATION_TEST_PAT }}
          repository: ascoderu/iiab-lokole-tests
          event-type: test-integration-lokole
          client-payload: |
            {
              "pr_number": ${{ github.event.pull_request.number }},
              "ref": "${{ github.event.pull_request.head.ref }}",
              "sha": "${{ github.event.pull_request.head.sha }}",
              "repo": "${{ github.repository }}"
            }
  
  trigger-on-merge:
    if: github.event_name == 'push' && github.ref == 'refs/heads/master'
    runs-on: ubuntu-latest
    
    steps:
      - name: Trigger post-merge tests
        uses: peter-evans/repository-dispatch@v2
        with:
          token: ${{ secrets.INTEGRATION_TEST_PAT }}
          repository: ascoderu/iiab-lokole-tests
          event-type: lokole-merged
          client-payload: |
            {
              "branch": "${{ github.ref_name }}",
              "sha": "${{ github.sha }}",
              "repo": "${{ github.repository }}"
            }
```

### Step 2: Add Trigger Workflow to IIAB Repository

Create `.github/workflows/trigger-integration-tests.yml` in the `iiab/iiab` repository:

```yaml
name: Trigger Lokole Integration Tests

on:
  pull_request:
    types: [labeled, synchronize]
    paths:
      - 'roles/lokole/**'
  push:
    branches:
      - master
    paths:
      - 'roles/lokole/**'

jobs:
  trigger-on-label:
    if: github.event_name == 'pull_request' && contains(github.event.pull_request.labels.*.name, 'test-iiab-integration')
    runs-on: ubuntu-latest
    
    steps:
      - name: Trigger integration tests
        uses: peter-evans/repository-dispatch@v2
        with:
          token: ${{ secrets.INTEGRATION_TEST_PAT }}
          repository: ascoderu/iiab-lokole-tests
          event-type: test-integration-iiab
          client-payload: |
            {
              "pr_number": ${{ github.event.pull_request.number }},
              "ref": "${{ github.event.pull_request.head.ref }}",
              "sha": "${{ github.event.pull_request.head.sha }}",
              "repo": "${{ github.repository }}"
            }
  
  trigger-on-merge:
    if: github.event_name == 'push' && github.ref == 'refs/heads/master'
    runs-on: ubuntu-latest
    
    steps:
      - name: Trigger post-merge tests
        uses: peter-evans/repository-dispatch@v2
        with:
          token: ${{ secrets.INTEGRATION_TEST_PAT }}
          repository: ascoderu/iiab-lokole-tests
          event-type: iiab-merged
          client-payload: |
            {
              "branch": "${{ github.ref_name }}",
              "sha": "${{ github.sha }}",
              "repo": "${{ github.repository }}"
            }
```

### Step 3: Configure Secrets

#### In Lokole Repository (`ascoderu/lokole`)
1. Go to Settings → Secrets and variables → Actions
2. Add secret: `INTEGRATION_TEST_PAT` = `<your PAT>`

#### In IIAB Repository (`iiab/iiab`)
1. Go to Settings → Secrets and variables → Actions
2. Add secret: `INTEGRATION_TEST_PAT` = `<your PAT>`

#### In Integration Test Repository (`ascoderu/iiab-lokole-tests`)
1. Go to Settings → Secrets and variables → Actions
2. Add secret: `INTEGRATION_TEST_PAT` = `<your PAT>`

### Step 4: Verify Setup

1. Create a test PR in the lokole repository
2. Add the label `test-iiab-integration`
3. Check Actions tab in `ascoderu/iiab-lokole-tests` for workflow run
4. Results should be posted as a comment on the original PR

## Usage

### For Developers

#### Test a PR Before Merge

1. Open your PR in lokole or IIAB repository
2. Add label: `test-iiab-integration`
3. Integration tests will run automatically
4. Results posted as PR comment

#### Manual Test Runs

In the `iiab-lokole-tests` repository:

1. Go to Actions → Test Ubuntu LTS Versions
2. Click "Run workflow"
3. Configure:
   - Ubuntu version (22.04, 24.04, 26.04, or all)
   - Lokole version (leave empty for latest PyPI)
   - IIAB branch (default: master)
   - Pre-release testing (enable for daily builds)

### For Maintainers

#### Scheduled Tests

The workflow `test-ubuntu-lts.yml` runs automatically:
- **Schedule**: Weekly on Sundays at 2 AM UTC
- **Purpose**: Detect regressions across Ubuntu LTS versions
- **Automatic issue creation**: On failure, creates issue with logs

#### Post-Merge Validation

After merging to master:
- Lokole merges trigger tests with the merged commit
- IIAB merges trigger tests with the updated role
- Failures create issues automatically

## Troubleshooting

### Tests Not Triggering

1. **Check PAT permissions**:
   - Go to GitHub Settings → Developer settings → Personal access tokens
   - Verify `repo` and `workflow` scopes are enabled

2. **Check secret configuration**:
   - Repository Settings → Secrets → Actions
   - Verify `INTEGRATION_TEST_PAT` exists

3. **Check label name**:
   - Must be exactly `test-iiab-integration` (case-sensitive)

### Test Results Not Posting

1. **Check PAT has write access** to the PR's repository
2. **Review workflow logs** in iiab-lokole-tests Actions tab
3. **Verify client_payload** contains correct repository info

### Multipass Issues

If tests fail with Multipass errors:

1. GitHub Actions runners have limited nested virtualization
2. Tests may need adjustment for runner environment
3. Check logs: `multipass version`, `multipass find`

## Architecture Reference

### Workflow Files

| File | Repository | Purpose |
|------|------------|----------|
| `trigger-integration-tests.yml` | lokole, iiab | Dispatch events to test repo |
| `test-on-pr-label.yml` | iiab-lokole-tests | Run tests on PR label |
| `test-on-merge.yml` | iiab-lokole-tests | Run tests post-merge |
| `test-ubuntu-lts.yml` | iiab-lokole-tests | Scheduled & manual tests |

### Event Types

| Event Type | Triggered By | Payload |
|-----------|--------------|----------|
| `test-integration-lokole` | Lokole PR labeled | pr_number, ref, sha, repo |
| `test-integration-iiab` | IIAB PR labeled | pr_number, ref, sha, repo |
| `lokole-merged` | Lokole master push | branch, sha, repo |
| `iiab-merged` | IIAB master push | branch, sha, repo |

### Script Flow

```
test-on-pr-label.yml
  └── scripts/scenarios/test-pr-branch.sh
      ├── scripts/vm/multipass/setup-vm.sh
      ├── scripts/vm/multipass/install-iiab.sh
      │   └── scripts/monitoring/monitor_installation.py
      └── scripts/verify/verify-installation.sh
```

## Next Steps

1. **Add composite actions**: Reusable action components in `.github/actions/`
2. **Matrix testing**: Expand to test multiple Python versions
3. **Performance baselines**: Track installation times
4. **Integration with IIAB CI**: Coordinate with existing IIAB workflows
