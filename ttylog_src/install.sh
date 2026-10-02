#!/bin/sh
#
# Installs the ACSLE ttylog pipeline on Debian/Ubuntu, RHEL/Rocky/Fedora,
# Arch, openSUSE and Alpine, and points sshd's ForceCommand at it.
#
#   sudo ./install.sh                 full install + sshd config + sshd restart
#   sudo ./install.sh --no-restart    for image builds (Dockerfile, Packer, chroot)
#   sudo ./install.sh --uninstall     undo the sshd change and remove the files (keeps logs)
#
# Run ./install.sh --help for all options.

set -eu

PREFIX=/usr
DO_DEPS=1
DO_FILES=1
DO_SSHD=1
DO_RESTART=1
UNINSTALL=0
PURGE=0

SSHD_CONFIG=/etc/ssh/sshd_config
DROPIN_DIR=/etc/ssh/sshd_config.d
DROPIN=$DROPIN_DIR/50-acsle.conf
BLOCK_BEGIN="# BEGIN acsle"
BLOCK_END="# END acsle"

SRC_DIR=$(cd "$(dirname "$0")" && pwd)

usage() {
    cat <<EOF
Usage: sudo $0 [options]

  --no-deps      don't install packages (strace, perl, python3, ...)
  --no-sshd      don't change the sshd config
  --sshd-only    only change the sshd config (files already installed)
  --no-restart   don't restart sshd (image builds; takes effect on next boot)
  --prefix DIR   install prefix (default /usr -> /usr/lib/acsle, /usr/bin/acsle)
  --uninstall    remove the sshd config and installed files; logs are kept
  --purge        with --uninstall, also delete /etc/acsle and all logs
  -h, --help     show this help
EOF
}

log()  { echo "acsle: $*"; }
warn() { echo "acsle: WARNING: $*" >&2; }
die()  { echo "acsle: ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case $1 in
        --no-deps)    DO_DEPS=0 ;;
        --no-sshd)    DO_SSHD=0 ;;
        --sshd-only)  DO_DEPS=0; DO_FILES=0 ;;
        --no-restart) DO_RESTART=0 ;;
        --prefix)     [ $# -ge 2 ] || die "--prefix needs a directory"; PREFIX=$2; shift ;;
        --uninstall)  UNINSTALL=1 ;;
        --purge)      PURGE=1 ;;
        -h|--help)    usage; exit 0 ;;
        *)            usage >&2; die "unknown option: $1" ;;
    esac
    shift
done

LIBDIR=$PREFIX/lib/acsle
FORCE_LINE="ForceCommand $LIBDIR/script.sh \"\$SSH_ORIGINAL_COMMAND\""

[ "$(id -u)" -eq 0 ] || die "must be run as root (use sudo)"

install_deps() {
    # bash: the scripts need it (Alpine has only busybox sh)
    # procps: ttylog runs `ps fauwwx`, which busybox ps doesn't support
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y \
            bash strace perl python3 openssh-server sudo procps make
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y bash strace perl python3 openssh-server sudo procps-ng make
    elif command -v yum >/dev/null 2>&1; then
        yum install -y bash strace perl python3 openssh-server sudo procps-ng make
    elif command -v zypper >/dev/null 2>&1; then
        zypper --non-interactive install bash strace perl python3 openssh sudo procps make
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm --needed bash strace perl python openssh sudo procps-ng make
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache bash strace perl python3 openssh-server sudo procps make
    else
        die "no supported package manager found; install bash strace perl python3 openssh-server sudo procps make yourself and rerun with --no-deps"
    fi
}

find_sshd() {
    for s in "$(command -v sshd 2>/dev/null || true)" /usr/sbin/sshd /usr/bin/sshd; do
        [ -n "$s" ] && [ -x "$s" ] && { echo "$s"; return; }
    done
    die "sshd not found; install openssh-server"
}

# `sshd -t` needs host keys, which image builds usually don't have yet.
# Test with a throwaway key instead of generating real ones into the image.
sshd_test() {
    sshd_bin=$(find_sshd)
    mkdir -p /run/sshd 2>/dev/null || true   # Debian's privilege separation dir
    if ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
        "$sshd_bin" -t
    else
        tmpdir=$(mktemp -d)
        ssh-keygen -q -t ed25519 -N "" -f "$tmpdir/key"
        rc=0
        "$sshd_bin" -t -h "$tmpdir/key" || rc=$?
        rm -rf "$tmpdir"
        return $rc
    fi
}

# Remove our drop-in, our marked block, and ForceCommand lines from the old manual install
remove_sshd_config() {
    rm -f "$DROPIN"
    sed -i \
        -e "/^$BLOCK_BEGIN\$/,/^$BLOCK_END\$/d" \
        -e '/^[[:space:]]*ForceCommand[[:space:]].*\/usr\/local\/src\/ttylog\/script\.sh/d' \
        "$SSHD_CONFIG"
}

has_dropin_include() {
    grep -Eq "^[[:space:]]*Include[[:space:]]+$DROPIN_DIR/\*\.conf" "$SSHD_CONFIG"
}

configure_sshd() {
    [ -f "$SSHD_CONFIG" ] || die "$SSHD_CONFIG not found; install openssh-server"
    [ -x "$LIBDIR/script.sh" ] || die "$LIBDIR/script.sh is missing or not executable"

    cp -p "$SSHD_CONFIG" "$SSHD_CONFIG.acsle.bak"
    remove_sshd_config

    if has_dropin_include; then
        # The Include sits near the top and sshd keeps the first value it
        # sees, so this applies to every login regardless of Match blocks.
        mkdir -p "$DROPIN_DIR"
        printf '# Managed by ACSLE install.sh; remove with install.sh --uninstall\n%s\n' \
            "$FORCE_LINE" > "$DROPIN"
        where=$DROPIN
    else
        # Lines after a Match block only apply to that block, so go before the first one
        tmp=$(mktemp)
        awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" -v f="$FORCE_LINE" '
            !done && tolower($1) == "match" { print b; print f; print e; print ""; done = 1 }
            { print }
            END { if (!done) { print ""; print b; print f; print e } }
        ' "$SSHD_CONFIG" > "$tmp"
        cat "$tmp" > "$SSHD_CONFIG"
        rm -f "$tmp"
        where=$SSHD_CONFIG
    fi

    if ! sshd_test; then
        cp -p "$SSHD_CONFIG.acsle.bak" "$SSHD_CONFIG"
        rm -f "$DROPIN"
        die "sshd rejected the new config; restored $SSHD_CONFIG"
    fi
    log "ForceCommand set in $where (backup: $SSHD_CONFIG.acsle.bak)"
}

unconfigure_sshd() {
    [ -f "$SSHD_CONFIG" ] || return 0
    cp -p "$SSHD_CONFIG" "$SSHD_CONFIG.acsle.bak"
    remove_sshd_config
    if ! sshd_test; then
        cp -p "$SSHD_CONFIG.acsle.bak" "$SSHD_CONFIG"
        die "sshd rejected the config after removing ACSLE; restored $SSHD_CONFIG"
    fi
    log "removed ACSLE ForceCommand from the sshd config"
}

restart_sshd() {
    if [ "$DO_RESTART" -eq 0 ]; then
        log "not restarting sshd (--no-restart); the change applies when sshd next starts"
        return
    fi
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        # Debian/Ubuntu call the unit ssh, everyone else sshd
        for unit in ssh sshd; do
            if systemctl list-unit-files "$unit.service" 2>/dev/null | grep -q "^$unit\.service"; then
                systemctl restart "$unit"
                log "restarted $unit"
                return
            fi
        done
    elif command -v rc-service >/dev/null 2>&1 && rc-service sshd status >/dev/null 2>&1; then
        rc-service sshd restart
        log "restarted sshd"
        return
    fi
    warn "could not find a running sshd service; restart sshd yourself"
}

if [ "$UNINSTALL" -eq 1 ]; then
    if [ "$DO_SSHD" -eq 1 ]; then
        unconfigure_sshd
        restart_sshd
    fi
    if [ "$DO_FILES" -eq 1 ]; then
        rm -rf "$LIBDIR"
        rm -f "$PREFIX/bin/acsle" /etc/acsle/acsle.conf.new
        if [ "$PURGE" -eq 1 ]; then
            rm -rf /etc/acsle /var/log/ttylog /var/log/analyze_cont /var/log/annotator
            log "removed files, config and logs"
        else
            log "removed files; kept /etc/acsle and the logs in /var/log (use --purge to delete them)"
        fi
    fi
    exit 0
fi

if [ "$DO_DEPS" -eq 1 ]; then
    install_deps
fi

if [ "$DO_FILES" -eq 1 ]; then
    command -v make >/dev/null 2>&1 || die "make not found; install it or rerun without --no-deps"
    make -C "$SRC_DIR" install PREFIX="$PREFIX"
    log "installed to $LIBDIR and $PREFIX/bin/acsle"
    if [ -e /etc/acsle/acsle.conf.new ]; then
        log "kept your /etc/acsle/acsle.conf; new defaults are in acsle.conf.new"
    fi
fi

if [ "$DO_SSHD" -eq 1 ]; then
    configure_sshd
    restart_sshd
    warn "every new SSH login now goes through $LIBDIR/script.sh."
    warn "keep this session open until a fresh login works."
fi
