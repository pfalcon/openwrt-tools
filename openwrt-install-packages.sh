#!/bin/bash

if [ "$1" == "" ]; then
    echo "Usage: $0 <config file>"
    exit 1
fi

set -x

set -e
. $1

CRED="$ROUTER_USER@$ROUTER_IP"
SSH="ssh $SSH_OPTS $CRED"
set +e

$SSH <<EOF
set -xe
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
opkg update

# USB CDC ACM communication driver, used for modems and other stuff (e.g. TI Launchpad)
opkg install kmod-usb-acm

# Normal less with '/' (search regexp) command, need to overwrite
# busybox' version
opkg install --force-overwrite less
# Something may crash or misbehave, always have debugging tools
opkg install gdb strace
# The language. If readline package is not installed, "import readline" will segfault
opkg install python libreadline

# Bluez, etc. require DBus
opkg install dbus dbus-utils dbus-python
# If already enabled, returns 1
/etc/init.d/dbus enable || true
/etc/init.d/dbus start || true

# It's all about connectivity - Bluetooth
opkg install kmod-bluetooth bluez-libs bluez-utils bluez-hcidump python-bluez
/etc/init.d/bluez-utils enable || true
/etc/init.d/bluez-utils start || true

# The above is enough to run remote-version0.1.py client for PS3 BT BD Remote
# (will handle adhoc "pairing" on its own).

EOF

if [ $? -ne 0 ]; then
    echo "ERROR: Installation failed"
fi
