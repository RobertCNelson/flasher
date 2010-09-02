#!/bin/bash -e
#
# Copyright (c) 2009-2010 Robert Nelson <robertcnelson@gmail.com>
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

BOOT_LABEL=boot
PARTITION_PREFIX=""

DIR=$PWD

function detect_software {

#Currently only Ubuntu and Debian..
#Working on Fedora...
unset PACKAGE
unset APT

if [ ! $(which mkimage) ];then
 echo "Missing uboot-mkimage"
 PACKAGE="uboot-mkimage "
 APT=1
fi

if [ ! $(which wget) ];then
 echo "Missing wget"
 PACKAGE="wget "
 APT=1
fi

if [ "${APT}" ];then
 echo "Installing Dependicies"
 sudo aptitude install $PACKAGE
fi
}

function dl_xload_uboot {

 mkdir -p ${DIR}/dl/

 echo ""
 echo "Downloading X-loader and Uboot"
 echo ""

 rm -f ${DIR}/dl/bootloader || true
 wget -c --no-verbose --directory-prefix=${DIR}/dl/ ${MIRROR}tools/latest/bootloader

 MLO=$(cat ${DIR}/dl/bootloader | grep "ABI:1 MLO" | awk '{print $3}')
 UBOOT=$(cat ${DIR}/dl/bootloader | grep "ABI:1 UBOOT" | awk '{print $3}')

 wget -c --no-verbose --directory-prefix=${DIR}/dl/ ${MLO}
 wget -c --no-verbose --directory-prefix=${DIR}/dl/ ${UBOOT}

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

 sudo parted -s ${MMC} mklabel msdos
}

function create_partitions {

sudo fdisk -H 255 -S 63 ${MMC} << END
n
p
1
1
+64M
a
1
t
e
p
w
END

echo ""
echo "Formating Boot Partition"
echo ""

sudo mkfs.vfat -F 16 ${MMC}${PARTITION_PREFIX}1 -n ${BOOT_LABEL}

sudo rm -rfd ${DIR}/disk || true

mkdir ${DIR}/disk
sudo mount ${MMC}${PARTITION_PREFIX}1 ${DIR}/disk

sudo cp -v ${DIR}/dl/${MLO} ${DIR}/disk/MLO
sudo cp -v ${DIR}/dl/${UBOOT} ${DIR}/disk/u-boot.bin
sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Reset NAND" -d ${DIR}/reset.cmd ${DIR}/disk/user.scr

cd ${DIR}/disk
sync
cd ${DIR}/
sudo umount ${DIR}/disk || true
echo "done"

}

function check_mmc {
 FDISK=$(sudo LC_ALL=C sfdisk -l 2>/dev/null | grep "[Disk] ${MMC}" | awk '{print $2}')

 if test "-$FDISK-" = "-$MMC:-"
 then
  echo ""
  echo "I see..."
  echo "sudo sfdisk -l:"
  sudo LC_ALL=C sfdisk -l 2>/dev/null | grep "[Disk] /dev/" --color=never
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
  echo "sudo sfdisk -l:"
  sudo LC_ALL=C sfdisk -l 2>/dev/null | grep "[Disk] /dev/" --color=never
  echo ""
  echo "mount:"
  mount | grep -v none | grep "/dev/" --color=never
  echo ""
  exit
 fi
}

function usage {
    echo "usage: $(basename $0) --mmc /dev/sdd"
cat <<EOF

required options:
--mmc </dev/sdX>
    Unformated MMC Card

Additional/Optional options:
-h --help
    this help
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
        --mmc)
            checkparm $2
            MMC="$2"
	    if [[ "${MMC}" =~ "mmcblk" ]]
            then
	        PARTITION_PREFIX="p"
            fi
            check_mmc 
            ;;
    esac
    shift
done

if [ ! "${MMC}" ];then
    usage
fi

 detect_software
 dl_xload_uboot
 cleanup_sd
 create_partitions

