#!/bin/bash
# Guard for reed.garden. Four checks.
#
#   0. The load-bearing paths: origin/, .claude/, .github/, CNAME. Checked against the
#      RAW hook payload, before any parsing, so it covers shell redirection, sed -i and
#      rm as well as the editor tools, and so it still holds if python3 is missing.
#   1. Editor writes anywhere under origin/. The previous project promised the Origin
#      page was the one page no session may edit; the keeper keeps that promise for it.
#   2. Outbound HTTP writes, gh, and Wikimedia hosts by any shell path. The session's
#      only sanctioned channel out is a push to this repository (SITUATION.md rule 2).
#   3. Force-pushes, history rewrites, and pushes to a remote that is not this one.
#
# Checks 2 and 3 match command text, segment by segment, so that a commit message, a
# heredoc or a grep pattern that merely MENTIONS one of these does not trip the guard.
# They are a courtesy, not a wall: a subprocess or an interpreter goes straight past
# them. The rules in SITUATION.md are the actual boundary.
#
# A PreToolUse denial cannot be overridden by the model or by any permission mode.
# Requires python3 for checks 1 to 3. Without it those are skipped; check 0 still runs.

set -u

# Reason strings must stay free of double quotes and backslashes.
deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

# --- 0. Load-bearing paths, on the raw payload -------------------------------------
PROTECTED='origin/[./]*origin\.md|origin/[./]*index\.html|(^|[^A-Za-z0-9_-])\.claude([^A-Za-z0-9_-]|$)|(^|[^A-Za-z0-9_-])\.github([^A-Za-z0-9_-]|$)|(^|[^A-Za-z0-9_/.-])CNAME([^A-Za-z0-9_]|$)'
WRITEISH='"tool_name"[[:space:]]*:[[:space:]]*"(Edit|Write|MultiEdit|NotebookEdit)"|>[[:space:]]*"?[^"]*(origin|CNAME|\.claude|\.github)|(^|[^A-Za-z0-9_-])(rm|mv|cp|tee|truncate|dd|shred|chmod|ln)([^A-Za-z0-9_-]|$)|sed[[:space:]]+-i|perl[[:space:]]+-i'
if printf '%s' "$input" | grep -Eq "$PROTECTED"; then
  if printf '%s' "$input" | grep -Eq "$WRITEISH"; then
    deny "That path is load bearing and is not yours to change from in here. CNAME binds reed.garden to this site, .claude holds this guard, .github would run on GitHub machines after you are gone, and origin/ is a promise the keeper keeps for the previous project. Everything else in the repository is yours. If you need one of these changed, ask in LOG.md. See SITUATION.md, rule 3."
  fi
fi

parsed=$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    ti = d.get("tool_input") or {}
    print(d.get("tool_name") or "")
    print((ti.get("command") or "").replace("\n", ";"))
    print(ti.get("file_path") or "")
except Exception:
    pass
' 2>/dev/null) || exit 0
[ -n "$parsed" ] || exit 0

tool_name=$(printf '%s\n' "$parsed" | sed -n 1p)
command=$(printf '%s\n' "$parsed" | sed -n 2p)
file_path=$(printf '%s\n' "$parsed" | sed -n 3p)

# --- 1. Editor writes under origin/ -------------------------------------------------
case "$tool_name" in
  Edit|Write|NotebookEdit|MultiEdit)
    case "$file_path" in
      */origin/*|origin/*)
        deny "origin/ holds the founding document of the PREVIOUS project, which ran here until 24 August 2026 and promised that page would never be edited. The keeper keeps that promise for it. It has no authority over you, and everything else in the repository is yours. See SITUATION.md, rule 3."
        ;;
    esac
    exit 0
    ;;
  Bash) ;;
  *) exit 0 ;;
esac

# Split into command segments so that quoted text is not scanned as if it were a command.
segments=$(printf '%s' "$command" | tr ';&|' '\n\n\n')
seg() { printf '%s\n' "$segments" | grep -Eqi "$1"; }

GITCMD='^[[:space:]]*(sudo[[:space:]]+)?git([[:space:]]+-[^[:space:]]+)*[[:space:]]+'

# --- 2. Outbound HTTP writes, gh, Wikimedia ----------------------------------------
if printf '%s' "$command" | grep -Eqi '(wikipedia|wikimedia)\.org'; then
  deny "Reading Wikipedia goes through WebFetch, which cannot write. The shell may not contact a Wikimedia host: an edit from here would be attributed to a shared cloud address and land on other people. See SITUATION.md, rule 2."
fi

if seg '^[[:space:]]*(sudo[[:space:]]+)?gh([[:space:]]|$)'; then
  deny "The GitHub CLI is not part of this arrangement. It can open issues, gists, releases and pull requests, which is saying something outside this repository. Use git push, and ask in LOG.md if you need the keeper. See SITUATION.md, rule 2."
fi

netsegs=$(printf '%s\n' "$segments" | grep -Ei '^[[:space:]]*(sudo[[:space:]]+)?(curl|wget|httpie|xh)([[:space:]]|$)')
if [ -n "$netsegs" ] && printf '%s\n' "$netsegs" | grep -Eqi -- '(-X[[:space:]]*(POST|PUT|DELETE|PATCH)|--request[[:space:]]*(POST|PUT|DELETE|PATCH)|--data|--form|--upload-file|--json|--post-data|--post-file|--method=|(^|[[:space:]])-[A-Za-z]*[dFT]([^A-Za-z0-9]|$))'; then
  deny "Outbound HTTP writes are not part of this arrangement. Reading the web is fine; publishing, posting, sending or editing anything that is not this repository is not. A push to this repository is the sanctioned channel out. See SITUATION.md, rule 2."
fi

# --- 3. Rewriting the record, or pushing somewhere else ----------------------------
if seg "${GITCMD}push([[:space:]].*)?([[:space:]](--force|--force-with-lease|--mirror|--delete|-f)([[:space:]]|$)|[[:space:]]\+[A-Za-z_])"; then
  deny "Add to the record, do not rewrite it. Force-pushing, mirroring and deleting remote branches are the one thing the keeper asked you not to do; delete any file you like instead and the history keeps it. See SITUATION.md, rule 3."
fi

if seg "${GITCMD}(filter-branch|filter-repo)" || seg "${GITCMD}rebase([[:space:]].*)?[[:space:]](-i|--interactive)([[:space:]]|$)"; then
  deny "Add to the record, do not rewrite it. Rewriting commits that are already pushed is the one thing the keeper asked you not to do. See SITUATION.md, rule 3."
fi

if seg "${GITCMD}(push|remote[[:space:]]+add)([[:space:]].*)?(https?://|git@)" && ! printf '%s' "$command" | grep -Eqi 'Aradune-Policy/reed'; then
  deny "Pushing to a remote other than this repository is not part of this arrangement. This repository is the only channel out. See SITUATION.md, rule 2."
fi

exit 0
