#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright Â© 2008-2018 ANSSI. All Rights Reserved.

BIN_PATH=${0%/*}
# Generic CLIP configuration backup script
# Copyright (C) 2007-2009 SGDN
# Copyright (C) 2012 ANSSI
# Authors:
#	Vincent Strubel <clipos@ssi.gouv.fr>
#	Mickaël Salaün <clipos@ssi.gouv.fr>
# All rights reserved.


usage() {
	echo "save.sh  [-V] [ -d <disk> ] [ -c <conf-dir> ] [clip1|clip2]"
	echo "options: "
	echo "   -d <disk> : use <disk> as root disk (default: /dev/sda)"
	echo "   -c <conf-dir> : use <conf-dir> as destination backup (default: /tmp/.conf)"
	echo "   -V : be more verbose"
}

################## MAIN ####################

CONF_BASE="/tmp/.conf"

while getopts Vd:c:h arg ; do
	case $arg in
		d)
			ROOT_DISK="${OPTARG}"
			;;
		c)
			CONF_BASE="${OPTARG}"
			;;
		V)
			VERBOSE="yes"
			;;
		h)
			usage
			exit 0
			;;
		*)
			ewarn "Unsupported option: ${arg}"
			usage
			exit 1
			;;
	esac
done
shift `expr $OPTIND - 1`

ROOT="/${1:-clip1}"

mkdir -p -- "${CONF_BASE}"

source /opt/clip-installer/clip-disk-common
DO_MOUNT_CLEANUP="YES"
trap cleanup EXIT INT

source "${BIN_PATH}/common.sh" || exit 1

mount_fs || error "Failed to mount filesystems"

save_ssh || error "Failed to save SSH host keys"

save_conf || error "Failed to save configuration"

# Migrate immutable keys to mutable ones
for k in "${CONF_BASE}/params/ike2_cert"/*.ppr; do
    if [[ -f "${k}" ]]; then
        einfo "Making immutable key $(basename ${k}) mutable"
        mv "${k}" "${CONF_BASE}/conf/ike2_cert/" || error "Failed to move ${k}"
    fi
done

trap - EXIT
cleanup
exit 0
