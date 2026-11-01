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
# or scp-like host:path URL.
#
# The SSH form is a representation only: CI disables SSH and rewrites both
# forms to authenticated HTTPS. Exit 0 when the files pass, 1 when they do
# not, 2 on a usage error. Offending lines are printed with any URL
# credential redacted.
set -eu

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
  HTTPS_REPO = "https://github.com/SoutienScolaireApp/contracts.git"
  SSH_REPO = "git@github.com:SoutienScolaireApp/contracts.git"
  HTTPS_URL = "git+" HTTPS_REPO
  SSH_URL = "git+ssh://git@github.com/SoutienScolaireApp/contracts.git"
  SPEC_RE = "^git\\+https://github\\.com/SoutienScolaireApp/contracts\\.git#v[0-9]+\\.[0-9]+\\.[0-9]+&path:/clients/typescript$"
}

# --- package.json -----------------------------------------------------------
FILENAME == PF {
  l = tolower($0)
  if (index(l, "git@") || index(l, "ssh://") || index(l, "git+ssh") || index(l, "git://") || index(l, "http://"))
    fail(PF, FNR, "package.json holds a git@, ssh://, git+ssh, git:// or http:// URL", $0)
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
/^[^ ]/ { sec = $0; sub(/:.*/, "", sec); entry = ""; scan($0, FNR); next }
{
  ind = indent($0)
  if (entry != "" && ind <= entry_ind) entry = ""

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
  if ((sec == "packages" || sec == "snapshots") && ind == 2 && key($0) && index(KEY, "@usc/api-client@") == 1) {
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

exec awk -v me="$me" -v PF="$pkg" -v LF="$lock" "$prog" "$pkg" "$lock"
