-- EldoUI character store (E.Characters, also EldoUI.Characters for plugins).
--
-- One account-wide record per character, written by the character itself
-- whenever it logs in, logs out or the game reports a change. It records
-- whether or not the Bags module is on, so the Alts window, the Gold
-- datatext and the item counts in tooltips also work next to another bag
-- addon.
--
-- Records live in EldoUIDB.inventory[charKey] (the Bags cache that already
-- holds every character's items, so nothing the player has is moved) and
-- carry `realmKey` (E:RealmKey(): the ruleset on Forever, the realm
-- elsewhere), which is what "this realm" means in every scope.
--
--   local C = E.Characters
--   C:Me()                     the current character's record
--   C:Get(key)                 a record or nil
--   C:Keys(scope)              keys in display order (current first);
--                              scope: "char", "realm", "faction", "account"
--   C:Forget(key, settings)    removes a character from every table
--                              (refuses the current one); settings = true
--                              also drops its EldoUI settings; its journal
--                              leaves after one backup the Saved data page
--                              puts back or removes
--   C:Recording()              the Alts-window parts are recorded (the
--                              Characters module is on, or My Adventure
--                              records through it; character not skipped)
--   C:IsSkipped(key), C:SetSkipped(key, on)   "Don't record this
--                              character", account-wide per character
--   C:Guilds(), C:GuildKeys(scope)
--   C:RestedEstimate(record)   rested XP now, and whether it is an estimate
--   C:RestCap(record), C:RestRate(record)   the rested cap and rate (of a
--                              level), learned per character
--   C:Played(record)           total played seconds now (estimate offline)
--   C.callbacks                CallbackHandler: "Updated"(key, section),
--                              "Forgotten"(key)
--   C:RegisterCallback("Updated", fn) / C:UnregisterCallback(...)
--
-- Record fields (all optional, written lazily):
--   name, realm, realmKey, class, faction, level, race, sex, guid, money,
--   seen (last login), loggedOut (nil while online), updated, bankUpdated,
--   mailUpdated, played, playedLevel, playedAt (server time of the read),
--   xp, xpMax, rested, resting, restRate, restCap (learned, C:LearnRest),
--   xpOff, hearth, zone, subZone,
--   guild = { name, rank, rankIndex }, gear = { ilvl, equipped },
--   durability = { pct, low }, slots = { bags, bagsFree, bank, bankFree },
--   bags, bank, mail, equip, bagsLayout, bankLayout, counts, currency, watched
--   (the Bags item cache), mailMeta = { { sender, subject, expires, money,
--   cod, items, returned } }, profs = { [name] = { rank, max, icon, line,
--   recipes = "<packed ids>", scanned } }, cooldowns = { [recipeID or
--   "item:<id>"] = { readyAt, name, prof } }, lockouts = { [id] = { name, resetAt, extended,
--   raid, done, total, difficulty } }, levels = { [level] = { at, zone,
--   played, took, kills, quests } }, levelNow = { kills, quests, since,
--   mobs = { [creature] = XP kills } },
--   quests = { log = { { id, title, level, done, daily } }, history =
--   "<packed ids>", historyAt, daily = { [id] = at } }, reps = { [factionID]
--   = { name, reaction, value, min, max, header } }, auctions = { visited,
--   list = { { link, count, bid, buyout, endsAt } }, bids = { ... } },
--   calendar = { { at, title, kind, invite } }, stats = { at, ... }.
--
-- Read-only scanning: nothing here changes what the game shows. It never
-- reads mail bodies (GetInboxText marks mail read), never selects a quest
-- or expands a quest, reputation or currency header, never changes the
-- calendar month and never sends anything to other players.
local _, E = ...
local L = E.L

local C = {}
E.Characters = C

local CBH = LibStub and LibStub("CallbackHandler-1.0", true)
if CBH then C.callbacks = CBH:New(C) end

-- issecretvalue first: comparing a secret value (even with nil) errors.
local function IsSecret(value)
	return issecretvalue and issecretvalue(value) and true or false
end

-- The answers of a call, each secret one as nil; nothing when it fails.
local Read = E.PlainCallEach

local function Plain(value)
	if IsSecret(value) then return nil end
	return value
end

local function Now()
	return GetServerTime and GetServerTime() or time()
end
C.Now = Now

---------------------------------------------------------------------------
-- Settings (the Characters module's page)
--
-- The store always records what Bags, the Gold datatext and Mail need
-- (bags, bank, gear, mail, gold, currencies, guild bank). Everything only
-- the Alts window shows (quests, reputation, professions and recipes,
-- lockouts, calendar, stats, auctions, the level log and played time) is
-- recorded only while the Characters module is on, and the played-time
-- request is never sent without it.
---------------------------------------------------------------------------
local function CharactersModule()
	local module = E.modules and E.modules.Characters
	return module and module.active and module or nil
end

-- The Characters module is on (and not standing back for another addon).
function C:Full()
	return CharactersModule() ~= nil
end

local function Opt(key)
	local module = CharactersModule()
	return module and module.db and module.db[key] and true or false
end

-- Parts only the Alts window reads: not scanned while Characters is off.
local CHARACTERS_ONLY = {
	durability = true, lockouts = true, professions = true, recipes = true, itemCooldowns = true, quests = true,
	questHistory = true, reps = true, auctions = true, bids = true, calendar = true, stats = true,
}
C.CHARACTERS_ONLY = CHARACTERS_ONLY

-- "Don't record this character": kept account-wide per character in
-- E.global.characters.skip (never in a profile). A choice made in an older
-- version (the Characters module's profile table) moves there once.
function C:SkipList()
	local global = E.global
	if type(global) ~= "table" then return nil end
	local data = E.GetGlobal and E:GetGlobal("characters")
	if type(data) ~= "table" then
		global.characters = type(global.characters) == "table" and global.characters or {}
		data = global.characters
	end
	data.skip = type(data.skip) == "table" and data.skip or {}
	local module = E.modules and E.modules.Characters
	local old = module and module.db and rawget(module.db, "skip")
	if type(old) == "table" then
		for key, value in pairs(old) do
			if rawget(old, key) ~= nil then
				if value == true then data.skip[key] = true end
				rawset(old, key, nil)
			end
		end
	end
	return data.skip
end

-- The character asked not to be listed (Characters page, per character).
function C:IsSkipped(key)
	local skip = self:SkipList()
	return type(skip) == "table" and skip[key or E.charKey] == true
end

function C:SetSkipped(key, on)
	local skip = self:SkipList()
	if type(skip) ~= "table" or type(key) ~= "string" then return end
	skip[key] = on and true or nil
	if self.ForgetKeys then self:ForgetKeys() end
	if self.callbacks then self.callbacks:Fire("Updated", key, "skip") end
end

-- My Adventure records through these stores: with its "Use the
-- Characters and Instances records" option on, the Alts-window parts are
-- recorded while the journal writes, even with the Characters window off.
-- The journal never keeps second copies of them.
function C:JournalRecording()
	local J = E.Journal
	local module = E.modules and E.modules.Adventure
	if not (J and J.Recording and module and module.db) then return false end
	if module.db.useStores == false then return false end
	return J:Recording() and true or false
end

-- The Alts-window parts are recorded for this character: Characters is on
-- (or the journal records through it) and the character didn't ask to be
-- left out.
function C:Recording()
	return (self:Full() or self:JournalRecording()) and not self:IsSkipped()
end

local function Allowed(part)
	return not CHARACTERS_ONLY[part] or C:Recording()
end

---------------------------------------------------------------------------
-- Item strings (shared with Bags): "item:1234:..;count"
---------------------------------------------------------------------------
local function ShortItem(link)
	if type(link) ~= "string" or IsSecret(link) then return end
	local short = link:match("|H(item:[^|]+)|h") or link:match("^(item:[%-%d:]+)")
	if not short then return end
	return (short:gsub(":+$", ""))
end
C.ShortItem = ShortItem

local function ItemIDOf(short)
	return short and tonumber(short:match("^item:(%d+)"))
end
C.ItemIDOf = ItemIDOf

local function Encode(short, count)
	if count and count > 1 then return short .. ";" .. count end
	return short
end
C.Encode = Encode

local function Decode(value)
	if type(value) ~= "string" then return end
	local short, count = value:match("^(.-);(%d+)$")
	if short then return short, tonumber(count) end
	return value, 1
end
C.Decode = Decode

-- Sorted number lists packed as base-36 deltas ("1a,3,f"): quest history
-- and recipe lists stay small in the saved file.
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function ToBase36(n)
	if n == 0 then return "0" end
	local out = {}
	while n > 0 do
		local d = n % 36
		table.insert(out, 1, DIGITS:sub(d + 1, d + 1))
		n = math.floor(n / 36)
	end
	return table.concat(out)
end

function C.PackIDs(list)
	local ids = {}
	for _, id in ipairs(list or {}) do
		if type(id) == "number" and id >= 0 then ids[#ids + 1] = math.floor(id) end
	end
	table.sort(ids)
	local parts, last = {}, 0
	for _, id in ipairs(ids) do
		if id ~= last or #parts == 0 then
			parts[#parts + 1] = ToBase36(id - last)
			last = id
		end
	end
	return table.concat(parts, ",")
end

function C.UnpackIDs(text)
	local set = {}
	if type(text) ~= "string" or text == "" then return set end
	local last = 0
	for part in text:gmatch("[^,]+") do
		local delta = tonumber(part, 36)
		if delta then
			last = last + delta
			set[last] = true
		end
	end
	return set
end

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------
function C:All()
	EldoUIDB.inventory = type(EldoUIDB.inventory) == "table" and EldoUIDB.inventory or {}
	return EldoUIDB.inventory
end

function C:Get(key)
	if type(EldoUIDB) ~= "table" or key == nil then return nil end
	local record = self:All()[key]
	return type(record) == "table" and record or nil
end

-- The current character's record, with its identity refreshed.
function C:Me()
	local all = self:All()
	local me = all[E.charKey]
	if type(me) ~= "table" then
		me = {}
		all[E.charKey] = me
	end
	local _, class = UnitClass("player")
	me.name = E:PlayerName()
	me.realm = GetRealmName()
	me.realmKey = E:RealmKey()
	me.class = class or me.class
	me.faction = Plain(UnitFactionGroup("player")) or me.faction
	-- A character's level never goes down: a lower answer (a read while
	-- leaving the world, or a scaled level) leaves the saved level alone.
	-- A record that names another GUID takes the level as read.
	local level = Plain(UnitLevel("player"))
	if type(level) == "number" and level > 0 then
		local guid = Plain(Read(UnitGUID, "player"))
		if type(me.level) ~= "number" or level >= me.level or (guid and me.guid and guid ~= me.guid) then me.level = level end
	end
	return me
end

-- Lazily created sub-table of a record.
function C:Section(key, name)
	local record = key == E.charKey and self:Me() or self:Get(key)
	if not record then return nil end
	if type(record[name]) ~= "table" then record[name] = {} end
	return record[name]
end

local function Fire(section, key)
	-- A new name, level or realm can change a list's order.
	if section == "login" or section == "basics" then C:ForgetKeys() end
	if C.callbacks then C.callbacks:Fire("Updated", key or E.charKey, section) end
end
C.FireUpdated = function(_, section, key) Fire(section, key) end

local function RealmOf(record)
	return record.realmKey or record.realm
end

-- Same "realm" as the current character (E:RealmKey: the ruleset on
-- Forever). A record saved before realmKey existed only knows its realm
-- name: it matches when that is the current realm.
local function SameRealm(record, me)
	if record.realmKey and me.realmKey then return record.realmKey == me.realmKey end
	return record.realm ~= nil and record.realm == me.realm
end
C.SameRealm = SameRealm

-- Records from before realmKey (older Bags caches) on this realm get the
-- current realm key once, so "This realm" scopes, the Mail address book,
-- the Gold datatext and recipe owners list them again.
function C:BackfillRealmKeys()
	local realm, realmKey = GetRealmName(), E:RealmKey()
	if type(realm) ~= "string" or realmKey == nil then return 0 end
	local filled = 0
	for _, record in pairs(self:All()) do
		if type(record) == "table" and record.realmKey == nil and record.realm == realm then
			record.realmKey = realmKey
			filled = filled + 1
		end
	end
	for _, guild in pairs(type(EldoUIDB.guildBanks) == "table" and EldoUIDB.guildBanks or {}) do
		if type(guild) == "table" and guild.realmKey == nil and guild.realm == realm then guild.realmKey = realmKey end
	end
	return filled
end

-- Keys in display order: the current character first, then by realm and
-- name. scope: "char", "realm" (same ruleset on Forever), "faction"
-- (same realm and faction) or "account". Characters that asked not to be
-- recorded are left out unless withSkipped (Forget lists, saved size).
-- The sorted lists are kept per scope and handed out as copies, so an
-- item tooltip redraw does not walk, filter and sort every record again.
-- A list is used again while the same records (same keys, same tables),
-- the same current character and skip list and no new identity or skip
-- change are there.
local keysCache = { version = 0, lists = {} }
C.keysCache = keysCache
function C:ForgetKeys()
	keysCache.version = keysCache.version + 1
	wipe(keysCache.lists)
end

local function KeysStillValid(entry, all, me, skip)
	if entry.all ~= all or entry.charKey ~= E.charKey or entry.version ~= keysCache.version or entry.skip ~= skip
		or entry.realmKey ~= me.realmKey or entry.realm ~= me.realm or entry.faction ~= me.faction then
		return false
	end
	local count = 0
	for key, record in pairs(all) do
		if type(record) == "table" then
			if entry.records[key] ~= record then return false end
			count = count + 1
		end
	end
	return count == entry.count
end

local function CopyKeys(list)
	local copy = {}
	for index = 1, #list do copy[index] = list[index] end
	return copy
end

function C:Keys(scope, withSkipped)
	local me = self:Me()
	local all, skip = self:All(), self:SkipList()
	local cacheKey = tostring(scope) .. (withSkipped and "+" or "")
	local entry = keysCache.lists[cacheKey]
	if entry and KeysStillValid(entry, all, me, skip) then
		keysCache.hits = (keysCache.hits or 0) + 1
		return CopyKeys(entry.list)
	end
	keysCache.builds = (keysCache.builds or 0) + 1
	local list = {}
	for key, record in pairs(self:All()) do
		if type(record) == "table" then
			local keep = true
			if key ~= E.charKey then
				if scope == "char" then
					keep = false
				elseif scope == "realm" then
					keep = SameRealm(record, me)
				elseif scope == "faction" then
					keep = SameRealm(record, me) and record.faction == me.faction
				end
				if keep and not withSkipped and self:IsSkipped(key) then keep = false end
			end
			if keep then list[#list + 1] = key end
		end
	end
	table.sort(list, function(a, b)
		if a == E.charKey then return true end
		if b == E.charKey then return false end
		local ra, rb = all[a], all[b]
		if RealmOf(ra) ~= RealmOf(rb) then return tostring(RealmOf(ra) or "") < tostring(RealmOf(rb) or "") end
		return tostring(ra.name or a) < tostring(rb.name or b)
	end)
	local records, count = {}, 0
	for key, record in pairs(all) do
		if type(record) == "table" then
			records[key] = record
			count = count + 1
		end
	end
	keysCache.lists[cacheKey] = { list = list, all = all, charKey = E.charKey, version = keysCache.version, skip = skip,
		realmKey = me.realmKey, realm = me.realm, faction = me.faction, records = records, count = count }
	return CopyKeys(list)
end

-- A character by name (and realm), for mail recipients.
local function NormalRealm(realm)
	return (tostring(realm or "")):gsub("[%s%-']", ""):lower()
end

function C:FindCharacter(name, realm)
	if type(name) ~= "string" then return end
	name = name:lower()
	realm = NormalRealm(realm or GetRealmName())
	for key, record in pairs(self:All()) do
		if type(record) == "table" and type(record.name) == "string" and record.name:lower() == name
			and (NormalRealm(record.realm) == realm or NormalRealm(record.realmKey) == realm) then
			return key, record
		end
	end
end

---------------------------------------------------------------------------
-- Rested XP and played time (estimates for characters that are offline)
---------------------------------------------------------------------------
local REST_PER_8H = 0.05   -- of a level, while resting (the game's published rate)
local REST_CAP = 1.5       -- the bar holds one and a half levels

-- WoW: Forever's Legacy talent Well Rested raises both, by amounts the
-- client does not expose. Each character learns its own from what the
-- game gave it while it was away (C:LearnRest at login): restRate (of a
-- level per 8 hours in a rested area) and restCap (of a level).
function C:RestCap(record)
	local cap = record and tonumber(record.restCap)
	return cap and cap > REST_CAP and cap or REST_CAP
end

function C:RestRate(record)
	local rate = record and tonumber(record.restRate)
	return rate and rate > REST_PER_8H and rate or REST_PER_8H
end

-- At login, before the scan: what the record said at logout.
local function RestBefore(me)
	return { rested = me.rested, xpMax = me.xpMax, level = me.level, resting = me.resting, at = me.loggedOut }
end

-- After the scan: the rested XP the game gave while the character was
-- away, against the record at logout. A bar that grew less than the plain
-- rate would give hit its top: that value is the cap. One that grew while
-- still below 150 % shows the rate. Only a logout in a rested area, at the
-- same level, an hour or more ago counts.
function C:LearnRest(me, before)
	local now, xpMax = me.rested, me.xpMax
	if type(now) ~= "number" or type(xpMax) ~= "number" or xpMax <= 0 then return end
	local ratio = now / xpMax
	-- More than the cap known so far: the cap is at least this.
	if ratio > self:RestCap(me) + 0.001 then me.restCap = math.floor(ratio * 1000 + 0.5) / 1000 end
	if not (before and before.at and before.resting and type(before.rested) == "number")
		or before.xpMax ~= xpMax or before.level ~= me.level then return end
	local periods = (Now() - before.at) / 28800
	if periods < 0.125 then return end
	local gained = (now - before.rested) / xpMax
	if gained < REST_PER_8H * periods * 0.9 then
		if ratio >= REST_CAP - 0.005 then me.restCap = math.floor(ratio * 1000 + 0.5) / 1000 end
	elseif ratio < REST_CAP - 0.01 then
		me.restRate = math.floor(gained / periods * 1000 + 0.5) / 1000
	end
end
C.RestBefore = RestBefore

local function MaxLevel()
	local level = Read(GetMaxLevelForPlayerExpansion) or Read(GetMaxPlayerLevel)
	return type(level) == "number" and level > 0 and level or 60
end
C.MaxLevel = MaxLevel

-- Rested XP now: the recorded value for the current character, an estimate
-- since logout for the others. Returns rested, xpMax, estimated.
function C:RestedEstimate(record)
	if not record or (record.level or 0) >= MaxLevel() or record.xpOff then return 0, record and record.xpMax, false end
	local rested, xpMax = record.rested or 0, record.xpMax
	if not xpMax or xpMax <= 0 then return rested, xpMax, false end
	if record == self:Get(E.charKey) and not record.loggedOut then return rested, xpMax, false end
	local since = record.loggedOut or record.seen
	if not since then return rested, xpMax, false end
	local elapsed = math.max(Now() - since, 0)
	local rate = self:RestRate(record) * (record.resting and 1 or 0.25)
	local value = math.min(rested + xpMax * rate * elapsed / 28800, xpMax * self:RestCap(record))
	return value, xpMax, true
end

-- Seconds until the rested bar is full (estimate), or nil.
function C:FullyRestedIn(record)
	local rested, xpMax = self:RestedEstimate(record)
	if not xpMax or xpMax <= 0 or (record.level or 0) >= MaxLevel() then return nil end
	local missing = xpMax * self:RestCap(record) - rested
	if missing <= 0 then return 0 end
	local rate = self:RestRate(record) * (record.resting and 1 or 0.25)
	return math.floor(missing / (xpMax * rate) * 28800)
end

-- Total played seconds now: the last read plus the time since (online),
-- or the last read (offline).
function C:Played(record)
	if not record or not record.played then return nil end
	if record == self:Get(E.charKey) and not record.loggedOut and record.playedAt then
		return record.played + math.max(Now() - record.playedAt, 0)
	end
	return record.played
end

---------------------------------------------------------------------------
-- Scanners
---------------------------------------------------------------------------
local Scan = {}
C.Scan = Scan

local function NumSlots(bag)
	if bag == nil then return 0 end
	local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
	return ok and type(slots) == "number" and slots or 0
end

local KEYRING = Enum.BagIndex and Enum.BagIndex.Keyring
local REAGENT = Enum.BagIndex and Enum.BagIndex.ReagentBag
local BANK_CHARACTER = Enum.BankType and Enum.BankType.Character

local function BagIDs()
	local ids = {}
	for bag = 0, (NUM_BAG_SLOTS or 4) do ids[#ids + 1] = bag end
	if REAGENT and NumSlots(REAGENT) > 0 then ids[#ids + 1] = REAGENT end
	if KEYRING and NumSlots(KEYRING) > 0 then ids[#ids + 1] = KEYRING end
	return ids
end
C.BagIDs = BagIDs

local function TabIDs(bankType)
	local ids = {}
	if not (C_Bank and C_Bank.FetchPurchasedBankTabData and bankType) then return ids end
	if C_Bank.CanViewBank and not Read(C_Bank.CanViewBank, bankType) then return ids end
	local tabs = Read(C_Bank.FetchPurchasedBankTabData, bankType)
	if type(tabs) == "table" then
		for _, tab in ipairs(tabs) do ids[#ids + 1] = tab.ID end
	end
	return ids
end

-- The character's own bank containers (never the shared warband tabs).
local function BankBagIDs()
	local ids = TabIDs(BANK_CHARACTER)
	if #ids > 0 then return ids end
	local bank = (Enum.BagIndex and Enum.BagIndex.Bank) or rawget(_G, "BANK_CONTAINER")
	if bank then
		ids[1] = bank
		local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
		for bag = first, first + (rawget(_G, "NUM_BANKBAGSLOTS") or 0) - 1 do ids[#ids + 1] = bag end
	end
	return ids
end

local LOCATIONS = { "bags", "bank", "mail", "equip" }
C.LOCATIONS = LOCATIONS

function C:Recount(record)
	local counts = {}
	for index, location in ipairs(LOCATIONS) do
		for _, value in ipairs(record[location] or {}) do
			local short, count = Decode(value)
			local id = ItemIDOf(short)
			if id then
				local entry = counts[id]
				if not entry then
					entry = { 0, 0, 0, 0 }
					counts[id] = entry
				end
				entry[index] = entry[index] + count
			end
		end
	end
	record.counts = counts
end

local function ScanContainers(ids)
	local list, layout, free = {}, {}, 0
	for _, bag in ipairs(ids) do
		local size = NumSlots(bag)
		for slot = 1, size do
			local info = Read(C_Container.GetContainerItemInfo, bag, slot)
			local short = type(info) == "table" and ShortItem(info.hyperlink)
			list[#list + 1] = short and Encode(short, Plain(info.stackCount)) or false
			if not short then free = free + 1 end
		end
		layout[#layout + 1] = { bag, size }
	end
	return list, layout, free
end

local bankOpen = false

-- Bags named by BAG_UPDATE since the last bag scan.
C.changedBags = {}

-- One slot's change in the bags column of record.counts: the old item
-- out, the new one in, and an item with nothing left anywhere dropped, as
-- a full recount would leave it.
local function AddToBags(counts, value, sign)
	local short, count = Decode(value)
	local id = ItemIDOf(short)
	if not id then return end
	local entry = counts[id]
	if not entry then
		entry = { 0, 0, 0, 0 }
		counts[id] = entry
	end
	entry[1] = entry[1] + sign * count
	if entry[1] == 0 and entry[2] == 0 and entry[3] == 0 and entry[4] == 0 then counts[id] = nil end
end
local function CountSlot(counts, old, new)
	AddToBags(counts, old, -1)
	AddToBags(counts, new, 1)
end

-- Only the bags BAG_UPDATE named are read again while the bag layout is
-- the same; anything else (a new bag, the first scan) reads every bag.
-- True when the partial read was enough.
local function ScanChangedBags(me, ids)
	local changed, layout, list = C.changedBags, me.bagsLayout, me.bags
	if not (next(changed) and type(layout) == "table" and type(list) == "table" and type(me.counts) == "table")
		or #layout ~= #ids then
		return false
	end
	for index, bag in ipairs(ids) do
		local entry = layout[index]
		if type(entry) ~= "table" or entry[1] ~= bag or entry[2] ~= NumSlots(bag) then return false end
	end
	local offset, free = 0, me.slots and me.slots.bagsFree
	if type(free) ~= "number" then return false end
	for _, entry in ipairs(layout) do
		local bag, size = entry[1], entry[2]
		if changed[bag] then
			for slot = 1, size do
				local info = Read(C_Container.GetContainerItemInfo, bag, slot)
				local short = type(info) == "table" and ShortItem(info.hyperlink)
				local value = short and Encode(short, Plain(info.stackCount)) or false
				local old = list[offset + slot]
				if old ~= value then
					CountSlot(me.counts, old, value)
					if old and not value then free = free + 1 elseif value and not old then free = free - 1 end
					list[offset + slot] = value
				end
			end
		end
		offset = offset + size
	end
	me.slots.bagsFree = free
	return true
end

function Scan.bags()
	local me = C:Me()
	local ids = BagIDs()
	local partial = ScanChangedBags(me, ids)
	wipe(C.changedBags)
	if not partial then
		local list, layout, free = ScanContainers(ids)
		me.bags, me.bagsLayout = list, layout
		me.slots = me.slots or {}
		me.slots.bags, me.slots.bagsFree = #list, free
		C:Recount(me)
	end
	me.updated = Now()
end

function Scan.bank()
	if not bankOpen then return end
	local me = C:Me()
	local list, layout, free = ScanContainers(BankBagIDs())
	me.bank, me.bankLayout = list, layout
	me.slots = me.slots or {}
	me.slots.bank, me.slots.bankFree = #list, free
	me.bankUpdated = Now()
	C:Recount(me)
end

-- Equipped gear, its average item level and the durability summary.
function Scan.equip()
	local me = C:Me()
	local list = {}
	for slot = 1, 19 do
		local short = ShortItem(Read(GetInventoryItemLink, "player", slot))
		list[slot] = short or false
	end
	me.equip = list
	local overall, equipped = Read(GetAverageItemLevel)
	if type(overall) == "number" and overall > 0 then
		me.gear = { ilvl = math.floor(overall * 10 + 0.5) / 10, equipped = type(equipped) == "number" and math.floor(equipped * 10 + 0.5) / 10 or nil }
	end
	C:Recount(me)
end

function Scan.durability()
	local me = C:Me()
	local total, max, low = 0, 0, 100
	for slot = 1, 19 do
		local current, maximum = Read(GetInventoryItemDurability, slot)
		if type(current) == "number" and type(maximum) == "number" and maximum > 0 then
			total, max = total + current, max + maximum
			low = math.min(low, math.floor(current / maximum * 100))
		end
	end
	if max > 0 then me.durability = { pct = math.floor(total / max * 100), low = low, at = Now() } end
end

-- Mail: attached items (Bags cache) and the header of every mail: sender,
-- subject, days left, money, COD. Never the body: reading it marks a mail
-- as read.
function Scan.mail()
	local me = C:Me()
	local list, meta = {}, {}
	local now = Now()
	for index = 1, (Read(GetInboxNumItems) or 0) do
		local items = 0
		for attachment = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
			local short = ShortItem(Read(GetInboxItemLink, index, attachment))
			if short then
				local count = select(4, Read(GetInboxItem, index, attachment)) or 1
				list[#list + 1] = Encode(short, Plain(count))
				items = items + 1
			end
		end
		local _, _, sender, subject, money, cod, daysLeft, _, _, returned = Read(GetInboxHeaderInfo, index)
		if type(daysLeft) == "number" then
			meta[#meta + 1] = {
				sender = Plain(sender), subject = Plain(subject), money = Plain(money) or 0, cod = Plain(cod) or 0,
				expires = now + math.floor(daysLeft * 86400), items = items, returned = returned and true or nil,
			}
		end
	end
	me.mail = list
	me.mailMeta = meta
	me.mailUpdated = now
	C:Recount(me)
end

-- A read of 0 replaces saved gold only for a money change while the
-- character is in the world: a scan at login, or a read while leaving the
-- world, can answer 0 before or after the game has the amount.
local inWorld = true
function Scan.money(changed)
	local money = Plain(GetMoney())
	if type(money) ~= "number" then return end
	local me = C:Me()
	if money == 0 and type(me.money) == "number" and me.money > 0 and not (changed and inWorld) then return end
	me.money = money
end

-- Currencies the player can see in the currency list (collapsed headers
-- hide theirs until opened once; never expanded here) and the ones
-- tracked in the backpack.
function Scan.currency()
	if not C_CurrencyInfo then return end
	local me = C:Me()
	if C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListLink then
		local list = {}
		for index = 1, (Read(C_CurrencyInfo.GetCurrencyListSize) or 0) do
			local info = Read(C_CurrencyInfo.GetCurrencyListInfo, index)
			if type(info) == "table" and not info.isHeader and (Plain(info.quantity) or 0) > 0 and not info.isAccountWide then
				local link = Read(C_CurrencyInfo.GetCurrencyListLink, index)
				local id = type(link) == "string" and not IsSecret(link) and tonumber(link:match("currency:(%d+)"))
				if id then list[id] = info.quantity end
			end
		end
		me.currency = list
	end
	if C_CurrencyInfo.GetBackpackCurrencyInfo then
		local watched = {}
		for index = 1, 10 do
			local info = Read(C_CurrencyInfo.GetBackpackCurrencyInfo, index)
			if type(info) ~= "table" then break end
			watched[#watched + 1] = { id = info.currencyTypesID, quantity = Plain(info.quantity), icon = info.iconFileID }
		end
		me.watched = watched
	end
end

-- Level, XP, rested, zone, hearth and guild.
function Scan.basics()
	local me = C:Me()
	local race, raceFile = Read(UnitRace, "player")
	me.race, me.raceFile = Plain(race) or me.race, Plain(raceFile) or me.raceFile
	me.sex = Plain(Read(UnitSex, "player")) or me.sex
	me.guid = Plain(Read(UnitGUID, "player")) or me.guid
	local xp, xpMax = Plain(Read(UnitXP, "player")), Plain(Read(UnitXPMax, "player"))
	if type(xp) == "number" then me.xp = xp end
	if type(xpMax) == "number" then me.xpMax = xpMax end
	me.rested = Plain(Read(GetXPExhaustion)) or 0
	me.resting = Read(IsResting) and true or false
	me.xpOff = Read(IsXPUserDisabled) and true or nil
	me.hearth = Plain(Read(GetBindLocation)) or me.hearth
	local zone = Plain(Read(GetRealZoneText)) or Plain(Read(GetZoneText))
	if type(zone) == "string" and zone ~= "" then me.zone = zone end
	me.subZone = Plain(Read(GetSubZoneText))
	if Read(IsInGuild) then
		local name, rankName, rankIndex = Read(GetGuildInfo, "player")
		if type(name) == "string" and not IsSecret(name) then
			me.guild = { name = name, rank = Plain(rankName), rankIndex = Plain(rankIndex) }
		end
	elseif IsInGuild then
		me.guild = nil
	end
	-- Hunters: ammo in the ammo slot and a snapshot of the pet.
	if me.class == "HUNTER" then
		local ammo = Plain(Read(GetInventoryItemCount, "player", INVSLOT_AMMO or 0))
		if type(ammo) == "number" then me.ammo = ammo end
		if Read(UnitExists, "pet") then
			local name = Plain(Read(UnitName, "pet"))
			if type(name) == "string" then
				me.pet = { name = name, family = Plain(Read(UnitCreatureFamily, "pet")), level = Plain(Read(UnitLevel, "pet")) }
			end
		end
	end
	Scan.money()
end

-- Saved instances (raid and dungeon lockouts) with their absolute reset
-- time. The game answers RequestRaidInfo with UPDATE_INSTANCE_INFO.
function Scan.lockouts()
	if not (GetNumSavedInstances and GetSavedInstanceInfo) then return end
	local me = C:Me()
	local now = Now()
	local list = {}
	for index = 1, (Read(GetNumSavedInstances) or 0) do
		local name, _, reset, difficulty, locked, extended, _, isRaid, _, difficultyName, numEncounters, encounterProgress, _, instanceID =
			Read(GetSavedInstanceInfo, index)
		if type(name) == "string" and not IsSecret(name) and type(reset) == "number" and reset > 0 and (locked or extended) then
			local id = ("%s:%s"):format(tostring(Plain(instanceID) or name), tostring(Plain(difficulty) or 0))
			list[id] = {
				name = name, resetAt = now + reset, extended = extended and true or nil, raid = isRaid and true or nil,
				difficulty = Plain(difficultyName), done = Plain(encounterProgress), total = Plain(numEncounters),
			}
		end
	end
	me.lockouts = list
end

-- Professions from the spellbook's profession list (rank and cap). Recipe
-- lists come from the profession window (Scan.recipes).
function Scan.professions()
	if not (GetProfessions and GetProfessionInfo) then return end
	local me = C:Me()
	local profs = type(me.profs) == "table" and me.profs or {}
	local seen = {}
	local indexes = { Read(GetProfessions) }
	for slot = 1, 6 do
		local index = indexes[slot]
		if type(index) == "number" then
			local name, icon, rank, max, _, _, skillLine = Read(GetProfessionInfo, index)
			if type(name) == "string" and not IsSecret(name) then
				local entry = profs[name] or {}
				entry.rank, entry.max, entry.icon, entry.line = Plain(rank), Plain(max), icon, Plain(skillLine)
				entry.slot = slot
				profs[name] = entry
				seen[name] = true
			end
		end
	end
	for name in pairs(profs) do
		if not seen[name] then profs[name] = nil end
	end
	me.profs = profs
end

-- The player's own open profession (never a linked one, a guild list or
-- an NPC's): known recipes and recipe cooldowns.
function Scan.recipes()
	local T = C_TradeSkillUI
	if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return end
	if Read(T.IsTradeSkillLinked) or Read(T.IsTradeSkillGuild) or Read(T.IsNPCCrafting) then return end
	local info = Read(T.GetBaseProfessionInfo)
	local profName = type(info) == "table" and Plain(info.professionName)
	if type(profName) ~= "string" or profName == "" then return end
	local ids = Read(T.GetAllRecipeIDs)
	if type(ids) ~= "table" then return end
	local me = C:Me()
	local known = {}
	me.cooldowns = type(me.cooldowns) == "table" and me.cooldowns or {}
	local now = Now()
	for _, recipeID in ipairs(ids) do
		local recipe = Read(T.GetRecipeInfo, recipeID)
		if type(recipe) == "table" and recipe.learned then
			known[#known + 1] = recipeID
			local cooldown = T.GetRecipeCooldown and Read(T.GetRecipeCooldown, recipeID)
			if type(cooldown) == "number" and cooldown > 0 then
				me.cooldowns[recipeID] = { readyAt = now + math.floor(cooldown), name = Plain(recipe.name), prof = profName }
			end
		end
	end
	me.profs = type(me.profs) == "table" and me.profs or {}
	local entry = me.profs[profName] or {}
	entry.recipes = C.PackIDs(known)
	entry.count = #known
	entry.scanned = now
	if type(info.skillLevel) == "number" and not IsSecret(info.skillLevel) then entry.rank = info.skillLevel end
	if type(info.maxSkillLevel) == "number" and not IsSecret(info.maxSkillLevel) then entry.max = info.maxSkillLevel end
	me.profs[profName] = entry
end

-- Profession items with a long cooldown of their own: no recipe makes
-- what they make, so the profession window never lists the cooldown.
-- Saved with the recipe cooldowns under "item:<id>".
local COOLDOWN_ITEMS = {
	{ id = 15846, prof = 165 }, -- Salt Shaker (Leatherworking): Refined Deeprock Salt, 3 days
}

local function ItemName(itemID)
	local name = C_Item and C_Item.GetItemNameByID and Plain(Read(C_Item.GetItemNameByID, itemID))
	if type(name) ~= "string" and C_Item and C_Item.GetItemInfo then name = Plain(Read(C_Item.GetItemInfo, itemID)) end
	return type(name) == "string" and name ~= "" and name or nil
end

local function ProfessionName(skillLine)
	local info = C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID
		and Read(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLine)
	local name = type(info) == "table" and Plain(info.professionName)
	return type(name) == "string" and name ~= "" and name or nil
end

function Scan.itemCooldowns()
	local getCooldown = C_Container and C_Container.GetItemCooldown
	if not getCooldown then return end
	local me = C:Me()
	me.cooldowns = type(me.cooldowns) == "table" and me.cooldowns or {}
	local now, clock = Now(), GetTime()
	for _, item in ipairs(COOLDOWN_ITEMS) do
		local key = "item:" .. item.id
		local count = C_Item and C_Item.GetItemCount and Plain(Read(C_Item.GetItemCount, item.id, true))
		if type(count) == "number" and count <= 0 then
			me.cooldowns[key] = nil
		elseif type(count) == "number" then
			local start, duration = Read(getCooldown, item.id)
			start, duration = Plain(start), Plain(duration)
			-- Longer than a global cooldown: the item's own cooldown.
			if type(start) == "number" and type(duration) == "number" and start > 0 and duration > 2 then
				local old = me.cooldowns[key]
				me.cooldowns[key] = {
					readyAt = now + math.floor(start + duration - clock + 0.5),
					name = ItemName(item.id) or (type(old) == "table" and old.name) or nil,
					prof = ProfessionName(item.prof) or (type(old) == "table" and old.prof) or nil,
				}
			end
		end
	end
end

-- Quest log rows (headers skipped, nothing selected or expanded).
function Scan.quests()
	local Q = C_QuestLog
	if not (Q and Q.GetNumQuestLogEntries and Q.GetInfo) then return end
	local me = C:Me()
	local quests = type(me.quests) == "table" and me.quests or {}
	local log = {}
	for index = 1, (Read(Q.GetNumQuestLogEntries) or 0) do
		local info = Read(Q.GetInfo, index)
		if type(info) == "table" and not info.isHeader and not info.isHidden and type(info.questID) == "number" then
			local done = Q.IsComplete and Read(Q.IsComplete, info.questID)
			log[#log + 1] = {
				id = info.questID, title = Plain(info.title), level = Plain(info.level),
				done = done and true or nil, daily = (info.frequency or 0) > 0 and true or nil,
			}
			if #log >= 40 then break end
		end
	end
	quests.log = log
	me.quests = quests
end

function Scan.questHistory()
	local Q = C_QuestLog
	if not (Q and Q.GetAllCompletedQuestIDs) then return end
	local ids = Read(Q.GetAllCompletedQuestIDs)
	if type(ids) ~= "table" then return end
	local me = C:Me()
	me.quests = type(me.quests) == "table" and me.quests or {}
	me.quests.history = C.PackIDs(ids)
	me.quests.historyAt = Now()
end

-- Reputation rows the panel shows. Collapsed headers are never expanded:
-- rows under them keep their last value.
function Scan.reps()
	local R = C_Reputation
	if not (R and R.GetNumFactions and R.GetFactionDataByIndex) then return end
	local me = C:Me()
	local reps = type(me.reps) == "table" and me.reps or {}
	local header
	for index = 1, (Read(R.GetNumFactions) or 0) do
		local data = Read(R.GetFactionDataByIndex, index)
		if type(data) == "table" and type(data.factionID) == "number" then
			if data.isHeader and not data.isHeaderWithRep then
				header = Plain(data.name)
			elseif type(data.name) == "string" and not IsSecret(data.name) then
				reps[data.factionID] = {
					name = data.name, reaction = Plain(data.reaction), value = Plain(data.currentStanding),
					min = Plain(data.currentReactionThreshold), max = Plain(data.nextReactionThreshold), header = header,
				}
			end
		end
	end
	me.reps = reps
end

-- Own auctions and bids, as the auction house lists them.
function Scan.auctions()
	local A = C_AuctionHouse
	if not (A and A.GetNumOwnedAuctions and A.GetOwnedAuctionInfo) then return end
	local me = C:Me()
	local auctions = type(me.auctions) == "table" and me.auctions or {}
	local now = Now()
	local list = {}
	for index = 1, (Read(A.GetNumOwnedAuctions) or 0) do
		local info = Read(A.GetOwnedAuctionInfo, index)
		if type(info) == "table" then
			local sold = Enum.AuctionStatus and info.status == Enum.AuctionStatus.Sold
			if not sold then
				list[#list + 1] = {
					link = Plain(info.itemLink), id = info.itemKey and info.itemKey.itemID, count = Plain(info.quantity) or 1,
					bid = Plain(info.bidAmount), buyout = Plain(info.buyoutAmount),
					endsAt = type(info.timeLeftSeconds) == "number" and now + info.timeLeftSeconds or nil,
				}
			end
		end
	end
	auctions.list = list
	auctions.at = now
	me.auctions = auctions
end

function Scan.bids()
	local A = C_AuctionHouse
	if not (A and A.GetNumBids and A.GetBidInfo) then return end
	local me = C:Me()
	local auctions = type(me.auctions) == "table" and me.auctions or {}
	local bids = {}
	for index = 1, (Read(A.GetNumBids) or 0) do
		local info = Read(A.GetBidInfo, index)
		if type(info) == "table" then
			bids[#bids + 1] = { link = Plain(info.itemLink), id = info.itemKey and info.itemKey.itemID, bid = Plain(info.bidAmount), buyout = Plain(info.buyoutAmount) }
		end
	end
	auctions.bids = bids
	me.auctions = auctions
end

-- Calendar events of the current month. GetMonthInfo(0) is the month the
-- calendar shows (the player may have paged it), so the scan only runs
-- while that is the current month, and never changes it. Event times are
-- realm time: they become server timestamps through the distance to the
-- realm's "now" (C_DateAndTime.GetCurrentCalendarTime), never through the
-- computer's own time zone.
local function DayNumber(year, month, day)
	if month <= 2 then year, month = year - 1, month + 12 end
	return 365 * year + math.floor(year / 4) - math.floor(year / 100) + math.floor(year / 400)
		+ math.floor((153 * (month - 3) + 2) / 5) + day
end

local function CalendarMinutes(t)
	if type(t) ~= "table" or type(t.year) ~= "number" or type(t.month) ~= "number" then return nil end
	local day = t.monthDay or t.day
	if type(day) ~= "number" then return nil end
	return DayNumber(t.year, t.month, day) * 1440 + (tonumber(t.hour) or 0) * 60 + (tonumber(t.minute) or tonumber(t.min) or 0)
end
C.CalendarMinutes = CalendarMinutes

-- Holidays and raid resets are the same for every character; the rest
-- (invites, guild and community events) are the character's own.
local SHARED_CALENDAR = { HOLIDAY = true, RAID_RESET = true }
C.SHARED_CALENDAR = SHARED_CALENDAR

-- The month's events from now on, one entry per event: the game lists a
-- holiday once for each day it lasts, all with the same start. Up to 30
-- of the character's own events and 30 shared ones.
function Scan.calendar()
	local K = C_Calendar
	if not (K and K.GetNumDayEvents and K.GetDayEvent and K.GetMonthInfo) then return end
	local D = C_DateAndTime
	local current = D and D.GetCurrentCalendarTime and Read(D.GetCurrentCalendarTime)
	local nowMinutes = CalendarMinutes(current)
	if not nowMinutes then return end
	local month = Read(K.GetMonthInfo, 0)
	if type(month) ~= "table" or not month.numDays then return end
	if month.month ~= current.month or month.year ~= current.year then return end
	local me = C:Me()
	local now = Now()
	local list, seen, own, shared = {}, {}, 0, 0
	for day = 1, month.numDays do
		for index = 1, (Read(K.GetNumDayEvents, 0, day) or 0) do
			local event = Read(K.GetDayEvent, 0, day, index)
			local start = type(event) == "table" and event.startTime
			local minutes = CalendarMinutes(start)
			if minutes and type(event.title) == "string" and not IsSecret(event.title) then
				local at = now + (minutes - nowMinutes) * 60
				local kind = Plain(event.calendarType)
				local id = event.title .. "\001" .. minutes
				local isShared = SHARED_CALENDAR[kind] or false
				if at >= now - 86400 and not seen[id] and (isShared and shared or own) < 30 then
					seen[id] = true
					if isShared then shared = shared + 1 else own = own + 1 end
					list[#list + 1] = { at = at, title = event.title, kind = kind, invite = Plain(event.inviteStatus) }
				end
			end
		end
	end
	me.calendar = list
end

-- Base stats, out of combat; each secret value is skipped.
function Scan.stats()
	if InCombatLockdown() then return end
	local me = C:Me()
	local stats = { at = Now() }
	for index, key in ipairs({ "str", "agi", "sta", "int", "spi" }) do
		local _, value = Read(UnitStat, "player", index)
		if type(value) == "number" and not IsSecret(value) then stats[key] = value end
	end
	local _, armor = Read(UnitArmor, "player")
	if type(armor) == "number" and not IsSecret(armor) then stats.armor = armor end
	local health = Read(UnitHealthMax, "player")
	if type(health) == "number" and not IsSecret(health) then stats.hp = health end
	local power = Read(UnitPowerMax, "player")
	if type(power) == "number" and not IsSecret(power) then stats.power = power end
	local hk = Read(GetPVPLifetimeStats)
	if type(hk) == "number" and not IsSecret(hk) then stats.hk = hk end
	me.stats = stats
end

-- Guild bank tabs, as each one is shown.
local function CurrentGuildKey()
	local name = Read(IsInGuild) and Read(GetGuildInfo, "player")
	if type(name) ~= "string" or IsSecret(name) or name == "" then return end
	return name .. " - " .. GetRealmName(), name
end
C.CurrentGuildKey = CurrentGuildKey

function C:Guilds()
	EldoUIDB.guildBanks = type(EldoUIDB.guildBanks) == "table" and EldoUIDB.guildBanks or {}
	return EldoUIDB.guildBanks
end

function Scan.guildTab(tab)
	if not (GetGuildBankItemLink and GetGuildBankItemInfo and GetGuildBankTabInfo) then return end
	local key, name = CurrentGuildKey()
	if not key or not tab or tab < 1 then return end
	local numTabs = Read(GetNumGuildBankTabs) or 0
	if tab > numTabs then return end
	local tabName, icon, isViewable = Read(GetGuildBankTabInfo, tab)
	if not isViewable then return end
	local guilds = C:Guilds()
	local guild = guilds[key] or {}
	guilds[key] = guild
	guild.name, guild.realm, guild.realmKey, guild.faction = name, GetRealmName(), E:RealmKey(), Plain(UnitFactionGroup("player"))
	guild.tabs = guild.tabs or {}
	local items = {}
	for slot = 1, (rawget(_G, "MAX_GUILDBANK_SLOTS_PER_TAB") or 98) do
		local short = ShortItem(Read(GetGuildBankItemLink, tab, slot))
		local _, count = Read(GetGuildBankItemInfo, tab, slot)
		items[slot] = short and Encode(short, Plain(count)) or false
	end
	guild.tabs[tab] = { name = tabName, icon = icon, items = items, updated = Now() }
	for index in pairs(guild.tabs) do
		if index > numTabs then guild.tabs[index] = nil end
	end
	if GetGuildBankMoney then guild.money = Plain(Read(GetGuildBankMoney)) or guild.money end
	guild.updated = Now()
	local counts = {}
	for _, data in pairs(guild.tabs) do
		for _, value in ipairs(data.items or {}) do
			local short, count = Decode(value)
			local id = ItemIDOf(short)
			if id then counts[id] = (counts[id] or 0) + count end
		end
	end
	guild.counts = counts
end

-- Guild banks on the realms the scope covers.
function C:GuildKeys(scope)
	local me = self:Me()
	local list = {}
	for key, guild in pairs(self:Guilds()) do
		if type(guild) == "table" then
			local keep = true
			local realm = guild.realmKey or guild.realm
			if scope == "char" then
				keep = key == CurrentGuildKey()
			elseif scope == "faction" then
				keep = (realm == RealmOf(me) or guild.realm == me.realm) and (guild.faction == nil or guild.faction == me.faction)
			elseif scope == "realm" then
				keep = realm == RealmOf(me) or guild.realm == me.realm
			end
			if keep then list[#list + 1] = key end
		end
	end
	table.sort(list)
	return list
end

---------------------------------------------------------------------------
-- Mail sent to your own characters shows in their mailbox at once.
---------------------------------------------------------------------------
local pendingMail

function C:CaptureSendMail(recipient)
	pendingMail = nil
	if type(recipient) ~= "string" or IsSecret(recipient) or recipient == "" then return end
	local name, realm = strsplit("-", recipient)
	local key = self:FindCharacter(strtrim(name or ""), realm and strtrim(realm))
	if not key or key == E.charKey then return end
	local items = {}
	for index = 1, (ATTACHMENTS_MAX_SEND or 12) do
		local short = ShortItem(Read(GetSendMailItemLink, index))
		if short then
			local count = select(4, Read(GetSendMailItem, index)) or 1
			items[#items + 1] = Encode(short, Plain(count))
		end
	end
	if #items > 0 then pendingMail = { key = key, items = items } end
end

function C:MailSent()
	if not pendingMail then return end
	local record = self:Get(pendingMail.key)
	if record then
		record.mail = record.mail or {}
		for _, item in ipairs(pendingMail.items) do table.insert(record.mail, item) end
		record.mailMeta = record.mailMeta or {}
		table.insert(record.mailMeta, { sender = E:PlayerName(), expires = Now() + 30 * 86400, items = #pendingMail.items, money = 0, cod = 0 })
		self:Recount(record)
		Fire("mail", pendingMail.key)
	end
	pendingMail = nil
end

---------------------------------------------------------------------------
-- Played time. EldoUI asks once at login (and on level-up when that is
-- on); the answer for EldoUI's own request stays out of chat when "quiet"
-- is on: the chat frames skip that one TIME_PLAYED_MSG and get it back
-- right after. A /played the player types always prints as usual.
---------------------------------------------------------------------------
local quiet = { frames = nil, timer = nil }

local function ChatFrames()
	local list = {}
	for index = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. index]
		if frame and frame.IsEventRegistered and frame:IsEventRegistered("TIME_PLAYED_MSG") then list[#list + 1] = frame end
	end
	return list
end

local function EndQuiet()
	local frames = quiet.frames
	quiet.frames = nil
	if quiet.timer then quiet.timer:Cancel() end
	quiet.timer = nil
	for _, frame in ipairs(frames or {}) do
		if not frame:IsEventRegistered("TIME_PLAYED_MSG") then frame:RegisterEvent("TIME_PLAYED_MSG") end
	end
end

function C:RequestPlayed()
	-- The /played request is the Characters module's own (it prints in chat).
	if not RequestTimePlayed or quiet.frames or not self:Recording() or not self:Full() then return end
	if Opt("quietPlayed") then
		quiet.frames = ChatFrames()
		for _, frame in ipairs(quiet.frames) do frame:UnregisterEvent("TIME_PLAYED_MSG") end
		-- No answer (server busy): the chat frames get the event back anyway.
		quiet.timer = C_Timer.NewTimer(10, EndQuiet)
	end
	RequestTimePlayed()
end

local function OnPlayed(total, level)
	if not C:Recording() then return end
	total, level = Plain(total), Plain(level)
	if type(total) ~= "number" then return end
	local me = C:Me()
	me.played, me.playedLevel, me.playedAt = total, level, Now()
	if quiet.frames then C_Timer.After(0, EndQuiet) end
	Fire("played")
end

---------------------------------------------------------------------------
-- Level log: one row per level gained, with the time, zone, played
-- time at the ding, how long the level took, XP kills and quests turned in.
---------------------------------------------------------------------------
local function LevelNow(me)
	if type(me.levelNow) ~= "table" or me.levelNow.level ~= me.level then
		me.levelNow = { level = me.level, kills = 0, quests = 0, since = Now() }
	end
	return me.levelNow
end
C.LevelNow = LevelNow

-- XP kills of the open level. The creature's name is kept too (mobs), so a
-- "defeat 10 of these" goal counts only kills the game named.
function C:CountKill(text)
	if not self:Recording() then return end
	local fields = E.ChatParse and E.ChatParse:Parse("xpkill", text)
	local mob = fields and fields.mob
	if IsSecret(mob) or type(mob) ~= "string" or mob == "" then return end
	local now = LevelNow(self:Me())
	now.kills = now.kills + 1
	now.mobs = type(now.mobs) == "table" and now.mobs or {}
	now.mobs[mob] = (now.mobs[mob] or 0) + 1
end

function C:CountQuest(questID)
	if not self:Recording() then return end
	local me = self:Me()
	local now = LevelNow(me)
	now.quests = now.quests + 1
	if type(questID) == "number" then
		me.quests = type(me.quests) == "table" and me.quests or {}
		if me.quests.history then
			local set = C.UnpackIDs(me.quests.history)
			if not set[questID] then
				local list = {}
				for id in pairs(set) do list[#list + 1] = id end
				list[#list + 1] = questID
				me.quests.history = C.PackIDs(list)
			end
		end
		for _, entry in ipairs(me.quests.log or {}) do
			if entry.id == questID and entry.daily then
				me.quests.daily = me.quests.daily or {}
				me.quests.daily[questID] = Now()
			end
		end
	end
end

function C:OnLevelUp(level)
	if not self:Recording() then return end
	level = Plain(level)
	if type(level) ~= "number" then return end
	local me = self:Me()
	local now = Now()
	local current = LevelNow(me)
	me.levels = type(me.levels) == "table" and me.levels or {}
	local played = self:Played(me)
	local previous = me.levels[level - 1]
	local took
	if played and previous and previous.played then
		took = played - previous.played
	elseif played and me.playedLevel and me.playedAt then
		took = me.playedLevel + (now - me.playedAt)
	end
	me.levels[level] = {
		at = now, zone = Plain(Read(GetRealZoneText)) or me.zone, played = played and math.floor(played) or nil,
		took = took and math.floor(took) or (now - (current.since or now)), kills = current.kills, quests = current.quests,
		money = Plain(GetMoney()),
	}
	me.level = level
	me.levelNow = { level = level, kills = 0, quests = 0, since = now }
	if me.playedAt then me.playedLevel = 0 end
	if Opt("playedOnLevelUp") then C_Timer.After(1, function() C:RequestPlayed() end) end
	Fire("levels")
end

-- The ding row's played time from a later read (the level-up request).
local function FillDingPlayed(total)
	if not C:Recording() then return end
	local me = C:Me()
	local row = me.levels and me.levels[me.level]
	if row and type(total) == "number" and row.at and Now() - row.at < 60 then row.played = math.floor(total) end
end

---------------------------------------------------------------------------
-- Forget
---------------------------------------------------------------------------
local SETTINGS_TABLES = { "private", "profileKeys", "installed", "installerRun", "installerLogin", "profileRules", "keybindBackup" }

-- Removes the character from every table EldoUI keeps per character.
-- settings = true also drops its EldoUI settings (profile choice,
-- per-character options, installer state, profile rules, key backup).
function C:Forget(key, settings)
	if type(key) ~= "string" or key == E.charKey then return false end
	if key:find("^guild:") then
		self:Guilds()[key:sub(7)] = nil
		if self.callbacks then self.callbacks:Fire("Forgotten", key) end
		return true
	end
	-- My Adventure's journal and its dated backups leave only after one
	-- backup of it is kept apart (also when the module is off); the Saved
	-- data page puts it back or removes it. A journal that could not be
	-- backed up stays where it is, with its dated backups.
	local B = E.Adventure and E.Adventure.Backup
	if B and B.KeepForgotten then
		if type(EldoUIDB.journal) == "table" and type(EldoUIDB.journal[key]) == "table" then
			local ok, kept
			ok, kept = pcall(B.KeepForgotten, B, EldoUIDB.journal[key], key)
			if not ok then geterrorhandler()(kept) end
			if ok and kept then EldoUIDB.journal[key] = nil end
		elseif B:List(key)[1] ~= nil then
			-- No journal, only dated backups: the newest is kept apart.
			local ok, err = pcall(B.KeepForgotten, B, nil, key)
			if not ok then geterrorhandler()(err) end
		end
	end
	local record = self:Get(key)
	self:All()[key] = nil
	local auction = EldoUIDB.auction
	if type(auction) == "table" and type(auction.chars) == "table" then auction.chars[key] = nil end
	if type(EldoUIDB.chars) == "table" then EldoUIDB.chars[key] = nil end
	if type(EldoUIDB.lootGuide) == "table" then EldoUIDB.lootGuide[key] = nil end
	local skip = self:SkipList()
	if skip then skip[key] = nil end
	-- Instances keeps runs and lockouts per character too, keyed
	-- "Name - <realm key>" (the ruleset on Forever).
	local instances = E.modules and E.modules.Instances
	if instances and instances.ForgetCharacter then
		local name = key:match("^(.-) %- ") or (record and record.name)
		local realmKey = record and record.realmKey or (record and record.realm == GetRealmName() and E:RealmKey()) or nil
		if type(name) == "string" and realmKey then
			local ok, err = pcall(instances.ForgetCharacter, instances, ("%s - %s"):format(name, tostring(realmKey)))
			if not ok then geterrorhandler()(err) end
		end
	end

	local module = E.modules and E.modules.Characters
	local db = module and module.db
	if db then
		for _, members in pairs(type(db.groups) == "table" and db.groups or {}) do
			if type(members) == "table" then members[key] = nil end
		end
	end
	if settings then
		for _, name in ipairs(SETTINGS_TABLES) do
			if type(EldoUIDB[name]) == "table" then EldoUIDB[name][key] = nil end
		end
	end
	-- What the modules keep deeper in the file (the setup backup, the quest
	-- tracker fold and more), each through its owner.
	E:RunCharacterForgets(key)
	if self.callbacks then self.callbacks:Fire("Forgotten", key) end
	return true
end

function E:ForgetCharacter(key, settings)
	return C:Forget(key, settings)
end

-- Mail that ran out leaves the record: its header and its items (the
-- inbox scan writes each mail's items in header order, items = how many).
function C:PruneMail(record, now)
	now = now or Now()
	local meta = record.mailMeta
	local mail = type(record.mail) == "table" and record.mail or {}
	local total = 0
	for _, entry in ipairs(meta) do total = total + (type(entry) == "table" and tonumber(entry.items) or 0) end
	local aligned = total == #mail
	local keptMeta, keptMail, position = {}, {}, 1
	for _, entry in ipairs(meta) do
		local count = type(entry) == "table" and tonumber(entry.items) or 0
		if type(entry) == "table" and (entry.expires or now + 1) > now then
			keptMeta[#keptMeta + 1] = entry
			for index = position, position + count - 1 do
				if mail[index] ~= nil then keptMail[#keptMail + 1] = mail[index] end
			end
		end
		position = position + count
	end
	if #keptMeta == #meta then return end
	record.mailMeta = keptMeta
	if aligned then
		record.mail = keptMail
	elseif #keptMeta == 0 then
		record.mail = {}
	else
		return
	end
	self:Recount(record)
end

-- Expired lockouts, past calendar events, old cooldowns and expired mail
-- and auctions leave every record at login.
function C:Prune()
	local now = Now()
	for _, record in pairs(self:All()) do
		if type(record) == "table" then
			for id, lock in pairs(type(record.lockouts) == "table" and record.lockouts or {}) do
				if type(lock) ~= "table" or (lock.resetAt or 0) <= now then record.lockouts[id] = nil end
			end
			if type(record.calendar) == "table" then
				for index = #record.calendar, 1, -1 do
					if (record.calendar[index].at or 0) < now - 86400 then table.remove(record.calendar, index) end
				end
			end
			for id, cd in pairs(type(record.cooldowns) == "table" and record.cooldowns or {}) do
				if type(cd) ~= "table" or (cd.readyAt or 0) < now - 7 * 86400 then record.cooldowns[id] = nil end
			end
			if type(record.mailMeta) == "table" then self:PruneMail(record, now) end
			local auctions = record.auctions
			if type(auctions) == "table" and type(auctions.list) == "table" then
				for index = #auctions.list, 1, -1 do
					local endsAt = auctions.list[index].endsAt
					if endsAt and endsAt < now - 3600 then table.remove(auctions.list, index) end
				end
			end
			local quests = record.quests
			if type(quests) == "table" and type(quests.daily) == "table" then
				local reset = C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset and Read(C_DateAndTime.GetSecondsUntilDailyReset)
				if type(reset) == "number" then
					local last = now + reset - 86400
					for id, at in pairs(quests.daily) do
						if at < last then quests.daily[id] = nil end
					end
				end
			end
		end
	end
end

-- Rough saved size of a record in bytes (our own estimate).
function C:Size(value)
	local kind = type(value)
	if kind == "string" then return #value + 3 end
	if kind == "number" then return 8 end
	if kind == "boolean" then return 5 end
	if kind ~= "table" then return 0 end
	local size = 2
	for k, v in pairs(value) do size = size + self:Size(k) + self:Size(v) + 2 end
	return size
end

---------------------------------------------------------------------------
-- Events: debounced scans, one timer per part.
---------------------------------------------------------------------------
local pending = {}

local function Schedule(part, delay, arg)
	if pending[part] then return end
	pending[part] = true
	C_Timer.After(delay or 0.5, function()
		pending[part] = nil
		if not Allowed(part) then return end
		local fn = Scan[part]
		if fn then
			local ok, err = pcall(fn, arg)
			if not ok then geterrorhandler()(err) return end
		end
		Fire(part)
	end)
end
C.Schedule = function(_, part, delay, arg) Schedule(part, delay, arg) end

-- Runs a scan now (Bags' bank window, tests).
function C:ScanNow(part, arg)
	if not Allowed(part) then return end
	local fn = Scan[part]
	if not fn then return end
	local ok, err = pcall(fn, arg)
	if not ok then geterrorhandler()(err) return end
	Fire(part)
end

function C:IsBankOpen() return bankOpen end

-- Logout: the last money, rested XP and played time, and when.
function C:Logout()
	local me = self:Me()
	-- The gold follows every money change; a read while leaving the world
	-- that answers nothing or 0 keeps the amount saved last.
	local money = Plain(Read(GetMoney))
	if type(money) == "number" and (money > 0 or type(me.money) ~= "number") then me.money = money end
	me.rested = Plain(Read(GetXPExhaustion)) or me.rested
	me.resting = Read(IsResting) and true or false
	local played = self:Played(me)
	if played then
		me.playedLevel = (me.playedLevel or 0) + (Now() - (me.playedAt or Now()))
		me.played, me.playedAt = math.floor(played), Now()
	end
	me.loggedOut = Now()
end

local owner = {}
local started = false
local guildBankOpen = false

local function On(event, fn)
	E:RegisterEvent(event, function(_, _, ...) fn(...) end, owner)
end

-- The Alts-window parts of a login: at login while Characters is on, or
-- when Characters is switched on later in the session.
local function CatchUp()
	if not C:Recording() then return end
	LevelNow(C:Me())
	for _, part in ipairs({ "durability", "professions", "quests", "reps" }) do
		local ok, err = pcall(Scan[part])
		if not ok then geterrorhandler()(err) end
	end
	Schedule("stats", 5)
	Schedule("itemCooldowns", 3)
	Schedule("questHistory", 10)
	C_Timer.After(5, function()
		if RequestRaidInfo and C:Recording() then RequestRaidInfo() end
	end)
	if Opt("requestPlayed") then C_Timer.After(3, function() C:RequestPlayed() end) end
end

local function Login()
	C:Prune()
	C:SkipList()
	C:BackfillRealmKeys()
	-- A skipped character keeps its record (its own bag window and item
	-- counts use it); it only leaves the other characters' lists.
	local me = C:Me()
	local rest = RestBefore(me)
	me.seen = Now()
	me.loggedOut = nil
	for _, part in ipairs({ "basics", "bags", "equip" }) do
		local ok, err = pcall(Scan[part])
		if not ok then geterrorhandler()(err) end
	end
	C:LearnRest(me, rest)
	Schedule("currency", 3)
	CatchUp()
	Fire("login")
end

-- Characters switched on during the session (its OnEnable).
function C:OnCharactersEnabled()
	if started then CatchUp() end
end

function C:Start()
	if started then return end
	started = true
	On("PLAYER_LEVEL_UP", function(level) C:OnLevelUp(level) Schedule("basics", 1) end)
	On("PLAYER_XP_UPDATE", function() Schedule("basics", 1) end)
	On("PLAYER_UPDATE_RESTING", function() Schedule("basics", 1) end)
	On("ENABLE_XP_GAIN", function() Schedule("basics", 1) end)
	On("DISABLE_XP_GAIN", function() Schedule("basics", 1) end)
	On("ZONE_CHANGED_NEW_AREA", function() Schedule("basics", 2) end)
	On("HEARTHSTONE_BOUND", function() Schedule("basics", 1) end)
	On("PLAYER_GUILD_UPDATE", function() Schedule("basics", 2) end)
	On("UNIT_PET", function(unit) if unit == "player" then Schedule("basics", 2) end end)
	On("PLAYER_MONEY", function() Scan.money(true) Fire("money") end)
	On("PLAYER_LEAVING_WORLD", function() inWorld = false end)
	On("PLAYER_ENTERING_WORLD", function() inWorld = true end)
	On("BAG_UPDATE_COOLDOWN", function() Schedule("itemCooldowns", 1) end)
	On("BAG_UPDATE", function(bag)
		bag = Plain(bag)
		if type(bag) == "number" then C.changedBags[bag] = true end
	end)
	On("BAG_UPDATE_DELAYED", function()
		Schedule("bags")
		if bankOpen then Schedule("bank") end
	end)
	On("BANKFRAME_OPENED", function() bankOpen = true C:ScanNow("bank") end)
	On("BANKFRAME_CLOSED", function()
		if bankOpen then C:ScanNow("bank") end
		bankOpen = false
	end)
	On("PLAYERBANKSLOTS_CHANGED", function() Schedule("bank") end)
	On("BANK_TABS_CHANGED", function() Schedule("bank") end)
	On("PLAYER_EQUIPMENT_CHANGED", function() Schedule("equip") end)
	On("PLAYER_AVG_ITEM_LEVEL_UPDATE", function() Schedule("equip", 1) end)
	On("UPDATE_INVENTORY_DURABILITY", function() Schedule("durability", 2) end)
	On("MAIL_INBOX_UPDATE", function() Schedule("mail") end)
	On("MAIL_SEND_SUCCESS", function() C:MailSent() end)
	On("MAIL_FAILED", function() pendingMail = nil end)
	On("CURRENCY_DISPLAY_UPDATE", function() Schedule("currency", 2) end)
	On("TIME_PLAYED_MSG", function(total, level)
		OnPlayed(total, level)
		FillDingPlayed(Plain(total))
	end)
	On("UPDATE_INSTANCE_INFO", function() Schedule("lockouts", 0.5) end)
	On("SKILL_LINES_CHANGED", function() Schedule("professions", 1) end)
	On("TRADE_SKILL_SHOW", function() Schedule("recipes", 1) end)
	On("TRADE_SKILL_LIST_UPDATE", function() Schedule("recipes", 1) end)
	On("TRADE_SKILL_DATA_SOURCE_CHANGED", function() Schedule("recipes", 1) end)
	On("QUEST_LOG_UPDATE", function() Schedule("quests", 2) end)
	On("QUEST_TURNED_IN", function(questID) C:CountQuest(Plain(questID)) Fire("quests") end)
	On("CHAT_MSG_COMBAT_XP_GAIN", function(text) C:CountKill(text) end)
	On("UPDATE_FACTION", function() Schedule("reps", 2) end)
	On("AUCTION_HOUSE_SHOW", function()
		if not C:Recording() then return end
		local auctions = C:Section(E.charKey, "auctions")
		if auctions then auctions.visited = Now() end
	end)
	On("OWNED_AUCTIONS_UPDATED", function() Schedule("auctions", 0.5) end)
	On("BIDS_UPDATED", function() Schedule("bids", 0.5) end)
	On("CALENDAR_UPDATE_EVENT_LIST", function() Schedule("calendar", 1) end)
	On("UNIT_INVENTORY_CHANGED", function(unit) if unit == "player" then Schedule("stats", 5) end end)
	On("PLAYER_REGEN_ENABLED", function() if not C:Get(E.charKey) or not (C:Me().stats) then Schedule("stats", 5) end end)
	On("GUILDBANKFRAME_OPENED", function() guildBankOpen = true end)
	On("GUILDBANKFRAME_CLOSED", function() guildBankOpen = false end)
	On("GUILDBANKBAGSLOTS_CHANGED", function()
		if not guildBankOpen or not GetCurrentGuildBankTab then return end
		local tab = Read(GetCurrentGuildBankTab)
		C_Timer.After(0.2, function()
			local ok, err = pcall(Scan.guildTab, tab)
			if not ok then geterrorhandler()(err) end
			Fire("guild")
		end)
	end)
	On("PLAYER_LOGOUT", function() C:Logout() end)
	if SendMail then
		hooksecurefunc("SendMail", function(recipient)
			C:CaptureSendMail(recipient)

		end)
	end
	Login()
end

-- A character's login in the same session (tests switch characters).
C.Login = Login

E:RegisterEvent("PLAYER_LOGIN", function()
	-- After the modules: their settings (Characters page) are read.
	C_Timer.After(0, function() C:Start() end)
end, C, "modules")

