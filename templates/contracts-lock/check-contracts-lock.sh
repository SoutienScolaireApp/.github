#!/bin/sh
# Lockfile guard of the @usc/api-client git dependency on the private
# SoutienScolaireApp/contracts (ADR-013 Amendment 3, amended rules 5 and 9).
#
# Source of truth: templates/contracts-lock/check-contracts-lock.sh in
# SoutienScolaireApp/.github. Consumers copy it, unchanged, to
# .github/scripts/check-contracts-lock.sh (CI.md, "The contracts lockfile
# guard"). The same script runs in CI before the install and in the backend
# image build stage. POSIX sh and awk only, no other dependency.
#
# Usage: check-contracts-lock.sh <pnpm-lock.yaml> <package.json>
#
# package.json: the @usc/api-client specifier is exactly
#   git+https://github.com/SoutienScolaireApp/contracts.git#vX.Y.Z&path:/clients/typescript
# and the file holds no git@, ssh://, git+ssh, git:// or http:// (any case).
#
# pnpm-lock.yaml: a positive allowlist on the @usc/api-client entry. The
# importer `version:`, the `packages:` key and the `snapshots:` key are
# exactly <form>#<40-hex>&path:/clients/typescript, <form> being
#   git+https://github.com/SoutienScolaireApp/contracts.git   or
#   git+ssh://git@github.com/SoutienScolaireApp/contracts.git
# `resolution` is exactly {commit, path, repo, type} with repo
# https://github.com/SoutienScolaireApp/contracts.git or
# git@github.com:SoutienScolaireApp/contracts.git, path /clients/typescript,
# type git, and no tarball; every URL commit equals resolution.commit. The
# importer `specifier:` mirrors package.json. Every other line fails on any
# git@, ssh://, git+ssh, ssh+git://, git://, http://, github.com (any case)
# or scp-like host:path URL. Every key under `packages:` and `snapshots:` is
# either that exact entry or a registry key name@<semver>, with an optional
# (peers) suffix (no `=`, so no patch_hash: patches are refused); a tarball,
# link:, file: or git key of another package fails. Every other entry under
# `packages:` has exactly `resolution: {integrity: sha...}`; no tarball, type,
# repo, directory or commit field outside the contracts entry; no link: or
# file: importer; no top-level patchedDependencies, pnpmfileChecksum,
# packageExtensionsChecksum or catalogs; overrides only to registry versions.
# package.json: no pnpmfile, patchedDependencies or packageExtensions, and no
# https://, link:, file:, npm: or @usc outside the specifier line.
#
# Both files: no backslash escape (an escaped key would hide the dependency;
# package.json allows only \" and \\, which npm scripts need), no CRLF, no
# byte order mark; the lockfile has no YAML anchor, alias or flow mapping
# under importers. Repository root (the directory of the lockfile): no
# .pnpmfile.cjs or .pnpmfile.mjs and no pnpmfile setting in .npmrc (pnpmfile
# hooks run inside the install step that holds the token, --ignore-scripts or
# not), and pnpm-workspace.yaml, if present, holds no pnpmfile, overrides,
# patchedDependencies, packageExtensions, catalog or @usc text (any case,
# anywhere), no top-level flow mapping and no `?` key.
#
# Every packages/snapshots entry field is an unquoted key from the list pnpm
# writes; no carriage return anywhere; no quote left open on a line and no
# block scalar in the lockfile.
#
# Canonical layout only: column-0 lines are lockfileVersion and the section
# lines pnpm writes, each once; flow values only on the one-line resolution,
# engines, cpu, os and libc fields and as {} on a snapshot key. package.json
# dependency and overrides values are semver ranges or the exact specifier.
#
# A safety net against accidents and Dependabot rewrites, not a control
# against a malicious writer with push access (the ruleset and review cover
# that).
#
# The SSH form is a representation only: CI disables SSH and rewrites both
# forms to authenticated HTTPS. Exit 0 when the files pass, 1 when they do
# not, 2 on a usage error. Offending lines are printed with any URL
# credential redacted.
set -eu
# Bytes, not characters: awk regexes, tolower and grep -i behave the same
# with every awk and runner locale.
LC_ALL=C
export LC_ALL

me=check-contracts-lock
if [ "$#" -ne 2 ]; then
  echo "usage: $me <pnpm-lock.yaml> <package.json>" >&2
  exit 2
fi
if [ "$1" = "$2" ]; then
  echo "$me: the lockfile and package.json are the same path" >&2
  exit 2
fi
for f in "$1" "$2"; do
  if [ ! -f "$f" ] || [ ! -r "$f" ]; then
    echo "$me: $f: not a readable file" >&2
    exit 2
  fi
done
# awk reads an operand of the form name=value as an assignment: anchor
# relative paths so a file name with '=' is still read as a file.
lock=$1
pkg=$2
case $lock in /*) ;; *) lock=./$lock ;; esac
case $pkg in /*) ;; *) pkg=./$pkg ;; esac

status=0
# A byte order mark, read as bytes in sh: awk and the locale cannot change it.
for f in "$1" "$2"; do
  if [ "$(dd if="$f" bs=3 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')" = efbbbf ]; then
    echo "$me: $f:1: byte order mark: refused" >&2
    status=1
  fi
done

# Settings that change what pnpm installs, outside the two files.
root=$(dirname -- "$1")
for f in .pnpmfile.cjs .pnpmfile.mjs; do
  if [ -e "$root/$f" ]; then
    echo "$me: $root/$f: a pnpmfile is refused, its hooks run while the contracts token is reachable" >&2
    status=1
  fi
done
# Substring matches, any case: quoting, flow style or complex keys cannot hide
# a setting.
if [ -f "$root/.npmrc" ] && grep -iq 'pnpmfile' "$root/.npmrc"; then
  echo "$me: $root/.npmrc: a pnpmfile setting is refused" >&2
  status=1
fi
ws=$root/pnpm-workspace.yaml
if [ -f "$ws" ]; then
  bad=$(grep -niE 'pnpmfile|overrides|patcheddependencies|packageextensions|catalog|@usc|^[[:space:]]*[{?]' "$ws" | cut -d: -f1 | tr '\n' ' ' || true)
  if [ -n "$bad" ]; then
    echo "$me: $ws: pnpmfile, overrides, patchedDependencies, packageExtensions, catalog, @usc, a top-level flow mapping or a ? key are refused (line(s) $bad)" >&2
    status=1
  fi
fi

# The program holds no single quote (written \047), so it is one literal.
# shellcheck disable=SC2016  # an awk program, not shell expansions
prog='
function fail(file, line, why, text, out, u) {
  # Never print a credential: any URL userinfo but the plain SSH user git,
  # and anything shaped like a GitHub token.
  out = ""
  while (match(text, /\/\/[^\/@ ]+@/)) {
    u = substr(text, RSTART + 2, RLENGTH - 3)
    out = out substr(text, 1, RSTART + 1) (u == "git" ? u : "***") "@"
    text = substr(text, RSTART + RLENGTH)
  }
  text = out text
  gsub(/(gh[pousr]_|github_pat_)[A-Za-z0-9_]+/, "***", text)
  if (length(text) > 200) text = substr(text, 1, 200) "..."
  printf "%s: %s:%d: %s\n", me, file, line, why > "/dev/stderr"
  if (text != "") printf "    %s\n", text > "/dev/stderr"
  errors++
}
function ishex40(s) { return length(s) == 40 && s ~ /^[0-9a-f]+$/ }
function indent(s) { match(s, /^ */); return RLENGTH }
# Checks one locked URL, records its commit for the comparison at the end.
function url(u, line, text, rest) {
  if (index(u, HTTPS_URL "#") == 1) rest = substr(u, length(HTTPS_URL) + 2)
  else if (index(u, SSH_URL "#") == 1) rest = substr(u, length(SSH_URL) + 2)
  else { fail(LF, line, "@usc/api-client is not locked to SoutienScolaireApp/contracts over the HTTPS or SSH form", text); return }
  if (!ishex40(substr(rest, 1, 40)) || substr(rest, 41) != "&path:/clients/typescript") {
    fail(LF, line, "@usc/api-client URL is not <form>#<40-hex commit>&path:/clients/typescript", text); return
  }
  nurl++; url_commit[nurl] = substr(rest, 1, 40); url_line[nurl] = line; url_text[nurl] = text
}
# Splits a quoted YAML key line into KEY and KEY_REST (after the colon);
# returns 0 if the key is not quoted.
function key(s, q, end) {
  sub(/^ */, "", s); q = substr(s, 1, 1)
  if (q != "\047" && q != "\"") return 0
  end = index(substr(s, 2), q)
  if (end == 0 || substr(s, end + 2, 1) != ":") return 0
  KEY = substr(s, 2, end - 1); KEY_REST = substr(s, end + 3)
  return 1
}
function resolution(s, line, text, n, i, parts, k, v, seen, c) {
  if (s !~ /^    resolution: \{.*\}$/) { fail(LF, line, "@usc/api-client resolution is not a {commit, path, repo, type} map", text); return }
  sub(/^    resolution: \{/, "", s); sub(/\}$/, "", s)
  n = split(s, parts, ", ")
  for (i = 1; i <= n; i++) {
    c = index(parts[i], ": ")
    if (c == 0) { fail(LF, line, "@usc/api-client resolution has a malformed field", text); return }
    k = substr(parts[i], 1, c - 1); v = substr(parts[i], c + 2)
    if (k in seen) { fail(LF, line, "@usc/api-client resolution repeats " k, text); return }
    seen[k] = v
  }
  if ("tarball" in seen) { fail(LF, line, "@usc/api-client resolution has a tarball: refused (ADR-013 Amendment 3)", text); return }
  for (k in seen) if (k != "commit" && k != "path" && k != "repo" && k != "type") { fail(LF, line, "@usc/api-client resolution has an unexpected field " k, text); return }
  if (!ishex40(seen["commit"])) { fail(LF, line, "@usc/api-client resolution.commit is not a 40-hex commit", text); return }
  if (seen["repo"] != HTTPS_REPO && seen["repo"] != SSH_REPO) { fail(LF, line, "@usc/api-client resolution.repo is not SoutienScolaireApp/contracts over the HTTPS or SSH form", text); return }
  if (seen["path"] != "/clients/typescript") { fail(LF, line, "@usc/api-client resolution.path is not /clients/typescript", text); return }
  if (seen["type"] != "git") { fail(LF, line, "@usc/api-client resolution.type is not git", text); return }
  nres++; res_commit = seen["commit"]
}
# A value that opens a quote it does not close on the same line, or starts a
# block scalar, spans lines: refused. Returns the reason, or "".
function multiline(s, t, q, e, c, v, f) {
  t = s; sub(/^ */, "", t)
  if (substr(t, 1, 2) == "- ") t = substr(t, 3)
  q = substr(t, 1, 1)
  if (q == "\047" || q == "\"") {
    e = index(substr(t, 2), q)
    if (e == 0) return "quoted key not closed on its line"
    t = substr(t, e + 2)
  } else {
    c = index(t, ": ")
    if (c == 0) return ""
    t = substr(t, c)
  }
  if (substr(t, 1, 1) != ":") return ""
  v = substr(t, 2); sub(/^ /, "", v); f = substr(v, 1, 1)
  if (f == "|" || f == ">") return "block scalar"
  if ((f == "\047" || f == "\"") && (length(v) < 2 || substr(v, length(v), 1) != f)) return "quoted value not closed on its line"
  return ""
}
# Ends the registry entry under packages: being read, if any.
function close_other() {
  if (oline && ores != 1) fail(LF, oline, "registry package needs exactly one resolution: {integrity: sha...}", otext)
  oline = 0
}
# Every line that is not an allowlisted field of the entry.
function scan(s, line, l) {
  l = tolower(s)
  if (index(l, "git@") || index(l, "ssh://") || index(l, "git+ssh") || index(l, "git://") || index(l, "http://"))
    fail(LF, line, "SSH, git:// or http:// URL outside the @usc/api-client entry", s)
  else if (index(l, "github.com"))
    fail(LF, line, "github.com URL outside the @usc/api-client entry", s)
  else if (s ~ /(^|[ \t\047"{,[])([A-Za-z0-9._-]+@)?[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+:[A-Za-z0-9._~-]/)
    fail(LF, line, "scp-like host:path URL", s)
  else if (index(s, "@usc/api-client"))
    fail(LF, line, "unexpected @usc/api-client line", s)
}
BEGIN {
  # Paths come from the environment: awk -v would interpret backslashes.
  me = ENVIRON["ME"]; PF = ENVIRON["PF"]; LF = ENVIRON["LF"]
  INTEG_RE = "^    resolution: \\{integrity: sha(1|256|384|512)-[A-Za-z0-9+/]+=*\\}$"
  n = split("resolution engines cpu os libc deprecated hasBin prepare requiresBuild bundledDependencies peerDependencies peerDependenciesMeta version", a, " ")
  for (i = 1; i <= n; i++) FIELDS["packages" SUBSEP a[i]] = 1
  n = split("dependencies optionalDependencies transitivePeerDependencies optional id", a, " ")
  for (i = 1; i <= n; i++) FIELDS["snapshots" SUBSEP a[i]] = 1
  RANGE_RE = "^[\\^~<>=*xX0-9][0-9A-Za-z.^~<>=|*+ -]*$"
  REG_RE = "^(@[A-Za-z0-9._~-]+/)?[A-Za-z0-9._~-]+@[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?(\\([A-Za-z0-9@/._~+()-]*\\))?$"
  HTTPS_REPO = "https://github.com/SoutienScolaireApp/contracts.git"
  SSH_REPO = "git@github.com:SoutienScolaireApp/contracts.git"
  HTTPS_URL = "git+" HTTPS_REPO
  SSH_URL = "git+ssh://git@github.com/SoutienScolaireApp/contracts.git"
  SPEC_RE = "^git\\+https://github\\.com/SoutienScolaireApp/contracts\\.git#v[0-9]+\\.[0-9]+\\.[0-9]+&path:/clients/typescript$"
}

# --- both files -------------------------------------------------------------
{
  file = (FILENAME == PF) ? PF : LF
  # Any carriage return: a lone CR mid-line is a line break for js-yaml.
  if (index($0, "\r") && !cr[file]++) fail(file, FNR, "carriage return (CR or CRLF) is not supported", "")
  gsub(/\r/, "")
  t = $0
  if (file == PF) { gsub(/\\\\/, "", t); gsub(/\\"/, "", t) }
  if (index(t, "\\")) fail(file, FNR, "backslash escape: refused (an escaped key could hide @usc/api-client)", $0)
}

# --- package.json -----------------------------------------------------------
FILENAME == PF {
  l = tolower($0)
  # Dependency blocks, one entry per line as npm and pnpm write them: every
  # value is a semver range, or the exact contracts specifier checked below.
  if ($0 ~ /"(dependencies|devDependencies|optionalDependencies|peerDependencies|overrides)"/) {
    if ($0 ~ /^ *"(dependencies|devDependencies|optionalDependencies|peerDependencies|overrides)": \{$/) depblock = 1
    else fail(PF, FNR, "package.json dependency block must be written one entry per line", $0)
  } else if (depblock && $0 ~ /^ *\},?$/) depblock = 0
  else if (depblock && !index($0, "\"@usc/api-client\"")) {
    v = $0
    if (!sub(/^ *"[^"]+": "/, "", v) || !sub(/",?$/, "", v) || v !~ RANGE_RE)
      fail(PF, FNR, "package.json dependency value is not a semver range (github:, user/repo, workspace:, jsr:, catalog:, npm:, runtime: and URLs are refused)", $0)
  }
  if (index(l, "git@") || index(l, "ssh://") || index(l, "git+ssh") || index(l, "git://") || index(l, "http://"))
    fail(PF, FNR, "package.json holds a git@, ssh://, git+ssh, git:// or http:// URL", $0)
  if (index(l, "pnpmfile") || index(l, "patcheddependencies") || index(l, "packageextensions"))
    fail(PF, FNR, "package.json holds a pnpmfile, patchedDependencies or packageExtensions setting", $0)
  if (!index($0, "\"@usc/api-client\"") && (index(l, "https://") || index(l, "@usc") || l ~ /"(link|file|npm):/))
    fail(PF, FNR, "package.json holds an https://, link:, file: or npm: value or an @usc reference outside the @usc/api-client specifier", $0)
  if (index($0, "\"@usc/api-client\"")) {
    v = $0
    if (!sub(/^[ \t]*"@usc\/api-client": "/, "", v) || !sub(/",?$/, "", v) || v !~ SPEC_RE)
      fail(PF, FNR, "@usc/api-client must be exactly git+https://github.com/SoutienScolaireApp/contracts.git#vX.Y.Z&path:/clients/typescript", $0)
    else if (spec != "" && spec != v)
      fail(PF, FNR, "@usc/api-client is declared twice with different specifiers", $0)
    else spec = v
  }
  next
}

# --- pnpm-lock.yaml ---------------------------------------------------------
/^[ \t]*$/ { next }
/^[^ ]/ {
  close_other()
  sec = $0; sub(/:.*/, "", sec); entry = ""
  # Only the canonical top-level lines pnpm writes, each section once.
  if ($0 ~ /^lockfileVersion: \047[0-9]+\.[0-9]+\047$/) sec = "lockfileVersion"
  else if ($0 !~ /^(settings|importers|packages|snapshots|overrides|ignoredOptionalDependencies|time):$/) {
    fail(LF, FNR, "top-level line is not one pnpm writes (refused: other keys, quoting, flow values, a space before the colon)", $0); sec = "?"
  }
  if (seen_sec[sec]++ && sec != "?") fail(LF, FNR, "top-level " sec " appears twice", $0)
  scan($0, FNR); next
}
{
  ind = indent($0)
  if (entry != "" && ind <= entry_ind) entry = ""
  if ($0 ~ /(^|[:-] )[&*][A-Za-z0-9_]/ || $0 ~ /^ *<<:/) fail(LF, FNR, "YAML anchor, alias or merge key: refused", $0)
  # pnpm indents by two: any other step could move a line out of its entry.
  if (ind % 2) { fail(LF, FNR, "odd indentation: refused", $0); next }
  why = multiline($0)
  if (why != "") { fail(LF, FNR, why ": refused", $0); next }
  # Entry fields: the unquoted keys pnpm writes, nothing else.
  if ((sec == "packages" || sec == "snapshots") && ind == 4) {
    k = $0
    if (!sub(/^    /, "", k) || k !~ /^[A-Za-z]+:( |$)/) { fail(LF, FNR, sec " entry field is not an unquoted key", $0); next }
    sub(/:.*/, "", k)
    if (!((sec SUBSEP k) in FIELDS)) { fail(LF, FNR, "unexpected " sec " entry field " k, $0); next }
  }
  # deprecated: is free text, never a source: no URL scan, no flow rule.
  if (sec == "packages" && ind == 4 && $0 ~ /^    deprecated: /) next
  # Flow values only where pnpm writes them: one-line resolution, engines,
  # cpu, os and libc of a package entry, and `{}` on a snapshot key.
  if ((index($0, "{") || index($0, "[")) && \
      !(sec == "packages" && ind == 4 && $0 ~ /^    (resolution|engines|cpu|os|libc): [{[][^{}[\]]*[}\]]$/) && \
      !(sec == "snapshots" && ind == 2 && $0 ~ /: \{\}$/ && gsub(/[{}[\]]/, "&") == 2)) {
    fail(LF, FNR, "flow value where pnpm writes none: refused", $0); next
  }
  if (oline && ind <= 2) close_other()
  if (oline) {
    if (ind == 4 && $0 ~ /^    resolution:/) {
      if ($0 ~ INTEG_RE) ores++
      else fail(LF, FNR, "resolution of a registry package must be exactly {integrity: sha...}", $0)
    } else if (ind == 4 && $0 ~ /^    (tarball|type|repo|directory|commit): /)
      fail(LF, FNR, "resolution field outside the @usc/api-client entry", $0)
    scan($0, FNR); next
  }
  if (sec == "snapshots" && ind == 4 && $0 ~ /^    resolution:/) { fail(LF, FNR, "resolution under snapshots: refused", $0); next }
  if (sec == "overrides" && $0 ~ /link:|file:|npm:|:\/\/|@usc/) { fail(LF, FNR, "override to a link:, file:, npm: or URL source, or of @usc: refused", $0); next }
  if (sec == "importers" && $0 ~ /^ *(specifier|version): (link|file):/) { fail(LF, FNR, "link: or file: dependency: refused", $0); next }

  if (entry == "importer") {
    if ($0 ~ /^ *specifier: /) {
      v = $0; sub(/^ *specifier: /, "", v)
      if (spec == "") fail(LF, FNR, "@usc/api-client is locked but package.json does not declare it", $0)
      else if (v != spec) fail(LF, FNR, "@usc/api-client specifier differs from package.json", $0)
    } else if ($0 ~ /^ *version: /) {
      v = $0; sub(/^ *version: /, "", v); url(v, FNR, $0)
    } else fail(LF, FNR, "unexpected field in the @usc/api-client importer entry", $0)
    next
  }
  if (entry == "package" && ind == 4 && $0 ~ /^    resolution:/) {
    resolution($0, FNR, $0); next
  }
  if (entry != "") { scan($0, FNR); next }

  if (sec == "importers" && key($0) && KEY == "@usc/api-client" && KEY_REST == "") {
    entry = "importer"; entry_ind = ind; next
  }
  if (sec == "importers" && index($0, "://")) { fail(LF, FNR, "URL dependency outside the @usc/api-client entry", $0); next }
  if ((sec == "packages" || sec == "snapshots") && ind == 2) {
    if (!key($0)) {
      # Unquoted key: `  name@1.2.3:` or `  name@1.2.3: {}`.
      KEY = substr($0, 3); KEY_REST = ""
      if (sub(/: \{\}$/, "", KEY)) KEY_REST = " {}"
      else if (!sub(/:$/, "", KEY)) { fail(LF, FNR, "malformed " sec " key", $0); next }
    }
  }
  if ((sec == "packages" || sec == "snapshots") && ind == 2 && index(KEY, "@usc/api-client@") != 1 && KEY !~ REG_RE) {
    fail(LF, FNR, sec " key is neither name@<semver>(peers) nor the @usc/api-client entry", $0); next
  }
  if (sec == "packages" && ind == 2 && index(KEY, "@usc/api-client@") != 1) {
    if (KEY_REST != "") { fail(LF, FNR, "registry package entry without its resolution", $0); next }
    oline = FNR; otext = $0; ores = 0; scan($0, FNR); next
  }
  if ((sec == "packages" || sec == "snapshots") && ind == 2 && index(KEY, "@usc/api-client@") == 1) {
    if (KEY_REST != "" && !(sec == "snapshots" && KEY_REST == " {}")) {
      fail(LF, FNR, "unexpected value on the @usc/api-client " sec " key", $0); next
    }
    url(substr(KEY, length("@usc/api-client@") + 1), FNR, $0)
    if (sec == "packages") { npkg++; entry = "package"; entry_ind = ind; pkg_line = FNR }
    else if (KEY_REST == "") { entry = "snapshot"; entry_ind = ind }
    next
  }
  scan($0, FNR)
}
END {
  close_other()
  if (npkg > 1) fail(LF, pkg_line, "more than one @usc/api-client entry under packages:", "")
  if (npkg == 1 && nres != 1) fail(LF, pkg_line, "the @usc/api-client entry needs exactly one valid resolution", "")
  if (nurl > 0 && npkg == 0) fail(LF, url_line[1], "@usc/api-client has no entry under packages:", url_text[1])
  if (spec != "" && npkg == 0) fail(PF, 0, "package.json declares @usc/api-client but the lockfile has no entry for it", "")
  if (nres == 1)
    for (i = 1; i <= nurl; i++)
      if (url_commit[i] != res_commit)
        fail(LF, url_line[i], "commit differs from resolution.commit " res_commit, url_text[i])
  if (errors) {
    printf "%s: %d problem(s): the @usc/api-client entry must follow ADR-013 Amendment 3 (CI.md in SoutienScolaireApp/.github).\n", me, errors > "/dev/stderr"
    exit 1
  }
  if (npkg) printf "%s: OK, @usc/api-client locked to contracts at %s.\n", me, res_commit
  else printf "%s: OK, no @usc/api-client dependency.\n", me
}
'

rc=0
ME=$me PF=$pkg LF=$lock awk "$prog" "$pkg" "$lock" || rc=$?
if [ "$rc" -eq 0 ] && [ "$status" -ne 0 ]; then rc=1; fi
exit "$rc"
