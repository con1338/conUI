-- EldoUI Click Casting: bind spells, macros and frame actions to mouse
-- clicks (with Shift, Ctrl and Alt) on party, raid and unit frames, and to
-- keys or the mouse wheel while hovering a frame, written from scratch on
-- Blizzard's secure templates.
--
-- How it works (all of it set up out of combat; in combat the game runs it):
--   * Mouse clicks: secure attributes on each frame, e.g.
--       shift-type1 = "spell", shift-spell1 = "Flash Heal"
--     SecureUnitButtonTemplate does the rest. Group headers also carry the
--     attributes (eldo-clickcast), so buttons made in combat get them too.
--   * Keys and the wheel on hover: a secure OnEnter wrapper (SecureHandler)
--     points override bindings at one hidden SecureActionButton and gives it
--     the hovered unit; OnLeave clears them. On each press the button takes
--     the unit again from the hovered frame, in case it changed meanwhile.
--   * The game's own Click Casting (C_ClickBindings, spellbook > Click
--     Casting) keeps working on EldoUI's frames; on the same click the
--     game's binding wins. The tooltip lists both.
-- Nothing is cast unless the player clicks or presses the key.
--
-- Bindings are saved per class (and optionally per talent group) inside the
-- profile, so one profile can serve several characters.
--
-- Frames: EldoUI's group frames register themselves (E:RegisterClickCastFrame
-- and E:RegisterClickCastHeader, also open to plugins); EldoUI's unit frames
-- are found by name; Blizzard's compact party and raid frames only when the
-- party/raid element's "Improve" switch is on (Blizzard UI page).
local _, E = ...
local L = E.L

local Key = E.Key
local M = E:NewModule("ClickCast", {
	title = "Click Casting",
	desc = "Bind spells and macros to clicks on party, raid and unit frames, and see every binding in the frame's tooltip.",
	conflicts = { "Clique", "ClickCastingTooltip", "VoidBox", "ForeverClick" },
	frames = { "EldoUI_ClickCastHandler", "EldoUI_ClickCastHover" },
	movers = {},
	blizzard = { "party-frames", "raid-frames" },
	savedKeys = { "profile.modules.ClickCast" },
	optionsPage = "module:ClickCast",
	presets = { "GroupOnly", "Healer", "MouseOnly", "Quiet", "TipsOnly" },
	reload = false,
	defaults = {
		bindingsEnabled = true,  -- EldoUI's own bindings on the frames
		sets = {},               -- [class or class-talentGroup] = { { key, mods, action, value }, ... }
		perTalentGroup = false,  -- separate bindings per talent group
		hoverKeys = true,        -- keyboard keys and the mouse wheel while hovering a frame
		bindUnitFrames = true,   -- also EldoUI's player, target, focus, pet frames
		bindBlizzard = true,     -- also Blizzard's compact frames (needs the Improve switch)
		-- Tooltip tips (v0.5.0 keys)
		party = true,            -- on party and raid frames
		unitFrames = false,      -- on EldoUI's unit frames
		heldOnly = false,
		showTargetMenu = false,
	},
})

-- "Reset to defaults" keeps the bindings: they are the player's data,
-- not a setting (E:ResetModuleSettings, Core/Config.lua).
M.keepOnReset = { "sets" }
M.keepOnResetNote = Key("Your click-cast bindings are kept too.")

---------------------------------------------------------------------------
-- Binding model
---------------------------------------------------------------------------
-- key:    "BUTTON1".."BUTTON5", "MOUSEWHEELUP", "MOUSEWHEELDOWN" or a key name
-- mods:   "" or a canonical prefix like "ALT-CTRL-SHIFT-" (the game's order)
-- action: "spell", "macro", "target", "menu", "focus" or "assist"
-- value:  spell name, macro name, or macro text starting with "/"
local ACTIONS = { "spell", "macro", "target", "menu", "focus", "assist" }
local ACTION_LABEL = E:TranslateValues({
	spell = E.Key("Spell"), macro = E.Key("Macro"), target = E.Key("Target"), menu = E.Key("Open menu"), focus = E.Key("Focus"), assist = E.Key("Assist"),
})
local ACTION_TYPE = { spell = "spell", macro = "macro", target = "target", menu = "togglemenu", focus = "focus", assist = "assist" }
local MOUSE_KEYS = { BUTTON1 = "1", BUTTON2 = "2", BUTTON3 = "3", BUTTON4 = "4", BUTTON5 = "5" }
local MOUSE_FROM_CLICK = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
local KEY_LABEL = E:TranslateValues({
	BUTTON1 = E.Key("Left click"), BUTTON2 = E.Key("Right click"), BUTTON3 = E.Key("Middle click"), BUTTON4 = E.Key("Button 4"), BUTTON5 = E.Key("Button 5"),
	MOUSEWHEELUP = E.Key("Wheel up"), MOUSEWHEELDOWN = E.Key("Wheel down"),
})
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }

local function IsMouseKey(key)
	return MOUSE_KEYS[key] ~= nil
end

local function CurrentMods()
	local mods = ""
	if IsAltKeyDown() then mods = mods .. "ALT-" end
	if IsControlKeyDown() then mods = mods .. "CTRL-" end
	if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
	return mods
end

local function ModsLabel(mods)
	if mods == "" then return nil end
	local parts = {}
	if mods:find("CTRL-", 1, true) then parts[#parts + 1] = E:GameText(CTRL_KEY, L["Ctrl"]) end
	if mods:find("ALT-", 1, true) then parts[#parts + 1] = E:GameText(ALT_KEY, L["Alt"]) end
	if mods:find("SHIFT-", 1, true) then parts[#parts + 1] = E:GameText(SHIFT_KEY, L["Shift"]) end
	return table.concat(parts, " + ")
end

local function KeyLabel(key)
	return KEY_LABEL[key] or (GetBindingText and GetBindingText(key)) or key
end

function M:BindingLabel(binding)
	local mods = ModsLabel(binding.mods or "")
	local key = KeyLabel(binding.key)
	return mods and (mods .. " + " .. key) or key
end

-- Name of the hover button's virtual mouse button for a key ("eldof").
local function VirtualButton(key)
	return "eldo" .. key:lower():gsub("[^%w]", function(char) return ("%02x"):format(char:byte()) end)
end

local function SetKey()
	local _, class = UnitClass("player")
	class = class or "ALL"
	if M.db.perTalentGroup and C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
		local ok, group = pcall(C_SpecializationInfo.GetActiveSpecGroup)
		if ok and group then return class .. "-" .. group end
	end
	return class
end

function M:GetBindings()
	local key = SetKey()
	local sets = self.db.sets
	if sets[key] == nil then
		-- A talent group seen for the first time starts as a copy of the
		-- class list, so turning on "per talent group" loses nothing.
		local class = key:match("^(.-)%-%d+$")
		sets[key] = class and type(sets[class]) == "table" and CopyTable(sets[class]) or {}
	end
	return sets[key], key
end

-- Copy another list (the class list "CLASS" or talent group "CLASS-2") over
-- the current one. Out of combat only.
function M:CopyBindingsFrom(source)
	if InCombatLockdown() then return false end
	local sets = self.db.sets
	local _, key = self:GetBindings()
	if source == key or type(sets[source]) ~= "table" then return false end
	sets[key] = CopyTable(sets[source])
	self:Changed()
	return true
end

-- The other lists of this class that bindings can be copied from, as
-- { [setKey] = label }.
function M:CopySources()
	local _, key = self:GetBindings()
	local class = key:match("^(.-)%-%d+$") or key
	local out = {}
	for setKey, list in pairs(self.db.sets) do
		if setKey ~= key and type(list) == "table" and #list > 0 then
			if setKey == class then
				out[setKey] = L["Class list (%d)"]:format(#list)
			else
				local group = setKey:sub(1, #class + 1) == class .. "-" and setKey:sub(#class + 2):match("^(%d+)$")
				if group then out[setKey] = L["Talent group %s (%d)"]:format(group, #list) end
			end
		end
	end
	return out
end

-- The attributes one binding sets: { name = value, ... } for a mouse
-- binding on unit frames, or for the hover button.
local function BindingAttributes(binding, out)
	local actionType = ACTION_TYPE[binding.action]
	if not actionType then return out end
	local prefix = (binding.mods or ""):lower()
	local suffix
	if IsMouseKey(binding.key) then
		suffix = MOUSE_KEYS[binding.key]
	else
		suffix = "-" .. VirtualButton(binding.key)
	end
	out[prefix .. "type" .. suffix] = actionType
	if binding.action == "spell" then
		out[prefix .. "spell" .. suffix] = binding.value
	elseif binding.action == "macro" then
		local value = binding.value or ""
		if value:sub(1, 1) == "/" then
			out[prefix .. "macrotext" .. suffix] = value
		else
			out[prefix .. "macro" .. suffix] = value
		end
	end
	return out
end

local function Valid(binding)
	if type(binding) ~= "table" or type(binding.key) ~= "string" or not ACTION_TYPE[binding.action] then return false end
	if (binding.action == "spell" or binding.action == "macro") and (type(binding.value) ~= "string" or binding.value == "") then return false end
	return true
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local frames = setmetatable({}, { __mode = "k" })   -- frame -> "group", "unit" or "blizzard"
local headers = setmetatable({}, { __mode = "k" })  -- secure group headers
local applied = setmetatable({}, { __mode = "k" })  -- frame -> { attribute names we set }
local wrapped = setmetatable({}, { __mode = "k" })  -- frames with the hover wrapper
local handler, hover

-- Plugins and EldoUI modules: make a secure unit button click-castable.
function E:RegisterClickCastFrame(frame, kind)
	if not frame or E.FrameCheck(frame, "IsForbidden") then return end
	frames[frame] = kind or "group"
	if M.active then
		E:RunOutOfCombat(function() M:ApplyFrame(frame) end)
	end
end

function E:UnregisterClickCastFrame(frame)
	if not frame then return end
	E:RunOutOfCombat(function()
		M:ClearFrame(frame)
		frames[frame] = nil
	end)
end

-- Secure group headers copy the attributes onto buttons they create later.
function E:RegisterClickCastHeader(header)
	if not header then return end
	headers[header] = true
	if M.active then
		E:RunOutOfCombat(function() M:ApplyHeader(header) end)
	end
end

local UNIT_FRAME_NAMES = {
	"EldoUI_PlayerFrame", "EldoUI_TargetFrame", "EldoUI_FocusFrame", "EldoUI_PetFrame", "EldoUI_TargettargetFrame",
}

local function ScanUnitFrames()
	for _, name in ipairs(UNIT_FRAME_NAMES) do
		local frame = _G[name]
		if frame and not frames[frame] then frames[frame] = "unit" end
	end
end

-- Blizzard's compact party and raid frames, by name. Nameplates are set up
-- by the same game code but are forbidden to addons, so a forbidden frame is
-- turned away before its name is read.
local function CompactElement(frame)
	if not frame or E.FrameCheck(frame, "IsForbidden") then return nil end
	local name = frame.GetName and frame:GetName()
	if type(name) ~= "string" or E.Secret(name) then return nil end
	if name:find("^CompactParty") then return "party-frames" end
	if name:find("^CompactRaid") then return "raid-frames" end
end

local function ScanBlizzardFrames()
	local function Add(frame)
		if frame and not E.FrameCheck(frame, "IsForbidden") and frame.GetAttribute then frames[frame] = "blizzard" end
	end
	for index = 1, 5 do
		Add(_G["CompactPartyFrameMember" .. index])
		Add(_G["CompactPartyFramePet" .. index])
	end
	for index = 1, 40 do Add(_G["CompactRaidFrame" .. index]) end
	for group = 1, 8 do
		for member = 1, 5 do Add(_G["CompactRaidGroup" .. group .. "Member" .. member]) end
	end
end

-- May EldoUI put bindings on this frame right now?
local function FrameWanted(frame, kind)
	if not M.active or not M.db.bindingsEnabled then return false end
	if kind == "unit" then return M.db.bindUnitFrames end
	if kind == "blizzard" then
		local element = CompactElement(frame)
		return M.db.bindBlizzard and element ~= nil and E:BlizzardAllowed(element, "improve")
	end
	return true
end

-- The attributes for mouse bindings, as { name = value }.
local function MouseAttributes()
	local out = {}
	if not M.db.bindingsEnabled then return out end
	for _, binding in ipairs(M:GetBindings()) do
		if Valid(binding) and IsMouseKey(binding.key) then BindingAttributes(binding, out) end
	end
	return out
end

-- Out of combat only. Also switches the hover keys off for the frame: the
-- secure wrapper stays (it can't be removed) but does nothing without
-- "eldo-hover".
function M:ClearFrame(frame)
	if wrapped[frame] then frame:SetAttribute("eldo-hover", nil) end
	local names = applied[frame]
	if not names then return end
	for _, name in ipairs(names) do frame:SetAttribute(name, nil) end
	applied[frame] = nil
end

function M:ApplyFrame(frame, attributes)
	if InCombatLockdown() then return end
	self:ClearFrame(frame)
	local kind = frames[frame]
	if not kind or not FrameWanted(frame, kind) then return end
	attributes = attributes or MouseAttributes()
	local names = {}
	for name, value in pairs(attributes) do
		frame:SetAttribute(name, value)
		names[#names + 1] = name
	end
	applied[frame] = names
	if kind ~= "blizzard" then
		self:WrapHover(frame)
		if wrapped[frame] then frame:SetAttribute("eldo-hover", true) end
	end
end

-- Serialized as name \002 value \001 for the header's restricted snippet.
function M:ApplyHeader(header, attributes)
	if InCombatLockdown() then return end
	if not self.active or not self.db.bindingsEnabled then
		header:SetAttribute("eldo-clickcast", nil)
		return
	end
	attributes = attributes or MouseAttributes()
	local parts = {}
	for name, value in pairs(attributes) do
		if not name:find("[\001\002]") and not tostring(value):find("[\001\002]") then
			parts[#parts + 1] = name .. "\002" .. tostring(value) .. "\001"
		end
	end
	header:SetAttribute("eldo-clickcast", #parts > 0 and table.concat(parts) or nil)
end

---------------------------------------------------------------------------
-- Keys and the mouse wheel on hover
---------------------------------------------------------------------------
-- In the restricted environment: `self` is the hovered unit frame, `owner`
-- the handler. The hidden hover button gets the unit and the bindings.
-- All three snippets run in the handler's environment, so `eldoHovered`
-- (the frame whose keys are bound) is shared between them.
local ON_ENTER = [[
	if not self:GetAttribute("eldo-hover") then return end
	local keys = owner:GetAttribute("eldo-hoverkeys")
	local hoverButton = owner:GetFrameRef("eldo-hover")
	if not keys or not hoverButton then return end
	local unit = self:GetAttribute("unit")
	if not unit then return end
	local suffix = self:GetAttribute("unitsuffix")
	if suffix then unit = unit .. suffix end
	hoverButton:SetAttribute("unit", unit)
	eldoHovered = self
	self:ClearBindings()
	for key, button in gmatch(keys, "([^\001\002]+)\002([^\001]+)\001") do
		self:SetBindingClick(true, key, hoverButton, button)
	end
]]
-- Only the frame that is left forgets itself: the mouse may enter the next
-- frame before the old one gets OnLeave.
local ON_LEAVE = [[
	if eldoHovered == self then eldoHovered = nil end
	self:ClearBindings()
]]
-- Before the hover button acts (`self` is the hover button): take the unit
-- again from the frame under the mouse. A group header can give that frame
-- another unit while the mouse rests on it (someone leaves the raid in
-- combat); the unit copied on enter would then be someone else. A frame
-- that has no unit any more gets nothing. Without a frame (a /click macro)
-- the button keeps the unit it has.
local ON_CLICK = [[
	local frame = eldoHovered
	if not frame then return end
	local unit = frame:GetAttribute("unit")
	if not unit then return false end
	local suffix = frame:GetAttribute("unitsuffix")
	if suffix then unit = unit .. suffix end
	self:SetAttribute("unit", unit)
]]

local function CreateHoverParts()
	if handler then return end
	handler = CreateFrame("Frame", "EldoUI_ClickCastHandler", UIParent, "SecureHandlerBaseTemplate")
	hover = CreateFrame("Button", "EldoUI_ClickCastHover", UIParent, "SecureActionButtonTemplate")
	hover:SetSize(1, 1)
	hover:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
	-- Down and up: a key binding acts on the press (useOnKeyDown), and
	-- whichever half the game treats as the click runs exactly once.
	hover:RegisterForClicks("AnyUp", "AnyDown")
	hover:SetAttribute("useOnKeyDown", true)
	SecureHandlerSetFrameRef(handler, "eldo-hover", hover)
	-- Should the wrapper fail, the unit copied on enter is used, as before.
	pcall(SecureHandlerWrapScript, hover, "OnClick", handler, ON_CLICK)
end

function M:WrapHover(frame)
	if wrapped[frame] or InCombatLockdown() then return end
	CreateHoverParts()
	local ok = pcall(SecureHandlerWrapScript, frame, "OnEnter", handler, ON_ENTER)
	if ok then
		pcall(SecureHandlerWrapScript, frame, "OnLeave", handler, ON_LEAVE)
		-- A frame hidden under the cursor (a player leaving the group, the
		-- group frames hiding) may never get OnLeave; its hover keys would
		-- stay bound and keep casting on the last unit.
		pcall(SecureHandlerWrapScript, frame, "OnHide", handler, ON_LEAVE)
		wrapped[frame] = true
	end
end

-- Attributes on the hover button and the key list for the snippet.
function M:ApplyHover()
	if InCombatLockdown() then return end
	CreateHoverParts()
	for _, name in ipairs(applied[hover] or {}) do hover:SetAttribute(name, nil) end
	applied[hover] = nil
	local keys, names = {}, {}
	if self.active and self.db.bindingsEnabled and self.db.hoverKeys then
		local attributes = {}
		for _, binding in ipairs(self:GetBindings()) do
			if Valid(binding) and not IsMouseKey(binding.key) then
				BindingAttributes(binding, attributes)
				keys[#keys + 1] = (binding.mods or "") .. binding.key .. "\002" .. VirtualButton(binding.key) .. "\001"
			end
		end
		for name, value in pairs(attributes) do
			hover:SetAttribute(name, value)
			names[#names + 1] = name
		end
	end
	applied[hover] = names
	handler:SetAttribute("eldo-hoverkeys", #keys > 0 and table.concat(keys) or nil)
end

---------------------------------------------------------------------------
-- Apply everything (out of combat)
---------------------------------------------------------------------------
function M:Apply()
	if InCombatLockdown() then
		E:RunOutOfCombat(function() self:Apply() end)
		return
	end
	ScanUnitFrames()
	ScanBlizzardFrames()
	local attributes = MouseAttributes()
	for frame in pairs(frames) do self:ApplyFrame(frame, attributes) end
	for header in pairs(headers) do self:ApplyHeader(header, attributes) end
	self:ApplyHover()
end

function M:ClearAll()
	for frame in pairs(frames) do self:ClearFrame(frame) end
	for header in pairs(headers) do header:SetAttribute("eldo-clickcast", nil) end
	if hover then
		for _, name in ipairs(applied[hover] or {}) do hover:SetAttribute(name, nil) end
		applied[hover] = nil
		handler:SetAttribute("eldo-hoverkeys", nil)
	end
end

-- Blizzard's compact frames are created and re-used by the game; pick up
-- new ones after setup (the switch is checked every time). In combat no
-- attribute can be set, so they wait in `setUpInCombat` for its end.
local setUpInCombat = setmetatable({}, { __mode = "k" })
local COMPACT_JOB = "ClickCast:compact"

-- Out of combat only: bindings for compact frames that have none yet or
-- were set up again in combat. One queued job covers any number of frames.
local function PickUpCompactFrames()
	if not M.active or not M.db.bindBlizzard then
		for frame in pairs(setUpInCombat) do setUpInCombat[frame] = nil end
		return
	end
	ScanBlizzardFrames()
	local attributes
	for frame, kind in pairs(frames) do
		if kind == "blizzard" and (not applied[frame] or setUpInCombat[frame]) then
			attributes = attributes or MouseAttributes()
			M:ApplyFrame(frame, attributes)
		end
	end
	for frame in pairs(setUpInCombat) do setUpInCombat[frame] = nil end
end

local function OnCompactSetup(frame)
	if not M.active or E.FrameCheck(frame, "IsForbidden") then return end
	if not CompactElement(frame) or not frame.GetAttribute then return end
	frames[frame] = "blizzard"
	if InCombatLockdown() then
		if M.db.bindBlizzard then
			setUpInCombat[frame] = true
			E:RunOutOfCombat(PickUpCompactFrames, COMPACT_JOB)
		end
		return
	end
	M:ApplyFrame(frame)
end

-- The element switches: Improve lets EldoUI add bindings and tooltip tips
-- to Blizzard's compact frames.
for _, element in ipairs({ "party-frames", "raid-frames" }) do
	E:RegisterBlizzardHandler(element, {
		owner = "ClickCast",
		apply = function() M:Apply() end,
		undo = function()
			for frame, kind in pairs(frames) do
				if kind == "blizzard" and CompactElement(frame) == element then M:ClearFrame(frame) end
			end
		end,
	})
end

---------------------------------------------------------------------------
-- Tour help: the healer role's click-casting, once per account, the first
-- time a party or raid frame with those clicks is on screen
---------------------------------------------------------------------------
-- The healer suggestions that are bound on this character now.
local function RoleClicks()
	if not (M.active and M.db.bindingsEnabled and E.GetRoleClickCast) or E:GetRole() ~= "healer" then return nil end
	local list = {}
	for _, item in ipairs(E:GetRoleClickCast()) do
		if item.bound then list[#list + 1] = item end
	end
	return #list > 0 and list or nil
end

-- A party or raid frame on screen that carries the clicks.
local function GroupFrame()
	for frame, kind in pairs(frames) do
		if kind ~= "unit" and applied[frame] and frame:IsVisible() then return frame end
	end
end

-- Plain left and right clicks still target and open the menu.
local function PlainClicksFree()
	for _, key in ipairs({ "BUTTON1", "BUTTON2" }) do
		local _, binding = M:FindBinding(key, "")
		if binding and binding.action ~= "target" and binding.action ~= "menu" then return false end
	end
	return true
end

E.Tour:Register("clickcast:role", {
	form = "spot", word = "clickcast",
	offer = function(_, force)
		local list = RoleClicks()
		if not list then return false end
		local lines = { L["These clicks on party and raid frames cast your spells now:"] }
		for _, item in ipairs(list) do lines[#lines + 1] = L["%s: %s"]:format(item.label or M:BindingLabel(item), item.spell) end
		local notes = {}
		if PlainClicksFree() then notes[#notes + 1] = L["Plain left and right clicks still target and open the menu."] end
		if M.db.party then notes[#notes + 1] = L["Hover a frame to see every click in its tooltip."] end
		notes[#notes + 1] = L["/eui clickcast changes or removes these clicks."]
		if #notes > 0 then lines[#lines + 1] = table.concat(notes, " ") end
		return E.Tour:Spot("clickcast:role", {
			force = force, target = GroupFrame() and GroupFrame or nil,
			title = L["Click-casting is on"],
			text = table.concat(lines, "\n"),
		})
	end,
	replay = function(def)
		if not M.active then
			E:Print(E:ModuleOffHint("ClickCast"))
		elseif not RoleClicks() then
			E:Print(L["This help shows once the healer role's click-casting is set up on this character."])
		else
			def.offer(def, true)
		end
	end,
})

-- Offered only while a group frame with the clicks is on screen; a
-- group, the setup's end or a reload brings the next chance.
function M:OfferRoleHelp()
	if E.Tour:Seen("clickcast:role") or not GroupFrame() or not RoleClicks() then return end
	E.Tour:Offer("clickcast:role")
end

hooksecurefunc(E, "BindRoleClickCast", function()
	C_Timer.After(1, function() M:OfferRoleHelp() end)
end)
if E.Installer and type(E.Installer.SetupDone) == "function" then
	hooksecurefunc(E.Installer, "SetupDone", function()
		C_Timer.After(2, function() M:OfferRoleHelp() end)
	end)
end

---------------------------------------------------------------------------
-- Editing bindings
---------------------------------------------------------------------------
function M:FindBinding(key, mods)
	for index, binding in ipairs(self:GetBindings()) do
		if binding.key == key and (binding.mods or "") == (mods or "") then return index, binding end
	end
end

-- Add or replace the binding for key + mods.
function M:SetBinding(key, mods, action, value)
	if InCombatLockdown() then return false, L["Bindings change after combat."] end
	if not key or not ACTION_TYPE[action] then return false, L["Pick a click or key and an action."] end
	value = value and strtrim(value) or nil
	if (action == "spell" or action == "macro") and (not value or value == "") then
		return false, action == "spell" and L["Type a spell name or drag a spell here."] or L["Type a macro name or /macro text."]
	end
	if action == "spell" and C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, value)
		if ok and info and info.name then value = info.name end
	end
	if not IsMouseKey(key) and not self.db.hoverKeys then
		self:Print(L["Key and wheel bindings work once \"Keys and wheel on hover\" is on."])
	end
	local bindings = self:GetBindings()
	local record = { key = key, mods = mods or "", action = action, value = (action == "spell" or action == "macro") and value or nil }
	local index = self:FindBinding(key, mods)
	if index then bindings[index] = record else bindings[#bindings + 1] = record end
	table.sort(bindings, function(a, b)
		if a.mods ~= b.mods then return (a.mods or "") < (b.mods or "") end
		return a.key < b.key
	end)
	self:Changed()
	return true
end

function M:RemoveBinding(index)
	if InCombatLockdown() then return false end
	table.remove(self:GetBindings(), index)
	self:Changed()
	return true
end

function M:Changed()
	self.cache = nil
	if self.active then self:Apply() end
	if self.window and self.window:IsShown() then self:RefreshWindow() end
end

-- The class list (group = false) or another talent group's list (true)
-- that holds bindings, or nil.
function M:OtherSet(group)
	if not self.db then return nil end
	for setKey in pairs(self:CopySources()) do
		if (setKey:find("-%d+$") ~= nil) == group then return setKey end
	end
end

function M:ConfirmCopy(source)
	local list = source and self:CopySources()[source] and self.db.sets[source]
	if not list then return end
	local work = function() self:CopyBindingsFrom(source) end
	local group = source:match("%-(%d+)$")
	local text = group and L["Replace this talent group's click-cast bindings with the talent group %s (%d)?"]:format(group, #list)
		or L["Replace this talent group's click-cast bindings with the class list (%d)?"]:format(#list)
	E:ConfigConfirm(text, work, { title = L["Copy bindings"], accept = L["Replace"] })
end

---------------------------------------------------------------------------
-- Tooltip tips: the game's Click Casting and EldoUI's bindings
---------------------------------------------------------------------------
local BUTTONS = E:TranslateValues({
	LeftButton = E.Key("Left"), RightButton = E.Key("Right"), MiddleButton = E.Key("Middle"),
	Button4 = E.Key("Button 4"), Button5 = E.Key("Button 5"),
})
local BUTTON_ORDER = { LeftButton = 1, RightButton = 2, MiddleButton = 3, Button4 = 4, Button5 = 5 }
local BLIZZ_BUTTON = { BUTTON1 = "LeftButton", BUTTON2 = "RightButton", BUTTON3 = "MiddleButton", BUTTON4 = "Button4", BUTTON5 = "Button5" }

-- Modifier bits as the click binding profile stores them.
local SHIFT, CTRL, ALT = 3, 12, 48

local function ModifierName(mask)
	mask = mask or 0
	local parts = {}
	if bit.band(mask, CTRL) ~= 0 then table.insert(parts, E:GameText(CTRL_KEY, L["Ctrl"])) end
	if bit.band(mask, ALT) ~= 0 then table.insert(parts, E:GameText(ALT_KEY, L["Alt"])) end
	if bit.band(mask, SHIFT) ~= 0 then table.insert(parts, E:GameText(SHIFT_KEY, L["Shift"])) end
	return #parts > 0 and table.concat(parts, " + ") or nil
end

local function HeldMask()
	local mask = 0
	if IsShiftKeyDown() then mask = mask + SHIFT end
	if IsControlKeyDown() then mask = mask + CTRL end
	if IsAltKeyDown() then mask = mask + ALT end
	return mask
end

-- Collapse left/right modifier bits into one value per key.
local function Normalize(mask)
	mask = mask or 0
	local out = 0
	if bit.band(mask, SHIFT) ~= 0 then out = out + SHIFT end
	if bit.band(mask, CTRL) ~= 0 then out = out + CTRL end
	if bit.band(mask, ALT) ~= 0 then out = out + ALT end
	return out
end

local function MaskFromMods(mods)
	local mask = 0
	if mods:find("SHIFT-", 1, true) then mask = mask + SHIFT end
	if mods:find("CTRL-", 1, true) then mask = mask + CTRL end
	if mods:find("ALT-", 1, true) then mask = mask + ALT end
	return mask
end

local function SpellNameIcon(spell)
	if not (C_Spell and C_Spell.GetSpellInfo) then return spell end
	local ok, info = pcall(C_Spell.GetSpellInfo, spell)
	if ok and info then return info.name, info.iconID end
	return spell
end

local function BlizzardActionName(info)
	local kind = info.type
	local types = Enum.ClickBindingType or {}
	if kind == types.Spell or kind == 1 then
		return SpellNameIcon(info.actionID)
	elseif kind == types.Macro or kind == 2 then
		local name, icon = GetMacroInfo(info.actionID)
		return name and L["%s %s"]:format(name, E:TextHex("secondary") .. L["(macro)"] .. "|r"), icon
	elseif kind == types.Interaction or kind == 3 then
		if info.actionID == 1 then return E:GameText(TARGET, L["Target"]) end
		if M.db.showTargetMenu then return ACTION_LABEL.menu end
		return nil
	elseif kind == types.PetAction or kind == 4 then
		local name, icon = GetPetActionInfo(info.actionID)
		return name and _G[name] or name, icon
	end
end

local function EldoActionName(binding)
	if binding.action == "spell" then return SpellNameIcon(binding.value) end
	if binding.action == "macro" then
		if (binding.value or ""):sub(1, 1) == "/" then return L["Macro %s"]:format(E:TextHex("secondary") .. L["(text)"] .. "|r") end
		local index = GetMacroIndexByName and GetMacroIndexByName(binding.value)
		local _, icon = nil, nil
		if index and index > 0 then _, icon = GetMacroInfo(index) end
		return L["%s %s"]:format(binding.value, E:TextHex("secondary") .. L["(macro)"] .. "|r"), icon
	end
	if binding.action == "menu" and not M.db.showTargetMenu then return nil end
	return ACTION_LABEL[binding.action]
end

-- Bindings grouped by modifier, cached until they change.
function M:TooltipGroups()
	if self.cache then return self.cache end
	local cache = {}
	local groups = {}
	local function Add(mask, order, label, name, icon)
		groups[mask] = groups[mask] or { mask = mask, rows = {} }
		table.insert(groups[mask].rows, { order = order, label = label, name = name, icon = icon })
	end
	if C_ClickBindings and C_ClickBindings.GetProfileInfo then
		local ok, profile = pcall(C_ClickBindings.GetProfileInfo)
		if ok and type(profile) == "table" then
			for _, info in ipairs(profile) do
				local name, icon = BlizzardActionName(info)
				if name and BUTTONS[info.button] then
					Add(Normalize(info.modifiers), BUTTON_ORDER[info.button] or 9, BUTTONS[info.button], name, icon)
				end
			end
		end
	end
	if self.db.bindingsEnabled then
		for _, binding in ipairs(self:GetBindings()) do
			if Valid(binding) and (IsMouseKey(binding.key) or self.db.hoverKeys) then
				local name, icon = EldoActionName(binding)
				if name then
					local blizz = BLIZZ_BUTTON[binding.key]
					local label = blizz and BUTTONS[blizz] or KeyLabel(binding.key)
					Add(MaskFromMods(binding.mods or ""), blizz and BUTTON_ORDER[blizz] or 10, label, name, icon)
				end
			end
		end
	end
	for _, group in pairs(groups) do
		table.sort(group.rows, function(a, b)
			if a.order ~= b.order then return a.order < b.order end
			return a.label < b.label
		end)
		table.insert(cache, group)
	end
	table.sort(cache, function(a, b) return a.mask < b.mask end)
	self.cache = cache
	return cache
end

-- Is the tooltip's owner a frame we want tips on?
local function WantedOwner(owner)
	if not owner or E.FrameCheck(owner, "IsForbidden") then return false end
	local kind = frames[owner]
	local element = CompactElement(owner)
	if element then return M.db.party and E:BlizzardAllowed(element, "improve") end
	if kind == "group" then return M.db.party end
	if kind == "unit" then return M.db.unitFrames end
	return false
end

-- The bindings as rows of the shared info area: a header per modifier,
-- then one row per button.
local function AddLines(add)
	local groups = M:TooltipGroups()
	if #groups == 0 then return end
	local held = M.db.heldOnly and HeldMask()
	local r, g, b = unpack(E.media.accentColor)
	local grey = E.tokens.text.secondary
	for _, group in ipairs(groups) do
		if not held or group.mask == held then
			add(ModifierName(group.mask) or L["Click"], nil, r, g, b)
			for _, row in ipairs(group.rows) do
				local icon = row.icon and ("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(row.icon) or ""
				add("   " .. row.label, icon .. row.name, grey[1], grey[2], grey[3])
			end
		end
	end
end
M.TooltipRows = AddLines

-- A unit section of the shared info area (Modules/Tooltip.lua): it shows
-- with the Tooltip module on or off, like every other extra line.
local function HookTooltips()
	if M.tooltipHooked then return end
	M.tooltipHooked = true
	E:RegisterTooltipSection("clickCast", { order = 45, title = "Click casting", default = "always",
		desc = "On your unit and group frames: what each mouse button casts with the modifier you hold (Click Casting module).",
		unit = function(tooltip, _, add)
			if not M.active or tooltip ~= GameTooltip then return end
			local ok, owner = pcall(tooltip.GetOwner, tooltip)
			if ok and WantedOwner(owner) then AddLines(add) end
		end })
end

---------------------------------------------------------------------------
-- Binding window (out of combat editing)
---------------------------------------------------------------------------
local WINDOW_W, WINDOW_H = 460, 480
local ROW_H = 22

-- The shared kit's button (E.UIKit.Button).
local function CreateButton(parent, text, width, onClick)
	return E.UIKit.Button(parent, text, { width = width, onClick = onClick })
end

local function SpellFromCursor()
	local cursorType, info1, _, info3 = GetCursorInfo()
	if cursorType == "spell" then
		local spellID = info3 or info1
		local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
		ClearCursor()
		return "spell", name
	elseif cursorType == "macro" then
		local name = GetMacroInfo(info1)
		ClearCursor()
		return "macro", name
	end
end

function M:CreateWindow()
	-- The shared tool window shell (E.UIKit.CreateToolWindow).
	local window = E.UIKit.CreateToolWindow("EldoUI_ClickCastWindow", { title = L["Click Casting"], width = WINDOW_W,
		height = WINDOW_H, strata = "DIALOG" })
	window.subtitle = E.UIKit.Text(window, E.tokens.size.small, "LEFT", "secondary")
	window.subtitle:SetPoint("TOPLEFT", 12, -36)
	window.subtitle:SetPoint("TOPRIGHT", -12, -36)
	window.subtitle:SetWordWrap(false)

	-- Binding list
	local list = CreateFrame("ScrollFrame", nil, window)
	list:SetPoint("TOPLEFT", 12, -56)
	list:SetPoint("TOPRIGHT", -12, -56)
	list:SetHeight(ROW_H * 12)
	list:EnableMouseWheel(true)
	local content = CreateFrame("Frame", nil, list)
	content:SetSize(WINDOW_W - 24, ROW_H)
	list:SetScrollChild(content)
	list:SetScript("OnMouseWheel", function(frame, delta)
		local max = math.max(0, content:GetHeight() - frame:GetHeight())
		frame:SetVerticalScroll(math.min(max, math.max(0, frame:GetVerticalScroll() - delta * ROW_H * 2)))
	end)
	window.list, window.content, window.rows = list, content, {}
	local inset = CreateFrame("Frame", nil, window)
	inset:SetPoint("TOPLEFT", list, -2, 2)
	inset:SetPoint("BOTTOMRIGHT", list, 2, -2)
	inset:SetFrameLevel(math.max(window:GetFrameLevel(), 1))
	E:SetTemplate(inset, true)
	window.empty = E.UIKit.Text(content, E.tokens.size.label, "LEFT", "secondary")
	window.empty:SetPoint("TOPLEFT", 6, -6)
	window.empty:SetWidth(WINDOW_W - 40)
	window.empty:SetWordWrap(true)
	window.empty:SetText(L["No bindings yet. Click the box below with the mouse button you want (hold Shift, Ctrl or Alt for a modifier), pick an action and press Add."])

	-- New binding
	local header = E.UIKit.Text(window, E.tokens.size.body, "LEFT", "header")
	header:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -14)
	header:SetText(L["New binding"])
	window.newHeader = header

	local capture = E.UIKit.Button(window, { text = "", width = WINDOW_W - 24, large = true })
	capture:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	capture:RegisterForClicks("AnyUp")
	capture:EnableMouseWheel(true)
	window.capture = capture
	local function SetCaptured(key, mods)
		window.pendingKey, window.pendingMods = key, mods
		self:UpdateNewBinding()
	end
	capture:SetScript("OnClick", function(_, button)
		local key = MOUSE_FROM_CLICK[button]
		if key then SetCaptured(key, CurrentMods()) end
	end)
	capture:SetScript("OnMouseWheel", function(_, delta)
		SetCaptured(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN", CurrentMods())
	end)
	-- Keys are read only while the mouse is over the box.
	capture:HookScript("OnEnter", function(button)
		if not InCombatLockdown() then button:EnableKeyboard(true) end
	end)
	capture:HookScript("OnLeave", function(button)
		if not InCombatLockdown() then button:EnableKeyboard(false) end
	end)
	capture:SetScript("OnKeyDown", function(button, key)
		if key == "ESCAPE" or MODIFIER_KEYS[key] then
			if not InCombatLockdown() then button:SetPropagateKeyboardInput(true) end
			return
		end
		if not InCombatLockdown() then button:SetPropagateKeyboardInput(false) end
		SetCaptured(key, CurrentMods())
	end)
	capture:SetScript("OnReceiveDrag", function()
		local kind, name = SpellFromCursor()
		if name then
			window.action = kind
			window.value:SetText(name)
			self:UpdateNewBinding()
		end
	end)

	local action = CreateButton(window, "", 140, function(_, mouse)
		local current = 1
		for index, key in ipairs(ACTIONS) do
			if key == window.action then current = index end
		end
		local step = mouse == "RightButton" and -1 or 1
		window.action = ACTIONS[(current - 1 + step) % #ACTIONS + 1]
		self:UpdateNewBinding()
	end)
	action:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	action:SetPoint("TOPLEFT", capture, "BOTTOMLEFT", 0, -8)
	window.actionButton = action

	local value = E.UIKit.Input(window, { width = WINDOW_W - 24 - 140 - 14 })
	value:SetPoint("LEFT", action, "RIGHT", 12, 0)
	value:SetScript("OnEnterPressed", function(box) box:ClearFocus(); self:AddPending() end)
	value:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
	value:SetScript("OnReceiveDrag", function(box)
		local kind, name = SpellFromCursor()
		if name then
			window.action = kind
			box:SetText(name)
			self:UpdateNewBinding()
		end
	end)
	value:HookScript("OnMouseDown", function(box)
		if GetCursorInfo() then
			local kind, name = SpellFromCursor()
			if name then
				window.action = kind
				box:SetText(name)
				self:UpdateNewBinding()
			end
		end
	end)
	window.value = value

	local add = CreateButton(window, E:GameText(ADD, L["Add"]), 90, function() self:AddPending() end)
	add:SetPoint("TOPLEFT", action, "BOTTOMLEFT", 0, -10)
	window.add = add

	window.status = E.UIKit.Text(window, E.tokens.size.small, "LEFT")
	window.status:SetPoint("LEFT", add, "RIGHT", 10, 0)
	window.status:SetPoint("RIGHT", window, "RIGHT", -12, 0)
	window.status:SetWordWrap(true)

	local help = E.UIKit.Text(window, E.tokens.size.small, "LEFT", "secondary")
	help:SetPoint("TOPLEFT", add, "BOTTOMLEFT", 0, -10)
	help:SetWidth(WINDOW_W - 24) -- as wide as the key button above
	help:SetWordWrap(true)
	help:SetText(L["Drag a spell or macro onto the text box, or type a spell name. Macro text starts with /, for example /cast [@mouseover] Renew. Right-click the action button to go back. The game's own Click Casting wins on the same click."])
	window.help = help

	local blizzard = CreateButton(window, L["Game's Click Casting"], 160, function()
		if ToggleClickBindingFrame then ToggleClickBindingFrame() end
	end)
	blizzard:SetPoint("BOTTOMRIGHT", -12, 12)

	window:HookScript("OnShow", function() self:RefreshWindow() end)
	window:RegisterEvent("PLAYER_REGEN_DISABLED")
	window:RegisterEvent("PLAYER_REGEN_ENABLED")
	window:SetScript("OnEvent", function() self:UpdateNewBinding() end)
	window.action = "spell"
	window:Hide()
	self.window = window
	return window
end

function M:UpdateNewBinding()
	local window = self.window
	if not window then return end
	if window.pendingKey then
		local label = self:BindingLabel({ key = window.pendingKey, mods = window.pendingMods or "" })
		window.capture:SetText(label .. "  " .. E:TokenHex(E.tokens.text.dim) .. L["(click or press again to change)"] .. "|r")
	else
		window.capture:SetText(L["Click here with a mouse button, or hover and press a key"])
	end
	window.actionButton:SetText(L["Action: %s"]:format(ACTION_LABEL[window.action or "spell"]))
	local needsValue = window.action == "spell" or window.action == "macro"
	window.value:SetShown(needsValue)
	local combat = InCombatLockdown()
	window.add:SetEnabled(not combat)
	if combat then
		window.status:SetTextColor(E:TokenColor("bad"))
		window.status:SetText(L["Bindings change after combat."])
	end
end

function M:AddPending()
	local window = self.window
	if not window then return end
	local ok, message = self:SetBinding(window.pendingKey, window.pendingMods, window.action, window.value:GetText())
	if ok then
		window.status:SetTextColor(E:TokenColor("good"))
		window.status:SetText(L["Added."])
		window.pendingKey, window.pendingMods = nil, nil
		window.value:SetText("")
		self:UpdateNewBinding()
	else
		window.status:SetTextColor(E:TokenColor("bad"))
		window.status:SetText(message or "")
	end
end

local function CreateRow(window, index)
	local row = CreateFrame("Frame", nil, window.content)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
	row:SetPoint("TOPRIGHT", window.content, "TOPRIGHT", 0, -(index - 1) * ROW_H)
	E:SkinRow(row)
	row.key = E:CreateText(row, E.tokens.size.label, "LEFT")
	row.key:SetPoint("LEFT", 6, 0)
	row.key:SetWidth(150)
	row.key:SetTextColor(unpack(E.media.text.secondary))
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", 160, 0)
	E:TrimIcon(row.icon)
	row.action = E:CreateText(row, E.tokens.size.label, "LEFT")
	row.action:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.action:SetPoint("RIGHT", -70, 0)
	row.remove = CreateButton(row, L["Remove"], 62, function()
		if row.index then M:RemoveBinding(row.index) end
	end)
	row.remove:SetHeight(18)
	row.remove:SetPoint("RIGHT", -2, 0)
	return row
end

function M:RefreshWindow()
	local window = self.window
	if not window then return end
	-- The accent may have changed since the window was built.
	window.newHeader:SetTextColor(E:TokenColor("accent"))
	local bindings, key = self:GetBindings()
	local className = UnitClass("player") or key
	local subtitle = self.db.perTalentGroup and L["Bindings for %s, talent group %s"]:format(className, key:match("%-(%d+)$") or "1")
		or L["Bindings for %s"]:format(className)
	if not self.db.bindingsEnabled then subtitle = subtitle .. "  " .. E:TokenHex(E.tokens.text.bad) .. L["(bindings switched off in the options)"] .. "|r" end
	window.subtitle:SetText(subtitle)
	for index, binding in ipairs(bindings) do
		local row = window.rows[index] or CreateRow(window, index)
		window.rows[index] = row
		row.index = index
		row.key:SetText(self:BindingLabel(binding))
		local name, icon = EldoActionName(binding)
		if binding.action == "menu" then name = ACTION_LABEL.menu end
		if binding.action == "macro" and (binding.value or ""):sub(1, 1) == "/" then name = binding.value end
		if not IsMouseKey(binding.key) and not self.db.hoverKeys then
			name = (name or "") .. "  " .. E:TokenHex(E.tokens.text.bad) .. L["(keys on hover are off)"] .. "|r"
		end
		row.action:SetText(name or ACTION_LABEL[binding.action] or "?")
		row.icon:SetTexture(icon)
		row.icon:SetShown(icon ~= nil)
		row:Show()
	end
	for index = #bindings + 1, #window.rows do window.rows[index]:Hide() end
	window.content:SetHeight(math.max(ROW_H, #bindings * ROW_H))
	window.empty:SetShown(#bindings == 0)
	self:UpdateNewBinding()
end

function M:ToggleWindow()
	local window = self.window or self:CreateWindow()
	window:SetShown(not window:IsShown())
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnEnable()
	HookTooltips()
	if not self.compactHooked and CompactUnitFrame_SetUpFrame then
		self.compactHooked = true
		hooksecurefunc("CompactUnitFrame_SetUpFrame", OnCompactSetup)
	end
	local function Reset() self.cache = nil end
	self:RegisterEvent("CLICKBINDINGS_SET_HIGHLIGHTS_SHOWN", Reset)
	self:RegisterEvent("SPELLS_CHANGED", Reset)
	self:RegisterEvent("UPDATE_MACROS", Reset)
	self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", function()
		self.cache = nil
		if self.db.perTalentGroup then
			E:RunOutOfCombat(function() self:Apply() end)
			if self.window and self.window:IsShown() then self:RefreshWindow() end
		end
	end)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function()
		-- New Blizzard compact frames; EldoUI's buttons register themselves.
		-- In combat once it ends.
		if self.db.bindBlizzard then E:RunOutOfCombat(PickUpCompactFrames, COMPACT_JOB) end
		-- The group frames show a moment later.
		if not E.Tour:Seen("clickcast:role") then C_Timer.After(2, function() M:OfferRoleHelp() end) end
	end)
	-- The game's binding window saves on close; read the profile fresh
	-- afterwards (the event covers it when the hook is not allowed).
	E:OnBlizzardAddOn("Blizzard_ClickBindingUI", function()
		-- Blizzard's click-binding window belongs to the "macros-click-binding"
		-- element; only hook it while that element's Improve switch allows.
		if ClickBindingFrame and not self.frameHooked and E:BlizzardAllowed("macros-click-binding", "improve") then
			self.frameHooked = true
			ClickBindingFrame:HookScript("OnHide", function() self.cache = nil end)
		end
	end)
	self:RegisterEvent("MODIFIER_STATE_CHANGED", function()
		if not self.db.heldOnly or not GameTooltip:IsShown() then return end
		-- Rebuild the tooltip from its own data; never call a (secure,
		-- wrapped) frame script from here.
		local ok, owner = pcall(GameTooltip.GetOwner, GameTooltip)
		if ok and WantedOwner(owner) and GameTooltip.RefreshData then
			pcall(GameTooltip.RefreshData, GameTooltip)
		end
	end)
	E:RunOutOfCombat(function() self:Apply() end)
end

function M:OnDisable()
	for _, event in ipairs({ "CLICKBINDINGS_SET_HIGHLIGHTS_SHOWN", "SPELLS_CHANGED", "UPDATE_MACROS",
		"ACTIVE_TALENT_GROUP_CHANGED", "GROUP_ROSTER_UPDATE", "MODIFIER_STATE_CHANGED" }) do
		self:UnregisterEvent(event)
	end
	if self.window then self.window:Hide() end
	E:RunOutOfCombat(function() self:ClearAll() end)
end

function M:OnProfileChanged()
	self.cache = nil
	if not self.active then return end
	E:RunOutOfCombat(function() self:Apply() end)
	if self.window and self.window:IsShown() then self:RefreshWindow() end
end

E:AddCommand("clickcast", "open the click-casting bindings window", function()
	if not M.active then
		E:Print(E:ModuleOffHint("ClickCast"))
		return
	end
	M:ToggleWindow()
end, "Layout & frames")

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
M.options = {
	{ type = "tab", label = "Bindings" },
	{ type = "description", label = "Bind spells and macros to clicks, modifier clicks, keys or the mouse wheel on party, raid and unit frames. Saved per class." },
	{ type = "execute", label = "Edit bindings", desc = "Opens the binding window. Also /eui clickcast.",
		disabled = function() if not M.active then return E:ModuleOffNote("ClickCast") end end,
		func = function() if M.active then M:ToggleWindow() end end },
	{ type = "toggle", key = "bindingsEnabled", label = "Use EldoUI's bindings", desc = "Off: frames keep only the game's own Click Casting and the default target and menu clicks." },
	{ type = "toggle", key = "hoverKeys", label = "Keys and wheel on hover", desc = "Key and mouse wheel bindings work while the mouse is over an EldoUI frame." },
	{ type = "toggle", key = "perTalentGroup", label = "Separate bindings per talent group",
		desc = "Each talent group (dual spec) keeps its own list. A talent group starts as a copy of your class list; the class list itself stays saved and comes back when this is off." },
	{ type = "execute", label = "Copy the class list", desc = "Replaces this talent group's bindings with a copy of the class list (the one used while \"per talent group\" is off).",
		hidden = function() return not M.db.perTalentGroup or not M:OtherSet(false) end,
		func = function() M:ConfirmCopy(M:OtherSet(false)) end },
	{ type = "execute", label = "Copy the other talent group", desc = "Replaces this talent group's bindings with a copy of your other talent group's bindings.",
		hidden = function() return not M.db.perTalentGroup or not M:OtherSet(true) end,
		func = function() M:ConfirmCopy(M:OtherSet(true)) end },
	{ type = "header", label = "Frames" },
	{ type = "toggle", key = "bindUnitFrames", label = "EldoUI unit frames too", desc = "Player, target, focus, pet and target-of-target frames." },
	{ type = "toggle", key = "bindBlizzard", label = "Blizzard's party and raid frames too",
		desc = "Only when the Improve switch for party or raid frames is on (Blizzard UI page). Key and wheel bindings stay on EldoUI's frames." },
	{ type = "execute", label = "Game's Click Casting", desc = "Opens the game's own Click Casting window; its bindings work on EldoUI's frames too.",
		func = function() if ToggleClickBindingFrame then ToggleClickBindingFrame() end end },
	{ type = "tab", label = "Tooltip" },
	{ type = "description", label = "Hovering a frame lists your bindings in the tooltip, grouped by modifier: the game's Click Casting and EldoUI's." },
	{ type = "toggle", key = "party", label = "Party and raid frames", desc = "EldoUI's group frames, and Blizzard's when their Improve switch is on." },
	{ type = "toggle", key = "unitFrames", label = "Player, target and focus frames", desc = "EldoUI's unit frames." },
	{ type = "toggle", key = "heldOnly", label = "Only the held modifier", desc = "Hold Shift, Ctrl or Alt to see just those clicks; no modifier shows plain clicks." },
	{ type = "toggle", key = "showTargetMenu", label = "List \"Open menu\" clicks too", desc = "Also list the clicks that open the frame's menu." },
}

---------------------------------------------------------------------------
-- Style presets: how much click-casting does and shows. Bindings
-- themselves are never touched by a preset.
---------------------------------------------------------------------------
E:RegisterStyles("ClickCast", {
	{ key = "Healer", title = "Healer", desc = "Bindings on every frame, keys and wheel on hover, tips for the modifier you hold.",
		settings = { bindingsEnabled = true, hoverKeys = true, bindUnitFrames = true, bindBlizzard = true, party = true, unitFrames = true, heldOnly = true } },
	{ key = "GroupOnly", title = "Group frames only", desc = "Bindings and tips only on party and raid frames.",
		settings = { bindingsEnabled = true, hoverKeys = true, bindUnitFrames = false, bindBlizzard = true, party = true, unitFrames = false, heldOnly = false } },
	{ key = "MouseOnly", title = "Mouse only", desc = "Mouse button bindings without keys or the wheel on hover.",
		settings = { bindingsEnabled = true, hoverKeys = false, party = true, heldOnly = false } },
	{ key = "TipsOnly", title = "Tips only", desc = "Only the game's own Click Casting, listed in the tooltip.",
		settings = { bindingsEnabled = false, party = true, unitFrames = false, heldOnly = false } },
	{ key = "Quiet", title = "Quiet", desc = "Bindings work, the tooltip stays clean.",
		settings = { bindingsEnabled = true, party = false, unitFrames = false } },
})
