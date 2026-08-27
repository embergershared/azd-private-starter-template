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
