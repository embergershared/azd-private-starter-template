# Configuration

Configuration belongs in the selected `azd` environment, not committed files.
Use `azd env set`; never commit `.azure/<environment>`, `.env*`, credentials, or
generated deployment output.

## Profiles

| Feature | `minimal` | `full` |
|---|:---:|:---:|
| VNet, NSGs, private DNS | ✓ | ✓ |
| Private Key Vault and Storage | ✓ | ✓ |
| Log Analytics and App Insights | ✓ | ✓ |
| Windows and Ubuntu jumpboxes |  | ✓ |
| Standard Bastion |  | ✓ |
| NAT and Entra VM login |  | ✓ |
| VM auto-shutdown |  | ✓ |

```powershell
azd env set DEPLOYMENT_PROFILE minimal # or full
```

## Required environment values

| Name | Purpose |
|---|---|
| `AZURE_ENV_NAME` | Lowercase 2–32 character environment name; initialized by `azd env new` |
| `AZURE_SUBSCRIPTION_ID` | Target subscription GUID; its display name must end in a hyphen and 1-4 digits |
| `AZURE_SUBSCRIPTION_CODE` | Internal cached `s<digits>` code initialized and verified by `set-deployment-tags.ps1` |
| `AZURE_LOCATION` | Azure region, default design target `eastus2` |
| `DEPLOYMENT_PROFILE` | `minimal` or `full`; hook defaults to `full` |
| `AZURE_OPERATOR_PRINCIPAL_IDS` | Comma-separated Entra user/group object IDs |
| `AZURE_FEATURE_OVERRIDES_JSON` | Expert feature object; hook defaults to `{}` |

The hook base64-encodes override JSON into the internal
`AZURE_FEATURE_OVERRIDES_BASE64` transport value so AZD can substitute it into
ARM parameter JSON without quote corruption. Do not edit the encoded value.

The environment helper derives `AZURE_SUBSCRIPTION_CODE` from the active
subscription display name, seeds it with `AZURE_CREATED_ON`, and verifies it on
later runs. The display name must end in a final hyphen-delimited 1-4 digit
token; for example, `ME-MngEnvMCAP300003-emberger-3` derives `s3`. If a
subscription rename would derive a different code, preflight fails instead of
silently changing resource identities. Review the replacement impact before
manually updating the cached code.

The pre-provision hook refreshes `AZURE_LAST_UPDATED_ON` on each provision
using America/New_York time with an explicit UTC offset. Do not edit these
lifecycle values casually.

After `azd env new` and the required `azd env set` commands, initialize the
first-use values once:

```powershell
.\scripts\set-deployment-tags.ps1
```

AZD resolves required Bicep inputs before it invokes `preprovision`, so the
first preview cannot rely on the hook to create them. Later provisions invoke
the same script automatically and preserve `AZURE_CREATED_ON`.

## Expert feature overrides

Supported Boolean keys are `bastion`, `windowsVm`, `linuxVm`, `natGateway`,
`entraLogin`, `shutdownSchedules`, and `roleAssignments`.

```powershell
azd env set AZURE_FEATURE_OVERRIDES_JSON '{"bastion":true,"windowsVm":true,"linuxVm":false,"natGateway":true,"entraLogin":true,"shutdownSchedules":true,"roleAssignments":true}'
```

Dependency rules fail preflight:

- `shutdownSchedules` and `entraLogin` each require at least one VM.
- `natGateway` and `entraLogin` must have identical values.
- Any enabled jumpbox VM requires Bastion because the template has no VPN,
  peering, or VM public-IP access path.
- Full-profile Entra extension installation and authentication require NAT
  egress. Do not disable NAT alone.
- An expert air-gapped deployment **must** set both to false:

```powershell
azd env set AZURE_FEATURE_OVERRIDES_JSON '{"natGateway":false,"entraLogin":false}'
```

Air-gapped mode removes the primary Entra login path. Confirm an approved local
break-glass access process and required offline package/update strategy before
deployment.

Setting `roleAssignments` to `false` supports a deployer without
`roleAssignments/write`, but an authorized administrator must manually grant
the [operator roles](deployment.md#prerequisites-and-roles).

## Bicep-level parameters

`infra/main.bicep` also defines CIDRs, VM sizes and fixed image contracts,
retention (30–730 days), daily ingestion cap (minimum 1 GB), shutdown time,
Windows MDM application ID, and tag values. The current `azd` parameter file
exposes only the environment values above. To make another value reusable
through `azd`, update the Bicep parameter, `infra/main.parameters.json`,
preflight validation, and this document together.

The Windows contract is Windows 11 Pro 24H2 Gen2 and intentionally does not fall
back to Windows Server or Enterprise.

`windowsMdmId` defaults to an explicit empty string. This satisfies the
case-sensitive `AADLoginForWindows` extension contract without requesting
automatic MDM enrollment. Set it to the application ID of an approved MDM
provider only when that enrollment is intentional; Microsoft Intune uses
`0000000a-0000-0000-c000-000000000000`.

## Resource naming

The template enforces the
`<resource-prefix>-<location-code>-<subscription-code>-<environment>` order and
resource-specific length/character constraints in `infra/main.bicep`; see the
[architecture naming contract](architecture.md#naming-contract). Do not encode
custom resource names in AZD environment values. Changing a prefix or suffix
replaces resources whose Azure names are immutable, so review the preview for
data migration, retained resources, downtime, and additional cost before
provisioning an existing environment.

`infra/location-codes.json` is the shared public-cloud location catalog used by
Bicep and preflight. An Azure location that is valid but not yet mapped fails
closed until the catalog receives a reviewed, unique country-first code.
