# mqlinux

A minimal Linux system with an automated build process.

## Overview

This project automates building a minimal Linux environment from source. The build process is orchestrated by the `make` script,
which prepares a root filesystem, fetches, builds, installs, and configures a set of core packages using per-package `makepkg` scripts
found in each package directory (e.g., `linux/makepkg`, `glibc/makepkg`, etc.).

## How It Works

- **`make`**: The main script. It:
  - Creates the root filesystem structure.
  - Iterates through a predefined package list, using each package’s `makepkg` to download, build, install, and configure.
  - Creates a hash of the build process for each package and on consecutive runs, it checks if the package has changed to avoid unnecessary rebuilds.
  - At the end, builds an initramfs image.

- **`*/makepkg`**: Each package directory contains a `makepkg` script defining how to build and install that package.
  These scripts standardize the build process by defining `build`, `install`, and `configure` functions.

- Packages include the Linux kernel, glibc, BusyBox, OpenRC, and other essential utilities.

## Usage

```sh
./make
```

This will build all components and produce a bootable root filesystem and initramfs.

## TODO

- [x] Get networking working
- [ ] Modify the build process to produce tarballs of each package, effectively making a proto-package manager
  - [ ] Transform the proto-package manager into a full package manager and bundle it with the root filesystem
- [ ] Transition from `busybox` to `GNU coreutils`
- [ ] Add more packages (e.g., `bash`, `zsh`, `vim`, `git`, etc.)
- [x] Use `udev` instead of a fixed `/dev` directory
  - [ ] Stop cheating and build `libgcc_s.so` and `libgcc_s.so.1` from source, instead of copying them from the host system
- [ ] Add a bootloader configuration and ability to make a bootable ISO
- [ ] Add an install script to the ISO that can install the system to a disk
- [ ] Move each package into its own repository

# License

This project (in particular, the `make` script and each package `makepkg` script and accompanying files) is licensed under the GPL-3.0 License.

See the [LICENSE.md](LICENSE.md) file for details.
