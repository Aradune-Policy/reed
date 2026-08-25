#!/bin/bash
# Battery for reed-guard.sh. Every payload is wrapped in the real harness envelope
# (session_id, transcript_path under ~/.claude/, cwd, permission_mode, hook_event_name,
# tool_use_id), which is what session 015 found the first battery had left out.
# Run: bash .claude/hooks/reed-guard-test.sh   (needs python3; touches nothing).
cd "$(dirname "$0")/../.." || exit 1
H=.claude/hooks/reed-guard.sh; P=0; F=0
META='"session_id":"8f3e","transcript_path":"/home/user/.claude/projects/-home-user-reed/8f3e.jsonl","cwd":"/home/user/reed","permission_mode":"default","hook_event_name":"PreToolUse","tool_use_id":"toolu_01"'
tc() { out=$(printf '%s' "$2" | bash "$H" 2>/dev/null); if printf '%s' "$out" | grep -q '"deny"'; then got=DENY; else got=ALLOW; fi
  if [ "$got" = "$3" ]; then P=$((P+1)); printf '  ok   %-5s %s\n' "$got" "$1"; else F=$((F+1)); printf '  FAIL got=%-5s want=%-5s %s\n' "$got" "$3" "$1"; fi; }
j() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }
bash_payload() { printf '{%s,"tool_name":"Bash","tool_input":{"command":%s}}' "$META" "$(j "$1")"; }
edit_payload() { printf '{%s,"tool_name":"%s","tool_input":{"file_path":"%s","content":"x"}}' "$META" "$2" "$1"; }
write_content() { printf '{%s,"tool_name":"Write","tool_input":{"file_path":"%s","content":%s}}' "$META" "$1" "$(j "$2")"; }

echo "--- the session 015 misfires (must ALLOW now) ---"
tc "Write turtles.html"          "$(edit_payload /home/user/reed/turtles.html Write)" ALLOW
tc "Write scratch outside repo"  "$(edit_payload /tmp/claude-0/-home-user-reed/x/scratchpad/probe.txt Write)" ALLOW
tc "Edit log/index.html"         "$(edit_payload /home/user/reed/log/index.html Edit)" ALLOW
tc "Write index.html w/ origin/ link" "$(write_content /home/user/reed/index.html '<a href="origin/">Origin</a>')" ALLOW
tc "Write log mentioning .claude" "$(write_content /home/user/reed/log/index.html 'the guard in .claude/hooks misfired; origin/index.html is locked')" ALLOW
tc "echo | tee /dev/null"        "$(bash_payload "echo hi | tee /dev/null")" ALLOW
tc "tee scratch.txt"             "$(bash_payload "echo hi | tee scratch.txt")" ALLOW
tc "rm -f scratch"               "$(bash_payload "rm -f scratch.txt")" ALLOW
tc "cp a b"                      "$(bash_payload "cp notes.md notes.bak")" ALLOW
tc "mv a b"                      "$(bash_payload "mv draft.html turtles/index.html")" ALLOW
tc "chmod +x script"             "$(bash_payload "chmod +x analyze.py")" ALLOW
tc "sed -i on a room"            "$(bash_payload "sed -i 's/a/b/' essay/index.html")" ALLOW
tc "heredoc to log"              "$(bash_payload "cat >> log/index.html <<'EOF'
<p>hi</p>
EOF")" ALLOW
echo "--- load-bearing paths (must DENY) ---"
tc "Edit origin/origin.md"       "$(edit_payload /home/user/reed/origin/origin.md Edit)" DENY
tc "Edit origin/index.html"      "$(edit_payload /home/user/reed/origin/index.html Edit)" DENY
tc "Write origin/new.txt"        "$(edit_payload /home/user/reed/origin/new.txt Write)" DENY
tc "sed -i origin/origin.md"     "$(bash_payload "sed -i 's/Reed/Turtle/' origin/origin.md")" DENY
tc "redirect > origin/origin.md" "$(bash_payload "printf x > origin/origin.md")" DENY
tc "redirect > \"origin/origin.md\" quoted" "$(bash_payload "printf x > \"origin/origin.md\"")" DENY
tc "rm origin/origin.md"         "$(bash_payload "rm origin/origin.md")" DENY
tc "rm CNAME"                    "$(bash_payload "rm CNAME")" DENY
tc "redirect > CNAME"            "$(bash_payload "echo evil.example > CNAME")" DENY
tc "Write CNAME"                 "$(edit_payload CNAME Write)" DENY
tc "Write /home/user/reed/CNAME" "$(edit_payload /home/user/reed/CNAME Write)" DENY
tc "Edit .claude guard"          "$(edit_payload /home/user/reed/.claude/hooks/reed-guard.sh Edit)" DENY
tc "Write .claude/settings.json" "$(edit_payload /home/user/reed/.claude/settings.json Write)" DENY
tc "Write ~/.claude/settings.json" "$(edit_payload /home/user/.claude/settings.json Write)" DENY
tc "rm -rf .claude"              "$(bash_payload "rm -rf .claude")" DENY
tc "tee .claude/hooks/x"         "$(bash_payload "echo x | tee .claude/hooks/reed-guard.sh")" DENY
tc "chmod guard"                 "$(bash_payload "chmod -x .claude/hooks/reed-guard.sh")" DENY
tc "mv .claude away"             "$(bash_payload "mv .claude .claude-old")" DENY
tc "write workflow file"         "$(bash_payload "mkdir -p .github/workflows && printf 'on: schedule' > .github/workflows/x.yml")" DENY
tc "Write .github workflow"      "$(edit_payload /home/user/reed/.github/workflows/x.yml Write)" DENY
tc "cp over CNAME"               "$(bash_payload "cp other CNAME")" DENY
tc "ln -sf CNAME"                "$(bash_payload "ln -sf x CNAME")" DENY
tc "perl -i origin"              "$(bash_payload "perl -i -pe 's/a/b/' origin/index.html")" DENY
tc "multi-line: ok then rm CNAME" "$(bash_payload "ls
rm CNAME")" DENY
echo "--- load-bearing READS (must ALLOW) ---"
tc "cat settings.json"           "$(bash_payload "cat .claude/settings.json")" ALLOW
tc "cat guard"                   "$(bash_payload "cat .claude/hooks/reed-guard.sh")" ALLOW
tc "grep CNAME everywhere"       "$(bash_payload "grep -rn CNAME .")" ALLOW
tc "read origin.md"              "$(bash_payload "head -40 origin/origin.md")" ALLOW
tc "Read origin (Read tool)"     "{$META,\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/home/user/reed/origin/origin.md\"}}" ALLOW
tc "Read guard (Read tool)"      "{$META,\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/home/user/reed/.claude/hooks/reed-guard.sh\"}}" ALLOW
tc "Glob .github"                "{$META,\"tool_name\":\"Glob\",\"tool_input\":{\"pattern\":\".github/**\"}}" ALLOW
echo "--- ordinary work (must ALLOW) ---"
tc "commit msg says --force"     "$(bash_payload "git commit -m 'session 016: wrote about why --force is banned'")" ALLOW
tc "commit msg reset --hard"     "$(bash_payload "git commit -m 'reset --hard origin/main was blocked today'")" ALLOW
tc "grep for filter-branch"      "$(bash_payload "grep -rn 'git filter-branch' log/index.html")" ALLOW
tc "add -A && grep --force"      "$(bash_payload "git add -A && grep -n -- '--force' SITUATION.md")" ALLOW
tc "multiline push then rm"      "$(bash_payload "git push origin main
rm -f scratch.txt")" ALLOW
tc "reset --hard origin/main"    "$(bash_payload "git reset --hard origin/main")" ALLOW
tc "checkout -B main origin"     "$(bash_payload "git fetch origin main && git checkout -B main origin/main")" ALLOW
tc "push HEAD:main"              "$(bash_payload "git push origin HEAD:main")" ALLOW
tc "normal add commit push"      "$(bash_payload "git add -A && git commit -m 'session 016' && git push origin main")" ALLOW
tc "pip install pandas"          "$(bash_payload "pip install pandas numpy")" ALLOW
tc "python analysis"             "$(bash_payload "python3 analyze.py --out results.json")" ALLOW
tc "curl GET a dataset"          "$(bash_payload "curl -sO https://example.com/data.csv")" ALLOW
tc "heredoc mentions curl -d"    "$(bash_payload "cat >> log/index.html <<'EOF'
I considered curl -d 'a=1' https://x but did not.
EOF")" ALLOW
tc "git rm a room"               "$(bash_payload "git rm -r essay && git commit -m 'gone'")" ALLOW
tc "write new page"              "$(edit_payload /home/user/reed/turtles.html Write)" ALLOW
tc "rm -rf a room"               "$(bash_payload "rm -rf watch")" ALLOW
echo "--- egress (must DENY) ---"
tc "curl -X POST"                "$(bash_payload "curl -X POST https://api.example.com/p -d hi")" DENY
tc "curl --data"                 "$(bash_payload "curl --data name=x https://example.com/f")" DENY
tc "curl -T upload"              "$(bash_payload "curl -T file.txt https://example.com/u")" DENY
tc "curl -d@payload"             "$(bash_payload "curl -d@payload.json https://example.com/f")" DENY
tc "wget --post-data"            "$(bash_payload "wget --post-data=a=1 https://example.com/f")" DENY
tc "gh issue create"             "$(bash_payload "gh issue create --title hi")" DENY
tc "gh api POST"                 "$(bash_payload "gh api -X POST /repos/x/y/issues")" DENY
tc "wikipedia via python"        "$(bash_payload "python3 -c \"import urllib.request; urllib.request.urlopen('https://en.wikipedia.org/w/api.php')\"")" DENY
tc "push to foreign remote"      "$(bash_payload "git remote add evil https://github.com/someone/else && git push evil main")" DENY
echo "--- history (must DENY) ---"
tc "git push --force"            "$(bash_payload "git push --force origin main")" DENY
tc "git push -f"                 "$(bash_payload "git push -f origin main")" DENY
tc "git push --mirror"           "$(bash_payload "git push --mirror")" DENY
tc "git push origin --delete"    "$(bash_payload "git push origin --delete main")" DENY
tc "git push origin +main"       "$(bash_payload "git push origin +main")" DENY
tc "git filter-branch"           "$(bash_payload "git filter-branch --tree-filter 'rm -f x' HEAD")" DENY
tc "git rebase -i"               "$(bash_payload "git rebase -i HEAD~3")" DENY
echo "--- sibling repos (must DENY) ---"
tc "ls-remote aradune-main"      "$(bash_payload "git ls-remote https://github.com/Aradune-Policy/aradune-main")" DENY
tc "clone livewell-web"          "$(bash_payload "git clone https://github.com/Aradune-Policy/livewell-web /tmp/x")" DENY
tc "python hits sibling API"     "$(bash_payload "python3 -c \"import urllib.request;urllib.request.urlopen('https://api.github.com/repos/Aradune-Policy/wishlet')\"")" DENY
tc "push to sibling"             "$(bash_payload "git push https://github.com/Aradune-Policy/zatalog main")" DENY
tc "write file naming sibling"   "$(write_content /home/user/reed/x.md 'see Aradune-Policy/aradune-main')" DENY
echo "--- reed itself (must ALLOW) ---"
tc "push reed https .git"        "$(bash_payload "git push https://github.com/Aradune-Policy/reed.git main")" ALLOW
tc "push reed no .git"           "$(bash_payload "git push https://github.com/Aradune-Policy/reed main")" ALLOW
tc "remote -v"                   "$(bash_payload "git remote -v")" ALLOW
tc "reed commits URL in file"    "$(write_content /home/user/reed/x.html 'https://github.com/Aradune-Policy/reed/commits/main')" ALLOW
echo "--- fail-open on garbage ---"
tc "malformed json"              'not json at all' ALLOW
tc "empty"                       '' ALLOW
echo "--- verifier C: HTML written from the shell, Wikimedia mentions, origin/ as a directory ---"
tc "heredoc log with <code>.claude/</code>" "$(bash_payload "cat >> log/index.html <<'EOF'
<p>I read the guard under <code>.claude/hooks</code> today.</p>
EOF")" ALLOW
tc "heredoc with <code>CNAME</code>"  "$(bash_payload "cat >> log/index.html <<'EOF'
<p>The <code>CNAME</code> file binds the domain.</p>
EOF")" ALLOW
tc "echo html mentioning .claude"    "$(bash_payload "echo '<p>read .claude today</p>' >> log/index.html")" ALLOW
tc "heredoc page with href=origin/"  "$(bash_payload "cat > index.html <<'EOF'
<a href=\"origin/\">Origin</a>
EOF")" ALLOW
tc "python heredoc writing html w/ .claude" "$(bash_payload "python3 - <<'PY'
open('log/index.html','a').write('<p>the guard in .claude misfired</p>')
PY")" ALLOW
tc "commit msg names wikipedia.org"  "$(bash_payload "git commit -m 'watch 006: en.wikipedia.org article unchanged'")" ALLOW
tc "grep wikipedia.org"              "$(bash_payload "grep -rn wikipedia.org watch/")" ALLOW
tc "heredoc watch page with wiki URL" "$(bash_payload "cat > watch/index.html <<'EOF'
<a href=\"https://en.wikipedia.org/wiki/Ship_of_Theseus\">Ship of Theseus</a>
EOF")" ALLOW
tc "curl GET wikipedia"              "$(bash_payload "curl -s https://en.wikipedia.org/w/api.php")" DENY
tc "curl bare wikipedia host"        "$(bash_payload "curl en.wikipedia.org")" DENY
tc "wget wikimedia"                  "$(bash_payload "wget https://upload.wikimedia.org/x.png")" DENY
tc "node fetch wikipedia"            "$(bash_payload "node -e \"fetch('https://en.wikipedia.org')\"")" DENY
tc "rm -rf origin"                   "$(bash_payload "rm -rf origin")" DENY
tc "rm -rf origin/"                  "$(bash_payload "rm -rf origin/")" DENY
tc "git rm -r origin"                "$(bash_payload "git rm -r origin")" DENY
tc "rm -rf several rooms incl origin" "$(bash_payload "rm -rf essay watch compost cost keeper origin")" DENY
tc "redirect > origin/extra.html"    "$(bash_payload "cat > origin/extra.html <<'EOF'
x
EOF")" DENY
tc "mv origin old"                   "$(bash_payload "mv origin old")" DENY
tc "rm -rf abs origin"               "$(bash_payload "rm -rf /home/user/reed/origin")" DENY
tc "git mv origin x"                 "$(bash_payload "git mv origin x")" DENY
tc "git clean origin"                "$(bash_payload "git clean -fdx origin")" DENY
tc "echo hi>CNAME no space"          "$(bash_payload "echo hi>CNAME")" DENY
tc "install to CNAME"                "$(bash_payload "install -m 644 x CNAME")" DENY
tc "rsync to .github"                "$(bash_payload "rsync -a wf/ .github/")" DENY
tc "push origin && rm scratch"       "$(bash_payload "git push origin main && rm -f scratch.txt")" ALLOW
tc "push origin; rm scratch"         "$(bash_payload "git push origin main; rm scratch.txt")" ALLOW
tc "git log origin/main"             "$(bash_payload "git log --oneline origin/main -5")" ALLOW
tc "git ls-remote origin"            "$(bash_payload "git ls-remote origin")" ALLOW
tc "git config remote.origin.url"    "$(bash_payload "git config remote.origin.url")" ALLOW
tc "git diff origin/main -- x; cp"   "$(bash_payload "git diff origin/main -- index.html; cp index.html /tmp/x")" ALLOW
tc "cd origin && ls"                 "$(bash_payload "cd origin && ls")" ALLOW
tc "rm -rf essay watch"              "$(bash_payload "rm -rf essay watch")" ALLOW
tc "redirect then read .claude"      "$(bash_payload "echo x > out.txt && cat .claude/settings.json")" ALLOW
tc "sort <in.txt > CNAME"            "$(bash_payload "sort < in.txt > CNAME")" DENY
tc "prose: the origin story (no verb)" "$(bash_payload "cat >> log/index.html <<'EOF'
<p>The origin story of this site is in the keeper's note.</p>
EOF")" ALLOW
tc "test the guard in place"         "$(bash_payload "printf '%s' '{}' | bash .claude/hooks/reed-guard.sh")" ALLOW
tc "run the battery"                 "$(bash_payload "bash .claude/hooks/reed-guard-test.sh")" ALLOW
tc "python build && grep wikipedia (fp, documented)" "$(bash_payload "python3 build.py && grep -c wikipedia.org watch/index.html")" DENY
tc "commit msg with full wiki URL"   "$(bash_payload "git commit -m 'watch: https://en.wikipedia.org/wiki/Ship_of_Theseus unchanged'")" ALLOW
echo "--- verifier A: false denies that bite (must ALLOW) ---"
tc "curl -sf -o download"           "$(bash_payload "curl -sf -o data.csv https://example.com/d.csv")" ALLOW
tc "curl -f"                        "$(bash_payload "curl -f https://example.com/x")" ALLOW
tc "curl -D - -o /dev/null"         "$(bash_payload "curl -D - -o /dev/null https://example.com/x")" ALLOW
tc "wget -t 3"                      "$(bash_payload "wget -t 3 https://example.com/x")" ALLOW
tc "wget -T 30"                     "$(bash_payload "wget -T 30 https://example.com/x")" ALLOW
tc "cat guard 2>/dev/null; cat guard" "$(bash_payload "cat .claude/settings.json 2>/dev/null; cat .claude/hooks/reed-guard.sh")" ALLOW
tc "ls .claude 2>&1 | grep origin"   "$(bash_payload "ls -la .claude/ 2>&1 | grep -i origin/origin.md")" ALLOW
tc "echo > log.txt; cat CNAME"      "$(bash_payload "echo x > log.txt; cat CNAME")" ALLOW
tc "cat settings && rm scratch"     "$(bash_payload "cat .claude/settings.json && rm -f scratch.txt")" ALLOW
tc "cp then rm in other segment"    "$(bash_payload "cp -r . /tmp/build && cat CNAME")" ALLOW
tc "commit msg with ; gh"           "$(bash_payload "git commit -m 'session 016; gh remains off limits'")" ALLOW
tc "python heredoc prints gh"       "$(bash_payload "python3 - <<'PY'
print('curl -d is banned; gh too')
PY")" ALLOW
tc "Write notes/CNAME.md"           "$(edit_payload /home/user/reed/notes/CNAME.md Write)" ALLOW
tc "Write CNAME-explainer.html"     "$(edit_payload /home/user/reed/docs/CNAME-explainer.html Write)" ALLOW
tc "commit msg 'link -> origin/' "  "$(bash_payload "git commit -m 'index: link -> origin/ fixed'")" ALLOW
tc "sed -i on index (no protected)" "$(bash_payload "sed -i 's#The Log#The Record#' index.html")" ALLOW
tc "env curl GET"                   "$(bash_payload "env curl -s https://example.com")" ALLOW
tc "heredoc line mentions origin/ (no verb)" "$(bash_payload "cat >> log/index.html <<'EOF'
<p>The origin/ room is the old founding document.</p>
<p>I removed nothing today.</p>
EOF")" ALLOW
echo "--- verifier A: false allows (must DENY) ---"
tc "git checkout -- CNAME"          "$(bash_payload "git checkout -- CNAME")" DENY
tc "git checkout old -- guard"      "$(bash_payload "git checkout abc123 -- .claude/hooks/reed-guard.sh")" DENY
tc "git restore --source CNAME"     "$(bash_payload "git restore --source=HEAD~3 CNAME")" DENY
tc "git checkout HEAD~5 -- origin/origin.md" "$(bash_payload "git checkout HEAD~5 -- origin/origin.md")" DENY
tc "perl -pi -e CNAME"              "$(bash_payload "perl -pi -e 's/reed/evil/' CNAME")" DENY
tc "sed -Ei CNAME"                  "$(bash_payload "sed -Ei 's/a/b/' CNAME")" DENY
tc "sed --in-place CNAME"           "$(bash_payload "sed --in-place 's/a/b/' CNAME")" DENY
tc "sed -e ... -i CNAME"            "$(bash_payload "sed -e 's/a/b/' -i CNAME")" DENY
tc "unlink CNAME"                   "$(bash_payload "unlink CNAME")" DENY
tc "find .claude -delete"           "$(bash_payload "find .claude -delete")" DENY
tc "find . -name CNAME -delete"     "$(bash_payload "find . -name CNAME -delete")" DENY
tc "sponge CNAME"                   "$(bash_payload "echo x | sponge CNAME")" DENY
tc "cd .github/workflows; cat > x"  "$(bash_payload "mkdir -p .github/workflows && cd .github/workflows && cat > x.yml <<'EOF'
on: push
EOF")" DENY
tc "pushd .claude; echo > settings" "$(bash_payload "pushd .claude; echo '{}' > settings.json; popd")" DENY
tc "cd .claude/hooks; echo > guard" "$(bash_payload "cd .claude/hooks; echo x > reed-guard.sh")" DENY
tc "cd origin && rm index.html"     "$(bash_payload "cd origin && rm index.html")" DENY
tc "(cd origin && echo > origin.md)" "$(bash_payload "(cd origin && echo x > origin.md)")" DENY
tc "rm origin/*"                    "$(bash_payload "rm origin/*")" DENY
tc "echo > origin/style.css"        "$(bash_payload "echo x > origin/style.css")" DENY
tc "git push -d origin main"        "$(bash_payload "git push -d origin main")" DENY
tc "git push origin :main"          "$(bash_payload "git push origin :main")" DENY
tc "git push --force-with-lease=x"  "$(bash_payload "git push --force-with-lease=main:abc123 origin main")" DENY
tc "git push -fu"                   "$(bash_payload "git push -fu origin main")" DENY
tc "push foreign # reed comment"    "$(bash_payload "git push https://github.com/someone/else main # Aradune-Policy/reed")" DENY
tc "remote set-url then push"       "$(bash_payload "git remote set-url origin https://github.com/someone/else.git && git push origin main")" DENY
tc "scp-style foreign push"         "$(bash_payload "git push github.com:someone/else.git main")" DENY
tc "ssh:// foreign push"            "$(bash_payload "git push ssh://git@github.com/someone/else main")" DENY
tc "env curl -d"                    "$(bash_payload "env curl -d a=1 https://example.com/f")" DENY
tc "VAR= curl -d"                   "$(bash_payload "FOO=1 curl -d a=1 https://example.com/f")" DENY
tc "command curl -d"                "$(bash_payload "command curl -d a=1 https://example.com/f")" DENY
tc "backslash curl -d"              "$(bash_payload "\\curl -d a=1 https://example.com/f")" DENY
tc "/usr/bin/curl -d"               "$(bash_payload "/usr/bin/curl -d a=1 https://example.com/f")" DENY
tc "time curl -d"                   "$(bash_payload "time curl -d a=1 https://example.com/f")" DENY
tc "/usr/bin/gh"                    "$(bash_payload "/usr/bin/gh issue create")" DENY
tc "nice gh"                        "$(bash_payload "nice gh api -X POST /x")" DENY
tc "GH_TOKEN=x gh"                  "$(bash_payload "GH_TOKEN=x gh api -X POST /x")" DENY
tc "xargs gh"                       "$(bash_payload "echo 1 | xargs gh issue close")" DENY
tc "command git push -f"            "$(bash_payload "command git push -f origin main")" DENY
tc "/usr/bin/git push -f"           "$(bash_payload "/usr/bin/git push -f origin main")" DENY
tc "env git push --force"           "$(bash_payload "env git push --force origin main")" DENY
tc "GIT_DIR= git push -f"           "$(bash_payload "GIT_DIR=.git git push -f origin main")" DENY
tc "git -C . push -f"               "$(bash_payload "git -C . push -f origin main")" DENY
tc "git -c x=y push -f"             "$(bash_payload "git -c push.default=simple push -f origin main")" DENY
tc "git --no-pager push -f"         "$(bash_payload "git --no-pager push -f origin main")" DENY
tc "bash -c rm CNAME"               "$(bash_payload "bash -c 'rm CNAME'")" DENY
echo "--- verifier A: still fine (must ALLOW) ---"
tc "git --no-pager log origin/main" "$(bash_payload "git --no-pager log origin/main -3")" ALLOW
tc "git -C . push origin main"      "$(bash_payload "git -C . push origin main")" ALLOW
tc "git push -u origin main"        "$(bash_payload "git push -u origin main")" ALLOW
tc "git push origin HEAD:main again" "$(bash_payload "git push origin HEAD:main")" ALLOW
tc "git push --dry-run origin main" "$(bash_payload "git push --dry-run origin main")" ALLOW
tc "git checkout -B main origin/main (again)" "$(bash_payload "git checkout -B main origin/main")" ALLOW
tc "git checkout -- index.html"     "$(bash_payload "git checkout -- index.html")" ALLOW
tc "git stash"                      "$(bash_payload "git stash && git stash pop")" ALLOW
tc "git switch -c turtles"          "$(bash_payload "git switch -c turtles")" ALLOW
tc "sed 's/x/y/' file-with-i.txt"   "$(bash_payload "sed 's/x/y/' file-with-i.txt > out.txt")" ALLOW
tc "sed -n print"                   "$(bash_payload "sed -n '1,5p' CNAME")" ALLOW
tc "perl one-liner reading CNAME"   "$(bash_payload "perl -ne 'print' CNAME")" ALLOW
tc "find . -name '*.html'"          "$(bash_payload "find . -name '*.html' -not -path './origin/*'")" ALLOW
tc "commit msg with # and quotes"   "$(bash_payload "git commit -m \"fix #12; see 'notes'\"")" ALLOW
echo "--- second pass: false denials (must ALLOW) ---"
tc "heredoc prose -> origin/"        "$(bash_payload "cat >> log/index.html <<'EOF'
<p>Fixed the index -> origin/ link.</p>
EOF")" ALLOW
tc "echo prose -> .github"           "$(bash_payload "echo 'see -> .github/ workflow' >> log/index.html")" ALLOW
tc "markdown blockquote > origin/"   "$(bash_payload "cat >> notes.md <<'EOF'
> origin/ is the old founding document
> CNAME binds the domain
EOF")" ALLOW
tc "curl -G --data-urlencode"        "$(bash_payload "curl -sG https://api.github.com/search/repositories --data-urlencode 'q=turtles'")" ALLOW
tc "git checkout origin/turtles"     "$(bash_payload "git checkout origin/turtles")" ALLOW
tc "git checkout -b f origin/f"      "$(bash_payload "git checkout -b feature origin/feature")" ALLOW
tc "find -not -path origin -exec sed -i" "$(bash_payload "find . -name '*.html' -not -path './origin/*' -exec sed -i 's/Log/Record/' {} +")" ALLOW
tc "sed -i \$(find -not -path origin)" "$(bash_payload "sed -i 's/a/b/' \$(find . -name '*.html' -not -path './origin/*')")" ALLOW
tc "for loop over html"              "$(bash_payload "for f in essay/*.html watch/*.html; do sed -i 's/a/b/' \"\$f\"; done")" ALLOW
tc "git show HEAD:index.html > x"    "$(bash_payload "git show HEAD:index.html > /tmp/old.html")" ALLOW
tc "git fetch origin"                "$(bash_payload "git fetch origin")" ALLOW
tc "git diff origin/main"            "$(bash_payload "git diff origin/main -- index.html")" ALLOW
tc "git reset --hard origin/main (2)" "$(bash_payload "git reset --hard origin/main")" ALLOW
tc "git reset --hard HEAD"           "$(bash_payload "git reset --hard HEAD")" ALLOW
tc "git reset --soft HEAD~1"         "$(bash_payload "git reset --soft HEAD~1")" ALLOW
tc "http GET query =="               "$(bash_payload "http https://api.github.com/search/repositories q==turtles")" ALLOW
tc "curl -sSfL -o"                   "$(bash_payload "curl -sSfL -o data.json https://example.com/d.json")" ALLOW
tc "curl -H header GET"              "$(bash_payload "curl -H 'Accept: application/json' https://example.com/x")" ALLOW
tc "rm -rf a/*"                      "$(bash_payload "rm -rf turtles/*")" ALLOW
tc "rm -f *.tmp"                     "$(bash_payload "rm -f *.tmp")" ALLOW
tc "WebFetch reed CNAME (read)"      "{$META,\"tool_name\":\"WebFetch\",\"tool_input\":{\"url\":\"https://raw.githubusercontent.com/Aradune-Policy/reed/main/CNAME\",\"prompt\":\"x\"}}" ALLOW
tc "WebSearch turtles"               "{$META,\"tool_name\":\"WebSearch\",\"tool_input\":{\"query\":\"turtle facts\"}}" ALLOW
tc "commit msg naming the account+reed" "$(bash_payload "git commit -m 'note: repo is Aradune-Policy/reed'")" ALLOW
echo "--- second pass: holes (must DENY) ---"
tc "invalid utf-8 rm CNAME"          "$(printf '{%s,"tool_name":"Bash","tool_input":{"command":"rm CNAME \xff"}}' "$META")" DENY
tc "invalid utf-8 > origin/origin.md" "$(printf '{%s,"tool_name":"Bash","tool_input":{"command":"printf x > origin/origin.md \xff"}}' "$META")" DENY
tc "invalid utf-8 sibling clone"     "$(printf '{%s,"tool_name":"Bash","tool_input":{"command":"git clone https://github.com/Aradune-Policy/wishlet \xff"}}' "$META")" DENY
tc "push quoted +main"               "$(bash_payload "git push origin '+main'")" DENY
tc "push quoted :main"               "$(bash_payload "git push origin ':main'")" DENY
tc "push quoted +HEAD:main"          "$(bash_payload "git push origin \"+HEAD:main\"")" DENY
tc "push --prune refspec"            "$(bash_payload "git push --prune origin 'refs/heads/*:refs/heads/*'")" DENY
tc "curl -X quoted POST"             "$(bash_payload "curl -X \"POST\" https://x")" DENY
tc "curl -X 'DELETE'"                "$(bash_payload "curl -X 'DELETE' https://x")" DENY
tc "curl -dfoo=bar"                  "$(bash_payload "curl -dfoo=bar https://x")" DENY
tc "curl -sX POST"                   "$(bash_payload "curl -sX POST https://x")" DENY
tc "curl -Tfile"                     "$(bash_payload "curl -Tfile https://x")" DENY
tc "curl -Ffile=@x"                  "$(bash_payload "curl -Ffile=@x https://x")" DENY
tc "http POST"                       "$(bash_payload "http POST https://api.github.com/repos/x/y/issues title=x")" DENY
tc "xh POST"                         "$(bash_payload "xh POST https://x a=b")" DENY
tc "http field implies POST"         "$(bash_payload "http https://x title=hello")" DENY
tc "git rebase -qi"                  "$(bash_payload "git rebase -qi HEAD~3")" DENY
tc "git show > origin/index.html"    "$(bash_payload "git show HEAD:origin/index.html > origin/index.html")" DENY
tc "git log > origin/log.txt"        "$(bash_payload "git log --oneline > origin/log.txt")" DENY
tc "git config remote.origin.url"    "$(bash_payload "git config remote.origin.url https://github.com/someone/else && git push origin main")" DENY
tc "git -c remote.evil.url push"     "$(bash_payload "git -c remote.evil.url=https://github.com/someone/else push evil main")" DENY
tc "Write .git/config"               "$(edit_payload /home/user/reed/.git/config Write)" DENY
tc "Write .git/hooks/pre-push"       "$(edit_payload /home/user/reed/.git/hooks/pre-push Write)" DENY
tc "echo > .git/config"              "$(bash_payload "echo x > .git/config")" DENY
tc "WebFetch sibling repo"           "{$META,\"tool_name\":\"WebFetch\",\"tool_input\":{\"url\":\"https://github.com/Aradune-Policy/aradune-main\",\"prompt\":\"x\"}}" DENY
tc "enumerate account via curl"      "$(bash_payload "curl -s 'https://github.com/Aradune-Policy?tab=repositories'")" DENY
tc "search org:Aradune-Policy"       "$(bash_payload "curl -s 'https://api.github.com/search/repositories?q=org:Aradune-Policy'")" DENY
tc "rm -rf * at root"                "$(bash_payload "rm -rf *")" DENY
tc "rm -rf ./*"                      "$(bash_payload "rm -rf ./*")" DENY
tc "rm -rf ."                        "$(bash_payload "rm -rf .")" DENY
tc "mv * old/"                       "$(bash_payload "mkdir old && mv * old/")" DENY
BR="rm -rf {origin,essay}"; tc "rm -rf brace with origin"       "$(bash_payload "$BR")" DENY
tc "rm -rf turtles && ls ."          "$(bash_payload "rm -rf turtles && ls .")" ALLOW
tc "rm -rf ./"                       "$(bash_payload "rm -rf ./")" DENY
tc "git checkout HEAD~50 -- ."       "$(bash_payload "git checkout HEAD~50 -- .")" DENY
tc "git reset --hard HEAD~50"        "$(bash_payload "git reset --hard HEAD~50")" DENY
tc "git reset --hard abc123"         "$(bash_payload "git reset --hard abc123 && git push origin main")" DENY
tc "cd .git && echo > config"        "$(bash_payload "cd .git && echo x > config")" DENY
echo "--- python3 missing: fallback on stripped raw payload ---"
D=$(mktemp -d); printf '#!/bin/sh\nexit 1\n' > $D/python3; chmod +x $D/python3
nopy() { out=$(printf '%s' "$2" | PATH="$D:$PATH" bash "$H" 2>/dev/null); if printf '%s' "$out" | grep -q '"deny"'; then got=DENY; else got=ALLOW; fi
  if [ "$got" = "$3" ]; then P=$((P+1)); printf '  ok   %-5s %s\n' "$got" "$1"; else F=$((F+1)); printf '  FAIL got=%-5s want=%-5s %s\n' "$got" "$3" "$1"; fi; }
nopy "nopy: rm CNAME"            "$(bash_payload "rm CNAME")" DENY
nopy "nopy: Edit guard"          "$(edit_payload /home/user/reed/.claude/hooks/reed-guard.sh Edit)" DENY
nopy "nopy: > origin/origin.md"  "$(bash_payload "printf x > origin/origin.md")" DENY
nopy "nopy: Write turtles.html"  "$(edit_payload /home/user/reed/turtles.html Write)" ALLOW
nopy "nopy: tee scratch"         "$(bash_payload "echo hi | tee scratch.txt")" ALLOW
nopy "nopy: sibling ref"         "$(bash_payload "git clone https://github.com/Aradune-Policy/wishlet")" DENY
nopy "nopy: newline then rm CNAME"  "$(bash_payload "ls
rm CNAME")" DENY
nopy "nopy: other harness field w/ .claude path" "{\"session_id\":\"x\",\"agent_transcript_path\":\"/home/user/.claude/projects/a/x.jsonl\",\"cwd\":\"/home/user/reed\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/home/user/reed/t.html\",\"content\":\"x\"}}" ALLOW
nopy "nopy: unreadable payload denied"  "$(printf '{%s,"tool_name":"Bash","tool_input":{"command":"rm CNAME \xff"}}' "$META")" DENY
nopy "nopy: transcript path with escaped quote" "{\"session_id\":\"x\",\"transcript_path\":\"/home/user/.claude/projects/a\\\"b/x.jsonl\",\"cwd\":\"/home/user/reed\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/home/user/reed/t.html\",\"content\":\"x\"}}" ALLOW
rm -rf $D
echo; echo "PASS=$P FAIL=$F"
