---
name: monthly-time-report
description: "Writes the user's monthly time report: a week-by-week monthly report plus a per-day daily log, both as flat markdown files in ~ (monthly-report-YYYY-MM.md, daily-log-YYYY-MM.md), with a working-days / hours estimate. Gathers evidence from GitHub (PRs opened, merged, reviewed, commits, event stream), Jira via a configurable CLI, local Claude session activity, ~/*.md drafts and published artifacts. Use this whenever the user mentions a time report, tidrapport, monthly report, month summary, 'what did I do last month', daily log, hours worked, working days, or wants to reconstruct a month's activity for reporting — even if they only ask 'got the format?' or 'same as last month'."
---

# Monthly time report

Produces two files in `~` for a calendar month. The point of the format is that every
claim is traceable: a PR link, a ticket key, a file path, or an explicit "not
recoverable" caveat. The report is sent onward to people who did not watch the work, so
links and dates matter more than prose.

Read `references/format.md` for the exact structure of both files before writing. If a
previous month's pair exists in `~`, open it as the live exemplar: match its voice and
density.

## Configuration

Nothing organisation-specific lives in the scripts. Values come from the environment
first, then from `scripts/config.local.sh` (gitignored; copy `scripts/config.example.sh`
and edit) or the file named by `TIME_REPORT_CONFIG`:

| Variable | Required | Meaning |
|---|---|---|
| `ORG` | for GitHub | GitHub organisation (or user) whose repos are searched; the `github-*` collectors skip without it |
| `LOGIN` | no | GitHub login to report on; defaults to the authenticated `gh` user |
| `JIRA_SEARCH` | no | Command that takes a JQL string as its last argument and prints a JSON array of issues with `key`, `fields.status.name`, `fields.summary`. The `jira` collector skips with a note when unset |
| `TICKET_RE` | no | Regex for ticket keys in PR bodies; defaults to the generic `\b[A-Z]{2,10}-[0-9]+\b`. Set an explicit list such as `\b(PROJ\|OPS)-[0-9]+\b` when you know the projects |
| `TICKET_EXCLUDE` | no | Regex for matches to drop; defaults to `^(CVE\|UTF\|SHA\|RFC\|ISO\|MD\|TLS\|SSL\|AES\|RSA\|HTTP\|GHSA\|X\|ID)-` so `CVE-2026-1234`, `RFC-001`, `SHA-256` and the like are not reported as tickets |
| `PROJECT_PREFIX` | no | Colon-separated prefixes stripped from `~/.claude/projects/` directory names in `sessions.tsv`, first match wins, e.g. `C--Users-me-work-:C--Users-me-` |
| `PROJECT_HOME` | no | Project directory name shown as `home`, e.g. `C--Users-me` |
| `HOLIDAY_NOTE` | no | Note line in `workdays.txt`; defaults to a generic public-holiday reminder |
| `HOME_DIR` | no | Defaults to `$HOME` |

The repo short-name table and ticket link convention in `references/format.md` are also
per-user: fill them in the first time the skill is used and keep them current.

## Workflow

### 1. Gather evidence (one script, one collector per source)

```
bash ~/.claude/skills/monthly-time-report/scripts/gather.sh YYYY-MM <scratchpad>/time-report-YYYY-MM
```

Pass the session scratchpad directory (listed in the environment section of the system
prompt) as `outdir`. Without it the script falls back to `/tmp/time-report-YYYY-MM`,
which is shared across sessions. `gather.sh` runs every `scripts/collectors/NN-name.sh`
in order; each collector checks its own tools, writes its own files and its own lines in
`summary.txt`. A collector whose tool is missing or unconfigured records
`name=skipped (reason)` and the rest still run, so read `summary.txt` first: every
`skipped` line is a gap to state in the report's Sources line, and a `limit_hit=` line
means a search was truncated at the API cap of 1000 results. `--only a,b` and `--skip c`
select collectors by name or group prefix (`github`), `--list` prints the names, and each
collector also runs on its own with the same two arguments.
| Collector | Files | Used for |
|---|---|---|
| `github-prs` | `prs-opened.tsv`, `prs-merged.tsv` (merged in month, any open date), `prs-closed-unmerged.tsv`, `prs-open-all.tsv`, `pr-jira-keys.tsv` | the day-by-day body and the header counts; carry-overs ("opened D" when earlier); who closed what; stacked-PR context; ticket keys cited in PR bodies (`TICKET_RE` minus `TICKET_EXCLUDE`) for the Jira table |
| `github-reviews` | `reviews.tsv` | "reviewed" count. A plain `--reviewed-by` search over-counts, so candidates are every reviewed PR updated since the month start and each review is dated by its own `submitted_at` |
| `github-commits` | `commits.tsv` | days where work happened without a PR event |
| `github-events` | `events.tsv` (count, date, type, repo, action, ref/number) | review comments, pushes, branch churn. Only ~300 events deep: `event_stream_dense_from` in the summary is the cutoff to state in the report |
| `claude-sessions` | `sessions.tsv` | what was worked on per day outside GitHub; the opening prompt gives the topic |
| `home-docs` | `home-docs.tsv` | the Docs table |
| `jira` | `jira-weekly.txt` | which tickets were updated / transitioned by the user per week, via `$JIRA_SEARCH` |
| `workdays` | `workdays.txt` | the time estimate |

To add a source, drop a new `NN-name.sh` into `scripts/collectors/` modelled on an
existing one: source `../lib.sh`, call `tr_init "$@"`, declare tools with
`require_tools`, write files into the current directory and summary lines with `note`.

Two things the script cannot reach, do them yourself in the same turn:

- **Artifacts**: call `Artifact list` and note any artifact updated in the month (decks,
  briefings). They go in the Docs table with their claude.ai URL.
- **Memory**: `MEMORY.md` project entries often carry the "why" behind a PR cluster and
  the state of things at month end. Use them for week themes and carry-over.

If Jira fails (401, timeout) or is not configured, do not stall: write the report with
the PR-cited keys and a visible Jira caveat in the header.

### 2. Write the monthly report

`~/monthly-report-YYYY-MM.md`, structure in `references/format.md`. Rules that matter:

- **Header numbers first**: PRs opened · merged across N repos (how many opened this
  month vs carried over) · still open · PRs by others reviewed · Jira transitions ·
  docs deliverables. Then a **Sources** line naming what was reachable and its limits,
  then the **Time** line (step 4).
- **ISO weeks**, each with a one-line theme in the heading. Within a week, bold day
  headers (`**Tue 13 Oct**`), one bullet per PR or notable act.
- **Every PR is a link** `[repo-short #N](url)`, followed by its title in sentence form,
  then the outcome: `— merged same day`, `→ merged 19 Oct`, `— open`, `— draft`,
  `— closed unmerged`. A PR opened earlier gets `(opened 30 Sep)`. Cite the ticket key in
  parentheses when the PR body names one.
- **Reviews** of other people's PRs are their own bullets starting `Reviewed`, with the
  author named when it is a colleague's series (e.g. "<name>'s <TICKET> series").
- **Quiet weeks get a heading too**, stating what the sources show ("no recorded
  activity", or "vacation" once confirmed). Never guess the reason for a gap.
- **Jira table**: key as link (see link conventions in `references/format.md`), title /
  context, status at month end, days touched. Bulk updates that look like board
  housekeeping are described as such, without claiming what changed.
- **Docs handled table** and **Carry-over into next month** close the file.

### 3. Write the daily log

`~/daily-log-YYYY-MM.md`: one `## D Www` entry for every calendar day 1–31, including
weekends ("No activity.") and vacation days. Bullets are grouped by repo short name in
bold (`**infra:**`, `**Review:**`, `**Home:**`, `**Jira:**`). Personal repos appear but
are marked *(personal)* so they can be dropped from a work-only view. Keep the
short-name legend at the top in sync with the repos that actually appear.

### 4. Estimate working days and hours

- Weekdays in the month, from `workdays.txt`.
- Subtract public holidays that fall on a weekday. `references/format.md` carries the
  Swedish list as the default; replace it for another country.
- Subtract vacation. A week with zero activity in every source is a strong hint, but
  confirm with the user before labelling it vacation; until confirmed write "no recorded
  activity".
- Remaining days × 8 h. Put the arithmetic on the **Time** line in the header and label
  the vacation days in both files once confirmed.

### 5. Verify before handing over

Run a link sanity check (no `](` without `http`, no stray `]( `), recount the header
numbers against the TSVs, and make sure the Sources line states every gap you hit
(event window cutoff, Jira changelog not available, wiki history not pulled).
Then give the user the two absolute paths and the headline numbers in a short table.

## Conventions

- Write the files in English; quote ticket titles verbatim in their original language.
- Repo short names: `references/format.md` has the table; add new repos there when they
  first appear.
- "Days touched" for Jira come from weekly `updated` buckets unless the Jira CLI exposes
  a changelog. Say so rather than inventing exact dates.
- The reviewed-PR count includes only reviews submitted inside the month. A PR merged
  this month that was reviewed last month is mentioned as "merged by the team (reviewed
  29 Sep)" and not counted.
- Stacked PRs (several merged onto a long-lived base PR) are noted as "(stacked on #60)"
  so the base PR's age is not misread as neglect.
- Do not post, publish or email the report. The deliverable is the two local files.
