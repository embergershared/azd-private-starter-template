# Deployment targets

The tenants and subscriptions this repository deploys to. This file and
`infra/core/tenant-codes.json` hold the owner's specifics; a repository created
from the template replaces both with their `.example` counterparts. See
[Starting a repository from the template](deployment.md#starting-a-repository-from-the-template).

The default target is tenant `00000000-0000-4000-8000-000000000001`
(code `100001`) and subscription `MngEnv100001-s2-Sandbox`
(`00000000-0000-4000-8000-000000000003`).

| Tenant | Tenant ID | Code | Subscriptions |
|---|---|---|---|
| Contoso | `00000000-0000-4000-8000-000000000001` | `100001` | `MngEnv100001-s1-Hub`, `MngEnv100001-s2-Sandbox` (default), `MngEnv100001-s3-Projects` |
| Fabrikam | `00000000-0000-4000-8000-000000000002` | `200002` | `Fabrikam-200002-s1` (`00000000-0000-4000-8000-000000000004`, code `s1`) |

Every tenant in this table must be listed in `infra/core/tenant-codes.json`. To
add one, follow
[Deploy to another tenant or subscription](deployment.md#deploy-to-another-tenant-or-subscription).
