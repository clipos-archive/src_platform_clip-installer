#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2008-2018 ANSSI. All Rights Reserved.

BIN_PATH=${0%/*}
# Generic clip install-time configuration script
# Copyright (C) 2007-2008 SGDN
# Authors: 
#	Olivier Levillain <clipos@ssi.gouv.fr>
#	Vincent Strubel <clipos@ssi.gouv.fr>
# All rights reserved.

# configure.sh can be called standalone and should have a default CONF_PATH
[[ -z "${CONF_PATH}" ]] && CONF_PATH=${0%/*}
if [[ -z "${NOCONF}" ]]; then
	CONF_BASE="${CONF_PATH}"
else
	CONF_BASE="/tmp/.conf"
fi

if [[ -z "${2}" ]] ; then
	echo "You must pass the base mountpoint for CLIP"
	echo "and the clip 'species' (rm,single)"
	exit 1
fi

ROOT="${1}"
SPECIES="${2}"

source "${BIN_PATH}/common.sh" || exit 1

# configure.sh <root_path> <species>
#    where <root_path> can be /clip1 for example, and <species> "rm", "single", etc.
# the variables CONF_PATH, WITHRM, NOCONF and CLIP_BOOT_PART are given by install.sh

if [[ -z "${NOCONF}" ]]; then
	save_ssh || error "Failed to save SSH host keys"
else
	copy_ssh || error "Failed to copy SSH host keys"
fi


install_conf_1 || error "Primary configuration failed"
install_conf_2 || error "Secondary configuration failed"

if [[ -z "${NOCONF}" ]]; then
	CONF_BASE="/tmp/.conf"
	save_conf || error "Failed to save configuration"
fi

if [[ "${ROOT%2}" != "${ROOT}" ]]; then # Second install
	# Fixup bootloader versions after a full install
	VERS="$(grep 'CLIP, version precedente .*' "${ROOT}/boot/extlinux_5.conf")"
	VERS="${VERS##*version precedente }"
	if [[ -n "${VERS}" ]]; then
		sed -i -e "s:CLIP, version courante:CLIP, version courante ${VERS}:" \
			"${ROOT}/boot/extlinux_5.conf"
		sed -i -e "s:CLIP, version precedente:CLIP, version precedente ${VERS}:" \
			"${ROOT}/boot/extlinux_10.conf"
	fi
fi

DO_MOUNT_CLEANUP="YES"
source /opt/clip-installer/clip-disk-common
cleanup
exit 0

