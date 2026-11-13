-- EldoUI Group Board: German texts.
--
-- Registered as a function, so the table is only built when German is the
-- language EldoUI shows; EldoUI adds it to the texts of its German pack
-- (EldoUI_Locale_deDE). Keys every EldoUI text already has keep the pack's
-- translation (tools/groupboard/check_locale.lua checks it).
-- Style and terms: tools/locale/glossar-deDE.md (Ihr-form, Stufe,
-- Schlachtzug, Flüstern). "Group board" is "Gruppen-Pinnwand": the game's
-- own group finder is already "Gruppensuche".
local E = EldoUI
if not (E and E.RegisterLocale) then return end

E:RegisterLocale("deDE", function()
	return {
		-- The module and its page
		["Group Board"] = "Gruppen-Pinnwand",
		["Group board"] = "Gruppen-Pinnwand",
		["Collects group posts from the public chat channels in one window: who looks for which dungeon, which roles a group needs, how long ago."] =
			"Sammelt Gruppenbeiträge aus den öffentlichen Chat-Kanälen in einem Fenster: wer für welchen Dungeon sucht, welche Rollen eine Gruppe braucht und wie lange das her ist.",
		["Open the group board"] = "Gruppen-Pinnwand öffnen",
		["Opens the board window. /eui board and the Group board block on the info bar open it too."] =
			"Öffnet das Fenster der Pinnwand. Auch /eui board und der Block Gruppen-Pinnwand in der Infoleiste öffnen es.",
		["Channels"] = "Kanäle",
		["LookingForGroup channel"] = "Kanal SucheNachGruppe",
		["Reads group posts in the LookingForGroup channel, when you have joined it."] =
			"Liest Gruppenbeiträge im Kanal SucheNachGruppe, wenn Ihr ihm beigetreten seid.",
		["General channel"] = "Kanal Allgemein",
		["Reads group posts in the General channel of the zone you are in."] =
			"Liest Gruppenbeiträge im Kanal Allgemein des Gebiets, in dem Ihr seid.",
		["Trade channel"] = "Handelskanal",
		["Reads group posts in the Trade channel of the city you are in."] =
			"Liest Gruppenbeiträge im Handelskanal der Stadt, in der Ihr seid.",
		["Other channels by name"] = "Weitere Kanäle nach Name",
		["Reads group posts in joined channels whose names you list below, such as World."] =
			"Liest Gruppenbeiträge in beigetretenen Kanälen, deren Namen Ihr unten angebt, etwa World.",
		["Channel names"] = "Kanalnamen",
		["Names of joined channels to read, separated by commas. Upper and lower case don't matter."] =
			"Namen der beigetretenen Kanäle, die gelesen werden, durch Kommas getrennt. Groß- und Kleinschreibung spielt keine Rolle.",
		["Posts"] = "Beiträge",
		["Minutes a post stays"] = "Minuten, die ein Beitrag bleibt",
		["A post leaves the board this many minutes after its sender last posted it."] =
			"Ein Beitrag verschwindet so viele Minuten, nachdem sein Absender ihn zuletzt gepostet hat.",
		["Notice"] = "Hinweis",
		["Tell me about new groups"] = "Über neue Gruppen informieren",
		["A chat line and a sound when a new group post passes the board's filters. Never in combat."] =
			"Eine Chatzeile und ein Sound, wenn ein neuer Gruppenbeitrag durch die Filter der Pinnwand kommt. Nie im Kampf.",
		["Chat line"] = "Chatzeile",
		["One line in your chat window with the sender, the place and the roles the group needs."] =
			"Eine Zeile in Eurem Chatfenster mit dem Absender, dem Ort und den Rollen, die die Gruppe braucht.",
		["Sound"] = "Sound",
		["The sound for a new group post. None plays nothing."] =
			"Der Sound für einen neuen Gruppenbeitrag. Bei „Nichts“ ist nichts zu hören.",

		-- The window
		["Groups"] = "Gruppen",
		["Groups looking for players (LFM)."] = "Gruppen, die Spieler suchen (LFM).",
		["Players"] = "Spieler",
		["Players looking for a group (LFG)."] = "Spieler, die eine Gruppe suchen (LFG).",
		["My level"] = "Meine Stufe",
		["Only places that fit your level: from three levels under the range to five over it."] =
			"Nur Orte, die zu Eurer Stufe passen: von drei Stufen unter dem Bereich bis fünf darüber.",
		["Tank"] = "Tank",
		["Groups that need a tank, players who tank. Posts that name no role stay."] =
			"Gruppen, die einen Tank brauchen, und Spieler, die tanken. Beiträge ohne Rolle bleiben sichtbar.",
		["Healer"] = "Heiler",
		["Groups that need a healer, players who heal. Posts that name no role stay."] =
			"Gruppen, die einen Heiler brauchen, und Spieler, die heilen. Beiträge ohne Rolle bleiben sichtbar.",
		["Damage"] = "Schaden",
		["Groups that need damage, players who deal damage. Posts that name no role stay."] =
			"Gruppen, die Schaden brauchen, und Spieler, die Schaden machen. Beiträge ohne Rolle bleiben sichtbar.",
		["Dungeons"] = "Dungeons",
		["Posts that name a dungeon."] = "Beiträge, die einen Dungeon nennen.",
		["Raids"] = "Schlachtzüge",
		["Posts that name a raid, or raid groups."] = "Beiträge, die einen Schlachtzug nennen, und Schlachtzuggruppen.",
		["Quests"] = "Quests",
		["Groups for quests, without a dungeon."] = "Gruppen für Quests, ohne Dungeon.",
		["Other"] = "Anderes",
		["Battlegrounds and group posts that name no place."] = "Schlachtfelder und Gruppenbeiträge, die keinen Ort nennen.",
		["Search"] = "Suchen",
		["Matches names, places and the text of the posts."] = "Durchsucht Namen, Orte und den Text der Beiträge.",
		["Whisper"] = "Flüstern",
		["Opens a whisper to this player in the chat box."] = "Öffnet ein Flüstern an diesen Spieler im Chatfeld.",
		["Invite"] = "Einladen",
		["Invites this player to your group."] = "Lädt diesen Spieler in Eure Gruppe ein.",
		["Hide"] = "Ausblenden",
		["Hides this post until its sender posts something else."] =
			"Blendet diesen Beitrag aus, bis sein Absender etwas anderes postet.",
		["Clear"] = "Leeren",
		["Removes every post from the board. New posts show up again as they come."] =
			"Entfernt alle Beiträge von der Pinnwand. Neue Beiträge erscheinen wieder, sobald sie kommen.",
		["Options"] = "Optionen",
		["Channels, how long posts stay, and the notice for new groups."] =
			"Kanäle, wie lange Beiträge bleiben, und der Hinweis auf neue Gruppen.",
		["%d of %d posts"] = "%d von %d Beiträgen",
		["Invite after combat."] = "Einladen nach dem Kampf.",
		["The game did not send the invite."] = "Das Spiel hat die Einladung nicht verschickt.",
		["Chat is held back"] = "Chat zurückgehalten",
		["The game holds chat back from addons right now, in boss fights or PvP matches for example. The board fills again afterwards."] =
			"Das Spiel hält den Chat gerade vor Addons zurück, etwa in Bosskämpfen oder PvP-Matches. Danach füllt sich die Pinnwand wieder.",
		["Nothing matches"] = "Nichts passt",
		["No post passes the filters. Turn off a chip or clear the search to see more."] =
			"Kein Beitrag kommt durch die Filter. Schaltet einen Filter ab oder leert die Suche, um mehr zu sehen.",
		["No group posts yet"] = "Noch keine Gruppenbeiträge",
		["Group posts from the channels you read show up here, newest first. Options picks the channels."] =
			"Gruppenbeiträge aus den gelesenen Kanälen erscheinen hier, die neuesten zuerst. Unter Optionen wählt Ihr die Kanäle.",

		-- Rows and tooltips
		["Looking for"] = "Sucht",
		["Place"] = "Ort",
		["Levels"] = "Stufen",
		["Channel"] = "Kanal",
		["Last posted"] = "Zuletzt gepostet",
		["Times posted"] = "Wie oft gepostet",
		["Click"] = "Klick",
		["whisper"] = "flüstern",
		["Right-click"] = "Rechtsklick",
		["hide this post"] = "diesen Beitrag ausblenden",
		["Group"] = "Gruppe",
		["Player"] = "Spieler",
		["Raid"] = "Schlachtzug",
		["PvP"] = "PvP",
		["+%d more"] = "+%d weitere",
		["%s or %s"] = "%s oder %s",
		["Group, needs %d: %s"] = "Gruppe, braucht %d: %s",
		["Group, needs %d"] = "Gruppe, braucht %d",
		["Group, needs %s"] = "Gruppe, braucht %s",
		["Player: %s"] = "Spieler: %s",
		["just now"] = "gerade eben",
		["%d min ago"] = "vor %d Min.",

		-- Chat, info bar block, Finder, command
		["Group board: %s for %s (%s)."] = "Gruppen-Pinnwand: %s für %s (%s).",
		["The group board is off. Turn it on on the Plugins page."] =
			"Die Gruppen-Pinnwand ist aus. Schaltet sie auf der Seite Plugins ein.",
		["LFG"] = "LFG",
		["Off"] = "Aus",
		["%d groups"] = { one = "%d Gruppe", other = "%d Gruppen" },
		["The game holds chat back from addons right now, in boss fights for example."] =
			"Das Spiel hält den Chat gerade vor Addons zurück, etwa in Bosskämpfen.",
		["No group posts that pass your filters yet."] = "Noch keine Gruppenbeiträge, die durch Eure Filter kommen.",
		["and %d more"] = { one = "und %d weiterer", other = "und %d weitere" },
		["open the group board"] = "Gruppen-Pinnwand öffnen",
		["Group posts from chat"] = "Gruppenbeiträge aus dem Chat",
		["open or close the group board"] = "Gruppen-Pinnwand öffnen oder schließen",
	}
end)
