#!/usr/bin/env bash
# Collector: local Claude Code sessions active in the month, with the opening prompt as topic.
# Needs: jq, GNU find/stat.  Config: HOME_DIR, PROJECT_PREFIX, PROJECT_HOME.
# Writes: sessions.tsv   date (file mtime), project, first 160 chars of the first real prompt
# Scope: only what this user's local install recorded under $HOME_DIR/.claude/projects.
# Sessions run in Docker sandboxes, dev containers, on other machines or in the web app
# are not seen; the report's Sources line should say so.
. "$(dirname "$0")/../lib.sh"; tr_init "$@"
require_tools jq stat
[ -d "$HOME_DIR/.claude/projects" ] || skip "no $HOME_DIR/.claude/projects directory"

project_name() { # path-under-projects -> short name
  local p="$1" pre prefs
  IFS=: read -ra prefs <<< "$PROJECT_PREFIX"
  for pre in "${prefs[@]}"; do
    [ -n "$pre" ] || continue
    if [ "${p#"$pre"}" != "$p" ]; then p="${p#"$pre"}"; break; fi
  done
  [ -n "$PROJECT_HOME" ] && [ "$p" = "$PROJECT_HOME" ] && p=home
  printf '%s' "$p"
}

say "Local Claude sessions"
find "$HOME_DIR/.claude/projects" -maxdepth 2 -name '*.jsonl' -newermt "$FIRST" ! -newermt "$NEXT" -not -path '*AppData*' 2>/dev/null \
  | while read -r f; do
      d="$(stat -c %y "$f" | cut -c1-10)"
      p="$(project_name "$(printf '%s' "$f" | sed "s#.*/\.claude/projects/##; s#/[^/]*\$##")")"
      # First user message that is real prompt text: skip tool results, slash-command
      # caveats and other harness-generated content so sessions started with a slash
      # command are not lost.
      m="$(grep '"type":"user"' "$f" | jq -r '
            (.message.content // "")
            | if type=="string" then . else ([.[]? | select(.type=="text") | .text] | join(" ")) end
            | gsub("\\s+"; " ") | ltrimstr(" ")
            | select(length>0)
            | select(test("^<(local-command|command-|system-reminder|bash-|task-notification)")|not)' 2>/dev/null \
          | head -n1 | cut -c1-160)"
      [ -z "$m" ] && m="(no prompt text)"
      printf '%s\t%s\t%s\n' "$d" "$p" "$m"
    done | sort > sessions.tsv

note "sessions=$(wc -l < sessions.tsv)"
