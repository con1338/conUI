#!/usr/bin/env bash
# Every offline check of the repository, the same ones GitHub runs on each
# push and pull request (.github/workflows/ci.yml).
#
#   tools/ci/check_all.sh              # all checks
#   tools/ci/check_all.sh toc luacheck # only these
#
# Checks: syntax, toc, luacheck, tests, load, locale. Needs lua5.1, luac5.1,
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
	step "Profiles page: New profile, Rename and the picks reach the page"
	lua5.1 tools/config/test_profile_page.lua || return 1
	step "Hidden Blizzard action bars: the game's own update in combat"
	lua5.1 tools/actionbars/test_hidden_blizzard_bars.lua || return 1
	step "Click-cast keys on hover after a roster change"
	lua5.1 tools/clickcast/test_hover_unit.lua || return 1
	step "Click-cast bindings for compact frames made in combat"
	lua5.1 tools/clickcast/test_compact_combat.lua || return 1
	step "Nameplate driver hook after Blizzard_NamePlates loads"
	lua5.1 tools/nameplates/test_driver_hook.lua || return 1
	step "Info Bar blocks for other addons (LibDataBroker)"
	lua5.1 tools/infobar/test_broker.lua || return 1
	step "Info Bar memory block: rare readings, fresh on hover"
	lua5.1 tools/infobar/test_memory_poll.lua || return 1
	step "Masque on the Consumable Bar, totem bars and Quickdraw"
	lua5.1 tools/masque/test_masque.lua || return 1
	step "DKP and EPGP standings from the guild notes"
	lua5.1 tools/raidloot/test_points.lua || return 1
	step "Timing per module (/eui perf)"
	lua5.1 tools/perf/test_perf.lua || return 1
	step "Combat Text: the Punchy style and the leaner updater"
	lua5.1 tools/combattext/test_punchy.lua || return 1
	step "Cast bars on the party and raid frames"
	lua5.1 tools/groupframes/test_cast.lua || return 1
	step "World buffs"
	lua5.1 tools/worldbuffs/test_world_buffs.lua || return 1
	step "Fishing: soft interact reaches the bobber, catches from LOOT_READY"
	lua5.1 tools/fishing/test_fishing.lua || return 1
	step "RestedXP on a client in another language: target names, guide chain, group names"
	lua5.1 tools/integrations/test_rxp_locale.lua || return 1
	step "Quality of Life: Wowhead links in the game's language"
	lua5.1 tools/qol/test_wowhead.lua || return 1
	step "Quality of Life: XP after each title in the quest log"
	lua5.1 tools/qol/test_quest_xp.lua || return 1
	step "Quality of Life: a signal when eating and drinking are done"
	lua5.1 tools/qol/test_meal_done.lua || return 1
	step "Quality of Life: a hint when the bags are almost full"
	lua5.1 tools/qol/test_bag_space.lua || return 1
	step "Character: a gear set clicked in combat goes on after combat"
	lua5.1 tools/character/test_gear_after_combat.lua || return 1
	step "Quest Item Bar: the quest items you can use, out of combat only"
	lua5.1 tools/questbar/test_quest_bar.lua || return 1
	step "Consumable Bar: buttons work with Shift, Ctrl or Alt held"
	lua5.1 tools/consumablebar/test_modifier_clicks.lua || return 1
	step "German pack: Fork.lua rules"
	python3 tools/locale/test_fork.py || return 1
	step "Version watcher (offline)"
	python3 tools/ci/test_watch_versions.py
}

check_load() {
	local result=0
	step "All of EldoUI loaded offline, first log-in, English client (tools/harness)"
	lua5.1 tools/harness/load_eldoui.lua || result=1
	step "The same with a German client (EldoUI loads the German pack)"
	lua5.1 tools/harness/load_eldoui.lua --locale deDE || result=1
	step "The offline start catches a broken module"
	lua5.1 tools/harness/test_harness.lua || result=1
	return $result
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
[ ${#checks[@]} -eq 0 ] && checks=(syntax toc luacheck tests load locale)
for name in "${checks[@]}"; do
	if ! declare -F "check_$name" >/dev/null; then
		echo "unknown check: $name (syntax, toc, luacheck, tests, load, locale)"
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
