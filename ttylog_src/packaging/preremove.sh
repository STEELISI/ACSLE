#!/bin/sh
# Only undo the sshd change on a real removal, not on an upgrade
case "$1" in
    upgrade|1|2) exit 0 ;;   # deb: "upgrade"; rpm: remaining package count
esac
/usr/lib/acsle/install.sh --uninstall --sshd-only
