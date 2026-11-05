#!/usr/bin/env bash
# Table test of scripts/apply-ruleset.sh (SchoolEngine/.github#23), without
# network: `gh` is a stub that serves two organisation rulesets (id 1,
# `protect-develop`, and id 3, `other-ruleset`) and one repository ruleset of
# SoutienScolaireApp/contracts (id 2, `protect-release-tags`), and records every
# write it receives.
#
# Usage: tests/apply-ruleset/run.sh   (needs jq)
set -euo pipefail

root=$(git rev-parse --show-toplevel)
script="$root/scripts/apply-ruleset.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

jq '. + {id: 1, source_type: "Organization"}' "$root/rulesets/protect-develop.json" >"$work/live-org.json"
jq '. + {id: 3, name: "other-ruleset", bypass_actors: []}' "$work/live-org.json" >"$work/live-other.json"
cat >"$work/live-repo.json" <<'JSON'
{"id": 2, "name": "protect-release-tags", "target": "tag", "enforcement": "active",
 "source_type": "Repository", "bypass_actors": [],
 "conditions": {"ref_name": {"exclude": [], "include": ["refs/tags/v*"]}},
 "rules": [{"type": "deletion"}, {"type": "non_fast_forward"}, {"type": "update"}]}
JSON

cat >"$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo "gh $*" >>"$GH_STUB_LOG"
# Stands for a file changed after its validation: every call comes after it.
[[ -z "${GH_STUB_CLOBBER:-}" ]] || echo '{"name": "other-ruleset", "enforcement": "disabled"}' >"$GH_STUB_CLOBBER"
[[ "$1" == "api" ]] || exit 3
shift
case "$*" in
  "orgs/SoutienScolaireApp/rulesets --paginate") jq -cs 'map({id, name})' "$GH_STUB_DIR/live-org.json" "$GH_STUB_DIR/live-other.json" ;;
  "orgs/SoutienScolaireApp/rulesets/1") cat "$GH_STUB_DIR/live-org.json" ;;
  "orgs/SoutienScolaireApp/rulesets/3") cat "$GH_STUB_DIR/live-other.json" ;;
  "repos/SoutienScolaireApp/contracts/rulesets?includes_parents=false --paginate") jq -c '[{id, name}]' "$GH_STUB_DIR/live-repo.json" ;;
  "repos/SoutienScolaireApp/contracts/rulesets/2") cat "$GH_STUB_DIR/live-repo.json" ;;
  -X\ PUT\ *|-X\ POST\ *)
    while [[ "$1" != "--input" ]]; do shift; done
    cp "$2" "$GH_STUB_DIR/sent.json"
    echo "write recorded" ;;
  *) echo "stub: unexpected call: gh api $*" >&2; exit 4 ;;
esac
STUB
chmod +x "$work/bin/gh"
mkdir -p "$work/broken-diff" "$work/tmp"
printf '#!/usr/bin/env bash\nexit 2\n' >"$work/broken-diff/diff"
chmod +x "$work/broken-diff/diff"
export PATH="$work/bin:$PATH" GH_STUB_DIR="$work" GH_STUB_LOG="$work/gh.log"

failures=0
# expect <exit> <label> <expected write or "-" for none> <"--" or a text the output must hold> <args...>
expect() {
  local want=$1 label=$2 write=$3 message=$4 rc=0
  shift 4
  : >"$GH_STUB_LOG"
  "$script" "$@" >"$work/out.txt" 2>&1 || rc=$?
  local got
  got=$(grep -E '^gh api -X (PUT|POST) ' "$GH_STUB_LOG" | awk '{print $4, $5}' || true)
  [[ -n "$got" ]] || got="-"
  if [[ "$rc" -eq "$want" && "$got" == "$write" ]] && { [[ "$message" == "--" ]] || grep -qF -- "$message" "$work/out.txt"; }; then
    echo "ok   $label"
  else
    echo "FAIL $label: exit $rc (expected $want), write '$got' (expected '$write'), message '$message'"
    sed 's/^/     /' "$work/out.txt"
    failures=$((failures + 1))
  fi
}

# Derived rulesets start without bypass actor, so each case tests one thing,
# under another name: protect-develop accepts only the break-glass.
ruleset() { jq ".name = \"other-ruleset\" | .bypass_actors = [] | $1" "$root/rulesets/protect-develop.json" >"$work/$2"; echo "$work/$2"; }
develop_ruleset() { jq "$1" "$root/rulesets/protect-develop.json" >"$work/$2"; echo "$work/$2"; }
repo_ruleset() { jq "$1" "$work/live-repo.json" | jq 'del(.id, .source_type)' >"$work/$2"; echo "$work/$2"; }
# check_sent <label> <jq filter on the last body sent>
check_sent() {
  if jq -e "$2" "$work/sent.json" >/dev/null; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    failures=$((failures + 1))
  fi
}

echo "== The committed rulesets"
# Without actor_id: the API ignores it for OrganizationAdmin, null or 1 are both fine.
break_glass='[{"actor_type":"OrganizationAdmin","bypass_mode":"pull_request"}]'
if [[ "$(jq -c '.bypass_actors | map(del(.actor_id))' "$root/rulesets/protect-develop.json")" == "$break_glass" ]]; then
  echo "ok   protect-develop.json has only the break-glass bypass (organisation owners, through a PR)"
else
  echo "FAIL protect-develop.json bypass actors are not exactly the break-glass one"
  failures=$((failures + 1))
fi
if jq -e '.conditions.repository_name.include | index("~ALL") | not' "$root/rulesets/protect-develop.json" >/dev/null; then
  echo "ok   protect-develop.json lists its repositories (no ~ALL)"
else
  echo "FAIL protect-develop.json targets ~ALL"
  failures=$((failures + 1))
fi

echo "== Organisation rulesets"
expect 1 "committed file without --allow-bypass refused" - -- --apply "$root/rulesets/protect-develop.json"
expect 0 "file matches live: nothing to do" - -- --allow-bypass "$root/rulesets/protect-develop.json"
expect 0 "file matches live, --apply: no write" - -- --apply --allow-bypass "$root/rulesets/protect-develop.json"
changed=$(ruleset '.enforcement = "evaluate"' changed.json)
expect 0 "file differs: dry-run writes nothing" - -- "$changed"
expect 0 "file differs, --apply: PUT on the organisation ruleset" "PUT orgs/SoutienScolaireApp/rulesets/3" -- --apply "$changed"
created=$(ruleset '.name = "new-ruleset"' created.json)
expect 0 "unknown name: dry-run writes nothing" - -- "$created"
expect 0 "unknown name, --apply: POST" "POST orgs/SoutienScolaireApp/rulesets" -- --apply "$created"

echo "== What is sent"
only_keys='keys == ["bypass_actors", "conditions", "enforcement", "name", "rules", "target"]'
swapped=$(ruleset '.enforcement = "evaluate" | .unvalidated = true' swapped.json)
GH_STUB_CLOBBER="$swapped" expect 0 "PUT of a file changed after validation" "PUT orgs/SoutienScolaireApp/rulesets/3" -- --apply "$swapped"
check_sent "PUT sends the validated snapshot, without the extra key" "$only_keys and .enforcement == \"evaluate\""
swapped=$(ruleset '.name = "new-ruleset" | .unvalidated = true' swapped.json)
GH_STUB_CLOBBER="$swapped" expect 0 "POST of a file changed after validation" "POST orgs/SoutienScolaireApp/rulesets" -- --apply "$swapped"
check_sent "POST sends the validated snapshot, without the extra key" "$only_keys and .name == \"new-ruleset\""

echo "== Temporary files"
TMPDIR="$work/tmp" expect 0 "a write leaves no temporary file" "PUT orgs/SoutienScolaireApp/rulesets/3" -- --apply "$changed"
TMPDIR="$work/tmp" expect 1 "a refusal leaves no temporary file" - "is not a ruleset" "$(ruleset '{name}' tmp-refused.json)"
if [[ -z "$(ls -A "$work/tmp")" ]]; then
  echo "ok   temporary files are removed"
else
  echo "FAIL temporary files left: $(ls -A "$work/tmp")"
  failures=$((failures + 1))
fi

echo "== Diff errors"
broken_path="$work/broken-diff:$PATH"
PATH="$broken_path" expect 1 "diff error, --apply: fails closed, no write" - "diff failed (exit 2)" --apply "$changed"
PATH="$broken_path" expect 1 "diff error, dry-run: fails closed" - "diff failed (exit 2)" "$changed"

echo "== Refusals"
expect 1 "no bypass_actors key" - -- --apply "$(ruleset 'del(.bypass_actors) | .enforcement = "evaluate"' nobypasskey.json)"
for value in '[1]' '["Integration"]' '[null]' '[[]]'; do
  expect 1 "bypass_actors element not an object ($value)" - -- --apply --allow-bypass "$(ruleset ".bypass_actors = $value" notobject.json)"
done
for value in null '{}' '"none"'; do
  expect 1 "bypass_actors not an array ($value)" - -- --apply --allow-bypass "$(ruleset ".bypass_actors = $value" notarray.json)"
done
expect 1 "not a ruleset" - -- "$(ruleset '{name}' notruleset.json)"
for key in enforcement conditions; do
  expect 1 "no $key key (the snapshot would hold null)" - "is not a ruleset" --apply "$(ruleset "del(.$key)" nokey.json)"
done
bypass=$(ruleset '.bypass_actors = [{"actor_id": 15368, "actor_type": "Integration", "bypass_mode": "always"}]' bypass.json)
expect 1 "bypass actor without --allow-bypass" - -- --apply "$bypass"
expect 0 "bypass actor with --allow-bypass, --apply" "PUT orgs/SoutienScolaireApp/rulesets/3" -- --apply --allow-bypass "$bypass"
bypass_case() {
  local want=$1 label=$2 actor=$3 write=-
  [[ "$want" -ne 0 ]] || write="PUT orgs/SoutienScolaireApp/rulesets/3"
  expect "$want" "$label" "$write" -- --apply --allow-bypass "$(ruleset ".bypass_actors = [$actor]" actor.json)"
}
for id in 0 '"0"' '""' -5 1.5 null; do
  bypass_case 1 "Integration with actor_id $id refused, even with --allow-bypass" \
    "{\"actor_id\": $id, \"actor_type\": \"Integration\", \"bypass_mode\": \"always\"}"
done
bypass_case 1 "Team without actor_id refused" '{"actor_type": "Team", "bypass_mode": "pull_request"}'
bypass_case 1 "RepositoryRole with actor_id 0 refused" '{"actor_id": 0, "actor_type": "RepositoryRole", "bypass_mode": "always"}'
bypass_case 1 "User with a string actor_id refused" '{"actor_id": "42", "actor_type": "User", "bypass_mode": "always"}'
bypass_case 1 "DeployKey with an actor_id refused (null expected)" '{"actor_id": 3, "actor_type": "DeployKey", "bypass_mode": "always"}'
bypass_case 1 "unknown actor type refused" '{"actor_id": 3, "actor_type": "Robot", "bypass_mode": "always"}'
bypass_case 0 "DeployKey with actor_id null accepted" '{"actor_id": null, "actor_type": "DeployKey", "bypass_mode": "always"}'
bypass_case 0 "OrganizationAdmin with actor_id null (as the API returns it) accepted" '{"actor_id": null, "actor_type": "OrganizationAdmin", "bypass_mode": "always"}'
bypass_case 0 "OrganizationAdmin (actor_id 1, ignored by the API) accepted" '{"actor_id": 1, "actor_type": "OrganizationAdmin", "bypass_mode": "always"}'
bypass_case 0 "Team with a positive integer id accepted" '{"actor_id": 7, "actor_type": "Team", "bypass_mode": "pull_request"}'
break_glass_actor='{"actor_id": null, "actor_type": "OrganizationAdmin", "bypass_mode": "pull_request"}'
develop_case() {
  local want=$1 label=$2 actors=$3 write=- message="exactly one bypass actor for protect-develop"
  [[ "$want" -ne 0 ]] || { write="PUT orgs/SoutienScolaireApp/rulesets/1"; message=--; }
  expect "$want" "protect-develop: $label" "$write" "$message" --apply --allow-bypass \
    "$(develop_ruleset ".conditions.repository_name.include += [\"docs\"] | .bypass_actors = $actors" develop.json)"
}
develop_case 0 "break-glass with actor_id null accepted" "[$break_glass_actor]"
develop_case 0 "break-glass with actor_id 1 accepted" '[{"actor_id": 1, "actor_type": "OrganizationAdmin", "bypass_mode": "pull_request"}]'
develop_case 1 "break-glass plus a Team actor refused" "[$break_glass_actor, {\"actor_id\": 7, \"actor_type\": \"Team\", \"bypass_mode\": \"pull_request\"}]"
develop_case 1 "OrganizationAdmin with bypass_mode always refused" '[{"actor_id": null, "actor_type": "OrganizationAdmin", "bypass_mode": "always"}]'
develop_case 1 "OrganizationAdmin with actor_id 2 refused" '[{"actor_id": 2, "actor_type": "OrganizationAdmin", "bypass_mode": "pull_request"}]'
develop_case 1 "a single Team actor refused" '[{"actor_id": 7, "actor_type": "Team", "bypass_mode": "pull_request"}]'
develop_case 1 "no bypass actor refused" '[]'
weakened_case() {
  expect 1 "protect-develop: $1 refused" - "would weaken protect-develop" --apply --allow-bypass \
    "$(develop_ruleset "$2" weakened.json)"
}
weakened_case "enforcement disabled" '.enforcement = "disabled"'
weakened_case "enforcement evaluate" '.enforcement = "evaluate"'
weakened_case "target tag" '.target = "tag"'
weakened_case "empty rules" '.rules = []'
weakened_case "null conditions" '.conditions = null'
weakened_case "ref_name include matching nothing" '.conditions.ref_name.include = ["refs/heads/nothing"]'
weakened_case "empty ref_name include" '.conditions.ref_name.include = []'
weakened_case "default branch excluded" '.conditions.ref_name.exclude = ["~DEFAULT_BRANCH"]'
# Read from the committed file: a rule type added there must join the guard.
for type in $(jq -r '.rules[].type' "$root/rulesets/protect-develop.json"); do
  weakened_case "no $type rule" ".rules |= map(select(.type != \"$type\"))"
done
expect 0 "protect-develop: ref_name refs/heads/develop accepted" "PUT orgs/SoutienScolaireApp/rulesets/1" -- --apply --allow-bypass \
  "$(develop_ruleset '.conditions.ref_name.include = ["refs/heads/develop"]' develop-ref.json)"
repo_placeholder=$(repo_ruleset '.bypass_actors = [{"actor_id": 0, "actor_type": "Integration", "bypass_mode": "always"}]' repo-placeholder.json)
expect 1 "repository ruleset with a placeholder bypass actor" \
  - -- --apply --allow-bypass --repo SoutienScolaireApp/contracts "$repo_placeholder"
expect 2 "--repo with a .. segment" - -- --repo "SoutienScolaireApp/.." "$root/rulesets/protect-develop.json"
expect 2 "--repo with a . segment" - -- --repo "./contracts" "$root/rulesets/protect-develop.json"
expect 2 "--repo of another owner" - "must be SoutienScolaireApp/<repo>" --repo "Other/contracts" "$root/rulesets/protect-develop.json"
expect 2 "malformed --repo" - -- --repo "SoutienScolaireApp" "$root/rulesets/protect-develop.json"
expect 2 "unknown option" - -- --force "$root/rulesets/protect-develop.json"

echo "== Repository rulesets (--repo)"
same=$(repo_ruleset '.' repo-same.json)
expect 0 "repository file matches live" - -- --repo SoutienScolaireApp/contracts "$same"
creation=$(repo_ruleset '.rules += [{"type": "creation"}]' repo-creation.json)
expect 0 "repository file differs: dry-run" - -- --repo SoutienScolaireApp/contracts "$creation"
expect 0 "repository file differs, --apply: PUT on the repository ruleset" \
  "PUT repos/SoutienScolaireApp/contracts/rulesets/2" -- --apply --repo SoutienScolaireApp/contracts "$creation"
expect 0 "repository ruleset unknown, --apply: POST on the repository" \
  "POST repos/SoutienScolaireApp/contracts/rulesets" -- --apply --repo SoutienScolaireApp/contracts "$(repo_ruleset '.name = "other"' repo-new.json)"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures case(s) failed."
  exit 1
fi
echo "All cases passed."
