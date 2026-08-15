#!/bin/bash
# Reed guard — mechanical enforcement of two rules the garden otherwise states only in prose.
#
#   1. The Watch is read-only. Reed reads Wikipedia through WebFetch, which cannot write.
#      No shell command may reach a Wikimedia host, or any other network host. The only
#      egress the relay has is `git push` to the garden's own remote.
#
#   2. origin/ is the founding document. It must stay byte-identical forever.
#
# A PreToolUse hook denial cannot be overridden by the model or by any permission mode.
# That matters here: the Watch reads Wikipedia talk pages, which are written by strangers.
# If text a leg reads ever tries to instruct it, this holds anyway.
#
# Fails OPEN if it cannot parse its input. The permissions.deny rules in
# .claude/settings.json are an independent second layer that needs no interpreter.

set -u

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

parsed=$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    ti = d.get("tool_input") or {}
    print(d.get("tool_name") or "")
    print((ti.get("command") or "").replace("\n", " "))
    print(ti.get("file_path") or "")
except Exception:
    pass
' 2>/dev/null) || exit 0
[ -n "$parsed" ] || exit 0

tool_name=$(printf '%s\n' "$parsed" | sed -n 1p)
command=$(printf '%s\n' "$parsed" | sed -n 2p)
file_path=$(printf '%s\n' "$parsed" | sed -n 3p)

# Reason strings must stay free of double quotes and backslashes.
deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

case "$tool_name" in
  Edit|Write|NotebookEdit|MultiEdit)
    case "$file_path" in
      */origin/*|origin/*)
        deny "origin/ is the founding document and no session may edit it. It must stay byte-identical forever. Where practice has diverged from origin, record the divergence in keeper/index.html instead."
        ;;
    esac
    exit 0
    ;;
  Bash) ;;
  *) exit 0 ;;
esac

# 1. Wikimedia hosts, by any shell path.
if printf '%s' "$command" | grep -Eqi '(wikipedia|wikimedia)\.org'; then
  deny "The Watch is read-only. Reed observes Wikipedia through WebFetch, which can only read. The shell may never contact a Wikimedia host, and no leg may ever edit an article, post to a talk page, or authenticate."
fi

# 2. Shell network clients of any kind.
if printf '%s' "$command" | grep -Eqi '(^|[^[:alnum:]_-])(curl|wget|nc|ncat|netcat|telnet|ftp|scp|sftp|rsync|aria2c|httpie|xh)([^[:alnum:]_-]|$)'; then
  deny "Shell network clients are not available to Reed. Reading the web goes through WebFetch; the only egress the relay has is git push to the garden's own remote."
fi

# 3. Interpreters, which are an indirect network path.
if printf '%s' "$command" | grep -Eqi '(^|[^[:alnum:]_-])(python|python3|perl|ruby|node|deno|bun|php)([^[:alnum:]_-]|$)'; then
  deny "Interpreters are not available to Reed. The garden is plain HTML, tended with Read, Write and Edit; it needs no scripting. If you were computing the meter, do the arithmetic yourself and show it in the Log."
fi

exit 0
