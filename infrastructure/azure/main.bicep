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

@description('Ubuntu version for the VM')
@allowed([
  '22.04-LTS'
  '24.04-LTS'
])
param ubuntuVersion string = '22.04-LTS'

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
param runnerLabels string = 'azure-spot,self-hosted'

@description('Test PR number (for tagging/tracking)')
param prNumber string = ''

@description('Test run ID (for tagging/tracking)')
param runId string = uniqueString(resourceGroup().id, vmName)

@description('Max Spot price (-1 = pay up to regular price)')
param maxSpotPrice string = '-1'

// Variables
var networkSecurityGroupName = '${vmName}-nsg'
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
  - snapd

runcmd:
  # Install Multipass for nested VM support
  - snap install multipass

  # Create runner user
  - useradd -m -s /bin/bash runner
  - usermod -aG sudo runner
  - echo "runner ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner

  # Download and setup GitHub Actions runner
  - mkdir -p /home/runner/actions-runner
  - cd /home/runner/actions-runner
  - curl -o actions-runner-linux-x64.tar.gz -L https://github.com/actions/runner/releases/download/v2.313.0/actions-runner-linux-x64-2.313.0.tar.gz
  - tar xzf ./actions-runner-linux-x64.tar.gz
  - chown -R runner:runner /home/runner/actions-runner

  # Register runner (done via startup script that has secrets)
  - echo "Runner setup complete, ready for registration"

write_files:
  - path: /home/runner/register-runner.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -euo pipefail
      
      GITHUB_TOKEN="${GITHUB_TOKEN}"
      GITHUB_REPO="${GITHUB_REPO}"
      RUNNER_LABELS="${RUNNER_LABELS}"
      
      cd /home/runner/actions-runner
      
      # Get registration token
      REGISTRATION_TOKEN=$(curl -s -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/registration-token" \
        | jq -r .token)
      
      if [ -z "$REGISTRATION_TOKEN" ] || [ "$REGISTRATION_TOKEN" = "null" ]; then
        echo "Failed to get registration token"
        exit 1
      fi
      
      # Configure runner as ephemeral (self-destructs after one job)
      sudo -u runner ./config.sh \
        --url "https://github.com/${GITHUB_REPO}" \
        --token "${REGISTRATION_TOKEN}" \
        --name "$(hostname)" \
        --labels "${RUNNER_LABELS}" \
        --work _work \
        --ephemeral \
        --unattended
      
      # Install and start runner service
      sudo ./svc.sh install runner
      sudo ./svc.sh start
      
      echo "Runner registered and started successfully"

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
    purpose: 'github-runner'
    project: 'iiab-lokole-tests'
  }
}

// Virtual Network (shared across all runners)
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: virtualNetworkName
}

// If VNet doesn't exist, create it
resource vnetNew 'Microsoft.Network/virtualNetworks@2023-05-01' = if (false) {  // Only deploy if needed
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
        offer: '0001-com-ubuntu-server-jammy'
        sku: ubuntuVersion
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
    createdAt: utcNow()
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
    settings: {}
    protectedSettings: {
      script: base64('''#!/bin/bash
export GITHUB_TOKEN="${GITHUB_TOKEN}"
export GITHUB_REPO="${GITHUB_REPO}"
export RUNNER_LABELS="${RUNNER_LABELS}"

# Wait for cloud-init to complete
cloud-init status --wait

# Run registration script
sudo -u runner /home/runner/register-runner.sh

# Setup auto-shutdown after runner job completes
cat > /home/runner/auto-shutdown.sh << 'EOF'
#!/bin/bash
# Monitor runner and shutdown VM after job completes
while true; do
  if ! pgrep -f "Runner.Listener" > /dev/null; then
    echo "Runner process not found, initiating shutdown..."
    sudo shutdown -h now
    exit 0
  fi
  sleep 60
done
EOF

chmod +x /home/runner/auto-shutdown.sh
nohup /home/runner/auto-shutdown.sh > /var/log/auto-shutdown.log 2>&1 &
''')
      fileUris: []
      commandToExecute: 'bash -c "$(echo ${base64(format('export GITHUB_TOKEN="{0}"; export GITHUB_REPO="{1}"; export RUNNER_LABELS="{2}"', githubToken, githubRepository, runnerLabels))} | base64 -d)"'
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
