# Fehler

Pfade relativ zu `EldoUI/`. ✔ = im Code ein zweites Mal nachvollzogen.
Schwere: hoch / mittel / niedrig. Sicherheit: bestätigt = Codepfad vollständig gelesen,
plausibel = hängt von API-Verhalten ab, das sich ohne Spiel nicht prüfen lässt.

## Übersicht

| Nr. | Kurz | Schwere | Status |
|---|---|---|---|
| F01 ✔ | Import „global“ ersetzt accountweite Daten ohne Prüfung | hoch | offen |
| F02 | Mover-Positionen aus Imports ungeprüft, Frames verschwinden | mittel–hoch | offen |
| F03 ✔ | Snapshot-Import übernimmt Makroinhalte ungeprüft | mittel | offen |
| F04 | Settings-Angebote Fremder ohne Limit, schließen offene Dialoge | mittel | offen |
| F05 ✔ | Layer-Modul antwortet jedem per Whisper | mittel | offen |
| F06 | Fremdtext mit Link-/Escape-Codes ungefiltert im Chat | niedrig–mittel | offen |
| F07 | Strings anderer Versionen als „beschädigt“ abgelehnt, Teil-Importe ohne Migration | niedrig–mittel | offen |
| F08 | Entpackgröße erst nach dem Entpacken geprüft | niedrig–mittel | offen |
| F09 | Segensplan und Whisper-Kontakte ohne Obergrenze | niedrig | offen |
| F10 ✔ | RaidLoot-JSON: `null` verschiebt Array-Elemente | niedrig | offen |
| F11 | Castbar wertet geheime Werte direkt aus | hoch (plausibel) | offen |
| F12 | Gruppenframes fallen fälschlich auf Blizzard zurück | mittel | offen |
| F13 ✔ | Drei Event-Handler mit falscher Signatur | mittel | offen |
| F14 | Mover ziehen über Kampfbeginn → ADDON_ACTION_BLOCKED | mittel (plausibel) | offen |
| F15 | Blizzard-Leiste kommt mit „toten“ Buttons zurück | mittel | offen |
| F16 | Click-Casting: Hover-Unit veraltet nach Roster-Änderung | niedrig–mittel (plausibel) | offen |
| F17 | Kleinkram: Click-Bindungen, Secret-Checks, Unit-Filter | niedrig | offen |

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

### F02 – Mover-Positionen aus Imports ungeprüft (mittel–hoch, bestätigt)
- **Stelle:** `Core/Share.lua:820`, `:940`; `Core/Movers.lua:986` (`ApplyPosition`), `:1806` (`PlaceAll`)
- **Problem:** Punktnamen, Offsets und das Anker-Frame (beliebiger `_G`-Name) gehen ungeprüft an `SetPoint`.
  `PlaceAll` hat vorher bei allen Movern `ClearAllPoints` aufgerufen; ein Fehler bricht die Schleife ab.
- **Szenario:** Ein Eintrag `{"FOO", "UIParent", "CENTER", 0, 0}` in einem „positions“-/„all“-Import:
  `SetPoint` wirft, alle danach platzierten Mover bleiben ohne Anker, Frames unsichtbar – bei jedem
  Profilwechsel erneut, weil es gespeichert ist.
- **Fix-Idee:** Positionen vor dem Anwenden bereinigen; `ApplyPosition` in `PlaceAll` einzeln absichern.

### F03 ✔ – Snapshot-Import übernimmt Makroinhalte ungeprüft (mittel, bestätigt)
- **Stelle:** `Modules/Snapshots.lua:980` (`CleanImport`), Vorschau `:440`, `:477`
- **Problem:** `m.body` wird ungeprüft übernommen; Plan und Restore-Fenster zeigen nur die Makronamen.
- **Szenario:** Ein geteilter `!EUS1!`-String legt ein Makro „Mount“ mit `/run …` auf Slot 1. Nach „Restore“
  und Tastendruck läuft der Code.
- **Fix-Idee:** Makros mit Skript-Befehlen in der Vorschau deutlich markieren.

### F04 – Settings-Angebote Fremder ohne Limit (mittel, bestätigt)
- **Stelle:** `Core/Share.lua:1471` (`IsTrustedSender`), `:1508`, `:1549`
- **Problem:** Jede Nachricht über PARTY, RAID, INSTANCE_CHAT oder GUILD gilt als vertrauenswürdig – auch von
  Fremden im Battleground oder in Zufallsgruppen. `OnOffer` hat kein Rate-Limit und ersetzt den einzigen
  Bestätigungsdialog (`CloseConfirm(false)` bricht den offenen ab).
- **Szenario:** Jemand schickt jede Sekunde ein Angebot → kein EldoUI-Dialog lässt sich mehr bestätigen.
- **Fix-Idee:** INSTANCE_CHAT nicht als vertrauenswürdig zählen; Abkühlzeit pro Absender; keinen offenen Dialog ersetzen.

### F05 ✔ – Layer-Modul antwortet jedem per Whisper (mittel, bestätigt)
- **Stelle:** `Modules/MinimapLayer.lua:509` (`OnChosen`), `:562` (`OnMessage`)
- **Problem:** Auf „LR|id“ per Whisper kommt immer eine Antwort „LN|id|busy“, auch ohne eigenes Angebot und mit
  ausgeschalteter Layer-Hilfe.
- **Szenario:** Jeder auf dem Realm kann so prüfen, wer online ist und EldoUI nutzt.
- **Fix-Idee:** Ohne eigenes Angebot (`Layer.offered[tag]`) gar nicht antworten.

### F06 – Fremdtext mit Link-/Escape-Codes ungefiltert (niedrig–mittel, bestätigt)
- **Stellen:** `Modules/Instances/Reset.lua:122` (Leader-Reset-Namen), `Modules/Hardcore/Core.lua:368`
  (Killer/Zone), `Core/Plugins.lua:101` (Versionstext)
- **Problem:** Text von anderen Spielern geht mit `|H…|h`-Links, Farb- und Textur-Codes in `E:Print` bzw. Alerts.
- **Szenario:** Ein Gruppenleiter schickt `|Haddon:EldoUI:talents:learn|h[Reset-Log]|h`; ein Klick lernt Talente.
- **Fix-Idee:** Fremdtext vor der Anzeige mit `gsub("|", "||")` entschärfen.

### F07 – Strings anderer Versionen abgelehnt, Teil-Importe ohne Migration (niedrig–mittel, bestätigt)
- **Stelle:** `Core/Share.lua:139`, `:831`; `Core/Database.lua:625`
- **Problem:** Ein String mit neuerem/älterem Profilschema meldet „damaged or cut short“. Bei „module:“ und
  „general“ läuft `RunProfileMigrations` nicht.
- **Fix-Idee:** Eigene Meldungen für ältere/neuere Version; Payload vor dem Anwenden migrieren.

### F08 – Entpackgröße erst nach dem Entpacken geprüft (niedrig–mittel, plausibel)
- **Stelle:** `Core/Share.lua:480`; `Core/Import.lua:179`
- **Problem:** 1–2 MB komprimierte Daten können auf sehr viel mehr entpacken, bevor `#out > MAX_STRING` greift.
  Ob `C_EncodingUtil.DecompressString` selbst begrenzt, ist unklar.

### F09 – Daten ohne Obergrenze (niedrig, bestätigt)
- **Stellen:** `Modules/Blessings.lua:289` (Segensplan nimmt beliebige Namen an, wird nie aufgeräumt);
  `Modules/Messages.lua:359` (jeder neue Whisper-Absender wird dauerhaft gespeichert)
- **Fix-Idee:** Nur Paladine der Gruppe annehmen; Kontakte begrenzen und nach Alter aufräumen.

### F10 ✔ – RaidLoot-JSON: `null` verschiebt Array-Elemente (niedrig, bestätigt)
- **Stelle:** `Modules/RaidLoot/Core.lua:239`
- **Problem:** `arr[#arr + 1] = Value()` mit `nil` erhöht den Index nicht: `[a, null, c]` wird zu `{a, c}`.
- **Fix-Idee:** Eigenen Index mitzählen.

## Kampf und Frames

### F11 – Castbar wertet geheime Werte direkt aus (hoch, plausibel)
- **Stelle:** `Modules/UnitFrames.lua:1597`, `:1626`, `:1648`, `:1875`
- **Problem:** `if not name`, `if targetName`, `if duration` und `if UnitCastingInfo(unit)` (ohne pcall) testen
  Werte, die laut eigener Code-Doku (`:1360`) geheim sein können. Nameplates nutzt dafür `Present()` (`Modules/Nameplates.lua:409`).
- **Szenario:** Ein Gegner castet in einer Instanz → Lua-Fehler bei jedem Cast-Event, Castbar bleibt leer.
- **Fix-Idee:** Wie in Nameplates `Present()` verwenden; `UnitCastingInfo` in pcall.

### F12 – Gruppenframes fallen fälschlich auf Blizzard zurück (mittel, bestätigt)
- **Stelle:** `Modules/GroupFrames.lua:2809` (`ScheduleCheck` / `CheckHeaders`)
- **Problem:** Gezählt werden nur Buttons mit `IsVisible()`. Ist der Holder per Sichtbarkeitsregel versteckt
  („nur im Kampf“, „beritten ausblenden“), ist das Ergebnis 0 → Engine „auto“ schaltet für die Sitzung auf
  Blizzard-Frames, mit irreführender Chatmeldung.
- **Fix-Idee:** Nur werten, wenn der Header selbst sichtbar ist; sonst später erneut prüfen.

### F13 ✔ – Drei Event-Handler mit falscher Signatur (mittel, bestätigt)
- **Stellen:** `Modules/ActionBars/RankCheck.lua:488`, `Core/KeybindNewSpells.lua:509`, `Core/KeybindQuietBars.lua:305`
- **Problem:** Der Dispatcher ruft `handler(owner, event, ...)` auf (`Core/Init.lua:105`). Diese drei Handler
  lassen `event` aus: In RankCheck ist `name` immer `"ADDON_LOADED"`, in den beiden anderen ist `isLogin` immer wahr.
  Eine Suche über den ganzen Code fand genau diese drei.
- **Szenario:** Die Rangprüfung im Zauberbuch greift nach dem Laden von Blizzard_PlayerSpells nicht; neu gelernte
  Zauber gehen verloren, wenn kurz danach ein Ladebildschirm kommt.

### F14 – Mover ziehen über Kampfbeginn (mittel, plausibel)
- **Stelle:** `Core/Movers.lua:1637` (`OnDragStart`/`OnDragStop`), `:2321`
- **Problem:** Nur `OnDragStart` prüft auf Kampf. Bei Kampfbeginn wird ein laufendes Ziehen nicht gestoppt;
  `OnDragStop` setzt dann im Kampf Punkte.
- **Szenario:** Mover einer Aktionsleiste ziehen, angegriffen werden, loslassen → ADDON_ACTION_BLOCKED.

### F15 – Blizzard-Leiste kommt mit „toten“ Buttons zurück (mittel, bestätigt)
- **Stelle:** `Modules/ActionBars.lua:1830` (`HideBlizzardBar`), `:1874` (`ShowBlizzardBar`)
- **Problem:** Beim Verstecken werden die Events der Buttons abgemeldet (laut Kommentar bringt nur `/reload` sie
  zurück). Beim Wieder-Anzeigen fehlt der Reload-Hinweis.
- **Szenario:** Eine EldoUI-Leiste abschalten → Blizzards Leiste erscheint, aktualisiert aber keine Cooldowns/Reichweite.

### F16 – Click-Casting: Hover-Unit veraltet (niedrig–mittel, plausibel)
- **Stelle:** `Modules/ClickCast.lua:345`
- **Problem:** Die Unit wird nur beim Betreten des Frames kopiert. Ändert der Header danach `unit`, bleibt der alte Token.
- **Szenario:** Maus ruht auf einem Raid-Frame, jemand verlässt im Kampf den Raid → Zauber geht an den Falschen.

### F17 – Kleinkram (niedrig)
- `Modules/ClickCast.lua:443`, `:1074`: Blizzard-Kompaktframes, die im Kampf entstehen, bekommen keine Bindungen nachgeholt.
- `Modules/ClassPower.lua:1720`, `:1898`: Hooks vergleichen eine evtl. geheime Textur und prüfen nicht, ob das Modul aktiv ist.
- `Modules/Nameplates.lua:2979`: Hook auf `NamePlateDriverFrame` beim Laden der Datei statt über `E:OnBlizzardAddOn`.
- `Modules/Auras.lua:740`: `UNIT_INVENTORY_CHANGED` ohne Unit-Filter.

## Sonstiges

- **Toter Code:** rund 25 ungenutzte lokale Funktionen und ungenutzte Variablen (luacheck W211). Reste von
  Umbauten, keine Auswirkung.
