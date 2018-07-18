#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2008-2018 ANSSI. All Rights Reserved.

# remember the clip-installer path
BIN_PATH=${0%/*}

# config for CLIP_RM
CLIP_MIRROR="http://mirror.clip/debian"
CLIP_CORE_MIRROR_DIR="clip4-rm-dpkg/clip/clip-core-conf"
CLIP_APPS_MIRROR_DIR="clip4-rm-dpkg/clip/clip-apps-conf"
RM_CORE_MIRROR_DIR="clip4-rm-dpkg/rm/rm-core-conf"
RM_APPS_MIRROR_DIR="clip4-rm-dpkg/rm/rm-apps-conf"
CLIP_KEY_PATH="clip4-rm-dpkg/keys"

CONFIG_CLIP_CORE="clip-core-conf"

CONFIG_CLIP_APPS="clip-apps-conf"

CONFIG_RM_CORE="rm-core-conf"

CONFIG_RM_APPS="rm-apps-conf"

WITH_RM=yes
SPECIES=rm

. "/etc/clip-installer.conf"

. "$BIN_PATH/install.sh"
