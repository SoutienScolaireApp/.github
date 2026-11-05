#!/usr/bin/env bash
# Table test of SOPS_FILE_REGEX in workflow-templates/ci-ansible.yml
# (SoutienScolaireApp/.github#8): the encrypted files match, the sops
# configuration `.sops.yaml` (and look-alikes) do not, so the `sops` job never
# requires the config file to be encrypted. Then the real script of the
# `sops` job runs on throw-away repositories: non-ASCII names, and files that
# are clear in full or in part (SoutienScolaireApp/.github#13).
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

file_case() {  # file_case <want exit> <label> <file name> <content>
  local dir="$work/case-$((++cases))"
  git init -q "$dir"
  printf '%s' "$4" >"$dir/$3"
  git -C "$dir" add -A
  run_step "$1" 1 "$2" "$dir"
}
cases=0
# The shape real sops output has, here with an age recipient: the metadata
# holds clear values and only `mac` is encrypted.
meta=$'sops:\n    age:\n        - recipient: age1x\n          enc: clear\n    lastmodified: "2026-11-05T00:00:00Z"\n    mac: ENC[AES256_GCM,data:y]\n    version: 3.13.1\n'
enc='ENC[AES256_GCM,data:x]'
y=vault.sops.yml
j=vault.sops.json
json_meta='"sops":{"mac":"ENC[AES256_GCM,data:y]","version":"3.13.1"}'

file_case 0 "yaml: nested values and lists" $y \
  "a: $enc"$'\nn: '"$enc"$'\nm:\n    k: '"$enc"$'\nl:\n    - '"$enc"$'\n'"$meta"
file_case 0 "yaml: empty strings and nulls, which sops leaves as is" $y \
  "a: $enc"$'\nempty: ""\nnothing: null\nblank:\nl:\n    - null\n    - ""\n'"$meta"
file_case 0 "yaml: every document encrypted" $y "a: $enc"$'\n'"$meta"$'---\n'"b: $enc"$'\n'"$meta"
file_case 1 "yaml: clear string next to the block" $y "a: $enc"$'\npassword: hunter2\n'"$meta"
file_case 1 "yaml: clear number" $y "a: $enc"$'\nport: 5432\n'"$meta"
file_case 1 "yaml: clear boolean" $y "a: $enc"$'\nflag: true\n'"$meta"
file_case 1 "yaml: clear value in a nested mapping" $y "a: $enc"$'\nm:\n    k: clear\n'"$meta"
file_case 1 "yaml: clear value in a list" $y $'l:\n    - '"$enc"$'\n    - clear\n'"$meta"
file_case 1 "yaml: clear value under an _unencrypted key" $y "a: $enc"$'\nname_unencrypted: clear\n'"$meta"
file_case 1 "yaml: clear second document" $y "a: $enc"$'\n'"$meta"$'---\nb: clear\n'"$meta"
file_case 1 "yaml: second document without metadata" $y "a: $enc"$'\n'"$meta"$'---\n'"b: $enc"$'\n'
file_case 1 "yaml: no sops block" $y "a: $enc"$'\n'
file_case 1 "yaml: sops block without a mac" $y "a: $enc"$'\nsops:\n    version: 3.13.1\n'
file_case 1 "yaml: clear mac" $y "a: $enc"$'\nsops:\n    mac: clear\n'
file_case 1 "yaml: sops metadata below the top level" $y "a: $enc"$'\nm:\n    sops:\n        mac: '"$enc"$'\n'
file_case 1 "yaml: empty file" $y ''
file_case 1 "yaml: not a mapping" $y $'- clear\n'
file_case 1 "yaml: unreadable" $y $'a: [\n'
file_case 0 "json: encrypted" $j "{\"a\":\"$enc\",\"m\":{\"k\":\"$enc\"},\"l\":[\"$enc\"],\"e\":\"\",\"n\":null,$json_meta}"
file_case 1 "json: clear string next to the block" $j "{\"a\":\"$enc\",\"p\":\"clear\",$json_meta}"
file_case 1 "json: clear number" $j "{\"a\":\"$enc\",\"p\":5432,$json_meta}"
file_case 1 "json: clear value in a list" $j "{\"l\":[\"$enc\",true],$json_meta}"
file_case 1 "json: no sops block" $j "{\"a\":\"$enc\"}"
file_case 1 "json: empty file" $j ''

exit "$fail"
