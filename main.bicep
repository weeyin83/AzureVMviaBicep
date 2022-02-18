@description('Storage Account name')
param storagename string = 'storage${uniqueString(resourceGroup().id)}'

@description('VM DNS label prefix')
param vm_dns string = 'octopusworker-${uniqueString(resourceGroup().id)}'

@description('Admin user for VM')
param adminUser string

@secure()
param adminPassword string

@description('Computer Name')
param computerName string

@description('VM size for VM')
param vmsize string

@description('SKU of the Windows Server')
@allowed([
  '2019-datacenter'
  '2019-datacenter-core-smalldisk-g2'
  '2022-datacenter-core-g2'
  '2022-datacenter-core-smalldisk-g2'
  '2022-datacenter-azure-edition-core'
  '2022-datacenter-azure-edition-core-smalldisk'
])
param vmSku string

@description('SKU of the attached data disk (Standard HDD, Standard SSD or Premium SSD)')
@allowed([
  'Standard_LRS'
  'StandardSSD_LRS'
  'Premium_LRS'
])
param diskSku string

@description('Size of the attached data disk in GB')
param diskSizeGB int = 256

@description('Deployment location')
param location string = resourceGroup().location


resource storageAccount 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: toLower(storagename)
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'Storage'
  tags: {
    displayName: 'Storage account'
  }
}

resource publicIP 'Microsoft.Network/publicIPAddresses@2020-11-01' = {
  name: 'publicIP'
  location: location
  tags: {
    displayName: 'PublicIPAddress'
  }
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    dnsSettings: {
      domainNameLabel: vm_dns
    }
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2020-04-01' = {
  name: 'nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'rdp'
        properties: {
          description: 'description'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'http'
        properties: {
          description: 'description'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2020-04-01' = {
  name: 'virtualNetwork'
  location: location
  tags: {
    displayName: 'Virtual Network'
  }
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet'
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2020-04-01' = {
  name: 'nic'
  location: location
  tags: {
    displayName: 'Network Interface'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'ipConfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIP.id
          }
          subnet: {
            id: virtualNetwork.properties.subnets[0].id
          }
        }
      }
    ]
  }
}

resource datadisk 'Microsoft.Compute/disks@2020-09-30' = {
  name: 'datadisk'
  location: location
  properties: {
    diskSizeGB: diskSizeGB
    creationData: {
      createOption: 'Empty'
    }
  }
  sku: {
    name: diskSku
  }
}

resource octopusworker 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: 'octopus-worker'
  location: location
  tags: {
    displayName: 'WIndows Server'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmsize
    }
    osProfile: {
      computerName: computerName
      adminUsername: adminUser
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: vmSku
        version: 'latest'
      }
      osDisk: {
        name: 'osdisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
      }
      dataDisks: [
        {
          createOption: 'Attach'
          lun: 0
          managedDisk: {
            id: datadisk.id
          }
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: storageAccount.properties.primaryEndpoints.blob
      }
    }
  }
}

resource quickinstall 'Microsoft.Compute/virtualMachines/extensions@2020-12-01' = {
  parent:octopusworker
  name: 'chocoinstalltool'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.3'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        'https://gist.githubusercontent.com/weeyin83/8816049ce235d02a7c2fab5f2faf0448/raw/2af41c9bddbbc9301dd4ea058393a04a6e583b18/quickinstall.ps1'
      ]
      commandToExecute: 'powershell.exe -File quickinstall.ps1'
    }
  }
}
