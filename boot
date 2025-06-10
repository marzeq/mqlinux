#!/bin/bash
qemu-system-x86_64 \
  -kernel bzImage \
  -initrd init.cpio \
  -append "console=ttyS0 root=/dev/ram rdinit=/sbin/init" \
  -nographic \
  -m 1024M
