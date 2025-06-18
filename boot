#!/bin/bash
nographic=false
kernelimage="bzImage"
initrdimage="init.cpio"
init="/sbin/openrc-init"

for arg in "$@"; do
  # useful for debugging kernel or init system issues,
  # because the errors don't dissapear when we get to the getty login screen
  if [ "$arg" = "-nog" ]; then
    nographic=true
  elif [[ "$arg" == "-kernel="* ]]; then
    kernelimage="${arg#-kernel=}"
  elif [[ "$arg" == "-initrd="* ]]; then
    initrdimage="${arg#-initrd=}"
  elif [[ "$arg" == "-init="* ]]; then
    init="${arg#-init=}"
  else
    echo "Unknown argument: $arg"
    exit 1
  fi
done

if [ "$nographic" = true ]; then
  qemu-system-x86_64 \
    -kernel "$kernelimage" \
    -initrd "$initrdimage" \
    -append "console=ttyS0 root=/dev/ram rdinit=$init" \
    -m 1024M \
    -nographic \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device e1000,netdev=net0
else
  qemu-system-x86_64 \
    -kernel "$kernelimage" \
    -initrd "$initrdimage" \
    -append "console=tty1 root=/dev/ram rdinit=$init" \
    -m 1024M \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device e1000,netdev=net0
fi
