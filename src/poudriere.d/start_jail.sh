#!/bin/sh

usage() {
	echo "poudriere startjail -n name"
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

. /etc/rc.subr
. /etc/defaults/rc.conf

while getopts "n:" FLAG; do
	case "${FLAG}" in 
		n)
		NAME=${OPTARG}
		;;
		*)
		usage
		;;
	esac
done

test -z ${NAME} && usage

zfs list ${ZPOOL}/poudriere/${NAME} >/dev/null 2>&1 || err 1 "No such jail"

test -z ${IP} && err 1 "No IP defined for poudriere"

if [ "${USE_LOOPBACK}" = "yes" ]; then
        LOOP=0
        while :; do
		LOOP=$(( LOOP += 1))
		ifconfig lo${LOOP} create > /dev/null 2>&1 && break
        done
	msg "Adding loopback lo${LOOP}"
        ifconfig lo${LOOP} inet ${IP} > /dev/null 2>&1
else
        /usr/sbin/jls ip4.addr | egrep "^${IP}$" > /dev/null && err 2 "Configured IP is already in use by another jail."
	test -z ${ETH} && err 1 "No ethernet device defined for poudriere"
fi

MNT=`zfs list -H -o mountpoint ${ZPOOL}/poudriere/${NAME}`
msg "Mounting devfs"
devfs_mount_jail "${MNT}/dev"
if [ ! "${USE_LOOPBACK}" = "yes" ]; then
	msg "Adding IP alias"
	ifconfig ${ETH} inet ${IP} alias > /dev/null 2>&1
fi
msg "Starting jail ${NAME}"
jail -c persist name=${NAME} path=${MNT} host.hostname=${NAME} ip4.addr=${IP}
