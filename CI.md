# CI of the code repositories

Every code repository, and this one, owns one workflow, `.github/workflows/ci.yml`, copied from a template of this repository. There is no reusable workflow: a repository's CI is readable in one file and changes through a pull request of that repository. Security tool choices: ADR-014 (`SoutienScolaireApp/architecture`).

## Templates

| Template | For | Jobs on top of the common ones |
|---|---|---|
| [`ci-common`](workflow-templates/ci-common.yml) | Docs and configuration repositories (`architecture`, `.github`) | none |
| [`ci-node`](workflow-templates/ci-node.yml) | pnpm repositories (`backend`, `parent-web`, `admin-web`) | `node`: token guard, [contracts lockfile guard](#the-contracts-lockfile-guard), frozen install without scripts [reading `contracts`](#reading-the-private-contracts-repository) over HTTPS only, format check (Prettier), lint, typecheck, tests with a coverage floor (`COVERAGE_MIN`: 80 % for `backend`, 70 % for `parent-web` and `admin-web`), build |
| [`ci-flutter`](workflow-templates/ci-flutter.yml) | `mobile-app` | `flutter`: pinned SDK (sha256 verified), token guard, HTTPS-only check of `contracts`, enforced lockfile [reading `contracts`](#reading-the-private-contracts-repository), `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test --coverage`, coverage floor 70 % |
| [`ci-openapi`](workflow-templates/ci-openapi.yml) | `contracts` | `openapi-lint` (Spectral 6.16.3 standalone binary, sha256 verified, rule set `.spectral.yaml` from `templates/openapi/`, warnings block), `oasdiff` (breaking changes against the latest `v*` release tag, or the base branch while no release exists; the whole top-level directory of `OPENAPI_SPEC`, `openapi/v1/openapi.yaml` in `contracts`, is the baseline, so a split document compares correctly), `generation-drift` (`git status` must stay clean after regeneration) |
| [`ci-ansible`](workflow-templates/ci-ansible.yml) | `infrastructure` | `ansible`: ansible-core and ansible-lint installed from the [hashed pins](#the-ansible-toolchain) of `.github/ansible/`, `--syntax-check` of every playbook; `sops`: every tracked `<name>.sops.yml`, `.yaml` or `.json` has a `sops` block with an encrypted `mac`, and every value outside that block is `ENC[...]`, in every YAML document (empty strings and nulls excepted: sops leaves them as is, and they hold no secret; a key excluded from encryption, such as `*_unencrypted` or a key left out by `encrypted_regex`, fails, so keep clear settings out of `*.sops.*` files; the sops configuration `.sops.yaml` has no prefix and is not matched; file names are read NUL separated and unquoted, so a non-ASCII name is checked too; `tests/sops-regex/run.sh`) |

Common jobs, in every template:

| Job | Display name | Blocks on |
|---|---|---|
| `pr-conventions` | PR title and linked issue | title not in Conventional Commits or not ending with the issue number `(#<issue>)`; no `Closes #n` (or Fixes/Resolves, `<this repo>#n` or its issue URL) on an issue of the same repository in the body. Dependabot PRs are exempt from the suffix and the closing keyword |
| `gitleaks` | Secrets (gitleaks) | any secret in the commits of the PR (`gitleaks git --redact` on `base..head`) |
| `actionlint` | Workflows (actionlint) | any actionlint or shellcheck finding in the workflows |
| `lint-yaml-markdown` | YAML and Markdown lint | yamllint (`--strict`) or markdownlint finding |
| `osv-scanner` | Vulnerable dependencies (osv-scanner) | a high or critical vulnerability (CVSS 7.0 or more), or one without a score, in a committed lockfile |
| `gate-drift` | Gate copy drift | a PR that touches `gate-integrity.yml` or `gate-integrity.sh` while either differs from public `.github` `develop`: see [Drift of the copies](#drift-of-the-copies) |
| `quality-gate` | **Quality Gate** | any job above that did not succeed |

Next to `ci.yml`, every repository has `.github/workflows/gate-integrity.yml` ([template](workflow-templates/gate-integrity.yml)), the `Gate integrity` check: see [Gate integrity](#gate-integrity), and `.github/workflows/gitleaks-history.yml` ([template](workflow-templates/gitleaks-history.yml)), the weekly scan of the whole history: see [Security rules](#security-rules-adr-014).

**Drift.** The common jobs, the gate (its `needs:` aside), the shared `env:` pins and every action SHA are identical in all the templates and in this repository's own workflows; `templates/lint/` and `.github/lint/` are identical too. `tests/ci-templates/run.sh` (run by the `scripts` job) fails otherwise, and the same job runs actionlint on `workflow-templates/*.yml`. Dependabot scans `workflow-templates/` with `.github/workflows/`, so an action update reaches both in one PR. Each repository's `ci.yml` follows the template through its own PR (listed in the issue that changed the template).

Placeholders that a scaffold ticket must fill are marked `TODO(scaffold)` in the templates. They fail closed: an unfilled template is red, never green on nothing.

## Using a template

1. In the repository, open **Actions > New workflow**: the templates are listed in the section of workflows created by SoutienScolaireApp. If they are not shown, copy the file by hand: `workflow-templates/ci-<variant>.yml` to `.github/workflows/ci.yml`.
2. Copy `templates/lint/.yamllint.yml` and `templates/lint/.markdownlint-cli2.yaml` to the repository root (and, for `contracts`, `templates/openapi/.spectral.yaml`), and `templates/lint/requirements.txt`, `package.json` and `package-lock.json` to `.github/lint/`. Append `templates/dependabot/lint.yml` to `.github/dependabot.yml`, and copy `workflow-templates/gitleaks-history.yml` to `.github/workflows/`. The lint jobs refuse to run without these files.
   For `ci-ansible`, copy `templates/ansible/requirements.txt` to `.github/ansible/` and append `templates/dependabot/ansible.yml` to `.github/dependabot.yml`. The `ansible` job refuses to run without the file.
   For a pnpm repository, pin pnpm in the `packageManager` field of `package.json` to a major that Dependabot supports (GitHub documents pnpm v7 to v10; `pnpm@10.34.6` on 2026-10-15).
   For a pnpm repository, also define the scripts the `node` job calls (`format:check` = `prettier --check .`, `lint`, `typecheck`, `test:coverage`, `build`) and keep YAML and Markdown out of Prettier (see [Formatting](#formatting)).
3. Fill the `TODO(scaffold)` placeholders, open the pull request, and check that every job, then `Quality Gate`, is green.

The templates are only offered from the default branch (`develop`) of this repository, once merged.

## The shape every `ci.yml` keeps

- `name: CI`.
- `on: pull_request` with types `[opened, synchronize, reopened]` only. No `edited`: **after editing the PR title or body, push a commit or re-run the `PR title and linked issue` job** (it reads the title and body live from the API, so a re-run sees the new text). Same for a label added after the last run (`breaking-change-approved` in `ci-openapi`). No `workflow_dispatch`: the fork guard would skip every job and the gate would fail.
- `permissions: contents: read` at workflow level. A job that needs more declares it at job level, minimal (`pull-requests: read` to read the PR title, body and labels). The organisation enforces a read-only default `GITHUB_TOKEN`.
- `concurrency` group `${{ github.workflow }}-${{ github.head_ref || github.ref_name }}` with `cancel-in-progress: true`.
- Fork guard on every job except the gate: `if: github.event.pull_request.head.repo.full_name == github.repository`. A fork PR skips every job and fails the gate: it never runs code with the repository's token.
- `timeout-minutes` on every job.
- `actions/checkout` always with `persist-credentials: false`.
- Third-party actions pinned by full commit SHA with a `# owner/action@vX.Y.Z` comment (checked in review and by `tests/ci-templates/run.sh` for the templates; and enforced by the organisation setting `sha_pinning_required` since 2026-11-01, see [Allowed actions](#allowed-actions)). No wrapper action for the security tools.
- Lint tools (yamllint, markdownlint-cli2) installed from `.github/lint/`, every package including transitive ones pinned with its hash: `pip install --require-hashes --only-binary :all: --no-deps -r .github/lint/requirements.txt`, and `npm ci --ignore-scripts` of `package.json` and `package-lock.json` in `$RUNNER_TEMP` (no `node_modules` in the checkout). Dependabot bumps them (`pip`, `npm`).
- Tool versions pinned in the workflow `env:` block, one place per template, each with the sha256 of its linux amd64 release asset (`GITLEAKS_SHA256`, `ACTIONLINT_SHA256`, `OSV_SCANNER_SHA256`, `OASDIFF_SHA256`, `YQ_SHA256`, `SPECTRAL_SHA256`, `FLUTTER_SHA256`). The download is checked against that pinned value, never against a checksum file of the same release (an attacker who can replace an asset can replace the checksum file next to it).
- PR title, body and labels never appear in a `${{ }}` expression inside `run:` (script injection): they are fetched by the script and kept in shell variables.

## The Quality Gate

`Quality Gate` and [`Gate integrity`](#gate-integrity) are the **two required checks** of `develop`. They are required by the organisation ruleset `protect-develop` (kept as code in [`rulesets/protect-develop.json`](rulesets/protect-develop.json), see [`rulesets/README.md`](rulesets/README.md)), which names each check and its source (GitHub Actions, integration id 15368), not the workflow: every repository must produce checks called exactly `Quality Gate` and `Gate integrity`, or none of its PRs can be merged. The policy is **strict**: a PR merges only when its branch is up to date with `develop` and both checks passed on that state, so a PR older than a new CI rule cannot skip it (SoutienScolaireApp/parent-web#12). After each merge, update the other open PRs before merging them: the **Update branch** button or `gh pr update-branch <n>`. Dependabot PRs are rebased by Dependabot itself (`@dependabot rebase`); never push to them. Details in [`rulesets/README.md`](rulesets/README.md#why-strict_required_status_checks_policy-is-true).

Rules, all learned on TheOpenMusicBox:

- **Never rename** the `quality-gate` job or its name `Quality Gate`. A required check that no longer reports blocks every PR; a renamed one silently stops being required.
- **Its `if:` is exactly `${{ !cancelled() }}`, nothing else.** A skipped required check counts as **passing**: any extra condition that can be false (a fork guard, an event test) turns a red PR into a mergeable one. `always()` is not used either: it keeps the job alive on a cancelled run.
- It `needs:` **every other job** and fails unless every needed result is `success`. A `skipped` or `cancelled` job fails the gate.
- A cancelled run leaves the gate `cancelled`, which blocks the merge: re-run the workflow.
- **Adding a job**: add it under `jobs:` with the fork guard and a `timeout-minutes`, then add its id to the `needs:` list of `quality-gate`. Nothing else: the gate reads the results of `needs` generically. A job missing from `needs:` does not block anything.
- Removing a job: remove it from `needs:` in the same PR. It is a gate change ([Gate integrity](#gate-integrity)).

## Gate integrity

`Quality Gate` lives in each PR's own `ci.yml`, and `protect-develop` requires no approving review: a PR can weaken the gate that judges it. `Gate integrity` is the detective control decided on 2026-10-16 (SchoolEngine/.github#22) instead of mandatory approvals. It is the **second required check** of `protect-develop`, added by the activation PR SoutienScolaireApp/.github#43 and live once an organisation owner has applied the file ([`rulesets/README.md`](rulesets/README.md#enabling-the-gate-integrity-check)). The workflow has no fork or Dependabot guard: those PRs report it like any other, and a Dependabot PR gets it green with its read-only token.

### How it runs, and why the PR it judges cannot rewrite it

- It is a separate workflow, `.github/workflows/gate-integrity.yml`, on **`pull_request_target`**. GitHub takes that workflow file, and the checker `.github/scripts/gate-integrity.sh` it runs, from the repository's **default branch** (`develop`), never from the PR. GitHub's documentation used to say "the PR base branch"; since our PRs target `develop`, the default branch, both readings give the same file. A change to either file only takes effect after its own merge, and is itself a gate change.
- The PR is **data only**. The job checks out the default branch (no `ref:`), fetches the merge commit GitHub computed (`refs/pull/<n>/merge`) as git objects, and reads the files it needs with `git cat-file`: nothing from the PR is checked out, built, installed or executed. The base of the comparison is the first parent of that merge commit (the tip of `develop`).
- No PR field is interpolated into a script: only the PR number and SHAs go through `env:`; the PR (body, author) is saved as a JSON file read by `jq` and Python. Text from the PR is escaped in annotations and fenced by `::stop-commands::` markers in diffs, so it cannot issue workflow commands.
- `permissions: {}` at the top, `contents: read` and `pull-requests: read` for the job, no secret. Actions pinned by SHA, yq by version and sha256; `python3`, `jq`, `git` and `gh` come from the runner image. `tests/gate-integrity/run.sh` asserts these invariants on the workflow file and that this repository's copy is the template.
- It re-runs on new commits and when the title or body is edited (`opened`, `synchronize`, `reopened`, `edited`). It runs on fork PRs too (nothing is executed).

### What it checks

| Finding | With a `## Gate change` justification? |
|---|---|
| A common job missing from `ci.yml` (`pr-conventions`, `gitleaks`, `actionlint`, `lint-yaml-markdown`, `osv-scanner`, `gate-drift`), or `quality-gate` missing or renamed | refused |
| The gate's `if:` not exactly `${{ !cancelled() }}`; a job not in its `needs:`; `continue-on-error` other than an explicit `false` anywhere in `ci.yml` | refused |
| In any workflow: more than one YAML document, duplicate keys in a mapping, a YAML anchor, alias or merge key; a top-level key other than `name`, `run-name`, `on`, `permissions`, `env`, `defaults`, `concurrency`, `jobs` (keys are case-sensitive: `On:` is refused); no top-level `permissions:`; a `shell` other than exactly `bash`, `sh`, `pwsh`, `powershell`, `python` or `cmd`; a job named like a required check (`Quality Gate` outside `ci.yml`'s `quality-gate`, `Gate integrity` outside `gate-integrity.yml`'s `gate-integrity`) | refused |
| In any workflow: a job `name:` with an expression in any form other than `<name> (${{ matrix.<key> }})` (the rendered name then ends with `)` and can never be a required check's exact name; `Code quality (${{ matrix.os }})` is fine) | refused |
| In any workflow: a local `uses: ./...` outside `./.github/actions/` (steps) or `./.github/workflows/` (reusable workflows), or with `..` | refused |
| In any workflow but `gate-integrity.yml`: a `pull_request_target` or `workflow_run` trigger; `write-all`; a `write` permission in a workflow triggered by `pull_request`, `pull_request_target`, `pull_request_review`, `pull_request_review_comment`, `issue_comment` or `workflow_run` | refused |
| `ci.yml` `env:`: a `*_VERSION` that is not digits and dots, a version lower than on the base branch, a `*_SHA256` that is not 64 lowercase hex digits, a tool whose `*_VERSION` and `*_SHA256` do not change together, a `*_SHA256` removed while its `*_VERSION` stays | refused |
| `gate-integrity.yml` or the checker removed; an ignore without a valid justification and expiry ([Ignore files](#ignore-files)); `.gitleaks.toml` with `[extend] path` or `url`; a TOML ignore file with keys that differ only by case, or that is not valid TOML | refused |
| A job of the base branch removed from `ci.yml`; the definition of a common job or of the gate changed (the gate's `needs:` aside, so adding a job passes) | gate change |
| `ci.yml` changed outside `jobs`: `name`, `on`, `permissions`, `defaults`, `concurrency`, or `env` except the `*_VERSION` / `*_SHA256` pins (a new `BASH_ENV` or a lowered `COVERAGE_MIN` is a gate change); any `*_SHA256` value changed (a different tool binary) | gate change |
| Any other workflow added or changed, `gate-integrity.yml` included; a `write` permission that differs from the base branch in a workflow on other triggers (a release on `push`, CodeQL `security-events`): the set of scopes of a workflow added, widened or removed, an unchanged set is not reported; the checker changed; any file under `.github/actions/` added, changed or removed | gate change |
| The configuration of the common jobs or of Dependabot added, changed or removed: `.github/actionlint.yaml`, `.yamllint*`, `.markdownlint*`, `.github/dependabot.yml` | gate change |
| The tool pins `.github/lint/requirements.txt`, `package.json`, `package-lock.json` and `.github/ansible/requirements.txt` added or removed, or changed outside a Dependabot PR verified as for action SHAs (a swapped pin could make yamllint, markdownlint or ansible-lint a no-op) | gate change |
| `.gitleaks.toml` without `[extend] useDefault = true`, with `disabledRules`, or with a `[[rules]]` entry added or changed (a rule with a default rule's id replaces it) | gate change |

TOML keys are compared lowercased, as gitleaks and osv-scanner read them: `[AllowList]` is checked like `[allowlist]`, `DisabledRules` like `disabledRules`.

**Action SHAs.** A changed SHA in `uses:` is ignored only in a PR opened by `dependabot[bot]` whose every commit is authored by `dependabot[bot]` with a verified signature (anyone with write access can push to a Dependabot branch), and only when the action itself (`owner/repo`) is unchanged; in `gate-integrity.yml` it is never ignored. Otherwise a changed SHA makes a gate change: add the `## Gate change` section to the PR body (editing the body of a Dependabot PR is fine; pushing to its branch is not).

Changes to stack jobs (adding a job, a step, a stack job's commands) are not gate changes. Matrix jobs without a `name:` get the matrix values appended in parentheses, so they never carry a required check's exact name.

### Approving a gate change

The checker only asks for a reason: the PR body has a `## Gate change` section whose text, **HTML comments removed entirely**, has at least 20 letters or digits. The approval itself is the **double agent review (code and security) recorded on the PR**, then the explicit go of an organisation owner to merge, as for every PR. There is no label and no human approver mechanism. The section is re-read when the body is edited: no re-run by hand is needed.

### Residual risks

It is a detective control with a narrow preventive core, not a guarantee:

- **Owners are trusted.** The PRs are opened by an organisation owner account and `protect-develop` requires 0 approvals: an owner can still change the ruleset or merge after a review that missed something. The control makes a weakening visible and attributable.
- **A new or changed workflow runs before review.** A workflow added on `pull_request` runs on the PR's own commits as soon as they are pushed, before anyone reads it (read-only token, no secret, but it can report checks). `Gate integrity` flags it; reviewers read every workflow change before anything else.
- **Required checks are matched by name.** Other workflows of a PR can report checks; the checker refuses the reserved names, and reviewers confirm that `Gate integrity` and `Quality Gate` each appear once on the head commit.
- **Dependabot rewrites PR bodies.** When Dependabot rebases or recreates a PR, it can rewrite the body and drop a `## Gate change` section added by hand: the check turns red again until the section is restored.
- **A broken check blocks its own fix.** The workflow and the checker always run from `develop`, so a PR that repairs them is judged by the broken version. The way out is the break-glass: the owner bypass on that PR, or the check removed from the live ruleset ([`rulesets/README.md`](rulesets/README.md#enabling-the-gate-integrity-check)).
- **The source of a required check is an app, not a workflow.** `integration_id` 15368 is the generic `github-actions` app, so `protect-develop` accepts a check of the right name from any workflow of the repository. A workflow that declares `checks: write` on a pushed branch, which the checker never sees because that branch is not the PR, can post a success named `Gate integrity` on the head SHA of a PR with its `GITHUB_TOKEN`. Only someone with write access can do it: a fork PR gets a read-only token, and users and OAuth apps cannot create check runs. It already applies to `Quality Gate`. No mitigation is applied: reviewers confirming that each check appears once is the only detection.
- **The script does not guard `Gate integrity`.** The guard of `scripts/apply-ruleset.sh` keeps `Quality Gate` only, deliberately, because the break-glass removes `Gate integrity` with the same script (`tests/apply-ruleset/run.sh` pins it). So a file that drops `Gate integrity` passes the guard, and the checker does not watch `rulesets/`: review and the dry-run are the only controls.
- **`pull_request_target` in a public repository.** GitHub blocks this event by default in public repositories unless an applicable Actions event policy allows it ([changelog of 2026-11-02](https://github.blog/changelog/2026-11-02-pull_request_target-blocked-by-default-december-2/), [Default policy for `pull_request_target`](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target)). Private and internal repositories are not affected, so only this repository is concerned. The default policy is in evaluate mode, apart from two brownouts on Monday 2026-11-09 and Monday 2026-11-16, 16:00 to 18:00 UTC: a blocked run fails with an error annotation and the workflow does not execute, so the check on `.github` is red until it is re-run after the window. From 2026-12-02 GitHub enforces the policy, as the docs say, for affected repositories on the default policy before general availability; without an explicit policy, PRs here could then pass only with the owner bypass. On 2026-11-06, `GET orgs/SoutienScolaireApp/actions/policies` and `GET repos/SoutienScolaireApp/.github/actions/policies` returned `total_count: 0`: there is no Actions event policy, which is consistent with the implicit default. This is separate from the Actions permissions of [Allowed actions](#allowed-actions). The decision and the change belong to an organisation owner.
- **After merge.** An approved change to `gate-integrity.yml` or the checker judges every later PR: the review of such a PR is the real control.
- **Not covered:** stack jobs made weaker while still succeeding (a test command that tests less), and files the checker does not read (a lint configuration, a `package.json` script). Those are for review.

### Rolling it out to a repository

The eight repositories of `protect-develop` have it (SoutienScolaireApp/.github#36). A new repository does it **before it joins the ruleset**: one `ci(quality-gate)` PR copies `.github/workflows/gate-integrity.yml` and `.github/scripts/gate-integrity.sh` from this repository unchanged, and adds the `gate-drift` job to `ci.yml` and to the gate's `needs:` in the same PR: the checker refuses a `ci.yml` without that job. That PR gets no `Gate integrity` run (the workflow is not on `develop` yet), which only a repository outside the ruleset can merge; the next ones do. Canary, activation, break-glass and new repositories: [`rulesets/README.md`](rulesets/README.md#enabling-the-gate-integrity-check).

To change the checker: change it and its tests here (`tests/gate-integrity/run.sh`, run by the `scripts` job of this repository's `ci.yml`), then copy it into each repository in a PR justified as a gate change.

**Adoption window.** A change to the checker, a template, a lint configuration or `dependabot.yml` merged here reaches each repository through its own PR, and until that PR merges:

- the repository is still judged by its previous checker and `ci.yml`, so a new rule is not enforced there yet, and `gate-drift` only warns on its other PRs;
- the adopting PR is judged by that previous checker, from `develop`, and is a gate change as soon as it touches a watched file. Without a `## Gate change` section `Gate integrity` is red, and since the check is required the PR cannot merge;
- if the new checker requires something new (a common job, for example), the same PR adds it: the next PR is judged by the new checker.

### Drift of the copies

The `gate-drift` job of each `ci.yml` compares both files, by file mode and git blob hash (a lost executable bit is drift), with `develop` of public `SoutienScolaireApp/.github`. It uses no token: it reads a public repository with an anonymous `git fetch`, and only compares the files, never runs them.

| The PR (merge commit against its first parent) | Result |
|---|---|
| Touches either file, and either differs from the source | fails, the PR must copy both unchanged |
| Touches neither, and either differs | `::warning::`, the job passes: a merge in this repository must not turn the others red before their copies land |
| Both files match | passes |
| Touches either file, and the source cannot be read within 60 seconds or lacks a file | fails, re-run the job: a PR that touches these files must not pass unseen |
| Touches neither, and the source cannot be read within 60 seconds or lacks a file | `::warning::`, the job passes, drift not checked: an outage must not block every PR. Re-run the job to check |

- **In this repository** the job passes with a `::notice::` and fetches nothing: it is the source, a PR here legitimately differs from `develop`, and comparing `develop` with itself proves nothing. The job stays in `ci.yml` so that the common jobs stay identical. Here, `tests/gate-integrity/run.sh` checks the workflow against its template.
- **Fork PRs** skip the job with the same guard as the other common jobs: it never fails one on its own, and `Quality Gate` stays red on a fork PR as it already does.
- **Dependabot.** A bump of an action SHA in a repository's `gate-integrity.yml` touches that file: it fails until the same bump is on `develop` here, and it needs a hand-written `## Gate change` section in each repository, this one included (see "Action SHAs"). Merge the `.github` PR first, then re-run the job on the other PRs.
- It runs from the PR's own `ci.yml`, so a PR can edit it: `Gate integrity` reports that as a gate change. This job detects drift, it is not a control against a hostile PR. Tests: `tests/gate-drift/run.sh`.

### Ignore files

Every ignore carries a justification of at least 20 letters or digits and an expiry date that is not past and at most **180 days** ahead (ADR-014). Renewing means a new justification and a new date, in a reviewed PR.

- `osv-scanner.toml` (any directory but `.git`, `node_modules` and `.dart_tool`: osv-scanner reads the one next to each lockfile): each `[[IgnoredVulns]]` has `reason` and `ignoreUntil`; each `[[PackageOverrides]]` that ignores has `reason` and `effectiveUntil`. osv-scanner itself stops ignoring after the date; the check also refuses a past date.
- `.gitleaksignore`: each fingerprint is preceded by a comment `# <justification> expires: YYYY-MM-DD`. gitleaks has no expiry of its own, so the check fails once the date is past: remove the entry or renew it.
- `.gitleaks.toml`: extends the default rules (`[extend] useDefault = true`); each allowlist (top level or in a rule) has a `description` ending with `expires: YYYY-MM-DD`, enforced the same way.

```toml
[[allowlists]]
description = "Synthetic keys of the test fixtures, not secrets. expires: 2027-01-31"
paths = ['''tests/fixtures/keys/''']
```

An expired entry turns every PR of the repository red until it is removed or renewed: intended.

## Formatting

One formatter of record per file type, all blocking:

| Files | Tool | Job |
| --- | --- | --- |
| YAML | yamllint `--strict` (`.yamllint.yml`, version in `.github/lint/requirements.txt`) | `lint-yaml-markdown` |
| Markdown | markdownlint-cli2 (`.markdownlint-cli2.yaml`, version in `.github/lint/package-lock.json`) | `lint-yaml-markdown` |
| TypeScript, JavaScript, JSON, CSS, HTML (pnpm repositories) | Prettier, `pnpm run format:check` | `node` (`Format check`) |
| Dart | `dart format --set-exit-if-changed` | `flutter` (`Format`) |

In a pnpm repository, `.prettierignore` lists `*.md`, `*.yml` and `*.yaml` (plus the lockfile and build outputs). Prettier would otherwise judge them a second time with a different rule set: a Markdown file that markdownlint accepts can fail `Format check`, and Dependabot PRs, which rewrite `.github/` YAML, would fail on a rule nobody chose. In `parent-web` an unformatted `CLAUDE.md` merged from a branch older than the `node` job turned `develop` red for every PR (SoutienScolaireApp/parent-web#12).

## Security rules (ADR-014)

- **A gitleaks finding means the secret is compromised**: it has already been pushed. Rotate it first, then remove it from the branch. `.gitleaksignore` and inline `gitleaks:allow` are used only for proven false positives, justified in the PR; `.gitleaksignore` entries and allowlists also carry an expiry date ([Ignore files](#ignore-files)).
- **osv-scanner** blocks on high and critical findings, and on findings without a severity score. Moderate and low findings are left to Dependabot alerts. A finding with no available fix may be ignored only in `osv-scanner.toml` (`[[IgnoredVulns]]` with `reason` and `ignoreUntil`), reviewed in the PR. `pnpm audit` is a local command, never a CI check.
- **Dependabot PRs** are exempt from the `Closes #n` check only (author `dependabot[bot]`); their `chore(deps): ...` titles pass the title check like any other.
- **Whole history, weekly**: `gitleaks-history.yml` scans every commit reachable from any branch or tag every Monday, and is run by hand (**Actions > Secrets history scan > Run workflow**) before any mirror or migration of a repository (the Forgejo mirror included). The `gitleaks` job of `ci.yml` only scans the commits of the PR. A finding of the scheduled run only shows as a red run in the Actions tab (and GitHub's failure email to the last person who changed the schedule): no issue or PR check is created, so look at it every week. GitHub disables a scheduled workflow after 60 days without repository activity; re-enable it in **Actions > Secrets history scan** if the repository was quiet.
- **Checksum provenance**: every tool downloaded in a `run:` step is checked against a sha256 pinned in `env:`, never against a checksum file of the same release. The accepted risk is the first pin: the sha256 is taken once from the release (asset digest, cross-checked locally); a release replaced before that moment would be pinned as is.

## Reading the private contracts repository

The generated API clients are git dependencies on the private `SoutienScolaireApp/contracts`: `@usc/api-client` for pnpm, `usc_api_client` for pub. CI reads that repository through the GitHub App "SchoolEngine CI". The normative rules are ADR-013 rule 9 ([Amendment 1](https://github.com/SoutienScolaireApp/architecture/blob/develop/adr/ADR-013-api-client-distribution.md#amendment-1-2026-10-16-dependabot-and-ci-access-to-contracts), then Amendment 3) in `SoutienScolaireApp/architecture`; this section says how the templates apply them.

**Consumers only.** The steps are in `ci-node` and `ci-flutter`, the templates of the four consumers (`backend`, `mobile-app`, `parent-web`, `admin-web`). `ci-common`, `ci-openapi` and `ci-ansible` carry none. A repository copied from `ci-node` or `ci-flutter` that does not consume a client deletes the guards, the credential check, the token step and the `env:` of the install step: the credentials are not shared with it, so the check would fail.

| Credential | Kind | Purpose |
|---|---|---|
| GitHub App "SchoolEngine CI" | Organization App | Repository permission `Contents: read` only, installed on `contracts` only |
| `SCHOOLENGINE_CI_APP_CLIENT_ID` | Organization variable | Client ID of the App, not a secret |
| `SCHOOLENGINE_CI_APP_PRIVATE_KEY` | Organization Actions secret | App key for ordinary runs |
| `SCHOOLENGINE_CI_APP_PRIVATE_KEY` | Organization Dependabot secret | Second key of the same App, for the CI of Dependabot PRs: same name, other store |

The variable and both secrets are limited to the four consumers.

**In the job that installs dependencies** (`node`, `flutter`):

1. The workflow declares `permissions: contents: read` and runs on `pull_request`; the job keeps the fork guard, so a fork PR never reaches a token. A job that mints the token only runs on `push` or a same-repository `pull_request`, never on `pull_request_target` or `workflow_run`.
2. `GIT_SSH_COMMAND: "false"` and `GIT_TERMINAL_PROMPT: "0"` are set at **job level**: an SSH attempt fails closed, and a URL that no rewrite matches fails fast.
3. Two guards run before any token exists. The token guard fails on a tracked file holding `x-access-token:` followed by a value, or `ghs_`, and prints only `file:line`. The lockfile guard differs by client: pnpm runs [the contracts lockfile guard](#the-contracts-lockfile-guard), which also accepts the SSH spelling Dependabot records; pub refuses `git@github.com`, `ssh://` and `git+ssh` in `pubspec.yaml` and `pubspec.lock`, because `contracts` has one form there, HTTPS.
4. A credential check ends with a clear `::error::` when the variable or the secret is missing. The private key never enters a `run:` step: the step only receives whether it is set.
5. `actions/create-github-app-token`, pinned by SHA, mints a token per job with `owner: SoutienScolaireApp`, `repositories: contracts` and `permission-contents: read`. It lasts one hour at most, and the action masks it and revokes it in its post step.
6. The rewrite exists only in the `env:` of the install step (`GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_n`, `GIT_CONFIG_VALUE_n`), anchored on `contracts.git`. `ci-node` carries two values of it (the HTTPS and SSH spellings), `ci-flutter` one (HTTPS). Never `git config --global`, never a file, never a rewrite of `git@github.com:` as a whole. The install step is the only reader of the token output, which is never copied to another output, `GITHUB_ENV`, an artifact or a cache.
7. The install runs no package script: `pnpm install --frozen-lockfile --ignore-scripts`, or `flutter pub get --enforce-lockfile`, which runs none.

The guards are steps of the `node` and `flutter` jobs, and those jobs are in the `needs:` of `Quality Gate`, so a failed guard blocks the merge. `tests/ci-templates/run.sh` holds the token guard, the credential check, the token step and the job-level `env:` the same in both templates, and runs the two `ci-flutter` guards on fixtures. It does not read the consumers' copies, which follow in their own PRs.

**Residual risks.**

- A writer to a consumer can exfiltrate an App key through a modified workflow, and read `contracts` with it. Bounded by `Contents: read` on `contracts` only, review of every PR, yearly key rotation and the emergency revocation of ADR-013 rule 9.
- The guards catch accidents and Dependabot rewrites. They are not a control against a PR author, who could change the workflow itself: that is the role of review and of [Gate integrity](#gate-integrity).
- The HTTPS-only transport rests on the job-level `GIT_SSH_COMMAND`: a job that loses it could try SSH with whatever the runner holds. This is harmless only while no runner has an SSH agent, key or deploy key for GitHub, which holds for GitHub-hosted runners and is a requirement for self-hosted ones.

## The contracts lockfile guard

`@usc/api-client` is a git dependency on the private `SoutienScolaireApp/contracts` (ADR-013 rules 5 and 9, Amendment 3 in `SoutienScolaireApp/architecture`). Dependabot records its lockfile entry in the SSH spelling (`git+ssh://git@github.com/...`, `repo: git@github.com:...`), with the same commit as the HTTPS spelling. Both spellings are accepted as a **representation only**: CI and the backend image build never speak SSH.

**The rule** ([`templates/contracts-lock/check-contracts-lock.sh`](templates/contracts-lock/check-contracts-lock.sh), POSIX `sh` and `awk`, tested by `tests/contracts-lock/run.sh`):

- `package.json`: the `@usc/api-client` specifier is exactly `git+https://github.com/SoutienScolaireApp/contracts.git#vX.Y.Z&path:/clients/typescript` (an exact tag), and the file contains no `git@`, `ssh://`, `git+ssh`, `git://` or `http://` (any case).
- `pnpm-lock.yaml`, a positive allowlist on the entry, exact and case-sensitive: the importer `version:` and the keys under `packages:` and `snapshots:` are `<form>#<40-hex commit>&path:/clients/typescript`, `<form>` being `git+https://github.com/SoutienScolaireApp/contracts.git` or `git+ssh://git@github.com/SoutienScolaireApp/contracts.git`; `resolution` holds exactly `commit`, `path: /clients/typescript`, `repo` (`https://github.com/SoutienScolaireApp/contracts.git` or `git@github.com:SoutienScolaireApp/contracts.git`) and `type: git`, and **no `tarball`**; every URL commit equals `resolution.commit`; the importer `specifier:` equals the one of `package.json`.
- Anywhere else in the lockfile, any `git@`, `ssh://`, `git+ssh`, `ssh+git://`, `git://`, `http://`, `github.com` or scp-like `host:path` URL fails (any case). Every key under `packages:` and `snapshots:` is either that exact entry or a registry key `name@<semver>` with an optional `(peers)` suffix: a tarball, `link:`, `file:` or git key of another package fails, as does a URL dependency or a flow mapping under `importers:`.
- Every other package: its key is `name@<semver>` with an optional `(peers)` suffix (no `=`, so no `patch_hash`: patches are refused), and its entry under `packages:` has exactly one `resolution: {integrity: sha<n>-<base64>}`, the only form pnpm 10 writes for registry packages; a `tarball`, `type`, `repo`, `directory` or `commit` field of the entry, a block-style resolution or a `resolution:` of a snapshot entry fails (a dependency that happens to be named `type` or `commit` is fine). `deprecated:` text is never scanned for URLs. No `link:` or `file:` importer, no URL dependency under `importers:`, `overrides:` only to registry versions (backend overrides one transitive version), and two-space indentation only. `node@runtime:` entries (pnpm's Node.js runtime dependencies) are refused by design.
- **Canonical layout only**: the guard accepts what pnpm itself writes and refuses every other YAML spelling. At column 0, only `lockfileVersion: '<n.n>'` and the section lines `settings:`, `importers:`, `packages:`, `snapshots:`, `overrides:`, `ignoredOptionalDependencies:` and `time:`, each once (a quoted key, a space before the colon, a flow value or any other key fails, `patchedDependencies`, `pnpmfileChecksum` and `catalogs` included). Flow values (`{`, `[`) only on the one-line `resolution`, `engines`, `cpu`, `os` and `libc` fields of a package entry and as `{}` on a snapshot key, the only places pnpm 10 writes them.
- Both files: no backslash escape (an escaped key such as `\u0040usc/api-client` would hide the dependency; `package.json` allows only `\"` and `\\`, which npm scripts need), no CRLF line endings, no byte order mark; no YAML anchor, alias or merge key in the lockfile.
- `package.json` also holds no `pnpmfile`, `patchedDependencies` or `packageExtensions` (the `pnpm` field included), and no `https://`, `link:`, `file:`, `npm:` value or `@usc` text outside the specifier line. In `dependencies`, `devDependencies`, `optionalDependencies`, `peerDependencies` and `overrides` (one entry per line, as npm and pnpm write them), every value is a semver range or the exact contracts specifier: `github:`, `user/repo`, `workspace:`, `jsr:`, `catalog:`, `npm:`, `runtime:` and URLs fail. `pnpm.overrides` to registry versions stay allowed.
- The repository root (the directory of the lockfile argument): no `.pnpmfile.cjs` or `.pnpmfile.mjs` and no `pnpmfile` text in `.npmrc`, because pnpmfile hooks run inside the install step that holds the token, `--ignore-scripts` or not; `pnpm-workspace.yaml`, if present, contains none of `pnpmfile`, `overrides`, `patchedDependencies`, `packageExtensions`, `catalog` or `@usc` anywhere (any case, so quoting, flow style or complex keys cannot hide them), no top-level flow mapping and no `?` key.

- Entry fields: under `packages:` only the unquoted keys `resolution`, `engines`, `cpu`, `os`, `libc`, `deprecated`, `hasBin`, `prepare`, `requiresBuild`, `bundledDependencies`, `peerDependencies`, `peerDependenciesMeta` and `version`; under `snapshots:` only `dependencies`, `optionalDependencies`, `transitivePeerDependencies`, `optional` and `id`. No carriage return anywhere (a lone CR is a line break for the YAML parser), no quote left open at the end of a line and no block scalar (`|`, `>`) in the lockfile.

The guard prints the offending line with any URL credential redacted.

**Not covered.** `.npmrc` settings other than `pnpmfile`, notably `registry=` and `@scope:registry=` pointing elsewhere (and `git-shallow-hosts`, and so on), `packageManager` and `devEngines` in `package.json` are not checked: they are reviewed in the PR like any configuration change.

**What it is for.** The guard is a safety net against accidents and Dependabot rewrites: it keeps a lockfile that the review would wave through from fetching anything but the locked commit of `contracts` with the token in scope. It is not a control against a malicious writer with push access, who could change the workflow or the guard itself, nor does it aim to catch hand-crafted YAML (multi-line quoted scalars, decoy lines and other spellings pnpm never writes) beyond the rules above; that risk rests on trust in the organisation owners while review is not enforced: no repository has a CODEOWNERS file and the code owner review decision was withdrawn ([ADR-014 note of 2026-11-05](https://github.com/SoutienScolaireApp/architecture/blob/develop/adr/ADR-014-security-tooling.md#note-of-2026-11-05-code-owner-review-withdrawn)). It is revisited when a second developer gets write access (SoutienScolaireApp/.github#9, deferred).

**The CI configuration it relies on** (the `node` job of `ci-node`): `GIT_SSH_COMMAND: "false"` and `GIT_TERMINAL_PROMPT: "0"` at **job level** on every job that installs dependencies, so an SSH attempt fails closed and an unmatched URL fails fast; the guard step before the install; and, in the `env:` of the install step only, `GIT_CONFIG_COUNT: "2"` with two values of the same rewrite to the token URL of `contracts.git`: `https://github.com/SoutienScolaireApp/contracts.git` and `git@github.com:SoutienScolaireApp/contracts.git`. Never `git config --global`, never a file, never a rewrite of `git@github.com:` or `ssh://git@github.com/` as a whole. The token handling (App token minted per job, `contents: read` on `contracts` only, `--ignore-scripts`) is unchanged.

**Adopting it in a consumer**: copy `templates/contracts-lock/check-contracts-lock.sh`, unchanged, to `.github/scripts/check-contracts-lock.sh`, in the same PR as the `ci.yml` changes above; the step fails if the copy is missing. The backend runs the **same script** in its `Containerfile` build stage before the install (`COPY` into the build stage only, allowed through `.containerignore`), with the same `GIT_SSH_COMMAND`, `GIT_TERMINAL_PROMPT` and two rewrite values. A consumer drifts from the template until its own PR merges: a change of the script here is rolled out by a PR per consumer, like `gate-integrity.sh`. Until a consumer has adopted it, its npm Dependabot PRs still need the HTTPS relock of [DEPENDABOT.md](DEPENDABOT.md#generated-api-clients).

## Bumping a tool version

Versions downloaded in `run:` steps are not seen by Dependabot. To bump one: change the version **and its `*_SHA256`** in the `env:` block of the template here, then in each repository's `ci.yml`. Take the sha256 from the asset digest GitHub shows on the release page (or `gh release view`), cross-checked with a local `sha256sum` of the downloaded asset and, when the project publishes one, its checksum file (the Flutter value comes from the Flutter release index). A version bump with its sha256 is a gate change (a different binary): the PR body gets a `## Gate change` section naming the release and where the sha256 was taken from. `Gate integrity` refuses a malformed version, a downgrade, a version or sha256 changed alone, and a sha256 removed while its version stays. Actions in `uses:` are bumped by Dependabot (`github-actions` ecosystem), keeping the SHA and the version comment in sync: in this repository it scans both `.github/workflows/` and `workflow-templates/` (minor and patch in one PR, a major in one PR per action across both directories). Each other repository's `ci.yml` gets its own Dependabot PR. The lint tools of `.github/lint/` and the Ansible toolchain of `.github/ansible/` are bumped by Dependabot too (`pip` and `npm`). When the pin of a step tool changes, also update `gitleaks-history.yml` for gitleaks.

## The Ansible toolchain

`ci-ansible` installs ansible-core, ansible-lint and every transitive package from `.github/ansible/requirements.txt`, a copy of `templates/ansible/requirements.txt`: `pip install --require-hashes --only-binary :all: --no-deps -r .github/ansible/requirements.txt`, then `pip check`, because `--no-deps` resolves nothing. Adopting it: copy the file and append `templates/dependabot/ansible.yml` to `.github/dependabot.yml`. A version bump by hand follows the regenerate line at the top of the file.

Galaxy collections are not covered. `requirements.yml` pins each collection by exact version, and `ansible-galaxy` installs it **without hash or signature verification**: a version is trusted as Galaxy serves it, and Dependabot does not see it (bump by hand, reviewed in a PR).

## Allowed actions

Decision of SoutienScolaireApp/.github#8, completed by SoutienScolaireApp/.github#17 after an audit (2026-10-31) of every `uses:` on every branch of the non-archived repositories, and recorded in ADR-014 (Amendment 2) in `SoutienScolaireApp/architecture`. The organisation moved from "allow all actions" to **selected actions**, with SHA pinning required. The policy is **applied since 2026-11-01** (SoutienScolaireApp/.github#13):

- `allowed_actions: selected`, `github_owned_allowed: true` (`actions/*`), `verified_allowed: false`;
- `patterns_allowed`: the third-party actions in use, nothing else. A new third-party action is added to this list in the PR that first uses it, after review:
  - `pnpm/action-setup@*`: installs pnpm in the Node.js and OpenAPI jobs (`workflow-templates/ci-node.yml`, `ci-openapi.yml` and their copies);
  - `sigstore/cosign-installer@*`: installs cosign in `backend` `.github/workflows/image.yml`, which signs the published image digest and verifies the signature before deployment (ADR-013, Amendment 2). It runs in the `publish` job (`contents: read`, `packages: write`, `id-token: write`) and in the `weekly-scan` job (`contents: read`, `packages: read`);
  - `dataaxiom/ghcr-cleanup-action@*`: deletes old backend image versions from GHCR in `backend` `.github/workflows/image-cleanup.yml` (retention). It runs in the `cleanup` job (`contents: read`, `packages: write`);
- `sha_pinning_required: true`: an action referenced by tag or branch fails the run.

The `@*` suffix allows every version of the action, so a Dependabot bump of its SHA needs no change here; the pin itself is enforced by `sha_pinning_required`. This is a deliberate trade-off: SHA pinning already forces a full SHA in every `uses:`, and a pattern per SHA would refuse every Dependabot bump until an owner edits the organisation setting by hand.

**Bumps of the backend image actions are reviewed by a human.** A Dependabot PR that bumps `sigstore/cosign-installer` or `dataaxiom/ghcr-cleanup-action` brings new third-party code that runs with the job permissions above (package write, and an OIDC token for `publish`): it merges only after a person has read the release and the diff between the two SHAs, never on a green gate alone.

**Local actions and reusable workflows.** The policy option allows the actions and reusable workflows of the organisation itself, so local actions (`uses: ./.github/actions/...`) and the reusable `add-to-project.yml` need no pattern. SHA pinning applies to actions only: a reusable workflow may still be referenced by branch or tag (`add-to-project.yml@develop`). A caller that references `add-to-project.yml@develop` runs whatever is on `develop` of this repository at the time of the run, with the secrets it passes (`secrets: inherit`): `develop` here stays protected by `protect-develop` and every change to the workflow is reviewed. Pinning a caller to a commit SHA of this repository is possible, at the cost of a manual bump in each caller; it is an option, not a requirement.

**Applying it again, or changing it,** is an owner action (the policy changes only by a PR to this section first), at the organisation level, in **Settings > Actions > General**, "Policies":

1. Select **Allow SoutienScolaireApp, and select non-SoutienScolaireApp, actions and reusable workflows**.
2. **Allow actions created by GitHub**: on.
3. **Allow Marketplace actions by verified creators**: off.
4. **Allow or block specified actions and reusable workflows**: on, with this line pasted as is:

   ```text
   pnpm/action-setup@*, sigstore/cosign-installer@*, dataaxiom/ghcr-cleanup-action@*
   ```

5. **Require actions to be pinned to a full-length commit SHA**: on.
6. **Save**.

**After applying**:

- Read the result back, read-only, with a token of an organisation owner (the endpoints need organisation administration access): `gh api orgs/SoutienScolaireApp/actions/permissions` (`allowed_actions: selected`, `sha_pinning_required: true`) and `gh api orgs/SoutienScolaireApp/actions/permissions/selected-actions` (the three patterns, `verified_allowed: false`).
- Re-run the `Quality Gate` of one open PR per stack. `image.yml` runs only on push to `develop` and on its weekly schedule, and `image-cleanup.yml` only weekly, so a refused action in `backend` may show up to a week later: check the next run of each in the Actions tab of `backend` (or `gh run list -R SoutienScolaireApp/backend -w image.yml`, then `-w image-cleanup.yml`). A refused action shows as a failed run naming the action.
- A branch whose workflows still reference an action by tag fails once the setting is on: rebase it on `develop`.
- **Residual risk, Dependabot.** The GitHub documentation does not say whether `sha_pinning_required` applies to the jobs Dependabot runs to compute its updates. Watch the next weekly Dependabot run of each repository (the "Dependabot Updates" runs in the Actions tab). If they fail on the policy, do not switch SHA pinning off for the organisation: record the failure in SoutienScolaireApp/.github#13 and decide there first; the policy changes only by a PR to this section.

Applied on 2026-11-01 (SoutienScolaireApp/.github#13). Read back through the API that day: `allowed_actions: selected`, `github_owned_allowed: true`, `verified_allowed: false`, `patterns_allowed` with the three patterns above, `sha_pinning_required: true`. Before that date the organisation allowed all actions without the SHA pinning requirement.

## Runners: GitHub-hosted now, self-hosted later

Jobs run on `ubuntu-latest` until the self-hosted lanes exist (SoutienScolaireApp/infrastructure#12, ADR-011). Each `runs-on:` carries a comment with its future value, `[self-hosted, Linux, X64, <lane>]`. The switch is a one-line change per job and does not touch the gate. Tools are installed by the jobs themselves (no reliance on the preinstalled software of the GitHub image, except `jq`, `curl`, `git`, `gh`, `shellcheck` and, for `Gate integrity`, `python3`), so the same file runs on a self-hosted lane, and later on Forgejo Actions.
