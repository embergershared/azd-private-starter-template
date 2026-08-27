[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'naming.ps1')

function Invoke-AzJson {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    $json = & az @Arguments --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) {
        throw "az $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }

    return $json | ConvertFrom-Json
}

function Get-RequiredEnvironmentValue {
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $value = & azd env get-value $Name 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($value)) {
        throw "Required azd environment value '$Name' is not set."
    }

    return $value.Trim()
}

foreach ($command in @('az', 'azd')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command '$command' was not found."
    }
}

$subscriptionId = Get-RequiredEnvironmentValue -Name 'AZURE_SUBSCRIPTION_ID'
$location = Get-RequiredEnvironmentValue -Name 'AZURE_LOCATION'
$environmentName = Get-RequiredEnvironmentValue -Name 'AZURE_ENV_NAME'
$cachedSubscriptionCode = Get-RequiredEnvironmentValue -Name 'AZURE_SUBSCRIPTION_CODE'
$profile = (& azd env get-value DEPLOYMENT_PROFILE 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($profile)) {
    $profile = 'full'
}
$profile = $profile.Trim()

if ($profile -notin @('minimal', 'full')) {
    throw "DEPLOYMENT_PROFILE must be 'minimal' or 'full'; received '$profile'."
}

$featureOverridesJson = Get-RequiredEnvironmentValue -Name 'AZURE_FEATURE_OVERRIDES_JSON'
try {
    $featureOverrides = $featureOverridesJson | ConvertFrom-Json -AsHashtable
}
catch [System.ArgumentException] {
    throw 'AZURE_FEATURE_OVERRIDES_JSON must be a JSON object.'
}
if ($featureOverrides -isnot [System.Collections.IDictionary]) {
    throw 'AZURE_FEATURE_OVERRIDES_JSON must be a JSON object.'
}

$supportedFeatures = @(
    'bastion',
    'entraLogin',
    'linuxVm',
    'natGateway',
    'roleAssignments',
    'shutdownSchedules',
    'windowsVm'
)
foreach ($feature in $featureOverrides.Keys) {
    if ($feature -cnotin $supportedFeatures) {
        throw "Unsupported feature override '$feature'."
    }
    if ($featureOverrides[$feature] -isnot [bool]) {
        throw "Feature override '$feature' must be true or false."
    }
}

$featureSettings = @{
    bastion = $profile -eq 'full'
    entraLogin = $profile -eq 'full'
    linuxVm = $profile -eq 'full'
    natGateway = $profile -eq 'full'
    roleAssignments = $true
    shutdownSchedules = $profile -eq 'full'
    windowsVm = $profile -eq 'full'
}
foreach ($feature in $featureOverrides.Keys) {
    $featureSettings[$feature] = $featureOverrides[$feature]
}

if ($featureSettings.shutdownSchedules -and -not ($featureSettings.windowsVm -or $featureSettings.linuxVm)) {
    throw 'shutdownSchedules requires at least one jumpbox VM.'
}
if ($featureSettings.entraLogin -and -not ($featureSettings.windowsVm -or $featureSettings.linuxVm)) {
    throw 'entraLogin requires at least one jumpbox VM.'
}
if ($featureSettings.entraLogin -ne $featureSettings.natGateway) {
    throw 'natGateway and entraLogin must be enabled or disabled together; air-gapped deployments set both to false.'
}
if (($featureSettings.windowsVm -or $featureSettings.linuxVm) -and -not $featureSettings.bastion) {
    throw 'Jumpbox VMs require Bastion because this template configures no alternate private access path.'
}

if ($environmentName -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])$') {
    throw 'AZURE_ENV_NAME must contain 2-32 lowercase alphanumeric or hyphen characters and must start and end with an alphanumeric character.'
}
if ($location -cnotmatch '^[a-z0-9]+$') {
    throw "AZURE_LOCATION '$location' is not a valid Azure region name."
}
$parsedSubscriptionId = [Guid]::Empty
if (
    -not [Guid]::TryParseExact($subscriptionId, 'D', [ref] $parsedSubscriptionId) -or
    $parsedSubscriptionId -eq [Guid]::Empty
) {
    throw 'AZURE_SUBSCRIPTION_ID must be a non-empty GUID.'
}

$account = Invoke-AzJson -Arguments @('account', 'show', '--subscription', $subscriptionId)
if ($account.state -ne 'Enabled') {
    throw "Subscription '$subscriptionId' is not enabled."
}
$null = Assert-SubscriptionCode -SubscriptionName $account.name `
    -CachedCode $cachedSubscriptionCode

$locations = Invoke-AzJson -Arguments @('account', 'list-locations', '--query', "[?name=='$location'].name")
if ($locations.Count -eq 0) {
    throw "Azure location '$location' is not recognized."
}
$locationCatalogPath = Join-Path $PSScriptRoot '..\infra\location-codes.json'
$locationCode = Get-LocationCode -Location $location -CatalogPath $locationCatalogPath

$providers = @(
    'Microsoft.Authorization',
    'Microsoft.Insights',
    'Microsoft.KeyVault',
    'Microsoft.Network',
    'Microsoft.OperationalInsights',
    'Microsoft.Storage'
)
if ($featureSettings.windowsVm -or $featureSettings.linuxVm) {
    $providers += 'Microsoft.Compute'
}
if (
    $featureSettings.shutdownSchedules -and
    ($featureSettings.windowsVm -or $featureSettings.linuxVm)
) {
    $providers += 'Microsoft.DevTestLab'
}

$unregisteredProviders = foreach ($provider in $providers) {
    $state = & az provider show --namespace $provider --subscription $subscriptionId `
        --query registrationState --output tsv --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect provider '$provider'."
    }
    if ($state -ne 'Registered') {
        $provider
    }
}

if ($unregisteredProviders.Count -gt 0) {
    throw "Register these Azure providers before provisioning: $($unregisteredProviders -join ', ')."
}

$operatorPrincipalIdsCsv = (& azd env get-value AZURE_OPERATOR_PRINCIPAL_IDS 2>$null)
$operatorPrincipalIds = if (
    $LASTEXITCODE -ne 0 -or
    [string]::IsNullOrWhiteSpace($operatorPrincipalIdsCsv)
) {
    @()
}
else {
    @($operatorPrincipalIdsCsv.Split(',', [StringSplitOptions]::RemoveEmptyEntries) |
        ForEach-Object { $_.Trim() })
}
if ($featureSettings.roleAssignments -and $operatorPrincipalIds.Count -eq 0) {
    throw 'At least one Entra operator principal ID is required when role assignments are enabled.'
}
$seenPrincipalIds = [System.Collections.Generic.HashSet[Guid]]::new()
foreach ($principalId in $operatorPrincipalIds) {
    $parsedPrincipalId = [Guid]::Empty
    if (
        $principalId -isnot [string] -or
        -not [Guid]::TryParseExact($principalId, 'D', [ref] $parsedPrincipalId) -or
        $parsedPrincipalId -eq [Guid]::Empty
    ) {
        throw "Invalid Entra operator principal ID '$principalId'."
    }
    if (-not $seenPrincipalIds.Add($parsedPrincipalId)) {
        throw "Duplicate Entra operator principal ID '$principalId'."
    }
}

if ($featureSettings.windowsVm -or $featureSettings.linuxVm) {
    $vmSizes = @()
    if ($featureSettings.windowsVm) {
        $vmSizes += 'Standard_D4s_v5'
    }
    if ($featureSettings.linuxVm) {
        $vmSizes += 'Standard_D2s_v5'
    }
    foreach ($vmSize in $vmSizes) {
        $sku = Invoke-AzJson -Arguments @(
            'vm', 'list-skus',
            '--subscription', $subscriptionId,
            '--location', $location,
            '--size', $vmSize,
            '--all',
            '--query', "[?name=='$vmSize']"
        )

        $locationRestrictionCount = @(
            $sku[0].restrictions |
                Where-Object { $null -ne $_ -and $_.type -eq 'Location' }
        ).Count
        if ($sku.Count -eq 0 -or $locationRestrictionCount -gt 0) {
            throw "VM size '$vmSize' is unavailable or restricted in '$location'."
        }
    }

    if ($featureSettings.windowsVm) {
        $windowsUrn = 'MicrosoftWindowsDesktop:windows-11:win11-24h2-pro:latest'
        $null = Invoke-AzJson -Arguments @(
            'vm', 'image', 'show',
            '--subscription', $subscriptionId,
            '--location', $location,
            '--urn', $windowsUrn
        )
    }

    $regionalUsage = Invoke-AzJson -Arguments @(
        'vm', 'list-usage',
        '--subscription', $subscriptionId,
        '--location', $location,
        '--query', "[?localName=='Total Regional vCPUs' || localName=='Standard DSv5 Family vCPUs']"
    )

    foreach ($usage in $regionalUsage) {
        $requiredVcpus = $(if ($featureSettings.windowsVm) { 4 } else { 0 }) +
            $(if ($featureSettings.linuxVm) { 2 } else { 0 })
        if (($usage.limit - $usage.currentValue) -lt $requiredVcpus) {
            throw "Insufficient '$($usage.localName)' quota in '$location': $requiredVcpus vCPUs are required."
        }
    }
}

Write-Output "Preflight passed for environment '$environmentName' using profile '$profile' in '$location' ($locationCode) and subscription code '$cachedSubscriptionCode'."
