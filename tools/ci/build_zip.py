#!/usr/bin/env python3
"""Build the release ZIP: every addon folder, ready to unzip into Interface/AddOns.

  python3 tools/ci/build_zip.py                    # dist/conUI-<version>.zip
  python3 tools/ci/build_zip.py --tag v0.7.4001-p1 # also check the tag matches the version

The version comes from EldoUI/EldoUI.toc. Only files git tracks go in, so
local leftovers (caches, test output) never ship; tools/, docs/ and review/
stay out because they aren't addon folders. File times are the last
commit's, so the same commit gives the same ZIP.
"""
import argparse
import hashlib
import os
import re
import subprocess
import sys
import time
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DIST = os.path.join(ROOT, "dist")


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout


def toc_version(path):
    with open(path, encoding="utf-8-sig") as fh:
        for line in fh:
            match = re.match(r"##\s*Version\s*:\s*(\S+)", line)
            if match:
                return match[1]
    sys.exit("%s has no '## Version:' line" % os.path.relpath(path, ROOT))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", help="release tag; must be v<version> or <version>")
    args = parser.parse_args()

    version = toc_version(os.path.join(ROOT, "EldoUI", "EldoUI.toc"))
    if args.tag and args.tag not in (version, "v" + version):
        sys.exit("tag %s doesn't match the version in EldoUI/EldoUI.toc (%s): "
                 "use the tag v%s or change the .toc first" % (args.tag, version, version))

    folders = sorted(d for d in os.listdir(ROOT)
                     if d.startswith("EldoUI") and os.path.isfile(os.path.join(ROOT, d, d + ".toc")))
    files = sorted(f for f in git("ls-files", "-z", "--", *folders).split("\0") if f)
    missing = [f for f in files if not os.path.isfile(os.path.join(ROOT, f))]
    if missing:
        sys.exit("tracked but not on disk (delete them with git rm): " + ", ".join(missing[:10]))

    try:
        stamp = time.gmtime(int(git("log", "-1", "--format=%ct").strip()))[:6]
    except (subprocess.CalledProcessError, ValueError):
        stamp = time.gmtime()[:6]
    stamp = max(stamp, (1980, 1, 1, 0, 0, 0))

    os.makedirs(DIST, exist_ok=True)
    target = os.path.join(DIST, "conUI-%s.zip" % version)
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            info = zipfile.ZipInfo(path, date_time=stamp)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            with open(os.path.join(ROOT, path), "rb") as fh:
                archive.writestr(info, fh.read())

    digest = hashlib.sha256()
    with open(target, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            digest.update(block)
    print("%s: %d files in %d folders (%s), %.1f MB"
          % (os.path.relpath(target, ROOT), len(files), len(folders), ", ".join(folders),
             os.path.getsize(target) / 1e6))
    print("SHA-256 %s" % digest.hexdigest())
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as fh:
            fh.write("zip=%s\nversion=%s\nsha256=%s\n" % (os.path.relpath(target, ROOT), version, digest.hexdigest()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
