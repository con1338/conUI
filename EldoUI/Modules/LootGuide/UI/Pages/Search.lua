-- EldoUI Loot Guide: search.
--
--   LG:Fold(text)          the search key (E:FoldText): lower case, no
--                          accents (Latin-1), Cyrillic lower case (Ё -> е),
--                          CJK as it is, no apostrophes
--   LG:SearchLength(text)  letters typed; a CJK character counts as three
--   LG:BuildSearchIndex()  the index (built once, out of combat, after the
--                          loot data loads; rebuilt when it changes, and
--                          a moment after the client learns localized
--                          item names)
--   LG:Search(text, opts)  results by kind with counts; items capped at 100
--
-- Quick dropdown under the window's search box: from three letters (at
-- once for an alias such as "dm"), eight rows and "Show all"; Enter opens
-- the Search page. The page: category chips with counts, an "Owned" chip
-- (bags, bank and alts, from Bags), results grouped by kind.
--
-- Order: instances (alias first), bosses, quests (your faction, level,
-- name), zones and mobs, items (every word, best quality first), then the
-- kinds other modules add:
--
--   LG:RegisterSearchProvider(kind, {
--       title  = L["Your journal"],       the category chip and header
--       order  = 10,                       among the added kinds
--       search = function(words, folded, text) return entries end,
--                -- entries { name, sub, icon, ... }: every word matched
--                -- already, best first; at most PROVIDER_CAP are kept
--       open   = function(entry) end,      a click on a result
--   })
--   LG:UnregisterSearchProvider(kind), LG:SearchProvider(kind)
-- Added kinds take part in the counts, the dropdown and the Search page
-- (their chip shows while they have results). "Owned" leaves them out.
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local L = E.L

local Key = E.Key
local ITEM_CAP = 100
local PROVIDER_CAP = 50
local DROPDOWN_ROWS = 8
local BASE_KINDS = { "instance", "boss", "quest", "place", "item" }
local KINDS = { "instance", "boss", "quest", "place", "item" }
local KIND_TITLE = {
	all = Key("All"), instance = Key("Instances"), boss = Key("Bosses"), quest = Key("Quests"), place = Key("Zones and mobs"), item = Key("Items"),
}
LG.SEARCH_KINDS = KINDS

---------------------------------------------------------------------------
-- Providers: kinds other modules add (My Adventure's journal rows)
---------------------------------------------------------------------------
local providers, providerOrder = {}, {}

local function SyncKinds()
	table.sort(providerOrder, function(a, b)
		local pa, pb = providers[a], providers[b]
		if pa.order ~= pb.order then return pa.order < pb.order end
		return a < b
	end)
	wipe(KINDS)
	for _, kind in ipairs(BASE_KINDS) do KINDS[#KINDS + 1] = kind end
	for _, kind in ipairs(providerOrder) do KINDS[#KINDS + 1] = kind end
end

function LG:RegisterSearchProvider(kind, def)
	assert(type(kind) == "string" and type(def) == "table" and type(def.search) == "function",
		"LootGuide:RegisterSearchProvider(kind, { title, search = function(words, folded, text) ... end })")
	local own = kind == "all"
	for _, base in ipairs(BASE_KINDS) do own = own or base == kind end
	assert(not own, "LootGuide:RegisterSearchProvider: that kind is the Loot Guide's own")
	def.kind = kind
	def.order = tonumber(def.order) or 50
	if not providers[kind] then providerOrder[#providerOrder + 1] = kind end
	providers[kind] = def
	KIND_TITLE[kind] = def.title or kind
	SyncKinds()
end

function LG:UnregisterSearchProvider(kind)
	if not providers[kind] then return end
	providers[kind] = nil
	KIND_TITLE[kind] = nil
	for index, other in ipairs(providerOrder) do
		if other == kind then
			table.remove(providerOrder, index)
			break
		end
	end
	SyncKinds()
end

function LG:SearchProvider(kind)
	return providers[kind]
end

---------------------------------------------------------------------------
-- Folding
---------------------------------------------------------------------------
-- E:FoldText (Core/Locale.lua): Latin-1 and Cyrillic case and accents,
-- CJK left as it is.
function LG:Fold(text)
	return E:FoldText(text)
end

-- Letters typed: a CJK character (and Hangul) counts as three.
function LG:SearchLength(text)
	local count = 0
	for char in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		local lead = char:byte()
		if lead >= 0xE3 and lead <= 0xED then
			count = count + 3
		elseif not char:match("^%s$") then
			count = count + 1
		end
	end
	return count
end

---------------------------------------------------------------------------
-- Index
---------------------------------------------------------------------------
local index
-- Item names a non-English client learns later ("itemnames"): the
-- index is marked stale and built again once the names settle (at most
-- every REBUILD_GAP seconds, never in combat), then an open Search page
-- redraws with the new names ("searchindex").
local REBUILD_GAP = 2
local rebuildQueued = false

local function Now() return GetTime and GetTime() or 0 end

local function RebuildStale()
	rebuildQueued = false
	if not (index and index.stale) then return end
	if InCombatLockdown() then return end -- the next search out of combat builds it
	index = nil
	if LG:BuildSearchIndex() then LG:Fire("searchindex") end
end

LG:On("search-index", function(changed)
	if changed.data then index = nil end
	if changed.itemnames and index then
		index.stale = true
		if not rebuildQueued then
			rebuildQueued = true
			C_Timer.After(REBUILD_GAP, RebuildStale)
		end
	end
end)

-- Field n of a "a|b|c" record, found without splitting the whole record.
local function Field(packed, n)
	if type(packed) ~= "string" then return end
	local first = 1
	for _ = 2, n do
		local bar = packed:find("|", first, true)
		if not bar then return end
		first = bar + 1
	end
	local bar = packed:find("|", first, true)
	return packed:sub(first, bar and bar - 1 or -1)
end

local function ZoneEntries(out)
	if not (C_Map and C_Map.GetMapChildrenInfo) then return end
	local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
	for _, continent in ipairs({ 1414, 1415 }) do
		local ok, children = pcall(C_Map.GetMapChildrenInfo, continent, zoneType, true)
		if ok and type(children) == "table" then
			for _, child in ipairs(children) do
				if type(child.name) == "string" and not P.Secret(child.name) then
					out[#out + 1] = { kind = "place", zone = child.mapID, name = child.name, fold = LG:Fold(child.name), sub = L["Zone"] }
				end
			end
		end
	end
end

-- Built once (out of combat) and kept until the loot data changes.
function LG:BuildSearchIndex()
	if index and not (index.stale and not InCombatLockdown() and Now() - (index.at or 0) >= REBUILD_GAP) then return index end
	if InCombatLockdown() then return nil end
	local started = debugprofilestop and debugprofilestop() or 0
	local LD = select(3, self:DataStatus())
	local out = {}
	-- Instances (with aliases).
	for _, info in ipairs(self:Catalog()) do
		local aliases = {}
		for _, alias in ipairs(info.aliases or {}) do aliases[#aliases + 1] = self:Fold(alias) end
		out[#out + 1] = { kind = "instance", key = info.key, name = info.name, fold = self:Fold(info.name), aliases = aliases,
			order = info.order or 0, sub = P.LevelText(info) .. "  " .. P.SizeText(info) }
	end
	-- Bosses.
	local bossNpc = {}
	for _, info in ipairs(self:Catalog()) do
		if info.world or (LD and LD.instances and LD.instances[info.key]) then
			for _, boss in ipairs(self:InstanceLoot(info.key).bosses) do
				if boss.npc and not bossNpc[boss.npc] then
					bossNpc[boss.npc] = true
					out[#out + 1] = { kind = "boss", npc = boss.npc, key = info.key, name = boss.name, fold = self:Fold(boss.name), sub = info.name }
				end
			end
		end
	end
	if LD then
		-- Quests.
		for questID, packed in pairs(LD.quests or {}) do
			local name = self:DataName("quest", questID, Field(packed, 1), true)
			if name and name ~= "" then
				out[#out + 1] = { kind = "quest", quest = questID, name = name, fold = self:Fold(name), level = tonumber(Field(packed, 2)) or 0 }
			end
		end
		-- Mobs that drop something (bosses are above).
		for npc, packed in pairs(LD.mobs or {}) do
			if LD.loot and LD.loot[npc] and not bossNpc[npc] then
				local name = self:DataName("mob", npc, Field(packed, 1), true)
				if name and name ~= "" then
					out[#out + 1] = { kind = "place", npc = npc, name = name, fold = self:Fold(name), level = tonumber(Field(packed, 3)) or 0,
						instance = Field(packed, 5) }
				end
			end
		end
		-- Items.
		for itemID, packed in pairs(LD.items or {}) do
			local name, quality = packed:match("^([^|]*)|(%d*)")
			name = self:DataName("item", itemID, name, true)
			if name and name ~= "" then
				out[#out + 1] = { kind = "item", itemID = itemID, name = name, fold = self:Fold(name), quality = tonumber(quality) or 1 }
			end
		end
	end
	ZoneEntries(out)
	local ms = debugprofilestop and (debugprofilestop() - started) or 0
	index = { entries = out, ms = ms, at = Now() }
	return index
end

-- Words of the query, folded.
local function Words(folded)
	local words = {}
	for word in folded:gmatch("%S+") do words[#words + 1] = word end
	return words
end

local function Matches(entry, words)
	for _, word in ipairs(words) do
		if not entry.fold:find(word, 1, true) then return false end
	end
	return true
end

-- opts: { owned = true (items you have only) }.
-- Returns { all = n, instance = { ... }, boss = ..., quest, place, item,
-- counts = { kind = n }, capped = bool, alias = key, short = bool }.
function LG:Search(text, opts)
	opts = opts or {}
	local folded = self:Fold(text)
	local result = { counts = {}, capped = false }
	for _, kind in ipairs(KINDS) do
		result[kind] = {}
		result.counts[kind] = 0
	end
	result.counts.all = 0
	if folded == "" then return result end
	local built = self:BuildSearchIndex()
	if not built then
		result.combat = true
		return result
	end
	local words = Words(folded)
	-- A short form several instances share ("dm", "st") finds all of them.
	local aliasHits, aliasHit = {}, nil
	for _, entry in ipairs(built.entries) do
		if entry.kind == "instance" then
			for _, alias in ipairs(entry.aliases) do
				if alias == folded and not aliasHits[entry] then
					aliasHits[entry] = true
					aliasHit = aliasHit or entry
				end
			end
		end
	end
	result.alias = aliasHit and aliasHit.key
	if self:SearchLength(text) < 3 and not aliasHit then
		result.short = true
		return result
	end
	local owned
	if opts.owned then
		owned = {}
		local bags = E.modules and E.modules.Bags
		if bags and bags.active and bags.FindAll then
			local ok, found = pcall(bags.FindAll, bags, text)
			if ok and type(found) == "table" then
				for _, entry in ipairs(found) do owned[tonumber(entry.id) or 0] = true end
			end
		end
	end
	local player = self:Player()
	for _, entry in ipairs(built.entries) do
		local hit = aliasHits[entry] or Matches(entry, words)
		if hit and entry.kind == "item" and owned and not (owned[entry.itemID] or self:Owns(entry.itemID)) then hit = false end
		if hit then
			local list = result[entry.kind]
			list[#list + 1] = entry
		end
	end
	local function Starts(entry) return entry.fold:sub(1, #folded) == folded end
	table.sort(result.instance, function(a, b)
		if (a == aliasHit) ~= (b == aliasHit) then return a == aliasHit end
		if Starts(a) ~= Starts(b) then return Starts(a) end
		return a.order < b.order
	end)
	table.sort(result.boss, function(a, b)
		if Starts(a) ~= Starts(b) then return Starts(a) end
		return a.name < b.name
	end)
	local mine = {}
	for _, entry in ipairs(result.quest) do mine[entry.quest] = self:QuestForFaction(entry.quest, "mine") end
	table.sort(result.quest, function(a, b)
		if mine[a.quest] ~= mine[b.quest] then return mine[a.quest] end
		if a.level ~= b.level then return a.level < b.level end
		if a.name ~= b.name then return a.name < b.name end
		return a.quest < b.quest
	end)
	table.sort(result.place, function(a, b)
		if (a.zone ~= nil) ~= (b.zone ~= nil) then return a.zone ~= nil end
		if Starts(a) ~= Starts(b) then return Starts(a) end
		if a.name ~= b.name then return a.name < b.name end
		return (a.npc or 0) < (b.npc or 0)
	end)
	table.sort(result.item, function(a, b)
		if a.quality ~= b.quality then return a.quality > b.quality end
		if a.name ~= b.name then return a.name < b.name end
		return a.itemID < b.itemID
	end)
	-- Kinds other modules add: not for "Owned" (items only).
	for _, kind in ipairs(providerOrder) do
		local def = providers[kind]
		local list = result[kind]
		if not opts.owned then
			local ok, found = pcall(def.search, words, folded, text)
			if not ok then
				geterrorhandler()(found)
			elseif type(found) == "table" then
				for _, entry in ipairs(found) do
					if #list >= PROVIDER_CAP then break end
					if type(entry) == "table" and type(entry.name) == "string" then
						entry.kind = kind
						list[#list + 1] = entry
					end
				end
			end
		end
	end
	for _, kind in ipairs(KINDS) do
		result.counts[kind] = #result[kind]
		result.counts.all = result.counts.all + #result[kind]
	end
	if #result.item > ITEM_CAP then
		for i = #result.item, ITEM_CAP + 1, -1 do result.item[i] = nil end
		result.capped = true
	end
	result.level = player.level
	return result
end

---------------------------------------------------------------------------
-- Opening a result
---------------------------------------------------------------------------
-- An item from the results: its route, but never back into a search.
local function OpenItem(itemID)
	local key, arg = LG:ItemRoute(itemID)
	if key == "search" then key, arg = "item", itemID end
	LG:Open(key, arg)
end

function LG:OpenSearchEntry(entry)
	local provider = providers[entry.kind]
	if provider then
		if provider.open then
			local ok, err = pcall(provider.open, entry)
			if not ok then geterrorhandler()(err) end
		end
		return
	end
	if entry.kind == "instance" then
		self:Open("journal", entry.key)
	elseif entry.kind == "boss" then
		self:Open("journal", { key = entry.key, npc = entry.npc })
	elseif entry.kind == "quest" then
		local quest = self:Quest(entry.quest)
		if quest and quest.instance and self:InstanceInfo(quest.instance) then
			self:Open("journal", { key = quest.instance, quest = entry.quest })
		else
			self:Open("detail", { quest = entry.quest })
		end
	elseif entry.kind == "place" and entry.zone then
		if self:GetPage("world") and self:IsPageOn("world") then
			self:Open("world", entry.zone)
		else
			self:OpenWorldMapAt(entry.zone)
		end
	elseif entry.kind == "place" then
		self:Open("detail", { npc = entry.npc })
	elseif entry.kind == "item" then
		OpenItem(entry.itemID)
	end
end

local KIND_ICON = {
	instance = "Interface\\Icons\\INV_Misc_Bone_Skull_01", boss = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
	quest = "Interface\\GossipFrame\\AvailableQuestIcon", place = "Interface\\Icons\\INV_Misc_Map_01",
}

local function EntryIcon(entry)
	if providers[entry.kind] then return entry.icon or LG.ICON end
	if entry.kind == "item" then return C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.itemID) or 134400 end
	if entry.kind == "instance" then return (LG:InstanceArt(entry.key)) end
	return KIND_ICON[entry.kind]
end

local function EntrySub(entry)
	if providers[entry.kind] then return entry.sub end
	if entry.kind == "quest" then
		local side = LG:QuestSide(entry.quest)
		local where = LG:QuestInstance(entry.quest)
		local bits = { (L["Quest, level %d"]):format(entry.level) }
		if side then bits[#bits + 1] = side end
		if where then bits[#bits + 1] = LG:InstanceName(where) or where end
		return table.concat(bits, "  ·  ")
	elseif entry.kind == "place" and entry.npc then
		local bits = { (L["Level %d"]):format(entry.level or 0) }
		if entry.instance and entry.instance ~= "" then bits[#bits + 1] = LG:InstanceName(entry.instance) or entry.instance end
		return table.concat(bits, "  ·  ")
	elseif entry.kind == "boss" then
		return (L["Boss · %s"]):format(entry.sub or "")
	end
	return entry.sub
end

---------------------------------------------------------------------------
-- Result rows (dropdown and page)
---------------------------------------------------------------------------
local function ResultRowCreate(row)
	row.cell = P.ItemCell(row)
	row.cell:SetAllPoints()
	row.plain = CreateFrame("Button", nil, row)
	row.plain:SetAllPoints()
	E:SkinRow(row.plain)
	row.plain.icon = row.plain:CreateTexture(nil, "ARTWORK")
	row.plain.icon:SetPoint("LEFT", 2, 0)
	E:TrimIcon(row.plain.icon)
	row.plain.name = Kit.Text(row.plain, 12, "LEFT")
	row.plain.name:SetWordWrap(false)
	row.plain.sub = Kit.Text(row.plain, 10, "LEFT", "secondary")
	row.plain.sub:SetWordWrap(false)
	row.plain.right = Kit.Text(row.plain, 11, "RIGHT", "secondary")
	row.plain.right:SetPoint("RIGHT", -6, 0)
	-- The drop-down's keyboard pick (Up/Down).
	row.selection = row:CreateTexture(nil, "OVERLAY")
	row.selection:SetAllPoints()
	E:AccentTexture(row.selection, E.tokens.pressed)
	row.selection:Hide()
	row.plain:SetScript("OnClick", function(self)
		local item = self:GetParent().item
		if not item then return end
		if item.more then
			if item.more() then return end
		elseif item.entry then
			LG:OpenSearchEntry(item.entry)
		end
		if LG.HideSearchDropdown then LG:HideSearchDropdown() end
	end)
	row.plain:HookScript("OnEnter", function(self)
		local item = self:GetParent().item
		local data = item and item.entry
		if not data then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if data.kind == "instance" then
			P.InstanceTooltip(GameTooltip, data.key)
		else
			E.UIKit.TipTitle(GameTooltip, data.name)
			local sub = EntrySub(data)
			if sub and sub ~= "" then GameTooltip:AddLine(sub, unpack(Kit.SECONDARY)) end
			E:TooltipHint(GameTooltip, { L["Click"], L["open it"] })
		end
		GameTooltip:Show()
	end)
	row.plain:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local dropdown

local function ResultRowUpdate(row, item)
	local picked = dropdown and row.list == dropdown.list and dropdown.selected and dropdown.items
		and dropdown.items[dropdown.selected] == item
	row.selection:SetShown(picked and true or false)
	if item.entry and item.entry.kind == "item" then
		row.plain:Hide()
		P.SetItem(row.cell, { itemID = item.entry.itemID, onClick = function()
			OpenItem(item.entry.itemID)
			if LG.HideSearchDropdown then LG:HideSearchDropdown() end
		end })
		return
	end
	row.cell:Hide()
	row.cell.data = nil
	local plain = row.plain
	plain:Show()
	local height = row:GetHeight() or 20
	local size = math.max(height - 4, 12)
	plain.icon:SetSize(size, size)
	plain.name:ClearAllPoints()
	plain.sub:ClearAllPoints()
	if item.header then
		plain.icon:Hide()
		plain.name:SetPoint("LEFT", 4, -2)
		plain.name:SetText(E:TextHex("accent") .. E:CaptionText(item.header) .. "|r  " .. E:TextHex("secondary") .. (item.count or "") .. "|r")
		E:SetFont(plain.name, E.tokens.size.tiny)
		plain.sub:SetText("")
		plain.right:SetText("")
		plain:EnableMouse(false)
		return
	end
	plain:EnableMouse(true)
	E:SetFont(plain.name, E.tokens.size.label)
	if item.more then
		plain.icon:Hide()
		plain.name:SetPoint("LEFT", 6, 0)
		plain.name:SetText(item.text)
		plain.name:SetTextColor(E:TokenColor("accent"))
		plain.sub:SetText("")
		plain.right:SetText("")
		return
	end
	local entry = item.entry
	plain.icon:Show()
	plain.icon:SetTexture(EntryIcon(entry))
	Kit.Paint(plain.name)
	plain.name:SetText(entry.name)
	local sub = EntrySub(entry)
	if sub and sub ~= "" and height >= 20 then
		-- The icon and the right text sit on the row's middle: the two
		-- lines take their top and bottom from the icon's edges.
		plain.name:SetPoint("TOPLEFT", plain.icon, "TOPRIGHT", 6, 1)
		plain.name:SetPoint("TOPRIGHT", plain.right, "LEFT", -6, size / 2 + 1)
		plain.sub:SetPoint("BOTTOMLEFT", plain.icon, "BOTTOMRIGHT", 6, -1)
		plain.sub:SetPoint("BOTTOMRIGHT", plain.right, "LEFT", -6, -(size / 2 + 1))
		plain.sub:SetText(sub)
		plain.sub:Show()
	else
		plain.name:SetPoint("LEFT", plain.icon, "RIGHT", 6, 0)
		plain.name:SetPoint("RIGHT", plain.right, "LEFT", -6, 0)
		plain.sub:Hide()
	end
	if entry.kind == "quest" then
		local status = LG:QuestStatus(entry.quest)
		plain.right:SetText(LG.QUEST_STATUS_TITLE[status] or "")
		plain.right:SetTextColor(P.QuestStatusColor(status))
	else
		plain.right:SetText("")
	end
end

---------------------------------------------------------------------------
-- Quick dropdown under the window's search box
---------------------------------------------------------------------------
local function DropdownItems(result, text)
	local items = {}
	for _, kind in ipairs(KINDS) do
		for _, entry in ipairs(result[kind]) do
			if #items >= DROPDOWN_ROWS then break end
			items[#items + 1] = { entry = entry }
		end
	end
	if result.counts.all > #items then
		items[#items + 1] = { more = function() LG:Open("search", text) end,
			text = E:Plural(result.counts.all, "Show %d result", "Show all %d results"):format(result.counts.all) }
	end
	return items
end

function LG:UpdateSearchDropdown(text)
	if not dropdown then return end
	text = strtrim(text or "")
	local result = text ~= "" and self:Search(text) or nil
	if not result or result.short or result.combat or result.counts.all == 0 then
		dropdown:Hide()
		return result
	end
	local items = DropdownItems(result, text)
	dropdown.items, dropdown.selected = items, nil
	dropdown.list:SetData(items)
	dropdown:SetHeight(#items * 24 + 8 + 18)
	dropdown:Show()
	return result, items
end

function LG:HideSearchDropdown()
	if dropdown then
		dropdown:Hide()
		dropdown.selected = nil
	end
end

-- Up/Down (and Tab) move the pick in the drop-down; it wraps around.
function LG:MoveSearchSelection(step)
	if not (dropdown and dropdown:IsShown() and dropdown.items and #dropdown.items > 0) then return end
	local count = #dropdown.items
	local pick = dropdown.selected
	if not pick then
		pick = step > 0 and 1 or count
	else
		pick = (pick - 1 + step) % count + 1
	end
	dropdown.selected = pick
	dropdown.list:Refresh()
	return pick
end

function LG:SearchSelection()
	local pick = dropdown and dropdown:IsShown() and dropdown.selected
	return pick and dropdown.items and dropdown.items[pick] or nil
end

-- Enter with a picked row opens it; true when it did (the box's own
-- Enter opens the Search page otherwise).
function LG:OpenSearchSelection()
	local item = self:SearchSelection()
	if not item then return false end
	self:HideSearchDropdown()
	if item.more then
		item.more()
	elseif item.entry and item.entry.kind == "item" then
		OpenItem(item.entry.itemID)
	elseif item.entry then
		self:OpenSearchEntry(item.entry)
	end
	return true
end

-- Window.lua hands over its search box once it builds it.
function LG:AttachSearchBox(box)
	self.searchBox = box
	dropdown = CreateFrame("Frame", nil, box)
	dropdown:SetFrameStrata("DIALOG")
	dropdown:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -4)
	dropdown:SetWidth(320)
	E:SetTemplate(dropdown)
	dropdown:Hide()
	dropdown.list = Kit.CreateList(dropdown, { rowHeight = 22, gap = 2, create = ResultRowCreate, update = ResultRowUpdate })
	dropdown.list:SetPoint("TOPLEFT", 4, -4)
	dropdown.list:SetPoint("BOTTOMRIGHT", -4, 22)
	dropdown.hint = Kit.Text(dropdown, E.tokens.size.small, "LEFT", "secondary")
	dropdown.hint:SetPoint("BOTTOMLEFT", 8, 6)
	dropdown.hint:SetPoint("BOTTOMRIGHT", -8, 6)
	dropdown.hint:SetText(L["Up/Down to pick, Enter to open"])
	self.searchDropdown = dropdown
	box:HookScript("OnTextChanged", function(own, userInput)
		if userInput then LG:UpdateSearchDropdown(own:GetText()) end
	end)
	box:HookScript("OnEditFocusLost", function()
		C_Timer.After(0.2, function() LG:HideSearchDropdown() end)
	end)
	box:HookScript("OnEscapePressed", function() LG:HideSearchDropdown() end)
	box:HookScript("OnArrowPressed", function(_, key)
		if key == "UP" then LG:MoveSearchSelection(-1) elseif key == "DOWN" then LG:MoveSearchSelection(1) end
	end)
	box:HookScript("OnTabPressed", function()
		LG:MoveSearchSelection(IsShiftKeyDown() and -1 or 1)
	end)
	box:HookScript("OnEnterPressed", function() LG:HideSearchDropdown() end)
end

---------------------------------------------------------------------------
-- The Search page
---------------------------------------------------------------------------
local function State()
	local ui = LG:UI()
	if type(ui.search) ~= "table" then ui.search = {} end
	local s = ui.search
	if not KIND_TITLE[s.kind or ""] then s.kind = "all" end
	return s
end

local function PageItems(result, kind)
	local items = {}
	for _, each in ipairs(KINDS) do
		if (kind == "all" or kind == each) and #result[each] > 0 then
			items[#items + 1] = { header = L[KIND_TITLE[each]], count = result.counts[each] }
			for _, entry in ipairs(result[each]) do items[#items + 1] = { entry = entry } end
			if each == "item" and result.capped then
				items[#items + 1] = { more = function() return true end,
					text = (L["Showing the first %d items. Type more to narrow it down."]):format(ITEM_CAP) } -- no-plural: always 100
			end
		end
	end
	return items
end

local Chip

-- "all", the Loot Guide's kinds, then the added kinds that found something.
local function ChipKeys(result)
	local keys = { "all" }
	for _, kind in ipairs(KINDS) do
		if not providers[kind] or (result.counts[kind] or 0) > 0 or State().kind == kind then keys[#keys + 1] = kind end
	end
	return keys
end

local function Draw(page)
	local s = State()
	local query = page.query or ""
	local result = LG:Search(query, { owned = s.owned })
	page.result = result
	page.title:SetText(query ~= "" and (L["Results for %q"]):format(query) or L["Search"])
	for _, chip in pairs(page.chips) do chip:Hide() end
	local x = 0
	for _, key in ipairs(ChipKeys(result)) do
		local chip = page.chips[key] or Chip(page, key)
		local count = result.counts[key] or 0
		chip:SetLabel(L[KIND_TITLE[key]] .. (count > 0 and (" " .. E:TextHex("secondary") .. count .. "|r") or ""))
		chip:SetOn(s.kind == key)
		chip:ClearAllPoints()
		chip:SetPoint("TOPLEFT", page, "TOPLEFT", x, -24)
		chip:Show()
		x = x + chip:GetWidth() + 4
	end
	page.owned:SetOn(s.owned)
	page.list:SetData(PageItems(result, s.kind))
end

function Chip(page, key)
	local tip = key == "all" and L["Every kind of result."] or (L["Only %s."]):format(L[KIND_TITLE[key]]:lower())
	page.chips[key] = P.Toggle(page, KIND_TITLE[key], function()
		State().kind = key
		Draw(page)
	end, KIND_TITLE[key], tip)
	return page.chips[key]
end

local function Create(parent)
	local page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()
	page.back = P.Back(page, nil, function() LG:Open(LG:StartPage()) end)
	page.back:SetPoint("TOPLEFT")
	page.title = Kit.Text(page, 14, "LEFT")
	page.title:SetPoint("LEFT", page.back, "RIGHT", 10, 0)
	page.title:SetPoint("RIGHT", -10, 0)
	page.title:SetWordWrap(false)
	page.chips = {}
	for _, key in ipairs({ "all", "instance", "boss", "quest", "place", "item" }) do Chip(page, key) end
	page.owned = P.Toggle(page, L["Owned"], function()
		local s = State()
		s.owned = not s.owned
		Draw(page)
	end, L["Owned"], L["Only items in your bags, bank or on your other characters (from Bags)."])
	page.owned:SetPoint("TOPRIGHT", 0, -24)
	page.list = Kit.CreateList(page, { rowHeight = 24, gap = 2, create = ResultRowCreate, update = ResultRowUpdate })
	page.list:SetPoint("TOPLEFT", 0, -50)
	page.list:SetPoint("BOTTOMRIGHT")
	return page
end

local function Show(page, arg)
	if type(arg) == "string" then page.query = strtrim(arg) end
	if LG.searchBox and page.query and LG.searchBox:GetText() ~= page.query then LG.searchBox:SetText(page.query) end
	LG:HideSearchDropdown()
	Draw(page)
end

LG:RegisterPage("search", {
	title = "Search",
	desc = "Dungeons, bosses, quests, zones, mobs and items.",
	order = 90,
	hidden = true,
	command = "search",
	usage = Key("search the Loot Guide (/eui search <text>)"),
	create = Create,
	show = Show,
	refresh = function(page, changed)
		if changed.data or changed.quests or changed.bags or changed.searchindex then Draw(page)
		elseif changed.items or changed.wishlist then page.list:Refresh() end
	end,
	empty = function(page)
		local result = page.result
		if not result then return end
		if (page.query or "") == "" then
			return L["Search the Loot Guide"], L["Type three letters in the box at the top (or an alias such as dm or zf) and press Enter."], LG.ICON
		elseif result.combat then
			return L["Search waits for the end of combat"], L["The search index is built out of combat. Try again in a moment."], LG.ICON
		elseif result.short then
			return L["Type a little more"], L["Search starts from three letters, or one Chinese, Japanese or Korean character."], LG.ICON
		elseif result.counts.all == 0 then
			if State().owned then
				return L["Nothing found"], (L["Nothing you own matches %q. Turn off Owned to search everything."]):format(page.query), LG.ICON
			end
			return L["Nothing found"], (L["Nothing in the Loot Guide matches %q."]):format(page.query), LG.ICON
		end
	end,
})
