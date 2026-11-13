#!/usr/bin/env python3
"""Check the Group Board's German texts (EldoUI_GroupBoard/Locale/deDE.lua).

  python3 tools/groupboard/check_locale.py

* every text the plugin shows has a German translation;
* placeholders (%s, %d, ...) and text codes match the English key;
* a key EldoUI's German pack (EldoUI_Locale_deDE) already has keeps the
  pack's translation: the plugin's table is merged into the same language,
  so a different text would change EldoUI's own windows too;
* the table has no key the plugin doesn't use.
Needs lua5.1 (it reads the Lua tables as the game loads them).
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PLUGIN = os.path.join(ROOT, "EldoUI_GroupBoard")
PACK = os.path.join(ROOT, "EldoUI_Locale_deDE")
DUMP = os.path.join(ROOT, "tools", "locale", "dump.lua")

READ_PLUGIN = r"""
local captured
EldoUI = { RegisterLocale = function(_, code, strings)
  if code == "deDE" then captured = type(strings) == "function" and strings() or strings end
end }
dofile(arg[1])
local function esc(s)
  return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\t', '\\t')
    :gsub('[%z\1-\31]', function(c) return string.format('\\u%04x', c:byte()) end) .. '"'
end
local out = {}
for key, value in pairs(captured or {}) do
  if type(value) == "table" then
    out[#out + 1] = esc(key) .. ':{"one":' .. esc(value.one or "") .. ',"other":' .. esc(value.other or "") .. '}'
  else
    out[#out + 1] = esc(key) .. ':' .. esc(value)
  end
end
io.write("{" .. table.concat(out, ",") .. "}")
"""

STRING = r'"((?:[^"\\]|\\.)*)"'


def unescape(text):
    return text.replace('\\"', '"').replace("\\\\", "\\")


def plugin_keys():
    keys = {}
    for name in sorted(os.listdir(PLUGIN)):
        if not name.endswith(".lua"):
            continue
        path = os.path.join(PLUGIN, name)
        source = open(path, encoding="utf-8").read()
        found = []
        found += re.findall(r'L\[' + STRING + r'\]', source)
        found += re.findall(r'Key\(' + STRING + r'\)', source)
        found += re.findall(r'\b(?:label|desc|title) = ' + STRING, source)
        found += re.findall(r'AddCommand\("[^"]+", ' + STRING, source)
        for one, other in re.findall(r'Plural\([^,]+, ' + STRING + r', ' + STRING + r'\)', source):
            keys.setdefault(unescape(other), name)
        for key in found:
            keys.setdefault(unescape(key), name)
    return keys


def german_plugin():
    path = os.path.join(PLUGIN, "Locale", "deDE.lua")
    script = os.path.join(os.environ.get("TMPDIR", "/tmp"), "groupboard_read_locale.lua")
    with open(script, "w", encoding="utf-8") as handle:
        handle.write(READ_PLUGIN)
    out = subprocess.run(["lua5.1", script, path], check=True, capture_output=True, text=True).stdout
    return json.loads(out)


def german_pack():
    paths = [os.path.join(PACK, f) for f in ("Core.lua", "ModulesAL.lua", "ModulesMZ.lua", "LootGuide.lua")]
    out = subprocess.run(["lua5.1", DUMP, *paths], check=True, capture_output=True, text=True).stdout
    merged = {}
    for data in json.loads(out).values():
        merged.update(data.get("deDE", {}))
    return merged


CODE = re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?[sdif%]|\|c[0-9a-fA-F]{8}|\|r|\|T.*?\|t|\|n|\{[a-z]+\}")


def codes(text):
    return [c if not c.startswith("%") else re.sub(r"^%\d+\$", "%", c) for c in CODE.findall(text)]


def main():
    keys = plugin_keys()
    german = german_plugin()
    pack = german_pack()
    problems = []
    for key, where in sorted(keys.items()):
        if key not in german:
            problems.append(f"missing ({where}): {key!r}")
    for key, value in sorted(german.items()):
        if key not in keys:
            problems.append(f"not used by the plugin: {key!r}")
        forms = value.values() if isinstance(value, dict) else [value]
        for form in forms:
            if not form:
                problems.append(f"empty translation: {key!r}")
            elif isinstance(value, str) and sorted(codes(form)) != sorted(codes(key)):
                problems.append(f"placeholders differ: {key!r} -> {form!r}")
        if key in pack and pack[key] != value:
            problems.append(f"differs from EldoUI_Locale_deDE: {key!r}: pack {pack[key]!r}, plugin {value!r}")
    for problem in problems:
        print(problem)
    print(f"{len(keys)} texts, {len(german)} translations, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
