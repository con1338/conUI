-- EldoUI key bindings (Bindings.xml at the addon root): an "EldoUI" section
-- in the game's Key Bindings window under AddOns. Each binding calls
-- EldoUI:RunBinding(name), so the actions live here in Lua and the XML only
-- names them.
--
--   METER_TOGGLE   show or hide Blizzard's damage meter (/eui meter toggle)
--   METER_RESET    clear the damage meter's fights (/eui meter reset)
--   LOOTGUIDE      open or close the Loot Guide when it is installed
--   LOOTGUIDE_BIS  open the Loot Guide on Best in Slot
--   ALTS           open or close the Characters (Alts) window
--   MAPNOTES_TOGGLE  show or hide every EldoUI map pin (Map Notes)
--   MINIMAP_OVERLAY  toggle the centered minimap overlay
--   WHISPER_TARGET   open the chat box to whisper your target (/eui tt)
--   ADVENTURE      open or close My Adventure in the Journal window
--   ADVENTURE_NOTE write a quick journal note (the quick note card)
--   ADVENTURE_TRACKER  show or hide the journal tracker
--   ADVENTURE_NEXT open My Adventure on Next trips
--   MOVEMODE       open or close move mode (/eui move); refused in combat
--   ELDOUI_SHOW_HUD  hold to show every faded EldoUI frame (Core/Visibility.lua,
--                  alpha only, so it works in combat)
--   FOCUS_QUEST_NEXT / FOCUS_QUEST_PREVIOUS  cycle the native quest focus
--   CLICK EldoUI_QuestItemButton   use the tracked quest's item
--   CLICK EldoUI_Quickdraw1..16    hold for a Quickdraw menu (the same
--                                  as the key set in the menu's editor)
--
-- Every action is something the player starts with a key press; none of
-- them plays the game for the player.
local _, E = ...
local L = E.L

local function Slash(text)
	local handler = SlashCmdList and SlashCmdList.ELDOUI
	if handler then handler(text) end
end

local function FocusQuest(direction)
	local tracker = E:GetModule("ObjectiveTracker")
	if tracker then tracker:CycleWatchedQuest(direction) end
end

local ACTIONS = {
	METER_TOGGLE = function() Slash("meter toggle") end,
	METER_RESET = function() Slash("meter reset") end,
	INFOBAR_TOGGLE = function() if E.ToggleInfoBar then E:ToggleInfoBar() end end,
	LOOTGUIDE = function()
		local guide = E:GetModule("LootGuide")
		if not guide then
			E:Print(L["The Loot Guide isn't installed."])
		else
			guide:BindingToggle()
		end
	end,
	LOOTGUIDE_BIS = function()
		local guide = E:GetModule("LootGuide")
		if not guide then
			E:Print(L["The Loot Guide isn't installed."])
		else
			guide:BindingBiS()
		end
	end,
	ALTS = function()
		local alts = E:GetModule("Characters")
		if alts then alts:Toggle() end
	end,
	MAPNOTES_TOGGLE = function()
		local notes = E:GetModule("MapNotes")
		if notes then notes:BindingToggle() end
	end,
	MOVEMODE = function() E:ToggleMoveMode() end,
	MINIMAP_OVERLAY = function()
		local minimap = E:GetModule("Minimap")
		if minimap then minimap:ToggleMinimapOverlay() end
	end,
	FOCUS_QUEST_NEXT = function() FocusQuest(1) end,
	FOCUS_QUEST_PREVIOUS = function() FocusQuest(-1) end,
	WHISPER_TARGET = function()
		local chat = E:GetModule("Chat")
		if chat and chat.WhisperTarget then chat:WhisperTarget() end
	end,
}

-- My Adventure: the actions live in Adventure/Entry.lua; each one
-- says why nothing opens while the journal can't run.
for name, method in pairs({ ADVENTURE = "BindingToggle", ADVENTURE_NOTE = "BindingNote",
	ADVENTURE_TRACKER = "BindingTracker", ADVENTURE_NEXT = "BindingNext" }) do
	ACTIONS[name] = function()
		local adventure = E.Adventure
		if not (adventure and adventure[method]) then
			E:Print(E:ModuleOffHint("Adventure"))
		else
			adventure[method](adventure)
		end
	end
end

function E:RunBinding(name)
	local action = ACTIONS[name]
	if action then action() end
end

-- Names shown in the Key Bindings window, in the language EldoUI shows:
-- set again at login, once the saved language is read.
function E:NameKeyBindings()
	self:NameModuleBindings()
	_G.BINDING_HEADER_ELDOUI = E.brand
	_G.BINDING_NAME_ELDOUI_METER_TOGGLE = L["Show or hide the damage meter"]
	_G.BINDING_NAME_ELDOUI_METER_RESET = L["Clear the damage meter"]
	_G.BINDING_NAME_ELDOUI_LOOTGUIDE = L["Open or close the Loot Guide"]
	_G.BINDING_NAME_ELDOUI_LOOTGUIDE_BIS = L["Open the Loot Guide on Best in Slot"]
	_G.BINDING_NAME_ELDOUI_ALTS = L["Open or close the Alts window"]
	_G.BINDING_NAME_ELDOUI_MAPNOTES_TOGGLE = L["Show or hide all map notes"]
	_G.BINDING_NAME_ELDOUI_MINIMAP_OVERLAY = L["Toggle minimap overlay"]
	_G.BINDING_NAME_ELDOUI_ADVENTURE = L["Open or close My Adventure"]
	_G.BINDING_NAME_ELDOUI_ADVENTURE_NOTE = L["Write a quick journal note"]
	_G.BINDING_NAME_ELDOUI_ADVENTURE_TRACKER = L["Show or hide the journal tracker"]
	_G.BINDING_NAME_ELDOUI_ADVENTURE_NEXT = L["Open Next trips"]
	_G.BINDING_NAME_ELDOUI_SHOW_HUD = L["Show the HUD (hold)"]
	_G.BINDING_NAME_ELDOUI_MOVEMODE = L["Open or close move mode"]
	_G.BINDING_NAME_ELDOUI_FOCUS_QUEST_NEXT = L["Focus next tracked quest"]
	_G.BINDING_NAME_ELDOUI_FOCUS_QUEST_PREVIOUS = L["Focus previous tracked quest"]
	_G["BINDING_NAME_CLICK EldoUI_QuestItemButton:LeftButton"] = L["Use the quest item (Objective Tracker)"]
	-- Consumable Bar buttons, in its category order.
	_G.BINDING_HEADER_ELDOUICONSUMABLES = L["EldoUI Consumable Bar"]
	for index, what in ipairs({ L["Food"], L["Drink"], L["Health potion"], L["Mana potion"], L["Bandage"], L["Healthstone"] }) do
		_G[("BINDING_NAME_CLICK EldoUI_ConsumableButton%d:LeftButton"):format(index)] = L["Use the best %s (Consumable Bar)"]:format(E:InSentence(what))
	end
	_G["BINDING_NAME_CLICK EldoUI_ConsumableButton7:LeftButton"] = L["Use the Hearthstone (Consumable Bar)"]
	_G["BINDING_NAME_CLICK EldoUI_ConsumableButton8:LeftButton"] = L["Mount up (Consumable Bar)"]
	_G["BINDING_NAME_CLICK EldoUI_ConsumableButton9:LeftButton"] = L["Use your mana gem (Consumable Bar)"]
	_G.BINDING_HEADER_ELDOUIQUICKDRAW = E.brand .. " Quickdraw"
	for index = 1, 16 do
		_G[("BINDING_NAME_CLICK EldoUI_Quickdraw%d:LeftButton"):format(index)] = L["Quickdraw menu %d (hold)"]:format(index)
	end
end
E:NameKeyBindings()
local bindingNames = {}
E:RegisterEvent("PLAYER_LOGIN", function() E:NameKeyBindings() end, bindingNames)
