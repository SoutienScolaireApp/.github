# Contributing to SoutienScolaireApp

These rules apply to every repository of the organization: the tracking repositories (`docs`, `journal`, `legal`, `.github`) and the code repositories of the SchoolEngine platform (`contracts`, `backend`, `mobile-app`, `parent-web`, `admin-web`, `infrastructure`, `architecture`). A repository's own `CONTRIBUTING.md`, `CLAUDE.md` or README may add stricter rules; it never relaxes these ones. The normative reference is the founding specification (§25 to §28, §37, §38).

GitHub shows this file in every repository that has no `CONTRIBUTING.md` of its own. The code repositories carry their own copy, with their issue forms and pull request template.

## Branches

- `develop` is the default branch, the only long-lived branch and the starting point of every branch. There is no `main`.
- In the code repositories, `develop` is protected by the organization ruleset `protect-develop`: pull request required, squash only, linear history, no force-push, no deletion, review threads resolved; the only bypass is a break-glass for organization owners, through a pull request (logged), see [rulesets/README.md](https://github.com/SoutienScolaireApp/.github/blob/develop/rulesets/README.md#break-glass).
- Never commit directly to `develop`, not even a typo.

## Workflow

1. **Issue first.** Nothing starts without an issue: context, problem, expected behavior, verifiable acceptance criteria. Tracking work (lot cards, task cards, convention) is a card of the organization board or one of its sub-issues (ADR-010 in `docs`); only a card carries the `contribution` label and points. A development ticket is opened with one of the forms of its code repository, as a sub-issue of its lot epic in `SoutienScolaireApp/architecture`, without the `contribution` label; it is ready only when it meets the Definition of Ready (spec §37): context, verifiable acceptance criteria, contract impact identified, dependencies resolved, reasonable size.
2. **Dedicated worktree.** Several people and agents work in parallel: each ticket gets its own worktree, never the shared checkout.

   ```bash
   git fetch origin
   git worktree add ../.worktrees/<repo>/<issue> -b <type>/<issue>-<description> origin/develop
   ```

3. **Branch naming:** `<type>/<issue>-<short-description>`, in English, lowercase, words separated by hyphens. The issue number is mandatory.

   | Type | Use |
   |---|---|
   | `feature` | New behavior |
   | `fix` | Bug fix |
   | `refactor` | Restructuring without behavior change |
   | `chore` | Tooling, dependencies, configuration |
   | `ci` | CI workflows and their templates |
   | `docs` | Documentation only |
   | `test` | Tests only |

4. **Commits:** [Conventional Commits](https://www.conventionalcommits.org/), in English: `<type>(<scope>): <imperative description> (#<issue>)`. Types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `perf`, `ci`. The scope is the module or domain touched. The body explains why, never how.
5. **Pull request** against `develop`, with `Closes #<issue>`, the context, the changes and what to review first (code repositories: their template, with the contract impact (none, additive, breaking) and the Definition of Done checklist). Its title follows the commit format and becomes the squash message. Target size: under ~400 diff lines.
6. **CI:** where a repository runs the `Quality Gate` check (format, lint, types, tests, gitleaks, osv-scanner, contract), it must be green. A red CI is never bypassed: fix the cause, never the test or the threshold.
   - The `Gate integrity` check must be green too. A PR that changes the gate itself (removes a job, changes a common job, the gate, a workflow, a local action or the workflow-level settings of `ci.yml`, loosens the gitleaks configuration) is a **gate change**: its body has a `## Gate change` section with a justification of at least 20 letters or digits (HTML comments do not count). The double agent review (code and security) recorded on the PR is the approval. Details: [CI.md](CI.md#gate-integrity).
   - Every ignore (`osv-scanner.toml`, `.gitleaksignore`, `.gitleaks.toml` allowlist) carries a justification and an expiry date at most 180 days ahead ([CI.md](CI.md#ignore-files)).
7. **Merge:** squash and merge only, and only with Céline's explicit approval. Nobody merges on their own initiative.
8. **Cleanup:** the branch is deleted on merge; remove the local branch and the worktree.

## Labels

Code repositories. Type: `feature`, `bug`, `tech-debt`, `security`, `docs`, `test`. State: `blocked`, `needs-info`, `breaking-change-approved`. Other: `epic`, `accessibility`, `privacy`. GitHub Actions is case-sensitive on labels: never create a duplicate with a different casing.

## Contract changes (code repositories)

An API change is never local: a pull request in `contracts` first, then the release of the generated clients, then one pull request per impacted consumer. Never hand-write an API type, model or path: everything comes from the generated clients. A breaking change requires the `breaking-change-approved` label and a prior explicit decision.

## Data and secrets

- No secret in git, ever, not even temporarily.
- No real user data outside production: local and staging use synthetic data only.
- No personal data in logs, issues, pull requests or screenshots.
- Install the [gitleaks](https://github.com/gitleaks/gitleaks) pre-commit hook (recommended, not mandatory) to catch a secret before it is committed. In the code repositories, the `Quality Gate` runs gitleaks and osv-scanner (dependency audit) on every pull request regardless, and a finding blocks the merge.

## Security

Never report a vulnerability in a regular issue. See [SECURITY.md](SECURITY.md).
