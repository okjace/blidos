#!/usr/bin/env python3
"""Builds the BlidOS package (the update file) from the source tree. Needs no root.

usage: os/tools/make-deb.py VERSION OUT.deb

The package holds os/rootfs (system files), os/blidos (the interface and blidosd) at
/usr/lib/blidos/blidos, and os/debian (control file and install scripts). Every file is owned
by root, whoever runs this.
"""
import io
import os
import sys
import tarfile
import time

OS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP = {"__pycache__"}


def add_tree(tar, src, dest, seen):
    """Adds src's contents at dest ("./usr/lib/..."), with every parent directory."""
    parts = dest.strip("./").split("/") if dest.strip("./") else []
    for i in range(len(parts) + 1):
        d = "./" + "/".join(parts[:i]) if i else "."
        if d not in seen:
            seen.add(d)
            info = tarfile.TarInfo(d + "/" if d != "." else "./")
            info.type, info.mode, info.mtime = tarfile.DIRTYPE, 0o755, int(time.time())
            tar.addfile(info)
    for root, dirs, files in os.walk(src):
        dirs[:] = sorted(d for d in dirs if d not in SKIP)
        rel = os.path.relpath(root, src)
        base = dest if rel == "." else dest.rstrip("/") + "/" + rel
        for name in dirs + sorted(f for f in files if not f.endswith(".pyc")):
            path = os.path.join(root, name)
            arc = base.rstrip("/") + "/" + name
            if arc in seen:
                continue
            seen.add(arc)
            info = tar.gettarinfo(path, arc)
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            if info.isdir():
                info.mode = 0o755
                tar.addfile(info)
            elif info.issym():
                tar.addfile(info)
            else:
                info.mode = 0o755 if os.stat(path).st_mode & 0o111 else 0o644
                with open(path, "rb") as f:
                    tar.addfile(info, f)


def tar_xz(build):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:xz", format=tarfile.GNU_FORMAT) as tar:
        build(tar)
    return buf.getvalue()


def ar_member(name, data):
    header = f"{name:<16}{int(time.time()):<12}{0:<6}{0:<6}{100644:<8}{len(data):<10}`\n".encode()
    return header + data + (b"\n" if len(data) % 2 else b"")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    version, out = sys.argv[1], sys.argv[2]

    def data(tar):
        seen = {"./etc/blidos-version"}  # written below, so it always matches the package version
        add_tree(tar, os.path.join(OS, "rootfs"), "./", seen)
        add_tree(tar, os.path.join(OS, "blidos"), "./usr/lib/blidos/blidos", seen)
        content = (version + "\n").encode()
        info = tarfile.TarInfo("./etc/blidos-version")
        info.size, info.mode, info.mtime = len(content), 0o644, int(time.time())
        info.uname = info.gname = "root"
        tar.addfile(info, io.BytesIO(content))

    def control(tar):
        for name in sorted(os.listdir(os.path.join(OS, "debian"))):
            with open(os.path.join(OS, "debian", name), "rb") as f:
                content = f.read()
            if name == "control":
                content = content.replace(b"@VERSION@", version.encode())
            info = tarfile.TarInfo("./" + name)
            info.size, info.mtime = len(content), int(time.time())
            info.mode = 0o755 if name in ("preinst", "postinst", "prerm", "postrm") else 0o644
            info.uname = info.gname = "root"
            tar.addfile(info, io.BytesIO(content))

    deb = b"!<arch>\n" + ar_member("debian-binary", b"2.0\n") + \
        ar_member("control.tar.xz", tar_xz(control)) + ar_member("data.tar.xz", tar_xz(data))
    with open(out, "wb") as f:
        f.write(deb)
    print(out)


if __name__ == "__main__":
    main()
