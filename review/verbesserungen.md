# Verbesserungen und fehlende Features

Pfade relativ zum Repo. Aufwand: klein / mittel / groß.

**Rahmen:** WoW: Forever wendet die Addon-Regeln von Midnight an (`docs/PLUGINS.md:14`). Viele Kampfwerte
sind im Kampf geheim, und ein Kampflog gibt es für Addons nicht. Ein eigenes Damage-Meter, ein eigener
Boss-Mod oder Nameplate-Scripting wie in Plater sind deshalb nicht machbar.

## Übersicht

| Nr. | Kurz | Aufwand | Status | Commit |
|---|---|---|---|---|
| A1 | Deutsches Sprachpaket `EldoUI_Locale_deDE` | groß | umgesetzt | `7deb15e` … `37a75bf` |
| A2 | Texte außerhalb der dänischen Liste ins deutsche Paket (`Fork.lua`) | klein–mittel | umgesetzt | `6e7bdf4`, `bc5f0aa` |
| B1 | Gruppensuche-Board aus dem Chat (`EldoUI_GroupBoard`) | mittel | umgesetzt | `6fa6000`, `62ae50d` |
| B2 | Castbars an Party-/Raid-Frames | mittel | offen | |
| B3 | DKP-/EPGP-Stände anzeigen | klein–mittel | offen | |
| B4 | Weltbuff-Tracker (falls Forever Weltbuffs hat) | mittel | offen | |
| C1 | Masque auch für Auren, Combat HUD, ConsumableBar, Totems, Quickdraw | klein–mittel | offen | |
| C2 | Info-Bar stellt ihre Blöcke als LDB-Objekte bereit | klein | umgesetzt | `98cb929` |
| C3 | Doku veraltet: README, CHANGELOG, CONTRIBUTING | klein | umgesetzt | `7781b25` |
| C4 | Versionsgrenzen bei Integrationen (Ace3-Skins bis AceGUI-Minor 41) | – | Daueraufgabe | |
| D1 | Upstream-Updates: Releases unverändert importieren, Eigenes als Plugin | klein | teilweise | `c77d98e` |
| D2 | CI: Syntax, luacheck, TOC, Tests, Release-ZIP | klein–mittel | umgesetzt | `9eb8305` |
| D3 | Version und Fehler-Links des Forks | klein | umgesetzt | `260d193` |
| D4 | Offline-Test-Harness: API-Stubs, Dateien in TOC-Reihenfolge laden | mittel | teilweise | |
| E1 | Module erst bei Bedarf laden | groß | abwarten | |
| E2 | Profiling pro Modul (`/eui perf`) | mittel | offen | |
| E3 | Combat Text setzt pro Frame Punkt, Skalierung, Alpha jeder Zeile | klein | offen | |

**Reihenfolge der offenen Punkte** (für „nächster offener Punkt“): C1, B3, E2, D4, B2, B4, E3, E1.
Kleine Punkte zuerst, und solche, die sich ohne Spiel prüfen lassen. Neue Texte brauchen seit A2 eine deutsche
Übersetzung in `EldoUI_Locale_deDE/Fork.lua`, sonst schlägt die CI fehl (bei `L["…"]`-Texten). B2 hängt an
geheimen Werten im Kampf (wie
F11). Für B4 muss erst feststehen, ob Forever Weltbuffs hat. E1 plant Upstream (`EldoUI/Core/Modules.lua:252`),
und ein eigener Umbau gäbe bei jedem Upstream-Update große Konflikte (D1). D4: Einzeltests, die echten Code aus
den Dateien schneiden, gibt es (`tools/share/`, `tools/clickcast/`, `tools/nameplates/`, `tools/infobar/`,
`tools/groupboard/`).
Ein Laden aller Dateien mit API-Stubs gibt es nicht.

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

**A2 – Texte außerhalb der dänischen Liste (umgesetzt):**
- Problem: Das Paket übernimmt die Schlüssel aus EldoUIs dänischem Paket, und `deDE.py check` lehnte alles andere
  ab. Texte, die der Fork neu geschrieben hat (F01, F03, F04, F07, C2), erschienen deshalb im deutschen Spiel
  englisch. Dasselbe galt für einige Texte von EldoUI selbst, die im dänischen Paket fehlen.
- Neu: `EldoUI_Locale_deDE/Fork.lua`, als letzte Datei geladen. `E:RegisterLocale` führt Tabellen derselben
  Sprache zusammen. Sie enthält 23 Texte:
  - die 11 des Forks;
  - 6 `L["…"]`-Texte von EldoUI: Prüfung von Profilnamen, „Profil … hat ausgeschaltet“, die Zeile beim Login;
  - 6 Texte, die EldoUI erst beim Anzeigen übersetzt (`-- no-L (translated where shown)`): drei
    Selbstgefunden-Hinweise und drei Finder-Einträge.
- `tools/locale/deDE.py`:
  - `check`: Jeder Schlüssel in `Fork.lua` muss ein String im Code sein und darf kein dänischer Schlüssel sein.
    Es gelten dieselben Platzhalter-Regeln wie überall.
  - Neu in `check`: Jeder `L["…"]`-Schlüssel im Code braucht eine deutsche Übersetzung, in einer der beiden
    Listen. Ein neuer Text ohne Übersetzung lässt die CI also fehlschlagen.
  - `apply` legt Schlüssel, die keine dänischen sind, aber im Code stehen, in `Fork.lua` ab. `build` und `xref`
    beziehen sie ein, `status` zählt sie.
  - Lua-Escapes werden als Bytes gelesen: `"\226\128\147"` ist ein Gedankenstrich. Bisher zerfiel er in drei
    falsche Zeichen, und die Fundstellen für Übersetzer stimmten bei solchen Texten nicht.
- Nicht automatisch geprüft: Texte, die erst beim Anzeigen übersetzt werden, also Beschriftungen und
  Beschreibungen in Optionstabellen und `no-L`-Zeilen. Eine Suche danach findet zu viel anderes (Bezeichner,
  Icon-Pfade, Diagnose-Ausgaben). Solche Texte kommen von Hand per `apply` dazu. `tools/ci/README.md` beschreibt
  den Ablauf.
- Test: `tools/locale/test_fork.py` (läuft in `tools/ci/check_all.sh tests`, 17 Prüfungen). Er baut ein
  Mini-Repository und lässt `check` und `apply` von `deDE.py` darauf laufen, mit dem echten `dump.lua`:
  - Ein Text ohne Übersetzung, ein Schlüssel in `Fork.lua`, den der Code nicht benutzt, und ein dänischer
    Schlüssel in `Fork.lua` lassen `check` fehlschlagen.
  - Nach `apply` steht der neue Text in `Fork.lua`, und `check` ist grün.
- Im Spiel prüfen, mit Deutsch unter General › EldoUI language:
  - Wie beim Test zu F07: `/eui exportlua module:Chat`, im Text `["version"]` des Schemas auf 99 setzen, mit
    `/eui import` einfügen. Erwartung: „der String stammt aus einem neueren EldoUI …“.
  - Info Bar › Datentexte: Die Zeile „Datentext 1 für andere Addons“ ist deutsch, wenn Titan Panel o. Ä. geladen
    ist; sonst der deutsche Hinweis.
  - Beim Login (wenn die Begrüßung an ist): „v… geladen. Gebt /eui ein, um die Optionen zu öffnen.“

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
  - **Umgesetzt (C2):**
    - Auswahl: Der Spieler wählt bis zu acht Info-Bar-Blöcke (Info Bar › Datatexts, unter „Other addons
      (LibDataBroker)“: „Block 1 for other addons“ usw.). Die Zeilen erscheinen erst, wenn ein Addon
      LibDataBroker geladen hat, sonst steht dort ein Hinweis.
    - Jeder gewählte Block wird ein Datenobjekt „EldoUI: <Block>“ mit Text, Name, Icon, Tooltip und Klick. Das
      macht `Modules/InfoBar/Broker.lua`.
    - Warum nicht alle Blöcke: Manche Displays (ChocolateBar) setzen jedes neue Objekt auf ihre Leiste. Gut 60
      EldoUI-Blöcke auf einen Schlag wären zu viel. Außerdem muss jeder angebotene Block ständig aktuell gehalten
      werden, weil ein Display nicht sagt, was es zeigt.
    - Aktualisierung wie auf der Leiste: bei den Events des Blocks, im Poll-Takt (1 s oder der eigene) und wenn
      die Info-Bar ihn per Name auffrischt (Post, Würfe usw.).
    - Geheime Texte (im Kampf) werden nicht weitergegeben, weil die Bibliothek jeden neuen Wert mit dem alten
      vergleicht. Das Objekt behält dann seinen letzten lesbaren Text.
    - Klicks: Ein Klick im Display macht dasselbe wie auf dem Block. Im Kampf gilt dieselbe Regel: Nur Blöcke
      mit `combatClick` reagieren, sonst erscheint „Not in combat.“ am Display. Menüs öffnen am Knopf des
      Displays.
    - Ein Block, der aus der Liste genommen wird, oder das ausgeschaltete Modul: Das Objekt zeigt „Off“, denn
      die Bibliothek kann Objekte nicht zurücknehmen. Bis zum Reload bleibt es in der Liste des Displays.
    - Die Bibliothek bringt jedes Display selbst mit, EldoUI liefert sie nicht. Lädt das Display nach EldoUI,
      findet `ADDON_LOADED` sie. Ein Name, den schon ein anderes Addon benutzt, wird nicht angefasst.
    - In `InfoBar.lua`:
      - Die Tooltip-Zeilen stehen jetzt in `TooltipLines`, das die Leiste und die Objekte teilen.
      - `UpdateButton` übergeht Frames ohne `dataName`: Ein Klick im Display gibt dessen Frame an Blöcke weiter,
        die sich danach selbst auffrischen (Speicher, Lautstärke, Gold).
      - Die Brücke, die fremde LDB-Feeds liest, überspringt EldoUIs eigene Objekte. Sonst kämen sie als
        „LDB: EldoUI: …“ zurück.
    - Test: `tools/infobar/test_broker.lua` (läuft in `tools/ci/check_all.sh tests`, 57 Prüfungen). Er lädt
      `Broker.lua` ganz und die geänderten Teile von `InfoBar.lua`. Dazu kommt ein Modell von LibDataBroker-1.1,
      das wie die Bibliothek Werte vergleicht und bei einem geheimen Wert scheitert.
    - Grenzen:
      - Das Mausrad hat in LibDataBroker kein Gegenstück.
      - Der Ruhestein-Block zeigt seinen Text, ein Klick benutzt ihn aber nicht. Das geht nur über den
        geschützten Knopf auf EldoUIs Leiste.
      - Die Optionstexte waren zuerst nur englisch; seit A2 sind sie auch deutsch.
    - Im Spiel prüfen, mit Titan Panel oder ChocolateBar:
      - Info Bar › Datatexts: „Durability“ und „Time“ als Block 1 und 2 wählen. Erwartung: Im Display erscheinen
        „EldoUI: Durability“ und „EldoUI: Time“. Die Uhr läuft mit, die Haltbarkeit ändert sich nach einem Tod
        bzw. beim Reparieren.
      - Maus darüber halten: derselbe Tooltip wie auf der Leiste.
      - Klick auf „Durability“: Das Charakterfenster öffnet sich. Im Kampf erscheint stattdessen „Not in combat.“.
      - Block 1 wieder leeren: Der Block zeigt „Off“ und ist nach `/reload` weg.
      - Danach `/eui errors`: keine Lua-Fehler.
- **Doku veraltet:** README nennt 0.7.1000; `CHANGELOG.md:3` hat einen verirrten Punkt; `.github/CONTRIBUTING.md`
  sagt „PRs cannot be merged“. Aufwand klein.
  - **Umgesetzt (C3):**
    - README: „0.7.1000“ ist kein Fehler im eigentlichen Sinn. Es ist EldoUIs Ausgangsstand für Profile und
      Presets. Upstream hat README und Wiki für 0.7.2000 und 0.7.2001 bewusst so gelassen (der Upstream-README
      von 0.7.2000 sagt dasselbe). Statt den Upstream-Text umzuschreiben, erklärt der Fork-Hinweis die Zahl und
      verweist auf CHANGELOG und `docs/wiki/current-release.md`. Das hält spätere Upstream-Importe konfliktarm (D1).
    - Im Original-Text geändert, weil es für den Fork falsch war: Sprachen nennen jetzt Deutsch; der Link für
      Fehlerberichte führt wie der Report-Knopf im Spiel (D3) zu diesem Repo.
    - CHANGELOG: Die verirrte Zeile („Pick the spell and rank each class buff reminder asks for…“) kam mit dem
      Upstream-Commit „EldoUI 0.7.1001“ (10.11.) in die damalige [Unreleased]-Liste, aus der 0.7.2000 wurde.
      Sie steht jetzt unter 0.7.2000 › Auras and cooldowns › New, in `CHANGELOG.md` und dem identischen
      `EldoUI/CHANGELOG.md`.
    - CONTRIBUTING: Fork-Hinweis oben. Einleitung und „Pull requests“ beschreiben den Fork: Code liegt hier,
      Änderungen per PR mit den Prüfungen aus `tools/ci/README.md`. Journal-Daten gehen wie der Link im Spiel an
      EldoUIs Formular.
    - Nicht geändert: Das Wiki (`docs/wiki/`) und `.github/SUPPORT.md` verweisen weiter auf Upstream. Das passt,
      weil Upstream sie pflegt. Die Issue-Vorlagen sind Upstreams. Im privaten Repo ist das Fehlerformular für
      den Report-Knopf nötig, die anderen schaden nicht.
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
