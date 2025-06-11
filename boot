#!/bin/bash
if [ "$1" = "nog" ]; then
  qemu-system-x86_64 \
    -kernel bzImage \
    -initrd init.cpio \
    -append "console=ttyS0 root=/dev/ram rdinit=/sbin/init" \
    -m 1024M \
    -nographic \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device e1000,netdev=net0
else
qemu-system-x86_64 \
  -kernel bzImage \
  -initrd init.cpio \
  -append "console=tty0 root=/dev/ram rdinit=/sbin/init" \
  -m 1024M \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device e1000,netdev=net0
fi
