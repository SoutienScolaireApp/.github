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
# package file. <old> may be '$' to append <new> at the end of the file, or
# CRLF to turn the line endings into CRLF. EXTRA_FILE and EXTRA_CONTENT, when
# set, write one more file next to the lockfile (the repository root).
run() {
  local want=$1 label=$2 lock pkg file old new rc=0 out
  lock=$(<"$fx/$3")
  pkg=$(<"$fx/$4")
  shift 4
  while (($#)); do
    file=$1 old=$2 new=$3
    shift 3
    if [[ "$old" == CRLF ]]; then
      if [[ "$file" == lock ]]; then lock=${lock//$'\n'/$'\r\n'}; else pkg=${pkg//$'\n'/$'\r\n'}; fi
    elif [[ "$file" == lock ]]; then
      if [[ "$old" == '$' ]]; then lock+=$'\n'"$new"; else
        [[ "$lock" == *"$old"* ]] || { echo "FAIL $label: '$old' not in the lockfile"; fail=1; return; }
        lock=${lock//"$old"/"$new"}
      fi
    else
      [[ "$pkg" == *"$old"* ]] || { echo "FAIL $label: '$old' not in package.json"; fail=1; return; }
      pkg=${pkg//"$old"/"$new"}
    fi
  done
  rm -f "$work/.pnpmfile.cjs" "$work/.npmrc" "$work/pnpm-workspace.yaml"
  if [[ -n "${EXTRA_FILE:-}" ]]; then printf '%s\n' "$EXTRA_CONTENT" >"$work/$EXTRA_FILE"; fi
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

# --- escapes, other keys, YAML forms (security review of PR #23) -----------
run 1 "escaped key in package.json" https.lock package.json \
  pkg '"@usc/api-client":' '"\u0040usc/api-client":'
run 1 "escaped key in the lockfile" https.lock package.json \
  lock "      '@usc/api-client':" '      "\u0040usc/api-client":'
run 1 "tarball key for another package" https.lock package.json \
  lock '$' '  evil@https://evil.example/x.tgz: {}'
run 1 "file: key for another package" https.lock package.json \
  lock '$' "  'evil@file:../evil': {}"
run 1 "git key for another package" https.lock package.json \
  lock '$' "  'evil@git+https://evil.example/x.git#$C': {}"
run 1 "alias importer entry on a tarball" https.lock package.json \
  lock $'    dependencies:\n' $'    dependencies:\n      alias:\n        specifier: https://evil.example/a.tgz\n        version: https://evil.example/a.tgz\n'
run 1 "flow-style importer entry" https.lock package.json \
  lock $'      ssh2:\n        specifier: 1.17.0\n        version: 1.17.0' '      ssh2: {specifier: 1.17.0, version: 1.17.0}'
run 1 "second @usc/api-client entry under packages:" https.lock package.json \
  lock $'packages:\n\n' $'packages:\n\n'"  '@usc/api-client@$S#$C$P':"$'\n'"    resolution: {commit: $C, path: /clients/typescript, $SREPO, type: git}"$'\n\n'
run 1 "unexpected field in the importer entry" https.lock package.json \
  lock "version: $H#$C$P"$'\n' "version: $H#$C$P"$'\n        optional: true\n'
run 1 "peer suffix on the contracts key" https.lock package.json \
  lock "$P':"$'\n    resolution' "$P(zod@3.0.0)':"$'\n    resolution' lock "$P': {}" "$P(zod@3.0.0)': {}"
run 1 "YAML anchor and alias" https.lock package.json \
  lock $'      ssh2:\n' $'      ssh2: &x\n'
run 1 "CRLF lockfile" https.lock package.json lock CRLF ''
run 1 "CRLF package.json" https.lock package.json pkg CRLF ''
run 1 "byte order mark" https.lock package.json lock 'lockfileVersion' $'\xef\xbb\xbflockfileVersion'
run 0 "registry key with nested peers" https.lock package.json \
  lock '$' "  'a@1.0.0(b@2.0.0(c@3.0.0))(@d/e@1.0.0-rc.1)': {}"
run 0 "escaped quote in a package.json script" https.lock package.json \
  pkg '"git config core.hooksPath .githooks"' '"node -e \"process.exit(0)\""'

# --- other packages: resolutions, overrides, links (security re-review) -----
LM='resolution: {integrity: sha512-0KpjqXRVvrYyCsX1swR/XTK0va6VQkQM6MNo7PqW77ByjAhoARA8EfrP1N4+KlKj8YS0ZUCtRT/YUuhyYDujIQ==}'
run 1 "registry entry with a tarball resolution" https.lock package.json \
  lock "$LM" 'resolution: {tarball: https://evil.example/x.tgz}'
run 1 "registry entry with a git resolution on another host" https.lock package.json \
  lock "$LM" 'resolution: {type: git, repo: https://gitlab.example/x/y.git, commit: 0123456789012345678901234567890123456789}'
run 1 "registry entry with a block-style resolution" https.lock package.json \
  lock "$LM" $'resolution:\n      tarball: https://evil.example/x.tgz\n      integrity: sha512-x'
run 1 "registry entry without a resolution" https.lock package.json \
  lock "    $LM"$'\n' ''
run 1 "resolution in a snapshot entry" https.lock package.json \
  lock '  lodash.merge@4.6.2: {}' $'  lodash.merge@4.6.2:\n    resolution: {tarball: https://evil.example/x.tgz}'
run 1 "override to a tarball URL" https.lock package.json \
  lock "'@esbuild-kit/core-utils>esbuild': 0.25.12" "'@esbuild-kit/core-utils>esbuild': https://evil.example/e.tgz"
run 1 "override to link:" https.lock package.json \
  lock "'@esbuild-kit/core-utils>esbuild': 0.25.12" "'@esbuild-kit/core-utils>esbuild': link:../evil"
run 1 "override to file:" https.lock package.json \
  lock "'@esbuild-kit/core-utils>esbuild': 0.25.12" "'@esbuild-kit/core-utils>esbuild': file:./x.tgz"
run 1 "importer version link:" https.lock package.json \
  lock $'        specifier: 1.17.0\n        version: 1.17.0' $'        specifier: link:../evil\n        version: link:../evil'
run 1 "npm: alias on a tarball URL" https.lock package.json \
  lock $'        specifier: 1.17.0' $'        specifier: npm:evil@https://evil.example/x.tgz'
run 1 "patch_hash peer suffix (patches are refused)" https.lock package.json \
  lock '  lodash.merge@4.6.2: {}' $'  lodash.merge@4.6.2(patch_hash=abcd1234efgh):\n    dependencies: {}'
run 1 "top-level patchedDependencies" https.lock package.json \
  lock $'importers:\n' $'patchedDependencies:\n  ssh2: p.patch\n\nimporters:\n'
run 1 "top-level pnpmfileChecksum" https.lock package.json \
  lock $'importers:\n' $'pnpmfileChecksum: sha256-x\n\nimporters:\n'
run 1 "alias of a snapshot entry" https.lock package.json \
  lock '  lodash.merge@4.6.2: {}' $'  lodash.merge@4.6.2: &x {}\n  zzz@1.0.0: *x'
run 1 "complex ? key in the lockfile" https.lock package.json \
  lock '  lodash.merge@4.6.2: {}' $'  ? lodash.merge@4.6.2\n  : {}'
run 1 "space before the colon of the contracts importer key" https.lock package.json \
  lock "      '@usc/api-client':" "      '@usc/api-client' :"
run 1 "one-space indentation" https.lock package.json \
  lock $'  \'@typescript-eslint/visitor-keys@8.71.2\':\n    resolution' $' \'@typescript-eslint/visitor-keys@8.71.2\':\n   resolution'
run 1 "space before the colon in package.json" https.lock package.json \
  pkg '"@usc/api-client":' '"@usc/api-client" :'
run 1 "flow devDependencies on one line in package.json" https.lock package.json \
  pkg '"devDependencies": {' '"devDependencies": {"@usc/api-client": "https://evil.example/x.tgz",'
run 1 "escaped backslash before the closing quote of the key" https.lock package.json \
  pkg '"ssh2": "1.17.0"' '"ssh2": "1.17.0", "@usc/api-client\\": "https://evil.example/x.tgz"'
run 1 "pnpm.overrides to a tarball in package.json" https.lock package.json \
  pkg '"private": true,' '"private": true, "pnpm": {"overrides": {"ssh2": "https://evil.example/s.tgz"}},'
run 1 "pnpm.pnpmfile and patchedDependencies in package.json" https.lock package.json \
  pkg '"private": true,' '"private": true, "pnpm": {"pnpmfile": "./x.cjs", "patchedDependencies": {"ssh2": "p.patch"}},'
run 1 "pnpm.packageExtensions in package.json" https.lock package.json \
  pkg '"private": true,' '"private": true, "pnpm": {"packageExtensions": {"ssh2": {}}},'
run 0 "pnpm.overrides to a registry version in package.json" https.lock package.json \
  pkg '"private": true,' $'"private": true,\n  "pnpm": {\n    "overrides": {\n      "@esbuild-kit/core-utils>esbuild": "0.25.12"\n    }\n  },'

# --- canonical layout only (final review: what pnpm itself writes) ---------
# raw <want> <label> <lockfile text>: a whole lockfile, with package-none.json.
raw() {
  local want=$1 label=$2 rc=0 out
  printf '%s\n' "$3" >"$work/raw-lock.yaml"
  out=$("$guard" "$work/raw-lock.yaml" "$fx/package-none.json" 2>&1) || rc=$?
  if [[ "$rc" -eq "$want" ]]; then
    echo "ok   exit=$rc  $label"
    [[ "$rc" -eq 0 ]] || sed -n '1s/^check-contracts-lock: [^:]*:[0-9]*: /       /p' <<<"$out"
  else
    echo "FAIL $label (exit $rc, want $want)"; printf '     %s\n' "$out"; fail=1
  fi
}
run 0 "real pnpm 10.34.6 lockfile: libc, cpu, os, engines, nested peers" pnpm10-real.lock package-none.json
run 0 "real pnpm 10.34.6 lockfile: a dependency named type, deprecated text with a URL" pnpm10-real2.lock package-none.json
IMP=$'lockfileVersion: \'9.0\'\nimporters:\n  .:\n    dependencies:\n      foo:\n        specifier: 1.0.0\n        version: 1.0.0'
GOODPK=$'packages:\n  foo@1.0.0:\n    resolution: {integrity: sha512-AAAA}\nsnapshots:\n  foo@1.0.0: {}'
raw 0 "minimal canonical lockfile" "$IMP"$'\n'"$GOODPK"
raw 0 "overrides to semver ranges and ignoredOptionalDependencies" \
  $'lockfileVersion: \'9.0\'\nsettings:\n  autoInstallPeers: true\noverrides:\n  foo: ^1.2.3\n  bar@<2: 2.0.0\nignoredOptionalDependencies:\n  - fsevents\n'"${IMP#*$'\n'}"$'\n'"$GOODPK"
raw 1 "quoted packages key (pnpm reads it)" "$IMP"$'\n\'packages\':\n  foo@1.0.0:\n    resolution: {tarball: \'https://evil.example/foo.tgz\'}\nsnapshots:\n  foo@1.0.0: {}'
raw 1 "quoted packages key with integrity and tarball" "$IMP"$'\n\'packages\':\n  foo@1.0.0:\n    resolution: {integrity: sha512-AAAA, tarball: \'https://evil.example/foo.tgz\'}\nsnapshots:\n  foo@1.0.0: {}'
raw 1 "space before the colon of packages" "$IMP"$'\npackages :\n  foo@1.0.0:\n    resolution: {tarball: \'https://evil.example/foo.tgz\'}\nsnapshots:\n  foo@1.0.0: {}'
raw 1 "packages as a flow mapping" "$IMP"$'\npackages: {\'foo@1.0.0\': {resolution: {tarball: \'https://evil.example/foo.tgz\'}}}\nsnapshots:\n  foo@1.0.0: {}'
raw 1 "importers as a flow mapping" $'lockfileVersion: \'9.0\'\nimporters: {\'.\': {dependencies: {foo: {specifier: 1.0.0, version: \'https://evil.example/foo.tgz\'}}}}'
raw 1 "snapshots as a flow mapping" "$IMP"$'\npackages:\n  foo@1.0.0:\n    resolution: {integrity: sha512-AAAA}\nsnapshots: {foo@1.0.0: {dependencies: {bar: \'https://evil.example/b.tgz\'}}}'
raw 1 "flow value on a snapshot key" "$IMP"$'\npackages:\n  foo@1.0.0:\n    resolution: {integrity: sha512-AAAA}\nsnapshots:\n  foo@1.0.0: {dependencies: {bar: 1.0.0}}'
raw 1 "flow value on an importer field" "${IMP/specifier: 1.0.0/specifier: {a: 1}}"$'\n'"$GOODPK"
raw 1 "packages twice" "$IMP"$'\n'"$GOODPK"$'\npackages:\n  bar@1.0.0:\n    resolution: {integrity: sha512-AAAA}'
raw 1 "unknown top-level key" "$IMP"$'\n'"$GOODPK"$'\nextra:\n  x: 1'
raw 1 "unquoted lockfileVersion" "${IMP/\'9.0\'/9.0}"$'\n'"$GOODPK"
raw 1 "node@runtime: entry" "$IMP"$'\npackages:\n  node@runtime:24.11.0:\n    resolution: {integrity: sha512-AAAA}\nsnapshots:\n  node@runtime:24.11.0: {}'
# Fourth security review (pnpm 10.34.6 accepted both): a quoted scalar spread
# over lines hides a decoy resolution, and a lone CR splits a line.
INT=sha512-41Cifkg6e8TylSpdtTpeLVMqvSBEVzTttHvERD741+pnZ8ANv0004MRL43QKPDlK9cGvNp6NZWZUBlbGXYxxng==
NUMIMP=$'lockfileVersion: \'9.0\'\n\nimporters:\n\n  .:\n    dependencies:\n      is-number:\n        specifier: 7.0.0\n        version: 7.0.0\n\npackages:\n\n  is-number@7.0.0:\n    hasBin: "true\n    resolution: {integrity: '"$INT"$'}\n    "\n'
raw 1 "decoy resolution inside a multi-line quoted scalar" \
  "$NUMIMP"$'    "resolution":\n      tarball: https://127.0.0.1:1/is-number.tgz\n      integrity: '"$INT"$'\n\nsnapshots:\n\n  is-number@7.0.0: {}'
raw 1 "lone CR splitting a deprecated line" \
  "$NUMIMP"$'    deprecated: x\r    resolution: {tarball: https://127.0.0.1:1/x.tgz, integrity: '"$INT"$'}\n\nsnapshots:\n\n  is-number@7.0.0: {}'
raw 1 "lone CR mid-line in the lockfile" "$IMP"$'\npackages:\n  foo@1.0.0:\n    resolution: {integrity: sha512-AAAA}\r    hasBin: true\nsnapshots:\n  foo@1.0.0: {}'
raw 1 "block scalar value" "${IMP/specifier: 1.0.0/specifier: |}"$'\n'"$GOODPK"
raw 1 "quoted key not closed on its line" "$IMP"$'\npackages:\n  foo@1.0.0:\n    resolution: {integrity: sha512-AAAA}\n    peerDependencies:\n      \'bar: 1.0.0\nsnapshots:\n  foo@1.0.0: {}'
raw 1 "quoted packages entry field" "$IMP"$'\npackages:\n  foo@1.0.0:\n    \'resolution\': {integrity: sha512-AAAA}\nsnapshots:\n  foo@1.0.0: {}'
raw 1 "? field in a packages entry" "$IMP"$'\npackages:\n  foo@1.0.0:\n    resolution: {integrity: sha512-AAAA}\n    ? hasBin\nsnapshots:\n  foo@1.0.0: {}'
raw 1 "sequence item as a packages entry field" "$IMP"$'\npackages:\n  foo@1.0.0:\n    resolution: {integrity: sha512-AAAA}\n    - x\nsnapshots:\n  foo@1.0.0: {}'
raw 1 "unknown packages entry field" "$IMP"$'\npackages:\n  foo@1.0.0:\n    resolution: {integrity: sha512-AAAA}\n    fetch: x\nsnapshots:\n  foo@1.0.0: {}'
raw 1 "unknown snapshots entry field" "$IMP"$'\n'"$GOODPK"$'\n  bar@1.0.0:\n    source: x'
raw 0 "known fields, quoted deeper keys" "$IMP"$'\npackages:\n  foo@1.0.0:\n    resolution: {integrity: sha512-AAAA}\n    hasBin: true\n    peerDependencies:\n      \'@vitest/browser\': 5.0.5\n    peerDependenciesMeta:\n      \'@vitest/browser\':\n        optional: true\nsnapshots:\n  foo@1.0.0:\n    optional: true\n    dependencies:\n      \'@a/b\': 1.0.0'
run 1 "lone CR in package.json" https.lock package.json pkg '"private": true,' $'"private": true,\r'
run 1 "github: dependency in package.json" https.lock package.json pkg '"ssh2": "1.17.0"' '"ssh2": "github:evil/x"'
run 1 "user/repo dependency in package.json" https.lock package.json pkg '"ssh2": "1.17.0"' '"ssh2": "evil/x"'
run 1 "workspace: dependency in package.json" https.lock package.json pkg '"ssh2": "1.17.0"' '"ssh2": "workspace:*"'
run 1 "jsr: dependency in package.json" https.lock package.json pkg '"ssh2": "1.17.0"' '"ssh2": "jsr:@s/c@1"'
run 1 "catalog: dependency in package.json" https.lock package.json pkg '"ssh2": "1.17.0"' '"ssh2": "catalog:"'
run 1 "runtime: dependency in package.json" https.lock package.json pkg '"ssh2": "1.17.0"' '"node": "runtime:24.11.0"'
run 1 "tarball dependency in package.json" https.lock package.json pkg '"ssh2": "1.17.0"' '"ssh2": "https://evil.example/foo.tgz"'
run 1 "github: in pnpm.overrides" https.lock package.json \
  pkg '"private": true,' $'"private": true,\n  "pnpm": {\n    "overrides": {\n      "foo": "github:evil/x"\n    }\n  },'
run 1 "one-line package.json" none.lock package-none.json pkg "$(<"$fx/package-none.json")" '{"name":"t","dependencies":{"foo":"1.0.0"}}'
run 0 "semver ranges in package.json" https.lock package.json pkg '"ssh2": "1.17.0"' '"ssh2": "^1.17.0 || >=2.0.0-rc.1 <3"'

# --- repository root: pnpmfile and workspace settings -----------------------
EXTRA_FILE=.pnpmfile.cjs EXTRA_CONTENT='module.exports = {}' \
  run 1 ".pnpmfile.cjs present" https.lock package.json
EXTRA_FILE=.npmrc EXTRA_CONTENT='pnpmfile = hooks.cjs' \
  run 1 "pnpmfile setting in .npmrc" https.lock package.json
EXTRA_FILE=pnpm-workspace.yaml EXTRA_CONTENT=$'overrides:\n  ssh2: 1.17.0' \
  run 1 "pnpm-workspace.yaml with overrides" https.lock package.json
EXTRA_FILE=pnpm-workspace.yaml EXTRA_CONTENT=$'catalog:\n  ssh2: 1.17.0' \
  run 1 "pnpm-workspace.yaml with a catalog" https.lock package.json
EXTRA_FILE=pnpm-workspace.yaml EXTRA_CONTENT='"pnpmfile": ./x.cjs' \
  run 1 "pnpm-workspace.yaml with a quoted pnpmfile key" https.lock package.json
EXTRA_FILE=pnpm-workspace.yaml EXTRA_CONTENT="{packages: ['.'], pnpmfile: x.cjs}" \
  run 1 "pnpm-workspace.yaml as a flow mapping" https.lock package.json
EXTRA_FILE=pnpm-workspace.yaml EXTRA_CONTENT=$'? pnpmFile\n: x.cjs' \
  run 1 "pnpm-workspace.yaml with a complex key" https.lock package.json
EXTRA_FILE=pnpm-workspace.yaml EXTRA_CONTENT=$'packageExtensions:\n  ssh2:\n    dependencies:\n      evil: https://evil.example/x.tgz' \
  run 1 "pnpm-workspace.yaml with packageExtensions" https.lock package.json
EXTRA_FILE=.npmrc EXTRA_CONTENT='PNPMFILE=x.cjs' \
  run 1 "uppercase pnpmfile setting in .npmrc" https.lock package.json
EXTRA_FILE=pnpm-workspace.yaml EXTRA_CONTENT=$'onlyBuiltDependencies:\n  - esbuild' \
  run 0 "pnpm-workspace.yaml with an unrelated setting" https.lock package.json
EXTRA_FILE=.npmrc EXTRA_CONTENT='engine-strict=true' \
  run 0 ".npmrc without a pnpmfile setting" https.lock package.json

# --- never print a token ----------------------------------------------------
TOKEN="gh""s_$(printf 'A%.0s' {1..36})"
run 1 "token in an offending URL is redacted" https.lock package.json \
  lock "version: $H#" "version: git+ssh://x-access-token:$TOKEN@github.com/SoutienScolaireApp/contracts.git#"
TOKEN=$(printf '0123456789abcdef%.0s' 1 2 3)
run 1 "bare userinfo credential is redacted" https.lock package.json \
  lock "version: $H#" "version: git+https://$TOKEN@github.com/SoutienScolaireApp/contracts.git#"
unset TOKEN

# --- usage ------------------------------------------------------------------
usage() {  # usage <label> <args...>: the guard must exit 2
  local label=$1 rc=0
  shift
  "$guard" "$@" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 2 ]]; then echo "ok   exit=2  $label"; else echo "FAIL $label (exit $rc, want 2)"; fail=1; fi
}
usage "one argument" "$fx/https.lock"
usage "identical paths" "$fx/https.lock" "$fx/https.lock"
usage "unreadable path" "$fx/https.lock" "$work/missing.json"

exit "$fail"
