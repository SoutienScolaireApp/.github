# Rulesets

Organisation rulesets of SoutienScolaireApp, kept as code. The JSON file is the source of truth: the live ruleset must always match it.

**Scope.** `protect-develop.json` lists its repositories by name: `contracts`, `backend`, `mobile-app`, `parent-web`, `admin-web`, `infrastructure`, `architecture` and `.github`, the repositories that report `Quality Gate` and `Gate integrity`. History: in the SchoolEngine organisation it targeted `~ALL`; applied as is in SoutienScolaireApp (SoutienScolaireApp/architecture#25), it would have blocked every merge in `docs`, `journal` and `legal`, which do not report that check. A new code repository is added to the list in a PR, once it reports both checks.

| File | Ruleset | What it enforces |
|---|---|---|
| `protect-develop.json` | `protect-develop` (id 25757180; 25146431 in the former SchoolEngine organisation) | Default branch of the listed repositories: no deletion, no force-push, linear history, PR required (squash only, review threads resolved, stale approvals dismissed), required checks `Quality Gate` and `Gate integrity` (GitHub Actions, integration id 15368, branch required to be up to date with `develop`). One bypass actor, the break-glass: organisation owners, through a pull request only (see [Break-glass](#break-glass)). |

The file holds only the fields accepted by the API (`name`, `target`, `enforcement`, `bypass_actors`, `conditions`, `rules`): no `id`, timestamps, `_links`, `node_id` or `source`. It can be re-imported as is, with `PUT` on the existing ruleset or `POST` on a new organisation.

## Changing a ruleset

1. **Change the JSON in a pull request first**, linked to an issue, and get it reviewed. Never change the ruleset in the GitHub UI.
2. After the merge, compare the file with the live ruleset (dry-run, changes nothing):

   ```bash
   scripts/apply-ruleset.sh --allow-bypass rulesets/protect-develop.json
   ```

3. Apply it (organisation owner only):

   ```bash
   scripts/apply-ruleset.sh --apply --allow-bypass rulesets/protect-develop.json
   ```

   The script is idempotent (a second run reports nothing to do). It reads the file once and validates, diffs and sends only that snapshot, reduced to the six API keys. A `diff` error stops it before any write. It refuses a file without `name`, `target`, `enforcement`, `conditions` and `rules`, a file without a `bypass_actors` array of objects (`[]` for none: without a key, a `PUT` keeps the live value and the file stops describing the ruleset), and a file that declares bypass actors unless `--allow-bypass` is given (`protect-develop` declares only the break-glass, so its commands below pass `--allow-bypass`). Each bypass actor needs a valid `actor_id` for its type, as the REST API defines it, or the file is refused even with `--allow-bypass`: `Integration`, `RepositoryRole`, `Team` and `User` take a positive integer (a placeholder such as `0`, `"0"` or a negative value is refused); `OrganizationAdmin` ignores it (GitHub returned `null` on 2026-11-05, so the file declares `null` to match the live ruleset); `DeployKey` takes `null`; any other type is refused. A ruleset named `protect-develop` is stricter: even with `--allow-bypass`, it must declare exactly one bypass actor, `OrganizationAdmin` with `bypass_mode` `pull_request` and `actor_id` `null` or `1`. It must also keep `enforcement` `active`, `target` `branch`, the rule types `deletion`, `non_fast_forward`, `required_linear_history`, `pull_request` and `required_status_checks`, the required check `Quality Gate` (integration id 15368; not `Gate integrity`, which the [break-glass](#enabling-the-gate-integrity-check) of that check removes with this script), the `pull_request` parameters the file sets to harden a merge (`dismiss_stale_reviews_on_push`, `required_review_thread_resolution` and `require_extra_approval_for_unattributed_changes` true, `allowed_merge_methods` `squash` only), a `ref_name` that includes `~DEFAULT_BRANCH` or `refs/heads/develop` with an empty `exclude` and, for an organisation ruleset, a `repository_name` with a non-empty `include` and an empty `exclude`. The parameters at `0` or `false`, such as `required_approving_review_count`, are not checked: raising them is not a weakening. These checks catch an accident in the file; they are no control against an owner. A rule type added to `protect-develop.json` joins the list in the script (`tests/apply-ruleset/run.sh` fails otherwise). The `--repo` value must be `SoutienScolaireApp/<repo>` and refuses `.` and `..` segments. The equivalent raw call, without any of these checks, is `gh api -X PUT orgs/SoutienScolaireApp/rulesets/<id> --input rulesets/protect-develop.json`.

4. Check the result on one repository: `gh api repos/SoutienScolaireApp/backend/rules/branches/develop`.

If the live ruleset was changed outside this process, export it back (`gh api orgs/SoutienScolaireApp/rulesets/<id> | jq '{name, target, enforcement, bypass_actors, conditions, rules}'`) and open a PR so the file matches again.

## Break-glass

`protect-develop` has one bypass actor: `OrganizationAdmin` (the organisation owners; the API ignores its `actor_id` and returned `null` on 2026-11-05) with `bypass_mode` `pull_request`. An owner can merge a pull request that does not meet the rules (for example a red `Quality Gate` caused by a broken GitHub-side dependency), but never push to `develop` directly: the bypass goes through a pull request, so it is visible on the PR and logged in the organisation audit log. Use it only when the normal path is blocked, say why in the PR, and open an issue for the cause. Before the break-glass existed, the ruleset had no bypass actor at all (owners included).

## Repository rulesets

A repository keeps its own rulesets as code in its `rulesets/` folder (for example `protect-release-tags` in `SoutienScolaireApp/contracts`). The same script handles them with `--repo`, run from a checkout of this repository (repository administrator only for `--apply`):

```bash
scripts/apply-ruleset.sh --repo SoutienScolaireApp/contracts ../contracts/rulesets/protect-release-tags.json
scripts/apply-ruleset.sh --apply --repo SoutienScolaireApp/contracts ../contracts/rulesets/protect-release-tags.json
```

It then reads `repos/<owner>/<repo>/rulesets?includes_parents=false` (never an inherited organisation ruleset), and updates `repos/<owner>/<repo>/rulesets/<id>` or creates the ruleset on the repository. The same rules apply: dry-run by default, `bypass_actors` required, `--allow-bypass` for a file that declares bypass actors.

The script is tested without network by `tests/apply-ruleset/run.sh` (a `gh` stub).

## Why `strict_required_status_checks_policy` is true

A strict policy only lets a PR merge when its branch contains the tip of `develop` and `Quality Gate` passed on that state. Without it, `Quality Gate` proves the branch is green, not that the result of the merge is: a PR opened before a new CI rule can be merged without ever meeting it. That happened in `parent-web`, where a `CLAUDE.md` PR based on an old `develop` never ran the newer `Format check` and turned `develop` red for every PR (SoutienScolaireApp/parent-web#12). Decided by Céline on 2026-10-16 (SchoolEngine/.github#19).

The cost: after every merge, the other open PRs of the repository are out of date and must be updated before they can merge, which runs their CI again.

- Use the **Update branch** button of the PR, or `gh pr update-branch <n>` (`--rebase` to rebase instead of merging `develop` in; both are fine, the PR is squashed anyway).
- **Dependabot PRs are rebased by Dependabot itself**: comment `@dependabot rebase` on the PR (it also rebases on its own when the PR conflicts). Do not use Update branch on them: once someone else pushes to a Dependabot branch, Dependabot stops updating that PR.

## Enabling the Gate integrity check

`Gate integrity` (SchoolEngine/.github#22, [CI.md](../CI.md#gate-integrity)) is in `protect-develop.json` since the activation PR (SoutienScolaireApp/.github#43), and an organisation owner applies the file after its merge: until then the file is ahead of the live ruleset. Steps 1 and 2 were done for the eight repositories on 2026-11-06 (SoutienScolaireApp/.github#36). A required check that a repository never reports blocks every merge there, and a `pull_request_target` workflow only runs once it is on the default branch, so the order is fixed, and it stays the order for a new repository:

1. **Rollout.** In every repository, a PR copies `.github/workflows/gate-integrity.yml` and `.github/scripts/gate-integrity.sh` from this repository unchanged, and adds the `gate-drift` job to `ci.yml` and to the gate's `needs:`. That PR gets no `Gate integrity` run (the workflow is not on `develop` yet).
2. **Canary.** In every repository, a trivial PR (a typo fix, for example) must show `Gate integrity` green, and a deliberately weakened draft PR (a job removed from the gate's `needs:`) must show it red; close the draft. From the root of a checkout, check that every repository of the ruleset has both files on `develop` (each line must say `ok`; `docs`, `journal` and `legal` are outside the ruleset and are not listed):

   ```bash
   for r in $(jq -r '.conditions.repository_name.include[]' rulesets/protect-develop.json); do
     for f in .github/workflows/gate-integrity.yml .github/scripts/gate-integrity.sh; do
       gh api "repos/SoutienScolaireApp/$r/contents/$f?ref=develop" --silent 2>/dev/null \
         && echo "ok      $r $f" || echo "MISSING $r $f"
     done
   done
   ```

3. **Activation PR** in this repository: adds `{"context": "Gate integrity", "integration_id": 15368}` to the required checks of `protect-develop.json` (done, SoutienScolaireApp/.github#43). After its merge, an organisation owner applies it; the dry-run must show only the added check:

   ```bash
   scripts/apply-ruleset.sh --allow-bypass rulesets/protect-develop.json
   scripts/apply-ruleset.sh --apply --allow-bypass rulesets/protect-develop.json
   ```

4. **Check** on one repository: `gh api repos/SoutienScolaireApp/backend/rules/branches/develop --jq '.[] | select(.type == "required_status_checks") | .parameters.required_status_checks'` lists both checks.
5. **Open PRs** whose head commit has no `Gate integrity` run cannot merge: use **Update branch** (or push a commit, or edit the PR body) to trigger it. On a Dependabot PR, edit the body or comment `@dependabot rebase`, never Update branch.

**New repositories** get `gate-integrity.yml` and the checker in their scaffold, before they join the list of `protect-develop.json`: a repository on the list without them cannot merge anything, not even the PR that would add them, since the check only runs from `develop`. The fix would then be the break-glass of this ruleset.

**Break-glass** (the check is broken everywhere, for example a GitHub change to `pull_request_target`): an organisation owner removes the check from the live ruleset through the API, then records it in a PR so the file matches again:

```bash
jq '(.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks)
    |= map(select(.context != "Gate integrity"))' rulesets/protect-develop.json > /tmp/protect-develop.json
scripts/apply-ruleset.sh --apply --allow-bypass /tmp/protect-develop.json
```

The PR that fixes the check then restores the entry, and it is applied again after its merge.
