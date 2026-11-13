#!/usr/bin/env python3
"""The list of WoW API names the addon code reads (tools/ci/globals.lua).

  python3 tools/ci/globals.py            # show names used but not in the list
  python3 tools/ci/globals.py --update   # write the list from the code as it is

.luacheckrc reads tools/ci/globals.lua as its read_globals: luacheck then
flags any other global the code reads, such as a typo in an API name or a
variable that lost its "local". When new code uses a WoW API name on
purpose, update the list and commit it with the change; the diff of the
list shows reviewers which new names came in.
Needs luacheck (apt: lua-check, or luarocks install luacheck).
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LIST = os.path.join(ROOT, "tools", "ci", "globals.lua")
LINE = re.compile(r"^(?P<file>[^:]+):\d+:\d+: \(W113\) accessing undefined variable '(?P<name>[^']+)'$")


def addon_dirs():
    return sorted(d for d in os.listdir(ROOT) if d.startswith("EldoUI") and os.path.isdir(os.path.join(ROOT, d)))


def read_names():
    """Every global the addon code reads that luacheck doesn't know."""
    # Same settings as .luacheckrc, without the list itself.
    globals_written = []
    with open(os.path.join(ROOT, ".luacheckrc"), encoding="utf-8") as fh:
        block = re.search(r"^globals = \{(.*?)^\}", fh.read(), re.S | re.M)
        globals_written = re.findall(r'"([^"]+)"', block.group(1)) if block else []
    cmd = ["luacheck", "--no-config", "--std", "lua51", "--no-max-line-length",
           "--ignore", "2", "3", "4", "5", "6", "--formatter", "plain", "--codes", "--no-color",
           "--globals", *globals_written, "--", *addon_dirs()]
    out = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if out.returncode not in (0, 1):
        sys.exit("luacheck failed:\n" + out.stderr + out.stdout)
    names = {}
    for line in out.stdout.splitlines():
        match = LINE.match(line)
        if match:
            names.setdefault(match["name"], match["file"])
    return names


def listed_names():
    if not os.path.exists(LIST):
        return set()
    with open(LIST, encoding="utf-8") as fh:
        return set(re.findall(r'^\t"([^"]+)",$', fh.read(), re.M))


def write(names):
    lines = [
        "-- WoW API and Blizzard names the addon code reads; .luacheckrc uses it as read_globals.",
        "-- Made by tools/ci/globals.py --update from the code; don't edit by hand.",
        "return {",
    ]
    lines += ['\t"%s",' % name for name in sorted(names)]
    lines.append("}")
    with open(LIST, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")


def main():
    used = read_names()
    if "--update" in sys.argv[1:]:
        before = listed_names()
        write(used)
        added, gone = sorted(set(used) - before), sorted(before - set(used))
        print("tools/ci/globals.lua: %d names (%d new, %d no longer used)" % (len(used), len(added), len(gone)))
        for name in added:
            print("  + %s  (%s)" % (name, used[name]))
        for name in gone:
            print("  - %s" % name)
        return 0
    missing = sorted(set(used) - listed_names())
    for name in missing:
        print("%s  (first in %s)" % (name, used[name]))
    print("%d names used that the list doesn't have" % len(missing))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
