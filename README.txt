Simple local installer for CLIP
===============================

This is a minimal clip installer, which works for all species of clip. It is
meant to be run locally (from e.g. a local developper partition), on a system
that is already partitionned (although it could quite easily be turned into a
full blown installer).

Used by clip-dev/clip-installer from CLIP OS.

USAGE:
------

Run as ./install_clip_<species>.sh clip1|clip2 on a system that is already
partitionned (but where the clip partitions are not mounted). The scripts 
assume the following partitionning:

/dev/XX1	boot
/dev/XX2	home
/dev/XX3	logs
/dev/XX5	clip1 root
/dev/XX6	clip1 mounts
/dev/XX7	clip1 rm_h
/dev/XX8	clip1 rm_b
/dev/XX9	swap
/dev/XX10	clip2 root
/dev/XX11	clip2 mounts
/dev/XX12	clip2 rm_h
/dev/XX13	clip2 rm_b
/dev/XX14	system backup
/dev/XX15	data backup

where XX stands for sda, hda, md, or whatever the root device happens to be.
Note that the scripts, at this stage, assume a CLIP-RM inspired partitionning, 
no matter what the actual species being installed is. It is the user's
responsibility to create these partitions and make there is sufficient space 
in each of them. The mandatory argument, 'clip1' or 'clip2', selects which 
set of clip partitions the new system will be installed to.

Furthermore the installation program assume the common partitions
(boot, home, logs, backups) to be already formatted, and that a
correct master boot is already in place.

The script will:
 - create filesystems on the partitions
 - mount them 
 - run several debootstrap calls to install a set of configurations from one 
   or several mirrors 
 - create the local package mirrors
 - run an initial configuration script to set up the network, create users 
   and install crypto keys
 - install bootloader configuration files to boot the new system (the
   bootloader is assumed to be already installed on the first partition.

OPTIONS:
--------

Every install script supports the following options :

 -z		Do not configure the system, keep the common configuration
   		files saved by a previous clip install, or configuration
		backup operation.
 -m		Modular kernel and configurations (configured through 
 		conf/modules and conf/bootargs) 
 -d <disk>	Set the root disk to <disk> (default /dev/sda)
 -s <geom>	Set the screen geom to <geom> (default 1024x768)
 -u <URL>	Use <URL> as the base mirror to get packages from (default
 		http://mirror.clip/debian)
 -t <type>	Hardware type (same keywords as the suffixes for clip-kernel-* 
 		packages) (default d520).
 -c <path>	Indicates the root path where the configuration (conf
    		subdirectory), the keys (keys subdir.) and the ike2 material
		(admin_ike2_cert and ike2_cert subdirs) should be read.
 -b		Do not bind "/" to "/clipX/boot", but rather mount it from
 		/dev/XX1 (which is the correct way of mounting boot partition
		when installing from a live CD)
 -D		Install packages marked as 'devel' in deboostrap lists.
 -V		Verbose debootstrap


RESTORING A PREVIOUS CONFIGURATION
----------------------------------

The configuration files (including keys, etc.) from a previous install may be
backed-up, by running the save.sh script. More precisely, the script should
be run as :
	./save.sh [-d <disk>] clip1|clip2 <species>
where clip1|clip2 designates the first or second clip install on disk, and
<species> is either 'rm', 'gtw' or 'single'. The configuration files are then
copied into a configuration tree in /tmp/.conf. This can then be re-used by
running the installer with the -z option, to reinstall CLIP with the old
configuration files, instead of those provided by the <conf_path>
configuration tree. Note however that, at the moment, the following
configuration files are still systematically copied from the <conf_path> 
configuration tree, and not from the backup :
 - usbkeys.conf
 - keys/*
 - cert/*
 - clip_download/*
These are typically updated by the new CLIP install, and therefore not kept
through a reinstall.

