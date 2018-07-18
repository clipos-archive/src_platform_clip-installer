#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2008-2018 ANSSI. All Rights Reserved.

export BIN_PATH=${0%/*}
# Generic clip installer script
# Copyright (C) 2007-2008 SGDN/DCSSI
# Copyright (C) 2010-2012 SGDSN/ANSSI
# Authors:
#	Olivier Levillain <clipos@ssi.gouv.fr>
#	Vincent Strubel <clipos@ssi.gouv.fr>
#	Mickaël Salaün <clipos@ssi.gouv.fr>
# All rights reserved.

PERSONNALITY="${0}"
# Default config
[[ -z "${ROOT_DISK}" ]] && ROOT_DISK=/dev/sda
[[ -z "${CLIP_MIRROR}" ]] && CLIP_MIRROR=http://mirror.clip/debian
[[ -z "${DEBOOTSTRAP_BASE}" ]] && DEBOOTSTRAP_BASE=/usr/lib/debootstrap
[[ -z "${BIND_MOUNT_BOOT}" ]] && BIND_MOUNT_BOOT=yes
[[ -z "${CONF_PATH}" ]] && CONF_PATH=$BIN_PATH

CRYPT=""

if [[ -f "${CONF_PATH}/params/conf.d/clip" ]]; then
	source "${CONF_PATH}/params/conf.d/clip"
else
	CLIP_JAILS=""
	# Compat mode: CLIP-RM with 2 RM jails
	[[ -n "${WITH_RM}" ]] && CLIP_JAILS="rm_h rm_b"
fi

. "/opt/clip-installer/config-admin.sub"

usage() {
	echo "${PERSONNALITY} [-zbD] [-d disk ] [ -s screen ] [ -u URL ]
			[-H type] [-c path] clip1|clip2"
	echo "options: "
	echo "   -z : do not configure"
	echo "   -d <disk> : use <disk> as root disk (default: /dev/sda)"
	echo "   -s <scr> : use <scr> as screen resolution (default: 1024x768:32)"
	echo "   -u <URL> : use <URL> as mirror"
	echo "           (default http://mirror.clip/debian)"
	echo "   -V : be more verbose"
	echo "   -c <path> : use <path> as root dir for configuration files"
	echo "           (default: $BIN_PATH)"
	echo "   -C <type> : full-disk encryption with <type> (crypt0|crypt1|crypt2) scheme"
	echo "   -b : do not bind / to /clipX/boot, but use directly /dev/XX1"
	echo "           (needed when installing from a live cd)"
	echo "	 -H <type> : install for <type> hardware type"
	echo "Supported hardware types:"
	for f in $(ls -1 "${BIN_PATH}/hw_conf"); do
		printf "\t%s\n" "$(basename "${f}")"
	done
}

set_screen_geom() {
	local geom="$(grep -oEe '[0-9]+x[0-9]+-[0-9]+' ${HW_CONF}/bootargs)"
	if [[ -z "${geom}" ]]; then
		echo " * Could not determine SCREEN_GEOM, defaulting to 1024x768:32"
		CLIP_SCREEN_GEOM="1024x768:32"
		return
	fi

	CLIP_SCREEN_GEOM="${geom/-/:}"
	echo " * SCREEN_GEOM: ${CLIP_SCREEN_GEOM} (from bootargs parameter)"
}

preconf() {
	local ret=0
	local confpath="${CONF_PATH}"

	ebegin "Creating etc directories"
	mkdir -p "${ROOT}/mounts/admin_priv/etc.admin/clip_install"
	for jail in ${CLIP_JAILS}; do
		mkdir -p "${ROOT}/vservers/${jail}/admin_priv/etc.admin/clip_install"
	done
	eend $?

	if [[ -n "${NOCONF}" ]]; then
		confpath="/tmp/.conf"
	else
		ebegin "Cleaning up home"
		eindent
		# ugly...
		if [[ -e "${ROOT}/home/etc.users/core/screen.geom" ]]; then
			chattr -i "${ROOT}/home/etc.users/core/screen.geom"
		fi
		for dir in etc.users/tcb etc.users/core parts \
				keys rm_h rm_b adminclip/.ssh auditclip/.ssh \
				adminrmh/.ssh adminrmb/.ssh ; do
			if [[ -d "${ROOT}/home/${dir}" ]]; then
				einfo "/home/${dir}"
				rm -fr "${ROOT}/home/${dir}"/* || ret=1
			fi
		done
		eoutdent
		eend $ret
	fi

	ret=0

	einfo "Setting up ${HW_TYPE} hardware configuration"
	mkdir -p "${ROOT}/home/etc.users/core"
	mkdir -p "${ROOT}/etc/conf.d"
	mkdir -p "${ROOT}/etc/shared"
	install -D -o 0 -g 0 -m 600 "${HW_CONF}/modules" "${ROOT}/etc/modules" || ret=1
	install -D -o 0 -g 0 -m 600 "${HW_CONF}/bootargs" "${ROOT}/etc/bootargs" || ret=1
	if [[ -n "${CRYPT}" ]]; then
		if [[ "$(wc -l "${ROOT}/etc/bootargs" | cut -d ' ' -f 1)" == "0" ]]; then
			echo "${CRYPT}" > "${ROOT}/etc/bootargs" || ret=1
		else
			sed -i -e "s/$/ ${CRYPT}/" "${ROOT}/etc/bootargs" || ret=1
		fi
	fi
	if [[ -e "${HW_CONF}/firmwares" ]]; then
		install -D -o 0 -g 0 -m 600 "${HW_CONF}/firmwares" "${ROOT}/etc/firmwares" || ret=1
	fi
	if [[ -e "${HW_CONF}/power" ]]; then
		install -D -o 0 -g 0 -m 600 "${HW_CONF}/power" "${ROOT}/etc/conf.d/power" || ret=1
	fi
	if [[ -e "${HW_CONF}/video" ]]; then
		install -D -o 0 -g 0 -m 600 "${HW_CONF}/video" "${ROOT}/etc/shared/video" || ret=1
	fi
	if [[ -e "${HW_CONF}/leds" ]]; then
		install -D -o 0 -g 0 -m 600 "${HW_CONF}/leds" "${ROOT}/etc/conf.d/leds" || ret=1
	fi
	if [[ -e "${HW_CONF}/leds.map" ]]; then
		install -D -o 0 -g 0 -m 600 "${HW_CONF}/leds.map" "${ROOT}/etc/conf.d/leds.map" || ret=1
	fi
	if [[ -e "${HW_CONF}/uboot.prepare" ]]; then
		install -D -o 0 -g 0 -m 600 "${HW_CONF}/uboot.prepare" "${ROOT}/etc/conf.d/uboot.prepare" || ret=1
	fi
	if [[ -e "${HW_CONF}/uboot.console" ]]; then
		install -D -o 0 -g 0 -m 600 "${HW_CONF}/uboot.console" "${ROOT}/etc/conf.d/uboot.console" || ret=1
	fi
	if [[ -e "${HW_CONF}/uboot.loadaddr_vmlinuz" ]]; then
		install -D -o 0 -g 0 -m 600 "${HW_CONF}/uboot.loadaddr_vmlinuz" "${ROOT}/etc/conf.d/uboot.loadaddr_vmlinuz" || ret=1
	fi
	if [[ -e "${HW_CONF}/uboot.loadaddr_initrd" ]]; then
		install -D -o 0 -g 0 -m 600 "${HW_CONF}/uboot.loadaddr_initrd" "${ROOT}/etc/conf.d/uboot.loadaddr_initrd" || ret=1
	fi
	if [[ -e "${HW_CONF}/uboot.ext2load_device" ]]; then
		install -D -o 0 -g 0 -m 600 "${HW_CONF}/uboot.ext2load_device" "${ROOT}/etc/conf.d/uboot.ext2load_device" || ret=1
	fi
	if [[ -e "${HW_CONF}/uboot.rootdev" ]]; then
		install -D -o 0 -g 0 -m 600 "${HW_CONF}/uboot.rootdev" "${ROOT}/etc/conf.d/uboot.rootdev" || ret=1
	fi
	echo "${HW_TYPE}" > "${ROOT}/home/etc.users/core/machine"

	# Include extra and blacklisted modules and firmwares from conf profile
	for b in modules firmwares; do
		for ext in extra blacklist; do
			if [[ -e "${CONF_PATH}/params/hw/${b}.${ext}" ]]; then
				install -D -o 0 -g 0 -m 600 "${CONF_PATH}/params/hw/${b}.${ext}" \
					"${ROOT}/etc/${b}.${ext}" || ret=1
			fi
		done
	done

	eend $ret

	if [[ ( "${SPECIES}" == "gtw" || "${SPECIES}" == "bare" ) && -f "${CONF_PATH}/params/conf.d/net" ]]; then
		ebegin "Installing gateway net parameters"
		install -D -o 0 -g 0 -m 0644 "${CONF_PATH}/params/conf.d/net" \
			"${ROOT}/etc/conf.d/net"
		eend $?
	fi
	ret=0
	mkdir -p "${ROOT}/mounts/admin_priv/etc.admin/conf.d" || ret=1
	chown 4000:4000 "${ROOT}/mounts/admin_priv/etc.admin/conf.d" || ret=1
	if [[ -e "${confpath}/conf/net" ]]; then
		einfo "Installing internal net configuration"
		CONF_BASE="${confpath}" _install_admin "conf.d" "net" || ret=1
		eend ${ret}
	else
		if [[ -d "${confpath}/conf/netconf.d/default" ]]; then
			einfo "Installing net profiles"
			CONF_BASE="${confpath}" _install_netconf || ret=1
			eend ${ret}
		else
			ewarn "No default net configuration, this will not work"
			return 1
		fi
	fi

	if [[ -f "${CONF_PATH}/params/conf.d/clip" ]]; then
		einfo "Setting up /etc/conf.d/clip"
		install -D -o 0 -g 0 -m 0644 \
			"${CONF_PATH}/params/conf.d/clip" \
			"${ROOT}/etc/conf.d/clip"
		eend $?
	fi

	if [[ -f "${CONF_PATH}/params/conf.d/jail-net" ]]; then
		einfo "Setting up /etc/conf.d/jail-net from profile"
		install -D -o 0 -g 0 -m 0644 \
			"${CONF_PATH}/params/conf.d/jail-net" \
			"${ROOT}/etc/conf.d/jail-net" 
		eend $?
	else
		einfo "Setting up default /etc/conf.d/jail-net"
		local tmpfile="$(mktemp /tmp/jail-net.XXXXXX)"
		cat > "${tmpfile}" <<EOF
UPDATE_LOCAL_ADDR="127.51.0.1"
USER_LOCAL_ADDR="127.52.0.1"
AUDIT_LOCAL_ADDR="127.53.0.1"
ADMIN_LOCAL_ADDR="127.54.0.1"
RMH_LOCAL_ADDR="127.101.0.1"
RMB_LOCAL_ADDR="127.102.0.1"
EOF
		install -D -o 0 -g 0 -m 0644 "${tmpfile}" \
			"${ROOT}/etc/conf.d/jail-net"
		eend $?
		rm -f "${tmpfile}"
	fi
}

create_pkg_links() {
	local base="${1}"
	local dist="${2}"
	local mirror="${base}/mirrors/${dist}"
	local core_cache="${base}/cache/apt/clip_install/${dist}/core/archives"
	local apps_cache="${base}/cache/apt/clip_install/${dist}/apps/archives"
	local dl_cache="${base}/cache/apt/clip_download/${dist}/archives"
	pushd ${mirror} 1>/dev/null || error "Failed to enter ${mirror}"
	for pkg in *.deb; do
		local prio="$(dpkg -f "${pkg}" Priority)"
		local target=""
		case "${prio}" in
			"Required")
				target="${core_cache}/${pkg}"
				;;
			"Important")
				target="${apps_cache}/${pkg}"
				;;
			*)
				error "Unsupported priority ${prio} on package ${pkg}"
				;;
		esac
		ln "${pkg}" "${target}" || error "Failed to link ${pkg} to ${target}"
		ln "${pkg}" "${dl_cache}/${pkg}" \
			|| error "Failed to link ${pkg} to ${dl_cache}/${pkg}"
	done
	popd 1>/dev/null
}

init_mirror() {
	local dist="${1}"
	local src="${2}"
	local base="${3}"

	local some_deb=$(find "${src}" -name '*.deb' | head -n 1)
	local arch="${some_deb/#*_/}"
	arch="${arch/%.deb}"

	ebegin "Creating debian mirror for architecture ${arch} at ${base}"
	mkdir -p "${base}/mirrors/dists/main/${dist}/binary-${arch}"
	mkdir -p "${base}/mirrors/${dist}"

	mv "${src}"/*.deb "${base}/mirrors/${dist}"

	"${BIN_PATH}/gen_packages_gz" "${base}/mirrors/" "${dist}" \
		"${base}/mirrors/dists/main/${dist}/binary-${arch}/Packages.gz" \
		|| error "gen_packages_gz failed for ${base}/${dist}"

	mkdir "${base}/mirrors/flags" # download flags directory

	create_pkg_links "${base}" "${dist}"
	eend 0 # Only reached on success
}

init_optional_list() {
	local jail="${1}"
	local jailtype="${2}"
	local outpath="${3}"
	local mirpath1="${4}"
	local mirpath2="${5}"
	local optpath="${6}"
	local ret=0

	if [[ ! -d "/usr/share/clip-config" ]]; then
		ewarn "clip-config is missing, optional packages list will not be initialized for ${jail}"
		return 0
	fi

	ebegin "Generating optional packages list in ${outpath}"
	cat > "/tmp/sources.list"<<EOF
deb ${CLIP_MIRROR}/${mirpath1} ${jailtype} main
deb ${CLIP_MIRROR}/${mirpath2} ${jailtype} main
EOF
	local suf="${ROOT#/}"
	local outlist="${outpath}/optional.list"
	local outcache="${outpath}/optional.cache"
	local APT_CONFIG="/usr/share/clip-config/apt.conf.${jail}.${suf}"
	export APT_CONFIG
	apt-get update 1>/dev/null || ret=1
	list_optional.pl -jail "${jail}" \
		-optional "${optpath}" \
		-mirror "${CLIP_MIRROR}" \
		-cache "${outcache}" \
		-force \
		-conf "${APT_CONFIG}" > "${outlist}" || ret=1

	eend $ret
}

set_extra_pkg() {
	CLIP_EXTRA_PKG=""
	for src in $*; do 
		if [[ -e "${src}" ]]; then
			CLIP_EXTRA_PKG="${CLIP_EXTRA_PKG} $(cat "${src}")"
		fi
	done
	export CLIP_EXTRA_PKG
}

install_clip() {
	ebegin "Installing CLIP core packages"
	export CLIP_CONFIGURATION="${CONFIG_CLIP_CORE}"
	set_extra_pkg "${CONF_PATH}/params/extra.clip.core"
	if [[ -n "${VERBOSE}" ]]; then
		debootstrap --verbose clip "${ROOT}" "${CLIP_MIRROR}/${CLIP_CORE_MIRROR_DIR}" \
			"${DEBOOTSTRAP_BASE}/scripts/clip_core" \
			|| error "Debootstrap failed for clip_core"
	else
		debootstrap clip "${ROOT}" "${CLIP_MIRROR}/${CLIP_CORE_MIRROR_DIR}" \
			"${DEBOOTSTRAP_BASE}/scripts/clip_core" 1>/dev/null \
			|| error "Debootstrap failed for clip_core"
	fi
	unset CLIP_CONFIGURATION
	eend 0 # only reached on success

	ebegin "Installing CLIP secondary packages"
	export CLIP_CONFIGURATION="${CONFIG_CLIP_APPS}"
	set_extra_pkg "${CONF_PATH}/params/extra.clip.apps ${CONF_PATH}/conf/optional.clip"
	if [[ -n "${VERBOSE}" ]]; then
		debootstrap --verbose clip "${ROOT}" "${CLIP_MIRROR}/${CLIP_APPS_MIRROR_DIR}" \
			"${DEBOOTSTRAP_BASE}/scripts/clip_apps" \
			|| error "Debootstrap failed for clip_apps"
	else
		debootstrap clip "${ROOT}" "${CLIP_MIRROR}/${CLIP_APPS_MIRROR_DIR}" \
			"${DEBOOTSTRAP_BASE}/scripts/clip_apps" 1>/dev/null \
			|| error "Debootstrap failed for clip_apps"
	fi
	unset CLIP_CONFIGURATION
	eend 0 # only reached on success

	if [[ -e "${CONF_PATH}/conf/optional.clip" ]]; then
		ebegin "Installing optional.conf.clip"
		local ret=0
		install -D -o 4000 -g 4000 "${CONF_PATH}/conf/optional.clip" \
			"${ROOT}/etc/admin/clip_install/optional.conf.clip" || ret=1
		install -D -o 4000 -g 4000 "${CONF_PATH}/conf/optional.clip" \
			"${ROOT}/var/pkg/cache/apt/clip_install/clip/apps/optional.conf.clip" || ret=1
		eend $ret
	fi

	init_mirror clip "${ROOT}/var/cache/apt/archives" \
			"${ROOT}/var/pkg"

	init_optional_list "clip" "clip" \
		"${ROOT}/var/pkg/cache/apt/clip_download/clip" \
			"${CLIP_CORE_MIRROR_DIR}" "${CLIP_APPS_MIRROR_DIR}" \
			"${ROOT}/etc/admin/clip_install/optional.conf.clip"

	# Cleanup files created by debootstrap
	rm -fr "${ROOT}/var/"{lib/apt,lib/dpkg,cache/apt}
}

install_rm() {
	local jail="${1}"
	local ret=0

	ebegin "Installing ${jail} core packages"
	export CLIP_CONFIGURATION="${CONFIG_RM_CORE}"
	set_extra_pkg "${CONF_PATH}/params/extra.${jail}.core"
	if [[ -n "${VERBOSE}" ]]; then
		debootstrap rm "${ROOT}/vservers/${jail}" \
			"${CLIP_MIRROR}/${RM_CORE_MIRROR_DIR}" \
			"${DEBOOTSTRAP_BASE}/scripts/rm_core" \
			|| error "Debootstrap failed for rm_core"
	else 
		debootstrap rm "${ROOT}/vservers/${jail}" \
			"${CLIP_MIRROR}/${RM_CORE_MIRROR_DIR}" \
			"${DEBOOTSTRAP_BASE}/scripts/rm_core" 1>/dev/null \
			|| error "Debootstrap failed for rm_core"
	fi
	unset CLIP_CONFIGURATION
	eend 0 # only reached on success

	local msg_install="Installing ${jail} secondary packages"
	if [ "${CONFIG_RM_APPS_SPECIFIC_JAIL}" == "yes" ]; then
		case "${jail}" in
			rm_h)
				CLIP_CONFIGURATION="${CONFIG_RM_APPS}-h"
				msg_install="${msg_install} (specific)"
				;;
			rm_b)
				CLIP_CONFIGURATION="${CONFIG_RM_APPS}-b"
				msg_install="${msg_install} (specific)"
				;;
			*)
				error "Unknown jail: ${jail}"
				;;
		esac
	else
		CLIP_CONFIGURATION="${CONFIG_RM_APPS}"
	fi
	export CLIP_CONFIGURATION
	ebegin "${msg_install}"
	set_extra_pkg "${CONF_PATH}/conf/optional.${jail}"
	if [[ -n "${VERBOSE}" ]]; then
		debootstrap rm "${ROOT}/vservers/${jail}" \
			"${CLIP_MIRROR}/${RM_APPS_MIRROR_DIR}" \
			"${DEBOOTSTRAP_BASE}/scripts/rm_apps" \
			|| error "Debootstrap failed for rm_apps"
	else
		debootstrap rm "${ROOT}/vservers/${jail}" \
			"${CLIP_MIRROR}/${RM_APPS_MIRROR_DIR}" \
			"${DEBOOTSTRAP_BASE}/scripts/rm_apps" 1>/dev/null \
			|| error "Debootstrap failed for rm_apps"
	fi
	unset CLIP_CONFIGURATION
	eend 0 # only reached on success
	if [[ -e "${CONF_PATH}/conf/optional.${jail}" ]]; then
		ebegin "Installing optional.conf.rm in ${jail}"
		local ret=0
		install -D -o 4000 -g 4000 "${CONF_PATH}/conf/optional.${jail}" \
			"${ROOT}/vservers/${jail}/admin_priv/etc.admin/clip_install/optional.conf.rm" || ret=1
		install -D -o 4000 -g 4000 "${CONF_PATH}/conf/optional.${jail}" \
			"${ROOT}/vservers/${jail}/update_priv/var/pkg/cache/apt/clip_install/rm/apps/optional.conf.rm" || ret=1
		eend $ret
	fi

	init_mirror rm "${ROOT}/vservers/${jail}/update_priv/var/cache/apt/archives" \
				"${ROOT}/vservers/${jail}/update_priv/var/pkg" 


	init_optional_list "${jail}" "rm" \
		"${ROOT}/vservers/${jail}/update_priv/var/pkg/cache/apt/clip_download/rm" \
		"${RM_CORE_MIRROR_DIR}" "${RM_APPS_MIRROR_DIR}" \
		"${ROOT}/vservers/${jail}/admin_priv/etc.admin/clip_install/optional.conf.rm"
	
	# Cleanup files created by debootstrap
	rm -fr "${ROOT}/vservers/${jail}/update_priv/var/"{lib/apt,lib/dpkg,cache/apt}
}

################## MAIN ####################

source /opt/clip-installer/clip-disk-common
DO_MOUNT_CLEANUP="YES"
trap cleanup EXIT INT 

while getopts zbVd:hH:s:u:c:C:e: arg ; do
	case $arg in
		z) 
			NOCONF="yes"
			if [[ ! -d "/tmp/.conf" ]]; then
				echo "/tmp/.conf does not exist, -z install will fail" >&2
				exit 1
			fi
			export NOCONF
			;;
	        b)
			BIND_MOUNT_BOOT="no"
			;;
		d)
			ROOT_DISK="${OPTARG}"
			;;
		s)
			CLIP_SCREEN_GEOM="${OPTARG}"
			;;
		u)
			CLIP_MIRROR="${OPTARG}"
			;;
		c)
			CONF_PATH="${OPTARG}"
			;;
		C)
			CRYPT="${OPTARG}"
			;;
		V)
			VERBOSE="yes"
			;;
		h)	usage
			exit 0
			;;
		H)
			HW_TYPE="${OPTARG}"
			if [[ ! -e "${BIN_PATH}/hw_conf/${HW_TYPE}" ]]; then
				echo "Unsupported hardware type: ${HW_TYPE}" >&2
				usage
				exit 1
			fi
			HW_CONF="${BIN_PATH}/hw_conf/${HW_TYPE}"
			;;
		*)
			echo "Unsupported option: ${arg}" >&2
			usage
			exit 1
			;;
	esac
done
shift `expr $OPTIND - 1`

case "${CRYPT}" in
	crypt0|crypt1|crypt2)
		;;
	"")
		;;
	*)
		echo "Unsupported encryption scheme : ${CRYPT}" >&2
		exit 1
		;;
esac

if [[ -z "${CLIP_SCREEN_GEOM}" ]]; then
	set_screen_geom
fi

export CLIP_KERNEL="clip-kernel-modular"
export CLIP_SCREEN_GEOM
export HW_TYPE
export HW_CONF
export CLIP_KEY_PATH
export CLIP_MIRROR

case "$1" in
	clip1)
		DEV_LIST="5 6"
		if [[ -n "${WITH_RM}" ]]; then
			DEV_LIST="${DEV_LIST} 7 8"
		fi
		;;
	clip2)
		DEV_LIST="10 11"
		;;
	*)
		echo "Not a valid clip root : $1" >&2
		usage
		exit 1;
		;;
esac

ROOT="/${1}"

source "${BIN_PATH}/common.sh" || exit 1

init_fs || error "Failed to init filesystems"

mount_fs || error "Failed to mount filesystems"

preconf || error "Failed preconfiguration"

install_clip

if [[ "${1}" == "clip1" ]]; then
	for jail in ${CLIP_JAILS}; do
		install_rm ${jail}
	done
fi

einfo "Configuring"
export WITH_RM
export CLIP_JAILS
export CONF_PATH
export NOCONF
"$BIN_PATH/configure.sh" "${ROOT}" "${SPECIES}"
trap - EXIT
exit $?
