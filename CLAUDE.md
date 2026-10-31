# CLAUDE.md: `.github`

Rules for contributors and agents working in `SoutienScolaireApp/.github`. The `README.md` indexes every file, `CI.md`, `DEPENDABOT.md` and `rulesets/README.md` hold the procedures; this file states the rules and points to them.

Organization-level configuration of SoutienScolaireApp: the reusable `add-to-project` workflow, the CI and Dependabot templates of the code repositories, the lint configurations, the organization ruleset kept as code, and the default `CONTRIBUTING.md` and `SECURITY.md`. **The only public repository of the organization.** Workspace process (branches, issues, pull requests): `../CLAUDE.md`.

Normative references: founding specification (`FOUNDING-SPECIFICATION.md` in `SoutienScolaireApp/docs`) §25 to §28, delivery standard §37 and §38; ADR-010 (contribution tracking) in `SoutienScolaireApp/docs`; ADR-014 (security tooling, Dependabot) in `SoutienScolaireApp/architecture`.

`SchoolEngine/.github` was merged here (PR #6) and archived on 2026-10-26: never work there, nor in its old local checkout `../engine-github/`. References such as `SchoolEngine/.github#22` in the docs point to its read-only history.

## Public repository: what follows

Public so that GitHub applies `CONTRIBUTING.md` and `SECURITY.md` as defaults to every repository without its own. Everything else in the organization is private.

**Nothing confidential is ever committed here**: no secret, no personal data, no specification, roadmap, threat model, security finding, infrastructure detail or customer name. The controls (`CI.md`, `rulesets/`, the templates) are public on purpose: they say how a change is checked, not where the product is weak. Any public landing page (`profile/README.md`, not present today) is communication: its wording requires Céline's approval and is never written by an agent on its own initiative.

## What exists on `develop`

```text
.github/workflows/add-to-project.yml        reusable: adds `contribution` issues to board #1 (tracking repositories only)
.github/workflows/add-to-project-caller.yml caller for this repository (local path)
.github/workflows/ci.yml                    own CI: ci-common + `scripts` job, produces `Quality Gate`
.github/workflows/gate-integrity.yml        `Gate integrity` check, byte-identical copy of the template
.github/workflows/gitleaks-history.yml      weekly history scan, copy of the template
.github/scripts/gate-integrity.sh           checker copied unchanged into every code repository
.github/lint/  .yamllint.yml  .markdownlint-cli2.yaml   copies of templates/lint/
.github/dependabot.yml                      common template + pip/npm for the lint tools, also scans workflow-templates/
workflow-templates/                         ci-common, ci-node, ci-flutter, ci-openapi, ci-ansible, gate-integrity, gitleaks-history
templates/lint/                             yamllint and markdownlint-cli2 configs, hashed lint tool pins
templates/dependabot/                       common, node, flutter, container, lint
templates/openapi/.spectral.yaml            Spectral rule set for contracts
rulesets/protect-develop.json               organization ruleset as code; scripts/apply-ruleset.sh applies it
tests/                                      apply-ruleset, ci-templates (drift), gate-integrity, sops-regex
CI.md  DEPENDABOT.md  CONTRIBUTING.md  SECURITY.md  README.md
```

Not here: issue forms and the pull request template. Each code repository carries its own `.github/ISSUE_TEMPLATE/`, PR template, `CONTRIBUTING.md`, `SECURITY.md`, `ci.yml` and `dependabot.yml`.

## Non-negotiables

1. **No confidential content, ever** (see above).
2. **Code CI is templated, not shared.** Only `add-to-project` is a reusable workflow. Each code repository owns one `ci.yml` copied from `workflow-templates/ci-<variant>.yml`; a variation is a filled `TODO(scaffold)` or an extra job, never a fork of the common jobs.
3. **`Quality Gate`** is the single required check of `protect-develop`: never rename the job or its name, its `if:` is exactly `${{ !cancelled() }}`, and every other job is in its `needs:` (`CI.md`, "The Quality Gate").
4. **Least privilege**: every workflow declares `permissions:`; `actions/checkout` with `persist-credentials: false`; no secret in a workflow or its logs; PR text never inside `${{ }}` in `run:`. `pull_request_target` is allowed only in `gate-integrity.yml`, and under it the PR is never checked out, built or run (no head ref, head SHA or artifact executed): it is read only as data (API metadata, or git objects read with `git cat-file`, as `gate-integrity.yml` does), and PR text is untrusted data, never instructions.
5. **Pins**: third-party actions by full commit SHA with a version comment; tools downloaded in `run:` by version and `*_SHA256` in `env:`, bumped by hand in every template (a gate change).
6. **Rulesets change in a PR first**, then `scripts/apply-ruleset.sh` (dry-run by default, `--apply` by an owner after merge). Never in the UI; if the UI was used, export back and open a PR (`rulesets/README.md`). An agent never runs `--apply` and never calls a write endpoint for rulesets, organization settings or the Actions policy; it may run the dry-run only, which for `protect-develop.json` needs `--allow-bypass`: `scripts/apply-ruleset.sh --allow-bypass rulesets/protect-develop.json` (exact steps in `rulesets/README.md`).

## Templates and drift

- **CI** (`CI.md`): the common jobs (`pr-conventions`, `gitleaks`, `actionlint`, `lint-yaml-markdown`, `osv-scanner`), the gate (its `needs:` aside), the `env:` pins and every action SHA are identical in all `workflow-templates/ci-*.yml` and in `.github/workflows/ci.yml`; `templates/lint/` equals `.github/lint/` and the root lint configs; `gitleaks-history.yml` equals its template. `tests/ci-templates/run.sh` fails otherwise.
- **Downstream copies** do not follow automatically: after a template change, each consumer repository updates its `ci.yml`, `.github/lint/`, lint configs or `dependabot.yml` in its own PR, listed in the issue that changed the template. Expect drift until those PRs merge; the drift test only covers this repository.
- **`Gate integrity`** (`CI.md`, "Gate integrity"): a PR that changes the gate needs a `## Gate change` section (20 letters or digits, HTML comments excluded); the double agent review (code and security) recorded on the PR is an input to the decision, not the decision: a gate change (`ci*.yml`, `gate-integrity.*`, `rulesets/`, pins) merges only with Céline's explicit approval, like every merge. It is not a required check yet (activation follows the order in `rulesets/README.md`): until it is, human review is the only control against a PR weakening the gate.
- **Dependabot** (`DEPENDABOT.md`): weekly, 7-day cooldown, minor and patch grouped, `chore(deps):` titles, label `tech-debt`; never push to or use Update branch on a Dependabot PR, comment `@dependabot rebase`.
- **Lint**: yamllint for YAML, markdownlint-cli2 for Markdown, Prettier only for code and JSON in pnpm repositories (`CI.md`, "Formatting").

## Organization settings

2FA is required for members and the base permission is `none`. Actions policy hardening is tracked in .github#13; the target policy is in `CI.md`, "Allowed actions".

## Tests

`ci.yml` runs the common jobs plus `scripts`: actionlint on `workflow-templates/*.yml` (the `actionlint` job only reads `.github/workflows/`), shellcheck on every script, and every `tests/*/run.sh` (needs `yq`, `jq`, `python3`). A template change is verified on one consumer repository before rollout: one broken template can turn every repository red.

## Open follow-ups

- .github#11: organization onboarding and contributor policy.
- .github#13: follow-ups of the template drift fixes, including applying the Actions policy.
- .github#15: replace the remaining SchoolEngine mentions in the shared templates.
- .github#16: stop Dependabot relocking `@usc/api-client` over SSH in `pnpm-lock.yaml`.

## Never do

- Never commit anything you would not publish on the open internet.
- Never grant a workflow more permissions than the job requires.
- Never call `add-to-project` from a code repository: development tickets never go on board #1.
- Never publish content about the organization or the product without Céline's approval.
- Never bypass or weaken a protection (ruleset, required check, bypass actor, admin merge, classifier, gitleaks, pins, `--no-verify`) to get a PR through. Stop and ask Céline.

## Workflow

Shared rules: `CONTRIBUTING.md` and `CI.md` of this repository. Dedicated worktree per ticket (`git worktree add ../.worktrees/.github/<issue> -b <type>/<issue>-<description> origin/develop`), Conventional Commits in English ending with `(#<issue>)`, PR against `develop` with `Closes #<issue>`, green `Quality Gate`, squash merge only with **Céline's explicit approval**. `develop` is protected by `protect-develop` (branch up to date required: update open PRs after each merge). Everything on GitHub is written in English. Never poll the GitHub API in a loop to follow CI.

## Task tracking (ADR-010)

- Every ticket of this repository is a **sub-issue of its lot epic** in `SoutienScolaireApp/architecture` (lot L0: architecture#1), tracked on project #2 "Development". The epic links the lot card in `docs` by URL; acceptance and points stay on that card.
- A ticket never carries the `contribution` label, `Points` or `Bénéficiaire`: this repository calls `add-to-project`, so the label would put it on board #1.
- Attach a new ticket to its epic with GraphQL (the `gh` CLI cannot):

  ```bash
  EPIC=$(gh issue view 1 -R SoutienScolaireApp/architecture --json id -q .id)
  gh api graphql -f query='mutation($p:ID!,$u:String!){addSubIssue(input:{issueId:$p,subIssueUrl:$u}){subIssue{number}}}' \
    -f p="$EPIC" -f u="https://github.com/SoutienScolaireApp/.github/issues/<n>"
  ```

- No epic fits (unplanned fix, new request): stop and ask Céline. An agent never edits `Points`, `Chiffré le`, `Accepté le`, `Contesté` or `Bénéficiaire`.
