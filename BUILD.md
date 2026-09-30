# Building the AIX 4.3.3 + xldb image by hand

These are the manual steps that `build.sh` automates.  They produce the same
`data/aix433.dbxl.qcow2`: AIX 4.3.3 installed on an emulated IBM 40p, with
networking to the host, the IBM `xldb` debugger installed, and the guest set
up for dbxl's recon and tests.  For the automated version, see the
[TL;DR build](README.md#tldr-build) in the README.

`build.sh` does this in four stages, shutting down and keeping a disk image
after each one.  By hand it's simpler to do it all in one QEMU session, with
every CD and the network card attached from the start, and shut down once
at the end.

All commands on the host are run from the top of this repo.  Commands shown
after a `#` prompt are typed on the emulated AIX console, logged in as `root`.

## 1. Host packages

On Debian based systems:

```
apt update && apt install \
    build-essential git curl ninja-build pkg-config python3 python3-venv \
    libglib2.0-dev libpixman-1-dev libfdt-dev zlib1g-dev \
    libarchive-tools genisoimage qemu-utils expect
```

## 2. Build QEMU

Stock QEMU can't boot AIX on its 40p machine.  Use the `dbxl-debug` fork,
which is based on Artyom Tarasenko's `40p-20260308-aix-boots` branch:

```
mkdir -p src
git clone https://github.com/dbxl-debug/qemu-aix.git src/qemu-aix
cd src/qemu-aix
./configure --target-list=ppc-softmmu
make -j"$(nproc)"
cp build/qemu-system-ppc ../../bin/
cd ../..
```

QEMU needs the boot ROM for the 40p's network card.  Since the binary isn't
installed, copy it next to the other firmware:

```
mkdir -p res/pc-bios
cp src/qemu-aix/pc-bios/efi-pcnet.rom res/pc-bios/
```

## 3. Firmware, ISOs and the xldb images

Download these into `res/`:

| File | Where from | md5 |
| --- | --- | --- |
| `q40pofw-serial.rom` | <https://github.com/artyom-tarasenko/openfirmware/releases/download/40p-20190413/q40pofw-serial.rom> | `6afab1e6ffb2af7abb7f3de566f2a2ac` |
| `IBM AIX 4.3.3 (LCD4_0286_06) (ISO) [PPC] Volume 1.7z` | [WinWorld](https://winworldpc.com/download/6193a427-4be5-11e8-8d2a-fa163e9022f0/from/c3ae6ee2-8099-713d-3411-c3a6e280947e) | `c261fd0bf11f6a2a02db3caf2e04d718` |
| `SK2T-2729-03.01.iso` | <https://ftp.zx.net.nz/pub/Media/IBM/SK2T-2729-03.01.iso> | `32ce4ddbc8ae676c6de1e95ca45822e6` |
| `SK2T-2729-04.01.iso` | <https://ftp.zx.net.nz/pub/Media/IBM/SK2T-2729-04.01.iso> | `5f80c778cd3be23582a3ccaf8b867fd1` |

`q40pofw-serial.rom` is Artyom Tarasenko's Open Firmware for the 40p, built
to use the serial console.  The two `SK2T-2729` discs are AIX software CDs
that carry the `xldb` filesets.  The expected checksums are also in
`res/*.md5`, so you can check the downloads with:

```
cd res
md5sum -c *.md5
cd ..
```

Extract the install CD from the 7z archive:

```
bsdtar xvf "res/IBM AIX 4.3.3 (LCD4_0286_06) (ISO) [PPC] Volume 1.7z" \
    -C res --strip-components 1 "*/Volume_1.iso"
```

The `xldb` filesets are spread across the two `SK2T-2729` discs.
`bin/extract-xldb` pulls every version of `xldb.base`, `xldb.help.en_US` and
`xldb.msg.en_US` out of them into a plain tar file that AIX's `tar` can read:

```
bin/extract-xldb res/xldb.tar res/SK2T-2729-03.01.iso res/SK2T-2729-04.01.iso
```

AIX needs a way to read that tar file, so put it on a plain ISO9660 CD image
with no Rock Ridge or Joliet extensions:

```
genisoimage -quiet -V XLDB -o res/xldb.tar.iso res/xldb.tar
```

## 4. Host networking

AIX reaches the host through a tap device, `tap0`, with the host at
`192.168.76.1` and AIX at `192.168.76.2`.  Create it once per host boot:

```
sudo ip tuntap add tap0 mode tap user "$USER"
sudo ip addr add 192.168.76.1/24 dev tap0
sudo ip link set tap0 up
```

QEMU won't start without it, since the network card is attached for the
whole session.

## 5. Start QEMU

Create a blank 4 GB disk, then start QEMU with everything attached:

```
qemu-img create -f qcow2 data/aix433.dbxl.qcow2 4G
./bin/qemu-system-ppc -L res/pc-bios -M 40p -m 192 \
    -bios res/q40pofw-serial.rom -vga none -nographic \
    -hda data/aix433.dbxl.qcow2 \
    -nic tap,model=pcnet,ifname=tap0,script=no,downscript=no \
    -cdrom res/Volume_1.iso \
    -drive file=res/xldb.tar.iso,if=scsi,index=3,media=cdrom,readonly=on
```

* `-hda` is the disk AIX is installed on (`hdisk0`).
* `-nic` is a PCnet network card connected to `tap0`.
* `-cdrom` is the AIX install CD.  AIX sees it as `cd0`, and it's also used
  later for the AIXwindows libraries `xldb` needs.
* The `-drive` line adds `xldb.tar.iso` as a second CD-ROM at SCSI ID 3,
  which AIX sees as `cd1`.

`-nographic` puts the machine's serial console in your terminal.  The
firmware always tries to boot from the network first; after a short
countdown it fails with `Boot load failed` and leaves you at its `ok`
prompt.  Don't press any keys before then.

## 6. Install the Base Operating System

At the `ok` prompt, boot the install CD's AIX boot partition:

```
ok boot cdrom:2
```

The firmware reboots itself once ("Rebooting in the correct mode for this
client program") and then appears to sit at `Boot device:
/pci/scsi@1/disk@2,0:2` for a while.  That's normal; wait and don't press
anything.

Then answer the installer's prompts:

1. **Please define the System Console**: type `1` and press Enter.
2. **Language during install**: type `1` (English) and press Enter.
3. **Welcome to Base Operating System Installation and Maintenance**: type
   `2` (Change/Show Installation Settings and Install).
4. **Installation and Settings**: check that it shows
   * Method of Installation: **New and Complete Overwrite**
   * Disk Where You Want to Install: **hdisk0**
   * Install Trusted Computing Base: **No**

   then type `0` to install with those settings.

The **Installing Base Operating System** screen shows progress.  Ignore its
message about the system key; that's for real RS/6000 hardware.  When the
install finishes, AIX reboots and the firmware ends up at the `ok` prompt
again.  Boot the new system from the disk:

```
ok boot disk:1
```

Booting AIX under emulation takes a few minutes.  On this first boot:

1. **Set Terminal Type**: type `vt100` and press Enter.
2. The **Installation Assistant** menu appears.  Use the arrow keys to
   select **Set root Password**, press Enter and set the password.  The
   scripts in this repo expect `root`, unless you set `AIX_ROOT_PASSWORD`
   when running them.
3. Back in the menu, select **Tasks Completed - Exit to AIX Login** and
   press Enter.  This also grows the paging space to 256 MB.

Log in as `root` at the `Console login:` prompt, and carry straight on.

## 7. Set up networking

AIX 4.3.3 detects QEMU's PCnet network card as `ent0`, but can't use it
until the device's `busio` attribute is corrected.  Until then, bringing
up `en0` fails with `ns_alloc(en0) failed with errno = 50`.  The fix is
applied by a small script that runs on every boot.

Create the corrected ODM attribute:

```
# cat > /etc/qemu-ent0-busio.asc <<'EOF'
CuAt:
        name = "ent0"
        attribute = "busio"
        value = "0x01000000"
        type = "O"
        generic = "D"
        rep = "nr"
        nls_index = 3
EOF
```

Create the script that applies it, reconfigures `ent0` and brings up `en0`:

```
# cat > /etc/rc.qemu-net <<'EOF'
#!/bin/ksh

# QEMU 40p / AIX 4.3.3 PCnet busio workaround.
# Must run after PCI device discovery and before TCP/IP startup.

odmchange -o CuAt -q "name=ent0 and attribute=busio" /etc/qemu-ent0-busio.asc || exit 1

rmdev -l ent0 || exit 1
mkdev -l ent0 || exit 1

ifconfig en0 192.168.76.2 netmask 255.255.255.0 up
EOF
# chmod 755 /etc/rc.qemu-net
```

Run it now, and check that `en0` is up:

```
# /etc/rc.qemu-net
ent0 Defined
ent0 Available
# ifconfig en0
en0: flags=e080863<UP,BROADCAST,NOTRAILERS,RUNNING,SIMPLEX,MULTICAST,GROUPRT,64BIT>
        inet 192.168.76.2 netmask 0xffffff00 broadcast 192.168.76.255
```

`ping 192.168.76.1` should now reach the host; stop it with Ctrl-C.  Make the
script run on every boot by adding it to `/etc/inittab`, keeping a copy of
the original:

```
# cp /etc/inittab /etc/inittab.before-qemu-net
# mkitab -i rctcpip "qemunet:2:wait:/etc/rc.qemu-net > /dev/console 2>&1"
# lsitab qemunet
qemunet:2:wait:/etc/rc.qemu-net > /dev/console 2>&1
```

## 8. Install the xldb prerequisites and xldb

Mount both CDs:

```
# mkdir /cdrom
# mount -v cdrfs -o ro /dev/cd0 /cdrom
# mkdir /cdrom2
# mount -v cdrfs -o ro /dev/cd1 /cdrom2
```

### The prerequisites

`xldb` needs the AIXwindows runtime libraries from the install CD.  Install
`X11.base.lib`; `-g` also installs what it requires, `X11.base.common` and
`X11.base.smt`:

```
# installp -a -g -d /cdrom/usr/sys/inst.images X11.base.lib
# lslpp -L 'X11.base.*'
  X11.base.common            4.3.3.0    C    AIXwindows Runtime Common
  X11.base.lib              4.3.3.25    C    AIXwindows Runtime Libraries
  X11.base.smt               4.3.3.0    C    AIXwindows Runtime Shared Memory
```

### xldb

Unpack the xldb images, build the table of contents `installp` needs, and
install:

```
# mkdir /tmp/xldb
# cd /tmp/xldb
# tar xvf /cdrom2/xldb.tar
# inutoc .
# installp -a -d . xldb.base xldb.help.en_US xldb.msg.en_US
```

`installp` picks the newest levels and applies each update in turn.  It
warns about older versions being "Already superseded" and about conflicting
versions on the media; those warnings are expected.  Check that all three
filesets ended up at 1.2.1.1:

```
# lslpp -L 'xldb*'
  xldb.base                  1.2.1.1    A    IBM XLDB Source Level Debugger
  xldb.help.en_US            1.2.1.1    A    IBM XLDB Source Level Debugger
  xldb.msg.en_US             1.2.1.1    A    IBM XLDB Source Level Debugger
```

Clean up the unpacked images:

```
# cd /
# rm -rf /tmp/xldb
```

## 9. Set up for dbxl

dbxl's recon and tests build their test programs on the guest from
hand-written assembly, run them as an unprivileged `tester` user, and have
xldb read core files.

### The assembler and dbx

Install the assembler (`as`, in `bos.adt.base`), `/usr/lib/syscalls.exp`
(`bos.adt.syscalls`) and `dbx` (`bos.adt.debug`) from the install CD, still
mounted on `/cdrom`.  `-g` also installs `bos.adt.lib`, which
`bos.adt.base` requires:

```
# installp -a -g -d /cdrom/usr/sys/inst.images \
    bos.adt.base bos.adt.syscalls bos.adt.debug
# lslpp -L 'bos.adt.*'
  bos.adt.base               4.3.3.0    C    Base Application Development
                                             Toolkit
  bos.adt.debug              4.3.3.0    C    Base Application Development
                                             Debuggers
  bos.adt.lib                4.3.3.0    C    Base Application Development
                                             Libraries
  bos.adt.syscalls           4.3.3.0    C    System Calls Application
                                             Development Toolkit
```

### Core files

xldb predates AIX 4.3's core file layout; version 1.2.1.0 can only read
cores with both of these `sys0` settings on.  Without `fullcore` it fails with
`Read failed for corefile`; without `pre430core` it reports that the core
was generated by executable `"ÿÿÿÿ"`.

```
# chdev -l sys0 -a fullcore=true -a pre430core=true
# lsattr -El sys0 -a fullcore -a pre430core
fullcore   true Enable full CORE dump     True
pre430core true IBM PowerPC CHRP Computer True
```

### The tester account

Create the `tester` user and set its password to `tester`.  When root sets
a password, AIX makes the user change it at their next login; `pwdadm -c`
clears that:

```
# mkuser tester
# passwd tester
tester's New password:
Enter the new password again:
# pwdadm -c tester
```

`build.sh` uses `tester` unless you set `AIX_TESTER_PASSWORD`.

The CDs can be unmounted now:

```
# umount /cdrom
# umount /cdrom2
```

## 10. Shut down safely

Always shut AIX down cleanly before stopping QEMU, or the disk image may
be left with unclean filesystems:

```
# shutdown -F
```

The shutdown starts by printing `Wait for '....Halt completed....' before
stopping.`.  That's only a reminder: wait for the line that says just

```
....Halt completed....
```

then quit QEMU by pressing **Ctrl-A** and then **x**.

`data/aix433.dbxl.qcow2` is now the same image that `build.sh` produces.

## 11. Using the image

To keep the finished image pristine, run a copy of it, which is what
`run.sh` does:

```
cp data/aix433.dbxl.qcow2 data/aix433.working.qcow2
./bin/qemu-system-ppc -L res/pc-bios -M 40p -m 192 \
    -bios res/q40pofw-serial.rom -vga none -nographic \
    -hda data/aix433.working.qcow2 \
    -nic tap,model=pcnet,ifname=tap0,script=no,downscript=no
```

At the `ok` prompt, type `boot disk:1` and log in as `root`, or as `tester`
for anything that doesn't need root.  When you're done, shut down as in
step 10.
