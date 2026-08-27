targetScope = 'resourceGroup'

param name string
@minLength(2)
@maxLength(80)
param publicIpName string
param location string = resourceGroup().location
param tags object = {}
param enabled bool = false

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-07-01' = if (enabled) {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 10
  }
}

resource natGateway 'Microsoft.Network/natGateways@2024-07-01' = if (enabled) {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 10
    publicIpAddresses: [
      {
        id: publicIp.id
      }
    ]
  }
}

output natGatewayId string = enabled ? natGateway!.id : ''
