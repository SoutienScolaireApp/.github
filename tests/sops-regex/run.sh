#!/usr/bin/env bash
# Table test of SOPS_FILE_REGEX in workflow-templates/ci-ansible.yml
# (SoutienScolaireApp/.github#8): the encrypted files match, the sops
# configuration `.sops.yaml` (and look-alikes) do not, so the `sops` job never
# requires the config file to be encrypted.
#
# Usage: tests/sops-regex/run.sh   (needs yq)
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

echo "regex: $regex"
exit "$fail"
