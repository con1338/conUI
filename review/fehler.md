# Fehler

Pfade relativ zu `EldoUI/`. ✔ = im Code ein zweites Mal nachvollzogen.
Schwere: hoch / mittel / niedrig. Sicherheit: bestätigt = Codepfad vollständig gelesen,
plausibel = hängt von API-Verhalten ab, das sich ohne Spiel nicht prüfen lässt.

## Übersicht

| Nr. | Kurz | Schwere | Status | Commit |
|---|---|---|---|---|
| F01 ✔ | Import „global“ ersetzt accountweite Daten ohne Prüfung | hoch | behoben | `ec8eb1a` |
| F02 | Mover-Positionen aus Imports ungeprüft, Frames verschwinden | mittel–hoch | behoben | `723320c` |
| F03 ✔ | Snapshot-Import übernimmt Makroinhalte ungeprüft | mittel | behoben | `9dac6fc` |
| F04 | Settings-Angebote Fremder ohne Limit, schließen offene Dialoge | mittel | behoben | `8119cf7` |
| F05 ✔ | Layer-Modul antwortet jedem per Whisper | mittel | behoben | `3deb369` |
| F06 | Fremdtext mit Link-/Escape-Codes ungefiltert im Chat | niedrig–mittel | behoben | `eee687e` |
| F07 | Strings anderer Versionen als „beschädigt“ abgelehnt, Teil-Importe ohne Migration | niedrig–mittel | behoben | `419d511` |
| F08 | Entpackgröße erst nach dem Entpacken geprüft | niedrig–mittel | behoben | `d6042ce` |
| F09 | Segensplan und Whisper-Kontakte ohne Obergrenze | niedrig | behoben | `3b0c340` |
| F10 ✔ | RaidLoot-JSON: `null` verschiebt Array-Elemente | niedrig | bewusst nicht | |
| F11 | Castbar wertet geheime Werte direkt aus | hoch (plausibel) | behoben | `e5844d2` |
| F12 | Gruppenframes fallen fälschlich auf Blizzard zurück | mittel | behoben | `5c3b9c6` |
| F13 ✔ | Drei Event-Handler mit falscher Signatur | mittel | behoben | `1dc7a1d` |
| F14 | Mover ziehen über Kampfbeginn → ADDON_ACTION_BLOCKED | mittel (plausibel) | behoben | `8f18ddf` |
| F15 | Blizzard-Leiste kommt mit „toten“ Buttons zurück | mittel | behoben | `c0345a9` |
| F16 | Click-Casting: Hover-Unit veraltet nach Roster-Änderung | niedrig–mittel (plausibel) | behoben | `2731180` |
| F17 | Kleinkram: Click-Bindungen, Secret-Checks, Unit-Filter | niedrig | behoben | `9159f19`, `e49c371` |
| F18 | Profilseite: „Neues Profil“, „Umbenennen“ und die Auswahllisten bewirken nichts (im Spiel gefunden) | mittel | behoben | `c6ef76c` |
| F19 | Ausgeblendete Blizzard-Aktionsleisten: Platzwechsel im Kampf → ADDON_ACTION_BLOCKED (im Spiel gefunden) | mittel | behoben | `512df80` |
| F20 | Angeln: Die Angeltaste erreicht den Schwimmer nicht, „Ihr müsst Euch näher an Eurem Ziel befinden …“ (im Spiel gefunden) | mittel | behoben | `cfebaee` |
| F21 | Angeln: Das Fangprotokoll bleibt bei 0 (im Spiel gefunden) | niedrig–mittel | behoben | `cfebaee` |
| F22 | Auktionshaus: Verkaufen-Seite bleibt nach „Schnellverkauf“ leer; Rechtsklick in die Taschen verboten (im Spiel gefunden) | mittel | teilweise | `391f0b7` |

**Prüfung der Änderungen:** `luac5.1 -p` über alle 626 Dateien fehlerfrei; luacheck zeigt gegenüber dem
Originalstand keine neue Warnung (259 vor und nach den Änderungen, ohne W113/W212); kein neuer unbekannter
globaler Name außer `IsInInstance` (WoW-API, im Addon schon 47-mal genutzt). Reine Hilfsfunktionen
(Makro-Erkennung, Punkt-Prüfung, Versionsformat) wurden mit Lua 5.1 getestet. **Im Spiel getestet ist nichts.**

### Gegenprüfung der Fixes

Ein unabhängiger Prüfer hat alle 13 Fix-Commits anhand von Code und Commit-Messages nachvollzogen, ohne diesen
Ordner zu kennen. Ergebnis: 12 in Ordnung (teils mit Anmerkung), eins mit einem kleinen Problem. Kein schwerer
neuer Fehler.

| Befund des Prüfers | Reaktion | Commit |
|---|---|---|
| F04: Auch ein *angenommenes* Angebot startete die 30-s-Sperre; ein zweiter Teil („positions“ nach „general“) wurde still verworfen, der Absender wartete 90 s | Angenommene Angebote zählen nicht mehr; bei offenem Dialog bekommt der Absender eine Absage | `07c73da` |
| F11: Ein geheimes Dauer-Objekt würde jetzt in `CastOnUpdate` bei jedem Tick einen Wahrheitstest auslösen | `CastOnUpdate` nutzt ebenfalls `Present()` | `709b42a` |
| F03: Lokalisierte Aliase, `/tinspect` und `\r`-Zeilen wurden nicht erkannt; Makronamen im Restore-Fenster nicht entschärft | Aliase aus `SLASH_SCRIPT*`/`SLASH_DUMP*`/`SLASH_TABLEINSPECT*`, `/tinspect`, Trennung an `\r\n`, Namen entschärft | `62c114c` |
| F02: Scheitert `SetPoint` trotz Prüfung (Anker-Schleife), bleibt der Mover ohne Punkt | Dann Bildschirmmitte, dort ist er sichtbar und lässt sich zurückziehen | `12abe29` |
| F01: Für eine vorhandene, aber nicht teilbare Liste kam „a list your EldoUI doesn't have“ | Eigene Meldung; Name ohne Textcodes | `07c73da` |
| F12: Mit „nur im Kampf“ wird ein wirklich defekter Client nie erkannt | bewusst so gelassen (vertretbar) | |
| F04: In Schlachtfeldern lehnt auch das Senden einer Wunschliste an ein Gruppenmitglied ab, Text „only to your group…“ ist dort irreführend | bewusst so gelassen (seltener Fall) | |

---

## Import und Nachrichten anderer Spieler

### F01 ✔ – Import „global“ ersetzt accountweite Daten ohne Prüfung (hoch, bestätigt)
- **Stelle:** `Core/Share.lua:878` (`ApplyGlobal`), `Core/Share.lua:942`; `Core/Database.lua:229` (`RegisterGlobal`)
- **Problem:** `ApplyGlobal` prüft nur, ob für den Namespace Defaults existieren. Weil `RegisterGlobal` immer
  `defaults or {}` speichert, gilt das für jeden registrierten Namespace. Das Flag `share` wird nicht geprüft
  (kein Namespace ist mit `share = true` registriert; der Export erzeugt solche Strings also nie).
- **Szenario:** Ein selbst gebauter `!EUI1!`-String mit `kind = "global"` und z. B.
  `{ BarSnapshots = {}, RaidLoot = {}, MapNotes = {}, PlayerNotes = {} }` – eingefügt oder per „Send to“
  von einem Gilden- oder Gruppenmitglied. Nach „Accept“ sind Snapshots, GDKP-Ledger, Notizen usw. weg, ohne Backup.
- **Fix-Idee:** In `ApplyGlobal` `spec.share == true` verlangen.
- **Umsetzung:** `ApplyGlobal` nimmt nur noch Namespaces mit `share = true` an – dieselbe Regel, nach der der
  Export (`E:SharedGlobals`) auswählt. Da aktuell kein Namespace geteilt wird, lehnt der Import „global“ jetzt
  alles ab („None of these lists exist in your EldoUI.“).

### F02 – Mover-Positionen aus Imports ungeprüft (mittel–hoch, bestätigt)
- **Stelle:** `Core/Share.lua:820`, `:940`; `Core/Movers.lua:986` (`ApplyPosition`), `:1806` (`PlaceAll`)
- **Problem:** Punktnamen, Offsets und das Anker-Frame (beliebiger `_G`-Name) gehen ungeprüft an `SetPoint`.
  `PlaceAll` hat vorher bei allen Movern `ClearAllPoints` aufgerufen; ein Fehler bricht die Schleife ab.
- **Szenario:** Ein Eintrag `{"FOO", "UIParent", "CENTER", 0, 0}` in einem „positions“-/„all“-Import:
  `SetPoint` wirft, alle danach platzierten Mover bleiben ohne Anker, Frames unsichtbar – bei jedem
  Profilwechsel erneut, weil es gespeichert ist.
- **Fix-Idee:** Positionen vor dem Anwenden bereinigen; `ApplyPosition` in `PlaceAll` einzeln absichern.
- **Umsetzung:** `ApplyPosition` prüft den Punkt (Ankerpunkte, endliche Offsets, Relativ-Frame ist ein Frame
  oder nicht geladen) und nimmt sonst den Standardpunkt des Movers. `PlaceAll` platziert jeden Mover einzeln
  per `pcall` und meldet Fehler an den Error-Handler. Nicht umgesetzt: Typprüfung skalarer Einstellungen
  (`fontSize = "x"`) bei Imports.

### F03 ✔ – Snapshot-Import übernimmt Makroinhalte ungeprüft (mittel, bestätigt)
- **Stelle:** `Modules/Snapshots.lua:980` (`CleanImport`), Vorschau `:440`, `:477`
- **Problem:** `m.body` wird ungeprüft übernommen; Plan und Restore-Fenster zeigen nur die Makronamen.
- **Szenario:** Ein geteilter `!EUS1!`-String legt ein Makro „Mount“ mit `/run …` auf Slot 1. Nach „Restore“
  und Tastendruck läuft der Code.
- **Fix-Idee:** Makros mit Skript-Befehlen in der Vorschau deutlich markieren.
- **Umsetzung:** Makros mit einer Zeile `/run`, `/script` oder `/dump` sind im Restore-Fenster mit „(runs Lua
  code)“ markiert, der Import-Dialog warnt mit den Namen. Bei importierten Snapshots ist „Add missing macros“
  dann anfangs nicht angehakt. Eigene Snapshots verhalten sich wie bisher.
- **Im Spiel geprüft (15.11.2026):** Die Warnung im Import-Dialog kommt wie erwartet. Im Wiederherstellen-Fenster
  des importierten Snapshots steht neben „Fehlende Makros hinzufügen“ „1 fehlend, 1 davon führen Lua-Code aus“,
  das Kästchen ist leer, der Tooltip nennt das Makro mit „(führt Lua-Code aus)“. Der erste Anlauf nach der alten
  Anleitung öffnete mit `restore <Nummer>` den eigenen Snapshot, denn der Import setzt den neuen auf Nr. 1
  (`Modules/Snapshots.lua:1069`); dort ist der Haken richtig gesetzt. In der Platzliste steht die Markierung nicht
  („vorher leer“ heißt dort: der Platz ist jetzt leer). Die Anleitung unten ist entsprechend genauer.

### F04 – Settings-Angebote Fremder ohne Limit (mittel, bestätigt)
- **Stelle:** `Core/Share.lua:1471` (`IsTrustedSender`), `:1508`, `:1549`
- **Problem:** Jede Nachricht über PARTY, RAID, INSTANCE_CHAT oder GUILD gilt als vertrauenswürdig – auch von
  Fremden im Battleground oder in Zufallsgruppen. `OnOffer` hat kein Rate-Limit und ersetzt den einzigen
  Bestätigungsdialog (`CloseConfirm(false)` bricht den offenen ab).
- **Szenario:** Jemand schickt jede Sekunde ein Angebot → kein EldoUI-Dialog lässt sich mehr bestätigen.
- **Fix-Idee:** INSTANCE_CHAT nicht als vertrauenswürdig zählen; Abkühlzeit pro Absender; keinen offenen Dialog ersetzen.
- **Umsetzung:**
  - In Schlachtfeldern, Arenen und Instanz-Gruppen zählt Gruppenmitgliedschaft nicht mehr; Gilde und Freunde
    bleiben vertrauenswürdig. Forever hat laut Code keine Instanz-Gruppen; Schlachtfelder werden deshalb
    zusätzlich über `IsInInstance()` erkannt.
  - Pro Absender höchstens ein Angebot alle 30 s.
  - Ist ein Dialog offen, wird das Angebot nicht angezeigt, sondern im Chat erwähnt.
  - Gilt auch für das Verschicken von Wunschlisten per Whisper.

### F05 ✔ – Layer-Modul antwortet jedem per Whisper (mittel, bestätigt)
- **Stelle:** `Modules/MinimapLayer.lua:509` (`OnChosen`), `:562` (`OnMessage`)
- **Problem:** Auf „LR|id“ per Whisper kommt immer eine Antwort „LN|id|busy“, auch ohne eigenes Angebot und mit
  ausgeschalteter Layer-Hilfe.
- **Szenario:** Jeder auf dem Realm kann so prüfen, wer online ist und EldoUI nutzt.
- **Fix-Idee:** Ohne eigenes Angebot (`Layer.offered[tag]`) gar nicht antworten.
- **Umsetzung:** Ohne eigenes Angebot keine Antwort. Wer ein (abgelaufenes) Angebot bekommen hat, erhält
  weiterhin „busy“. Unbeantwortete Angebote werden nach 60 s aus dem Speicher entfernt.

### F06 – Fremdtext mit Link-/Escape-Codes ungefiltert (niedrig–mittel, bestätigt)
- **Stellen:** `Modules/Instances/Reset.lua:122` (Leader-Reset-Namen), `Modules/Hardcore/Core.lua:368`
  (Killer/Zone), `Core/Plugins.lua:101` (Versionstext)
- **Problem:** Text von anderen Spielern geht mit `|H…|h`-Links, Farb- und Textur-Codes in `E:Print` bzw. Alerts.
- **Szenario:** Ein Gruppenleiter schickt `|Haddon:EldoUI:talents:learn|h[Reset-Log]|h`; ein Klick lernt Talente.
- **Fix-Idee:** Fremdtext vor der Anzeige mit `gsub("|", "||")` entschärfen.
- **Umsetzung:**
  - Reset-Namen: `|` verdoppelt, auf 64 Bytes gekürzt.
  - Hardcore: Killer und Zone werden beim Empfang mit derselben `Clean()`-Funktion bereinigt wie beim Senden.
  - Versionscheck: nur Text im Format `1.2.3` bzw. `1.2.3-beta2` (max. 24 Zeichen) wird angezeigt.

### F07 – Strings anderer Versionen abgelehnt, Teil-Importe ohne Migration (niedrig–mittel, bestätigt)
- **Stelle:** `Core/Share.lua:139`, `:831`; `Core/Database.lua:625`
- **Problem:** Ein String mit neuerem/älterem Profilschema meldet „damaged or cut short“. Bei „module:“ und
  „general“ läuft `RunProfileMigrations` nicht.
- **Fix-Idee:** Eigene Meldungen für ältere/neuere Version; Payload vor dem Anwenden migrieren.
- **Umsetzung:**
  - Meldungen: Ein String aus einem neueren EldoUI meldet „the string comes from a newer EldoUI (0.8.0). Update
    EldoUI, then import it again.“ Die Version des Absenders erscheint nur, wenn sie wie eine Version aussieht. Ein
    String von vor 0.7.1000 (ohne `profileBaseline`) meldet, dass diese Version ihn nicht lesen kann. Die Prüfung
    steht in `E:ProfileVersionProblem` (`Core/Database.lua`, neben den Grenzen, die `ProfileData` nutzt). Sie läuft
    vor `PayloadAdmit`; jeder solche String wäre dort ohnehin abgelehnt worden.
  - Migration: „module:“, „general“ und „positions“ laufen jetzt durch `MigratePart` (`Core/Share.lua`). Das baut ein
    Ersatzprofil aus dem Teil und einer Kopie der eigenen allgemeinen Einstellungen (für Migrationen, die das
    Layout lesen). Darauf laufen die verpassten Default-Änderungen (`Data/DefaultChanges.lua`) und die
    Profil-Migrationen. Übernommen wird nur der Teil. Ganze Profile („all“) wurden schon vorher migriert, über
    `SetProfile` bzw. `ApplyProfileParts`.
  - Stempel: Teil-Strings tragen jetzt die Migrations-Stempel des Absender-Profils (`payload.migrations`). Mit
    Stempeln laufen genau die Migrationen, die dem Absender fehlten. Strings ohne Stempel (von EldoUI selbst und
    alle älteren) bekommen nur die Default-Änderungen und die Migrationen ohne Schlüssel. Eine Migration mit
    Schlüssel kann einen alten Wert nicht von einer späteren Wahl unterscheiden: `general:clock` hätte z. B. einem
    aktuellen „general“-String die 24-Stunden-Uhr aufgezwungen. Ältere EldoUI-Versionen ignorieren das neue Feld.
  - Test: `tools/share/test_import_versions.lua` (läuft in `tools/ci/check_all.sh tests`). Er schneidet die echten
    Funktionen aus beiden Dateien und prüft Versionsgrenzen, Meldungen, Stempel und `MigratePart`.
  - Nicht umgesetzt: Werte, die eine Migration aus dem Modul in ein anderes verschiebt (z. B. `Messages.sound` →
    `Chat.whisperSound`), gehen beim Teil-Import verloren, weil nur der eine Teil übernommen wird. Die neuen
    Meldungen waren zuerst nur englisch; seit Verbesserung A2 (`EldoUI_Locale_deDE/Fork.lua`) sind sie auch
    deutsch, ebenso die neuen Texte aus F01, F03 und F04. Share-Arten mit eigenem Präfix (Wunschliste, Pack usw.)
    sind unverändert.
- **Im Spiel geprüft (15.11.2026):** Ein String mit Schema-Version 99 meldet auf Deutsch „… stammt aus einem
  neueren EldoUI …“ statt „beschädigt“. Export und Import von „chat“, „general“ und „all“ laufen wie vorher, ohne
  Lua-Fehler. Der Befehl heißt `/eui exportlua chat`: `module:Chat` meldet „Unbekannte Kategorie“, weil der
  Befehl `module:` selbst ergänzt.

### F08 – Entpackgröße erst nach dem Entpacken geprüft (niedrig–mittel, plausibel)
- **Stelle:** `Core/Share.lua:480`; `Core/Import.lua:179`
- **Problem:** 1–2 MB komprimierte Daten können auf sehr viel mehr entpacken, bevor `#out > MAX_STRING` greift.
  Ob `C_EncodingUtil.DecompressString` selbst begrenzt, ist unklar.
- **Umsetzung:**
  - Neues `E:Inflate(bytes, limit)` (`Core/Share.lua:668`). Es geht vorher den rohen DEFLATE-Strom durch
    (`Inflate.Size`, `:576`) und zählt die Bytes, die beim Entpacken entstünden, ohne sie zu erzeugen. Sobald die
    Summe die Grenze übersteigt, bricht es ab. Ein String, der auf 64 MB entpacken würde, kostet so nur ein paar
    tausend Schritte. Erst wenn die Größe passt, entpackt das Spiel.
  - Gelesen wird jeder Code wie in zlib. Was zlib ablehnt, lehnt auch die Prüfung ab: Blocktyp 3, Kopie von vor dem
    Anfang, Codes 286/287 und 30/31, überbelegte oder unvollständige Code-Tabellen, abgeschnittene Daten.
  - Zusätzlich abgelehnt: mehr als 256 Blöcke plus einer je 64 entpackte Bytes. Solche Ströme schreibt kein
    Encoder (zlib und LibDeflate schreiben einen Block je 16–64 KB). Sie würden nur die Prüfung verlangsamen.
  - EldoUI-Strings (`Decode` in `Share.lua`) und ElvUI-/EllesmereUI-Strings (`Inflate` in `Import.lua`) entpacken
    nur noch über `E:Inflate`. Die Meldungen bleiben dieselben. Nicht geändert: `Modules/Auction.lua` entpackt nur
    die eigenen gespeicherten Auktionsdaten, keine Strings von anderen.
  - Test: `tools/share/test_inflate.lua` (läuft in `tools/ci/check_all.sh tests`). Er schneidet die Prüfung aus
    `Share.lua` und prüft sie mit 779 Strömen, die `tools/share/deflate_cases.py` mit zlib erzeugt: Größe wie
    zlib, abgeschnittene und an einem Bit veränderte Ströme, handgemachte fehlerhafte Ströme, Bomben, Blockgrenze.
    Außerdem prüft er, dass `E:Inflate` zu große und beschädigte Strings nie an `DecompressString` gibt.
  - Kosten: Die Prüfung läuft in Lua und geht jeden Code einzeln durch. Gemessen mit Lua 5.1 auf dem CI-Rechner:
    eine große, profilartige Tabelle (113 KB gepackt, 1 MB entpackt) 0,04 s. Die ungünstigsten Ströme brauchen etwa
    0,3–0,4 s je 500 KB gepackt. Bei voller Länge sind das bis etwa 0,6 s für EldoUI-Strings (1 MB) und 1,2 s für
    ElvUI-/EllesmereUI-Strings (2 MB). Das fällt nur beim Einfügen oder Empfangen an, einmal pro String.

### F09 – Daten ohne Obergrenze (niedrig, bestätigt)
- **Stellen:** `Modules/Blessings.lua:289` (Segensplan nimmt beliebige Namen an, wird nie aufgeräumt);
  `Modules/Messages.lua:359` (jeder neue Whisper-Absender wird dauerhaft gespeichert)
- **Fix-Idee:** Nur Paladine der Gruppe annehmen; Kontakte begrenzen und nach Alter aufräumen.
- **Umsetzung:**
  - Segensplan: nur Zeilen für Paladine in der Gruppe. Ab 40 gespeicherten Namen fallen die weg, die nicht in
    der Gruppe sind.
  - Whisper-Kontakte: höchstens 200; darüber fallen die am längsten stillen weg, nie einer mit offenem Fenster.
  - Nicht umgesetzt: Wiederverwendung der Gesprächsfenster (betrifft nur den Speicher einer Sitzung).

### F10 ✔ – RaidLoot-JSON: `null` verschiebt Array-Elemente (niedrig, bestätigt)
- **Stelle:** `Modules/RaidLoot/Core.lua:239`
- **Problem:** `arr[#arr + 1] = Value()` mit `nil` erhöht den Index nicht: `[a, null, c]` wird zu `{a, c}`.
- **Fix-Idee:** Eigenen Index mitzählen.
- **Bewusst nicht geändert:** Der Leser verarbeitet JSON-Arrays nur als Listen von Objekten (`ipairs`,
  Spaltensuche über Feldnamen, `Modules/RaidLoot/Core.lua:324`). Positionen spielen keine Rolle. Würden
  `null`-Lücken erhalten, bräche `ipairs` beim ersten `null` ab und Einträge gingen verloren. Das heutige
  Zusammenschieben ist hier das bessere Verhalten.

## Kampf und Frames

### F11 – Castbar wertet geheime Werte direkt aus (hoch, plausibel)
- **Stelle:** `Modules/UnitFrames.lua:1597`, `:1626`, `:1648`, `:1875`
- **Problem:** `if not name`, `if targetName`, `if duration` und `if UnitCastingInfo(unit)` (ohne pcall) testen
  Werte, die laut eigener Code-Doku (`:1360`) geheim sein können. Nameplates nutzt dafür `Present()` (`Modules/Nameplates.lua:409`).
- **Szenario:** Ein Gegner castet in einer Instanz → Lua-Fehler bei jedem Cast-Event, Castbar bleibt leer.
- **Fix-Idee:** Wie in Nameplates `Present()` verwenden; `UnitCastingInfo` in pcall.
- **Umsetzung:** Lokales `Present()` in `UnitFrames.lua` (Secret zählt als vorhanden, sonst `~= nil`), an allen
  vier Stellen; `UnitCastingInfo`/`UnitChannelInfo` in `UpdateCast` per pcall. Andere Wahrheitstests auf
  Cast-Info gibt es im Code nicht (Suche).

### F12 – Gruppenframes fallen fälschlich auf Blizzard zurück (mittel, bestätigt)
- **Stelle:** `Modules/GroupFrames.lua:2809` (`ScheduleCheck` / `CheckHeaders`)
- **Problem:** Gezählt werden nur Buttons mit `IsVisible()`. Ist der Holder per Sichtbarkeitsregel versteckt
  („nur im Kampf“, „beritten ausblenden“), ist das Ergebnis 0 → Engine „auto“ schaltet für die Sitzung auf
  Blizzard-Frames, mit irreführender Chatmeldung.
- **Fix-Idee:** Nur werten, wenn der Header selbst sichtbar ist; sonst später erneut prüfen.
- **Umsetzung:** Wie vorgeschlagen. Neu geprüft wird bei jeder Roster-Änderung und bei Kampfende (bestehende Aufrufe).

### F13 ✔ – Drei Event-Handler mit falscher Signatur (mittel, bestätigt)
- **Stellen:** `Modules/ActionBars/RankCheck.lua:488`, `Core/KeybindNewSpells.lua:509`, `Core/KeybindQuietBars.lua:305`
- **Problem:** Der Dispatcher ruft `handler(owner, event, ...)` auf (`Core/Init.lua:105`). Diese drei Handler
  lassen `event` aus: In RankCheck ist `name` immer `"ADDON_LOADED"`, in den beiden anderen ist `isLogin` immer wahr.
  Eine Suche über den ganzen Code fand genau diese drei.
- **Szenario:** Die Rangprüfung im Zauberbuch greift nach dem Laden von Blizzard_PlayerSpells nicht; neu gelernte
  Zauber gehen verloren, wenn kurz danach ein Ladebildschirm kommt.
- **Umsetzung:** Signaturen auf `(_, _, …)` korrigiert, wie bei allen anderen Handlern im Code.

### F14 – Mover ziehen über Kampfbeginn (mittel, plausibel)
- **Stelle:** `Core/Movers.lua:1637` (`OnDragStart`/`OnDragStop`), `:2321`
- **Problem:** Nur `OnDragStart` prüft auf Kampf. Bei Kampfbeginn wird ein laufendes Ziehen nicht gestoppt;
  `OnDragStop` setzt dann im Kampf Punkte.
- **Szenario:** Mover einer Aktionsleiste ziehen, angegriffen werden, loslassen → ADDON_ACTION_BLOCKED.
- **Umsetzung:** Bei `PLAYER_REGEN_DISABLED` (läuft vor der Kampfsperre) wird jeder gerade gezogene Mover
  gestoppt und gespeichert. `OnDragStop` im Kampf merkt sich den Ablegepunkt und speichert ihn nach dem Kampf.
- **Im Spiel geprüft (15.11.2026):** Mover „Atem und Erschöpfung“ in `/eui move` über Kampfbeginn gezogen, dann
  weitergekämpft: kein Eintrag im Fehlerlog (zweimal, in zwei Sessions).

### F15 – Blizzard-Leiste kommt mit „toten“ Buttons zurück (mittel, bestätigt)
- **Stelle:** `Modules/ActionBars.lua:1830` (`HideBlizzardBar`), `:1874` (`ShowBlizzardBar`)
- **Problem:** Beim Verstecken werden die Events der Buttons abgemeldet (laut Kommentar bringt nur `/reload` sie
  zurück). Beim Wieder-Anzeigen fehlt der Reload-Hinweis.
- **Szenario:** Eine EldoUI-Leiste abschalten → Blizzards Leiste erscheint, aktualisiert aber keine Cooldowns/Reichweite.
- **Umsetzung:** `UpdateBlizzardBars` zeigt denselben Reload-Hinweis wie `OnDisable`, sobald eine in dieser
  Sitzung versteckte Leiste zurückkommt. Die Events selbst werden nicht wiederhergestellt, weil unklar ist,
  welche der Forever-Client pro Button erwartet.

### F16 – Click-Casting: Hover-Unit veraltet (niedrig–mittel, plausibel)
- **Stelle:** `Modules/ClickCast.lua:345`
- **Problem:** Die Unit wird nur beim Betreten des Frames kopiert. Ändert der Header danach `unit`, bleibt der alte Token.
- **Szenario:** Maus ruht auf einem Raid-Frame, jemand verlässt im Kampf den Raid → Zauber geht an den Falschen.
- **Umsetzung:**
  - Die Unit wird jetzt bei jedem Tastendruck neu vom Frame unter der Maus geholt, direkt bevor der Hover-Button
    zaubert. Dafür merkt sich `ON_ENTER` den Frame, dessen Tasten es belegt hat (`eldoHovered`), und `ON_LEAVE`
    vergisst ihn wieder, aber nur, wenn es derselbe Frame ist. Die Maus kann den nächsten Frame betreten, bevor der
    alte sein OnLeave bekommt. Ein neuer OnClick-Wrapper auf dem Hover-Button (`ON_CLICK`, `Modules/ClickCast.lua:376`)
    liest dann `unit` und `unitsuffix` dieses Frames.
  - Alle drei Snippets laufen mit demselben Handler und teilen sich so seine Umgebung. Sie benutzen nichts, was
    `ON_ENTER` nicht schon benutzt hat, außer einer globalen Variable in dieser Umgebung und `return false`, das
    Quickdraw genauso nutzt.
  - Hat der Frame beim Tastendruck keine Unit mehr, passiert nichts. Wird der Button ohne Frame unter der Maus
    geklickt (ein `/click`-Makro), behält er seine Unit wie bisher.
  - Lässt sich der Wrapper nicht anlegen, gilt wie bisher die Unit vom Betreten. Schlechter als vorher wird es
    also nicht.
  - Test: `tools/clickcast/test_hover_unit.lua` (läuft in `tools/ci/check_all.sh tests`). Er schneidet die echten
    Snippets und `CreateHoverParts`/`WrapHover` aus `ClickCast.lua` und spielt sie in einem kleinen Nachbau der
    Secure-Handler durch: Override-Bindungen, gemeinsame Umgebung, Abbruch per `false`. Geprüft wird:
    - Unit-Wechsel durch den Header, mit und ohne `unitsuffix`;
    - Frame ohne Unit;
    - nächster Frame betreten vor OnLeave des alten;
    - OnHide und `/click`;
    - ein neues Handle bei jedem Aufruf, für den Fall, dass das Spiel Handles nicht wiederverwendet;
    - ohne Wrapper zeigt das Modell den alten Fehler.
  - Nicht umgesetzt: Bekommt ein Frame erst *nach* dem Betreten eine Unit, sind seine Tasten erst nach erneutem
    Betreten belegt. Das kostet nur einen fehlenden Zauber, keinen falschen. Dafür müsste man auf
    OnAttributeChanged reagieren.

### F17 – Kleinkram (niedrig)
- `Modules/ClickCast.lua:443`, `:1074`: Blizzard-Kompaktframes, die im Kampf entstehen, bekommen keine Bindungen nachgeholt.
- `Modules/ClassPower.lua:1720`, `:1898`: Hooks vergleichen eine evtl. geheime Textur und prüfen nicht, ob das Modul aktiv ist.
- `Modules/Nameplates.lua:2979`: Hook auf `NamePlateDriverFrame` beim Laden der Datei statt über `E:OnBlizzardAddOn`.
- `Modules/Auras.lua:740`: `UNIT_INVENTORY_CHANGED` ohne Unit-Filter.
- **Umsetzung:**
  - ClassPower: Hook ohne Texturvergleich (Guard wie in UnitFrames), beide Hooks prüfen `M.active`.
  - Auras: Event nur noch für `player` registriert.
  - Click-Casting (`e49c371`):
    - Kompaktframes, die Blizzard im Kampf einrichtet (Hook auf `CompactUnitFrame_SetUpFrame`), werden jetzt
      vorgemerkt (`setUpInCombat`). Bisher wurden sie übersprungen. Dasselbe gilt für Frames, die
      `GROUP_ROSTER_UPDATE` im Kampf findet.
    - Nach dem Kampf bekommen sie ihre Bindungen (`PickUpCompactFrames`). Dafür reicht ein einziger Auftrag
      über `E:RunOutOfCombat` mit festem Schlüssel, egal wie viele Frames es sind.
    - Im Kampf wird nichts gesetzt. Ob das Modul, „Blizzard-Frames“ und der Improve-Schalter an sind, wird erst
      geprüft, wenn der Auftrag läuft.
    - Bisher kamen die Bindungen erst mit der nächsten Roster-Änderung außerhalb des Kampfs.
  - Nameplates (`e49c371`):
    - Der Hook auf `NamePlateDriverFrame.OnNamePlateAdded` greift sofort, wenn der Driver beim Laden der Datei
      da ist, sonst sobald `Blizzard_NamePlates` geladen ist. So machen es auch die anderen Driver-Hooks
      (`Nameplates/Size.lua`).
    - Er steht in einem eigenen `do`-Block, weil die Datei nahe an Luas Grenze von 200 lokalen Variablen liegt.
  - Tests (laufen in `tools/ci/check_all.sh tests`):
    - `tools/clickcast/test_compact_combat.lua` schneidet Bindungsattribute, Frame-Liste, `ApplyFrame`,
      `PickUpCompactFrames` und `M:OnEnable` aus `ClickCast.lua`. Er spielt sie mit einem Modell durch, in dem
      `SetAttribute` im Kampf blockiert ist.
    - `tools/nameplates/test_driver_hook.lua` prüft den Hook: Driver beim Laden da, mit und ohne geladenes
      Addon; Driver erst mit dem Addon; kein Driver. Es wird immer genau einmal gehookt.

## Im Spiel gefunden

### F18 – Profilseite bewirkt nichts (mittel, im Spiel bestätigt)
- **Gefunden:** 15.11.2026 beim Spieltest zu F02. „Neues Profil“ mit Namen und Enter: keine Meldung, kein
  Profil, auch nicht in den Saved Variables. Der Fehler steckt schon in EldoUI 0.7.2001 (Upstream).
- **Stelle:** `Core/Config.lua` (Zeilen-Bausteine `builders.input`, `builders.select`, `builders.media`,
  Farbe), `Core/Share.lua:2051` (`ProfileTarget`)
- **Problem:** Eine Zeile setzt den Wert und zeichnet sich dann neu, erst danach reagiert die Seite. Beim
  Textfeld kommt das Neuzeichnen vom Verlust des Fokus, bei der Auswahl direkt danach. Das Neuzeichnen liest das
  Ziel der Seite noch einmal. `ProfileTarget` setzt dabei „Neues Profil“, „Umbenennen“, „Kopieren“ und „Löschen“
  zurück und „Profil für diesen Charakter“ auf das aktuelle Profil. Die Seite sah den Wert also nie.
- **Szenario:** „Neues Profil“ `Test` + Enter → nichts. Ebenso „Umbenennen“; „Profil für diesen Charakter“,
  „Kopieren von“, „Alles kopieren von“ und „Profil löschen“ nach demselben Muster (im Spiel nur „Neues Profil“
  gesehen, die anderen folgen aus dem Code).
- **Umsetzung:** In den vier Bausteinen ruft die Zeile `Changed` (die Seite) vor ihrem eigenen Neuzeichnen
  auf, beim Textfeld vor `ClearFocus`. Auf Seiten, deren Ziel beim Lesen nichts ändert, macht das keinen
  Unterschied. `ProfileTarget` bleibt, wie Upstream es gedacht hat: Aktionsfelder sind nach der Aktion leer.
- **Test:** `tools/config/test_profile_page.lua` (läuft in `tools/ci/check_all.sh tests`). Er schneidet die
  echten Bausteine und `SetOption` aus `Config.lua` und die Profilseite aus `Share.lua` heraus. Das Textfeld
  verliert den Fokus wie im Spiel (`ClearFocus` ruft die Focus-Lost-Skripte sofort). Geprüft werden Enter in
  „Neues Profil“ und „Umbenennen“ sowie eine Auswahl in den vier Listen. Eine Gegenprobe zeigt, dass die alte
  Reihenfolge den Namen verliert. Außerdem prüft er für jede Zeile in `Config.lua`, die sich nach dem Setzen
  neu zeichnet, dass die Seite vorher reagiert.
- **Im Spiel geprüft (15.11.2026):** Neues Profil anlegen, mit der Auswahl zurückwechseln, Profil löschen:
  alles wie erwartet. Alle Frames standen nach dem Zurückwechseln an ihrem Platz (zugleich der Test zu F02).

### F19 – Ausgeblendete Blizzard-Leisten blockiert im Kampf (mittel, im Spiel bestätigt)
- **Gefunden:** 15.11.2026 im Fehlerlog nach dem Kampftest (Brachland). Einträge „Blocked: EldoUI tried to call
  the protected function ActionButton<n>:SetShown()“ und „MainActionBarButtonContainer<n>:SetShown()“, Ablauf
  `OnActionBarSlotChanged` → `UpdateAction` → `UpdateShownButtons` (Blizzards eigener Code). Nachgestellt in
  einer frischen Session ohne Profilwechsel: ein Zauber im Kampf auf Leiste 1 gelegt, 25 neue Einträge. Der Fehler
  steckt schon in EldoUI 0.7.2001 (Upstream).
- **Stelle:** `Modules/ActionBars.lua` (`HideBlizzardBar`, `ShowBlizzardBar`)
- **Problem:** EldoUI setzte beim Ausblenden von Blizzards Leisten 1–8 auf jeden Knopf das Attribut
  `statehidden`. Blizzards `UpdateShownButtons` liest genau dieses Attribut, wenn es entscheidet, welche Knöpfe
  zu sehen sind, auch im Kampf bei jedem Platzwechsel der Leiste. Ein Attribut, das ein Addon gesetzt hat, zählt
  als Wert des Addons: Blizzards Update lief damit als EldoUIs Code, und das Spiel sperrte im Kampf jedes
  `SetShown` darin. Zu sehen war nichts (die Knöpfe sind ohnehin unsichtbar), aber das Log lief voll. Die alte
  Anmerkung zu den Grid-Ereignissen hatte denselben Fehler schon gesehen und dem versteckten Zustand
  zugeschrieben.
- **Szenario:** Leiste 1 von EldoUI an, Blizzards Leiste ausgeblendet („auto“). Im Kampf einen Zauber auf
  einen Platz der Leiste legen oder zwei Knöpfe tauschen → 12 + 12 blockierte Aufrufe pro Platzwechsel.
- **Umsetzung:** Kein Attribut mehr auf Blizzards Knöpfen; ausgeblendet bleiben sie durch den versteckten
  Elternrahmen, wie die Leiste selbst. Blizzards Update darf sie jetzt sauber ein- und ausblenden, sie bleiben
  unsichtbar. Grid-Ereignisse, `UnregisterAllEvents` und `Hide` bleiben wie gehabt.
- **Test:** `tools/actionbars/test_hidden_blizzard_bars.lua` (läuft in `tools/ci/check_all.sh tests`). Er
  schneidet die Tabelle `BARS` und den Block zum Aus- und Einblenden aus `ActionBars.lua` heraus. Darum ein
  Modell der Leisten und Knöpfe mit der Regel des Spiels: Ein vom Addon gesetztes Attribut macht den Code, der
  es liest, zum Code des Addons; im Kampf wird dann jedes `SetShown` gesperrt. Geprüft werden: kein Attribut beim
  Aus- und Einblenden, Blizzards Update im Kampf läuft ungesperrt, kein Knopf einer ausgeblendeten Leiste ist zu
  sehen, die Grid-Ereignisse kommen mit der Leiste zurück. Eine Gegenprobe mit dem alten Code ergibt die
  gesperrten Aufrufe aus dem Spiel.
- **Im Spiel geprüft (15.11.2026):** Mit der Korrektur im Kampf wieder einen Zauber auf Leiste 1 gelegt bzw.
  Knöpfe getauscht, danach `/reload`: kein neuer Eintrag im Fehlerlog (vorher 25 pro Versuch), die Leiste zeigt
  den Zauber.
- **Noch offen, zweiter Eintrag aus derselben Session:** „MainActionBar:SetPointBase()“ und
  „MultiBarBottomLeft/Right:ClearAllPointsBase()/SetPointBase()“, Ablauf `PetActionBar:Update` → `Hide` →
  `UpdateVisibility` → `EditModeManagerFrame:UpdateActionBarLayout` → `UpdateBottomActionBarPositions`, 35-mal
  in knapp zwei Minuten Kampf. In drei späteren Sessions nicht nachgestellt: Kampf mit vielen Zielwechseln, ein
  neues Profil angelegt und zurückgewechselt ohne Neuladen, `/eui move` mit dem Mover „Atem und Erschöpfung“
  über Kampfbeginn gezogen (F14). In jener Session lief außerdem `/eui perf`, und das Profil wurde umbenannt.
  Ein Taint-Log schreibt der Client nicht (`/console taintLog 1` ohne Datei). Bleibt beobachtet: Kommt der
  Eintrag wieder, zählt, was in der Session davor geschah.

### F20 – Die Angeltaste erreicht den Schwimmer nicht (mittel, Ursache im Spiel bestätigt)
- **Gefunden:** 15.11.2026. Die Angeltaste wirft aus. Liegt der Schwimmer draußen, meldet ein Druck „Ihr müsst
  Euch näher an Eurem Ziel befinden, um mit diesem zu interagieren.“ oder tut nichts. Der Fehler steckt schon in
  EldoUI 0.7.2001 (Upstream).
- **Stelle:** `Modules/Fishing.lua` (`M:ApplyCVars`, `M.SOFT_INTERACT`, Option „Same key loots the bobber“)
- **Problem:** Mit dem Schwimmer draußen ist die Taste „Mit Ziel interagieren“. Den Schwimmer dafür wählt die
  Soft-Interaktion des Spiels, und die stand auf den Vorgaben des Clients:
  - `SoftTargetInteract` 1: nur für das Gamepad.
  - `SoftTargetInteractRange` 10: Der Schwimmer landet weiter draußen.
  - `SoftTargetInteractArc` 0: nur genau geradeaus.

  Ohne Soft-Ziel spricht die Taste das feste Ziel an, hier einen weit entfernten Spieler. EldoUI hielt
  `SoftTargetInteract` für geschützt und bot dafür nur auf der Optionsseite einen Chatbefehl an. Reichweite und
  Winkel prüfte es gar nicht.
- **Im Spiel gemessen (15.11.2026):**
  - Mit den Vorgaben und dem Schwimmer draußen: `UnitName("softinteract")` = `nil`, Ziel „Hermano“, die Taste
    auf `interact`.
  - Mit 3, 30 und Winkel 0 noch immer kein Soft-Ziel.
  - Mit 3, 30 und 1 nennt `softinteract` den Schwimmer (`GameObject-…`, „Schwimmer“), und ein Druck beim
    Platschen holt den Fang.
  - `C_CVar.SetCVar` aus `/run` (also mit den Rechten eines Addons) hielt bei `SoftTargetInteractRange` (30)
    und bei `SoftTargetInteract` (2).
- **Umsetzung:**
  - Solange „Same key loots the bobber“ an ist, hebt der Angelmodus die drei Werte an:
    - `SoftTargetInteract`: Maus und Tastatur kommen dazu (0 → 2, 1 → 3).
    - Reichweite: auf 30.
    - Winkel: auf 1 (vor Euch).
  - Höhere eigene Werte bleiben.
  - Wie die Lautstärke laufen die drei über `E:SetCVar` mit eigenem Eintrag. Wenn der Angelmodus endet, auch
    nach einem Reload mitten im Angeln, kommen die eigenen Werte zurück.
  - Einen alten Eintrag zu `SoftTargetInteract` verwirft das Modul einmal. Er stammt aus einer Version, deren
    Schreiben das Spiel abgelehnt hatte.
  - Den Chatbefehl zeigt die Optionsseite nur noch, wo das Spiel `SoftTargetInteract` als geschützt meldet.
- **Test:** `tools/fishing/test_fishing.lua` (läuft in `tools/ci/check_all.sh tests`).
  - Er lädt das echte `Fishing.lua` und den echten CVar-Teil aus `Core/Blizzard.lua`. Drumherum steht ein Modell
    der CVars mit Schutz-Flag, der Override-Bindungen, des Beutefensters und der Ereignisse.
  - Geprüft wird:
    - Die Vorgaben werden zu 3/30/1, danach sind die eigenen Werte zurück.
    - Höhere Werte bleiben, 0 wird 2.
    - Mit der Option aus ändert sich nichts. Abschalten mitten im Angeln gibt die Werte sofort zurück.
    - Ein geschütztes `SoftTargetInteract` bleibt unberührt, die Optionsseite zeigt dann den Chatbefehl.
      Reichweite und Winkel steigen trotzdem.
    - Ein alter Eintrag wird einmal verworfen. Ein Reload mitten im Angeln gibt die eigenen Werte zurück.
- **Noch offen:** Was `C_CVar.GetCVarInfo` auf diesem Client als Schutz-Flag meldet (sechster Rückgabewert).
  Die Abfrage im Spiel las versehentlich den siebten (`false`). Meldet das Spiel `SoftTargetInteract` als
  geschützt, lässt EldoUI die Einstellung in Ruhe, und die Optionsseite zeigt den Chatbefehl.

### F21 – Das Fangprotokoll bleibt bei 0 (niedrig–mittel, Ursache im Spiel bestätigt)
- **Gefunden:** 15.11.2026. Die Fänge landen in den Taschen, die Zählung auf der Angelleiste bleibt bei 0. Der
  Fehler steckt schon in EldoUI 0.7.2001 (Upstream).
- **Stelle:** `Modules/Fishing.lua` (`M:OnLootOpened`, Ereignisliste)
- **Problem:** Das Modul zählte einen Fang nur bei `LOOT_OPENED`. Mit Auto-Loot schickt WoW: Forever für einen
  Fang aber nur `LOOT_READY` und `LOOT_CLOSED`, nie `LOOT_OPENED`.
- **Im Spiel mitgeschnitten (15.11.2026):**
  - Die Reihenfolge: Ende der Kanalisierung, `LOOT_READY`, zweimal `LOOT_CLOSED`, `ITEM_PUSH`, `CHAT_MSG_LOOT`.
  - Bei `LOOT_READY` meldet `IsFishingLoot()` `true`, es gibt einen Platz, der Fisch ist lesbar, der Angelmodus
    ist an.
  - Ob `LOOT_OPENED` grundsätzlich ausbleibt oder nur wegen EldoUIs „Faster auto loot“ (beim Spieler an), ist
    offen. Der Fix braucht die Antwort nicht.
- **Umsetzung:**
  - Gezählt wird bei `LOOT_READY` oder `LOOT_OPENED`, je nachdem, was zuerst kommt, und einmal pro Beute.
  - Es zählt das erste Ereignis, bei dem die Beute einen Platz hat. Danach zählt nichts mehr bis `LOOT_CLOSED`
    oder bis zum nächsten Auswurf.
- **Test:** `tools/fishing/test_fishing.lua` (siehe F20). Geprüft wird:
  - Ein Fang zählt bei `LOOT_READY`.
  - Ein zweites `LOOT_READY` und ein späteres `LOOT_OPENED` zählen nicht doppelt.
  - `LOOT_OPENED` allein zählt.
  - Ein `LOOT_READY` ohne Platz wartet auf das nächste.
  - Andere Beute zählt nie.
  - Fehlt `LOOT_CLOSED`, zählt nach dem nächsten Auswurf wieder ein Fang.
  - Außerhalb des Angelmodus zählt nichts.
- **Nicht geprüft:** ob die Skill-ups im Protokoll ankommen (`GetProf### F22 – Auktionshaus: leere Verkaufen-Seite, Rechtsklick in die Taschen verboten (mittel, teilweise)
- **Gefunden:** 16.11.2026. Im Fehlerlog stand aus Sitzung 59 (15.11. 23:32 bis 16.11. 00:18, Orgrimmar, außerhalb des
  Kampfes, 51-mal) „Forbidden: EldoUI tried to call the protected function UNKNOWN() at
  Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:1611“: `UseContainerItem` aus `ContainerFrameItemButton_OnClick`, also
  ein Rechtsklick auf einen Gegenstand in EldoUIs Taschenfenster. Der Spieler war an Bank, Auktionshaus und Berufslehrern.
- **Vorgehen:** Blizzards Code aus der öffentlichen Kopie Gethe/wow-ui-source, Zweig `ptr` (12.1.7, Build 70892; der
  Forever-Client ist 70888, die Zeilen des Stapels passen). EldoUIs Taschenknöpfe sind sauber: Sie nutzen
  `ContainerFrameItemButtonTemplate`, die Taschennummer geht über Blizzards Attribut `bagid`. Vor `UseContainerItem` liest
  Blizzard nur den Händler-Tab, den Modus des Auktionshauses (`IsListingAuctions`) und den Bank-Typ. `/console taintLog 1`
  schreibt auf Forever kein `Logs/taint.log`, deshalb Nachstellen im Spiel.
- **Im Spiel nachgestellt (16.11.2026):** Gegenstand per Rechtsklick in Blizzards Verkaufen-Seite, dann EldoUIs Tab
  „Schnellverkauf“, dann zurück auf Blizzards „Verkaufen“: Das Fenster blieb leer (nur der Titel „Auktionen einstellen“),
  der Gegenstand blieb im Verkaufsplatz gesperrt (ausgegraut) und ließ sich nicht verkaufen. Ein neuer Eintrag im
  Fehlerlog entstand dabei nicht.
- **Ursache 1, behoben:** `Modules/Auction.lua`. EldoUIs Haken an Blizzards `SetDisplayMode` nahm an, Blizzard habe danach
  seine Seiten selbst gezeigt, und holte die von EldoUI weggelegten nicht zurück. Blizzards `SetDisplayMode` kehrt aber
  sofort zurück, wenn der Modus schon gilt (`Blizzard_AuctionHouseFrame.lua`). Das passiert beim Verkaufen-Tab, solange
  ein Gegenstand im Verkaufsplatz liegt, und bei einem Rechtsklick auf Schnellverkauf. Jetzt merkt sich EldoUI Blizzards
  Modus beim Weglegen (`modeAway`). Bleibt er gleich, kommen die Seiten zurück (`M:OnBlizzardDisplayMode`).
- **Ursache 2, vermutet (Code gelesen), noch offen:** Ein Klick auf ein Ergebnis der Einkaufsliste öffnet Blizzards
  Kaufbildschirm aus EldoUIs Code (`OpenBuy` → `AuctionHouseFrame:SelectBrowseResult` → `SetDisplayMode`). Der Modus gilt
  danach als von EldoUI verunreinigt. Jeder Rechtsklick in die Taschen am Auktionshaus liest ihn (`IsListingAuctions`) und
  läuft dann verunreinigt: Bei einem Gegenstand, der nicht einstellbar ist, endet er in `UseContainerItem`, und das Spiel
  sperrt ihn. Das bleibt so, bis Blizzard selbst in einen anderen Modus wechselt (ein Tab mit anderem Modus). Das würde den
  Eintrag aus Sitzung 59 erklären; ob die Einkaufsliste damals benutzt wurde, ist nicht bekannt.
  - Prüfung im Spiel: Einkaufsliste, suchen, auf ein Ergebnis klicken (Blizzards Kaufbildschirm öffnet sich), dann
    `/run print(issecurevariable(AuctionHouseFrame,"displayMode"))`. Erwartung, falls die Vermutung stimmt: `false EldoUI`.
  - Abhilfe: Blizzards Kaufbildschirm nicht mehr aus EldoUI öffnen. Zum Beispiel setzt EldoUI nur den Namen in Blizzards
    Suchfeld (der Text eines Eingabefelds verunreinigt nichts), und Suche und Ergebnis klickt der Spieler bei Blizzard selbst.
    Das ist ein Klick mehr; die Entscheidung liegt beim Nutzer.
- **Test:** `tools/auction/test_native_screens.lua` (läuft in `tools/ci/check_all.sh tests`). Er schneidet die echte
  Seiten-Buchhaltung und `ShowPage`/`HidePanel` aus `Auction.lua` und lässt sie gegen ein Modell von Blizzards Fenster laufen
  (nach `SetDisplayMode`, `SetPostItem` und den Tabs von 12.1.7, mit der Rückkehr bei gleichem Modus). Geprüft: der Fall aus
  dem Spiel; Kaufen-Tab nach der Einkaufsliste; ein Tab mit neuem Modus überlässt Blizzard die Seiten; Rechtsklick auf
  Schnellverkauf (von Verkaufen und von Kaufen aus); Schließen; eine geschützte Seite wartet bis nach dem Kampf.
- **Im Spiel prüfen:** wie oben nachgestellt (Verkaufen, Gegenstand, Schnellverkauf, Verkaufen). Erwartung: Blizzards
  Verkaufen-Seite mit dem Gegenstand ist wieder da, er lässt sich einstellen.
- **Nebenbei im Fehlerlog gesehen:** „Blocked: … at EldoUI/Modules/InfoBar.lua:800“ (`GuildTooltip`, im Kampf, Eschental,
  3-mal, zuletzt 16.11. 11:11 in Sitzung 65): Der Gilden-Tooltip der Infoleiste fragt im Kampf `C_GuildInfo.GetMOTD` ab.
  Nicht untersucht.

b es sich nachstellen lässt.

## Sonstiges

- **Toter Code:** rund 25 ungenutzte lokale Funktionen und ungenutzte Variablen (luacheck W211). Reste von
  Umbauten, keine Auswirkung.

## Im Spiel prüfen (nach den Änderungen)

Vorher den Ordner `WTF` sichern. Nach dem Login mit `/eui errors` auf neue Fehler schauen.

Die letzte Spalte hält fest, was am 15.11.2026 im Spiel geprüft wurde (WoW: Forever 1.60.1, deutscher Client,
Paladin Stufe 24, allein). „Keine Abweichung gemeldet“: Der Schritt war dran, eine Rückmeldung dazu kam nicht.

| Fix | Was ausprobieren | Erwartung | Im Spiel (15.11.2026) |
|---|---|---|---|
| F11 | Ziel/Fokus auf einen castenden Gegner in einem Dungeon | Castbar läuft, keine Lua-Fehler | draußen ohne Abweichung (Ziel und Fokus auf einem zaubernden Gegner); im Dungeon offen |
| F12 | Raid-Sichtbarkeit „nur im Kampf“, außerhalb des Kampfs einer Gruppe beitreten | keine Meldung „Secure group headers did not create any frames“, EldoUI-Frames im Kampf | offen (Gruppe) |
| F13 | Zauberbuch öffnen (erstes Mal nach Login) | Rangprüfung/Zauberbuch-Button sofort da | keine Abweichung gemeldet |
| F14 | `/eui move`, einen Mover ziehen und dabei in den Kampf kommen | kein ADDON_ACTION_BLOCKED; Mover bleibt dort liegen | bestätigt: kein Eintrag im Fehlerlog (Mover „Atem und Erschöpfung“, zwei Sessions) |
| F15 | eine EldoUI-Aktionsleiste abschalten | Reload-Hinweis erscheint | bestätigt: der Hinweis erschien |
| F03 | eigenen Snapshot mit einem Makro mit `/run` exportieren (`/eui snapshot take`, `export`), das Makro löschen, den String mit `/eui import` einfügen. Nur das Wiederherstellen-Fenster prüfen, das sich danach von selbst öffnet (Titel mit „importiert“); in `/eui snapshot list` ist der importierte Snapshot Nr. 1, der eigene rutscht auf Nr. 2 | Warnung im Import-Dialog; neben „Fehlende Makros hinzufügen“ steht „1 fehlend, 1 davon führen Lua-Code aus“, das Kästchen ist nicht angehakt, der Tooltip zeigt das Makro mit „(führt Lua-Code aus)“. Die Platzliste zeigt beim gelöschten Makro „vorher leer“ | bestätigt, im zweiten Anlauf (der erste öffnete den eigenen Snapshot, siehe F03) |
| F02 | Profil wechseln / Layout anwenden | alle Frames an ihrem Platz wie vorher | bestätigt: neues Profil, zurück, alle Frames an ihrem Platz |
| F18 | Profile: „Neues Profil“ + Enter, dann über „Profil für diesen Charakter“ zurück, dann „Profil löschen“ | Profil wird angelegt (Einrichtung öffnet sich), Wechsel und Löschen wirken | bestätigt |
| F19 | im Kampf einen Zauber auf Leiste 1 legen oder zwei Knöpfe tauschen, danach `/reload` | kein neuer Eintrag „ActionButton<n>:SetShown()“ im Fehlerlog; Leiste 1 zeigt den neuen Zauber | bestätigt: kein neuer Eintrag (vorher 25 je Versuch) |
| F20 | vorher die Soft-Interaktion auf die Vorgaben zurück (`/console SoftTargetInteract 1`, `/console SoftTargetInteractRange 10`, `/console SoftTargetInteractArc 0`); Angel anlegen, mit der Angeltaste auswerfen, ein entferntes Ziel ausgewählt lassen, beim Platschen die Taste drücken | der Fang kommt; währenddessen zeigt `/run local g=C_CVar.GetCVar print(g("SoftTargetInteract"),g("SoftTargetInteractRange"),g("SoftTargetInteractArc"))` `3 30 1` | offen |
| F20 | Angel ablegen (der Angelmodus endet), derselbe Befehl | wieder `1 10 0` | offen |
| F21 | ein paar Fische fangen, Maus auf die Zählung der Angelleiste | die Zahl steigt pro Fang um 1, der Tooltip zeigt Ort und Fische | offen |
| F17 | Persönliche Ressourcenanzeige (falls genutzt) | Leisten mit EldoUI-Textur | offen |
| F17 | Blizzard-Raidframes mit „Improve“ und Click-Casting an; im Kampf jemanden in die Gruppe einladen oder einen Raid bilden lassen, nach dem Kampf mit einer Click-Cast-Bindung auf den neuen Frame klicken | Bindung wirkt sofort nach dem Kampf, nicht erst nach der nächsten Gruppenänderung | offen (Gruppe) |
| F17 | Nameplates im EldoUI-Modus, an einer Gruppe Gegner vorbeilaufen | wie vorher; keine Lua-Fehler beim ersten Erscheinen der Plates | keine Abweichung gemeldet, keine Lua-Fehler im Log |
| F07 | `/eui exportlua chat`, im Text `["version"]` des Schemas auf 99 setzen, mit `/eui import` einfügen | Meldung „comes from a newer EldoUI“ statt „damaged“ | bestätigt |
| F07 | einen Modul-String und „General“ exportieren und wieder importieren | Import wie vorher, keine Lua-Fehler; im Lua-Export steht `["migrations"]` | bestätigt (`chat` und `general`, `["migrations"]` im Lua-Export) |
| F08 | „All“ exportieren (`/eui export all`) und mit `/eui import` wieder einfügen; einen ElvUI-Profilstring einfügen | Vorschau wie vorher, ohne spürbare Verzögerung; keine Lua-Fehler | „All“ bestätigt (Vorschau ohne Verzögerung, dann abgebrochen); ElvUI-String offen |
| F08 | einer Gruppe oder Gilde per „Send to“ ein Profil schicken | kommt an wie vorher | offen (Gruppe oder Gilde) |
| F16 | eine Taste oder das Mausrad als Click-Cast-Bindung anlegen (`/eui clickcast`), über einem Gruppenframe drücken | Zauber geht an die Person auf dem Frame, keine Lua-Fehler | offen (Gruppe) |
| F16 | Maus auf einem Raid-Frame ruhen lassen, jemand weiter oben verlässt den Raid (am besten im Kampf), dann die Taste drücken | Zauber geht an die Person, die der Frame *jetzt* zeigt | offen (Gruppe oder Raid) |
| F16 | eine Taste mit gedrückter Umschalt-/Strg-Taste und das Mausrad je einmal ausprobieren | wie vorher | offen (Gruppe) |
