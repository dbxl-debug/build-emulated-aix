# build-emulated-aix

## abstract

This repo contains tools for building QEUM that will run AIX 4.3.3 and
installs the AIX base image, sets up networking, and then installs the IBM AIX
`xldb` graphical debugger.  This is part of the **dbxl debugger** project
which aims to build an `xldb` clone for modern systems.

## prereqs

On Debian based systems:

```
apt update && apt install \
    build-essential git curl ninja-build pkg-config python3 python3-venv \
    libglib2.0-dev libpixman-1-dev libfdt-dev zlib1g-dev \
    libarchive-tools genisoimage qemu-utils expect
```

## TL;DR build

```
./build.sh
```

