"""BSD rcmd protocol, shared by the rsh and rcp clients.

Connects to rshd (port 514) from a reserved port and starts a command.
Binding reserved ports needs root, or net.ipv4.ip_unprivileged_port_start
set to 512 or lower.
"""

import errno
import getpass
import os
import socket
import sys

RSH_PORT = 514


def die(prog, msg):
    sys.stderr.write(f"{prog}: {msg}\n")
    sys.exit(1)


def local_user():
    return os.environ.get("SUDO_USER") or getpass.getuser()


def reserved_ports():
    # rshd only accepts connections from ports 512-1023
    return range(1023, 511, -1)


def _bind_reserved(prog, sock, port):
    try:
        sock.bind(("", port))
        return True
    except OSError as e:
        if e.errno == errno.EADDRINUSE:
            return False
        if e.errno == errno.EACCES:
            die(prog, "cannot bind a reserved port: run as root, or set "
                      "net.ipv4.ip_unprivileged_port_start=512")
        raise


def _connect_reserved(prog, addr):
    for port in reserved_ports():
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        if not _bind_reserved(prog, sock, port):
            sock.close()
            continue
        try:
            sock.connect((addr, RSH_PORT))
            return sock
        except OSError as e:
            sock.close()
            # a recent connection from this port may still be in TIME_WAIT
            if e.errno in (errno.EADDRINUSE, errno.EADDRNOTAVAIL):
                continue
            die(prog, f"{addr}: {e.strerror}")
    die(prog, "no free reserved port")


def _listen_reserved(prog):
    for port in reserved_ports():
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        if _bind_reserved(prog, sock, port):
            sock.listen(1)
            return sock, port
        sock.close()
    die(prog, "no free reserved port")


def rcmd(prog, host, remuser, command, want_stderr=True):
    """Run command on host as remuser.

    Returns (sock, err_sock).  sock carries the command's stdin and stdout.
    If want_stderr is false, err_sock is None and the command's stderr
    arrives on sock as well.
    """
    try:
        addr = socket.gethostbyname(host)
    except OSError as e:
        die(prog, f"{host}: {e}")

    sock = _connect_reserved(prog, addr)

    err_sock = None
    if want_stderr:
        # Ask the server to connect back to us for the command's stderr.
        listener, err_port = _listen_reserved(prog)
        sock.sendall(f"{err_port}\0".encode())
        listener.settimeout(30)
        try:
            err_sock, (peer_addr, peer_port) = listener.accept()
        except socket.timeout:
            die(prog, "server did not open the stderr connection")
        finally:
            listener.close()
        if peer_addr != addr or peer_port >= 1024:
            die(prog, f"unexpected stderr connection from {peer_addr}:{peer_port}")
    else:
        sock.sendall(b"0\0")

    sock.sendall(f"{local_user()}\0{remuser}\0{command}\0".encode())

    status = sock.recv(1)
    if status != b"\0":
        # the server sends \1 followed by an error message line
        msg = b""
        while not msg.endswith(b"\n"):
            chunk = sock.recv(1024)
            if not chunk:
                break
            msg += chunk
        sys.stderr.write(msg.decode(errors="replace"))
        sys.exit(1)

    return sock, err_sock
