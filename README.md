# Private Azure PoC starter

An infrastructure-only [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
template for private-by-default proofs of concept. Modular Bicep creates a VNet,
private Key Vault and Storage, Log Analytics, and Application Insights. The
`full` profile also adds Standard Bastion, Windows and Linux jumpboxes, NAT,
Entra login, and auto-shutdown.

## Start here

1. Review [prerequisites and required roles](docs/deployment.md#prerequisites-and-roles).
2. Choose [minimal, full, or expert configuration](docs/configuration.md).
3. Follow the gated [prepare → validate → deploy lifecycle](docs/deployment.md).
4. Read the [security and private-access model](docs/security.md).

```powershell
# Variables values
$subscriptionId = '<subscription-guid>'
# Use a lowercase, unique 2-32 character environment name.
$environment = 'my-azd-env-dev'
$location = 'eastus2'
$profile = 'full' # minimal or full

# Commands execution
az login
az account set --subscription $subscriptionId
azd auth login
$operatorId = az ad signed-in-user show --query id --output tsv
azd env new $environment
azd env set AZURE_SUBSCRIPTION_ID $subscriptionId
azd env set AZURE_LOCATION $location
azd env set DEPLOYMENT_PROFILE $profile
azd env set AZURE_OPERATOR_PRINCIPAL_IDS $operatorId
.\scripts\set-deployment-tags.ps1
azd provision --preview -e $environment
```

Preview is not deployment. Do not run `azd provision` or `azd up` until the
validation gate and deployment approval are complete.

Run `set-deployment-tags.ps1` once after creating an environment. AZD resolves
required Bicep inputs before `preprovision` hooks run; the script seeds those
first-use values, including the stable subscription code, and the hook refreshes
update metadata on later provisions. The active subscription display name must
end in a hyphen-delimited 1-4 digit token, such as `-1`.

## Deployment profiles

Set the profile in the selected AZD environment before previewing or
provisioning:

```powershell
azd env set DEPLOYMENT_PROFILE minimal # or full
```

Profiles are cumulative:

| `DEPLOYMENT_PROFILE` | Includes | Adds to the previous profile |
|---|---|---|
| `minimal` | Resource group, VNet, three subnets and NSGs, private DNS, private Key Vault, private Blob/File Storage endpoints, Log Analytics, and Application Insights | Base private environment |
| `full` | Everything in `minimal` | Standard Bastion, Windows 11 and Ubuntu jumpboxes, NAT Gateway, Entra VM login, operator RBAC, and VM auto-shutdown schedules |

`full` is the default. The `full` profile includes Standard Bastion, NAT
Gateway, public IPs, and two jumpbox VMs; choose `minimal` explicitly for a
lower-cost, smaller-surface deployment. Re-provisioning a full environment with
`minimal` can propose deletion of those resources, so always inspect
`azd provision --preview` before applying a profile change.

Environments deployed by an earlier revision with Azure Monitor private link
require the ordered cleanup described in
[deployment migration guidance](docs/deployment.md#migrating-an-environment-that-previously-used-azure-monitor-private-link)
before reprovisioning.

For combinations between these profiles, use the documented
[expert feature overrides](docs/configuration.md#expert-feature-overrides).
Dependency validation still applies; for example, jumpbox VMs require Bastion,
and Entra VM login requires NAT egress.

## Documentation

- [Architecture and extension points](docs/architecture.md)
- [Profiles and expert overrides](docs/configuration.md)
- [Deployment, access, cost, and teardown](docs/deployment.md)
- [Security, private DNS, monitoring access, and break glass](docs/security.md)

This repository also contains an installed Squad workspace. Do not repurpose or
rewrite Squad-owned files under `.squad/templates/`, the coordinator agent, or
the installed Squad workflows.
