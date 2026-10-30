#!/usr/bin/env bash
# Collector: Jira tickets assigned to the user and updated, and status changes made by the
# user, in weekly buckets (Monday to Sunday, clipped to the month).
# Needs: jq and the command in JIRA_SEARCH (takes a JQL string as its last argument, prints a
#        JSON array of issues with key, fields.status.name, fields.summary).
# Writes: jira-weekly.txt   "== from .. to ==" blocks with two TSV lists each
. "$(dirname "$0")/../lib.sh"; tr_init "$@"
[ -n "$JIRA_SEARCH" ] || skip "JIRA_SEARCH not set; write the Jira caveat in the report"
require_tools jq "${JIRA_SEARCH%% *}"

jira() { $JIRA_SEARCH "$1" 2>/dev/null | jq -r '.[] | [.key, .fields.status.name, .fields.summary[:80]] | @tsv' 2>/dev/null || echo "(query failed)"; }

say "Jira weekly buckets"
{
  d="$FIRST"
  while [ "$d" \< "$NEXT" ]; do
    # bucket end = next Monday or month end (exclusive)
    e="$d"
    while :; do e="$(date -d "$e +1 day" +%F)"; [ "$(date -d "$e" +%u)" = 1 ] && break; [ "$e" = "$NEXT" ] && break; done
    last="$(date -d "$e -1 day" +%F)"
    echo "== $d .. $last =="
    echo "-- assigned to me, updated:"
    jira "assignee = currentUser() AND updated >= '$d' AND updated < '$e'"
    echo "-- status changed by me:"
    # JQL DURING is inclusive at both ends, so stop one day short of the next bucket start.
    jira "status CHANGED BY currentUser() DURING ('$d', '$last')"
    echo
    d="$e"
  done
} > jira-weekly.txt 2>&1

if grep -q '(query failed)' jira-weekly.txt; then
  note "jira=jira-weekly.txt written with '(query failed)' buckets: check auth/connectivity, write the Jira caveat"
else
  note "jira=jira-weekly.txt written (empty buckets mean no updates)"
fi
