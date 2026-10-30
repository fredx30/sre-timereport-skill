# Format reference

Both files live flat in `~`. The previous month's pair, if any, is the live exemplar;
this file is the skeleton plus the conventions that are easy to forget.

## monthly-report-YYYY-MM.md

```markdown
# Monthly report — <Name>, <Month YYYY>

**Numbers:** N PRs opened · N PRs merged across N repos (N of them opened this month, N carried over from <date>) · N still open (N of them <repo>) · N PRs by others reviewed · N Jira tickets closed/advanced (<keys>) · N presentation artifacts · N docs deliverables.

**Sources:** <what was reachable, and each limit: event-stream cutoff date, Jira changelog not exposed, wiki history not pulled>.

**Time:** N weekdays in <Month>, <public-holiday note>. Week NN (D–D Mon) was vacation, N days. Working days N × 8 h = **N hours**.

Weeks are ISO weeks. Within a week, points are sorted by day. Dates on PRs are the day opened; "→ merged D" gives the merge day when it differs.

---

## Week NN (D–D Mon) — <one-line theme>

**Thu 1 Oct**
- [repo #N](https://github.com/<org>/<repo>/pull/N) <Title in sentence form> — merged same day (<TICKET-KEY>).
- [repo #N](url) <Title> → merged 12 Oct.
- [repo #N](url) <Title> — merged (opened 30 Sep). <One clause on what it closed or enabled.>
- <Non-PR work: meeting notes written, message drafted, investigation done.>
- Reviewed [repo #N](url) — <title>.

**Fri 2 Oct**
- ...

---

## Week NN (D–D Mon) — vacation  (or: no recorded activity)

No activity recorded. <Anything the team did to the user's PRs that week.>

---

## Jira

| Key | Title / context | Status at month end | Days touched |
|---|---|---|---|
| [KEY](link) | <title> — <PRs that cite it> | <status> | <days, or "weekly bucket D–D"> |

<One paragraph on bulk updates that look like board housekeeping, if any.>

---

## Docs handled

| Day | Doc | Where |
|---|---|---|
| D Mon | <doc> | <PR link, ~/file.md, or artifact URL> |

---

## Carry-over into <next month>

- <open PRs grouped by theme, with numbers>
- <decisions pending>
- From <previous month>: <still-open items inherited>
```

## daily-log-YYYY-MM.md

```markdown
# Daily log — <Name>, <Month YYYY>

One entry per calendar day, 1–N. Sources: <same list as the report, one sentence>.

Personal repos (`<login>/...`) are listed but marked *(personal)* so they can be dropped from a work-only view.

Repo short names: infra = `<org>-platform-infra`, api = `<org>-public-api`, ...

---

## 1 Thu
- **repo:** [#N](url) <what>, [#N](url) <what> — both merged. <Outcome clause.>
- **Home:** <non-repo work from sessions in ~>.
- **Review:** [repo #N](url) <title>.

## 3 Sat
- No activity.

## 5 Mon
- Vacation.          (only once confirmed; otherwise "No activity recorded.")

## 24 Sat
- *(personal)* my-side-project #107.
```

## Repo short names

Keep this table current for the user's organisation. Add a row the first time a repo
appears in a report; the short form is what the day bullets and the daily-log legend use.

| Short | Repository |
|---|---|
| infra | `<org>-platform-infra` (example) |
| rw | `<org>-reusable-workflows` (example) |

Repos touched only in bulk waves (a dependency bump across many services, say) are
written with their natural short form and always linked.

## Link conventions

- GitHub PR: `https://github.com/<org>/<repo>/pull/<n>`.
- Jira ticket: `https://<site>.atlassian.net/browse/<KEY>` by default. If the team
  reads a board rather than the issue view, record the board deep link format here and
  use it consistently.
- Artifacts: the `https://claude.ai/artifact/<id>` URL from `Artifact list`.

## Public holidays that can fall on a weekday

The default list is Sweden's. Replace it for another country, and check the year's
actual dates rather than assuming.

Fixed: 1 Jan (Nyårsdagen), 6 Jan (Trettondedag jul), 1 May, 6 Jun (Nationaldagen),
24–26 Dec, 31 Dec (24 and 31 Dec are commonly de-facto days off; follow the employer's
calendar).
Moveable: Långfredagen, Annandag påsk, Kristi himmelsfärdsdag (Thursday), Midsommarafton
(Friday, 19–25 Jun). Alla helgons dag is always a Saturday and never reduces the count.
