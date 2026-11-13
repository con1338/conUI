#!/usr/bin/env python3
"""German language pack (EldoUI_Locale_deDE): status, work chunks, import, checks.

The Danish pack (EldoUI_Locale_daDK) is the key list: every key it has, in
the same four files (Core, ModulesAL, ModulesMZ, LootGuide). The German pack's
Lua files are the source of truth for the translations; this tool reads them
back through tools/locale/dump.lua (Lua 5.1), so it sees exactly what the game
loads.

  python3 tools/locale/deDE.py status
  python3 tools/locale/deDE.py export --section Core --size 350 --out DIR
  python3 tools/locale/deDE.py validate FILE.out.json [...]   # check answers, write nothing
  python3 tools/locale/deDE.py import FILE.out.json [...]
  python3 tools/locale/deDE.py seed-lootguide   # take the Loot Guide's deDE table
  python3 tools/locale/deDE.py check            # placeholders of every translation
  python3 tools/locale/deDE.py xref             # quoted labels match their translation
  python3 tools/locale/deDE.py apply FIXES.json # {English key: German text}, checked
  python3 tools/locale/deDE.py build            # rewrite the Lua files as they are

A chunk (export) is a JSON list of {"id", "key", "plural", "where"}. Its answer
(import) is a JSON list of {"id", "de"}: "de" is a string, or {"one", "other"}
for a plural key. The ids belong to the chunk file the answer is named after:
Core-03.json -> Core-03.out.json.
"""
import argparse
import collections
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DUMP = os.path.join(ROOT, "tools", "locale", "dump.lua")
DA = os.path.join(ROOT, "EldoUI_Locale_daDK")
DE = os.path.join(ROOT, "EldoUI_Locale_deDE")
LOOTGUIDE_DE = os.path.join(ROOT, "EldoUI", "Modules", "LootGuide", "Locale", "deDE.lua")
SECTIONS = ["Core", "ModulesAL", "ModulesMZ", "LootGuide"]

HEADERS = {
    "Core": "the core: options window, installer, layouts, move mode, profiles, saved data and chat messages",
    "ModulesAL": "the modules A to L: action bars, bags, chat, combat text, Fanfare, frames, info bar, instances and the rest",
    "ModulesMZ": "the modules M to Z: maps, nameplates, quests, raid tools, tooltips, unit frames and the rest",
    "LootGuide": "the Loot Guide, My Adventure and the Journal",
}


# --------------------------------------------------------------------------
# Reading and writing the Lua tables
# --------------------------------------------------------------------------
def dump(paths):
    paths = [p for p in paths if os.path.exists(p)]
    if not paths:
        return {}
    out = subprocess.run(["lua5.1", DUMP, *paths], check=True, capture_output=True, text=True).stdout
    return json.loads(out)


def section_path(base, section):
    return os.path.join(base, section + ".lua")


def danish_sections():
    data = dump([section_path(DA, s) for s in SECTIONS])
    return {s: data[section_path(DA, s)]["daDK"] for s in SECTIONS}


def german_sections():
    data = dump([section_path(DE, s) for s in SECTIONS])
    return {s: data.get(section_path(DE, s), {}).get("deDE", {}) for s in SECTIONS}


def lua_string(text):
    out = []
    for ch in text:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif ord(ch) < 32 or ord(ch) == 127:
            out.append("\\%03d" % ord(ch))
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def lua_value(value):
    if isinstance(value, dict):
        return "{ one = %s, other = %s }" % (lua_string(value["one"]), lua_string(value["other"]))
    return lua_string(value)


def write_section(section, entries, complete=False):
    os.makedirs(DE, exist_ok=True)
    lines = [
        "-- EldoUI's texts in German (deDE): %s." % HEADERS[section],
        "-- English is the key; a text missing here shows in English. The player is",
        "-- addressed with \"Ihr/Euch\" and game terms are the ones the deDE client",
        "-- uses, as in the Loot Guide's German table. Keep every %s, %d, {token} and",
        "-- |c...|r code exactly as it is. Built with tools/locale/deDE.py.",
        "-- This folder loads only when Deutsch is picked under General > EldoUI language",
        "-- (or on a German client), and the table is built then. It is its own addon,",
        "-- so EldoUI comes from its global.",
        "local E = EldoUI",
        "if not E then return end",
    ]
    if section == "Core" and complete:
        lines += [
            "-- German is complete: General > EldoUI language offers it.",
            "E.completeLanguages = E.completeLanguages or {}",
            "E.completeLanguages.deDE = true",
        ]
    lines.append('E:RegisterLocale("deDE", function() return {')
    for key in sorted(entries, key=lambda k: k.encode("utf-8")):
        lines.append("\t[%s] = %s," % (lua_string(key), lua_value(entries[key])))
    lines.append("} end)")
    with open(section_path(DE, section), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")


# --------------------------------------------------------------------------
# Placeholder check
# --------------------------------------------------------------------------
# No space flag: "20 % slower" is text, and no format string here uses it.
FMT = re.compile(r"%(?:\d+\$)?[-+#0]*\d*(?:\.\d+)?[cdiouxXeEfgGqs]|%%")
TOKEN = re.compile(r"\{[A-Za-z_]\w*\}")
ESCAPE = re.compile(r"\|c[0-9a-fA-F]{8}|\|r|\|T[^|]*\|t|\|A[^|]*\|a|\|H[^|]*\|h|\|h|\|n|\|\|")


def strip_positions(spec):
    return re.sub(r"^%\d+\$", "%", spec)


def problems(key, text):
    """Why `text` can't stand in for `key` (empty list: fine)."""
    found = []
    want, got = FMT.findall(key), FMT.findall(text)
    positional = any("$" in g for g in got)
    if positional:
        if sorted(want) != sorted(strip_positions(g) for g in got):
            found.append("format %s -> %s" % (want, got))
    elif want != got:
        found.append("format %s -> %s" % (want, got))
    if collections.Counter(TOKEN.findall(key)) != collections.Counter(TOKEN.findall(text)):
        found.append("tokens %s -> %s" % (TOKEN.findall(key), TOKEN.findall(text)))
    if collections.Counter(ESCAPE.findall(key)) != collections.Counter(ESCAPE.findall(text)):
        found.append("codes %s -> %s" % (ESCAPE.findall(key), ESCAPE.findall(text)))
    if key.count("\n") != text.count("\n"):
        found.append("line breaks %d -> %d" % (key.count("\n"), text.count("\n")))
    if text.strip() == "":
        found.append("empty")
    return found


def entry_problems(key, value):
    if isinstance(value, dict):
        if set(value) != {"one", "other"} or not all(isinstance(v, str) for v in value.values()):
            return ["plural needs one and other"]
        found = ["other: " + p for p in problems(key, value["other"])]
        # The one form may spell the number out ("Ein Gegenstand"), so only
        # its codes and tokens must match.
        found += ["one: " + p for p in problems(key, value["one"]) if not p.startswith("format")]
        return found
    if not isinstance(value, str):
        return ["not a string"]
    return problems(key, value)


# --------------------------------------------------------------------------
# Where a key is used (context for translators)
# --------------------------------------------------------------------------
LUA_STRING = re.compile(r'"((?:\\.|[^"\\\n])*)"')
LUA_ESC = re.compile(r"\\(\d{1,3}|.)", re.S)


def lua_unescape(body):
    def repl(m):
        e = m.group(1)
        if e.isdigit():
            return chr(int(e))
        return {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v"}.get(e, e)
    return LUA_ESC.sub(repl, body)


def usage_index():
    index = collections.defaultdict(list)
    base = os.path.join(ROOT, "EldoUI")
    for folder, _, files in os.walk(base):
        if "Libs" in folder.split(os.sep) or os.sep + "Locale" in folder:
            continue
        for name in files:
            if not name.endswith(".lua"):
                continue
            path = os.path.join(folder, name)
            rel = os.path.relpath(path, base)
            with open(path, encoding="utf-8", errors="replace") as fh:
                for literal in LUA_STRING.findall(fh.read()):
                    text = lua_unescape(literal)
                    if rel not in index[text]:
                        index[text].append(rel)
    return index


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------
def cmd_status(_):
    da, de = danish_sections(), german_sections()
    total = done = 0
    for s in SECTIONS:
        have = sum(1 for k in da[s] if k in de[s])
        total += len(da[s])
        done += have
        print("%-10s %5d / %5d  (%3d %%)" % (s, have, len(da[s]), 100 * have // max(1, len(da[s]))))
    print("%-10s %5d / %5d  (%3d %%)" % ("total", done, total, 100 * done // max(1, total)))


def cmd_export(args):
    da, de = danish_sections(), german_sections()
    keys = sorted((k for k in da[args.section] if k not in de[args.section]), key=lambda k: k.encode("utf-8"))
    index = usage_index()
    os.makedirs(args.out, exist_ok=True)
    count = 0
    for start in range(0, len(keys), args.size):
        count += 1
        chunk = []
        for offset, key in enumerate(keys[start:start + args.size]):
            chunk.append({
                "id": offset + 1,
                "key": key,
                "plural": isinstance(da[args.section][key], dict),
                "where": index.get(key, [])[:3],
            })
        path = os.path.join(args.out, "%s-%02d.json" % (args.section, count))
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(chunk, fh, ensure_ascii=False, indent=1)
    print("%d keys in %d chunks -> %s" % (len(keys), count, args.out))


def read_answers(files):
    """(key, value) pairs that pass the check; prints every problem. Returns
    (accepted, problem count, unanswered count)."""
    accepted, bad, unanswered = [], 0, 0
    for answer in files:
        source = re.sub(r"\.out\.json$", ".json", answer)
        name = os.path.basename(answer)
        try:
            chunk = {item["id"]: item for item in json.load(open(source, encoding="utf-8"))}
            items = json.load(open(answer, encoding="utf-8"))
        except (OSError, ValueError) as err:
            print("%s: can't read (%s)" % (name, err))
            bad += 1
            continue
        seen = set()
        for item in items:
            entry = chunk.get(item.get("id")) if isinstance(item, dict) else None
            if not entry:
                print("%s: unknown id %r" % (name, item.get("id") if isinstance(item, dict) else item))
                bad += 1
                continue
            seen.add(entry["id"])
            key, value = entry["key"], item.get("de")
            if entry["plural"] and isinstance(value, str):
                value = {"one": value, "other": value}
            if not entry["plural"] and isinstance(value, dict):
                print("%s #%d %r: not a plural key, give one text" % (name, entry["id"], key[:60]))
                bad += 1
                continue
            found = entry_problems(key, value)
            if found:
                print("%s #%d %r: %s" % (name, entry["id"], key[:60], "; ".join(found)))
                bad += 1
                continue
            accepted.append((key, value))
        missing = sorted(set(chunk) - seen)
        if missing:
            print("%s: %d ids without an answer: %s" % (name, len(missing), missing[:20]))
            unanswered += len(missing)
    return accepted, bad, unanswered


def cmd_validate(args):
    accepted, bad, unanswered = read_answers(args.files)
    print("ok %d, problems %d, unanswered %d" % (len(accepted), bad, unanswered))
    return 1 if bad or unanswered else 0


def cmd_import(args):
    da, de = danish_sections(), german_sections()
    section_of = {k: s for s in SECTIONS for k in da[s]}
    accepted, bad, unanswered = read_answers(args.files)
    for key, value in accepted:
        de[section_of[key]][key] = value
    for s in SECTIONS:
        write_section(s, de[s])
    print("imported %d, rejected %d, unanswered %d" % (len(accepted), bad, unanswered))


def cmd_seed_lootguide(_):
    da, de = danish_sections(), german_sections()
    section_of = {k: s for s in SECTIONS for k in da[s]}
    table = dump([LOOTGUIDE_DE])[LOOTGUIDE_DE]["deDE"]
    added = 0
    for key, value in table.items():
        if key in section_of and key not in de[section_of[key]]:
            de[section_of[key]][key] = value
            added += 1
    for s in SECTIONS:
        write_section(s, de[s])
    print("seeded %d of %d Loot Guide texts" % (added, len(table)))


def cmd_check(_):
    da, de = danish_sections(), german_sections()
    bad = 0
    for s in SECTIONS:
        for key, value in de[s].items():
            if key not in da[s]:
                print("%s: key not in the Danish list: %r" % (s, key[:70]))
                bad += 1
            found = entry_problems(key, value)
            if found:
                print("%s %r: %s" % (s, key[:70], "; ".join(found)))
                bad += 1
    print("%d problems" % bad)
    return 1 if bad else 0


QUOTED = re.compile(r'"([^"%{}|]{3,80})"')
# Quoted names that stay English on purpose: the code uses them as they are
# (Professions Planner's shopping list, M.LIST_NAME, is saved under this name).
XREF_KEEP = {"Profession Planner"}


def plain(value):
    return value["other"] if isinstance(value, dict) else value


def cmd_xref(_):
    """A text that quotes another one ("Turn on \"Show the clock\" first.")
    must quote that text's German translation."""
    de = german_sections()
    german = {}
    for s in SECTIONS:
        german.update(de[s])
    bad = 0
    for s in SECTIONS:
        for key, value in sorted(de[s].items()):
            for label in QUOTED.findall(key):
                if label in XREF_KEEP:
                    continue
                target = german.get(label)
                if not isinstance(target, str) or target == label:
                    continue
                if target not in plain(value):
                    print("%s: %r\n    quotes %r = %r\n    but says %r" % (s, key[:90], label, target, plain(value)[:140]))
                    bad += 1
    print("%d texts quote a label differently" % bad)
    return 1 if bad else 0


def cmd_apply(args):
    """Set translations from a JSON object {English key: German text}."""
    da, de = danish_sections(), german_sections()
    section_of = {k: s for s in SECTIONS for k in da[s]}
    fixes = json.load(open(args.file, encoding="utf-8"))
    applied = bad = 0
    for key, value in fixes.items():
        if key not in section_of:
            print("unknown key %r" % key[:80])
            bad += 1
            continue
        if isinstance(da[section_of[key]][key], dict) and isinstance(value, str):
            value = {"one": value, "other": value}
        found = entry_problems(key, value)
        if found:
            print("%r: %s" % (key[:80], "; ".join(found)))
            bad += 1
            continue
        de[section_of[key]][key] = value
        applied += 1
    for s in SECTIONS:
        write_section(s, de[s])
    print("applied %d, rejected %d" % (applied, bad))
    return 1 if bad else 0


def cmd_build(_):
    de = german_sections()
    for s in SECTIONS:
        write_section(s, de[s])
    print("rewrote %d files" % len(SECTIONS))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    export = sub.add_parser("export")
    export.add_argument("--section", choices=SECTIONS, required=True)
    export.add_argument("--size", type=int, default=350)
    export.add_argument("--out", required=True)
    imp = sub.add_parser("import")
    imp.add_argument("files", nargs="+")
    val = sub.add_parser("validate")
    val.add_argument("files", nargs="+")
    sub.add_parser("seed-lootguide")
    sub.add_parser("check")
    sub.add_parser("xref")
    app = sub.add_parser("apply")
    app.add_argument("file")
    sub.add_parser("build")
    args = parser.parse_args()
    handler = {"status": cmd_status, "export": cmd_export, "import": cmd_import, "validate": cmd_validate,
               "seed-lootguide": cmd_seed_lootguide, "check": cmd_check, "build": cmd_build,
               "xref": cmd_xref, "apply": cmd_apply}[args.command]
    sys.exit(handler(args) or 0)


if __name__ == "__main__":
    main()
