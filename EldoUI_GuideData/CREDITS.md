# EldoUI_GuideData credits

The guides in this folder are the WoW: Forever guides of **Polestar**, a free,
open-source guide project of the WoW: Forever community. Thank you to its
authors for writing them and for sharing them under an open license.

| | |
|---|---|
| Project | Polestar |
| Authors | The Polestar authors: Fitz (fitzforge) and the project's contributors, as credited in its repository ("Copyright (c) 2026 The Polestar authors") |
| Repository | https://github.com/fitzforge/polestar |
| Release | `v0.3.7.2` |
| Commit | `19bd636e7d6f33231770f6029c76d2d4dfc63798` |
| Files used | the English WoW: Forever guides, `guides/forever/**/*.guide` |
| License | GNU General Public License, version 3 (GPL-3.0-only), see `LICENSE` in this folder |

## What this folder holds

`Guides.lua` holds the guide texts and routes of that release: titles, steps,
tips, notes, quest and NPC ids, levels, zones and the coordinates the guide
authors wrote. They are the Polestar authors' work, and they stay under the
GPL-3.0 like the files they come from. Polestar's additional permission for
its compiled guide packs does not cover its guide texts, so it does not apply
to this folder.

The texts are unchanged. The only change is the conversion of the `.guide`
text format into one Lua table that EldoUI's guide window reads: each line
becomes a table entry, zone names become the game's map ids, and the authors'
`#` comments, which players never see, are left out. Translations are not
included; the guides are in English.

The source form of this data is the `.guide` files at the commit above. The
converter that reads them is EldoUI's own code (Apache-2.0); it reads only
those files, never Polestar's program code, its compiled packs or its
reference data.

## The rest of EldoUI

EldoUI itself is licensed under the Apache License 2.0 and does not include
this data. The release zip ships this folder next to the EldoUI folder as a
separate addon, an aggregate under section 5 of the GPL-3.0. This folder
loads only when EldoUI's guide window needs it.

World of Warcraft and Blizzard Entertainment are trademarks or registered
trademarks of Blizzard Entertainment, Inc. Neither Polestar nor EldoUI is
affiliated with or endorsed by Blizzard Entertainment.
