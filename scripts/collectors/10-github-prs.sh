#!/usr/bin/env bash
# Collector: PRs authored by LOGIN in ORG, and the ticket keys their bodies cite.
# Needs: gh (authenticated), jq.  Config: ORG, LOGIN, TICKET_RE, TICKET_EXCLUDE.
# Writes: prs-opened.tsv      repo, number, state, draft, opened, closed, title, url
#         prs-merged.tsv      repo, number, opened, merged, title, url   (merged in month, any open date)
#         prs-closed-unmerged.tsv  same columns as prs-merged.tsv
#         prs-open-all.tsv    repo, number, opened, draft, title, url    (currently open, any date)
#         pr-jira-keys.tsv    repo, number, space-separated keys
. "$(dirname "$0")/../lib.sh"; tr_init "$@"
require_github

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

say "Ticket keys in PR bodies"
# Bodies came with the two searches above; @tsv escapes newlines so one PR per line.
jq -r '.[] | [.repository.name, .number, (.body // "")] | @tsv' .prs-opened.json .prs-merged.json \
  | sort -u -t$'\t' -k1,2 | while IFS=$'\t' read -r repo num body; do
      keys="$(printf '%s' "$body" | grep -oE "$TICKET_RE" | grep -vE "$TICKET_EXCLUDE" | sort -u | tr '\n' ' ')"
      [ -n "$keys" ] && printf '%s\t%s\t%s\n' "$repo" "$num" "$keys"
    done > pr-jira-keys.tsv
rm -f .prs-opened.json .prs-merged.json

opened=$(wc -l < prs-opened.tsv); merged=$(wc -l < prs-merged.tsv)
merged_from_month=$(awk -F'\t' -v a="$FIRST" '$3 >= a' prs-merged.tsv | wc -l)
repos=$(cut -f1 prs-merged.tsv | sort -u | wc -l)
note "prs_opened=$opened"
note "prs_merged=$merged (opened this month: $merged_from_month, carried over: $((merged-merged_from_month))) across $repos repos"
note "prs_opened_still_open=$(awk -F'\t' '$3=="open"' prs-opened.tsv | wc -l)"
note "prs_closed_unmerged=$(wc -l < prs-closed-unmerged.tsv)"
note "prs_with_ticket_keys=$(wc -l < pr-jira-keys.tsv)"
