#!/bin/bash -e

#Notes: need to check for: parted, fdisk, wget, mkfs.*, mkimage, md5sum

MIRROR="http://rcn-ee.net/deb/"

unset MMC

BOOT_LABEL=boot

DIR=$PWD

function dl_xload_uboot {
 mkdir -p ${DIR}/dl/

 echo ""
 echo "Downloading X-loader and Uboot"
 echo ""

 wget -c --no-verbose --directory-prefix=${DIR}/dl/ ${MIRROR}tools/latest/bootloader

 MLO=$(cat ${DIR}/dl/bootloader | grep "ABI:1 MLO" | awk '{print $3}')
 XLOAD=$(cat ${DIR}/dl/bootloader | grep "ABI:1 XLOAD" | awk '{print $3}')
 UBOOT=$(cat ${DIR}/dl/bootloader | grep "ABI:1 UBOOT" | awk '{print $3}')

 wget -c --no-verbose --directory-prefix=${DIR}/dl/ ${MLO}
 wget -c --no-verbose --directory-prefix=${DIR}/dl/ ${XLOAD}
 wget -c --no-verbose --directory-prefix=${DIR}/dl/ ${UBOOT}

 MLO=${MLO##*/}
 XLOAD=${XLOAD##*/}
 UBOOT=${UBOOT##*/}
}

function cleanup_sd {

 echo ""
 echo "Umounting Partitions"
 echo ""

 sudo umount ${MMC}1 &> /dev/null || true
 sudo umount ${MMC}2 &> /dev/null || true

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

sudo mkfs.vfat -F 16 ${MMC}1 -n ${BOOT_LABEL}

sudo rm -rfd ./disk || true

mkdir ./disk
sudo mount ${MMC}1 ./disk

sudo cp -v ${DIR}/dl/${MLO} ./disk/MLO
sudo cp -v ${DIR}/dl/${XLOAD} ./disk/x-load.bin.ift
sudo cp -v ${DIR}/dl/${UBOOT} ./disk/u-boot.bin
sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Reset NAND" -d ./reset.cmd ./disk/boot.scr

cd ./disk
sync
cd ..
sudo umount ./disk || true
echo "done"

}

function check_mmc {
 DISK_NAME="Disk|Platte"
 FDISK=$(sudo fdisk -l | grep "[${DISK_NAME}] ${MMC}" | awk '{print $2}')

 if test "-$FDISK-" = "-$MMC:-"
 then
  echo ""
  echo "I see..."
  echo "sudo fdisk -l:"
  sudo fdisk -l | grep "[${DISK_NAME}] /dev/" --color=never
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
  sudo fdisk -l | grep "[${DISK_NAME}] /dev/" --color=never
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
            check_mmc 
            ;;
    esac
    shift
done

if [ ! "${MMC}" ];then
    usage
fi

 dl_xload_uboot
 cleanup_sd
 create_partitions



