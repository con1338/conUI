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
| B5 | Leiste mit allen benutzbaren Questgegenständen aus den Taschen | mittel | offen | |
| B6 | Signal, wenn Essen und Trinken fertig sind (Wunsch des Nutzers) | klein | umgesetzt | `7213a3d`, `f90e7f1` |
| B7 | Taschen fast voll: früher Hinweis und Liste „Platz schaffen“ | klein–mittel | offen | |
| B8 | Quest-EP hinter jedem Titel im Questlog (Wunsch des Nutzers) | klein | umgesetzt | `7213a3d`, `f90e7f1` |
| B9 | „Wer fehlt?“ für Gruppe und Raid (Herbeirufen) | mittel | abwarten | |
| B10 | Wowhead-Links in der Spielsprache (Wunsch des Nutzers) | klein | umgesetzt | `7213a3d` |
| B11 | Absitzen und Aufstehen bei Fehlermeldung (einschaltbar) | klein | offen | |
| B12 | Ausrüstungsset nach dem Kampf anlegen (einschaltbar) | klein | offen | |
| C1 | Masque auch für Auren, Combat HUD, ConsumableBar, Totems, Quickdraw | klein–mittel | teilweise | `5753197` |
| C2 | Info-Bar stellt ihre Blöcke als LDB-Objekte bereit | klein | umgesetzt | `98cb929` |
| C3 | Doku veraltet: README, CHANGELOG, CONTRIBUTING | klein | umgesetzt | `7781b25` |
| C4 | Versionsgrenzen bei Integrationen (Ace3-Skins bis AceGUI-Minor 41) | – | Daueraufgabe | |
| C5 | Combat Text: Stil „Kräftig“ (Wunsch des Nutzers, Entwurf gewählt) | mittel | umgesetzt | `d83f389` |
| C6 | RestedXP im deutschen Client: Zielnamen, Guide-Kette, Gruppennamen (Wunsch des Nutzers) | mittel | umgesetzt | `befb8ab` |
| D1 | Upstream-Updates: Releases unverändert importieren, Eigenes als Plugin | klein | teilweise | `c77d98e` |
| D2 | CI: Syntax, luacheck, TOC, Tests, Release-ZIP | klein–mittel | umgesetzt | `9eb8305` |
| D3 | Version und Fehler-Links des Forks | klein | umgesetzt | `260d193` |
| D4 | Offline-Test-Harness: API-Stubs, Dateien in TOC-Reihenfolge laden | mittel | umgesetzt | `fb8c242` … `141e84d` |
| E1 | Module erst bei Bedarf laden | groß | abwarten | |
| E2 | Profiling pro Modul (`/eui perf`) | mittel | umgesetzt | `cc64a52` |
| E3 | Combat Text setzt pro Frame Punkt, Skalierung, Alpha jeder Zeile | klein | umgesetzt | `d83f389` |
| E4 | Infoleiste: Speicher-Block hält das Spiel alle 30 s an (mit `/eui perf` gefunden) | klein | umgesetzt | `4c6cf53` |

**Reihenfolge der offenen Punkte** (für „nächster offener Punkt“): B5, B7, B11, B12, C1 (Rest), E1.
**Stand 16.11.2026:** B5 bis B12 kommen aus einer Suche nach QoL-Lücken (Abschnitt B, „QoL-Vorschläge“). Der Nutzer
hat B6, B8 und B10 gewählt. B9 wartet, bis er Stufe 60 erreicht und Gruppeninhalte spielt (seine Auskunft). Bei B11
erst im Spiel prüfen, ob Forever schon von selbst absitzt. B6 und B8 sind neue Dateien in der `EldoUI.toc`: Nach dem
Kopieren das Spiel ganz neu starten, denn `/reload` liest die Dateiliste nicht neu (wie bei C6). Ohne Neustart fehlen
nur die beiden Funktionen, Fehler gibt es keine, weil nichts in `QoL.lua` sie aufruft.
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
      weil Upstream sie pflegt. Die Issue-Vorlagen sind Upstreams. Im privaten Repo ist das Fehlerformular für
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
