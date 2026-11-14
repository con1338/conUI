-- EldoUI's texts in German (deDE): the texts that are not in EldoUI's Danish list (this fork's own, and EldoUI's own that the Danish pack lacks).
-- English is the key; a text missing here shows in English. The player is
-- addressed with "Ihr/Euch" and game terms are the ones the deDE client
-- uses, as in the Loot Guide's German table. Keep every %s, %d, {token} and
-- |c...|r code exactly as it is. Built with tools/locale/deDE.py.
-- This folder loads only when Deutsch is picked under General > EldoUI language
-- (or on a German client), and the table is built then. It is its own addon,
-- so EldoUI comes from its global.
local E = EldoUI
if not E then return end
-- Later tables for the same language add keys (E:RegisterLocale), so these
-- join the four files before it. `check` keeps every key here a string of
-- EldoUI's code that is not in the Danish list.
E:RegisterLocale("deDE", function() return {
	["%d run Lua code"] = "%d davon führen Lua-Code aus",
	["%d. %s: %.2f ms/s (%d%%), %d calls, slowest %.2f ms (%s)"] = "%d. %s: %.2f ms/s (%d%%), %d Aufrufe, langsamster %.2f ms (%s)",
	["%s wants to send you EldoUI settings. Answer your open question first; they can offer again in %d seconds."] = "%s möchte Euch EldoUI-Einstellungen senden. Beantwortet zuerst Eure offene Frage; ein neues Angebot ist in %d Sekunden möglich.",
	["(runs Lua code)"] = "(führt Lua-Code aus)",
	["A block other addons can show: Titan Panel, ChocolateBar and the like list it as \"EldoUI: name\". It is kept up to date while it is chosen here, also in combat. A block taken out again stays in their list until a reload."] = "Ein Datentext, den andere Addons zeigen können: Titan Panel, ChocolateBar und ähnliche führen ihn als „EldoUI: Name“. Er bleibt aktuell, solange er hier gewählt ist, auch im Kampf. Wieder herausgenommen bleibt er bis zum nächsten Neuladen in ihrer Liste.",
	["A guild member's DKP or EPGP standing, read from the guild notes (Raid Loot > Guild points)."] = "Der DKP- oder EPGP-Stand eines Gildenmitglieds, gelesen aus den Gildennotizen (Schlachtzugsbeute > Gildenpunkte).",
	["A thin bar at the bottom of each frame while the member casts: casts fill, channels empty, gray when the cast can't be interrupted."] = "Eine schmale Leiste am unteren Rand jedes Rahmens, solange das Mitglied zaubert: Zauber füllen sie, kanalisierte Zauber leeren sie, grau, wenn sich der Zauber nicht unterbrechen lässt.",
	["After the names"] = "Hinter den Namen",
	["Battleground map"] = "Schlachtfeldkarte",
	["Block %d for other addons"] = "Datentext %d für andere Addons",
	["Careful: %d of these macros run Lua code (%s). Add them only if you trust where the string came from."] = "Vorsicht: %d dieser Makros führen Lua-Code aus (%s). Fügt sie nur hinzu, wenn Ihr der Herkunft des Strings vertraut.",
	["Cast bar height"] = "Höhe der Zauberleiste",
	["Clock and stopwatch"] = "Uhr und Stoppuhr",
	["DKP or EPGP standings from the guild notes, after the names on the SR and TMB lines, on guild members' tooltips and in the Info Bar block \"Guild points\". Automatic: EPGP notes (\"1250,830\") and DKP notes with a label (\"Net:350\", \"DKP: 350\"). DKP also takes a plain number."] = "DKP- oder EPGP-Stände aus den Gildennotizen, hinter den Namen in den SR- und TMB-Zeilen, im Tooltip von Gildenmitgliedern und im Infoleisten-Block „Gildenpunkte“. Automatisch: EPGP-Notizen („1250,830“) und DKP-Notizen mit Kennung („Net:350“, „DKP: 350“). DKP nimmt auch eine bloße Zahl.",
	["Each player's standing after their name on the SR and TMB lines. The chat post of the reservations never carries it."] = "Der Stand jedes Spielers hinter seinem Namen in den SR- und TMB-Zeilen. Der Chat-Beitrag mit den Reservierungen enthält ihn nie.",
	["EldoUI timing"] = "EldoUI-Zeitmessung",
	["EldoUI timing, %s measured (%s):"] = "EldoUI-Zeitmessung, %s gemessen (%s):",
	["From the note"] = "Aus der Notiz",
	["Guild points"] = "Gildenpunkte",
	["Guild points (DKP and EPGP)"] = "Gildenpunkte (DKP und EPGP)",
	["Height of the cast bar. From 8 pixels it has room for the spell name."] = "Höhe der Zauberleiste. Ab 8 Pixeln hat sie Platz für den Zaubernamen.",
	["Names can't contain | or line breaks."] = "Namen dürfen kein | und keine Zeilenumbrüche enthalten.",
	["No DKP or EPGP standings in the guild notes."] = "Keine DKP- oder EPGP-Stände in den Gildennotizen.",
	["Nothing measured yet."] = "Noch nichts gemessen.",
	["Officer note"] = "Offiziersnotiz",
	["Profile %s switched off: %s. Blizzard's own versions come fully back after a reload."] = "Profil %s hat ausgeschaltet: %s. Blizzards eigene Versionen kehren nach einem Neuladen vollständig zurück.",
	["Public note"] = "Öffentliche Notiz",
	["Read standings"] = "Stände lesen",
	["Self-Found is on for this character: mail from other players can't be used."] = "„Selbstgefunden“ ist für diesen Charakter aktiv: Post von anderen Spielern kann nicht genutzt werden.",
	["Self-Found is on for this character: the auction house can't be used."] = "„Selbstgefunden“ ist für diesen Charakter aktiv: Das Auktionshaus kann nicht genutzt werden.",
	["Self-Found is on for this character: trading with other players is blocked."] = "„Selbstgefunden“ ist für diesen Charakter aktiv: Der Handel mit anderen Spielern ist gesperrt.",
	["Spell name on the cast bar"] = "Zaubername auf der Zauberleiste",
	["That name is too long."] = "Dieser Name ist zu lang.",
	["The name of the spell on the bar, when the bar is at least 8 pixels high."] = "Der Name des Zaubers auf der Leiste, wenn sie mindestens 8 Pixel hoch ist.",
	["There is no profile with that name."] = "Es gibt kein Profil mit diesem Namen.",
	["This list can't be imported from a string (%s)."] = "Diese Liste lässt sich nicht aus einem String importieren (%s).",
	["Timing each module now. /eui perf shows the results, /eui perf stop ends it."] = "Jedes Modul wird jetzt gemessen. /eui perf zeigt die Ergebnisse, /eui perf stop beendet die Messung.",
	["Timing is not running. /eui perf starts it."] = "Die Zeitmessung läuft nicht. /eui perf startet sie.",
	["Timing started again from zero."] = "Zeitmessung von vorn gestartet.",
	["Titan Panel, ChocolateBar and other LibDataBroker displays can show Info Bar blocks once one of them is loaded."] = "Titan Panel, ChocolateBar und andere LibDataBroker-Anzeigen können Datentexte der Infoleiste zeigen, sobald eines davon geladen ist.",
	["Total: %.2f ms/s over %d calls."] = "Gesamt: %.2f ms/s bei %d Aufrufen.",
	["Toy box"] = "Spielzeugkiste",
	["Type a name first."] = "Gebt zuerst einen Namen ein.",
	["When the Masque addon is loaded, let it skin these buttons (Masque lists them under EldoUI). EldoUI's own button art steps aside."] = "Ist das Addon Masque geladen, darf es diese Tasten skinnen (Masque führt sie unter EldoUI). EldoUIs eigene Tastengrafik tritt dann zurück.",
	["Which guild note holds the standings. The officer note counts only when the game lets you see it."] = "Welche Gildennotiz die Stände enthält. Die Offiziersnotiz zählt nur, wenn das Spiel sie Euch zeigt.",
	["[stop | reset | copy]  time each module's events and timers; once started, /eui perf shows what it measured"] = "[stop | reset | copy]  Events und Timer jedes Moduls messen; läuft die Messung, zeigt /eui perf das Ergebnis",
	["running"] = "läuft",
	["stopped"] = "beendet",
	["the string comes from a newer EldoUI (%s). Update EldoUI, then import it again."] = "der String stammt aus einem neueren EldoUI (%s). Aktualisiert EldoUI und importiert ihn dann erneut.",
	["the string comes from a newer EldoUI. Update EldoUI, then import it again."] = "der String stammt aus einem neueren EldoUI. Aktualisiert EldoUI und importiert ihn dann erneut.",
	["the string comes from an EldoUI before 0.7.1000, which this version can't read. Ask for a new string."] = "der String stammt aus einem EldoUI vor 0.7.1000; diese Version kann ihn nicht lesen. Bittet um einen neuen String.",
	["v%s loaded. Type %s for options."] = "v%s geladen. Gebt %s ein, um die Optionen zu öffnen.",
} end)
