-- Combat Text: Blizzard's own floating combat text (element
-- "floating-combat-text") and frame feedback. Moved here from
-- Combat HUD so every combat text choice sits on one page; the settings
-- were copied over once (Core.lua, M.MigrateProfile).
--
-- Blizzard element actions (CVars go through E:SetCVar, so "Blizzard
-- default" and switching EldoUI's text off put the player's values back):
--   skin     CombatTextFont (the text around your character) and, after a
--            relog, the font of the numbers over targets (DAMAGE_TEXT_FONT)
--   move     scroll direction of the self text (floatingCombatTextFloatMode_v2)
--   hide     Blizzard's floating combat text off: the self text
--            (enableFloatingCombatText) and the numbers over targets
--            (floatingCombatTextCombatDamage_v2 / _Healing_v2)
--   replace  EldoUI's scrolling text instead of Blizzard's self text: only
--            enableFloatingCombatText is set to 0, and only while EldoUI's
--            scrolling text runs. Your damage numbers over enemies stay.
-- Numbers over enemies have one owner: while EldoUI's hit numbers on enemy
-- plates run, Blizzard's damage numbers over enemies (your hits, periodic
-- and pet damage) left at "Blizzard setting" are set to 0, so one hit draws
-- one number over the enemy. Hit numbers off, the module off or Blizzard
-- default put the player's own values back. A row set to Show keeps
-- Blizzard's numbers as well, on purpose.
-- While another combat text addon is loaded (E:FeatureConflict), EldoUI
-- leaves these CVars alone: that addon sets the same ones.
--
-- Frame feedback: short-lived text over EldoUI's player, target, pet and
-- focus frames from UNIT_COMBAT (M.ParseUnitCombat). Secret amounts are
-- drawn as they are. It keeps working while another combat text addon is
-- loaded.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local K = E.CombatKit
local M = E:GetModule("CombatText")
local issecret = M.issecret

local ID = "floating-combat-text"
M.BLIZZARD_ID = ID
local SELF_CVAR = "enableFloatingCombatText"
local WORLD_CVARS = { "floatingCombatTextCombatDamage_v2", "floatingCombatTextCombatHealing_v2" }

-- Message CVars of the self text, as Blizzard lists them in its options.
-- `world` rows (numbers over targets) show on the Nameplates tab.
-- `optional` rows show only when the client has the CVar.
M.BLIZZARD_MESSAGES = {
	{ cvar = "floatingCombatTextCombatState_v2", label = L["Entering and leaving combat"] },
	{ cvar = "floatingCombatTextDodgeParryMiss_v2", label = L["Dodge, parry, miss"] },
	{ cvar = "floatingCombatTextDamageReduction_v2", label = L["Resist, block, absorb"] },
	{ cvar = "floatingCombatTextCombatHealingAbsorbSelf_v2", label = L["Shields on you"], optional = true },
	{ cvar = "floatingCombatTextAuras_v2", label = L["Auras gained"] },
	{ cvar = "floatingCombatTextLowManaHealth_v2", label = L["Low health and mana"] },
	{ cvar = "floatingCombatTextEnergyGains_v2", label = L["Resource gains"] },
	{ cvar = "floatingCombatTextPeriodicEnergyGains_v2", label = L["Periodic resource gains"] },
	{ cvar = "floatingCombatTextComboPoints_v2", label = L["Combo points"] },
	{ cvar = "floatingCombatTextReactives_v2", label = L["Spell alerts (reactives)"] },
	{ cvar = "floatingCombatTextFriendlyHealers_v2", label = L["Names of friendly healers"] },
	{ cvar = "floatingCombatTextRepChanges_v2", label = L["Reputation changes"] },
	{ cvar = "floatingCombatTextHonorGains_v2", label = L["Honor gains"] },
	{ cvar = "floatingCombatTextCombatDamage_v2", label = L["Your damage numbers over enemies"], optional = true, world = true, plateOwned = true },
	{ cvar = "floatingCombatTextCombatHealing_v2", label = L["Your healing numbers"], optional = true, world = true },
	{ cvar = "floatingCombatTextCombatLogPeriodicSpells_v2", label = L["Periodic damage numbers"], optional = true, world = true, plateOwned = true },
	{ cvar = "floatingCombatTextPetMeleeDamage_v2", label = L["Pet damage numbers"], optional = true, world = true, plateOwned = true },
	{ cvar = "floatingCombatTextCombatHealingAbsorbTarget_v2", label = L["Your shields on targets"], optional = true, world = true },
	{ cvar = "floatingCombatTextSpellMechanics_v2", label = L["Effects on your target"], optional = true, world = true },
	{ cvar = "floatingCombatTextSpellMechanicsOther_v2", label = L["Effects on other targets"], optional = true, world = true },
}

-- Message CVars Blizzard no longer offers in its options. EldoUI drops its
-- row and puts back the player's own value if EldoUI had set one.
M.RETIRED_MESSAGES = { "floatingCombatTextAuraFade_v2" }

-- Their saved choices go once (after the move from Combat HUD, which may
-- bring them along).
E:RegisterProfileMigration(function(profile)
	local modules = type(profile.modules) == "table" and profile.modules or nil
	local own = modules and type(modules.CombatText) == "table" and modules.CombatText or nil
	local messages = own and type(own.blizzard) == "table" and own.blizzard.messages or nil
	if type(messages) ~= "table" then return end
	for _, cvar in ipairs(M.RETIRED_MESSAGES) do messages[cvar] = nil end
end, "CombatText:retired", 1)

M.defaults.blizzard = { font = "THEME", fontSize = 0, outline = "OUTLINE", worldFont = false, direction = "blizzard", messages = {} }
for _, message in ipairs(M.BLIZZARD_MESSAGES) do M.defaults.blizzard.messages[message.cvar] = "blizzard" end

function M.KnownCVar(cvar)
	if not C_CVar then return false end
	if C_CVar.GetCVarDefault then return C_CVar.GetCVarDefault(cvar) ~= nil end
	return C_CVar.GetCVar(cvar) ~= nil
end

local function Allowed(action) return M.active and E:BlizzardAllowed(ID, action) end

local originalFont -- { file, size, flags } of CombatTextFont before EldoUI

local function FontPath(db)
	return K.FontPath(db.font)
end

-- The game's DAMAGE_TEXT_FONT before EldoUI first wrote it (saved once).
local originalDamageFont, damageFontSaved, damageFontWritten

-- DAMAGE_TEXT_FONT only while the skin and "numbers over targets" are on;
-- turned off in the same session, the game's own value goes back.
local function ApplyDamageFont(path)
	if path then
		if not damageFontSaved then
			originalDamageFont, damageFontSaved = _G.DAMAGE_TEXT_FONT, true
		end
		-- Read by the game at login: takes effect after a relog.
		DAMAGE_TEXT_FONT = path -- luacheck: ignore 111
		damageFontWritten = true
	elseif damageFontWritten then
		DAMAGE_TEXT_FONT = originalDamageFont -- luacheck: ignore 111
		damageFontWritten = nil
	end
end
M.ApplyDamageFont = ApplyDamageFont

local function ApplyFont(db)
	local skin = Allowed("skin")
	ApplyDamageFont(skin and db and db.worldFont and FontPath(db) or nil)
	local object = CombatTextFont
	if not object then return end
	if skin then
		if not originalFont then originalFont = { object:GetFont() } end
		local size = db.fontSize > 0 and db.fontSize or originalFont[2] or 25
		local outline = db.outline == "NONE" and "" or db.outline
		object:SetFont(FontPath(db), size, outline)
	elseif originalFont and originalFont[1] then
		object:SetFont(originalFont[1], originalFont[2], originalFont[3] or "")
		originalFont = nil
	end
end

-- True while EldoUI's plate numbers own the numbers over enemies.
function M:PlatesOwnWorldNumbers()
	return self:PlatesRunning() and E:BlizzardAllowed(ID) and not E:BlizzardState(ID).hide and true or false
end

-- The player's choice for a message row, with the plate numbers' claim on
-- "Blizzard setting" for Blizzard's damage numbers over enemies.
function M:WorldMessageWanted(message)
	local wanted = self.db.blizzard.messages[message.cvar]
	if message.plateOwned and wanted ~= "on" and wanted ~= "off" and self:PlatesRunning() then return "off" end
	return wanted
end

-- Both Blizzard's damage numbers over enemies and EldoUI's plate numbers
-- draw the same hit (shown on the Nameplates tab), or nil.
function M:WorldNumbersTwice()
	if not self:PlatesRunning() or not (C_CVar and C_CVar.GetCVar) then return nil end
	if E:BlizzardAllowed(ID) and E:BlizzardState(ID).hide then return nil end
	for _, message in ipairs(self.BLIZZARD_MESSAGES) do
		if message.plateOwned and M.KnownCVar(message.cvar) and C_CVar.GetCVar(message.cvar) == "1" then
			return message.label
		end
	end
	return nil
end

local function SetMessage(cvar, wanted)
	if not M.KnownCVar(cvar) then return end
	if wanted == "on" or wanted == "off" then
		E:SetCVar(cvar, wanted == "on" and "1" or "0", ID)
	else
		E:RestoreCVar(cvar, ID)
	end
end

-- Apply the element's switches. Out of combat (CVars, a game font object).
function M:ApplyBlizzard()
	if not (self.active and E:BlizzardAllowed(ID)) or self:Conflict() then
		self:RestoreBlizzard()
		return
	end
	local db = self.db.blizzard
	-- BlizzardAllowed(ID, "hide") is also true for Replace; Hide itself
	-- switches the numbers over enemies off too.
	local hidden = E:BlizzardState(ID).hide and true or false
	local replaced = E:BlizzardAllowed(ID, "replace") and self:ScrollRunning()
	if hidden then
		E:SetCVar(SELF_CVAR, "0", ID)
		for _, cvar in ipairs(WORLD_CVARS) do
			if M.KnownCVar(cvar) then E:SetCVar(cvar, "0", ID) end
		end
	else
		if replaced then E:SetCVar(SELF_CVAR, "0", ID) else E:RestoreCVar(SELF_CVAR, ID) end
		for _, message in ipairs(self.BLIZZARD_MESSAGES) do SetMessage(message.cvar, self:WorldMessageWanted(message)) end
	end
	for _, cvar in ipairs(self.RETIRED_MESSAGES) do E:RestoreCVar(cvar, ID) end
	if Allowed("move") and db.direction ~= "blizzard" then
		E:SetCVar("floatingCombatTextFloatMode_v2", db.direction, ID)
	else
		E:RestoreCVar("floatingCombatTextFloatMode_v2", ID)
	end
	ApplyFont(db)
end

-- Everything back to the player's own values.
function M:RestoreBlizzard()
	ApplyFont(self.db.blizzard)
	if not self:Conflict() then
		E:RestoreCVars(ID)
		return
	end
	-- Another combat text addon: the numbers over enemies EldoUI's plate
	-- hits had claimed go back to the player's values; the rest is left to
	-- that addon.
	for _, message in ipairs(self.BLIZZARD_MESSAGES) do
		if message.plateOwned then E:RestoreCVar(message.cvar, ID) end
	end
end

E:RegisterBlizzardHandler(ID, {
	owner = "CombatText",
	apply = function() E:RunOutOfCombat(function() M:ApplyBlizzard() end) end,
	undo = function() M:RestoreBlizzard() end,
	reload = { skin = true },
	install = { skin = true },
	-- v0.5.0 never touched this element.
	legacy = function() return false end,
})

-- Hand-off (design decision): the first time EldoUI's scrolling text runs
-- while Blizzard's own text around the character is on, ask once whether
-- to hide Blizzard's. Your damage numbers over enemies stay either way.
function M:AskHandOff()
	if self.db.handoffAsked or not self:ScrollRunning() then return end
	if E:BlizzardHidden(ID) or not self:GameTextFeedOn() then return end
	self.db.handoffAsked = true
	M:PushAlert({
		key = "combattext-handoff",
		title = L["Combat Text"],
		text = L["EldoUI shows your combat text now. Hide Blizzard's own text around your character? Your damage numbers over enemies stay."],
		actions = {
			{ label = L["Hide Blizzard's"], func = function()
				E:SetBlizzardElement(ID, "enabled", true)
				E:SetBlizzardElement(ID, "replace", true)
			end },
			{ label = L["Keep both"] },
		},
	})
end

M:AddPart("Blizzard", {
	enable = function()
		E:RunOutOfCombat(function() M:ApplyBlizzard() end)
		C_Timer.After(4, function() if M.active then M:AskHandOff() end end)
	end,
	refresh = function()
		E:RunOutOfCombat(function() M:ApplyBlizzard() end)
		M:AskHandOff()
	end,
	disable = function()
		E:RunOutOfCombat(function() M:RestoreBlizzard() end)
	end,
})

---------------------------------------------------------------------------
-- Frame feedback
---------------------------------------------------------------------------
local FEEDBACK_UNITS = { "player", "target", "pet", "focus" }
local FADE_IN, FADE_OUT = 0.2, 0.3

M.defaults.feedback = {
	enabled = true,
	-- Design decision: on the target frame only by default (your own
	-- hits show in the scrolling text).
	units = { player = false, target = true, pet = false, focus = false },
	fontSize = 18,
	font = "THEME",
	position = "center",     -- center | portrait | health
	hold = 1.5,
	energize = false,
	colorMode = "type",      -- type | white | custom
	damageColor = { 1, 0.25, 0.25 },
	healColor = { 0.25, 1, 0.35 },
	missColor = { 1, 1, 1 },
}

local overlays = {}   -- unit -> overlay frame (EldoUI's own)

local function FeedbackDB() return M.db.feedback end

local function KindColor(kind)
	local db = FeedbackDB()
	if kind == "energize" then
		local mana = E:PowerColorObject("MANA")
		if mana then return mana.r, mana.g, mana.b end
		return 0.4, 0.8, 0.95
	end
	if db.colorMode == "white" then return 1, 1, 1 end
	if db.colorMode == "custom" then
		return unpack(kind == "damage" and db.damageColor or kind == "heal" and db.healColor or db.missColor)
	end
	if kind == "damage" then return 1, 0.25, 0.25 end
	if kind == "heal" then return 0.25, 1, 0.35 end
	return 1, 1, 1
end

-- Plain amounts get the game's digit grouping; secret ones go as they are.
local function AmountText(amount)
	if issecret(amount) then return amount end
	return BreakUpLargeNumbers and BreakUpLargeNumbers(amount) or tostring(amount)
end

local function Show(overlay, text, kind)
	if issecret(text) then
		overlay.text:SetFormattedText("%s", text)
	else
		overlay.text:SetText(text)
	end
	overlay.text:SetTextColor(KindColor(kind))
	overlay.text:SetAlpha(0)
	overlay.started = GetTime()
	overlay:Show()
end

local function OnCombat(overlay, _, _, action, flags, amount, school)
	if not (M.active and FeedbackDB().enabled) then return end
	-- /eui diag answers "does the game send UNIT_COMBAT?" even while the
	-- scrolling text (the other listener) is off.
	local probe = M.probe
	if probe then
		probe.seen = probe.seen + 1
		probe.secret = issecret(amount)
	end
	local kind, payload = M.ParseUnitCombat(action, flags, amount, school)
	if not kind then return end
	if kind == "damage" or kind == "crit" then
		local text = AmountText(payload.amount)
		if not issecret(text) and not issecret(flags) and flags == "BLOCK_REDUCED" then text = L["%s (blocked)"]:format(text) end
		Show(overlay, text, "damage")
	elseif kind == "heal" or kind == "healCrit" then
		Show(overlay, AmountText(payload.amount), "heal")
	elseif kind == "energize" then
		if FeedbackDB().energize then Show(overlay, AmountText(payload.amount), "energize") end
	else
		Show(overlay, payload.type, "miss")
	end
end

-- Blizzard's own timing: fade in, hold, fade out.
local function OnUpdate(overlay)
	local started = overlay.started
	if not started then overlay:Hide() return end
	local elapsed = GetTime() - started
	local hold = FeedbackDB().hold
	if elapsed < FADE_IN then
		overlay.text:SetAlpha(elapsed / FADE_IN)
	elseif elapsed < FADE_IN + hold then
		overlay.text:SetAlpha(1)
	elseif elapsed < FADE_IN + hold + FADE_OUT then
		overlay.text:SetAlpha(1 - (elapsed - FADE_IN - hold) / FADE_OUT)
	else
		overlay.started = nil
		overlay:Hide()
	end
end

-- One overlay per unit: the drawing frame rides on the unit frame, a
-- separate listener frame takes the unit's UNIT_COMBAT events.
local function Overlay(unit)
	local overlay = overlays[unit]
	if overlay then return overlay end
	overlay = CreateFrame("Frame", nil, UIParent)
	overlay:SetSize(1, 1)
	overlay.text = overlay:CreateFontString(nil, "OVERLAY")
	overlay.text:SetPoint("CENTER")
	overlay:SetScript("OnUpdate", OnUpdate)
	overlay:Hide()
	overlay.listener = CreateFrame("Frame")
	overlay.listener:SetScript("OnEvent", function(_, ...) OnCombat(overlay, ...) end)
	overlays[unit] = overlay
	return overlay
end
M.FeedbackOverlay = function(unit) return overlays[unit] end

local function Anchor(frame, position)
	if position == "portrait" and frame.portraitShown and frame.portrait then return frame.portrait end
	if position == "health" and frame.health then return frame.health end
	return frame
end

local function UnitFramesModule()
	return E:GetModule("UnitFrames")
end

-- The feedback font, read again on each theme refresh; nil is the theme font.
local function FeedbackFont()
	local font = FeedbackDB().font
	if E:IsThemeFont(font) then return nil end
	return K.FontPath(font)
end

-- Put each overlay on its unit frame. Out of combat only: the unit frames
-- are secure buttons.
function M:AttachFeedback()
	local db = FeedbackDB()
	local uf = UnitFramesModule()
	local frames = uf and uf.active and uf.frames or {}
	for _, unit in ipairs(FEEDBACK_UNITS) do
		local frame = frames[unit]
		local wanted = M.active and db.enabled and db.units[unit] and frame ~= nil
		local overlay = overlays[unit]
		if wanted then
			overlay = Overlay(unit)
			overlay:SetParent(frame)
			overlay:SetFrameLevel(frame:GetFrameLevel() + 20)
			overlay:ClearAllPoints()
			overlay:SetAllPoints(Anchor(frame, db.position))
			E:SetFont(overlay.text, db.fontSize, nil, FeedbackFont)
			overlay.listener:UnregisterAllEvents()
			overlay.listener:RegisterUnitEvent("UNIT_COMBAT", unit)
		elseif overlay then
			overlay.listener:UnregisterAllEvents()
			overlay.started = nil
			overlay:Hide()
		end
	end
end

local ufHooked = false
local function HookUnitFrames()
	-- The unit frames rebuild on their own profile changes; follow them.
	local uf = UnitFramesModule()
	if uf and not ufHooked and type(uf.Build) == "function" then
		ufHooked = true
		hooksecurefunc(uf, "Build", function()
			if M.active then E:RunOutOfCombat(function() M:AttachFeedback() end) end
		end)
	end
end

local function StopFeedback()
	for _, overlay in pairs(overlays) do
		overlay.listener:UnregisterAllEvents()
		overlay.started = nil
		overlay:Hide()
	end
end

M:AddPart("Feedback", {
	enable = function()
		HookUnitFrames()
		E:RunOutOfCombat(function() M:AttachFeedback() end)
	end,
	refresh = function() E:RunOutOfCombat(function() M:AttachFeedback() end) end,
	disable = StopFeedback,
})
