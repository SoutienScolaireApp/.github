#!/usr/bin/env bash
# Checks of the CI templates (SoutienScolaireApp/.github#8), without network:
# 1. drift: the common jobs, the gate, the shared tool pins and every action
#    pin are the same in every workflow-templates/ci-*.yml and in this
#    repository's own workflows; the lint lockfiles, the root lint
#    configurations and the history scan of this repository are copies of
#    the templates;
# 2. the `PR title and linked issue` script of ci-common, run against a stub
#    of the GitHub API on a table of titles and bodies;
# 3. the contracts read of ci-flutter: same steps as ci-node, step order, token
#    scope, and the two guards run on fixtures;
# 4. the pre-check of the Ansible toolchain pins of ci-ansible.
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

# --- 3. contracts read of ci-flutter ----------------------------------------
node=workflow-templates/ci-node.yml
flutter=workflow-templates/ci-flutter.yml
step() { yq -o=json ".jobs.$1.steps[] | select(.name == \"$2\")" "$3"; }

for s in 'No installation token in tracked files' 'Mint a read-only token for SoutienScolaireApp/contracts'; do
  want=$(step node "$s" "$node")
  [[ -n "$want" ]] || ko "step '$s' not found in $node"
  check "step '$s' of ci-flutter is the one of ci-node" "step '$s' differs between ci-flutter and ci-node" \
    test "$(step flutter "$s" "$flutter")" == "$want"
done
# Only the client name differs: same variable, secret, tests and messages.
s='Require the SchoolEngine CI App credentials'
want=$(step node "$s" "$node")
[[ -n "$want" ]] || ko "step '$s' not found in $node"
check "step '$s' of ci-flutter is the one of ci-node" "step '$s' differs between ci-flutter and ci-node (client name aside)" \
  test "$(step flutter "$s" "$flutter" | sed 's/usc_api_client/@usc\/api-client/g')" == "$want"

check "job env of ci-flutter is the one of ci-node" "job env of ci-flutter differs from ci-node (GIT_SSH_COMMAND, GIT_TERMINAL_PROMPT)" \
  test "$(yq -o=json '.jobs.flutter.env' "$flutter")" == "$(yq -o=json '.jobs.node.env' "$node")"
check "job env of ci-flutter disables SSH" "job env of ci-flutter does not set GIT_SSH_COMMAND to false" \
  test "$(yq '.jobs.flutter.env.GIT_SSH_COMMAND' "$flutter")" == "false"

install='Install dependencies (enforced lockfile)'
check "install of ci-flutter has the HTTPS rewrite of ci-node" "install of ci-flutter: not exactly one rewrite, the HTTPS value of ci-node" \
  test "$(step flutter "$install" "$flutter" | jq -cS '.env')" == \
  "$(yq -o=json '.jobs.node.steps[] | select(.name == "Install (frozen lockfile, no scripts)") | .env' "$node" \
    | jq -cS '{GIT_CONFIG_COUNT: "1", GIT_CONFIG_KEY_0, GIT_CONFIG_VALUE_0}')"
check "install of ci-flutter enforces the lockfile" "install of ci-flutter does not run flutter pub get --enforce-lockfile" \
  test "$(step flutter "$install" "$flutter" | jq -r '.run')" == 'flutter pub get --enforce-lockfile'
check "only the install step reads the token" "contracts-token.outputs is used outside the install step of ci-flutter" \
  test "$(grep -c 'contracts-token\.outputs' "$flutter")" -eq 1

# Guards before the token, the token before the install.
order=$(yq '.jobs.flutter.steps[].name' "$flutter" | grep -E '^(No installation token|Contracts is referenced|Require the SchoolEngine|Mint a read-only|Install dependencies)' | cut -d' ' -f1 | tr '\n' ' ')
check "steps of ci-flutter in order" "steps of ci-flutter out of order: $order" \
  test "$order" == "No Contracts Require Mint Install "

# The two guards, run on fixtures.
step flutter 'Contracts is referenced by its HTTPS URL' "$flutter" | jq -r '.run' >"$work/pubspec-guard.sh"
step flutter 'No installation token in tracked files' "$flutter" | jq -r '.run' >"$work/token-guard.sh"
url=https://github.com/SoutienScolaireApp/contracts.git
mkdir "$work/pub"
pub() {  # pub <want exit> <label> <pubspec.yaml url> <pubspec.lock url>
  local want="$1" label="$2" rc=0
  printf 'dependencies:\n  usc_api_client:\n    git:\n      url: %s\n' "$3" >"$work/pub/pubspec.yaml"
  printf 'packages:\n  usc_api_client:\n    description:\n      url: "%s"\n' "$4" >"$work/pub/pubspec.lock"
  (cd "$work/pub" && bash "$work/pubspec-guard.sh") >"$work/out" 2>&1 || rc=$?
  if [[ "$rc" -eq "$want" ]]; then ok "pubspec guard: $label"; else ko "pubspec guard: $label (exit $rc, want $want)"; cat "$work/out"; fi
}
pub 0 "HTTPS in both files" "$url" "$url"
pub 1 "scp form in pubspec.yaml" git@github.com:SoutienScolaireApp/contracts.git "$url"
pub 1 "scp form in pubspec.lock" "$url" git@github.com:SoutienScolaireApp/contracts.git
pub 1 "ssh:// in pubspec.lock" "$url" ssh://github.com/SoutienScolaireApp/contracts.git
pub 1 "git+ssh in pubspec.yaml" git+ssh://github.com/SoutienScolaireApp/contracts.git "$url"
pub 1 "another case" GIT@GitHub.com:SoutienScolaireApp/contracts.git "$url"

mkdir "$work/repo"
git -C "$work/repo" init -q
tok() {  # tok <want exit> <label> <file content>
  local want="$1" label="$2" rc=0
  printf '%s\n' "$3" >"$work/repo/f"
  git -C "$work/repo" add f
  (cd "$work/repo" && bash "$work/token-guard.sh") >"$work/out" 2>&1 || rc=$?
  if [[ "$rc" -eq "$want" ]]; then ok "token guard: $label"; else ko "token guard: $label (exit $rc, want $want)"; cat "$work/out"; fi
  if [[ "$want" -eq 1 ]]; then
    if grep -qF -- "$3" "$work/out"; then ko "token guard: $label, the token is in the output"; else ok "token guard: $label, not printed"; fi
  fi
}
# Built here so no scanner reads this script as holding a token.
fake="ghs""_$(printf 'a%.0s' {1..24})"
# shellcheck disable=SC2016  # the literal expression of the install step
tok 0 "workflow expression" 'x-access-token:${{ steps.contracts-token.outputs.token }}@github.com'
tok 1 "token URL" "https://x-access-token:abc123@github.com/SoutienScolaireApp/contracts.git"
tok 1 "installation token" "$fake"

# --- 4. Ansible toolchain pins of ci-ansible ---------------------------------
yq '.jobs.ansible.steps[] | select(.name == "Require the Ansible toolchain pins") | .run' \
  workflow-templates/ci-ansible.yml >"$work/pins.sh"
mkdir -p "$work/pins"
if (cd "$work/pins" && bash ../pins.sh >/dev/null); then ko "ansible pins: a missing file passes"; else ok "ansible pins: a missing file fails"; fi
mkdir -p "$work/pins/.github/ansible" && touch "$work/pins/.github/ansible/requirements.txt"
if (cd "$work/pins" && bash ../pins.sh); then ok "ansible pins: the file is there"; else ko "ansible pins: the file is refused"; fi

exit "$fail"
