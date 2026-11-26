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
| F05 ✔ | Layer-Modul antwortet jedem per Whisper | mittel | behoben (Teil seit 0.7.3000, ganz seit 0.7.3002 von EldoUI) | `3deb369`, `c323ceb`, `f9c0fc9` |
| F06 | Fremdtext mit Link-/Escape-Codes ungefiltert im Chat | niedrig–mittel | behoben | `eee687e` |
| F07 | Strings anderer Versionen als „beschädigt“ abgelehnt, Teil-Importe ohne Migration | niedrig–mittel | behoben (Meldung seit 0.7.3000 von EldoUI) | `419d511`, `c323ceb` |
| F08 | Entpackgröße erst nach dem Entpacken geprüft | niedrig–mittel | behoben | `d6042ce` |
| F09 | Segensplan und Whisper-Kontakte ohne Obergrenze | niedrig | behoben | `3b0c340` |
| F10 ✔ | RaidLoot-JSON: `null` verschiebt Array-Elemente | niedrig | bewusst nicht | |
| F11 | Castbar wertet geheime Werte direkt aus | hoch (plausibel) | behoben | `e5844d2` |
| F12 | Gruppenframes fallen fälschlich auf Blizzard zurück | mittel | behoben | `5c3b9c6` |
| F13 ✔ | Drei Event-Handler mit falscher Signatur | mittel | behoben | `1dc7a1d` |
| F14 | Mover ziehen über Kampfbeginn → ADDON_ACTION_BLOCKED | mittel (plausibel) | behoben (seit 0.7.3000 von EldoUI) | `8f18ddf`, `c323ceb` |
| F15 | Blizzard-Leiste kommt mit „toten“ Buttons zurück | mittel | behoben | `c0345a9` |
| F16 | Click-Casting: Hover-Unit veraltet nach Roster-Änderung | niedrig–mittel (plausibel) | behoben | `2731180` |
| F17 | Kleinkram: Click-Bindungen, Secret-Checks, Unit-Filter | niedrig | behoben | `9159f19`, `e49c371` |
| F18 | Profilseite: „Neues Profil“, „Umbenennen“ und die Auswahllisten bewirken nichts (im Spiel gefunden) | mittel | behoben | `c6ef76c` |
| F19 | Ausgeblendete Blizzard-Aktionsleisten: Platzwechsel im Kampf → ADDON_ACTION_BLOCKED (im Spiel gefunden) | mittel | behoben | `512df80` |
| F20 | Angeln: Die Angeltaste erreicht den Schwimmer nicht, „Ihr müsst Euch näher an Eurem Ziel befinden …“ (im Spiel gefunden) | mittel | behoben | `cfebaee` |
| F21 | Angeln: Das Fangprotokoll bleibt bei 0 (im Spiel gefunden) | niedrig–mittel | behoben | `cfebaee` |
| F22 | Auktionshaus: Verkaufen-Seite bleibt nach „Schnellverkauf“ leer; Rechtsklick in die Taschen verboten (im Spiel gefunden) | mittel | teilweise | `391f0b7` |
| F23 | Gilden-Tooltip der Infoleiste fragt im Kampf die Gildennachricht ab → ADDON_ACTION_BLOCKED (im Fehlerlog gefunden) | niedrig | behoben | `bb28608` |
| F24 | Nach einem Bankbesuch ist jeder Rechtsklick zum Benutzen aus den Taschen verboten, bis zum Reload (im Spiel gefunden) | hoch | behoben (im Spiel offen) | |
| F25 | Das Koordinatenfeld (und der Wegpfeil) lässt sich nicht verschieben: im Verschiebemodus nur unter „Alle Rahmen“ (im Spiel gefunden) | niedrig | behoben (im Spiel offen) | `d1fece9` |
| F26 | In einer Gruppe keine Schadenszahlen über Gegnern: Plakettenzahlen aus, Blizzards trotzdem auf 0 (im Spiel gefunden) | mittel | behoben (im Spiel offen) | `1c693b8` |
| F27 | Post: Ein Twink aus dem Adressbuch kommt nur mit Vornamen ins Feld „An“, der Brief scheitert (im Spiel gefunden) | mittel | behoben (im Spiel offen) | `3058828`, `0e18af3` |
| F28 | Gildenhandwerker: Listen und „Flüstern“ nur mit Vornamen, Handwerker erscheinen offline (bei F27 gefunden) | mittel | behoben (im Spiel offen) | `493c8cf` |
| F29 | Weltkarte und Questlog: L, M und Escape melden immer wieder „Blocked: EldoUI tried to call the protected function SetPassThroughButtons()“ (EldoUI-Issue #5) | mittel | behoben (plausibel, im Spiel offen) | |

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

## Nach dem Update auf EldoUI 0.7.3001 (16.11.2026)

Der Fork steht seit `c323ceb` auf EldoUI 0.7.3001 (vorher 0.7.2001; Weg in `tools/ci/README.md`). EldoUI 0.7.3000
behebt einige der Fehler unten selbst. Absprache mit dem Nutzer: Dann gilt EldoUIs Lösung, und der Fork behält nur
den Teil, den EldoUI nicht abdeckt. Geprüft wurde jeder Fix-Commit gegen den Code von 0.7.3001 (nicht im Spiel).

| Nr. | In 0.7.3001 | Was im Fork bleibt |
|---|---|---|
| F05 | Teilweise: EldoUI wartet bei wiederholten Anfragen eines Spielers, begrenzt die offenen Angebote auf 32 und vergisst ein Angebot nach 61 s (`Modules/MinimapLayer.lua`, `ForgetOffer`). Ein „LR“ von jemandem ohne Angebot beantwortet es aber weiter mit „busy“. | Keine Antwort ohne eigenes Angebot (`OnChosen`). Das Aufräumen alter Angebote ist EldoUIs. |
| F07 | Teilweise: EldoUI nennt bei einem String aus einer neueren oder unlesbaren Version den Grund (`PayloadAdmit`, „it was made with a newer EldoUI (%s)“). Teil-Importe migriert es weiter nicht. | Die Migration von Teil-Importen (`MigratePart`, Stempel in `BuildPayload`). Die eigenen Meldungen (`VersionMessage`, `E:ProfileVersionProblem`) und ihre drei deutschen Texte sind weg. |
| F14 | Ja: `E:EndMoverDrag` beendet einen Zug bei Kampfbeginn und speichert die Stelle nach dem Kampf; der Verschiebemodus geht danach wieder auf. | Nichts; F02s Punktprüfung in `Core/Movers.lua` bleibt. |
| F01–F04, F06, F08, F09, F11–F13, F15–F21 | Nein (Code an diesen Stellen gleich oder nur verschoben). | Alles. F18 sitzt jetzt in EldoUIs neuen Funktionen `Set` (Auswahl) und `Apply` (Farbe), die auch die Tastatur nutzt. |
| F22 | Unverändert (teilweise behoben). Der Hotfix 0.7.3001 („Right-clicking a potion … uses it again“) betrifft einen Fehler aus 0.7.3000 (`WatchJunkSlot` ersetzte den Klick-Handler der Taschenplätze), nicht die Ursache von F22. | F22s Auktionshaus-Fix (PR #36). |

## Nach dem Update auf EldoUI 0.7.3005 (19.11.2026)

Der Fork steht seit `f9c0fc9` auf EldoUI 0.7.3005 (vorher 0.7.3001; dazwischen 0.7.3002, 0.7.3003 und 0.7.3004).
Geprüft wurde jeder Fix gegen den Code von 0.7.3005 (nicht im Spiel). Nur sechs Dateien hatten beide geändert:
`EldoUI.toc`, `CHANGELOG.md`, `Core/Media.lua`, `Modules/InfoBar.lua`, `Modules/MinimapLayer.lua` und
`Modules/Nameplates.lua`. Konflikte gab es nur in der TOC (Versionszeile) und in `MinimapLayer.lua`.

| Nr. | In 0.7.3005 | Was im Fork bleibt |
|---|---|---|
| F05 | Ja, ganz: 0.7.3002 baut den Layerwechsel neu, auf dem Netz des verbreitetsten Layer-Addons. „LR“, `OnChosen` und die Angebotsliste gibt es nicht mehr. Ohne „Help others hop“ (Standard: aus) antwortet `Layer.OnAsk` niemandem; wer hilft, antwortet mit Absicht jedem, der fragt, und nennt dabei Layer und Gebiet (das ist das Netz; höchstens alle 10 s je Spieler, eingeladen wird nur im selben Gebiet, höchstens sechs Einladungen in zehn Minuten). | Nichts: `Modules/MinimapLayer.lua` ist wieder ganz EldoUIs. |
| F23 | Nein: Der Gilden-Tooltip ist unverändert. EldoUIs Änderung in `InfoBar.lua` betrifft den Klick auf die Kartenblöcke (`E:OpenWorldMapAt` statt `ToggleWorldMap`). | Alles. |
| F01–F04, F06–F22 | Nein: Code an diesen Stellen gleich. | Alles. |

## Nach dem Update auf EldoUI 0.7.3100 (23.11.2026)

Der Fork steht seit `b850d60` auf EldoUI 0.7.3100 (vorher 0.7.3005; dazwischen 0.7.3006). Geprüft wurde jeder Fix
gegen den Code von 0.7.3100 (nicht im Spiel). Beide hatten elf Dateien geändert: `EldoUI.toc`, `CHANGELOG.md`,
`Bindings.xml`, `Core/Bindings.lua`, `Modules/Bags/Core.lua`, `Modules/Chat/Core.lua`, `Modules/ConsumableBar.lua`,
`Modules/DBM.lua`, `Modules/Gathering/Core.lua`, `Modules/InfoBar.lua` und `Modules/QoL.lua` (dazu die Titelzeilen der
TOCs von `EldoUI_Locale_daDK` und `EldoUI_LootSim`). Konflikte gab es nur in der TOC (Versionszeile), im CHANGELOG und
bei den Tastenbelegungen (EldoUIs neue Tasten der Verbrauchsgüterleiste neben denen der Questgegenstandsleiste).

| Nr. | In 0.7.3100 | Was im Fork bleibt |
|---|---|---|
| F24 | Nein: In `Modules/Bags/Core.lua` gibt EldoUI nur `CanBuyTab` als `M.CanBuyBankTab` heraus, für die neue Schaltfläche „Nächsten Bankreiter kaufen“ auf der Seitenleiste des Bankfensters (`Modules/Bags/BankActions.lua`). Sie ist wie das Plus auf der Taschenleiste seit 0.7.3005 die Kaufschaltfläche des Spiels; ohne sie öffnet sie Blizzards Bankfenster (`M:ShowBlizzardBank`, wie bisher). Neue Aufrufe von `OpenAllBags`, `CloseAllBags` oder `ToggleAllBags` gibt es nicht (im ganzen Addon gesucht; die Textprüfung in `tools/bags/test_game_bag_code.lua` liest nur `Bags/Core.lua`, `InfoBar.lua` und `FlightView.lua`). Die Gegenprüfung fand dabei einen alten Weg, den F24 nicht abdeckte: den Finder (siehe F24, inzwischen behoben). | Alles. |
| F23 | Nein: Der Gilden-Tooltip ist unverändert. EldoUIs Änderungen in `InfoBar.lua` sind der neue Block „PvP rank“ und die Trefferwertung in den Blöcken Hit und Spell hit. | Alles. |
| F01–F22 | Nein: Code an diesen Stellen gleich. | Alles. |

## Nach dem Update auf EldoUI 0.7.4001 (26.11.2026)

Der Fork steht seit `efe68ce` auf EldoUI 0.7.4001 (vorher 0.7.3100; dazwischen 0.7.4000). Geprüft wurde jeder Fix
gegen den Code von 0.7.4001 (nicht im Spiel). Beide hatten zehn Dateien geändert: `EldoUI.toc`, `CHANGELOG.md`,
`Core/Commands.lua`, `Core/Init.lua`, `Core/Share.lua`, `Data/AddonFit.lua`, `Modules/ActionBars.lua`,
`Modules/Auction.lua`, `Modules/Minimap.lua` und `Modules/UnitFrames.lua` (dazu die Titelzeilen der TOCs von
`EldoUI_Locale_daDK` und `EldoUI_LootSim`). Konflikte gab es nur in der TOC (Versionszeile) und im CHANGELOG.

| Nr. | In 0.7.4001 | Was im Fork bleibt |
|---|---|---|
| F18 | Nein: EldoUI ändert in `ProfileRefresh` nur, was „Neues Profil“ aufruft (`E:CreateProfile`, lehnt einen Namen ab, den ein anderes Profil in anderer Groß-/Kleinschreibung hat) und dass `E:SetProfile` selbst bis nach dem Kampf wartet. Der Weg der Zeilen zur Seite (F18) ist unverändert. | Alles. Der Test `tools/config/test_profile_page.lua` bekommt einen Nachbau von `E:CreateProfile`. |
| F19, F15 | Nein: EldoUI baut in `Modules/ActionBars.lua` die Seiten für Übernahme, Fahrzeug und Gestaltwandel um (`NativePages`, Seiten über 18 an Leiste 1). Die ausgeblendeten Blizzard-Leisten (F19) und ihre Rückkehr (F15) berührt das nicht. | Alles. |
| F22 | Nein: EldoUIs Änderungen in `Modules/Auction.lua` sind die gespeicherten Preise je Markt ohne Realmnamen, die Suche und die Preise in Tooltips; `RestoreNative` und `ShowPage` (F22) sind unverändert. | Alles. |
| F11 | Nein: In `Modules/UnitFrames.lua` ändert EldoUI nur die Test-Auren (`ReleaseAuras`, `EndTest`); die Castbar (`Present`, F11) ist unverändert. | Alles. |
| F01–F26 sonst | Nein: Code an diesen Stellen gleich. Der Layerwechsel (`Modules/MinimapLayer.lua`, F05) ist in 0.7.4000 ganz entfallen. | Alles. |

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
- **Nicht geprüft:** ob die Skill-ups im Protokoll ankommen (`GetProfessions` auf diesem Client).

### F22 – Auktionshaus: leere Verkaufen-Seite, Rechtsklick in die Taschen verboten (mittel, teilweise)
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
- **Nebenbei im Fehlerlog gesehen:** der gesperrte Gilden-Tooltip der Infoleiste, jetzt F23.

### F23 – Gilden-Tooltip der Infoleiste fragt im Kampf die Gildennachricht ab (niedrig, im Fehlerlog gefunden)
- **Gefunden:** 16.11.2026 im Fehlerlog, neben F22: „Blocked: EldoUI tried to call the protected function UNKNOWN() at
  EldoUI/Modules/InfoBar.lua:800“, im Kampf, Eschental, 3-mal, zuletzt 16.11. 11:11 in Sitzung 65. Der Fehler steckt
  schon in EldoUI 0.7.2001 (Upstream); 0.7.3001 hat an der Stelle nichts geändert (jetzt Zeile 833).
- **Stelle:** `Modules/InfoBar.lua` (`M.GuildTooltip`)
- **Problem:** Zeile 800 las die Gildennachricht (`C_GuildInfo.GetMOTD`). EldoUIs Fehlerlog hängt bei „UNKNOWN()“ die
  erste Addon-Zeile im Stapel an (`FirstCallSite` in `Core/Errors.lua`); in dieser Zeile ruft EldoUI nur `GetMOTD` auf,
  die Prüfungen in `E:CommRestricted` laufen in `Core/Comm.lua`. EldoUI ließ die Nachricht nur bei einer Chat-Sperre weg
  (Bosskampf, Schlüsselstein, PvP). WoW: Forever sperrt sie offenbar in jedem Kampf. Folgen: ein Eintrag im Fehlerlog
  und eine Gildennachricht, die im Kampf ohnehin fehlt.
- **Umsetzung:** Im Kampf (`InCombatLockdown()`) liest der Tooltip die Gildennachricht nicht und lässt sie weg, wie bei
  einer Chat-Sperre. Gilde, Rang, Anzahl und die Mitglieder zeigt er weiter. Beim nächsten Darüberfahren nach dem Kampf
  ist sie wieder da. `E:CommRestricted` bleibt, wie es ist: EldoUI fragt damit auch, ob es Addon-Nachrichten senden darf.
- **Test:** `tools/infobar/test_guild_motd.lua` (läuft in `tools/ci/check_all.sh tests`, 15 Prüfungen). Er schneidet den
  echten Tooltip aus `InfoBar.lua` und lässt ihn gegen ein Modell laufen: eine Gilde, Kampf, Chat-Sperre und ein
  `GetMOTD`, das im Kampf und bei einer Chat-Sperre gesperrt ist. Geprüft wird:
  - Außerhalb des Kampfs wird die Nachricht einmal gelesen und gezeigt.
  - Im Kampf und bei einer Chat-Sperre wird sie nicht gelesen; der Rest des Tooltips ist da.
  - Nach dem Kampf zeigt sie der nächste Tooltip wieder.
  - Eine leere Nachricht fügt keine Zeilen hinzu; ohne Gilde wird nichts abgefragt.
  - Gegenprobe: Ohne die Kampfprüfung ruft der Tooltip im Kampf die gesperrte Funktion auf, wie im Fehlerlog.
- **Im Spiel prüfen:** siehe Tabelle unten.

### F24 – Nach einem Bankbesuch ist jeder Rechtsklick zum Benutzen aus den Taschen verboten (hoch, im Spiel gefunden)
- **Gefunden:** 20./21.11.2026 beim Spielen. Ein Silberdietrich ließ sich per Rechtsklick nicht ins Handelsfenster legen,
  danach ging bis zum `/reload` kein Rechtsklick mehr (Ruhestein, später ein Kochrezept in Donnerfels). Im Fehlerlog
  derselbe Eintrag wie bei F22: „Forbidden: EldoUI tried to call the protected function UNKNOWN() at
  Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:1611“ (`UseContainerItem` aus `ContainerFrameItemButton_OnClick`),
  inzwischen 157-mal, 15.11. bis 21.11., immer außerhalb des Kampfes. Profil: Taschen und Bank „Ersetzen“.
- **Vorgehen:** Blizzards Code aus Gethe/wow-ui-source, Zweig `forever` (Client 1.60.1, Build 70959: `Mainline`-Taschen,
  `Camelot`-Bank). Im gesperrten Zustand haben Prüfzeilen im Spiel `issecurevariable` für jeden Wert im Rechtsklick-Pfad
  abgefragt und das Ergebnis in `EldoUIErrorsDB` gespeichert. Verunreinigt von EldoUI waren nur `BankFrame.currentBankPage`,
  `BankFrame.BankPanel.purchasedBankTabData`, `BankFrame.BankPanel.bankType` sowie `MerchantFrame.selectedTab` und
  `MerchantFrame.itemIndex`. Die Taschenknöpfe selbst waren sauber.
- **Ursache:** `ContainerFrameItemButton_OnClick` übergibt `BankFrame:GetActiveBankType()` an `UseContainerItem`, bei
  jedem Rechtsklick und auch bei geschlossener Bank (das `BankPanel` bleibt nach dem ersten Bankbesuch „gezeigt“). Den
  Bank-Typ setzt Blizzard in `BankFrameBaseMixin:OnShow`, aber erst *nach* `OpenAllBags(self)`. Hatte EldoUI vorher etwas
  geschrieben, das Blizzards Taschencode dort liest, läuft der Rest von `OnShow` verunreinigt, und alle drei Bank-Werte
  oben sind von EldoUI. Ab dann ist jedes Benutzen aus den Taschen verboten. Das Herausholen aus der Bank ist nicht
  geschützt, deshalb fiel es dort nicht auf. EldoUI schrieb diese Werte auf zwei Wegen:
  - Sein Taschenfenster rief beim Schließen (X, Escape, `CloseWindow`, Kampfbeginn) Blizzards `CloseAllBags()` auf. Das
    setzt `FRAME_THAT_OPENED_BAGS`, und `OpenAllBags(self)` der Bank liest genau diesen Wert.
  - Öffnen aus EldoUIs Code (`/eui find`, Tour, Taschen mit Handel, Gildenbank und Beruf öffnen, Infoleiste, Flugansicht)
    rief `OpenAllBags`/`ToggleAllBags` auf. Das baut Blizzards Taschenrahmen samt `ContainerFrameSettingsManager`.
  `MerchantFrame_OnShow` ruft ebenso zuerst `OpenAllBags(self, true)` und setzt danach seinen Tab. Daher der verunreinigte
  Händler-Tab. Das Auktionshaus öffnet die Taschen genauso. Das könnte auch den noch offenen Teil von F22 erklären.
- **Umsetzung:** `Modules/Bags/Core.lua`. Solange Blizzards Taschenrahmen auf EldoUIs verstecktem Elternrahmen liegen
  (`M:GameBagsParked`, Taschen „Ersetzen“ oder „Ausblenden“), ruft EldoUI Blizzards Taschencode nicht mehr selbst auf.
  - `M:CloseGameBags` versteckt die Rahmen nur. Auf dem versteckten Elternrahmen laufen ohnehin keine Skripte. Wie bei
    Blizzard verlieren die Gegenstände ihre „Neu“-Markierung (`UpdateNewItemList`, nur `C_NewItems`).
  - `M:OpenBags` öffnet nur EldoUIs Fenster (`window.eldoOnly`). Es bleibt offen, bis der Spieler es schließt: mit X,
    Escape, B (Haken an `ToggleAllBags`) oder einem Taschen-Block. Auch Blizzards `CloseAllBags()` ohne Fenster schließt
    es, etwa die Rucksack-Taste auf dem offenen Rucksack. Weil Blizzard die Taschen für geschlossen hält, öffnet der
    erste Druck der Rucksack-Taste aber nur Blizzards versteckten Rucksack. Öffnet und schließt eine Bank oder ein
    Händler die Taschen, bleibt das Fenster offen, wie vorher bei schon offenen Taschen.
  - `M:CloseBags` und `M:ToggleBags` sind die Gegenstücke. Infoleiste (Gold, Taschen, Munition) und der Taschen-Knopf der
    Flugansicht laufen über `M:ToggleBags`.
  - Mit sichtbaren Blizzard-Taschen (Taschen nicht ersetzt) ruft EldoUI wie bisher Blizzards Funktionen auf. Dort bleibt
    das Risiko bestehen (offen).
- **Nicht erklärt:** Laut dem Spieler war der Rechtsklick ins Handelsfenster gleich nach einem `/reload` erneut gesperrt.
  Nach einem Reload ist der Bank-Typ sauber. Ob dazwischen die Bank offen war, ist nicht bekannt.
- **Test:** `tools/bags/test_game_bag_code.lua` (läuft in `tools/ci/check_all.sh tests`). Er schneidet die Helfer,
  `CloseWindow`, `SyncOpen` und die Haken an `ToggleAllBags` und `CloseAllBags` aus `Core.lua` und lässt sie gegen ein
  Modell der versteckten Taschenrahmen laufen. Geprüft wird:
  - Mit versteckten Rahmen ruft EldoUI keine von Blizzards Taschenfunktionen auf.
  - Das allein geöffnete Fenster übersteht einen Bankbesuch. Es schließt mit X, Infoleiste und B, auch an der Bank,
    und mit dem zweiten Druck der Rucksack-Taste.
  - Der normale Weg mit B ist unverändert.
  - Mit sichtbaren Rahmen nutzt EldoUI Blizzards Funktionen wie bisher.
  - Der Eintrag „Taschen“ des Finders (echtes `PANELS` und `PanelCall` aus `Finder.lua`) öffnet und schließt nur
    EldoUIs Fenster und nimmt mit sichtbaren Rahmen das Umschalten des Spiels.
  - Eine Textprüfung stellt sicher, dass `Core.lua`, `InfoBar.lua` und `FlightView.lua` sie sonst nirgends direkt aufrufen.
    Seit der Gegenprüfung liest sie jede Lua-Datei aus den TOCs von EldoUI, Gruppen-Pinnwand und Loot Sim, auch auf
    Namen in Anführungszeichen (wie `fn = "ToggleAllBags"`); Nachhaken (`hooksecurefunc`) und die `watch`-Listen in
    `Data/AddonFit.lua` folgen nur dem Aufruf des Spiels und zählen nicht.
  Er läuft nur in der CI, denn auf dem Entwicklungsrechner gibt es kein Lua.
- **Lücke (Gegenprüfung beim Update auf 0.7.3100, 23.11.2026), behoben:** Der Finder (das Suchfeld des Moduls Finder,
  Eintrag „Taschen“) rief Blizzards `ToggleAllBags` weiter direkt aus EldoUIs Code auf: `Modules/Finder/Finder.lua`
  (`PANELS`, Eintrag `fn = "ToggleAllBags"`; `PanelCall` gab `function() fn(arg) end` zurück, `M:Run` ruft es auf Klick
  oder Eingabe auf). Das ist der zweite Weg der Ursache oben, nur von dort. Szenario: Taschen „Ersetzen“, im Finder
  „Taschen“ wählen, zur Bank, dann Rechtsklick auf den Ruhestein: vermutlich wieder „Forbidden …
  ContainerFrame.lua:1611“ (Codepfad bestätigt, die Folge plausibel, wie bei F24). Die Textprüfung des Tests las den
  Finder nicht. Der Weg stammt nicht aus dem Update.
  - **Umsetzung:** Der Eintrag heißt jetzt `bags = true`, und `PanelCall` führt ihn über `M:ToggleBags` des
    Taschen-Moduls. Das nimmt selbst das Umschalten des Spiels, solange EldoUIs Fenster die Taschen nicht ersetzt; ein
    eigener Rückfall im Finder ist darum nicht nötig.
- **Im Spiel prüfen:** siehe Tabelle unten.

### F25 – Das Koordinatenfeld lässt sich nicht verschieben (niedrig, im Spiel gefunden)
- **Gefunden:** 23.11.2026 beim Spielen. Das kleine Koordinatenfeld des Moduls Wegpunkte ließ sich nicht verschieben.
  Im Fehlerlog steht dazu nichts. In Defrons Profil gibt es keine gespeicherte Position für `EldoUI_WaypointCoords`: Das
  Feld wurde also nie gezogen.
- **Stelle:** `Modules/Waypoints/Coords.lua` (`M:BuildCoords`), `Modules/Waypoints/Core.lua` (`M:BuildArrow`),
  `Core/Movers.lua` (`view`, `InMode`, `E:IsCombatMover`)
- **Ursache:** Das Feld lässt sich nicht direkt ziehen, sondern nur im Verschiebemodus. Das sagt auch sein Tooltip. Der
  Verschiebemodus öffnet aber jedes Mal in der Ansicht „Kampfmodus“ (`view.mode = "combat"`; beim Schließen setzt
  `E:ToggleMoveMode` die Ansicht wieder darauf zurück). Dort zeigt er nur die Mover aus `COMBAT_MOVERS` und
  `COMBAT_PREFIXES` und die mit `combat = true`. Das Koordinatenfeld gehörte nicht dazu. Es bekam keinen Kasten, und ein
  Klick darauf öffnete wie sonst „Wegpunkt hinzufügen“. Ziehen ließ es sich nur in der Ansicht „Alle Rahmen“. Der Wegpfeil
  (`EldoUI_WaypointArrow`) hatte denselben Fehler. Beides stammt aus EldoUI und steckt schon in 0.7.2001.
- **Umsetzung:**
  - Beide Mover tragen jetzt `combat = true` (fünftes Argument von `E:CreateMover`, beim Pfeil neu). Sie gehören zum
    Hauptbildschirm wie die Minikarte, die schon im Kampfmodus ist.
  - Der Pfeil-Mover trägt dazu `followShown = true`, wie das Koordinatenfeld: Sein Kasten erscheint nur, solange der
    Pfeil eingeschaltet ist (`M:UpdateArrowShown` blendet den Halter mit `db.arrow` aus). Ohne das hätte der Kampfmodus
    einen Kasten für einen abgeschalteten Pfeil gezeigt (Befund der Gegenprüfung).
  - Das Rechtsklickmenü des Koordinatenfelds hat den Eintrag „Verschieben“: `E:MoveFrame` öffnet den Verschiebemodus,
    wechselt die Ansicht, falls nötig, und wählt den Kasten aus. Der Text ist schon übersetzt.
- **Übergang:** Im Verschiebemodus oben im Feld „Kampfmodus“ auf „Alle Rahmen“ umstellen.
- **Gegenprüfung (23.11.2026):** Ein unabhängiger Prüfer hat den Diff gelesen, ohne diesen Ordner zu kennen. Er fand
  keinen Fehler, der den Fix aufhält. Die Ursache hält er für plausibel, aber nicht aus dem Code beweisbar: Ob der
  Spieler den Verschiebemodus geöffnet oder das Feld direkt zu ziehen versucht hat, ist nicht bekannt. Auch nach einer
  zweiten Ursache hat er gesucht: Kein Mover überlappt in den mitgelieferten Layouts, die Sichtbarkeitsregeln ändern nur
  die Deckkraft, und „In Instanzen ausblenden“ versteckt nur den Knopf. Seine Befunde und was daraus wurde:
  - Kasten des abgeschalteten Pfeils im Kampfmodus: behoben (`followShown`, oben).
  - Kein Weg „Verschieben“ vom Feld aus: Eintrag im Rechtsklickmenü (oben).
  - Ein Kommentar sagte, die Layouts setzten das Feld neben die Minikarte. Das gilt nur für einige: korrigiert.
- **Offen (nicht geändert):** Weitere Fenster sagen „Verschiebt es im Verschiebemodus“ und stehen nur unter „Alle
  Rahmen“, laut Prüfer etwa Lagerpanel, Farmleiste, Angelleiste und Einkaufsliste (nur per Suche gefunden, nicht im
  Einzelnen geprüft).
- **Test:** keiner. Der Fix besteht aus Schaltern beim Anlegen der Mover und einem Menüeintrag. Die Regel dazu
  (`E:IsCombatMover`) ist unverändert.
- **Im Spiel prüfen:** siehe Tabelle unten.

### F26 – In einer Gruppe keine Schadenszahlen über Gegnern (mittel, im Spiel gefunden)
- **Gefunden:** 23.11.2026 in einem Dungeon mit Gruppe: keine eigenen Schadenszahlen. Im Fehlerlog steht dazu nichts.
  In `WTF/Config.wtf` stehen `floatingCombatTextCombatDamage_v2`, `floatingCombatTextCombatLogPeriodicSpells_v2` und
  `floatingCombatTextPetMeleeDamage_v2` auf `"0"`. `EldoUIDB.cvarSnapshot` hält für alle drei den eigenen Wert des
  Spielers, `"1"` (Besitzer `floating-combat-text`, `held`). Profil Defron: Zahlen auf den Namensplaketten an, „Auch in
  Gruppen“ aus, Blizzards Zahlen auf „Blizzard-Einstellung“ (alles Vorgaben).
- **Stelle:** `Modules/CombatText/Blizzard.lua` (`M:WorldMessageWanted`, `M:PlatesOwnWorldNumbers`,
  `M:WorldNumbersTwice`, `M:ApplyBlizzard`), `Modules/CombatText/Plates.lua` (`Wanted`), `Modules/CombatText/Options.lua`
  (Reiter Namensplaketten)
- **Ursache:** Zwei Regeln passten nicht zusammen:
  - Die Zahlen auf den Plaketten zeigen jeden Treffer auf den Gegner, gleich von wem. In einer Gruppe oder einem
    Schlachtzug zeigt `Wanted` sie darum nur mit „Auch in Gruppen“ (`plates.inGroup`, Vorgabe aus).
  - Damit ein Treffer nicht zweimal erscheint, setzte EldoUI Blizzards Zahlen über Gegnern (eigener Schaden,
    periodischer Schaden, Begleiter) auf 0, solange die Plakettenzahlen *liefen* (`M:PlatesRunning`). Das galt auch in
    der Gruppe, wo sie nichts zeichnen.

  Mit den Vorgaben gab es so in jeder Gruppe gar keine Schadenszahlen. Beides stammt aus EldoUI und steckt schon in
  0.7.2001. Der Stil „Punchy“ des Forks hat an dieser Stelle nichts geändert.
- **Umsetzung:**
  - Neu ist `M:PlatesDrawHere` (`Plates.lua`): Plakettenzahlen an, in einer Gruppe nur mit „Auch in Gruppen“. Die drei
    Funktionen in `Blizzard.lua` fragen das statt `M:PlatesRunning`.
  - In einer Gruppe ohne Plakettenzahlen bekommen Blizzards Zahlen den eigenen Wert des Spielers zurück
    (`E:RestoreCVar`). Diese Zahlen zeigen nur die eigenen Treffer. Allein setzt EldoUI sie wieder auf 0.
  - Ein Listener auf `GROUP_ROSTER_UPDATE` wendet die Einstellungen neu an, sobald sich „in einer Gruppe“ ändert
    (`M.blizzardGrouped`). Das läuft außerhalb des Kampfs (`E:RunOutOfCombat`, Schlüssel `CombatText:blizzardGroup`).
    Wer im Kampf einer Gruppe beitritt, sieht bis zum Kampfende keine Zahlen; endet die Gruppe im Kampf, zeigt jeder
    Treffer bis dahin zwei.
  - Den Gruppentest teilen sich beide Dateien (`M.InGroup` aus `Plates.lua`), damit Plaketten und CVars nicht
    auseinanderlaufen.
  - Unverändert: Mit „Auch in Gruppen“ zeigt EldoUI auch in der Gruppe die Plakettenzahlen, und Blizzards Zahlen bleiben
    aus. Eine Zeile auf „Anzeigen“ oder „Ausblenden“ bleibt die Wahl des Spielers.
  - Ein neuer Satz unter „Blizzards Zahlen über Gegnern“ erklärt das, solange die Plakettenzahlen an sind und „Auch in
    Gruppen“ aus ist: „In einer Gruppe oder einem Schlachtzug, wo die Trefferzahlen auf Namensplaketten aus sind, zeigt
    das Spiel stattdessen Blizzards Schadenszahlen: nur Eure eigenen Treffer.“ (`Options.lua`; deutsch in
    `EldoUI_Locale_deDE/Fork.lua`, dänisch bleibt es englisch). Der Hinweis „Trefferzahlen auf Namensplaketten sind an,
    daher bleiben Blizzards Schadenszahlen …“ hängt an `M:PlatesOwnWorldNumbers` und verschwindet darum in der Gruppe.
- **Übergang:** Unter Kampftext → Namensplaketten „Eure Schadenszahlen über Gegnern“ auf „Anzeigen“ stellen. Allein
  zeigt dann jeder Treffer zwei Zahlen.
- **Gegenprüfung (23.11.2026):** Ein unabhängiger Prüfer hat den Diff gelesen, ohne diesen Ordner zu kennen. Er bestätigt
  die Ursache aus dem Code und fand keinen Fehler, der den Fix aufhält. Ohne Abweichung geprüft hat er Ladereihenfolge,
  Login und Reload in der Gruppe, Reload im Kampf, Schlachtzüge und Schlachtfelder, „Auch in Gruppen“ an, Zeilen auf
  „Anzeigen“ oder „Ausblenden“, Blizzards Element auf „Ausblenden“ oder „Ersetzen“, ein anderes Kampftext-Addon, das
  Modul aus und den Profilwechsel. Seine Befunde und was daraus wurde:
  - Die Optionen sagten nicht, dass in der Gruppe jetzt Blizzards Zahlen kommen: der neue Satz (oben).
  - Lücke bei einem Gruppenwechsel im Kampf: bleibt so (CVars nur außerhalb des Kampfs), im Code beschrieben.
  - Zwei gleiche Gruppentests in zwei Dateien: zusammengelegt (`M.InGroup`).
- **Offen (nicht geändert):** Dieselbe Art Lücke gibt es auch allein. Bei „Welche Plaketten“ = „Nur Euer Ziel“ zeigen
  Treffer auf andere Gegner (etwa Weihe) nirgends eine Zahl. Ebenso, wenn die gegnerischen Namensplaketten aus sind:
  Blizzards Zahlen bleiben aus, obwohl die Plaketten nichts zeichnen. Das ist EldoUIs Regel „eine Zahl je Treffer“ und
  gehört nicht zu dieser Meldung.
- **Nicht im Spiel prüfbar gewesen:** ob das Spiel die geänderten CVars sofort übernimmt, ohne Reload, und ob
  `IsInGroup()` in einer Gruppe aus der Gruppensuche `true` ist. Beide Dateien nutzen denselben Aufruf.
- **Test:** keiner. Ein Test müsste die CVar-Verwaltung aus `Core/Blizzard.lua` und den Gruppenwechsel nachbauen; auf dem
  Entwicklungsrechner gibt es kein Lua.
- **Im Spiel prüfen:** siehe Tabelle unten.

### F27 – Post: Twinks aus dem Adressbuch nur mit Vornamen (mittel, im Spiel gefunden)
- **Gefunden:** 26.11.2026 beim Spielen. Im Fenster „Post verschicken“ bietet das Adressbuch (der Pfeil im Feld „An“)
  unter „Twinks“ die eigenen Charaktere an. Ein Klick trug nur den Vornamen ein, und das Verschicken scheiterte: Auf
  WoW: Forever braucht ein Brief den Vor- und den Nachnamen.
- **Stelle:** `Modules/Mail.lua` (`Alts`, das Menü in `M:CreateAddressBook`)
- **Ursache:** `Alts` nahm den Namen aus dem Eintrag des Charakterspeichers (`record.name`, `Core/CharacterStore.lua`,
  `C:Me`). Dort steht nur der Vorname (`E:PlayerName`). Den vollen Namen hält der Schlüssel des Eintrags:
  „Vorname Nachname - <Realm>“, ohne lesbaren Realm mit dem Regelwerk (`E:CharacterName`, `ResolveCharacterKey`,
  `Core/Database.lua`). Der Fehler stammt aus EldoUI und steckt
  auch in 0.7.4001.
- **Umsetzung:**
  - Neu ist `C.FullName(key, record)` (`Core/CharacterStore.lua`): Beginnt der Name im Schlüssel mit dem Vornamen und
    einem Leerzeichen, kommt der Rest als Nachname dazu, mit dem Trennzeichen des Spiels
    (`Constants.CharacterNameSeparatorConsts`, sonst ein Leerzeichen, wie `E:UnitWhisperName`). Ein Schlüssel ohne
    Nachnamen (andere Clients, ein Nachname, den das Spiel geheim hielt, ein alter Schlüssel) gibt den Vornamen, wie
    bisher.
  - `Alts` (`Modules/Mail.lua`) nimmt diesen Namen; das Menü zeigt denselben, den es einträgt.
  - `C:FindCharacter` erkennt auch den vollen Namen. Sonst zählte ein Brief an „Vorname Nachname“ nicht mehr für den
    Briefkasten des Twinks (`C:CaptureSendMail`, Befund der Gegenprüfung).
  - „Zuletzt“ merkt sich einen Empfänger erst, wenn der Brief abging (`MAIL_SEND_SUCCESS`), nicht schon beim Aufruf von
    `SendMail`. Sonst stand der abgelehnte Vorname oben in der Liste, und das automatische Ausfüllen trug ihn wieder
    ein (Befund der Gegenprüfung, Code von EldoUI).
  - `FixRecent`: Ein Vorname eines eigenen Charakters, den ältere Versionen unter „Zuletzt“ gespeichert haben, wird zum
    vollen Namen, auch in der gespeicherten Liste. Teilen sich zwei eigene Charaktere den Vornamen, bleibt er, wie er
    ist. Doppelte fallen weg, auch in zwei Schreibweisen (`C.NameKey`: Trennzeichen des Spiels wie Leerzeichen), der
    neueste Platz bleibt.
- **Übergang:** Den Nachnamen von Hand ergänzen.
- **Test:** `tools/mail/test_alt_recipient.lua` (35 Prüfungen, im ganzen Offline-Start): Twink mit Nachnamen in Liste,
  Menü und Feld „An“, auch mit dem Trennzeichen des Spiels und einem, das kein Text ist; alter Schlüssel ohne
  Nachnamen; ein Schlüssel mit fremdem Namen; andere Fraktion, anderes Regelwerk und der eigene Charakter bleiben
  draußen; `FindCharacter` mit vollem Namen und der Brief im Briefkasten des Twinks; „Zuletzt“ nach `MAIL_FAILED` und
  nach `MAIL_SEND_SUCCESS`; alte Vornamen in „Zuletzt“ und im automatischen Ausfüllen, ein geteilter Vorname, beide
  Schreibweisen. Mit dem Code vor F27 schlagen 16 der ersten 32 Prüfungen fehl, mit der ersten Fassung (`3058828`) 7;
  die drei letzten schlagen vor der zweiten Gegenprüfung fehl.
- **Gegenprüfung (26.11.2026):** Ein unabhängiger Prüfer hat beide Diffs gelesen, ohne diesen Ordner zu kennen. Er fand
  keinen Fehler, der den Fix aufhält. Ohne Abweichung: der Schlüssel trennt immer mit Leerzeichen, `FullName` setzt das
  Trennzeichen des Spiels ein wie die Flüsternamen, der Realm-Teil wird am ersten „ - “ abgeschnitten, ein
  `record.name` mit vollem Namen bleibt, andere Clients bekommen den Vornamen. Seine Befunde und was daraus wurde:

  | Befund | Gewicht | Reaktion |
  |---|---|---|
  | Ein Brief an den vollen Namen zählt nicht mehr für den Briefkasten des Twinks (`FindCharacter` kannte nur den Vornamen) | mittel | behoben |
  | „Zuletzt“ merkt sich auch abgelehnte Namen; der alte Vorname kommt per automatischem Ausfüllen zurück | niedrig (EldoUIs Code) | behoben, dazu `FixRecent` |
  | Ein Twink mit altem Schlüssel ohne Nachnamen (seit den Schlüsseln mit vollem Namen nicht eingeloggt) bekommt weiter nur den Vornamen; ein über die GUID gehaltener Schlüssel behält nach einer Namensänderung den alten Nachnamen | niedrig–mittel (plausibel) | bleibt: Der Twink einmal einloggen; Namensänderungen sind selten |
  | Der Test rief `store.InvalidateKeys` (gibt es nicht); „6 Prüfungen fehlschlagen“ war nur mit nachträglich ausgegebenem `M.Alts` nachvollziehbar | niedrig | `ForgetKeys`; der Test bricht ohne `M.Alts` nicht mehr ab, Zahlen oben neu |

- **Offen (nicht geändert):**
  - Dieselbe Lücke bei den Gildenhandwerkern: siehe F28 (behoben).
  - `E:CharacterName` (`Core/Database.lua`) hängt den Nachnamen an, auch wenn der erste Wert ihn schon enthält (wenn
    `UnitName` statt `UnitNameUnmodified` antwortet). Der Schlüssel hieße dann „Vorname Nachname Nachname“ (Code von
    EldoUI, laut Prüfer plausibel, nicht beobachtet).
- **Im Spiel prüfen:** siehe Tabelle unten.

### F28 – Gildenhandwerker nur mit Vornamen (mittel, bei F27 gefunden)
- **Gefunden:** 26.11.2026 von der Gegenprüfung zu F27, nicht im Spiel beobachtet. Der Nutzer wollte es mit behoben
  haben.
- **Stelle:** `Modules/Characters/GuildCrafters.lua` (`M:MyRecipeList`, `M:ScanGuildOnline`, `M:CrafterOnline`,
  `M:WhisperCrafter`)
- **Ursache:** Die Rezeptlisten, die man mit der Gilde teilt, nennen jeden Charakter mit `record.name`, also nur mit dem
  Vornamen. „Flüstern“ auf dem Reiter Handwerker flüstert diesen Namen an; auf Forever braucht ein Flüstern Vor- und
  Nachnamen. Die Online-Markierung vergleicht den Namen mit der Gildenliste, die Mitglieder mit Nachnamen führt
  (laut Prüfer; die Post nutzt die Namen der Gildenliste ebenfalls direkt). Der Fehler stammt aus EldoUI.
- **Umsetzung:**
  - `MyRecipeList` nennt jeden Charakter mit vollem Namen (`C.FullName`, wie F27). Ein Schlüssel ohne Nachnamen gibt
    den Vornamen, wie bisher. Das Format der Nachricht trägt Leerzeichen schon.
  - `CrafterOnline`: Ein voller Name ist online, wenn die Gildenliste ihn hat, oder bei einer Gildenliste ohne
    Nachnamen über den Vornamen. Ein Vorname allein (eine Liste aus einer älteren Version) ist online, wenn ein
    Mitglied mit diesem Vornamen online ist (Vornamen sind auf Forever nicht eindeutig; so gut wie vorher).
  - „Flüstern“: Ein Vorname allein wird zum vollen Namen des einen Mitglieds online, das ihn hat
    (`M:CrafterWhisperName`). Bei zweien oder keinem bleibt er, wie er ist, ebenso wenn ein Mitglied online genau so
    heißt.
  - Ein Vorname allein aus einer alten Liste weicht einer vollen Zeile mit diesem Vornamen und derselben Klasse
    (`Shadowed`): wahrscheinlich derselbe Charakter, von einem anderen Charakter des Spielers neu geschickt.
  - Die Namen erscheinen im Namensformat des Spielers (`E:FormatNameString`, Allgemein > Namensformat).
  - `Core/CharacterStore.lua` gibt sein Trennzeichen heraus (`C.SurnameSeparator`).
- **Übergang:** Wer seine Liste mit einer älteren Version geschickt hat, schickt sie einmal neu („Meine Rezepte
  senden“). Bis dahin hilft der Vorname-Abgleich mit der Gildenliste.
- **Test:** `tools/characters/test_guild_crafter_names.lua` (26 Prüfungen, im ganzen Offline-Start): die eigene Liste
  mit vollem Namen, auch durch das Nachrichtenformat; online mit vollem Namen, mit dem Trennzeichen des Spiels, mit
  einer Gildenliste ohne Nachnamen und für Vornamen aus alten Listen; „Flüstern“ an den vollen Namen, an den vollen
  Namen der Gildenliste, unverändert bei zwei, keinem oder einem genau so heißenden Mitglied; alte und neue Liste
  desselben Charakters, das Namensformat. Mit dem alten Code schlagen 9 der ersten 20 Prüfungen fehl; vier der sechs
  neuen schlagen vor der zweiten Gegenprüfung fehl.
- **Gegenprüfung (26.11.2026):** von der zweiten Gegenprüfung über den ganzen PR mit gelesen; ihre Befunde und was
  daraus wurde stehen in `verbesserungen.md` unter D1 (0.7.4001).
- **Nicht im Spiel prüfbar gewesen:** wie die Gildenliste und der Absender einer Addon-Nachricht auf Forever einen
  Namen schreiben (mit oder ohne Nachnamen). Der Code nimmt beides.
- **Im Spiel prüfen:** siehe Tabelle unten.

### F29 – Weltkarte und Questlog: Kartenpins blockiert (mittel, EldoUI-Issue #5)
- **Gefunden:** 26.11.2026 im Upstream-Issue [Eldodeldo/EldoUI#5](https://github.com/Eldodeldo/EldoUI/issues/5) (EldoUI
  0.7.4000, Fehlerbericht über EldoUIs Discord). Der Fork steht auf 0.7.4001; die Stellen unten sind dort unverändert,
  und upstream gibt es nach 0.7.4001 nichts Neues. Der Fehler steckt also auch in conUI. Vier Einträge im Bericht:
  - „Blocked: EldoUI tried to call the protected function Button:SetPassThroughButtons()“, 46-mal. Stapel:
    `TOGGLEGAMEMENU` → `ToggleGameMenu` → `CloseAllWindows` → `CloseWindows` → `HideUIPanel` → (Rückruf
    `ClearFocusedQuestID` der Karte) → `QuestDataProvider:RefreshAllData` → `AddQuest` → `AcquirePin` →
    `CheckMouseButtonPassthrough` → `SetPassThroughButtons`.
  - Dasselbe als „Frame:SetPassThroughButtons()“, 2-mal: `TOGGLEQUESTLOG` → `ToggleQuestLog` → `SetDisplayState` →
    `ShowUIPanel` → `RefreshAllDataProviders` → `WaypointLocationDataProvider:RefreshAllData` → `AcquirePin`.
  - „Core/Errors.lua:-1: insecure scripts exceeded execution limit for addon EldoUI“, 50-mal (siehe unten).
  - „Core/Skin.lua:318: script ran too long“ aus `Modules/Skins.lua:2131`, einmal am 18.11. (siehe unten).
  - Als Auslöser nennt der Bericht nur „pressing Minimap botton“, unter „Other addons“ steht „MinimapBottom“.
- **Vorgehen:** Blizzards Code aus Gethe/wow-ui-source, Zweig `forever` (1.60.1, Build 71139), wie bei F24. Kein Spiel.
- **Ursache:** `SetPassThroughButtons` ist geschützt (`IsProtectedFunction = true` in der API-Doku), und jeder Kartenpin
  ruft es in `AcquirePin` auf. Jeder Pin, den die Karte in einem verunreinigten Lauf holt, wird also blockiert, auch
  außerhalb des Kampfes. Beide Stapel beginnen bei Tasten des Spiels: Der Zustand der Karte war schon verunreinigt.
  EldoUI kennt den Weg selbst (Kommentare in `Core/UIKit.lua` bei `Kit.GameButton` und in `Modules/InfoBar.lua` bei
  den sicheren Blöcken): Eine aus Addon-Code geöffnete Karte bleibt verunreinigt, und die späteren Öffnungen des Spiels
  bekommen ihre geschützten Aufrufe blockiert. Deshalb öffnet EldoUI die Karte sonst über die Anfrage des Spiels
  (`E:OpenWorldMapAt`, `C_Map.OpenWorldMap`: das Spiel beantwortet sie über das Ereignis `WORLD_MAP_OPEN` selbst) oder
  per sicherem Klick auf den Knopf des Spiels. Drei Wege liefen trotzdem durch den Kartencode des Spiels:
  - Der Finder (`/eui find`, Eintrag „Questlog“) rief `ToggleQuestLog` auf (`PANELS`, `fn = "ToggleQuestLog"`). Das
    Questlog sitzt auf der Weltkarte (`QuestLogOwnerMixin`); `SetDisplayState`, `ShowUIPanel`, `SetUIPanelAttribute`
    und der erste Aufbau der Pins liefen so als EldoUI-Code. Der Eintrag „Weltkarte“ daneben nutzte schon die Anfrage.
  - Der Block „Menü“ der Infoleiste klickte die Mikroknöpfe aus EldoUIs Code (`button:Click()`), auch
    `QuestLogMicroButton`.
  - EldoUIs eigene Nachrichtenfenster (Flüsterfenster `Modules/Messages.lua`, Nachrichtenbereich
    `Modules/Chat/Messages.lua`, „Bisher“ im Journal) gaben jeden Link an `SetItemRef` weiter. Für Kartenpin-Links
    (`worldmap:`), Weltquest- und Ereignis-Links ruft das Spiel dort `OpenMapToUserWaypoint`, `OpenWorldMap` bzw.
    `OpenMapToEventPoi` auf, alles Lua-Code der Karte.
  Welchen Weg der Spieler im Bericht genommen hat, lässt sich nicht sagen: „Minimap button“ passt zu einem
  Infoleisten-Panel an der Unterkante der Minimap (Block „Menü“). Plausibel, nicht bewiesen; andere Wege (etwa die
  Uhr der Minimap, die `ToggleCalendar` aufruft) verunreinigen andere Fenster, nicht die Karte.
- **Umsetzung:**
  - Finder: „Questlog“ trägt `map = true` und öffnet wie „Weltkarte“ über `E:OpenWorldMapAt`, nicht im Kampf
    (`combat = false`; `ToggleQuestLog` aus Addon-Code ist im Kampf ohnehin gesperrt).
  - Infoleiste, Block „Menü“ (`Modules/MicroMenu.lua`): Die Einträge laufen über `M.OpenFromMenu`. Für
    `QuestLogMicroButton` steht in `GAME_REQUESTS` die Anfrage des Spiels; die anderen Einträge klicken wie bisher.
  - Neu ist `E:FollowLink(link, text, button, frame)` in `Core/ChatLinks.lua`. Es gibt jeden Link an `SetItemRef`
    weiter, außer `worldmap:`, `worldquest:` und `eventpoi:`. Ein Kartenpin-Link setzt den Wegpunkt wie das Spiel
    (`C_Map.GetUserWaypointFromHyperlink`, `C_Map.SetUserWaypoint`) und öffnet die Karte auf seiner Karte; ein
    Ereignis-Link auf der Karte des Ereignisses (`C_EventScheduler.GetEventUiMapID`); ein Weltquest-Link öffnet die
    Karte. Das Anpingen des Pins entfällt (es liefe über die Rückrufe der Karte, wieder als EldoUI-Code). Ein
    Ereignis-Link behält, was `SetItemRef` nach Blizzards Handler tat („Unhandled“): Tooltip beim Klick, mit
    Umschalt in den Chat. Die drei Nachrichtenfenster rufen `E:FollowLink` statt `SetItemRef`.
  - Die Einträge „Questlog“ (Finder, Menü) öffnen die Karte so, wie sie zuletzt war (mit oder ohne Questlog, je nach
    `questLogOpen` und `miniWorldMap`). Eine offene Karte schließen sie nicht mehr, und sie wechseln dort nicht zum
    Questlog: Beides ginge nur über den Kartencode des Spiels.
- **Übergang:** Ein schon verunreinigter Zustand bleibt bis zum nächsten `/reload`.
- **Test:** `tools/maps/test_map_open_code.lua` (46 Prüfungen): die echten Finder-Einträge „Questlog“ und „Weltkarte“
  (`PANELS`, `PanelCall`), `OpenFromMenu` aus `MicroMenu.lua` (Questlog über die Anfrage, andere Knöpfe per Klick,
  nichts im Kampf) und `E:FollowLink` (Kartenpin, Weltquest, Ereignis über die Anfrage, beim Ereignis Tooltip und
  Umschalt-Klick wie bisher, alles andere unverändert an `SetItemRef`) gegen Stubs. Eine Textprüfung über alle
  Lua-Dateien der TOCs und `Bindings.xml`: `ToggleQuestLog`, `ToggleWorldMap`, `OpenWorldMap`, `OpenQuestLog`,
  `OpenMapToUserWaypoint`, `OpenMapToEventPoi` und `QuestMapFrame_OpenToQuestDetails` weder aufgerufen noch als Wert
  weitergegeben (`pcall(ToggleWorldMap)`, `_G.OpenWorldMap()`) noch in Anführungszeichen genannt, kein Klick auf
  `QuestLogMicroButton` oder den Zonen-Knopf der Minimap, und `SetItemRef` nur in `Core/ChatLinks.lua`, auch nicht
  als Wert (Nachhaken und `type(SetItemRef)` zählen nicht). Mit dem alten Code schlagen die Finder-Prüfungen und die
  `SetItemRef`-Prüfung fehl, die Menü-Prüfung findet `OpenFromMenu` nicht; vor der Gegenprüfung schlagen die zwei
  Prüfungen zum Ereignis-Link fehl.
- **Nicht geändert:**
  - Fehler 3 („insecure scripts exceeded execution limit“ in `Core/Errors.lua`) ist eine Folge: Das Spiel meldet jeden
    blockierten Aufruf sofort (`ADDON_ACTION_BLOCKED`, noch im blockierten Lauf), und EldoUIs Fehlerfänger zählt jeden
    der 46 Pins mit. Wiederholungen kosten dort wenig (kein Stapel, Benachrichtigung erst im nächsten Frame); ohne die
    Blockaden fällt der Eintrag weg. Ohne Spiel nicht weiter eingrenzbar.
  - Fehler 4 („script ran too long“ in `Core/Skin.lua`) stammt vom 18.11., also aus 0.7.3004/0.7.3005: Beim Laden
    eines Blizzard-Addons skinnt EldoUI dessen Fenster in einem Durchgang (`M:Watch` → `M:SetupWindow`), und der
    Abgleich in `ClosePass` brauchte einmal zu lange. Einmalig, ohne Messung im Spiel keine sichere Änderung.
  - Andere Fenster öffnet EldoUI weiter aus eigenem Code (Uhr der Minimap: `ToggleCalendar`/`ToggleTimeManager`,
    Infoleiste und Finder: `ToggleCharacter`, `ToggleFriendsFrame` usw., Block „Menü“: die übrigen Mikroknöpfe).
    Nach EldoUIs eigener Regel bleiben auch diese Fenster danach verunreinigt; Meldungen dazu gibt es bisher keine.
- **Gegenprüfung (26.11.2026):** Ein unabhängiger Prüfer hat Code und Commit-Messages gelesen, ohne diesen Ordner zu
  kennen, Blizzards Code dazu nachgesehen und den Test gegen den alten Stand laufen lassen. Er hält die Diagnose für
  stimmig: Die drei Wege liefen wirklich mit EldoUIs Verunreinigung durch den Kartencode. Seine Befunde und was
  daraus wurde:
  - Ereignis-Links verloren Tooltip und Umschalt-Klick: behoben (oben).
  - Die Einträge „Questlog“ garantieren das Questlog nicht mehr und schließen eine offene Karte nicht: so gelassen
    (sauber geht es nicht), aber im CHANGELOG und oben beschrieben.
  - Die Textprüfung fand Funktionsverweise (`pcall(ToggleWorldMap)`, `C_Timer.After(0, ToggleQuestLog)`),
    `_G.ToggleWorldMap()` und `local ref = SetItemRef` nicht und las `Bindings.xml` nicht: erweitert, mit
    Gegenproben.
  - Das CHANGELOG versprach als Tatsache, dass L, M und Escape nichts mehr melden: Es beschreibt jetzt, was sich
    ändert.
  - Offen, nur im Spiel zu klären (siehe unten): Ob Ereignisse, die das Spiel noch *im* Aufruf auslöst
    (`SynchronousEvent = true` in der API-Doku, etwa `WORLD_MAP_OPEN`, `USER_WAYPOINT_UPDATED`,
    `QUEST_WATCH_LIST_CHANGED`), mit der Verunreinigung des Aufrufers laufen.
- **Offen:**
  - Laufen synchrone Ereignisse verunreinigt, dann wäre der Fix unvollständig:
    - `E:OpenWorldMapAt(mapID)` mit Karten-ID: Blizzards Handler von `WORLD_MAP_OPEN` ruft nach `ShowUIPanel` noch
      `SetMapID` auf (das schreibt `WorldMapFrame.mapID`, das beide Stapel vor `AcquirePin` lesen). Das betrifft den
      Kartenpin- und den Ereignis-Link und ältere Aufrufe mit ID (Loot Guide, Orte im Finder, Journal). Ohne ID geht
      nur `ShowUIPanel` durch den geschützten Delegaten.
    - EldoUIs Wegpunkte bei offener Karte (`C_Map.SetUserWaypoint`, etwa Strg+Rechtsklick auf die Karte mit
      „Spielpin“ an, `Waypoints/Core.lua` `SyncGamePin`; dazu Map Notes, Loot Guide, Training, Camp): Der
      Wegpunkt-Provider der Karte holt dann im Aufruf seinen Pin, wie in Fehler 2.
    - Der Haken „ganze Zone verfolgen“ im Questlog (`Modules/QoL.lua`, `C_QuestLog.AddQuestWatch`): Der
      Quest-Provider holt bei `QUEST_WATCH_LIST_CHANGED` seine Pins, wie in Fehler 1.
    Die Gegenprobe im Spiel steht in der Tabelle unten. Für das, was diese Ereignisse auslösen, gäbe es dann keinen
    sauberen Weg aus Addon-Code; man müsste sie bei offener Karte bis zum Schließen aufschieben.
  - Der Finder-Eintrag „Schlachtfeldkarte“ ruft weiter `ToggleBattlefieldMap` aus EldoUIs Code auf (dieselbe
    Fehlerklasse für die Schlachtfeldkarte; für die Weltkarte nur kurz, über gemeinsame Quest-Zwischenspeicher). Eine
    saubere Anfrage des Spiels gibt es für diese Karte nicht; Shift+M öffnet sie sauber.
- **Im Spiel prüfen:** siehe Tabelle unten.

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
| F23 | in einer Gilde, mit dem Block „Gilde“ auf der Infoleiste: im Kampf die Maus auf den Block; nach dem Kampf noch einmal | im Kampf Gilde und Mitglieder ohne Gildennachricht, kein neuer Eintrag „Blocked: … InfoBar.lua“ in `/eui errors`; nach dem Kampf mit Gildennachricht | offen |
| F24 | `/reload`; Taschen mit B öffnen und mit EldoUIs X schließen; zur Bank, etwas herausholen, Bank schließen; Ruhestein oder Rezept per Rechtsklick aus der Tasche benutzen, danach `/run print(issecurevariable("FRAME_THAT_OPENED_BAGS"))print(issecurevariable(BankFrame.BankPanel,"bankType"))print(issecurevariable(MerchantFrame,"selectedTab"))` | Rechtsklick wirkt, kein neuer Eintrag „ContainerFrame.lua:1611“ in `/eui errors`; dreimal `true` | offen |
| F24 | Taschen über die Infoleiste öffnen, mit B schließen; noch einmal über die Infoleiste öffnen, einen Händler besuchen und verlassen | B schließt das Fenster; nach dem Händler bleibt es offen | offen |
| F24 | mit einem Freund handeln: einen Gegenstand per Rechtsklick aus der Tasche ins Handelsfenster legen | er landet im Handelsfenster | offen |
| F24 | `/reload`; im Finder „Taschen“ wählen (öffnet), noch einmal (schließt), wieder öffnen; zur Bank, etwas herausholen, Bank schließen; Ruhestein per Rechtsklick aus der Tasche benutzen | das Fenster öffnet und schließt; Rechtsklick wirkt, kein neuer Eintrag „ContainerFrame.lua:1611“ | offen |
| F25 | `/eui move` öffnen (Ansicht „Kampfmodus“), das Koordinatenfeld ziehen, den Verschiebemodus schließen, `/reload` | Koordinatenfeld und Wegpfeil haben sofort einen Kasten; das Feld bleibt nach dem Reload am neuen Platz | offen |
| F25 | Rechtsklick auf das Koordinatenfeld → „Verschieben“ | der Verschiebemodus öffnet, der Kasten des Felds ist ausgewählt | offen |
| F25 | den Wegpunktpfeil in den Optionen der Wegpunkte abschalten, `/eui move` | kein Kasten „Wegpunktpfeil“, auch nicht unter „Alle Rahmen“ | offen |
| F26 | allein: `/dump C_CVar.GetCVar("floatingCombatTextCombatDamage_v2")`, einen Gegner angreifen | `"0"`; die Zahlen stehen auf der Plakette des Ziels | offen |
| F26 | außerhalb des Kampfs einer Gruppe beitreten, derselbe Befehl, einen Gegner angreifen | `"1"`; Blizzards eigene Schadenszahlen über dem Gegner, keine Plakettenzahlen | offen (Gruppe) |
| F26 | die Gruppe verlassen, derselbe Befehl | wieder `"0"`, wieder Plakettenzahlen | offen (Gruppe) |
| F27 | am Briefkasten „Post verschicken“, Pfeil im Feld „An“ → „Twinks“ → einen eigenen Charakter wählen, etwas schicken | im Menü und im Feld steht „Vorname Nachname“, der Brief geht ab | offen |
| F27 | den Briefkasten schließen und wieder öffnen, „Post verschicken“ | das Feld „An“ füllt sich mit „Vorname Nachname“, auch wenn vorher ein Brief an den Vornamen allein gescheitert war; beim Twink liegt der Brief im Briefkasten-Block der Infoleiste | offen |
| F28 | in einer Gilde mit einem zweiten EldoUI- oder conUI-Spieler: beide „Eure Rezepte mit der Gilde teilen“ an, beide „Meine Rezepte senden“; auf dem Reiter Handwerker ein Rezept suchen, „Flüstern“ | die Handwerker stehen mit Vor- und Nachnamen da, online richtig markiert; das Flüstern geht an „Vorname Nachname“ und kommt an | offen (Gilde) |
| F29 | `/reload`; im Finder (`/eui find`) „Questlog“ wählen, schließen; danach mit L und M öffnen und mit Escape schließen | die Karte öffnet sich; kein neuer Eintrag „SetPassThroughButtons()“ in `/eui errors` | offen |
| F29 | `/reload`; im Block „Menü“ der Infoleiste „Questlog“ wählen; danach L, M und Escape | wie oben | offen |
| F29 | in EldoUIs Flüsterfenster einen Kartenpin-Link (`[Map Pin Location]`, etwa von einem Mitspieler geflüstert) anklicken; danach L, M und Escape | die Karte öffnet auf dem Pin, der Wegpunkt steht; kein neuer Eintrag „SetPassThroughButtons()“ | offen |
| F29 | nach den Schritten oben `/run local p=WorldMapFrame.pinPools print((issecurevariable(p,"QuestPinTemplate")),(issecurevariable(p,"WaypointLocationPinTemplate")),(issecurevariable(WorldMapFrame,"isMaximized")))` | dreimal `true` (auch für einen Pool, den es noch nicht gibt) | offen |
| F29 | Gegenprobe zu „Offen“: `/reload`, die Weltkarte mit M öffnen, dann `/run C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(C_Map.GetBestMapForUnit("player"),.5,.5))` | kein Eintrag „Blocked: … SetPassThroughButtons()“ in `/eui errors`. Kommt einer, laufen synchrone Ereignisse verunreinigt, und die Punkte unter „Offen“ sind echt | offen |
| F29 | in Zone A einen Kartenpin-Link für Zone B im Flüsterfenster anklicken, mit Escape schließen, dann L und M; dasselbe mit `/run C_Map.OpenWorldMap(1429)` (Elwynn) | kein neuer Eintrag „SetPassThroughButtons()“ | offen |
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
