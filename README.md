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

## Host network

TODO

## TL;DR build

The `build.sh` script will

1. Build a patched QEMU that can run AIX 4.3.3
2. Install the base AIX 4.3.3 and `xldb` packages
3. Set up network between the host and the emulated AIX via `tap0`

```
./build.sh
```

## Run

```
./run.sh
```

When you get to the `ok` prompt enter `boot disk:1`.  You should be able to
login as `root` with password `root`.  You can also telnet or ftp to the
emulated AIX system at `192.168.76.2`, and from AIX your host system is
`192.168.76.1`.