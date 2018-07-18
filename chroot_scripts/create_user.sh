#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2008-2018 ANSSI. All Rights Reserved.

# Clip-installer user creation script.
# Copyright (C) 2010 ANSSI
# Author: 
#	Vincent Strubel <clipos@ssi.gouv.fr>
# All rights reserved.


export PATH="/bin:/sbin:/usr/bin:/usr/sbin"

source /lib/rc/sh/functions.sh
source /lib/clip/userkeys.sub
source /etc/conf.d/clip
source /etc/conf.d/user-ssh

FILL_DEVICE="/dev/zero"
CRYPT_ROUNDS="12"

EXTRA_USER_SCRIPTS_DIR="/etc/clip_useradd.d"
EXTRA_USER_POSTCONF_SCRIPTS_DIR="/etc/clip_userpostconf.d"

TMPMOUNT="/var/tmp/newuser"

###############################################################
#                  Command line parsing                       #
###############################################################

get_user_type() {
	case "${USER_TYPE}" in 
		user)
			MAIN_GROUP="crypthomes"
			EXTRA_GROUPS=""
			AUTH_KEYS=""
			HOST_KEYS=""
			DO_RM_JAILS="yes"
			;;
		privuser)
			MAIN_GROUP="priv_user"
			EXTRA_GROUPS="crypthomes,mount_update"
			AUTH_KEYS="${PUBKEY_COPIES["privuser"]}";
			HOST_KEYS="yes"
			DO_RM_JAILS="yes"
			;;
		nomad)
			MAIN_GROUP="nomad_user"
			EXTRA_GROUPS="priv_user,crypthomes,mount_update"
			AUTH_KEYS="${PUBKEY_COPIES["nomad"]}";
			HOST_KEYS="yes"
			DO_RM_JAILS="yes"
			;;
		admin)
			MAIN_GROUP="core_admin"
			EXTRA_GROUPS="crypthomes,mount_update"
			AUTH_KEYS="${PUBKEY_COPIES["admin"]}";
			HOST_KEYS="yes"
			DO_RM_JAILS="no"
			;;
		audit)
			MAIN_GROUP="core_audit"
			EXTRA_GROUPS="crypthomes"
			AUTH_KEYS="${PUBKEY_COPIES["audit"]}";
			HOST_KEYS="yes"
			DO_RM_JAILS="no"
			;;
		*)
			ewarn "Unsupported user type: ${utype}" >&2
			return 1;
			;;
	esac

	if [[ -n "${PKAUTH}" ]]; then
		if [[ -z "${EXTRA_GROUPS}" ]]; then
			EXTRA_GROUPS="pkauth"
		else
			EXTRA_GROUPS="${groups},pkauth"
		fi
	fi
}

parse_cmdline() {
	local line="${1}"
	local extra=""

	USER_NAME="$(echo "${line}" | awk '{print $1}')"
	USER_TYPE="$(echo "${line}" | awk '{print $2}')"
	USER_PW="$(echo "${line}" | awk '{print $3}')"
	RMH_SIZE="$(echo "${line}" | awk '{print $4}')"
	RMB_SIZE="$(echo "${line}" | awk '{print $5}')"
	extra="$(echo "${line}" | awk '{print $6}')"

	if [[ -z "${RMB_SIZE}" ]]; then
		ewarn "Incomplete command line" >&2
		ewarn "Expected format is <user name> <type> <password> <rmh size> <rmb size> [<extras>]">&2
		return 1
	fi

	if echo "${extra}" | grep -q "pkauth"; then
		PKAUTH="yes"
	fi

	get_user_type || return 1
}

###############################################################
#                  User account setup                         #
###############################################################

cleanup_account() {
	userdel "${USER_NAME}"
}

do_usermod() {
	einfo "Setting up password for user ${USER_NAME}"

	local phash
	phash="$(PASS="${USER_PW}" cryptpasswd --passvar "PASS" --rounds "${CRYPT_ROUNDS}")"
	if [[ -z "${phash}" ]]; then
		ewarn "do_usermod(): could not hash password for ${USER_NAME}" >&2
		return 1
	fi
	usermod -p "${phash}" ${USER_NAME}
	if [[ $? -ne 0 ]]; then
		ewarn "do_usermod(): usermod failed for ${USER_NAME}" >&2
		return 1
	fi
}

create_account() {
	ebegin "Creating account ${USER_NAME}"
	local grps=""
	[[ -n "${EXTRA_GROUPS}" ]] && grps="-G ${EXTRA_GROUPS}"

	useradd -N -d "/home/user" -g "${MAIN_GROUP}" ${grps} "${USER_NAME}"
	if [[ $? -ne 0 ]]; then
		ewarn "useradd ${USER_NAME} failed" >&2
		eend 1
		return 1
	fi
	do_usermod 
	eend $?
}

###############################################################
#                  Partition initialization                   #
###############################################################

cleanup_mount() {
	umount "${TMPMOUNT}"
	cryptsetup remove "tmp"
	losetup -d "/dev/loop7"
	rmdir "${TMPMOUNT}"
}

create_partition_init() {
	local prefix="${1}"
	local size="${2}"

	mkdir -p "${prefix}/keys" "${prefix}/parts" || return 1

	local setfile="${prefix}/keys/${USER_NAME}.settings"
	local keyfile="${prefix}/keys/${USER_NAME}.key"
	local imgfile="${prefix}/parts/${USER_NAME}.part"

	if [ -z "${prefix}" ]; then
		ewarn "Prefix not set" >&2
		return 1
	fi

	create_settings "${USER_NAME}" "${setfile}"
	if [[ $? -ne 0 ]]; then
		ewarn "Create settings failed" >&2
		return 1
	fi
	local key="$(tr -cd '[:graph:]' < "/dev/urandom" 2>/dev/null | head -c 119)"
	local num="$(echo -n "${key}" | wc -c)"
	if [[ $num -ne 119 ]]; then
		ewarn "Wrong key length: $num" >&2
		return 1
	fi

	echo -n "${key}" |\
		PASS="${USER_PW}" encrypt_stage2_key "${setfile}" \
			"PASS" "${keyfile}" "pw"
	if [[ $? -ne 0 ]]; then
		ewarn "Key encryption failed" >&2
		return 1
	fi

	fallocate -l ${size}M ${imgfile} || \
	dd if="${FILL_DEVICE}" of="${imgfile}" bs=1M count="${size}" 1>/dev/null 2>/dev/null 
	if [[ $? -ne 0 ]]; then
		ewarn "dd failed" >&2
		return 1
	fi
	losetup /dev/loop7 "${imgfile}"
	if [[ $? -ne 0 ]]; then
		ewarn "losetup failed" >&2
		return 1
	fi


	echo -n "${key}" | cryptsetup create -c aes-lrw-benbi \
				-s 384 -h sha256 "tmp" /dev/loop7

	if [ ! -e "/dev/mapper/tmp" ] ; then
		ewarn "cryptsetup error" >&2
		return 1
	fi

	mkfs.ext4 -Ouninit_bg -Elazy_itable_init=1,lazy_journal_init=1 \
				"/dev/mapper/tmp" 1>/dev/null 2>/dev/null
	if [[ $? -ne 0 ]]; then
		ewarn "mkfs failed" >&2
		return 1
	fi

	mkdir -p "${TMPMOUNT}"
	mount "/dev/mapper/tmp" "${TMPMOUNT}"
	if [[ $? -ne 0 ]]; then
		ewarn "mount failed" >&2
		return 1
	fi
	chown -R "${USER_NAME}:${MAIN_GROUP}" "${TMPMOUNT}" || return 1
	chmod 700 "${TMPMOUNT}" || return 1
}

create_partition_fini() {
	cleanup_mount
}

###############################################################
#                  SSH keys handling                          #
###############################################################

create_authkeys_file() {
	local keyfile="${1}"
	local keydir="$(dirname "${keyfile}")"

	[[ -e "${keyfile}" ]] && return 0

	mkdir -p "${keydir}" || return 1
	touch "${keyfile}" || return 1
	chown -R 0:0 "${keydir}" || return 1
	chmod 755 "${keydir}" || return 1
	chmod 644 "${keyfile}" || return 1
}

setup_user_key() {
	mkdir "${TMPMOUNT}/.ssh" || return 1
	chown "${USER_NAME}:${MAIN_GROUP}" "${TMPMOUNT}/.ssh" || return 1
	su "${USER_NAME}" -c "/usr/local/bin/ssh-keygen -t rsa -N '' -b 2048 -f ${TMPMOUNT}/.ssh/id_rsa" 1>/dev/null|| return 1
	chmod 400 "${TMPMOUNT}/.ssh"/* || return 1

	for authkey in ${AUTH_KEYS}; do
		create_authkeys_file "${authkey}/.ssh/authorized_keys" || return 1
		cat "${TMPMOUNT}/.ssh/id_rsa.pub" >> "${authkey}/.ssh/authorized_keys" || return 1
	done
}

setup_pubkeys() {
	if [[ "${HOST_KEYS}" == "yes" ]]; then
		ln -sf "/etc/known_hosts" "${TMPMOUNT}/.ssh/known_hosts" || return 1
	fi
}

###############################################################
#                  Extra scripts at user creation             #
###############################################################

run_extra_scripts() {
	local name="${1}"
	local size="${2}"
	local ret=0

	if [[ -d "${EXTRA_USER_SCRIPTS_DIR}" ]]; then
		for script in "${EXTRA_USER_SCRIPTS_DIR}"/*; do
			[[ -x "${script}" ]] || continue

			"${script}" "${TMPMOUNT}" "${USER_NAME}" "${USER_TYPE}" "${name}" "${size}"
			if [[ $? -ne 0 ]]; then
				ewarn "Script ${script} returned an error" >&2
				ret=1
			fi
		done
	fi

	if [[ -d "${EXTRA_USER_POSTCONF_SCRIPTS_DIR}" ]]; then
		for script in "${EXTRA_USER_POSTCONF_SCRIPTS_DIR}"/*; do
			[[ -f "${script}" && -x "${script}" ]] || continue

			"${script}" "${TMPMOUNT}" "${USER_NAME}" "${USER_TYPE}" "${name}" "${size}" "${EXTRA_USER_POSTCONF_SCRIPTS_DIR}"
			if [[ $? -ne 0 ]]; then
				ewarn "Postconf script ${script} returned an error" >&2
				ret=1
			fi
		done
	fi
				
	return $ret
}

###############################################################
#                  Full partition setup                       #
###############################################################


create_partition() {
	local prefix="${1}"
	local size="${2}"
	local name="${3}"
	local ret=0

	ebegin "Creating ${name} partition of size ${size}"
	if ! create_partition_init "${prefix}" "${size}"; then
		ewarn "Failed to initialize partition" >&2
		cleanup_mount
		return 1
	fi

	# we only provide the SSH key to non user accesible containers (e.g. USER)
	if [[ -n "${AUTH_KEYS}" && "${name##RM_}" == "${name}" ]]; then
		setup_user_key || ret=1
		setup_pubkeys || ret=1
	fi

	run_extra_scripts "${name}" "${size}" 

	create_partition_fini
	eend $ret
}

########################################
#                  MAIN                #
########################################

cleanup_partitions() {
	for base in "/home" "/home/rm_h" "/home/rm_b"; do
		for f in "keys/${USER_NAME}.key" "keys/${USER_NAME}.settings" "parts/${USER_NAME}.part"; do
			rm -f "${base}/${f}"
		done
	done
}

if ! parse_cmdline "$*"; then
	ewarn "Failed to parse command line $*" >&2
	exit 1
fi

einfo "Creating ${USER_TYPE} account \"${USER_NAME}\""
eindent

if ! create_account; then
	eoutdent
	cleanup_account
	exit 1
fi

if ! create_partition "/home" "8" "CLIP"; then
	eoutdent
	cleanup_account
	cleanup_partitions
	exit 1
fi

if [[ "${DO_RM_JAILS}" == "no" ]]; then
	einfo "User ${USER_NAME} created successfully"
	eoutdent
	exit 0
fi

if echo "${CLIP_JAILS}" | grep -qw "rm_h"; then
	if ! create_partition "/home/rm_h" "${RMH_SIZE}" "RM_H"; then
		cleanup_account
		cleanup_partitions
		eoutdent
		exit 1
	fi
fi

if echo "${CLIP_JAILS}" | grep -qw "rm_b"; then
	if ! create_partition "/home/rm_b" "${RMB_SIZE}" "RM_B"; then
		cleanup_account
		cleanup_partitions
		eoutdent
		exit 1
	fi
fi

einfo "User ${USER_NAME} created successfully"
eoutdent
exit 0
