# Installing ttylog and the `acsle` CLI

ttylog records every interactive SSH session on a machine. It traces sshd with
strace, writes the terminal text to a trace file, and turns each session into
a CSV with one row per command. `acsle` is a read-only CLI to browse, search
and export those sessions.

Supported: Ubuntu/Debian, RHEL/Rocky/Fedora, Arch, openSUSE and Alpine.
Every distro here has been tested in containers.

## Install

```sh
git clone https://github.com/STEELISI/ACSLE.git
sudo ACSLE/ttylog_src/install.sh
```

`install.sh` does four things:
1. Installs the dependencies with the distro's package manager: `bash strace perl python3 openssh-server sudo procps make`.
2. Runs `make install`.
3. Sets sshd's `ForceCommand`.
4. Restarts sshd.

It is safe to run again, for example after a `git pull`, to upgrade.

**Keep your current SSH session open** until a new login works. `ForceCommand`
applies to every SSH login, including yours.

| Option | Use |
|---|---|
| `--no-restart` | Image builds (Dockerfile, Packer, chroot): the change applies when sshd first starts |
| `--no-deps` | Dependencies are already installed, or come from your own tooling |
| `--no-sshd` | Only install the files; set `ForceCommand` yourself |
| `--sshd-only` | Only (re)apply the sshd change |
| `--prefix DIR` | Install under `DIR` instead of `/usr` |
| `--uninstall [--purge]` | Undo the sshd change and remove the files. `--purge` also deletes `/etc/acsle` and all logs |

### In an image build

```dockerfile
# Dockerfile
RUN git clone https://github.com/STEELISI/ACSLE.git /opt/ACSLE \
 && /opt/ACSLE/ttylog_src/install.sh --no-restart
```

```yaml
# cloud-init
runcmd:
  - git clone https://github.com/STEELISI/ACSLE.git /opt/ACSLE
  - /opt/ACSLE/ttylog_src/install.sh
```

With Packer, Ansible or similar, run the same `install.sh --no-restart` as a shell step.

### As a package (.deb / .rpm / .apk / Arch)

You can also build native packages with [nfpm](https://nfpm.goreleaser.com):

```sh
cd ACSLE/ttylog_src
make packages VERSION=1.0.0      # writes dist/*.deb, *.rpm, *.apk, *.pkg.tar.zst
sudo apt install ./dist/acsle-ttylog_1.0.0_all.deb     # or dnf / apk / pacman
```

The package declares the dependencies, sets `ForceCommand` on install, and
removes it on uninstall (but not on upgrade).

## What goes where

| Path | Contents |
|---|---|
| `/usr/lib/acsle/` | `script.sh` (the `ForceCommand` target), `start_ttylog.sh`, `ttylog`, `analyze_continuous.py` |
| `/usr/bin/acsle` | CLI |
| `/etc/acsle/acsle.conf` | Log directories. An upgrade never overwrites it; new defaults go to `acsle.conf.new` |
| `/etc/ssh/sshd_config.d/50-acsle.conf` | The `ForceCommand`. If sshd has no `Include` of that directory, it goes in a `# BEGIN acsle` block in `sshd_config`, above any `Match` block, instead |
| `/var/log/ttylog/` | `ttylog.<host>.<user>.<N>.trace` (terminal text), `.err` (ttylog debug output), `count.<user>` |
| `/var/log/analyze_cont/` | `analyze.<user>.<N>.csv`, one row per command |

## Checking it works

Open a **new** SSH session and run a few commands, then `exit`. From another
session:

```sh
acsle sessions            # the session should be listed as "closed"
acsle show <N>            # one line per command
```

## Using `acsle`

Regular users see their own sessions. Use `sudo acsle`, or `--all`/`--user` if
the files are readable, to see everyone's.

```sh
acsle sessions [--since 2026-09-01]     # SESSION USER HOST START LAST-ACTIVITY CMDS STATUS
acsle show 12                           # commands with the first line of output
acsle show 12 --full                    # full output of every command
acsle trace 12                          # readable terminal replay (full-screen apps hidden)
acsle trace 12 --raw                    # the trace file as recorded
acsle grep 'nmap|ssh ' -i               # search commands across sessions
acsle grep secret --output              # ...and their output
acsle export --all --format csv -o all.csv         # one CSV with a header row
acsle export --user bob --format json              # or json / jsonl
```

Common filters: `-u/--user`, `-a/--all`, `--host`, and `-s/--session` for
`export`/`grep`. If the same session number exists for several users or hosts,
`show` and `trace` ask you to add `--user` or `--host`.

Export columns: `user, host, session, id, node, timestamp, time, cwd, command, output, prompt`.

## Uninstall

```sh
sudo ACSLE/ttylog_src/install.sh --uninstall           # keeps logs and /etc/acsle
sudo ACSLE/ttylog_src/install.sh --uninstall --purge   # deletes them too
```

## Requirements and limits

- Only users in the `sudo`, `wheel` or `root` group are logged, and they need
  passwordless sudo. Everyone else gets a plain unlogged shell.
- Prompts must look like the default `user@host:cwd$`.
- See `DEBUGGING_NOTES.md` for how the pipeline works and for known limitations.
