#!/usr/bin/env bash
# Table test of templates/contracts-lock/check-contracts-lock.sh, the lockfile
# guard of ADR-013 Amendment 3 (SoutienScolaireApp/.github#21). The passing
# bases are fixtures/: the HTTPS lockfile, the SSH relock written by
# Dependabot (the lines of SoutienScolaireApp/backend#43, verbatim) and a
# lockfile without the dependency. Each failing case is one of these bases
# with literal replacements, so the case states exactly what changed.
#
# Usage: tests/contracts-lock/run.sh
set -euo pipefail

root=$(git rev-parse --show-toplevel)
guard="$root/templates/contracts-lock/check-contracts-lock.sh"
fx="$root/tests/contracts-lock/fixtures"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0

C=002f155502b4d8ce7487058a6f924b6c9fdf20cf
H=git+https://github.com/SoutienScolaireApp/contracts.git
S=git+ssh://git@github.com/SoutienScolaireApp/contracts.git
P='&path:/clients/typescript'
SPEC="$H#v0.2.0$P"
HREPO='repo: https://github.com/SoutienScolaireApp/contracts.git'
SREPO='repo: git@github.com:SoutienScolaireApp/contracts.git'

# run <want exit> <label> <lock base> <package base> [lock|pkg <old> <new>]...
# Each triple replaces every literal <old> with <new> in the lock or the
# package file. <old> may be '$' to append <new> at the end of the file.
run() {
  local want=$1 label=$2 lock pkg file old new rc=0 out
  lock=$(<"$fx/$3")
  pkg=$(<"$fx/$4")
  shift 4
  while (($#)); do
    file=$1 old=$2 new=$3
    shift 3
    if [[ "$file" == lock ]]; then
      if [[ "$old" == '$' ]]; then lock+=$'\n'"$new"; else
        [[ "$lock" == *"$old"* ]] || { echo "FAIL $label: '$old' not in the lockfile"; fail=1; return; }
        lock=${lock//"$old"/"$new"}
      fi
    else
      [[ "$pkg" == *"$old"* ]] || { echo "FAIL $label: '$old' not in package.json"; fail=1; return; }
      pkg=${pkg//"$old"/"$new"}
    fi
  done
  printf '%s\n' "$lock" >"$work/pnpm-lock.yaml"
  printf '%s\n' "$pkg" >"$work/package.json"
  out=$("$guard" "$work/pnpm-lock.yaml" "$work/package.json" 2>&1) || rc=$?
  if [[ "$rc" -ne "$want" ]]; then
    echo "FAIL $label (exit $rc, want $want)"
    printf '     %s\n' "$out"
    fail=1
  elif [[ -n "${TOKEN:-}" && "$out" == *"$TOKEN"* ]]; then
    echo "FAIL $label: the output prints the token"
    fail=1
  else
    echo "ok   exit=$rc  $label"
    # The first reason, to show that a case fails for the expected cause.
    [[ "$rc" -eq 0 ]] || sed -n '1s/^check-contracts-lock: [^:]*:[0-9]*: /       /p' <<<"$out"
  fi
}

# --- pass -------------------------------------------------------------------
run 0 "HTTPS lockfile" https.lock package.json
run 0 "SSH relock written by Dependabot (backend#43)" ssh.lock package.json
run 0 "lockfile without the dependency" none.lock package-none.json
run 0 "SSH key under packages, HTTPS elsewhere (same commit)" https.lock package.json \
  lock "  '@usc/api-client@$H#" "  '@usc/api-client@$S#"

# --- lockfile: the @usc/api-client entry -----------------------------------
run 1 "another owner (SSH form)" ssh.lock package.json \
  lock "$S" "${S/SoutienScolaireApp/EvilOrg}" lock "$SREPO" "${SREPO/SoutienScolaireApp/EvilOrg}"
run 1 "another owner (HTTPS form)" https.lock package.json \
  lock "$HREPO" 'repo: https://github.com/EvilOrg/contracts.git'
run 1 "another repository" ssh.lock package.json \
  lock "$S" "${S/contracts/backend}" lock "$SREPO" "${SREPO/contracts/backend}"
run 1 "contracts.gitx in every field" ssh.lock package.json \
  lock "$S#" "${S}x#" lock "$SREPO" "${SREPO}x"
run 1 "contracts.gitx in resolution.repo only" https.lock package.json \
  lock "$HREPO" "${HREPO}x"
run 1 "bob@evil.com:x/y.git as resolution.repo" ssh.lock package.json \
  lock "$SREPO" 'repo: bob@evil.com:x/y.git'
run 1 "evil.com:x/y.git as resolution.repo" ssh.lock package.json \
  lock "$SREPO" 'repo: evil.com:x/y.git'
run 1 "SSH form with another user" ssh.lock package.json \
  lock "$SREPO" 'repo: bob@github.com:SoutienScolaireApp/contracts.git'
run 1 "ssh+git:// URL" https.lock package.json \
  lock "version: $H#" 'version: ssh+git://git@github.com/SoutienScolaireApp/contracts.git#'
run 1 "ssh:// URL (no git+ prefix)" https.lock package.json \
  lock "version: $H#" 'version: ssh://git@github.com/SoutienScolaireApp/contracts.git#'
run 1 "git:// URL" https.lock package.json \
  lock "version: $H#" 'version: git://github.com/SoutienScolaireApp/contracts.git#'
run 1 "http:// URL" https.lock package.json \
  lock "version: $H#" 'version: git+http://github.com/SoutienScolaireApp/contracts.git#'
run 1 "tarball: on the entry" https.lock package.json \
  lock ', type: git}' ", type: git, tarball: https://codeload.github.com/SoutienScolaireApp/contracts/tar.gz/$C}"
run 1 "resolution.commit differs from the URL commits" ssh.lock package.json \
  lock "commit: $C" 'commit: 0123456789abcdef0123456789abcdef01234567'
run 1 "snapshot key commit differs" https.lock package.json \
  lock "$H#$C$P': {}" "$H#0123456789abcdef0123456789abcdef01234567$P': {}"
run 1 "short commit" https.lock package.json \
  lock "version: $H#$C" "version: $H#002f155"
run 1 "wrong path in the URL" https.lock package.json \
  lock "version: $H#$C$P" "version: $H#$C&path:/clients/dart"
run 1 "wrong resolution.path" https.lock package.json \
  lock 'path: /clients/typescript,' 'path: /clients/dart,'
run 1 "resolution.type not git" https.lock package.json \
  lock 'type: git}' 'type: directory}'
run 1 "unexpected field in resolution" https.lock package.json \
  lock 'type: git}' 'type: git, integrity: sha512-x}'
run 1 "uppercase variant of the repository" ssh.lock package.json \
  lock "$S" "${S/contracts/Contracts}" lock "$SREPO" "${SREPO/contracts/Contracts}"
run 1 "uppercase scheme" https.lock package.json \
  lock "version: $H#" 'version: GIT+HTTPS://github.com/SoutienScolaireApp/contracts.git#'
run 1 "registry version instead of the git entry" https.lock package.json \
  lock "  '@usc/api-client@$H#$C$P':" "  '@usc/api-client@0.2.0':"
run 1 "lockfile entry without a package.json dependency" https.lock package-none.json
run 1 "package.json dependency without a lockfile entry" none.lock package.json
run 1 "specifier differs from package.json" https.lock package.json \
  lock "specifier: $SPEC" "specifier: $H#v0.1.0$P"

# --- lockfile: anywhere else ------------------------------------------------
other='
  other@1.0.0:
    resolution: {commit: 0123456789abcdef0123456789abcdef01234567, repo: REPO, type: git}'
run 1 "another git dependency on github.com" https.lock package.json \
  lock '$' "${other/REPO/https://github.com/someone/other.git}"
run 1 "bob@evil.com:x/y.git elsewhere" https.lock package.json \
  lock '$' "${other/REPO/bob@evil.com:x/y.git}"
run 1 "evil.com:x/y.git elsewhere" https.lock package.json \
  lock '$' "${other/REPO/evil.com:x/y.git}"
run 1 "git:// elsewhere" https.lock package.json \
  lock '$' "${other/REPO/git://evil.example/x.git}"
run 1 "http:// elsewhere" https.lock package.json \
  lock '$' "${other/REPO/http://evil.example/x.git}"
run 1 "uppercase GIT@ elsewhere" https.lock package.json \
  lock '$' "${other/REPO/GIT@GITHUB.COM:x/y.git}"

# --- package.json -----------------------------------------------------------
run 1 "SSH specifier in package.json" ssh.lock package.json \
  pkg "\"$SPEC\"" "\"$S#v0.2.0$P\""
run 1 "git:// in package.json" https.lock package.json \
  pkg '"private": true,' '"private": true, "repository": "git://example.com/x.git",'
run 1 "http:// in package.json" https.lock package.json \
  pkg '"private": true,' '"private": true, "homepage": "http://example.com",'
run 1 "git@ in package.json" https.lock package.json \
  pkg '"private": true,' '"private": true, "repository": "Git@example.com:x/y.git",'
run 1 "branch instead of an exact tag" https.lock package.json \
  pkg "#v0.2.0$P" "#main$P" lock "#v0.2.0$P" "#main$P"
run 1 "another owner in package.json" https.lock package.json \
  pkg SoutienScolaireApp/contracts EvilOrg/contracts lock "specifier: $SPEC" "specifier: ${SPEC/SoutienScolaireApp/EvilOrg}"

# --- never print a token ----------------------------------------------------
TOKEN="gh""s_$(printf 'A%.0s' {1..36})"
run 1 "token in an offending URL is redacted" https.lock package.json \
  lock "version: $H#" "version: git+ssh://x-access-token:$TOKEN@github.com/SoutienScolaireApp/contracts.git#"
TOKEN=$(printf '0123456789abcdef%.0s' 1 2 3)
run 1 "bare userinfo credential is redacted" https.lock package.json \
  lock "version: $H#" "version: git+https://$TOKEN@github.com/SoutienScolaireApp/contracts.git#"
unset TOKEN

# --- usage ------------------------------------------------------------------
rc=0
"$guard" "$fx/https.lock" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then echo "ok   exit=2  usage error"; else echo "FAIL usage error (exit $rc, want 2)"; fail=1; fi

exit "$fail"
