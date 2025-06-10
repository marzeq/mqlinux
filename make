#!/bin/bash
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
cd "$SCRIPT_DIR"
set -e

LINUX_VERSION="6.15.2"
LINUX_URL="https://cdn.kernel.org/pub/linux/kernel/v$(echo "$LINUX_VERSION" | cut -d. -f1).x/linux-$LINUX_VERSION.tar.xz"

BUSYBOX_VERSION="1.36.1"
BUSYBOX_URL="https://github.com/mirror/busybox/archive/refs/tags/$(echo "$BUSYBOX_VERSION" | sed 's/\./_/g').tar.gz"

OPENRC_VERSION="0.62.2"
OPENRC_URL="https://github.com/OpenRC/openrc/archive/refs/tags/$OPENRC_VERSION.tar.gz"

KBD_VERSION="2.8.0"
KBD_URL="https://www.kernel.org/pub/linux/utils/kbd/kbd-$KBD_VERSION.tar.xz"

PROCPS_VERSION="4.0.5"
PROCPS_URL="https://gitlab.com/procps-ng/procps/-/archive/v$PROCPS_VERSION/procps-v$PROCPS_VERSION.tar.gz"

GLIBC_VERSION="2.41"
GNU_LIBC_URL="https://ftpmirror.gnu.org/glibc/glibc-$GLIBC_VERSION.tar.xz"

LIBCAP_VERSION="2.76"
LIBCAP_URL="https://git.kernel.org/pub/scm/libs/libcap/libcap.git/snapshot/libcap-$LIBCAP_VERSION.tar.gz"

UTIL_LINUX_VERSION="2.41"
UTIL_LINUX_URL="https://github.com/util-linux/util-linux/archive/refs/tags/v$UTIL_LINUX_VERSION.tar.gz"

JOBS=$(nproc)

prepareRootfs() {
  mkdir rootfs
  mkdir rootfs/{dev,etc,proc,sys,tmp,usr,run,var}
  mkdir -p rootfs/{root,home,mnt,lib/modules}
  mkdir -p rootfs/usr/{bin,lib,share,include}
  chmod 1777 rootfs/tmp rootfs/run
  ln -s lib rootfs/usr/lib64
  ln -s usr/bin rootfs/bin
  ln -s usr/bin rootfs/sbin
  ln -s usr/lib rootfs/lib
  ln -s usr/lib64 rootfs/lib64

  sudo mknod -m 666 rootfs/dev/null c 1 3
  sudo mknod -m 666 rootfs/dev/zero c 1 5
  sudo mknod -m 666 rootfs/dev/full c 1 7
  sudo mknod -m 666 rootfs/dev/random c 1 8
  sudo mknod -m 666 rootfs/dev/urandom c 1 9
  sudo mknod -m 600 rootfs/dev/console c 5 1
  sudo mknod -m 666 rootfs/dev/ptmx c 5 2
  sudo mkdir -m 755 rootfs/dev/pts
  sudo mkdir -m 1777 rootfs/dev/shm

  sudo mknod -m 666 rootfs/dev/tty c 5 0
  sudo mknod -m 666 rootfs/dev/ttyAMA0 c 204 64
  for x in {0..6}; do
    sudo mknod -m 620 rootfs/dev/tty$x c 4 $x
  done
}

buildKernel() {
  mkdir -p linux
  cd linux
  if [ ! -f "linux.tar.xz" ]; then
    wget "$LINUX_URL" -O linux.tar.xz
    tar -xf linux.tar.xz
    mv linux-* linux-src
  fi
  cd linux-src
  make defconfig
  scripts/config --enable CONFIG_64BIT
  make -j"$JOBS"
  cp arch/x86/boot/bzImage ../..
  cd $SCRIPT_DIR
}

installHeaders() {
  mkdir -p linux
  cd linux
  if [ ! -f "linux.tar.xz" ]; then
    wget "$LINUX_URL" -O linux.tar.xz
    tar -xf linux.tar.xz
    mv linux-* linux-src
  fi
  cd linux-src
  mkdir -p ../headers
  make headers_install INSTALL_HDR_PATH=../../rootfs/usr
  cd $SCRIPT_DIR
}

buildBusybox() {
  mkdir -p busybox
  cd busybox
  if [ ! -f "busybox.tar.gz" ]; then
    wget "$BUSYBOX_URL" -O busybox.tar.gz
    tar -xf busybox.tar.gz
    mv busybox-* busybox-src
  fi
  cd busybox-src
  make defconfig
  sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
  sed -i 's/CONFIG_TC=y/CONFIG_TC=n/' .config
  sed -i 's/# CONFIG_BASH_IS_ASH is not set/CONFIG_BASH_IS_ASH=y/' .config
  sed -i 's/CONFIG_BASH_IS_NONE=y/CONFIG_BASH_IS_NONE=n/' .config

  make -j"$JOBS"
  make CONFIG_PREFIX="$SCRIPT_DIR/rootfs" install
  cd $SCRIPT_DIR/rootfs
  rm linuxrc
  cd $SCRIPT_DIR
}

buildKbd() {
  mkdir -p kbd
  cd kbd
  if [ ! -f "kbd.tar.xz" ]; then
    wget "$KBD_URL" -O kbd.tar.xz
    tar -xf kbd.tar.xz
    mv kbd-* kbd-src
  fi
  cd kbd-src
  ./configure --prefix=/usr
  make -j"$JOBS"
  make install DESTDIR="$SCRIPT_DIR/rootfs"
  cd $SCRIPT_DIR
}

buildProcps() {
  mkdir -p procps
  cd procps
  if [ ! -f "procps.tar.gz" ]; then
    wget "$PROCPS_URL" -O procps.tar.gz
    tar -xf procps.tar.gz
    mv procps-* procps-src
  fi
  cd procps-src
  ./autogen.sh
  ./configure --prefix=/usr --sysconfdir=/etc
  make -j"$JOBS"

  # unlink busybox symlinks for process management, as procps provides these
  unlink $SCRIPT_DIR/rootfs/usr/bin/hugetop || true
  unlink $SCRIPT_DIR/rootfs/usr/bin/kill || true
  unlink $SCRIPT_DIR/rootfs/usr/bin/pgrep || true
  unlink $SCRIPT_DIR/rootfs/usr/bin/pkill || true
  unlink $SCRIPT_DIR/rootfs/usr/bin/pmap || true
  unlink $SCRIPT_DIR/rootfs/usr/bin/ps || true
  unlink $SCRIPT_DIR/rootfs/usr/bin/pwdx || true
  unlink $SCRIPT_DIR/rootfs/usr/bin/skill || true
  unlink $SCRIPT_DIR/rootfs/usr/bin/slabtop || true
  unlink $SCRIPT_DIR/rootfs/usr/bin/snice || true
  unlink $SCRIPT_DIR/rootfs/usr/bin/sysctl || true
  unlink $SCRIPT_DIR/rootfs/usr/bin/tload || true
  unlink $SCRIPT_DIR/rootfs/usr/bin/top || true
  unlink $SCRIPT_DIR/rootfs/usr/bin/uptime || true
  unlink $SCRIPT_DIR/rootfs/usr/bin/vmstat || true
  unlink $SCRIPT_DIR/rootfs/usr/bin/w || true
  unlink $SCRIPT_DIR/rootfs/usr/bin/watch || true

  make install DESTDIR="$SCRIPT_DIR/rootfs"
  cd $SCRIPT_DIR
}

buildLibcap() {
  mkdir -p libcap
  cd libcap
  if [ ! -f "libcap.tar.gz" ]; then
    wget "$LIBCAP_URL" -O libcap.tar.gz
    tar -xf libcap.tar.gz
    mv libcap-* libcap-src
  fi
  cd libcap-src
  make -j"$JOBS"
  make install DESTDIR="$SCRIPT_DIR/rootfs"
  cd $SCRIPT_DIR
}

buildUtilLinux() {
  mkdir -p util-linux
  cd util-linux
  if [ ! -f "util-linux.tar.gz" ]; then
    wget "$UTIL_LINUX_URL" -O util-linux.tar.gz
    tar -xf util-linux.tar.gz
    mv util-linux-* util-linux-src
  fi
  cd util-linux-src
  ./autogen.sh
  ./configure --prefix=/usr \
    --sysconfdir=/etc \
    --libdir=/usr/lib \
    --disable-nls
  make -j"$JOBS"
  sudo make install-strip DESTDIR="$SCRIPT_DIR/rootfs"
  cd $SCRIPT_DIR
}

buildOpenRC() {
  mkdir -p openrc
  cd openrc
  if [ ! -f "openrc.tar.gz" ]; then
    wget "$OPENRC_URL" -O openrc.tar.gz
    tar -xf openrc.tar.gz
    mv openrc-* openrc-src
  fi
  cd openrc-src
  meson setup build \
    --prefix=/usr \
    --sysconfdir=/etc \
    --localstatedir=/var \
    -Dpam=false
  meson compile -C build -j"$JOBS"
  meson install -C build --destdir $SCRIPT_DIR/rootfs
  cd $SCRIPT_DIR/rootfs

  mkdir -p etc/init.d
  touch etc/fstab etc/inittab
  unlink sbin/init || true
  ln -s ./openrc-init sbin/init

  cat > etc/init.d/rcS <<EOF
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t tmpfs -o nosuid,nodev tmpfs /run
mkdir -p /run/lock /run/openrc

exec /usr/bin/rc default
EOF
  chmod +x etc/init.d/rcS

  # we handle mounting of proc, sys, and tmpfs etc in rcS
  echo "" > etc/fstab

  echo "root:x:0:0:root:/root:/bin/sh" > etc/passwd
  echo "root:x:0:" > etc/group
  echo "uucp:x:10:" >> etc/group

  mkdir -p var/cache/rc

  mkdir -p $SCRIPT_DIR/rootfs/etc/runlevels/default
  for n in $(seq 1 6); do
    ln -s /etc/init.d/agetty $SCRIPT_DIR/rootfs/etc/init.d/agetty.tty$n
    ln -s /etc/init.d/agetty.tty$n $SCRIPT_DIR/rootfs/etc/runlevels/default/
  done

  cd $SCRIPT_DIR

  buildKbd
  # needed because busybox provides an outdated version of sysctl
  buildProcps
  buildLibcap
  buildUtilLinux
}

buildGlibc() {
  mkdir -p glibc
  cd glibc
  if [ ! -f "glibc.tar.xz" ]; then
    wget "$GNU_LIBC_URL" -O glibc.tar.xz
    tar -xf glibc.tar.xz
    mv glibc-* glibc-src
  fi
  cd glibc-src
  mkdir -p build
  cd build

  ../configure --prefix="/usr" \
    --libdir="/usr/lib" \
    --libexecdir="/usr/lib" \
    --enable-kernel=6.15 \
    --with-headers="$SCRIPT_DIR/rootfs/usr/include"

  make -j"$JOBS"
  make install DESTDIR="$SCRIPT_DIR/rootfs"

  cd $SCRIPT_DIR
}

createInitramfs() {
  cd rootfs
  find . | cpio -H newc -o > $SCRIPT_DIR/init.cpio
  cd $SCRIPT_DIR
}

if [ "$#" -eq 0 ]; then
  prepareRootfs
  buildKernel
  installHeaders
  buildBusybox
  buildOpenRC
  buildGlibc
  createInitramfs
else
  for arg in "$@"; do
    case $arg in
      kernel|allnk|headers|rootfs|busybox|openrc|glibc|initramfs)
        ;;
      *)
        echo "Unknown argument: $arg"
        exit 1
        ;;
    esac
  done
  for arg in "$@"; do
    if [ "$arg" == "kernel" ]; then
      buildKernel
    elif [ "$arg" == "rootfs" ]; then
      prepareRootfs
    elif [ "$arg" == "headers" ]; then
      installHeaders
    elif [ "$arg" == "busybox" ]; then
      buildBusybox
    elif [ "$arg" == "openrc" ]; then
      buildOpenRC
    elif [ "$arg" == "glibc" ]; then
      buildGlibc
    elif [ "$arg" == "initramfs" ]; then
      createInitramfs
    elif [ "$arg" == "allnk" ]; then
      prepareRootfs
      installHeaders
      buildBusybox
      buildOpenRC
      buildGlibc
      createInitramfs
    else
      echo "Unknown argument: $arg"
      exit 1
    fi
  done
fi
