#!/usr/bin/env bash
# lib.sh — shared helpers for gather.sh and the collectors. Source it, do not run it:
#   . "$(dirname "$0")/../lib.sh"; tr_init "$@"
#
# Configuration, read from the environment first, then from scripts/config.local.sh
# (or the file named by TIME_REPORT_CONFIG), see config.example.sh:
#   ORG             GitHub organisation or user whose repos are searched (github-* collectors)
#   LOGIN           GitHub login to report on (default: the authenticated gh user)
#   JIRA_SEARCH     command that takes a JQL string as its last argument and prints a JSON
#                   array of issues with key, fields.status.name, fields.summary;
#                   the jira collector is skipped with a note when unset
#   TICKET_RE       extended regex for ticket keys in PR bodies
#                   (default: generic Jira key \b[A-Z]{2,10}-[0-9]+\b; set it if your
#                   project keys contain digits, or to an explicit list of projects)
#   TICKET_EXCLUDE  extended regex; matching keys are dropped (default rejects CVE-, RFC-,
#                   SHA-, UTF- and similar non-ticket tokens)
#   PROJECT_PREFIX  colon-separated prefixes stripped from ~/.claude/projects/ directory
#                   names in sessions.tsv, first match wins, e.g. C--Users-me-work-:C--Users-me-
#   PROJECT_HOME    project directory name shown as "home" in sessions.tsv, e.g. C--Users-me
#   HOLIDAY_NOTE    note line written to workdays.txt
#   HOME_DIR        default: $HOME
set -uo pipefail

TR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_tr_name() { printf '%s' "${TR_NAME:-${COLLECTOR#[0-9][0-9]-}}"; }
die() { printf '%s: %s\n' "$(_tr_name)" "$1" >&2; exit "${2:-1}"; }
say() { printf '[%s] %s\n' "$(_tr_name)" "$*" >&2; }

# Windows jq builds (1.8.x via Scoop/Chocolatey) end every output line with CRLF; strip the CR
# so the TSVs stay clean. pipefail is on, so a jq failure still fails the pipeline.
jq() { command jq "$@" | tr -d '\r'; }

LIMIT=1000   # GitHub search API hard cap
check_limit() { # name count — records a summary line when a search is truncated
  [ "${2:-0}" -ge "$LIMIT" ] && { say "WARNING: $1 reached --limit $LIMIT, results truncated"; note "limit_hit=$1"; }
  return 0
}

# Summary lines: each collector appends to its own part under $OUT/.summary/ and gather.sh
# concatenates the parts in collector order into summary.txt.
note() { printf '%s\n' "$*" >> "$OUT/.summary/$COLLECTOR.txt"; }

# Leave this collector out, record why, and let the rest of the run continue.
skip() { note "${COLLECTOR#[0-9][0-9]-}=skipped ($1)"; say "skipped: $1"; exit 0; }

# Install hint per tool, shown in every "missing tool" skip so the user can fix the gap
# without opening the docs. Windows package managers first, then macOS/Linux. Keep in sync with the Prerequisites section of SKILL.md.
tool_hint() {
  case "$1" in
    gh)   echo "GitHub CLI — scoop install gh | winget install GitHub.cli | brew install gh | apt install gh; then: gh auth login" ;;
    jq)   echo "jq — scoop install jq | winget install jqlang.jq | brew install jq | apt install jq" ;;
    npx|node|npm) echo "Node.js (ships npx) — choco install nodejs-lts | winget install OpenJS.NodeJS.LTS | brew install node | apt install nodejs npm" ;;
    stat|find|date|sort|awk|sed|grep|cut|tr) echo "GNU coreutils/findutils — on Windows run from Git Bash (Git for Windows) | brew install coreutils findutils (then use g-prefixed names or gnubin) | preinstalled on Linux" ;;
    python|python3) echo "Python 3 — scoop install python | winget install Python.Python.3 | brew install python | apt install python3" ;;
    *)    echo "see Prerequisites in SKILL.md" ;;
  esac
}
missing() { skip "missing tool: $1 — install: $(tool_hint "$1")"; }   # skip with the install hint
require_tools() { local t; for t in "$@"; do command -v "$t" >/dev/null 2>&1 || missing "$t"; done; }

# gh present and authenticated, ORG set, LOGIN resolvable; otherwise skip.
require_github() {
  require_tools gh jq
  gh auth status >/dev/null 2>&1 || skip "gh is not authenticated — run: gh auth login (then re-run)"
  [ -n "${ORG:-}" ] || skip "ORG is not set"
  LOGIN="${LOGIN:-$(gh api user --jq .login 2>/dev/null | tr -d '\r')}"
  [ -n "$LOGIN" ] || skip "could not resolve the GitHub login; set LOGIN"
}

tr_init() { # MONTH [outdir]
  COLLECTOR="${COLLECTOR:-$(basename "$0" .sh)}"
  MONTH="${1:?usage: $(basename "$0") YYYY-MM [outdir]}"
  [[ $MONTH =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]] || die "MONTH must be YYYY-MM, got '$MONTH'" 2
  local t
  for t in date find sort awk sed grep cut tr; do
    command -v "$t" >/dev/null 2>&1 || die "required tool '$t' not found in PATH — install: $(tool_hint "$t")" 127
  done
  date -d 2000-01-01 +%F >/dev/null 2>&1 || die "GNU date is required (date -d) — install: $(tool_hint date)" 127

  local cfg="${TIME_REPORT_CONFIG:-$TR_LIB_DIR/config.local.sh}"
  [ -f "$cfg" ] && . "$cfg"
  ORG="${ORG:-}"; LOGIN="${LOGIN:-}"; JIRA_SEARCH="${JIRA_SEARCH:-}"
  HOME_DIR="${HOME_DIR:-$HOME}"; PROJECT_PREFIX="${PROJECT_PREFIX:-}"; PROJECT_HOME="${PROJECT_HOME:-}"
  HOLIDAY_NOTE="${HOLIDAY_NOTE:-subtract public holidays on weekdays and confirmed vacation; see references/format.md}"
  # Defaults kept in plain variables: a literal } inside ${VAR:-...} would end the expansion.
  local def_re='\b[A-Z]{2,10}-[0-9]+\b'
  local def_ex='^(CVE|UTF|SHA|RFC|ISO|MD|TLS|SSL|AES|RSA|HTTP|GHSA|X|ID)-'
  TICKET_RE="${TICKET_RE:-$def_re}"; TICKET_EXCLUDE="${TICKET_EXCLUDE:-$def_ex}"

  FIRST="$MONTH-01"
  LAST="$(date -d "$FIRST +1 month -1 day" +%F)"
  NEXT="$(date -d "$FIRST +1 month" +%F)"
  OUT="${2:-/tmp/time-report-$MONTH}"
  mkdir -p "$OUT/.summary" || die "cannot create outdir $OUT"
  OUT="$(cd "$OUT" && pwd)" || die "cannot enter outdir $OUT"
  cd "$OUT" || die "cannot enter outdir $OUT"
  : > "$OUT/.summary/$COLLECTOR.txt"
}
