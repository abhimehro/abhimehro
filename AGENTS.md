# AGENTS.md

Guidance for coding agents working in  (GitHub profile + related assets).

## Workspace
- Primary path: 
- Related infra: 

## Agent shell policy (local macOS)

Login shell stays **Fish**. Coding agents must not evaluate Fish syntax.

### Required command pattern
## main...origin/main
?? .agents/
?? .claude/
?? .cursor/
?? .github/github-app.yml
?? .trunk/
?? .vscode/
?? .windsurf/
## main...origin/main
?? .agents/
?? .claude/
?? .cursor/
?? .github/github-app.yml
?? .trunk/
?? .vscode/
?? .windsurf/

### Session start
=== agent-term-doctor ===
log: /Users/speedybee/.local/state/agent-term-doctor/session-20260804T184629Z-28345.log
PASS  found agent-zsh -> /Users/speedybee/bin/agent-zsh
PASS  found agent-bash -> /Users/speedybee/bin/agent-bash
login_shell=unknown
WARN  could not read login shell
parent_comm=/bin/sh
PASS  agent-zsh workspace cd ok
PASS  agent-zsh unbuffered + pager hardened
PASS  agent-zsh stdout captured
PASS  agent-zsh stderr emitted
PASS  agent-bash workspace cd ok
PASS  agent-bash unbuffered + pager hardened
PASS  agent-bash stdout captured
PASS  agent-bash stderr emitted
PASS  agent-bash rc loaded on -c
burst agent-zsh 12/12
PASS  agent-zsh burst reliable
burst agent-bash 12/12
PASS  agent-bash burst reliable
PASS  git --no-pager returns output (0927973 fix: neutralize middle-dot in langs card alt text)
stdin_tty=no
stdout_tty=no
stderr_tty=no
----
INTERPRETATION
- PASS launchers + swallowed output later => suspect agent terminal tool/PTY, not shell rc
- Agents do NOT auto-switch from Fish; point them at agent-zsh or agent-bash
- Prefer: agent-zsh -c ...   fallback: agent-bash -c ...
----
summary warnings=1 failures=0
status=warn exit=1
latest=/Users/speedybee/.local/state/agent-term-doctor/latest.log
=== agent-term-doctor ===
log: /Users/speedybee/.local/state/agent-term-doctor/session-20260804T184630Z-28518.log
PASS  found agent-zsh -> /Users/speedybee/bin/agent-zsh
PASS  found agent-bash -> /Users/speedybee/bin/agent-bash
login_shell=unknown
WARN  could not read login shell
parent_comm=/bin/bash
NOTE  parent looks POSIX (/bin/bash)
PASS  agent-zsh workspace cd ok
PASS  agent-zsh unbuffered + pager hardened
PASS  agent-zsh stdout captured
PASS  agent-zsh stderr emitted
PASS  agent-bash workspace cd ok
PASS  agent-bash unbuffered + pager hardened
PASS  agent-bash stdout captured
PASS  agent-bash stderr emitted
PASS  agent-bash rc loaded on -c
burst agent-zsh 12/12
PASS  agent-zsh burst reliable
burst agent-bash 12/12
PASS  agent-bash burst reliable
PASS  git --no-pager returns output (0927973 fix: neutralize middle-dot in langs card alt text)
stdin_tty=no
stdout_tty=no
stderr_tty=no
----
INTERPRETATION
- PASS launchers + swallowed output later => suspect agent terminal tool/PTY, not shell rc
- Agents do NOT auto-switch from Fish; point them at agent-zsh or agent-bash
- Prefer: agent-zsh -c ...   fallback: agent-bash -c ...
----
summary warnings=1 failures=0
status=warn exit=1
latest=/Users/speedybee/.local/state/agent-term-doctor/latest.log

### Do not
- Change the macOS login shell away from Fish
- Run interactive editors ([m[m[0m[H[2J[2;1H[1m[34m~                                                                               [3;1H~                                                                               [4;1H~                                                                               [5;1H~                                                                               [6;1H~                                                                               [7;1H~                                                                               [8;1H~                                                                               [9;1H~                                                                               [10;1H~                                                                               [11;1H~                                                                               [12;1H~                                                                               [13;1H~                                                                               [14;1H~                                                                               [15;1H~                                                                               [16;1H~                                                                               [17;1H~                                                                               [18;1H~                                                                               [19;1H~                                                                               [20;1H~                                                                               [21;1H~                                                                               [22;1H~                                                                               [23;1H~                                                                               [0m[7;32HVIM - Vi IMproved[9;33Hversion 9.1.1752[10;29Hby Bram Moolenaar et al.[11;19HVim is open source and freely distributable[13;29HSponsor Vim development![14;18Htype  :help sponsor[34m<Enter>[0m    for information [16;18Htype  :q[34m<Enter>[0m               to exit         [17;18Htype  :help[34m<Enter>[0m  or  [34m<F1>[0m  for on-line help[18;18Htype  :help version9[34m<Enter>[0m   for version info[1;1H[24;1HVim: Error reading input, exiting...
Vim: Finished.
[24;1H, ) in agent shells
- Assume  is the repo (agents often start in  or )
- Source Fish config, Fish functions, or Fish-only PATH helpers

### Environment guarantees from agent-zsh / agent-bash
- 
-  / 
- Clean Homebrew +  PATH
- Auto-cd to  when launched from  or 
-  recommended in IDE automation env to avoid 1Password GUI prompts

Details: 

