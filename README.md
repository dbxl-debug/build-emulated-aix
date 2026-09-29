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

To build the same image by hand instead, see [BUILD.md](BUILD.md).

## Run

```
./run.sh
```

When you get to the `ok` prompt enter `boot disk:1`.  You should be able to
login as `root` with password `root`.  You can also telnet or ftp to the
emulated AIX system at `192.168.76.2`, and from AIX your host system is
`192.168.76.1`.

## Acknowledgements

This project builds on Artyom Tarasenko's work enabling IBM AIX to run under
QEMU's PowerPC/PReP (IBM 40p) emulation. In particular, it uses his patched
QEMU branch
[`40p-20260308-aix-boots`](https://github.com/artyom-tarasenko/qemu/tree/40p-20260308-aix-boots)
and
[custom Open Firmware implementation](https://github.com/artyom-tarasenko/openfirmware/releases/tag/40p-20190413).
His
[AIX/PReP under QEMU How-To](https://tyom.blogspot.com/2019/04/aixprep-under-qemu-how-to.html)
provided the foundation for this setup. Many thanks to Artyom for developing
and documenting this work.
