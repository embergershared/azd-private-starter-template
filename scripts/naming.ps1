function Get-SubscriptionCode {
    param(
        [Parameter(Mandatory)]
        [string] $SubscriptionName
    )

    $match = [regex]::Match($SubscriptionName.Trim(), '-(?<number>[0-9]{1,4})$')
    if (-not $match.Success) {
        throw "Subscription display name '$SubscriptionName' must end with a hyphen-delimited 1-4 digit token, such as '-1'."
    }

    return "s$($match.Groups['number'].Value)"
}

function Assert-SubscriptionCode {
    param(
        [Parameter(Mandatory)]
        [string] $SubscriptionName,

        [Parameter(Mandatory)]
        [string] $CachedCode
    )

    $derivedCode = Get-SubscriptionCode -SubscriptionName $SubscriptionName
    if ($CachedCode.Trim() -cne $derivedCode) {
        throw "Cached subscription code '$($CachedCode.Trim())' does not match '$derivedCode' derived from subscription '$SubscriptionName'."
    }

    return $derivedCode
}

function Get-LocationCode {
    param(
        [Parameter(Mandatory)]
        [string] $Location,

        [Parameter(Mandatory)]
        [string] $CatalogPath
    )

    try {
        $catalog = Get-Content -LiteralPath $CatalogPath -Raw |
            ConvertFrom-Json -AsHashtable -ErrorAction Stop
    }
    catch {
        throw "Unable to load the Azure location-code catalog '$CatalogPath': $($_.Exception.Message)"
    }

    $canonicalLocation = $Location.Trim().ToLowerInvariant()
    if (-not $catalog.ContainsKey($canonicalLocation)) {
        throw "Azure location '$Location' has no approved code in '$CatalogPath'."
    }

    $code = [string] $catalog[$canonicalLocation]
    if ($code -cnotmatch '^[a-z]{2}[a-z0-9]{0,3}$') {
        throw "Azure location '$canonicalLocation' has invalid code '$code'; codes must be 2-5 lowercase alphanumeric characters and start with two letters."
    }

    return $code
}

# --------------------------------------------------------------------------
# PowerShell mirror of infra/core/naming.bicep.
#
# These functions must stay byte-for-byte equivalent to the Bicep exports.
# tests/naming.tests.ps1 renders the compiled ARM template and compares it to
# these, so a divergence fails the suite rather than silently producing a
# second naming convention.
# --------------------------------------------------------------------------

function Get-CoreCatalogPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $FileName
    )

    $repoRoot = Split-Path -Parent $PSScriptRoot
    $path = Join-Path $repoRoot "infra/core/$FileName"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Core catalog '$FileName' was not found at '$path'."
    }

    return $path
}

function Get-Abbreviation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Key,

        [string] $CatalogPath
    )

    if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
        $CatalogPath = Get-CoreCatalogPath -FileName 'abbreviations.json'
    }

    $catalog = Get-Content -LiteralPath $CatalogPath -Raw |
        ConvertFrom-Json -AsHashtable -ErrorAction Stop

    if (-not $catalog.ContainsKey($Key)) {
        throw "Resource type '$Key' has no approved abbreviation in '$CatalogPath'."
    }

    return [string] $catalog[$Key]
}

function Get-NormalizedEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $EnvironmentName
    )

    return $EnvironmentName.Replace('-', '').ToLowerInvariant()
}

function Get-BaseName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $LocationCode,
        [Parameter(Mandatory)] [string] $SubscriptionCode,
        [Parameter(Mandatory)] [string] $EnvironmentName
    )

    return "$LocationCode-$SubscriptionCode-$EnvironmentName"
}

function Get-AzName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Abbreviation,
        [Parameter(Mandatory)] [string] $LocationCode,
        [Parameter(Mandatory)] [string] $SubscriptionCode,
        [Parameter(Mandatory)] [string] $EnvironmentName,

        [AllowEmptyString()]
        [string] $Suffix = ''
    )

    $body = Get-BaseName -LocationCode $LocationCode `
        -SubscriptionCode $SubscriptionCode -EnvironmentName $EnvironmentName

    if ([string]::IsNullOrEmpty($Suffix)) {
        return "$Abbreviation-$body"
    }

    return "$Abbreviation-$body-$Suffix"
}

function Get-GlobalName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Abbreviation,
        [Parameter(Mandatory)] [string] $LocationCode,
        [Parameter(Mandatory)] [string] $SubscriptionCode,
        [Parameter(Mandatory)] [string] $EnvironmentName,
        [Parameter(Mandatory)] [string] $ShortHash,

        [AllowEmptyString()]
        [string] $Separator = '-',

        [int] $Budget = 24
    )

    $fixed = "$Abbreviation$Separator$LocationCode$Separator$SubscriptionCode$Separator$Separator$ShortHash"
    $allowance = [Math]::Max(1, $Budget - $fixed.Length)
    $environment = Get-NormalizedEnvironment -EnvironmentName $EnvironmentName
    $trimmed = $environment.Substring(0, [Math]::Min($allowance, $environment.Length))

    return "$Abbreviation$Separator$LocationCode$Separator$SubscriptionCode$Separator$trimmed$Separator$ShortHash"
}

function Get-ShortName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Prefix,
        [Parameter(Mandatory)] [string] $EnvironmentName,
        [Parameter(Mandatory)] [string] $ShortHash,

        [int] $Budget = 15
    )

    $allowance = [Math]::Max(1, $Budget - "$Prefix--$ShortHash".Length)
    $environment = Get-NormalizedEnvironment -EnvironmentName $EnvironmentName
    $trimmed = $environment.Substring(0, [Math]::Min($allowance, $environment.Length))

    return "$Prefix-$trimmed-$ShortHash"
}

function Get-CommonTags {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Repository,
        [Parameter(Mandatory)] [string] $EnvironmentName,
        [Parameter(Mandatory)] [string] $DeploymentProfile,
        [Parameter(Mandatory)] [string] $CreatedOn,
        [Parameter(Mandatory)] [string] $LastUpdatedOn,

        [AllowEmptyString()] [string] $Owner = '',
        [AllowEmptyString()] [string] $CostCenter = ''
    )

    $tags = [ordered] @{
        repository        = $Repository
        'azd-env-name'    = $EnvironmentName
        environment       = $EnvironmentName
        profile           = $DeploymentProfile
        'managed-by'      = 'azd'
        'created-on'      = $CreatedOn
        'last-updated-on' = $LastUpdatedOn
    }

    if (-not [string]::IsNullOrEmpty($Owner)) {
        $tags['owner'] = $Owner
    }

    if (-not [string]::IsNullOrEmpty($CostCenter)) {
        $tags['cost-center'] = $CostCenter
    }

    return $tags
}

function Get-TemplateVersion {
    [CmdletBinding()]
    param(
        [string] $AzureYamlPath
    )

    if ([string]::IsNullOrWhiteSpace($AzureYamlPath)) {
        $AzureYamlPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'azure.yaml'
    }

    if (-not (Test-Path -LiteralPath $AzureYamlPath)) {
        throw "Unable to determine the template version: '$AzureYamlPath' was not found."
    }

    $content = Get-Content -LiteralPath $AzureYamlPath -Raw
    $match = [regex]::Match($content, '(?m)^\s*template:\s*(?<name>[^@\s]+)@(?<version>[^\s]+)\s*$')
    if (-not $match.Success) {
        throw "'$AzureYamlPath' does not declare a 'metadata.template' value of the form '<name>@<version>'."
    }

    return [pscustomobject] @{
        Name    = $match.Groups['name'].Value
        Version = $match.Groups['version'].Value
        Stamp   = "$($match.Groups['name'].Value)@$($match.Groups['version'].Value)"
    }
}

function Get-RepositoryName {
    [CmdletBinding()]
    param(
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Split-Path -Parent $PSScriptRoot
    }

    $remote = $null
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $remote = & git -C $Path remote get-url origin 2>$null
        if ($LASTEXITCODE -ne 0) {
            $remote = $null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($remote)) {
        $trimmed = $remote.Trim() -replace '\.git$', ''
        # Accepts https://host/owner/repo, git@host:owner/repo and ssh://host/owner/repo.
        $match = [regex]::Match($trimmed, '(?<owner>[^/:]+)/(?<repo>[^/]+)$')
        if ($match.Success) {
            return "$($match.Groups['owner'].Value)/$($match.Groups['repo'].Value)"
        }
    }

    return (Split-Path -Leaf (Resolve-Path -LiteralPath $Path).Path)
}
