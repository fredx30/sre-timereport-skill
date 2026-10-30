#!/usr/bin/env bash
# Collector: weekday count for the month, the base of the hours estimate.
# Needs: GNU date only.  Config: HOLIDAY_NOTE.
# Writes: workdays.txt   weekdays_in_month, first_weekday, note
. "$(dirname "$0")/../lib.sh"; tr_init "$@"

say "Working days"
{
  n=0; d="$FIRST"
  while [ "$d" \< "$NEXT" ]; do
    [ "$(date -d "$d" +%u)" -le 5 ] && n=$((n+1))
    d="$(date -d "$d +1 day" +%F)"
  done
  echo "weekdays_in_month=$n"
  echo "first_weekday=$(date -d "$FIRST" +%a)"
  echo "note=$HOLIDAY_NOTE"
} > workdays.txt

while IFS= read -r line; do note "$line"; done < workdays.txt
