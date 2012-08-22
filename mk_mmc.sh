#!/bin/bash
#
# Copyright (c) 2009-2012 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Latest can be found at:
# http://github.com/RobertCNelson/flasher/blob/master/mk_mmc.sh

MIRROR="http://rcn-ee.net/deb"
BACKUP_MIRROR="http://rcn-ee.homeip.net:81/dl/mirrors/deb"

BOOT_LABEL="boot"
PARTITION_PREFIX=""

unset MMC
unset USE_BETA_BOOTLOADER

GIT_VERSION=$(git rev-parse --short HEAD)
IN_VALID_UBOOT=1

DIR="$PWD"
TEMPDIR=$(mktemp -d)

function check_root {
	if [[ $UID -ne 0 ]]; then
		echo "$0 must be run as sudo user or root"
		exit
	fi
}

function check_for_command {
	if ! which "$1" > /dev/null ; then
		echo -n "You're missing command $1"
		NEEDS_COMMAND=1
		if [ -n "$2" ] ; then
			echo -n " (consider installing package $2)"
		fi
		echo
	fi
}

function detect_software {
	unset NEEDS_COMMAND

	check_for_command mkimage uboot-mkimage
	check_for_command mkfs.vfat dosfstools
	check_for_command wget wget
	check_for_command parted parted

	if [ "${NEEDS_COMMAND}" ] ; then
		echo ""
		echo "Your system is missing some dependencies"
		echo "Ubuntu/Debian: sudo apt-get install uboot-mkimage wget dosfstools parted"
		echo "Fedora: as root: yum install uboot-tools wget dosfstools parted dpkg patch"
		echo "Gentoo: emerge u-boot-tools wget dosfstools parted dpkg"
		echo ""
		exit
	fi

	#Check for gnu-fdisk
	#FIXME: GNU Fdisk seems to halt at "Using /dev/xx" when trying to script it..
	if fdisk -v | grep "GNU Fdisk" >/dev/null ; then
		echo "Sorry, this script currently doesn't work with GNU Fdisk."
		echo "Install the version of fdisk from your distribution's util-linux package."
		exit
	fi

	unset PARTED_ALIGN
	if parted -v | grep parted | grep 2.[1-3] >/dev/null ; then
		PARTED_ALIGN="--align cylinder"
	fi
}

function rcn-ee_down_use_mirror {
	echo "rcn-ee.net down, switching to slower backup mirror"
	echo "-----------------------------"
	MIRROR=${BACKUP_MIRROR}
	RCNEEDOWN=1
}

function dl_bootloader {
	echo ""
	echo "Downloading Device's Bootloader"
	echo "-----------------------------"

	mkdir -p ${TEMPDIR}/dl

	unset RCNEEDOWN
	echo "attempting to use rcn-ee.net for dl files [10 second time out]..."
	wget -T 10 -t 1 --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}/tools/latest/bootloader

	if [ ! -f ${TEMPDIR}/dl/bootloader ] ; then
		rcn-ee_down_use_mirror
		wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}/tools/latest/bootloader
	fi

	if [ "${RCNEEDOWN}" ] ; then
		sed -i -e "s/rcn-ee.net/rcn-ee.homeip.net:81/g" ${TEMPDIR}/dl/bootloader
		sed -i -e 's:81/deb/:81/dl/mirrors/deb/:g' ${TEMPDIR}/dl/bootloader
	fi

	if [ "${USE_BETA_BOOTLOADER}" ] ; then
		ABI="ABX2"
	else
		ABI="ABI2"
	fi

	if [ "${spl_name}" ] ; then
		MLO=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:${BOOTLOADER}:SPL" | awk '{print $2}')
		wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MLO}
		MLO=${MLO##*/}
		echo "SPL Bootloader: ${MLO}"
	else
		unset MLO
	fi

	if [ "${boot_name}" ] ; then
		UBOOT=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:${BOOTLOADER}:BOOT" | awk '{print $2}')
		wget --directory-prefix=${TEMPDIR}/dl/ ${UBOOT}
		UBOOT=${UBOOT##*/}
		echo "UBOOT Bootloader: ${UBOOT}"
	else
		unset UBOOT
	fi
}

function drive_error_ro {
	echo "-----------------------------"
	echo "Error: for some reason your SD card is not writable..."
	echo "Check: is the write protect lever set the locked position?"
	echo "Check: do you have another SD card reader?"
	echo "-----------------------------"
	echo "Script gave up..."

	exit
}

function unmount_all_drive_partitions {
	echo ""
	echo "Unmounting Partitions"
	echo "-----------------------------"

	NUM_MOUNTS=$(mount | grep -v none | grep "$MMC" | wc -l)

	for (( c=1; c<=$NUM_MOUNTS; c++ ))
	do
		DRIVE=$(mount | grep -v none | grep "$MMC" | tail -1 | awk '{print $1}')
		umount ${DRIVE} &> /dev/null || true
	done

	LC_ALL=C parted --script ${MMC} mklabel msdos | grep "Error:" && drive_error_ro
}

function omap_fatfs_boot_part {
	echo ""
	echo "Using fdisk to create an omap compatible fatfs BOOT partition"
	echo "-----------------------------"

	fdisk ${MMC} <<-__EOF__
		n
		p
		1

		+64M
		t
		e
		p
		w
	__EOF__

	sync

	echo "Setting Boot Partition's Boot Flag"
	echo "-----------------------------"
	parted --script ${MMC} set 1 boot on
}

function dd_to_drive {
	echo ""
	echo "Using dd to place bootloader on drive"
	echo "-----------------------------"
	dd if=${TEMPDIR}/dl/${UBOOT} of=${MMC} seek=1 bs=1024
	bootloader_installed=1

	echo "Using parted to create BOOT Partition"
	echo "-----------------------------"
	if [ "x${boot_fstype}" == "xfat" ] ; then
		parted --script ${PARTED_ALIGN} ${MMC} mkpart primary fat16 10 100
	else
		parted --script ${PARTED_ALIGN} ${MMC} mkpart primary ext2 10 100
	fi
}

function no_boot_on_drive {
	echo "Using parted to create BOOT Partition"
	echo "-----------------------------"
	if [ "x${boot_fstype}" == "xfat" ] ; then
		parted --script ${PARTED_ALIGN} ${MMC} mkpart primary fat16 1 100
	else
		parted --script ${PARTED_ALIGN} ${MMC} mkpart primary ext2 1 100
	fi
}

function format_boot_partition {
	echo "Formating Boot Partition"
	echo "-----------------------------"
	if [ "x${boot_fstype}" == "xfat" ] ; then
		boot_part_format="vfat"
		mkfs.vfat -F 16 ${MMC}${PARTITION_PREFIX}1 -n ${BOOT_LABEL}
	else
		boot_part_format="ext2"
		mkfs.ext2 ${MMC}${PARTITION_PREFIX}1 -L ${BOOT_LABEL}
	fi
}

function create_partitions {
	unset bootloader_installed
	case "${bootloader_location}" in
	omap_fatfs_boot_part)
		omap_fatfs_boot_part
		;;
	dd_to_drive)
		dd_to_drive
		;;
	*)
		no_boot_on_drive
		;;
	esac
	format_boot_partition
}

function populate_boot {
	echo "Populating Boot Partition"
	echo "-----------------------------"

	if [ ! -d ${TEMPDIR}/disk ] ; then
		mkdir -p ${TEMPDIR}/disk
	fi

	if mount -t ${boot_part_format} ${MMC}${PARTITION_PREFIX}1 ${TEMPDIR}/disk; then

		if [ "${spl_name}" ] ; then
			if [ -f ${TEMPDIR}/dl/${MLO} ]; then
				cp -v ${TEMPDIR}/dl/${MLO} ${TEMPDIR}/disk/${spl_name}
				echo "-----------------------------"
			fi
		fi

		if [ "${boot_name}" ] ; then
			if [ -f ${TEMPDIR}/dl/${UBOOT} ]; then
				cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/${boot_name}
			fi
		fi

		case "${SYSTEM}" in
		beagle_bx|beagle_cx)
			cat > ${TEMPDIR}/disk/reset.cmd <<-__EOF__
				echo "Starting NAND UPGRADE, do not REMOVE SD CARD or POWER till Complete"
				fatload mmc 0:1 0x80200000 ${spl_name}
				nandecc hw
				nand erase 0 80000
				nand write 0x80200000 0 20000
				nand write 0x80200000 20000 20000
				nand write 0x80200000 40000 20000
				nand write 0x80200000 60000 20000

				fatload mmc 0:1 0x80200000 ${boot_name}
				nandecc hw
				nand erase 80000 160000
				nand write 0x80200000 80000 170000
				nand erase 260000 20000
				echo "FLASH UPGRADE Complete"
				exit

			__EOF__

			mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Reset NAND" -d ${TEMPDIR}/disk/reset.cmd ${TEMPDIR}/disk/user.scr
			cat ${TEMPDIR}/disk/reset.cmd

			cat > ${TEMPDIR}/disk/uEnv.txt <<-__EOF__
				bootenv=user.scr
				loaduimage=fatload mmc \${mmcdev} \${loadaddr} \${bootenv}
				mmcboot=echo Running user.scr script from mmc ...; source \${loadaddr}

			__EOF__

			cp -v ${TEMPDIR}/disk/uEnv.txt ${TEMPDIR}/disk/user.txt
			;;
		mx6qsabrelite)
			cat > ${TEMPDIR}/disk/reset.cmd <<-__EOF__
				echo "check U-Boot" ;
				if ext2load mmc \${disk}:1 12000000 ${boot_name} ; then
					echo "read \${filesize} bytes from SD card" ;
					if sf probe 1 27000000 ; then
						echo "probed SPI ROM" ;
						if sf read 0x12400000 0 \${filesize} ; then
							if cmp.b 0x12000000 0x12400000 \${filesize} ; then
								echo "------- U-Boot versions match" ;
							else
								echo "erasing" ;
								sf erase 0 0x40000 ;
								echo "programming" ;
								sf write 0x12000000 ${offset} \${filesize} ;
							fi
						else
							echo "Error reading boot loader from EEPROM" ;
						fi
					else
						echo "Error initializing EEPROM" ;
					fi ;
				else
					echo "No U-Boot image found on SD card" ;
				fi

			__EOF__

			mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Reset NAND" -d ${TEMPDIR}/disk/reset.cmd ${TEMPDIR}/disk/boot.scr
			sudo cp -v ${TEMPDIR}/disk/boot.scr ${TEMPDIR}/disk/6q_bootscript
			;;
		mx6qsabrelite_sd)
			cat > ${TEMPDIR}/disk/reset.cmd <<-__EOF__
				echo "check U-Boot" ;
				if ext2load mmc \${disk}:1 12000000 ${boot_name} ; then
					echo "read \${filesize} bytes from SD card" ;
					if sf probe 1 27000000 ; then
						echo "probed SPI ROM" ;
						if sf read 0x12400000 0 \${filesize} ; then
							if cmp.b 0x12000000 0x12400000 \${filesize} ; then
								echo "------- U-Boot versions match" ;
							else
								echo "erasing" ;
								sf erase 0 0x40000 ;
								echo "programming" ;
								sf write 0x12000000 ${offset} \${filesize} ;
							fi
						else
							echo "Error reading boot loader from EEPROM" ;
						fi
					else
						echo "Error initializing EEPROM" ;
					fi ;
				else
					echo "No U-Boot image found on SD card" ;
				fi

			__EOF__

			mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Reset NAND" -d ${TEMPDIR}/disk/reset.cmd ${TEMPDIR}/disk/boot.scr
			sudo cp -v ${TEMPDIR}/disk/boot.scr ${TEMPDIR}/disk/6q_bootscript
			;;
		esac

		cd ${TEMPDIR}/disk
		sync
		cd "${DIR}/"

		echo "Debug: Contents of Boot Partition"
		echo "-----------------------------"
		ls -lh ${TEMPDIR}/disk/
		echo "-----------------------------"

		umount ${TEMPDIR}/disk || true

		echo "Finished populating Boot Partition"
		echo "-----------------------------"
	else
		echo "-----------------------------"
		echo "Unable to mount ${MMC}${PARTITION_PREFIX}1 at ${TEMPDIR}/disk to complete populating Boot Partition"
		echo "Please retry running the script, sometimes rebooting your system helps."
		echo "-----------------------------"
		exit
fi
	echo "mk_mmc.sh script complete"
}

function check_mmc {
	FDISK=$(LC_ALL=C fdisk -l 2>/dev/null | grep "Disk ${MMC}" | awk '{print $2}')

	if [ "x${FDISK}" = "x${MMC}:" ] ; then
		echo ""
		echo "I see..."
		echo "fdisk -l:"
		LC_ALL=C fdisk -l 2>/dev/null | grep "Disk /dev/" --color=never
		echo ""
		echo "mount:"
		mount | grep -v none | grep "/dev/" --color=never
		echo ""
		read -p "Are you 100% sure, on selecting [${MMC}] (y/n)? "
		[ "${REPLY}" == "y" ] || exit
		echo ""
	else
		echo ""
		echo "Are you sure? I Don't see [${MMC}], here is what I do see..."
		echo ""
		echo "fdisk -l:"
		LC_ALL=C fdisk -l 2>/dev/null | grep "Disk /dev/" --color=never
		echo ""
		echo "mount:"
		mount | grep -v none | grep "/dev/" --color=never
		echo ""
		exit
	fi
}

function is_omap {
	IS_OMAP=1

	bootloader_location="omap_fatfs_boot_part"
	spl_name="MLO"
	boot_name="u-boot.img"

	boot_fstype="fat"
}

function is_imx {
	IS_IMX=1

	bootloader_location="dd_to_drive"
	unset spl_name
	boot_name="u-boot.imx"
	offset="0x400"

	boot_fstype="fat"
}

function check_uboot_type {
	unset DO_UBOOT
	unset IN_VALID_UBOOT

	case "${UBOOT_TYPE}" in
	beagle_bx)
		SYSTEM="beagle_bx"
		DO_UBOOT=1
		BOOTLOADER="BEAGLEBOARD_BX"
		is_omap
		;;
	beagle_cx)
		SYSTEM="beagle_cx"
		DO_UBOOT=1
		BOOTLOADER="BEAGLEBOARD_CX"
		is_omap
		;;
	mx6qsabrelite)
		SYSTEM="mx6qsabrelite"
		BOOTLOADER="MX6QSABRELITE_D"
		is_imx
		unset bootloader_location
		boot_fstype="ext2"
		;;
	mx6qsabrelite_sd)
		SYSTEM="mx6qsabrelite_sd"
		BOOTLOADER="MX6QSABRELITE_D_SPI_TO_SD"
		is_imx
		boot_name="iMX6DQ_SPI_to_uSDHC3.bin"
		offset="0x00"
		unset bootloader_location
		boot_fstype="ext2"
		;;
	*)
		IN_VALID_UBOOT=1
		cat <<-__EOF__
			-----------------------------
			ERROR: This script does not currently recognize the selected: [--uboot ${UBOOT_TYPE}] option..
			Please rerun $(basename $0) with a valid [--uboot <device>] option from the list below:
			-----------------------------
			        TI:
			                beagle_bx - <BeagleBoard Ax/Bx>
			                beagle_cx - <BeagleBoard Cx>
			        Freescale:
			                mx6qsabrelite - (boot off SPI)
			                mx6qsabrelite_sd - (boot off SD)
			-----------------------------
		__EOF__
		exit
		;;
	esac
}

function usage {
	echo "usage: sudo $(basename $0) --mmc /dev/sdX --uboot <dev board>"
	#tabed to match 
		cat <<-__EOF__
			Script Version git: ${GIT_VERSION}
			-----------------------------
			Bugs email: "bugs at rcn-ee.com"

			Required Options:
			--mmc </dev/sdX>

			--uboot <dev board>
			        TI:
			                beagle_bx - <BeagleBoard Ax/Bx>
			                beagle_cx - <BeagleBoard Cx>
			        Freescale:
			                mx6qsabrelite - (boot off SPI)
			                mx6qsabrelite_sd - (boot off SD)

			Additional Options:
			        -h --help

			--probe-mmc
			        <list all partitions: sudo ./mk_mmc.sh --probe-mmc>

		__EOF__
	exit
}

function checkparm {
	if [ "$(echo $1|grep ^'\-')" ] ; then
		echo "E: Need an argument"
		usage
	fi
}

IN_VALID_UBOOT=1

# parse commandline options
while [ ! -z "$1" ]; do
	case $1 in
	-h|--help)
		usage
		MMC=1
		;;
	--probe-mmc)
		MMC="/dev/idontknow"
		check_root
		check_mmc
	;;
	--mmc)
		checkparm $2
		MMC="$2"
		if [[ "${MMC}" =~ "mmcblk" ]] ; then
			PARTITION_PREFIX="p"
		fi
		check_root
		check_mmc
		;;
	--uboot)
		checkparm $2
		UBOOT_TYPE="$2"
		check_uboot_type
		;;
	--use-beta-bootloader)
		USE_BETA_BOOTLOADER=1
		;;
	esac
	shift
done

if [ ! "${MMC}" ] ; then
	echo "ERROR: --mmc undefined"
	usage
fi

if [ "${IN_VALID_UBOOT}" ] ; then
	echo "ERROR: --uboot undefined"
	usage
fi

echo ""
echo "Script Version git: ${GIT_VERSION}"
echo "-----------------------------"

check_root
detect_software

if [ "${spl_name}" ] || [ "${boot_name}" ] ; then
	dl_bootloader
fi

unmount_all_drive_partitions
create_partitions
populate_boot

