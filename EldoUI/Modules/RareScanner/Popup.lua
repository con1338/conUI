-- Rare Alerts: the alert card. A secure button the player clicks to
-- target the rare: "/cleartarget" + "/targetexact <name>" (and "/tm" when
-- "Mark when you click the card" is on). Right-click and the x close it
-- through a secure snippet, so closing works in combat too.
--
--   +------------------------------------------------------------+
--   | +--------+  MINIMAP                                 2m  [x] |  source chip, time
--   | | model  |  Lord Kazzak                                     |  name
--   | | 72x72  |  Rare elite · 60                                 |  classification, level
--   | |        |  Blasted Lands  45.2, 33.8                       |  zone and coordinates
--   | +--------+  [mount][pet]                       +2 waiting   |  notable drops, queue
--   +------------------------------------------------------------+
--
-- A treasure or event card (no creature) has no target action: its left
-- click sets a waypoint, and the glyph is the game's own marker atlas.
--
-- Rules: the cards are made out of combat; attributes, Show, Hide, size and
-- position change only out of combat (E:RunOutOfCombat). A sighting in
-- combat shows a text toast (E:PushAlert) and the card follows after
-- combat. Only the player's click targets or marks; nothing clicks the card
-- for them. Shift-click fills the chat box and sends nothing.
--
-- The cards are a holder of EldoUI's one notice queue (Core/Alerts.lua),
-- under their own "Rare Alerts" mover: the queue holds the rares that wait
-- for a free card or the end of combat, closes a card after its time
-- (never while the mouse is over it) and ticks the "2m" times once a
-- second while a card is up.
local _, E = ...
local L = E.L
local M = E.RareScanner

local POOL = 4
local GAP = 4      -- between stacked cards
local LINE = 2     -- between text lines on a card
local PAD = 8
local QUEUE_MAX = 10
local DEAD_CLOSE = 5
M.MOVER = "EldoUI_RareAlert"
M.DEFAULT_POINT = { "TOP", "UIParent", "TOP", -550, -196 }

local cards = {}   -- all cards, made once
local shown = {}   -- cards on screen, top first
local queue = {}   -- infos waiting for a free card or the end of combat (kept by the notice queue)
M.cards, M.shownCards, M.queue = cards, shown, queue

local SOURCE_LABEL = {
	vignette = "Minimap", nameplate = "Nameplate", target = "Target", mouseover = "Mouseover",
	group = "Group", chat = E.Key("Yell"), test = "Test",
}
local CLASS_LABEL = { rare = "Rare", rareelite = "Rare elite", worldboss = "World boss" }
-- Kind lines, translated where they are shown: L["Treasure"], L["Event"]
local KIND_LABEL = { treasure = "Treasure", event = "Event" }
local KIND_ATLAS = { treasure = "VignetteLoot", event = "VignetteEvent" }
M.SOURCE_LABEL, M.CLASS_LABEL, M.KIND_LABEL = SOURCE_LABEL, CLASS_LABEL, KIND_LABEL

local IsMarker = M.IsMarker

local function Text(color)
	return E.tokens.text[color]
end

---------------------------------------------------------------------------
-- Click actions (insecure, after the secure click)
---------------------------------------------------------------------------
-- The chat type a shared line goes to: the player's pick, or for "group"
-- the group they are in (instance, raid, party), else Say. A pick the
-- player is not in (Raid while in a party) falls back to the same rule.
local GROUP_TYPES = { party = "PARTY", raid = "RAID", say = "SAY" }
function M:ShareChatType()
	local pick = self.db.shareTo
	local instance = LE_PARTY_CATEGORY_INSTANCE or 2
	local inInstance = M.Read(IsInGroup, instance) == true
	local inRaid = M.Read(IsInRaid) == true
	local inGroup = M.Read(IsInGroup) == true
	if pick == "say" then return "SAY" end
	if pick == "raid" and inRaid then return "RAID" end
	if pick == "party" and inGroup then return "PARTY" end
	if inInstance then return "INSTANCE_CHAT" end
	if inRaid then return "RAID" end
	if inGroup then return "PARTY" end
	return "SAY"
end
M.SHARE_TYPES = GROUP_TYPES

-- The game's own map pin link for the sighting's place, after setting the
-- player's map pin there (the option says so). nil when the game makes none.
function M:SharePin(info)
	if not self.db.sharePin then return nil end
	local mapPoint = rawget(_G, "UiMapPoint")
	if type(info.uiMapID) ~= "number" or type(info.x) ~= "number" or type(info.y) ~= "number" then return nil end
	if not (C_Map and C_Map.SetUserWaypoint and C_Map.GetUserWaypointHyperlink and mapPoint and mapPoint.CreateFromCoordinates) then return nil end
	if C_Map.CanSetUserWaypointOnMap and M.Read(C_Map.CanSetUserWaypointOnMap, info.uiMapID) == false then return nil end
	local point = M.Read(mapPoint.CreateFromCoordinates, info.uiMapID, info.x, info.y)
	if not point then return nil end
	local ok = pcall(C_Map.SetUserWaypoint, point)
	if not ok then return nil end
	local link = M.Read(C_Map.GetUserWaypointHyperlink)
	if type(link) ~= "string" or link == "" then return nil end
	return link
end

-- "Rare: Lord Kazzak (Blasted Lands 45.2, 33.8) [map pin]". Only plain
-- values: no health, and a secret name or zone is never shared.
function M:ShareLine(info)
	local name = info.name
	if type(name) ~= "string" or M.Secret(name) or name == "" then return nil end
	local title = info.kind == "treasure" and L["Treasure: %s"] or info.kind == "event" and L["Event: %s"] or L["Rare: %s"]
	local text = title:format(name)
	local place = {}
	if type(info.zone) == "string" and not M.Secret(info.zone) and info.zone ~= "" then place[#place + 1] = info.zone end
	local coords = self.Coords(info.x, info.y)
	if coords then place[#place + 1] = coords end
	if #place > 0 then text = text .. " (" .. table.concat(place, " ") .. ")" end
	if info.dead then text = text .. " " .. L["(dead)"] end
	local link = self:SharePin(info)
	if link then text = text .. " " .. link end
	return text
end

-- Open the chat box on the share channel with the line in it; the player
-- presses Enter to send it. EldoUI never sends it.
function M:Share(info)
	local line = self:ShareLine(info)
	if not line then return false end
	local util = rawget(_G, "ChatFrameUtil")
	local open = (util and util.OpenChat) or rawget(_G, "ChatFrame_OpenChat")
	if type(open) ~= "function" then return false end
	local ok, editBox = pcall(open, line)
	if not ok then
		geterrorhandler()(editBox)
		return false
	end
	if type(editBox) == "table" and editBox.SetChatType then
		pcall(editBox.SetChatType, editBox, self:ShareChatType())
		if editBox.UpdateHeader then pcall(editBox.UpdateHeader, editBox) end
	end
	return true
end

function M:ShowOnMap(info)
	local lg = E.LootGuide
	if not lg then return false end
	if type(info.x) == "number" and type(info.uiMapID) == "number" and lg.SetWaypoint then
		lg:SetWaypoint({ uiMapID = info.uiMapID, x = info.x, y = info.y, zone = info.zone }, info.name)
		return true
	end
	if info.npc and lg.CycleCamps then
		local index = lg:CycleCamps("npc", info.npc, info.name)
		return (index or 0) > 0
	end
	return false
end

-- The Loot Guide's World page on the rare's zone (or the player's zone).
function M:ZoneOfRare(npc)
	local lg = E.LootGuide
	if not (npc and lg and lg.WorldZones) then return nil end
	local ok, index = pcall(lg.WorldZones, lg)
	if not ok or type(index) ~= "table" then return nil end
	for id, zone in pairs(index.zones or {}) do
		for _, rare in ipairs(zone.rares or {}) do
			if rare == npc then return id end
		end
	end
end

function M:OpenLootGuide(npc)
	local lg = E.LootGuide
	if not (lg and lg.active and lg.Open) then
		E:Print(E:ModuleOffHint("LootGuide"))
		return false
	end
	local zone = self:ZoneOfRare(npc)
	if not zone then zone = select(2, self.PlayerZone()) end
	lg:Open("world", zone)
	return true
end

local function OpenMenu(card)
	local info = card.info
	if not info then return end
	E.UIKit.ContextMenu(card.menuButton, function(_, root)
		root:CreateTitle(info.name)
		if info.key ~= "test" then
			local ignore = info.kind == "treasure" and L["Ignore this treasure"] or info.kind == "event" and L["Ignore this event"] or L["Ignore this rare"]
			root:CreateButton(ignore, function() M:Ignore(info.key) end)
		end
		if info.key ~= "test" and type(info.uiMapID) == "number" and not M:IsQuietZone(info.uiMapID) then
			root:CreateButton(L["Quiet this zone"], function() M:SetQuietZone(info.uiMapID, true) end)
		end
		if not IsMarker(info) then
			root:CreateButton(L["Open in Loot Guide"], function() M:OpenLootGuide(info.npc) end)
		end
		root:CreateButton(L["Show on map"], function() M:ShowOnMap(info) end)
		root:CreateButton(L["Share in chat"], function() M:Share(info) end)
	end, { at = "owner" })
end

---------------------------------------------------------------------------
-- Building the cards
---------------------------------------------------------------------------
local function ShowTooltip(card)
	local info = card.info
	if not info then return end
	GameTooltip:SetOwner(card, "ANCHOR_BOTTOM", 0, -4)
	E.UIKit.TipTitle(GameTooltip, info.name)
	local secondary = Text("secondary")
	if IsMarker(info) then
		E:TooltipHint(GameTooltip, { L["Click"], L["set a waypoint"] }, { L["Shift-click"], L["share in chat"] }, { L["Right-click"], L["close"] })
	else
		E:TooltipHint(GameTooltip, { L["Click"], L["target"] }, { L["Shift-click"], L["share in chat"] }, { L["Alt-click"], L["show on map"] },
			{ L["Ctrl-click"], L["Loot Guide"] }, { L["Right-click"], L["close"] })
	end
	for _, item in ipairs(info.notableItems or {}) do
		local name = C_Item and C_Item.GetItemNameByID and M.Read(C_Item.GetItemNameByID, item.itemID)
		local kind = item.kind == "mount" and L["Mount"] or item.kind == "pet" and L["Pet"] or item.kind == "set" and L["Set piece"] or L["Toy"]
		GameTooltip:AddDoubleLine(kind, name or ("#" .. item.itemID), secondary[1], secondary[2], secondary[3], 1, 1, 1)
	end
	GameTooltip:Show()
end

local function CreateCard(index)
	local card = CreateFrame("Button", "EldoUI_RareAlertButton" .. index, UIParent, "SecureActionButtonTemplate, BackdropTemplate")
	card:SetFrameStrata("DIALOG")
	card:SetClampedToScreen(true)
	card:RegisterForClicks("AnyUp")
	card:SetAttribute("useOnKeyDown", false)
	card:SetAttribute("type1", "macro")
	-- Modified left clicks do the insecure actions below instead of targeting.
	for _, modifier in ipairs({ "shift", "alt", "ctrl" }) do card:SetAttribute(modifier .. "-type1", "eldoinfo") end
	card:SetAttribute("*type2", "close")
	card:SetAttribute("_close", "self:Hide()")
	card:Hide()

	card.hover = card:CreateTexture(nil, "HIGHLIGHT")
	card.hover:SetAllPoints()
	card.hover:SetColorTexture(1, 1, 1, E.tokens.hover.control)
	card.topLine = card:CreateTexture(nil, "OVERLAY")
	card.topLine:SetPoint("TOPLEFT", 1, -1)
	card.topLine:SetPoint("TOPRIGHT", -1, -1)
	E:Hairline(card.topLine, "h", 2)
	card.topLine:Hide()

	card.box = CreateFrame("Frame", nil, card, "BackdropTemplate")
	card.box:EnableMouse(false)
	card.model = CreateFrame("PlayerModel", nil, card.box)
	card.model:SetPoint("TOPLEFT", 1, -1)
	card.model:SetPoint("BOTTOMRIGHT", -1, 1)
	card.model:EnableMouse(false)
	card.glyph = card.box:CreateTexture(nil, "ARTWORK")
	card.glyph:SetPoint("CENTER")

	card.source = E:CreateText(card, E.tokens.size.small, "LEFT")
	card.time = E:CreateText(card, E.tokens.size.small, "RIGHT")
	card.name = E:CreateText(card, E.tokens.size.cardTitle, "LEFT")
	card.sub = E:CreateText(card, E.tokens.size.small, "LEFT")
	card.zone = E:CreateText(card, E.tokens.size.small, "LEFT")
	card.waiting = E:CreateText(card, E.tokens.size.small, "RIGHT")
	for _, fs in ipairs({ card.name, card.sub, card.zone, card.source }) do fs:SetWordWrap(false) end
	card.icons = {}
	for i = 1, 4 do
		local holder = CreateFrame("Frame", nil, card, "BackdropTemplate")
		holder:SetSize(16, 16)
		holder:EnableMouse(false)
		E:SetTemplate(holder)
		holder.icon = holder:CreateTexture(nil, "ARTWORK")
		holder.icon:SetPoint("TOPLEFT", 1, -1)
		holder.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		E:TrimIcon(holder.icon)
		holder:Hide()
		card.icons[i] = holder
	end

	-- The x: its own secure button, so it closes the card in combat too.
	local close = CreateFrame("Button", nil, card, "SecureActionButtonTemplate, UIPanelCloseButtonNoScripts")
	close:SetSize(18, 18)
	close:SetPoint("TOPRIGHT", -2, -2)
	close:RegisterForClicks("AnyUp")
	close:SetAttribute("useOnKeyDown", false)
	close:SetAttribute("type", "closecard")
	close:SetAttribute("_closecard", "self:GetParent():Hide()")
	E:SkinCloseButton(close)
	card.close = close

	-- The card menu: an ordinary button (it only opens a menu).
	local menu = CreateFrame("Button", nil, card)
	menu:SetSize(18, 18)
	menu:SetPoint("RIGHT", close, "LEFT", -2, 0)
	menu.dots = E:CreateText(menu, E.tokens.size.body, "CENTER")
	menu.dots:SetPoint("CENTER", 0, 2)
	menu.dots:SetText("...")
	menu:SetScript("OnClick", function(self, button)
		if E:IsOptionsLinkClick(self, button) then return end
		OpenMenu(card)
	end)
	E:SkinHoverPress(menu)
	E.UIKit.Tooltip(menu, L["Rare Alerts"], L["Ignore this rare, open it in the Loot Guide or show it on the map."])
	-- The card itself is a secure target button whose modified clicks are
	-- taken (share, map, Loot Guide), so the menu button carries the link.
	E:BindOptionsLink(menu, { page = "module:RareScanner" })
	card.menuButton = menu

	card:HookScript("PostClick", function(self, button)
		if button ~= "LeftButton" or not self.info then return end
		if IsShiftKeyDown() then
			M:Share(self.info)
		elseif IsMarker(self.info) then
			M:ShowOnMap(self.info)
		elseif IsAltKeyDown() then
			M:ShowOnMap(self.info)
		elseif IsControlKeyDown() then
			M:OpenLootGuide(self.info.npc)
		end
	end)
	card:SetScript("OnEnter", function(self)
		self.hovered = true
		ShowTooltip(self)
	end)
	card:SetScript("OnLeave", function(self)
		self.hovered = nil
		GameTooltip:Hide()
	end)
	card:HookScript("OnHide", function(self) M:CardHidden(self) end)
	card.index = index
	return card
end

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------
local function Size()
	local db = M.db
	return math.max(160, tonumber(db.width) or 280), math.max(32, tonumber(db.height) or 88)
end

-- The panel, fonts and accent (also after a theme change).
function M:StyleCard(card)
	local db = self.db
	E:SetPanelTemplate(card, false)
	E:SetTemplate(card.box)
	local inset = E.tokens.inset
	card.box:SetBackdropColor(inset[1], inset[2], inset[3], inset[4])
	local size = math.max(10, math.min(18, tonumber(db.fontSize) or 13))
	E:SetHeaderFont(card.name, size + 1)
	for _, fs in ipairs({ card.sub, card.zone, card.source, card.time, card.waiting }) do E:SetFont(fs, math.max(9, size - 2)) end
	local body, secondary = Text("body"), Text("secondary")
	card.name:SetTextColor(body[1], body[2], body[3])
	for _, fs in ipairs({ card.zone, card.source, card.time, card.waiting }) do fs:SetTextColor(secondary[1], secondary[2], secondary[3]) end
end

-- Size and the place of every part for the current style.
function M:LayoutCard(card)
	local db = self.db
	local width, height = Size()
	card:SetSize(width, height)
	card:SetScale(math.max(0.6, math.min(1.6, tonumber(db.scale) or 1)))
	local boxSize = height - 2 * PAD
	local showModel = db.model and boxSize >= 24
	local left = PAD
	card.box:ClearAllPoints()
	if showModel then
		card.box:SetPoint("TOPLEFT", PAD, -PAD)
		card.box:SetSize(boxSize, boxSize)
		card.glyph:SetSize(math.floor(boxSize * 0.6), math.floor(boxSize * 0.6))
		card.box:Show()
		left = PAD + boxSize + PAD
	else
		card.box:Hide()
	end
	local small = math.max(9, (tonumber(db.fontSize) or 13) - 2)
	local nameSize = (tonumber(db.fontSize) or 13) + 1
	local y = -PAD
	-- Source chip and time share the top line when there is room for it.
	local chip = db.showSource and height >= 72
	card.source:ClearAllPoints()
	card.time:ClearAllPoints()
	card.time:SetPoint("TOPRIGHT", card, "TOPRIGHT", -46, -PAD)
	if chip then
		card.source:SetPoint("TOPLEFT", card, "TOPLEFT", left, y)
		card.source:SetPoint("TOPRIGHT", card.time, "TOPLEFT", -4, 0)
		card.source:Show()
		y = y - small - LINE
	else
		card.source:Hide()
	end
	card.name:ClearAllPoints()
	card.name:SetPoint("TOPLEFT", card, "TOPLEFT", left, y)
	card.name:SetPoint("TOPRIGHT", card, "TOPRIGHT", chip and -PAD or -46, y)
	y = y - nameSize - LINE
	local rows = { card.sub, card.zone }
	if height < 52 then
		-- A strip: name and zone only.
		rows = { card.zone }
		card.sub:Hide()
	end
	for _, fs in ipairs(rows) do
		fs:ClearAllPoints()
		if -y + small <= height - PAD + 2 then
			fs:SetPoint("TOPLEFT", card, "TOPLEFT", left, y)
			fs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PAD, y)
			fs:Show()
			y = y - small - LINE
		else
			fs:Hide()
		end
	end
	card.lootRoom = db.showLoot and (-y + 16 <= height - PAD + 4)
	for i, holder in ipairs(card.icons) do
		holder:ClearAllPoints()
		holder:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", left + (i - 1) * 20, PAD)
	end
	card.waiting:ClearAllPoints()
	card.waiting:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -PAD, PAD)
end

local function Ago(seconds)
	if seconds < 60 then return L["now"] end
	return L["%dm"]:format(seconds / 60)
end

-- Fill a card from a sighting. Attributes only out of combat.
function M:FillCard(card, info)
	local db = self.db
	card.info = info
	card.shownAt = card.shownAt or GetTime()
	if not InCombatLockdown() then
		if IsMarker(info) then
			-- Nothing to target: the click sets a waypoint (PostClick).
			card:SetAttribute("type1", "eldoinfo")
			card:SetAttribute("macrotext1", nil)
		else
			local macro = "/cleartarget\n/targetexact " .. info.name
			if db.markOnClick then macro = macro .. ("\n/tm [exists] %d"):format(db.marker) end
			card:SetAttribute("type1", "macro")
			card:SetAttribute("macrotext1", macro)
		end
	end
	card.source:SetText(L[SOURCE_LABEL[info.source] or "Rare"]:upper())
	card.name:SetText(info.name)
	local class = L[KIND_LABEL[info.kind] or CLASS_LABEL[info.classification] or "Rare"]
	if type(info.level) == "number" then
		local color = GetCreatureDifficultyColor and GetCreatureDifficultyColor(info.level)
		local hex = color and ("|cff%02x%02x%02x"):format(math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5)) or ""
		card.sub:SetText(("%s · %s%d|r"):format(class, hex, info.level))
	else
		card.sub:SetText(class)
	end
	-- The game says this character already has it: a short note after it.
	local entry = self.session[info.key]
	if info.done or (entry and entry.done) then
		card.sub:SetText(card.sub:GetText() .. "  " .. E:TokenHex(Text("good")) .. L["Already done"] .. "|r")
	end
	local secondary = Text("secondary")
	card.sub:SetTextColor(secondary[1], secondary[2], secondary[3])
	local coords = self.Coords(info.x, info.y)
	card.zone:SetText((info.zone or "") .. (coords and ("  " .. coords) or ""))

	-- Model: the data's display id, else the creature id, else the glyph.
	local modelShown = false
	if db.model and card.box:IsShown() and info.npc and not IsMarker(info) then
		local mob = self:Record(info.npc)
		local ok = false
		if mob and mob.display then ok = pcall(card.model.SetDisplayInfo, card.model, mob.display) end
		if not ok then ok = pcall(card.model.SetCreature, card.model, info.npc) end
		if ok then
			pcall(card.model.SetPortraitZoom, card.model, 0.6)
			modelShown = true
		end
	end
	card.model:SetShown(modelShown)
	card.glyph:SetShown(not modelShown)
	if not modelShown then
		local atlas = KIND_ATLAS[info.kind] or (info.classification == "rareelite" and "VignetteKillElite" or "VignetteKill")
		local icon = info.kind == "treasure" and "Interface\\Icons\\INV_Box_02" or info.kind == "event" and "Interface\\Icons\\INV_Misc_Note_01"
			or "Interface\\Icons\\Ability_Hunter_SniperShot"
		E:SetClientAtlas(card.glyph, atlas, icon)
	end

	-- Notable: the best collectable drop's quality color on the edge.
	local best
	for i, holder in ipairs(card.icons) do
		local item = card.lootRoom and info.notableItems and info.notableItems[i]
		if item then
			local icon = C_Item and C_Item.GetItemIconByID and M.Read(C_Item.GetItemIconByID, item.itemID)
			holder.icon:SetTexture(E:ClientIcon(icon))
			local quality = C_Item and C_Item.GetItemQualityByID and M.Read(C_Item.GetItemQualityByID, item.itemID)
			if type(quality) == "number" then
				local r, g, b = C_Item.GetItemQualityColor(quality)
				holder:SetBackdropBorderColor(r, g, b, 1)
				if not best or quality > best then best = quality end
			end
			holder:Show()
		else
			holder:Hide()
		end
	end
	if info.notable and not best and info.notableItems and info.notableItems[1] then best = 3 end
	if best and C_Item and C_Item.GetItemQualityColor then
		local r, g, b = C_Item.GetItemQualityColor(best)
		card:SetBackdropBorderColor(r, g, b, 1)
		card.topLine:SetColorTexture(r, g, b, 1)
		card.topLine:Show()
	else
		local border = E.media.borderColor
		card:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
		card.topLine:Hide()
	end
	self:PaintDead(card)
	self:UpdateTimes()
end

function M:PaintDead(card)
	local entry = card.info and self.session[card.info.key]
	local dead = (entry and entry.dead) or (card.info and card.info.dead)
	card:SetAlpha(dead and E.tokens.disabledAlpha or 1)
	if dead then
		local bad = Text("bad")
		card.time:SetText(L["Dead"])
		card.time:SetTextColor(bad[1], bad[2], bad[3])
	else
		local secondary = Text("secondary")
		card.time:SetTextColor(secondary[1], secondary[2], secondary[3])
	end
end

function M:UpdateTimes()
	local now = GetTime()
	for _, card in ipairs(shown) do
		local entry = card.info and self.session[card.info.key]
		if not (entry and entry.dead) and not (card.info and card.info.dead) then
			local text = Ago(now - (card.shownAt or now))
			if card.agoText ~= text then
				card.agoText = text
				card.time:SetText(text)
			end
		end
		card.waiting:SetText(#queue > 0 and L["+%d waiting"]:format(#queue) or "")
	end
end

---------------------------------------------------------------------------
-- Showing, closing, the queue
---------------------------------------------------------------------------
local function FreeCard()
	for _, card in ipairs(cards) do
		if not card:IsShown() and not card.busy then return card end
	end
end

local function Place()
	local anchor = M.anchor
	if not anchor or InCombatLockdown() then return end
	local _, height = Size()
	for i, card in ipairs(shown) do
		card:ClearAllPoints()
		card:SetPoint("TOP", anchor, "TOP", 0, -(i - 1) * (height + GAP))
	end
end

local function CardFor(key)
	for _, card in ipairs(shown) do
		if card.info and card.info.key == key then return card end
	end
end
M.CardFor = CardFor

function M:CloseCard(card)
	E:RunOutOfCombat(function() card:Hide() end)
end

function M:CloseKey(key)
	local card = CardFor(key)
	if card then self:CloseCard(card) end
	for i = #queue, 1, -1 do
		if queue[i].key == key then table.remove(queue, i) end
	end
	self:UpdateTimes()
end

-- OnHide of a card (Lua close, the secure snippet in combat, the module off).
function M:CardHidden(card)
	if card.timer then card.timer:Cancel() end
	card.timer, card.shownAt, card.agoText = nil, nil, nil
	for i, other in ipairs(shown) do
		if other == card then table.remove(shown, i) break end
	end
	card.info = nil
	-- Its place is free: the queue shows the next rare (out of combat).
	E:NoticeClosed(card)
	if not InCombatLockdown() then Place() end
	self:UpdateTimes()
end

function M:ShowCard(info)
	local card = FreeCard()
	if not card then return false end
	card.shownAt = GetTime()
	card.agoText = nil
	self:LayoutCard(card)
	shown[#shown + 1] = card
	self:FillCard(card, info)
	Place()
	E:SlideIn(card, "UP")
	return card
end

local function Limit()
	return math.max(1, math.min(POOL, M.db.stackSize or 1))
end

E:RegisterNoticeHolder("rare", {
	waiting = queue,
	most = QUEUE_MAX,
	usable = function() return M.active and M.db.popup and true or false end,
	slots = Limit,
	-- The secure card changes only out of combat, once the cards are made.
	ready = function() return not InCombatLockdown() and M.cardsReady and FreeCard() ~= nil end,
	duration = function()
		local after = tonumber(M.db.closeAfter) or 60
		return after > 0 and after or nil
	end,
	show = function(info) return M:ShowCard(info) or nil end,
	refresh = function(card, info)
		if not InCombatLockdown() then M:FillCard(card, info) end
	end,
	hide = function(card) M:CloseCard(card) end,
	hovered = function(card) return card.hovered or (card.IsMouseOver and card:IsMouseOver()) end,
	tick = function() M:UpdateTimes() end,
	changed = function() M:UpdateTimes() end,
})

-- Fill free card slots from the queue (out of combat).
function M:ShowNext()
	if InCombatLockdown() or not self.active then return end
	E:PumpNotices("rare")
	Place()
	self:UpdateTimes()
end

-- A new sighting for the card.
function M:PushCard(info)
	if not self.active or not self.db.popup then return end
	local card = CardFor(info.key)
	if card then
		if not InCombatLockdown() then self:FillCard(card, info) end
		return card
	end
	for _, waiting in ipairs(queue) do
		if waiting.key == info.key then return end
	end
	if E:PushNotice("rare", info) == "waiting" then
		-- The secure card can't show in combat: a text toast now.
		if InCombatLockdown() then
			local title = info.kind == "treasure" and L["Treasure: %s"] or info.kind == "event" and L["Event: %s"] or L["Rare: %s"]
			M:PushAlert({ key = "rarescanner:" .. info.key, title = title:format(info.name),
				text = L["The card opens after combat."], icon = "Interface\\Icons\\Ability_Hunter_SniperShot" })
		end
		E:RunOutOfCombat(function() M:ShowNext() end)
		self:UpdateTimes()
		return
	end
	Place()
	self:UpdateTimes()
end

-- A later source of the same rare (the vignette's position, say).
function M:MergeCard(info)
	local card = CardFor(info.key)
	if not card or not card.info then return end
	local current = card.info
	local changed = false
	if type(info.x) == "number" and type(current.x) ~= "number" then
		current.x, current.y, current.uiMapID = info.x, info.y, info.uiMapID
		changed = true
	end
	if info.dead and not current.dead then current.dead = true changed = true end
	if info.done and not current.done then current.done = true changed = true end
	if changed then self:FillCard(card, current) end
end

function M:CardDead(key)
	local card = CardFor(key)
	if not card then return end
	self:PaintDead(card)
	if self.db.closeDead then
		if card.timer then card.timer:Cancel() end
		card.timer = C_Timer.NewTimer(DEAD_CLOSE, function()
			card.timer = nil
			if card:IsShown() then M:CloseCard(card) end
		end)
	end
end

---------------------------------------------------------------------------
-- Enable, apply, disable
---------------------------------------------------------------------------
function M:ApplyAnchor()
	local anchor = self.anchor
	if not anchor then return end
	local width, height = Size()
	local scale = math.max(0.6, math.min(1.6, tonumber(self.db.scale) or 1))
	anchor:SetSize(width * scale, height * scale)
	anchor:SetShown(self.active and self.db.popup and true or false)
end

function M:BuildCards()
	if self.cardsReady then return end
	if not self.anchor then
		local anchor = CreateFrame("Frame", M.MOVER, UIParent)
		anchor:EnableMouse(false)
		self.anchor = anchor
		self:ApplyAnchor()
		E:CreateMover(anchor, M.MOVER, L["Rare Alerts"], M.DEFAULT_POINT, { followShown = true, sample = { kind = "toast" } })
	end
	for i = 1, POOL do
		cards[i] = cards[i] or CreateCard(i)
		self:StyleCard(cards[i])
		self:LayoutCard(cards[i])
	end
	self.cardsReady = true
end

function M:ApplyCards()
	if not self.cardsReady then return end
	E:RunOutOfCombat(function()
		M:ApplyAnchor()
		for _, card in ipairs(cards) do
			M:StyleCard(card)
			M:LayoutCard(card)
			if card.info then M:FillCard(card, card.info) end
		end
		if not M.db.popup then
			for i = #shown, 1, -1 do shown[i]:Hide() end
			wipe(queue)
		end
		-- Fewer cards at once: the extra ones go back to the queue.
		local limit = math.max(1, math.min(POOL, M.db.stackSize or 1))
		for i = #shown, limit + 1, -1 do
			local card = shown[i]
			if card.info then table.insert(queue, 1, card.info) end
			card:Hide()
		end
		Place()
		M:ShowNext()
	end)
end

function M:EnableCards()
	E:RunOutOfCombat(function()
		if not M.active then return end
		M:BuildCards()
		M:ApplyCards()
		M:ShowNext()
	end)
end

function M:DisableCards()
	E:DropNotices("rare")
	wipe(queue)
	E:RunOutOfCombat(function()
		for i = #shown, 1, -1 do shown[i]:Hide() end
		if M.anchor then M.anchor:Hide() end
	end)
end
