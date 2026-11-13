-- EldoUI Loot Guide: wishlists and drop alerts.
--
-- Lists
--   * "main": every character's own list (EldoUIDB.lootGuide[charKey].wishlist).
--     A player who never makes another list sees exactly one wishlist.
--   * more lists per character (data.wishLists) or for the whole account
--     (EldoUIDB.lootGuideLists), each with a name and an icon.
--   * one list is active: the star and "Add to wishlist" put items there.
--     Other lists can be "shown": their items are starred and alerted too.
--   * an entry is { added = time, hint = "bis" | nil, note = "up to 60 letters" }.
--
-- Alerts (wishAlert, read-only): a wished item in an open loot window
-- (LOOT_READY + GetLootSlotLink), in a group roll (START_LOOT_ROLL +
-- GetLootRollItemLink), won by someone in your group (ENCOUNTER_LOOT_RECEIVED),
-- or listed for the dungeon you enter. Each item at most once per 15
-- seconds; a sound (wishSound) and a chat line, plus a toast or banner
-- (wishRoute). CHAT_MSG_LOOT is never parsed, nothing is looted or rolled.
--
-- Sharing: a list travels as an EldoUI share string ("!EUW1!", through
-- E:RegisterShareKind in Core/Share.lua): item ids, notes, the list name
-- and icon, never a character name. "Send to" uses E:SendShare, so the
-- receiver must know you (group, guild, friend) and accepts first.
--
-- Turning the Wishlist page off hides the stars, the tooltip line and the
-- alerts (LG:WishlistOn in UI/Kit.lua).
local _, E = ...
local LG = E.LootGuide
local L = E.L

local NOTE_MAX = 60
local THROTTLE = 15
local MAIN = "main"
LG.WISH_NOTE_MAX = NOTE_MAX

local Secret = E.Secret

local function ItemName(itemID, link)
	local name, _, quality = C_Item.GetItemInfo(link or itemID)
	if Secret(name) then name = nil end
	if not name then
		local record = LG:ItemRecord(itemID)
		name, quality = record and record.name, record and record.quality
	end
	return name or ("item:" .. itemID), quality
end

-- Icons a list can wear: roles and classes from the game's own art.
LG.WISH_ICONS = {
	"Interface\\Icons\\INV_Misc_Note_01", "Interface\\Icons\\INV_Misc_Book_09", "Interface\\Icons\\Ability_Warrior_DefensiveStance",
	"Interface\\Icons\\Spell_Holy_FlashHeal", "Interface\\Icons\\Ability_DualWield", "Interface\\Icons\\Spell_Fire_FireBolt02",
	"Interface\\Icons\\INV_Sword_04", "Interface\\Icons\\INV_Chest_Plate06", "Interface\\Icons\\INV_Misc_Gem_Pearl_05",
	"Interface\\Icons\\INV_Misc_Coin_01",
}

---------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------
local function AccountLists(create)
	if type(EldoUIDB) ~= "table" then return create and {} or nil end
	if type(EldoUIDB.lootGuideLists) ~= "table" then
		if not create then return end
		EldoUIDB.lootGuideLists = {}
	end
	return EldoUIDB.lootGuideLists
end

-- The raw list record { name, icon, items } (main: a view on data.wishlist).
local function Raw(id)
	local data = LG:Char()
	if not data then return end
	if id == MAIN or id == nil then
		return { id = MAIN, name = data.mainListName or L["Wishlist"], icon = data.mainListIcon or LG.WISH_ICONS[1],
			items = data.wishlist }
	end
	local list = data.wishLists[id]
	if type(list) == "table" then
		list.items = type(list.items) == "table" and list.items or {}
		list.id = id
		return list
	end
	local account = AccountLists(false)
	list = account and account[id]
	if type(list) == "table" then
		list.items = type(list.items) == "table" and list.items or {}
		list.id, list.account = id, true
		return list
	end
end
LG.WishListRecord = function(_, id) return Raw(id) end

function LG:ActiveListID()
	local data = self:Char()
	local id = data and data.activeList or MAIN
	if not Raw(id) then id = MAIN end
	return id
end

function LG:IsListShown(id)
	local data = self:Char()
	if not data then return id == MAIN end
	return id == self:ActiveListID() or data.shownLists[id] == true
end

-- Every list: { { id, name, icon, account, count, active, shown }, ... }
-- (main first, then character lists, then account lists, by name).
function LG:WishLists()
	local data = self:Char()
	local out = {}
	if not data then return out end
	local function Add(list)
		local count = 0
		for _ in pairs(list.items) do count = count + 1 end
		out[#out + 1] = { id = list.id, name = list.name or "?", icon = list.icon or LG.WISH_ICONS[1], account = list.account or false,
			count = count, active = list.id == self:ActiveListID(), shown = self:IsListShown(list.id) }
	end
	Add(Raw(MAIN))
	local extra = {}
	for id in pairs(data.wishLists) do extra[#extra + 1] = Raw(id) end
	for id in pairs(AccountLists(false) or {}) do extra[#extra + 1] = Raw(id) end
	table.sort(extra, function(a, b)
		if (a.account or false) ~= (b.account or false) then return not a.account end
		return (a.name or "") < (b.name or "")
	end)
	for _, list in ipairs(extra) do Add(list) end
	return out
end

local function NewID(prefix, taken)
	local index = 1
	while taken[prefix .. index] do index = index + 1 end
	return prefix .. index
end

local function UniqueName(name)
	name = strtrim(tostring(name or ""))
	if name == "" then name = L["Wishlist"] end
	name = E:Utf8Sub(name, 40)
	local used = {}
	for _, list in ipairs(LG:WishLists()) do used[list.name] = true end
	if not used[name] then return name end
	local index = 2
	while used[("%s (%d)"):format(name, index)] do index = index + 1 end
	return ("%s (%d)"):format(name, index)
end

-- account: true keeps the list for every character on the account.
function LG:NewWishList(name, account, icon)
	local data = self:Char()
	if not data then return end
	local store = account and AccountLists(true) or data.wishLists
	local id = NewID(account and "a" or "c", store)
	store[id] = { name = UniqueName(name), icon = icon or LG.WISH_ICONS[(#self:WishLists() % #LG.WISH_ICONS) + 1], items = {} }
	self:Fire("wishlist")
	return id
end

function LG:RenameWishList(id, name)
	local data = self:Char()
	name = strtrim(tostring(name or ""))
	if not data or name == "" then return false end
	name = E:Utf8Sub(name, 40)
	if id == MAIN then data.mainListName = name else
		local list = Raw(id)
		if not list then return false end
		list.name = name
	end
	self:Fire("wishlist")
	return true
end

function LG:SetWishListIcon(id, icon)
	local data = self:Char()
	if not data or not icon then return end
	if id == MAIN then data.mainListIcon = icon else
		local list = Raw(id)
		if list then list.icon = icon end
	end
	self:Fire("wishlist")
end

-- The main list cannot be deleted (it is emptied instead).
function LG:DeleteWishList(id)
	local data = self:Char()
	if not data or id == MAIN then return false end
	if data.wishLists[id] then
		data.wishLists[id] = nil
	else
		local account = AccountLists(false)
		if not (account and account[id]) then return false end
		account[id] = nil
	end
	data.shownLists[id] = nil
	if data.activeList == id then data.activeList = MAIN end
	self:Fire("wishlist")
	return true
end

function LG:SetActiveList(id)
	local data = self:Char()
	if not data or not Raw(id) then return end
	data.activeList = id
	self:Fire("wishlist")
end

function LG:SetListShown(id, on)
	local data = self:Char()
	if not data or not Raw(id) then return end
	data.shownLists[id] = on and true or nil
	self:Fire("wishlist")
end

-- Lists whose items are marked: the active one and the shown ones.
local function MarkedLists()
	local data = LG:Char()
	local list = {}
	if not data then return list end
	local active = LG:ActiveListID()
	list[1] = Raw(active)
	for _, entry in ipairs(LG:WishLists()) do
		if entry.id ~= active and entry.shown then list[#list + 1] = Raw(entry.id) end
	end
	return list
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
-- entry, list for the first marked list that holds the item.
function LG:WishEntry(itemID)
	itemID = tonumber(itemID)
	if not itemID then return end
	for _, list in ipairs(MarkedLists()) do
		local entry = list.items[itemID]
		if entry then return entry, list end
	end
end

function LG:IsWished(itemID)
	return self:WishEntry(itemID) ~= nil
end

-- on: add to the active list (or listID). off: take it out of every marked
-- list (the star means "wished anywhere you see it").
function LG:SetWished(itemID, on, hint, listID)
	itemID = tonumber(itemID)
	if not itemID or not self:Char() then return end
	if on then
		local list = Raw(listID or self:ActiveListID())
		if not list then return end
		list.items[itemID] = list.items[itemID] or { added = time(), hint = hint }
	elseif listID then
		local list = Raw(listID)
		if list then list.items[itemID] = nil end
	else
		for _, list in ipairs(MarkedLists()) do list.items[itemID] = nil end
	end
	self:Fire("wishlist")
end

function LG:ToggleWished(itemID)
	self:SetWished(itemID, not self:IsWished(itemID))
	return self:IsWished(itemID)
end

-- { [itemID] = { entry, list } } over every marked list.
function LG:WishedItems()
	local out = {}
	for _, list in ipairs(MarkedLists()) do
		for itemID, entry in pairs(list.items) do
			itemID = tonumber(itemID)
			if itemID and not out[itemID] then out[itemID] = { entry = entry, list = list } end
		end
	end
	return out
end

function LG:WishlistCount()
	local count = 0
	for _ in pairs(self:WishedItems()) do count = count + 1 end
	return count
end

function LG:WishNote(itemID)
	local entry = self:WishEntry(itemID)
	local note = entry and entry.note
	return type(note) == "string" and note ~= "" and note or nil
end

function LG:SetWishNote(itemID, text)
	local entry = self:WishEntry(itemID)
	if not entry then return false end
	text = strtrim(tostring(text or "")):gsub("|", "")
	entry.note = text ~= "" and text:sub(1, NOTE_MAX) or nil
	self:Fire("wishlist")
	return true
end

-- Empty one list (the page asks for Shift first).
function LG:ClearWishList(id)
	local list = Raw(id or self:ActiveListID())
	if not list then return end
	wipe(list.items)
	self:Fire("wishlist")
end

-- A one-line text question (note, list name) on the shared dialog: accept(text)
-- runs with what the player typed.
function LG:AskText(question, text, max, accept)
	return E:ShowConfirm({ key = "ELDOUI_LOOTGUIDE_TEXT", title = L["Loot Guide"], text = question, accept = ACCEPT,
		edit = { text = text or "", maxLetters = max or 60 },
		onAccept = function(_, typed) if accept then accept(typed or "") end end })
end

-- Right-click > Edit note.
function LG:EditWishNote(itemID)
	if not self:WishEntry(itemID) then return end
	local name = ItemName(itemID)
	self:AskText((L["Note for %s (up to %d letters, shown in its tooltip; empty removes it):"]):format(name, NOTE_MAX), -- no-plural: a fixed count
		self:WishNote(itemID) or "", NOTE_MAX, function(text) LG:SetWishNote(itemID, text) end)
end

---------------------------------------------------------------------------
-- Add my BiS: the best-in-slot picks you do not own and have not
-- wished for yet. fn(added) runs when the ranking is ready.
---------------------------------------------------------------------------
function LG:AddMyBiS(fn)
	self:RankAll(function(rank)
		local set = self:ResolveBiS(rank)
		local added = 0
		for _, itemID in pairs(set) do
			if not self:Owns(itemID) and not self:IsWished(itemID) then
				self:SetWished(itemID, true, "bis")
				added = added + 1
			end
		end
		if fn then fn(added) end
	end)
end

---------------------------------------------------------------------------
-- Obsolete: a wished item you already beat
---------------------------------------------------------------------------
function LG:WishObsolete(itemID)
	if not self.IsObsolete then return false end
	local ok, obsolete, better = pcall(self.IsObsolete, self, itemID)
	return ok and obsolete or false, better
end

---------------------------------------------------------------------------
-- Alerts
---------------------------------------------------------------------------
local lastAlert = {}      -- itemID -> GetTime()
local instanceAlerted = {} -- instance key -> true (once per session)

local function AlertsOn()
	return LG.active and LG.db.wishAlert and LG:WishlistOn()
end

local function NotificationsLane()
	local notifications = E.modules and E.modules.Notifications
	if not (notifications and notifications.active and notifications.PushToast) then return end
	if E.BlizzardAllowed and not E:BlizzardAllowed("alert-toasts", "replace") then return end
	return notifications
end

local function LootToasts()
	local loot = E.modules and E.modules.Loot
	if loot and loot.active and loot.db and loot.db.toasts and loot.AddGain then return loot end
end

-- Show one alert: title, item, where. Returns the route used.
function LG:ShowWishAlert(title, itemID, link, where)
	local name, quality = ItemName(itemID, link)
	local r, g, b = self.Kit.QualityColor(quality)
	local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or LG.ICON
	local route = self.db.wishRoute or "auto"
	local used = "chat"
	if route == "auto" or route == "lane" then
		local lane = NotificationsLane()
		if lane then
			lane:PushToast({ title = title, text = name, sub = where, icon = icon, color = { r, g, b }, border = { r, g, b },
				onClick = function() LG:Open("item", itemID) end })
			used = "lane"
		elseif route == "auto" then
			local loot = LootToasts()
			if loot then
				loot:AddGain({ kind = "item", name = name, icon = icon, r = r, g = g, b = b, key = "lgwish" .. itemID })
				used = "loot"
			end
		end
	elseif route == "banner" and E.PushAlert then
		-- An alert card with a button that opens the item's page.
		LG:PushAlert({ key = "lgwish" .. itemID, title = title, icon = icon,
			text = self.Kit.Hex(r, g, b) .. name .. "|r" .. ((where and where ~= "") and ("\n" .. where) or ""),
			actions = { { label = L["Show item"], func = function() LG:Open("item", itemID) end } } })
		used = "banner"
	end
	-- Always one chat line, so the alert can be read later.
	local text = ("%s: %s%s|r"):format(title, self.Kit.Hex(r, g, b), (not Secret(link) and link and link:find("|H", 1, true)) and link or name)
	if where and where ~= "" then text = text .. " " .. E:TextHex("secondary") .. "(" .. where .. ")|r" end
	E:Print(text)
	if self.db.wishSound and self.db.wishSound ~= "" then E:PlayMedia(self.db.wishSound) end
	return used
end

-- A wished item turned up. Throttled per item. Returns true, route when
-- it alerted.
function LG:WishAlert(itemID, link, where)
	itemID = tonumber(itemID)
	if not itemID or not AlertsOn() or not self:IsWished(itemID) then return false end
	local now = GetTime()
	if lastAlert[itemID] and now - lastAlert[itemID] < THROTTLE then return false end
	lastAlert[itemID] = now
	return true, self:ShowWishAlert(L["Wishlist item"], itemID, link, where)
end

local function LinkID(link)
	if type(link) ~= "string" or Secret(link) then return end
	return tonumber(link:match("item:(%d+)"))
end

LG:Listen("LOOT_READY", "wishlist", function()
	if not AlertsOn() or not GetNumLootItems then return end
	local count = GetNumLootItems()
	if Secret(count) or type(count) ~= "number" then return end
	for slot = 1, count do
		local link = GetLootSlotLink and GetLootSlotLink(slot)
		local itemID = LinkID(link)
		if itemID then LG:WishAlert(itemID, link, L["in the loot window"]) end
	end
end)

LG:Listen("START_LOOT_ROLL", "wishlist", function(_, rollID)
	if not AlertsOn() or not GetLootRollItemLink or Secret(rollID) then return end
	local link = GetLootRollItemLink(rollID)
	local itemID = LinkID(link)
	if itemID then LG:WishAlert(itemID, link, L["up for a roll (you roll yourself)"]) end
end)

LG:Listen("ENCOUNTER_LOOT_RECEIVED", "wishlist", function(_, _, itemID, link, _, playerName)
	if not AlertsOn() or Secret(itemID) or Secret(playerName) then return end
	itemID = tonumber(itemID) or LinkID(link)
	if not itemID then return end
	local who = type(playerName) == "string" and playerName ~= "" and (Ambiguate and Ambiguate(playerName, "short") or playerName)
	LG:WishAlert(itemID, link, who and (L["dropped, won by %s"]):format(who) or L["dropped"])
end)

-- Wished items that drop in an instance (bosses and trash).
function LG:WishedInInstance(key)
	local inst = self:Instance(key)
	if not inst then return {} end
	local wished = self:WishedItems()
	local found, seen = {}, {}
	local function Scan(text)
		for itemID in (text or ""):gmatch("(%d+):%-?[%d%.]+") do
			itemID = tonumber(itemID)
			if wished[itemID] and not seen[itemID] then
				seen[itemID] = true
				found[#found + 1] = itemID
			end
		end
	end
	for _, boss in ipairs(inst.bosses or {}) do Scan(boss.loot) end
	Scan(inst.trash)
	return found
end

-- Entering a dungeon: one alert naming how many wished items drop there.
function LG:CheckInstanceWishes()
	if not AlertsOn() or not GetInstanceInfo then return end
	local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	if Secret(instanceID) or (instanceType ~= "party" and instanceType ~= "raid") then return end
	-- The wing the player is in, where several share the map.
	local key = self:InstanceForPlayer(instanceID) or self:InstanceForMap(instanceID)
	if not key or instanceAlerted[key] then return end
	local found = self:WishedInInstance(key)
	if #found == 0 then return end
	instanceAlerted[key] = true
	local first = found[1]
	lastAlert[first] = GetTime()
	local where = E:Plural(#found, "%d wishlist item drops in %s", "%d wishlist items drop in %s"):format(#found, self:InstanceName(key) or key)
	if #found == 1 then where = (L["drops in %s"]):format(self:InstanceName(key) or key) end
	return self:ShowWishAlert(L["Wishlist"], first, nil, where)
end

LG:Listen("PLAYER_ENTERING_WORLD", "wishlist", function()
	C_Timer.After(3, function() if LG.active then LG:CheckInstanceWishes() end end)
end)

-- Tests: forget the throttle.
function LG:ResetWishAlerts()
	wipe(lastAlert)
	wipe(instanceAlerted)
end

-- Settings > Test alert: one sample with the player's route and sound
-- (a wished item, else the Hearthstone). Not throttled, not counted.
function LG:TestWishAlert()
	local itemID = next(self:WishedItems()) or 6948
	return self:ShowWishAlert(L["Wishlist alert (test)"], itemID, nil, L["This is how wishlist alerts look."])
end

---------------------------------------------------------------------------
-- Sharing ("!EUW1!")
---------------------------------------------------------------------------
-- The share payload of one list: { name, icon, items = { { id, note } } }.
function LG:WishListShareData(id)
	local list = Raw(id or self:ActiveListID())
	if not list then return end
	local items = {}
	for itemID, entry in pairs(list.items) do
		items[#items + 1] = { id = tonumber(itemID), note = type(entry) == "table" and entry.note or nil }
	end
	table.sort(items, function(a, b) return a.id < b.id end)
	return { name = list.name, icon = list.icon, items = items }
end

-- Put shared items in a list: a new list (into = nil) or an existing one.
-- Returns the list id and the number of items added.
function LG:ImportWishList(data, into)
	if type(data) ~= "table" or type(data.items) ~= "table" then return end
	local id = into
	if not (id and Raw(id)) then
		local icon = type(data.icon) == "string" and data.icon:match("^Interface\\Icons\\[%w_]+$") and data.icon or nil
		id = self:NewWishList(type(data.name) == "string" and data.name:gsub("|", "") or L["Shared wishlist"], false, icon)
	end
	local list = Raw(id)
	if not list then return end
	local added = 0
	for _, item in ipairs(data.items) do
		local itemID = type(item) == "table" and tonumber(item.id)
		if itemID and itemID > 0 and not list.items[itemID] then
			local note = type(item.note) == "string" and item.note:gsub("|", ""):sub(1, NOTE_MAX) or nil
			list.items[itemID] = { added = time(), note = note ~= "" and note or nil }
			added = added + 1
		end
	end
	-- Items whose note marks them best in slot become the slot's main pick
	-- in the Best in Slot page's Wishlist view.
	if self.PromoteBiSNotes then self:PromoteBiSNotes(id, data.items) end
	self:Fire("wishlist")
	return id, added
end

function LG:ExportWishList(id)
	return E:ExportShareKind("lootwishlist", id or self:ActiveListID())
end

function LG:ShowWishListExport(id)
	local text = self:ExportWishList(id)
	if not text then return end
	local list = Raw(id or self:ActiveListID())
	E:ShowCopyBox((L["Share %s"]):format(list and list.name or L["Wishlist"]),
		L["Everything is selected. Press Ctrl+C and share it. Others paste it into /eui import or the wishlist's Import."], text)
end

-- Paste a list: into = nil makes a new list, else the items join that list.
function LG:ShowWishListImport(into)
	E:ShowPasteBox(L["Import a wishlist"], L["Paste a wishlist string (Ctrl+V) and click Save."], function(text)
		local kind, data = E:DecodeShareData(text)
		if kind ~= "lootwishlist" then
			E:Print((L["Import failed: %s"]):format(kind and L["this is not a wishlist string"] or tostring(data)))
			return
		end
		local id, added = LG:ImportWishList(data, into)
		if id then
			local list = Raw(id)
			E:Print(E:Plural(added or 0, "Added %d item to %s.", "Added %d items to %s."):format(added or 0, list and list.name or L["Wishlist"]))
		end
	end)
end

-- Offer a list to a group, guild or a player you know.
function LG:SendWishList(id, target)
	target = strtrim(tostring(target or ""))
	local upper = target:upper()
	if upper ~= "PARTY" and upper ~= "RAID" and upper ~= "GUILD" and upper ~= "GROUP" then
		if target == "" or not E:IsTrustedSender(target, "WHISPER") then
			E:Print(L["Wishlists go only to your group, your guild or friends."])
			return false
		end
	end
	return E:SendShare("share:lootwishlist:" .. (id or self:ActiveListID()), target)
end

if E.RegisterShareKind then
	E:RegisterShareKind("lootwishlist", {
		prefix = "!EUW1!",
		version = 1,
		title = function(data)
			if type(data) == "table" and type(data.name) == "string" then
				return (L["Loot Guide wishlist: %s"]):format(data.name:gsub("|", ""))
			end
			return L["Loot Guide wishlist"]
		end,
		build = function(id) return LG:WishListShareData(id) end,
		describe = function(data)
			local count = type(data.items) == "table" and #data.items or 0
			return { E:Plural(count, "%d item. Importing makes a new wishlist for this character.", "%d items. Importing makes a new wishlist for this character."):format(count) }
		end,
		apply = function(data)
			if not LG.active then
				E:Print(E:ModuleOffHint("LootGuide", L["Importing a wishlist needs it."]))
				return
			end
			local id, added = LG:ImportWishList(data)
			local list = id and Raw(id)
			if list then E:Print(E:Plural(added or 0, "Imported the wishlist %s (%d item).", "Imported the wishlist %s (%d items)."):format(list.name, added or 0)) end
		end,
	})
end
