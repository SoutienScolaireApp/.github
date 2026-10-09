# `.github`

Organization-wide GitHub configuration: the public landing page, the shared issue and pull request templates, and the reusable CI workflows. **The only public repository of the organization.**

> Workspace process (branches, issues, pull requests) is in `../CLAUDE.md`.

## Why this repository is public, and what follows

GitHub renders an organization's landing page only when `profile/README.md` lives in a repository named exactly `.github` **that is public**. Everything else in the organization is private.

**Consequence, and it is the rule that matters most here: nothing confidential may ever be committed to this repository.** Not the founding specification (it carries the roadmap, the security posture, the threat model and GDPR gaps), not infrastructure details, not internal planning, not customer names. Assume every file is world-readable, because it is. If a members-only landing page is needed later, GitHub supports a separate private repository named `.github-private` using the same `profile/README.md` path.

## Architecture

```text
profile/README.md                      public organization landing page
.github/ISSUE_TEMPLATE/                shared issue forms
.github/PULL_REQUEST_TEMPLATE.md       shared pull request template
.github/workflows/                     reusable workflows called by other repositories
CONTRIBUTING.md  SECURITY.md           shared community health files
```

Files here are **inherited** by every repository that does not define its own. That inheritance is the whole point: one definition, eight repositories.

## Reusable workflows: where this repository earns its keep

With eight repositories and one main developer, duplicating the same CI eight times is where technical debt returns first. Shared pipelines live here and are called with one line:

```yaml
jobs:
  ci:
    uses: SoutienScolaireApp/.github/.github/workflows/node-ci.yml@develop
```

Fix a pipeline once, all repositories benefit. Workflows are **parameterised, not forked**: a repository that needs a variation passes an input, it does not copy the file. Pin third-party actions by commit SHA, never by a floating tag: a supply-chain compromise of a popular action would otherwise reach every repository at once.

## Conformance: the non-negotiables

1. **No confidential content, ever.**
2. **No secret in a workflow**, and no workflow that echoes a secret into logs. `pull_request_target` is forbidden unless a specific need is documented and reviewed: it runs with write permissions against untrusted code.
3. **Least privilege**: every workflow declares explicit `permissions:` rather than inheriting the default write-all token.
4. **The public landing page is communication.** Its wording requires Céline's approval; it is not written by an agent on its own initiative.

## Templates: the expected shape

Issue: **Context · Problem · Expected behavior · Acceptance criteria · Technical notes · Dependencies · Definition of Done.**

Labels: type (`feature`, `bug`, `tech-debt`, `security`, `docs`, `test`), state (`blocked`, `needs-info`, `breaking-change-approved`), plus `epic` and `accessibility`. **Domain and priority are deliberately not labels**: the organization project board already carries the repository as a field, and priority lives in the board's `Priority` field; a label would create a second source that silently diverges. **GitHub Actions is case-sensitive on labels**: create each one once and never duplicate it with different casing.

Tracking (ADR-010 in `docs`): only a board card (a lot card in `docs` or a task card in `journal`) carries the `contribution` label, which is what adds it to the board; technical work in the product repositories is opened as native sub-issues of a lot card, with no points and no `contribution` label.

Pull request template: what changes, what to review first, contract impact (none / additive / breaking), and the Definition of Done checklist.

## Tests

Workflows are validated by `actionlint` before merge, and a shared workflow is exercised on a real repository before being adopted everywhere. Changing a reusable workflow can break eight pipelines at once: change it on a branch, verify it against one consumer, then roll it out.

## Documentation

Every reusable workflow documents its inputs, its expectations of the calling repository, and how to migrate to it. A template change is announced in the pull request description because it affects everyone's daily workflow.

## Never do

- Never commit anything you would not publish on the open internet.
- Never grant a workflow more permissions than the job requires.
- Never publish content about the organization or the product without Céline's approval.

## Task tracking (ADR-010)

Every task in this repository is a **sub-issue of a card** on the organization board (`https://github.com/orgs/SoutienScolaireApp/projects/1`): a lot card (`A6.lot.L0` to `L9`, issues in `docs`), a lot planning card, or a task card in `journal`. Points live on the card, never on the task. Full rule: `adr/ADR-010-contribution-tracking.md` in the `docs` repository.

Before starting a task:

1. **Identify the parent card**, usually the lot in progress. If no card fits (unplanned fix, new request), stop and ask Céline: the work must first be costed as a card of its own at the weekly meeting.
2. **Check that the card is costed**: `Points` and `Chiffré le` are set. Otherwise, do not start: work executed before costing falls back to the day-based count.

```bash
gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){title projectItems(first:5){nodes{status:fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}} points:fieldValueByName(name:"Points"){... on ProjectV2ItemFieldNumberValue{number}} costed:fieldValueByName(name:"Chiffré le"){... on ProjectV2ItemFieldDateValue{date}}}}}}}' -f o=SoutienScolaireApp -f r=docs -F n=<card>
```

3. **Open the task as an issue in this repository**, without the `contribution` label and without adding it to the board, then attach it to the card (the `gh` CLI cannot do it, use GraphQL):

```bash
PARENT=$(gh issue view <card> -R SoutienScolaireApp/docs --json id -q .id)
gh api graphql -f query='mutation($p:ID!,$u:String!){addSubIssue(input:{issueId:$p,subIssueUrl:$u}){subIssue{number}}}' \
  -f p="$PARENT" -f u="https://github.com/SoutienScolaireApp/<repo>/issues/<n>"
```

Then the usual cycle applies to the sub-issue: dedicated worktree, pull request `Closes #<n>`, green CI, squash merge after Céline's approval.

An agent **never** edits `Points`, `Chiffré le`, `Accepté le`, `Contesté` or `Bénéficiaire` (those are set in session between the Parties), never adds a sub-issue to the board, never puts the `contribution` label on a sub-issue, and never creates a card carrying points on its own initiative. Issues, pull requests and merges are made from the contributor's own GitHub account: a squash commit takes the pull request author as its author.
