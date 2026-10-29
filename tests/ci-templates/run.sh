#!/usr/bin/env bash
# Checks of the CI templates (SoutienScolaireApp/.github#8), without network:
# 1. drift: the common jobs, the gate, the shared tool pins and every action
#    pin are the same in every workflow-templates/ci-*.yml and in this
#    repository's own workflows; the lint lockfiles, the root lint
#    configurations and the history scan of this repository are copies of
#    the templates;
# 2. the `PR title and linked issue` script of ci-common, run against a stub
#    of the GitHub API on a table of titles and bodies.
#
# Usage: tests/ci-templates/run.sh   (needs yq, jq)
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cd "$root"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0
ok() { echo "ok   $1"; }
ko() { echo "FAIL $1"; fail=1; }
# check <ok message> <failure message> <command...>
check() { local m="$1" k="$2"; shift 2; if "$@"; then ok "$m"; else ko "$k"; fi; }

ref=workflow-templates/ci-common.yml
others=(workflow-templates/ci-ansible.yml workflow-templates/ci-flutter.yml
  workflow-templates/ci-node.yml workflow-templates/ci-openapi.yml .github/workflows/ci.yml)

# --- 1. drift ---------------------------------------------------------------
for job in pr-conventions gitleaks actionlint lint-yaml-markdown osv-scanner; do
  want=$(yq -o=json ".jobs.\"$job\"" "$ref")
  for f in "${others[@]}"; do
    check "job $job of $f is the one of $ref" "job $job of $f differs from $ref" \
      test "$(yq -o=json ".jobs.\"$job\"" "$f")" == "$want"
  done
done

want=$(yq -o=json '.jobs."quality-gate" | del(.needs)' "$ref")
for f in "${others[@]}"; do
  check "quality-gate of $f" "quality-gate of $f differs from $ref (needs aside)" \
    test "$(yq -o=json '.jobs."quality-gate" | del(.needs)' "$f")" == "$want"
done

while IFS= read -r key; do
  want=$(yq ".env.\"$key\"" "$ref")
  for f in "${others[@]}"; do
    check "env $key of $f" "env $key of $f is not '$want' as in $ref" \
      test "$(yq ".env.\"$key\"" "$f")" == "$want"
  done
done < <(yq '.env | keys | .[]' "$ref")
for key in GITLEAKS_VERSION GITLEAKS_SHA256; do
  check "env $key of gitleaks-history.yml" "env $key of gitleaks-history.yml differs from $ref" \
    test "$(yq ".env.$key" workflow-templates/gitleaks-history.yml)" == "$(yq ".env.$key" "$ref")"
done

# One SHA per action across every template and workflow of this repository:
# Dependabot bumps .github/workflows and workflow-templates in the same PR.
pins=$(cat workflow-templates/*.yml .github/workflows/*.yml \
  | sed -nE 's/^[[:space:]-]*uses:[[:space:]]*([^.][^@[:space:]]*)@([0-9a-f]{40}).*/\1 \2/p' | sort -u)
while read -r action; do
  n=$(awk -v a="$action" '$1 == a' <<<"$pins" | wc -l | tr -d ' ')
  check "one pin for $action" "$action is pinned to $n different SHAs: $(awk -v a="$action" '$1 == a {print $2}' <<<"$pins" | tr '\n' ' ')" \
    test "$n" -eq 1
done < <(awk '{print $1}' <<<"$pins" | sort -u)

for f in requirements.txt package.json package-lock.json; do
  check ".github/lint/$f is the template" ".github/lint/$f differs from templates/lint/$f" \
    cmp -s "templates/lint/$f" ".github/lint/$f"
done
check "gitleaks-history.yml is the template" ".github/workflows/gitleaks-history.yml differs from the template" \
  cmp -s workflow-templates/gitleaks-history.yml .github/workflows/gitleaks-history.yml

# The root lint configurations of this repository are the templates as is.
for f in .yamllint.yml .markdownlint-cli2.yaml; do
  check "$f is the template" "$f differs from templates/lint/$f" cmp -s "templates/lint/$f" "$f"
done

# --- 2. PR title and linked issue -------------------------------------------
yq '.jobs."pr-conventions".steps[] | select(.name == "Check the Conventional Commits title and the closing keyword") | .run' \
  "$ref" >"$work/check.sh"
[[ -s "$work/check.sh" ]] || { ko "the pr-conventions step was not found in $ref"; exit 1; }
mkdir -p "$work/bin"
cat >"$work/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s' "$PR_JSON"
STUB
chmod +x "$work/bin/curl"

pr() {  # pr <want exit> <label> <author> <title> <body>
  local want="$1" label="$2" rc=0
  PR_JSON=$(jq -n --arg u "$3" --arg t "$4" --arg b "$5" '{user: {login: $u}, title: $t, body: $b}') \
    PATH="$work/bin:$PATH" GH_TOKEN=x GITHUB_API_URL=https://api.github.invalid \
    REPO=SoutienScolaireApp/.github PR_NUMBER=1 bash "$work/check.sh" >"$work/out" 2>&1 || rc=$?
  if [[ "$rc" -eq "$want" ]]; then ok "pr: $label"; else ko "pr: $label (exit $rc, want $want)"; cat "$work/out"; fi
}

t='ci(templates): fix drift (#8)'
pr 0 "valid title and Closes #n" me "$t" $'Closes #8\n\nSummary.'
pr 0 "Fixes: this repo#n" me "$t" 'Fixes: SoutienScolaireApp/.github#8'
pr 0 "Resolves this repo issue URL" me "$t" 'Resolves https://github.com/SoutienScolaireApp/.github/issues/8.'
pr 0 "repository name in another case" me "$t" 'closes soutienscolaireapp/.GITHUB#8'
pr 1 "Closes an issue of another repository" me "$t" 'Closes SoutienScolaireApp/backend#8'
pr 1 "Closes an issue URL of another repository" me "$t" 'Closes https://github.com/SoutienScolaireApp/backend/issues/8'
pr 1 "dot of the repository name is literal" me "$t" 'Closes SoutienScolaireApp/xgithub#8'
pr 1 "no closing keyword" me "$t" 'Refs #8'
pr 1 "no body" me "$t" ''
pr 1 "title without the issue suffix" me 'ci(templates): fix drift' 'Closes #8'
pr 1 "suffix not at the end" me 'ci(templates): fix (#8) drift' 'Closes #8'
pr 1 "not Conventional Commits" me 'Fix drift (#8)' 'Closes #8'
pr 0 "Dependabot: no suffix nor closing keyword" 'dependabot[bot]' 'chore(deps): bump actions/checkout' ''
pr 1 "Dependabot: title still checked" 'dependabot[bot]' 'Bump actions/checkout' ''

exit "$fail"
