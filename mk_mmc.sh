#!/bin/bash -e
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

#Notes: need to check for: parted, fdisk, wget, mkfs.*, mkimage, md5sum

MIRROR="http://rcn-ee.net/deb/"

unset MMC
unset BETA
unset BOOTLOADER
IN_VALID_UBOOT=1

BOOT_LABEL=boot
PARTITION_PREFIX=""

DIR=$PWD
TEMPDIR=$(mktemp -d)

#Software Qwerks
#fdisk 2.18.x/2.19.x, dos no longer default
unset FDISK_DOS

if test $(sudo fdisk -v | grep -o -E '2\.[0-9]+' | cut -d'.' -f2) -ge 18 ; then
 FDISK_DOS="-c=dos -u=cylinders"
fi

#Check for gnu-fdisk
#FIXME: GNU Fdisk seems to halt at "Using /dev/xx" when trying to script it..
if fdisk -v | grep "GNU Fdisk" >/dev/null ; then
 echo "Sorry, this script currently doesn't work with GNU Fdisk"
 exit
fi

function detect_software {

#Currently only Ubuntu and Debian..
#Working on Fedora...
unset DEB_PACKAGE
unset RPM_PACKAGE
unset NEEDS_PACKAGE

if [ ! $(which mkimage) ];then
 echo "Missing uboot-mkimage"
 DEB_PACKAGE="uboot-mkimage "
 RPM_PACKAGE="uboot-tools "
 NEEDS_PACKAGE=1
fi

if [ ! $(which wget) ];then
 echo "Missing wget"
 DEB_PACKAGE+="wget "
 RPM_PACKAGE+="wget "
 NEEDS_PACKAGE=1
fi

if [ ! $(which mkfs.vfat) ];then
 echo "Missing mkfs.vfat"
 DEB_PACKAGE+="dosfstools "
 RPM_PACKAGE+="dosfstools "
 NEEDS_PACKAGE=1
fi

if [ ! $(which parted) ];then
 echo "Missing parted"
 DEB_PACKAGE+="parted "
 RPM_PACKAGE+="parted "
 NEEDS_PACKAGE=1
fi

if [ "${NEEDS_PACKAGE}" ];then
 echo ""
 echo "Please Install Missing Dependencies"
 echo "Ubuntu/Debian: sudo apt-get install $DEB_PACKAGE"
 echo "Fedora: as root: yum install $RPM_PACKAGE"
 echo ""
 exit
fi

}

function dl_xload_uboot {

 echo ""
 echo "Downloading X-loader and Uboot"
 echo ""

 mkdir ${TEMPDIR}/dl

 wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}tools/latest/bootloader

 if [ "$BETA" ];then
  ABI="ABX2"
 else
  ABI="ABI2"
 fi

case "$SYSTEM" in
    beagle_bx)

 MLO=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:${BOOTLOADER}:SPL" | awk '{print $2}')
 UBOOT=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:${BOOTLOADER}:BOOT" | awk '{print $2}')

        ;;
    beagle_cx)

 MLO=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:${BOOTLOADER}:SPL" | awk '{print $2}')
 UBOOT=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:${BOOTLOADER}:BOOT" | awk '{print $2}')

        ;;
esac

 wget -c --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MLO}
 wget -c --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${UBOOT}

 MLO=${MLO##*/}
 UBOOT=${UBOOT##*/}
}

function cleanup_sd {

 echo ""
 echo "Umounting Partitions"
 echo ""

NUM_MOUNTS=$(mount | grep -v none | grep "$MMC" | wc -l)

 for (( c=1; c<=$NUM_MOUNTS; c++ ))
 do
  DRIVE=$(mount | grep -v none | grep "$MMC" | tail -1 | awk '{print $1}')
  sudo umount ${DRIVE} &> /dev/null || true
 done

 sudo parted --script ${MMC} mklabel msdos
}

function create_partitions {

sudo fdisk ${FDISK_DOS} ${MMC} << END
n
p
1
1
+64M
t
e
p
w
END

sync

sudo parted --script ${MMC} set 1 boot on

echo ""
echo "Formating Boot Partition"
echo ""

sudo mkfs.vfat -F 16 ${MMC}${PARTITION_PREFIX}1 -n ${BOOT_LABEL}

mkdir ${TEMPDIR}/disk
sudo mount ${MMC}${PARTITION_PREFIX}1 ${TEMPDIR}/disk

sudo cp -v ${TEMPDIR}/dl/${MLO} ${TEMPDIR}/disk/MLO
sudo cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/u-boot.img
sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Reset NAND" -d ${DIR}/reset.cmd ${TEMPDIR}/disk/user.scr
cat ${DIR}/reset.cmd
sudo cp -v ${DIR}/uEnv.txt ${TEMPDIR}/disk/user.txt

cd ${TEMPDIR}/disk
sync
cd ${TEMPDIR}/
sudo umount ${TEMPDIR}/disk || true
echo "done"

}

function check_mmc {
 FDISK=$(sudo LC_ALL=C fdisk -l 2>/dev/null | grep "[Disk] ${MMC}" | awk '{print $2}')

 if test "-$FDISK-" = "-$MMC:-"
 then
  echo ""
  echo "I see..."
  echo "sudo fdisk -l:"
  sudo LC_ALL=C fdisk -l 2>/dev/null | grep "[Disk] /dev/" --color=never
  echo ""
  echo "mount:"
  mount | grep -v none | grep "/dev/" --color=never
  echo ""
  read -p "Are you 100% sure, on selecting [${MMC}] (y/n)? "
  [ "$REPLY" == "y" ] || exit
  echo ""
 else
  echo ""
  echo "Are you sure? I Don't see [${MMC}], here is what I do see..."
  echo ""
  echo "sudo fdisk -l:"
  sudo LC_ALL=C fdisk -l 2>/dev/null | grep "[Disk] /dev/" --color=never
  echo ""
  echo "mount:"
  mount | grep -v none | grep "/dev/" --color=never
  echo ""
  exit
 fi
}

function check_uboot_type {
 unset DO_UBOOT

case "$UBOOT_TYPE" in
    beagle_bx)

 SYSTEM=beagle_bx
 BOOTLOADER="BEAGLEBOARD_BX"
 unset IN_VALID_UBOOT
 DO_UBOOT=1

        ;;
    beagle_cx)

 SYSTEM=beagle_cx
 BOOTLOADER="BEAGLEBOARD_CX"
 unset IN_VALID_UBOOT
 DO_UBOOT=1

        ;;
esac

 if [ "$IN_VALID_UBOOT" ] ; then
   usage
 fi
}

function usage {
    echo "usage: $(basename $0) --mmc /dev/sdX --uboot <dev board>"
cat <<EOF

Script Version $SCRIPT_VERSION
Bugs email: "bugs at rcn-ee.com"

Required Options:
--mmc </dev/sdX>
    Unformated MMC Card

Additional/Optional options:
-h --help
    this help

--probe-mmc
    List all partitions

--uboot <dev board>
    beagle_bx - <Ax/Bx Models>
    beagle_cx - <Cx Models>

EOF
exit
}

function checkparm {
    if [ "$(echo $1|grep ^'\-')" ];then
        echo "E: Need an argument"
        usage
    fi
}

# parse commandline options
while [ ! -z "$1" ]; do
    case $1 in
        -h|--help)
            usage
            MMC=1
            ;;
        --probe-mmc)
            MMC="/dev/idontknow"
            check_mmc
            ;;
        --mmc)
            checkparm $2
            MMC="$2"
	    if [[ "${MMC}" =~ "mmcblk" ]]
            then
	        PARTITION_PREFIX="p"
            fi
            check_mmc
            ;;
        --uboot)
            checkparm $2
            UBOOT_TYPE="$2"
            check_uboot_type
            ;;
        --beta)
            BETA=1
            ;;
    esac
    shift
done

if [ ! "${MMC}" ];then
    echo "ERROR: --mmc undefined"
    usage
fi

if [ "$IN_VALID_UBOOT" ] ; then
    echo "ERROR: --uboot undefined"
    usage
fi

 detect_software
 dl_xload_uboot
 cleanup_sd
 create_partitions

