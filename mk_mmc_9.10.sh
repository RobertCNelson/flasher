#!/bin/bash -e

#Notes: need to check for: parted, fdisk, wget, mkfs.*, mkimage, md5sum

MIRROR="http://rcn-ee.homeip.net:81/dl/omap/uboot/old/"
MLO="MLO-beagleboard-1.42+r7+gitr73eb0caf065b3b3f407d8af5c4836624e5cc7b69-r7"
XLOAD="x-load-beagleboard-1.42+r7+gitr73eb0caf065b3b3f407d8af5c4836624e5cc7b69-r7.bin.ift"
UBOOT="u-boot-beagleboard-2009.11-rc1+r43+gitra5cf522a91ba479d459f8221135bdb3e9ae97479-r43.bin"

unset MMC

BOOT_LABEL=boot

DIR=$PWD

function dl_xload_uboot {
 mkdir -p ${DIR}/dl/

 echo ""
 echo "Downloading X-loader and Uboot"
 echo ""

 wget -c --no-verbose --directory-prefix=${DIR}/dl/ ${MIRROR}${MLO}
 wget -c --no-verbose --directory-prefix=${DIR}/dl/ ${MIRROR}${XLOAD}
 wget -c --no-verbose --directory-prefix=${DIR}/dl/ ${MIRROR}${UBOOT}
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
 FDISK=$(sudo fdisk -l | grep "Disk ${MMC}" | awk '{print $2}')

 if test "-$FDISK-" = "-$MMC:-"
 then
  echo ""
  echo "I see..."
  echo "sudo fdisk -l:"
  sudo fdisk -l | grep "Disk /dev/" --color=never
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
  sudo fdisk -l | grep "Disk /dev/" --color=never
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



