<#
.SYNOPSIS
    Shared helpers for the pull request deployment workflows.

.DESCRIPTION
    Dot-source this file. It names the throwaway environments that
    .github/workflows/deploy-environment.yml creates, recognizes them again for
    teardown, decides which profiles a run deploys and formats the what-if
    preview for the pull request. docs/ci-deployment.md describes the workflows.

    Every throwaway environment name matches $CiEnvironmentNamePattern, and the
    teardown and nightly cleanup never touch a resource group whose name does
    not match it.
#>

Set-StrictMode -Version Latest

$script:CiProfiles = @('core', 'private', 'full')

# pr<number>-<profile>-<run>-<attempt> for a pull request, ci-<profile>-<run>-<attempt>
# for a manual run. The longest possible name, pr999999-private-9999999-99, is
# 27 characters, inside AZURE_ENV_NAME's 32-character limit.
$script:CiEnvironmentNamePattern = '^(pr[0-9]{1,6}|ci)-(core|private|full)-[0-9]{1,7}-[0-9]{1,2}$'

# The paths whose changes can alter what a deployment creates. A pull request
# that touches none of them deploys nothing. pr-deployment-full.yml repeats this
# list as its paths filter; a test keeps the two in step.
$script:CiInfrastructurePaths = @(
    'infra/**'
    'scripts/**'
    'azure.yaml'
    '.github/workflows/pr-deployment.yml'
    '.github/workflows/pr-deployment-full.yml'
    '.github/workflows/deploy-environment.yml'
)

function Get-CiEnvironmentName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [ValidateSet('core', 'private', 'full')] [string] $DeploymentProfile,
        [int] $PullRequest = 0,
        [Parameter(Mandatory)] [ValidateRange(1, 9999999)] [int] $RunNumber,
        [ValidateRange(1, 99)] [int] $RunAttempt = 1
    )

    $prefix = if ($PullRequest -gt 0) { "pr$PullRequest" } else { 'ci' }
    $name = "$prefix-$DeploymentProfile-$RunNumber-$RunAttempt"
    if ($name -cnotmatch $script:CiEnvironmentNamePattern) {
        throw "Throwaway environment name '$name' does not match $script:CiEnvironmentNamePattern."
    }
    return $name
}

function Test-CiEnvironmentName {
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowEmptyString()] [AllowNull()] [string] $Name)

    return ([string] $Name) -cmatch $script:CiEnvironmentNamePattern
}

function Test-InfrastructureChange {
    <#
    .SYNOPSIS
        True when any of the changed paths can alter what a deployment creates.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowEmptyCollection()] [string[]] $Path = @())

    foreach ($changed in $Path) {
        $normalized = ([string] $changed).Trim().Replace('\', '/')
        if (-not $normalized) { continue }
        foreach ($pattern in $script:CiInfrastructurePaths) {
            if ($pattern.EndsWith('/**')) {
                if ($normalized.StartsWith($pattern.Substring(0, $pattern.Length - 2), [StringComparison]::Ordinal)) { return $true }
            }
            elseif ($normalized -ceq $pattern) {
                return $true
            }
        }
    }
    return $false
}

function Get-CiDeploymentProfiles {
    <#
    .SYNOPSIS
        The profiles one run of pr-deployment.yml deploys.
    .DESCRIPTION
        A pull request deploys core and private when it changes infrastructure,
        and nothing otherwise. A manual run deploys the one profile it was given.
        full never runs from here on a pull request; pr-deployment-full.yml
        deploys it when the pull request carries the deploy-full label.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string] $EventName,
        [AllowEmptyString()] [string] $DispatchProfile = '',
        [bool] $InfrastructureChanged = $false
    )

    switch ($EventName) {
        'pull_request' {
            if ($InfrastructureChanged) { return [string[]] @('core', 'private') }
            return [string[]] @()
        }
        'workflow_dispatch' {
            if ($DispatchProfile -cnotin $script:CiProfiles) {
                throw "Manual runs deploy one of: $($script:CiProfiles -join ', '); received '$DispatchProfile'."
            }
            return [string[]] @($DispatchProfile)
        }
        default { throw "Unsupported event '$EventName'." }
    }
}

function ConvertTo-PreviewComment {
    <#
    .SYNOPSIS
        Formats `azd provision --preview` output as a pull request comment.
    .DESCRIPTION
        Strips terminal color codes, keeps the comment under GitHub's size limit
        and starts with a marker so a later run edits the same comment.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [ValidateSet('core', 'private', 'full')] [string] $DeploymentProfile,
        [Parameter(Mandatory)] [string] $EnvironmentName,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Preview,
        [Parameter(Mandatory)] [ValidateSet('success', 'failure', 'cancelled', 'skipped')] [string] $Outcome,
        [string] $RunUrl = '',
        [int] $MaxPreviewLength = 60000
    )

    $clean = ($Preview -replace "`e\[[0-9;?]*[A-Za-z]", '' -replace "`r", '').Trim()
    if ($clean.Length -gt $MaxPreviewLength) {
        $clean = $clean.Substring(0, $MaxPreviewLength) + "`n... (truncated; the full preview is in the run log)"
    }
    # A fence longer than any backtick run in the text keeps the block intact.
    $longest = @([regex]::Matches($clean, '`+') | ForEach-Object { $_.Length } | Sort-Object -Descending)
    $fence = '`' * [Math]::Max(3, $(if ($longest.Count) { $longest[0] + 1 } else { 3 }))
    $status = switch ($Outcome) {
        'success' { 'succeeded' }
        'failure' { 'failed' }
        'cancelled' { 'was cancelled' }
        'skipped' { 'did not run' }
    }
    $lines = @(
        "<!-- pr-deployment:$DeploymentProfile -->"
        "### What-if: ``$DeploymentProfile`` profile"
        ''
        "The preview for the throwaway environment ``$EnvironmentName`` $status." + $(if ($RunUrl) { " [Run log]($RunUrl)" } else { '' })
        ''
        '<details><summary>azd provision --preview</summary>'
        ''
        "${fence}text"
        $(if ($clean) { $clean } else { '(no output)' })
        $fence
        ''
        '</details>'
    )
    return ($lines -join "`n")
}
