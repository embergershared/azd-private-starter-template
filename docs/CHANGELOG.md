# Changelog

What changed for users of __PROJECT_NAME__, newest first. Each merged PR adds its line under
**Unreleased** (with its issue number); a release moves them under a dated version.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added
- CI: one **CI result** check sums up the workflow lint and the infrastructure validation;
  **PR rules** checks the branch name, the linked issue, authorship and commit style; Dependabot
  updates the pinned workflow actions after a 7-day cooldown (#15).
- Public repository pages: MIT license, security policy, support, contributing, code of
  conduct, this changelog, decision records, a PR template and issue forms. The README is a
  table of contents; its how-to moved to [getting-started.md](getting-started.md) (#14).
- Pull request deployments: infrastructure changes are previewed, deployed, checked and torn
  down before they merge, once the deployment identity is set up (#21).

### Changed
- The tenant catalog and the targets page are local to each clone, created from their
  committed examples by `scripts/init-from-template.ps1` (#12).

### Removed
- The Squad agent workspace (#11).
