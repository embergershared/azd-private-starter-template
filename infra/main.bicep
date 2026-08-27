targetScope = 'subscription'

@description('Short azd environment name used in resource names and tags.')
@minLength(2)
@maxLength(32)
param environmentName string

@description('Azure region for the resource group and regional resources.')
param location string = 'eastus2'

@description('Stable code derived from the final numeric token of the Azure subscription display name.')
@minLength(2)
@maxLength(5)
param subscriptionCode string

@description('Deployment profile. Minimal excludes VMs, Bastion, NAT, and Entra login; full enables them plus shutdown schedules.')
@allowed([
  'minimal'
  'full'
])
param deploymentProfile string = 'full'

@description('Repository identifier applied to common tags.')
@minLength(1)
@maxLength(256)
param repository string = 'azure-azd-private-starter'

@description('Optional owner tag. Avoid personal data; prefer a team or service identifier.')
@maxLength(256)
param owner string = ''

@description('Optional cost-center tag.')
@maxLength(256)
param costCenter string = ''

@description('Creation timestamp seeded once by the azd preprovision hook.')
@minLength(25)
@maxLength(25)
param createdOn string

@description('Last-update timestamp refreshed by the azd preprovision hook.')
@minLength(25)
@maxLength(25)
param lastUpdatedOn string

@description('Deploy Standard Azure Bastion. Defaults on for the full profile.')
param enableBastion bool = deploymentProfile == 'full'

@description('Deploy the Windows 11 Pro jumpbox. Defaults on for the full profile.')
param enableWindowsVm bool = deploymentProfile == 'full'

@description('Deploy the Ubuntu jumpbox. Defaults on for the full profile.')
param enableLinuxVm bool = deploymentProfile == 'full'

@description('Enable outbound internet from the jumpbox subnet through a NAT Gateway. Defaults on for full and must be disabled with Entra login for air-gapped deployments.')
param enableNatGateway bool = deploymentProfile == 'full'

@description('Install Microsoft Entra login extensions on jumpbox VMs. Defaults on for full and must match the NAT Gateway setting.')
param enableEntraLogin bool = deploymentProfile == 'full'

@description('Optional MDM application ID passed to AADLoginForWindows. Leave empty for Entra login without automatic MDM enrollment.')
@maxLength(36)
param windowsMdmId string = ''

@description('Create VM auto-shutdown schedules. Defaults on for the full profile.')
param enableShutdownSchedules bool = deploymentProfile == 'full'

@description('Create configured operator RBAC assignments. Disable when the deployer lacks roleAssignments/write.')
param enableRoleAssignments bool = true

@description('Base64-encoded JSON object overriding profile feature flags. Supported keys: bastion, windowsVm, linuxVm, natGateway, entraLogin, shutdownSchedules, roleAssignments. natGateway and entraLogin must match.')
param featureOverridesBase64 string = 'e30='

@description('Comma-separated Entra user or group object IDs that receive VM login and private data-plane roles.')
param operatorPrincipalIdsCsv string = ''

@description('VNet address space. Default subnet parameters are derived from this /22.')
param vnetAddressPrefix string = '10.42.0.0/22'

@description('Azure Bastion subnet. Azure requires /26 or larger.')
param bastionSubnetPrefix string = cidrSubnet(vnetAddressPrefix, 26, 0)

@description('Private jumpbox subnet.')
param jumpboxSubnetPrefix string = cidrSubnet(vnetAddressPrefix, 26, 1)

@description('Private endpoint subnet.')
param privateEndpointSubnetPrefix string = cidrSubnet(vnetAddressPrefix, 27, 4)

@description('Windows VM size.')
param windowsVmSize string = 'Standard_D4s_v5'

@description('Ubuntu VM size.')
param linuxVmSize string = 'Standard_D2s_v5'

@description('Windows 11 Pro Marketplace image.')
param windowsImage object = {
  publisher: 'MicrosoftWindowsDesktop'
  offer: 'windows-11'
  sku: 'win11-24h2-pro'
  version: 'latest'
}

@description('Ubuntu Server 24.04 LTS Marketplace image.')
param linuxImage object = {
  publisher: 'Canonical'
  offer: 'ubuntu-24_04-lts'
  sku: 'server'
  version: 'latest'
}

@description('Local Windows break-glass account name.')
param windowsAdminUsername string = 'azurelocaladmin'

@description('Local Ubuntu break-glass account name.')
param linuxAdminUsername string = 'azurelocaladmin'

@description('Log Analytics retention in days.')
@minValue(30)
@maxValue(730)
param logRetentionInDays int = 30

@description('Log Analytics daily ingestion cap in GB.')
@minValue(1)
param logDailyCapGb int = 1

@description('Local auto-shutdown time in HHmm format.')
@minLength(4)
@maxLength(4)
param shutdownTime string = '1900'

@description('Windows time zone ID used by Azure DevTest Lab auto-shutdown schedules.')
param shutdownTimeZone string = 'Eastern Standard Time'

var abbreviations = loadJsonContent('./abbreviations.json')
var locationCodes = loadJsonContent('./location-codes.json')
var locationCode = string(locationCodes[location])
var normalizedEnvironmentName = toLower(replace(environmentName, '-', ''))
var shortUniqueSuffix = take(uniqueString(subscription().id, environmentName, location), 3)
var baseName = '${locationCode}-${subscriptionCode}-${environmentName}'
var keyVaultEnvironmentLength = max(
  1,
  24 - length('${abbreviations.keyVault}-${locationCode}-${subscriptionCode}--${shortUniqueSuffix}')
)
var storageEnvironmentLength = max(
  1,
  24 - length('${abbreviations.storageAccount}${locationCode}${subscriptionCode}${shortUniqueSuffix}')
)
var resourceGroupName = '${abbreviations.resourceGroup}-${baseName}'
var vnetName = '${abbreviations.virtualNetwork}-${baseName}'
var bastionNsgName = '${abbreviations.networkSecurityGroup}-${baseName}-bastion'
var jumpboxNsgName = '${abbreviations.networkSecurityGroup}-${baseName}-jumpboxes'
var privateEndpointNsgName = '${abbreviations.networkSecurityGroup}-${baseName}-private-endpoints'
var jumpboxSubnetName = '${abbreviations.subnet}-${baseName}-jumpboxes'
var privateEndpointSubnetName = '${abbreviations.subnet}-${baseName}-private-endpoints'
var keyVaultName = '${abbreviations.keyVault}-${locationCode}-${subscriptionCode}-${take(normalizedEnvironmentName, keyVaultEnvironmentLength)}-${shortUniqueSuffix}'
var keyVaultPrivateEndpointName = '${abbreviations.privateEndpoint}-${baseName}-kv'
var keyVaultPrivateEndpointNicName = '${abbreviations.privateEndpointNetworkInterface}-${baseName}-kv'
var storageAccountName = '${abbreviations.storageAccount}${locationCode}${subscriptionCode}${take(normalizedEnvironmentName, storageEnvironmentLength)}${shortUniqueSuffix}'
var blobPrivateEndpointName = '${abbreviations.privateEndpoint}-${baseName}-blob'
var blobPrivateEndpointNicName = '${abbreviations.privateEndpointNetworkInterface}-${baseName}-blob'
var filePrivateEndpointName = '${abbreviations.privateEndpoint}-${baseName}-file'
var filePrivateEndpointNicName = '${abbreviations.privateEndpointNetworkInterface}-${baseName}-file'
var logAnalyticsName = '${abbreviations.logAnalytics}-${baseName}'
var appInsightsName = '${abbreviations.applicationInsights}-${baseName}'
var natGatewayName = '${abbreviations.natGateway}-${baseName}'
var natGatewayPublicIpName = '${abbreviations.publicIp}-${baseName}-nat'
var bastionName = '${abbreviations.bastion}-${baseName}'
var bastionPublicIpName = '${abbreviations.publicIp}-${baseName}-bastion'
var windowsVmName = '${abbreviations.windowsVirtualMachine}-${baseName}'
var windowsComputerName = 'w-${take(normalizedEnvironmentName, 9)}-${shortUniqueSuffix}'
var windowsNicName = '${abbreviations.networkInterface}-${baseName}-win'
var linuxVmName = '${abbreviations.linuxVirtualMachine}-${baseName}'
var linuxNicName = '${abbreviations.networkInterface}-${baseName}-lin'
var commonTags = union(
  {
    repository: repository
    'azd-env-name': environmentName
    environment: environmentName
    profile: deploymentProfile
    'managed-by': 'azd'
    'created-on': createdOn
    'last-updated-on': lastUpdatedOn
  },
  empty(owner)
    ? {}
    : {
        owner: owner
      },
  empty(costCenter)
    ? {}
    : {
        'cost-center': costCenter
      }
)
var featureSettings = union(
  {
    bastion: enableBastion
    windowsVm: enableWindowsVm
    linuxVm: enableLinuxVm
    natGateway: enableNatGateway
    entraLogin: enableEntraLogin
    shutdownSchedules: enableShutdownSchedules
    roleAssignments: enableRoleAssignments
  },
  json(base64ToString(featureOverridesBase64))
)
var deployBastion = bool(featureSettings.bastion)
var deployWindowsVm = bool(featureSettings.windowsVm)
var deployLinuxVm = bool(featureSettings.linuxVm)
var deployNatGateway = bool(featureSettings.natGateway)
var deployEntraLogin = bool(featureSettings.entraLogin)
var deployShutdownSchedules = bool(featureSettings.shutdownSchedules)
var assignRoles = bool(featureSettings.roleAssignments)
var deployAnyVm = deployWindowsVm || deployLinuxVm
var operatorPrincipalIds = empty(operatorPrincipalIdsCsv)
  ? []
  : map(split(operatorPrincipalIdsCsv, ','), principalId => trim(principalId))

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: resourceGroupName
  location: location
  tags: commonTags
}

module natGateway './modules/nat-gateway.bicep' = {
  name: 'nat-gateway'
  scope: resourceGroup
  params: {
    name: natGatewayName
    publicIpName: natGatewayPublicIpName
    location: location
    tags: commonTags
    enabled: deployNatGateway
  }
}

module network './modules/network.bicep' = {
  name: 'network'
  scope: resourceGroup
  params: {
    name: vnetName
    bastionNetworkSecurityGroupName: bastionNsgName
    jumpboxNetworkSecurityGroupName: jumpboxNsgName
    privateEndpointNetworkSecurityGroupName: privateEndpointNsgName
    jumpboxSubnetName: jumpboxSubnetName
    privateEndpointSubnetName: privateEndpointSubnetName
    location: location
    tags: commonTags
    vnetAddressPrefix: vnetAddressPrefix
    bastionSubnetPrefix: bastionSubnetPrefix
    jumpboxSubnetPrefix: jumpboxSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    enableNatGateway: deployNatGateway
    natGatewayId: natGateway.outputs.natGatewayId
  }
}

module privateDns './modules/private-dns.bicep' = {
  name: 'private-dns'
  scope: resourceGroup
  params: {
    name: 'private-dns'
    location: 'global'
    tags: commonTags
    virtualNetworkId: network.outputs.virtualNetworkId
  }
}

module monitoring './modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: resourceGroup
  params: {
    name: logAnalyticsName
    location: location
    tags: commonTags
    applicationInsightsName: appInsightsName
    retentionInDays: logRetentionInDays
    dailyCapGb: logDailyCapGb
  }
}

module keyVault './modules/key-vault.bicep' = {
  name: 'key-vault'
  scope: resourceGroup
  params: {
    name: keyVaultName
    privateEndpointName: keyVaultPrivateEndpointName
    privateEndpointNetworkInterfaceName: keyVaultPrivateEndpointNicName
    location: location
    tags: commonTags
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    privateDnsZoneId: privateDns.outputs.keyVaultZoneId
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    enableWindowsVm: deployWindowsVm
    enableLinuxVm: deployLinuxVm
    windowsAdminUsername: windowsAdminUsername
    linuxAdminUsername: linuxAdminUsername
    enableRoleAssignments: assignRoles
    operatorPrincipalIds: operatorPrincipalIds
  }
}

resource deployedKeyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
  scope: resourceGroup
}

module storage './modules/storage.bicep' = {
  name: 'storage'
  scope: resourceGroup
  params: {
    name: storageAccountName
    blobPrivateEndpointName: blobPrivateEndpointName
    blobPrivateEndpointNetworkInterfaceName: blobPrivateEndpointNicName
    filePrivateEndpointName: filePrivateEndpointName
    filePrivateEndpointNetworkInterfaceName: filePrivateEndpointNicName
    location: location
    tags: commonTags
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    blobPrivateDnsZoneId: privateDns.outputs.blobZoneId
    filePrivateDnsZoneId: privateDns.outputs.fileZoneId
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    enableRoleAssignments: assignRoles
    operatorPrincipalIds: operatorPrincipalIds
  }
}

module bastion './modules/bastion.bicep' = if (deployBastion) {
  name: 'bastion'
  scope: resourceGroup
  params: {
    name: bastionName
    publicIpName: bastionPublicIpName
    location: location
    tags: commonTags
    bastionSubnetId: network.outputs.bastionSubnetId
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
  }
}

module jumpboxes './modules/jumpboxes.bicep' = if (deployAnyVm) {
  name: 'jumpboxes'
  scope: resourceGroup
  params: {
    windowsVmName: windowsVmName
    windowsComputerName: windowsComputerName
    windowsNicName: windowsNicName
    linuxVmName: linuxVmName
    linuxNicName: linuxNicName
    location: location
    tags: commonTags
    jumpboxSubnetId: network.outputs.jumpboxSubnetId
    deployWindowsVm: deployWindowsVm
    deployLinuxVm: deployLinuxVm
    windowsVmSize: windowsVmSize
    linuxVmSize: linuxVmSize
    windowsImage: windowsImage
    linuxImage: linuxImage
    windowsAdminUsername: windowsAdminUsername
    windowsAdminPassword: deployWindowsVm ? deployedKeyVault.getSecret('windows-admin-password') : ''
    linuxAdminUsername: linuxAdminUsername
    linuxAdminPassword: deployLinuxVm ? deployedKeyVault.getSecret('linux-admin-password') : ''
    enableEntraLogin: deployEntraLogin
    windowsMdmId: windowsMdmId
    credentialRotationTag: lastUpdatedOn
    enableShutdownSchedules: deployShutdownSchedules
    shutdownTime: shutdownTime
    shutdownTimeZone: shutdownTimeZone
    enableRoleAssignments: assignRoles
    operatorPrincipalIds: operatorPrincipalIds
  }
  dependsOn: [
    keyVault
  ]
}

output AZURE_RESOURCE_GROUP string = resourceGroup.name
output AZURE_VIRTUAL_NETWORK_NAME string = network.outputs.virtualNetworkName
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.keyVaultName
output AZURE_STORAGE_ACCOUNT_NAME string = storage.outputs.storageAccountName
output AZURE_LOG_ANALYTICS_WORKSPACE_ID string = monitoring.outputs.logAnalyticsWorkspaceId
output AZURE_APPLICATION_INSIGHTS_NAME string = monitoring.outputs.applicationInsightsName
output AZURE_BASTION_NAME string = deployBastion ? bastion!.outputs.bastionName : ''
output AZURE_WINDOWS_VM_NAME string = deployWindowsVm ? jumpboxes!.outputs.windowsVmName : ''
output AZURE_LINUX_VM_NAME string = deployLinuxVm ? jumpboxes!.outputs.linuxVmName : ''
