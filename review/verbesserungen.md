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
| B2 | Castbars an Party-/Raid-Frames | mittel | umgesetzt | `0192bd9` |
| B3 | DKP-/EPGP-Stände anzeigen | klein–mittel | umgesetzt | `66b7bee`, `2101fcd` |
| B4 | Weltbuff-Tracker (Forever hat Weltbuffs, laut Nutzer) | mittel | umgesetzt | `2b77920` |
| B5 | Leiste mit allen benutzbaren Questgegenständen aus den Taschen (Wunsch des Nutzers) | mittel | umgesetzt | `597197f`, `c64271e`, `bbc944e` |
| B6 | Signal, wenn Essen und Trinken fertig sind (Wunsch des Nutzers) | klein | umgesetzt | `7213a3d`, `f90e7f1` |
| B7 | Taschen fast voll: früher Hinweis und Liste „Platz schaffen“ | klein–mittel | umgesetzt | `86fba91`, `fc8f1ee` |
| B8 | Quest-EP hinter jedem Titel im Questlog (Wunsch des Nutzers) | klein | umgesetzt | `7213a3d`, `f90e7f1` |
| B9 | „Wer fehlt?“ für Gruppe und Raid (Herbeirufen) | mittel | abwarten | |
| B10 | Wowhead-Links in der Spielsprache (Wunsch des Nutzers) | klein | umgesetzt | `7213a3d` |
| B11 | Absitzen und Aufstehen bei Fehlermeldung (einschaltbar) | klein | offen | |
| B12 | Ausrüstungsset nach dem Kampf anlegen (einschaltbar) | klein | umgesetzt | `9cdd6aa`, `dd84be6` |
| C1 | Masque auch für Auren, Combat HUD, ConsumableBar, Totems, Quickdraw | klein–mittel | teilweise | `5753197`, `575bafc` |
| C2 | Info-Bar stellt ihre Blöcke als LDB-Objekte bereit | klein | umgesetzt | `98cb929` |
| C3 | Doku veraltet: README, CHANGELOG, CONTRIBUTING | klein | umgesetzt | `7781b25` |
| C4 | Versionsgrenzen bei Integrationen (Ace3-Skins bis AceGUI-Minor 41) | – | Daueraufgabe | |
| C5 | Combat Text: Stil „Kräftig“ (Wunsch des Nutzers, Entwurf gewählt) | mittel | umgesetzt | `d83f389` |
| C6 | RestedXP im deutschen Client: Zielnamen, Guide-Kette, Gruppennamen (Wunsch des Nutzers) | mittel | umgesetzt | `befb8ab` |
| C7 | Leisten-Schnappschüsse sichern auch, welche Aktionsleisten an sind (Forever-Hotfix 13.11.) | klein | umgesetzt | `95002b5` |
| C8 | Kampfsimulation: Richturteil würfelt als Fernkampfangriff (Forever-Hotfix 11.11.) | klein | umgesetzt (seit 0.7.3000 von EldoUI) | `95002b5`, `c323ceb` |
| D1 | Upstream-Updates: Releases unverändert importieren, Eigenes als Plugin | klein | umgesetzt | `c77d98e`, `8b8f957`, `c323ceb`, `775b23d`, `f9c0fc9` |
| D2 | CI: Syntax, luacheck, TOC, Tests, Release-ZIP | klein–mittel | umgesetzt | `9eb8305` |
| D3 | Version und Fehler-Links des Forks | klein | umgesetzt | `260d193` |
| D4 | Offline-Test-Harness: API-Stubs, Dateien in TOC-Reihenfolge laden | mittel | umgesetzt | `fb8c242` … `141e84d` |
| E1 | Module erst bei Bedarf laden | groß | abwarten | |
| E2 | Profiling pro Modul (`/eui perf`) | mittel | umgesetzt | `cc64a52` |
| E3 | Combat Text setzt pro Frame Punkt, Skalierung, Alpha jeder Zeile | klein | umgesetzt | `d83f389` |
| E4 | Infoleiste: Speicher-Block hält das Spiel alle 30 s an (mit `/eui perf` gefunden) | klein | umgesetzt | `4c6cf53` |

**Reihenfolge der offenen Punkte** (für „nächster offener Punkt“): B11, C1 (Rest), E1.
**Stand 16.11.2026:** B5 bis B12 kommen aus einer Suche nach QoL-Lücken (Abschnitt B, „QoL-Vorschläge“). Der Nutzer
hat B6, B8 und B10 gewählt. B9 wartet, bis er Stufe 60 erreicht und Gruppeninhalte spielt (seine Auskunft). Bei B11
erst im Spiel prüfen, ob Forever schon von selbst absitzt. B6 und B8 sind neue Dateien in der `EldoUI.toc`: Nach dem
Kopieren das Spiel ganz neu starten, denn `/reload` liest die Dateiliste nicht neu (wie bei C6). Ohne Neustart fehlen
nur die beiden Funktionen, Fehler gibt es keine, weil nichts in `QoL.lua` sie aufruft.
Danach wählte der Nutzer B5. Auch B5 ist eine neue Datei in der TOC, dazu kommen neue Einträge in `Bindings.xml`:
wieder das Spiel ganz neu starten. Die zwei offenen Fragen zu B8 (eigene EP je Quest, Häkchen) prüft der Nutzer am
Abend des 16.11. im Spiel. Nach dem Merge von B5 (PR #31) ging es mit dem nächsten offenen Punkt weiter, B7. Auch B7 ist
eine neue Datei in der TOC (`Modules/QoL/BagSpace.lua`): wieder ganz neu starten. Nach dem Merge von B7 (PR #33) wählte
der Nutzer B12. B11 bleibt offen; dort muss vorher ein Spieltest klären, ob Forever von selbst absitzt. B12 ändert nur
eine vorhandene Datei: `/reload` reicht.
**Stand 14.11.2026:** Was offline ging, ist erledigt. C1 (Rest) und E3 gehen wir gemeinsam an, sobald jemand im Spiel
testen kann (Absprache mit dem Nutzer). Der Rest von C1 (Auren, Combat HUD) braucht einen Test mit Masque. E3 ändert
das Zeichnen von Combat Text, das sieht man nur im Spiel. E1 plant Upstream (`EldoUI/Core/Modules.lua:252`), und
ein eigener Umbau gäbe bei jedem Upstream-Update große Konflikte (D1). Neue Texte brauchen seit A2 eine deutsche
Übersetzung in `EldoUI_Locale_deDE/Fork.lua`, sonst schlägt die CI fehl (bei `L["…"]`-Texten). Dazu kommen die
Spieltests aller umgesetzten Punkte (jeweils unter „Im Spiel prüfen“).

## Top-Empfehlungen

| # | Was | Aufwand |
|---|---|---|
| 1 | Arbeitsweise für Upstream-Updates: Releases unverändert importieren, eigene Features als Plugin | klein |
| 2 | CI: Syntaxcheck, luacheck mit `.luacheckrc`, TOC-Check, Release-ZIP (umgesetzt, siehe D2) | klein–mittel |
| 3 | Deutsches Sprachpaket `EldoUI_Locale_deDE` | Struktur klein, Inhalt groß |
| 4 | Versionscheck und Fehler-Links an den Fork anpassen (umgesetzt, siehe D3) | klein |
| 5 | Erstes eigenes Feature: Gruppensuche-Board aus dem LFG-Chat (umgesetzt: `EldoUI_GroupBoard`) | mittel |

## A – Deutsche Übersetzung

> **Umgesetzt:** `EldoUI_Locale_deDE` ist vollständig (20.827 von 20.827 Texten; seit EldoUI 0.7.3001 wieder
> vollständig mit 21.525, seit 0.7.3005 mit 21.557, seit 0.7.3100 mit 21.664, siehe D1), Anrede „Ihr/Euch“,
> Begriffe des deutschen Clients. Werkzeuge, Prüfungen und Glossar: `tools/locale/` (`deDE.py status|check|xref`).
> Im Code: deutsches Datumsformat (`Core/Dates.lua`) und `E:InSentence` für Wörter, die in Sätze eingesetzt
> werden.
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
  - Wie beim Test zu F07: `/eui exportlua chat`, im Text `["version"]` des Schemas auf 99 setzen, mit
    `/eui import` einfügen. Erwartung: „der String stammt aus einem neueren EldoUI …“.
  - Info Bar › Datentexte: Die Zeile „Datentext 1 für andere Addons“ ist deutsch, wenn Titan Panel o. Ä. geladen
    ist; sonst der deutsche Hinweis.
  - Beim Login (wenn die Begrüßung an ist): „v… geladen. Gebt /eui ein, um die Optionen zu öffnen.“
- Im Spiel geprüft (15.11.2026), deutscher Client: Die Meldung „… stammt aus einem neueren EldoUI …“ kommt auf
  Deutsch. Zur Begrüßung keine Abweichung gemeldet. Die Zeile für andere Addons in der Info Bar ist nicht geprüft
  (kein Titan Panel geladen).

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

**B4 – Weltbuff-Tracker (umgesetzt):**
- Forever hat Weltbuffs (Auskunft des Nutzers, 14.11.2026). Neu: Modul „World Buffs“ (`Modules/WorldBuffs.lua`,
  Kategorie Gruppe, standardmäßig an).
- Info-Bar-Block „World buffs“: Anzahl der eigenen Weltbuffs und die kürzeste Restzeit. Der Tooltip zeigt jeden
  einzeln mit Zeit, in einer Gruppe außerhalb des Kampfs auch, wie viele jedes Mitglied hat.
- Warnung: eine lokale Chatzeile, wenn ein eigener Weltbuff nur noch wenige Minuten hat. Standard 5 Minuten, einmal
  pro Buff, nie im Kampf (dann gleich danach), nie gesendet.
- Bereitschaftsbericht: eine Spalte „World buffs“ mit der Anzahl je Mitglied. Standardmäßig aus, über
  `ReadyReport:AddColumn`.
- Welche Buffs: die der klassischen Welt, also Drachentöter (22888), Segen des Kriegshäuptlings (16609), Geist von
  Zandalar (24425), Liedblumen-Serenade (15366), Sayges dunkles Schicksal (8 IDs), die drei Düsterbruch-Tribute.
  Eine Aura zählt über die Spell-ID **oder** über den Namen, den der Client für eine dieser IDs liefert. Andere IDs
  desselben Buffs in Forever und jede Sprache passen damit auch.
- Regeln: Auren über `C_UnitAuras` in pcall. Andere Mitglieder werden nur außerhalb des Kampfs gelesen. Geheime
  Auren, Namen und Zeiten bleiben weg und werden nie verglichen.
- Deutsch: „Weltbuffs“. Das Glossar erlaubt die Kurzform „Buffs“, wo Platz knapp ist, und so heißt es unter
  deutschen Spielern.
- Test: `tools/worldbuffs/test_world_buffs.lua` (läuft in `tools/ci/check_all.sh tests`, 39 Prüfungen). Der
  Offline-Start (D4) lädt das Modul mit.
- Risiko: Die Spell-IDs stammen aus Classic. Hat Forever für einen Weltbuff eine andere ID **und** einen anderen
  Namen, wird er nicht erkannt. Das zeigt erst der Test im Spiel; dann gehört die ID in `M.BUFFS`.
- Im Spiel prüfen:
  - Info-Bar-Block „World buffs“ einem Platz zuweisen und einen Weltbuff holen (z. B. Liedblume oder
    Dunkelmond-Jahrmarkt). Erwartung: Anzahl und Restzeit; im Tooltip Name und Zeit.
  - Mit einem Buff kurz vor dem Ende: die Chatzeile „… läuft in … aus.“ kommt einmal.
  - In einer Gruppe den Tooltip öffnen: die Mitglieder mit ihrer Anzahl. Im Kampf steht dort der Hinweis.
  - Optionen › World Buffs › „Column in the Ready Check Report“ an, dann einen Bereitschaftscheck: Spalte mit
    der Anzahl je Mitglied.
  - Danach `/eui errors`: keine Lua-Fehler.

**B2 – Castbars an Party-/Raid-Frames (umgesetzt):**
- Neu: `Modules/GroupFrames/Cast.lua`. Eine schmale Leiste am unteren Rand des Rahmens zeigt, was das Mitglied
  zaubert. Zauber füllen sie, kanalisierte Zauber leeren sie, grau, wenn sich der Zauber nicht unterbrechen lässt.
- Einstellungen je Abschnitt (Gruppe, die Raid-Größen, Main Tanks) bei den Leisten: „Cast bar“, Höhe (2–16 px) und
  „Spell name on the cast bar“. Der Name erscheint ab 8 px. Standardmäßig aus; solange kein Abschnitt sie an hat,
  hört nichts auf das Spiel.
- So liest es das Spiel:
  - Ein Frame hört die `UNIT_SPELLCAST_*`-Events für Euch, party1–4 und raid1–40.
  - Welche Rahmen welche Unit zeigen, steht in einem Index. `SetUnit` in `GroupFrames.lua` meldet jeden
    Unit-Wechsel (eine Zeile dort). So wandert die Leiste bei einer Roster-Änderung im Kampf mit.
  - Jedes Event liest den Zauber neu (`UnitCastingInfo`, dann `UnitChannelInfo`). Ein gescheiterter Versuch eines
    anderen Zaubers lässt die Leiste stehen, ein Ende versteckt sie.
- Geheime Werte (wie bei F11):
  - Mit dem Dauer-Objekt des Spiels (`UnitCastingDuration`) lässt der Client die Leiste selbst laufen
    (`SetTimerDuration`). Geheime Zeiten sind dann kein Problem.
  - Das Grau für ein geheimes „nicht unterbrechbar“ wählt `C_CurveUtil.EvaluateColorFromBoolean`.
  - Ohne Dauer-Objekt läuft die Leiste über klare Start- und Endzeiten am gemeinsamen Ticker. Sind die geheim,
    bleibt sie aus. Nichts Geheimes wird getestet, verglichen oder gerechnet.
- Nicht dabei: Begleiter und die Ziele der Main Tanks, denn ihre Units bekommen keine eigenen Zauber-Events.
- Test: `tools/groupframes/test_cast.lua` (läuft in `tools/ci/check_all.sh tests`, 35 Prüfungen). Er lädt
  `Cast.lua` ganz, mit nachgebauten Zauber-APIs. Geheime Werte scheitern dort bei jedem Vergleich und jeder
  Rechnung, wie im Spiel. Der Offline-Start (D4) lädt die Datei mit und schaltet das Modul an und aus.
- Im Spiel prüfen, vor allem in einer Instanz und im Kampf, wo Werte geheim sein können:
  - Party › Leisten › „Cast bar“ an. Ein Gruppenmitglied zaubert: Die Leiste füllt sich, beim kanalisierten Zauber
    leert sie sich.
  - In einem Dungeon im Kampf: Die Leisten laufen weiter, auch wenn das Spiel Zeiten geheim hält. Grau erscheint
    nur bei Zaubern, die sich nicht unterbrechen lassen (bei Spielern selten).
  - Raid: Jemand verlässt im Kampf den Raid, während andere zaubern. Die Leisten sitzen danach am richtigen Rahmen.
  - Höhe 10 und „Spell name“ an: Der Name steht auf der Leiste.
  - Danach `/eui errors`: keine Lua-Fehler, auch nicht im Kampf.

**B3 – DKP-/EPGP-Stände (umgesetzt):**
- Datenquelle: Gilden mit DKP oder EPGP führen den Stand jedes Mitglieds in den Notizen des Gildenrosters,
  geschrieben vom DKP-/EPGP-Addon oder von einem Offizier. Neu: `Modules/RaidLoot/Points.lua` liest sie, nur
  lesend.
- Anzeige:
  - hinter jedem Namen in den SR- und TMB-Zeilen (Gegenstands-Tooltips, Würfelfenster);
  - im Tooltip von Gildenmitgliedern (Tooltip-Abschnitt „Guild points (DKP and EPGP)“);
  - im Info-Bar-Block „Guild points“: der eigene Stand; im Tooltip die Gruppe, ohne Gruppe die besten 15 der
    Gilde.
- Datenschutz: Der Chat-Beitrag mit den Reservierungen enthält die Stände nie, denn Offiziersnotizen sind für
  Offiziere.
- Formate:
  - EPGP „EP,GP“, wie EPGP und CEPGP es schreiben. Die Priorität ist EP / (GP + Basis-GP); das Basis-GP stammt aus
    der Gildeninfo (`@BASE_GP:n`, die Zeile des EPGP-Addons), sonst 0. Twinks, deren Notiz der Name des Mains ist
    (EPGPs Twink-Regel), zeigen den Stand des Mains.
  - DKP: „Net:350“ (QDKP), „DKP: 350“, „350 DKP“. Mit der Einstellung „DKP“ zählt auch eine bloße Zahl.
  - „Automatisch“ (Standard) nimmt nie eine bloße Zahl, weil eine Notiz für alles Mögliche eine Zahl enthalten
    kann.
- Notiz: Standard ist die Offiziersnotiz, gelesen nur, wenn das Spiel sie zeigt. Wahlweise die öffentliche Notiz
  oder beide. Die Optionen stehen auf der Raid-Loot-Seite vor „Posting“.
- Neu gelesen wird bei `GUILD_ROSTER_UPDATE`. Neu gezeichnet wird nur, wenn sich ein Stand geändert hat.
- Im Spiel gefunden (15.11.2026): WoW: Forever blockiert `GetGuildInfoText` im Kampf. Im Fehlerlog stand 10-mal
  „Blocked: EldoUI tried to call the protected function UNKNOWN()“ aus `Points.lua:179`, in Westfall im Kampf.
  Das Roster meldet sich auch im Kampf. Seitdem liest das Modul im Kampf nichts. Roster und Stände holt es direkt
  nach dem Kampf (`PLAYER_REGEN_ENABLED`), auch wenn das Modul im Kampf angeht.
- Nicht umgesetzt: Daten aus den Saved Variables anderer DKP-Addons (z. B. MonolithDKP) lassen sich nicht lesen.
  Nur was in den Notizen steht, zählt.
- Zwei neue WoW-API-Namen in `tools/ci/globals.lua`: `GetGuildInfoText`, `UnitIsInMyGuild`.
- Test: `tools/raidloot/test_points.lua` (läuft in `tools/ci/check_all.sh tests`, 78 Prüfungen). Er lädt
  `Points.lua` ganz und die Zeilenbauer aus `RaidLoot/Core.lua`, mit nachgebautem Roster, Einheiten und Info-Bar.
  Im Kampf zählt er jeden Aufruf einer Gildenfunktion als Fehler.
- Im Spiel prüfen, in einer Gilde mit EPGP- oder DKP-Notizen:
  - Maus über ein Gildenmitglied: Zeile „EPGP“ oder „DKP“ mit dem Stand.
  - Info-Bar-Block „Guild points“ in einen Platz setzen: eigener Stand; der Tooltip listet die Gruppe bzw. die
    Gilde.
  - Mit importierten Soft-Reserves: Im Gegenstands-Tooltip steht hinter den Namen „[PR …]“ bzw. „[… DKP]“.
    „Post reservations“ postet ohne Stände.
  - Eine Weile kämpfen, während Gildenmitglieder sich an- und abmelden: keine Meldung „Blocked …“ mehr. Nach dem
    Kampf stimmen die Stände.
  - Danach `/eui errors`: keine Lua-Fehler.
- Im Spiel geprüft (15.11.2026): Seit dem Fix (PR #20) kein neuer „Blocked …“-Eintrag, in keiner Session bis
  Nr. 52, darunter mehrere mit Kampf. Ob sich dabei Gildenmitglieder im Kampf an- oder abgemeldet haben, ist
  nicht bekannt. Tooltip, Info-Bar-Block und Soft-Reserves sind noch nicht geprüft.

**QoL-Vorschläge (16.11.2026):** Der Nutzer fragte nach weiteren QoL-Features. Geprüft wurden alle 100 Module und
rund 45 übliche QoL-Funktionen per Codesuche. Das meiste gibt es schon: Auto-Reparatur, Grau verkaufen, „LÖSCHEN“
vorausfüllen, schnelles Plündern, Rang-Upgrades auf den Leisten, Haltbarkeit je Platz, Itemlevel in Taschen, Quest-EP
auf der EP-Leiste, Kartenaufdeckung, Screenshots bei Ereignissen, Ausrüstungssets, Fanfare-Hinweise bei vollen Taschen
und fälliger Reparatur. Übrig blieben B5 bis B12. Alle halten EldoUIs Regeln ein: Nichts handelt ohne Klick, außer es
ist eingeschaltet, und es werden keine geheimen Werte gelesen.

| Nr. | Idee | Beleg (Suche) |
|---|---|---|
| B5 | Leiste mit allen benutzbaren Questgegenständen der Taschen, per Klick oder Taste | ein Knopf, nur für die verfolgte Quest (`EldoUI/Modules/ObjectiveTracker.lua:30`) |
| B7 | Hinweis ab z. B. 3 freien Plätzen, dazu die fünf billigsten Gegenstände; ein Klick öffnet Blizzards Löschdialog | Fanfare meldet sich erst bei 0 freien Plätzen |
| B9 | Liste der Mitglieder außerhalb Eurer Zone oder Instanz, offline oder AFK; ein Klick setzt das Ziel (Hexer) | `GetRaidRosterInfo` kommt im Code nicht vor |
| B11 | Bei „beritten“ oder „Ihr müsst stehen“ (auch am Flugmeister) absitzen bzw. aufstehen | kein Modul wertet diese Fehlermeldungen aus |
| B12 | Ein Setwechsel im Kampf wird gemerkt und danach ausgeführt | heute nur eine Meldung (`EldoUI/Modules/Character.lua:2064`) |

Unsicher bei B11: Vielleicht sitzt Forever schon von selbst ab, und ob `Dismount()` ohne Klick erlaubt ist, zeigt nur
das Spiel. B12 handelt nach dem Klick, deshalb einschaltbar und standardmäßig aus.

Geprüft und verworfen:
- „Alles lernen“ beim Lehrer: EldoUI lehnt das bewusst ab, viele Käufe auf einen Klick gelten als Automatisierung
  (`EldoUI/Modules/Skins.lua:845`).
- Energie-Ticker: Die eigene Energie kann im Kampf geheim sein (`EldoUI/Modules/ClassPower.lua:16`).
- Unterbrechungs-Tracker mit Ansagen: Fremde Abklingzeiten sind geheim, und Chatzeilen schreibt EldoUI nur auf Klick.
- Herbeirufen oder Wiederbeleben automatisch annehmen: gegen die Fair-Play-Regel. Die Abfragen gibt es schon.
- Entfernung zum Ziel in Metern: Reichweiten-Abfragen sind im Kampf eingeschränkt. Das Fadenkreuz nutzt schon die
  Reichweitenprüfung des Spiels.

**B5 – Leiste mit Questgegenständen (umgesetzt):**
- Neu: Modul „Quest Item Bar“, deutsch „Questgegenstandsleiste“ (`Modules/QuestBar.lua`). Es steht in der
  Kategorie „Quality of Life“ und ist standardmäßig an.
- Jeder benutzbare Questgegenstand aus den Taschen bekommt einen Platz, höchstens 12. Ein Klick oder die Taste des
  Platzes benutzt ihn, über Blizzards sichere Aktion „item“. Ohne Klick oder Tastendruck passiert nichts.
- Welche Gegenstände, in der Reihenfolge der Taschen, jeder nur einmal:
  - Der Gegenstand, den das Questlog für eine Quest nennt (`GetQuestLogSpecialItemInfo`), solange er in der Tasche
    liegt. Bei einer Quest, die zum Abgeben bereit ist, nur wenn das Spiel ihn dafür behält
    (`showWhenComplete`) oder „Auch abgeschlossene Quests“ an ist. Sonst bleibt er weg, auch wenn er nach der
    Regel darunter passen würde, außer eine andere offene Quest nennt ihn.
  - Gegenstände, die das Spiel als Questgegenstand markiert (`GetContainerItemQuestInfo`) oder deren Klasse
    „Quest“ ist (12). Sie brauchen eine Benutzung: einen Zauber (`GetItemSpell`) oder einen Inhalt zum Öffnen
    (`hasLoot`). Reine Questbeute wie Felle bleibt weg, ebenso Tränke.
  - Gegenstände, die eine Quest beginnen, die Ihr nicht habt und nicht erledigt habt, mit dem „!“ der Taschen.
    Der Schalter „Gegenstände, die Quests beginnen“ nimmt sie heraus.
- Umschalt-Rechtsklick nimmt einen Gegenstand von der Leiste, mit einer Chatzeile. „Ausgeblendete Gegenstände
  zeigen“ holt alle zurück. Ein normaler Rechtsklick tut nichts, so wird beim Ausblenden nichts benutzt.
- Regeln:
  - Welcher Gegenstand auf welchem Platz liegt, welche Plätze zu sehen sind, Größe und Lage ändern sich nur
    außerhalb des Kampfs (`E:RunOutOfCombat`). Im Kampf behalten die Plätze ihre Gegenstände. Anzahl und
    Abklingzeit laufen weiter, ein verbrauchter Gegenstand wird grau. Am Kampfende liest die Leiste die Taschen neu.
  - Jede Antwort des Spiels läuft über `pcall`. Eine geheime Antwort zählt als „nicht da“ und wird nie verglichen.
  - Die Abklingzeit kommt aus der gemeinsamen Quelle des Kampf-Kits, wie bei der Verbrauchsgüterleiste.
  - Reichweite: rotes Symbol, wenn das Spiel „außer Reichweite“ meldet (`IsQuestLogSpecialItemInRange`). Das gibt es
    nur für die Gegenstände des Questlogs und nur, solange einer davon zu sehen ist (fünfmal pro Sekunde). Den Platz
    der Quest im Questlog liest es jedes Mal neu (`GetLogIndexForQuestID`), ebenso der Tooltip.
  - Leuchten nur für Gegenstände, die seit dem letzten Lesen in die Taschen kamen.
  - Bündel von Taschen- und Quest-Events werden einmal gelesen (0,2 s). Bringt ein Event dieselben Gegenstände,
    wird nichts neu gesetzt.
- Einstellungen: Starter, abgeschlossene Quests, „Ausgeblendete Gegenstände zeigen“, „Tasten belegen“
  (Tastenbelegungsmodus mit allen 12 Plätzen, auch wenn die Sichtbarkeitsregel die Leiste gerade versteckt), Tastentext, Größe, Abstand, vertikal, Anzahlen, Farbe außer
  Reichweite, Leuchten bei neuem Gegenstand, Masque, dazu die gemeinsamen Sichtbarkeitsregeln.
- Tastenbelegung: 12 Einträge „Questgegenstand 1 … 12“ unter „EldoUI Questgegenstandsleiste“ im Tastenbelegungsfenster
  (`Bindings.xml`). Platz 1 hält den ersten Questgegenstand in den Taschen, und so weiter.
- Mover „Questgegenstandsleiste“ unten rechts über dem Extra-Aktionsknopf, in der Gruppe „Aktionsleisten“ und im
  Kampfmodus. Gruppe und Kampfmodus gibt das Modul beim Anlegen des Movers an (`E:CreateMover`, `opts.group` und
  `opts.combat`). Die Kategorie setzt die Optionsseite in die Gruppe „Quality of Life“. So braucht es keine Einträge in
  `Movers.lua` oder `Config.lua`.
- Upstream-Dateien (D1): nur eine Zeile in `EldoUI.toc` und 12 Zeilen in `Bindings.xml`.
- Die Schaltfläche für Questgegenstand der Questverfolgung bleibt, wie sie ist. Sie hält den Gegenstand der verfolgten
  Quest auf ihrer eigenen Taste. Dieser Gegenstand steht deshalb auch auf der Leiste.
- Deutsche Texte in `EldoUI_Locale_deDE/Fork.lua` (23 Texte). „Keys“ heißt im Paket schon „Schlüssel“, deshalb
  heißt der Abschnitt „Keybinds“ („Tastenbelegungen“).
- Test: `tools/questbar/test_quest_bar.lua` (läuft in `tools/ci/check_all.sh tests`, 157 Prüfungen). Er lädt die
  Datei ganz, dazu EldoUIs echtes `Core/Safe.lua` (geheime Werte) und `Core/BagCache.lua` (Taschen). Ein sicherer
  Knopf, der im Kampf gezeigt, versteckt, verschoben oder mit einem Attribut versehen wird, zählt als blockiert, wie
  im Spiel. Geprüft werden:
  - Welche Gegenstände kommen, in welcher Reihenfolge, einer pro Gegenstand, höchstens 12.
  - Abgeschlossene Quests mit und ohne `showWhenComplete` und Schalter, Starter an und aus, erledigte und
    angenommene Quests.
  - Geheime oder fehlerhafte Antworten, die Leiste ohne Gegenstände und im Verschiebemodus.
  - Kampf: nichts blockiert, Änderungen kommen am Kampfende. Dieselben Gegenstände werden nicht neu gesetzt.
  - Ein Lesen pro Bündel von Events, Layout waagrecht und senkrecht.
  - Anzahl, Aufladungen, „!“, Tastentext, Abklingzeiten.
  - Reichweitenfarbe, auch abgeschaltet, nach einer neuen Quest im Kampf und ohne `GetLogIndexForQuestID`.
  - Leuchten nur für Neues, nicht nach „Ausgeblendete Gegenstände zeigen“, Schaltern oder spät geladenen Daten.
  - Umschalt-Rechtsklick auch im Kampf, Tasten belegen, Tooltip, Modul aus im Kampf, Masque.
  - Namen der Tastenbelegungen, Standards, Optionen.
  - Gegenprobe: Drei absichtlich eingebaute Fehler (kein Kampfschutz, keine Benutzung nötig, Reichweite trotz
    Schalter) lassen den Test fehlschlagen.
- Grenzen:
  - Gegenstände, die eine Quest braucht, die das Spiel aber weder als Questgegenstand markiert noch dem Questlog
    zuordnet, fehlen. Ein Beispiel wäre ein normales Verbrauchsgut, das man für eine Quest auf ein Ziel anwendet.
    Die Questdaten des Loot Guides kennen solche Gegenstände, würden aber auch Tränke und Stoffe bringen, die eine
    Quest nur abholt.
  - Ein Questgegenstand mit Benutzung, dessen Quest schon erledigt ist, bleibt, bis man ihn wegwirft oder ausblendet.
  - Reichweite gibt es nur für die Gegenstände des Questlogs. Für andere Gegenstände ist die Reichweitenabfrage im
    Kampf eingeschränkt.
- Im Spiel prüfen (nach einem Neustart des Spiels, siehe „Stand 16.11.2026“):
  - Mit einem benutzbaren Questgegenstand in der Tasche: Die Leiste erscheint unten rechts über dem Extra-Knopf, mit
    dem Symbol. Ein Klick benutzt ihn (z. B. auf ein Ziel oder einen Ort).
  - Ein Gegenstand, der eine Quest beginnt: Er steht mit „!“ auf der Leiste. Ein Klick öffnet das Questfenster.
  - Quest annehmen, Gegenstand plündern, Quest abgeben: Die Leiste passt sich an. Ein neuer Gegenstand leuchtet kurz.
  - Im Kampf einen Questgegenstand plündern: Er erscheint erst nach dem Kampf. Danach `/eui errors`: kein
    „Blocked …“-Eintrag.
  - Optionen › Questgegenstandsleiste › „Tasten belegen“: alle 12 Plätze sind zu sehen. Eine Taste auf Platz 1
    legen, speichern, danach benutzt die Taste den ersten Gegenstand, auch im Kampf. Dasselbe mit der
    Sichtbarkeit „Im Kampf“: Beim Belegen ist die Leiste trotzdem da.
  - Umschalt-Rechtsklick auf einen Platz: Der Gegenstand verschwindet, mit einer Chatzeile. „Ausgeblendete
    Gegenstände zeigen“ holt ihn zurück.
  - Mit einem Ziel außer Reichweite eines Questlog-Gegenstands: Das Symbol wird rot.
  - Tooltip: Bei Questlog-Gegenständen der Gegenstand mit Questbezug, sonst der Gegenstand aus der Tasche, darunter
    die Taste und der Hinweis zum Ausblenden.
  - `/eui move`: Die Leiste lässt sich unter „Aktionsleisten“ verschieben.
  - Danach `/eui errors`: keine Lua-Fehler.

**Gegenprüfung von B5 (16.11.2026, Wunsch des Nutzers):** Ein unabhängiger Prüf-Agent las den Commit `597197f` und
die EldoUI-Funktionen, die er nutzt, und ließ alle Prüfungen laufen (grün). Er fand keine Lua-Fehler, keine Änderung
an sicheren Knöpfen im Kampf, keine Benutzung ohne Klick und keine Probleme mit geheimen Werten. Die Befunde und
was daraus wurde (Korrekturen in `c64271e`, jeder Fall im Test, der gegen den alten Stand fehlschlägt):

| # | Befund | Schwere | Ergebnis |
|---|---|---|---|
| 1 | „Auch abgeschlossene Quests“ wirkungslos: Der Questlog-Gegenstand einer fertigen Quest kam über die Taschenregel (Klasse „Quest“ mit Benutzung) zurück. Der Test sah es nicht, weil sein Questlog-Gegenstand keine Questklasse hatte | mittel | behoben |
| 2 | Platz der Quest im Questlog veraltet im Kampf (neue Quest darüber, Überschrift zugeklappt): Reichweitenfarbe und Tooltip zeigten auf eine andere Quest | klein | behoben |
| 3 | „Tasten belegen“ bei einer Sichtbarkeitsregel wie „Im Kampf“: Der sichere Treiber versteckt die Leiste, nichts zum Zeigen | klein | behoben (`opts.condition`, `forceShow`) |
| 4 | Leuchten ohne neuen Gegenstand: nach „Ausgeblendete Gegenstände zeigen“ und Schaltern (bestätigt), beim Login mit spät geladenen Daten (plausibel) | klein | behoben: nur, was neu in die Taschen kam |
| 5 | Test: Einige Fälle (Modul aus, Einstellung im Kampf) laufen im Spiel so nicht, weil die Optionen und der Modulschalter bis zum Kampfende warten | klein | bleibt als Prüfung der eigenen Schutzabfragen, im Test vermerkt |

**Nachtrag zu B5 (PR #32, `bbc944e`, aus einer anderen Sitzung):** Die Knöpfe setzten ihre Aktion als `type1`. Das
liest das Spiel nur für den Linksklick ohne Umschalt, Strg oder Alt (`SecureTemplates.lua`). Eine Taste mit
Modifikator oder ein `/click` mit gehaltener Taste benutzte deshalb nichts, bei der Verbrauchsgüterleiste ebenso.
Jetzt `*type1` (Linksklick mit jedem Modifikator). Weder die eigene Prüfung noch die Gegenprüfung hatten das gesehen;
der Test von B5 bildet die Attributsuche des Spiels seither nach. Im Spiel prüfen: eine Taste mit Strg oder Umschalt
auf einen Platz der Questgegenstandsleiste legen, sie benutzt den Gegenstand.

**B7 – Hinweis bei fast vollen Taschen (umgesetzt):**
- Neu: `Modules/QoL/BagSpace.lua`, ein Teil des Moduls Quality of Life (Reiter „Sound und Sonstiges“, Abschnitt
  „Taschenplatz“), standardmäßig an.
- Sinken die freien Plätze der normalen Taschen auf die Grenze (Standard 3, einstellbar 1–10), kommt eine Karte
  „Taschen fast voll“: „Noch freie Plätze: 3. Platz schaffen: …“, darunter die fünf billigsten Gegenstände.
  - Graue Gegenstände stehen zuerst, dann geht es nach dem Verkaufswert des Stapels.
  - Jede Zeile nennt den Gegenstand, die Anzahl und den Verkaufspreis.
  - Die Karte bleibt 30 Sekunden, solange die Maus darauf ist auch länger. Ein Sound ist wählbar, standardmäßig keiner.
  - Es ist immer eine Karte (`closable`), auch ohne Zeilen. Sonst ginge sie als Toast in die Alarmleiste.
- Ein Klick auf eine Zeile legt den Gegenstand an den Mauszeiger (`PickupContainerItem`, die Stelle wird neu
  gesucht, falls er gewandert ist, aber nur in normalen Taschen und nur, wenn er noch jede Prüfung der Liste besteht).
  Ein Klick außerhalb der Taschen öffnet dann Blizzards eigenen Löschdialog, mit „LÖSCHEN vorausfüllen“ und der
  Quest-Zeile aus `Modules/SystemUI.lua`. Auf einem offenen Händlerfenster abgelegt wird er verkauft. Hängt schon
  etwas am Mauszeiger (auch Geld oder ein Zauber, `GetCursorInfo`), passiert nichts außer einem Hinweis. Beim ersten Mal pro Sitzung erklärt eine
  Chatzeile, was man jetzt tun kann.
- Abweichung vom Vorschlag („ein Klick öffnet Blizzards Löschdialog“):
  - Den Dialog öffnet nur das Spiel selbst, wenn ein Gegenstand außerhalb der Taschen abgelegt wird.
  - `StaticPopup_Show("DELETE_ITEM")` aus EldoUIs Code würde das Popup-System mit Taint belegen.
  - `DeleteCursorItem` mit einem eigenen Dialog würde selbst löschen und ist unter den Midnight-Regeln vielleicht
    gesperrt.
  - Deshalb zwei Klicks, und das Löschen bleibt ganz bei Blizzard.
- Wann die Karte kommt:
  - Einmal pro Abfall auf die Grenze oder darunter. Erst wenn wieder mehr als die Grenze frei war, kann sie erneut
    kommen.
  - Beim Login nicht: Die Plätze beim Login sind der Ausgangspunkt. Fällt danach ein Platz weg, kommt sie. In den
    ersten 5 Sekunden nach dem Login oder einem Ladebildschirm zählt kein Abfall, weil die Taschen dann vielleicht
    noch laden.
  - Nie im Kampf. Ein Abfall im Kampf zeigt die Karte am Kampfende, wenn die Taschen dann noch so voll sind. Eine
    Karte, die im Kampf zu sehen war, holt am Kampfende nach.
  - Solange die Karte zu sehen ist oder auf ihren Platz wartet, folgt sie den Taschen, ohne Sound. Ist wieder Platz,
    verschwindet sie, auch aus der Warteschlange (`E:NoticeQueue`, `E:DismissAlert`).
  - Nur der Schalter, die Grenze und ein neues Profil fangen neu an. Andere Einstellungen der QoL-Seite lassen den
    Stand, wie er ist. Eine Grenze unter den freien Plätzen nimmt die Karte weg.
  - `/eui room` und „Jetzt zeigen“ zeigen die Karte jederzeit, als „Platz schaffen“, auch mit ausgeschaltetem Hinweis.
    Sie folgt den Taschen, bleibt aber, wenn Platz ist. Kommt der Hinweis, nimmt er ihren Platz ein.
- Was „Platz schaffen“ weglässt:
  - Gegenstände, die eine Quest oder ein lernbares Rezept braucht (`E:IsItemProtected`, `Core/ItemProtect.lua`).
  - Gegenstände ohne Händlerpreis oder mit der Spielmarke „kein Wert“, gesperrte Gegenstände, Ausrüstungssets, noch
    erstattbare Käufe und die Liste „nie verkaufen“ des Händler-Moduls (auch wenn das Modul aus ist).
  - Essen, Trinken und Tränke, Reagenzien, Munition, Köcher, Rezepte, Questgegenstände und Schlüssel. Bei ihnen sagt
    der Händlerpreis wenig über den Wert.
  - Gegenstände in Berufs- und Spezialtaschen. Nur normale Taschen zählen, auch beim Zählen der freien Plätze.
- Regeln: Die Taschen werden über den gemeinsamen Bag-Cache gelesen, jede Antwort in `pcall`. Eine geheime Antwort zählt
  als „nicht da“. Ein eigener Event-Besitzer für das Kampfende, wie bei B6. Die Liste wird nur gebaut, wenn die Karte
  kommt oder zu sehen ist.
- „Minimal“ schaltet es aus. Deutsche Texte in `EldoUI_Locale_deDE/Fork.lua` (19 Texte), „zerstören“ wie im
  Löschdialog des Clients.
- Test: `tools/qol/test_bag_space.lua` (läuft in `tools/ci/check_all.sh tests`, 89 Prüfungen). Er lädt die Datei ganz,
  dazu EldoUIs echtes `Core/Safe.lua` und `Core/BagCache.lua`. Die Alarm-Warteschlange ist nachgebaut, soweit der Teil
  sie sieht: Alarmleiste für Meldungen ohne Zeilen, drei Karten, wartende und schließende Karten. Geprüft werden:
  - Wann die Karte kommt: Abfall auf die Grenze, nicht beim Login, einmal bis wieder Platz ist, nach dem Kampf, nicht
    wenn im Kampf wieder Platz wurde.
  - Die Karte folgt den Taschen, auch wartend, holt nach dem Kampf nach und verschwindet bei Platz, nicht beim Schließen.
  - Andere Einstellungen, neues Profil, niedrigere Grenze, die ersten Sekunden nach Login und Ladebildschirm.
  - Die Karte von `/eui room`, auch bei ausgeschaltetem Hinweis.
  - Welche Gegenstände die Liste nennt und in welcher Reihenfolge, höchstens fünf, und was sie weglässt.
  - Aufnehmen: nur mit leerem Mauszeiger (auch ohne Geld), von der aktuellen Stelle und nur ein Exemplar, das die
    Prüfungen besteht, der Hinweis einmal pro Sitzung.
  - Sound, Schalter, Grenze, neues Profil, Modul aus, `/eui room`, „Jetzt zeigen“, Standards, „Minimal“, Optionen.
  - Gegenprobe: Drei absichtlich eingebaute Fehler (Karte im Kampf, geschützte Gegenstände in der Liste, Karte beim
    Login) lassen den Test fehlschlagen.
- Grenzen:
  - „Billig“ heißt Händlerpreis. Ein Gegenstand, der im Auktionshaus viel wert ist (z. B. ein seltener Stoff), kann
    trotzdem auf der Liste stehen.
  - Gegenstände, deren Daten der Client noch nicht geladen hat, fehlen in der Liste, bis sie geladen sind.
- Im Spiel prüfen (nach einem Neustart des Spiels):
  - Taschen bis auf 4 freie Plätze füllen, dann einen Gegenstand plündern. Erwartung: Die Karte „Taschen fast voll“
    mit „Noch freie Plätze: 3.“ und bis zu fünf Gegenständen, graue zuerst.
  - Noch einen Gegenstand plündern, während die Karte zu sehen ist: Die Zahl und die Liste ändern sich, keine zweite
    Karte.
  - Auf eine Zeile klicken: Der Gegenstand hängt am Mauszeiger, beim ersten Mal mit einer Chatzeile. Außerhalb der
    Taschen klicken: Blizzards Dialog „… zerstören?“ erscheint. Abbrechen legt ihn zurück.
  - Bei einem Händler eine Zeile anklicken, dann auf das offene Händlerfenster klicken: verkauft.
  - Questgegenstände, Essen, Munition und Gegenstände eines Ausrüstungssets stehen nie auf der Liste.
  - Im Kampf plündern, bis die Grenze erreicht ist: Die Karte kommt erst nach dem Kampf.
  - Platz schaffen, bis wieder 4 frei sind: Die Karte verschwindet. Beim nächsten Abfall kommt sie wieder.
  - `/eui room`: Die Karte „Platz schaffen“ kommt auch mit vielen freien Plätzen und bleibt, wenn man etwas verkauft.
  - Danach `/eui errors`: keine Lua-Fehler.

**Gegenprüfung von B7 (16.11.2026, Wunsch des Nutzers):** Ein unabhängiger Prüf-Agent las den Commit `86fba91` und
die EldoUI-Funktionen, die er nutzt, und ließ alle Prüfungen laufen (grün). Er fand keine Lua-Fehler, nichts, was ohne
Klick löscht, verkauft oder bewegt, keine geschützten Aufrufe und keine Blizzard-Dialoge. Die Befunde und was daraus
wurde (Korrekturen in `fc8f1ee`, jeder Fall im Test, der gegen den alten Stand fehlschlägt):

| # | Befund | Schwere | Ergebnis |
|---|---|---|---|
| 1 | Die Karte von `/eui room` verschwand beim nächsten Taschen-Event, wenn mehr als die Grenze frei war | mittel | behoben: bleibt, Titel „Platz schaffen“ |
| 2 | Leere Liste: Die Meldung ging ohne Zeilen als Toast in die Alarmleiste, die alte Karte blieb mit toten Zeilen | mittel | behoben (`closable`) |
| 3 | Eine wartende Karte wurde nie weggenommen oder aktualisiert und kam später mit alter Liste. Eine Karte, die gerade schließt, zählte als sichtbar | mittel | behoben (`E:NoticeQueue`) |
| 4 | Jede Einstellung der QoL-Seite setzte den Hinweis zurück, er konnte erneut kommen. Eine niedrigere Grenze ließ die Karte stehen | klein | behoben |
| 5 | Ein gewanderter Gegenstand wurde ohne die Filter gesucht (Ausrüstungsset, Berufstasche, gesperrt …) | klein | behoben |
| 6 | Eine sichtbare Karte wurde nach dem Kampf nicht aktualisiert | klein | behoben |
| 7 | Karte beim Login, wenn die Taschen erst spät geladen sind (plausibel) | klein | abgesichert: 5 Sekunden nach Login und Ladebildschirm |
| 8 | Geld oder ein Zauber am Mauszeiger wurde nicht erkannt (plausibel) | klein | behoben (`GetCursorInfo`) |
| 9 | Texte: Titel bei `/eui room`, Begründung der leeren Liste unvollständig, „klickt auf einen Händler“ statt Händlerfenster | klein | behoben |
| 10 | Test: Der Nachbau zeigte jede Karte sofort, Alarmleiste und Warteschlange fehlten | klein | behoben |

**B7 und EldoUI 0.7.3000 (16.11.2026, offen: Entscheidung des Nutzers):** EldoUI warnt jetzt selbst vor vollen
Taschen, aber nur, solange Taschen- oder Lootfenster offen sind: Die Fußzeile der Taschen färbt sich ab 5 freien
Plätzen (`Modules/Bags/Core.lua`), der Info-Bar-Block „Bags“ ab 4, ein Pfeil markiert ab 5 freien Plätzen den
billigsten Stapel (`Modules/Bags/Marks.lua`, Option `lowestValueMark`), und das Lootfenster nennt ihn, wenn kein
Platz mehr ist (`Modules/Loot.lua`). B7 bleibt, denn es meldet sich auch bei geschlossenen Taschen, mit Liste,
Klick an den Mauszeiger, `/eui room` und Warten bis nach dem Kampf. Beide laufen aber gleichzeitig und können
verschiedene Gegenstände nennen: B7 lässt Verbrauchsgüter, Reagenzien, Munition, Rezepte und Schlüssel weg, EldoUI nur
Quest-, geschützte, Set-, erstattbare und unverkäufliche Gegenstände. Möglich wäre, B7 auf EldoUIs Auswahl
(`Bags:LowestValueItem`) und Platzzählung (`E.BagCache:GeneralSlots`, meldet eine unlesbare Tasche als unbekannt statt
0 frei) zu stellen.

**B12 – Ausrüstungsset nach dem Kampf anlegen (umgesetzt):**
- Geändert: `Modules/Character.lua`, Abschnitt „Gear sets“, der einzige Ort, an dem EldoUI Sets wechselt (Set-Knöpfe im
  Charakterfenster, Menü des Infoleisten-Blocks „Ausrüstung“).
- Neuer Schalter „Nach dem Kampf anlegen“ unter Charakter › Ausrüstungssets, standardmäßig aus. Er handelt später für
  den Spieler und ist deshalb in der Liste als `acts` markiert.
- Klickt man an, solange der Kampf läuft:
  - Das Set wird gemerkt. Eine Meldung in Grün sagt: „EldoUI: Schaden wird angelegt, sobald der Kampf endet. Ein zweiter
    Klick darauf behält Eure Ausrüstung.“
  - Nur der letzte Klick zählt. Ein zweiter Klick auf dasselbe Set oder ein Klick auf das getragene Set nimmt es zurück
    („EldoUI: kein Setwechsel nach dem Kampf.“). Ein Klick auf das getragene Set ohne gemerktes Set tut nichts.
  - Am Kampfende (`PLAYER_REGEN_ENABLED`) wird es angelegt, mit der Chatzeile „Nach dem Kampf: Schaden angelegt.“
  - Ist man dann tot oder stellt sich tot, wartet es, bis man wieder lebt und steht (`PLAYER_ALIVE`,
    `PLAYER_UNGHOST`, beim Totstellen die Auren des Spielers) und außerhalb des Kampfs ist. Ein Klick, während man
    außerhalb des Kampfs tot ist, wird genauso gemerkt („… wird angelegt, sobald Ihr wieder lebt“).
  - Beginnt ein neuer Kampf, bevor es angelegt werden konnte, verfällt es mit „kein Setwechsel nach dem Kampf“. So kommt
    es nie nach einem späteren, fremden Kampf. Eine Wiederbelebung im Kampf zählt dabei als neuer Kampf.
  - Ein Klick außerhalb des Kampfs gilt vor dem gemerkten Set.
  - Ist der Schalter inzwischen aus, das Charakter-Modul aus, das Set gelöscht oder schon angelegt, passiert nichts.
    Schalter und Modul nehmen es sofort weg. Nach einem Neuladen ist nichts mehr gemerkt.
  - Die Chatzeile kommt nur, wenn das Spiel den Wechsel angenommen hat (Antwort von `UseEquipmentSet`).
  - Der Infoleisten-Block „Ausrüstung“ nimmt dafür im Kampf Klicks an (`combatClick`). Sein Menü ist EldoUIs eigenes.
- Anzeige: Das gemerkte Set hat an der Set-Leiste einen gelben Rand. Sein Tooltip sagt „Wird angelegt, sobald der Kampf
  endet.“ Der Tooltip des Infoleisten-Blocks zeigt „Nach dem Kampf: Schaden“. Die Klick-Hinweise lauten bei
  eingeschaltetem Schalter „anlegen (im Kampf: sobald er endet)“.
- Ohne den Schalter bleibt alles wie vorher („Ausrüstungssets wechseln nur außerhalb des Kampfes“).
- Regeln: Die Events laufen nur, solange ein Set gemerkt ist, unter einem eigenen Besitzer. Set-Infos werden in `pcall`
  gelesen; eine geheime Antwort ändert nichts. `UseEquipmentSet` läuft weiter in `pcall`.
- Die Beschreibung des Abschnitts hieß „… nichts wird für später vorgemerkt“. Sie heißt jetzt nur „Jeder Wechsel
  geschieht außerhalb des Kampfes“.
- Upstream-Datei (D1): `Character.lua`, gut 100 Zeilen im Abschnitt „Gear sets“ und zwei Zeilen bei Standards und
  Optionen. Deutsche Texte in `EldoUI_Locale_deDE/Fork.lua` (10 Texte).
- Test: `tools/character/test_gear_after_combat.lua` (läuft in `tools/ci/check_all.sh tests`, 57 Prüfungen). Er schneidet
  den Abschnitt „Gear sets“ sowie `OnDisable` und `OnProfileChanged` aus `Character.lua` heraus und lässt sie unverändert
  laufen. Geprüft werden:
  - Schalter aus: wie vorher.
  - Schalter an: gemerkt, der letzte Klick zählt, zurücknehmen, Klick außerhalb des Kampfs gilt, einmal am Kampfende.
  - Tot, Geist, wiederbelebt, im Kampf wiederbelebt, tot außerhalb des Kampfs, Totstellen, ein neuer Kampf, geheime
    Antworten zum Tod und zum Totstellen.
  - Schalter, Modul oder Profil aus, Set gelöscht oder schon angelegt, das Spiel lehnt ab (Fehler oder `false`), ein
    geheimer Set-Name. Der Block „Ausrüstung“ nimmt Klicks im Kampf an.
  - Events nur, solange ein Set gemerkt ist. Rand, Tooltips, Hinweise, Menü, Standard und Option.
  - Gegenprobe: Drei absichtlich eingebaute Fehler (Anlegen im Tod, Merken ohne Schalter, kein Zurücknehmen beim zweiten
    Klick) lassen den Test fehlschlagen.
- Offen, nur im Spiel zu klären: ob `C_EquipmentSet.UseEquipmentSet` unter den Midnight-Regeln auch aus einem Event
  ohne Tastendruck läuft. Andere Addons wechseln Sets seit Langem nach dem Kampf. Klappt es nicht, gibt es keinen
  Lua-Fehler, und die Chatzeile bleibt aus. Gibt das Spiel stattdessen „blockiert“ aus, steht das unter `/eui errors`.
- Im Spiel prüfen (`/reload` reicht):
  - Charakter › Ausrüstungssets › „Nach dem Kampf anlegen“ einschalten. Zwei Sets im Ausrüstungsmanager haben.
  - Im Kampf auf das andere Set klicken (Set-Leiste am Charakterfenster oder Infoleisten-Block „Ausrüstung“). Erwartung:
    die grüne Meldung, das Set bekommt einen gelben Rand.
  - Kampf beenden. Erwartung: Das Set wird angelegt, mit der Chatzeile „Nach dem Kampf: … angelegt.“
  - Im Kampf zweimal auf dasselbe Set klicken: Die zweite Meldung sagt „kein Setwechsel nach dem Kampf“, nach dem Kampf
    bleibt die Ausrüstung.
  - Im Kampf sterben, während ein Set gemerkt ist: Nach dem Wiederbeleben wird es angelegt.
  - Schalter aus: Ein Klick im Kampf sagt wie bisher „Ausrüstungssets wechseln nur außerhalb des Kampfes“.
  - Im Kampf den Infoleisten-Block „Ausrüstung“ anklicken: Das Menü öffnet sich, ein Set darin wird gemerkt.
  - Danach `/eui errors`: keine Lua-Fehler.

**Gegenprüfung von B12 (16.11.2026, Wunsch des Nutzers):** Ein unabhängiger Prüf-Agent las den Commit `9cdd6aa` und
die EldoUI-Funktionen, die er nutzt, und ließ alle Prüfungen laufen (grün). Er fand keine Lua-Fehler, keinen Wechsel im
Kampf, kein doppeltes Anlegen und nichts ohne Schalter. Die Befunde und was daraus wurde (Korrekturen in `dd84be6`,
jeder Fall im Test, der gegen den alten Stand fehlschlägt):

| # | Befund | Schwere | Ergebnis |
|---|---|---|---|
| 1 | Ein gemerktes Set wurde auch angelegt, nachdem das Charakter-Modul ausgeschaltet war: Die eigenen Events nimmt der Modulschalter nicht mit | mittel | behoben |
| 2 | Der Block „Ausrüstung“ nahm im Kampf keine Klicks an (`combatClick` fehlte), Hinweis und Option versprachen es | mittel | behoben |
| 3 | Die Chatzeile kam auch, wenn das Spiel den Wechsel ablehnte (Antwort `false`) | klein–mittel | behoben |
| 4 | Ein Klick, während man außerhalb des Kampfs tot ist, verwarf das gemerkte Set (plausibel) | klein | behoben: wird gemerkt |
| 5 | Den Schalter ausschalten nahm das gemerkte Set erst beim nächsten Event weg | klein | behoben |
| 6 | Ein gemerktes Set lief nie ab; bei Totstellen konnte es nach einem späteren Kampf kommen (plausibel) | klein | behoben: Totstellen wie tot, ein neuer Kampf verwirft es |
| 7 | Test: Block im Kampf, Modul aus, Profilwechsel und Ablehnung per `false` fehlten | klein | behoben |

**B6 – Signal, wenn Essen und Trinken fertig sind (umgesetzt):**
- Neu: `Modules/QoL/MealDone.lua`, ein Teil des Moduls Quality of Life (Reiter „Sound and misc“, Abschnitt „Essen
  und Trinken“), standardmäßig an.
- Beim Essen oder Trinken: ein Sound und ein Blinken des Spiels in der Taskleiste, sobald voll ist, was die Mahlzeit
  füllt. Bei Essen ist das die Gesundheit, bei Getränken das Mana und bei Rationen beides. Eine Klasse ohne Mana bekommt
  das Signal beim Trinken sofort.
- Essen, das „Satt“ gibt, wartet außerdem die 10 Sekunden, die der Buff braucht. Sie zählen ab dem Beginn dieses
  Essens, auch wenn vorher schon getrunken wurde.
- Nach dem Beginn oder einer Änderung der Mahlzeit wartet es eine Sekunde. So zählen Essen und Trinken aus einem
  Tastendruck (Makro) als eine Mahlzeit.
- Ein Signal pro Mahlzeit. Kommt zu einer fertigen Mahlzeit ein Getränk oder Essen mit „Satt“ dazu, gibt es ein
  neues Signal, sobald auch das fertig ist.
- Einstellungen: Schalter, Sound (Standard „Chime“, „Keiner“ für Stille), Blinken in der Taskleiste, Knopf „Test“.
  „Minimal“ schaltet es aus.
- Was als Mahlzeit zählt:
  - Auren mit dem Namen, den der Client für Essen (433) und Trinken (430) liefert, in jeder Sprache. Alle Ränge
    von normalem Essen und Wasser tragen diesen Namen.
  - Die Benutzungs-Zauber, die die Verbrauchsleiste kennt (`USE_SPELLS`, `BUFF_FOOD_SPELLS` in
    `Modules/ConsumableBar.lua`): Rationen, Kekse sowie die nahrhaften Speisen und Getränke von Forever. Die Leiste
    leiht nur ihre Listen und darf aus sein.
- Regeln: Im Kampf liest es nichts. Auren laufen über `C_UnitAuras` in pcall. Geheime Auren, Gesundheit oder Mana
  zählen als „nicht lesbar“ und werden nie verglichen. Es hört auf `UNIT_AURA` nur für Euch und liest am Kampfende
  einmal neu (`PLAYER_REGEN_ENABLED`, eigener Besitzer, weil Tweaks dieses Event schon für das Modul belegt). Nur
  während einer Mahlzeit schaut es viermal pro Sekunde nach, am gemeinsamen Ticker.
- Die Namen von Essen und Trinken liest es einmal pro Sitzung. Ohne Zauber-API nimmt es wie die Verbrauchsleiste die
  englischen Namen.
- Deutsche Texte in `EldoUI_Locale_deDE/Fork.lua`.
- Test: `tools/qol/test_meal_done.lua` (läuft in `tools/ci/check_all.sh tests`, 76 Prüfungen). Er lädt die Datei
  ganz, mit deutschen Namen für Essen und Trinken. Geprüft werden:
  - Welche Auren zählen, geheime nie, ohne die Listen der Verbrauchsleiste nur die Namen, ohne Zauber-API die
    englischen. Die Namen werden einmal gelesen.
  - Gesundheit, Mana, Rationen, eine Klasse ohne Mana, „Satt“ nach 10 Sekunden ab dem Essen, auch nach einem Getränk
    und nach einer schon fertigen Mahlzeit.
  - Essen und Trinken aus einem Tastendruck geben ein Signal.
  - Ein Signal pro Mahlzeit, ein neues für ein dazukommendes Getränk.
  - Eine Mahlzeit, die im Kampf endet: Am Kampfende ist sie weg, ohne spätes Signal, und die nächste Mahlzeit bekommt
    ihres.
  - Nichts im Kampf, nichts bei geheimen Werten, nichts nach frühem Aufstehen.
  - Der Ticker läuft nur während einer Mahlzeit.
  - Schalter, Sound, Blinken, Test-Knopf, Modul aus.
- Grenze: Ist das Spiel im Hintergrund, spielt es Sounds nur mit seiner Einstellung „Sound im Hintergrund“. Das
  Blinken in der Taskleiste kommt immer.
- Im Spiel prüfen (nach einem Neustart des Spiels, siehe „Stand 16.11.2026“):
  - Mit halber Gesundheit Brot essen. Erwartung: Ein Glockenton und das Blinken, sobald die Gesundheit voll ist,
    und nur einmal.
  - Als Klasse mit Mana Wasser trinken: das Signal bei vollem Mana. Essen und Trinken zusammen: ein Signal für das
    Essen, ein zweites für das Mana.
  - Essen, das „Satt“ gibt, bei voller Gesundheit: das Signal erst nach etwa 10 Sekunden, wenn „Satt“ da ist.
  - Eine Ration oder nahrhaftes Essen von Forever: Signal, wenn beides voll ist.
  - Vor dem Ende aufstehen: kein Signal.
  - Erst trinken, dann Essen mit „Satt“ dazu: das Signal erst, wenn „Satt“ da ist.
  - Beim Essen angegriffen werden, kämpfen, danach normal regenerieren: kein Signal.
  - `/eui qol` → Sound und Sonstiges → „Essen und Trinken“ → „Test“: Ton und Blinken.
  - Danach `/eui errors`: keine Lua-Fehler.

**B8 – Quest-EP im Questlog (umgesetzt):**
- Neu: `Modules/QoL/QuestXP.lua`, ein Teil des Moduls Quality of Life (Reiter „Quests“, Abschnitt „Belohnungen“),
  standardmäßig an. Questie zeigt die EP beim Nutzer nicht an, nur die EP-Leiste hat sie (gelb).
- Hinter jedem Questtitel im Questlog stehen die EP fürs Abgeben: „[24] The Collector  +1.250 EP“, in der Farbe der
  fertigen Quests auf der EP-Leiste (Erfahrungs- und Rufleisten › „Farbe für Quest-EP“, Standard gelb). Die Zahl
  kommt vom Spiel (`GetQuestLogRewardXP`), wie bei der EP-Leiste (`Modules/StatusBars.lua:98`), mit dem
  Tausendertrenner des Clients.
- Keine EP: auf der Höchststufe, bei gesperrter EP (`IsXPUserDisabled`), bei Quests ohne EP, bei geheimer oder
  fehlerhafter Antwort.
- Der Questlog ist die Questliste der Weltkarte (`QuestScrollFrame`), wie bei Quest Marks
  (`Modules/QuestTint.lua`). Blizzard schreibt jeden Titel bei jedem Update neu und passt die Zeile vorher an den
  Titel an. Darum:
  - Die EP kommen nur dazu, wenn der Titel dabei nicht mehr Zeilen braucht. Sonst weicht das Ende des Titels einem
    „...“.
  - Bliebe vom Titel fast nichts übrig (unter 10 Bytes samt „[24] “), bleibt er ohne EP.
  - Ein Titel, den das Spiel schon abschneidet, wird genauso gekürzt, damit die EP lesbar bleiben.
- Post-Hook auf `QuestLogQuests_Update`, auch wenn die Weltkarte später lädt. Nur Text: Kein Blizzard-Frame bekommt
  ein Feld. Was EldoUI geändert hat, steht in einer schwachen Tabelle. Ausgeschaltet bekommt jeder Titel Blizzards
  Text zurück, aber nur, wenn dort noch EldoUIs Text steht.
- Verträgt sich mit Quest Marks, das bei Farbenblindheit „[24 schwer]“ in denselben Titel schreibt. Dessen Wort
  kommt zuerst hinein (`AddDifficultyWord`, wirkt nur einmal), dann wird gemessen, egal welcher Hook zuerst läuft. Die
  EP am Ende werden erkannt und nicht doppelt gesetzt, auch nach einem Farbwechsel.
- Das Häkchen einer verfolgten Quest setzt Blizzards Zeilencode in Retail direkt hinter den Titel (bei dessen
  Breite). Steht es dort (ein Anker am Titel, höchstens 6 Punkte hinter dem Ende), rückt es hinter die EP und beim
  Ausschalten zurück. Jede andere Anordnung bleibt unberührt.
- Der Schalter folgt Blizzard UI › „World map and quest log“ › Improve. „Minimal“ schaltet ihn aus.
- Deutsche Texte in `EldoUI_Locale_deDE/Fork.lua` („+%s EP“, „EP im Questlog“).
- Test: `tools/qol/test_quest_xp.lua` (läuft in `tools/ci/check_all.sh tests`, 54 Prüfungen). Er lädt die Datei ganz.
  Ein Titel ist dort ein Textfeld, das nach einer festen Zahl Zeichen umbricht. Geprüft werden:
  - EP einmal, auch wenn der Hook ohne neues Schreiben von Blizzard läuft.
  - Quests ohne EP, mit geheimer Antwort oder einem Fehler bleiben, wie sie sind.
  - Lange Titel bekommen ein „...“ und behalten den Farbcode. Fast leere Titel bleiben ohne EP. Abgeschnittene
    Titel werden gekürzt.
  - Farbe aus der EP-Leiste, kaputte oder fehlende Farbe.
  - Das Wort von Quest Marks, auch wenn dessen Hook später läuft; ein Fehler dort wird gemeldet.
  - Das Häkchen rückt mit und zurück, andere Anker bleiben.
  - Höchststufe, gesperrte EP, Schalter aus, Blizzard-Schalter aus, Modul aus: Blizzards Text zurück. Ein Titel, den
    Blizzard inzwischen neu geschrieben hat, bleibt unberührt.
  - Ein Hook, Standards, „Minimal“, Optionen.
- Im Spiel prüfen (nach einem Neustart des Spiels):
  - Questlog öffnen (L). Erwartung: hinter jedem Titel „+… EP“ in Gelb. Zwei Quests mit verschiedener Belohnung
    zeigen verschiedene Zahlen (sonst liest das Spiel nur die ausgewählte Quest). Die Summe der fertigen Quests passt
    zum gelben Teil der EP-Leiste.
  - Eine verfolgte Quest: Das Häkchen steht hinter den EP, nicht darauf.
  - Gehen die gelben EP neben gelben Questtiteln unter, die Farbe unter Erfahrungs- und Rufleisten › „Farbe für
    Quest-EP“ ändern oder Bescheid geben.
  - Eine Quest mit langem Titel: Die Zeile wird nicht höher und überlappt nicht. Das Ende des Titels endet auf „...“,
    die EP bleiben sichtbar.
  - Quests verfolgen, abschließen, abbrechen, Zonen auf- und zuklappen: EP stehen nie doppelt da.
  - Optionen › Quality of Life › Quests › „EP im Questlog“ aus: Die EP verschwinden sofort.
  - Danach `/eui errors`: keine Lua-Fehler.

**B10 – Wowhead-Links in der Spielsprache (umgesetzt):**
- Bisher führten die Wowhead-Links (Strg+Alt-Klick im Chat, `/eui wowhead`, „Wowhead-Link kopieren“ im Loot Guide
  und im Questmenü) nur auf die englischen Seiten.
- Neu in `Modules/QoL.lua` (Reiter „Interface“, Abschnitt Wowhead): Auswahl „Wowhead-Sprache“. Standard
  „Spielsprache“ folgt dem Client, so heißen Dinge auf der Seite wie im Spiel. Wählbar sind auch Englisch, Deutsch,
  Français, Español, Italiano, Português, Русский, 한국어 und 简体中文.
- Adresse: `https://www.wowhead.com/classic/de/item=19019`, mit „Retail“ `https://www.wowhead.com/de/…`.
  Clients ohne eigene Wowhead-Sprache (zhTW, Englisch) bekommen die englische Seite. Ein unbekannter Wert ebenfalls,
  nie ein kaputter Pfad.
- Alte Profile ohne die Einstellung verhalten sich wie „Spielsprache“: Beim Nutzer kommt also ab jetzt die deutsche
  Seite.
- Deutsche Texte in `EldoUI_Locale_deDE/Fork.lua`.
- Test: `tools/qol/test_wowhead.lua` (läuft in `tools/ci/check_all.sh tests`, 48 Prüfungen). Er schneidet den
  Adressteil aus `QoL.lua` heraus. Geprüft werden:
  - Spielsprache für jeden Client und gewählte Sprachen.
  - Classic und Retail, alte Profile, ein unbekannter Wert.
  - Jede Sprache der Auswahl ergibt ihren eigenen Pfad.
  - Kopierfeld und Loot Guide nutzen dieselbe Adresse.
- Im Spiel prüfen: Strg+Alt-Klick auf einen Gegenstandslink im Chat. Erwartung: Das Kopierfeld zeigt
  `https://www.wowhead.com/classic/de/item=…`. Im Browser öffnet sich die deutsche Seite mit dem deutschen Namen.

**Gegenprüfung von B6, B8 und B10 (16.11.2026, Wunsch des Nutzers):** Ein unabhängiger Prüf-Agent las den Commit
`7213a3d` und ließ alle Prüfungen laufen. Er fand keine Lua-Fehler und keine Probleme mit geheimen Werten oder Taint.
Die Befunde und was daraus wurde (Korrekturen in `f90e7f1`):

| # | Befund | Schwere | Ergebnis |
|---|---|---|---|
| 1 | B6: „Satt“-Wartezeit zählte ab Beginn der Mahlzeit, nicht ab dem Essen (erst trinken, dann Buff-Essen: Signal zu früh) | mittel | behoben |
| 2 | B6: Endete die Mahlzeit im Kampf, blieb ihr Zustand stehen (spätes Fehlsignal, oder die nächste Mahlzeit ohne Signal) | mittel | behoben |
| 3 | B8: Das Wort von Quest Marks kam nach dem Messen dazu, wenn dessen Hook später lief | klein | behoben |
| 4 | B8: Das Häkchen verfolgter Quests sitzt an der alten Titelbreite (plausibel, Retail-Code) | klein | behoben, im Spiel prüfen |
| 5 | B8: Farbe fest verdrahtet statt „Quest XP color“ der EP-Leiste | klein | behoben |
| 6 | B8: EP bei gesperrter EP-Gewinnung | klein | behoben |
| 7 | B6: Beschriftung „Signal, wenn Ihr satt seid“ verwechselbar mit dem Buff „Satt“ und mit Anrede | klein | behoben: „Signal, wenn die Mahlzeit fertig ist“ |
| 8 | B6: keine Ersatznamen ohne Zauber-API, Namen bei jeder Aura neu gelesen | klein | behoben |
| 9 | B6: Makro mit Essen und Trinken bei voller Gesundheit gab ein Signal zu viel | klein | behoben (eine Sekunde Wartezeit) |
| 10 | B8: Liest `GetQuestLogRewardXP(questID)` wirklich die genannte Quest? | klein | im Spiel prüfen (die EP-Leiste nutzt denselben Aufruf) |

**Schon vorhanden:** Damage-Meter-Skin, Encounter Timeline, Fokus- und Boss-Frames, frei belegbare Datenleisten
(`RegisterDataText`), Profile pro Charakter und Talentgruppe, Nameplate-Farbregeln, 67 Tags, Aurenfilter-Editor,
Cooldown-Text, Chat kopieren, Gamepad, Spell-/Item-IDs im Tooltip, Quest-Automatik, Reichweiten-Fade.

**Bewusst ausgeschlossen:** Arena-Frames (keine Arenen in Forever), Gegner-Auren auf Nameplates,
Inspect-Anfragen, automatische Loot-Verteilung.

## C – Verbesserungen bestehender Features

- **Masque nur für Aktionsleisten** (`EldoUI/Modules/ActionBars/Buttons.lua:792`). Auren, Combat HUD,
  ConsumableBar, Totems, Quickdraw: kein Masque. Aufwand klein–mittel.
  - **Umgesetzt (C1, teilweise):**
    - Neue Schalter „Use Masque“: Verbrauchsleiste, Totemleiste mit Abklingleiste (ein Schalter für beide) und
      Quickdraw haben je einen. Sie sind standardmäßig aus, wirken nach einem Reload und erscheinen, wenn Masque
      geladen ist.
    - Masque-Gruppen: „EldoUI“ › Consumable Bar, Totem Bar, Shaman Cooldowns, Quickdraw. Die Namen sind fest
      englisch, weil Masque die Skin-Einstellungen unter dem Namen speichert. Ein Sprachwechsel verlöre sie sonst.
    - Neu: `Core/Masque.lua` mit
      - `E:MasqueButton`: `group:AddButton` mit den Teilen des Buttons (Icon, Cooldown, Count, HotKey,
        Highlight). Scheitert der Aufruf, bleibt EldoUIs Aussehen.
      - `E:MasqueReSkin`: nachdem ein Modul seine Buttons in der Größe gesetzt hat. Masque passt den Skin an die
        Größe an, die es beim Skinnen vorfindet.
      - `E:Masqued`.
    - `Core/Media.lua`: `E:DropTemplate` nimmt einem Masque-Button den `E:SetTemplate`-Rahmen dauerhaft weg.
      Sonst käme er zurück, denn die Totemleisten rufen bei jedem Apply `E:SetTemplate` auf, und auch
      Themenwechsel und neue UI-Skalierung bauen Rahmen neu.
    - Was EldoUI bleibt: Bei den Totems das Gedrückt-Aussehen in der Akzentfarbe und die Elementkante. Bei
      Quickdraw Beschriftung, Leuchten des gewählten Eintrags und der Untermenü-Pfeil.
    - Nicht umgesetzt:
      - Auren: `Modules/Auras.lua` hat eigene Icons nur für Waffenverzauberungen (Rückfall, wenn der Client
        keine Verzauberungs-Plätze hat). Alles andere sind Blizzards Buff-Buttons, die EldoUI nur einrahmt.
        Masque auf fremden Buttons, die Blizzard selbst neu aufbaut, lässt sich ohne Spiel nicht prüfen.
      - Combat HUD: Die Abklingzeit-Icons (`CombatHUD/CooldownRows.lua`) sind Frames, keine Buttons. Sie setzen
        Icon-Punkte und -Ausschnitt bei jedem Stil neu (`StyleIcon`) und tragen zwei Leucht-Ebenen. Ob Masque mit
        Frames arbeitet und wie sich die Leuchteffekte mit einem Skin vertragen, zeigt nur das Spiel.
    - Test: `tools/masque/test_masque.lua` (läuft in `tools/ci/check_all.sh tests`, 42 Prüfungen). Er lädt
      `Core/Masque.lua` ganz, dazu die Rahmen-Teile von `Core/Media.lua` und die echten Button-Funktionen der
      drei Module. Die Gegenseite ist ein Modell von Masques öffentlicher API. Geprüft wird:
      - Ohne Masque oder mit Schalter aus ändert sich nichts.
      - Mit beidem kommt jeder Button einmal in seine Gruppe, mit seinen Teilen.
      - Der Rahmen bleibt weg nach Neuzeichnen, Themenwechsel und neuer UI-Skalierung. Andere Rahmen bleiben
        unberührt.
      - Ein scheiternder Masque-Aufruf lässt EldoUIs Aussehen stehen.
    - Im Spiel prüfen, mit Masque und einem Skin:
      - Verbrauchsleiste › „Use Masque“ an, `/reload`. Erwartung: Die Buttons tragen den Masque-Skin, Masque zeigt
        unter EldoUI die Gruppe „Consumable Bar“, Anzahl und Abklingzeit sind lesbar.
      - Buttongröße der Leiste ändern: Der Skin passt sich an.
      - Dasselbe für die Totemleiste (als Schamane, mit Auswahlmenüs und Abklingleiste) und für Quickdraw (Menü
        öffnen).
      - UI-Skalierung ändern: Kein dunkler EldoUI-Rahmen erscheint über dem Skin.
      - Schalter aus und `/reload`: wieder EldoUIs eigenes Aussehen.
      - Danach `/eui errors`: keine Lua-Fehler.
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
      weil Upstream sie pflegt. Die Issue-Vorlagen sind Upstreams. In diesem Repo ist das Fehlerformular für
      den Report-Knopf nötig, die anderen schaden nicht.
- **Versionsgrenzen bei Integrationen:** Ace3-Skins nur bis AceGUI-Minor 41 (`EldoUI/Modules/SkinsAddons.lua:29`).
  Bei Addon-Updates prüfen.
- **C5 Combat Text: Stil „Kräftig“:** Der Nutzer fand den Combat Text im Spiel lieblos (15.11.2026, Stil
  „Plakettenfokus“: dünne Kontur, gleichmäßige Bewegung, normale Treffer auf der Plakette rot wie eigener
  Schaden, Krits nur etwas größer). Aus einem bewegten Entwurf mit drei Varianten wählte er „Kräftig“.
  - **Umgesetzt:** neue Stil-Vorlage „Kräftig“ (`Punchy`, `Modules/CombatText/Options.lua`), dazu:
    - EldoUIs Schrift Anton, dicke Kontur, Textschatten (`scroll.shadow`, `plates.shadow`, `M.SetTextShadow`).
    - Haftende Zeilen und kritische Plakettentreffer blitzen weiß auf und nehmen in 0,35 s ihre Farbe an
      (`scroll.flash`, `plates.flash`, `M.FlashColor`).
    - Neue Bewegungen (`Animations.lua`): „Wurf“ für Scroll-Zeilen (schnell los, dann langsamer, kurz größer),
      „Wumms“ für haftende Zeilen (doppelt so groß, kurz unter Normalgröße, Ruckeln), „Wurf“ für Plaketten
      (zur Seite geworfen, steigt schnell, sinkt am Ende; Krits springen darüber heraus und bleiben länger).
    - Plakettenfarben „Elfenbein, kritische Treffer golden“ (`plates.colorMode = "warm"`): normale Treffer
      elfenbein, Krits gold, Zauberschulen in ihrer Farbe. Schrift und Kontur der Plaketten sind jetzt einstellbar.
    - Zusammengefasste Treffer können das „×3“ grau schreiben (`scroll.countGray`).
    - Alles Neue ist eine eigene Einstellung und standardmäßig aus. Andere Vorlagen schreiben sie nicht, beim
      Anwenden setzt `E:ApplyStyle` sie also auf den Standard zurück: Die alten Stile sehen aus wie vorher.
    - Grenzen des Spiels: Die Größe einer Zahl kann nicht vom Schaden abhängen (Werte sind im Kampf geheim),
      und Treffer nennen keinen Zauber, also keine Symbole pro Treffer.
    - Deutsche Texte in `EldoUI_Locale_deDE/Fork.lua`.
  - **Test:** `tools/combattext/test_punchy.lua` (läuft in `tools/ci/check_all.sh tests`). Er lädt
    `Animations.lua` ganz und schneidet die Standards (`Core.lua`), Zeilentext, Schulfarben, Schatten, Blitz und
    Updater (`Engine.lua`), die Plakettenfarben (`Plates.lua`) und die Stil-Liste (`Options.lua`) heraus.
    Geprüft: Form der drei neuen Bewegungen, die alten sind noch da; eine stehende Zeile kostet nach dem
    ersten Bild keinen Aufruf, kein `ClearAllPoints`; Blitz von Weiß zur Farbe; Schatten; grauer Zähler, auch
    mit geheimer Zahl; Plakettenfarben neu und alt; „Kräftig“ schreibt nur vorhandene Einstellungen, nennt
    Bewegungen der richtigen Art und eine mitgelieferte Schrift; alle anderen Stile bleiben beim alten Look.
  - **Im Spiel prüfen:** `/eui` → Combat Text → Vorlagen → „Kräftig“ anwenden, dann `/eui sct test` und kämpfen.
    Erwartung: Anton-Zahlen mit Schatten, Krits blitzen weiß und springen heraus, Treffer auf der Plakette
    elfenbein, Krits gold; keine Lua-Fehler. Danach eine andere Vorlage wählen: alter Look ohne Schatten.
  - **Im Spiel geprüft (15.11.2026):** „Kräftig“ angewendet, Test und Kampf: gefällt dem Nutzer („Passt so“), keine
    Einträge im Fehlerlog. Der Gegentest mit einer anderen Vorlage steht noch aus.
- **C6 RestedXP im deutschen Client:** Der Nutzer spielt mit den gekauften RestedXP-Guides (nur Englisch) und hatte
  das Gefühl, dass sie sich mit dem deutschen Forever-Client beißen (16.11.2026). Geprüft: RestedXP Guides v4.11.36 im
  Forever-Ordner, die 198 gekauften Guides aus RestedXPs Guide-Speicher (`WTF/…/SavedVariables/RXPGuides.lua`, nur
  lokal ausgewertet, nichts davon im Repo) und die NPC-Namen aus QuestieDB.
  - **Gefunden** (alles ohne Fehlermeldung, es passiert nur nichts):
    - Zielnamen: Die gekauften Guides haben rund 16.800 Einträge in `.target`, `.mob` und `.unitscan` mit englischen
      NPC-Namen. 556 Namen (rund 3.100 Einträge) heißen im deutschen Client anders und fehlen in RestedXPs eigener Liste
      (`locale/NPCnames.lua`). Zielmakro, Zielknöpfe, Plakettenmarkierung und Rare-Alarm finden diese NPCs nicht.
    - Guide-Kette: Die Gratis-Guides 1–22 laden auf Deutsch, mit eigenen Gruppen („RestedXP Forever Route (H)“,
      „RestedXP Forever Dungeonführer (H)“). Die gekauften bleiben in den englischen Gruppen und beginnen bei 21/22.
      Sechs „nächster Guide“-Verweise am Ende der Gratis-Guides laufen ins Leere (z. B. „22-24 Hügellandhof“ statt
      „22-24 Hillsbrad“); im englischen Client keiner.
    - Gruppennamen: RestedXPs deutsche Liste (`locale/deDE.lua:353-356`) übersetzt „RestedXP Forever Guide“ mit
      „Dungeonführer“ und „RestedXP Forever Dungeon Guide“ mit „Dungeon Dungeonführer“. Im Guide-Menü heißt die gekaufte
      Route deshalb wie der Gratis-Dungeonguide. Die Standardgruppe (`DB/forever/db.lua`) kommt aus diesem Text: Der
      Guide-Assistent bietet für die Open-World-Route den Dungeonguide an und für die Dungeon-Route gar nichts. Milka
      stand deshalb im Dungeonguide.
    - Levelstatistik: RestedXP erkennt Quest-Erfahrung nur am englischen Anfang „You“; im deutschen Client zählt sie
      zusätzlich als Erfahrung von Gegnern.
    - Sprachunabhängig (über IDs) und in Ordnung: Quests, Ruhestein, Zonen, Flugpunkte, Händler, Lehrer,
      Gesprächsoptionen, Gegenstände.
  - **Umgesetzt:** neuer Schalter „Fit RestedXP to this game language“ / „RestedXP an die Spielsprache anpassen“
    (`rxp.locale`, Standard an) im RestedXP-Reiter der Integrationen, sichtbar nur auf einem nicht-englischen Client mit
    RestedXP. Code in `EldoUI/Modules/IntegrationsRXPLocale.lua`. Das ist die einzige Stelle, an der EldoUI Funktionen
    eines anderen Addons umhüllt (Regel oben in `Integrations.lua` ergänzt). Jede Hülle ruft zuerst RestedXPs eigene
    Funktion und füllt nur Lücken. Ausgeschaltet (oder Integration bzw. Modul aus) gibt sie RestedXPs Antwort
    unverändert weiter. Dateien und gespeicherte Einstellungen von RestedXP bleiben unberührt.
    - `GetCreatureName`: Namen, die RestedXP englisch lässt, kommen aus QuestieDB (`LibQuestieDB.Npc`, Vertrag 4):
      englischer Name → NPC → deutscher Name. Die englischen Namen werden einmal pro Sitzung nach dem Login in Schritten
      gelesen (500 NPCs alle 0,05 s, nicht im Kampf), danach baut RestedXP seine Zielliste neu. Ohne QuestieDB bleibt
      RestedXPs Liste.
    - `GetGuideTable`: Einen Guide, den RestedXP in einer deutschen Gratis-Gruppe nicht findet, sucht EldoUI in der
      englischen Gruppe: unter dem Namen des gekauften Guides (feste Tabelle der Übergänge) oder über den Stufenbereich,
      wenn genau ein nutzbarer Guide passt.
    - `GetActiveGuidesByGroupNameOrId`: Deutsche Gratis-Gruppe und englische Gruppe stehen im Guide-Assistenten zusammen
      (eine Route von 1 bis 60).
    - Die vier falschen Gruppennamen bekommen die Namen der deutschen Gratis-Gruppen, so wie RestedXPs französische und
      spanische Liste es machen; die Standardgruppe ebenso. Nur Texte mit genau RestedXPs falschem Wortlaut, ausgeschaltet
      kommen sie zurück. Im Guide-Menü steht „RestedXP Forever Route (H)“ danach zweimal (Gratis 1–22, gekauft ab 21):
      so zeigt RestedXP das in den anderen Sprachen auch.
    - Levelstatistik: Die Quest-Meldungen der Spielsprache (Spieltexte `COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED…`) zählen
      nicht mehr als Gegner-Erfahrung.
    - Andere Sprachen bekommen Zielnamen und Levelstatistik; Daten für Gruppen und Guide-Kette gibt es nur für Deutsch.
    - Deutsche Texte in `EldoUI_Locale_deDE/Fork.lua`.
  - **Test:** `tools/integrations/test_rxp_locale.lua` (läuft in `tools/ci/check_all.sh tests`). Er lädt die echte Datei
    in ein Modell von RestedXP (nach dem Verhalten von v4.11.36 nachgebaut, kein RestedXP-Code) und von QuestieDB.
    Geprüft: Zielnamen aus QuestieDB erst nach dem Lesen, in Schritten und nicht im Kampf; RestedXPs eigene Liste und
    gleiche Namen bleiben; das „*“ vor einem Namen; NPC-IDs; mehrere NPCs mit einem englischen Namen; ohne QuestieDB
    oder mit falschem Vertrag nichts. Guide-Kette über die bekannten Namen und den Stufenbereich, nie zu einem Guide,
    den die Figur nicht nutzen kann, und nicht, wenn zwei passen. Der Assistent listet Gratis und gekauft zusammen.
    Gruppennamen und Standardgruppe ändern sich nur, solange sie RestedXPs falsche sind, und kommen zurück.
    Quest-Erfahrung auf Deutsch zählt nicht als Gegner. Ausgeschaltet, Modul aus oder englischer Client: RestedXP
    antwortet wie vorher. Ein französischer Client bekommt Namen und Statistik, aber nicht die deutschen Guide-Daten.
  - **Im Spiel prüfen:**
    1. `/reload`, ein paar Sekunden warten, `/eui` → Integrationen → RestedXP. Erwartung: Schalter „RestedXP an die
       Spielsprache anpassen“ an, darunter „Zielnamen: bisher … mit QuestieDB übersetzt.“
    2. Ohne Laufen, eine Zeile: `/run local r=LibStub("AceAddon-3.0"):GetAddon("RXPGuides") print(r.GetCreatureName("Thistlefur Shaman"),(r.GetGuideTable("RestedXP Forever Route (H)","22-24 Hügellandhof") or {}).name)`
       Erwartung: „Schamane der Distelfelle“ und „22-24 Hillsbrad“.
    3. Defron in „26-28 Ashenvale“: bei einem Schritt mit Distelfell-Gegnern oder Geisterpfotenalpha das Makro
       „RXPTargeting“ ansehen (deutsche Namen nach `/targetexact`) und den Zielknopf drücken: Er trifft.
    4. RestedXPs Guide-Menü: Gruppen „RestedXP Forever Route (H)“ und „RestedXP Forever Dungeonführer (H)“, kein
       „Dungeon Dungeonführer“ mehr.
    5. Milka: RestedXPs Guide-Assistent → Dungeon-Route: Die Liste ist nicht leer. Open-World-Route: bietet die Route an,
       nicht den Dungeonguide.
    6. Danach: Fehlerlog (`EldoUIErrorsDB`) ohne neue Einträge. Die Guide-Kette selbst zeigt sich erst bei Stufe 21/22
       (Milka); Punkt 2 prüft sie vorher.
  - **Im Spiel geprüft (16.11.2026, Defron, Stand `6a2c479` in den AddOns-Ordner kopiert, Client neu gestartet):**
    - 1.: Der Schalter steht im RestedXP-Reiter, laut Nutzer „sieht alles sauber aus“. Ob die Statuszeile die Zahl der
      übersetzten Namen zeigte, hat er nicht eigens gesagt.
    - 2.: Die `/run`-Zeile zeigt „Schamane der Distelfelle“ und „22-24 Hillsbrad“.
    - 3.: Zielmakro in „26-28 Ashenvale“: funktioniert bisher.
    - 4.: Im Guide-Menü stehen „RestedXP Forever Route (H)“ (zweimal, Gratis und gekauft) und „RestedXP Forever
      Dungeonführer (H)“, kein „Dungeon Dungeonführer“ mehr.
    - 6.: Nach `/reload` kein Eintrag im Fehlerlog aus der Zeit nach dem Einspielen. Der jüngste Eintrag stammt aus
      Sitzung 59 (16.11. 00:18, vor dem Einspielen) und hat mit C6 nichts zu tun, siehe F22 in `fehler.md`.
    - Noch offen: Guide-Assistent mit Milka (5., der Nutzer prüft das später, Milka ist ein Bankcharakter) und die
      Guide-Kette selbst bei Stufe 21/22.
- **C7 Leisten-Schnappschüsse: welche Aktionsleisten an sind:** Bis zum Forever-Hotfix vom 13.11.2026 haben sich
  mit Dual-Spezialisierung die Einstellungen der Aktionsleisten bei jedem Ausloggen zurückgesetzt („Fixed a bug that
  caused Action Bar settings to reset every time players who acquired Secondary Talents logged out“). Laut Timesaver
  (14.11.) meldete ein Spieler danach noch geleerte Leisten. Die Schnappschüsse sicherten Plätze, Makros, Tasten und
  das Layout des Bearbeitungsmodus, aber nicht die Schalter „Aktionsleiste 2 bis 8 anzeigen“.
  - **Umgesetzt** (`Modules/Snapshots.lua`): Ein Schnappschuss hält die sieben Werte von `GetActionBarToggles`, nur
    wenn das Spiel klar true oder false meldet. Neuer Teil „Welche Leisten an sind“ im Wiederherstellungsfenster und
    in den Optionen. Wiederherstellen setzt alle sieben mit einem Aufruf `SetActionBarToggles`, wie Blizzards
    Optionen (`Blizzard_SettingsDefinitions_Frame/ActionBars.lua`, Branch `forever`), und bietet danach das Neuladen
    an. EldoUI ruft `MultiActionBar_Update` bewusst nicht selbst auf: Es schreibt `VIEWABLE_ACTION_BAR_PAGES`, das
    `ActionBar_PageUp` beim Blättern liest, und aus Addon-Code wäre das im Kampf verseucht. Die Prüfung beim Einloggen
    zählt es als Zurücksetzen, wenn zwei oder mehr Leisten aus sind, die im Schnappschuss an waren, und keine neu an
    ist. Strings zum Teilen tragen die Werte mit, außerhalb der Prüfsumme, damit ältere Versionen neue Strings
    weiter annehmen. Test: `tools/snapshots/test_bar_toggles.lua` (31 Prüfungen, mit dem alten Code 11 Fehlschläge).
  - **Im Spiel prüfen:**
    1. Mit Blizzards Leisten (Aktionsleisten-Modul von EldoUI aus oder „Blizzards behalten“): `/eui snapshot take`.
    2. Unter Optionen → Aktionsleisten zwei Leisten ausschalten, dann `/eui snapshot restore 1`. Erwartung: Der Teil
       „Welche Leisten an sind“ ist angehakt und nennt „2 Leisten ändern sich“, der Tooltip die beiden Leisten.
    3. Wiederherstellen, dann über die Abfrage neu laden. Erwartung: Beide Leisten sind wieder da, im Fehlerlog kein
       `ADDON_ACTION_BLOCKED`. Danach im Kampf mit Umschalt + Mausrad bzw. Umschalt + Zahl blättern: Es geht.
    4. Mit „Wiederherstellung nach einem Zurücksetzen anbieten“: zwei Leisten aus, ausloggen, einloggen. Erwartung: Die
       Frage nennt „die Aktionsleisten … sind ausgeschaltet“.
- **C8 Kampfsimulation: Richturteil als Fernkampfangriff:** Forever-Hotfix vom 11.11.2026: „Judgement changed to now
  be considered a Ranged Attack … uses the Paladin's Ranged Hit chance“. Am 13.11. kam Richturteil des Befehls als
  Nahkampf zurück. Die Simulation (`EldoUI_LootSim`) würfelte Richturteil mit der Zauber-Trefferchance.
  - **Umgesetzt:** Richturteil (`Data.lua`, `rangedHit`) würfelt jetzt die Fehlschlagchance eines Fernkampfangriffs
    aus der Trefferchance (`Engine.lua`, `Fight:SpellLands`), ohne Ausweichen wie die anderen Fernkampfangriffe der
    Simulation. Schaden, Krit und Widerstand bleiben wie bei Zaubern, weil der Hotfix nur die Trefferchance nennt.
    Richturteil des Befehls betrifft die Simulation nicht: Die Variante mit Siegel des Befehls richtet nie.
    Test: `tools/lootsim/test_judgement.lua` (13 Prüfungen, ohne die Regel 5 Fehlschläge).
  - **Offen:** Ob ein Krit des Richturteils jetzt wie ein Fernkampf-Krit zählt, sagt der Hotfix nicht. Es gibt keinen
    Spieltest dafür, nur die Zahlen der Simulation.

## D – Infrastruktur für den Fork

- **Ist-Zustand:** kein CI, keine `.luacheckrc`, keine Tests, keine Build-Skripte. Der Code verweist rund 40-mal
  auf nie veröffentlichte `tools/…`-Skripte. 42 Dateien sind generiert („never edit by hand“) und lassen sich
  nicht neu erzeugen – nur mit Vorsicht von Hand ändern.
- **D1 Upstream-Updates:**
  - neue Releases unverändert in einen Branch `upstream-release` importieren und von dort nach `main` mergen;
  - eigene Features möglichst als Plugin-Addons `EldoUI_<Name>` über die öffentliche API (`docs/PLUGINS.md`).
  - Der Versionswächter (`.github/workflows/watch.yml`) meldet jede neue EldoUI-Version als Issue, dazu neue
    WoW: Forever-Patches (live und im Test-Client).
  - **Umgesetzt (16.11.2026, EldoUI 0.7.3001, Issue #29):** Der Branch `upstream-release` hält die Releases
    unverändert: `e454ab1` (0.7.2001) und `8b8f957` (0.7.3001, ZIP byte-genau geprüft). `c323ceb` mergt ihn nach
    `main`, davor `549e229` EldoUIs Doku-Historie bis 0.7.3001. Der Weg steht in `tools/ci/README.md`
    („Neue EldoUI-Version übernehmen“).
    - Umfang 0.7.2001 → 0.7.3001: 332 Dateien geändert, 15 neu, rund +47.000/−17.000 Zeilen. Von den rund 60
      Upstream-Dateien, die der Fork geändert hat, hatten 11 Konflikte (18 Stellen).
    - Doppelte Fixes (Absprache: EldoUIs Lösung gilt, der Fork behält nur, was sie nicht abdeckt): F05 und F07
      teilweise, F14 und C8 ganz (Tabelle in `fehler.md`). C8: `EldoUI_LootSim` ist wieder ganz EldoUIs,
      `tools/lootsim/test_judgement.lua` prüft jetzt EldoUIs Regel (`hitType = "ranged"`).
    - Fork-Features gegen 0.7.3001 geprüft: keins ist doppelt. Überschneidungen: B7 (siehe dort), B5 (EldoUIs
      Questgegenstand-Knopf folgt jetzt der gewählten Quest; unsere Leiste bleibt) und E2 (EldoUI zeigt seine
      Gesamtzeit pro Bild unter der Seitenleiste, `/eui perf` teilt sie weiter nach Modulen auf).
    - Angepasst, weil EldoUI den Code umgebaut hat: F18 (Reihenfolge in EldoUIs neuen `Set`/`Apply`), E3 (EldoUIs
      Ereignis-Sounds im schlankeren Updater), C1 (Masque bekommt `button.hover` aus EldoUIs `E:SkinHudButton`;
      vorher zeigte der Code auf eine nicht mehr vorhandene Variable).
    - Deutsches Paket: 292 Texte, die die dänische Liste nicht mehr hat, sind raus. Die 989 neuen sind übersetzt
      (eigener PR nach dem Update): sieben Übersetzer-Agenten mit Glossar, der dänischen Fassung als
      Bedeutungshilfe und den alten Texten samt Übersetzung als Vorlage, wo EldoUI nur umformuliert hat; jede
      Antwort mit `deDE.py`s eigener Prüfung, danach `check` und `xref` über das ganze Paket. Wieder
      vollständig: 21.525 von 21.525. Dezimalkomma an (`E.decimalCommas.deDE`, neu in 0.7.3000).
      Nicht übersetzbar ohne Code-Änderung: die Rangnamen der Berufe in
      `Modules/Notifications/Professions.lua` (`NEXT_RANK`, nicht durch `L`), sie bleiben englisch.
    - Prüfungen: 21 neue WoW-API-Namen in `tools/ci/globals.lua`; Platzhalter in vier Tests für EldoUIs neue
      Helfer; `check_all.sh tests` läuft jetzt ganz durch und nennt am Ende alle roten Tests. Offline-Start:
      630 bzw. 636 Dateien, 103 Module (84 an), 0 Fehler, englischer und deutscher Client.
    - Version `0.7.3001-p1`. Im Spiel ist das Update noch nicht getestet.
    - Im Spiel prüfen (vorher `WTF` sichern; alte `EldoUI*`-Ordner löschen, das neue ZIP entpacken und das Spiel ganz
      neu starten, die TOC hat neue Dateien):
      - Login: `/eui errors` ohne neue Fehler; der Hinweis „Was ist neu“ zu 0.7.3001 kommt einmal.
      - Deutscher Client: EldoUIs Texte deutsch, nur Neues aus 0.7.3000 englisch; Schieberegler mit Komma (z. B. „0,71“).
      - F18: Profilseite „Neues Profil“, „Umbenennen“ und die Auswahllisten; eine Auswahl auch mit den Pfeiltasten.
      - F14 (jetzt EldoUIs): `/eui move`, einen Mover ziehen und dabei in den Kampf kommen: kein ADDON_ACTION_BLOCKED,
        der Verschiebemodus geht nach dem Kampf wieder auf.
      - E3/C5: Kampftext im Stil „Kräftig“; Loot-Zeilen mit Ton spielen ihn bei einem Schwung nur einmal.
      - C1: mit Masque Hover-Optik auf Verbrauchsgüter- und Totemleiste.
      - Rechtsklick auf einen Trank in der Tasche benutzt ihn (Hotfix 0.7.3001); dazu F22s Auktionshaus-Ablauf.
      - B7: Taschen bis auf 3 freie Plätze füllen: unsere Karte und EldoUIs Pfeil, ob sie verschiedene Gegenstände nennen.
  - **Umgesetzt (19.11.2026, EldoUI 0.7.3005, Issues #40, #41, #42):** `upstream-release` hält jetzt auch
    0.7.3002 (`df15974`), 0.7.3003 (`7b5e982`), 0.7.3004 (`6b68763`) und 0.7.3005 (`775b23d`), jedes ZIP byte-genau
    gegen seinen Commit geprüft. `f9c0fc9` mergt 0.7.3005 nach dem Fork, davor `f87148d` EldoUIs Doku-Historie bis
    0.7.3005. Für 0.7.3002 gab es kein Issue (am selben Tag wie 0.7.3003 erschienen).
    - Umfang 0.7.3001 → 0.7.3005: 30 Dateien, rund +1.600/−630 Zeilen, keine neue Datei. Das meiste ist der neue
      Layerwechsel (0.7.3002), Schriften für Namen in anderen Alphabeten (0.7.3003), Gnomensprint (0.7.3002–0.7.3004)
      und Fehler auf Schlachtfeldern (0.7.3005).
    - Konflikte: TOC (Version) und `Modules/MinimapLayer.lua` (F05, jetzt ganz EldoUIs; siehe `fehler.md`).
    - Fork-Features gegen 0.7.3005 geprüft: keins ist doppelt, keins überschneidet sich. Ohne Konflikt durchgelaufen
      und unabhängig: C1 (`E:DropTemplate`) neben EldoUIs Schrift-Objekten in `Core/Media.lua`; F23, C2 und E4 neben
      EldoUIs Kartenklick in `Modules/InfoBar.lua`; der Haken für `Blizzard_NamePlates` neben `E:SkipSnap` in
      `Modules/Nameplates.lua`.
    - Deutsches Paket: 17 Texte des alten Layerwechsels sind raus, die 49 neuen übersetzt (`ea79c06`). Wieder
      vollständig: 21.557 von 21.557.
    - Prüfungen: keine neuen WoW-API-Namen, keine Änderung an Tests oder am Nachbau nötig. Offline-Start: 630 bzw.
      636 Dateien, 103 Module (84 an), 0 Fehler, englischer und deutscher Client.
    - Beim Import gelernt: Im ZIP trägt jede Datei den Zeitstempel 1980-01-01, und Git übersah drei geänderte
      `.toc`-Dateien gleicher Größe. Die Import-Commits sind darum mit frisch eingelesenem Index gebaut; der Weg steht
      in `tools/ci/README.md`.
    - Version `0.7.3005-p1`. Im Spiel ist das Update noch nicht getestet.
    - Im Spiel prüfen (vorher `WTF` sichern; alte `EldoUI*`-Ordner löschen, das neue ZIP entpacken und das Spiel ganz
      neu starten, die Version steht in der TOC):
      - Login: `/eui errors` ohne neue Fehler; der Hinweis „Was ist neu“ zu 0.7.3005 kommt einmal, deutsch.
      - Layerwechsel: Klick auf die Layer-Anzeige, „Zu einem anderen Layer wechseln“; Statuszeilen deutsch, eine
        Einladung kommt im Fenster des Spiels. Mit „Anderen beim Wechseln helfen“: die Karte Einladen/Nicht jetzt.
      - Namen in kyrillischer, koreanischer oder chinesischer Schrift, falls einer auftaucht: Namensplaketten und Rahmen
        zeigen Zeichen statt leerer Kästchen.
      - Schlachtfeld betreten: keine Fehler von Kalender, Questverfolgung, Tooltip oder Weltkarte; Ergebnisfenster
        am Ende ohne Ruckler.
      - F23 (Gilden-Tooltip im Kampf) und F22 (Auktionshaus) wie vorher.
  - **Umgesetzt (23.11.2026, EldoUI 0.7.3100, Issues #3 und #5):** `upstream-release` hält jetzt auch 0.7.3006
    (`0874892`) und 0.7.3100 (`844f1b7`), jedes ZIP byte-genau gegen seinen Commit geprüft (`git archive`, `diff -r`).
    `b850d60` mergt 0.7.3100 nach dem Fork, davor `3f153cb` EldoUIs Doku-Historie bis 0.7.3100.
    - Umfang 0.7.3005 → 0.7.3100: 69 Dateien, rund +2.560/−270 Zeilen, vier neue Dateien (`Core/PvPRank.lua`,
      `Data/EldostarPlaces.lua`, `Data/ForeverFactions.lua`, `Data/Training/PetCare.lua`, alle in der TOC). Das meiste
      sind der PvP-Rang (Block, Leiste, Tooltip), die Fraktionen von WoW: Forever im Tagebuch, die Einstimmungsseiten
      für Barrow Deeps und Hyjalgipfel, das Jägertier im Trainingsfenster, die Heilmittel auf der Verbrauchsgüterleiste,
      die Volksfähigkeiten in der Tastenbelegung und der Umzug eines Charakters auf ein anderes Regelwerk; 0.7.3006 sind
      Würfelleisten, Beutefenster und Bankreiter.
    - Konflikte: TOC (Version), CHANGELOG, `Bindings.xml` und `Core/Bindings.lua`. Die Namen der neuen Tasten 10 bis 12
      setzen ihr Heilmittel mit `E:InSentence` ein wie die übrigen Tasten der Leiste (Deutsch behält das Substantiv groß).
    - Fork-Features gegen 0.7.3100 geprüft: keins ist doppelt, im Code überschneidet sich keins. Auf dem Bildschirm
      vielleicht: EldoUI Center legt die Verbrauchsgüterleiste weiter nach rechts (BOTTOM +420 statt +330), mit bis zu
      zwölf statt neun Schaltflächen; die Questgegenstandsleiste (fester Platz BOTTOMRIGHT −463, 246) könnte sie bei
      vielen Questgegenständen berühren (Rechnung der Gegenprüfung: bei 2560 Breite und voller Leiste ab sechs
      Gegenständen, vorher ab zehn). Im Spiel prüfen, dann ggf. den Platz der Questleiste je Layout setzen.
      Ohne Konflikt durchgelaufen und unabhängig: C1 (Masque) und die Tasten mit Umschalt/Strg/Alt auf der Verbrauchsgüterleiste gelten auch für die
      drei neuen Schaltflächen (dieselbe `CreateButton`); `E:InSentence` in `Chat/Core.lua` und `Gathering/Core.lua`
      neben EldoUIs Ausführungsmarke und dem Lernen neuer Vorkommen; F23, F24 und der Name conUI in `InfoBar.lua` neben
      dem PvP-Rang-Block; die Wowhead-Sprache in `QoL.lua` neben EldoUIs Flugleiste; der Name im DBM-Panel neben
      `E:BossModHidesTracker`.
    - Deutsches Paket: 9 Texte sind raus, die 116 neuen übersetzt (`dcd5e46`), 22 davon aus EldoUIs eigener
      Loot-Guide-Tabelle. „Fish“ heißt jetzt „Fisch“ (der Schlüssel benennt seit 0.7.3100 auch ein Futter des
      Jägertiers). Wieder vollständig: 21.664 von 21.664.
    - Prüfungen: vier neue WoW-API-Namen, sieben nicht mehr benutzte raus (`23a26d0`); keine Änderung an Tests oder am
      Nachbau nötig. Offline-Start: 635 bzw. 641 Dateien, 103 Module (84 an), 0 Fehler, englischer und deutscher Client.
    - CHANGELOG: Der Merge von 0.7.3001 hatte eine Zeile (Klassenbuff-Erinnerung) unter 0.7.2000 doppelt stehen
      lassen; sie ist raus, beide CHANGELOGs sind wieder EldoUIs plus der Abschnitt [Unreleased] des Forks.
    - Gegenprüfung (unabhängiger Prüfer, 23.11.2026): Importe byte-genau, den Merge in einem eigenen Klon wiederholt
      (dieselben vier Konflikte, alles andere gleich), `check_all.sh` grün, Zahlen in Notizen und Commits richtig.

      | Befund des Prüfers | Reaktion |
      |---|---|
      | F24: Der Finder ruft `ToggleAllBags` direkt auf (alter Weg, nicht aus dem Update); die Textprüfung des Tests liest ihn nicht, die Notiz zum Update nannte sie aber als Beleg | In `fehler.md` unter F24 als offene Lücke eingetragen, die Notiz zum Update berichtigt; Fix getrennt |
      | Deutsch: fünf Sätze holprig (PvP-Rangleiste, Jäger in den Neuigkeiten, Obergrenze „öffnet sich“, „Sie“ wie Höflichkeitsform, „Obergrenze“ ohne „erreicht“) | Alle fünf geändert |
      | Namen aus dem Gedächtnis (Loyalitätsstufen, Futter, „Berg Hyjal“, „Gegenstandsinformationen werden abgerufen“) | Als Punkt für den Spieltest unten |
      | Glossar nicht nachgezogen | Neue Begriffe in `tools/locale/glossar-deDE.md` |
      | Questleiste neben der verschobenen Verbrauchsgüterleiste (plausibel) | Aussage oben berichtigt, Punkt für den Spieltest |
      | Sammeln lernt neue Vorkommen nur bei `LOOT_OPENED`; mit Auto-Loot schickt Forever beim Angeln nur `LOOT_READY` (F21), vielleicht auch beim Bergbau (plausibel, EldoUIs Code) | Punkt für den Spieltest; trifft es zu, an EldoUI melden |

    - Version `0.7.3100-p1`. Im Spiel ist das Update noch nicht getestet.
    - Im Spiel prüfen (vorher `WTF` sichern; alte `EldoUI*`-Ordner löschen, das neue ZIP entpacken und das Spiel ganz
      neu starten, die TOC hat neue Dateien):
      - Login: `/eui errors` ohne neue Fehler; der Hinweis „Was ist neu“ zu 0.7.3100 kommt einmal, deutsch.
      - Infoleiste: Block „PvP-Rang“ (Tooltip mit Rangpunkten und Obergrenze dieser Woche); Treffer und Zaubertreffer
        gleich dem Charakterbogen.
      - Verbrauchsgüterleiste: die drei Heilmittel an, je eine Taste darauf, auch mit Strg oder Umschalt gedrückt;
        mit Masque im selben Skin. Die Tastenbelegung zeigt „Beste Sorte benutzen: Mittel gegen Gift …“.
      - Bank: die Kaufschaltfläche auf der Seitenleiste; danach Rechtsklick auf den Ruhestein in den Taschen (F24).
      - Beute: Würfe in der Gruppe bekommen sofort ihre Leiste; das Beutefenster schließt mit Esc.
      - Jäger: Trainingsfenster, Reiter „Tierfähigkeiten“ mit Zufriedenheit, Loyalität und Futter (deutsch).
      - Instanzen: Stundenlimit 10; ein eigenes Limit bleibt.
      - Deutscher Client: die Loyalitätsstufen (Rebellisch … Bester Freund), die Futterarten und „Berg Hyjal“ so, wie
        das Spiel sie nennt; sonst die Übersetzung anpassen. „Gegenstandsinformationen werden abgerufen“ beim Würfeln.
      - `/eui move` mit voller Verbrauchsgüterleiste (die Heilmittel an) und mehreren Questgegenständen: Die beiden
        Leisten liegen nicht übereinander.
      - Sammeln mit Auto-Loot: eine Ader Heavy Thorium am Berg Hyjal abbauen; die Markierung zeigt Bergbau 300.
- **D2 CI** per GitHub Action:
  - `luac -p`, luacheck und TOC-Check;
  - bei Tag `v*` ein ZIP mit den sechs Addon-Ordnern.
  - **Umgesetzt:** `.github/workflows/ci.yml` (jeder Push und PR) und `release.yml` (Tag `v*`), Skripte und
    Beschreibung in `tools/ci/` (`check_all.sh` läuft lokal genauso). luacheck prüft nur Globals, gegen die Liste
    der heute benutzten WoW-API-Namen (`tools/ci/globals.lua`); Stilwarnungen bleiben aus, der Upstream-Code ist
    nicht dafür geschrieben. Das ZIP enthält alle acht `EldoUI*`-Ordner, nur von git erfasste Dateien.
- **D3 Eigener Fork:**
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
  - **Umgesetzt:**
    - Neu: `tools/harness/load_eldoui.lua` mit dem Spiel-Nachbau `tools/harness/wow.lua` und der neuen Prüfung
      `load` (eigener CI-Schritt „Ganzes Addon offline laden“). Der Lauf:
      - lädt alle Dateien der `EldoUI.toc` in ihrer Reihenfolge mit Addon-Namen und gemeinsamer Privattabelle,
        dann `ADDON_LOADED`;
      - lädt danach die Addons, die mit EldoUI laden (Gruppen-Pinnwand), und Bedarfs-Addons, sobald EldoUI sie per
        `C_AddOns.LoadAddOn` anfordert, aus ihren eigenen TOC-Dateien;
      - spielt `PLAYER_LOGIN` und `PLAYER_ENTERING_WORLD` wie ein erster Login ohne Einstellungen, dazu die
        gestarteten Timer;
      - schaltet zuletzt jedes Modul über `E:SetModuleEnabled` an, aus und zurück.
    - Zwei Läufe: englischer Client und deutscher Client. Beim deutschen wählt EldoUI selbst Deutsch und lädt das
      deutsche Paket samt `Fork.lua`.
    - Ergebnis beim Einbau: 608 bzw. 614 Dateien, 100 Module (80 starten an), alle 100 gleichzeitig an und aus,
      0 Fehler, gut 2 s pro Lauf.
    - Nachbau:
      - Die API-Namen aus `tools/ci/globals.lua` antworten. Wichtige sind von Hand gebaut: Spieler, Client, Zeit,
        Addons aus den echten TOCs, CVars, Timer, Hooks, Farben, Konstanten. Frames merken sich Größe, Anker wie
        im Spiel, Skripte, Attribute und Events. `ActionButtonTemplate` bringt seine Teile mit.
      - Der Rest ist ein „Mock“, aufrufbar und indizierbar; ein Aufruf antwortet nach dem Namen (`Is*` false,
        „Num“/„Count“ 0, sonst nil).
      - Andere Globals sind nil, wie bei einem fehlenden Addon.
    - Gegentest: `tools/harness/test_harness.lua` startet den Lauf mit einem absichtlich kaputten Modul
      (`fixtures/broken_module.lua`). Er muss fehlschlagen und Modul, Datei, Zeile und Phase nennen.
    - Beim Einbau gefunden wurden nur Lücken im Nachbau (Anker, Templates, Frame-Pools, TOC-Bedingungen, drei
      Blizzard-Funktionen, die LibActionButton hookt), kein Fehler in EldoUI.
    - Grenzen: Die Mocks sind großzügig. Wo das Spiel echte Daten liefern würde, nimmt der Code meist den Weg
      „keine Daten“. Der Lauf findet Abstürze und falsche Aufrufe, nicht falsches Verhalten oder Zeichnen.
      Beschrieben in `tools/ci/README.md`, mit dem Hinweis, was ein neuer `load`-Fehler bedeutet (echter Fehler
      oder Lücke im Nachbau).
    - Die Einzeltests mit ausgeschnittenem Code (`tools/share/`, `tools/clickcast/` usw.) bleiben. Sie prüfen
      Verhalten genauer, der Offline-Start prüft das Ganze.

## E – Performance

1. **Alles lädt beim Login:** 589 Dateien, rund 16,8 MB Lua, davon rund 1,8 MB für Module, die standardmäßig aus
   sind (FlightGames allein 0,66 MB). Upstream plant eine Aufteilung (`EldoUI/Core/Modules.lua:252`).
2. **Kein Profiling pro Modul:** Der zentrale Event-Dispatcher (`EldoUI/Core/Init.lua:200`) und `E.Ticker`
   könnten pro Modul messen (`/eui perf`).
   - **Umgesetzt (E2):**
     - Neu: `Core/Perf.lua` mit `/eui perf`. Der Befehl startet die Messung, und solange sie läuft, zeigt er die
       Ergebnisse. Dazu gibt es `stop`, `reset` und `copy`; `copy` öffnet ein Kopierfeld für Fehlerberichte.
     - Gemessen wird jeder Aufruf in `RunHandler` (`Init.lua`: `E:RegisterEvent`, `E:RegisterUnitEvent`, alle
       Modul-Events) und jeder Ticker-Aufruf (`Ticker.lua`), mit `debugprofilestop()`.
     - Gebucht wird auf den Besitzer: den Modulnamen, „Core“, den Namen, unter dem ein Teil sich angemeldet hat,
       oder den Anfang des Ticker-Schlüssels („InfoBar:holders“ → InfoBar).
     - Ergebnis: die zwölf teuersten Besitzer mit ms pro Sekunde, Anteil, Aufrufen und dem langsamsten Aufruf
       samt Event bzw. Schlüssel, dazu die Summe.
     - Standardmäßig aus. Ausgeschaltet prüfen Dispatcher und Ticker einen Wert pro Aufruf, sonst nichts.
     - Robust: Stoppen mitten in einem Handler ist sicher, und ein fehlerhafter Handler wird trotzdem gemessen
       und gemeldet.
     - Nicht gemessen: Frame-Skripte auf eigenen Frames eines Moduls (OnUpdate, OnEvent), Hooks auf
       Spielfunktionen, gesicherte Snippets, das Zeichnen des Spiels. Die Zeiten sind inklusiv: Löst ein Handler
       ein weiteres Event aus, zählt dessen Zeit mit.
     - Test: `tools/perf/test_perf.lua` (läuft in `tools/ci/check_all.sh tests`, 31 Prüfungen). Er nimmt
       `RunHandler` aus `Init.lua`, lädt `Ticker.lua` und `Perf.lua` ganz und läuft mit einer Uhr, die der Test
       selbst stellt.
     - Im Spiel prüfen:
       - `/eui perf` eingeben, ein paar Minuten spielen (Taschen, Kampf, Chat), wieder `/eui perf`. Erwartung:
         eine Liste mit Modulen und plausiblen Werten (meist deutlich unter 1 ms/s).
       - `/eui perf copy`: Das Ergebnis steht im Kopierfeld.
       - `/eui perf stop`: Die Messung endet. Danach `/eui errors`: keine Lua-Fehler.
     - Im Spiel geprüft (15.11.2026): 3 Minuten mit Kampf gemessen, Liste und Kopierfeld wie erwartet, keine
       Lua-Fehler. Gesamt 4,5 ms/s; 68 % davon die Infoleiste mit einem Ausreißer von 130 ms (daraus E4).
3. **OnUpdate ist sauber:** Frames verstecken sich im Leerlauf. Einzig Combat Text setzt pro Frame Punkt,
   Skalierung und Alpha jeder Zeile (`EldoUI/Modules/CombatText/Engine.lua:360`). Niedrige Priorität.
   - **Umgesetzt (E3, zusammen mit C5):** Die Updater der Scroll-Zeilen (`Engine.lua`) und der Plakettenzahlen
     (`Plates.lua`) setzen nur noch, was sich seit dem letzten Bild geändert hat: Skalierung, Punkt, Alpha und
     Sichtbarkeit. `ClearAllPoints` fällt pro Bild weg; jede Zeile hat einen festen Punkt, den `SetPoint`
     verschiebt, `Release` räumt ihn ab. Eine stehende Zeile (Stapel, haftende Zeilen nach dem Auftakt) kostet
     nach ihrem ersten Bild keinen Aufruf mehr. Test: `tools/combattext/test_punchy.lua` (siehe C5).
4. **Speicher-Block der Infoleiste ruckelt (E4, im Spiel gefunden):** `/eui perf` zeigte für die Infoleiste
   3,06 ms/s und einen langsamsten Aufruf von 130 ms („InfoBar:holders“). Der Block „Mem“ (im Stil „Full“
   dabei) ließ alle 30 s `UpdateAddOnMemoryUsage` laufen. Mit Questie, AtlasLoot, Details und DBM steht das
   Spiel dabei rund 130 ms still, also ein Ruckler alle 30 s.
   - **Umgesetzt (E4):** `Modules/InfoBar.lua` (`memorySnapshot.Read` und der Block „Memory“).
     - Jede Messung wird mit `debugprofilestop()` gestoppt. Bis zur nächsten vergehen 3 s pro Millisekunde,
       die sie gedauert hat, mindestens 30 s, höchstens 10 Minuten. Bei 130 ms also etwa alle 6,5 Minuten;
       kleine Addon-Sammlungen bleiben bei 30 s.
     - Der Tooltip liest beim Öffnen frisch, wenn der letzte Stand älter als 10 s ist, und die Leiste zeigt
       dann dieselbe Summe. Seine Neuzeichnungen alle 5 s nehmen den gehaltenen Stand.
     - Wie vorher: im Kampf nie von selbst, ein Klick (gibt Speicher frei) liest sofort.
     - Test: `tools/infobar/test_memory_poll.lua` (läuft in `tools/ci/check_all.sh tests`). Er schneidet den
       Speicher-Teil aus `InfoBar.lua` heraus und läuft mit einer eigenen Uhr, deren Messung eine feste Zeit
       dauert. Geprüft: 5 statt 61 Messungen in 30 Minuten bei 130 ms, 30 s bei 5 ms, höchstens 10 Minuten bei
       1 s, ohne Uhr wie bisher; Tooltip frisch nur auf altem Stand, Leiste zieht nach; Neuzeichnungen lesen
       nie; im Kampf nur per Klick.
     - Im Spiel prüfen: `/eui perf`, ein paar Minuten spielen, `/eui perf`. Erwartung: Die Infoleiste fällt von
       rund 3 ms/s deutlich herunter, kein Ruckler alle 30 s. Mit der Maus auf „Mem“: frische Werte, Leiste
       und Tooltip zeigen dieselbe Summe.
     - Im Spiel geprüft (15.11.2026), 4 Minuten `/eui perf` nach `/reload`: Infoleiste 0,31 ms/s statt 3,06 ms/s,
       langsamster Aufruf 0,24 ms statt 130 ms; EldoUI gesamt 2,13 ms/s statt 4,51 ms/s. In den 4 Minuten fiel
       keine Messung an (die nächste kommt bei diesem Setup nach etwa 6,5 Minuten). Tooltip über „Mem“:
       Leiste und Tooltip zeigen dieselbe Summe.
