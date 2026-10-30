#!/usr/bin/env bash
# Collector: tokens and cost spent in coding-agent CLIs during the month, via ccusage
# (https://github.com/ryoppippi/ccusage), which reads the local logs of every agent it
# supports (Claude Code, Codex, OpenCode, pi, GitHub Copilot CLI, Gemini CLI) and
# reports them as one table. Only agents with logs on this machine appear.
# Scope: only logs written by this user's local install. Agents run in Docker sandboxes,
# dev containers, on other machines or in the web app leave no local log and are missing,
# so the figures are a floor; the report should say so.
# Needs: npx (Node), jq.  Config: CCUSAGE (command, default: npx -y ccusage@latest).
# Writes: agent-usage.tsv   agent, model, input, output, cache_create, cache_read, total, cost_usd
#                           — one row per agent+model, plus one "all" row per agent and one
#                           "all/all" grand total. Cost is ccusage's list-price estimate.
#         agent-usage.json  the raw ccusage output, for anything the TSV leaves out
. "$(dirname "$0")/../lib.sh"; tr_init "$@"
require_tools jq
CCUSAGE="${CCUSAGE:-npx -y ccusage@latest}"
command -v "${CCUSAGE%% *}" >/dev/null 2>&1 || missing "${CCUSAGE%% *}"   # ccusage itself needs no install: npx fetches it

say "Coding-agent usage via ccusage"
# ccusage takes its range as YYYYMMDD; --by-agent adds a per-agent array to each month row.
$CCUSAGE monthly --by-agent --breakdown -j --since "${FIRST//-/}" --until "${LAST//-/}" 2>/dev/null \
  | tr -d '\r' > agent-usage.json
[ -s agent-usage.json ] && jq -e '.monthly' agent-usage.json >/dev/null 2>&1 \
  || skip "ccusage produced no usable output (offline npx, or no agent logs for $MONTH)"

{
  printf 'agent\tmodel\tinput\toutput\tcache_create\tcache_read\ttotal\tcost_usd\n'
  jq -r --arg m "$MONTH" '
    def row(a; m; o): [a, m, o.inputTokens, o.outputTokens, o.cacheCreationTokens, o.cacheReadTokens,
                       (o.inputTokens + o.outputTokens + o.cacheCreationTokens + o.cacheReadTokens),
                       ((o.cost // o.totalCost) * 100 | round / 100)] | @tsv;
    .monthly[] | select(.period == $m)
    | ( .agents[]? | . as $ag | (.modelBreakdowns[] | row($ag.agent; .modelName; .)), row($ag.agent; "all"; $ag) ),
      row("all"; "all"; .)' agent-usage.json
} > agent-usage.tsv

agents="$(jq -r --arg m "$MONTH" '.monthly[] | select(.period == $m) | [.agents[]?.agent] | join(",")' agent-usage.json)"
cost="$(jq -r --arg m "$MONTH" '.monthly[] | select(.period == $m) | .totalCost * 100 | round / 100' agent-usage.json)"
note "agents=${agents:-none}"
note "agent_usage_rows=$(( $(wc -l < agent-usage.tsv) - 1 ))"
note "agent_usage_cost_usd=${cost:-0}"
