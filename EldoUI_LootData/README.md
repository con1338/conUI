# EldoUI_LootData

Loot tables, drop chances, creatures, spawn camps, instances and quests for
EldoUI's Loot Guide, as a separate load-on-demand addon folder.

**Licence: GPL-3.0-or-later** (see `LICENSE`). This folder is derived from
[CMaNGOS classic-db](https://github.com/cmangos/classic-db) (GPL-3.0). The
rest of EldoUI is Apache-2.0 and does not include this data; a release zip
that ships both folders side by side is an aggregate (GPLv3 section 5).

- Source: cmangos/classic-db, commit `ec4f596146be6467ea93c57397858e329e2db852` (2026-09-22)
- Generator: `tools/lootdata/gen_lootdata.py` 1.7.0 in the EldoUI repository
  (Apache-2.0, our own code; this is the corresponding source). Regenerate with
  `python3 -I tools/lootdata/gen_lootdata.py --db <classic-db checkout> --out EldoUI_LootData`.
- Values are Classic-era emulator values. **WoW: Forever may differ.**
- Blizzard owns World of Warcraft and its names; classic-db's own copyright
  note (`COPYRIGHT.md` in that repository) applies to the game content.

## Contents

| File | What |
|---|---|
| `Core.lua` | the global table, version, commit and counts |
| `Items.lua` | item records (name, quality, slot, levels, class/race limits, stats, weapon damage, set) |
| `Creatures.lua` | creatures (name, levels, rank, instance, model), their own drops, quest objects and chests |
| `Instances.lua` | dungeons and raids: bosses in order with loot, trash drops, quests; wing groups |
| `World.lua` | world drops with level bands, open-world rares and named mobs |
| `Quests.lua` | dungeon quests and item-reward quests with chains, objectives, starters, enders and rewards |
| `Journey.lua` | every other quest a player can pick up: level, side, class, zone, giver, ender and chain |
| `Spawns.lua` | spawn camps in world coordinates (zone resolved in game) |
| `Sources.lua` | per item: where it drops (best chances first), quest rewards, world drop, vendor, craft and token flags |
| `Vendors.lua` | vendors of kept items (reputation and honor gear, recipes) and vendor prices |
| `Recipes.lua` | craft spells (result, reagents, skill, recipe items) and the trainers that teach them |
| `Events.lua` | world events (Classic schedule) with their vendors, quests and mobs; content phases and role notes |
| `Attunements.lua` | attunements and keys: goals, every quest each needs in stage order, class quest chains |
| `Services.lua` | city services: trainers, weapon masters, bankers, auctioneers, flight masters and innkeepers with their spawns (Map Notes) |
| `Routes.lua` | dungeon packs (grouped spawns, patrol paths, bosses) and one suggested route per dungeon |
| `Locale/deDE.lua` | German item, creature, object and quest names and quest objective texts (loaded only on a German client) |
| `Locale/zhCN.lua` | Simplified Chinese item, creature and object names (loaded only on a Simplified Chinese client) |

Quest texts by language: English and German have quest names and objective
texts. The source has no Simplified Chinese quest names or texts, so on a
Simplified Chinese client a quest shows the game's own title once the game
knows that quest, and the English name and objectives otherwise. Every other
language uses the game's own titles and the English data.

All files fill one global table, `EldoUI_LootData` (`version`, `format`,
`commit`, `build`). The record formats are documented in
`tools/lootdata/README.md`. The folder is loaded on demand by the Loot Guide
(out of combat, a few seconds after login or on first use); nothing in it
runs code beyond filling tables, and it has no saved variables.
