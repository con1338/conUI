-- EldoUI CastFX: which bars get effects, and when.
--   * EldoUI's unit frame cast bars, through UnitFrames.CastX.RegisterCastHook
--     (start, delayed, channelUpdate, stop, fail, interrupted, layout).
--   * Blizzard's own cast bars (player, target, focus, pet, boss) of a unit
--     whose EldoUI cast bar is off (design decision): a hook
--     after the bar's own event handler reads the state the bar already has.
--     Nothing on Blizzard's bar is replaced; CastFX adds its own child frame.
--   * Test casts: a stand-in bar laid over each enabled cast bar.
local _, E = ...
local M = E.CastFX
local Engine = M.Engine
local L = E.L

local issecret = issecretvalue or function() return false end
local Plain = M.Plain

local function UnitFrames()
	local UF = E:GetModule("UnitFrames")
	return UF and UF.active and UF or nil
end

-- EldoUI's cast bar for a unit kind, when it is on.
function M:EldoBar(kind)
	local UF = UnitFrames()
	if not (UF and UF.frames) then return nil end
	if kind == "boss" then
		for index = 1, 5 do
			local frame = UF.frames["boss" .. index]
			if frame and frame.castbar and frame.castbar.enabled then return frame.castbar end
		end
		return nil
	end
	local frame = UF.frames[kind]
	return frame and frame.castbar and frame.castbar.enabled and frame.castbar or nil
end

---------------------------------------------------------------------------
-- EldoUI cast bars
---------------------------------------------------------------------------
local hideHooked = setmetatable({}, { __mode = "k" })

local function HookHide(bar)
	if hideHooked[bar] then return end
	hideHooked[bar] = true
	bar:HookScript("OnHide", function(self)
		local deco = Engine.Get(self)
		if deco and deco.active then Engine.Stop(deco) end
	end)
end

local function OnCastHook(event, castbar, unit, info)
	if not M.active then return end
	local kind = M.KindOf(unit)
	local deco = Engine.Get(castbar)
	if event == "layout" then
		-- Our own sizes: the bar part's width (the cast bar knows it) and
		-- the height the unit frame laid out. Plain numbers only.
		if type(info) == "table" then
			local width = castbar.barWidth
			if issecret(width) or type(width) ~= "number" then width = info.width end
			local height = info.height
			if issecret(width) or type(width) ~= "number" then width = nil end
			if issecret(height) or type(height) ~= "number" then height = nil end
			Engine.hookSizes[castbar] = (width or height) and { width = width, height = height } or nil
		end
		if deco then
			Engine.Layout(deco)
			if not (info and info.enabled) and deco.active then Engine.Stop(deco) end
		end
		-- The EldoUI bar may have been switched on or off.
		M:AttachBlizzard()
		return
	end
	if not (kind and M.db.bars[kind]) then
		if deco and deco.active then Engine.Stop(deco) end
		return
	end
	info = info or {}
	if event == "hold" then
		-- Our finish flash stands in for the unit frames' white end flash.
		local flash = castbar.flash
		if deco and deco.flashed and flash and flash.anim then
			flash.anim:Stop()
			flash:SetAlpha(0)
		end
		return
	end
	if event == "start" then
		if kind == "player" then M:RememberSpell(info.spellID, info.name, info.texture) end
		deco = Engine.Get(castbar, "eldo")
		HookHide(castbar)
		Engine.Start(deco, M:ThemeKeyFor(kind, info), info)
	elseif not (deco and deco.active) then
		return
	elseif event == "delayed" or event == "channelUpdate" then
		-- The unit frames colored the bar afresh: the theme goes back on.
		deco.info = info
		Engine.Tint(deco, deco.theme, info)
		Engine.Pushback(deco)
	elseif event == "stop" then
		Engine.Finish(deco, "success")
	elseif event == "fail" or event == "interrupted" then
		Engine.Finish(deco, "fail")
	end
end
M.OnCastHook = OnCastHook

local hookHandle
local function HookEldoBars()
	if hookHandle then return true end
	local UF = E:GetModule("UnitFrames")
	local CastX = UF and UF.CastX
	if not (CastX and CastX.RegisterCastHook) then return false end
	hookHandle = CastX.RegisterCastHook(OnCastHook)
	return true
end

local function UnhookEldoBars()
	if not hookHandle then return end
	local UF = E:GetModule("UnitFrames")
	if UF and UF.CastX and UF.CastX.UnregisterCastHook then UF.CastX.UnregisterCastHook(hookHandle) end
	hookHandle = nil
end

-- A cast turning interruptible again: the unit frames put their plain
-- color back (no hook for it), so the theme goes back on a frame later.
local function Retint(_, _, unit)
	local kind = M.KindOf(unit)
	if not (M.active and kind) then return end
	C_Timer.After(0, function()
		for bar, deco in pairs(Engine.decos) do
			if deco.active and deco.kind == "eldo" and bar.unit == unit then
				local info = {}
				for key, value in pairs(deco.info or {}) do info[key] = value end
				info.notInterruptible = false
				Engine.Tint(deco, deco.theme, info)
			end
		end
	end)
end
M.Retint = Retint

---------------------------------------------------------------------------
-- Blizzard's own cast bars
---------------------------------------------------------------------------
local BLIZZARD_BARS = {
	player = { "PlayerCastingBarFrame" },
	target = { "TargetFrameSpellBar" },
	focus = { "FocusFrameSpellBar" },
	pet = { "PetCastingBarFrame" },
	boss = { "Boss1TargetFrameSpellBar", "Boss2TargetFrameSpellBar", "Boss3TargetFrameSpellBar", "Boss4TargetFrameSpellBar", "Boss5TargetFrameSpellBar" },
}
M.BLIZZARD_BARS = BLIZZARD_BARS

local blizzKind = setmetatable({}, { __mode = "k" })  -- bar -> unit kind

function M:BlizzardWanted(kind)
	return self.active and self.db.blizzard and self.db.bars[kind] and not self:EldoBar(kind) and true or false
end

-- The first Blizzard cast bar of a kind the client has.
function M:BlizzardBar(kind)
	for _, name in ipairs(BLIZZARD_BARS[kind] or {}) do
		local bar = _G[name]
		if type(bar) == "table" and bar.GetStatusBarTexture then return bar end
	end
end

local function Casting(bar)
	return (Plain(bar.casting) or Plain(bar.channeling)) and true or false
end

-- What the unit casts, from the game (values may be secret).
local function CastInfo(unit)
	local ok, name, _, texture, _, _, isTradeskill, _, notInterruptible, spellID = pcall(UnitCastingInfo, unit)
	-- issecret first: a secret is never truth-tested or compared.
	if ok and (issecret(name) or name) then
		return { name = name, texture = texture, isTradeskill = isTradeskill, notInterruptible = notInterruptible, spellID = spellID, channel = false }
	end
	local okChannel, channelName, _, channelTexture, _, _, channelTradeskill, channelLocked, channelSpell = pcall(UnitChannelInfo, unit)
	if okChannel and (issecret(channelName) or channelName) then
		return { name = channelName, texture = channelTexture, isTradeskill = channelTradeskill, notInterruptible = channelLocked, spellID = channelSpell, channel = true }
	end
end

local START = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true }
local PUSH = { UNIT_SPELLCAST_DELAYED = true, UNIT_SPELLCAST_CHANNEL_UPDATE = true }
local STOP = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true }
local FAIL = { UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true }

-- Runs after the bar's own handler, so bar.casting / bar.channeling already
-- say what the bar shows (a failed attempt at another spell leaves them on).
local function OnBlizzardEvent(bar, event)
	local kind = blizzKind[bar]
	local deco = Engine.Get(bar)
	if not (kind and M:BlizzardWanted(kind)) then
		if deco and deco.active then Engine.Stop(deco) end
		return
	end
	local casting = Casting(bar)
	if casting and (START[event] or not (deco and deco.active)) then
		if not bar:IsVisible() then return end
		local unit = Plain(bar.unit) or kind
		local info = CastInfo(unit) or {}
		if kind == "player" then M:RememberSpell(info.spellID, info.name, info.texture) end
		deco = Engine.Get(bar, "blizzard")
		Engine.Start(deco, M:ThemeKeyFor(kind, info), info)
	elseif deco and deco.active then
		if PUSH[event] then
			Engine.Pushback(deco)
		elseif STOP[event] and not casting then
			Engine.Finish(deco, "success")
		elseif FAIL[event] and not casting then
			Engine.Finish(deco, "fail")
		elseif not casting then
			Engine.Stop(deco)
		end
	end
end
M.OnBlizzardEvent = OnBlizzardEvent

function M:AttachBlizzard()
	if not self.active then return end
	-- Bars are looked up only for units that want them.
	for kind, names in pairs(BLIZZARD_BARS) do
		if self:BlizzardWanted(kind) then
			for _, name in ipairs(names) do
				local bar = _G[name]
				if type(bar) == "table" and bar.GetStatusBarTexture and bar.HookScript and not blizzKind[bar] then
					blizzKind[bar] = kind
					bar:HookScript("OnEvent", OnBlizzardEvent)
					HookHide(bar)
				end
			end
		end
	end
	for bar, deco in pairs(Engine.decos) do
		if deco.kind == "blizzard" and deco.active and not self:BlizzardWanted(blizzKind[bar]) then Engine.Stop(deco) end
	end
end

---------------------------------------------------------------------------
-- Attach / detach
---------------------------------------------------------------------------
function M:AttachBars()
	if not self.active then return end
	HookEldoBars()
	self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE", Retint)
	self:AttachBlizzard()
	-- Bars switched off on the page drop their effects.
	for bar, deco in pairs(Engine.decos) do
		if deco.active and deco.kind == "eldo" then
			local kind = M.KindOf(bar.unit)
			if not (kind and self.db.bars[kind]) then Engine.Stop(deco) end
		end
	end
end

function M:DetachBars()
	UnhookEldoBars()
	self:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
	self:StopTests()
	Engine.ReleaseAll()
end

---------------------------------------------------------------------------
-- Test casts: a stand-in bar over every enabled cast bar (or one in the
-- middle of the screen), with the theme that bar would use.
---------------------------------------------------------------------------
local testBars = {}
M.TestBars = testBars

local function TestBar(index)
	local bar = testBars[index]
	if bar then return bar end
	bar = E:CreateStatusBar(UIParent)
	bar:SetFrameStrata("HIGH")
	bar:Hide()
	bar.text = E:CreateText(bar, E.tokens.size.label, "LEFT")
	bar.text:SetPoint("LEFT", 4, 0)
	bar.time = E:CreateText(bar, E.tokens.size.label, "RIGHT")
	bar.time:SetPoint("RIGHT", -4, 0)
	testBars[index] = bar
	return bar
end

local function TestUpdate(bar, elapsed)
	bar.elapsed = bar.elapsed + elapsed
	local spent = math.min(bar.elapsed, bar.seconds)
	bar:SetValue(spent)
	bar.time:SetFormattedText("%.1f", bar.seconds - spent)
	if bar.elapsed < bar.seconds then return end
	bar:SetScript("OnUpdate", nil)
	local deco = Engine.Get(bar)
	if deco then Engine.Finish(deco, bar.outcome) end
	bar.text:SetText(bar.outcome == "fail" and (_G.INTERRUPTED or L["Interrupted"]) or L["Done"])
	local token = {}
	bar.token = token
	C_Timer.After(0.8, function()
		if bar.token == token then bar:Hide() end
	end)
end

-- Starts a test cast on `bar` with theme `key`.
function M:RunTestBar(bar, key, seconds, outcome, anchor)
	bar:ClearAllPoints()
	if anchor then
		bar:SetAllPoints(anchor)
		bar:SetFrameLevel(anchor:GetFrameLevel() + 10)
	else
		bar:SetSize(240, 20)
		bar:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
	end
	bar:SetMinMaxValues(0, seconds)
	bar:SetValue(0)
	bar:SetStatusBarTexture(E.media.statusbar)
	bar:SetStatusBarColor(1, 1, 1)
	local theme = self:GetTheme(key) or M.BUILTIN.minimal
	bar.text:SetFormattedText(L["Test: %s"], E:Translate(theme.name or key))
	bar.time:SetText("")
	bar.seconds, bar.elapsed, bar.outcome, bar.token = seconds, 0, outcome or "success", nil
	bar:Show()
	local deco = Engine.Get(bar, "test")
	Engine.Start(deco, key, { channel = false, notInterruptible = false })
	bar:SetScript("OnUpdate", TestUpdate)
end

-- /eui castfx test [theme] [seconds] [fail]
function M:TestCast(themeKey, seconds, outcome)
	if not self.active then
		E:Print(E:ModuleOffHint("CastFX"))
		return
	end
	if InCombatLockdown() then
		E:Print(L["Test casts wait until you leave combat."])
		return
	end
	if themeKey and not self:ThemeExists(themeKey) then themeKey = nil end
	seconds = math.max(1, math.min(tonumber(seconds) or 3, 10))
	local index = 0
	for _, kind in ipairs(M.UNIT_KINDS) do
		if self.db.bars[kind] then
			local anchor = self:EldoBar(kind) or (self:BlizzardWanted(kind) and self:BlizzardBar(kind))
			if anchor then
				index = index + 1
				local key = themeKey or (kind == "player" and self.db.previewTheme) or self:ThemeKeyFor(kind)
				self:RunTestBar(TestBar(index), key, seconds, outcome, anchor)
			end
		end
	end
	if index == 0 then
		index = 1
		self:RunTestBar(TestBar(1), themeKey or self.db.previewTheme, seconds, outcome)
	end
	for extra = index + 1, #testBars do testBars[extra]:Hide() end
	return index
end

function M:StopTests()
	for _, bar in ipairs(testBars) do
		bar:SetScript("OnUpdate", nil)
		local deco = Engine.Get(bar)
		if deco then Engine.Stop(deco) end
		bar:Hide()
	end
end

E:RegisterEvent("PLAYER_REGEN_DISABLED", function() M:StopTests() end, testBars)

---------------------------------------------------------------------------
-- /eui castfx dump: the player's spellbook with IDs and the school CastFX
-- finds, to extend Data/CastFXSpells.lua.
---------------------------------------------------------------------------
function M:DumpSpellbook()
	local book = C_SpellBook
	if not (book and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo and book.GetSpellBookItemInfo) then
		E:Print(L["This client has no spellbook API to list."])
		return
	end
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
	local count = 0
	for line = 1, book.GetNumSpellBookSkillLines() or 0 do
		local lineInfo = book.GetSpellBookSkillLineInfo(line)
		if lineInfo and lineInfo.numSpellBookItems then
			for offset = 1, lineInfo.numSpellBookItems do
				local item = book.GetSpellBookItemInfo((lineInfo.itemIndexOffset or 0) + offset, bank)
				local id = item and Plain(item.spellID)
				if id and not (item.isPassive or item.isOffSpec) then
					local school = M.SchoolOf(id, item.name, item.iconID)
					E:Print(L["%d  %s  icon %s  %s"]:format(id, tostring(item.name), tostring(item.iconID),
						E:TextHex("secondary") .. (school and L[M.SCHOOL_NAMES[school]] or L["no school"]) .. "|r"))
					count = count + 1
				end
			end
		end
	end
	E:Print(E:Plural(count, "%d spell listed.", "%d spells listed."):format(count))
end

E:AddCommand("castfx", "[test [theme] [seconds] [fail] | dump]  cast bar effects: open the page, play a test cast on every enabled cast bar, or list your spellbook with spell IDs", function(arg)
	local word, rest = (arg or ""):match("^(%S*)%s*(.*)$")
	word = (word or ""):lower()
	if word == "test" then
		local theme, seconds, outcome
		for token in rest:gmatch("%S+") do
			local lower = token:lower()
			if tonumber(token) then seconds = tonumber(token)
			elseif lower == "fail" or lower == "interrupt" then outcome = "fail"
			else theme = lower end
		end
		M:TestCast(theme, seconds, outcome)
	elseif word == "dump" then
		M:DumpSpellbook()
	else
		E:ToggleConfig("module:CastFX", true)
	end
end)
