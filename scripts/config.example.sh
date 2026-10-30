# Local configuration for the gather collectors.
# Copy to scripts/config.local.sh (gitignored), or point TIME_REPORT_CONFIG at your copy.
# It is sourced by scripts/lib.sh after the environment, so use ": ${VAR:=value}" and the
# environment still wins. Variable meanings: header of scripts/lib.sh.

: "${ORG:=my-org}"
# : "${LOGIN:=my-login}"                          # default: the authenticated gh user

# Jira CLI; the JQL string is appended as the last argument. Unset = jira collector skipped.
# : "${JIRA_SEARCH:=mycli issue search --limit 100 --output json --jql}"

# Explicit project keys beat the generic default when you know them. Plain assignment here:
# a literal } inside ${VAR:=...} would end the expansion.
# [ -n "${TICKET_RE:-}" ] || TICKET_RE='\b(PROJ|OPS)-[0-9]+\b'

# ~/.claude/projects/ directory names are the working directory with separators replaced by
# "-". Prefixes are tried in order, first match is stripped; PROJECT_HOME is shown as "home".
# : "${PROJECT_PREFIX:=C--Users-me-work-:C--Users-me-}"
# : "${PROJECT_HOME:=C--Users-me}"

# : "${HOLIDAY_NOTE:=subtract Swedish public holidays on weekdays and confirmed vacation; see references/format.md}"
