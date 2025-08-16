#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    #Clone only if the repository does not exist.
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    # TODO: Add your kernel build steps here
    #Cleans the config files
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- mrproper
    #Configures default config for virt dev board
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- defconfig
    #Makes the kernel image
    make -j4 ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- 
    #makes all the modules
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- modules
    #Makes the device tree
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- dtbs
fi

echo "Adding the Image in outdir"
cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ${OUTDIR}/
echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

# TODO: Create necessary base directories
mkdir ${OUTDIR}/rootfs
cd ${OUTDIR}/rootfs
mkdir -p bin dev etc home lib lib64 proc sbin sys tmp usr var conf
mkdir -p usr/bin usr/lib usr/sbin
mkdir -p var/log
mkdir -p home/conf

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    # TODO:  Configure busyboxs
    make defconfig
else
    cd busybox
fi

# TODO: Make and install busybox
make distclean
make defconfig
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
make CONFIG_PREFIX=${OUTDIR}/rootfs ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} install

echo "Library dependencies"
cd ${OUTDIR}/rootfs
${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library"
cd ${OUTDIR}

# TODO: Add library dependencies to rootfs
if [ -d "${FINDER_APP_DIR}/conf" ]; then
    cp -r ${FINDER_APP_DIR}/conf/* ${OUTDIR}/rootfs/conf/ 2>/dev/null || true
    cp -r ${FINDER_APP_DIR}/conf/* ${OUTDIR}/rootfs/home/conf/ 2>/dev/null || true
fi
SYSROOT=$(${CROSS_COMPILE}gcc --print-sysroot)
find ${SYSROOT} -name "ld-linux-aarch64.so.1" -exec cp -a {} ${OUTDIR}/rootfs/lib/ \;
find ${SYSROOT} -name "libm.so.6" -exec cp -a {} ${OUTDIR}/rootfs/lib64/ \;
find ${SYSROOT} -name "libresolv.so.2" -exec cp -a {} ${OUTDIR}/rootfs/lib64/ \;
find ${SYSROOT} -name "libc.so.6" -exec cp -a {} ${OUTDIR}/rootfs/lib64/ \;

# TODO: Make device nodes
cd ${OUTDIR}/rootfs
if [ ! -c dev/null ]; then
	sudo mknod -m 666 dev/null c 1 3
fi
if [ ! -c dev/console ]; then
	sudo mknod -m 666 dev/console c 5 1 
fi
# TODO: Clean and build the writer utility
cd ${FINDER_APP_DIR}
make clean
make CROSS_COMPILE=${CROSS_COMPILE}

# TODO: Copy the finder related scripts and executables to the /home directory
# on the target rootfs

cp ${FINDER_APP_DIR}/finder-test.sh ${OUTDIR}/rootfs/home
cp ${FINDER_APP_DIR}/writer ${OUTDIR}/rootfs/home
cp ${FINDER_APP_DIR}/finder.sh ${OUTDIR}/rootfs/home
cp ${FINDER_APP_DIR}/autorun-qemu.sh ${OUTDIR}/rootfs/home
chmod +x ${OUTDIR}/rootfs/home/finder-test.sh
chmod +x ${OUTDIR}/rootfs/home/finder.sh
chmod +x ${OUTDIR}/rootfs/home/autorun-qemu.sh
chmod +x ${OUTDIR}/rootfs/home/writer

# TODO: Chown the root directory

sudo chown -R root:root ${OUTDIR}/rootfs

# TODO: Create initramfs.cpio.gz
cd "$OUTDIR/rootfs"
find . | cpio -H newc -ov --owner root:root | gzip > "${OUTDIR}/initramfs.cpio.gz"
