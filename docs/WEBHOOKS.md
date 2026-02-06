# Cross-Repository Webhook Configuration

This document details the webhook setup for cross-repository integration testing.

## Overview

Integration tests are triggered via GitHub's `repository_dispatch` API:

```
Source Repo (lokole/iiab) → repository_dispatch → Test Repo (iiab-lokole-tests)
```

## Event Flow

### 1. PR Label Trigger

**Scenario**: Developer adds `test-iiab-integration` label to PR

```yaml
# In lokole/.github/workflows/trigger-integration-tests.yml
on:
  pull_request:
    types: [labeled, synchronize]

jobs:
  trigger-on-label:
    if: contains(github.event.pull_request.labels.*.name, 'test-iiab-integration')
    steps:
      - uses: peter-evans/repository-dispatch@v2
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
```

**Result**:
- Triggers `test-on-pr-label.yml` in iiab-lokole-tests
- Runs tests with PR's code
- Posts results as PR comment

### 2. Post-Merge Trigger

**Scenario**: PR merged to master branch

```yaml
# In lokole/.github/workflows/trigger-integration-tests.yml
on:
  push:
    branches: [master]

jobs:
  trigger-on-merge:
    steps:
      - uses: peter-evans/repository-dispatch@v2
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

**Result**:
- Triggers `test-on-merge.yml` in iiab-lokole-tests
- Validates merged commit
- Creates issue on failure

## Repository Configurations

### ascoderu/lokole

**Workflow**: `.github/workflows/trigger-integration-tests.yml`

**Triggers**:
- PR labeled `test-iiab-integration`
- PR synchronized (new commits)
- Push to master

**Dispatches**:
- `test-integration-lokole` (PR tests)
- `lokole-merged` (post-merge tests)

**Secrets Required**:
- `INTEGRATION_TEST_PAT`: GitHub PAT with `repo` + `workflow` scopes

### iiab/iiab

**Workflow**: `.github/workflows/trigger-integration-tests.yml`

**Triggers**:
- PR labeled `test-iiab-integration`
- PR synchronized (new commits)
- Push to master (only if `roles/lokole/**` changed)

**Dispatches**:
- `test-integration-iiab` (PR tests)
- `iiab-merged` (post-merge tests)

**Secrets Required**:
- `INTEGRATION_TEST_PAT`: GitHub PAT with `repo` + `workflow` scopes

### ascoderu/iiab-lokole-tests

**Workflows**:
1. `.github/workflows/test-on-pr-label.yml`
2. `.github/workflows/test-on-merge.yml`
3. `.github/workflows/test-ubuntu-lts.yml`

**Receives Events**:
- `test-integration-lokole`
- `test-integration-iiab`
- `lokole-merged`
- `iiab-merged`

**Secrets Required**:
- `INTEGRATION_TEST_PAT`: For posting PR comments back to source repos
- `GITHUB_TOKEN`: Auto-provided for creating issues

## Event Payload Schemas

### PR Test Events

**Event Types**: `test-integration-lokole`, `test-integration-iiab`

```json
{
  "pr_number": 123,
  "ref": "feature/my-branch",
  "sha": "abc123def456...",
  "repo": "ascoderu/lokole"
}
```

**Accessed in workflow**:
```yaml
${{ github.event.client_payload.pr_number }}
${{ github.event.client_payload.ref }}
${{ github.event.client_payload.sha }}
${{ github.event.client_payload.repo }}
```

### Post-Merge Events

**Event Types**: `lokole-merged`, `iiab-merged`

```json
{
  "branch": "master",
  "sha": "def456abc789...",
  "repo": "ascoderu/lokole"
}
```

**Accessed in workflow**:
```yaml
${{ github.event.client_payload.branch }}
${{ github.event.client_payload.sha }}
${{ github.event.client_payload.repo }}
```

## Security Considerations

### Personal Access Token (PAT)

**Scope Requirements**:
- `repo`: Full control of private repositories
- `workflow`: Update GitHub Actions workflows

**Access Level**:
- Must have write access to `ascoderu/iiab-lokole-tests`
- Must have read access to source repositories

**Best Practices**:
1. Use a dedicated service account or bot account
2. Set expiration date (e.g., 90 days)
3. Rotate regularly
4. Limit to minimum required scopes
5. Store as repository secret (never commit to code)

### Webhook Security

GitHub `repository_dispatch` requires authentication:
- Token validated by GitHub API
- No webhook endpoint exposed
- Events only triggerable by authorized users with PAT

### PR Comment Permissions

To post comments back to PRs:
- PAT needs `repo` scope for target repository
- Action uses `github-script@v7` to create comments
- Only comments on PRs that triggered the test

## Testing the Setup

### 1. Verify Token Permissions

```bash
# Test token access to test repository
curl -H "Authorization: token YOUR_PAT" \
  https://api.github.com/repos/ascoderu/iiab-lokole-tests

# Should return repository details (not 404)
```

### 2. Manual Repository Dispatch

```bash
# Trigger test manually
curl -X POST \
  -H "Authorization: token YOUR_PAT" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/ascoderu/iiab-lokole-tests/dispatches \
  -d '{
    "event_type": "test-integration-lokole",
    "client_payload": {
      "pr_number": 999,
      "ref": "test-branch",
      "sha": "abc123",
      "repo": "ascoderu/lokole"
    }
  }'
```

### 3. Check Workflow Run

1. Go to https://github.com/ascoderu/iiab-lokole-tests/actions
2. Look for "Test on PR Label" workflow run
3. Verify it started within 1-2 minutes

### 4. Verify PR Comment

1. Check the test PR in source repository
2. Integration test results should appear as comment
3. Comment should include:
   - Test status (pass/fail)
   - Test output/logs
   - Link to workflow run

## Troubleshooting

### Issue: Workflow Not Triggering

**Possible Causes**:
1. PAT expired or invalid
2. Label name mismatch (case-sensitive)
3. Workflow file syntax error

**Debug Steps**:
```bash
# 1. Verify token is valid
curl -H "Authorization: token YOUR_PAT" \
  https://api.github.com/user

# 2. Check workflow syntax
cd /path/to/lokole
yamlint .github/workflows/trigger-integration-tests.yml

# 3. Review GitHub Actions logs
# Go to Actions tab → Select workflow → View logs
```

### Issue: PR Comments Not Posting

**Possible Causes**:
1. PAT lacks write access to source repo
2. `github-script` action failing
3. Repository name in payload incorrect

**Debug Steps**:
```yaml
# Add debug step to workflow
- name: Debug payload
  run: |
    echo "Repo: ${{ github.event.client_payload.repo }}"
    echo "PR: ${{ github.event.client_payload.pr_number }}"
```

### Issue: 403 Forbidden on Dispatch

**Cause**: PAT missing `workflow` scope

**Solution**: Regenerate PAT with both `repo` and `workflow` scopes

### Issue: 404 Not Found on Dispatch

**Cause**: Repository name incorrect or no access

**Solution**: 
1. Verify repository exists: `ascoderu/iiab-lokole-tests`
2. Check PAT has read access to repository

## Advanced Configurations

### Rate Limiting

GitHub API rate limits:
- Authenticated: 5,000 requests/hour
- repository_dispatch counts as 1 request

**Best Practice**: Use `synchronize` event to re-test on new commits

### Multiple Test Environments

To test different Ubuntu versions:

```yaml
# In trigger workflow, add environment info
client-payload: |
  {
    "pr_number": ${{ github.event.pull_request.number }},
    "ref": "${{ github.event.pull_request.head.ref }}",
    "sha": "${{ github.event.pull_request.head.sha }}",
    "repo": "${{ github.repository }}",
    "test_config": {
      "ubuntu_versions": ["22.04", "24.04"],
      "python_versions": ["3.9", "3.12"]
    }
  }
```

### Deployment Gates

Prevent merging if integration tests fail:

1. Add branch protection rule
2. Require status check: "test-pr / test-pr"
3. Must pass before merge allowed

## References

- [GitHub repository_dispatch documentation](https://docs.github.com/en/rest/repos/repos#create-a-repository-dispatch-event)
- [peter-evans/repository-dispatch action](https://github.com/peter-evans/repository-dispatch)
- [GitHub Actions: repository_dispatch event](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#repository_dispatch)
- [GitHub API rate limiting](https://docs.github.com/en/rest/overview/resources-in-the-rest-api#rate-limiting)
