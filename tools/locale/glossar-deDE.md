# Glossar und Stilregeln: EldoUI auf Deutsch (deDE)

Gilt für alle Texte in `EldoUI_Locale_deDE`. Vorbild ist die vorhandene deutsche Loot-Guide-Übersetzung
(`EldoUI/Modules/LootGuide/Locale/deDE.lua`) und der deutsche WoW-Client.

## Stil

- **Anrede „Ihr/Euch/Euer“**, großgeschrieben, wie im deutschen WoW-Client:
  „Wählt Euer Layout.“ – „Eure Taschen zählen es, sobald Ihr es plündert.“ – „Etwas hoch für Euch.“
  Imperativ in der Ihr-Form: „Klickt“, „Wählt“, „Öffnet“, „Zieht“. Nie „du“ oder „Sie“.
- **Kurze Beschriftungen** (Buttons, Schalter, Spaltenköpfe, Menüeinträge): Infinitiv oder Substantiv,
  keine Anrede: „Anzeigen“, „Zurücksetzen“, „Aktionsleisten ausblenden“, „Schriftgröße“.
- **Kürze:** Deutsch läuft etwa 20 % länger als Englisch, viele Buttons haben eine feste Breite. Bei kurzen
  Beschriftungen das kürzeste natürliche Wort wählen („Aus“ statt „Ausgeschaltet“, „Karte“ statt „Weltkarte“,
  wenn der Zusammenhang klar ist).
- **Natürliches Deutsch**, keine Wort-für-Wort-Übersetzung. Satzbau darf sich ändern, solange die Platzhalter
  in derselben Reihenfolge bleiben (siehe unten).
- **Groß/klein:** Englische Title Case wird zu normaler deutscher Schreibung („Action Bars“ → „Aktionsleisten“).
  Beginnt der englische Text klein (Teilsatz, wird angehängt), beginnt der deutsche auch klein.
- **Satzzeichen** wie im Englischen übernehmen (Punkt, Doppelpunkt, Auslassungspunkte „…“). Deutsche
  Anführungszeichen „…“ nur, wo das Englische Anführungszeichen hat und kein Platzhalter darin steht;
  `"%s"` bleibt `"%s"`.

## Technische Regeln (werden automatisch geprüft)

- Jeder Platzhalter bleibt exakt erhalten und in **derselben Reihenfolge**: `%s`, `%d`, `%.1f`, `%02d`, `%%` …
  Muss die Reihenfolge wirklich anders sein, positionsbezogen schreiben: `%2$s … %1$s`.
- `{token}` (z. B. `{level}`, `{name}`) unverändert lassen.
- Farb- und Textcodes unverändert: `|cffRRGGBB` … `|r`, `|T…|t`, `|H…|h…|h`, `|n`, `||`.
- Zeilenumbrüche (`\n`) in gleicher Anzahl.
- **Nicht übersetzen:** „EldoUI“, Addon-Namen (Details!, BigWigs, ElvUI, Questie …), Slash-Befehle und alles,
  was der Spieler eintippt (`/eui move`, `on`, `off`, `undo`, `[name]`, `[text]`, Wörter in eckigen Klammern
  in Befehlshilfen), CVar-Namen, Dateipfade, Tastenkürzel-Codes.
- Rein technische Texte (`%s/%s`, `x%d`, `%d%%`) unverändert übernehmen.
- **Pluralformen** (`"plural": true`): `{"one": "…", "other": "…"}`. Die one-Form darf die Zahl ausschreiben
  („Ein Gegenstand“), meist bleibt `%d` aber stehen: `{"one": "%d Gegenstand", "other": "%d Gegenstände"}`.

## Begriffe

Spalte „fest“: so in der Loot-Guide-Übersetzung oder im Client; bitte genau so verwenden.

### Spiel

| Englisch | Deutsch |
|---|---|
| quest / quests | Quest / Quests (die Quest) |
| quest objective | Questziel |
| quest log | Questlog |
| loot (Nomen) / to loot | Beute / plündern |
| drop(s) | Beute; „X drops Y“ → „X lässt Y fallen“ |
| item(s) | Gegenstand / Gegenstände |
| gear | Ausrüstung |
| stats | Werte |
| upgrade(s) | Verbesserung(en) |
| raid | Schlachtzug |
| party / group | Gruppe |
| dungeon | Dungeon |
| instance | Instanz |
| boss | Boss |
| rare (Gegner) | Rar / rarer Gegner |
| elite | Elite |
| level | Stufe |
| experience / XP | Erfahrung / EP |
| reputation | Ruf |
| attunement | Einstimmung |
| zone | Gebiet (Zone als Fachwort nur in „Zonenfähigkeit“) |
| world map / map / minimap | Weltkarte / Karte / Minikarte |
| flight path / flight master | Flugroute / Flugmeister |
| hearthstone | Ruhestein |
| inn / innkeeper | Gasthaus / Gastwirt |
| trainer | Lehrer |
| vendor / merchant | Händler |
| auction house | Auktionshaus |
| mail / mailbox | Post / Briefkasten |
| trade | Handel |
| bags / bank | Taschen / Bank |
| profession | Beruf |
| recipe | Rezept |
| mount | Reittier |
| pet | Begleiter (Jägertier: Tier) |
| spell / ability | Zauber / Fähigkeit |
| spellbook | Zauberbuch |
| talents / talent tree | Talente / Talentbaum |
| cooldown | Abklingzeit |
| buff / debuff | Stärkungszauber / Schwächungszauber (kurz in Labels: Buffs/Debuffs nur wenn Platz knapp) |
| aura(s) | Aura / Auren |
| cast / cast bar | Zauber wirken / Zauberleiste |
| interrupt | unterbrechen |
| threat | Bedrohung |
| health / mana / rage / energy | Gesundheit / Mana / Wut / Energie |
| combo points | Kombopunkte |
| tank / healer / damage | Tank / Heiler / Schaden |
| melee / ranged | Nahkampf / Distanz |
| role | Rolle |
| guild / whisper | Gilde / Flüstern (flüstern) |
| ready check | Bereitschaftscheck |
| battleground / arena | Schlachtfeld / Arena |
| honor | Ehre |
| gold / silver / copper | Gold / Silber / Kupfer |
| character / alt | Charakter / Twink |
| realm | Realm |
| journal | Tagebuch |
| keepsake | Andenken |
| wishlist | Wunschliste |
| soft reserve (SR) | Soft-Reserve (SR) |
| waypoint | Wegpunkt |
| note(s) | Notiz(en) |

### Oberfläche (Client-Begriffe)

| Englisch | Deutsch |
|---|---|
| action bar | Aktionsleiste |
| action button / slot | Aktionstaste / Platz |
| unit frames | Einheitenrahmen |
| player / target / focus frame | Spielerrahmen / Zielrahmen / Fokusrahmen |
| party / raid frames | Gruppenrahmen / Schlachtzugsrahmen |
| nameplates | Namensplaketten |
| tooltip | Tooltip |
| chat frame / chat tab | Chatfenster / Chatreiter |
| micro menu | Mikromenü |
| bag bar | Taschenleiste |
| objective / quest tracker | Zielverfolgung / Questverfolgung |
| keybind / key binding | Tastenbelegung |
| key | Taste |
| macro | Makro |
| Edit Mode | Bearbeitungsmodus |
| UI scale | UI-Skalierung |
| reload (UI) | neu laden („Interface neu laden“, Button: „Neu laden“) |
| click / right-click / Shift-click | Klick / Rechtsklick / Umschaltklick (Strg-Klick, Alt-Klick) |
| drag | ziehen |
| combat | Kampf („im Kampf“, „nach dem Kampf“) |
| settings / options | Einstellungen / Optionen |
| profile | Profil |
| default(s) | Standard / Standardwerte |
| enable / disable / on / off | Aktivieren / Deaktivieren / An / Aus |
| show / hide | Anzeigen / Ausblenden |
| reset | Zurücksetzen |
| import / export / copy / delete | Importieren / Exportieren / Kopieren / Löschen |
| apply / undo / cancel | Übernehmen / Rückgängig / Abbrechen |
| accept / decline | Annehmen / Ablehnen |
| close / open / back / next / done | Schließen / Öffnen / Zurück / Weiter / Fertig |
| search / filter | Suchen / Filter |

### EldoUI-eigene Begriffe

| Englisch | Deutsch |
|---|---|
| module | Modul |
| layout | Layout |
| preset / preset pack | Vorlage / Vorlagenpaket |
| look | Optik |
| skin | Skin |
| style (module style) | Stil |
| setup (the guided setup) | Einrichtung |
| move mode | Verschiebemodus |
| mover (the box you drag) | Rahmen (im Verschiebemodus); wo Verwechslung droht: Verschiebefeld |
| lock / unlock | Sperren / Entsperren |
| grid / snap / nudge | Raster / einrasten / pixelweise verschieben |
| info bar / data text | Infoleiste / Datentext |
| combat HUD | Kampf-HUD |
| combat text | Kampftext |
| click casting | Klickzauber |
| streamer mode | Streamermodus |
| saved data | gespeicherte Daten |
| share string | Teilen-String |
| plugin | Plugin |
| toast | Hinweis (kleines Einblendfenster) |
| My Adventure | Mein Abenteuer (so in der Loot-Guide-Übersetzung) |
| Eldostar | Eldostar (Eigenname) |
| Loot Guide | Loot Guide (Eigenname) |
