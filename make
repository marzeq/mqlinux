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

LICAP_NG_VERSION="0.8.5"
LICAP_NG_URL="https://github.com/stevegrubb/libcap-ng/archive/refs/tags/v$LICAP_NG_VERSION.tar.gz"

UTIL_LINUX_VERSION="2.41"
UTIL_LINUX_URL="https://github.com/util-linux/util-linux/archive/refs/tags/v$UTIL_LINUX_VERSION.tar.gz"

NCURSES_VERSION="6.5"
NCURSES_URL="https://ftpmirror.gnu.org/ncurses/ncurses-$NCURSES_VERSION.tar.gz"

PAM_VERSION="1.7.0"
PAM_URL="https://github.com/linux-pam/linux-pam/releases/download/v$PAM_VERSION/Linux-PAM-$PAM_VERSION.tar.xz"

LIBAUDIT_VERSION="4.0.5"
LIBAUDIT_URL="https://github.com/linux-audit/audit-userspace/archive/refs/tags/v$LIBAUDIT_VERSION.tar.gz"

JOBS=$(nproc)

prepareRootfs() {
  set -x
  mkdir rootfs
  mkdir rootfs/{dev,etc,proc,sys,tmp,usr,run,var}
  mkdir -p rootfs/usr/{bin,lib,share,include}
  ln -s usr/lib rootfs/lib
  ln -s usr/bin rootfs/bin
  ln -s usr/bin rootfs/sbin
  ln -s usr/lib64 rootfs/lib64
  mkdir -p rootfs/{root,home,mnt,lib/modules}
  chmod 1777 rootfs/tmp rootfs/run
  ln -s lib rootfs/usr/lib64

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
  set -x
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
  set -x
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
  set -x
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
  set -x
  mkdir -p kbd
  cd kbd
  if [ ! -f "kbd.tar.xz" ]; then
    wget "$KBD_URL" -O kbd.tar.xz
    tar -xf kbd.tar.xz
    mv kbd-* kbd-src
  fi
  cd kbd-src
  ./configure --prefix=/usr --libdir=/usr/lib
  make -j"$JOBS"
  make install DESTDIR="$SCRIPT_DIR/rootfs"
  cd $SCRIPT_DIR
}

buildProcps() {
  set -x
  mkdir -p procps
  cd procps
  if [ ! -f "procps.tar.gz" ]; then
    wget "$PROCPS_URL" -O procps.tar.gz
    tar -xf procps.tar.gz
    mv procps-* procps-src
  fi
  cd procps-src
  ./autogen.sh
  ./configure --prefix=/usr --sysconfdir=/etc --libdir=/usr/lib
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
  set -x
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

buildLibcapNg() {
  set -x
  mkdir -p libcap-ng
  cd libcap-ng
  if [ ! -f "libcap-ng.tar.gz" ]; then
    wget "$LICAP_NG_URL" -O libcap-ng.tar.gz
    tar -xf libcap-ng.tar.gz
    mv libcap-ng-* libcap-ng-src
  fi
  cd libcap-ng-src
  ./autogen.sh
  ./configure --prefix=/usr --sysconfdir=/etc --libdir=/usr/lib

  make -j"$JOBS"
  make install DESTDIR="$SCRIPT_DIR/rootfs"
  cd $SCRIPT_DIR
}

buildUtilLinux() {
  set -x
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
    --disable-nls \
    --without-systemd \
    --without-python

  make -j"$JOBS"
  sudo make install-strip DESTDIR="$SCRIPT_DIR/rootfs"
  cd $SCRIPT_DIR
}

buildNcurses() {
  set -x
  mkdir -p ncurses
  cd ncurses
  if [ ! -f "ncurses.tar.gz" ]; then
    wget "$NCURSES_URL" -O ncurses.tar.gz
    tar -xf ncurses.tar.gz
    mv ncurses-* ncurses-src
  fi
  cd ncurses-src
  ./configure --prefix=/usr \
    --without-cxx-binding \
    --with-shared

  make -j"$JOBS"
  mkdir -p ../install
  make install DESTDIR="$SCRIPT_DIR/rootfs"
  cd $SCRIPT_DIR
}

setupPamConfig() {
  cd $SCRIPT_DIR/rootfs

  mkdir -p etc/pam.d

  cat > etc/pam.d/login <<EOF
#%PAM-1.0
auth      required  pam_unix.so nullok
account   required  pam_unix.so
password  required  pam_unix.so
session   required  pam_unix.so
EOF

  cat > etc/pam.d/other <<EOF
#%PAM-1.0
auth     required     pam_deny.so
account  required     pam_deny.so
password required     pam_deny.so
session  required     pam_deny.so
EOF

  cat > etc/pam.d/agetty <<EOF
#%PAM-1.0
auth      required  pam_unix.so nullok
account   required  pam_unix.so
password  required  pam_unix.so
session   required  pam_unix.so
EOF

  cd $SCRIPT_DIR
}

setupAuthFiles() {
  cd $SCRIPT_DIR/rootfs

  echo "root:x:0:0:root:/root:/bin/sh" > etc/passwd
  echo "root:x:0:root" > etc/group
  echo "root::0:0:99999:7:::" > etc/shadow
  chmod 600 etc/shadow

  cat > etc/nsswitch.conf <<EOF
passwd: files
group: files
shadow: files
hosts: files dns
networks: files
protocols: files
services: files
EOF

  cd $SCRIPT_DIR
}

buildPam() {
  set -x
  mkdir -p pam
  cd pam
  if [ ! -f "pam.tar.xz" ]; then
    wget "$PAM_URL" -O pam.tar.xz
    tar -xf pam.tar.xz
    mv Linux-PAM-* pam-src
  fi
  cd pam-src
  meson setup build \
    --prefix=/usr \
    --sysconfdir=/etc \
    --buildtype=release \
    --libdir=/usr/lib \
    -Dselinux=disabled \
    -Ddocs=disabled

  meson compile -C build -j"$JOBS"
  meson install -C build --destdir $SCRIPT_DIR/rootfs
  cd $SCRIPT_DIR

  setupPamConfig
  setupAuthFiles
}

buildLibAudit() {
  set -x
  mkdir -p libaudit
  cd libaudit
  if [ ! -f "libaudit.tar.gz" ]; then
    wget "$LIBAUDIT_URL" -O libaudit.tar.gz
    tar -xf libaudit.tar.gz
    mv audit-userspace-* libaudit-src
  fi
  cd libaudit-src
  autoreconf -f --install
  ./configure --prefix=/usr \
    --sysconfdir=/etc \
    --libdir=/usr/lib

  make -j"$JOBS"
  make install DESTDIR="$SCRIPT_DIR/rootfs"
  cd $SCRIPT_DIR
}

setupOpenRC() {
  cd $SCRIPT_DIR/rootfs

  mkdir -p etc/init.d
  touch etc/fstab etc/inittab
  unlink sbin/init || true
  ln -s ./openrc-init sbin/init

  cat > etc/fstab <<EOF
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
tmpfs /run tmpfs nosuid,nodev 0 0
tmpfs /run/lock tmpfs nosuid,nodev 0 0
tmpfs /run/openrc tmpfs nosuid,nodev 0 0
tmpfs /tmp tmpfs nosuid,nodev 0 0
EOF

  mkdir -p var/cache/rc
  mkdir -p run/openrc

  mkdir -p "etc/runlevels/default"
  cd etc/init.d
  for n in $(seq 1 6); do
    ln -sf agetty agetty.tty$n
    ln -sf "/etc/init.d/agetty.tty$n" "$SCRIPT_DIR/rootfs/etc/runlevels/default/agetty.tty$n"
  done

  cd $SCRIPT_DIR
}

buildOpenRC() {
  set -x
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

  cd $SCRIPT_DIR

  setupOpenRC
  
  buildKbd
  buildProcps
  buildLibcap
  buildLibcapNg
  buildUtilLinux
  buildNcurses
  buildPam
  buildLibAudit
}

buildGlibc() {
  set -x
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
}

createInitramfs() {
  set -x
  cd rootfs
  find . | cpio -H newc -o > $SCRIPT_DIR/init.cpio
  cd $SCRIPT_DIR
}

if [ "$#" -eq 0 ]; then
  prepareRootfs
  buildKernel
  installHeaders
  buildGlibc
  buildBusybox
  buildOpenRC
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
      buildGlibc
      buildOpenRC
      createInitramfs
    else
      echo "Unknown argument: $arg"
      exit 1
    fi
  done
fi

