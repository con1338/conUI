#!/usr/bin/env python3
"""Check the .toc files of every addon folder (EldoUI and EldoUI_*).

  python3 tools/ci/check_toc.py

* every file a .toc lists exists, with the exact upper and lower case
  (Windows doesn't care, but a wrong case breaks on case-sensitive disks
  and hides the file from this check);
* no file is listed twice;
* every .lua and .xml file in a folder is loaded by its .toc (directly or
  through an .xml it lists), so a new file can't be forgotten;
* every .toc has an Interface, a Title and a Version line, and all of them
  have the same Interface number.
Exit code 1 when something is wrong.
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# Files the game loads without a .toc line.
AUTO_LOADED = {"Bindings.xml"}
REQUIRED = ("Interface", "Title", "Version")

errors = []


def error(message):
    errors.append(message)


def exact_path(folder, relative):
    """The file's path if it exists with exactly this case; else None, and
    the case-insensitive match (if any) for the message."""
    current = folder
    for part in relative.split("/"):
        try:
            entries = os.listdir(current)
        except OSError:
            return None, None
        if part in entries:
            current = os.path.join(current, part)
            continue
        folded = [entry for entry in entries if entry.lower() == part.lower()]
        return None, (os.path.join(current, folded[0]) if folded else None)
    return (current if os.path.isfile(current) else None), None


def read_toc(path):
    meta, files = {}, []
    with open(path, encoding="utf-8-sig") as fh:
        for number, raw in enumerate(fh, 1):
            line = raw.rstrip("\r\n")
            if line.startswith("##"):
                match = re.match(r"##\s*([^:]+?)\s*:\s*(.*?)\s*$", line)
                if match:
                    meta[match[1]] = match[2]
                continue
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            # "Path\File.lua [AllowLoadTextLocale deDE]": the brackets are load conditions.
            entry = re.sub(r"\s*\[[^\]]*\]\s*$", "", stripped).replace("\\", "/")
            files.append((number, entry))
    return meta, files


def xml_children(path, folder):
    """Files an .xml loads (<Script file=...>, <Include file=...>), relative to the addon folder."""
    try:
        tree = ET.parse(path)
    except ET.ParseError as exc:
        error("%s: XML can't be read: %s" % (os.path.relpath(path, ROOT), exc))
        return []
    base = os.path.relpath(os.path.dirname(path), folder)
    children = []
    for node in tree.iter():
        tag = node.tag.split("}")[-1]
        if tag in ("Script", "Include") and node.get("file"):
            child = os.path.normpath(os.path.join(base, node.get("file").replace("\\", "/"))).replace(os.sep, "/")
            children.append(child)
    return children


def check_addon(folder):
    name = os.path.basename(folder)
    tocs = sorted(f for f in os.listdir(folder) if f.endswith(".toc") and (f == name + ".toc" or f.startswith(name + "_")))
    if not tocs:
        error("%s: no %s.toc" % (name, name))
        return {}
    interfaces = {}
    loaded = set()
    for toc in tocs:
        toc_path = os.path.join(folder, toc)
        shown = os.path.relpath(toc_path, ROOT)
        meta, files = read_toc(toc_path)
        for field in REQUIRED:
            if not meta.get(field):
                error("%s: no '## %s:' line" % (shown, field))
        if meta.get("Interface"):
            interfaces[shown] = meta["Interface"]
        seen = {}
        queue = [(shown, number, entry) for number, entry in files]
        while queue:
            source, number, entry = queue.pop(0)
            key = entry.lower()
            if key in seen:
                error("%s:%s: %s is already loaded (%s)" % (source, number, entry, seen[key]))
                continue
            seen[key] = "%s:%s" % (source, number)
            path, wrong_case = exact_path(folder, entry)
            if not path:
                if wrong_case:
                    error("%s:%s: %s has a different case on disk: %s"
                          % (source, number, entry, os.path.relpath(wrong_case, folder).replace(os.sep, "/")))
                else:
                    error("%s:%s: %s doesn't exist" % (source, number, entry))
                continue
            loaded.add(os.path.relpath(path, folder).replace(os.sep, "/"))
            if entry.lower().endswith(".xml"):
                xml_shown = os.path.relpath(path, ROOT)
                queue.extend((xml_shown, "-", child) for child in xml_children(path, folder))
    for directory, subdirs, names in os.walk(folder):
        subdirs[:] = sorted(d for d in subdirs if not d.startswith("."))
        for file_name in sorted(names):
            if not file_name.endswith((".lua", ".xml")):
                continue
            relative = os.path.relpath(os.path.join(directory, file_name), folder).replace(os.sep, "/")
            if relative in AUTO_LOADED or relative in loaded:
                continue
            error("%s/%s: not loaded by any .toc line" % (name, relative))
    return interfaces


def main():
    folders = sorted(os.path.join(ROOT, d) for d in os.listdir(ROOT)
                     if d.startswith("EldoUI") and os.path.isdir(os.path.join(ROOT, d)))
    interfaces = {}
    for folder in folders:
        interfaces.update(check_addon(folder))
    values = sorted(set(interfaces.values()))
    if len(values) > 1:
        for toc, value in sorted(interfaces.items()):
            error("%s: Interface %s" % (toc, value))
        error("the .toc files have different Interface numbers: %s" % ", ".join(values))
    for message in errors:
        print(message)
    if errors:
        print("%d problem(s) in the .toc files" % len(errors))
        return 1
    print("%d addon folders, %d .toc files, Interface %s: all files found"
          % (len(folders), len(interfaces), values[0] if values else "?"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
