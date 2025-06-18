#!/bin/bash
set -e

export ROOT_DIR=$(dirname "$(readlink -f "$0")")
cd "$ROOT_DIR"

export JOBS=$(nproc)

prepareRootfs() {
  sudo rm -rf rootfs
  mkdir rootfs
  mkdir rootfs/{dev,etc,proc,sys,tmp,usr,run,var}
  mkdir -p rootfs/usr/{bin,lib,share,include}
  ln -s usr/lib rootfs/lib
  ln -s usr/bin rootfs/bin
  ln -s ./bin rootfs/usr/sbin
  ln -s usr/sbin rootfs/sbin
  ln -s ./lib rootfs/usr/lib64
  ln -s usr/lib64 rootfs/lib64
  ln -s ../etc rootfs/usr/etc
  mkdir -p rootfs/{root,home,mnt,lib/modules}
  chmod 1777 rootfs/tmp rootfs/run

  sudo mkdir -m 755 rootfs/dev/pts
  sudo mkdir -m 1777 rootfs/dev/shm

  mkdir -p rootfs/var/{cache,log,run,spool,mail}
  touch rootfs/var/run/utmp rootfs/var/log/wtmp
  sudo chown root:utmp rootfs/var/run/utmp rootfs/var/log/wtmp
  sudo chmod 664 rootfs/var/run/utmp rootfs/var/log/wtmp
}

setupUsers() {
  local users=("$@")

  cd rootfs
  touch etc/group etc/passwd etc/shadow
  sudo chroot . /bin/sh -c "addgroup -g 0 root"
  sudo chroot . /bin/sh -c "addgroup -g 10 uucp"
  sudo chroot . /bin/sh -c "adduser -g '' -G root -s /bin/sh -h /root   -u 0    root -D"
  ROOTPSWD="root"
  sudo chroot . /bin/sh -c "echo root:$ROOTPSWD | chpasswd -c SHA512"

  for user in $users; do
    if [[ -z "$user" ]]; then
      continue
    fi
    sudo chroot . /bin/sh -c "addgroup -g 900 $user"
    sudo chroot . /bin/sh -c "adduser -g '' -G $user -s /usr/bin/nologin -h / -u 900     $user -D"
  done

  chmod 644 etc/passwd etc/group
  chmod 600 etc/shadow
  sudo chown root:root etc/passwd etc/group etc/shadow
  cd "$ROOT_DIR"
}

createInitramfs() {
  cd rootfs
  sudo find . | sudo cpio -H newc -o > $ROOT_DIR/init.cpio
  cd $ROOT_DIR
}

getPackageTarball() {
  local name="$1"
  local version="$2"
  local url="$3"
  local tarball_name="$4"

  cd "$name"

  if [[ ! -f "$tarball_name" ]]; then
    wget "$url" -O "$tarball_name"
  fi

  cd "$ROOT_DIR"
}

preparePackageSrcDir() {
  local name="$1"
  local version="$2"
  local url="$3"

  if [[ "$url" =~ \.tar\.gz$ ]]; then
    local tarball_name="${name}-${version}.tar.gz"
  elif [[ "$url" =~ \.tar\.xz$ ]]; then
    local tarball_name="${name}-${version}.tar.xz"
  elif [[ "$url" =~ \.tar\.bz2$ ]]; then
    local tarball_name="${name}-${version}.tar.bz2"
  else
    echo "Error: Unsupported tarball format for $name."
    exit 1
  fi

  getPackageTarball "$name" "$version" "$url" "$tarball_name"

  cd "$name"

  if [[ ! -d "$name-$version-src" ]]; then
    tar -xf "$tarball_name"

    if [[ $(ls -d */ | grep -v "install/" | wc -l) -ne 1 ]]; then
      echo "Error: Expected exactly one directory in the current directory. Package tarball may be malformed."
      exit 1
    fi

    local src_dir=$(ls -d */ | grep -v "install/" | head -n 1)

    if [[ "$src_dir" != "$name-$version-src/" ]]; then
      echo "Renaming directory $src_dir to $name-$version-src"
      mv "$src_dir" "$name-$version-src"
    fi
  fi

  cd "$ROOT_DIR"
}

getPackageBuildHash() {
  local name="$1"
  local version="$2"
  local url="$3"

  source "$name/makepkg"
  local config_contents=""
  if [[ -f "$name/.config" ]]; then
    config_contents=$(cat "$name/.config")
  fi
  local build_hash_input="$config_contents$VERSION$LOCAL_USER$(declare -f build package configure)"
  local build_hash=$(echo $build_hash_input | sha256sum | awk '{print $1}')

  echo "$build_hash"
}

packageNeedsBuilding() {
  local name="$1"
  local version="$2"
  local url="$3"

  local build_hash=$(getPackageBuildHash "$name" "$version" "$url")
  
  if [[ ! -f "$name/build.done" ]]; then
    return 0  # Package needs building
  fi

  local build_done_hash=$(cat "$name/build.done")
  if [[ "$build_hash" != "$build_done_hash" ]]; then
    return 0  # Package needs building
  fi

  return 1  # Package should be up to date unless it has been tampered with, not our problem then
}

buildPackageIfNeeded() {
  local name="$1"
  local version="$2"
  local url="$3"

  if ! packageNeedsBuilding "$name" "$version" "$url"; then
    echo "Package $name is already built and up to date."
    return
  fi

  source "$name/makepkg"

  echo "Building $name version $version..."

  export INSTALLDIR="$ROOT_DIR/$name/install"
  export SRCDIR="$ROOT_DIR/$name/$name-$version-src"
  export PKGDIR="$ROOT_DIR/$name"

  set -x
  build
  set +x
  cd "$ROOT_DIR"

  sudo rm -rf "$INSTALLDIR"
  mkdir -p "$INSTALLDIR"

  set -x
  package
  set +x
  cd "$ROOT_DIR"

  set -x
  configure
  set +x
  cd "$ROOT_DIR"

  rm -rf "$name/$name-$version-src"

  echo "Build completed for $name version $version."

  local build_hash=$(getPackageBuildHash "$name" "$version" "$url")
  echo "$build_hash" > "$name/build.done"

  echo "Build hash for $name version $version saved."
}

installPackage() {
  local name="$1"
  local version="$2"
  local url="$3"

  if [[ ! -f "$name/build.done" ]] || [[ ! -d "$name/install" ]]; then
    rm -f "$name/build.done"
    buildPackageIfNeeded "$name" "$version" "$url"
  fi

  cd "$name"
  echo "Installing $name version $version..."
  rsync -a --keep-dirlinks install/ "$ROOT_DIR/rootfs/"

  echo "Installation completed for $name version $version."
  cd "$ROOT_DIR"
}

INSTALL_ORDER=(
  "linux"
  "glibc"
  "ncurses"
  "procps" 
  "libcap"
  "libcap-ng"
  "libaudit"
  "libxcrypt"
  "libtirpc"
  "libnsl"
  "kmod"
  "zstd"
  "xz"
  "zlib"
  "openssl"
  "eudev"
  "pam"
  "util-linux"
  "kbd"
  "dhcpcd"
  "busybox"
  "openrc"
)

main() {
  prepareRootfs

  local users_to_create=()

  for package in "${INSTALL_ORDER[@]}"; do
    cd "$ROOT_DIR"
    source "$package/makepkg"
    if [[ -n "$LOCAL_USER" ]]; then
      users_to_create+=("$LOCAL_USER")
    fi
    local name="$NAME"
    local version="$VERSION"
    local tarball_url="$TARBALL_URL"

    preparePackageSrcDir "$name" "$version" "$tarball_url"
    buildPackageIfNeeded "$name" "$version" "$tarball_url"
    installPackage "$name" "$version" "$tarball_url"
    echo
  done

  setupUsers "${users_to_create[@]}"
  sudo chown -R root:root rootfs
  createInitramfs

  echo
  init_size=$(du -sh init.cpio | awk '{print $1}')
  echo "Initramfs ($init_size) - $ROOT_DIR/init.cpio"

  kernel_size=$(du -sh bzImage | awk '{print $1}')
  echo "Kernel ($kernel_size) - $ROOT_DIR/bzImage"

  total_size=$(du -cb init.cpio bzImage | grep total | awk '{print $1}')
  human_total=$(numfmt --to=iec $total_size)
  echo "Total - $human_total"

  echo
  echo "Run ./boot to test the system using QEMU, or package the kernel, initramfs and a bootloader to create a bootable image."
}

main "$@"
