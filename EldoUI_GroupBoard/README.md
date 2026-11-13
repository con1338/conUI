# EldoUI Group Board (Gruppen-Pinnwand)

Ein Plugin für EldoUI aus diesem Fork. Es sammelt Gruppenbeiträge aus den öffentlichen Chat-Kanälen
(„LF2M DM need tank“, „Heiler sucht Gruppe für BRT“) und zeigt sie in einem Fenster im EldoUI-Look:
wer sucht, für welchen Dungeon oder Schlachtzug, welche Rollen fehlen, wie lange das her ist.

Es nutzt nur die öffentliche Plugin-Schnittstelle von EldoUI (`docs/PLUGINS.md`), ändert nichts in
`EldoUI/` und bleibt so bei Upstream-Updates unberührt.

## Installation

Den Ordner `EldoUI_GroupBoard` neben `EldoUI` in `World of Warcraft\_forever_\Interface\AddOns` legen.
Das Plugin erscheint unter **Plugins** in den EldoUI-Optionen und lässt sich dort ein- und ausschalten.

## Bedienung

- **Öffnen:** `/eui board`, der Block „Gruppen-Pinnwand“ in der Infoleiste (in einem Slot auswählen),
  der Finder (`/eui go`) oder der Knopf auf der Optionsseite.
- **Filter (Chips oben):** Gruppen (LFM) / Spieler (LFG), „Meine Stufe“, Tank / Heiler / Schaden,
  Dungeons / Schlachtzüge / Quests / Anderes. Ist in einer Reihe nichts an, gilt die ganze Reihe.
  Beiträge ohne genannte Rolle bleiben bei Rollenfiltern sichtbar. Die Filter werden im Profil gespeichert.
- **Suche:** Namen, Orte (englisch, deutsch und der Name des Clients) und der Text der Beiträge.
- **Zeile:** Klick flüstert den Absender an, Rechtsklick blendet den Beitrag aus (bis der Absender etwas
  anderes postet). Knöpfe: Flüstern, Einladen (nur bei Spielern, die eine Gruppe suchen; nicht im Kampf),
  Ausblenden. Der Tooltip zeigt die ganze Zeile, Stufenbereich, Kanal und wie oft gepostet wurde.
- **Hinweis (aus):** Auf Wunsch eine Chatzeile und ein Sound bei jeder neuen Gruppe, die durch die Filter
  kommt. Nie im Kampf, einmal pro Beitrag.

## Optionen

| Option | Standard |
|---|---|
| Kanal SucheNachGruppe / Allgemein / Handel | an / an / aus |
| Weitere Kanäle nach Name (z. B. „World, Welt“) | an |
| Minuten, die ein Beitrag bleibt | 10 |
| Über neue Gruppen informieren (Chatzeile, Sound) | aus |

## Was erkannt wird

- **LFM/LFG:** `LFM`, `LF2M`, `need`, `x/5`, „suchen noch“, „brauchen“, „Gruppe sucht Tank“ gegen `LFG`,
  „LF group“, „suche Gruppe“, „Tank sucht Gruppe“. `LF`/„suche“ vor einer Rolle oder Zahl heißt Gruppe,
  vor einem Ort oder „Gruppe“ heißt Spieler.
- **Orte:** alle klassischen Dungeons und Schlachtzüge mit englischen und deutschen Namen und den üblichen
  Kürzeln (RFC, DM/Todesminen, SM Lib/Kloster Bibliothek, BRD/BRT, DM Ost/DB Ost, UBRS, Strat UD …), die
  neuen Forever-Dungeons mit ihren englischen Namen. Beim Login liest das Plugin die Dungeonliste des
  Clients: Namen in der Sprache des Clients, Stufenbereiche von Forever und Dungeons, die die Tabelle
  nicht kennt. Der längste Treffer gewinnt („DM East“ vor „DM“); Flügelwörter wie „lib“ oder „arm“
  zählen allein nur, wenn kein anderer Ort genannt ist, Richtungswörter („west“, „lower“) nur neben ihrem
  Hauptnamen.
- **Rollen:** Tank, Heiler/Healer, DPS/DD/Schaden, mit Anzahl („2 dps“, „2x DD“, „LF2dps“).
- **Keine Gruppenbeiträge:** Handel (WTS/WTB/VK), Gildenwerbung ohne Ort, Dienste (Portale, Beschwörungen,
  Verzauberungen, Schlossknacken, Boosts).

## Regeln (WoW: Forever)

- Gelesen wird nur, was das Spiel Addons gibt; geheime Werte werden nie gelesen. In Dungeons und
  Schlachtzügen verbirgt das Spiel den Chat vor Addons, das Fenster sagt das dann.
- Nichts wird gesendet: Flüstern und Einladen sind immer ein Klick des Spielers.
- Beiträge gibt es nur für die laufende Sitzung; gespeichert werden nur Optionen, Filter und Fensterplatz.
- Links und Textcodes aus fremden Zeilen werden entfernt, nicht angezeigt.

## Grenzen

- **Im Spiel nicht getestet.** Geprüft ist das Plugin offline (siehe unten). Unsicher sind vor allem die
  Kanal-ID von SucheNachGruppe auf Forever (angenommen: 26, zusätzlich Erkennung über den Namen) und die
  Rückgabewerte von `GetLFGDungeonInfo` (wie im Loot Guide von EldoUI).
- Für die neuen Forever-Dungeons sind keine Kürzel bekannt, nur die vollen Namen. Wenn sich in der
  Community Kürzel einbürgern, gehören sie in `Catalog.lua`.
- Die deutschen Namen der klassischen Dungeons stammen aus dem Gedächtnis, nicht aus dem Client; der
  Name aus der Dungeonliste des Clients wird zusätzlich erkannt.

## Prüfen

```bash
lua5.1 tools/groupboard/test_parse.lua
lua5.1 tools/groupboard/test_board.lua
python3 tools/groupboard/check_locale.py
luacheck --config tools/groupboard/luacheckrc.lua EldoUI_GroupBoard
```

`test_parse.lua` liest Beispielzeilen auf Englisch und Deutsch, `test_board.lua` spielt das Plugin mit
Attrappen für Spiel und EldoUI durch (Kanäle, Filter, Hinweis, Fenster, Infoleiste, Abschalten, Deutsch),
`check_locale.py` prüft die deutschen Texte auf Vollständigkeit, Platzhalter und gleiche Übersetzung wie
im Sprachpaket.

## Lizenz

Apache License 2.0 (`LICENSE`), wie EldoUI.
