-- EldoUI cooldown pulse: when one of your own chosen spells or items
-- is ready again, its icon pops in at the middle of the screen (scale in,
-- short hold, fade out), with an optional sound, a spoken line and a glow.
--
-- The ready moment comes only from what the game itself says, read
-- through the combat kit's one cooldown source (K.Cooldowns in Kit.lua),
-- which also says when the game reports a change:
--   spells  the spell cooldown's isActive / isOnGCD flags (NeverSecret)
--   items   the item cooldown's isActive / isOnGCD flags (NeverSecret)
-- An entry whose cooldown runs (not just the global cooldown) is "busy";
-- the first update where the game says it no longer runs is "ready". Spells
-- with charges count as busy while no charge is left, so the pulse shows
-- when the first charge is back. A flag that comes back secret leaves the
-- entry where it was: nothing is guessed from start times or durations.
-- The game sends no event when a cooldown simply runs out, so each busy
-- entry also hands the game's own duration object to a hidden Cooldown
-- widget; its OnCooldownDone callback makes EldoUI look at the flag again
-- right then. A slow re-check (4 times a second, only while something is
-- busy) is the safety net next to that callback.
--
-- Charge gained: a hidden Cooldown runs from C_Spell.GetSpellChargeDuration
-- while the spell's charge flag (SpellChargeInfo.isActive, NeverSecret)
-- says a charge is coming back, and is armed again after each one. Its
-- OnCooldownDone is the "charge gained" moment. `/eui probe charges <spell>`
-- prints each of these moments for one spell (an in-game check).
--
-- Own spells and items only; nothing about party or enemy cooldowns. The
-- pulse never casts or uses anything.
--
-- Other modules can listen to the same list (Combat Text item-ready):
--   E.CooldownReady.Register(key, function(info) end)
--       info = { kind = "spell" | "item", id, name, icon, token, charge }
--       (charge = true for a charge-gained moment)
--   E.CooldownReady.Unregister(key)
--   E.CooldownReady.Entries()  -> the parsed list (copies)
local _, E = ...
local K = E.CombatKit
local CD = K.Cooldowns
local L = E.L

local Key = E.Key
local MOVER = "EldoUI_CooldownPulse"
local GROUP = "cdpulse"
local POLL = 0.25            -- re-check rate while an entry is busy
local POLL_TICK = "cdpulse:poll"
local CHARGE_QUIET = 0.5     -- no charge-gained sound this soon after a ready pulse
local MAX_QUEUE = 6

local M = E:NewModule("CooldownPulse", {
	title = "Cooldown Pulse",
	desc = L["Shows your spell's or item's icon in the middle of the screen when the game says it is ready again, with an optional sound and spoken line."],
	category = "Combat",
	frames = {},
	movers = { "EldoUI_CooldownPulse" },
	blizzard = {},
	savedKeys = { "profile.modules.CooldownPulse" },
	optionsPage = "module:CooldownPulse",
	presets = { "Big", "Flash", "Linger", "Pop", "Subtle" },
	reload = false,
	defaults = {
		enabled = false,
		list = "",             -- spells and items, one per line or separated by commas
		size = 64,
		holdTime = 0.6,
		fadeTime = 0.4,
		startScale = 0.5,
		peakScale = 1.2,
		showName = true,
		sound = "none",
		speech = false,
		speechText = "{name} ready",
		chargeSound = false,
		glow = true,
		talentGroup = 0,       -- 0 = both, 1 or 2 = only that talent group
		overrides = {},        -- [token] = { sound = id|"default", speech = "default"|"on"|"off", glow = "default"|"on"|"off" }
		edit = "",             -- the entry the per-entry rows change
		visibility = E:VisibilityDefaults(),
	},
})

E:RegisterGlowUser("cooldownPulse", {
	title = "Cooldown Pulse",
	desc = "The icon that pops up in the middle of the screen when a spell or item on your Cooldown Pulse list is ready.",
	order = 23,
	button = true,
	default = { style = "blizzard", colorMode = "custom", color = { 1, 0.82, 0 } },
})

---------------------------------------------------------------------------
-- The list: "Fireball, 12051, item:5512, |Hitem:...|h[Healthstone]|h"
-- Plain numbers and names are spells (your own rank); "item:<id>", item
-- links and item names that are no spell are items.
---------------------------------------------------------------------------
local function Known(id)
	local book = C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook
	if not book then return true end
	local ok, known = pcall(book, id)
	if not ok or not K.Plain(known) then return true end
	return known and true or false
end

-- The player's own rank of a spell, by name (the game resolves it).
local function OwnSpell(id)
	local name = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
	local resolved = name and C_Spell.GetSpellIDForSpellIdentifier and C_Spell.GetSpellIDForSpellIdentifier(name)
	if resolved and K.Plain(resolved) and Known(resolved) then return resolved end
	return id
end

local function ItemByName(word)
	if not C_Item.GetItemInfoInstant then return nil end
	local ok, found = pcall(C_Item.GetItemInfoInstant, word)
	if ok and found and K.Plain(found) then return tonumber(found) end
end

-- One word of the list -> "spell", id or "item", id (nil when unknown).
local function ParseWord(word)
	word = strtrim(word or "")
	if word == "" then return nil end
	local item = tonumber(word:match("^[Ii]tem:(%d+)$") or word:match("|Hitem:(%d+)"))
	if item then return "item", item end
	local spell = tonumber(word:match("|Hspell:(%d+)")) or tonumber(word)
	if not spell and C_Spell.GetSpellIDForSpellIdentifier then
		local ok, found = pcall(C_Spell.GetSpellIDForSpellIdentifier, word)
		if ok and found and K.Plain(found) then spell = found end
	end
	if not spell and E.ResolveSpell then spell = E:ResolveSpell(word) end
	if spell and K.Plain(spell) and C_Spell.GetSpellTexture(spell) then return "spell", OwnSpell(spell) end
	item = ItemByName(word)
	if item then return "item", item end
end

local function Token(kind, id) return (kind == "item" and "i" or "s") .. id end

local function Describe(kind, id)
	if kind == "item" then
		local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
		local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
		return type(name) == "string" and name or ("item:" .. id), icon
	end
	local name = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
	return type(name) == "string" and name or ("spell:" .. id), C_Spell.GetSpellTexture(id)
end

-- Every entry of a list text, in order, each once.
function M.Parse(text)
	local list, seen = {}, {}
	for word in tostring(text or ""):gmatch("[^,;\n]+") do
		local kind, id = ParseWord(word)
		if kind then
			local token = Token(kind, id)
			if not seen[token] then
				seen[token] = true
				local name, icon = Describe(kind, id)
				list[#list + 1] = { kind = kind, id = id, token = token, name = name, icon = icon, index = #list + 1 }
			end
		end
	end
	return list
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local entries = {}        -- parsed list
local byToken = {}        -- token -> entry
local listeners = {}      -- key -> fn(info)
local watching = false    -- events registered

-- The game's own flags: active (cooldown runs) and gcd (only the global cooldown).
local function Flags(entry)
	if entry.kind == "spell" then
		local active, gcd, _, maxCharges = K.SpellFlags(entry.id)
		entry.maxCharges = maxCharges
		return active, gcd
	end
	return CD.ItemFlags(entry.id)
end

-- True while a charge of the spell is coming back (the game's own flag).
local function Charging(entry)
	if entry.kind ~= "spell" or not (entry.maxCharges and entry.maxCharges > 1) then return false end
	local info = CD.SpellCharges(entry.id)
	if type(info) ~= "table" or not K.Plain(info.isActive) or type(info.isActive) == "nil" then return nil end
	return info.isActive and true or false
end

local function TalentGroupOK()
	local wanted = tonumber(M.db and M.db.talentGroup) or 0
	if wanted == 0 or not E.TalentGroup then return true end
	return E:TalentGroup() == wanted
end

local function Tracking()
	return (M.active and TalentGroupOK()) or next(listeners) ~= nil
end

local refreshTimer
local function CancelRefresh()
	if refreshTimer then refreshTimer:Cancel(); refreshTimer = nil end
end

local function QueueRefresh()
	if refreshTimer then return end
	refreshTimer = C_Timer.NewTimer(0.2, function()
		refreshTimer = nil
		if Tracking() then M:Refresh() end
	end)
end

---------------------------------------------------------------------------
-- Hidden Cooldown widgets: the client's "done" callback for an entry's own
-- cooldown and for each charge. They never draw anything.
---------------------------------------------------------------------------
-- Released widgets wait in a pool: a list change, new spells, a gear or
-- talent swap reuse them instead of leaking new frames each time.
local cooldownPool = {}
M.hiddenCooldownStats = { created = 0, pooled = 0 }

local function HiddenCooldown(onDone)
	local cooldown = table.remove(cooldownPool)
	if cooldown then
		M.hiddenCooldownStats.pooled = #cooldownPool
		cooldown:Show()
		cooldown:SetScript("OnCooldownDone", onDone)
		return cooldown
	end
	M.hiddenCooldownStats.created = M.hiddenCooldownStats.created + 1
	cooldown = CreateFrame("Cooldown", nil, UIParent)
	cooldown:SetSize(1, 1)
	cooldown:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
	cooldown:SetAlpha(0)
	cooldown:EnableMouse(false)
	if cooldown.SetDrawSwipe then cooldown:SetDrawSwipe(false) end
	if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
	if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
	if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
	cooldown:SetScript("OnCooldownDone", onDone)
	return cooldown
end

local function PoolCooldown(cooldown)
	cooldown:SetScript("OnCooldownDone", nil)
	cooldown:Clear()
	cooldown:Hide()
	cooldownPool[#cooldownPool + 1] = cooldown
	M.hiddenCooldownStats.pooled = #cooldownPool
end

local function DurationOf(entry, charge)
	if entry.kind ~= "spell" then return nil end
	return CD.SpellDuration(entry.id, charge)
end

---------------------------------------------------------------------------
-- Ready service (also used by Combat Text)
---------------------------------------------------------------------------
local Ready = {}
E.CooldownReady = Ready

-- Same service, method style (Combat Text's item-ready line uses this).
function E:RegisterCooldownReady(key, fn) return Ready.Register(key, fn) end
function E:UnregisterCooldownReady(key) return Ready.Unregister(key) end

local Pulse -- forward

local function Notify(entry, charge)
	local info = { kind = entry.kind, id = entry.id, name = entry.name, icon = entry.icon, token = entry.token, charge = charge or nil }
	for _, fn in pairs(listeners) do
		local ok, err = pcall(fn, info)
		if not ok then geterrorhandler()(err) end
	end
end

local pending = {}   -- entries that became ready in this pass
local flushQueued = false

local function Flush()
	flushQueued = false
	table.sort(pending, function(a, b) return a.index < b.index end)
	local list = pending
	pending = {}
	for _, entry in ipairs(list) do
		if M.active and TalentGroupOK() then Pulse(entry) end
		Notify(entry)
	end
end

local function Fire(entry)
	entry.readyAt = GetTime()
	pending[#pending + 1] = entry
	if not flushQueued then
		flushQueued = true
		C_Timer.After(0, Flush)
	end
end

local UpdateEntry -- forward

local function ArmCooldown(entry)
	if not entry.cooldown then
		entry.cooldown = HiddenCooldown(function()
			C_Timer.After(0, function() UpdateEntry(entry) end)
		end)
	end
	if entry.kind == "item" then
		-- Item cooldowns: start and duration from the game, passed on untouched.
		CD.DrawItem(entry.cooldown, entry.id)
	else
		local duration = DurationOf(entry, false)
		if duration and entry.cooldown.SetCooldownFromDurationObject then
			pcall(entry.cooldown.SetCooldownFromDurationObject, entry.cooldown, duration)
		end
	end
end

local function ChargeGained(entry)
	local now = GetTime()
	-- One moment, one callback (a re-armed widget can fire twice in a row).
	if entry.chargeAt and now - entry.chargeAt < 0.25 then return end
	entry.chargeAt = now
	if entry.token == "probe" then
		if M.probeCallback then M.probeCallback(entry) end
	elseif not (entry.readyAt and now - entry.readyAt < CHARGE_QUIET) then
		if M.active and TalentGroupOK() and M.ChargeSound then M.ChargeSound(entry) end
		Notify(entry, true)
	end
	C_Timer.After(0, function() M.ArmCharge(entry) end)
end

-- Charge widget: armed while the game says a charge is coming back.
function M.ArmCharge(entry)
	local charging = Charging(entry)
	if charging == nil then return end
	if not charging then
		if entry.charge and entry.chargeArmed then entry.charge:Clear() end
		entry.chargeArmed = nil
		return
	end
	if not entry.charge then entry.charge = HiddenCooldown(function() ChargeGained(entry) end) end
	local duration = DurationOf(entry, true)
	if duration and entry.charge.SetCooldownFromDurationObject then
		entry.chargeArmed = pcall(entry.charge.SetCooldownFromDurationObject, entry.charge, duration) or nil
	end
end

local function Busy()
	for _, entry in ipairs(entries) do
		if entry.state == "busy" then return true end
	end
	return false
end

local function UpdatePoller()
	local want = watching and Busy()
	local polling = E.Ticker:IsSubscribed(POLL_TICK)
	if want and not polling then
		E.Ticker:Subscribe(POLL_TICK, POLL, function()
			for _, entry in ipairs(entries) do
				if entry.state == "busy" then UpdateEntry(entry) end
			end
			if not Busy() then E.Ticker:Unsubscribe(POLL_TICK) end
		end, "CooldownPulse")
	elseif not want and polling then
		E.Ticker:Unsubscribe(POLL_TICK)
	end
end

-- seed: note the state without firing (login, list change, new spells).
UpdateEntry = function(entry, seed)
	if not watching then return end
	local active, gcd = Flags(entry)
	if active == nil then return end -- the game didn't say: keep the state
	local busy = active and not gcd
	if busy then
		if entry.state ~= "busy" then
			entry.state = "busy"
			ArmCooldown(entry)
		end
	else
		if entry.state == "busy" and not seed then Fire(entry) end
		entry.state = "idle"
	end
	if entry.kind == "spell" and (entry.maxCharges or 0) > 1 then M.ArmCharge(entry) end
end

local function UpdateAll(seed)
	for _, entry in ipairs(entries) do UpdateEntry(entry, seed) end
	UpdatePoller()
end

local function ReleaseEntry(entry)
	if entry.cooldown then PoolCooldown(entry.cooldown) end
	if entry.charge then PoolCooldown(entry.charge) end
	entry.cooldown, entry.charge, entry.chargeArmed = nil, nil, nil
end

local RESEED = { "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED" }

local function Rebuild()
	for _, entry in ipairs(entries) do ReleaseEntry(entry) end
	wipe(entries)
	wipe(byToken)
	if not Tracking() then
		CancelRefresh()
		if watching then
			CD.Unsubscribe(GROUP)
			for _, event in ipairs(RESEED) do E:UnregisterEvent(event, GROUP) end
			watching = false
		end
		UpdatePoller()
		return
	end
	for _, entry in ipairs(M.Parse(M.db.list)) do
		entries[#entries + 1] = entry
		byToken[entry.token] = entry
	end
	if not watching then
		watching = true
		-- Cooldowns and charges come from the combat kit's cooldown source.
		CD.Subscribe(GROUP, function() UpdateAll(false) end)
		for _, event in ipairs(RESEED) do
			E:RegisterEvent(event, QueueRefresh, GROUP)
		end
	end
	UpdateAll(true)
end

function Ready.Register(key, fn)
	if type(fn) ~= "function" then return end
	listeners[key] = fn
	if M.db then Rebuild() end
end

function Ready.Unregister(key)
	listeners[key] = nil
	if M.db then Rebuild() end
end

-- A copy of the listener table (key -> fn).
function Ready.Listeners()
	local out = {}
	for key, fn in pairs(listeners) do out[key] = fn end
	return out
end

function Ready.Entries()
	local out = {}
	for _, entry in ipairs(entries) do
		out[#out + 1] = { kind = entry.kind, id = entry.id, token = entry.token, name = entry.name, icon = entry.icon }
	end
	return out
end

---------------------------------------------------------------------------
-- The pulse: one icon, queued in list order when several are ready at once.
---------------------------------------------------------------------------
local holder, fader, pulse
local queue = {}
local playing = false

local function Setting(entry, field)
	local override = entry and M.db.overrides[entry.token]
	local value = override and override[field]
	if value == nil or value == "default" then return M.db[field] end
	if value == "on" then return true end
	if value == "off" then return false end
	return value
end

local function SpeechLine(entry)
	local text = tostring(M.db.speechText or "")
	if text == "" or text == "{name} ready" then text = L["{name} ready"] end
	return (text:gsub("{name}", function() return entry.name or "" end))
end

function M.Speak(text)
	if not (C_VoiceChat and C_VoiceChat.SpeakText) or type(text) ~= "string" or text == "" then return false end
	local voice = 0
	if C_TTSSettings and C_TTSSettings.GetVoiceOptionID then
		local ok, id = pcall(C_TTSSettings.GetVoiceOptionID, 0)
		if ok and type(id) == "number" then voice = id end
	end
	local volume = 100
	if C_TTSSettings and C_TTSSettings.GetSpeechVolume then
		local ok, value = pcall(C_TTSSettings.GetSpeechVolume)
		if ok and type(value) == "number" then volume = value end
	end
	-- SpeakText(voiceID, text, rate, volume, overlap)
	return (pcall(C_VoiceChat.SpeakText, voice, text, 0, volume, false))
end

local function Sounds(entry)
	local sound = Setting(entry, "sound")
	if type(sound) == "string" and sound ~= "" and sound ~= "none" then E:PlayMedia(sound) end
	if Setting(entry, "speech") then M.Speak(SpeechLine(entry)) end
end

function M.ChargeSound(entry)
	if not M.db.chargeSound then return end
	local sound = Setting(entry, "sound")
	if type(sound) == "string" and sound ~= "" and sound ~= "none" then E:PlayMedia(sound) end
end

local function CreatePulse()
	holder = K.Holder(M, MOVER, L["Cooldown Pulse"], { "CENTER", "UIParent", "CENTER", 0, 40 }, 64, 64)
	-- The visibility rule fades this parent; the pulse's own animation
	-- keeps its alpha to itself.
	fader = CreateFrame("Frame", nil, UIParent)
	fader:SetAllPoints(UIParent)
	fader:SetFrameStrata("HIGH")
	fader:EnableMouse(false)
	pulse = CreateFrame("Frame", nil, fader)
	pulse:SetFrameStrata("HIGH")
	pulse:SetPoint("CENTER", holder, "CENTER")
	pulse.icon = pulse:CreateTexture(nil, "ARTWORK")
	pulse.name = E:CreateText(pulse, E.tokens.size.body, "CENTER")
	pulse.name:SetPoint("TOP", pulse, "BOTTOM", 0, -4)
	pulse:Hide()

	local group = pulse:CreateAnimationGroup()
	group.grow = group:CreateAnimation("Scale")
	group.grow:SetOrder(1)
	group.grow:SetSmoothing("OUT")
	group.appear = group:CreateAnimation("Alpha")
	group.appear:SetOrder(1)
	group.appear:SetFromAlpha(0)
	group.appear:SetToAlpha(1)
	group.settle = group:CreateAnimation("Scale")
	group.settle:SetOrder(2)
	group.settle:SetSmoothing("IN_OUT")
	group.fade = group:CreateAnimation("Alpha")
	group.fade:SetOrder(3)
	group.fade:SetFromAlpha(1)
	group.fade:SetToAlpha(0)
	group:SetScript("OnFinished", function() M.PulseDone() end)
	pulse.anim = group
end

local function Clamp(value, low, high, default)
	value = tonumber(value) or default
	return math.max(low, math.min(high, value))
end

local function Layout()
	if not pulse then CreatePulse() end
	local size = Clamp(M.db.size, 24, 160, 64)
	holder:SetSize(size, size)
	pulse:SetSize(size, size)
	E:SetTemplate(pulse)
	pulse.icon:ClearAllPoints()
	pulse.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	pulse.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(pulse.icon)
	E:SetFont(pulse.name, math.max(10, math.floor(size * 0.2)))
	pulse.name:SetShown(M.db.showName and true or false)
	holder:SetShown(M.active and true or false)
	if M.active then
		E:AttachVisibility(fader, M.db.visibility, { watch = false })
	else
		E:DetachVisibility(fader)
	end
end

local function Play(entry)
	playing = true
	pulse.entry = entry
	pulse.icon:SetTexture(entry.icon)
	pulse.name:SetText(entry.name or "")
	if Setting(entry, "glow") then E:ShowUserGlow(pulse, "cooldownPulse") else E:HideGlow(pulse) end
	Sounds(entry)
	local hold = Clamp(M.db.holdTime, 0, 5, 0.6)
	local fade = Clamp(M.db.fadeTime, 0, 5, 0.4)
	local group = pulse.anim
	group:Stop()
	pulse:SetAlpha(1)
	pulse:Show()
	if E.db.general.animations == false then
		-- No motion: show, hold, then go (the fade time still counts).
		C_Timer.After(hold + fade, function() if pulse.entry == entry then M.PulseDone() end end)
		return
	end
	local from = Clamp(M.db.startScale, 0.1, 2, 0.5)
	local peak = Clamp(M.db.peakScale, 0.5, 3, 1.2)
	group.grow:SetScaleFrom(from, from)
	group.grow:SetScaleTo(peak, peak)
	group.grow:SetDuration(0.15)
	group.appear:SetDuration(0.15)
	group.settle:SetScaleFrom(peak, peak)
	group.settle:SetScaleTo(1, 1)
	group.settle:SetDuration(0.1)
	group.fade:SetStartDelay(hold)
	group.fade:SetDuration(math.max(fade, 0.01))
	group:Play()
end

function M.PulseDone()
	if pulse then
		pulse.entry = nil
		pulse:Hide()
		E:HideGlow(pulse)
	end
	playing = false
	local nextEntry = table.remove(queue, 1)
	if nextEntry and M.active then Play(nextEntry) end
end

Pulse = function(entry)
	if not pulse then Layout() end
	if playing then
		for _, queued in ipairs(queue) do
			if queued.token == entry.token then return end
		end
		if pulse.entry and pulse.entry.token == entry.token then return end
		if #queue < MAX_QUEUE then queue[#queue + 1] = entry end
		return
	end
	Play(entry)
end

-- Test: the chosen entry (or the first one, or a sample) now.
function M:Test(token)
	if not self.active then
		self:Print(L["Turn on Cooldown Pulse first."])
		return
	end
	local entry = token and byToken[token] or entries[1]
	if not entry then
		local id = 6603 -- Attack: a spell every character has
		local name, icon = Describe("spell", id)
		entry = { kind = "spell", id = id, token = "test", name = name, icon = icon, index = 0 }
	end
	Pulse(entry)
end

---------------------------------------------------------------------------
-- "Add my Main row": the spells of EldoUI's own main cooldown row.
---------------------------------------------------------------------------
function M:AddMainRow()
	local CM = E:GetModule("CooldownManager")
	local lists = CM and CM.db and CM.db.rows and CM.db.rows.lists
	local _, class = UnitClass("player")
	local own = lists and lists[class or "ALL"]
	local text = own and own.main or ""
	if strtrim(text) == "" then
		self:Print(L["Your main cooldown row has no spells yet (Cooldown Manager > Own rows)."])
		return 0
	end
	local have = {}
	for _, entry in ipairs(M.Parse(self.db.list)) do have[entry.token] = true end
	local added = {}
	for _, entry in ipairs(M.Parse(text)) do
		if not have[entry.token] then
			have[entry.token] = true
			added[#added + 1] = tostring(entry.id)
		end
	end
	if #added > 0 then
		local current = strtrim(tostring(self.db.list or ""))
		self.db.list = (current ~= "" and (current .. ", ") or "") .. table.concat(added, ", ")
		self:Refresh()
	end
	self:Print(E:Plural(#added, "Added %d spell from your main cooldown row.", "Added %d spells from your main cooldown row."):format(#added))
	if E.RefreshConfig then E:RefreshConfig() end
	return #added
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:Refresh()
	CancelRefresh()
	if type(self.db.overrides) ~= "table" then self.db.overrides = {} end
	Layout()
	Rebuild()
	if not self.active then
		wipe(queue)
		if pulse and pulse:IsShown() then pulse.anim:Stop() M.PulseDone() end
	end
end

-- The mover exists from the start (layouts place it, move mode shows it
-- once the module is on); the frame stays hidden while the module is off.
function M:OnInitialize()
	Layout()
end

function M:OnEnable()
	self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", function() M:Refresh() end)
	self:Refresh()
end

function M:OnDisable()
	self:UnregisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
	self:Refresh()
end

function M:OnProfileChanged()
	self:Refresh()
end
M.refreshWhenOff = true

-- Read-only views of the pulse state.
M.entries, M.queue = entries, queue
function M.PulseFrame() return pulse end

---------------------------------------------------------------------------
-- /eui probe charges <spell>: prints every charge-gained moment of one
-- spell (the in-game check for the hidden-cooldown charge signal). The
-- probe command is shared (Core/Probes.lua).
---------------------------------------------------------------------------
local probe
function M.ProbeEntry() return probe end -- read-only

local function StopProbe()
	if not probe then return false end
	ReleaseEntry(probe)
	CD.Unsubscribe("cdpulse-probe")
	M.probeCallback = nil
	probe = nil
	return true
end

E:RegisterProbe("charges", Key("<spell> | off  print each charge that comes back for one of your spells"), function(arg)
	arg = strtrim(arg or "")
	if arg == "" or arg:lower() == "off" then
		if StopProbe() then E:Print(L["Charge probe stopped."]) else E:Print(L["Usage: /eui probe charges <spell name or ID>"]) end
		return
	end
	StopProbe()
	local kind, id = ParseWord(arg)
	if kind ~= "spell" then
		E:Print(L["No spell found for \"%s\"."]:format(arg))
		return
	end
	local name, icon = Describe("spell", id)
	local entry = { kind = "spell", id = id, token = "probe", name = name, icon = icon, index = 0, gained = 0, started = GetTime() }
	local _, _, _, maxCharges = K.SpellFlags(id)
	entry.maxCharges = maxCharges
	if not (maxCharges and maxCharges > 1) then
		E:Print(L["%s has no charges (or the game didn't say how many)."]:format(name))
		return
	end
	probe = entry
	E:Print(L["Watching %s (%d charges). Spend the charges; each one that comes back prints a line. /eui probe charges off stops."]:format(name, maxCharges))
	M.probeCallback = function(watched)
		if watched ~= probe then return end
		probe.gained = probe.gained + 1
		E:Print(L["Charge gained: %s (#%d, %.1f s after the probe started)"]:format(name, probe.gained, GetTime() - probe.started))
	end
	local function Rearm() M.ArmCharge(entry) end
	CD.Subscribe("cdpulse-probe", function(changes) if changes.spells then Rearm() end end)
	Rearm()
end)


---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function EntryValues()
	local values = {}
	for _, entry in ipairs(M.Parse(M.db and M.db.list)) do
		values[entry.token] = ("%d. %s"):format(entry.index, entry.name)
	end
	if not next(values) then values[""] = L["(add spells or items above)"] end
	return values
end

local function Editing()
	local token = M.db and M.db.edit
	if type(token) ~= "string" or token == "" then return nil end
	for _, entry in ipairs(M.Parse(M.db.list)) do
		if entry.token == token then return token end
	end
	return nil
end

local function NoEntry() return Editing() == nil end
local function O(field) return function() return "overrides." .. (Editing() or "none") .. "." .. field end end
local DEFAULT_ON_OFF = { default = "Module default", on = "On", off = "Off" }
local function NoSpeech() return not M.db.speech end

M.options = {
	{ type = "tab", label = L["Pulse"] },
	{ type = "description", label = L["When one of your listed spells or items is ready again, its icon pops up in the middle of the screen. The global cooldown never counts."] },
	{ type = "header", label = L["Spells and items"] },
	{ type = "input", key = "list", label = L["Names or IDs"],
		desc = L["Your own spells or items to watch, separated by commas or one per line. Spell names or IDs; items as item:ID, a shift-clicked item link or the item's name."] },
	{ type = "execute", label = L["Add my main cooldown row"], func = function() M:AddMainRow() end,
		desc = L["Adds every spell of your main cooldown row (Cooldown Manager > Own rows) to the list."] },
	{ type = "execute", label = L["Test"], func = function() M:Test(Editing()) end,
		desc = L["Shows a pulse now (the entry chosen below, or the first on the list)."] },
	{ type = "header", label = L["Look"] },
	{ type = "range", key = "size", label = L["Icon size"], min = 32, max = 128, step = 2,
		desc = L["How big the pulse icon is."] },
	{ type = "range", unit = "s", key = "holdTime", label = L["Hold time"], min = 0, max = 3, step = 0.1,
		desc = L["Seconds the icon stays at full size before it fades."] },
	{ type = "range", unit = "s", key = "fadeTime", label = L["Fade time"], min = 0, max = 2, step = 0.1,
		desc = L["Seconds the icon takes to fade out."] },
	{ type = "range", percent = true, key = "startScale", label = L["Start scale"], min = 0.2, max = 1, step = 0.05, cog = true,
		desc = L["How small the icon starts before it pops in (1 = full size)."] },
	{ type = "range", percent = true, key = "peakScale", label = L["Pop scale"], min = 1, max = 2, step = 0.05, cog = true,
		desc = L["How far the icon overshoots before it settles (1 = no overshoot)."] },
	{ type = "toggle", key = "showName", label = L["Show the name"],
		desc = L["The spell's or item's name under the icon."] },
	{ type = "toggle", key = "glow", label = L["Glow"],
		desc = L["A glow around the pulse icon. Its look is on the Glows page (Cooldown pulse)."] },
	{ type = "header", label = L["Sound and speech"] },
	{ type = "media", mediaKind = "sound", key = "sound", label = L["Sound"], none = true,
		desc = L["Plays when a spell or item is ready."] },
	{ type = "toggle", key = "chargeSound", label = L["Charge gained"],
		desc = L["Also play the sound each time a charge of a spell with charges comes back, not only when the first one does."] },
	{ type = "toggle", key = "speech", label = L["Speak"],
		desc = L["Reads a line out with the game's text-to-speech (its voice and volume from the game's Text to Speech settings)."] },
	{ type = "input", key = "speechText", label = L["Spoken line"], hidden = NoSpeech,
		desc = L["What is read out. {name} becomes the spell's or item's name."] },
	{ type = "header", label = L["When"] },
	{ type = "select", key = "talentGroup", label = L["Talent group"],
		values = { [0] = L["Both"], [1] = L["Talent group 1 only"], [2] = L["Talent group 2 only"] },
		desc = L["Pulse only while this talent group (dual specialization) is active."] },

	{ type = "tab", label = L["Per entry"] },
	{ type = "description", label = L["Give one spell or item its own sound, speech or glow. Module default uses the settings on the Pulse tab."] },
	{ type = "select", key = "edit", label = L["Entry"], values = EntryValues,
		desc = L["The spell or item the rows below change."] },
	{ type = "media", mediaKind = "sound", key = O("sound"), label = L["Sound"], none = true, default = "default",
		hidden = NoEntry, desc = L["The sound for this entry. Module default uses the sound on the Pulse tab."] },
	{ type = "select", key = O("speech"), label = L["Speak"], values = DEFAULT_ON_OFF, hidden = NoEntry,
		desc = L["Read the spoken line for this entry, or not."] },
	{ type = "select", key = O("glow"), label = L["Glow"], values = DEFAULT_ON_OFF, hidden = NoEntry,
		desc = L["Glow around the pulse icon for this entry, or not."] },
	{ type = "execute", label = L["Test this entry"], hidden = NoEntry, func = function() M:Test(Editing()) end,
		desc = L["Shows this entry's pulse now, with its sound and speech."] },
}

for _, row in ipairs(E:VisibilityOptions("visibility", { db = function() return M.db end })) do
	if row.type == "header" then row.label = L["Visibility"] end
	table.insert(M.options, row)
end

---------------------------------------------------------------------------
-- Styles: the look only (the list stays).
---------------------------------------------------------------------------
E:RegisterStyles("CooldownPulse", {
	{ key = "Pop", title = "Pop", desc = "64 px icon that pops in, holds for a moment and fades.",
		settings = { size = 64, holdTime = 0.6, fadeTime = 0.4, startScale = 0.5, peakScale = 1.2, showName = true } },
	{ key = "Big", title = "Big", desc = "A large 96 px icon with a longer hold, hard to miss.",
		settings = { size = 96, holdTime = 1, fadeTime = 0.5, startScale = 0.4, peakScale = 1.3, showName = true } },
	{ key = "Subtle", title = "Subtle", desc = "A small 44 px icon without name that fades quickly.",
		settings = { size = 44, holdTime = 0.3, fadeTime = 0.3, startScale = 0.8, peakScale = 1.05, showName = false } },
	{ key = "Flash", title = "Flash", desc = "Shows at once at full size and fades, no pop.",
		settings = { size = 64, holdTime = 0.4, fadeTime = 0.6, startScale = 1, peakScale = 1, showName = true } },
	{ key = "Linger", title = "Linger", desc = "Stays for two seconds with its name, for slow reminders.",
		settings = { size = 64, holdTime = 2, fadeTime = 0.6, startScale = 0.6, peakScale = 1.1, showName = true } },
})
