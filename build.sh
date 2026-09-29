#!/bin/bash

set -e

BUILDROOT="$(realpath $(dirname "$0"))"
cd "$BUILDROOT"

if [ ! -x bin/qemu-system-ppc ]; then
    if [ ! -d src/qemu-aix ]; then
        mkdir -p src
        git clone https://github.com/dbxl-debug/qemu-aix.git src/qemu-aix
    fi
    cd src/qemu-aix
    git fetch origin
    if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
      git switch main
    fi
    git pull --ff-only origin main
    ./configure --target-list=ppc-softmmu
    make -j"$(nproc)"
    cp ./build/qemu-system-ppc ../../bin/
    cd ../..
fi

if [ ! -e "res/pc-bios/efi-pcnet.rom" ]; then
    mkdir -p "res/pc-bios"
    cp "src/qemu-aix/pc-bios/efi-pcnet.rom" "res/pc-bios/efi-pcnet.rom"
fi

fetch() {
    local url="$1"
    local filename="$2"
    cd "$BUILDROOT/res"
    if ! md5sum -c --status "$filename.md5"; then
        curl -fL -o "$filename" "$url"
        md5sum -c "$filename.md5"
    fi
    cd "$BUILDROOT"
}

fetch https://github.com/artyom-tarasenko/openfirmware/releases/download/40p-20190413/q40pofw-serial.rom q40pofw-serial.rom
fetch https://winworldpc.com/download/6193a427-4be5-11e8-8d2a-fa163e9022f0/from/c3ae6ee2-8099-713d-3411-c3a6e280947e "IBM AIX 4.3.3 (LCD4_0286_06) (ISO) [PPC] Volume 1.7z"
fetch https://ftp.zx.net.nz/pub/Media/IBM/SK2T-2729-03.01.iso SK2T-2729-03.01.iso
fetch https://ftp.zx.net.nz/pub/Media/IBM/SK2T-2729-04.01.iso SK2T-2729-04.01.iso

if [ ! -e "res/Volume_1.iso" ]; then
    bsdtar xvf "res/IBM AIX 4.3.3 (LCD4_0286_06) (ISO) [PPC] Volume 1.7z" -C res --strip-components 1 "*/Volume_1.iso"
fi

if [ ! -e "res/xldb.tar" ]; then
    bin/extract-xldb "res/xldb.tar" "res/SK2T-2729-03.01.iso" "res/SK2T-2729-04.01.iso"
fi

# Plain ISO9660 with no Rock Ridge or Joliet, holding just xldb.tar.
if [ ! -e "res/xldb.tar.iso" ]; then
    genisoimage -quiet -V XLDB -o "res/xldb.tar.tmp.iso" "res/xldb.tar"
    mv "res/xldb.tar.tmp.iso" "res/xldb.tar.iso"
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

# Install BOS onto a scratch disk and only move it into place once the
# install succeeds, so a failed install gets retried on the next run.
if [ ! -e data/aix433.bos.qcow2 ]; then
    rm -f data/aix433.bos.qcow2.tmp
    qemu-img create -f qcow2 data/aix433.bos.qcow2.tmp 4G
    expect lib/exp/install-bos.exp "${QEMU[@]}" \
        -cdrom res/Volume_1.iso \
        -hda data/aix433.bos.qcow2.tmp
    chmod 400 data/aix433.bos.qcow2.tmp
    mv data/aix433.bos.qcow2.tmp data/aix433.bos.qcow2
fi

# set up networking
if [ ! -e data/aix433.net.qcow2 ]; then
    cp data/aix433.bos.qcow2 data/aix433.net.qcow2.tmp
    chmod 600 data/aix433.net.qcow2.tmp
    expect lib/exp/setup-network.exp "${QEMU[@]}" \
        -hda data/aix433.net.qcow2.tmp \
        -nic tap,model=pcnet,ifname=tap0,script=no,downscript=no
    chmod 400 data/aix433.net.qcow2.tmp
    mv data/aix433.net.qcow2.tmp data/aix433.net.qcow2
fi

# install xldb
if [ ! -e data/aix433.xldb.qcow2 ]; then
    cp data/aix433.net.qcow2 data/aix433.xldb.qcow2.tmp
    chmod 600 data/aix433.xldb.qcow2.tmp
    expect lib/exp/install-xldb.exp "${QEMU[@]}" \
        -hda data/aix433.xldb.qcow2.tmp \
        -nic tap,model=pcnet,ifname=tap0,script=no,downscript=no \
        -cdrom res/Volume_1.iso \
        -drive file=res/xldb.tar.iso,if=scsi,index=3,media=cdrom,readonly=on
    chmod 400 data/aix433.xldb.qcow2.tmp
    mv data/aix433.xldb.qcow2.tmp data/aix433.xldb.qcow2
fi
