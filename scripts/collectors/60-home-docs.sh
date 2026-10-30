#!/usr/bin/env bash
# Collector: markdown files in the home directory modified during the month (the Docs table).
# Needs: GNU find.  Config: HOME_DIR.
# Writes: home-docs.tsv   date, file name
. "$(dirname "$0")/../lib.sh"; tr_init "$@"

say "~/*.md modified in $MONTH"
find "$HOME_DIR" -maxdepth 1 -name '*.md' -newermt "$FIRST" ! -newermt "$NEXT" -printf '%TY-%Tm-%Td\t%f\n' 2>/dev/null | sort > home-docs.tsv

note "home_docs=$(wc -l < home-docs.tsv)"
