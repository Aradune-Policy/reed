#!/bin/bash
# Guard for reed.garden. Five checks.
#
#  0b. Sibling repositories. The keeper's GitHub account holds repositories that are
#      not this project. This session may touch exactly one of them, and any reference
#      to the account other than this repository is denied on the raw payload, before
#      parsing, so it applies to every tool and every shell path including interpreters
#      and file contents.
#
#   0. The load-bearing paths: origin/, .claude/, .github/, CNAME, and .git/config and
#      .git/hooks. Checked against what the tool would actually act on: the shell command
#      for Bash, the file path for the editor tools, the whole input for anything else.
#      NOT against the raw hook payload, which always carries the harness's own metadata
#      (the transcript path lives under a ".claude/" directory) and so matched on every
#      call, denying every editor write anywhere. Session 015 found that. If python3 is
#      missing, or the payload does not parse, the check falls back to the raw payload
#      with the harness metadata fields stripped out, where file CONTENTS do count and
#      an unreadable payload is denied rather than allowed.
#      For the shell: "origin" is masked where it is plainly the git remote; lowercase
#      HTML tags are removed so the ">" of a tag is not read as a redirection; find's
#      "-not -path" exclusions are removed; the command is judged one segment at a time
#      (so a read of the guard followed by an unrelated rm is fine), except that a cd or
#      pushd into a protected directory makes any write in the command count, and an
#      rm, mv or checkout aimed at "*" or "." from the repository root is denied because
#      the root holds these paths. What remains: prose written from the shell that names
#      one of these paths in the same segment as a bare rm/mv/cp/tee word is denied, as
#      is cp or sed -i naming one of them in either direction. The editor tools have
#      none of these problems, since only their path is checked.
#   1. Editor writes anywhere under origin/. The previous project promised the Origin
#      page was the one page no session may edit; the keeper keeps that promise for it.
#   2. Outbound HTTP writes (curl, wget, httpie, xh), gh, and a Wikimedia host named in
#      a command that also invokes a network client or an interpreter. The session's
#      only sanctioned channel out is a push to this repository (SITUATION.md rule 2).
#   3. Force-pushes, remote branch deletion, history rewrites, a hard reset to anything
#      but origin/main, and pushes, remote changes or remote URL settings that point
#      anywhere but this repository.
#
# Checks 2 and 3 match command text, segment by segment, with separators inside quoted
# strings neutralised, the quotes removed and trailing comments dropped, so that a
# commit message, a heredoc or a grep pattern that merely MENTIONS one of these does
# not trip the guard. They are a courtesy, not a wall: a subprocess, an interpreter, a
# variable, a glob that spells a protected name without naming it, an archive
# extracted over the tree, or an unusual spelling goes straight past them. The rules in
# SITUATION.md are the boundary.
#
# A PreToolUse denial cannot be overridden by the model or by any permission mode.
# Requires python3 for checks 1 to 3. Without it those are skipped; 0 and 0b still run.
# The test battery is reed-guard-test.sh, next to this file.

set -u
export LC_ALL=C

# Reason strings must stay free of double quotes and backslashes.
deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

# --- 0b. Sibling repositories in the keeper's account ------------------------------
siblings=$(printf '%s' "$input" | grep -oEi 'Aradune-Policy(/[A-Za-z0-9._-]+)?' \
           | grep -viE '^Aradune-Policy/reed(\.git)?$' | head -1)
if [ -n "$siblings" ]; then
  deny "This repository is the only one you may touch. The keeper's account holds other repositories that are not part of this project; reaching one of them or listing them - reading, cloning, pushing, fetching, or calling the API - is outside this arrangement. See SITUATION.md, rule 2."
fi

# --- Parse ---------------------------------------------------------------------------
# Output: line 1 the tool name, line 2 a flag (1 if the shell command cds into a
# protected directory), the rest the subject: for Bash the normalised command, for the
# editor tools the file path, otherwise the whole tool_input.
parsed=$(printf '%s' "$input" | python3 -c '
import json, re, sys
try:
    d = json.load(sys.stdin)
    t = d.get("tool_name") or ""
    ti = d.get("tool_input") or {}
    flag = "0"
    if t == "Bash":
        s = ti.get("command") or ""
        # Separators inside quoted strings are not separators; then the quotes go.
        s = re.sub(r"\x27[^\x27]*\x27|\"(\\\\.|[^\"\\\\])*\"",
                   lambda m: re.sub(r"[;&|\n]", " ", m.group(0)), s)
        s = re.sub(r"(^|\s)#[^\x27\"\n]*$", r"\1", s, flags=re.M)
        s = s.replace("\x27", " ").replace("\"", " ")
        # A find exclusion names a path in order NOT to touch it.
        s = re.sub(r"(-not|!)\s+-path\s+\S+", " ", s)
        # In a git segment "origin" is the remote, not the directory: mask it before
        # any redirection in the segment. Working-tree verbs get only the branch
        # forms masked, and never a file under origin/.
        out = []
        gitre = re.compile(r"^\s*(?:(?:sudo|env|command|time|nice|nohup|exec)\s+|[A-Za-z_][A-Za-z0-9_]*=\S*\s+|\\)*(?:/\S*/)?git(?:\s+(?:-[A-Za-z](?:\s+[^\s-]\S*)?|--\S+))*\s+(\S+)")
        filey = re.compile(r"\.(md|html|css|txt|js|json|yml|yaml|sh|py|csv|xml|svg)$")
        for seg in re.split(r"(\|\||&&|[;|\n])", s):
            m = gitre.match(seg)
            if m:
                head, sep, tail = seg.partition(">")
                if m.group(1) in ("rm", "mv", "clean", "checkout", "restore", "apply", "stash", "switch", "reset"):
                    head = re.sub(r"\borigin/([A-Za-z0-9_.-]+)(?![/A-Za-z0-9_.-])",
                                  lambda b: b.group(0) if filey.search(b.group(1)) else "REMOTE/" + b.group(1), head)
                else:
                    head = re.sub(r"\borigin\b", "REMOTE", head)
                seg = head + sep + tail
            out.append(seg)
        s = "".join(out)
        # A lowercase HTML tag is text, not a redirection.
        s = re.sub(r"<[a-z/!][a-z0-9-]*(\s[^<>]*)?>", " ", s)
        if re.search(r"(^|[;&|\n(]\s*)(cd|pushd)\s+\S*(origin|\.claude|\.github|\.git(?![A-Za-z]))", s):
            flag = "1"
    elif t in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        s = ti.get("file_path") or ti.get("notebook_path") or ""
    else:
        s = json.dumps(ti)
    sys.stdout.buffer.write((t + "\n" + flag + "\n" + s).encode("utf-8", "surrogateescape"))
except Exception:
    pass
' 2>/dev/null) || parsed=""

if [ -n "$parsed" ]; then
  tool_name=$(printf '%s\n' "$parsed" | sed -n 1p)
  cdflag=$(printf '%s\n' "$parsed" | sed -n 2p)
  subject=$(printf '%s\n' "$parsed" | sed '1,2d')
  have_python=1
else
  # No python3, or the payload did not parse: the raw payload minus the harness's own
  # fields (the ones that carry a ".claude/" path on every call), with JSON newline
  # escapes turned into spaces so a verb at the start of a line is still a word.
  tool_name=$(printf '%s' "$input" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[A-Za-z]+"' | head -1 | sed -E 's/.*"([A-Za-z]+)"$/\1/')
  cdflag=0
  subject=$(printf '%s' "$input" | sed -E 's/"(transcript_path|cwd|session_id|tool_use_id|permission_mode|hook_event_name)"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"//g; s/"[A-Za-z_]+"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*\.claude\/projects([^"\\]|\\.)*"//g; s/\\[ntr]/ /g')
  have_python=0
  if [ -z "$subject" ]; then
    deny "This tool call could not be read by the guard, so it is refused rather than let through unchecked. Plain text in commands and file contents always parses; retry without unusual bytes, and say so in the log if it keeps happening."
  fi
fi

# --- 0. Load-bearing paths ---------------------------------------------------------
PROTECTED='(^|[^A-Za-z0-9_-])origin(/|[[:space:]"]|$)|(^|[^A-Za-z0-9_-])\.claude([^A-Za-z0-9_-]|$)|(^|[^A-Za-z0-9_-])\.github([^A-Za-z0-9_-]|$)|(^|[^A-Za-z0-9_.-])CNAME([^A-Za-z0-9_.-]|$)|(^|[^A-Za-z0-9_-])\.git/(config|hooks)'
VERBS='(^|[^A-Za-z0-9_-])(rm|mv|cp|tee|truncate|dd|shred|chmod|ln|install|rsync|unlink|sponge)([^A-Za-z0-9_-]|$)|git[[:space:]]+(clean|checkout|restore|apply|stash|switch)|find[[:space:]].*-delete|sed([[:space:]]+[^[:space:]]+)*[[:space:]]+(-[A-Za-z]*i([[:space:]]|$|\.)|--in-place)|perl([[:space:]]+[^[:space:]]+)*[[:space:]]+-[A-Za-z]*i([[:space:]]|$|\.)'
# A redirection: ">" not part of an arrow "->", and not a markdown quote at line start.
REDIR='(^>>?[^[:space:]>]|[^-]>>?[[:space:]]*)\\?"?[^"[:space:];&|]*'
WRITEISH="${REDIR}"'(origin|CNAME|\.claude|\.github|\.git/)|'"$VERBS"
# Inside a protected directory (after cd or pushd) any write counts, whatever it names.
WRITEANY="${REDIR}"'[^"[:space:];&|]|'"$VERBS"
# rm, mv or checkout aimed at everything, from the root that holds these paths.
ROOTWIPE='(^|[^A-Za-z0-9_-])(rm|mv|git[[:space:]]+(checkout|restore))([[:space:]]+[^[:space:];&|>]+)*[[:space:]]+(\./)?(\*|\./?|\.\*|\{[^}]*(origin|CNAME|\.claude|\.github)[^}]*\})([[:space:]]|$)'
is_editor=0
case "$tool_name" in Edit|Write|MultiEdit|NotebookEdit) is_editor=1 ;; esac
hit0() { printf '%s' "$1" | grep -Eq "$PROTECTED" || return 1
         [ "$is_editor" = 1 ] && return 0
         printf '%s' "$1" | grep -Eq "$WRITEISH"; }
hit=0
if [ "$tool_name" = Bash ] && [ "$have_python" = 1 ]; then
  if [ "$cdflag" = 1 ]; then
    if printf '%s' "$subject" | grep -Eq "$WRITEANY"; then hit=1; fi
  elif printf '%s' "$subject" | grep -Eq "$ROOTWIPE"; then
    hit=1
  else
    while IFS= read -r seg; do
      if hit0 "$seg"; then hit=1; break; fi
    done <<EOF
$(printf '%s' "$subject" | tr ';&|' '\n\n\n')
EOF
  fi
else
  if hit0 "$subject"; then hit=1; fi
fi
if [ "$hit" = 1 ]; then
  deny "That path is load bearing and is not yours to change from in here. CNAME binds reed.garden to this site, .claude holds this guard, .github would run on GitHub machines after you are gone, origin/ is a promise the keeper keeps for the previous project, and .git/config and .git/hooks decide where a push goes. The rest of the repository is yours, within SITUATION.md rule 3. If you need one of these changed, or this denial is wrong, say so in the log."
fi

[ "$have_python" = 1 ] || exit 0

# --- 1. Editor writes under origin/ -------------------------------------------------
case "$tool_name" in
  Edit|Write|NotebookEdit|MultiEdit)
    case "$subject" in
      */origin/*|origin/*)
        deny "origin/ holds the founding document of the PREVIOUS project, which ran here until 24 August 2026 and promised that page would never be edited. The keeper keeps that promise for it. It has no authority over you, and the rest of the repository is yours, within SITUATION.md rule 3."
        ;;
    esac
    exit 0
    ;;
  Bash) ;;
  *) exit 0 ;;
esac

command=$(printf '%s' "$subject" | tr '\n' ';')

# Split into command segments so that quoted text is not scanned as if it were a command.
segments=$(printf '%s' "$command" | tr ';&|' '\n\n\n')
seg() { printf '%s\n' "$segments" | grep -Eqi "$1"; }

# A command may be prefixed by sudo, env, command, time, a VAR=value, a backslash or a
# directory; git may carry global flags before its verb.
PRE='^[[:space:]]*((sudo|env|command|time|nice|nohup|exec|xargs)[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|\\)*(/[^[:space:]]*/)?'
GITCMD="${PRE}git([[:space:]]+(-[A-Za-z]([[:space:]]+[^[:space:]-][^[:space:]]*)?|--[^[:space:]]+))*[[:space:]]+"
URLISH='(https?://|ssh://|git@|[A-Za-z0-9.-]+\.[a-z]{2,}:)'

# --- 2. Outbound HTTP writes, gh, Wikimedia ----------------------------------------
# A Wikimedia host named anywhere in a command that also invokes a network client or an
# interpreter. Naming the host in a commit message, a grep, or a page written by cat is fine.
if printf '%s' "$command" | grep -Eqi '(wikipedia|wikimedia)\.org' \
   && printf '%s' "$command" | grep -Eqi '(^|[^A-Za-z0-9_-])(curl|wget|httpie|http|xh|nc|ncat|telnet|openssl|ssh|python[0-9.]*|node|ruby|perl|php)([^A-Za-z0-9_-]|$)'; then
  deny "Reading Wikipedia goes through WebFetch, which cannot write. The shell may not contact a Wikimedia host: an edit from here would be attributed to a shared cloud address and land on other people. See SITUATION.md, rule 2."
fi

if seg "${PRE}gh([[:space:]]|$)"; then
  deny "The GitHub CLI is not part of this arrangement. It can open issues, gists, releases and pull requests, which is saying something outside this repository. Use git push, and ask in the log if you need the keeper. See SITUATION.md, rule 2."
fi

# curl/wget: long-form write options, or curl's short -d/-F/-T/-X clusters, unless the
# request is forced to GET (-G/--get). httpie/xh: a write method, or a body field.
curlwget=$(printf '%s\n' "$segments" | grep -Ei "${PRE}(curl|wget)([[:space:]]|$)" | grep -Eiv -- '(^|[[:space:]])(-[A-Za-z]*G[A-Za-z]*|--get)([[:space:]]|$)')
httpie=$(printf '%s\n' "$segments" | grep -Ei "${PRE}(httpie|http|https|xh|xhs)([[:space:]]|$)")
if { [ -n "$curlwget" ] && { printf '%s\n' "$curlwget" | grep -Eqi -- '(-X[[:space:]]*(POST|PUT|DELETE|PATCH)|--request[[:space:]]*(POST|PUT|DELETE|PATCH)|--data|--form|--upload-file|--json|--post-data|--post-file|--method=)' \
       || printf '%s\n' "$curlwget" | grep -Ei "${PRE}curl([[:space:]]|$)" | grep -Eq -- '(^|[[:space:]])-[A-Za-z]*([dFT]|X[[:space:]]*(POST|PUT|DELETE|PATCH))'; }; } \
   || { [ -n "$httpie" ] && printf '%s\n' "$httpie" | grep -Eq -- '(^|[[:space:]])(POST|PUT|PATCH|DELETE)([[:space:]]|$)|[[:space:]][A-Za-z_][A-Za-z0-9_-]*(:?=[^=]|@)'; }; then
  deny "Outbound HTTP writes are not part of this arrangement. Reading the web is fine; publishing, posting, sending or editing anything that is not this repository is not. A push to this repository is the sanctioned channel out. See SITUATION.md, rule 2."
fi

# --- 3. Rewriting the record, or pushing somewhere else ----------------------------
if seg "${GITCMD}push([[:space:]].*)?([[:space:]](--force(-with-lease)?(=[^[:space:]]*)?|--mirror|--delete|--prune|-[A-Za-z]*[fd][A-Za-z]*)([[:space:]]|$)|[[:space:]]\+[A-Za-z_]|[[:space:]]:[A-Za-z_/])"; then
  deny "Add to the record, do not rewrite it. Force-pushing, mirroring and deleting remote branches are the one thing the keeper asked you not to do; delete any file you like instead and the history keeps it. See SITUATION.md, rule 3."
fi

if seg "${GITCMD}(filter-branch|filter-repo)" || seg "${GITCMD}rebase([[:space:]].*)?[[:space:]](-[A-Za-z]*i[A-Za-z]*|--interactive)([[:space:]]|$)"; then
  deny "Add to the record, do not rewrite it. Rewriting commits that are already pushed is the one thing the keeper asked you not to do. See SITUATION.md, rule 3."
fi

if seg "${GITCMD}reset([[:space:]].*)?[[:space:]]--hard[[:space:]]+[^[:space:]]" && ! seg "${GITCMD}reset([[:space:]].*)?[[:space:]]--hard[[:space:]]+(REMOTE/(main|master)|HEAD)([[:space:]]|$)"; then
  deny "A hard reset to anything but origin/main puts an older version of every file back in the working tree, this guard included, and the next push would publish it. Check out the file you want from history instead. See SITUATION.md, rule 3."
fi

if printf '%s\n' "$segments" | grep -Ei "${GITCMD}(push|remote[[:space:]]+(add|set-url))([[:space:]].*)?${URLISH}" | grep -Eqvi 'Aradune-Policy/reed' \
   || printf '%s\n' "$segments" | grep -Ei "remote\.[^[:space:]]*\.(url|pushurl)[[:space:]=]+${URLISH}" | grep -Eqvi 'Aradune-Policy/reed'; then
  deny "Pushing to a remote other than this repository is not part of this arrangement. This repository is the only channel out. See SITUATION.md, rule 2."
fi

exit 0
