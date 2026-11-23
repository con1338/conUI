# Code-Review EldoUI 0.7.2001

Ergebnisse der Prüfung vom November 2026: private Notizen, nicht für Upstream gedacht. Seit dem 16.11.2026 steht
der Fork auf EldoUI 0.7.3001, seit dem 19.11.2026 auf 0.7.3005, seit dem 23.11.2026 auf 0.7.3100; was das an
den Befunden ändert, steht in beiden Dateien in den Abschnitten zu den Updates.

| Datei | Inhalt |
|---|---|
| [fehler.md](fehler.md) | Gefundene Fehler mit Stelle, Szenario, Schwere und Status |
| [verbesserungen.md](verbesserungen.md) | Verbesserungen, fehlende Features, Infrastruktur, mit Status und Reihenfolge |

## Wie geprüft wurde

1. **Automatisch über alle 626 Lua-Dateien:**
   - `luac5.1 -p`: keine Syntaxfehler.
   - TOC-Dateien gegen die Dateien auf der Platte: vollständig.
   - `luacheck`: keine versehentlichen Globals, keine Tippfehler bei WoW-API-Namen.
   - Abgleich aller Aufrufe `E:Foo()` / `E.Foo()` mit den Definitionen: alle vorhanden.
   - `loadstring` / `RunScript`: kommt nicht vor.
2. **Manuelles Lesen** in drei Bereichen:
   - nicht vertrauenswürdige Eingaben (Addon-Nachrichten, Import-Strings, Profile);
   - Kampf, geschützte Frames, Taint, Secret Values;
   - Feature-Lücken und Infrastruktur.
3. **Nachprüfung:** Die mit ✔ markierten Befunde wurden ein zweites Mal direkt im Code nachvollzogen.

Getestet ist nichts davon im Spiel, weil kein WoW-Client zur Verfügung stand. Befunde mit „plausibel“ hängen vom
genauen API-Verhalten von WoW: Forever ab, vor allem davon, welche Werte im Kampf geheim („secret“) sind.

## Status-Legende

| Status | Bedeutung |
|---|---|
| offen | noch nicht angefasst |
| behoben | im Code geändert; Commit in der Git-Historie |
| umgesetzt | Verbesserung fertig; Commit in der Git-Historie |
| teilweise | ein Teil erledigt; was fehlt, steht beim Punkt |
| bewusst nicht | absichtlich nicht geändert (Grund steht dabei) |
| Daueraufgabe | nichts zu bauen; bei jedem Update erneut prüfen |
| abwarten | erst angehen, wenn sich etwas ändert (Grund steht in der Übersicht) |

Beide Dateien beginnen mit einer Übersicht. „Weiter mit dem nächsten offenen Punkt“ heißt: in `fehler.md` die
nächste Zeile mit „offen“ (dort ist seit F17 keine mehr übrig), in `verbesserungen.md` der nächste Punkt aus der
Reihenfolge unter der Übersicht.
