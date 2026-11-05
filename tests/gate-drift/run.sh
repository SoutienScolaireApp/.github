#!/usr/bin/env bash
# Checks of the `gate-drift` common job (SoutienScolaireApp/.github#41), without
# network: the script of ci-common runs in a shallow clone of a real merge
# commit, as actions/checkout leaves it, against a local bare repository that
# stands for the public source.
#
# Usage: tests/gate-drift/run.sh   (needs yq, jq, git, timeout)
set -euo pipefail

root=$(git rev-parse --show-toplevel)
ref="$root/workflow-templates/ci-common.yml"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Throwaway commits: neither the identity nor the signature of the machine.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
fail=0
ok() { echo "ok   $1"; }
ko() { echo "FAIL $1"; fail=1; }

job='.jobs."gate-drift"'
step="$job.steps[] | select(.name == \"Compare the Gate integrity copies with the public source\")"
yq "$step | .run" "$ref" >"$work/job.sh"
[[ -s "$work/job.sh" ]] || { ko "the gate-drift step was not found in $ref"; exit 1; }

# --- Invariants of the job ---------------------------------------------------
assert() {  # assert <label> <yq expression that must print true>
  if [[ "$(yq "$2" "$ref")" == "true" ]]; then ok "$1"; else ko "$1"; fi
}
assert "the source is the public repository" "($step | .env.SOURCE_REPO) == \"SoutienScolaireApp/.github\""
assert "the checkout reaches the first parent" "($job.steps[0].with.fetch-depth) == 2"
assert "the checkout keeps no credential" "($job.steps[0].with.persist-credentials) == false"
assert "the action is pinned by SHA" "$job.steps[0].uses | test(\"@[0-9a-f]{40}\$\")"
assert "read-only permissions" "($job.permissions | to_entries | length == 1) and $job.permissions.contents == \"read\""
assert "the fork guard of the other common jobs" "$job.if == .jobs.gitleaks.if"
assert "in the needs of the gate" '.jobs."quality-gate".needs | contains(["gate-drift"])'
if grep -q 'secrets\.\|github\.token\|[$]{{' <(yq -o=json "$job" "$ref" | jq 'del(.if)'); then
  ko "no secret, no token, no expression in the job"
else
  ok "no secret, no token, no expression in the job"
fi

# --- Fixtures ----------------------------------------------------------------
wf=.github/workflows/gate-integrity.yml
sh=.github/scripts/gate-integrity.sh

put() {  # put <dir> <gate-integrity.yml content> <gate-integrity.sh content>; "-" removes
  mkdir -p "$1/.github/workflows" "$1/.github/scripts"
  if [[ "$2" == - ]]; then rm -f "$1/$wf"; else printf '%s\n' "$2" >"$1/$wf"; fi
  if [[ "$3" == - ]]; then rm -f "$1/$sh"; else printf '%s\n' "$3" >"$1/$sh"; fi
}
commit() { git -C "$1" add -A && git -C "$1" commit -qm "$2"; }

put "$work/src" public-yml public-sh
chmod +x "$work/src/$sh"
git -C "$work/src" init -q -b develop
commit "$work/src" source
git clone -q --bare "$work/src" "$work/source.git"

chmod_checker() { [[ ! -f "$work/repo/$sh" ]] || chmod "$1" "$work/repo/$sh"; }

# The repository of the PR: base files, then a PR that lands the head files and
# a marker, merged into a develop that moved on. Depth 2 as in the job. The
# checker is executable, as in the source, unless a chmod argument says otherwise.
pull_request() {  # <base yml> <base sh> <head yml> <head sh> [base chmod] [head chmod]
  rm -rf "$work/repo" "$work/pr"
  put "$work/repo" "$1" "$2"
  chmod_checker "${5:-+x}"
  git -C "$work/repo" init -q -b develop
  commit "$work/repo" base
  git -C "$work/repo" switch -qc pr
  put "$work/repo" "$3" "$4"
  chmod_checker "${6:-${5:-+x}}"
  echo marker >"$work/repo/marker"
  commit "$work/repo" pr
  git -C "$work/repo" switch -q develop
  echo moved >"$work/repo/moved"
  commit "$work/repo" moved
  git -C "$work/repo" merge -q --no-ff -m merge pr
  git clone -q --depth 2 "file://$work/repo" "$work/pr"
}

verdict() {  # verdict <want exit> <want annotation: error|warning|notice|none> <label> [source]
  local want=$1 note=$2 label=$3 src=${4:-source} rc=0 found=none
  (cd "$work/pr" && GITHUB_REPOSITORY=SoutienScolaireApp/app SOURCE_REPO="$src" \
    GITHUB_SERVER_URL="file://$work" GIT_TERMINAL_PROMPT=0 bash "$work/job.sh") >"$work/out" 2>&1 || rc=$?
  for a in error warning notice; do
    if grep -q "^::$a::" "$work/out"; then found=$a; fi
  done
  if [[ "$rc" -eq "$want" && "$found" == "$note" ]]; then
    ok "$label"
  else
    ko "$label (exit $rc, want $want; annotation $found, want $note)"
    sed 's/^/     /' "$work/out"
  fi
}

# --- Cases -------------------------------------------------------------------
pull_request old-yml public-sh weak-yml public-sh
verdict 1 error "touched and different fails"
pull_request old-yml old-sh public-yml public-sh
verdict 0 none "touched and same passes (the rollout PR)"
pull_request old-yml old-sh old-yml old-sh
verdict 0 warning "not touched and different warns"
pull_request public-yml public-sh public-yml public-sh
verdict 0 none "not touched and same passes"

pull_request old-yml old-sh old-yml old-sh
verdict 0 warning "fetch failure, not touched, warns" missing
if grep -q 'Could not read' "$work/out"; then ok "the warning names the failed read"; else ko "the warning names the failed read"; fi
pull_request old-yml public-sh weak-yml public-sh
verdict 1 error "fetch failure, touched, fails" missing
if grep -q 'could not be read' "$work/out"; then ok "the error names the failed read"; else ko "the error names the failed read"; fi
pull_request old-yml old-sh public-yml public-sh
verdict 1 error "fetch failure, touched even with the right copies, fails" missing

pull_request old-yml old-sh public-yml old-sh
verdict 1 error "one file touched, the other still different, fails"
pull_request public-yml old-sh weak-yml old-sh
verdict 1 error "the other file different, fails"
pull_request public-yml public-sh - public-sh
verdict 1 error "a file removed by the PR fails"
pull_request public-yml - public-yml -
verdict 0 warning "a file missing from the repository, not touched, warns"

pull_request public-yml public-sh public-yml public-sh +x -x
verdict 1 error "the executable bit lost by the PR fails"
pull_request public-yml public-sh public-yml public-sh -x
verdict 0 warning "the executable bit already missing, not touched, warns"
pull_request public-yml public-sh public-yml public-sh -x +x
verdict 0 none "the executable bit restored by the PR passes"

# A file missing from the source is an unreadable source, never a pass.
put "$work/src" - public-sh
commit "$work/src" "no workflow"
git -C "$work/src" push -q "$work/source.git" develop
pull_request - public-sh - public-sh
verdict 0 warning "a file missing from the source, not touched, warns"
pull_request - old-sh - public-sh
verdict 1 error "a file missing from the source, touched, fails"

# The source repository is its own reference: no fetch, no verdict.
pull_request old-yml old-sh weak-yml old-sh
rc=0
(cd "$work/pr" && GITHUB_REPOSITORY=SoutienScolaireApp/.github SOURCE_REPO=SoutienScolaireApp/.github \
  GITHUB_SERVER_URL=file:///nonexistent bash "$work/job.sh") >"$work/out" 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]] && grep -q '^::notice::' "$work/out" && ! grep -q '^::warning::' "$work/out"; then
  ok "the source repository passes with a notice, without a fetch"
else
  ko "the source repository (exit $rc)"
  sed 's/^/     /' "$work/out"
fi

exit "$fail"
