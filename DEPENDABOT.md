# Dependency updates with Dependabot

SchoolEngine repositories keep their dependencies up to date with Dependabot version updates and Dependabot security updates (ADR-014 in `SoutienScolaireApp/architecture`; Dependabot replaces the Renovate of the founding specification). Dependabot alerts are enabled on the organisation.

## Templates

| Template | For | Ecosystems |
|---|---|---|
| [`common.yml`](templates/dependabot/common.yml) | Repositories without a package manifest (`architecture`, `.github`, `infrastructure`), and every repository until its manifest exists | `github-actions` |
| [`node.yml`](templates/dependabot/node.yml) | pnpm repositories (`contracts`, `backend`, `parent-web`, `admin-web`) | `github-actions`, `npm` (reads `pnpm-lock.yaml`) |
| [`flutter.yml`](templates/dependabot/flutter.yml) | `mobile-app` | `github-actions`, `pub` |
| [`container.yml`](templates/dependabot/container.yml) | Entry to append in a repository that builds an OCI image (`backend`, `infrastructure` if it holds image definitions) | `docker` |
| [`lint.yml`](templates/dependabot/lint.yml) | Entries to append in **every** repository: the lint tools of `.github/lint/` (CI.md) | `pip`, `npm` |
| [`ansible.yml`](templates/dependabot/ansible.yml) | Entry to append in the repository that uses `ci-ansible` (`infrastructure`): the toolchain of `.github/ansible/` (CI.md) | `pip` |

## Using a template

1. **Each repository's CI ticket** copies `common.yml` to `.github/dependabot.yml`, in the same PR as its `ci.yml`.
2. **Each scaffold ticket** switches to `node.yml` or `flutter.yml` in the PR that commits the manifest and its lockfile (`package.json` + `pnpm-lock.yaml`, `pubspec.yaml` + `pubspec.lock`). An ecosystem is never declared before its manifest exists: Dependabot reports an error for it.
3. A repository that builds an image names its image file `Containerfile` (Podman's name, read by Dependabot's `docker` ecosystem like `Dockerfile`) and appends the entry of `container.yml` to its `updates:` list.

Keep the shared settings below when adapting a template; a different `directory` (for example a workspace package) is the only expected change.

The `github-actions` entry of `common.yml`, `node.yml` and `flutter.yml` lists `directories: ["/", "/.github/actions/*"]`: `/` covers `.github/workflows` and a root `action.yml` only, so the pins inside composite actions need the glob. The glob belongs only to `directories`, not to `directory`. A repository without composite actions keeps it unchanged: a glob that matches nothing adds no directory, and `/` is still scanned.

## Shared settings

- **Weekly**, Monday 06:00 Europe/Brussels.
- **Cooldown of 7 days**: a newly published version waits a week before Dependabot proposes it, which keeps most compromised releases out. The cooldown applies to version updates only.
- **Grouping**: minor and patch version updates of an ecosystem come in one PR per week; a major update gets its own PR.
- **Security updates are never delayed**: they are raised as soon as an alert exists, outside the schedule and the cooldown, and are not grouped (the groups apply to `version-updates` only). GitHub offers no security updates for the `docker` ecosystem: image vulnerabilities are a deferred control of ADR-014.
- **Commit messages and PR titles** start with `chore(deps):` (or `chore(deps-dev):` for development dependencies), which passes the Conventional Commits check of the `Quality Gate` (see [CI.md](CI.md)).
- **Label** `tech-debt`. The label must exist in the repository, otherwise Dependabot opens the PR without it.

## A fresh manual pin blocks npm updates during the cooldown

In a pnpm repository, Dependabot turns `cooldown: default-days: 7` into `--config.minimum-release-age=10080` on every pnpm command, including the final `pnpm install --lockfile-only`. That install re-checks the direct dependencies of `package.json`, not only the package being updated. So a manual bump that pins a direct dependency published less than 7 days ago fails every npm version update of the repository, until that version is 7 days old:

```text
ERR_PNPM_NO_MATURE_MATCHING_VERSION  Version 12.3.2 (released 5 days ago) of @nestjs/testing does not meet the minimumReleaseAge constraint
Handled error whilst updating zod: update_not_possible
```

The package named in the error is the fresh pin, not the one being updated, which is why every candidate of the run ends in `update_not_possible` (seen in SoutienScolaireApp/backend#63, after a manual security bump). The `minimum-release-age` of the repository `.npmrc` is not the cause: the value comes from the cooldown. Security updates run without this flag.

After a manual bump to a fresh release this failure is expected and needs no fix: note the date the release turns 7 days old, then let the next Monday run open the PRs, or start "Check for updates" from Insights > Dependency graph > Dependabot. If that run still fails, read its log for another blocker. A pnpm `minimumReleaseAgeExclude` entry for the bumped package is not adopted: nothing here shows that Dependabot honours it.

## Reviewing a Dependabot PR

A Dependabot PR goes through the same `Quality Gate` as any other and is merged the same way: squash, with Céline's approval. It is exempt from the `Closes #n` check only, since it has no issue. A red gate on a Dependabot PR is fixed in that PR or in a linked ticket, never bypassed. Since `develop` requires branches to be up to date before merge, a Dependabot PR left behind `develop` is rebased by Dependabot itself: comment `@dependabot rebase` (it also rebases on its own when the PR conflicts). Never use Update branch or push to it: once someone else pushes, Dependabot stops updating that PR.

Tool versions downloaded inside CI steps (gitleaks, osv-scanner, actionlint, oasdiff, the Flutter SDK, Node.js) are invisible to Dependabot and are bumped by hand in the CI templates (see [CI.md](CI.md)). In this repository, the `github-actions` entry also scans `workflow-templates/`, so the action SHAs of the templates are bumped in the same PR as `.github/workflows/`, the `pip` and `npm` entries cover both `templates/lint/` and `.github/lint/`, and a `pip` entry covers `templates/ansible/`.

## Ignored majors

The `node.yml` template ignores two semver-major updates in every `npm` ecosystem. A major of either package is closed with a comment, never merged on its own:

- **`@types/node`** follows the Node.js runtime we pin (Node 24 LTS). A newer major of the types describes APIs that do not exist at runtime. Change the rule when the LTS pin moves.
- **`typescript`** stays on 6.0.x in every repository, because typescript-eslint supports TypeScript < 6.1 only. Lift the rule when typescript-eslint supports TypeScript 7, then bump every repository in one coordinated change.

`update-types` filters version updates only: minor and patch updates of both packages, and every security update, still come.

## Generated API clients

`@usc/api-client` and `usc_api_client` are git-tag dependencies on the private `contracts` repository (ADR-013, SoutienScolaireApp/architecture#6). The templates **ignore** them: they are bumped by the contract change procedure (a PR per consumer after a new contracts tag), not by Dependabot. Dependabot still re-resolves `@usc/api-client` on every npm update, reading `contracts` through the organisation setting "Grant Dependabot access to private repositories" (ADR-013 Amendment 1, rule 8).

**Lockfile spelling (ADR-013 Amendment 3).** Inside Dependabot, pnpm records the `@usc/api-client` entry of `pnpm-lock.yaml` in the SSH spelling (`git+ssh://git@github.com/SoutienScolaireApp/contracts.git#<commit>&path:/clients/typescript`, `repo: git@github.com:SoutienScolaireApp/contracts.git`), although the `package.json` specifier is HTTPS and Dependabot fetched over HTTPS. The commit is the same; only the spelling flips. Both spellings are accepted by the shared [contracts lockfile guard](CI.md#the-contracts-lockfile-guard), and CI rewrites both to authenticated HTTPS with SSH disabled. In a consumer that has adopted the guard, such a PR needs **no manual relock**: review the commit of the `contracts` entry, not its URL (a change of spelling with the same commit changes nothing installed).

**HTTPS relock, optional.** It is still valid, and still required in a consumer that has not adopted the guard yet: relock with SSH disabled and no `insteadOf` rule rewriting HTTPS to SSH, with your own HTTPS credential for `contracts`, for example `GIT_SSH_COMMAND=false pnpm install --lockfile-only`, then commit `pnpm-lock.yaml`. Nobody edits the lockfile by hand.

## pnpm version

GitHub documents Dependabot support for pnpm v7 to v10. Each pnpm repository pins a supported major in the `packageManager` field of `package.json` (`pnpm@10.34.6` on 2026-10-15) and moves to a newer major only once GitHub lists it.
