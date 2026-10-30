#!/usr/bin/env bash
# Collector: LOGIN's public GitHub event stream (review comments, pushes, branch churn).
# Needs: gh (authenticated), jq.  Config: LOGIN.
# Writes: events.tsv   count, date, type, repo, action, ref/number
# GitHub serves at most ~300 events, so the usable window often starts inside the month;
# event_stream_dense_from in the summary says where, state it in the report's Sources line.
. "$(dirname "$0")/../lib.sh"; tr_init "$@"
require_github

say "Event stream (up to 300 events)"
# Later pages return an error object instead of an array, so keep only arrays.
for p in 1 2 3 4; do gh api "users/$LOGIN/events?per_page=100&page=$p" 2>/dev/null; done \
  | jq -c 'select(type=="array") | .[]' > .events.jsonl
# uniq -c prefixes "<spaces><count> "; turn that into a tab so the remaining tab-separated
# columns stay intact (empty ones too).
jq -r --arg a "$FIRST" --arg b "$NEXT" 'select(.created_at >= $a and .created_at < $b) |
    [.created_at[:10], .type, .repo.name, (.payload.action // ""), ((.payload.pull_request.number // .payload.issue.number // .payload.ref // "") | tostring)] | @tsv' .events.jsonl \
  | sort | uniq -c | sed 's/^ *\([0-9][0-9]*\) /\1\t/' > events.tsv
# A lone stray event can predate the real window by weeks; report the first day with >=2 events as the usable start.
OLDEST_EVENT="$(jq -r '.created_at[:10]' .events.jsonl | sort | uniq -c | awk '$1>=2{print $2; exit}')"
rm -f .events.jsonl

note "events_in_month=$(wc -l < events.tsv)"
note "event_stream_dense_from=${OLDEST_EVENT:-unknown} (state this cutoff in the report's Sources line when it is inside the month)"
