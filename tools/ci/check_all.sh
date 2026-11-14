#!/usr/bin/env bash
# Every offline check of the repository, the same ones GitHub runs on each
# push and pull request (.github/workflows/ci.yml).
#
#   tools/ci/check_all.sh              # all checks
#   tools/ci/check_all.sh toc luacheck # only these
#
# Checks: syntax, toc, luacheck, tests, locale. Needs lua5.1, luac5.1,
# luacheck and python3 (Ubuntu: apt-get install lua5.1 lua-check python3).
# Exit code 1 when a check fails; all chosen checks run either way.
set -u
cd "$(dirname "$0")/../.." || exit 2

ADDONS=(EldoUI EldoUI_*/)
ADDONS=("${ADDONS[@]%/}")
failed=()

step() { printf '\n== %s\n' "$1"; }

check_syntax() {
	step "Lua syntax (luac5.1 -p)"
	local count
	count=$(find "${ADDONS[@]}" tools -name '*.lua' | wc -l)
	find "${ADDONS[@]}" tools -name '*.lua' -print0 | xargs -0 -n 100 luac5.1 -p || return 1
	echo "$count Lua files parse"
	step "Python syntax"
	python3 - <<'EOF' || return 1
import ast, pathlib, sys
files = sorted(pathlib.Path("tools").rglob("*.py"))
bad = 0
for path in files:
    try:
        ast.parse(path.read_text(encoding="utf-8"), str(path))
    except SyntaxError as exc:
        print(exc); bad += 1
print("%d Python files parse" % (len(files) - bad))
sys.exit(1 if bad else 0)
EOF
}

check_toc() {
	step ".toc files"
	python3 tools/ci/check_toc.py
}

check_luacheck() {
	step "luacheck: globals in the addon folders"
	luacheck -q --codes --no-color "${ADDONS[@]}" || return 1
	step "luacheck: group board (stricter)"
	luacheck -q --codes --no-color --config tools/groupboard/luacheckrc.lua \
		EldoUI_GroupBoard tools/groupboard/test_parse.lua tools/groupboard/test_board.lua
}

check_tests() {
	step "Group board: parser"
	lua5.1 tools/groupboard/test_parse.lua | tail -n 1
	[ "${PIPESTATUS[0]}" -eq 0 ] || return 1
	step "Group board: plugin"
	lua5.1 tools/groupboard/test_board.lua | tail -n 1
	[ "${PIPESTATUS[0]}" -eq 0 ] || return 1
	step "Share strings from other versions"
	lua5.1 tools/share/test_import_versions.lua || return 1
	step "Unpacked size before unpacking"
	lua5.1 tools/share/test_inflate.lua || return 1
	step "Click-cast keys on hover after a roster change"
	lua5.1 tools/clickcast/test_hover_unit.lua || return 1
	step "Version watcher (offline)"
	python3 tools/ci/test_watch_versions.py
}

check_locale() {
	local result=0
	step "German pack: placeholders and text codes"
	python3 tools/locale/deDE.py check || result=1
	step "German pack: quoted labels"
	python3 tools/locale/deDE.py xref || result=1
	step "German pack: how much is translated"
	# Not a failure: an upstream update brings new English texts first,
	# and a text without a translation shows in English.
	python3 tools/locale/deDE.py status | tail -n 1
	step "Group board: German texts"
	python3 tools/groupboard/check_locale.py || result=1
	return $result
}

checks=("$@")
[ ${#checks[@]} -eq 0 ] && checks=(syntax toc luacheck tests locale)
for name in "${checks[@]}"; do
	if ! declare -F "check_$name" >/dev/null; then
		echo "unknown check: $name (syntax, toc, luacheck, tests, locale)"
		exit 2
	fi
	"check_$name" || failed+=("$name")
done

echo
if [ ${#failed[@]} -gt 0 ]; then
	echo "FAILED: ${failed[*]}"
	exit 1
fi
echo "All checks passed: ${checks[*]}"
