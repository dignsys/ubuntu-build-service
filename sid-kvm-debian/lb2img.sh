#!/bin/sh

# (C) 2013 Fathi Boudra <fathi.boudra@linaro.org>

# Convert live-build tarball to KVM image

PROGNAME=`basename $0`
DEVICE=
TARGZFILE=
IMGFILE=

usage() {
        echo "usage: ${PROGNAME} <device> <targzfile> <imgfile>"
        echo "e.g. ${PROGNAME} ${DEVICE} ${TARGZFILE} ${IMGFILE}"
        exit 1
}

DEVICE=$1
TARGZFILE=$2
IMGFILE=$3

# we must provide device name
[ -n "${DEVICE}" ] || usage
[ -n "${TARGZFILE}" ] || usage
[ -n "${IMGFILE}" ] || usage

# we must be root
[ `whoami` = "root" ] || { echo "E: You must be root" && exit 1; }

# we must have few tools
MKFS=`which mkfs.ext4` || { echo "E: You must have mkfs.ext3" && exit 1; }
TUNE2FS=`which tune2fs` || { echo "E: You must have tune2fs" && exit 1; }
QEMUIMG=`which qemu-img` || { echo "E: You must have qemu-img" && exit 1; }
GRUBMKIMAGE=`which grub-mkimage` || { echo "E: You must have grub-mkimage" && exit 1; }
GRUBSETUP=`which grub-setup` || { echo "E: You must have grub-setup" && exit 1; }

${QEMUIMG} create -f raw ${IMGFILE} 1G
losetup ${DEVICE} ${IMGFILE}

echo "I: Create filesystem"
${MKFS} -O ^has_journal ${DEVICE}

echo "I: Tune filesystem"
${TUNE2FS} -c 0 -i 0 ${DEVICE}

echo "I: Mount device on local filesystem"
MOUNTDIR=$(mktemp -d /tmp/${PROGNAME}.XXXXXX)
mount ${DEVICE} ${MOUNTDIR}

tar -zxf ${TARGZFILE} -C ${MOUNTDIR} --strip-components=1

echo "I: Install grub bootloader"
echo "(hd0) ${DEVICE}" > device.map
echo "set prefix=(hd0)/boot/grub" > mycfg.cfg
cp -a /usr/lib/grub/i386-pc/boot.img ${MOUNTDIR}/boot/grub/
cp -a /usr/lib/grub/i386-pc ${MOUNTDIR}/boot/grub/

${GRUBMKIMAGE} \
  --config=mycfg.cfg \
  --directory=/usr/lib/grub/i386-pc \
  --output=${MOUNTDIR}/boot/grub/core.img \
  --format=i386-pc \
  --prefix=/boot \
  biosdisk part_msdos ext2

${GRUBSETUP} \
  --directory=${MOUNTDIR}/boot/grub \
  --force \
  --device-map=device.map \
  ${DEVICE}

echo "I: Create grub configuration file"
VMLINUZ=`find ${MOUNTDIR}/boot -type f -name 'vmlinuz-*' |xargs basename`
INITRD=`find ${MOUNTDIR}/boot -type f -name 'initrd.img-*' |xargs basename`
UUID=`blkid ${DEVICE} |cut -d' ' -f2 |cut -d'"' -f2`
cat > ${MOUNTDIR}/boot/grub/grub.cfg << EOF
set default=0
set timeout=2

insmod part_msdos
insmod ext2
set root=(hd0)

menuentry 'linux' {
  linux /boot/${VMLINUZ} root=UUID=${UUID} console=ttyS0,115200 ro quiet
  initrd /boot/${INITRD}
}
EOF

umount ${MOUNTDIR}
rm -rf ${MOUNTDIR} device.map mycfg.cfg
losetup -d ${DEVICE}

echo "I: Done"
