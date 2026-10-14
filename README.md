# ACSLE Software Repository

This is the code accompanying our SIGCSE 2020 paper "Using Terminal Histories to Monitor Student Progress on Hands-on Exercises". 

Full paper can be accessed at: http://www.isi.edu/~mirkovic/publications/sigcse2020.pdf

The monitoring code should run on RedHat Linux flavors but may not be 
portable to other OS-es. It uses strace to capture user command line input

The preprocess code is specific to Deterlab in the way it copies files to
output folders. On a different platform you would need to modify the 
destination folders.

The rest of the code should be portable to any platform.

For comments/questions please contact Jelena Mirkovic at sunshine@isi.edu.


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
| `--no-sshd` | Only install the files; the sshd config is not touched. Record sessions with `acsle-record` (see below) |
| `--sshd-only` | Only (re)apply the sshd change |
| `--prefix DIR` | Install under `DIR` instead of `/usr` |
| `--uninstall [--purge]` | Undo the sshd change and remove the files. `--purge` also deletes `/etc/acsle` and all logs |

### Without changing the sshd config (remote testbeds)

On testbeds where the sshd config must not change, for example when the
testbed's own tooling connects over SSH, install the files only and record a
session by hand:

```sh
# Session 1: install, then record
sudo ACSLE/ttylog_src/install.sh --no-sshd
acsle-record           # as yourself, not with sudo; opens a recorded shell
...                    # run the commands you want recorded
exit                   # stops recording and returns to your normal shell

# Session 2 (not recorded): check the result
acsle sessions
acsle show 0
```

Install and record on the machine whose sessions you want, for example an
experiment node, and reach it with a plain `ssh`. ttylog traces the sshd
process that owns your terminal, so `acsle-record` refuses to run in a
Jupyter, VS Code, tmux or screen terminal. On SPHERE/Merge, open the XDC's
Jupyter terminal, `ssh <node>`, then run `acsle-record` on the node.

sshd is never reconfigured or restarted, and no other login is affected.
Only the shell that `acsle-record` opens is recorded. To remove everything
later, run `sudo ACSLE/ttylog_src/install.sh --uninstall`. It only edits the
sshd config if an ACSLE `ForceCommand` is in it.

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
| `/usr/bin/acsle-record` | Records the current session by hand (for `--no-sshd` installs) |
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

```sh
acsle sessions        # list your sessions and their numbers
acsle show 3          # commands and output of session 3
acsle trace 3         # terminal replay of session 3
acsle grep nmap       # search commands across sessions
acsle export -o x.csv # merge sessions into one CSV (or --format json)
```

See **[COMMANDS.md](COMMANDS.md)** for every option, examples, recipes and common mistakes.

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

