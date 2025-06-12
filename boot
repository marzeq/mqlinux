#!/bin/bash
nographic=false
kernelimage="bzImage"
initrdimage="init.cpio"

for arg in "$@"; do
  if [ "$arg" = "-nog" ]; then
    nographic=true
  elif [[ "$arg" == "-kernel="* ]]; then
    kernelimage="${arg#-kernel=}"
  elif [[ "$arg" == "-initrd="* ]]; then
    initrdimage="${arg#-initrd=}"
  fi
done

if [ "$nographic" = true ]; then
  qemu-system-x86_64 \
    -kernel "$kernelimage" \
    -initrd "$initrdimage" \
    -append "console=ttyS0 root=/dev/ram rdinit=/sbin/openrc-init" \
    -m 1024M \
    -nographic \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device e1000,netdev=net0
else
  qemu-system-x86_64 \
    -kernel "$kernelimage" \
    -initrd "$initrdimage" \
    -append "console=tty0 root=/dev/ram rdinit=/sbin/openrc-init" \
    -m 1024M \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device e1000,netdev=net0
fi
