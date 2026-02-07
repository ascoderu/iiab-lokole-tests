// Bicep template for cleaning up orphaned runner VMs
// Deletes VMs older than specified age to prevent cost leaks

@description('Maximum age for VMs in hours (VMs older than this will be deleted)')
param maxAgeHours int = 2

@description('Resource group name to clean')
param resourceGroupName string = resourceGroup().name

@description('Dry run - list VMs that would be deleted without actually deleting')
param dryRun bool = true

// This template is meant to be deployed with Azure CLI script
// The actual cleanup logic is in scripts/azure/cleanup-orphaned-vms.sh

output cleanupConfig object = {
  maxAgeHours: maxAgeHours
  resourceGroupName: resourceGroupName
  dryRun: dryRun
  targetTags: {
    purpose: 'github-runner'
    ephemeral: 'true'
  }
}
