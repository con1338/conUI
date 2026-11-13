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

## Festgelegt in Welle 1 (Core)

Diese Entscheidungen gelten für alle weiteren Texte.

| Englisch | Deutsch |
|---|---|
| box (im Verschiebemodus) / Hidden boxes | Feld / „Ausgeblendete Felder“ (Verschiebefeld, wo Verwechslung droht) |
| key set (Tastenvorlage eines Profils) | Tastensatz (der), Mehrzahl Tastensätze |
| key map | Tastenbelegung |
| keybind mode | Tastenbelegungsmodus |
| button (Platz für Zauber/Makro auf einer Leiste) | Platz („Leiste %d, Platz %d“) |
| button (Bedienelement) | Schaltfläche |
| power (Mana, Wut, Energie) / power bar | Ressource / Ressourcenleiste |
| panel | Panel (das Panel, die Panels) |
| Finish (letzter Schritt der Einrichtung) | „Abschließen“ – auch im Satz: „beim Abschließen“, „Übernehmen oder Abschließen“ |
| Applies at Finish | Wird beim Abschließen übernommen |
| apply (Verb im Satz) | anwenden / übernehmen |
| Revert / Revert this | Zurücknehmen / Dies zurücknehmen |
| set aside / put back / kept / held (gespeicherte Daten) | beiseitelegen / zurückholen / aufbewahrt / zurückgehalten |
| Let go (gespeicherte Daten) | Freigeben |
| job (ein Addon übernimmt eine EldoUI-Aufgabe) | Aufgabe; „X übernimmt diese Aufgabe“ |
| reload (Nomen) | Neuladen |
| error log | Fehlerprotokoll |
| outline (Schrift) | Kontur |
| glow / tint / pulse | Leuchten / Tönung / Pulsieren |
| accent (Farbe) | Akzent / Akzentfarbe |
| UI amount (Essential / Moderate / Full) | UI-Umfang (Grundlegend / Mittel / Voll) |
| Consumable Bar / Stance Bar / pet bar | Verbrauchsgüterleiste / Haltungsleiste / Begleiterleiste |
| Cooldown Manager | Abklingzeitenmanager |
| Appearance / Accessibility / What's new | Erscheinungsbild / Barrierefreiheit / Neuigkeiten |
| Convenience(s) | Komfort / Komfortfunktionen |
| alt setup / Alts window | Twink-Einrichtung / Twink-Fenster |
| Legacy (Forever-Funktion) | Vermächtnis |
| Group finder / gossip / Inspect | Gruppensuche / Gespräch / Betrachten |
| Shift / Ctrl / Mouse 4 / side buttons | Umschalt / Strg / Maustaste 4 / Seitentasten |
| string (Import/Teilen) / tag (Text-Tag) | String (der) / Tag (das) |
| Cleanse (Tastenkategorie) | Reinigung (der Paladinzauber heißt „Reinigung des Glaubens“) |
| thousand / million / billion | Tsd. / Mio. / Mrd. |
| on / off als Anzeige (nicht eingetippt) | an / aus |

**Namen bleiben englisch:** Layouts (EldoUI Center, Twin Orbs, Modern Center …) und Skins (Infernal Stone,
Forged Metal, Faction Heritage, Portrait Classic …) – das sind Eigennamen. Fraktionen darin deutsch:
„Faction Heritage: Allianz“.

**Modul-Stile werden übersetzt**, wenn ihr Name etwas beschreibt: „Quiet“ → „Ruhig“, „Compact“ → „Kompakt“,
„Cinematic“ → „Filmisch“, „Chunky“ → „Wuchtig“, „Large“ → „Groß“, „Plain“ → „Schlicht“. Reine Eigennamen
(Modern, Classic, Minimal) bleiben.

**Spiel-Eigennamen** (Zauber, Gegenstände, Reagenzien, Gebiete) wie im deutschen Client. Wo unsicher: so
belassen, wie der Code ihn zeigt – viele dieser Namen sind nur Ersatz, bis der Client den echten Namen liefert.

**Kleingeschriebene Einsetzungen:** Einige Texte bekommen einen Namen per `what:lower()` kleingeschrieben
eingesetzt. Den Satz dann so bauen, dass kein Artikel davor nötig ist („… verdecken: %s“).

## Festgelegt in Welle 2 (Module A–L, erste Hälfte)

| Englisch | Deutsch |
|---|---|
| Glows (Seite) | „Leuchteffekte“ – Verweise: „auf der Seite „Leuchteffekte““ (das Leuchten selbst bleibt „Leuchten“) |
| Alerts (Chat-Reiter) | „Hinweise“ („Chatreiter „Hinweise““) |
| run (Instanz) / runs | Durchlauf / Durchläufe |
| lockout(s) | Instanzsperre(n), kurz Sperre(n) |
| gathering node / fishing pool | Vorkommen / Fischschwarm |
| camp / camp buffs / Camp Helper | Lager / Lagereffekte / Lagerhelfer |
| pull / packs (Dungeonrouten) / floor | Pull / Gegnergruppen / Ebene |
| guide (Eldostar) / leveling guide | Guide / Levelguide |
| swing timer / swing bar | Schlagtimer / Schlagleiste |
| cooldown swipe / GCD sweep | Spirale / GCD-Füllung |
| charges / recharge | Aufladungen / Wiederaufladung |
| mirror timers | Atem- und Erschöpfungsleisten |
| damage meter / boss mod | Schadensmesser / Bossmod |
| master loot / master looter | Plündermeister |
| loot toasts / loot feed | Beutehinweise / Beuteticker |
| main hand / off hand | Waffenhand / Schildhand |
| rested XP / durability (kurz) | Erholungsbonus / Haltbarkeit („Haltb.“) |
| appearance (Transmog) / look | Vorlage / Aussehen; die Wörter der Sammlung: Neu / Aussehen / Vorhanden |
| keyword (Chat-Alarm) / edit box / mute | Stichwort / Eingabefeld / stummschalten |
| Death Recap / Crosshair / Cursor ring | Todesrückblick / Fadenkreuz / Cursorring |
| bank tab / account bank / junk | Bankreiter / Accountbank / Plunder |
| Raid Tools / Bag Actions / Integrations | Schlachtzugswerkzeuge / Taschenaktionen / Integrationen |
| Mill (Taschenaktion; derselbe Schlüssel ist das Spiel „Mühle“) | Mahlen |
| yd | m (wie der deutsche Client) |
| Zeiteinheiten kurz | Sek. / Min. / Std. |

## Festgelegt in Welle 3 (Module A–L, zweite Hälfte)

| Englisch | Deutsch |
|---|---|
| Let EldoUI change this (Schalter) | „EldoUI dies ändern lassen“ – Verweise genau so |
| Tell the guild (Schaltfläche) | „Der Gilde sagen“ |
| Boss Timers | Boss-Timer |
| Safe to sell | Sicher verkaufbar |
| Post to group / Post to guild | An Gruppe posten / An Gilde posten |
| post (Chat) / post (Auktionshaus) | posten / einstellen |
| Qualitätsstufen | Schlecht / Verbreitet / Selten / Rar / Episch / Legendär („Uncommon+“ → „Selten+“) |
| NPC | NSC |
| trinket / trinket slot | Schmuckstück / Schmuckplatz |
| undercut | unterbieten / Unterbietung |
| withdraw (Gildenbank) | abheben / Abhebung |
| tray (Aktionsleisten) | Ablage |
| pip (Kombopunkt) | Punkt |
| queue | Warteschlange |
| patrol | Patrouille |
| sticky lines (Kampftext) | haftende Zeilen |
| session (Farming) | Sitzung |
| tracking bar | Verfolgungsleiste |
| possess bar | Besessenheitsleiste |
| tick marks / stage (Timer) | Teilstriche / Phase |
| Stat-Kürzel Spi / Sta / Str / SP / RAP | Wil / Aus / Stä / ZM / DAK |
| Usage: | Verwendung: |
| Klick-Hinweise in Tooltips | Infinitiv klein („im Chat verlinken“) oder Substantiv; Ziele ohne Artikel |

**Querverweise:** Zitiert ein Text eine Beschriftung in Anführungszeichen, muss genau deren Übersetzung
stehen – `deDE.py xref` prüft das.

## Festgelegt in Welle 4 (Module M–Z, erste zwei Drittel)

| Englisch | Deutsch |
|---|---|
| ledger (GDKP) / pot / cut / payout | Kassenbuch / Topf / Abzug (Abzüge vom Topf) bzw. Anteil (der eines Spielers) / Auszahlung |
| button bin | Knopfsammler |
| alert lane | Warnspalte |
| restock / restock list | Auffüllen / Auffüllliste |
| scale (Pawn/Upgrades) / weights | Skala / Gewichtung |
| rare (Gegner) / Rares / Rare elite | rarer Gegner / Rare / Rar-Elite (nicht „selten“ – das ist die Qualitätsstufe) |
| snapshot / Bar Snapshots | Schnappschuss / Leistenschnappschüsse |
| plate | Plakette |
| leader / main tank / main assist | Anführer / Haupttank / Hauptassistent |
| map pin | Kartenmarkierung |
| alias (Streamermodus) | Aliasname |
| splits (Split Timer) | Zwischenzeiten |
| Modulnamen | Berufsplaner, Schlachtzugsbeute, Gruppenquests, Spielernotizen, Questmarkierungen, Schamanentotems, Bereitschaftsbericht, Tierpflege, Gegnerfähigkeiten, Zaubereffizienz, Rar-Alarme |
| In / Out (Handelsprotokoll) | Erhalten / Gegeben |

**Bleibt englisch, weil der Code den Namen so speichert:** „Profession Planner“ (Name der Einkaufsliste).
