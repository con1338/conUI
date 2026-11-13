-- EldoUI Cast Tooltips and Mob Abilities: three small helpers.
--
--   Cast bar tooltip  Mouse over the target or focus cast bar of EldoUI's
--                     unit frames and the spell's own tooltip shows
--                     (GameTooltip:SetSpellByID with the bar's spell). The
--                     bar keeps letting clicks through to the unit frame.
--   Ability log       A remembered list, per creature, of the spells hostile
--                     NPCs cast in front of you (target, focus and
--                     nameplates). Shown on the NPC's tooltip as
--                     "Abilities seen: Frost Nova, Fireball (+2)"; Shift
--                     lists them all.
--   Reputation tokens On items that a repeatable reputation quest asks for
--                     (Argent Dawn Valor Token, Scourgestones, Insignia and
--                     the like): "Turn in at <NPC>: +N <faction>", from
--                     EldoUI_LootData's quests (the Loot Guide's reader).
--
-- How it stays within the rules (Midnight / Forever):
--   * No combat log. The ability log listens only to the cast bar events
--     (UNIT_SPELLCAST_START and UNIT_SPELLCAST_CHANNEL_START) of units the
--     player can see. A secret spell ID, unit GUID or name is skipped, never
--     compared or stored; units whose identity the game hides
--     (C_Secrets.ShouldUnitIdentityBeSecret) are skipped first.
--   * The log only remembers what you saw: no timers, no cooldowns, no
--     "next cast" guesses. Each creature keeps at most CAP_SPELLS spells
--     and the log at most CAP_MOBS creatures; Forget clears it.
--   * The cast bar tooltip reads the bar's own spell ID; a secret one shows
--     nothing. Mouse motion only: the bar never takes a click.
--   * Nothing acts for the player.
--
-- Public API (E.MobAbilities):
--   M:Record(unit, spellID)   log one cast (what the events call)
--   M:Seen(npcID)             -> { { id, name, count }, ... } most seen first
--   M:Forget()                clear the log
--   M:TokenRows(itemID)       -> rows for the reputation token line
--   M:AttachCastbar(castbar)  hover tooltip on one cast bar
-- Written from scratch for EldoUI; no code, strings or data from other addons.
local _, E = ...
local L = E.L

local CAP_SPELLS = 16
local CAP_MOBS = 1500

local M = E:NewModule("MobAbilities", {
	title = "Cast Tooltips and Mob Abilities",
	desc = "The spell tooltip on the target and focus cast bars, a list of the abilities each mob cast in front of you, and reputation info on reputation tokens.",
	category = "Combat",
	frames = {},
	movers = {},
	blizzard = {},
	savedKeys = { "profile.modules.MobAbilities", "global.mobAbilities" },
	optionsPage = "module:MobAbilities",
	presets = { "Compact", "Detailed", "ForeverBronze", "IconsOnly", "Off" },
	reload = false,
	defaults = {
		castTooltip = true,       -- target and focus cast bars
		castFocus = true,         -- also the focus cast bar
		castAnchor = "bar",       -- "bar" (above the bar) or "cursor"
		log = true,               -- remember abilities seen
		logNameplates = true,     -- also from nameplate units
		tooltipRow = true,        -- the "Abilities seen" row
		maxNames = 3,             -- names before "(+N)"
		showIcons = false,        -- spell icons before the names
		showNames = true,         -- spell names (off with icons: icons only)
		showCounts = false,       -- how often each was seen (Shift list)
		accentLabels = false,     -- row labels in the accent color
		tokenRow = true,          -- reputation token rows
		tokenStanding = true,     -- your standing with the faction
	},
})
E.MobAbilities = M
M.CAP_SPELLS, M.CAP_MOBS = CAP_SPELLS, CAP_MOBS

local Secret = E.Secret
M.Secret = Secret

local Read = E.PlainCall
local IdentitySecret = E.IdentitySecret

local function NpcFromGUID(guid)
	if type(guid) ~= "string" or Secret(guid) then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end
M.NpcFromGUID = NpcFromGUID

-- The creature ID of a hostile NPC unit, or nil (players, friends, secrets).
function M.HostileNpc(unit)
	if type(unit) ~= "string" or Secret(unit) then return nil end
	if IdentitySecret(unit) then return nil end
	if Read(UnitIsPlayer, unit) ~= false then return nil end
	if not Read(UnitCanAttack, "player", unit) then return nil end
	return NpcFromGUID(Read(UnitGUID, unit))
end

---------------------------------------------------------------------------
-- Store: EldoUIDB.global.mobAbilities.mobs[npc] = { n = name, t = time,
-- s = { [spellID] = count } }
---------------------------------------------------------------------------
E:RegisterGlobal("mobAbilities", { mobs = {}, count = 0 }, {
	title = "Mob abilities", desc = "The abilities each mob cast in front of you.",
})

local function Store()
	local data = E:GetGlobal("mobAbilities")
	if type(data) ~= "table" then return nil end
	if type(data.mobs) ~= "table" then data.mobs = {} end
	return data
end
M.Store = Store

local function CountMobs(mobs)
	local n = 0
	for _ in pairs(mobs) do n = n + 1 end
	return n
end

-- Drop the creatures seen longest ago until the log is under the cap.
local function Prune(data)
	local count = CountMobs(data.mobs)
	if count <= CAP_MOBS then
		data.count = count
		return
	end
	local list = {}
	for npc, entry in pairs(data.mobs) do list[#list + 1] = { npc, type(entry) == "table" and entry.t or 0 } end
	table.sort(list, function(a, b) return a[2] < b[2] end)
	for index = 1, count - CAP_MOBS do data.mobs[list[index][1]] = nil end
	data.count = CAP_MOBS
end

function M:Record(unit, spellID)
	if not (self.active and self.db.log) then return false end
	if Secret(spellID) or type(spellID) ~= "number" or spellID <= 0 then return false end
	local npc = M.HostileNpc(unit)
	if not npc then return false end
	local data = Store()
	if not data then return false end
	local entry = data.mobs[npc]
	if type(entry) ~= "table" then
		entry = { s = {}, t = time() }
		data.mobs[npc] = entry
		data.count = (data.count or 0) + 1
		if data.count > CAP_MOBS then Prune(data) end
	end
	if type(entry.s) ~= "table" then entry.s = {} end
	local name = Read(UnitName, unit)
	if type(name) == "string" then entry.n = name end
	entry.t = time()
	if entry.s[spellID] then
		entry.s[spellID] = entry.s[spellID] + 1
		return true
	end
	local kinds = 0
	for _ in pairs(entry.s) do kinds = kinds + 1 end
	if kinds >= CAP_SPELLS then return false end
	entry.s[spellID] = 1
	return true
end

local function SpellName(id)
	return Read(C_Spell and C_Spell.GetSpellName, id)
end

local function SpellIcon(id)
	return Read(C_Spell and C_Spell.GetSpellTexture, id)
end

function M:Seen(npc)
	local data = Store()
	local entry = data and data.mobs[tonumber(npc) or 0]
	if type(entry) ~= "table" or type(entry.s) ~= "table" then return {} end
	local list = {}
	for id, count in pairs(entry.s) do
		local name = SpellName(id)
		if name then list[#list + 1] = { id = id, name = name, count = count } end
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.name < b.name
	end)
	return list
end

function M:Forget()
	local data = Store()
	if data then
		data.mobs = {}
		data.count = 0
	end
end

function M:LogSize()
	local data = Store()
	return data and CountMobs(data.mobs) or 0
end

---------------------------------------------------------------------------
-- Tooltip rows
---------------------------------------------------------------------------
local function Label(text)
	if M.db.accentLabels then
		local c = E.media.accentColor
		return text, c[1], c[2], c[3]
	end
	return text
end

local function Spell(item)
	local db = M.db
	local text = ""
	if db.showIcons then
		local icon = SpellIcon(item.id)
		if icon then text = ("|T%s:14:14:0:0:64:64:5:59:5:59|t"):format(tostring(icon)) end
	end
	if db.showNames or text == "" then text = text .. (text ~= "" and " " or "") .. item.name end
	return text
end

function M:AbilityRows(npc, shift)
	local list = self:Seen(npc)
	if #list == 0 then return {} end
	local rows = {}
	local label, r, g, b = Label(L["Abilities seen"])
	if shift then
		rows[#rows + 1] = { label, nil, r, g, b }
		for _, item in ipairs(list) do
			local right = self.db.showCounts and ("x%d"):format(item.count) or nil
			rows[#rows + 1] = { "  " .. Spell(item), right }
		end
		return rows
	end
	local shown = {}
	local limit = math.max(1, tonumber(self.db.maxNames) or 3)
	for index = 1, math.min(#list, limit) do shown[#shown + 1] = Spell(list[index]) end
	local text = table.concat(shown, self.db.showNames and ", " or " ")
	if #list > limit then text = text .. " " .. L["(+%d)"]:format(#list - limit) end
	rows[1] = { label, text, r, g, b }
	return rows
end

-- Reputation tokens: quests from EldoUI_LootData that ask for the item and
-- give reputation; the NPC who takes them and your standing.
function M:TokenRows(itemID)
	local LG = E.LootGuide
	itemID = tonumber(itemID)
	if not (itemID and LG and LG.HasData and LG:HasData() and LG.ItemQuests and LG.Quest) then return {} end
	local quests = LG:ItemQuests(itemID)
	if not (quests and quests.needed) then return {} end
	local rows, seen = {}, {}
	for _, questID in ipairs(quests.needed) do
		local quest = LG:Quest(questID)
		if quest and type(quest.reputation) == "table" and #quest.reputation > 0 and LG:QuestForFaction(questID, "mine") then
			local count
			for _, item in ipairs(quest.reqItems or {}) do
				if item.id == itemID then count = item.count end
			end
			local giver
			for _, place in ipairs(quest.ends or {}) do
				if place.kind == "npc" and not giver then
					local mob = LG.Mob and LG:Mob(place.id)
					giver = mob and mob.name
				end
			end
			for _, rep in ipairs(quest.reputation) do
				if type(rep.value) == "number" and rep.value > 0 then
					local key = ("%s:%d:%d"):format(tostring(giver), rep.faction, count or 0)
					if not seen[key] then
						seen[key] = true
						local faction = LG.FactionName and LG:FactionName(rep.faction) or ("#" .. rep.faction)
						local left
						if giver then
							left = L["Turn in at %s"]:format(giver)
						else
							left = L["Turn in"]
						end
						if count and count > 1 then left = left .. " " .. L["(%d)"]:format(count) end
						local right = ("+%d %s"):format(rep.value, faction)
						if self.db.tokenStanding and LG.FactionStanding then
							local live = LG:FactionStanding(rep.faction)
							if live and live.standing then right = right .. " · " .. LG:StandingName(live.standing) end
						end
						local _, r, g, b = Label(left)
						rows[#rows + 1] = { left, right, r, g, b }
					end
				end
			end
		end
	end
	return rows
end

local function Emit(rows, add)
	for _, row in ipairs(rows) do add(row[1], row[2], row[3], row[4], row[5]) end
end

if E.RegisterTooltipSection then
	E:RegisterTooltipSection("mobAbilities", {
		module = "MobAbilities",
		order = 44,
		title = "Abilities seen",
		desc = "On a hostile mob's tooltip: the abilities you saw it cast. Shift lists them all.",
		default = "always",
		unit = function(_, unit, add)
			if not (M.active and M.db.tooltipRow) then return end
			local npc = M.HostileNpc(unit)
			if not npc then return end
			Emit(M:AbilityRows(npc, IsShiftKeyDown()), add)
		end,
	})
	E:RegisterTooltipSection("repTokens", {
		module = "MobAbilities",
		order = 46,
		title = "Reputation tokens",
		desc = "On items a reputation quest asks for: where to turn them in and how much reputation they give.",
		default = "always",
		item = function(_, link, itemID, add)
			if not (M.active and M.db.tokenRow) then return end
			if Secret(link) or Secret(itemID) then return end
			itemID = tonumber(itemID) or (type(link) == "string" and tonumber(link:match("item:(%d+)")))
			if not itemID then return end
			Emit(M:TokenRows(itemID), add)
		end,
	})
end

---------------------------------------------------------------------------
-- Cast bar tooltip
---------------------------------------------------------------------------
local attached = setmetatable({}, { __mode = "k" })
local barUnit = setmetatable({}, { __mode = "k" }) -- castbar -> "target" / "focus" (the frame it belongs to)

local function CastSpell(castbar)
	if not castbar:IsShown() then return nil end
	local id = castbar.spellID
	if Secret(id) or type(id) ~= "number" or id <= 0 then return nil end
	return id
end
M.CastSpell = CastSpell

local function Wanted(castbar)
	if not (M.active and M.db.castTooltip) then return false end
	local unit = castbar.unit
	if Secret(unit) or type(unit) ~= "string" then unit = barUnit[castbar] end
	if unit == "target" then return true end
	if unit == "focus" then return M.db.castFocus and true or false end
	return false
end

local function OnEnter(castbar)
	if not Wanted(castbar) then return end
	local id = CastSpell(castbar)
	if not id then return end
	if M.db.castAnchor == "cursor" then
		GameTooltip:SetOwner(castbar, "ANCHOR_CURSOR")
	else
		GameTooltip:SetOwner(castbar, "ANCHOR_TOP")
	end
	local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, id)
	if ok then
		M.tipOwner = castbar
		GameTooltip:Show()
	else
		GameTooltip:Hide()
	end
end

local function OnLeave(castbar)
	if M.tipOwner == castbar then
		M.tipOwner = nil
		GameTooltip:Hide()
	end
end

-- Mouse motion only, so a click still reaches the unit frame under it.
local function SetHover(castbar, on)
	E:RunOutOfCombat(function()
		-- EnableMouse(false) turns clicks and motion off (a hooked OnEnter
		-- turns the mouse on), then motion alone comes back.
		if castbar.EnableMouse then pcall(castbar.EnableMouse, castbar, false) end
		if castbar.EnableMouseMotion then pcall(castbar.EnableMouseMotion, castbar, on and true or false) end
	end)
end

function M:AttachCastbar(castbar, unit)
	if type(castbar) ~= "table" or not castbar.HookScript then return end
	if unit then barUnit[castbar] = unit end
	if not attached[castbar] then
		attached[castbar] = true
		pcall(castbar.HookScript, castbar, "OnEnter", OnEnter)
		pcall(castbar.HookScript, castbar, "OnLeave", OnLeave)
	end
	SetHover(castbar, Wanted(castbar))
end

function M:UpdateCastbars()
	local UF = E.modules.UnitFrames
	if not (UF and UF.frames) then return end
	for _, key in ipairs({ "target", "focus" }) do
		local frame = UF.frames[key]
		if frame and frame.castbar then self:AttachCastbar(frame.castbar, key) end
	end
end

local function CastHook(event, castbar, unit)
	if event == "layout" or event == "start" then
		if (unit == "target" or unit == "focus") and not attached[castbar] then M:AttachCastbar(castbar, unit) end
	elseif (event == "stop" or event == "fail" or event == "interrupted") and M.tipOwner == castbar then
		OnLeave(castbar)
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function LoggedUnit(unit)
	if type(unit) ~= "string" or Secret(unit) then return false end
	if unit == "target" or unit == "focus" then return true end
	return M.db.logNameplates and unit:find("^nameplate%d+$") ~= nil
end

local function OnCast(_, _, unit, _, spellID)
	if LoggedUnit(unit) then M:Record(unit, spellID) end
end

function M:OnEnable()
	self:RegisterEvent("UNIT_SPELLCAST_START", OnCast)
	self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", OnCast)
	local UF = E.modules.UnitFrames
	if UF and UF.CastX and UF.CastX.RegisterCastHook and not self.castHook then
		self.castHook = UF.CastX.RegisterCastHook(CastHook)
	end
	self:UpdateCastbars()
end

function M:OnDisable()
	self:UnregisterEvent("UNIT_SPELLCAST_START")
	self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")
	local UF = E.modules.UnitFrames
	if self.castHook and UF and UF.CastX then
		UF.CastX.UnregisterCastHook(self.castHook)
		self.castHook = nil
	end
	for castbar in pairs(attached) do SetHover(castbar, false) end
	if self.tipOwner then OnLeave(self.tipOwner) end
end

function M:OnProfileChanged()
	if self.active then self:UpdateCastbars() end
end

E:RegisterDiagnostics("MobAbilities", function()
	if not M.initialized then return {} end
	return { ("   Mob abilities: %s, %d creatures logged"):format(M.active and "on" or "off", M:LogSize()) } -- no-L
end)
