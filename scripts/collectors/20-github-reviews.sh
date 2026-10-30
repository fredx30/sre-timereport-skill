#!/usr/bin/env bash
# Collector: reviews LOGIN submitted in the month on other people's PRs in ORG.
# Needs: gh (authenticated), jq.  Config: ORG, LOGIN.
# Writes: reviews.tsv   date, repo, number, author, state, title   (one row per review day and state)
#
# Candidates are every PR the user ever reviewed that was updated on or after the month
# start: a PR reviewed in-month can be merged (= updated) next month, so an upper bound on
# --updated would drop it. Each review is then dated by its own submitted_at, which bounds
# the month on both ends; a plain --reviewed-by search would over-count.
. "$(dirname "$0")/../lib.sh"; tr_init "$@"
require_github

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

note "prs_by_others_reviewed=$(cut -f2,3 reviews.tsv | sort -u | wc -l) (distinct PRs, reviews submitted in month)"
