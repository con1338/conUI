-- Rare Alerts: options, style presets, the tooltip line, the Info Bar data
-- text and the /eui rares command.
local _, E = ...
local L = E.L
local Key = E.Key
local M = E.RareScanner

local function Ago(seconds)
	if seconds < 60 then return L["just now"] end
	return L["%d min ago"]:format(math.floor(seconds / 60))
end

---------------------------------------------------------------------------
-- Tooltip section: "Rare" on rare units, "Seen this session", notable drops
---------------------------------------------------------------------------
local CLASS_LABEL = M.CLASS_LABEL

function M:UnitTooltipLines(unit)
	local lines = {}
	if not self.active or type(unit) ~= "string" or M.Secret(unit) then return lines end
	if M.IdentitySecret(unit) then return lines end
	local class = M.Read(UnitClassification, unit)
	if not CLASS_LABEL[class] then return lines end
	if M.Read(UnitPlayerControlled, unit) ~= false then return lines end
	lines[#lines + 1] = { L["Rare"], L[CLASS_LABEL[class]] }
	local npc = M.NpcFromGUID(M.Read(UnitGUID, unit))
	local key = M.KeyFor(npc, M.Read(UnitName, unit))
	local entry = key and self.session[key]
	if entry then lines[#lines + 1] = { L["Seen this session"], Ago(GetTime() - entry.t) } end
	local notable, items = self:Notable(npc)
	if notable then
		local names = {}
		for _, item in ipairs(items) do
			local name = C_Item and C_Item.GetItemNameByID and M.Read(C_Item.GetItemNameByID, item.itemID)
			names[#names + 1] = name or ("#" .. item.itemID)
		end
		lines[#lines + 1] = { L["Drops"], table.concat(names, ", ") }
	end
	return lines
end

if E.RegisterTooltipSection then
	E:RegisterTooltipSection("rareScanner", {
		order = 22, title = "Rare Alerts", default = "always",
		desc = "On a rare creature: its rank, whether you saw it this session and the mounts, pets, toys or set pieces it drops that you don't own yet.",
		unit = function(_, unit, add)
			for _, line in ipairs(M:UnitTooltipLines(unit)) do add(line[1], line[2]) end
		end,
	})
end

---------------------------------------------------------------------------
-- Info Bar data text "Rares"
---------------------------------------------------------------------------
function M:DataTextText()
	local last = self.sessionList[1]
	if last then return L["Rares: %s"]:format(last.name) end
	return L["Rares"]
end

function M:DataTextTooltip(tooltip)
	E.UIKit.TipTitle(tooltip, L["Rares this session"])
	local secondary = E.tokens.text.secondary
	if #self.sessionList == 0 then
		tooltip:AddLine(L["None yet. Rares you see show up here until you log out."], secondary[1], secondary[2], secondary[3], true)
		return
	end
	local now = GetTime()
	for i, entry in ipairs(self.sessionList) do
		if i > 15 then break end
		local right = (entry.zone or "") .. "  " .. Ago(now - entry.t)
		if entry.dead then right = right .. "  " .. L["Dead"] end
		tooltip:AddDoubleLine(entry.name, right, 1, 1, 1, secondary[1], secondary[2], secondary[3])
	end
end

function M:RefreshDataText()
	local infoBar = E.modules.InfoBar
	if infoBar and infoBar.active and infoBar.RefreshDataText then infoBar:RefreshDataText("Rares") end
end

if E.RegisterDataText then
	E:RegisterDataText("Rares", {
		title = "Rares",
		text = function() return M:DataTextText() end,
		tooltip = function(tooltip) M:DataTextTooltip(tooltip) end,
		hint = { Key("Click"), Key("this zone's rares in the Loot Guide") },
		onClick = function() M:OpenLootGuide(M.sessionList[1] and M.sessionList[1].npc) end,
	})
end

---------------------------------------------------------------------------
-- Command
---------------------------------------------------------------------------
E:AddCommand("rares", "[test]  Rare Alerts: open its settings, or show a test card", function(arg)
	arg = (arg or ""):lower()
	if arg == "test" then
		M:Test()
	else
		E:ToggleConfig("module:RareScanner")
	end
end, "Tools")

---------------------------------------------------------------------------
-- Style presets
---------------------------------------------------------------------------
E:RegisterStyles("RareScanner", {
	{ key = "Standard", title = "Standard", desc = "280 x 88 card with model, zone, time and notable drops.",
		settings = { width = 280, height = 88, model = true, showSource = true, showLoot = true, fontSize = 13, stackSize = 1, closeAfter = 60 } },
	{ key = "Compact", title = "Compact", desc = "Slim 240 x 56 card with a small model.",
		settings = { width = 240, height = 56, model = true, showSource = false, showLoot = false, fontSize = 12 } },
	{ key = "Minimal", title = "Minimal", desc = "Name and zone on a 240 x 40 strip, no model.",
		settings = { width = 240, height = 40, model = false, showSource = false, showLoot = false, fontSize = 12 } },
	{ key = "Showcase", title = "Showcase", desc = "Large 300 x 96 card with a bigger model and every detail.",
		settings = { width = 300, height = 96, model = true, showSource = true, showLoot = true, fontSize = 14 } },
	{ key = "Hunter", title = "Rare hunter", desc = "For camping a spawn: loud repeating sound, cards stay until closed, three at once (they grow down over the alert lane).",
		settings = { closeAfter = 0, stackSize = 3, soundRepeat = 3, notableRepeat = 5, flashTaskbar = true, repeatAfter = 300 } },
	{ key = "Quiet", title = "Quiet", desc = "Card only: no sound, no chat line, no taskbar flash.",
		settings = { sound = false, notableSound = false, chat = false, flashTaskbar = false } },
})

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local CHANNELS = { default = "Default", Master = "Master", SFX = "Effects", Dialog = "Dialog", Ambience = "Ambience" }
local MARKERS = { [1] = "Star", [2] = "Circle", [3] = "Diamond", [4] = "Triangle", [5] = "Moon", [6] = "Square", [7] = "Cross", [8] = "Skull" }

-- The notable sound rows need both switches: "Sound" first, then their own.
local function NotableParent() return M.db.sound and "notableSound" or "sound" end
local function TargetKeyOff() return not M.db.targetButton end

-- The session list block on the last tab.
local function CreateSessionList(frame)
	if not frame then return end
	frame.text = E:CreateText(frame, E.tokens.size.label, "LEFT")
	frame.text:SetPoint("TOPLEFT", 4, -4)
	frame.text:SetPoint("TOPRIGHT", -4, -4)
	frame.text:SetJustifyV("TOP")
	frame.text:SetWordWrap(true)
	local secondary = E.tokens.text.secondary
	frame.text:SetTextColor(secondary[1], secondary[2], secondary[3])
	frame:HookScript("OnShow", function(self) M:FillSessionList(self) end)
	M:FillSessionList(frame)
end

function M:FillSessionList(frame)
	if not (frame and frame.text) then return end
	if #self.sessionList == 0 then
		frame.text:SetText(L["No rares seen this session yet."])
		return
	end
	local now, lines = GetTime(), {}
	for i, entry in ipairs(self.sessionList) do
		if i > 12 then
			lines[#lines + 1] = L["and %d more"]:format(#self.sessionList - 12)
			break
		end
		lines[#lines + 1] = ("%s  -  %s, %s (%s)%s"):format(entry.name, entry.zone or "?", Ago(now - entry.t),
			L[M.SOURCE_LABEL[entry.source] or "Rare"], entry.dead and ("  " .. L["Dead"]) or "")
	end
	frame.text:SetText(table.concat(lines, "\n"))
end

M.options = {
	{ type = "description", label = "Finds rares, treasures and events from the minimap, nameplates, targets and yells. A rare's card targets it; a treasure's sets a waypoint." },

	{ type = "tab", label = "Finding" },
	{ type = "header", label = "Where rares are found" },
	{ type = "toggle", key = "sources.vignette", label = "Minimap skulls", desc = "Rares the game marks on the minimap. The most reliable source where the game shows them.",
		requiresAPI = "C_VignetteInfo.GetVignetteInfo" },
	{ type = "toggle", key = "sources.nameplate", label = "Nameplates", desc = "A rare's nameplate appears. Enemy nameplates must be on." },
	{ type = "toggle", key = "sources.target", label = "Your target and mouse-over", desc = "You target a rare or move the mouse over one." },
	{ type = "toggle", key = "sources.group", label = "Your group's targets", desc = "Someone in your party targets a rare." },
	{ type = "toggle", key = "sources.chat", label = "Monster yells", desc = "A rare you know of yells or emotes nearby." },
	{ type = "toggle", key = "worldBosses", label = "World bosses", desc = "Also alert for world bosses such as Azuregos." },
	{ type = "toggle", key = "treasures", label = "Treasures and chests", requiresAPI = "C_VignetteInfo.GetVignetteInfo",
		desc = "A card when the game marks a treasure or chest on the minimap. Click it to set a waypoint." },
	{ type = "toggle", key = "events", label = "Events", requiresAPI = "C_VignetteInfo.GetVignetteInfo",
		desc = "A card when the game marks an event on the minimap. Click it to set a waypoint." },
	{ type = "input", key = "watch", label = "Also watch for these names", desc = "Creature names, separated by commas. It alerts when one of them shows on a nameplate, as a target, under the mouse or yells. Use it for rares the data doesn't know." },
	{ type = "execute", label = "Clear ignored rares", desc = "Alert again for every rare you chose to ignore (card menu: Ignore this rare).",
		disabled = function() return M:IgnoredCount() == 0 and L["You ignore no rares."] or false end,
		func = function()
			E:ShowConfirm({ title = L["Clear ignored rares"], text = L["Alert again for all %d ignored rares?"]:format(M:IgnoredCount()),
				accept = L["Clear"], danger = true, onAccept = function() M:ClearIgnored() end })
		end },
	{ type = "toggle", key = "doneQuiet", label = "Keep rares you already did quiet",
		desc = "When the game says this character already killed or looted it (or did it today), no card and no sound; it is still listed under This session. Other cards show Already done." },
	{ type = "header", label = "When" },
	{ type = "toggle", key = "instances", label = "In dungeons and raids", desc = "Also alert inside instances. Most names are hidden there, so few rares show." },
	{ type = "toggle", key = "taxi", label = "On flight paths", desc = "Also alert while you are on a flight path." },
	{ type = "toggle", key = "dead", label = "Dead rares", desc = "Also alert for a rare that is already dead." },
	{ type = "range", key = "repeatAfter", label = "Alert again after", unit = "s", min = 60, max = 3600, step = 60, desc = "How long before the same rare alerts again." },

	{ type = "tab", label = "Quiet" },
	{ type = "header", label = "Quiet kinds and zones" },
	{ type = "description", label = "Quiet kinds and zones keep Rare Alerts calm where you don't hunt. A watched name is never quiet because of its kind." },
	{ type = "toggle", key = "quietKinds.rare", label = "Quiet: rares", desc = "Rares (not elite) are quiet everywhere." },
	{ type = "toggle", key = "quietKinds.rareelite", label = "Quiet: rare elites", desc = "Rare elites are quiet everywhere." },
	{ type = "toggle", key = "quietKinds.worldboss", label = "Quiet: world bosses", desc = "World bosses are quiet everywhere." },
	{ type = "toggle", key = "quietKinds.treasure", label = "Quiet: treasures and chests", desc = "Treasures and chests are quiet everywhere." },
	{ type = "toggle", key = "quietKinds.event", label = "Quiet: events", desc = "Events are quiet everywhere." },
	{ type = "select", key = "quietMode", label = "A quiet sighting shows", values = { card = "The card, no sound", nothing = "Nothing" }, order = { "card", "nothing" },
		desc = "The card, no sound: the card shows; no sound, flash, chat line or vibration. Nothing: no card either, and it is not listed under This session." },
	{ type = "header", label = "Quiet zones" },
	{ type = "execute", label = "Quiet this zone", desc = "Adds the zone you are in now to the quiet zones. The card menu offers it for the rare's zone too.",
		disabled = function()
			local _, uiMapID = M.PlayerZone()
			if not uiMapID then return L["The game names no zone here."] end
			return M:IsQuietZone(uiMapID) and L["This zone is already quiet."] or false
		end,
		func = function() M:SetQuietZone(nil, true) end },
	{ type = "description", label = function()
		local names = M:QuietZoneNames()
		if #names == 0 then return L["No quiet zones."] end
		return L["Quiet zones: %s"]:format(table.concat(names, ", "))
	end },
	{ type = "execute", label = "Clear quiet zones", desc = "Every zone alerts as usual again.",
		disabled = function() return #M:QuietZoneNames() == 0 and L["No quiet zones."] or false end,
		func = function() M:ClearQuietZones() end },

	{ type = "tab", label = "Card" },
	{ type = "header", label = "Card" },
	{ type = "toggle", key = "popup", label = "Show a card", desc = "A card left of the top center. Click it to target the rare; right-click or x closes it. In combat it waits until combat ends." },
	{ type = "range", key = "closeAfter", label = "Close after", unit = "s", min = 0, max = 300, step = 5, zeroText = "Never", dependsOn = "popup", desc = "At Never the card stays until you close it. It also stays while the mouse is over it." },
	{ type = "toggle", key = "closeDead", label = "Close when it dies", dependsOn = "popup", desc = "The card closes a few seconds after the rare dies." },
	{ type = "range", key = "stackSize", label = "Cards at once", min = 1, max = 4, step = 1, dependsOn = "popup", desc = "More rares wait in a queue. Above 1, cards grow down over the alert lane." },
	{ type = "toggle", key = "model", label = "3D model", dependsOn = "popup", desc = "Show the creature's model. Off shows the rare icon." },
	{ type = "toggle", key = "showSource", label = "Where it was seen", dependsOn = "popup", desc = "A small label: minimap, nameplate, target, group or yell." },
	{ type = "toggle", key = "showLoot", label = "Notable drops", dependsOn = "popup", desc = "Mount, pet and toy icons from the Loot Guide's data that you don't own yet." },
	{ type = "range", percent = true, key = "scale", label = "Scale", min = 0.6, max = 1.6, step = 0.05, dependsOn = "popup", desc = "Size of the card." },
	{ type = "range", key = "fontSize", label = "Text size", min = 10, max = 18, step = 1, dependsOn = "popup", desc = "Text size on the card." },
	{ type = "range", key = "width", label = "Width", min = 200, max = 320, step = 4, dependsOn = "popup", desc = "Width of the card. The style presets set it." },
	{ type = "range", key = "height", label = "Height", min = 40, max = 104, step = 4, dependsOn = "popup", desc = "Height of the card. Below 52 it shows only the name and zone." },
	{ type = "execute", label = "Test", testSafe = true, desc = "Show a sample card and play the sound with your settings.", func = function() M:Test() end },
	{ type = "execute", label = "Move", desc = "Unlock EldoUI frames to drag the card.", func = function() E:MoveFrame("EldoUI_RareAlert") end },
	{ type = "header", label = "Sharing" },
	{ type = "select", key = "shareTo", label = "Share to", order = { "group", "party", "raid", "say" },
		values = { group = "Your group", party = "Party", raid = "Raid", say = "Say" },
		desc = "Shift-click on a card or a Rare History line opens the chat box on this channel with the name and place; you press Enter to send it. Your group: the instance, raid or party you are in, Say when alone." },
	{ type = "toggle", key = "sharePin", label = "Map pin link (sets your map pin)",
		desc = "The shared line ends with the game's map pin link to the place. Sharing moves your own map pin there." },

	{ type = "tab", label = "Sound" },
	{ type = "header", label = "Sound and notice" },
	{ type = "toggle", key = "sound", label = "Sound", desc = "Play a sound when a rare shows up. If a Fanfare trigger for rares has a sound, that one plays instead, so you hear one sound per rare." },
	{ type = "media", mediaKind = "sound", key = "soundID", channel = "channel", label = "Sound file", dependsOn = "sound",
		desc = "EldoUI's sounds, the game's or a SharedMedia pack's." },
	{ type = "range", key = "soundRepeat", label = "Play it", min = 1, max = 5, step = 1, dependsOn = "sound", desc = "How many times the sound plays." },
	{ type = "toggle", key = "notableSound", label = "Other sound for mount, pet, toy and set rares", dependsOn = "sound", desc = "Rares that drop something you can still collect get their own sound." },
	{ type = "media", mediaKind = "sound", key = "notableID", channel = "channel", label = "Notable sound", dependsOn = NotableParent,
		desc = "The sound for a rare with a mount, pet, toy or set piece you don't own." },
	{ type = "range", key = "notableRepeat", label = "Play the notable sound", min = 1, max = 5, step = 1, dependsOn = NotableParent, desc = "How many times the notable sound plays." },
	{ type = "toggle", key = "treasureSound", label = "Sound for treasures and events", desc = "Play a sound once when a treasure, chest or event card shows." },
	{ type = "media", mediaKind = "sound", key = "treasureID", channel = "channel", label = "Treasure sound", dependsOn = "treasureSound",
		desc = "The sound for treasures, chests and events." },
	{ type = "select", key = "channel", label = "Sound channel", values = CHANNELS, order = { "default", "Master", "SFX", "Dialog", "Ambience" },
		desc = "Which volume slider controls these sounds. Default follows General > Sound channel." },
	{ type = "toggle", key = "flashTaskbar", label = "Flash the taskbar", desc = "Flash the game's taskbar icon when the game is in the background.", requires = function() return type(FlashClientIcon) == "function" end },
	{ type = "toggle", key = "vibrate", label = "Vibrate the gamepad", requiresAPI = "C_GamePad.SetVibration",
		desc = "A short pulse on your gamepad for each alert, a longer one for a rare with a mount, pet, toy or set piece you don't own. Only while you play with a gamepad; quiet sightings don't pulse." },
	{ type = "range", percent = true, key = "vibrateStrength", label = "Vibration strength", min = 0.1, max = 1, step = 0.05, dependsOn = "vibrate",
		requiresAPI = "C_GamePad.SetVibration", desc = "How strong the pulse is." },
	{ type = "toggle", key = "chat", label = "Chat line", desc = "A line with the place and a map link in your own chat frame. Nothing is sent to others. Off by default: the card and the sound already tell you." },

	{ type = "tab", label = "Acting for you" },
	{ type = "header", label = "Acting for you (off by default)" },
	{ type = "toggle", key = "markOnClick", label = "Mark when I click the card", desc = "Your click on the card also puts the raid marker below on the rare. Never automatic." },
	{ type = "select", key = "marker", label = "Marker", values = MARKERS, order = { 8, 7, 6, 5, 4, 3, 2, 1 }, dependsOn = "markOnClick", desc = "The raid marker your click puts on the rare." },
	{ type = "toggle", key = "targetButton", label = "Targeting key", desc = "Fills a button with this zone's rares. Press its key (Key Bindings > EldoUI Rare Alerts) while you look for one: each press tries to target one. Nothing presses it for you." },
	{ type = "execute", label = "Create a macro for your bars", hidden = TargetKeyOff,
		desc = "Adds the character macro EldoUI Rares that presses the targeting key, to put on an action bar. Your own macros are never changed.",
		func = function() M:CreateTargetMacro() end },

	{ type = "tab", label = "This session" },
	{ type = "header", label = "Rares seen this session" },
	{ type = "preview", height = 200, desc = "This session's sightings, newest first. Nothing is kept after you log out.",
		create = CreateSessionList, update = function(frame) M:FillSessionList(frame) end },
	{ type = "execute", label = "Clear", desc = "Forget this session's sightings. Nothing is kept after you log out anyway.",
		func = function() M:ClearSession() end },
	{ type = "header", label = "Rare History window" },
	{ type = "toggle", key = "historyWindow", label = "Show the window",
		desc = "A small list beside the rare cards with this session's sightings. Click a line to set a waypoint, Shift-click to share it, right-click to remove it." },
	{ type = "execute", label = "Move", desc = "Unlock EldoUI frames to drag the Rare History window.", hidden = function() return not M.db.historyWindow end,
		func = function() E:MoveFrame("EldoUI_RareHistory") end },
}
for _, row in ipairs(E:VisibilityOptions("historyVisibility", { db = function() return M.db end, label = "Window visibility", exempt = true,
	hidden = function() return not (M.db and M.db.historyWindow) end })) do
	table.insert(M.options, row)
end
