-- EldoUI Fishing: fishing made comfortable, one action per press.
--
-- Fishing mode (on while a fishing pole is equipped, or with the toggle
-- key): the key you pick casts Fishing through EldoUI's secure cast button
-- (an override binding, set only out of combat). While your bobber is out
-- the same key becomes the game's Interact with target, so a press on a
-- splash loots the bobber the game's own soft interact picks; fishing mode
-- turns soft interact on for mouse and keyboard and lets it reach the
-- bobber (your own settings come back after). Combat clears every override
-- at once; fishing mode comes back after combat.
--
-- The fishing bar (mover EldoUI_FishingBar): Cast, Lure (one macro press:
-- use your best lure, then the pole), Swap (equip your pole, or put your
-- weapons back: one equip press) and the catch count. Optional: a double
-- right-click casts (fishing mode only, out of combat), a louder splash
-- (sound channels raised through E:SetCVar and put back after), and the
-- catch log: fish and items per zone and spot, catches per hour, skill-ups.
-- With "Start a Farming session" a Farming session runs while you fish
-- (Farming counts the loot itself).
--
-- Never built (they act for the player): auto-equip and auto-lure chains,
-- auto-open clams, auto-recast, AFK fishing. Loot is the game's own auto-loot.
--
-- Data: the lure items and their bonus below were checked by hand against
-- the Classic item database (EldoUI_LootData has no lure table).
-- The spell IDs here are checked against the WoW: Forever client tables of
-- build 1.60.1.70862.
local _, E = ...
local L = E.L

local floor, max = math.floor, math.max

local M = E:NewModule("Fishing", {
	title = "Fishing",
	category = "Quality of Life",
	desc = "Fishing mode: one key casts and then loots the bobber, a bar with lure and pole buttons, a louder splash and a catch log.",
	conflicts = { "BetterFishing", "Angleur", "FishingBuddy" },
	frames = { "EldoUI_FishingBar", "EldoUI_FishingCast", "EldoUI_FishingLure", "EldoUI_FishingSwap" },
	movers = { "EldoUI_FishingBar" },
	blizzard = {},
	savedKeys = { "profile.modules.Fishing", "global.FishingLog", "private.Fishing" },
	optionsPage = "module:Fishing",
	presets = { "CompactBar", "ForeverBronze", "LargeButtons", "LogPanel", "Minimal" },
	reload = false,
	themed = "StyleBar",
	defaults = {
		enabled = false,       -- it takes over a key and changes sound settings
		trigger = "pole",      -- pole | toggle
		castKey = "",          -- e.g. "F" or "SHIFT-R"
		interact = true,       -- the same key loots the bobber
		doubleClick = false,   -- a double right-click casts
		soundBoost = true,
		boostLevel = 1,
		dimOthers = true,      -- music and ambience down while fishing
		bar = true,
		autoHide = true,       -- the bar only shows in fishing mode
		catchLog = true,
		feedFarming = false,
		buttonSize = 32,
		showCount = true,
		showLabels = false,
		backdrop = "transparent", -- panel | transparent | none
	},
})
E.Fishing = M

local Clean = E.Plain

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g, h, i, j, k = pcall(fn, ...)
	if ok then return a, b, c, d, e, f, g, h, i, j, k end
end

-- Fishing (the cast spell of every rank) and the lures, best first.
M.FISHING_SPELLS = { [7620] = true, [7731] = true, [7732] = true, [18248] = true }
M.FISHING_SPELL = 7620
M.LURES = {
	{ id = 6533, bonus = 100 }, -- Aquadynamic Fish Attractor
	{ id = 6532, bonus = 75 },  -- Bright Baubles
	{ id = 7307, bonus = 75 },  -- Flesh Eating Worm
	{ id = 6530, bonus = 50 },  -- Nightcrawlers
	{ id = 6811, bonus = 50 },  -- Aquadynamic Fish Lens
	{ id = 6529, bonus = 25 },  -- Shiny Bauble
}
local SUBCLASS_POLE = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole) or 20
local CLASS_WEAPON = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local CVAR_OWNER = "fishing"

local function FishingName()
	local name = C_Spell and C_Spell.GetSpellName and Clean(Try(C_Spell.GetSpellName, M.FISHING_SPELL))
	return type(name) == "string" and name ~= "" and name or nil
end
M.FishingName = FishingName

---------------------------------------------------------------------------
-- State: is a pole on, is fishing mode on, is the bobber out
---------------------------------------------------------------------------
local function IsPole(itemID)
	if not itemID then return false end
	local _, _, _, _, _, classID, subclassID = Try(C_Item.GetItemInfoInstant, itemID)
	return Clean(classID) == CLASS_WEAPON and Clean(subclassID) == SUBCLASS_POLE
end
M.IsPole = IsPole

function M:PoleEquipped()
	return IsPole(Clean(Try(GetInventoryItemID, "player", 16)))
end

function M:WantMode()
	if not self.active then return false end
	if self.db.trigger == "toggle" then return self.toggled and true or false end
	-- With a pole: the toggle key pauses fishing mode until the pole comes off.
	if not self:PoleEquipped() then
		self.paused = nil
		return false
	end
	return not self.paused
end

-- Your best lure in the bags, or nil.
function M:BestLure()
	for _, lure in ipairs(self.LURES) do
		local count = tonumber(Clean(Try(C_Item.GetItemCount, lure.id))) or 0
		if count > 0 then return lure.id end
	end
end

-- A pole in your bags (the first found), or nil.
function M:BagPole()
	local bags = E.BagCache
	for _, bag in ipairs(bags:BagIDs()) do
		for slot = 1, bags:NumSlots(bag) do
			local id = bags:ItemID(bag, slot)
			if id and IsPole(id) then return id end
		end
	end
end

local function ItemName(id)
	return id and (Clean(Try(C_Item.GetItemNameByID, id)) or Clean((Try(C_Item.GetItemInfo, id)))) or nil
end

---------------------------------------------------------------------------
-- Override bindings: only out of combat, cleared when combat starts
---------------------------------------------------------------------------
local function ValidKey(key)
	if type(key) ~= "string" then return nil end
	key = key:upper():gsub("%s+", "")
	if key == "" or not key:match("^[%w%-]+$") then return nil end
	return key
end
M.ValidKey = ValidKey

function M:ClearBindings()
	if not self.cast then return end
	if InCombatLockdown() then return end
	ClearOverrideBindings(self.cast)
	self.bound = nil
end

-- What the key does now: "cast", "interact" or nil (no override).
function M:BindingState()
	return self.bound
end

function M:UpdateBindings()
	if not self.cast then return end
	E:RunOutOfCombat(function()
		local key = ValidKey(self.db.castKey)
		local want = self.fishingMode and key and (self.bobber and self.db.interact and "interact" or "cast") or nil
		if want == self.bound and key == self.boundKey then return end
		ClearOverrideBindings(self.cast)
		self.bound, self.boundKey = nil, nil
		if want == "cast" then
			SetOverrideBindingClick(self.cast, true, key, self.cast:GetName(), "LeftButton")
		elseif want == "interact" then
			SetOverrideBinding(self.cast, true, key, "INTERACTTARGET")
		end
		self.bound, self.boundKey = want, want and key or nil
	end)
end

---------------------------------------------------------------------------
-- Sound and soft interact while fishing (E:SetCVar keeps your values).
-- Interact with target finds the bobber only through the game's soft
-- interact, and with the game's own defaults it never does: soft interact
-- for the gamepad only (SoftTargetInteract 1), a reach of 10 yards (the
-- bobber lands farther out) and straight ahead only (arc 0). The key then
-- reached the hard target instead ("You need to be closer to interact with
-- that target."). Seen in the game on 15.11.2026 (WoW: Forever 1.60.1):
-- with 3, 30 and 1 the key loots the bobber, and an addon may write all
-- three (C_CVar.GetCVarInfo: not secure; a write from /run held). Fishing
-- mode raises each of them to that (never lowers one) and puts your own
-- values back when it ends. On a client that protects SoftTargetInteract
-- the options page builds the player's own chat command instead.
---------------------------------------------------------------------------
-- Your own value of each CVar fishing changed is kept in the character's
-- saved data too, so it comes back even when another EldoUI feature had
-- changed that CVar first (and after a reload while fishing).
local function Saved()
	local saved = E:GetPrivate("Fishing")
	if not saved then return nil end
	saved.cvars = type(saved.cvars) == "table" and saved.cvars or {}
	return saved.cvars
end

local function SetFishingCVar(name, value)
	local saved = Saved()
	local current = C_CVar and C_CVar.GetCVar and Clean(Try(C_CVar.GetCVar, name))
	if current == nil then return end
	if saved and saved[name] == nil then saved[name] = current end
	E:SetCVar(name, value, CVAR_OWNER)
end

-- Soft interact for mouse and keyboard (SoftTargetInteract 2 or 3): the
-- fishing key finds the bobber only with it. nil when the game has no answer.
local function SoftInteractOn()
	if not (C_CVar and C_CVar.GetCVar) then return nil end
	local value = tonumber(Clean(Try(C_CVar.GetCVar, "SoftTargetInteract")))
	if not value then return nil end
	return value >= 2
end
M.SoftInteractOn = SoftInteractOn

-- What fishing mode needs of soft interact: each setting's value while
-- fishing for your own value, or nil when yours already reaches.
M.SOFT_INTERACT = {
	-- 0 off, 1 gamepad, 2 mouse and keyboard, 3 both: mouse and keyboard join.
	{ name = "SoftTargetInteract", raise = function(value) if value < 2 then return value + 2 end end },
	-- Yards: the bobber lands up to about 20 yards out.
	{ name = "SoftTargetInteractRange", raise = function(value) if value < 30 then return 30 end end },
	-- 0 straight ahead only, 1 in front of you, 2 all around.
	{ name = "SoftTargetInteractArc", raise = function(value) if value < 1 then return 1 end end },
}

function M:RaiseSoftInteract()
	if not (C_CVar and C_CVar.GetCVar) then return end
	for _, cvar in ipairs(self.SOFT_INTERACT) do
		local current = tonumber(Clean(Try(C_CVar.GetCVar, cvar.name)))
		local value = current and cvar.raise(current)
		if value and not E:CVarSecure(cvar.name) then SetFishingCVar(cvar.name, tostring(value)) end
	end
end

-- Before soft interact was raised here, a SoftTargetInteract record of
-- fishing's came only from an older version's write the game refused: it
-- holds nothing to put back, so it is dropped once.
local SOFT_RECORDS = 2

function M:ApplyCVars(on)
	local private = E:GetPrivate("Fishing")
	if private and private.softRecords ~= SOFT_RECORDS then
		local old = Saved()
		if old then old.SoftTargetInteract = nil end
		E:ForgetCVar("SoftTargetInteract", CVAR_OWNER)
		private.softRecords = SOFT_RECORDS
	end
	if on then
		if self.db.interact then self:RaiseSoftInteract() end
		if self.db.soundBoost then
			local level = tostring(self.db.boostLevel or 1)
			SetFishingCVar("Sound_SFXVolume", level)
			SetFishingCVar("Sound_MasterVolume", level)
		end
		if self.db.soundBoost and self.db.dimOthers then
			SetFishingCVar("Sound_MusicVolume", "0.1")
			SetFishingCVar("Sound_AmbienceVolume", "0.1")
		end
		self.cvarsOn = true
		return
	end
	local saved = Saved()
	local snapshot = EldoUIDB and EldoUIDB.cvarSnapshot
	for name, value in pairs(saved or {}) do
		local entry = snapshot and snapshot[name]
		if entry and entry.owner == CVAR_OWNER then
			E:RestoreCVar(name, CVAR_OWNER)
		else
			-- Another feature took the snapshot first: put fishing's own record back.
			E:SetCVar(name, value, CVAR_OWNER)
		end
		saved[name] = nil
	end
	self.cvarsOn = nil
end

---------------------------------------------------------------------------
-- Fishing mode
---------------------------------------------------------------------------
function M:SetMode(on)
	on = on and true or false
	if on == (self.fishingMode or false) then
		self:UpdateBindings()
		self:RefreshBar()
		return
	end
	self.fishingMode = on
	if not on then self.bobber = false end
	self:ApplyCVars(on)
	self:UpdateBindings()
	if on then
		self.session = self.session or { started = time(), casts = 0, catches = 0, items = 0, firstCast = nil, lastCatch = nil }
		local farming = E.Farming
		if self.db.feedFarming and farming and farming.active and not farming:Running() then farming:Start() end
	end
	self:RefreshBar()
	if on and not E.Tour:Seen("fishing:mode") then E.Tour:Offer("fishing:mode") end
end

-- Tour help: the first time fishing mode starts, what the fishing key
-- does now (once per account; never in combat).
E.Tour:Register("fishing:mode", {
	form = "spot", word = "fishing",
	offer = function(_, force)
		if not (M.active and M.fishingMode) then return false end
		local key = ValidKey(M.db.castKey)
		local text
		if key and M.db.interact then
			text = L["%s casts Fishing. While the bobber is out the same key loots it: press it when the bobber splashes. Combat gives the key back its normal job until the fight ends."]:format(M.KeyLabel(key))
		elseif key then
			text = L["%s casts Fishing. Combat gives the key back its normal job until the fight ends."]:format(M.KeyLabel(key))
		else
			text = L["Pick a fishing key in /eui fishing: it casts Fishing, then loots the bobber."]
			if M.bar and M.bar:IsVisible() then text = text .. " " .. L["Until then, the Cast button on the fishing bar casts."] end
		end
		local bar = M.bar and M.bar:IsVisible() and M.bar or nil
		return E.Tour:Spot("fishing:mode", {
			force = force, target = bar, side = "TOP",
			title = L["Fishing mode"],
			text = text,
		})
	end,
	replay = function(def)
		if not M.active then
			E:Print(E:ModuleOffHint("Fishing"))
		elseif not M.fishingMode then
			E:Print(L["This help shows while fishing mode is on."])
		else
			def.offer(def, true)
		end
	end,
})

-- The toggle key: starts or ends fishing mode ("With the toggle key"), or
-- pauses it while the pole stays on ("While a pole is equipped").
function M:Toggle()
	if InCombatLockdown() then
		E:Print(L["Fishing mode changes after combat."])
		return
	end
	if self.db.trigger == "toggle" then
		self.toggled = not self.toggled
	elseif self:PoleEquipped() then
		self.paused = not self.paused
	else
		E:Print(L["Equip a fishing pole to start fishing mode."])
		return
	end
	self:Evaluate()
end

function M:Evaluate()
	if InCombatLockdown() then return end
	self:SetMode(self:WantMode())
end

-- The bobber: the player's Fishing channel.
function M:OnChannel(started, spellID)
	spellID = Clean(spellID)
	local fishing = spellID and self.FISHING_SPELLS[spellID]
	if not fishing and started then
		local name = Clean((Try(UnitChannelInfo, "player")))
		fishing = name ~= nil and name == FishingName()
	end
	if started and not fishing then return end
	if not started and not self.bobber then return end
	self.bobber = started and true or false
	-- A new cast is a new catch, also when the last loot never sent LOOT_CLOSED.
	if started then self.lootCounted = nil end
	if started and self.session then
		self.session.casts = self.session.casts + 1
		self.session.firstCast = self.session.firstCast or GetTime()
	end
	self:UpdateBindings()
	self:RefreshBar()
end

---------------------------------------------------------------------------
-- Double right-click casts (fishing mode only, out of combat)
---------------------------------------------------------------------------
local DOUBLE_CLICK = 0.4

local function OnWorldMouseDown(_, button)
	if button ~= "RightButton" or not (M.active and M.db.doubleClick and M.fishingMode) then return end
	if InCombatLockdown() or not M.cast then return end
	local now = GetTime()
	if M.lastRight and now - M.lastRight < DOUBLE_CLICK then
		-- The release of this second click casts.
		SetOverrideBindingClick(M.cast, true, "BUTTON2", M.cast:GetName(), "LeftButton")
		M.doubleArmed = now
		C_Timer.After(DOUBLE_CLICK + 0.1, function()
			if M.doubleArmed == now and M.cast and not InCombatLockdown() then
				SetOverrideBinding(M.cast, true, "BUTTON2", nil)
				M.doubleArmed = nil
			end
		end)
		M.lastRight = nil
	else
		M.lastRight = now
	end
end

---------------------------------------------------------------------------
-- Catch log
---------------------------------------------------------------------------
function M:Log()
	local log = E:GetGlobal("FishingLog") or {}
	log.zones = type(log.zones) == "table" and log.zones or {}
	log.skill = type(log.skill) == "table" and log.skill or {}
	return log
end

local function Place()
	local zone = Clean(Try(GetRealZoneText)) or "?"
	local spot = Clean(Try(GetSubZoneText)) or ""
	if zone == "" then zone = "?" end
	return zone, spot ~= "" and spot or zone
end

-- One fishing loot window: count every item into this zone and spot.
function M:RecordLoot(items)
	if not self.db.catchLog then return end
	local zone, spot = Place()
	local log = self:Log()
	local z = log.zones[zone] or { catches = 0, spots = {} }
	log.zones[zone] = z
	z.catches = (z.catches or 0) + 1
	z.spots = type(z.spots) == "table" and z.spots or {}
	local s = z.spots[spot] or { catches = 0, items = {} }
	z.spots[spot] = s
	s.catches = (s.catches or 0) + 1
	s.items = type(s.items) == "table" and s.items or {}
	local total = 0
	for _, item in ipairs(items) do
		s.items[item.id] = (s.items[item.id] or 0) + item.count
		total = total + item.count
	end
	if self.session then
		self.session.catches = self.session.catches + 1
		self.session.items = self.session.items + total
		self.session.lastCatch = GetTime()
	end
end

-- One fishing loot, from LOOT_READY or LOOT_OPENED, whichever comes first:
-- with auto loot WoW: Forever sends only LOOT_READY (seen in the game on
-- 15.11.2026: LOOT_READY, then LOOT_CLOSED, never LOOT_OPENED), so a catch
-- log that waited for LOOT_OPENED stayed at 0. LOOT_READY can come more
-- than once for one loot: it counts once, on the first with a slot, until
-- LOOT_CLOSED or the next cast.
function M:OnLootOpened()
	if not (self.active and self.fishingMode) or self.lootCounted then return end
	if not Clean(Try(IsFishingLoot)) then return end
	local slots = tonumber(Clean(Try(GetNumLootItems))) or 0
	if slots < 1 then return end
	self.lootCounted = true
	local items = {}
	for slot = 1, slots do
		local link = Clean(Try(GetLootSlotLink, slot))
		local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
		if id then
			local _, _, count = Try(GetLootSlotInfo, slot)
			items[#items + 1] = { id = id, count = tonumber(Clean(count)) or 1 }
		end
	end
	self:RecordLoot(items)
	self.bobber = false
	self:UpdateBindings()
	self:RefreshBar()
end

-- Fishing skill-ups (from the profession list).
function M:FishingSkill()
	if not (GetProfessions and GetProfessionInfo) then return nil end
	local fishing = select(4, Try(GetProfessions))
	if not fishing then return nil end
	local _, _, rank, maxRank = Try(GetProfessionInfo, fishing)
	return tonumber(Clean(rank)), tonumber(Clean(maxRank))
end

function M:OnSkill()
	local rank = self:FishingSkill()
	if not rank then return end
	local last = self.lastSkill
	self.lastSkill = rank
	if last and rank > last and self.db.catchLog then
		local log = self:Log()
		log.skill[#log.skill + 1] = { t = time(), rank = rank, zone = (Place()) }
		while #log.skill > 200 do table.remove(log.skill, 1) end
		if self.session then self.session.skillUps = (self.session.skillUps or 0) + (rank - last) end
	end
end

-- Catches per hour this session (nil until a few minutes of data).
function M:PerHour()
	local s = self.session
	if not (s and s.firstCast and s.catches > 0) then return nil end
	local seconds = (s.lastCatch or GetTime()) - s.firstCast
	if seconds < 60 then return nil end
	return s.catches * 3600 / seconds
end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------
local function SecureButton(name, parent)
	local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
	-- On release only: a key press or a click is one action. useOnKeyDown
	-- keeps it on the release with the game's "cast on key press" setting,
	-- which otherwise waits for a press the button never receives.
	button:RegisterForClicks("AnyUp")
	button:SetAttribute("useOnKeyDown", false)
	E:SetTemplate(button)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	button.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(button.icon)
	button.label = E:CreateText(button, E.tokens.size.tiny, "CENTER")
	button.label:SetPoint("TOP", button, "BOTTOM", 0, -2)
	button:SetScript("OnEnter", function(self) M:ButtonTooltip(self) end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	-- Hover, pressed and the accent border from the Skin kit (after SetScript).
	E:SkinHoverPress(button, button.icon, button)
	return button
end

function M:ButtonTooltip(button)
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	local s = E.tokens.text.secondary
	if button == self.cast then
		GameTooltip:AddLine(L["Cast Fishing"], unpack(E.tokens.text.body))
		local key = ValidKey(self.db.castKey)
		GameTooltip:AddLine(key and (L["Your fishing key: %s. While the bobber is out it loots the bobber."]):format(key)
			or L["Pick a fishing key on the options page to cast and loot with one key."], s[1], s[2], s[3], true)
	elseif button == self.lure then
		local lure = self:BestLure()
		GameTooltip:AddLine(L["Apply a lure"], unpack(E.tokens.text.body))
		GameTooltip:AddLine(lure and (L["Uses %s on your pole: one press."]):format(ItemName(lure) or ("#" .. lure)) or L["No lure in your bags."], s[1], s[2], s[3], true)
	elseif button == self.swap then
		GameTooltip:AddLine(self:PoleEquipped() and L["Weapons back"] or L["Equip your pole"], unpack(E.tokens.text.body))
		GameTooltip:AddLine(L["One equip per click; not in combat."], s[1], s[2], s[3], true)
	else
		self:LogTooltip(GameTooltip)
	end
	GameTooltip:Show()
end

function M:LogTooltip(tooltip)
	local s, b = E.tokens.text.secondary, E.tokens.text.body
	tooltip:AddLine(L["Catch log"], unpack(E.tokens.text.body))
	local session = self.session
	if session then
		tooltip:AddDoubleLine(L["Casts"], tostring(session.casts), s[1], s[2], s[3], b[1], b[2], b[3])
		tooltip:AddDoubleLine(L["Catches"], tostring(session.catches), s[1], s[2], s[3], b[1], b[2], b[3])
		local perHour = self:PerHour()
		if perHour then tooltip:AddDoubleLine(L["Per hour"], ("%d"):format(floor(perHour + 0.5)), s[1], s[2], s[3], b[1], b[2], b[3]) end
		if session.skillUps then tooltip:AddDoubleLine(L["Skill-ups"], tostring(session.skillUps), s[1], s[2], s[3], b[1], b[2], b[3]) end
	end
	local zone, spot = Place()
	local z = self:Log().zones[zone]
	local here = z and z.spots and z.spots[spot]
	if here then
		tooltip:AddLine(" ")
		tooltip:AddLine((L["%s: %d catches"]):format(spot, here.catches or 0), s[1], s[2], s[3])
		local list = {}
		for id, count in pairs(here.items or {}) do list[#list + 1] = { id = id, count = count } end
		table.sort(list, function(x, y) return x.count > y.count end)
		for i = 1, math.min(6, #list) do
			tooltip:AddDoubleLine(ItemName(list[i].id) or ("#" .. list[i].id), tostring(list[i].count), b[1], b[2], b[3], b[1], b[2], b[3])
		end
	end
end

-- The catch log of the zone you are in, in chat: each spot with its
-- catches and the items caught most often there.
function M:PrintLog()
	local zone = Place()
	local z = self:Log().zones[zone]
	if not (z and z.spots and next(z.spots)) then
		E:Print(L["No catches logged in %s yet."]:format(zone))
		return
	end
	E:Print((L["%s: %d catches"]):format(zone, z.catches or 0))
	local spots = {}
	for name, spot in pairs(z.spots) do spots[#spots + 1] = { name = name, data = spot } end
	table.sort(spots, function(x, y) return (x.data.catches or 0) > (y.data.catches or 0) end)
	for _, spot in ipairs(spots) do
		local list = {}
		for id, count in pairs(spot.data.items or {}) do list[#list + 1] = { id = id, count = count } end
		table.sort(list, function(x, y) return x.count > y.count end)
		local parts = {}
		for i = 1, math.min(4, #list) do
			parts[#parts + 1] = ("%s x%d"):format(ItemName(list[i].id) or ("#" .. list[i].id), list[i].count)
		end
		E:Print(("  %s: %d  %s"):format(spot.name, spot.data.catches or 0, table.concat(parts, ", "))) -- no-L: names and numbers only
	end
end

function M:BuildBar()
	if self.bar then return end
	local bar = CreateFrame("Frame", "EldoUI_FishingBar", UIParent)
	bar:SetSize(200, 40)
	bar:SetFrameStrata("MEDIUM")
	bar.bg = CreateFrame("Frame", nil, bar)
	bar.bg:SetAllPoints()
	bar.bg:SetFrameLevel(max(bar:GetFrameLevel() - 1, 0))
	self.cast = SecureButton("EldoUI_FishingCast", bar)
	self.lure = SecureButton("EldoUI_FishingLure", bar)
	self.swap = SecureButton("EldoUI_FishingSwap", bar)
	self.cast.icon:SetTexture(136245) -- Trade_Fishing
	self.lure.icon:SetTexture(134335)
	self.swap.icon:SetTexture(132932)
	bar.count = CreateFrame("Button", nil, bar)
	bar.count.text = E:CreateText(bar.count, E.tokens.size.label, "LEFT")
	bar.count.text:SetPoint("LEFT")
	bar.count:SetScript("OnEnter", function(owner) M:ButtonTooltip(owner) end)
	bar.count:SetScript("OnLeave", GameTooltip_Hide)
	E:SkinHoverPress(bar.count)
	E:BindOptionsLink(bar.count, { page = "module:Fishing", key = "showCount" })
	bar:Hide()
	self.bar = bar
	E:CreateMover(bar, "EldoUI_FishingBar", "Fishing Bar", { "BOTTOM", "UIParent", "BOTTOM", 20, 240 })
	self:StyleBar()
end

function M:StyleBar()
	local bar = self.bar
	if not bar then return end
	E:RunOutOfCombat(function()
		local size, gap = self.db.buttonSize, 6
		local x = 4
		for _, button in ipairs({ self.cast, self.lure, self.swap }) do
			button:SetSize(size, size)
			button:ClearAllPoints()
			button:SetPoint("LEFT", bar, "LEFT", x, 0)
			button.label:SetShown(self.db.showLabels)
			x = x + size + gap
		end
		self.cast.label:SetText(L["Cast"])
		self.lure.label:SetText(L["Lure"])
		self.swap.label:SetText(L["Swap"])
		bar.count:ClearAllPoints()
		bar.count:SetPoint("LEFT", bar, "LEFT", x, 0)
		bar.count:SetSize(max(40, 200 - x - 4), size)
		bar.count:SetShown(self.db.showCount)
		local backdrop = self.db.backdrop
		if backdrop == "panel" then E:SetPanelTemplate(bar.bg, false) else E:SetTemplate(bar.bg, true) end
		bar.bg:SetShown(backdrop ~= "none")
		E:SetStyleEdge(bar.bg, backdrop ~= "none")
	end)
end

-- Secure attributes: only out of combat.
function M:UpdateButtons()
	if not self.cast then return end
	E:RunOutOfCombat(function()
		local fishing = FishingName()
		self.cast:SetAttribute("type", fishing and "spell" or nil)
		self.cast:SetAttribute("spell", fishing)
		local lure = self:BestLure()
		local lureName = ItemName(lure)
		self.lure:SetAttribute("type", lureName and "macro" or nil)
		self.lure:SetAttribute("macrotext", lureName and ("/use %s\n/use 16"):format(lureName) or nil)
		self.lure.icon:SetDesaturated(lureName == nil)
		-- Swap: equip the pole, or put back what was worn before.
		local text
		if self:PoleEquipped() then
			local saved = E:GetPrivate("Fishing") or {}
			local main, off = ItemName(saved.main), ItemName(saved.off)
			if main then text = ("/equipslot 16 %s"):format(main) .. (off and ("\n/equipslot 17 %s"):format(off) or "") end -- no-L (macro text the game parses)
		else
			local pole = ItemName(self:BagPole())
			if pole then text = ("/equip %s"):format(pole) end -- no-L (macro text the game parses)
		end
		self.swap:SetAttribute("type", text and "macro" or nil)
		self.swap:SetAttribute("macrotext", text)
		self.swap.icon:SetDesaturated(text == nil)
	end, "fishing:buttons")
end

-- What you wore before the pole, for Swap back.
function M:RememberWeapons()
	if self:PoleEquipped() then return end
	local saved = E:GetPrivate("Fishing")
	if not saved then return end
	saved.main = Clean(Try(GetInventoryItemID, "player", 16))
	saved.off = Clean(Try(GetInventoryItemID, "player", 17))
end

function M:CountText()
	local s = self.session
	if not s then return L["No catches yet"] end
	local perHour = self:PerHour()
	local text = E:Plural(s.catches, "%d catch", "%d catches"):format(s.catches)
	if perHour then text = text .. "  " .. E:TokenHex(E.tokens.text.secondary) .. (L["%d/h"]):format(floor(perHour + 0.5)) .. "|r" end
	return text
end

function M:RefreshBar()
	local bar = self.bar
	if not bar then return end
	local show = self.active and self.db.bar and (self.fishingMode or not self.db.autoHide)
	E:RunOutOfCombat(function()
		if show then
			bar.count.text:SetText(self:CountText())
			self.cast.icon:SetVertexColor(1, 1, 1)
			if self.bobber then
				local c = E.media.accentColor
				self.cast.icon:SetVertexColor(c[1], c[2], c[3])
			end
			bar:Show()
		else
			bar:Hide()
		end
	end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local EVENT_OWNER = "Fishing"

local function OnEvent(_, event, unit, _, spellID)
	if not M.active then return end
	if event == "PLAYER_REGEN_DISABLED" then
		-- Combat: every override goes now (InCombatLockdown is not set yet).
		M:ClearBindings()
		M.doubleArmed = nil
		if M.captureCanvas then
			M.captureCanvas.blocked = true
			M.StopCapture(M.captureCanvas)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		M:UpdateButtons()
		M:Evaluate()
		M:UpdateBindings()
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		if unit == "player" then M:OnChannel(true, spellID) end
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if unit == "player" then M:OnChannel(false, spellID) end
	elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
		M:OnLootOpened()
	elseif event == "LOOT_CLOSED" then
		M.lootCounted = nil
	elseif event == "SKILL_LINES_CHANGED" then
		M:OnSkill()
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		M:RememberWeapons()
		M:UpdateButtons()
		M:Evaluate()
	elseif event == "BAG_UPDATE_DELAYED" then
		M:UpdateButtons()
	elseif event == "PLAYER_ENTERING_WORLD" then
		M:RememberWeapons()
		M:UpdateButtons()
		M:Evaluate()
		M.lastSkill = M:FishingSkill()
	end
end

local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
	"LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "SKILL_LINES_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" }

function E:ToggleFishingMode()
	if M.active then M:Toggle() else E:Print(E:ModuleOffHint("Fishing")) end
end

function M:OnInitialize()
	E:RegisterPrivate("Fishing", {})
	E:RegisterGlobal("FishingLog", { zones = {}, skill = {} })
end

function M:OnEnable()
	self:BuildBar()
	for _, event in ipairs(EVENTS) do E:RegisterEvent(event, OnEvent, EVENT_OWNER) end
	if not self.worldHooked and WorldFrame then
		self.worldHooked = true
		WorldFrame:HookScript("OnMouseDown", OnWorldMouseDown)
	end
	-- A reload while fishing: the saved CVar values come back first.
	self:ApplyCVars(false)
	self:RememberWeapons()
	self:UpdateButtons()
	self.lastSkill = self:FishingSkill()
	self:StyleBar()
	self:Evaluate()
end

function M:OnDisable()
	for _, event in ipairs(EVENTS) do E:UnregisterEvent(event, EVENT_OWNER) end
	self.toggled = false
	self.paused = nil
	self.fishingMode = false
	self.bobber = false
	self:ApplyCVars(false)
	E:RunOutOfCombat(function()
		if self.cast then ClearOverrideBindings(self.cast) end
		self.bound, self.boundKey = nil, nil
		if self.bar then self.bar:Hide() end
	end)
end

function M:OnProfileChanged()
	if not self.active then return end
	self:StyleBar()
	-- Changed sound or key settings apply at once while fishing.
	if self.fishingMode then
		self:ApplyCVars(false)
		self:ApplyCVars(true)
	end
	self:Evaluate()
	self:UpdateBindings()
	self:RefreshBar()
end

---------------------------------------------------------------------------
-- Slash command and key binding
---------------------------------------------------------------------------
E:NameBinding("BINDING_HEADER_ELDOUIFISHING", E.Key("EldoUI Fishing"))
E:NameBinding("BINDING_NAME_ELDOUI_FISHING_TOGGLE", E.Key("Fishing mode on or off"))
E:NameBinding("BINDING_NAME_CLICK EldoUI_FishingCast:LeftButton", E.Key("Cast Fishing (Fishing bar)"))

E:AddCommand("fish", "[mode | log | reset]  fishing mode and the catch log", function(arg)
	if not M.active then
		E:Print(E:ModuleOffHint("Fishing"))
		return
	end
	arg = (arg or ""):lower():match("^%s*(.-)%s*$")
	if arg == "mode" then
		M:Toggle()
	elseif arg == "reset" then
		M.session = M.fishingMode and { started = time(), casts = 0, catches = 0, items = 0 } or nil
		M:RefreshBar()
		E:Print(L["Fishing session count cleared."])
	elseif arg == "log" then
		M:PrintLog()
	elseif arg == "" then
		local s = M.session
		E:Print(s and M:CountText() or L["No catches yet"])
	else
		E:Print(L["Usage: /eui fish [mode | log | reset]"])
	end
end)

---------------------------------------------------------------------------
-- Fishing key capture (an options row): click the button, press the key.
-- Out of combat only; Esc cancels, modifier keys alone wait for the key.
---------------------------------------------------------------------------
local MODIFIER_KEYS = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
	LALT = true, RALT = true, LMETA = true, RMETA = true, UNKNOWN = true,
}
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

-- The binding name of a key press with the modifiers held now.
function M.KeyChord(key)
	key = MOUSE_KEYS[key] or key
	local chord = CreateKeyChordStringUsingMetaKeyState and CreateKeyChordStringUsingMetaKeyState(key)
	if type(chord) == "string" and chord ~= "" then return chord end
	return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
		.. (IsShiftKeyDown() and "SHIFT-" or "") .. key
end

-- What the button shows for a key: the game's key name, or Not set.
function M.KeyLabel(key)
	key = ValidKey(key)
	if not key then return L["Not set"] end
	local text = GetBindingText and GetBindingText(key)
	return type(text) == "string" and text ~= "" and text or key
end

function M:SetCastKey(key)
	self.db.castKey = ValidKey(key) or ""
	if self.active then self:UpdateBindings() end
end

function M.ShowKey(canvas)
	if not (canvas and canvas.key) then return end
	if canvas.capturing then
		canvas.key:SetText(L["Press a key..."])
		canvas.hint:SetText(L["Esc cancels."])
	else
		canvas.key:SetText(M.KeyLabel(M.db and M.db.castKey))
		canvas.hint:SetText(canvas.blocked and L["Change the key out of combat."]
			or L["Click, then press the key. Shift, Ctrl and Alt work too."])
	end
	if canvas.clear then canvas.clear:SetEnabled(ValidKey(M.db and M.db.castKey) ~= nil and not canvas.capturing) end
end

function M.StopCapture(canvas)
	canvas = canvas or M.captureCanvas
	if not canvas then return end
	canvas.capturing = nil
	if M.captureCanvas == canvas then M.captureCanvas = nil end
	canvas:EnableKeyboard(false)
	canvas:SetScript("OnKeyDown", nil)
	M.ShowKey(canvas)
end

-- One key press while capturing: Esc cancels, a modifier alone waits,
-- anything else becomes the fishing key.
function M.CaptureKey(canvas, key)
	if not canvas.capturing then return end
	if InCombatLockdown() then
		canvas.blocked = true
		M.StopCapture(canvas)
		return
	end
	if MODIFIER_KEYS[key] then return end
	canvas:SetPropagateKeyboardInput(false)
	if key ~= "ESCAPE" then
		local chord = M.KeyChord(key)
		if ValidKey(chord) then M:SetCastKey(chord) end
	end
	M.StopCapture(canvas)
end

function M.StartCapture(canvas)
	canvas.blocked = InCombatLockdown() or nil
	if canvas.blocked then M.ShowKey(canvas) return end
	if M.captureCanvas and M.captureCanvas ~= canvas then M.StopCapture(M.captureCanvas) end
	M.captureCanvas = canvas
	canvas.capturing = true
	canvas:EnableKeyboard(true)
	canvas:SetPropagateKeyboardInput(false)
	canvas:SetScript("OnKeyDown", M.CaptureKey)
	M.ShowKey(canvas)
end

function M.CreateKeyRow(canvas)
	if not canvas then return end
	local Kit = E.UIKit
	local height = E.tokens.height.button
	local key = Kit.Button(canvas, "", 120, height)
	key:SetPoint("LEFT", 0, 0)
	key:RegisterForClicks("LeftButtonUp", "MiddleButtonUp", "Button4Up", "Button5Up")
	key:SetScript("OnClick", function(_, button)
		if canvas.capturing then
			if MOUSE_KEYS[button] then M.CaptureKey(canvas, button) end
			return
		end
		M.StartCapture(canvas)
	end)
	Kit.Tooltip(key, L["Fishing key"], L["Click, then press the key that casts Fishing in fishing mode. Esc cancels."])
	canvas.button = key
	canvas.key = key:GetFontString() or key
	local clear = Kit.Button(canvas, L["Clear"], 70, height, function()
		M.StopCapture(canvas)
		M:SetCastKey("")
		M.ShowKey(canvas)
	end, L["Clear"], L["No fishing key: use the Cast button on the Fishing bar."])
	clear:SetPoint("LEFT", key, "RIGHT", 6, 0)
	canvas.clear = clear
	canvas.hint = Kit.Text(canvas, E.tokens.size.label, "LEFT", "secondary")
	canvas.hint:SetPoint("LEFT", clear, "RIGHT", 10, 0)
	canvas.hint:SetPoint("RIGHT", -4, 0)
	canvas:SetScript("OnHide", function(self) self.blocked = nil M.StopCapture(self) end)
	M.ShowKey(canvas)
end

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
M.options = {
	{ type = "description", label = "One key casts Fishing and loots the bobber while it is out: one action per press. Combat clears the key. Also: /eui fish." },
	{ type = "header", label = "Fishing mode" },
	{ type = "select", key = "trigger", label = "Fishing mode is on", order = { "pole", "toggle" },
		values = { pole = "While a pole is equipped", toggle = "With the toggle key" },
		desc = "When fishing mode starts: whenever a fishing pole is in your main hand (the Fishing mode key binding pauses it), or only after you press that key binding (Key Bindings > AddOns)." },
	{ type = "preview", label = "Fishing key", height = 40, create = M.CreateKeyRow, update = M.ShowKey,
		desc = "The key that casts Fishing in fishing mode: click, then press the key. It keeps its normal job outside fishing mode. Clear: use the bar's Cast button." },
	{ type = "toggle", key = "interact", label = "Same key loots the bobber", desc = "While your bobber is out the fishing key is Interact with target, so a press on a splash loots it. For that, fishing mode turns on the game's soft interact for mouse and keyboard and lets it reach the bobber (30 yards, in front of you); your own settings come back when fishing mode ends." },
	-- Only where the game protects soft interact, so fishing mode can't turn it on.
	{ type = "description", dependsOn = "interact", hidden = function() return not (E:CVarSecure("SoftTargetInteract") and SoftInteractOn() == false) end,
		label = "Soft interact is off for mouse and keyboard, so the key misses the bobber. Only your own chat command can change this protected setting." },
	{ type = "execute", label = "Copy command", dependsOn = "interact", hidden = function() return not (E:CVarSecure("SoftTargetInteract") and SoftInteractOn() == false) end,
		desc = "Shows the chat command that turns soft interact on for mouse, keyboard and gamepad, selected for copying. Paste it in chat and press Enter.",
		func = function()
			E:ShowCopyBox(L["Soft interact"], L["Press Ctrl+C, open chat, paste the command and press Enter."], "/console SoftTargetInteract 3")
		end },
	{ type = "toggle", key = "doubleClick", label = "Double right-click casts", desc = "In fishing mode, out of combat, the second of two quick right-clicks casts Fishing." },
	{ type = "header", label = "Splash" },
	{ type = "toggle", key = "soundBoost", label = "Louder splash", desc = "Raises the sound effects and master volume while fishing, and puts your own values back when fishing mode ends." },
	{ type = "range", percent = true, key = "boostLevel", label = "Volume while fishing", min = 0.3, max = 1, step = 0.05, dependsOn = "soundBoost", desc = "Sound effects and master volume while fishing mode is on." },
	{ type = "toggle", key = "dimOthers", label = "Quieter music", dependsOn = "soundBoost", desc = "Turns music and ambience down while fishing, so the splash stands out." },
	{ type = "header", label = "Bar and log" },
	{ type = "toggle", key = "bar", label = "Fishing bar", desc = "Cast, Lure and Swap buttons with the catch count. Move it in move mode (Fishing Bar)." },
	{ type = "toggle", key = "autoHide", label = "Only in fishing mode", dependsOn = "bar", desc = "The bar shows only while fishing mode is on." },
	{ type = "toggle", key = "catchLog", label = "Catch log", desc = "Counts every fish and item per zone and spot, and your Fishing skill-ups. The bar's count shows the log in its tooltip." },
	{ type = "toggle", key = "feedFarming", label = "Start a Farming session", desc = "Starts the Farming module's session when fishing mode starts, so your catch counts there too." },
	{ type = "tab", label = "Look" },
	{ type = "range", key = "buttonSize", label = "Button size", min = 24, max = 40, step = 2, desc = "Size of the Cast, Lure and Swap buttons." },
	{ type = "toggle", key = "showCount", label = "Catch count", desc = "The catches of this session and catches per hour next to the buttons." },
	{ type = "toggle", key = "showLabels", label = "Button names", desc = "Cast, Lure and Swap under the buttons." },
	{ type = "select", key = "backdrop", label = "Background", order = { "panel", "transparent", "none" },
		values = { panel = "Panel", transparent = "See-through", none = "None" },
		desc = "The bar's background: a full panel in your art style, a see-through one, or none." },
}

E:RegisterStyles("Fishing", {
	{ key = "CompactBar", title = "Compact bar", desc = "Small buttons with the catch count.",
		settings = { buttonSize = 28, showCount = true, showLabels = false, backdrop = "transparent" } },
	{ key = "LargeButtons", title = "Large buttons", desc = "Big buttons with their names.",
		settings = { buttonSize = 40, showCount = false, showLabels = true, backdrop = "transparent" } },
	{ key = "LogPanel", title = "Log panel", desc = "Medium buttons, the catch count and the catch log on.",
		settings = { buttonSize = 32, showCount = true, showLabels = false, catchLog = true, backdrop = "panel" } },
	{ key = "ForeverBronze", title = "Forever bronze", desc = "A full panel in your art style, bronze under WoW Forever.",
		settings = { buttonSize = 32, showCount = true, showLabels = true, backdrop = "panel" } },
	{ key = "Minimal", title = "Minimal", desc = "Buttons only, no background or count.",
		settings = { buttonSize = 28, showCount = false, showLabels = false, backdrop = "none" } },
})
