#!/usr/bin/env python3
"""Offline test for the German pack's Fork.lua rules in deDE.py (review A2).

  python3 tools/locale/test_fork.py

Builds a tiny repository in a temporary folder (a code file, a Danish pack,
a German pack with Fork.lua) and runs deDE.py's own check and apply on it,
with the real tools/locale/dump.lua (needs lua5.1, as deDE.py does).
Checked: a text the code uses but neither list has, a Fork.lua key the code
doesn't use and one that is a Danish key all fail the check; apply puts a
new text into Fork.lua, after which the check passes; Lua escapes are read
as bytes, so a UTF-8 dash written as escapes matches its key.
"""
import contextlib
import importlib.util
import io
import json
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("deDE", os.path.join(HERE, "deDE.py"))
deDE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deDE)

passed = failed = 0


def check(ok, what):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
        print("FAIL: " + what)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def pack(code, entries):
    rows = "".join("\t[%s] = %s,\n" % (deDE.lua_string(k), deDE.lua_string(v)) for k, v in entries.items())
    return "local E = EldoUI\nE:RegisterLocale(%s, function() return {\n%s} end)\n" % (deDE.lua_string(code), rows)


def run(command, *args):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        result = command(*args)
    return result or 0, out.getvalue()


# Lua escapes are bytes.
check(deDE.lua_unescape("A \\226\\128\\147 B") == "A – B", "a UTF-8 dash written as escapes")
check(deDE.lua_unescape('say \\"hi\\"\\n') == 'say "hi"\n', "quote and line break escapes")

with tempfile.TemporaryDirectory() as root:
    deDE.ROOT = root
    deDE.DA = os.path.join(root, "EldoUI_Locale_daDK")
    deDE.DE = os.path.join(root, "EldoUI_Locale_deDE")
    write(os.path.join(root, "EldoUI", "Core", "Text.lua"), "\n".join([
        'local L = E.L',
        'print(L["Known text"])',
        'print(self.L["Fork text"])',
        'print(L["New text"])',
        'print(L["A \\226\\128\\147 dash"])',
        'local option = { label = "Option label" }',
        'print(L["..."], L["12"])',  # no letters: not a text
    ]))
    # A Danish text in a library or a language table doesn't count as code.
    write(os.path.join(root, "EldoUI", "Libs", "Lib.lua"), 'print(L["Library text"])\n')
    danish = {"Known text": "Kendt tekst", "A – dash": "En streg"}
    german = {"Known text": "Bekannter Text", "A – dash": "Ein Strich"}
    for section in deDE.SECTIONS:
        write(os.path.join(deDE.DA, section + ".lua"), pack("daDK", danish if section == "Core" else {}))
        write(os.path.join(deDE.DE, section + ".lua"), pack("deDE", german if section == "Core" else {}))
    fork_path = os.path.join(deDE.DE, "Fork.lua")
    write(fork_path, pack("deDE", {
        "Fork text": "Fork-Text",
        "Option label": "Optionsbeschriftung",
        "Gone text": "Weg",              # not in the code
        "Known text": "Doppelt",         # a Danish key
    }))

    result, out = run(deDE.cmd_check, None)
    check(result == 1, "check fails")
    check("no German text: 'New text'" in out, "a code text in neither list is named")
    check("Gone text" in out and "not a string in EldoUI's code" in out, "a Fork.lua key the code doesn't use is named")
    check("a Danish key, it belongs in its section: 'Known text'" in out, "a Danish key in Fork.lua is named")
    check("Library text" not in out, "libraries are not code")
    check("'...'" not in out and "'12'" not in out, "keys without letters are not texts")
    check("Option label" not in out and "Fork text" not in out, "good Fork.lua keys pass")
    check("dash" not in out, "the escaped dash matches its key")
    check(out.strip().endswith("3 problems"), "exactly three problems (got: %s)" % out.strip().splitlines()[-1:])

    # Repair: apply the missing text (it goes to Fork.lua), drop the bad ones.
    write(fork_path, pack("deDE", {"Fork text": "Fork-Text", "Option label": "Optionsbeschriftung"}))
    fixes = os.path.join(root, "fixes.json")
    write(fixes, json.dumps({"New text": "Neuer Text", "Not anywhere": "Nirgends"}))
    result, out = run(deDE.cmd_apply, type("Args", (), {"file": fixes}))
    check(result == 1 and "unknown key (neither Danish nor a string of the code) 'Not anywhere'" in out,
          "apply rejects a key that is neither Danish nor in the code")
    check(deDE.fork_texts().get("New text") == "Neuer Text", "apply puts a new text into Fork.lua")
    check(deDE.german_sections()["Core"].get("New text") is None, "and not into a Danish section")
    result, out = run(deDE.cmd_check, None)
    check(result == 0 and out.strip().endswith("0 problems"), "check passes after the repair (got: %s)" % out.strip()[-200:])
    result, out = run(deDE.cmd_status, None)
    check(re.search(r"^Fork\s+3 texts not in the Danish list", out, re.M) is not None, "status counts Fork.lua")
    check(out.strip().splitlines()[-1].startswith("total"), "status still ends with the total (the CI reads that line)")

print("%d checks passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
