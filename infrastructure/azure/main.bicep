// Azure Bicep Template for Ephemeral GitHub Actions Self-Hosted Runner
// Provisions a Spot VM configured to run IIAB integration tests

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique name for this runner VM')
param vmName string

@description('Azure VM size')
@allowed([
  'Standard_B1s'   // 1 vCPU, 1 GB RAM - Too small
  'Standard_B2s'   // 2 vCPU, 4 GB RAM - Recommended minimum
  'Standard_B2ms'  // 2 vCPU, 8 GB RAM - More RAM
  'Standard_B4ms'  // 4 vCPU, 16 GB RAM - Overkill
  'Standard_D2s_v3' // 2 vCPU, 8 GB RAM - More CPU
])
param vmSize string = 'Standard_B2s'

@description('Use Spot VM for cost savings (recommended)')
param useSpotInstance bool = true

@description('Azure Marketplace image offer')
param imageOffer string = '0001-com-ubuntu-server-jammy'

@description('Azure Marketplace image SKU')
param imageSku string = '22_04-lts-gen2'

@description('Admin username for the VM')
param adminUsername string = 'azureuser'

@description('SSH public key for VM access')
@secure()
param sshPublicKey string

@description('GitHub repository for runner registration (format: owner/repo)')
param githubRepository string = 'ascoderu/iiab-lokole-tests'

@description('GitHub Personal Access Token for runner registration')
@secure()
param githubToken string

@description('Runner labels (comma-separated)')
param runnerLabels string = 'azure,self-hosted'

@description('Test PR number (for tagging/tracking)')
param prNumber string = ''

@description('Test run ID (for tagging/tracking)')
param runId string = uniqueString(resourceGroup().id, vmName)

@description('Max Spot price (-1 = pay up to regular price)')
param maxSpotPrice string = '-1'

// Variables
var networkSecurityGroupName = 'iiab-lokole-runners-nsg'  // Shared NSG for all runners
var virtualNetworkName = 'iiab-lokole-vnet'
var subnetName = 'runners-subnet'
var publicIPAddressName = '${vmName}-pip'
var networkInterfaceName = '${vmName}-nic'
var osDiskName = '${vmName}-osdisk'
var diskSizeGB = 32  // 30 GB needed for IIAB + VM + runner

// Cloud-init script for runner setup
var cloudInit = base64('''#cloud-config
package_update: true
package_upgrade: true

packages:
  - curl
  - jq
  - git
  - build-essential
  - libssl-dev
  - libffi-dev
  - python3-dev

runcmd:
  # Create runner user
  - useradd -m -s /bin/bash runner
  - usermod -aG sudo runner
  - echo "runner ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner

  # Download and setup GitHub Actions runner
  - mkdir -p /home/runner/actions-runner
  - cd /home/runner/actions-runner
  - curl -o actions-runner-linux-x64.tar.gz -L https://github.com/actions/runner/releases/download/v2.313.0/actions-runner-linux-x64-2.313.0.tar.gz
  - tar xzf ./actions-runner-linux-x64.tar.gz
  - rm actions-runner-linux-x64.tar.gz
  - chown -R runner:runner /home/runner/actions-runner

  # Install runner dependencies
  - cd /home/runner/actions-runner
  - ./bin/installdependencies.sh

  # Create registration script placeholder (will be populated by Custom Script Extension)
  - mkdir -p /home/runner/scripts
  - chown runner:runner /home/runner/scripts

  - echo "Runner VM setup complete, awaiting registration"

final_message: "GitHub Actions runner VM provisioned at $TIMESTAMP"
''')

// Network Security Group with minimal access
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: networkSecurityGroupName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'  // Restrict this to your IP for production
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'AllowHTTPSOutbound'
        properties: {
          priority: 1100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowHTTPOutbound'
        properties: {
          priority: 1110
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '80'
        }
      }
    ]
  }
  tags: {
    purpose: 'github-runners'
    project: 'iiab-lokole-tests'
    // No runId - shared across all workflow runs
  }
}

// Virtual Network - create if it doesn't exist (idempotent)
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
  tags: {
    purpose: 'github-runners'
    project: 'iiab-lokole-tests'
  }
}

// Public IP (optional - can be removed for private runners)
resource publicIP 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: publicIPAddressName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: toLower(vmName)
    }
  }
  tags: {
    purpose: 'github-runner'
    project: 'iiab-lokole-tests'
    prNumber: prNumber
    runId: runId
  }
}

// Network Interface
resource nic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: networkInterfaceName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIP.id
            properties: {
              deleteOption: 'Delete'  // Auto-delete public IP when NIC is deleted
            }
          }
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, subnetName)
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
  tags: {
    purpose: 'github-runner'
    project: 'iiab-lokole-tests'
    prNumber: prNumber
    runId: runId
  }
  dependsOn: [
    vnet
  ]
}

// Virtual Machine
resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    priority: useSpotInstance ? 'Spot' : 'Regular'
    evictionPolicy: useSpotInstance ? 'Deallocate' : null
    billingProfile: useSpotInstance ? {
      maxPrice: maxSpotPrice == '-1' ? json('-1') : json(maxSpotPrice)
    } : null
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: imageOffer
        sku: imageSku
        version: 'latest'
      }
      osDisk: {
        name: osDiskName
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'  // SSD for better performance
        }
        diskSizeGB: diskSizeGB
        deleteOption: 'Delete'  // Auto-delete disk when VM is deleted
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      customData: cloudInit
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Delete'  // Auto-delete NIC when VM is deleted
          }
        }
      ]
    }
  }
  tags: {
    purpose: 'github-runner'
    project: 'iiab-lokole-tests'
    prNumber: prNumber
    runId: runId
    createdAtRunId: runId  // Unique identifier for creation time tracking
    ephemeral: 'true'
  }
}

// VM Extension to run runner registration script
resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: vm
  name: 'register-github-runner'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      script: base64(replace(replace(replace(loadTextContent('../../scripts/azure/runner-setup-wrapper.sh'), '__GITHUB_TOKEN__', githubToken), '__GITHUB_REPO__', githubRepository), '__RUNNER_LABELS__', runnerLabels))
    }
  }
}

// Outputs
output vmName string = vm.name
output publicIP string = publicIP.properties.ipAddress
output fqdn string = publicIP.properties.dnsSettings.fqdn
output vmId string = vm.id
output vmSize string = vmSize
output useSpot bool = useSpotInstance
output estimatedHourlyCost string = useSpotInstance ? '$0.0045' : '$0.015'

