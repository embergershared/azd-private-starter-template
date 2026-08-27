# Deployment lifecycle

Use three gated phases. The template is infrastructure-only, so `azd provision`
is the deployment operation; `azd deploy` has no application service to publish.

## Prerequisites and roles

Install current [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
and [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd),
with PowerShell 7 available for hooks. Authenticate to the intended tenant and
verify subscription, region, policy, resource providers, quota, and SKU/image
availability immediately before preview.

The deployment identity needs:

- **Contributor** at subscription scope (or equivalent custom permissions) to
  create the resource group and resources.
- **Role Based Access Control Administrator**, **User Access Administrator**, or
  equivalent `Microsoft.Authorization/roleAssignments/*` permission at the
  deployment scopes when `roleAssignments` is enabled.
- Read access to subscription, provider, quota, SKU, and Marketplace image
  metadata used by preflight.

  The target subscription display name must end in a hyphen-delimited 1-4 digit
  token. The initialization helper caches that token as `s<digits>` for resource
  naming, and preflight blocks if a later subscription rename would change it.

Configured operator principals receive:

- **Virtual Machine User Login** on each Entra-enabled VM.
- **Key Vault Secrets User** on the Key Vault.
- **Storage Blob Data Contributor** and **Storage File Data SMB Share
  Contributor** on the Storage account.

Role changes can take time to propagate. Use Entra object IDs, not display names.
If automatic assignments are disabled, have an authorized administrator apply
the same least-privilege roles before access testing. Review the authoritative
[Azure built-in role definitions](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles)
when permissions or role IDs change.

Windows 11 Pro is license-gated. Preflight queries the exact
`MicrosoftWindowsDesktop:windows-11:win11-24h2-pro:latest` offer in the target
subscription and region and blocks when it is unavailable. This check does not
grant a license or replace your organization's entitlement review. Never
silently substitute another Windows edition. Review Microsoft's
[Windows client image licensing guidance](https://learn.microsoft.com/azure/virtual-machines/windows/client-images)
before approving the profile.

Both jumpboxes use the standard Azure VM Agent for provisioning and extensions.
The template does not require the subscription-gated
`Microsoft.Compute/Agentless` feature.

Windows 11 uses OS-managed automatic updates because this client image does not
support Azure-orchestrated VM Guest Patching. Ubuntu retains
Azure-orchestrated patch assessment and installation. Entra login and VMAccess
extensions accept minor-version upgrades but do not opt into automatic
extension upgrades because these extension publishers do not support that
property.

The Windows Entra extension always receives the case-sensitive `mdmId` setting.
Its default empty value enables Entra login without requesting automatic MDM
enrollment. Configure an approved MDM application ID only when enrollment is
intentional and licensed for the target tenant.

## 1. Prepare

1. Review `.azure/deployment-plan.md`, architecture, public exceptions, budget,
   policy, identity, address space, recovery, and unresolved risks.
2. Create/select an environment and set the values in
   [configuration](configuration.md).
3. Review generated names and the preview target. Preparation must not change
   Azure.

```powershell
azd auth login
azd env new <environment>
azd env set AZURE_SUBSCRIPTION_ID <subscription-guid>
azd env set AZURE_LOCATION eastus2
azd env set DEPLOYMENT_PROFILE minimal
azd env set AZURE_OPERATOR_PRINCIPAL_IDS <entra-object-guid>
.\scripts\set-deployment-tags.ps1
```

The final command is a required one-time bootstrap for each new environment.
It initializes the stable subscription code and lifecycle values. AZD resolves
required Bicep parameters before running pre-provision hooks; later provisions
verify the code and refresh update metadata automatically.

## 2. Validate

Run local parsing and Bicep validation, then preview. The pre-provision hook
checks configuration dependencies, provider registration, target location,
operator IDs, VM SKU quota/restrictions, and Windows image visibility.

```powershell
Get-ChildItem -Recurse -Filter *.json |
  ForEach-Object { Get-Content $_.FullName -Raw | ConvertFrom-Json | Out-Null }
.\scripts\test-naming.ps1
az bicep build --file infra\main.bicep
az bicep lint --file infra\main.bicep
azd provision --preview -e <environment>
```

Inspect every create/change/delete and recurring-cost resource. Resolve policy,
quota, role, licensing, DNS, and dependency failures; do not bypass preflight.
Record evidence in the deployment plan and complete `azure-validate`.

### Migrating an environment that previously used Azure Monitor private link

ARM deployments are incremental, so removing private-link resources from Bicep
does not delete every previously deployed resource. Before provisioning this
revision over an environment that used Azure Monitor private link, remove only
the obsolete monitor private endpoint and its NIC, private-link scope, four
monitor-only private DNS zones/links, monitor subnet, and monitor NSG. Delete
the private endpoint before its subnet.

Do **not** delete the Log Analytics workspace or Application Insights. After
cleanup, run preview again and verify that both resources change
`publicNetworkAccessForIngestion` and `publicNetworkAccessForQuery` to
`Enabled`, with no monitor private-link resources being created.

## 3. Deploy and verify

After explicit approval, run:

```powershell
azd provision -e <environment>
```

Verify actual resource state, private DNS resolution, public-access settings,
operator RBAC, Entra login, current break-glass retrieval, monitoring ingestion,
and every enabled profile feature. A successful command alone is insufficient.

## Standard Bastion access

VMs have no public IP. From the Azure portal, open the VM, select
**Connect → Bastion**, and use Entra credentials where supported. Standard
Bastion also supports native clients:

```powershell
az network bastion rdp --name <bastion> --resource-group <resource-group> --target-resource-id <windows-vm-resource-id> --auth-type AAD
az network bastion ssh --name <bastion> --resource-group <resource-group> --target-resource-id <linux-vm-resource-id> --auth-type AAD
```

See [Bastion native-client access](https://learn.microsoft.com/azure/bastion/connect-vm-native-client-windows).
Do not add VM public IPs or internet RDP/SSH rules for convenience.

## Cost, shutdown, and teardown

Check current regional prices before approval. The largest idle charges usually
come from Standard Bastion, VMs/disks, NAT Gateway and public IPs, private
endpoints, and Log Analytics ingestion. The daily cap limits ingestion,
not all monitoring charges.

Full-profile shutdown schedules stop VM compute daily at `1900` Eastern by
default. They do not remove disk, Bastion, NAT, public IP, private endpoint, or
monitoring charges, and they do not restart VMs automatically.

For an ephemeral PoC, verify the environment contains no shared resources, then:

```powershell
azd down -e <environment>
```

Review and confirm the destructive plan. Verify the resource group is gone and
check for soft-deleted/purge-protected Key Vault state and any retained charges.
