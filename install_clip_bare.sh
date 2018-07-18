#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2008-2018 ANSSI. All Rights Reserved.

# remember the clip-installer path
BIN_PATH=${0%/*}

# config for CLIP_BARE
CLIP_MIRROR="http://mirror.clip/debian"
CLIP_CORE_MIRROR_DIR="clip4-bare-dpkg/clip/clip-core-conf"
CLIP_APPS_MIRROR_DIR="clip4-bare-dpkg/clip/clip-apps-conf"
CLIP_KEY_PATH="clip4-bare-dpkg/keys"

CONFIG_CLIP_CORE="clip-core-conf"

CONFIG_CLIP_APPS="clip-apps-conf"

WITH_RM=
SPECIES=bare

. "/etc/clip-installer.conf"

source "$BIN_PATH/install.sh"
