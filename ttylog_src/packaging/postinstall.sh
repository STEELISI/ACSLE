#!/bin/sh
# Point sshd's ForceCommand at the installed scripts (idempotent, so upgrades are fine)
/usr/lib/acsle/install.sh --sshd-only
