# .github

Organization-level files of SoutienScolaireApp: the shared reusable workflow, the CI and Dependabot templates of the SchoolEngine code repositories, the organization ruleset kept as code, and the default community files.

| File | Purpose |
|---|---|
| `.github/workflows/add-to-project.yml` | Reusable workflow that adds `contribution` issues to the organization board (see [Reusable workflows](#reusable-workflows)). |
| `.github/workflows/add-to-project-caller.yml` | Caller of `add-to-project.yml` for this repository. |
| `CONTRIBUTING.md` | Workflow and naming conventions shared by every repository. |
| `SECURITY.md` | Private vulnerability reporting procedure. |
| `CI.md` | Shape and rules of every code repository's `ci.yml`, the `Quality Gate` contract, `Gate integrity`. |
| `workflow-templates/` | Organization workflow templates `ci-common`, `ci-node`, `ci-flutter`, `ci-openapi`, `ci-ansible`, `gate-integrity` and `gitleaks-history` (Actions > New workflow). |
| `templates/lint/` | Default `.yamllint.yml` and `.markdownlint-cli2.yaml` copied to each repository root, and the hashed lint tool pins (`requirements.txt`, `package.json`, `package-lock.json`) copied to each repository's `.github/lint/`. |
| `templates/openapi/` | Default `.spectral.yaml` (extends `spectral:oas`) for the contracts repository. |
| `DEPENDABOT.md` | Dependency update rules and how each repository adopts its template. |
| `templates/dependabot/` | `dependabot.yml` templates: `common`, `node`, `flutter`, and the `container` and `lint` entries. |
| `.github/workflows/ci.yml` | CI of this repository, from the `ci-common` template plus a `scripts` job (actionlint on the templates, shellcheck, `tests/*/run.sh` including the template drift check `tests/ci-templates/`): produces the `Quality Gate` check. |
| `.github/workflows/gitleaks-history.yml` | Weekly gitleaks scan of the whole history, copy of the `gitleaks-history` template. |
| `.github/lint/` | Hashed lint tool pins of this repository, copies of `templates/lint/`. |
| `.github/dependabot.yml` | Dependabot configuration of this repository, from the `common` template (`github-actions`, also scanning `workflow-templates/`) plus `pip` and `npm` for the lint tools. |
| `.yamllint.yml`, `.markdownlint-cli2.yaml` | Lint configuration of this repository, copies of `templates/lint/`. |
| `rulesets/` | Organization rulesets as code (`protect-develop.json`: protection of the default branch, required `Quality Gate` check) and how to change them. Read its warning before the first `--apply`. |
| `workflow-templates/gate-integrity.yml`, `.github/workflows/gate-integrity.yml` | `Gate integrity` check (`pull_request_target`, the PR is read as data): template and this repository's copy. |
| `.github/scripts/gate-integrity.sh` | Checker run by `Gate integrity`, copied into every code repository; tests in `tests/gate-integrity/`, run by the `scripts` job of `ci.yml`. |
| `scripts/apply-ruleset.sh` | Compares a ruleset file with the live ruleset (dry-run by default) and applies it with `--apply`; organization rulesets, or repository rulesets with `--repo <owner>/<repo>`. Tested by `tests/apply-ruleset/run.sh`. |

The CI templates, the Dependabot templates, the checker and the ruleset come from the former `SchoolEngine/.github`, merged here when the SchoolEngine repositories moved into this organization (SoutienScolaireApp/architecture#25). The issue forms and the pull request template of the code repositories live in each code repository, not here.

## Reusable workflows

Shared workflows live in `.github/workflows/` and are called from each repository with a one-line job. They are parameterized, never forked.

### `add-to-project.yml`: contribution issues on the board

Adds an issue to the organization board (project #1, the single source of the contribution journal) **only when it carries the `contribution` label**. Ordinary issues and product sub-issues stay off the board. An issue labeled after its creation is added at that moment.

Caller, to save as `.github/workflows/add-to-project.yml` in each repository:

```yaml
name: Add contribution issues to the board

on:
  issues:
    types: [opened, reopened, transferred, labeled]

permissions: {}

jobs:
  add-to-project:
    uses: SoutienScolaireApp/.github/.github/workflows/add-to-project.yml@develop
    secrets: inherit
```

Requirements:

- the `contribution` label exists in the calling repository (exact case: GitHub Actions label matching is case-sensitive);
- the organization automation GitHub App is installed on the repository, with read and write access to organization projects and read access to issues;
- the organization variable `AUTOMATION_APP_ID` and the organization secret `AUTOMATION_APP_PRIVATE_KEY` are visible to the repository.

The workflow token needs no permission: the job authenticates as the App with a short-lived installation token. In this repository the caller is `add-to-project-caller.yml` and references the workflow by its local path.

## Inheritance by the other repositories

This repository is public, so GitHub applies `CONTRIBUTING.md` and `SECURITY.md` as defaults to every repository of the organization that does not define its own ([GitHub docs: creating a default community health file](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file)). They stay generic: they apply to `docs`, `journal` and `legal` as much as to the code repositories.

Being public, this repository must never hold anything confidential: no secret, no personal data, no internal roadmap, no threat model and no security finding. The controls it documents (`CI.md`, `rulesets/`, the templates) are public on purpose: they describe how every change is checked, which any contributor needs to know, not where the product is weak.
