# Squad Decisions

## Active Decisions

### DEPLOYMENT_PROFILE Default (2026-08-27)

**Scope:** Infrastructure deployment configuration  
**Status:** Accepted and implemented  
**Decision Maker:** Emmanuel  
**Reviewed By:** Independent review completed; no significant issues found

**What:** DEPLOYMENT_PROFILE parameter now defaults to `full` when omitted from deployment commands.

**Why:** Explicit default ensures predictable infrastructure footprint and cost; avoids silent fallback to minimal configuration. User explicitly requested the larger footprint as the standard.

**How Implemented:**
- `infra\main.parameters.json`: `${DEPLOYMENT_PROFILE=full}` default
- `infra\main.bicep`: `full` default in parameter
- `azure.yaml` preprovision: persistence fallback to `full`
- `scripts\preflight.ps1`: fallback to `full`

**Tradeoffs:**
- **Accepted:** Omitted/direct deployments now default to Standard Bastion, NAT Gateway with public IPs, and both Windows and Linux VMs (costlier than `minimal`)
- **Preserved:** Existing environments with explicit `minimal` or persisted values remain unaffected; `minimal` remains explicitly supported

**Key Resolutions:**
- Independent review identified AZD parameter-resolution-before-hook gap; resolved via inline default in `main.parameters.json`
- Final review confirmed no security or policy issues
- Backward compatibility maintained for environments with persisted `DEPLOYMENT_PROFILE` values

---

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
