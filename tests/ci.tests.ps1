# Proofs for the pull request deployment workflows: throwaway environment
# naming, profile selection, the what-if comment, the teardown's safety rules,
# the post-deployment checks and the shape of the workflow files themselves.
# Everything runs offline against mocked az, azd and gh commands.

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'assert.ps1')
. (Join-Path $PSScriptRoot 'common.ps1')
. (Get-RepoPath 'scripts/ci-environments.ps1')

$workflowRoot = Get-RepoPath '.github/workflows'

Test-Case 'throwaway environment names fit AZURE_ENV_NAME and are recognized again' {
    Assert-Equal -Actual (Get-CiEnvironmentName -DeploymentProfile private -PullRequest 12 -RunNumber 40 -RunAttempt 1) `
        -Expected 'pr12-private-40-1' -Message 'A pull request run is named after the pull request.'
    Assert-Equal -Actual (Get-CiEnvironmentName -DeploymentProfile full -RunNumber 40 -RunAttempt 2) `
        -Expected 'ci-full-40-2' -Message 'A manual run is named ci-.'
    $longest = Get-CiEnvironmentName -DeploymentProfile private -PullRequest 999999 -RunNumber 9999999 -RunAttempt 99
    Assert-True -Condition ($longest.Length -le 32) -Message "The longest name '$longest' must fit the 32-character limit."
    Assert-Match -Actual $longest -Pattern '^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])$' -Message 'Names must satisfy the AZURE_ENV_NAME rule preflight enforces.'
    foreach ($name in @('pr12-private-40-1', 'ci-core-1-1', $longest)) {
        Assert-True -Condition (Test-CiEnvironmentName $name) -Message "'$name' must be recognized as throwaway."
    }
    foreach ($name in @('sandbox', 'dev', 'pr12-private-40', 'PR12-core-1-1', 'pr12-core-1-1-extra', 'prod-core-1-1', '', $null)) {
        Assert-True -Condition (-not (Test-CiEnvironmentName $name)) -Message "'$name' must never be treated as throwaway."
    }
    Assert-Throws -Action { Get-CiEnvironmentName -DeploymentProfile minimal -RunNumber 1 } -Message 'Only the three profiles are allowed.'
}

Test-Case 'the runner gets a one-tenant catalog that naming accepts, and bad variables fail' {
    . (Get-RepoPath 'scripts/naming.ps1')
    $tenantId = '11111111-2222-3333-4444-555555555555'
    $path = Join-Path ([IO.Path]::GetTempPath()) ("tenant-codes-$([guid]::NewGuid().ToString('N')).json")
    try {
        New-CiTenantCatalog -TenantId $tenantId.ToUpperInvariant() -TenantCode 'cal01' -Path $path
        Assert-Equal -Actual (Get-TenantCode -TenantId $tenantId -CatalogPath $path) -Expected 'cal01' -Message 'Naming must read the code the job wrote.'
        Assert-Throws -Action { New-CiTenantCatalog -TenantId $tenantId -TenantCode 'cal01' -Path $path } -Message 'An existing catalog must never be overwritten.'
    }
    finally {
        Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
    }
    $unused = Join-Path ([IO.Path]::GetTempPath()) ("tenant-codes-$([guid]::NewGuid().ToString('N')).json")
    foreach ($case in @(@('', 'cal01'), @('not-a-guid', 'cal01'), @($tenantId, ''), @($tenantId, 'Cal01'), @($tenantId, 'c'))) {
        Assert-Throws -Action { New-CiTenantCatalog -TenantId $case[0] -TenantCode $case[1] -Path $unused } `
            -Message "Tenant '$($case[0])' with code '$($case[1])' must fail with setup guidance."
    }
    Assert-True -Condition (-not (Test-Path -LiteralPath $unused)) -Message 'A failed call must write nothing.'
    $deploy = Get-Content -LiteralPath (Join-Path $workflowRoot 'deploy-environment.yml') -Raw
    Assert-Match -Actual $deploy -Pattern '(?s)actions/checkout@v4\s+.*?- name: Write the tenant catalog.*?- name: Sign the Azure CLI in' `
        -Message 'The job must write the catalog before anything compiles Bicep.'
}

Test-Case 'only infrastructure changes deploy, and a manual run deploys its one profile' {
    foreach ($path in @('infra/main.bicep', 'infra/modules/network/main.bicep', 'scripts/preflight.ps1', 'azure.yaml', '.github/workflows/deploy-environment.yml', 'infra\core\naming.bicep')) {
        Assert-True -Condition (Test-InfrastructureChange -Path @('README.md', $path)) -Message "'$path' must count as an infrastructure change."
    }
    foreach ($path in @('README.md', 'docs/deployment.md', 'tests/ci.tests.ps1', 'azure.yaml.bak', 'infrastructure.md', '.github/workflows/infra-validation.yml')) {
        Assert-True -Condition (-not (Test-InfrastructureChange -Path @($path))) -Message "'$path' must not deploy anything."
    }
    Assert-True -Condition (-not (Test-InfrastructureChange -Path @())) -Message 'An empty change deploys nothing.'

    Assert-Equal -Actual ((Get-CiDeploymentProfiles -EventName pull_request -InfrastructureChanged $true) -join ',') -Expected 'core,private' `
        -Message 'An infrastructure pull request deploys core and private, never full.'
    Assert-Equal -Actual @(Get-CiDeploymentProfiles -EventName pull_request -InfrastructureChanged $false).Count -Expected 0 `
        -Message 'Any other pull request deploys nothing.'
    Assert-Equal -Actual ((Get-CiDeploymentProfiles -EventName workflow_dispatch -DispatchProfile full) -join ',') -Expected 'full' `
        -Message 'A manual run deploys the profile it was given.'
    Assert-Throws -Action { Get-CiDeploymentProfiles -EventName workflow_dispatch -DispatchProfile '' } -Message 'A manual run must name a profile.'
    Assert-Equal -Actual (ConvertTo-Json -InputObject @(Get-CiDeploymentProfiles -EventName pull_request) -Compress) -Expected '[]' `
        -Message 'No profiles must serialize to the [] the deploy job checks for.'
    Assert-Equal -Actual (ConvertTo-Json -InputObject @(Get-CiDeploymentProfiles -EventName workflow_dispatch -DispatchProfile core) -Compress) -Expected '["core"]' `
        -Message 'One profile must still serialize as an array for the matrix.'
}

Test-Case 'the what-if comment is marked, readable and bounded' {
    $preview = "`e[32mCreate`e[0m : Resource group`r`nModify : vnet with ``````fenced`````` text`n" + ('x' * 200)
    $comment = ConvertTo-PreviewComment -DeploymentProfile core -EnvironmentName pr1-core-2-1 -Preview $preview `
        -Outcome success -RunUrl 'https://example.test/run' -MaxPreviewLength 120
    $lines = $comment -split "`n"
    Assert-Equal -Actual $lines[0] -Expected '<!-- pr-deployment:core -->' -Message 'The marker must be the first line so later runs edit the same comment.'
    Assert-NotMatch -Actual $comment -Pattern "`e" -Message 'Terminal color codes must be stripped.'
    Assert-Match -Actual $comment -Pattern 'Create : Resource group' -Message 'The preview text must survive.'
    Assert-Match -Actual $comment -Pattern 'truncated' -Message 'An oversized preview must be truncated with a note.'
    Assert-Match -Actual $comment -Pattern '(?m)^````+text$' -Message 'The fence must be longer than any backtick run in the preview.'
    Assert-Match -Actual $comment -Pattern '\[Run log\]\(https://example\.test/run\)' -Message 'The comment must link the run.'
    $failed = ConvertTo-PreviewComment -DeploymentProfile full -EnvironmentName pr1-full-2-1 -Preview '' -Outcome failure
    Assert-Match -Actual $failed -Pattern 'pr1-full-2-1` failed' -Message 'A failed preview must say so.'
    Assert-Match -Actual $failed -Pattern '\(no output\)' -Message 'An empty preview must still render.'
}

function Invoke-RemoveFixture {
    param([hashtable] $Arguments, [switch] $WhatIf)

    $calls = [System.Collections.Generic.List[string]]::new()
    $old = [DateTimeOffset]::UtcNow.AddDays(-2).ToString('yyyy-MM-ddTHH:mm:sszzz')
    $young = [DateTimeOffset]::UtcNow.AddMinutes(-30).ToString('yyyy-MM-ddTHH:mm:sszzz')
    $repo = 'owner/repo'
    $groups = @(
        @{ name = 'rg-old-pr'; tags = @{ repository = $repo; 'azd-env-name' = 'pr3-core-10-1'; 'created-on' = $old } }
        @{ name = 'rg-young-pr'; tags = @{ repository = $repo; 'azd-env-name' = 'pr4-private-11-1'; 'created-on' = $young } }
        @{ name = 'rg-sandbox'; tags = @{ repository = $repo; 'azd-env-name' = 'sandbox'; 'created-on' = $old } }
        @{ name = 'rg-other-repo'; tags = @{ repository = 'someone/else'; 'azd-env-name' = 'pr3-core-10-1'; 'created-on' = $old } }
        @{ name = 'rg-untagged'; tags = $null }
        @{ name = 'rg-no-date'; tags = @{ repository = $repo; 'azd-env-name' = 'pr5-core-12-1' } }
    )
    $vaults = @(
        @{ name = 'kv-old'; properties = @{ location = 'eastus2'; purgeProtectionEnabled = $false; tags = @{ repository = $repo; 'azd-env-name' = 'pr3-core-10-1' } } }
        @{ name = 'kv-protected'; properties = @{ location = 'eastus2'; purgeProtectionEnabled = $true; scheduledPurgeDate = 'later'; tags = @{ repository = $repo; 'azd-env-name' = 'pr6-core-13-1' } } }
        @{ name = 'kv-sandbox'; properties = @{ location = 'eastus2'; purgeProtectionEnabled = $false; tags = @{ repository = $repo; 'azd-env-name' = 'sandbox' } } }
        @{ name = 'kv-untagged'; properties = @{ location = 'eastus2'; purgeProtectionEnabled = $false } }
    )
    function az {
        $global:LASTEXITCODE = 0
        switch ("$($args[0]) $($args[1])") {
            'group list' { return ($groups | ConvertTo-Json -Depth 5) }
            'keyvault list-deleted' { return ($vaults | ConvertTo-Json -Depth 5) }
            'group delete' { $calls.Add("delete $($args[3])"); return }
            'keyvault purge' { $calls.Add("purge $($args[3])"); return }
            default { throw "Unexpected Azure call: $args" }
        }
    }
    $output = (& (Get-RepoPath 'scripts/remove-ci-environments.ps1') -SubscriptionId 'sub' -Repository $repo @Arguments -WhatIf:$WhatIf 3>&1) -join "`n"
    return [pscustomobject] @{ Calls = @($calls); Output = $output }
}

Test-Case 'the nightly cleanup removes only old throwaway environments of this repository' {
    $result = Invoke-RemoveFixture -Arguments @{ OlderThanHours = 6 }
    Assert-Equal -Actual ($result.Calls -join ';') -Expected 'delete rg-old-pr;purge kv-old' `
        -Message 'Only the old throwaway group of this repository and its own vault may go.'
    Assert-Match -Actual $result.Output -Pattern "kv-protected.*purge protection" -Message 'A purge-protected vault must be reported, not purged.'
    Assert-Match -Actual $result.Output -Pattern "Skipping 'pr5-core-12-1'" -Message 'A group without a readable creation time must be skipped with a warning.'
}

Test-Case 'the teardown removes exactly its own environment and refuses any other name' {
    $result = Invoke-RemoveFixture -Arguments @{ EnvironmentName = 'pr4-private-11-1' }
    Assert-Equal -Actual ($result.Calls -join ';') -Expected 'delete rg-young-pr' -Message 'A teardown must not wait for the age cutoff, nor touch other environments.'
    $preview = Invoke-RemoveFixture -Arguments @{ OlderThanHours = 0 } -WhatIf
    Assert-Equal -Actual $preview.Calls.Count -Expected 0 -Message '-WhatIf must delete and purge nothing.'
    Assert-Throws -Action { Invoke-RemoveFixture -Arguments @{ EnvironmentName = 'sandbox' } } -Message 'A non-throwaway name must be refused before any call.'
}

function Invoke-DeploymentCheck {
    param(
        [string] $DeploymentProfile = 'private',
        [string] $Overrides = '{}',
        [object[]] $Resources,
        [hashtable] $Outputs = @{},
        [string] $PowerState = 'PowerState/running'
    )

    $values = [ordered] @{
        AZURE_ENV_NAME = 'pr1-private-2-1'; AZURE_SUBSCRIPTION_ID = 'sub'; AZURE_RESOURCE_GROUP = 'rg-fixture'
        AZURE_DEPLOYMENT_PROFILE = $DeploymentProfile; AZURE_FEATURE_OVERRIDES_JSON = $Overrides
        AZURE_LOG_ANALYTICS_WORKSPACE_ID = '/subscriptions/sub/resourceGroups/rg-fixture/providers/Microsoft.OperationalInsights/workspaces/law-fixture'
        AZURE_APPLICATION_INSIGHTS_NAME = 'appi-fixture'
    }
    foreach ($key in $Outputs.Keys) { $values[$key] = $Outputs[$key] }
    function azd {
        $global:LASTEXITCODE = 0
        if ("$($args[0]) $($args[1])" -ne 'env get-values') { throw "Unexpected azd call: $args" }
        return @($values.GetEnumerator() | ForEach-Object { "$($_.Key)=`"$($_.Value)`"" })
    }
    function az {
        $global:LASTEXITCODE = 0
        switch ("$($args[0]) $($args[1])") {
            'group show' { return (@{ name = 'rg-fixture'; tags = @{ 'azd-env-name' = 'pr1-private-2-1'; profile = $DeploymentProfile } } | ConvertTo-Json) }
            'resource list' { return (ConvertTo-Json -InputObject @($Resources) -Depth 4) }
            'vm get-instance-view' { return $PowerState }
            default { throw "Unexpected Azure call: $args" }
        }
    }
    return ((& (Get-RepoPath 'scripts/test-deployment.ps1') -Environment 'pr1-private-2-1') -join "`n")
}

$baseResources = @(
    @{ name = 'law-fixture'; type = 'Microsoft.OperationalInsights/workspaces'; provisioningState = 'Succeeded' }
    @{ name = 'appi-fixture'; type = 'microsoft.insights/components'; provisioningState = 'Succeeded' }
)

Test-Case 'the deployment check passes a healthy deployment and fails a broken one' {
    $private = $baseResources + @(@{ name = 'vnet-fixture'; type = 'Microsoft.Network/virtualNetworks'; provisioningState = 'Succeeded' })
    $output = Invoke-DeploymentCheck -Resources $private -Outputs @{ AZURE_VIRTUAL_NETWORK_NAME = 'vnet-fixture' }
    Assert-Match -Actual $output -Pattern 'All deployment checks passed' -Message 'A healthy private deployment must pass.'

    $failedState = $baseResources + @(@{ name = 'vnet-fixture'; type = 'Microsoft.Network/virtualNetworks'; provisioningState = 'Failed' })
    Assert-Throws -Action { Invoke-DeploymentCheck -Resources $failedState -Outputs @{ AZURE_VIRTUAL_NETWORK_NAME = 'vnet-fixture' } } `
        -Message 'A resource that did not finish provisioning must fail the check.'
    Assert-Throws -Action { Invoke-DeploymentCheck -Resources $baseResources -Outputs @{ AZURE_KEY_VAULT_NAME = 'kv-missing' } } `
        -Message 'An output that names a missing resource must fail the check.'

    $full = $baseResources + @(@{ name = 'vm-win-fixture'; type = 'Microsoft.Compute/virtualMachines'; provisioningState = 'Succeeded' })
    Assert-Throws -Action { Invoke-DeploymentCheck -DeploymentProfile full -Resources $full -Outputs @{ AZURE_WINDOWS_VM_NAME = 'vm-win-fixture' } -PowerState 'PowerState/deallocated' } `
        -Message 'A jumpbox that is not running must fail the check.'
}

Test-Case 'the deployment check holds core to no network or compute unless an override adds them' {
    $withNetwork = $baseResources + @(@{ name = 'vnet-fixture'; type = 'Microsoft.Network/virtualNetworks'; provisioningState = 'Succeeded' })
    Assert-Throws -Action { Invoke-DeploymentCheck -DeploymentProfile core -Resources $withNetwork } -Message 'core with a virtual network must fail.'
    Assert-Throws -Action { Invoke-DeploymentCheck -DeploymentProfile core -Overrides '{"roleAssignments":false}' -Resources $withNetwork } `
        -Message 'An override that adds no network must keep the core rule.'
    $output = Invoke-DeploymentCheck -DeploymentProfile core -Overrides '{"network":true}' -Resources $withNetwork
    Assert-Match -Actual $output -Pattern 'All deployment checks passed' -Message 'An override that adds the network lifts the core rule.'
    $output = Invoke-DeploymentCheck -DeploymentProfile core -Resources $baseResources
    Assert-Match -Actual $output -Pattern 'core profile deployed no network or compute' -Message 'A clean core deployment must pass the rule.'
}

foreach ($scenario in @(
        @{ Name = 'edits the existing marked comment'; Existing = $true; Expected = 'PATCH repos/owner/repo/issues/comments/77' }
        @{ Name = 'creates the comment the first time'; Existing = $false; Expected = 'POST repos/owner/repo/issues/5/comments' }
    )) {
    Test-Case "publishing the what-if $($scenario.Name)" {
        $calls = [System.Collections.Generic.List[string]]::new()
        $existing = $scenario.Existing
        function gh {
            $global:LASTEXITCODE = 0
            if ($args -contains '--paginate') {
                $list = @(@{ id = 12; body = 'An unrelated review comment' } | ConvertTo-Json -Compress)
                if ($existing) { $list += @{ id = 77; body = "<!-- pr-deployment:core -->`nold" } | ConvertTo-Json -Compress }
                return $list
            }
            $calls.Add("$($args[2]) $($args[3])")
        }
        $body = Join-Path ([IO.Path]::GetTempPath()) ("body-$([guid]::NewGuid().ToString('N')).md")
        try {
            Set-Content -LiteralPath $body -Value "<!-- pr-deployment:core -->`nnew"
            & (Get-RepoPath 'scripts/publish-pr-comment.ps1') -Repository owner/repo -PullRequest 5 -BodyPath $body | Out-Null
            Assert-Equal -Actual ($calls -join ';') -Expected $scenario.Expected -Message 'Exactly one comment per profile must exist.'
            Set-Content -LiteralPath $body -Value 'no marker'
            Assert-Throws -Action { & (Get-RepoPath 'scripts/publish-pr-comment.ps1') -Repository owner/repo -PullRequest 5 -BodyPath $body } `
                -Message 'A body without a marker could never be found again and must be refused.'
        }
        finally { Remove-Item -LiteralPath $body -Force -ErrorAction SilentlyContinue }
    }
}

Test-Case 'the full-profile paths filter matches the infrastructure paths' {
    $lines = Get-Content -LiteralPath (Join-Path $workflowRoot 'pr-deployment-full.yml')
    $start = [array]::FindIndex($lines, [Predicate[string]] { param($l) $l -match '^\s{4}paths:\s*$' })
    Assert-True -Condition ($start -ge 0) -Message 'pr-deployment-full.yml must filter on paths.'
    $paths = @($lines[($start + 1)..($lines.Count - 1)] | ForEach-Object {
            if ($_ -match '^\s{6}-\s+"(?<p>[^"]+)"\s*$') { $Matches['p'] } elseif ($_ -match '^\s*\S') { 'END' }
        })
    $paths = @($paths[0..([Math]::Max(0, [array]::IndexOf($paths, 'END') - 1))])
    Assert-Equal -Actual ($paths -join ',') -Expected ($script:CiInfrastructurePaths -join ',') `
        -Message 'The full workflow must deploy for exactly the changes pr-deployment.yml deploys for.'
}

Test-Case 'the deployment workflows are gated, never cancel a teardown and keep untrusted input out of scripts' {
    $files = @('deploy-environment.yml', 'pr-deployment.yml', 'pr-deployment-full.yml', 'pr-deployment-cleanup.yml')
    foreach ($file in $files) {
        $text = Get-Content -LiteralPath (Join-Path $workflowRoot $file) -Raw
        if ($file -ne 'deploy-environment.yml') {
            Assert-Match -Actual $text -Pattern "vars\.AZURE_CLIENT_ID != ''" -Message "'$file' must stay skipped until the repository is set up."
        }
        Assert-NotMatch -Actual $text -Pattern 'cancel-in-progress:\s*true' -Message "'$file' must never cancel a run whose teardown is pending."
    }
    $deploy = Get-Content -LiteralPath (Join-Path $workflowRoot 'deploy-environment.yml') -Raw
    Assert-Match -Actual $deploy -Pattern "(?s)- name: Tear down\s+if: always\(\) && steps\.env\.outputs\.name != ''" -Message 'The teardown must run even after a failure or cancellation.'
    Assert-Match -Actual $deploy -Pattern 'environment: pr-deployment' -Message 'Deployments must wait for the approval environment.'
    Assert-Match -Actual $deploy -Pattern "AZURE_KEY_VAULT_PURGE_PROTECTION = 'false'" -Message 'Throwaway vaults must be purgeable.'
    foreach ($caller in @('pr-deployment.yml', 'pr-deployment-full.yml')) {
        $text = Get-Content -LiteralPath (Join-Path $workflowRoot $caller) -Raw
        Assert-Match -Actual $text -Pattern 'github\.event\.pull_request\.head\.repo\.full_name == github\.repository' -Message "'$caller' must never deploy a fork's pull request."
    }

    # An expression expanded inside a script is an injection point. Every run
    # block must take its inputs through env: instead.
    foreach ($workflow in (Get-ChildItem -LiteralPath $workflowRoot -Filter *.yml)) {
        $lines = Get-Content -LiteralPath $workflow.FullName
        $runIndent = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $indent = $line.Length - $line.TrimStart().Length
            if ($runIndent -ge 0 -and ($line.Trim() -eq '' -or $indent -gt $runIndent)) {
                Assert-NotMatch -Actual $line -Pattern '\$\{\{' -Message "$($workflow.Name):$($i + 1) expands an expression inside a script."
                continue
            }
            $runIndent = -1
            if ($line -match '^(?<pad>\s*)(?<dash>- )?run:\s*(?<rest>.*)$') {
                $pad = $Matches['pad'].Length + $(if ($Matches['dash']) { 2 } else { 0 })
                $rest = $Matches['rest']
                Assert-NotMatch -Actual $rest -Pattern '\$\{\{' -Message "$($workflow.Name):$($i + 1) expands an expression inside a script."
                if ($rest -match '^[|>]') { $runIndent = $pad }
            }
        }
    }
}
