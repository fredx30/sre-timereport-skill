# sre-timereport-skill

A Claude Code skill that reconstructs a calendar month of work from auditable sources
(GitHub PRs, reviews, commits and events, Jira via a configurable CLI, local Claude
session activity, `~/*.md` drafts, published artifacts) and writes two flat markdown
files in `~`:

- `monthly-report-YYYY-MM.md`: ISO-week-by-week report with linked PRs, a Jira table,
  docs handled, carry-over, and a working-days / hours estimate.
- `daily-log-YYYY-MM.md`: one entry per calendar day, 1–31.

Every claim in the output is traceable to a PR link, ticket key, file path, or an
explicit "not recoverable" caveat.

## Layout

| Path | Purpose |
|---|---|
| `SKILL.md` | Skill entry point: trigger description, configuration, five-step workflow |
| `scripts/gather.sh` | Orchestrator. `gather.sh YYYY-MM [outdir] [--only a,b] [--skip c]` runs the collectors and assembles `summary.txt` |
| `scripts/lib.sh` | Shared helpers: argument and tool checks, config loading, CRLF-safe `jq`, summary lines |
| `scripts/collectors/NN-name.sh` | One collector per evidence source, each standalone with its own tool checks |
| `scripts/config.example.sh` | Template for `scripts/config.local.sh` (gitignored) |
| `references/format.md` | Structure of both output files, repo short-name table, link conventions, public holidays |

Collectors: `github-prs`, `github-reviews`, `github-commits`, `github-events`,
`claude-sessions`, `home-docs`, `jira`, `workdays`. A collector whose tool is missing or
unconfigured records `name=skipped (reason)` in `summary.txt` and the others still run.
To add a source, copy an existing collector: source `../lib.sh`, call `tr_init "$@"`,
declare tools with `require_tools`, write files into the current directory and summary
lines with `note`.

## Install

Clone (or symlink) the repo into your Claude Code skills directory under the skill name:

```bash
git clone https://github.com/fredx30/sre-timereport-skill.git ~/.claude/skills/monthly-time-report
```

The skill triggers on phrases like "time report", "tidrapport", "monthly report",
"what did I do last month", "daily log", "hours worked".

## Configuration

Nothing organisation-specific is hard-coded. Values come from the environment first, then
from `scripts/config.local.sh` (copy `scripts/config.example.sh`) or the file named by
`TIME_REPORT_CONFIG`:

| Variable | Required | Meaning |
|---|---|---|
| `ORG` | for GitHub | GitHub organisation (or user) whose repos are searched; the `github-*` collectors skip without it |
| `LOGIN` | no | GitHub login to report on; defaults to the authenticated `gh` user |
| `JIRA_SEARCH` | no | Command taking a JQL string as its last argument, printing a JSON array of issues with `key`, `fields.status.name`, `fields.summary`. The `jira` collector skips when unset |
| `TICKET_RE` | no | Extended regex for ticket keys in PR bodies; default `\b[A-Z]{2,10}-[0-9]+\b`, or an explicit list such as `\b(PROJ\|OPS)-[0-9]+\b` |
| `TICKET_EXCLUDE` | no | Extended regex for matches to drop; default rejects `CVE-`, `RFC-`, `SHA-`, `UTF-` and similar tokens |
| `PROJECT_PREFIX` | no | Colon-separated prefixes stripped from `~/.claude/projects/` directory names in `sessions.tsv`, first match wins |
| `PROJECT_HOME` | no | Project directory name shown as `home` |
| `HOLIDAY_NOTE` | no | Note line in `workdays.txt` |
| `HOME_DIR` | no | Defaults to `$HOME` |

Example `scripts/config.local.sh`:

```bash
: "${ORG:=my-org}"
: "${JIRA_SEARCH:=mycli issue search --limit 100 --output json --jql}"
: "${PROJECT_PREFIX:=C--Users-me-work-:C--Users-me-}"
: "${PROJECT_HOME:=C--Users-me}"
```

After the first run, fill in the repo short-name table and the Jira link convention in
`references/format.md` for your organisation; the holiday list defaults to Sweden.

## Requirements

- `jq`, GNU `date`, `find` and `stat` (Git Bash on Windows has them)
- `gh` (authenticated) for the four `github-*` collectors
- A Jira CLI of your choice behind `JIRA_SEARCH` for the `jira` collector, optional

## License

MIT, see `LICENSE`.
