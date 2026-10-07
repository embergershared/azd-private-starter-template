# Naming rules and the zero-drift proof.
#
# The refactor moved the resource-name algorithm out of infra/main.bicep and into
# infra/core/naming.bicep. An environment is already deployed from the previous
# algorithm, and a changed name means a replaced resource, so the equivalence
# below is the gate on the whole refactor.
#
# The proof has two independent legs:
#   1. tests/fixtures/legacy-naming.ps1 is a frozen transcription of the
#      pre-refactor algorithm. Its output is committed as legacy-names.golden.json.
#   2. The *compiled* ARM of infra/main.bicep is evaluated offline and compared
#      to that golden file, name by name.
# Leg 2 is what makes the proof binding: it exercises the Bicep the deployment
# actually uses, not a PowerShell restatement of it.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'arm-expression.ps1')
. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'fixtures\legacy-naming.ps1')
. (Join-Path (Get-RepoRoot) 'scripts\naming.ps1')

$abbreviationsPath = Get-RepoPath 'infra\core\abbreviations.json'
$locationCodesPath = Get-RepoPath 'infra\core\location-codes.json'
$nameRulesPath = Get-RepoPath 'infra\core\name-rules.json'
$goldenPath = Get-RepoPath 'tests\fixtures\legacy-names.golden.json'

$abbreviations = Get-Content -LiteralPath $abbreviationsPath -Raw | ConvertFrom-Json -AsHashtable
$locationCodes = Get-Content -LiteralPath $locationCodesPath -Raw | ConvertFrom-Json -AsHashtable
$nameRules = Get-Content -LiteralPath $nameRulesPath -Raw | ConvertFrom-Json -AsHashtable
$golden = Get-Content -LiteralPath $goldenPath -Raw | ConvertFrom-Json -AsHashtable
$matrix = Get-LegacyNameMatrix

Test-Case 'golden name file still matches the frozen legacy algorithm' {
    Assert-Equal $golden.Count $matrix.Count 'Golden row count drifted from the input matrix.'

    for ($i = 0; $i -lt $matrix.Count; $i++) {
        $case = $matrix[$i]
        $row = $golden[$i]

        Assert-Equal $row.environmentName $case.EnvironmentName "Row $i environment name drifted."
        Assert-Equal $row.subscriptionCode $case.SubscriptionCode "Row $i subscription code drifted."
        Assert-Equal $row.locationCode $case.LocationCode "Row $i location code drifted."

        $expected = Get-LegacyNames -Abbreviations $abbreviations `
            -LocationCode $case.LocationCode -SubscriptionCode $case.SubscriptionCode `
            -EnvironmentName $case.EnvironmentName -ShortUniqueSuffix $case.ShortUniqueSuffix

        foreach ($key in $expected.Keys) {
            Assert-Equal ([string] $row.names[$key]) ([string] $expected[$key]) `
                "Row $i golden name '$key' no longer matches the frozen algorithm."
        }
    }
}

Test-Case 'compiled infra/main.bicep reproduces every pre-refactor resource name' {
    $template = Get-CompiledTemplate -BicepPath (Get-RepoPath 'infra\main.bicep')
    $map = Get-NameVariableMap

    $firstRow = $golden[0]
    foreach ($key in $firstRow.names.Keys) {
        Assert-True $map.ContainsKey($key) `
            "The frozen fixture produces '$key' but no infra/main.bicep variable is mapped to it."
    }

    for ($i = 0; $i -lt $matrix.Count; $i++) {
        $case = $matrix[$i]
        $rendered = Get-BicepRenderedNames -Template $template `
            -LocationCode $case.LocationCode -SubscriptionCode $case.SubscriptionCode `
            -EnvironmentName $case.EnvironmentName -ShortUniqueSuffix $case.ShortUniqueSuffix

        foreach ($key in $golden[$i].names.Keys) {
            Assert-Equal $rendered[$key] ([string] $golden[$i].names[$key]) `
                ("Resource name drift for '$key' at environment '$($case.EnvironmentName)', " +
                "subscription '$($case.SubscriptionCode)', location '$($case.LocationCode)'. " +
                'Deploying this would REPLACE the existing resource.')
        }
    }
}

Test-Case 'the deployed my-azd-env-test names are unchanged' {
    # The environment in .azure/my-azd-env-test is live. Pinning it explicitly
    # makes a regression name the affected environment instead of a matrix index.
    $template = Get-CompiledTemplate -BicepPath (Get-RepoPath 'infra\main.bicep')
    $rendered = Get-BicepRenderedNames -Template $template -LocationCode 'use2' `
        -SubscriptionCode 's1' -EnvironmentName 'my-azd-env-test' -ShortUniqueSuffix 'abc'
    $expected = Get-LegacyNames -Abbreviations $abbreviations -LocationCode 'use2' `
        -SubscriptionCode 's1' -EnvironmentName 'my-azd-env-test' -ShortUniqueSuffix 'abc'

    foreach ($key in $expected.Keys) {
        Assert-Equal $rendered[$key] ([string] $expected[$key]) "my-azd-env-test '$key' drifted."
    }
}

Test-Case 'every rendered name satisfies infra/core/name-rules.json' {
    $template = Get-CompiledTemplate -BicepPath (Get-RepoPath 'infra\main.bicep')

    foreach ($case in $matrix) {
        $rendered = Get-BicepRenderedNames -Template $template `
            -LocationCode $case.LocationCode -SubscriptionCode $case.SubscriptionCode `
            -EnvironmentName $case.EnvironmentName -ShortUniqueSuffix $case.ShortUniqueSuffix

        foreach ($key in $rendered.Keys) {
            Assert-True $nameRules.resources.ContainsKey($key) `
                "infra/core/name-rules.json has no rule for '$key'."
            $rule = $nameRules.resources[$key]
            $name = [string] $rendered[$key]
            $minLength = if ($rule.ContainsKey('minLength')) { [int] $rule.minLength } else { 1 }

            Assert-True ($name.Length -le $rule.maxLength) `
                "'$key' name '$name' is $($name.Length) characters, over the $($rule.maxLength) limit."
            Assert-True ($name.Length -ge $minLength) `
                "'$key' name '$name' is shorter than the $minLength character minimum."
            Assert-Match $name $rule.charset "'$key' violates its charset rule."
            if ($rule.case -eq 'lower') {
                Assert-Equal $name $name.ToLowerInvariant() "'$key' name must be lowercase."
            }
            Assert-True $nameRules.classes.ContainsKey($rule.class) `
                "'$key' references the undefined name class '$($rule.class)'."
        }
    }
}

Test-Case 'globally unique names keep prefix, location, subscription and hash' {
    $template = Get-CompiledTemplate -BicepPath (Get-RepoPath 'infra\main.bicep')

    foreach ($case in $matrix) {
        $rendered = Get-BicepRenderedNames -Template $template `
            -LocationCode $case.LocationCode -SubscriptionCode $case.SubscriptionCode `
            -EnvironmentName $case.EnvironmentName -ShortUniqueSuffix $case.ShortUniqueSuffix

        $hash = $case.ShortUniqueSuffix
        Assert-Match $rendered.keyVault "^$($abbreviations.keyVault)-$($case.LocationCode)-$($case.SubscriptionCode)-.+-$hash$" `
            'Key Vault name lost a mandatory segment.'
        Assert-Match $rendered.storageAccount "^$($abbreviations.storageAccount)$($case.LocationCode)$($case.SubscriptionCode).+$hash$" `
            'Storage account name lost a mandatory segment.'
        Assert-Match $rendered.windowsComputerName "^w-.+-$hash$" `
            'Windows computer name lost a mandatory segment.'
    }
}

Test-Case 'AzureBastionSubnet keeps its Azure-mandated name' {
    Assert-True $nameRules.reserved.ContainsKey('AzureBastionSubnet') `
        'The reserved Bastion subnet name must stay exactly AzureBastionSubnet.'

    $networkBicep = Get-Content -LiteralPath (Get-RepoPath 'infra\modules\network\main.bicep') -Raw
    Assert-True ($networkBicep -cmatch "'AzureBastionSubnet'") `
        'The network module must still hard-code AzureBastionSubnet.'
}

Test-Case 'the location-code catalog is complete and unambiguous' {
    Assert-True ($locationCodes.Count -ge 50) `
        "The public-cloud location catalog unexpectedly contains only $($locationCodes.Count) entries."

    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $locationCodes.GetEnumerator()) {
        Assert-Match ([string] $entry.Key) '^[a-z0-9]+$' 'Location key is not canonical lowercase alphanumeric.'
        Assert-Match ([string] $entry.Value) '^[a-z]{2}[a-z0-9]{0,3}$' "Location '$($entry.Key)' has an invalid code."
        Assert-True ($seen.Add([string] $entry.Value)) "Location code '$($entry.Value)' is duplicated."
    }
}

Test-Case 'Get-LocationCode agrees with the Bicep locationCodeFor function' {
    $template = Get-CompiledTemplate -BicepPath (Get-RepoPath 'infra\main.bicep')

    foreach ($location in @('eastus2', 'westus3', 'canadacentral')) {
        $fromScript = Get-LocationCode -Location $location -CatalogPath $locationCodesPath
        $fromBicep = [string] (Invoke-ArmExpression -Expression $template.variables.locationCode `
                -Template $template -Parameters @{ location = $location })
        Assert-Equal $fromBicep $fromScript "Location code for '$location' differs between PowerShell and Bicep."
    }

    Assert-Throws { Get-LocationCode -Location 'moonbase1' -CatalogPath $locationCodesPath } `
        'Unknown locations must fail.'
}

Test-Case 'subscription codes derive and remain stable' {
    Assert-Equal (Get-SubscriptionCode -SubscriptionName 'ME-MngEnvMCAP300003-emberger-1') 's1' 'One-digit subscription code mismatch.'
    Assert-Equal (Get-SubscriptionCode -SubscriptionName 'example-1234') 's1234' 'Four-digit subscription code mismatch.'
    Assert-Throws { Get-SubscriptionCode -SubscriptionName 'example' } 'Missing subscription token must fail.'
    Assert-Throws { Get-SubscriptionCode -SubscriptionName 'example-final' } 'Nonnumeric subscription token must fail.'
    Assert-Throws { Get-SubscriptionCode -SubscriptionName 'example-12345' } 'Five-digit subscription token must fail.'
    Assert-Equal (Assert-SubscriptionCode -SubscriptionName 'example-3' -CachedCode 's3') 's3' 'Cached subscription code mismatch.'
    Assert-Throws { Assert-SubscriptionCode -SubscriptionName 'example-3' -CachedCode 's1' } 'Subscription code drift must fail.'
}
