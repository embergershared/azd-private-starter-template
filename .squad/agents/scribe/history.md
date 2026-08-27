# Project Context

- **Project:** azure-azd-private-starter
- **Created:** 2026-08-26

## Core Context

Agent Scribe initialized and ready for work.

## Recent Updates

📌 Team initialized on 2026-08-26

📌 Decision logged on 2026-08-27: DEPLOYMENT_PROFILE defaults to `full` when omitted. Implemented consistently across `infra\main.parameters.json`, `infra\main.bicep`, `azure.yaml` preprovision, and `scripts\preflight.ps1`. Explicit `minimal` remains supported. Independent and final reviews completed with no significant issues. Tradeoff accepted: omitted deployments now choose larger, costlier footprint (Standard Bastion, NAT Gateway with public IPs, VMs).

## Learnings

Initial setup complete. Squad conventions established: append-only decision logging in `.squad/decisions.md` with governance, rationale, implementation details, tradeoffs, and review findings.
