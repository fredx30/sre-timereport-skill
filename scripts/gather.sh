#!/usr/bin/env bash
# Gather the evidence for a monthly time report into TSV/TXT files.
# Usage: gather.sh YYYY-MM [outdir] [--only a,b] [--skip c,d]
#        gather.sh --list
# Pass the session scratchpad as outdir; the default is /tmp/time-report-YYYY-MM.
#
# Runs every scripts/collectors/NN-name.sh in name order. Each collector is standalone
# (same two arguments), checks its own tools, writes its own files into outdir and its own
# summary lines. A collector whose tool is missing records "name=skipped (reason)" and the
# others still run. --only and --skip take comma-separated names; a name matches a
# collector exactly or as a group prefix ("github" covers github-prs, github-reviews, ...).
# Add a source by dropping a new NN-name.sh into collectors/, modelled on an existing one.
# Configuration: header of scripts/lib.sh and scripts/config.example.sh.

DIR="$(cd "$(dirname "$0")" && pwd)"
ONLY=""; SKIP=""; ARGS=()
usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
list() { local c; for c in "$DIR"/collectors/[0-9][0-9]-*.sh; do c="$(basename "$c" .sh)"; echo "${c#[0-9][0-9]-}"; done; }
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="${2:?--only needs a comma-separated list}"; shift 2;;
    --skip) SKIP="${2:?--skip needs a comma-separated list}"; shift 2;;
    --list) list; exit 0;;
    -h|--help) usage;;
    -*) echo "gather.sh: unknown option $1" >&2; usage 2;;
    *) ARGS+=("$1"); shift;;
  esac
done

COLLECTOR=00-header; TR_NAME=gather
. "$DIR/lib.sh"
tr_init "${ARGS[@]}"
rm -f "$OUT"/.summary/*.txt      # stale parts from an earlier run into the same outdir
: > "$OUT/.summary/$COLLECTOR.txt"

# Resolve the GitHub login once; collectors inherit it and still skip cleanly without gh.
if [ -z "$LOGIN" ] && command -v gh >/dev/null 2>&1; then
  LOGIN="$(gh api user --jq .login 2>/dev/null | tr -d '\r')"
fi
export ORG LOGIN JIRA_SEARCH TICKET_RE TICKET_EXCLUDE PROJECT_PREFIX PROJECT_HOME HOLIDAY_NOTE HOME_DIR
export TIME_REPORT_CONFIG="${TIME_REPORT_CONFIG:-}"

matches() { # name list — exact name or group prefix
  local n="$1" i list
  IFS=, read -ra list <<< "$2"
  for i in "${list[@]}"; do
    [ -n "$i" ] || continue
    [ "$n" = "$i" ] && return 0
    [ "${n#"$i"-}" != "$n" ] && return 0
  done
  return 1
}
selected() {
  [ -z "$ONLY" ] || matches "$1" "$ONLY" || return 1
  [ -z "$SKIP" ] || ! matches "$1" "$SKIP" || return 1
  return 0
}

for c in "$DIR"/collectors/[0-9][0-9]-*.sh; do
  base="$(basename "$c" .sh)"; name="${base#[0-9][0-9]-}"
  if selected "$name"; then
    bash "$c" "$MONTH" "$OUT" || say "WARNING: collector $name exited with status $?"
  else
    printf '%s=skipped (by request)\n' "$name" > "$OUT/.summary/$base.txt"
  fi
done

{
  echo "month=$MONTH ($FIRST..$LAST)"
  echo "org=${ORG:-unset} login=${LOGIN:-unset}"
  cat "$OUT"/.summary/[0-9][0-9]-*.txt
  echo
  echo "Still to do by hand: Artifact list (decks/briefings updated in month), MEMORY.md project entries for themes and carry-over."
} > summary.txt

cat summary.txt
say "Files in $OUT"
