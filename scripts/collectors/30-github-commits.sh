#!/usr/bin/env bash
# Collector: commits authored by LOGIN in ORG during the month (days with work but no PR event).
# Needs: gh (authenticated), jq.  Config: ORG, LOGIN.
# Writes: commits.tsv   date, repo, first line of the message
. "$(dirname "$0")/../lib.sh"; tr_init "$@"
require_github

say "Commits authored in $MONTH"
gh search commits --author="$LOGIN" --owner="$ORG" --author-date="$FIRST..$LAST" --limit "$LIMIT" \
  --json repository,commit \
  --jq '.[] | [.commit.author.date[:10], .repository.name, (.commit.message | split("\n")[0])] | @tsv' \
  > .commits.raw
check_limit commits "$(wc -l < .commits.raw)"
sort -u .commits.raw > commits.tsv
rm -f .commits.raw

note "commits=$(wc -l < commits.tsv)"
