#!/usr/bin/env python3
"""Signs an APK with a v1 (JAR) signature, using openssl. Enough for packages that target
Android 10 (API 29) or older, like BlidOS's Android overlays.

usage: os/tools/sign-apk.py KEY.pem CERT.pem IN.apk OUT.apk

Stored entries (resources.arsc) are 4-byte aligned, like zipalign does.
"""
import base64
import hashlib
import subprocess
import sys
import tempfile
import zipfile


def b64sha(data):
    return base64.b64encode(hashlib.sha256(data).digest()).decode()


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    key, cert, src, out = sys.argv[1:]
    with zipfile.ZipFile(src) as z:
        entries = [(i, z.read(i.filename)) for i in z.infolist() if not i.filename.startswith("META-INF/")]

    manifest = "Manifest-Version: 1.0\r\nCreated-By: BlidOS\r\n\r\n"
    sf_entries = ""
    for info, data in entries:
        section = f"Name: {info.filename}\r\nSHA-256-Digest: {b64sha(data)}\r\n\r\n"
        manifest += section
        sf_entries += f"Name: {info.filename}\r\nSHA-256-Digest: {b64sha(section.encode())}\r\n\r\n"
    sf = ("Signature-Version: 1.0\r\nCreated-By: BlidOS\r\n"
          f"SHA-256-Digest-Manifest: {b64sha(manifest.encode())}\r\n\r\n" + sf_entries)
    with tempfile.NamedTemporaryFile() as f:
        f.write(sf.encode())
        f.flush()
        signature = subprocess.run(["openssl", "smime", "-sign", "-in", f.name, "-signer", cert, "-inkey", key,
                                    "-outform", "DER", "-binary", "-noattr", "-md", "sha256"],
                                   capture_output=True, check=True).stdout

    with zipfile.ZipFile(out, "w") as z:
        for info, data in entries:
            new = zipfile.ZipInfo(info.filename, date_time=(1980, 1, 1, 0, 0, 0))
            new.compress_type = info.compress_type
            if info.compress_type == zipfile.ZIP_STORED:
                # Local header is 30 bytes + name + extra; pad extra so the data starts 4-aligned.
                offset = z.fp.tell() + 30 + len(info.filename.encode())
                new.extra = b"\0" * ((4 - offset % 4) % 4)
            z.writestr(new, data)
        for name, data in (("META-INF/MANIFEST.MF", manifest.encode()), ("META-INF/CERT.SF", sf.encode()),
                           ("META-INF/CERT.RSA", signature)):
            z.writestr(zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0)), data, zipfile.ZIP_DEFLATED)
    print(out)


if __name__ == "__main__":
    main()
