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

`scripts/gather.sh` reads its specifics from environment variables so nothing
organisation-specific lives in the skill:

| Variable | Required | Meaning |
|---|---|---|
| `ORG` | yes | GitHub organisation (or user) whose repos are searched |
| `LOGIN` | no | GitHub login to report on; defaults to the authenticated `gh` user |
| `JIRA_SEARCH` | no | Command that takes a JQL string as its last argument and prints a JSON array of issues with `key`, `fields.status.name`, `fields.summary`. Jira is skipped with a note when unset |
| `TICKET_RE` | no | Regex for ticket keys in PR bodies; defaults to the generic `[A-Z][A-Z0-9]+-[0-9]+` |
| `PROJECT_PREFIX` | no | Prefix stripped from `~/.claude/projects/` directory names in `sessions.tsv`, e.g. `C--Users-me-work-` |
| `HOME_DIR` | no | Defaults to `$HOME` |

Put the values in the user's shell profile or pass them inline. The repo short-name
table and ticket link convention in `references/format.md` are also per-user: fill them
in the first time the skill is used and keep them current.

## Workflow

### 1. Gather evidence (one script)

```
bash ~/.claude/skills/monthly-time-report/scripts/gather.sh YYYY-MM [outdir]
```

Default outdir is the session scratchpad if `$CLAUDE_SCRATCHPAD` is set, else
`/tmp/time-report-YYYY-MM`. It writes TSV/TXT files and a `summary.txt` with the
headline counts. Read `summary.txt` first, then the individual files as you write.

What it pulls and why:

| File | Source | Used for |
|---|---|---|
| `prs-opened.tsv` | `gh search prs --author --created` | the day-by-day body, "PRs opened" count |
| `prs-merged.tsv` | `--merged-at` in month (any open date) | "merged" count, carry-overs ("opened D" when earlier) |
| `prs-closed-unmerged.tsv` | closed in month minus merged | note who closed what; often the team closing stale PRs |
| `prs-open-all.tsv` | all currently open by author | carry-over section, stacked-PR context |
| `reviews.tsv` | reviews API filtered to `submitted_at` in month | "reviewed" count. `--reviewed-by` search alone over-counts (it matches reviews from earlier months on PRs updated this month) |
| `commits.tsv` | `gh search commits` | days where work happened without a PR event |
| `events.tsv` | `users/<login>/events` | review comments, pushes, branch churn. Only ~300 events deep, so state the cutoff date in the report |
| `sessions.tsv` | `~/.claude/projects/**/*.jsonl` mtimes + opening prompt | what was worked on per day outside GitHub; the opening prompt gives the topic |
| `home-docs.tsv` | `~/*.md` modified in month | the Docs table |
| `jira-weekly.txt` | `$JIRA_SEARCH`, per ISO-week buckets | which tickets were updated / transitioned by the user per week |
| `pr-jira-keys.tsv` | ticket keys in PR bodies | ties PRs to tickets for the Jira table |
| `workdays.txt` | weekday count for the month | the time estimate |

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
