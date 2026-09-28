#!/bin/bash

set -ex

cd "$(dirname "$0")"

if [ ! -x bin/qemu-system-ppc ]; then
    if [ ! -d qemu-aix ]; then
        git clone git@github.com:dbxl-debug/qemu-aix.git qemu-aix
    fi
    cd qemu-aix
    git fetch origin
    if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
      git switch main
    fi
    git pull --ff-only origin main
    ./configure --target-list=ppc-softmmu
    make -j"$(nproc)"
    cp ./build/qemu-system-ppc ../bin/
    cd ..
fi

if ! (cd res && md5sum -c --status md5); then
    curl -fL -o res/q40pofw-serial.rom https://github.com/artyom-tarasenko/openfirmware/releases/download/40p-20190413/q40pofw-serial.rom
    (cd res && md5sum -c md5)
fi

