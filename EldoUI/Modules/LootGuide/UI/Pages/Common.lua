-- EldoUI Loot Guide: parts the pages share.
-- They add to the window kit (UI/Kit.lua) and follow DESIGN.md: accent
-- read when drawn, EldoUI templates, theme font.
--
--   P.Flow(parent[, opts])    a scrolling column of pooled blocks (detail panes);
--                             opts.virtual builds long pages as you scroll
--   P.Caption(parent)         a small upper-case gray caption
--   P.Pill(parent)            a chip with a color (upgrade, quest, status)
--   P.Art(parent, size)       an icon box with the EldoUI border
--   P.InstanceTile(parent)    art, name, level, pills, level-fit bar, tooltip
--   P.InstanceTooltip(tt, key) the instance tooltip
--   P.InstanceStats(key)      upgrades, wished, quests open/done, known drops
--   P.LevelText(info)         "17-26" colored green / yellow / gray
--   P.SourceLine(entry)       "Ras Frostwhisper · Scholomance" for a source
--   P.QuestRowText(row)       name, level and tags for a quest row
--   P.Back(parent, label, fn) a "< Back" link
-- Toggle and link labels, captions and line buttons may come as English
-- keys from tables built while the files load; these parts show them
-- translated (E:Translate).
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local L = E.L

local Key = E.Key
local P = {}
LG.PageKit = P

local Secret = E.Secret
P.Secret = Secret

---------------------------------------------------------------------------
-- Flow: a ScrollFrame whose child holds blocks placed top-down. Widgets are
-- pooled per kind and handed out again on each redraw.
--
-- A flow made with { virtual = true } builds long pages a screen at a time:
-- flow:Defer(estimate, build) queues a block (build(flow) places it), and
-- only the blocks that reach the visible part (plus a margin) are built;
-- the rest are built as you scroll down to them. The estimate only sizes
-- the scroll bar until the block is built. Once a block is queued, every
-- later block must be deferred too; a block placed directly builds the
-- queue first, so the order always holds. On a plain flow Defer builds at
-- once.
---------------------------------------------------------------------------
local SCROLL_WIDTH = 8
local FILL_MARGIN = 200   -- pixels built below the visible part

function P.Flow(parent, opts)
	local flow = CreateFrame("Frame", nil, parent)
	flow.virtual = type(opts) == "table" and opts.virtual and true or false
	flow.scroll = CreateFrame("ScrollFrame", nil, flow)
	flow.scroll:SetPoint("TOPLEFT")
	flow.scroll:SetPoint("BOTTOMRIGHT", -(SCROLL_WIDTH + 4), 0)
	flow.child = CreateFrame("Frame", nil, flow.scroll)
	flow.child:SetSize(10, 10)
	flow.scroll:SetScrollChild(flow.child)
	-- The kit's scroll bar (thin track, dim thumb, accent on hover or drag).
	flow.bar = E.UIKit.ScrollBar(flow, function(value)
		flow.scroll:SetVerticalScroll(value)
		if flow.virtual then flow:Fill() end
	end)
	flow:EnableMouseWheel(true)
	flow:SetScript("OnMouseWheel", function(self, delta)
		local _, maximum = self.bar:GetMinMaxValues()
		self.bar:SetValue(math.max(0, math.min(maximum, (self.bar:GetValue() or 0) - delta * 40)))
	end)
	flow:SetScript("OnSizeChanged", function(self)
		self.child:SetWidth(math.max(self.scroll:GetWidth() or 10, 10))
		if self.onResize then self.onResize(self) end
		if self.virtual then self:Fill() end
	end)
	flow.pools, flow.used = {}, {}
	flow.queue, flow.head, flow.pending = {}, 1, 0
	flow.y = 0

	function flow:Width()
		return math.max((self.scroll:GetWidth() or 0), 100)
	end

	function flow:Begin()
		for _, widget in ipairs(self.used) do
			widget:Hide()
			widget:ClearAllPoints()
			table.insert(self.pools[widget.flowKind], widget)
		end
		wipe(self.used)
		wipe(self.queue)
		self.head, self.pending, self.building, self.filling = 1, 0, false, false
		self.y = 0
		self.child:SetWidth(self:Width())
	end

	-- Blocks still waiting to be built (virtual flows).
	function flow:Pending()
		return self.head <= #self.queue
	end

	local function BuildNext(self)
		local entry = self.queue[self.head]
		self.queue[self.head] = false
		self.head = self.head + 1
		self.pending = math.max(0, self.pending - entry.estimate)
		self.building = true
		entry.build(self)
		self.building = false
	end

	-- A block placed directly after queued ones: build the queue first.
	local function Catchup(self)
		if self.building or not self:Pending() then return end
		while self:Pending() do BuildNext(self) end
	end

	-- A widget of a kind; create(child) builds a new one.
	function flow:Take(kind, create)
		Catchup(self)
		self.pools[kind] = self.pools[kind] or {}
		local widget = table.remove(self.pools[kind])
		if not widget then
			widget = create(self.child)
			widget.flowKind = kind
		end
		self.used[#self.used + 1] = widget
		widget:Show()
		return widget
	end

	-- Place a widget at the current line; indent from the left, the full width.
	function flow:Place(widget, height, indent, gap)
		Catchup(self)
		widget:ClearAllPoints()
		widget:SetPoint("TOPLEFT", self.child, "TOPLEFT", indent or 0, -self.y)
		widget:SetPoint("TOPRIGHT", self.child, "TOPRIGHT", 0, -self.y)
		widget:SetHeight(height)
		self.y = self.y + height + (gap or 0)
		return widget
	end

	function flow:Space(height)
		Catchup(self)
		self.y = self.y + (height or 8)
	end

	-- A block built by build(flow), on a virtual flow only once it comes
	-- into view. estimate: its height in pixels, for the scroll bar.
	function flow:Defer(estimate, build)
		if not self.virtual or self.building then
			build(self)
			return
		end
		self.queue[#self.queue + 1] = { estimate = math.max(tonumber(estimate) or 0, 0), build = build }
		self.pending = self.pending + math.max(tonumber(estimate) or 0, 0)
	end

	-- The child's height and the scroll range: what is built plus the
	-- estimate of what is not yet.
	local function Range(self)
		local total = self.y + self.pending
		self.child:SetHeight(math.max(total, 1))
		local maximum = math.max(0, total - (self.scroll:GetHeight() or 0))
		self.bar:SetMinMaxValues(0, maximum)
		self.bar:SetShown(maximum > 0)
		return maximum
	end

	-- Builds the queued blocks down to the bottom of the view (from top).
	function flow:Fill(top)
		if self.filling or self.building or not self:Pending() then return end
		self.filling = true
		local bottom = (top or self.bar:GetValue() or 0) + (self.scroll:GetHeight() or 0) + FILL_MARGIN
		local built = false
		while self:Pending() and self.y < bottom do
			BuildNext(self)
			built = true
		end
		if built then Range(self) end
		self.filling = false
	end

	function flow:Finish(keepScroll)
		local want = keepScroll and (self.bar:GetValue() or 0) or 0
		if self.virtual then self:Fill(want) end
		local maximum = Range(self)
		self.bar:SetValue(math.min(want, maximum))
		self.scroll:SetVerticalScroll(math.min(self.bar:GetValue() or 0, maximum))
	end

	return flow
end

---------------------------------------------------------------------------
-- Small parts
---------------------------------------------------------------------------
function P.Caption(parent)
	local fs = Kit.Text(parent, 10, "LEFT", "secondary")
	fs:SetWordWrap(false)
	return fs
end

-- Pill: a chip whose text color carries the meaning.
function P.Pill(parent)
	return Kit.Chip(parent, "")
end

function P.Art(parent, size)
	local box = CreateFrame("Frame", nil, parent)
	box:SetSize(size, size)
	E:SetTemplate(box)
	box.icon = box:CreateTexture(nil, "ARTWORK")
	box.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	box.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(box.icon)
	return box
end

function P.Back(parent, label, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(120, 18)
	-- A kit chevron instead of the letter <.
	button.arrow = E.UIKit.Chevron(button, "left", 9)
	button.arrow:SetPoint("LEFT")
	button.text = Kit.Text(button, 11, "LEFT", "secondary")
	button.text:SetPoint("LEFT", button.arrow, "RIGHT", 3, 0)
	button:SetScript("OnEnter", function(self)
		self.text:SetTextColor(E:TokenColor("accent"))
		self.arrow:SetVertexColor(Kit.Accent())
	end)
	button:SetScript("OnLeave", function(self)
		Kit.Paint(self.text, "secondary")
		self.arrow:SetVertexColor(unpack(E.tokens.text.secondary))
	end)
	function button:SetLabel(text)
		self.text:SetText(E:Translate(text) or L["Back"])
		self:SetWidth(math.ceil(self.text:GetStringWidth()) + 18)
	end
	button:SetLabel(label)
	button:SetScript("OnClick", onClick)
	Kit.Tooltip(button, L["Back"], L["Goes back to the list you came from."])
	return button
end

-- A text-only toggle chip (filters): accent text when on.
function P.Toggle(parent, label, onClick, tipTitle, tipText)
	local button = CreateFrame("Button", nil, parent)
	button:SetHeight(18)
	E:SetTemplate(button, true)
	button.text = Kit.Text(button, 11, "CENTER", "secondary")
	button.text:SetPoint("CENTER")
	-- menu = true: the toggle opens a menu, a kit chevron says so (no
	-- trailing letter v).
	function button:SetLabel(text, menu)
		self.text:SetText(E:Translate(text))
		if menu and not self.arrow then
			self.arrow = E.UIKit.Chevron(self, "down", 8)
			self.arrow:SetPoint("RIGHT", -5, 0)
		end
		if self.arrow then self.arrow:SetShown(menu and true or false) end
		self.text:ClearAllPoints()
		self.text:SetPoint("CENTER", menu and -5 or 0, 0)
		self:SetWidth(math.ceil(self.text:GetStringWidth()) + (menu and 26 or 14))
	end
	function button:SetOn(on)
		self.on = on and true or false
		if self.on then
			self.text:SetTextColor(E:TokenColor("accent"))
			self:SetBackdropBorderColor(Kit.Accent())
			if self.arrow then self.arrow:SetVertexColor(Kit.Accent()) end
		else
			Kit.Paint(self.text, "secondary")
			self:SetBackdropBorderColor(unpack(E.media.borderColor))
			if self.arrow then self.arrow:SetVertexColor(unpack(E.tokens.text.secondary)) end
		end
	end
	button:SetLabel(label)
	button:SetOn(false)
	button:SetScript("OnClick", onClick)
	Kit.Tooltip(button, E:Translate(tipTitle or label), E:Translate(tipText))
	return button
end

-- "17-26" colored: green when it fits your level, yellow near it, gray otherwise.
function P.LevelText(info, level)
	if not (info and info.min and info.max) then return "" end
	local fit = LG:FitsLevel(info, level)
	local color = fit == "fit" and Kit.GOOD or fit == "near" and Kit.WARN or Kit.DIM
	local text = info.min == info.max and tostring(info.min) or ("%d-%d"):format(info.min, info.max)
	return Kit.Hex(unpack(color)) .. text .. "|r"
end

function P.SizeText(info)
	if not info then return "" end
	if info.size and info.size > 5 then return E:Plural(info.size, "%d player", "%d players"):format(info.size) end
	return L["5 players"]
end

---------------------------------------------------------------------------
-- Instance stats: upgrades (unique items that beat what you wear), wished
-- items, open and done quests, known drops. Cached until the bus says
-- something moved.
---------------------------------------------------------------------------
local statsCache = {}
LG:On("pages-stats", function(changed)
	if changed.data or changed.gear or changed.list or changed.spec or changed.rank or changed.wishlist or changed.quests
		or changed.player or changed.bags or changed.settings then
		wipe(statsCache)
	end
end)

function P.ClearStats()
	wipe(statsCache)
end

local function Upgrade(itemID)
	if not LG:BiSOn() then return false end
	local targets = LG:UpgradeTargets(itemID)
	return targets[1] ~= nil and not LG:Owns(itemID)
end
P.IsUpgrade = Upgrade

function P.InstanceStats(key)
	local stats = statsCache[key]
	if stats then return stats end
	stats = { upgrades = 0, wished = 0, drops = 0, quests = 0, open = 0, done = 0 }
	local loot = LG:InstanceLoot(key)
	local seen = {}
	local level = LG:Player().level
	local function Count(itemID)
		if seen[itemID] then return end
		seen[itemID] = true
		stats.drops = stats.drops + 1
		if LG:IsWished(itemID) then stats.wished = stats.wished + 1 end
		local useLevel = LG:UseLevel(itemID) or 1
		if useLevel <= level + 3 and Upgrade(itemID) then stats.upgrades = stats.upgrades + 1 end
	end
	for _, boss in ipairs(loot.bosses) do
		for _, drop in ipairs(boss.loot) do Count(drop.itemID) end
	end
	for _, drop in ipairs(loot.trash) do Count(drop.itemID) end
	stats.quests, stats.open, stats.done = LG:InstanceQuestCounts(key)
	statsCache[key] = stats
	return stats
end

---------------------------------------------------------------------------
-- Instance tooltip
---------------------------------------------------------------------------
function P.InstanceTooltip(tooltip, key)
	local info = LG:InstanceInfo(key)
	if not info then return end
	local r, g, b = unpack(Kit.SECONDARY)
	E.UIKit.TipTitle(tooltip, info.name)
	local _, confidence = LG:Confidence(key)
	tooltip:AddDoubleLine(L["Level"], P.LevelText(info), r, g, b, 1, 1, 1)
	if info.gameRange then tooltip:AddLine(L["The game's recommended levels."], r, g, b) end
	if info.enterLevel then tooltip:AddDoubleLine(L["Enter from level"], tostring(info.enterLevel), r, g, b, 1, 1, 1) end
	local zone = LG:InstanceZone(key)
	if zone then tooltip:AddDoubleLine(L["Zone"], zone, r, g, b, 1, 1, 1) end
	tooltip:AddDoubleLine(L["Group"], P.SizeText(info), r, g, b, 1, 1, 1)
	tooltip:AddDoubleLine(L["Loot"], confidence, r, g, b, 1, 1, 1)
	local opens = LG:PhaseOpensText(info.phase, true)
	if opens then tooltip:AddDoubleLine(L["Opens"], opens, r, g, b, 1, 1, 1) end
	local stats = P.InstanceStats(key)
	if info.bosses and info.bosses > 0 then tooltip:AddDoubleLine(L["Bosses"], tostring(info.bosses), r, g, b, 1, 1, 1) end
	if stats.drops > 0 then tooltip:AddDoubleLine(L["Known drops"], tostring(stats.drops), r, g, b, 1, 1, 1) end
	if stats.quests > 0 then
		tooltip:AddDoubleLine(L["Quests for you"], (L["%d open, %d done"]):format(stats.open, stats.done), r, g, b, 1, 1, 1)
	end
	if stats.upgrades > 0 then
		local gr, gg, gb = unpack(Kit.GOOD)
		tooltip:AddDoubleLine(L["Upgrades for you"], tostring(stats.upgrades), r, g, b, gr, gg, gb)
	end
	if stats.wished > 0 and LG:WishlistOn() then
		tooltip:AddDoubleLine(L["On your wishlist"], tostring(stats.wished), r, g, b, 1, 0.82, 0)
	end
	tooltip:AddLine(" ")
	E:TooltipHint(tooltip, { L["Click"], L["open it in the Journal"] })
end

---------------------------------------------------------------------------
-- Instance tile: used by the Journal home and For You
---------------------------------------------------------------------------
local TILE_ART = 40

function P.InstanceTile(parent, onClick)
	local tile = CreateFrame("Button", nil, parent)
	tile:SetHeight(64)
	E:SetTemplate(tile, true)
	tile.hover = tile:CreateTexture(nil, "HIGHLIGHT")
	tile.hover:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	tile.hover:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:AccentTexture(tile.hover, 0.12)
	tile.art = P.Art(tile, TILE_ART)
	tile.art:SetPoint("TOPLEFT", 8, -8)
	tile.name = Kit.Text(tile, 13, "LEFT")
	tile.name:SetPoint("TOPLEFT", tile.art, "TOPRIGHT", 8, 0)
	tile.name:SetPoint("TOPRIGHT", -8, -8)
	tile.name:SetWordWrap(false)
	tile.sub = Kit.Text(tile, 11, "LEFT", "secondary")
	tile.sub:SetPoint("TOPLEFT", tile.name, "BOTTOMLEFT", 0, -3)
	tile.sub:SetPoint("TOPRIGHT", tile.name, "BOTTOMRIGHT", 0, -3)
	tile.sub:SetWordWrap(false)
	tile.pills = {}
	tile.fit = Kit.LevelFit(tile, 100)
	tile.fit:SetPoint("BOTTOMLEFT", tile.art, "BOTTOMRIGHT", 8, 0)
	tile.fit:SetPoint("BOTTOMRIGHT", tile, "TOPRIGHT", -8, -(8 + TILE_ART)) -- the art's bottom
	tile:SetScript("OnClick", function(self)
		if self.key and onClick then onClick(self.key) end
	end)
	tile:SetScript("OnEnter", function(self)
		if not self.key then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		P.InstanceTooltip(GameTooltip, self.key)
		GameTooltip:Show()
	end)
	tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
	function tile:SetInstance(key)
		self.key = key
		local info = LG:InstanceInfo(key)
		if not info then self:Hide() return end
		local icon = LG:InstanceArt(key)
		self.art.icon:SetTexture(icon)
		-- Announced, not open yet or not in WoW: Forever yet: grayed out.
		local announced = not LG:OpenNow(info)
		self.art.icon:SetDesaturated(announced)
		self.name:SetText(info.name)
		if announced then Kit.Paint(self.name, "dim") else Kit.Paint(self.name) end
		local bits = { P.LevelText(info), P.SizeText(info) }
		local _, confidence = LG:Confidence(key)
		-- A WoW: Forever dungeon names its zone, the rest how much is known.
		local zone = info.forever and LG:InstanceZone(key)
		if zone then
			bits[#bits + 1] = zone
		elseif info.status ~= "classic" then
			bits[#bits + 1] = confidence
		end
		self.sub:SetText(table.concat(bits, "  ·  "))
		local stats = P.InstanceStats(key)
		local pills = {}
		if stats.upgrades > 0 then pills[#pills + 1] = { E:Plural(stats.upgrades, "%d upgrade", "%d upgrades"):format(stats.upgrades), Kit.GOOD } end
		if stats.open > 0 then pills[#pills + 1] = { E:Plural(stats.open, "%d quest", "%d quests"):format(stats.open), Kit.WARN } end
		if stats.wished > 0 and LG:WishlistOn() then pills[#pills + 1] = { (L["%d wished"]):format(stats.wished), { 1, 0.82, 0 } } end
		-- Not open yet: the day it opens.
		local _, phase = LG:PhaseBadge({ phase = info.phase })
		if phase then pills[#pills + 1] = { LG:PhaseOpensText(phase), { 0.85, 0.7, 0.4 } } end
		local anchor = nil
		for index = 1, math.max(#pills, #self.pills) do
			local data = pills[index]
			local pill = self.pills[index]
			if data and not pill then
				pill = P.Pill(self)
				self.pills[index] = pill
			end
			if pill then
				pill:SetShown(data ~= nil)
				if data then
					pill:SetLabel(data[1], unpack(data[2]))
					pill:ClearAllPoints()
					if anchor then pill:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0) else pill:SetPoint("TOPRIGHT", self, "TOPRIGHT", -8, -8) end
					anchor = pill
				end
			end
		end
		if info.min and info.max then self.fit:SetRange(info.min, info.max, nil, tonumber(LG.db.levelWindow) or 3) else self.fit:Hide() end
		self:Show()
	end
	return tile
end

---------------------------------------------------------------------------
-- Source lines
---------------------------------------------------------------------------
local RANK = E:TranslateValues({ [1] = E.Key("Elite"), [2] = E.Key("Rare elite"), [3] = E.Key("Boss"), [4] = E.Key("Rare") })
P.RANK = RANK
-- Outside instances a boss-rank creature is a world boss.
local WORLD_RANK = E:TranslateValues({ [1] = E.Key("Elite"), [2] = E.Key("Rare elite"), [3] = E.Key("World boss"), [4] = E.Key("Rare") })
P.WORLD_RANK = WORLD_RANK

-- One line for a source entry (LG:ItemSources).
function P.SourceLine(entry)
	if not entry then return "" end
	local kind = entry.kind
	if kind == "world" then
		if entry.minLevel and entry.maxLevel then return (L["Random world drop, level %d-%d"]):format(entry.minLevel, entry.maxLevel) end
		return L["Random world drop"]
	elseif kind == "quest" or kind == "choice" then
		local title = LG:QuestTitle(entry.id) or ("#" .. tostring(entry.id))
		return (kind == "choice" and L["Quest choice: %s"] or L["Quest reward: %s"]):format(title)
	elseif kind == "crafted" then
		local craft = LG:Craft(entry.id)
		local skill = craft and craft.skill and C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName
			and C_TradeSkillUI.GetTradeSkillDisplayName(craft.skill)
		if Secret(skill) then skill = nil end
		return skill and (L["Crafted (%s)"]):format(skill) or L["Crafted"]
	elseif kind == "vendor" or kind == "repvendor" or kind == "pvpvendor" then
		return (L["Sold by %s"]):format(entry.name or L["NPC %s"]:format(tostring(entry.id)))
	elseif kind == "token" then
		local record = LG:ItemRecord(entry.id)
		return (L["For %s"]):format(record and record.name or ("item:" .. tostring(entry.id)))
	end
	local name = entry.name or (kind == "npc" and L["NPC %s"]:format(tostring(entry.id))) or L["Container"]
	if entry.instance then return name .. " · " .. (LG:InstanceName(entry.instance) or entry.instance) end
	if WORLD_RANK[entry.rank or 0] then return name .. " · " .. WORLD_RANK[entry.rank] end
	return name
end

-- The best drop chance of an item (for a row's right column).
function P.BestChance(itemID)
	local best
	for _, entry in ipairs(LG:ItemSources(itemID) or {}) do
		if (entry.kind == "npc" or entry.kind == "object") and type(entry.chance) == "number" then
			if not best or entry.chance > best then best = entry.chance end
		end
	end
	return best
end

-- Drop chance right-column text by the Drop chances option: "12%",
-- "seen 3/17" or both.
function P.ChanceData(chance, npc, itemID)
	local mode = LG.db.dropRates
	local data = {}
	if (mode == "classic" or mode == "both") and type(chance) == "number" then data.chance = chance end
	if (mode == "seen" or mode == "both") and npc then
		local drops, kills = LG:Seen(npc, itemID)
		if drops and kills then data.seen = (L["seen %d/%d"]):format(drops, kills) end
	end
	return data
end

---------------------------------------------------------------------------
-- Item cells: the shared cell (Kit.ItemCell) plus a clickable star.
---------------------------------------------------------------------------
-- Adds a star button over the cell's star; a click toggles the wishlist
-- (DESIGN: filled when on, outline on hover when off).
function P.ItemCell(parent)
	local cell = Kit.ItemCell(parent)
	cell.starButton = CreateFrame("Button", nil, cell)
	cell.starButton:SetSize(16, 16)
	cell.starButton:SetPoint("CENTER", cell.star, "CENTER")
	cell.starButton:SetScript("OnClick", function(self)
		local data = self:GetParent().data
		if data and data.itemID and LG:WishlistOn() then LG:ToggleWished(data.itemID) end
	end)
	Kit.Tooltip(cell.starButton, L["Wishlist"], nil, { { L["Click"], L["add or remove this item"] }, { L["Right-click the row"], L["notes and more"] } })
	cell:HookScript("OnEnter", function(self)
		if self.data and LG:WishlistOn() and not LG:IsWished(self.data.itemID) then
			self.star:SetShown(true)
			self.star:SetAlpha(0.35)
		end
	end)
	cell:HookScript("OnLeave", function(self)
		if self.data and not (LG:WishlistOn() and LG:IsWished(self.data.itemID)) then self.star:Hide() end
		self.star:SetAlpha(1)
	end)
	return cell
end

-- Kit.SetItem plus the seen text and the "Forever" tag in the right column.
function P.SetItem(cell, data)
	Kit.SetItem(cell, data)
	if not data then return end
	cell.starButton:SetShown(LG:WishlistOn())
	local right = cell.right:GetText() or ""
	local extra = {}
	if data.seen then extra[#extra + 1] = E:TextHex("secondary") .. data.seen .. "|r" end
	if data.badge then extra[#extra + 1] = data.badge end
	if #extra > 0 then
		cell.right:SetText(table.concat(extra, "  ") .. (right ~= "" and ("  " .. right) or ""))
	end
	if data.dim then
		cell.name:SetAlpha(0.5)
		cell.icon:SetAlpha(0.5)
	else
		cell.name:SetAlpha(1)
	end
end

---------------------------------------------------------------------------
-- Status glyphs for quests
---------------------------------------------------------------------------
-- Done and locked are the kit's check and cross, tinted in the status
-- color (a texture in the text keeps its own color, so it is passed in) and
-- sized to the font; they are made when read, so a theme or color-blind
-- change shows at once. The other states stay the game's quest marks.
local QUEST_MARKS = { turnin = "?", active = "!", available = "!", low = "-", notforyou = "-" }
local QUEST_GLYPHS = { done = "check", locked = "cross" }

function P.QuestGlyph(status)
	local glyph = QUEST_GLYPHS[status]
	if glyph then return E.UIKit.InlineGlyph(glyph, 0, { P.QuestStatusColor(status) }) end
	return QUEST_MARKS[status]
end

P.QUEST_GLYPH = setmetatable({}, { __index = function(_, status) return P.QuestGlyph(status) end })

function P.QuestStatusColor(status)
	if status == "turnin" or status == "available" then return unpack(E.tokens.text.gold) end
	if status == "active" then return Kit.Accent() end
	if status == "done" then return unpack(Kit.GOOD) end
	if status == "locked" then return unpack(Kit.BAD) end
	return unpack(Kit.DIM)
end

function P.MoneyText(copper)
	copper = tonumber(copper)
	if not copper or copper <= 0 then return end
	return E:FormatMoney(copper)
end

-- Opening an item: the item page, the boss, the quest or a search,
-- by LG:ItemRoute (ItemPage.lua).
function P.OpenItem(itemID)
	local key, arg = LG:ItemRoute(itemID)
	LG:Open(key, arg)
end

---------------------------------------------------------------------------
-- Flow blocks: text, captions, item rows and lines with a button.
---------------------------------------------------------------------------
local function TextBlock(child)
	local block = CreateFrame("Frame", nil, child)
	block.text = Kit.Text(block, 12, "LEFT")
	block.text:SetPoint("TOPLEFT")
	block.text:SetSpacing(2)
	return block
end

-- Wrapped text; kind as Kit.Text ("secondary", "header", "dim").
function P.FlowText(flow, text, size, kind, indent, gap)
	local block = flow:Take("text", TextBlock)
	E:SetFont(block.text, size or E.tokens.size.label)
	Kit.Paint(block.text, kind)
	block.text:SetWordWrap(true)
	block.text:SetWidth(math.max(flow:Width() - (indent or 0), 40))
	block.text:SetText(text or "")
	local height = math.max(math.ceil(block.text:GetStringHeight() or 0), (size or 12) + 2)
	return flow:Place(block, height, indent, gap or 4)
end

-- An upper-case caption with an optional gray note after it. A note that
-- doesn't fit beside the caption (a narrow page, a longer language) goes
-- below it, wrapped, instead of being cut.
function P.FlowCaption(flow, text, note)
	flow:Space(6)
	local block = flow:Take("caption", TextBlock)
	E:SetFont(block.text, E.tokens.size.tiny)
	block.text:SetWordWrap(false)
	block.text:SetSpacing(0)
	local width = math.max(flow:Width(), 40)
	block.text:SetWidth(width)
	local caption = E:TextHex("accent") .. E:CaptionText(E:Translate(text) or "") .. "|r"
	local tail = note and (E:TextHex("secondary") .. E:Translate(note) .. "|r")
	block.text:SetText(tail and (caption .. "  " .. tail) or caption)
	local height = 14
	if tail and block.text:GetStringWidth() > width then
		block.text:SetWordWrap(true)
		block.text:SetText(caption .. "\n" .. tail)
		height = math.max(28, math.ceil(block.text:GetStringHeight()) + 4)
	end
	block.text:SetTextColor(1, 1, 1)
	flow:Place(block, height, 0, 2)
	local rule = flow:Take("rule", function(child)
		local frame = CreateFrame("Frame", nil, child)
		frame.line = Kit.Divider(frame)
		frame.line:SetPoint("LEFT")
		frame.line:SetPoint("RIGHT")
		return frame
	end)
	flow:Place(rule, 1, 0, 4)
end

-- An item row (P.ItemCell) at list height.
function P.FlowItem(flow, data, indent)
	local cell = flow:Take("item", P.ItemCell)
	flow:Place(cell, math.max(Kit.RowHeight(), 20), indent, 2)
	P.SetItem(cell, data)
	return cell
end

local function LineBlock(child)
	local row = CreateFrame("Button", nil, child)
	row.text = Kit.Text(row, 12, "LEFT")
	row.text:SetWordWrap(false)
	row.button = Kit.Button(row, " ", 60, 18)
	row.button:SetPoint("RIGHT", -2, 0)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	return row
end

-- A one-line row: text, an optional click on the row and an optional
-- button on the right ({ label, fn, tipTitle, tipText, disabled }).
function P.FlowLine(flow, text, onClick, button, tipTitle, tipText, indent)
	local row = flow:Take("line", LineBlock)
	flow:Place(row, 20, indent, 2)
	row.text:SetText(text or "")
	row:SetScript("OnClick", onClick)
	row.hover:SetShown(onClick ~= nil)
	Kit.Tooltip(row, tipTitle, tipText)
	row.text:ClearAllPoints()
	row.text:SetPoint("LEFT", 4, 0)
	if button then
		row.button:SetText(E:Translate(button[1]))
		local label = row.button:GetFontString()
		row.button:SetWidth(math.max(56, math.ceil((label and label:GetStringWidth() or 40) + 18)))
		row.button:SetScript("OnClick", button[2])
		Kit.Tooltip(row.button, E:Translate(button[3] or button[1]), E:Translate(button[4]))
		row.button:SetEnabled(not button[5])
		row.button:Show()
		row.text:SetPoint("RIGHT", row.button, "LEFT", -6, 0)
	else
		row.button:Hide()
		row.text:SetPoint("RIGHT", -4, 0)
	end
	return row
end

-- A Map button for a creature or object: pins its camp (the next camp on
-- each click, then off) or the entrance of the dungeon it stands in. A
-- table for P.FlowLine; disabled with a reason when no place is known.
function P.MapButton(kind, id, title)
	local camps = LG:SpawnPoints(kind, id)
	local point = camps[1] and LG:PointFor(camps[1])
	if not point then
		return { L["Map"], nil, L["Map"], L["The loot data has no place on your map for this."], true }
	end
	local tip
	if #camps > 1 then
		tip = E:Plural(#camps, "Pins the biggest of %d camps on your map. Click again for the next one; after the last the pin goes away.", "Pins the biggest of %d camps on your map. Click again for the next one; after the last the pin goes away."):format(#camps)
	else
		tip = L["Pins the place on your map and turns on the arrow. Click again to take the pin away."]
	end
	return { L["Map"], function() LG:CycleCamps(kind, id, title) end, L["Map"], tip }
end
