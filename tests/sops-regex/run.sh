#!/usr/bin/env bash
# Table test of SOPS_FILE_REGEX in workflow-templates/ci-ansible.yml
# (SoutienScolaireApp/.github#8): the encrypted files match, the sops
# configuration `.sops.yaml` (and look-alikes) do not, so the `sops` job never
# requires the config file to be encrypted. Then the real script of the
# `sops` job runs on throw-away repositories, non-ASCII names included.
#
# Usage: tests/sops-regex/run.sh   (needs yq, jq, git)
set -euo pipefail

root=$(git rev-parse --show-toplevel)
regex=$(yq '.env.SOPS_FILE_REGEX' "$root/workflow-templates/ci-ansible.yml")
fail=0

expect() {
  local want="$1" path="$2" got=no
  # Same matcher as the job: `git ls-files | grep -E "$SOPS_FILE_REGEX"`.
  if grep -Eq "$regex" <<<"$path"; then got=yes; fi
  if [[ "$got" == "$want" ]]; then
    echo "ok   match=$want  $path"
  else
    echo "FAIL match=$got (want $want)  $path"
    fail=1
  fi
}

expect yes 'vault.sops.yml'
expect yes 'vault.sops.yaml'
expect yes 'secrets.sops.json'
expect yes 'inventories/staging/group_vars/all/vault.sops.yml'
expect yes 'inventories/prod/.hidden.sops.yaml'
expect no  '.sops.yaml'
expect no  '.sops.yml'
expect no  'inventories/.sops.yaml'
expect no  'vault.yml'
expect no  'vault.sops.yml.bak'
expect no  'docs/sops.yaml'
expect yes 'inventories/café.sops.yml'

echo "regex: $regex"

# --- The real `sops` step on throw-away repositories ------------------------
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
yq '.jobs.sops.steps[] | select(.name == "Check that sops files are encrypted") | .run' \
  "$root/workflow-templates/ci-ansible.yml" >"$work/check.sh"
[[ -s "$work/check.sh" ]] || { echo "FAIL the sops step was not found"; exit 1; }

encrypted=$'secret: ENC[AES256_GCM,data:x]\nsops:\n    mac: ENC[AES256_GCM,data:y]\n'
repo() {  # repo <name> <path=content|enc|plain>...
  local dir="$work/$1" spec path
  shift
  git init -q "$dir"
  for spec in "$@"; do
    path=${spec%%=*}
    mkdir -p "$dir/$(dirname "$path")"
    case "${spec#*=}" in
      enc) printf '%s' "$encrypted" >"$dir/$path" ;;
      *) printf 'secret: clear\n' >"$dir/$path" ;;
    esac
  done
  git -C "$dir" add -A
  echo "$dir"
}
run_step() {  # run_step <want exit> <want count> <label> <repo dir>
  local rc=0 out
  out=$(cd "$4" && SOPS_FILE_REGEX="$regex" bash "$work/check.sh" 2>&1) || rc=$?
  if [[ "$rc" -eq "$1" && "$out" == *"$2 sops file(s) checked."* ]]; then
    echo "ok   step: $3"
  else
    echo "FAIL step: $3 (exit $rc, want $1 and $2 file(s))"
    printf '     %s\n' "$out"
    fail=1
  fi
}
run_step 0 2 "config ignored, encrypted files pass" \
  "$(repo a .sops.yaml=plain vault.sops.yml=enc inventories/café.sops.yml=enc)"
run_step 1 1 "clear file with a non-ASCII name fails" "$(repo b 'inventories/café.sops.yml=plain')"
run_step 1 1 "clear file with a space in its name fails" "$(repo c 'inventories/my vault.sops.yaml=plain')"
run_step 0 0 "no sops file" "$(repo d README.md=plain)"

exit "$fail"
