#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2008-2018 ANSSI. All Rights Reserved.
# Common functions for CLIP installer
# Copyright 2008-2009 SGDN
# Copyright 2010-2014 ANSSI
# Authors:
#    Olivier Levillain <clipos@ssi.gouv.fr>
#    Vincent Strubel <clipos@ssi.gouv.fr>
#    Mickaël Salaün <clipos@ssi.gouv.fr>
# All rights reserved.

# TODO: Update clip-install-templates:config-tree.txt when configuration specs change!

BASE_PATH="/mnt/cdrom"

[[ -n "${BIN_PATH}" ]] || BIN_PATH=${0%/*}

source "/lib/rc/sh/functions.sh" # openRC

# Files copied from/to installation profile

# <prof>/params/conf.d -> <root>/etc/conf.d
declare -a PARAMS_CONF=( 
	clip
	ipsec
	net
	netconf
	power
	session/adeskbar
	session/openbox
	usermgmt
	user-ssh 
)

# <prof>/params -> </root>/etc
declare -a BASE_PARAMS=( 
	cryptd.algos
	strongswan.algos
	usbkeys.conf 
)

# XXX: ADMIN_CONF must be in sync with config-admin.sub!
# <prof>/conf -> /etc/admin/conf.d
declare -a ADMIN_CONF=( 
	devices 
	hostname 
	net 
	net-other 
	ntp 
	p11proxy 
	scdaemon 
	xscreensaver 
)

# XXX: AUDIT_CONF must be in sync with config-admin.sub!
# <prof>/conf/audit -> /etc/audit
declare -a AUDIT_CONF=( 
	logfiles 
	syslog
)


if [[ $? -ne 0 ]]; then
	einfo() {
		echo " $*"
	}
	ewarn() {
		echo " $*" >&2
	}
	ebegin() {
		echo " $* ..."
	}
	eend() {
		/bin/true
	}
	eindent() {
		/bin/true
	}
	eoutdent() {
		/bin/true
	}
fi

source "/opt/clip-installer/config-admin.sub"

error() {
	trap - EXIT
	ewarn "error: ${1}"
	cleanup 2>/dev/null || true
	exit 1
}


init_fs() {
	einfo "Creating filesystems (common)"
	eindent
	local root_map="${ROOT_DISK}"
	if [[ -n "${CRYPT}" ]]; then
		root_map="/dev/mapper${ROOT_DISK#/dev}"
	fi
	for i in ${DEV_LIST}; do
		einfo "${root_map}$i"
		mkfs.ext4 ${root_map}$i  1>/dev/null 2>/dev/null \
			|| error "mkfs failed for ${root_map}$i"
	done
	eoutdent
	# This is only reached on success
}

_bkp() {
	local dst_type="dir"
	# Rename option
	if [[ "$1" = "-f" ]]; then
		dst_type="file"
		shift
	fi
	local dst="$1"
	shift
	local gret=0 ret f
	[[ $# -gt 0 ]] || return 0

	einfo "into ${dst_type} ${dst}"
	eindent
	local f
	for f in "$@"; do
		if [[ -f "${f}" && ! -L "${f}" ]]; then
			ebegin "file ${f}"
			ret=0
			if [ "${dst_type}" == "dir" ]; then
				install -D -- "${f}" "${dst}/$(basename ${f})" || ret=1
			else
				install -D -- "${f}" "${dst}" || ret=1
			fi
			[[ ${ret} -ne 0 ]] && gret=1
			eend ${ret}
		fi
	done
	eoutdent
	return ${gret}
}

_bkp_from() {
	local dst="${1}"
	local base="${2}"
	shift 2

	einfo "into dir ${dst}"
	eindent
	local f fp
	for f in "$@"; do
		fp="${base}/${f}"
		if [[ -f "${fp}" && ! -L "${fp}" ]]; then
			ebegin "file ${fp}"
			ret=0
			install -D -- "${fp}" "${dst}/${f}" || ret=1
			[[ ${ret} -ne 0 ]] && gret=1
			eend ${ret}
		fi
	done
	eoutdent
	return ${gret}
}

save_update_certs() {
	# Figure out if we are using CCSD or Civil crypto
	if [[ -f "${ROOT}/update_root/etc/clip_update/keys/ctrl.bin" ]]; then
		einfo "Saving CCSD update certificates"
		eindent
		_bkp "${CONF_BASE}/params/update_keys" "${ROOT}/update_root/etc/clip_update/keys/"{ctrl,dev}.bin{,.txt} || ret=1
		eoutdent
	elif [[ -d "${ROOT}/update_root/etc/clip_update/keys/certs_ctrl/" ]]; then
		einfo "Saving Civil update certificates"
		eindent
		_bkp "${CONF_BASE}/params/update_keys/certs_dev" "${ROOT}/update_root/etc/clip_update/keys/certs_dev/"*.pem || ret=1
		_bkp "${CONF_BASE}/params/update_keys/certs_ctrl" "${ROOT}/update_root/etc/clip_update/keys/certs_ctrl/"*.pem || ret=1
		_bkp "${CONF_BASE}/params/update_keys/crl_dev" "${ROOT}/update_root/etc/clip_update/keys/crl_dev/"*.pem || ret=1
		_bkp "${CONF_BASE}/params/update_keys/crl_ctrl" "${ROOT}/update_root/etc/clip_update/keys/crl_ctrl/"*.pem || ret=1
		_bkp "${CONF_BASE}/conf/apt_host" "${ROOT}/etc/admin/clip_download/private/"*.pem || ret=1
		local trusted_ca_dev="$(readlink "${ROOT}/update_root/etc/clip_update/keys/certs_dev/trusted_ca_dev.pem")"
		local trusted_ca_ctrl="$(readlink "${ROOT}/update_root/etc/clip_update/keys/certs_ctrl/trusted_ca_ctrl.pem")"
		printf "TRUSTED_CA_DEV=%s\nTRUSTED_CA_CTRL=%s\n" "${trusted_ca_dev}" "${trusted_ca_ctrl}" \
			> "${CONF_BASE}/params/update_keys/trusted_ca.conf"
		eoutdent
	else
		eerror "Could not figure out if the installation is using CCSD or Civil crypto"
		return 1
	fi
}

save_conf() {
	local ret=0
	local retval=0
	local d

	einfo "Saving netconf profiles into ${CONF_BASE}/conf/netconf.d"
	eindent
	mkdir -p "${CONF_BASE}/conf/netconf.d" || ret=1
	[[ $ret -eq 0 ]] || retval=1
	ret=0
	for d in "${ROOT}/etc/admin/netconf.d/"*; do
		if [[ -d "${d}" ]]; then
			ebegin "directory ${d}"
			cp -r "${d}" "${CONF_BASE}/conf/netconf.d/$(basename "${d}")" || ret=1
			eend ${ret}
			[[ $ret -eq 0 ]] || retval=1
			ret=0
		fi
	done
	eoutdent

	einfo "Saving core configuration"
	eindent
	# conf.d files
	_bkp_from "${CONF_BASE}/conf" "${ROOT}/etc/admin/conf.d" ${ADMIN_CONF[@]} || ret=1
	_bkp_from "${CONF_BASE}/params/conf.d" "${ROOT}/etc/conf.d" ${PARAMS_CONF[@]} || ret=1
	# etc files
	_bkp_from "${CONF_BASE}/params" "${ROOT}/etc" ${BASE_PARAMS[@]} || ret=1
	_bkp "${CONF_BASE}/conf/clip_download" "${ROOT}/etc/admin/clip_download/sources.list."{clip,rm_{h,b}} || ret=1
	# audit files
	_bkp_from "${CONF_BASE}/conf/audit" "${ROOT}/etc/audit" ${AUDIT_CONF[@]} || ret=1
	# Optional packages
	_bkp -f "${CONF_BASE}/conf/optional.clip" "${ROOT}/etc/admin/clip_install/optional.conf.clip" || ret=1
	_bkp -f "${CONF_BASE}/conf/optional.rm_h" "${ROOT}/vservers/rm_h/admin_priv/etc.admin/clip_install/optional.conf.rm" || ret=1
	_bkp -f "${CONF_BASE}/conf/optional.rm_b" "${ROOT}/vservers/rm_b/admin_priv/etc.admin/clip_install/optional.conf.rm" || ret=1
	eoutdent

	einfo "Saving certs & keys"
	eindent
	_bkp "${CONF_BASE}/params/usb_keys" "${ROOT}/home/usb_keys/"{clip,rm_{h,b}}.pub || ret=1
	# Core update certificates
	save_update_certs || ret=1
	# XXX: for clip-hermes, there is only AC in etc/ike2/cert
	_bkp "${CONF_BASE}/params/ike2_cert" "${ROOT}/etc/ike2/cert/"* || ret=1
	_bkp "${CONF_BASE}/conf/ike2_cert" "${ROOT}/etc/admin/ike2/cert/"* || ret=1
	_bkp "${CONF_BASE}/conf/ike2_ca" "${ROOT}/etc/admin/ike2/cacerts/"* || ret=1
	_bkp "${CONF_BASE}/conf/ike2_host" "${ROOT}/etc/admin/ike2/private/"* || ret=1
	_bkp "${CONF_BASE}/conf/ike2_crl" "${ROOT}/etc/admin/ike2/crl/"* || ret=1
	# Legacy and new APT CA dir:
	_bkp "${CONF_BASE}/conf/apt_host" "${ROOT}/etc/admin/clip_download/cert"/apt.{key,cert}.pem || ret=1
	_bkp "${CONF_BASE}/conf/apt_host" "${ROOT}/etc/admin/clip_download/private/"* || ret=1
	_bkp "${CONF_BASE}/conf/apt_ca" "${ROOT}/etc/admin/clip_download"/{cert,cacerts}/* || ret=1
	# TODO: rename pkcs11_cert to pkcs11_ca as well
	_bkp "${CONF_BASE}/conf/pkcs11_cert" "${ROOT}/etc/admin/pkcs11/cacerts/"* || gret=1
	_bkp "${CONF_BASE}/conf/admin_pubkeys" "${ROOT}/home/adminclip/.ssh-remote/authorized_keys" || ret=1
	_bkp "${CONF_BASE}/conf/audit_pubkeys" "${ROOT}/home/auditclip/.ssh-remote/authorized_keys" || ret=1
	_bkp "${CONF_BASE}/conf/rm_h/tls_ca" "${ROOT}/vservers/rm_h/admin_priv/etc.admin/tls/cacerts/"* || ret=1
	for d in rm_h rm_b; do
		# Desktop: kde or xfce
		if echo "${CLIP_JAILS}" | grep -q "${d}"; then
			_bkp "${CONF_BASE}/conf/${d}" "${ROOT}/vservers/${d}/admin_priv/etc.admin/rm-session-type"  || ret=1
		fi
	done
	eoutdent

	[[ $ret -eq 0 ]] || retval=1
	ret=0

	return $retval
}

save_ssh() {
	local ret=0
	einfo "Saving CLIP SSH keys"
	eindent
	_bkp "/tmp/.ssh/admin_clip" "${ROOT}/mounts/admin_root/etc/ssh/"ssh_host* || ret=1
	_bkp "/tmp/.ssh/audit_clip" "${ROOT}/mounts/audit_root/etc/ssh/"ssh_host* || ret=1
	eoutdent
	return ${ret}
}

copy_ssh() {
	local ret=0
	einfo "Copying saved CLIP SSH keys"
	eindent
	_bkp "${ROOT}/mounts/admin_root/etc/ssh" "/tmp/.ssh/admin_clip/"ssh_host* || ret=1
	_bkp "${ROOT}/mounts/audit_root/etc/ssh" "/tmp/.ssh/audit_clip/"ssh_host* || ret=1
	chmod 600 "${ROOT}/mounts/admin_root/etc/ssh/"ssh_host*_key || ret=1
	chmod 644 "${ROOT}/mounts/admin_root/etc/ssh/"ssh_host*_key.pub || ret=1
	chmod 600 "${ROOT}/mounts/audit_root/etc/ssh/"ssh_host*_key || ret=1
	chmod 644 "${ROOT}/mounts/audit_root/etc/ssh/"ssh_host*_key.pub || ret=1
	eoutdent
	return ${ret}
}

# Install keys, directories and symlinks (c_rehash) for civil installs
install_civ_key_dir() {
	local ret=0
	local dir_src="${1}"
	local dir_dest="${2}"

	mkdir -p "${dir_dest}" || ret=1
	for f in "${dir_src}"/*; do
		if [[ -f "${f}" ]]; then
			einfo "$(basename "${f}")"
			install -D -o 0 -g 0 -m 0644 "${f}" "${dir_dest}/$(basename "${f}")" \
				|| ret=1
		else
			ewarn "Not a valid certificate file: ${f}"
			ret=1
		fi
	done
	c_rehash "${dir_dest}" || ret=1
	eend ${ret}
}

# Set designated certificate as trusted certificate for civil installs
install_civ_set_trusted_ca() {
	local dest="${1}"
	local ca="${2}"
	local linkname="${3}"

	pushd "${dest}" > /dev/null
	rm -f "${linkname}"
	if [[ -f "${ca}" ]]; then
		einfo "Setting '${ca}' as trusted certificate for '${dest}'"
		ln -s "${ca}" "${linkname}"
	else
		ewarn "Trusted developer certificate not valid/found: '${dest}/${ca}'"
		ret=1
	fi
	popd > /dev/null
}

# Install civil keys used to check package updates
# XXX: update save_update_certs function as well
install_keys_civil() {
	local ret=0
	local dest="${1}"
	local keypath="${2}"
	local trusted_ca="${3}"

	mkdir -p "${dest}" || ret=1
	install_civ_key_dir "${keypath}/certs_dev" "${dest}/certs_dev" || ret=1
	install_civ_key_dir "${keypath}/certs_ctrl" "${dest}/certs_ctrl" || ret=1
	install_civ_key_dir "${keypath}/crl_dev" "${dest}/crl_dev" || ret=1
	install_civ_key_dir "${keypath}/crl_ctrl" "${dest}/crl_ctrl" || ret=1

	source "${trusted_ca}"
	install_civ_set_trusted_ca "${dest}/certs_dev" "${TRUSTED_CA_DEV}" 'trusted_ca_dev.pem'
	install_civ_set_trusted_ca "${dest}/certs_ctrl" "${TRUSTED_CA_CTRL}" 'trusted_ca_ctrl.pem'

	eend ${ret}
}

# Install CCSD keys used to check package updates
# XXX: update save_update_certs function as well
install_keys_ccsd() {
	local ret=0
	local dest="${1}"
	local keypath="${2}"

	mkdir -p "${dest}" || ret=1
	eindent
	for f in "${keypath}"/{ctrl,dev}.bin{,.txt}; do
		if [[ -f "${f}" ]]; then
			einfo "$(basename "${f}")"
			install -D -o 0 -g 0 -m 0644 "${f}" "${dest}/$(basename "${f}")" \
				|| ret=1
		else
			ewarn "Not a valid update key file ${f}"
			ret=1
		fi
	done
	eoutdent
	eend $ret
}

# Install civil or CCSD keys used to check package updates
install_keys() {
	local dest="${1}"

	# Look for the path containing package upate keys (CCSD or civil).
	local keypath="${CLIP_MIRROR}/${CLIP_KEY_PATH}"
	keypath="${keypath##file://}"
	if [[ ! -d "${keypath}" ]]; then
		ewarn "No key found in mirror: ${keypath}"
		keypath="${CONF_PATH}/params/update_keys"
	fi
	einfo "Installing keys from '${keypath}' to '${dest}'"

	# Figure out if we are doing a CCSD or civil install. The 'trusted_ca.conf'
	# configuration file is only available in a civil install configuration
	# profile.
	local trusted_ca="${keypath}/trusted_ca.conf"
	if [ -f "${trusted_ca}" ]; then
		einfo "Installing civil certificates for package updates"
		install_keys_civil "${dest}" "${keypath}" "${trusted_ca}"
	else
		einfo "Installing CCSD certificates for package updates"
		install_keys_ccsd "${dest}" "${keypath}"
	fi
}

generate_knownhosts() {
	source "${ROOT}/etc/conf.d/jail-net"
	local kh_dest="${ROOT}/mounts/user_root/etc/known_hosts"

	local admin_key="${ROOT}/mounts/admin_root/etc/ssh/ssh_host_rsa_key.pub"
	local audit_key="${ROOT}/mounts/audit_root/etc/ssh/ssh_host_rsa_key.pub"

	if [[ ! -f "${kh_dest}" ]]; then
		if [[ -f "${admin_key}" ]]; then
			echo -n "${ADMIN_LOCAL_ADDR} " > "${kh_dest}"
			awk '{print $1" "$2}' "${admin_key}" >> "${kh_dest}" 
		fi
		if [[ -f "${audit_key}" ]]; then
			echo -n "${AUDIT_LOCAL_ADDR} " >> "${kh_dest}"
			awk '{print $1" "$2}' "${audit_key}" >> "${kh_dest}" 
		fi
	fi
	echo -n "OK"
}

# Install config files which may be saved from another install, or provided
# by the configuration tree
install_conf_1() {
	local ret=0
	local gret=0
	local d

	einfo "Importing first mutable configuration (conf directory)"
	eindent
	_install_confadmin_1 || gret=1
	eoutdent

	einfo "Importing first immutable configuration (params directory)"
	eindent
	# IKEv2 config
	_import_ike2 "immutable IKEv2 bundles" "params/ike2_cert" "etc/ike2/cert" || gret=1

	# RSA keys for USB export
	if [[ -d "${CONF_BASE}/params/usb_keys" ]]; then
		ebegin "Copying USB export keys"
		eindent
		for f in "${CONF_BASE}/params/usb_keys"/{clip,rm_{h,b}}.pub; do
			if [[ -f "${f}" ]]; then
				einfo "$(basename "${f}")"
				install -D -o 0 -g 0 -m 0400 "${f}" \
					"${ROOT}/home/usb_keys/$(basename "${f}")" || ret=1
			fi
		done
		eoutdent
		eend $ret
	fi
	[[ $ret -eq 0 ]] || gret=1
	ret=0

	# KnownHosts file for USER jail
	# Run in a subshell to avoid polluting env
	ebegin "Generating known hosts file"
	local retstr="$(generate_knownhosts)"
	if [[ "${retstr}" != "OK" ]]; then
		eend 1
		gret=1
	fi
	eoutdent
	return $gret
}

install_scripts() {
	local ret=0

	ebegin "Copying postinstall scripts in ${ROOT}"
	# Standard scripts
	cp -r "${BIN_PATH}/chroot_scripts" "${ROOT}/chroot_scripts" || ret=1
	chmod 755 "${ROOT}/chroot_scripts/"* || ret=1

	# Extra scripts (customized installer) to be run in the chroot target
	# after install
	if [[ -d "${BASE_PATH}/postinst_chroot_scripts" ]]; then 
		cp -r "${BASE_PATH}/postinst_chroot_scripts" "${ROOT}/postinst_scripts" || ret=1
		chmod 755 "${ROOT}/postinst_scripts/"* 2>/dev/null
	fi

	# Extra scripts (customized installer) to be run in the chroot target
	# after creating each user partition
	# Note that these will be left in place for later use by userd.
	if [[ -d "${BASE_PATH}/user_scripts" ]]; then 
		cp -r "${BASE_PATH}/user_scripts" "${ROOT}/etc/clip_useradd.d" || ret=1
		chmod 755 "${ROOT}/etc/clip_useradd.d/"* 2>/dev/null
	fi

	eend $ret
}

cleanup_scripts() {
	rm -fr "${ROOT}/chroot_scripts" "${ROOT}/postinst_scripts" "${ROOT}/etc/clip_userpostconf.d"
}

run_scripts() {
	if ! install_scripts; then
		ewarn "Failed to copy postinstall scripts, aborting user creation"
		return 1
	fi

	local ret=0
	if [[ -f "${CONF_PATH}/params/users.list"  && -z "${NOCONF}" ]]; then
		ebegin "Creating users in ${ROOT}"
		eindent
		cat "${CONF_PATH}/params/users.list" | while read line; do
			[[ -n "${line}" ]] || continue
			local username="$(echo "${line}" | awk '{print $1}')"
			local user_postconf="${CONF_PATH}/params/postconf-script/${username}"
			if [[ -d ${user_postconf} ]]; then
				mkdir "${ROOT}/etc/clip_userpostconf.d" || ret=1
				cp -r "${user_postconf}"/* "${ROOT}/etc/clip_userpostconf.d/" || ret=1
				chmod 755 "${ROOT}/etc/clip_userpostconf.d/"* || ret=1
			fi
			chroot "${ROOT}" "/chroot_scripts/create_user.sh" ${line} || ret=1
		done
		eoutdent
		eend $ret
	fi
	ret=0

	local arg="conf"
	[[ -n "${NOCONF}" ]] && arg="noconf"

	if [[ -d "${BASE_PATH}/postinst_scripts" ]]; then
		ebegin "Running post-install scripts in ${ROOT}"
		eindent
		for script in "${BASE_PATH}/postinst_scripts/"*; do
			[[ -f "${script}" ]] || continue # Script data must be in subdirs
			"${script}" "${ROOT}" "${arg}" || ret=1
		done
		eoutdent
		eend $ret
	fi

	if [[ -d "${ROOT}/postinst_scripts" ]]; then
		ebegin "Running chrooted post-install scripts in ${ROOT}"
		eindent
		for script in "${ROOT}/postinst_scripts/"*; do
			[[ -f "${script}" ]] || continue # Script data must be in subdirs
			local exe="$(basename "${script}")"
			einfo "${exe}"
			exe="/postinst_scripts/${exe}"
			chroot "${ROOT}" "${exe}" "${ROOT}" "${arg}" || ret=1
		done
		eoutdent
		eend $ret
	fi

	cleanup_scripts
}

# Install config files which are always provided by the configuration tree.
install_conf_2() {
	local ret=0
	local gret=0

	einfo "Importing second immutable configuration (params directory)"
	eindent

	ebegin "Copying base params"
	for f in ${BASE_PARAMS[@]}; do
		if [[ -f "${CONF_PATH}/params/${f}" ]]; then
			install -D -o 0 -g 0 "${CONF_PATH}/params/${f}" \
				"${ROOT}/etc/${f}" || ret=1
		fi
	done
	eend $ret
	[[ $ret -eq 0 ]] || gret=1
	ret=0

	if [[ -e "${CONF_PATH}/params/conf.d" ]]; then
		ebegin "Copying conf.d params"
		# XXX: update save_conf function as well
		for f in ${PARAMS_CONF[@]}; do
			if [[ -f "${CONF_PATH}/params/conf.d/${f}" ]]; then
				install -D -o 0 -g 0 "${CONF_PATH}/params/conf.d/${f}" \
					"${ROOT}/etc/conf.d/${f}" || ret=1
			fi
		done
		eend $ret
		[[ $ret -eq 0 ]] || gret=1
		ret=0
	fi

	# Add a direct boot on /dev/XX1 (assumed to be a developper partition)
	if [[ -e "${CONF_PATH}/params/extlinux.devel" ]]; then
		[[ -z "${CLIP_BOOT_PART}" ]] && CLIP_BOOT_PART="$(/bin/mount | head -n 1 | cut -d" " -f1)"
		einfo "Re-adding devel boot entry"
		for num in 5 10; do
			sed -i -e '/^IMPLICIT 0/d' ${ROOT}/boot/extlinux_${num}.conf || ret=1
			cat "${CONF_PATH}/params/extlinux.devel" \
				>> ${ROOT}/boot/extlinux_${num}.conf || ret=1
			sed -i -e "s:ROOTDEV:${CLIP_BOOT_PART}:" \
				${ROOT}/boot/extlinux_${num}.conf || ret=1
			echo 'IMPLICIT 0' >> "${ROOT}/boot/extlinux_${num}.conf" || ret=1
		done
		eend $ret
		ewarn "Note that this is a development option only"
		[[ $ret -eq 0 ]] || gret=1
		ret=0
	fi

	if [[ -d "${CONF_PATH}/params/update_keys" ]]; then
		ebegin "Installing UPDATE verification keys for CLIP"
		install_keys "${ROOT}/update_root/etc/clip_update/keys" || ret=1

		for jail in ${CLIP_JAILS}; do
			ebegin "Installing UPDATE verification keys in ${jail}"
			install_keys \
				"${ROOT}/vservers/${jail}/update_root/etc/clip_update/keys" \
				|| ret=1
		done
		[[ $ret -eq 0 ]] || gret=1
		ret=0
	fi


	einfo "Importing second mutable configuration (conf directory)"
	eindent
	_install_confadmin_2 || gret=1
	eoutdent

	# scripts
	run_scripts
	[[ $? -eq 0 ]] || gret=1

	# Permissions fixup
	chown -R 4000:4000 "${ROOT}/etc/admin/conf.d" || ret=1
	chmod -R u+w "${ROOT}/etc/admin/conf.d" || ret=1
	chown -R 4000:4000 "${ROOT}/etc/admin/netconf.d" || ret=1
	chmod -R u+w "${ROOT}/etc/admin/netconf.d" || ret=1
	find "${ROOT}/etc/admin/netconf.d/" -name hosts -exec chmod a+r '{}' \;
	find "${ROOT}/etc/admin/netconf.d/" -name hostname -exec chmod a+r '{}' \;
	find "${ROOT}/etc/admin/netconf.d/" -name proxy -exec chmod a+r '{}' \;
	find "${ROOT}/etc/admin/netconf.d/" -name resolv.conf -exec chmod a+r '{}' \;
	if [[ $ret -ne 0 ]]; then
		ewarn "Permission fixup failed"
		gret=1
	fi

	return $gret;
}
