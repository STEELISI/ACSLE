# ttylog / analyze_continuous — debugging notes

Last updated: 2026-09-14

## Status

**Fixed and verified on the testbed.** SSH sessions are now fully recorded
in the trace file, and `analyze_continuous.py` writes one CSV row per
command, including the last one (`exit`).

The changes were first made by hand on a testbed, in the installed copies
under `/usr/local/src/`. They were then applied to `ttylog_src/` on the
`feat/rithvik_fix` branch of the fork `RithvikR1218/ACSLE`. That branch's
files were checked against the "Validating a commit" section below, and
still need an end-to-end run on a fresh testbed installed from the branch.

Only two files changed: `start_ttylog.sh` and `analyze_continuous.py`.
`script.sh` and `ttylog/ttylog` (the Perl script) are unchanged.

The project goal is to record **commands and their output**, not file
contents. File changes are meant to be tracked with git and are out of
scope, which is why the GitHub upload feature is disabled and the contents
of full-screen editors are dropped.

## How the pipeline works

```
sshd ForceCommand
  -> /usr/local/src/script.sh
       -> bash -l -O huponexit /usr/local/src/start_ttylog.sh
            start_up():
              - picks a session number (CNT) from /var/log/ttylog/count.$USER
              - writes 3 header lines to the trace:
                  starting session w tty_sid:$CNT
                  User prompt is $USER@<short hostname>
                  Home directory is $HOME
            background job 1: setsid sudo ttylog <pts>
              ttylog (Perl) finds the sshd process for the pts with `ps fauwwx`, then runs
              strace -e read,write ... -p <sshd pid> -o "|ttylog -r - -o -"
              and a second ttylog process decodes the syscalls into terminal text
              -> appended to /var/log/ttylog/ttylog.<host>.<user>.<N>.trace
              -> ttylog's own debug messages go to .../ttylog.<host>.<user>.<N>.err
            background job 2: setsid sudo python3 analyze_continuous.py <trace> <csv>
              follows the trace and writes one row per command
              -> /var/log/analyze_cont/analyze.<user>.<N>.csv
            foreground: interactive `bash` (the user's shell)
            on exit, clean_up():
              - appends `END tty_sid:$CNT` to the trace
              - waits up to 5 s for analyze_continuous.py to exit on its own, then kills it if needed
```

CSV columns: `id, node_name, timestamp, cwd, command, output (wrapped in %), prompt`.
The `id` starts with `edulog` because the Emulab nickname file no longer
exists, and that is the fallback name.

## Root cause of the original bug

Symptom: the trace had the header, the first prompt and the first typed
character, then nothing until `END tty_sid:N`. No CSV rows were produced.

Cause: `start_ttylog.sh` is a non-interactive script, so it has no job
control. `sudo ... &` started both background jobs (ttylog and
analyze_continuous.py) in the terminal's **foreground** process group,
attached to the user's terminal. The script then started the interactive
`bash`, which took over the terminal. On the first keystroke, the
background `sudo` processes tried to use a terminal they no longer
controlled and terminated their commands. Both jobs died silently
(stderr was sent to `/dev/null`).

Fix: start both jobs with `setsid ... < /dev/null`, so they run in their
own session with no controlling terminal.

What was ruled out along the way, each by a direct test:
- sshd/kernel: a manual `strace -p <sshd pid>` showed the read/write
  syscalls continuing for the whole session.
- The ttylog decoder: `ttylog -r <saved raw trace>` decoded a full session
  correctly.
- ptrace permissions and ttylog's sshd PID and file-descriptor detection:
  all worked in every clean test.
- The pipe between strace and the decoder, and self-monitoring: running
  `sudo ttylog <pts> &` by hand from an interactive shell recorded
  everything live, whether it watched the same session or a different one.
- A live check (`ps`) showed no strace, ttylog or analyze_continuous.py
  processes left in sessions where capture had stopped. They had died,
  not stalled.

Useful way to find the sshd process for a session:
`ps fauwwx | grep -B2 'pts/N'`. The target is the `sshd: <user>@pts/N` line,
not the `sshd: <user> [priv]` line.

## Changes made

### start_ttylog.sh (installed at /usr/local/src/start_ttylog.sh)

#### S1. Session counter survives reboots

Ubuntu clears `/tmp` at boot, so the counter restarted at 0 and new
sessions were appended to old trace and CSV files with the same number.
The counter now lives in `/var/log/ttylog/`. Existing numbers are skipped,
so the migration needs no manual step and a deleted counter file can't
cause numbers to be reused. The counter file is root-only; it is no longer
world-writable.

Replaced the whole `if $sudo [ -e "/tmp/count.$USER" ]; then ... fi` block in `start_up()` with:
```sh
    COUNTFILE=/var/log/ttylog/count.$USER
    if $sudo [ -e "$COUNTFILE" ]; then
        CNT=$($sudo cat $COUNTFILE)
        let CNT++
    else
        CNT=0
    fi
    while $sudo [ -e "/var/log/ttylog/ttylog.$HN.$USER.$CNT.trace" ]; do
        let CNT++
    done
    echo $CNT | $sudo tee $COUNTFILE > /dev/null
```

#### S2. Separate error log for ttylog

Added right after `$sudo chmod ugo+rw $LOGPATH` in `start_up()`:
```sh
    ERRPATH=/var/log/ttylog/ttylog.$HN.$USER.$CNT.err
    $sudo touch $ERRPATH
    $sudo chmod ugo+rw $ERRPATH
```
The file is created through sudo because the `2>>` redirect in S4 is
opened by the user's shell, and `/var/log/ttylog/` is owned by root.

#### S3. Prompt header

`${PS1@P}` expanded to nothing, because `PS1` isn't set in a
non-interactive script. The analyzer takes the last word of this line as
the prompt, so it got `is` and could not split commands. `prompt.sh` in
the repo root is an old experiment with the same broken line and is not
used.

From:
```sh
    echo "User prompt is ${PS1@P}" >> $LOGPATH
```
to:
```sh
    echo "User prompt is ${USER}@${HN%%.*}" >> $LOGPATH
```
This writes `user@shorthost`, matching Ubuntu's default `\u@\h` prompt.

#### S4. Launch ttylog detached (the main fix)

From:
```sh
    $sudo /usr/local/src/ttylog/ttylog $TTY >> $LOGPATH 2>/dev/null &
```
to:
```sh
    setsid $sudo /usr/local/src/ttylog/ttylog $TTY >> $LOGPATH 2>> $ERRPATH < /dev/null &
```

#### S5. Launch analyze_continuous.py detached

From:
```sh
    $sudo python3 /usr/local/src/analyze_continuous.py ${LOGPATH} ${CONTCSVPATH} 2>/dev/null &
```
to:
```sh
    setsid $sudo python3 /usr/local/src/analyze_continuous.py ${LOGPATH} ${CONTCSVPATH} 2>/dev/null < /dev/null &
```
`PID_CONTCSV=$!` on the next line still holds the sudo PID. The background
child isn't a process group leader, so setsid replaces itself with sudo
instead of forking.

#### S6. clean_up() waits for the analyzer instead of killing it immediately

Killing it right after writing `END` meant the last two rows (the final
command before `exit`, and `exit`) were never written.

In `clean_up()`, from:
```sh
        PSTRING_KILL=$(ps -o args -p ${PID_CONTCSV} --no-headers 2>/dev/null)
        if [[ $PSTRING_KILL =~ ${CONTCSVPATH} ]]; then
            $sudo kill ${PID_CONTCSV} 2>/dev/null
        fi
```
to:
```sh
        for i in $(seq 1 50); do
            PSTRING_KILL=$(ps -o args -p ${PID_CONTCSV} --no-headers 2>/dev/null)
            [[ $PSTRING_KILL =~ ${CONTCSVPATH} ]] || break
            sleep 0.1
        done
        if [[ $PSTRING_KILL =~ ${CONTCSVPATH} ]]; then
            $sudo kill ${PID_CONTCSV} 2>/dev/null
        fi
```
The annotator and intervention kill blocks after it are unchanged. The
ttylog/strace job needs no cleanup: when the session ends, sshd exits, so
strace and the decoder exit too.

### analyze_continuous.py (installed at /usr/local/src/analyze_continuous.py)

#### P1. Ignore what full-screen programs draw

Text drawn by `nano`, `vim`, `less`, etc. was parsed as terminal output,
so a trace file opened in `nano` produced fake command rows. The content
between the alternate-screen codes `ESC[?1049h` and `ESC[?1049l` is now
removed before parsing. The command that opened the program is still
recorded, with empty output.

Added directly above `def get_ttylog_lines_from_file`:
```python
in_alternate_screen = False

def remove_alternate_screen(data):
    """Remove text drawn by full-screen programs (nano, vim, less) while they use the alternate screen"""
    global in_alternate_screen
    kept = []
    while data:
        if in_alternate_screen:
            end = data.find('\x1b[?1049l')
            if end == -1:
                break
            data = data[end + len('\x1b[?1049l'):]
            in_alternate_screen = False
        else:
            start = data.find('\x1b[?1049h')
            if start == -1:
                kept.append(data)
                break
            kept.append(data[:start])
            data = data[start + len('\x1b[?1049h'):]
            in_alternate_screen = True
    return ''.join(kept)
```
In `get_ttylog_lines_from_file`, from:
```python
    ttylog_read_data = ttylog_read_data.replace(r'\"','"')
    ttylog_lines = ttylog_read_data.split('\n')
```
to:
```python
    ttylog_read_data = ttylog_read_data.replace(r'\"','"')
    ttylog_read_data = remove_alternate_screen(ttylog_read_data)
    ttylog_lines = ttylog_read_data.split('\n')
```

#### P2. Only this session's own END line ends the session

Any displayed text containing `END tty_sid` (for example another session's
trace) was treated as the end. After P6 that would stop the analyzer.

Both occurrences (one in `get_ttylog_lines_to_decode`, one in the main loop), from:
```python
        if r'END tty_sid' in line:
```
```python
            if r'END tty_sid' in line:
```
to (same indentation as before):
```python
        if line.rstrip().endswith('END ' + current_session_id):
```
```python
            if line.rstrip().endswith('END ' + current_session_id):
```
`current_session_id` is like `tty_sid:14`, taken from the header. This
relies on session numbers being unique, which S1 provides.

#### P3. A prompt needs a `$` (or `#`) after `user@host:`

Before, any line containing `user@host:` counted as a prompt and was then
split on `$`/`#`. A line without one raised `ValueError`, and the analyzer
died silently. Ordinary output like `bash: rithvikr1218@a:/tmp: No such
file or directory` or `git remote -v` triggered it.

In the main loop, from:
```python
            command_pattern_user_prompt = re.compile("{}:.*?".format(user_initial_prompt.casefold())) 
            command_pattern_root_prompt = re.compile("{}:.*?".format(root_prompt.casefold()))
```
to:
```python
            command_pattern_user_prompt = re.compile(r"{}:[^$]*\$".format(re.escape(user_initial_prompt.casefold())))
            command_pattern_root_prompt = re.compile(r"{}:[^#]*#".format(re.escape(root_prompt.casefold())))
```

#### P4. Leftover prompt no longer appended to output

Each command's output ended with an extra `user@host` line: the start of
the next command's line, which `get_ttylog_lines_to_decode` includes when
it releases a batch.

From:
```python
            elif not end:
                output_txt += '\n'+line
```
to:
```python
            elif not end:
                if line.strip().casefold() not in (user_initial_prompt, root_prompt.casefold()):
                    output_txt += '\n'+line
```
Side effect: an output line that is exactly the bare prompt text
(e.g. `echo rithvikr1218@a`) is dropped.

#### P5. GitHub upload disabled

The script crashed at startup because `/var/emulab/boot/nickname` no
longer exists after the infrastructure migration. Uploading changed files
is out of scope.

From:
```python
    github_local_user_directory, github_global_user_directory = get_github_user_directory(github_repo_name='upload_modified_files', local_dir_to_clone_github='/tmp/')
```
to:
```python
    github_local_user_directory, github_global_user_directory = None, None
```
All other GitHub code is skipped when these are `None`. The functions are
left in the file unused. `get_unique_id_dict()` already handles the missing
nickname file (`exp_name = 'edulog'`).

#### P6. Analyzer exits after END

`exit_flag` was checked every loop but never set, so the analyzer ran
forever and had to be killed.

In the main loop's END branch (`# End, save what we can`), after the
`if cline >=0:` block, added one line at the same indentation as
`cline = ...` (16 spaces):
```python
                exit_flag = True
```
Result:
```python
            else:
                # End, save what we can
                if len(output_txt) > 500:
                    output_txt = output_txt[:500]
                unique_row_pid = ...
                cline = len(ttylog_sessions[current_session_id]['lines']) - 1
                if cline >=0:
                    ttylog_sessions[current_session_id]['lines'][cline]['output'] = output_txt
                    write_to_csv(ttylog_sessions[current_session_id]['lines'][cline])
                    #logfile ... (commented lines unchanged)
                exit_flag = True
```

## Install instructions (corrected)

The original instructions copied `script.sh` to the wrong directory.

```sh
sudo apt update && sudo apt install strace -y
git clone -b feat/rithvik_fix https://github.com/RithvikR1218/ACSLE.git   # fixed branch (fork)
sudo mkdir -p /usr/local/src/ttylog /var/log/ttylog
sudo cp ACSLE/ttylog_src/analyze_continuous.py /usr/local/src/
sudo cp ACSLE/ttylog_src/ttylog/ttylog /usr/local/src/ttylog/
sudo cp ACSLE/ttylog_src/start_ttylog.sh /usr/local/src/
sudo cp ACSLE/ttylog_src/script.sh /usr/local/src/        # was /usr/local/src/ttylog/ (wrong)
sudo chmod +x /usr/local/src/script.sh /usr/local/src/start_ttylog.sh /usr/local/src/ttylog/ttylog

sudo su
echo "" >> /etc/ssh/sshd_config
echo 'ForceCommand /usr/local/src/script.sh "$SSH_ORIGINAL_COMMAND"' >> /etc/ssh/sshd_config
echo "" >> /etc/ssh/sshd_config
systemctl restart sshd
```
Assumptions: Ubuntu, bash, the default `user@host:cwd$` prompt, and
passwordless sudo for every user who should be logged (see Open items).

## Validating a commit

### 0. If you edited the installed files on a server, copy them into the clone first

Edits made in `/usr/local/src/` are not in the git clone. Before committing
from a server, copy them back into the clone and check the diff:
```sh
cp /usr/local/src/start_ttylog.sh ~/ACSLE/ttylog_src/start_ttylog.sh
cp /usr/local/src/analyze_continuous.py ~/ACSLE/ttylog_src/analyze_continuous.py
cd ~/ACSLE && git diff --stat
```
Expected: only `ttylog_src/start_ttylog.sh` and `ttylog_src/analyze_continuous.py` changed.

### 1. Static checks (run from the repo root)

```sh
bash -n ttylog_src/start_ttylog.sh && echo "start_ttylog.sh syntax OK"
python3 -m py_compile ttylog_src/analyze_continuous.py && echo "analyze_continuous.py syntax OK"

grep -c 'setsid \$sudo' ttylog_src/start_ttylog.sh                    # 2   (S4, S5)
grep -c '< /dev/null &' ttylog_src/start_ttylog.sh                    # 2   (S4, S5)
grep -c '2>> \$ERRPATH' ttylog_src/start_ttylog.sh                    # 1   (S4)
grep -c 'ERRPATH=/var/log/ttylog' ttylog_src/start_ttylog.sh          # 1   (S2)
grep -c 'User prompt is \${USER}@\${HN%%.\*}' ttylog_src/start_ttylog.sh   # 1 (S3)
grep -c 'PS1@P' ttylog_src/start_ttylog.sh                            # 0   (S3)
grep -c 'COUNTFILE=/var/log/ttylog/count' ttylog_src/start_ttylog.sh  # 1   (S1)
grep -c '/tmp/count' ttylog_src/start_ttylog.sh                       # 0   (S1)
grep -c 'seq 1 50' ttylog_src/start_ttylog.sh                         # 1   (S6)

grep -c 'remove_alternate_screen' ttylog_src/analyze_continuous.py            # 2 (P1: def + call)
grep -c "endswith('END ' + current_session_id)" ttylog_src/analyze_continuous.py   # 2 (P2)
grep -c "r'END tty_sid' in line" ttylog_src/analyze_continuous.py             # 0 (P2)
grep -c 're.escape(' ttylog_src/analyze_continuous.py                         # 2 (P3)
grep -c 'not in (user_initial_prompt, root_prompt.casefold())' ttylog_src/analyze_continuous.py   # 1 (P4)
grep -c 'github_global_user_directory = None, None' ttylog_src/analyze_continuous.py   # 1 (P5)
grep -c 'exit_flag = True' ttylog_src/analyze_continuous.py                   # 1 (P6)
```
`py_compile` may print `SyntaxWarning: invalid escape sequence` for lines
like `'.*\^C'` and `";\d{9}"`. Those lines were already in the original
code and still work. Only a `SyntaxError` means something is broken.

These counts and a synthetic-trace run were checked against a copy of the
original files with every change above applied (2026-09-14): all counts
matched, the fake `echo` and foreign `END` inside a full-screen program
were ignored, `echo "bob@a:/tmp"` didn't crash the analyzer, and it exited
by itself after `END`.

Also read the diff for indentation: `exit_flag = True` must be inside the
END `else:` branch, and the P4 `if` must be under `elif not end:`. An
indentation mistake still compiles but behaves wrongly.

### 2. End-to-end tests (on the testbed, after installing the committed files)

Use a new SSH session for each test. To find the latest session's files:
```sh
N=$(ls -t /var/log/ttylog/*.trace | head -1 | sed 's/.*\.\([0-9]*\)\.trace/\1/')
sudo cat -v /var/log/ttylog/*.$USER.$N.trace
sudo cat /var/log/ttylog/*.$USER.$N.err
sudo cat /var/log/analyze_cont/analyze.$USER.$N.csv
ps aux | grep -E 'analyze_continuous|strace' | grep -v grep
```

| Test | Commands in the session | Expected |
|---|---|---|
| Basic capture | `ls`, `pwd`, `echo hello`, `exit` | Trace has every command and output, then `END tty_sid:N`. Header says `User prompt is <user>@<shorthost>`. No `DEBUG:` lines in the trace (they're in `.err`). CSV has 4 rows, `exit` included. No trailing `user@host` line in outputs. No analyzer or strace left running afterwards. |
| Processes detached | Mid-session, from another shell: `ps -eo pid,sid,tty,stat,args \| grep -E 'strace\|ttylog/ttylog\|analyze_continuous' \| grep -v grep` | strace, the ttylog decoder and analyze_continuous.py are alive, and the TTY column shows `?`. |
| Full-screen program (P1) | `ls`, `nano <some old .trace file>` (type or paste the path, don't use Tab), quit with Ctrl-X, `pwd`, `exit` | The `nano` row has empty output. No fake rows from the file's contents. |
| Crash protection (P3) | `echo "<user>@<shorthost>:/tmp"`, `pwd`, `exit` | The `echo` row's output is `<user>@<shorthost>:/tmp`, and the `pwd` and `exit` rows exist. |
| Foreign END line (P2) | `grep END /var/log/ttylog/*.$USER.<older N>.trace`, `ls`, `exit` | Rows for `grep`, `ls` and `exit` all exist. |
| Counter (S1) | `sudo cat /var/log/ttylog/count.$USER` after logging in | Equals this session's N, which is one higher than the previous session. After `sudo rm /var/log/ttylog/count.$USER` and a new login, N is the next unused number, not 0. |

### Results observed on 2026-09-14 (testbed host `a`, user `rithvikr1218`)

- Session 13: first full capture after S4/S5.
- Session 14: CSV correct after S2/S3/P5, but missing the last two rows (fixed by S6/P6).
- Session 17: counter continued correctly after S1. P2 held with trace 15 shown in `nano`. It also exposed the fake-row and tab-completion issues.
- Session with `ls`, `pwd`, `echo test`, `nano ...15.trace`, `exit`: 5 correct rows, empty `nano` output, no trailing prompts, analyzer exited (P1, P4, P6).
- Session with `rithvikr1218@a:/tmp` (as a command), `echo "rithvikr1218@a:/tmp"`, `pwd`, `exit`: 4 correct rows. The bash error output containing `user@host:` didn't crash the analyzer (P3).

## Known limitations and open items (not addressed yet)

1. **Users without sudo are not logged.** `start_ttylog.sh` runs `exec bash`
   with no logging and no warning for users outside the `sudo`/`wheel`/`root`
   groups. The pipeline also requires sudo without a password prompt. If
   students don't have sudo, they are not being recorded, and fixing that
   needs a root-owned service to do the attaching.
2. **Log privacy.** Trace, `.err` and CSV files are readable by all users,
   and trace/`.err` files are also writable by all (`chmod ugo+rw`). Traces
   contain everything shown on screen, including visibly typed secrets
   such as `export API_KEY=...`. How much tighter permissions help depends
   on item 1: any user with sudo can read them anyway. The logging is not
   tamper-proof, since a sudo user can kill their own strace.
3. **tmux/screen sessions are not recorded.** They use the alternate
   screen, so P1 drops everything inside them. They already recorded
   poorly before, because the shell inside tmux runs on a different
   terminal that isn't traced directly.
4. **Tab completion creates fake rows.** A double-Tab listing is recorded
   as a command that never ran, with the listing as its output. Possible
   fix: bash sends `ESC[?2004l` only when Enter is pressed, so only treat a
   prompt line as a command when that follows it. This depends on bash's
   bracketed paste being on (the default on current Ubuntu).
5. **Replayed prompt text still creates fake rows.** Plain `cat` of a trace
   file (not a full-screen program) inside a logged session prints real-
   looking prompts. P2/P3 stop it from ending the session or crashing the
   analyzer, but fake rows remain.
6. **Prompt assumptions.** Only the default `user@shorthost:cwd$` /
   `root@shorthost:cwd#` prompts are recognized. Custom `PS1`, zsh, or
   prompts ending in `>`/`%` won't be split into commands.
7. **Session number reuse across users.** Counters are per user, so user A's
   session 5 and user B's session 5 share an `END tty_sid:5` line. Only
   matters if someone displays another user's trace.
8. **CSV timestamps are processing time.** The `timestamp` column is
   `int(time.time())` when the analyzer handles the line, not the
   `;<epoch>` value in the trace. During a live session they're within about
   a second of each other. If `analyze_continuous.py` is re-run later on an
   old trace, every row gets the re-run time. The trace's own timestamp is
   already parsed into `line_timestamp` and could be used instead.
9. Minor: output is still capped at 500 characters per command (original
   behavior), and `TTY EOF` plus `DEBUG:` lines go to the `.err` file.
