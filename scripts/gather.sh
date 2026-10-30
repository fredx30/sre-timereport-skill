#!/usr/bin/env bash
# Gather the evidence for a monthly time report into TSV/TXT files.
# Usage: gather.sh YYYY-MM [outdir]   (pass the session scratchpad as outdir)
# Needs: gh (authenticated), jq, GNU coreutils (date -d, find -newermt, stat -c; Git Bash has them).
#
# Configuration (environment variables):
#   ORG             GitHub organisation or user whose repos are searched (required)
#   LOGIN           GitHub login to report on (default: the authenticated gh user)
#   JIRA_SEARCH     command that takes a JQL string as its last argument and prints a
#                   JSON array of issues with key, fields.status.name, fields.summary;
#                   Jira is skipped with a note when unset
#   TICKET_RE       extended regex for ticket keys in PR bodies
#                   (default: generic Jira key \b[A-Z]{2,10}-[0-9]+\b; set it if your
#                   project keys contain digits)
#   TICKET_EXCLUDE  extended regex; matching keys are dropped (default rejects
#                   CVE-, RFC-, SHA-, UTF- and similar non-ticket tokens)
#   PROJECT_PREFIX  prefix stripped from ~/.claude/projects/ directory names in
#                   sessions.tsv, e.g. C--Users-me-work-
#   HOME_DIR        default: $HOME
set -uo pipefail

die() { printf 'gather.sh: %s\n' "$1" >&2; exit "${2:-1}"; }

# Windows jq builds (1.8.x via Scoop/Chocolatey) end every output line with CRLF; strip the CR
# so the TSVs stay clean. pipefail is on, so a jq failure still fails the pipeline.
jq() { command jq "$@" | tr -d '\r'; }

# ---------- Prerequisites ----------
for t in gh jq date find stat awk sed sort; do
  command -v "$t" >/dev/null 2>&1 || die "required tool '$t' not found in PATH" 127
done
date -d 2000-01-01 +%F >/dev/null 2>&1 || die "GNU date is required (date -d); on macOS install coreutils and put gdate first in PATH" 127
gh auth status >/dev/null 2>&1 || die "gh is not authenticated (run gh auth login)" 1

MONTH="${1:?usage: gather.sh YYYY-MM [outdir]}"
[[ $MONTH =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]] || die "MONTH must be YYYY-MM, got '$MONTH'" 2
ORG="${ORG:?set ORG to the GitHub organisation to search}"
LOGIN="${LOGIN:-$(gh api user --jq .login 2>/dev/null)}"
[ -n "$LOGIN" ] || die "could not resolve the GitHub login from gh; set LOGIN explicitly" 1
JIRA_SEARCH="${JIRA_SEARCH:-}"
if [ -n "$JIRA_SEARCH" ]; then
  command -v "${JIRA_SEARCH%% *}" >/dev/null 2>&1 || die "JIRA_SEARCH command '${JIRA_SEARCH%% *}' not found in PATH (unset JIRA_SEARCH to skip Jira)" 127
fi
# Defaults kept in plain variables: a literal } inside ${VAR:-...} would end the expansion.
DEFAULT_TICKET_RE='\b[A-Z]{2,10}-[0-9]+\b'   # letters-only prefix: drops L76-79, Z0-9 style noise
DEFAULT_TICKET_EXCLUDE='^(CVE|UTF|SHA|RFC|ISO|MD|TLS|SSL|AES|RSA|HTTP|GHSA|X|ID)-'
TICKET_RE="${TICKET_RE:-$DEFAULT_TICKET_RE}"
TICKET_EXCLUDE="${TICKET_EXCLUDE:-$DEFAULT_TICKET_EXCLUDE}"
PROJECT_PREFIX="${PROJECT_PREFIX:-}"
HOME_DIR="${HOME_DIR:-$HOME}"

FIRST="$MONTH-01"
LAST="$(date -d "$FIRST +1 month -1 day" +%F)"
NEXT="$(date -d "$FIRST +1 month" +%F)"
OUT="${2:-/tmp/time-report-$MONTH}"
mkdir -p "$OUT" || die "cannot create outdir $OUT"
cd "$OUT" || die "cannot enter outdir $OUT"

say() { printf '%s\n' "$*" >&2; }

LIMIT=1000   # GitHub search API hard cap
LIMIT_HITS=""
check_limit() { # name count
  [ "${2:-0}" -ge "$LIMIT" ] && { say "WARNING: $1 reached --limit $LIMIT, results truncated"; LIMIT_HITS="$LIMIT_HITS $1"; }
  return 0
}

# ---------- PRs ----------
say "PRs opened in $MONTH"
gh search prs --author="$LOGIN" --owner="$ORG" --created="$FIRST..$LAST" --limit "$LIMIT" \
  --json repository,number,state,isDraft,createdAt,closedAt,title,url,body > .prs-opened.json
jq -r '.[] | [.repository.name, .number, .state, (.isDraft|tostring), .createdAt[:10], ((.closedAt//"")[:10]), .title, .url] | @tsv' .prs-opened.json \
  | sort -k5,5 -k1,1 > prs-opened.tsv
check_limit prs-opened "$(jq length .prs-opened.json 2>/dev/null || echo 0)"

say "PRs merged in $MONTH (any open date)"
gh search prs --author="$LOGIN" --owner="$ORG" --merged-at="$FIRST..$LAST" --limit "$LIMIT" \
  --json repository,number,createdAt,closedAt,title,url,body > .prs-merged.json
jq -r '.[] | [.repository.name, .number, .createdAt[:10], .closedAt[:10], .title, .url] | @tsv' .prs-merged.json \
  | sort -k4,4 > prs-merged.tsv
check_limit prs-merged "$(jq length .prs-merged.json 2>/dev/null || echo 0)"

say "PRs closed unmerged in $MONTH"
# gh's --merged flag only adds is:merged when true, so merged PRs cannot be excluded in the
# search itself; fetch everything closed in the month and subtract prs-merged.tsv.
gh search prs --author="$LOGIN" --owner="$ORG" --closed="$FIRST..$LAST" --limit "$LIMIT" \
  --json repository,number,state,createdAt,closedAt,title,url \
  --jq '.[] | select(.state=="closed") | [.repository.name, .number, .createdAt[:10], .closedAt[:10], .title, .url] | @tsv' \
  | sort -k4,4 > .prs-closed.tsv
check_limit prs-closed "$(wc -l < .prs-closed.tsv)"
awk -F'\t' 'NR==FNR{m[$1"\t"$2]=1;next} !($1"\t"$2 in m)' prs-merged.tsv .prs-closed.tsv > prs-closed-unmerged.tsv
rm -f .prs-closed.tsv

say "All currently open PRs by $LOGIN"
gh search prs --author="$LOGIN" --owner="$ORG" --state=open --limit "$LIMIT" \
  --json repository,number,createdAt,isDraft,title,url \
  --jq '.[] | [.repository.name, .number, .createdAt[:10], (.isDraft|tostring), .title, .url] | @tsv' \
  | sort -k3,3 > prs-open-all.tsv
check_limit prs-open-all "$(wc -l < prs-open-all.tsv)"

# ---------- Reviews (dated by submitted_at, not by PR update) ----------
# Candidates are every PR the user ever reviewed that was updated on or after the month
# start: a PR reviewed in-month can be merged (= updated) next month, so an upper bound on
# --updated would drop it. The submitted_at filter below bounds the month on both ends.
say "Reviews submitted in $MONTH"
gh search prs --reviewed-by="$LOGIN" --owner="$ORG" --updated=">=$FIRST" --limit "$LIMIT" \
  --json repository,number,author,title,url \
  --jq ".[] | select(.author.login!=\"$LOGIN\") | [.repository.name, .number, .author.login, .title, .url] | @tsv" \
  > .review-candidates.tsv
check_limit review-candidates "$(wc -l < .review-candidates.tsv)"
: > reviews.tsv
while IFS=$'\t' read -r repo num author title url; do
  gh api --paginate "repos/$ORG/$repo/pulls/$num/reviews" \
    --jq ".[] | select(.user.login==\"$LOGIN\") | select(.submitted_at >= \"$FIRST\" and .submitted_at < \"$NEXT\") | [.submitted_at[:10], .state] | @tsv" 2>/dev/null \
    | sort -u | while IFS=$'\t' read -r d st; do
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$d" "$repo" "$num" "$author" "$st" "$title" >> reviews.tsv
      done
done < .review-candidates.tsv
rm -f .review-candidates.tsv
sort -o reviews.tsv reviews.tsv

# ---------- Commits ----------
say "Commits authored in $MONTH"
gh search commits --author="$LOGIN" --owner="$ORG" --author-date="$FIRST..$LAST" --limit "$LIMIT" \
  --json repository,commit \
  --jq '.[] | [.commit.author.date[:10], .repository.name, (.commit.message | split("\n")[0])] | @tsv' \
  > .commits.raw
check_limit commits "$(wc -l < .commits.raw)"
sort -u .commits.raw > commits.tsv
rm -f .commits.raw

# ---------- Event stream (limited window) ----------
say "Event stream (up to 300 events)"
# GitHub serves at most ~300 events (3 pages); later pages return an error object, so keep only arrays.
for p in 1 2 3 4; do gh api "users/$LOGIN/events?per_page=100&page=$p" 2>/dev/null; done \
  | jq -c 'select(type=="array") | .[]' > .events.jsonl
# Columns: count, date, type, repo, action, ref/number. uniq -c prefixes "<spaces><count> ";
# turn that into a tab so the remaining tab-separated columns stay intact (empty ones too).
jq -r --arg a "$FIRST" --arg b "$NEXT" 'select(.created_at >= $a and .created_at < $b) |
    [.created_at[:10], .type, .repo.name, (.payload.action // ""), ((.payload.pull_request.number // .payload.issue.number // .payload.ref // "") | tostring)] | @tsv' .events.jsonl \
  | sort | uniq -c | sed 's/^ *\([0-9][0-9]*\) /\1\t/' > events.tsv
# A lone stray event can predate the real window by weeks; report the first day with >=2 events as the usable start.
OLDEST_EVENT="$(jq -r '.created_at[:10]' .events.jsonl | sort | uniq -c | awk '$1>=2{print $2; exit}')"; OLDEST_EVENT="${OLDEST_EVENT:-unknown}"
rm -f .events.jsonl

# ---------- Local sessions ----------
say "Local Claude sessions"
find "$HOME_DIR/.claude/projects" -maxdepth 2 -name '*.jsonl' -newermt "$FIRST" ! -newermt "$NEXT" -not -path '*AppData*' 2>/dev/null \
  | while read -r f; do
      d="$(stat -c %y "$f" | cut -c1-10)"
      p="$(printf '%s' "$f" | sed "s#.*/\.claude/projects/##; s#/[^/]*\$##")"
      [ -n "$PROJECT_PREFIX" ] && p="${p#"$PROJECT_PREFIX"}"
      # First user message that is real prompt text: skip tool results, slash-command
      # caveats and other harness-generated content so sessions started with a slash
      # command are not lost.
      m="$(grep '"type":"user"' "$f" | jq -r '
            (.message.content // "")
            | if type=="string" then . else ([.[]? | select(.type=="text") | .text] | join(" ")) end
            | gsub("\\s+"; " ") | ltrimstr(" ")
            | select(length>0)
            | select(test("^<(local-command|command-|system-reminder|bash-|task-notification)")|not)' 2>/dev/null \
          | head -n1 | cut -c1-160)"
      [ -z "$m" ] && m="(no prompt text)"
      printf '%s\t%s\t%s\n' "$d" "$p" "$m"
    done | sort > sessions.tsv

# ---------- Home docs ----------
say "~/*.md modified in $MONTH"
find "$HOME_DIR" -maxdepth 1 -name '*.md' -newermt "$FIRST" ! -newermt "$NEXT" -printf '%TY-%Tm-%Td\t%f\n' 2>/dev/null | sort > home-docs.tsv

# ---------- Ticket keys cited in PR bodies ----------
# Bodies came with the opened/merged searches above; @tsv escapes newlines so one PR per line.
say "Ticket keys in PR bodies"
jq -r '.[] | [.repository.name, .number, (.body // "")] | @tsv' .prs-opened.json .prs-merged.json \
  | sort -u -t$'\t' -k1,2 | while IFS=$'\t' read -r repo num body; do
      keys="$(printf '%s' "$body" | grep -oE "$TICKET_RE" | grep -vE "$TICKET_EXCLUDE" | sort -u | tr '\n' ' ')"
      [ -n "$keys" ] && printf '%s\t%s\t%s\n' "$repo" "$num" "$keys"
    done > pr-jira-keys.tsv
rm -f .prs-opened.json .prs-merged.json

# ---------- Jira, weekly buckets ----------
say "Jira weekly buckets"
if [ -n "$JIRA_SEARCH" ]; then
  jira() { $JIRA_SEARCH "$1" 2>/dev/null | jq -r '.[] | [.key, .fields.status.name, .fields.summary[:80]] | @tsv' 2>/dev/null || echo "(query failed)"; }
  {
    d="$FIRST"
    while [ "$d" \< "$NEXT" ]; do
      # bucket end = next Monday or month end
      e="$d"
      while :; do e="$(date -d "$e +1 day" +%F)"; [ "$(date -d "$e" +%u)" = 1 ] && break; [ "$e" = "$NEXT" ] && break; done
      echo "== $d .. $(date -d "$e -1 day" +%F) =="
      echo "-- assigned to me, updated:"
      jira "assignee = currentUser() AND updated >= '$d' AND updated < '$e'"
      echo "-- status changed by me:"
      # JQL DURING is inclusive at both ends, so stop one day short of the next bucket start.
      jira "status CHANGED BY currentUser() DURING ('$d', '$(date -d "$e -1 day" +%F)')"
      echo
      d="$e"
    done
  } > jira-weekly.txt 2>&1
  JIRA_NOTE="jira-weekly.txt written (empty buckets mean no updates, '(query failed)' means auth/connectivity)"
else
  JIRA_NOTE="JIRA_SEARCH not set — Jira skipped, write the Jira caveat in the report"
  : > jira-weekly.txt
fi

# ---------- Working days ----------
{
  n=0; d="$FIRST"
  while [ "$d" \< "$NEXT" ]; do
    [ "$(date -d "$d" +%u)" -le 5 ] && n=$((n+1))
    d="$(date -d "$d +1 day" +%F)"
  done
  echo "weekdays_in_month=$n"
  echo "first_weekday=$(date -d "$FIRST" +%a)"
  echo "note=subtract public holidays on weekdays and confirmed vacation; see references/format.md"
} > workdays.txt

# ---------- Summary ----------
opened=$(wc -l < prs-opened.tsv); merged=$(wc -l < prs-merged.tsv)
merged_from_month=$(awk -F'\t' -v a="$FIRST" '$3 >= a' prs-merged.tsv | wc -l)
repos=$(cut -f1 prs-merged.tsv | sort -u | wc -l)
still_open=$(awk -F'\t' '$3=="open"' prs-opened.tsv | wc -l)
reviews=$(cut -f2,3 reviews.tsv | sort -u | wc -l)
{
  echo "month=$MONTH ($FIRST..$LAST)"
  echo "org=$ORG login=$LOGIN"
  echo "prs_opened=$opened"
  echo "prs_merged=$merged (opened this month: $merged_from_month, carried over: $((merged-merged_from_month))) across $repos repos"
  echo "prs_opened_still_open=$still_open"
  echo "prs_closed_unmerged=$(wc -l < prs-closed-unmerged.tsv)"
  echo "prs_by_others_reviewed=$reviews (distinct PRs, reviews submitted in month)"
  echo "commits=$(wc -l < commits.tsv)"
  echo "limit_hit=${LIMIT_HITS:-none}"
  echo "event_stream_dense_from=$OLDEST_EVENT (state this cutoff in the report's Sources line when it is inside the month)"
  echo "sessions=$(wc -l < sessions.tsv)"
  echo "home_docs=$(wc -l < home-docs.tsv)"
  echo "jira=$JIRA_NOTE"
  cat workdays.txt
  echo
  echo "Still to do by hand: Artifact list (decks/briefings updated in month), MEMORY.md project entries for themes and carry-over."
} > summary.txt

cat summary.txt
say "Files in $OUT"
