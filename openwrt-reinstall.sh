#!/bin/bash

if [ "$1" == "" ]; then
    echo "Usage: $0 <config file>"
    exit 1
fi

set -x

. $1

CRED="$ROUTER_USER@$ROUTER_IP"

SSH="ssh $SSH_OPTS $CRED"

get_if_ip () {
    ifconfig $1 | awk -F ":|( +)" '
/inet addr/ { print $4; }
'
}

wait_for_if () {
    while true; do
        ip=`get_if_ip $1`
#        echo "ip=$ip="
        if [ -n "$ip" ]; then
            break
        fi
        sleep 1
    done
    echo $ip
}

wait_for_router () {
    local time1=`date +'%s'`

    while ! ping -c1 -W1 -q $ROUTER_IP >/dev/null; do
        echo -n .
        sleep 1
    done
    while ! ssh -o ServerAliveInterval=1 -o ServerAliveCountMax=6 $CRED true 2>/dev/null; do
        echo -n '*'
        sleep 2
    done
    echo
    local time2=`date +'%s'`
    echo "Router booted in $((time2 - time1)) seconds"
}

wait_for_reboot () {
    sleep 10
    set +x
    wait_for_if $LOCAL_IF
    wait_for_router
    set -ex
}

install_auth_keys () {
    scp ~/.ssh/authorized_keys $CRED:/etc/dropbear/
}

install_sys_image () {
    scp $IMAGE $CRED:/tmp/
    # Somehow, for non-interactive sessions, sbin path is not set
    # Expected to abort with timeout due to router reboot
    $SSH PATH=/bin:/sbin:/usr/bin:/usr/sbin sysupgrade /tmp/$IMAGE || true
}

install_usb_storage () {
    true
}


set +x
echo "Waiting for local interface..."
LOCAL_IP=`wait_for_if $LOCAL_IF`
echo "IP: $LOCAL_IP"
DNS=$LOCAL_IP
set -ex

install_auth_keys

install_sys_image
echo "Waiting for image to flash and router to reboot"
wait_for_reboot

set -e
PARTITION=/dev/sda1
$SSH <<EOF
set -xe
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
echo "Before install:"
df

#route add default gw $LOCAL_IP || true
# Install permanent route instead
uci set network.masq=route
uci set network.masq.interface=lan
uci set network.masq.target=0.0.0.0
uci set network.masq.netmask=0.0.0.0
uci set network.masq.gateway=192.168.2.247
uci set network.masq.metric=0
uci commit

echo "nameserver $DNS" >/tmp/resolv.conf
opkg update

# System-dependent USB drivers
opkg install kmod-usb-ohci kmod-usb2
# Generic USB device drivers
opkg install kmod-usb-storage
# USB support tools
opkg install usbutils
# External storage filesystems
opkg install kmod-fs-ext2
# OpenWRT tools for support external storage
opkg install block-mount block-hotplug block-extroot
# Due to some symbols conflict, ohci-hcd doesn't load automatically when package installed,
# so load it again manually
insmod /lib/modules/*/ohci-hcd.ko || true

uci set fstab.@mount[0].fstype=ext2
uci set fstab.@mount[0].options=rw,noatime
uci set fstab.@mount[0].target=/mnt/sda1
uci set fstab.@mount[0].is_rootfs=1
uci set fstab.@mount[0].enabled=1

uci set fstab.@swap[0].enabled=1

echo "Waiting for attached USB drive to be recognized"
sleep 10

# Init new rootfs with the contents of old
umount $PARTITION || true
umount /mnt/sda1 || true
mount $PARTITION /mnt/sda1 || { echo "Could not mount $PARTITION"; exit; }
# Remove everything except lost+found
rm -rf /mnt/sda1/[0-9A-Za-k]* /mnt/sda1/li* /mnt/sda1/[m-z]*
ls -l /mnt/sda1
tar -C /overlay -cf - . | tar -C /mnt/sda1 -xf -
echo =====
ls -l /mnt/sda1
umount /mnt/sda1

# script appear to return non-true
/etc/init.d/fstab enable || true
#/etc/init.d/fstab restart

echo "After install:"
df

echo "Rebooting router"
reboot

EOF

wait_for_reboot

echo "Router configured for extroot on USB drive"
