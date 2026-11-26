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
	# Every test runs; the ones that fail are named at the end.
	local bad=() name
	name="Group board: parser"; step "$name"
	lua5.1 tools/groupboard/test_parse.lua | tail -n 1
	[ "${PIPESTATUS[0]}" -eq 0 ] || bad+=("$name")
	name="Group board: plugin"; step "$name"
	lua5.1 tools/groupboard/test_board.lua | tail -n 1
	[ "${PIPESTATUS[0]}" -eq 0 ] || bad+=("$name")
	name="Share strings from other versions"; step "$name"
	lua5.1 tools/share/test_import_versions.lua || bad+=("$name")
	name="Unpacked size before unpacking"; step "$name"
	lua5.1 tools/share/test_inflate.lua || bad+=("$name")
	name="Profiles page: New profile, Rename and the picks reach the page"; step "$name"
	lua5.1 tools/config/test_profile_page.lua || bad+=("$name")
	name="Hidden Blizzard action bars: the game's own update in combat"; step "$name"
	lua5.1 tools/actionbars/test_hidden_blizzard_bars.lua || bad+=("$name")
	name="Click-cast keys on hover after a roster change"; step "$name"
	lua5.1 tools/clickcast/test_hover_unit.lua || bad+=("$name")
	name="Click-cast bindings for compact frames made in combat"; step "$name"
	lua5.1 tools/clickcast/test_compact_combat.lua || bad+=("$name")
	name="Nameplate driver hook after Blizzard_NamePlates loads"; step "$name"
	lua5.1 tools/nameplates/test_driver_hook.lua || bad+=("$name")
	name="Info Bar blocks for other addons (LibDataBroker)"; step "$name"
	lua5.1 tools/infobar/test_broker.lua || bad+=("$name")
	name="Info Bar memory block: rare readings, fresh on hover"; step "$name"
	lua5.1 tools/infobar/test_memory_poll.lua || bad+=("$name")
	name="Info Bar guild tooltip: no guild message in combat"; step "$name"
	lua5.1 tools/infobar/test_guild_motd.lua || bad+=("$name")
	name="Masque on the Consumable Bar, totem bars and Quickdraw"; step "$name"
	lua5.1 tools/masque/test_masque.lua || bad+=("$name")
	name="DKP and EPGP standings from the guild notes"; step "$name"
	lua5.1 tools/raidloot/test_points.lua || bad+=("$name")
	name="Timing per module (/eui perf)"; step "$name"
	lua5.1 tools/perf/test_perf.lua || bad+=("$name")
	name="Combat Text: the Punchy style and the leaner updater"; step "$name"
	lua5.1 tools/combattext/test_punchy.lua || bad+=("$name")
	name="Cast bars on the party and raid frames"; step "$name"
	lua5.1 tools/groupframes/test_cast.lua || bad+=("$name")
	name="World buffs"; step "$name"
	lua5.1 tools/worldbuffs/test_world_buffs.lua || bad+=("$name")
	name="Fishing: soft interact reaches the bobber, only the splash, catches from LOOT_READY"; step "$name"
	lua5.1 tools/fishing/test_fishing.lua || bad+=("$name")
	name="RestedXP on a client in another language: target names, guide chain, group names"; step "$name"
	lua5.1 tools/integrations/test_rxp_locale.lua || bad+=("$name")
	name="RestedXP's step list on a click: the minimap button and the key"; step "$name"
	lua5.1 tools/integrations/test_rxp_steplist.lua || bad+=("$name")
	name="RestedXP: sizes to fit EldoUI, the arrow and windows on layout spots"; step "$name"
	lua5.1 tools/integrations/test_rxp_parts.lua || bad+=("$name")
	name="Quality of Life: Wowhead links in the game's language"; step "$name"
	lua5.1 tools/qol/test_wowhead.lua || bad+=("$name")
	name="Quality of Life: XP after each title in the quest log"; step "$name"
	lua5.1 tools/qol/test_quest_xp.lua || bad+=("$name")
	name="Quality of Life: a signal when eating and drinking are done"; step "$name"
	lua5.1 tools/qol/test_meal_done.lua || bad+=("$name")
	name="Quality of Life: a hint when the bags are almost full"; step "$name"
	lua5.1 tools/qol/test_bag_space.lua || bad+=("$name")
	name="Character: a gear set clicked in combat goes on after combat"; step "$name"
	lua5.1 tools/character/test_gear_after_combat.lua || bad+=("$name")
	name="Quest Item Bar: the quest items you can use, out of combat only"; step "$name"
	lua5.1 tools/questbar/test_quest_bar.lua || bad+=("$name")
	name="Consumable Bar: buttons work with Shift, Ctrl or Alt held"; step "$name"
	lua5.1 tools/consumablebar/test_modifier_clicks.lua || bad+=("$name")
	name="Bar Snapshots: which action bars are on"; step "$name"
	lua5.1 tools/snapshots/test_bar_toggles.lua | tail -n 1
	[ "${PIPESTATUS[0]}" -eq 0 ] || bad+=("$name")
	name="Loot Sim: Judgement rolls as a ranged attack"; step "$name"
	lua5.1 tools/lootsim/test_judgement.lua || bad+=("$name")
	name="Auction House: Blizzard's screens come back under EldoUI's pages (F22)"; step "$name"
	lua5.1 tools/auction/test_native_screens.lua || bad+=("$name")
	name="Bags: EldoUI's bag window never runs the game's bag code (F24)"; step "$name"
	lua5.1 tools/bags/test_game_bag_code.lua || bad+=("$name")
	name="Tooltip: the mover in Combat mode, the tooltip grows away from the edge"; step "$name"
	lua5.1 tools/tooltip/test_tooltip_mover.lua || bad+=("$name")
	name="Mail: the address book's alts with their surname (F27)"; step "$name"
	lua5.1 tools/mail/test_alt_recipient.lua || bad+=("$name")
	name="Guild crafters: lists and whispers with the surname (F28)"; step "$name"
	lua5.1 tools/characters/test_guild_crafter_names.lua || bad+=("$name")
	name="conUI name: prose is renamed, names stay"; step "$name"
	lua5.1 tools/brand/test_brand.lua || bad+=("$name")
	name="German pack: Fork.lua rules"; step "$name"
	python3 tools/locale/test_fork.py || bad+=("$name")
	name="Version watcher (offline)"; step "$name"
	python3 tools/ci/test_watch_versions.py || bad+=("$name")
	if [ "${#bad[@]}" -gt 0 ]; then
		printf '\nFailed tests:\n'
		printf '  %s\n' "${bad[@]}"
		return 1
	fi
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
