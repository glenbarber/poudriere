#!/bin/sh

usage() {
	echo "poudriere createjail parameters [options]

Parameters:
    -j jailname -- Specifies the jailname
    -v version  -- Specifies which version of FreeBSD we want in jail
 
Options:
    -a arch     -- Indicates architecture of the jail: i386 or amd64
                   (Default: same as host)
    -m method   -- Method used to create jail, specify NONE if you want
                   to use your home made jail
                   (Default: FTP)
    -s          -- Installs the whole source tree, some ports may need it
                   (Default: install only kernel sources)"
	exit 1
}


ARCH=`uname -m`
REALARCH=${ARCH}
METHOD="FTP"

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

create_base_fs() {
	msg_n "Creating basefs:"
	zfs create -o mountpoint=${BASEFS:=/usr/local/poudriere} ${ZPOOL}/poudriere >/dev/null 2>&1 || err 1 " Fail" && echo " done"
}

fetch_file() {
		fetch -o $1 $2 || fetch -o $1 $2
}

#Test if the default FS for poudriere exists if not creates it
zfs list ${ZPOOL}/poudriere >/dev/null 2>&1 || create_base_fs

SRCS="ssys*"
SRCSNAME="ssys"

while getopts "j:v:a:z:m:sn:" FLAG; do
	case "${FLAG}" in
		j)
			NAME=${OPTARG}
			;;
		v)
			VERSION=${OPTARG}
			;;
		a)
			if [ "${REALARCH}" != "amd64" -a "${REALARCH}" != ${OPTARG} ]; then
				err 1 "Only amd64 host can choose another architecture"
			fi
			ARCH=${OPTARG}
			;;
		m)
			METHOD=${OPTARG}
			;;
		s)
			SRCS="s*"
			SRCSNAME="sources"
			;;
		*)
			usage
			;;
	esac
done

test -z ${NAME} && usage

if [ "${METHOD}" = "FTP" ]; then
	test -z ${VERSION} && usage
fi

# Test if a jail with this name already exists
zfs list -r ${ZPOOL}/poudriere/${NAME} >/dev/null 2>&1 && err 2 "The jail ${NAME} already exists"

JAILBASE=${BASEFS:=/usr/local/poudriere}/jails/${NAME}
# Create the jail FS
msg_n "Creating ${NAME} fs..."
zfs create -o mountpoint=${JAILBASE} ${ZPOOL}/poudriere/${NAME} >/dev/null 2>&1 || err 1 " Fail" && echo " done"

if [ ${VERSION%%.*} -lt 9 ]; then
	#We need to fetch base and src (for drivers)
	msg "Fetching base sets for FreeBSD ${VERSION} ${ARCH}"
	PKGS=`echo "ls base*"| ftp -aV ftp://${FTPHOST:=ftp.freebsd.org}/pub/FreeBSD/releases/${ARCH}/${VERSION}/base/ | awk '/-r.*/ {print $NF}'`
	mkdir ${JAILBASE}/fromftp

	for pkg in ${PKGS}; do
		# Let's retry at least one time
		fetch_file ${JAILBASE}/fromftp/ ftp://${FTPHOST}/pub/FreeBSD/releases/${ARCH}/${VERSION}/base/${pkg}
	done

	if [ ${ARCH} = "amd64" ]; then
		msg "Fetching lib32 sets for FreeBSD ${VERSION} ${ARCH}"
		PKGS=`echo "ls lib32*"| ftp -aV ftp://${FTPHOST:=ftp.freebsd.org}/pub/FreeBSD/releases/${ARCH}/${VERSION}/lib32/ | awk '/-r.*/ {print $NF}'`
		for pkg in ${PKGS}; do
			# Let's retry at least one time
			fetch_file ${JAILBASE}/fromftp/${pkg} ftp://${FTPHOST}/pub/FreeBSD/releases/${ARCH}/${VERSION}/lib32/${pkg}
		done
	fi

	msg "Fetching dict sets for FreeBSD ${VERSION} ${ARCH}"
	PKGS=`echo "ls dict*"| ftp -aV ftp://${FTPHOST:=ftp.freebsd.org}/pub/FreeBSD/releases/${ARCH}/${VERSION}/dict/ | awk '/-r.*/ {print $NF}'`
	for pkg in ${PKGS}; do
		# Let's retry at least one time
		fetch_file ${JAILBASE}/fromftp/${pkg} ftp://${FTPHOST}/pub/FreeBSD/releases/${ARCH}/${VERSION}/dict/${pkg}
	done


	msg "Extracting sets:"
	for SETS in ${JAILBASE}/fromftp/*.aa; do
		SET=`basename $SETS .aa`
		echo -e "\t- $SET...\c"
		cat ${JAILBASE}/fromftp/${SET}.* | tar --unlink -xpzf - -C ${JAILBASE}/ || err 1 " Fail" && echo " done"
	done
	rm ${JAILBASE}/fromftp/*

	msg "Fetching ${SRCSNAME} sets..."
	PKGS=`echo "ls ${SRCS}"| ftp -aV ftp://${FTPHOST:=ftp.freebsd.org}/pub/FreeBSD/releases/${ARCH}/${VERSION}/src/ | awk '/-r.*/ {print $NF}'`
	for pkg in ${PKGS}; do
		# Let's retry at least one time
		fetch_file ${JAILBASE}/fromftp/${pkg} ftp://${FTPHOST}/pub/FreeBSD/releases/${ARCH}/${VERSION}/src/${pkg}
	done

	msg "Extracting ${SRCSNAME}:"
	for SETS in ${JAILBASE}/fromftp/*.aa; do
		SET=`basename $SETS .aa`
		echo -e "\t- $SET...\c"
		cat ${JAILBASE}/fromftp/${SET}.* | tar --unlink -xpzf - -C ${JAILBASE}/usr/src || err 1 " Fail" && echo " done"
	done

	msg_n "Cleaning Up ${SRCSNAME} sets..."
	rm ${JAILBASE}/fromftp/*
	echo " done"
else
	msg "Fetching base.txz for FreeBSD ${VERSION} ${ARCH}"
	mkdir ${JAILBASE}/fromftp
	fetch_file ${JAILBASE}/fromftp/base.txz ftp://${FTPHOST}/pub/FreeBSD/releases/${ARCH}/${VERSION}/base.txz
	msg_n "Extracting base.txz..."
	tar -xpf ${JAILBASE}/fromftp/base.txz -C  ${JAILBASE}/ || err 1 " fail" && echo " done"
	if [ ${ARCH} = "amd64" ];then
		msg "Fetching lib32.txz for FreeBSD ${VERSION} ${ARCH}"
		fetch_file  ${JAILBASE}/fromftp/lib32.txz ftp://${FTPHOST}/pub/FreeBSD/releases/${ARCH}/${VERSION}/lib32.txz
		msg_n "Extracting lib32.txz for FreeBSD ${VERSION} ${ARCH}"
		tar -xpf ${JAILBASE}/fromftp/lib32.txz -C  ${JAILBASE}  || err 1 " fail" && echo " done"
	fi
	msg "Fetching src.txz for FreeBSD ${VERSION} ${ARCH}"
	fetch_file ${JAILBASE}/fromftp/src.txz ftp://${FTPHOST}/pub/FreeBSD/releases/${ARCH}/${VERSION}/src.txz
	msg_n "Extracting src.txz..."
	tar -xpf ${JAILBASE}/fromftp/src.txz -C  ${JAILBASE} || err 1 " fail" && echo " done"
	msg_n "Cleaning up..."
	rm -f ${JAILBASE}/fromftp/*
	echo " done"
fi

rmdir ${JAILBASE}/fromftp

OSVERSION=`awk '/\#define __FreeBSD_version/ { print $3 }' ${JAILBASE}/usr/include/sys/param.h`

LOGIN_ENV=",UNAME_r=${VERSION},UNAME_v=FreeBSD ${VERSION},OSVERSION=${OSVERSION}"

if [ "${ARCH}" = "i386" -a "${REALARCH}" = "amd64" ];then
	LOGIN_ENV="${LOGIN_ENV},UNAME_p=i386,UNAME_m=i386"
	cat > ${JAILBASE}/etc/make.conf << EOF
MACHINE=i386
MACHINE_ARCH=i386
EOF

fi

sed -i .back -e "s/:\(setenv.*\):/:\1${LOGIN_ENV}:/" ${JAILBASE}/etc/login.conf
cap_mkdb ${JAILBASE}/etc/login.conf
pwd_mkdb -d ${JAILBASE}/etc/ -p ${JAILBASE}/etc/master.passwd

cat >> ${JAILBASE}/etc/make.conf << EOF
USE_PACKAGE_DEPENDS=yes
BATCH=yes
WRKDIRPREFIX=/wrkdirs
EOF

mkdir -p ${JAILBASE}/usr/ports
mkdir -p ${JAILBASE}/wrkdirs
mkdir -p ${POUDRIERE_DATA}/packages/${NAME}/All
mkdir -p ${POUDRIERE_DATA}/logs

jail -U root -c path=${JAILBASE} command=/sbin/ldconfig -m /lib /usr/lib /usr/lib/compat

zfs snapshot ${ZPOOL}/poudriere/${NAME}@clean
msg "Jail ${NAME} ${VERSION} ${ARCH} is ready to be used"
