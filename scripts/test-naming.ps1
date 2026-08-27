[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'naming.ps1')

function Assert-Equal {
    param(
        [Parameter(Mandatory)]
        $Actual,

        [Parameter(Mandatory)]
        $Expected,

        [Parameter(Mandatory)]
        [string] $Message
    )

    if ($Actual -cne $Expected) {
        throw "$Message Expected '$Expected', received '$Actual'."
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Action,

        [Parameter(Mandatory)]
        [string] $Message
    )

    try {
        & $Action
    }
    catch {
        return
    }

    throw "$Message Expected an exception."
}

function Get-RepresentativeNames {
    param(
        [Parameter(Mandatory)]
        [hashtable] $Abbreviations,

        [Parameter(Mandatory)]
        [string] $LocationCode,

        [Parameter(Mandatory)]
        [string] $SubscriptionCode,

        [Parameter(Mandatory)]
        [string] $EnvironmentName
    )

    $hash = 'abc'
    $normalizedEnvironment = $EnvironmentName.Replace('-', '').ToLowerInvariant()
    $baseName = "$LocationCode-$SubscriptionCode-$EnvironmentName"
    $keyVaultEnvironmentLength = [Math]::Max(
        1,
        24 - "$($Abbreviations.keyVault)-$LocationCode-$SubscriptionCode--$hash".Length
    )
    $storageEnvironmentLength = [Math]::Max(
        1,
        24 - "$($Abbreviations.storageAccount)$LocationCode$SubscriptionCode$hash".Length
    )

    return @{
        resourceGroup = "$($Abbreviations.resourceGroup)-$baseName"
        virtualNetwork = "$($Abbreviations.virtualNetwork)-$baseName"
        bastionNsg = "$($Abbreviations.networkSecurityGroup)-$baseName-bastion"
        jumpboxNsg = "$($Abbreviations.networkSecurityGroup)-$baseName-jumpboxes"
        privateEndpointNsg = "$($Abbreviations.networkSecurityGroup)-$baseName-private-endpoints"
        jumpboxSubnet = "$($Abbreviations.subnet)-$baseName-jumpboxes"
        privateEndpointSubnet = "$($Abbreviations.subnet)-$baseName-private-endpoints"
        keyVault = "$($Abbreviations.keyVault)-$LocationCode-$SubscriptionCode-$($normalizedEnvironment.Substring(0, [Math]::Min($normalizedEnvironment.Length, $keyVaultEnvironmentLength)))-$hash"
        keyVaultPrivateEndpoint = "$($Abbreviations.privateEndpoint)-$baseName-kv"
        keyVaultPrivateEndpointNic = "$($Abbreviations.privateEndpointNetworkInterface)-$baseName-kv"
        storageAccount = "$($Abbreviations.storageAccount)$LocationCode$SubscriptionCode$($normalizedEnvironment.Substring(0, [Math]::Min($normalizedEnvironment.Length, $storageEnvironmentLength)))$hash"
        blobPrivateEndpoint = "$($Abbreviations.privateEndpoint)-$baseName-blob"
        blobPrivateEndpointNic = "$($Abbreviations.privateEndpointNetworkInterface)-$baseName-blob"
        filePrivateEndpoint = "$($Abbreviations.privateEndpoint)-$baseName-file"
        filePrivateEndpointNic = "$($Abbreviations.privateEndpointNetworkInterface)-$baseName-file"
        logAnalytics = "$($Abbreviations.logAnalytics)-$baseName"
        applicationInsights = "$($Abbreviations.applicationInsights)-$baseName"
        natGateway = "$($Abbreviations.natGateway)-$baseName"
        natPublicIp = "$($Abbreviations.publicIp)-$baseName-nat"
        bastion = "$($Abbreviations.bastion)-$baseName"
        bastionPublicIp = "$($Abbreviations.publicIp)-$baseName-bastion"
        windowsVm = "$($Abbreviations.windowsVirtualMachine)-$baseName"
        windowsComputerName = "w-$($normalizedEnvironment.Substring(0, [Math]::Min($normalizedEnvironment.Length, 9)))-$hash"
        windowsNic = "$($Abbreviations.networkInterface)-$baseName-win"
        linuxVm = "$($Abbreviations.linuxVirtualMachine)-$baseName"
        linuxNic = "$($Abbreviations.networkInterface)-$baseName-lin"
    }
}

$catalogPath = Join-Path $PSScriptRoot '..\infra\location-codes.json'
$abbreviationsPath = Join-Path $PSScriptRoot '..\infra\abbreviations.json'
$catalog = Get-Content -LiteralPath $catalogPath -Raw |
    ConvertFrom-Json -AsHashtable -ErrorAction Stop
$abbreviations = Get-Content -LiteralPath $abbreviationsPath -Raw |
    ConvertFrom-Json -AsHashtable -ErrorAction Stop

if ($catalog.Count -lt 50) {
    throw "The public-cloud location catalog unexpectedly contains only $($catalog.Count) entries."
}

$seenCodes = [System.Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal
)
foreach ($entry in $catalog.GetEnumerator()) {
    if ($entry.Key -cnotmatch '^[a-z0-9]+$') {
        throw "Location key '$($entry.Key)' is not canonical lowercase alphanumeric."
    }
    if ([string] $entry.Value -cnotmatch '^[a-z]{2}[a-z0-9]{0,3}$') {
        throw "Location '$($entry.Key)' has invalid code '$($entry.Value)'."
    }
    if (-not $seenCodes.Add([string] $entry.Value)) {
        throw "Location code '$($entry.Value)' is duplicated."
    }
}

Assert-Equal (Get-LocationCode -Location 'eastus2' -CatalogPath $catalogPath) 'use2' 'East US 2 code mismatch.'
Assert-Equal (Get-LocationCode -Location 'westus3' -CatalogPath $catalogPath) 'usw3' 'West US 3 code mismatch.'
Assert-Equal (Get-LocationCode -Location 'canadacentral' -CatalogPath $catalogPath) 'cac' 'Canada Central code mismatch.'
Assert-Throws { Get-LocationCode -Location 'moonbase1' -CatalogPath $catalogPath } 'Unknown locations must fail.'

Assert-Equal (Get-SubscriptionCode -SubscriptionName 'ME-MngEnvMCAP300003-emberger-1') 's1' 'One-digit subscription code mismatch.'
Assert-Equal (Get-SubscriptionCode -SubscriptionName 'example-1234') 's1234' 'Four-digit subscription code mismatch.'
Assert-Throws { Get-SubscriptionCode -SubscriptionName 'example' } 'Missing subscription token must fail.'
Assert-Throws { Get-SubscriptionCode -SubscriptionName 'example-final' } 'Nonnumeric subscription token must fail.'
Assert-Throws { Get-SubscriptionCode -SubscriptionName 'example-12345' } 'Five-digit subscription token must fail.'
Assert-Equal (Assert-SubscriptionCode -SubscriptionName 'example-3' -CachedCode 's3') 's3' 'Cached subscription code mismatch.'
Assert-Throws { Assert-SubscriptionCode -SubscriptionName 'example-3' -CachedCode 's1' } 'Subscription code drift must fail.'

$constraints = @{
    resourceGroup = @{ max = 90; pattern = '^[a-z0-9-]+$' }
    virtualNetwork = @{ max = 64; pattern = '^[a-z0-9-]+$' }
    bastionNsg = @{ max = 80; pattern = '^[a-z0-9-]+$' }
    jumpboxNsg = @{ max = 80; pattern = '^[a-z0-9-]+$' }
    privateEndpointNsg = @{ max = 80; pattern = '^[a-z0-9-]+$' }
    jumpboxSubnet = @{ max = 80; pattern = '^[a-z0-9-]+$' }
    privateEndpointSubnet = @{ max = 80; pattern = '^[a-z0-9-]+$' }
    keyVault = @{ max = 24; pattern = '^[a-z0-9-]+$' }
    keyVaultPrivateEndpoint = @{ max = 80; pattern = '^[a-z0-9-]+$' }
    keyVaultPrivateEndpointNic = @{ max = 80; pattern = '^[a-z0-9-]+$' }
    storageAccount = @{ max = 24; pattern = '^[a-z0-9]+$' }
    blobPrivateEndpoint = @{ max = 80; pattern = '^[a-z0-9-]+$' }
    blobPrivateEndpointNic = @{ max = 80; pattern = '^[a-z0-9-]+$' }
    filePrivateEndpoint = @{ max = 80; pattern = '^[a-z0-9-]+$' }
    filePrivateEndpointNic = @{ max = 80; pattern = '^[a-z0-9-]+$' }
    logAnalytics = @{ max = 63; pattern = '^[a-z0-9-]+$' }
    applicationInsights = @{ max = 255; pattern = '^[a-z0-9-]+$' }
    natGateway = @{ max = 80; pattern = '^[a-z0-9-]+$' }
    natPublicIp = @{ max = 80; pattern = '^[a-z0-9-]+$' }
    bastion = @{ max = 80; pattern = '^[a-z0-9-]+$' }
    bastionPublicIp = @{ max = 80; pattern = '^[a-z0-9-]+$' }
    windowsVm = @{ max = 64; pattern = '^[a-z0-9-]+$' }
    windowsComputerName = @{ max = 15; pattern = '^[a-z0-9-]+$' }
    windowsNic = @{ max = 80; pattern = '^[a-z0-9-]+$' }
    linuxVm = @{ max = 64; pattern = '^[a-z0-9-]+$' }
    linuxNic = @{ max = 80; pattern = '^[a-z0-9-]+$' }
}

foreach ($environmentName in @('poc', 'aca-private-acr', ('a' * 32))) {
    foreach ($subscriptionCode in @('s1', 's1234')) {
        $names = Get-RepresentativeNames -Abbreviations $abbreviations `
            -LocationCode 'use2' -SubscriptionCode $subscriptionCode `
            -EnvironmentName $environmentName
        foreach ($constraint in $constraints.GetEnumerator()) {
            $name = [string] $names[$constraint.Key]
            if ($name.Length -gt $constraint.Value.max) {
                throw "$($constraint.Key) name '$name' exceeds $($constraint.Value.max) characters."
            }
            if ($name -cnotmatch $constraint.Value.pattern) {
                throw "$($constraint.Key) name '$name' violates '$($constraint.Value.pattern)'."
            }
        }

        if ($names.keyVault -cnotmatch '-abc$' -or $names.storageAccount -cnotmatch 'abc$') {
            throw 'Globally unique names must retain the three-character hash.'
        }
        if ($names.keyVaultPrivateEndpoint -match '-kv-.*-kv-' -or
            $names.blobPrivateEndpoint -match '-stacct') {
            throw 'Child resource names must not embed a fully qualified parent name.'
        }
    }
}

Write-Output "Naming validation passed for $($catalog.Count) Azure public-cloud locations."
