# .github
Configuration GitHub de l'organisation : page d'accueil, templates d'issues/PR, workflows réutilisables

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
