# Verbesserungen und fehlende Features

Pfade relativ zum Repo. Aufwand: klein / mittel / groß.

**Rahmen:** WoW: Forever wendet die Addon-Regeln von Midnight an (`docs/PLUGINS.md:14`). Viele Kampfwerte
sind im Kampf geheim, und ein Kampflog gibt es für Addons nicht. Ein eigenes Damage-Meter, ein eigener
Boss-Mod oder Nameplate-Scripting wie in Plater sind deshalb nicht machbar.

## Top-Empfehlungen

| # | Was | Aufwand |
|---|---|---|
| 1 | Arbeitsweise für Upstream-Updates: Releases unverändert importieren, eigene Features als Plugin | klein |
| 2 | CI: Syntaxcheck, luacheck mit `.luacheckrc`, TOC-Check, Release-ZIP (umgesetzt, siehe D2) | klein–mittel |
| 3 | Deutsches Sprachpaket `EldoUI_Locale_deDE` | Struktur klein, Inhalt groß |
| 4 | Versionscheck und Fehler-Links an den privaten Fork anpassen (umgesetzt, siehe D3) | klein |
| 5 | Erstes eigenes Feature: Gruppensuche-Board aus dem LFG-Chat (umgesetzt: `EldoUI_GroupBoard`) | mittel |

## A – Deutsche Übersetzung

> **Umgesetzt:** `EldoUI_Locale_deDE` ist vollständig (20.827 von 20.827 Texten), Anrede „Ihr/Euch“, Begriffe des
> deutschen Clients. Werkzeuge, Prüfungen und Glossar: `tools/locale/` (`deDE.py status|check|xref`). Im Code:
> deutsches Datumsformat (`Core/Dates.lua`) und `E:InSentence` für Wörter, die in Sätze eingesetzt werden.
> Nicht geprüft am deutschen Client sind Zauber-, Gegenstands- und Gebietsnamen, die die Übersetzer aus dem
> Gedächtnis gesetzt haben. Die Analyse unten ist der Stand vor der Umsetzung.

**Locale-System** (`EldoUI/Core/Locale.lua`):
- Der englische Text ist der Schlüssel. Fehlt eine Übersetzung, erscheint Englisch (Metatable, `:101`).
- Sprachpakete melden sich mit `E:RegisterLocale(code, tabelle)` an (`:124`) und werden als eigenes Addon
  `EldoUI_Locale_<code>` per LoadOnDemand nur für die gewählte Sprache geladen (`:156`, `:230`).
- `deDE` hat schon Name, Flagge und Pluralregeln (`:56`, `:390`).
- Ein Tracker für fehlende Texte ist eingebaut: `/eui locale track`, `/eui locale missing` (`:547`).

**Umfang:**
- Das dänische Paket hat 20.827 Strings (Core 4.008, Module A–L 7.819, Module M–Z 5.814, LootGuide 3.186).
- 3.404 davon gibt es schon auf Deutsch in `EldoUI/Modules/LootGuide/Locale/deDE.lua`.
- Offen: 17.423 Strings, etwa 141.000 englische Wörter. Von Hand grob 2–3 Personenmonate; mit maschineller
  Vorübersetzung und Glossar etwa 2–4 Wochen Korrektur. Modulweise Auslieferung ist möglich.

**Nötige Anpassungen:**
- Paketstruktur von `EldoUI_Locale_daDK` übernehmen (TOC mit `## X-EldoUI-Locale: deDE`, `## LoadOnDemand: 1`).
- `EldoUI/Modules/LootGuide/Locale/deDE.lua:7` lädt nur auf einem deutschen Client → Kopie ohne diese Sperre ins Paket.
- `EldoUI/Core/Dates.lua:50`: `DAY_FIRST` um `deDE` ergänzen („14. Oktober“).
- Deutsch ist etwa 20 % länger als Englisch (Dänisch 6 %). Mindestens 21 Buttons mit fester Breite prüfen,
  z. B. `EldoUI/Modules/Chat/Messages.lua:1094` („Close“, 44 px).
- Schriften: alle Fonts in `EldoUI/Media/Fonts` enthalten äöüß – kein Handlungsbedarf.
- Nur englisch, nicht über das Locale-System: Story-Generator, Eldostar-Guides, Wortspiele, Trivia.
- Upstream-Werkzeuge für Locales (`tools/locale_keys.py` usw.) wurden nie veröffentlicht. Für den Fork braucht es
  einen eigenen Extraktor, einen Platzhalter-Check (`%s`, `%d`, `|c…|r`) und eine Pseudo-Locale mit +30 % Länge.

## B – Fehlende Features (per Codesuche geprüft)

> **Gruppensuche-Board umgesetzt** als Plugin `EldoUI_GroupBoard` („Gruppen-Pinnwand“, nach D1 über die öffentliche
> Plugin-API, nichts in `EldoUI/` geändert). Liest LFM/LFG-Beiträge aus SucheNachGruppe, Allgemein, Handel (aus)
> und Kanälen nach Name („World, Welt“), erkennt Orte (klassisch EN/DE mit Kürzeln, Forever-Dungeons, Dungeonliste
> des Clients), Rollen und Anzahl; Fenster mit Filter-Chips, Suche, Flüstern/Einladen per Klick; Infoleisten-Block,
> `/eui board`, Finder, Hinweis (aus). Deutsche Texte im Plugin. Offline geprüft (`tools/groupboard/`), **im Spiel
> nicht getestet**. Ordnername mit `EldoUI_`-Präfix wie das deutsche Paket: Fehler landen so im EldoUI-Fehlerlog;
> `docs/PLUGINS.md` reserviert das Präfix eigentlich für EldoUIs eigene Modul-Addons. Details:
> `EldoUI_GroupBoard/README.md`.
> Eine unabhängige Prüfung fand keine falschen Aufrufe der EldoUI- und WoW-API, aber Parser-Lücken: Alltagschat
> mit „need“/„sucht“ als Gruppe, „LF 2M“ übersehen, „summons ready“ verworfen, „DM w/ tank“ als Düsterbruch West,
> Flügel aus der Dungeonliste doppelt. Alle eingearbeitet und als Testzeilen in `tools/groupboard/` festgehalten.

| Feature | Beleg (Suche) | Aufwand |
|---|---|---|
| Gruppensuche-Board aus LFG-/World-Chat | `LFM\|LF[0-9]M\|bulletin`: nur Chat-Tab und eine LF2M-Zeile | mittel |
| Castbars an Party-/Raid-Frames | `UNIT_SPELLCAST\|UnitCastingInfo` in GroupFrames: 0 Treffer | mittel |
| DKP-/EPGP-Stände anzeigen | `EPGP\|DKP`: 0 Treffer (nur softres, TMB, GDKP) | klein–mittel |
| Weltbuff-Tracker (falls Forever Weltbuffs hat) | `songflower\|dragonslayer\|world buff`: 0 Treffer | mittel |

**Schon vorhanden:** Damage-Meter-Skin, Encounter Timeline, Fokus- und Boss-Frames, frei belegbare Datenleisten
(`RegisterDataText`), Profile pro Charakter und Talentgruppe, Nameplate-Farbregeln, 67 Tags, Aurenfilter-Editor,
Cooldown-Text, Chat kopieren, Gamepad, Spell-/Item-IDs im Tooltip, Quest-Automatik, Reichweiten-Fade.

**Bewusst ausgeschlossen:** Arena-Frames (keine Arenen in Forever), Gegner-Auren auf Nameplates,
Inspect-Anfragen, automatische Loot-Verteilung.

## C – Verbesserungen bestehender Features

- **Masque nur für Aktionsleisten** (`EldoUI/Modules/ActionBars/Buttons.lua:792`). Auren, Combat HUD,
  ConsumableBar, Totems, Quickdraw: kein Masque. Aufwand klein–mittel.
- **Info-Bar liest LDB, stellt aber nichts bereit:** kein `NewDataObject` im Code, Titan Panel kann keine
  EldoUI-Blöcke zeigen. Aufwand klein.
- **Doku veraltet:** README nennt 0.7.1000; `CHANGELOG.md:3` hat einen verirrten Punkt; `.github/CONTRIBUTING.md`
  sagt „PRs cannot be merged“. Aufwand klein.
- **Versionsgrenzen bei Integrationen:** Ace3-Skins nur bis AceGUI-Minor 41 (`EldoUI/Modules/SkinsAddons.lua:29`).
  Bei Addon-Updates prüfen.

## D – Infrastruktur für den Fork

- **Ist-Zustand:** kein CI, keine `.luacheckrc`, keine Tests, keine Build-Skripte. Der Code verweist rund 40-mal
  auf nie veröffentlichte `tools/…`-Skripte. 42 Dateien sind generiert („never edit by hand“) und lassen sich
  nicht neu erzeugen – nur mit Vorsicht von Hand ändern.
- **D1 Upstream-Updates:**
  - neue Releases unverändert in einen Branch `upstream-release` importieren und von dort nach `main` mergen;
  - eigene Features möglichst als Plugin-Addons `EldoUI_<Name>` über die öffentliche API (`docs/PLUGINS.md`).
  - **Teilweise umgesetzt:** Der Versionswächter (`.github/workflows/watch.yml`) meldet jede neue EldoUI-Version
    als Issue, dazu neue WoW: Forever-Patches (live und im Test-Client). Den Branch `upstream-release` gibt es
    noch nicht; er entsteht beim ersten Upstream-Update.
- **D2 CI** per GitHub Action:
  - `luac -p`, luacheck und TOC-Check;
  - bei Tag `v*` ein ZIP mit den sechs Addon-Ordnern.
  - **Umgesetzt:** `.github/workflows/ci.yml` (jeder Push und PR) und `release.yml` (Tag `v*`), Skripte und
    Beschreibung in `tools/ci/` (`check_all.sh` läuft lokal genauso). luacheck prüft nur Globals, gegen die Liste
    der heute benutzten WoW-API-Namen (`tools/ci/globals.lua`); Stilwarnungen bleiben aus, der Upstream-Code ist
    nicht dafür geschrieben. Das ZIP enthält alle acht `EldoUI*`-Ordner, nur von git erfasste Dateien.
- **D3 Privater Fork:**
  - **Umgesetzt:** Version `0.7.2001-p1` (EldoUI und deutsches Paket); der Hinweis „Was ist neu“ vergleicht die
    Version ohne Endung (`EldoUI/Core/Config.lua`, `CheckUpdateNote`). Fehlerbericht und Loot-Guide-Hilfe führen
    zu `con1338/WoW-UI-Addon`. Die Meldung von Journal-Daten (`LG.JOURNAL_DATA_ISSUE_URL`) geht bewusst weiter an
    Upstream: Die Daten pflegt EldoUI, nicht der Fork.
  - Der Versionscheck sendet über das Präfix `EldoUIVer` an Gilde und Gruppe (`EldoUI/Core/Plugins.lua:76`).
    Eine Version wie `0.7.2001.1` würde anderen EldoUI-Nutzern „newer version“ melden. Besser eine Endung
    `0.7.2001-p1` (wird ignoriert) oder den Versionscheck abschalten (Plugins > Notices).
  - Fehler-Links im Spiel zeigen auf das Upstream-Repo (`EldoUI/Core/Errors.lua:247`,
    `EldoUI/Modules/LootGuide/Options.lua:17`).
  - Schema-Nummern (`EldoUI/Core/Database.lua:588`) nicht selbst erhöhen, sonst kollidieren spätere
    Upstream-Migrationen.
- **D4 Offline-Test-Harness:** WoW-API-Stubs und Laden der Dateien in TOC-Reihenfolge. Aufwand mittel.

## E – Performance

1. **Alles lädt beim Login:** 589 Dateien, rund 16,8 MB Lua, davon rund 1,8 MB für Module, die standardmäßig aus
   sind (FlightGames allein 0,66 MB). Upstream plant eine Aufteilung (`EldoUI/Core/Modules.lua:252`).
2. **Kein Profiling pro Modul:** Der zentrale Event-Dispatcher (`EldoUI/Core/Init.lua:200`) und `E.Ticker`
   könnten pro Modul messen (`/eui perf`).
3. **OnUpdate ist sauber:** Frames verstecken sich im Leerlauf. Einzig Combat Text setzt pro Frame Punkt,
   Skalierung und Alpha jeder Zeile (`EldoUI/Modules/CombatText/Engine.lua:360`). Niedrige Priorität.
