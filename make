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

  sudo mknod -m 666 rootfs/dev/null c 1 3
  sudo mknod -m 666 rootfs/dev/zero c 1 5
  sudo mknod -m 666 rootfs/dev/full c 1 7
  sudo mknod -m 666 rootfs/dev/random c 1 8
  sudo mknod -m 666 rootfs/dev/urandom c 1 9
  sudo mknod -m 600 rootfs/dev/console c 5 1
  sudo mknod -m 666 rootfs/dev/ptmx c 5 2
  sudo mkdir -m 755 rootfs/dev/pts
  sudo mkdir -m 1777 rootfs/dev/shm

  mkdir -p rootfs/var/{cache,log,run,spool,mail}
  touch rootfs/var/run/utmp rootfs/var/log/wtmp
  sudo chown root:utmp rootfs/var/run/utmp rootfs/var/log/wtmp
  sudo chmod 664 rootfs/var/run/utmp rootfs/var/log/wtmp

  sudo mknod -m 666 rootfs/dev/tty c 5 0
  sudo mknod -m 666 rootfs/dev/ttyAMA0 c 204 64
  for x in {0..12}; do
    sudo mknod -m 660 rootfs/dev/tty$x c 4 $x
  done
}

createUser() {
  cd rootfs
  touch etc/group etc/passwd etc/shadow
  sudo chroot . /bin/sh -c "addgroup -g 0 root"
  sudo chroot . /bin/sh -c "adduser -g '' -D -u 0 -G root -s /bin/sh -h /root root"
  ROOTPSWD="root"
  sudo chroot . /bin/sh -c "echo root:$ROOTPSWD | chpasswd -c SHA512"
  chmod 644 etc/passwd etc/group
  chmod 600 etc/shadow
  sudo chown root:root etc/passwd etc/group etc/shadow
  cd "$ROOT_DIR"
}

createInitramfs() {
  cd rootfs
  find . | sudo cpio -H newc -o > $ROOT_DIR/init.cpio
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

  if [[ ! -d "$name-$version" ]]; then
    tar -xf "$tarball_name"

    if [[ $(ls -d */ | grep -v "install/" | wc -l) -ne 1 ]]; then
      echo "Error: Expected exactly one directory in the current directory. Package tarball may be malformed."
      exit 1
    fi

    local src_dir=$(ls -d */ | head -n 1)

    if [[ "$src_dir" != "$name-$version/" ]]; then
      echo "Renaming directory $src_dir to ${name}-$version"
      mv "$src_dir" "${name}-$version"
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
  local build_hash_input="$config_contents$VERSION$(declare -f build install)"
  local build_hash=$(echo $build_hash_input | sha256sum | awk '{print $1}')
  NAME=""
  VERSION=""
  TARBALL_URL=""
  unset -f build install configure

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

  cd "$name/$name-$version"

  echo "Building $name version $version..."

  set -x
  build
  set +x

  cd "$ROOT_DIR/$name/$name-$version"

  set -x
  export INSTALLDIR="$ROOT_DIR/$name/install"
  sudo rm -rf "$INSTALLDIR"
  mkdir -p "$INSTALLDIR"
  install
  export INSTALLDIR=""
  set +x

  NAME=""
  VERSION=""
  TARBALL_URL=""
  unset -f build install configure

  cd "$ROOT_DIR"

  echo "Build completed for $name version $version."

  local build_hash=$(getPackageBuildHash "$name" "$version" "$url")
  echo "$build_hash" > "$name/build.done"

  echo "Build hash for $name version $version saved."

  cd "$ROOT_DIR"
}

installPackage() {
  local name="$1"
  local version="$2"
  local url="$3"

  if [[ ! -f "$name/build.done" ]]; then
    echo "Error: Package $name version $version has not been built yet."
    exit 1
  fi

  cd "$name"
  echo "Installing $name version $version..."
  rsync -a --keep-dirlinks install/ "$ROOT_DIR/rootfs/"

  echo "Installation completed for $name version $version."
  cd "$ROOT_DIR"
}

configurePackage() {
  local name="$1"
  local version="$2"
  local url="$3"

  if [[ ! -f "$name/build.done" ]]; then
    echo "Error: Package $name version $version has not been built yet."
    exit 1
  fi

  source "$name/makepkg"
  echo "Configuring $name version $version..."
  set -x
  configure
  set +x
  echo "Configuration completed for $name version $version."
  NAME=""
  VERSION=""
  TARBALL_URL=""
  unset -f build install configure
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
  "pam"
  "util-linux"
  "kbd"
  "busybox"
  "openrc"
)

main() {
  prepareRootfs

  for package in "${INSTALL_ORDER[@]}"; do
    cd "$ROOT_DIR"
    source "$package/makepkg"
    local name="$NAME"
    local version="$VERSION"
    local tarball_url="$TARBALL_URL"
    NAME=""
    VERSION=""
    TARBALL_URL=""
    unset -f build install configure

    preparePackageSrcDir "$name" "$version" "$tarball_url"
    buildPackageIfNeeded "$name" "$version" "$tarball_url"
    installPackage "$name" "$version" "$tarball_url"
    configurePackage "$name" "$version" "$tarball_url"
  done

  createUser
  createInitramfs
}

main "$@"
