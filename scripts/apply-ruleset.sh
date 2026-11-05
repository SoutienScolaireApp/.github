#!/usr/bin/env bash
# Apply a SoutienScolaireApp ruleset from its JSON file: an organisation ruleset
# (rulesets/ of this repository) or, with --repo, a repository ruleset (for
# example rulesets/ of SoutienScolaireApp/contracts).
#
# Usage: scripts/apply-ruleset.sh [--apply] [--allow-bypass] [--repo SoutienScolaireApp/<repo>] <NAME.json>
#
# Dry-run by default: prints the diff between the live ruleset and the file and
# changes nothing. With --apply, replaces the live ruleset (PUT) when it differs,
# or creates it (POST) when no ruleset of that name exists. Running it twice is
# a no-op.
# The file is read once: only the six API keys of that snapshot are validated,
# diffed and sent. It must declare all six, `bypass_actors` explicitly (`[]` for
# none): without a key, a PUT would keep the live value and the file would no
# longer describe the ruleset. A file that declares bypass actors is refused unless
# --allow-bypass is given; the actors are printed in every case. A bypass
# actor without a valid actor_id for its type is always refused, and a ruleset
# named protect-develop accepts only the break-glass, even with --allow-bypass,
# and must stay active on the default branch with its rule types.
# Requires gh (authenticated as an organisation owner or repository admin) and jq.
set -euo pipefail

ORG="SoutienScolaireApp"
KEYS='{name, target, enforcement, bypass_actors, conditions, rules}'
USAGE="usage: scripts/apply-ruleset.sh [--apply] [--allow-bypass] [--repo $ORG/<repo>] <NAME.json>"

apply=false
allow_bypass=false
repo=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) apply=true; shift ;;
    --allow-bypass) allow_bypass=true; shift ;;
    --repo) repo="${2:?$USAGE}"; shift 2 ;;
    -*) echo "$USAGE" >&2; exit 2 ;;
    *) break ;;
  esac
done
file="${1:?$USAGE}"

if [[ -n "$repo" ]]; then
  if [[ ! "$repo" =~ ^$ORG/[A-Za-z0-9_.-]+$ || "/$repo/" == */./* || "/$repo/" == */../* ]]; then
    echo "Refused: --repo must be $ORG/<repo>, got '$repo'." >&2
    exit 2
  fi
  scope="repos/$repo/rulesets"
  # Only the repository's own rulesets: never an inherited organisation one.
  list="$scope?includes_parents=false"
  where="repository $repo"
else
  scope="orgs/$ORG/rulesets"
  list="$scope"
  where="organisation $ORG"
fi

original="$(mktemp)"
payload="$(mktemp)"
live="$(mktemp)"
trap 'rm -f "$original" "$payload" "$live"' EXIT
cp "$file" "$original"

# $KEYS turns an absent key into null: check the keys on the original.
if ! jq -e 'type == "object" and has("name") and has("target") and has("enforcement") and has("conditions") and has("rules")' "$original" >/dev/null; then
  echo "Refused: $file is not a ruleset (name, target, enforcement, conditions and rules are required)." >&2
  exit 1
fi
if ! jq -e 'has("bypass_actors")' "$original" >/dev/null; then
  echo "Refused: $file has no bypass_actors key. Declare it, [] for none: without it the live bypass list would be kept." >&2
  exit 1
fi

# From here on, everything reads and sends this snapshot, never $file again.
jq -S "$KEYS" "$original" > "$payload"

if ! jq -e '(.bypass_actors | type) == "array"' "$payload" >/dev/null; then
  echo "Refused: $file has a bypass_actors that is not an array ($(jq -r '.bypass_actors | type' "$payload")): use [] for none." >&2
  exit 1
fi
if ! jq -e 'all(.bypass_actors[]; type == "object")' "$payload" >/dev/null; then
  echo "Refused: every element of bypass_actors in $file must be an object ({actor_id, actor_type, bypass_mode})." >&2
  exit 1
fi

# Bypass actors as the REST API defines them: Integration, RepositoryRole,
# Team and User need a real id (a positive integer: a placeholder such as 0,
# "0", "" or a negative value is refused, even with --allow-bypass, since the
# API may resolve it to an actor nobody chose); OrganizationAdmin ignores the
# id (GitHub returned null on 2026-11-05); DeployKey takes null. Any other
# type is refused.
invalid="$(jq -r '[.bypass_actors[]? | select(
    if (.actor_type | IN("Integration", "RepositoryRole", "Team", "User")) then
      (.actor_id | (type == "number" and . > 0 and . == floor)) | not
    elif .actor_type == "OrganizationAdmin" then false
    elif .actor_type == "DeployKey" then .actor_id != null
    else true end)
  | "\(.actor_type // "?") \(.actor_id | tojson)"] | join(", ")' "$payload")"
if [[ -n "$invalid" ]]; then
  echo "Refused: $file has bypass actor(s) without a valid actor_id for their type: $invalid." >&2
  exit 1
fi

bypass_count="$(jq '.bypass_actors | length' "$payload")"
if [[ "$bypass_count" != "0" ]]; then
  echo "$file declares $bypass_count bypass actor(s):"
  jq -r '.bypass_actors[] | "  \(.actor_type) \(.actor_id // "-") (\(.bypass_mode))"' "$payload"
  if ! $allow_bypass; then
    echo "Refused: bypass actors need --allow-bypass (protect-develop declares only the OrganizationAdmin break-glass)." >&2
    exit 1
  fi
fi

if jq -e '.name == "protect-develop"' "$payload" >/dev/null; then
  # Exactly one bypass actor, the break-glass (rulesets/README.md).
  if ! jq -e '.bypass_actors | length == 1 and (.[0] | IN({actor_id: (null, 1), actor_type: "OrganizationAdmin", bypass_mode: "pull_request"}))' "$payload" >/dev/null; then
    echo "Refused: $file must declare exactly one bypass actor for protect-develop: OrganizationAdmin (actor_id null or 1), bypass_mode pull_request." >&2
    exit 1
  fi
  # A safety net against an accident, not a control against an owner. The rule
  # types are the ones of rulesets/protect-develop.json: written here, since a
  # guard read from the file would not catch that file losing one.
  if ! jq -e --arg repo "$repo" '
      .enforcement == "active" and .target == "branch"
      and ((["deletion", "non_fast_forward", "required_linear_history", "pull_request", "required_status_checks"] - [.rules[]?.type?]) == [])
      and any(.rules[]? | select(.type? == "required_status_checks") | .parameters.required_status_checks[]?;
        .context == "Quality Gate" and .integration_id == 15368)
      and any(.rules[]? | select(.type? == "pull_request") | .parameters;
        .dismiss_stale_reviews_on_push == true
        and .required_review_thread_resolution == true
        and .require_extra_approval_for_unattributed_changes == true
        and .allowed_merge_methods == ["squash"])
      and any(.conditions.ref_name.include[]?; IN("~DEFAULT_BRANCH", "refs/heads/develop"))
      and ((.conditions.ref_name.exclude // []) == [])
      and ($repo != "" or (.conditions.repository_name
        | (.include | type == "array" and length > 0) and ((.exclude // []) == [])))' "$payload" >/dev/null; then
    echo "Refused: $file would weaken protect-develop: it needs enforcement active, target branch, the rule types deletion, non_fast_forward, required_linear_history, pull_request and required_status_checks, the Quality Gate check (integration 15368), the pull_request parameters of rulesets/README.md, a ref_name including ~DEFAULT_BRANCH or refs/heads/develop with no exclude and, in an organisation, a repository_name include with no exclude." >&2
    exit 1
  fi
fi

name="$(jq -r '.name' "$payload")"
id="$(gh api "$list" --paginate | jq -r --arg name "$name" '.[] | select(.name == $name) | .id')"

if [[ -z "$id" ]]; then
  echo "No live ruleset named '$name' in $where: it would be created."
  if $apply; then
    gh api -X POST "$scope" --input "$payload" --jq '"Created ruleset \(.id)"'
  fi
  exit 0
fi

gh api "$scope/$id" | jq -S "$KEYS" > "$live"
rc=0
diff -u --label "live ($id)" --label "$file" "$live" "$payload" || rc=$?
if [[ "$rc" -gt 1 ]]; then
  echo "Refused: diff failed (exit $rc), so the file was not compared with the live ruleset." >&2
  exit 1
fi
if [[ "$rc" -eq 0 ]]; then
  echo "Ruleset '$name' ($id) of $where already matches $file: nothing to do."
  exit 0
fi

if $apply; then
  gh api -X PUT "$scope/$id" --input "$payload" --jq '"Updated ruleset \(.id) at \(.updated_at)"'
else
  echo "Dry-run: nothing changed. Re-run with --apply to update ruleset $id of $where."
fi
