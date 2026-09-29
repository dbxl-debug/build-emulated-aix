#!/bin/bash

set -e

if [ ! -f data/aix433.xldb.qcow2 ]; then
    ./build.sh
fi

QEMU=(
  ./bin/qemu-system-ppc
  -L res/pc-bios
  -M 40p
  -m 192
  -bios res/q40pofw-serial.rom
  -vga none
  -nographic
)

# create a one-off working copy
cp data/aix433.xldb.qcow2 data/aix433.working.$$.qcow2
chmod 600 data/aix433.working.$$.qcow2

"${QEMU[@]}" \
    -hda data/aix433.working.$$.qcow2 \
    -nic tap,model=pcnet,ifname=tap0,script=no,downscript=no