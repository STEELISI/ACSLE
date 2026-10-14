# `acsle` command reference

`acsle` is a read-only tool for browsing the SSH sessions that ttylog records.
It never changes or deletes logs.

```
acsle sessions    list recorded sessions (alias: acsle ls)
acsle show N      commands and output of session N
acsle trace N     terminal replay of session N
acsle grep PAT    search commands across sessions
acsle export      merge sessions into one CSV / JSON file
```

Run `acsle <command> -h` to see the options for any command.

## The basic workflow

Sessions are numbered per user: 0, 1, 2, ... Find the number with `sessions`,
then pass it to `show` or `trace`.

```sh
$ acsle sessions
SESSION  USER          HOST  START                LAST ACTIVITY        CMDS  STATUS
0        rithvikr1218  a     2026-09-14 10:02:11  2026-09-14 10:05:40  8     closed
1        rithvikr1218  a     2026-09-14 11:20:03  2026-09-14 11:31:17  9     closed
2        rithvikr1218  a     2026-09-25 09:12:45  2026-09-25 09:14:02  4     open

$ acsle show 1
Session 1 of rithvikr1218@a, started 2026-09-14 11:20:03 (closed)
   1  11:20:05  ~$ ls /
      bin   dev     etc   lib  ...  (+1 lines)
   2  11:20:09  ~$ echo hello world
      hello world
   3  11:20:12  ~$ cd /tmp
   4  11:20:14  /tmp$ pwd
      /tmp
   ...
```

`STATUS` is `closed` once the session has logged out. `open` means the
session is still running, or it ended without the logger writing its final
line (for example, the machine rebooted).

`CMDS` is `-` when the session has no CSV. You can still read it with `acsle trace N`.

## Who and what you can see

- **Default:** your own sessions only. You never need `-u yourname`.
- **`--all` / `-a`:** every user's sessions, if the log files are readable.
- **`-u USER`:** one specific user.
- **`sudo acsle ...`:** root sees every user by default.
- **`--host HOST`:** only needed when the same session number exists for the
  same user on more than one host. This happens only if logs from several
  machines are collected in one directory. Both the short name (`a`) and the
  full name (`a.infra.exp.proj`) work.

`show` and `trace` tell you when a number is ambiguous and which `--user` or
`--host` to add.

## `acsle sessions`

```sh
acsle sessions                     # your sessions
acsle ls                           # same thing
acsle sessions --since 2026-09-01  # only sessions started on or after this date
sudo acsle sessions                # everyone's sessions
acsle sessions -u alice            # one other user's sessions
```

## `acsle show N`

Shows one line per command: time, working directory, command, and the first
line of its output. A `(+k lines)` note means the output has more lines.

```sh
acsle show 3               # summary
acsle show 3 -f            # full output of every command
acsle show 3 -u alice      # alice's session 3
acsle show 3 | less        # page through a long session
```

Only the first 500 characters of each command's output are stored (a limit
in the analyzer). Use `acsle trace` to see everything.

## `acsle trace N`

Replays everything the user saw in the terminal, in a readable form. It hides
the escape codes and timestamps, and puts `[full-screen program output hidden]`
in place of full-screen programs such as `nano`, `vim` and `less`.

```sh
acsle trace 3              # readable replay
acsle trace 3 | less -R    # page through it
acsle trace 3 --raw        # the trace file exactly as recorded, escape codes included
acsle trace 3 | tail -20   # last part of a session
```

Use `trace` when `show` looks wrong or incomplete: it's the source that `show`
is built from.

## `acsle grep PATTERN`

Searches the commands in every session you can see. `PATTERN` is a Python
regular expression, so quote it. Each match prints as
`user:session  time  cwd$ command`.

```sh
acsle grep nmap                    # every command containing "nmap"
acsle grep -i 'ssh |scp '          # ssh or scp, case-insensitive
acsle grep '^sudo'                 # commands that start with sudo
acsle grep -o 'Permission denied'  # also search command OUTPUT
acsle grep -s 3 rm                 # only in session 3
sudo acsle grep -a 'passwd'        # across all users
```

The exit code is 1 when nothing matches, so it works in scripts:
`acsle grep nmap > /dev/null && echo "nmap was used"`.

## `acsle export`

Merges sessions into one file with a single header row. Unlike the raw
`analyze.*.csv` files, the export uses standard `"` quoting, so it opens
directly in Excel, pandas, etc.

```sh
acsle export > mine.csv                          # all your sessions as CSV
acsle export -o mine.csv                         # same, written with -o
acsle export -s 3 --format json                  # session 3 as a JSON array
sudo acsle export --format jsonl -o all.jsonl    # everyone, one JSON object per line
acsle export -u alice --format csv -o alice.csv  # one user
```

Columns: `user, host, session, id, node, timestamp, time, cwd, command, output, prompt`.
`timestamp` is Unix epoch; `time` is the same value as local date/time.

> Note: `-o` means **output file** for `export`, but **search output too** for
> `grep`.

## Recipes

```sh
# What did a student do today?
sudo acsle sessions -u alice --since $(date +%F)
sudo acsle show 12 -u alice -f

# Which users ran a given tool?
sudo acsle grep -a 'nmap' | cut -d: -f1 | sort -u

# Count commands per user, in Python
sudo acsle export --format csv -o all.csv
python3 -c "import pandas as pd; print(pd.read_csv('all.csv').groupby('user').size())"

# Watch a live session's CSV fill in
watch -n 2 'acsle show 4 | tail -15'
```

## Common mistakes

| You typed | Problem | Instead |
|---|---|---|
| `acsle show` | The session number is required | `acsle sessions`, then `acsle show N` |
| `acsle show session 0` | `session` in the help text is a placeholder, not a word to type | `acsle show 0` |
| `acsle show -u me --host a 0` | Works, but both flags are the defaults | `acsle show 0` |
| `acsle show --h a 0` | `--h` could mean `--help` or `--host` | `--host a` (or `--ho a`) |
| `acsle grep a|b` | The shell treats `|` as a pipe | Quote it: `acsle grep 'a|b'` |
| `No sessions found.` | You're only seeing your own sessions | `--all`, `-u USER`, or `sudo` |
| `permission denied (try sudo)` | The log file isn't readable by you | `sudo acsle ...` |

## Where the data comes from

| File | Used by |
|---|---|
| `/var/log/ttylog/ttylog.<host>.<user>.<N>.trace` | `sessions`, `trace` |
| `/var/log/analyze_cont/analyze.<user>.<N>.csv` | `show`, `grep`, `export` |

Both directories are set in `/etc/acsle/acsle.conf` (`TRACE_DIR`, `CSV_DIR`).
To browse logs copied off a machine, point `acsle` at another config:

```sh
cat > /tmp/copy.conf <<EOF
TRACE_DIR=/path/to/copied/ttylog
CSV_DIR=/path/to/copied/analyze_cont
EOF
ACSLE_CONF=/tmp/copy.conf acsle sessions --all
```
