# Prüfungen, Release-ZIP und Versionswächter

Drei GitHub-Workflows in `.github/workflows/`, die Skripte dazu liegen hier.

| Workflow | Wann | Was |
|---|---|---|
| `ci.yml` (Prüfungen) | jeder Push, jeder Pull Request | alle Prüfungen, danach das Addon-ZIP als Download (Actions → Lauf → Artifacts, 14 Tage) |
| `release.yml` (Release) | ein Tag `v*`, oder von Hand mit dem Tag als Eingabe | alle Prüfungen, ZIP bauen, GitHub-Release mit dem ZIP |
| `watch.yml` (Versionswächter) | täglich 05:23 UTC, oder von Hand | neuer WoW: Forever-Patch oder neue EldoUI-Version → Issue |

## Prüfungen

Lokal genauso wie auf GitHub:

```sh
tools/ci/check_all.sh                 # alle (gut 40 Sekunden)
tools/ci/check_all.sh toc luacheck    # nur einzelne
```

Braucht `lua5.1`, `luac5.1`, `luacheck` und `python3` (Ubuntu: `apt-get install lua5.1 lua-check`).

| Prüfung | Inhalt |
|---|---|
| `syntax` | `luac5.1 -p` über alle Lua-Dateien, Python-Syntax der Werkzeuge |
| `toc` | `check_toc.py`: jede Datei aus den .toc-Dateien existiert (mit genauer Groß-/Kleinschreibung), keine doppelt, keine Lua-/XML-Datei ungeladen, überall dieselbe Interface-Nummer |
| `luacheck` | Globals: kein vergessenes `local`, kein Tippfehler in API-Namen (`.luacheckrc`); die Pinnwand zusätzlich mit ihren strengeren Regeln |
| `tests` | Offline-Tests der Pinnwand (`tools/groupboard/`), der Share-Strings anderer Versionen und der Größenprüfung vor dem Entpacken (`tools/share/`), von Click-Casting (`tools/clickcast/`), des Nameplate-Hooks (`tools/nameplates/`), der Info-Bar-Blöcke für andere Addons (`tools/infobar/`), von Masque außerhalb der Aktionsleisten (`tools/masque/`), der DKP-/EPGP-Stände (`tools/raidloot/`), der Zeitmessung `/eui perf` (`tools/perf/`), der Zauberleisten an Gruppenframes (`tools/groupframes/`), der Weltbuffs (`tools/worldbuffs/`), der Wowhead-Sprache, der Quest-EP im Questlog und des Signals nach dem Essen und des Hinweises bei fast vollen Taschen (`tools/qol/`), der Questgegenstandsleiste (`tools/questbar/`), des Setwechsels nach dem Kampf (`tools/character/`), der Zusatztasten auf der Verbrauchsgüterleiste (`tools/consumablebar/`), der Leistenschalter in den Leisten-Schnappschüssen (`tools/snapshots/`), des Richturteils als Fernkampfangriff in der Kampfsimulation (`tools/lootsim/`), der Regeln für `Fork.lua` im deutschen Paket (`tools/locale/test_fork.py`) und des Versionswächters |
| `load` | ganzes Addon offline starten (`tools/harness/`, siehe unten), mit englischem und deutschem Client; dazu der Gegentest, dass ein kaputtes Modul auffällt |
| `locale` | deutsches Paket: Platzhalter und Textcodes, `Fork.lua` (siehe unten), jeder `L["…"]`-Text im Code hat eine Übersetzung, zitierte Beschriftungen, Pinnwand-Texte; der Übersetzungsstand wird nur angezeigt |

**Offline-Start (`load`):** `tools/harness/load_eldoui.lua` lädt EldoUI so, wie das Spiel es tut, mit einem
Nachbau des Spiels (`tools/harness/wow.lua`):

1. alle Dateien der `EldoUI.toc` in ihrer Reihenfolge, dann `ADDON_LOADED`;
2. die Addons, die mit EldoUI laden (Gruppen-Pinnwand);
3. Addons, die erst bei Bedarf laden (Sprachpakete, Loot-Daten), wenn EldoUI danach fragt. Sie kommen aus ihren
   eigenen TOC-Dateien;
4. danach `PLAYER_LOGIN` und `PLAYER_ENTERING_WORLD` wie beim ersten Login ohne gespeicherte Einstellungen,
   außerdem die gestarteten Timer;
5. jedes Modul über den Schalter, den auch die Optionen nutzen: alle an, alle aus, zurück.

Jeder Fehler wird gesammelt (beim Laden mit Datei, sonst über `geterrorhandler` wie im Spiel). Ein einziger
lässt die Prüfung fehlschlagen.

```sh
lua5.1 tools/harness/load_eldoui.lua                  # englischer Client
lua5.1 tools/harness/load_eldoui.lua --locale deDE    # deutscher Client: EldoUI lädt das deutsche Paket
lua5.1 tools/harness/load_eldoui.lua --all            # alle Fehler statt der ersten 60
```

Der Nachbau beantwortet die API-Namen aus `tools/ci/globals.lua`:

- Einige sind von Hand nachgebaut: Spieler, Client, Zeit, Addons, CVars, Timer, Hooks, Farben, Konstanten.
- Frames merken sich Größe, Anker, Skripte, Attribute, Texte und Events.
- Alles andere ist ein „Mock“, der sich aufrufen und indizieren lässt. Ein Aufruf antwortet nach dem Namen:
  `Is*`/`Has*`/`Can*` mit false, alles mit „Num“ oder auf „Count“ mit 0, sonst nil.

Ein neuer Fehler in `load` heißt deshalb entweder:

- ein echter Fehler im Code (z. B. ein Modul, das beim ersten Start abstürzt), oder
- eine Lücke im Nachbau, wenn neuer Code eine Antwort braucht, die der Mock nicht gibt. Dann gehört sie in
  `wow.lua`.

Was der Lauf nicht zeigen kann: alles, was von echten Antworten des Spiels oder vom Zeichnen abhängt.
`tools/harness/test_harness.lua` startet den Lauf mit einem absichtlich kaputten Modul
(`tools/harness/fixtures/broken_module.lua`) und prüft, dass er fehlschlägt und das Modul nennt.

**Neue Texte im Code:** Das deutsche Paket übernimmt die Liste der Texte aus EldoUIs dänischem Paket. Texte, die
dort fehlen (eigene des Forks oder EldoUIs eigene Lücken), stehen in `EldoUI_Locale_deDE/Fork.lua`. Ein neuer
`L["…"]`-Text ohne deutsche Übersetzung lässt `locale` fehlschlagen. Nachtragen mit einer JSON-Datei
`{"English text": "Deutscher Text"}`:

```sh
python3 tools/locale/deDE.py apply fixes.json   # landet in Fork.lua, wenn es kein dänischer Schlüssel ist
```

Texte, die erst beim Anzeigen übersetzt werden (Beschriftungen und Beschreibungen in Optionstabellen, Zeilen mit
`-- no-L (translated where shown)`), findet die Prüfung nicht: Die kommen von Hand per `apply` dazu.

**Neue WoW-API-Namen:** `tools/ci/globals.lua` listet die rund 1.100 Namen, die der Code heute liest. Benutzt
neuer Code bewusst einen weiteren, schlägt luacheck an (W113). Dann die Liste neu erzeugen und mit committen:

```sh
python3 tools/ci/globals.py --update   # zeigt die neuen Namen an
```

Ein neuer Name in der Liste ist im Diff gut zu sehen. So fällt ein Tippfehler wie `UnitHelath` auf, statt
mit in die Liste zu rutschen.

## Release

1. In `EldoUI/EldoUI.toc` (und `EldoUI_Locale_deDE/EldoUI_Locale_deDE.toc`) `## Version:` setzen, z. B. `0.7.3005-p1`, und nach `main` bringen.
2. Release starten, auf einem der zwei Wege:
   - **Auf GitHub, ohne git:** Actions → **Release** → **Run workflow**, Branch `main`, Tag `v0.7.3005-p1` eintragen → Run.
     Der Workflow legt den Tag auf den neuesten Commit von `main` und das Release dazu.
   - **Mit git:** `git tag v0.7.3005-p1 && git push origin v0.7.3005-p1`

Der Workflow bricht ab, wenn der Tag nicht zur Version passt, es den Tag schon für einen anderen Stand gibt oder
eine Prüfung fehlschlägt. Das ZIP heißt
`EldoUI-<Version>.zip` und enthält alle `EldoUI*`-Ordner, die git kennt: entpacken nach `Interface\AddOns`, fertig.
Lokal: `python3 tools/ci/build_zip.py` → `dist/`.

**Versions-Endung `-pN`:** Der Fork hängt an die EldoUI-Version eine Endung an (`0.7.3005-p1`). EldoUIs
Versionscheck liest nur die Zahlen davor. Andere EldoUI-Spieler in Gilde und Gruppe bekommen so keinen falschen
Hinweis „neuere Version“, und eine echte neue EldoUI-Version (0.7.3006) wird weiter gemeldet. Der Hinweis
„Was ist neu“ nach einem Update gehört zur EldoUI-Version vor der Endung (`EldoUI/Core/Config.lua`).

## Neue EldoUI-Version übernehmen

EldoUIs Git-Repository enthält nur die Doku; der Addon-Code erscheint nur als ZIP auf der Releases-Seite. Darum
gibt es zwei Quellen und zwei Merges (zuerst so gemacht für 0.7.3001):

1. **Doku:** `git fetch https://github.com/Eldodeldo/EldoUI.git main:refs/remotes/upstream/main`, dann
   `upstream/main` nach dem Arbeitsbranch mergen (CHANGELOG, README, `docs/`).
2. **Code:** Der Branch `upstream-release` hält jedes Release unverändert, einen Commit pro Version
   (`Import EldoUI <Version> addon source from release zip`). Für das neue Release: die sechs Ordner aus dem ZIP
   (`EldoUI`, `EldoUI_Emoji`, `EldoUI_GuideData`, `EldoUI_Locale_daDK`, `EldoUI_LootData`, `EldoUI_LootSim`) in
   einem Commit auf `upstream-release` ersetzen, Binärdateien unverändert (ohne Zeilenende-Umwandlung). Danach
   `upstream-release` in den Arbeitsbranch mergen: Git legt die Änderungen des Forks per Dreiwege-Merge auf das
   neue Release, Konflikte gibt es nur, wo beide dieselben Zeilen geändert haben.
   - Liegen mehrere Versionen dazwischen (0.7.3001 → 0.7.3005), bekommt jede ihren eigenen Commit; gemergt wird
     einmal, mit der neuesten. Der Versionswächter meldet nur die neueste Version des Tages, ein Issue fehlt dann
     (0.7.3002 erschien am selben Tag wie 0.7.3003).
   - Im ZIP trägt jede Datei denselben Zeitstempel (1980-01-01). Git kann dann eine geänderte Datei gleicher
     Größe übersehen (bei 0.7.3003 drei `.toc`-Dateien, nur die Versionsnummer war anders). Darum vor dem
     `git add` die sechs Ordner mit `git rm -r -q --cached` aus dem Index nehmen, damit Git alles neu einliest,
     und den Commit gegen das ZIP prüfen: `git archive <Commit> <die sechs Ordner> | tar -x -C <leerer Ordner>`,
     dann `diff -r` gegen das entpackte ZIP.
3. **Doppelte Fixes:** Behebt EldoUI selbst etwas, das der Fork schon behoben hatte, gilt EldoUIs Lösung, und der
   Fork behält nur den Teil, den EldoUI nicht abdeckt (Entscheidung des Nutzers vom 16.11.2026). Das betrifft auch
   Fork-Änderungen, die ohne Konflikt durchgelaufen sind; welche es waren, steht in `review/`.
4. **Deutsches Paket:** Die dänische Liste gibt die Schlüssel vor. Texte, die sie nicht mehr hat, fliegen aus den
   vier deutschen Dateien, neue brauchen eine Übersetzung (`deDE.py export` / `import`).
5. Versionen auf `<EldoUI-Version>-p1` setzen (siehe Release), Prüfungen grün, im Spiel testen, Tag pushen.

## Versionswächter

`watch_versions.py` liest einmal am Tag drei Quellen:

| Quelle | Woher | Meldet |
|---|---|---|
| WoW: Forever live | Blizzards öffentlicher Versionsserver, Produkt `wowf` (`1.60.1.70938` = Interface 16001) | Patch mit höherer Interface-Nummer als die .toc-Dateien |
| Test-Client | Produkt `wow_classic_beta`, nur solange dort ein 1.x-Build läuft | der nächste Patch, meist Tage bis Wochen vor dem Live-Gang |
| EldoUI | neuestes Release von github.com/Eldodeldo/EldoUI | neue Version, auf der der Fork aufbauen sollte |

Für jede Neuigkeit legt er genau ein Issue mit dem Label **Versions-Check** an. Ein geschlossenes Issue wird nicht
wieder geöffnet. Gibt es nichts Neues, endet der Lauf still und grün, mit dem aktuellen Stand in der Zusammenfassung.
Ist eine Quelle nicht erreichbar oder sind Issues im Repo abgeschaltet, wird der Lauf rot, und GitHub schickt
die übliche Fehler-Mail.

Grenzen:

- Die Interface-Nummer sagt nur, dass die .toc hinterher ist. Ob alle Teile mit dem Patch noch laufen, zeigt erst
  das Spiel, oder die EldoUI-Version für den Patch, die die nötigen Anpassungen mitbringt.
- Geplante Workflows laufen nur aus dem Standard-Branch (`main`). In einem öffentlichen Repo schaltet GitHub sie
  nach 60 Tagen ohne Aktivität ab; ein Klick unter Actions schaltet sie wieder ein.

Lokal, ohne Issues: `python3 tools/ci/watch_versions.py`
