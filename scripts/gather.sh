#!/usr/bin/env bash
# Gather the evidence for a monthly time report into TSV/TXT files.
# Usage: gather.sh YYYY-MM [outdir]
# Needs: gh (authenticated), jq, GNU date (Git Bash has it).
#
# Configuration (environment variables):
#   ORG             GitHub organisation or user whose repos are searched (required)
#   LOGIN           GitHub login to report on (default: the authenticated gh user)
#   JIRA_SEARCH     command that takes a JQL string as its last argument and prints a
#                   JSON array of issues with key, fields.status.name, fields.summary;
#                   Jira is skipped with a note when unset
#   TICKET_RE       extended regex for ticket keys in PR bodies
#                   (default: generic Jira key [A-Z][A-Z0-9]+-[0-9]+)
#   PROJECT_PREFIX  prefix stripped from ~/.claude/projects/ directory names in
#                   sessions.tsv, e.g. C--Users-me-work-
#   HOME_DIR        default: $HOME
set -uo pipefail

MONTH="${1:?usage: gather.sh YYYY-MM [outdir]}"
ORG="${ORG:?set ORG to the GitHub organisation to search}"
LOGIN="${LOGIN:-$(gh api user --jq .login)}"
JIRA_SEARCH="${JIRA_SEARCH:-}"
TICKET_RE="${TICKET_RE:-[A-Z][A-Z0-9]+-[0-9]+}"
PROJECT_PREFIX="${PROJECT_PREFIX:-}"
HOME_DIR="${HOME_DIR:-$HOME}"

FIRST="$MONTH-01"
LAST="$(date -d "$FIRST +1 month -1 day" +%F)"
NEXT="$(date -d "$FIRST +1 month" +%F)"
OUT="${2:-${CLAUDE_SCRATCHPAD:-/tmp}/time-report-$MONTH}"
mkdir -p "$OUT"
cd "$OUT" || exit 1

say() { printf '%s\n' "$*" >&2; }

# ---------- PRs ----------
say "PRs opened in $MONTH"
gh search prs --author="$LOGIN" --owner="$ORG" --created="$FIRST..$LAST" --limit 200 \
  --json repository,number,state,isDraft,createdAt,closedAt,title,url \
  --jq '.[] | [.repository.name, .number, .state, (.isDraft|tostring), .createdAt[:10], ((.closedAt//"")[:10]), .title, .url] | @tsv' \
  | sort -k5,5 -k1,1 > prs-opened.tsv

say "PRs merged in $MONTH (any open date)"
gh search prs --author="$LOGIN" --owner="$ORG" --merged-at="$FIRST..$LAST" --limit 200 \
  --json repository,number,createdAt,closedAt,title,url \
  --jq '.[] | [.repository.name, .number, .createdAt[:10], .closedAt[:10], .title, .url] | @tsv' \
  | sort -k4,4 > prs-merged.tsv

say "PRs closed unmerged in $MONTH"
gh search prs --author="$LOGIN" --owner="$ORG" --closed="$FIRST..$LAST" --limit 200 \
  --json repository,number,state,createdAt,closedAt,title,url \
  --jq '.[] | select(.state=="closed") | [.repository.name, .number, .createdAt[:10], .closedAt[:10], .title, .url] | @tsv' \
  | sort -k4,4 > prs-closed-unmerged.tsv
# gh reports merged PRs as "closed"; drop the ones in prs-merged.tsv
awk -F'\t' 'NR==FNR{m[$1"\t"$2]=1;next} !($1"\t"$2 in m)' prs-merged.tsv prs-closed-unmerged.tsv > .tmp && mv .tmp prs-closed-unmerged.tsv

say "All currently open PRs by $LOGIN"
gh search prs --author="$LOGIN" --owner="$ORG" --state=open --limit 200 \
  --json repository,number,createdAt,isDraft,title,url \
  --jq '.[] | [.repository.name, .number, .createdAt[:10], (.isDraft|tostring), .title, .url] | @tsv' \
  | sort -k3,3 > prs-open-all.tsv

# ---------- Reviews (dated by submitted_at, not by PR update) ----------
say "Reviews submitted in $MONTH"
: > reviews.tsv
gh search prs --reviewed-by="$LOGIN" --owner="$ORG" --updated="$FIRST..$LAST" --limit 200 \
  --json repository,number,author,title,url \
  --jq ".[] | select(.author.login!=\"$LOGIN\") | [.repository.name, .number, .author.login, .title, .url] | @tsv" \
  | while IFS=$'\t' read -r repo num author title url; do
      gh api "repos/$ORG/$repo/pulls/$num/reviews" \
        --jq ".[] | select(.user.login==\"$LOGIN\") | select(.submitted_at >= \"$FIRST\" and .submitted_at < \"$NEXT\") | [.submitted_at[:10], .state] | @tsv" 2>/dev/null \
        | sort -u | while IFS=$'\t' read -r d st; do
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$d" "$repo" "$num" "$author" "$st" "$title" >> reviews.tsv
          done
    done
sort -o reviews.tsv reviews.tsv

# ---------- Commits ----------
say "Commits authored in $MONTH"
gh search commits --author="$LOGIN" --owner="$ORG" --author-date="$FIRST..$LAST" --limit 300 \
  --json repository,commit \
  --jq '.[] | [.commit.author.date[:10], .repository.name, (.commit.message | split("\n")[0])] | @tsv' \
  | sort -u > commits.tsv

# ---------- Event stream (limited window) ----------
say "Event stream (up to 300 events)"
# GitHub serves at most ~300 events (3 pages); later pages return an error object, so keep only arrays.
for p in 1 2 3 4; do gh api "users/$LOGIN/events?per_page=100&page=$p" 2>/dev/null; done \
  | jq -c 'select(type=="array") | .[]' > .events.jsonl
jq -r --arg a "$FIRST" --arg b "$NEXT" 'select(.created_at >= $a and .created_at < $b) |
    [.created_at[:10], .type, .repo.name, (.payload.action // ""), ((.payload.pull_request.number // .payload.issue.number // .payload.ref // "") | tostring)] | @tsv' .events.jsonl \
  | sort | uniq -c | awk '{$1=$1};1' > events.tsv
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
      m="$(grep -m1 '"type":"user"' "$f" | jq -r '.message.content | if type=="string" then . else (map(select(.type=="text")|.text)|join(" ")) end' 2>/dev/null | tr '\n' ' ' | cut -c1-160)"
      case "$m" in "<local-command-caveat>"*|"<command-message>"*|"") continue;; esac
      printf '%s\t%s\t%s\n' "$d" "$p" "$m"
    done | sort > sessions.tsv

# ---------- Home docs ----------
say "~/*.md modified in $MONTH"
find "$HOME_DIR" -maxdepth 1 -name '*.md' -newermt "$FIRST" ! -newermt "$NEXT" -printf '%TY-%Tm-%Td\t%f\n' 2>/dev/null | sort > home-docs.tsv

# ---------- Ticket keys cited in PR bodies ----------
say "Ticket keys in PR bodies"
{ cut -f1,2 prs-opened.tsv; cut -f1,2 prs-merged.tsv; } | sort -u | while IFS=$'\t' read -r repo num; do
  keys="$(gh api "repos/$ORG/$repo/pulls/$num" --jq '.body // ""' 2>/dev/null | grep -oE "$TICKET_RE" | sort -u | tr '\n' ' ')"
  [ -n "$keys" ] && printf '%s\t%s\t%s\n' "$repo" "$num" "$keys"
done > pr-jira-keys.tsv

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
      jira "status CHANGED BY currentUser() DURING ('$d', '$e')"
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
