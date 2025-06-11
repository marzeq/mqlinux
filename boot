#!/bin/bash
qemu-system-x86_64 \
  -kernel bzImage \
  -initrd init.cpio \
  -append "console=ttyS0 console=tty0 root=/dev/ram rdinit=/sbin/openrc-init" \
  -m 1024M \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device e1000,netdev=net0
