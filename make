#!/bin/bash
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

# NCURSES_VERSION="6.5"
# NCURSES_URL="https://ftpmirror.gnu.org/ncurses/ncurses-$NCURSES_VERSION.tar.gz"
#
# ZSH_VERSION="5.9.0.2-test"
# ZSH_URL="https://github.com/zsh-users/zsh/archive/refs/tags/zsh-$ZSH_VERSION.tar.gz"

JOBS=$(nproc)

prepareRootfs() {
  mkdir rootfs
  mkdir rootfs/{dev,etc,proc,sys,tmp,usr,run,var}
  mkdir -p rootfs/usr/{bin,lib,share,include}
  ln -s lib rootfs/usr/lib64
  ln -s usr/bin rootfs/bin
  ln -s usr/bin rootfs/sbin
  ln -s usr/lib rootfs/lib
  ln -s usr/lib64 rootfs/lib64
  sudo mknod -m 666 rootfs/dev/null c 1 3
  sudo mknod -m 666 rootfs/dev/zero c 1 5
  sudo mknod -m 666 rootfs/dev/console c 5 1
  sudo mknod -m 666 rootfs/dev/tty c 5 0
  sudo mknod -m 666 rootfs/dev/tty1 c 4 1
  sudo mknod -m 666 rootfs/dev/tty2 c 4 2
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
  cd ../..
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
  cd ../..
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
  make CONFIG_PREFIX="../../rootfs" install
  cd ../../rootfs
  rm linuxrc
  unlink sbin/init
  echo -e '#!/bin/sh\nexec /bin/sh' > init
  chmod +x init
  cd ..
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
  make install DESTDIR="$(pwd)/../../../rootfs"
  cd ../..
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
  make install DESTDIR="$(pwd)../../../rootfs"
  cd ../..
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
  meson install -C build --destdir ../../../rootfs
  cd ../../rootfs

  mkdir -p etc/init.d
  touch etc/fstab etc/inittab
  ln -s ./openrc-init sbin/init

  cat > etc/inittab <<EOF
::sysinit:/etc/init.d/rcS
::respawn:/sbin/getty 38400 tty1
::ctrlaltdel:/sbin/reboot
EOF

  cat > etc/init.d/rcS <<EOF
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t tmpfs -o nosuid,nodev tmpfs /run
mkdir -p /run/lock /run/openrc
source /etc/init.d/functions.sh
rc_provide
EOF
  chmod +x etc/init.d/rcS

  mkdir -p var/cache/rc

  buildKbd
  buildProcps

  cd ..
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
    --with-headers="$(pwd)/../../../rootfs/usr/include"

  make -j"$JOBS"
  make install DESTDIR="../../../rootfs"

  cd ../..
}

# buildNcurses() {
#   mkdir -p ncurses
#   cd ncurses
#   if [ ! -f "ncurses.tar.gz" ]; then
#     wget "$NCURSES_URL" -O ncurses.tar.gz
#     tar -xf ncurses.tar.gz
#     mv ncurses-* ncurses-src
#   fi
#   cd ncurses-src
#   ./configure --prefix=/usr \
#     --without-cxx-binding \
#     --with-shared
#
#   make -j"$JOBS"
#   mkdir -p ../install
#   make install DESTDIR="$(pwd)/../install"
#   cd ../..
#   cp -r ncurses/install/* rootfs
# }
#
# buildZsh() {
#   mkdir -p zsh
#   cd zsh
#   if [ ! -f "zsh.tar.gz" ]; then
#     wget "$ZSH_URL" -O zsh.tar.gz
#     tar -xf zsh.tar.gz
#     mv zsh-* zsh-src
#   fi
#   cd zsh-src
#   ./Util/preconfig
#   ./configure --prefix=/usr --sysconfdir=/etc --libexecdir=/usr/lib/zsh
#   make -j"$JOBS"
#   make install.bin DESTDIR="../../../rootfs"
#   make install.modules DESTDIR="../../../../rootfs"
#   cd ../..
# }

createInitramfs() {
  cd rootfs
  find . | cpio -H newc -o > ../init.cpio
  cd ..
}

if [ "$#" -eq 0 ]; then
  prepareRootfs
  buildKernel
  installHeaders
  buildBusybox
  buildOpenRC
  buildGlibc
  # buildNcurses
  # buildZsh
  createInitramfs
else
  for arg in "$@"; do
    case $arg in
      kernel|allnk|headers|rootfs|busybox|openrc|glibc|ncurses|zsh|initramfs)
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
    # elif [ "$arg" == "ncurses" ]; then
    #   buildNcurses
    # elif [ "$arg" == "zsh" ]; then
    #   buildZsh
    elif [ "$arg" == "initramfs" ]; then
      createInitramfs
    elif [ "$arg" == "allnk" ]; then
      prepareRootfs
      installHeaders
      buildBusybox
      buildOpenRC
      buildGlibc
      # buildNcurses
      # buildZsh
      createInitramfs
    else
      echo "Unknown argument: $arg"
      exit 1
    fi
  done
fi
