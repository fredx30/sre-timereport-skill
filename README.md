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
| `scripts/gather.sh` | Evidence gatherer. `gather.sh YYYY-MM [outdir]` writes TSV/TXT files plus `summary.txt` |
| `references/format.md` | Structure of both output files, repo short-name table, link conventions, public holidays |

## Install

Clone (or symlink) the repo into your Claude Code skills directory under the skill name:

```bash
git clone https://github.com/fredx30/sre-timereport-skill.git ~/.claude/skills/monthly-time-report
```

The skill triggers on phrases like "time report", "tidrapport", "monthly report",
"what did I do last month", "daily log", "hours worked".

## Configuration

Nothing organisation-specific is hard-coded. `scripts/gather.sh` reads:

| Variable | Required | Meaning |
|---|---|---|
| `ORG` | yes | GitHub organisation (or user) whose repos are searched |
| `LOGIN` | no | GitHub login to report on; defaults to the authenticated `gh` user |
| `JIRA_SEARCH` | no | Command taking a JQL string as its last argument, printing a JSON array of issues with `key`, `fields.status.name`, `fields.summary`. Jira is skipped when unset |
| `TICKET_RE` | no | Extended regex for ticket keys in PR bodies; default `[A-Z][A-Z0-9]+-[0-9]+` |
| `PROJECT_PREFIX` | no | Prefix stripped from `~/.claude/projects/` directory names in `sessions.tsv` |
| `HOME_DIR` | no | Defaults to `$HOME` |

Example profile snippet:

```bash
export ORG=my-org
export JIRA_SEARCH='mycli issue search --limit 100 --output json --jql'
export PROJECT_PREFIX='C--Users-me-work-'
```

After the first run, fill in the repo short-name table and the Jira link convention in
`references/format.md` for your organisation; the holiday list defaults to Sweden.

## Requirements

- `gh` (authenticated), `jq`, GNU `date` (Git Bash on Windows has it)
- A Jira CLI of your choice behind `JIRA_SEARCH`, optional

## License

MIT, see `LICENSE`.
