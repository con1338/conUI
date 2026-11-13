-- EldoUI Zone Quests: quest giver pins on the world map and the Zone Info
-- line.
--
--   * Pins ("Quest givers on the map", off by default): one pin per giver of
--     the quests left in the zone the map shows, for the statuses you pick
--     (take now, needs a prerequisite, too low). Hover lists the quests;
--     click sets a waypoint on the giver. Behind the shared map pin switch
--     (Core/MapPins.lua, group "zonequests").
--   * Zone Info: "Quests 34 / 81" in the world map zone tooltip.
--
-- Pin looks (the style presets): Icons, Dots, High contrast, Forever bronze
-- and Minimal. Colors come from the tokens and the accent, read when drawn.
local _, E = ...
local L = E.L
local LG = E.LootGuide
local Z = E:GetModule("ZoneQuests")

local ICON = "Interface\\GossipFrame\\AvailableQuestIcon"

local function Accent()
	local c = E.media.accentColor
	return { c[1], c[2], c[3] }
end

-- The pin color of a status in a look.
function Z.PinColor(look, status)
	local safe = E.tokens.palette.safe
	if look == "contrast" then
		if status == "locked" then return safe.vermilion end
		if status == "low" then return safe.sky end
		return safe.yellow
	end
	if look == "bronze" then
		if E:SkinFlag("bronze") then return { E:SkinBronze() } end
		-- EldoUI's named Bronze accent (the palette token).
		local c = E.tokens.palette.bronze
		return { c[1], c[2], c[3] }
	end
	if status == "locked" then return E.tokens.text.warn end
	if status == "low" then return E.tokens.text.dim end
	return Accent()
end

local PIN_STATUS = { available = "pinAvailable", locked = "pinLocked", low = "pinLow" }
Z.PIN_STATUS = PIN_STATUS

-- { [giverKey] = { point, rows = { row, ... }, status } } for a zone, built
-- out of combat and kept until the quest list changes.
local pinCache = {}

function Z:InvalidatePins()
	wipe(pinCache)
end

function Z:GiverPins(uiMapID)
	uiMapID = tonumber(uiMapID)
	if not uiMapID then return {} end
	local cached = pinCache[uiMapID]
	if cached and cached.rev == self.rev then return cached.list end
	if InCombatLockdown() or not self:Ready() then return cached and cached.list or {} end
	local db = self.db
	local byGiver, list = {}, {}
	for _, row in ipairs(LG:ZoneQuests(uiMapID, { mine = true, hideDone = true, chains = false })) do
		local option = PIN_STATUS[row.status]
		if option and db[option] and row.giver and (row.giver.npc or row.giver.object) then
			local key = (row.giver.npc and "n" .. row.giver.npc) or ("o" .. row.giver.object)
			local entry = byGiver[key]
			if not entry then
				local point = LG:ZoneQuestGiverPoint(row)
				if point and point.uiMapID == uiMapID then
					entry = { key = key, point = point, rows = {}, status = row.status, name = row.giver.name }
					byGiver[key] = entry
					list[#list + 1] = entry
				end
			end
			if entry then
				entry.rows[#entry.rows + 1] = row
				-- The best status of the giver's quests colors the pin.
				if row.status == "available" then entry.status = "available"
				elseif row.status == "locked" and entry.status == "low" then entry.status = "locked" end
			end
		end
	end
	table.sort(list, function(a, b) return a.key < b.key end)
	pinCache[uiMapID] = { rev = self.rev, list = list }
	return list
end

local function PinTooltip(entry)
	return function(tooltip)
		local sr, sg, sb = unpack(E.tokens.text.secondary)
		E.UIKit.TipTitle(tooltip, entry.name or L["Quest giver"])
		for index, row in ipairs(entry.rows) do
			if index > 8 then
				tooltip:AddLine((L["and %d more"]):format(#entry.rows - 8), sr, sg, sb)
				break
			end
			local title = row.quest.title or ("#" .. row.id)
			local level = row.level and ("[%d] "):format(row.level) or ""
			tooltip:AddDoubleLine(level .. title, Z.GROUP_TITLE[row.group] or "", 1, 1, 1, sr, sg, sb)
		end
		tooltip:AddLine(" ")
		E:TooltipHint(tooltip, { L["Click"], L["set a waypoint on the giver"] })
	end
end

function Z:PinData(entry)
	local db = self.db
	local look = db.pinLook
	local size = db.pinSize or 18
	local color = Z.PinColor(look, entry.status)
	local count = #entry.rows > 1 and #entry.rows or nil
	local pin = { x = entry.point.x, y = entry.point.y, id = "zonequests:" .. entry.key, size = size, color = color,
		tooltip = PinTooltip(entry),
		onClick = function(_, button)
			if button == "LeftButton" then LG:SetWaypoint(entry.point, entry.rows[1].quest.title or entry.name) end
		end }
	if look == "icons" then
		pin.icon, pin.ring, pin.label = ICON, false, count
	elseif look == "bronze" then
		pin.icon, pin.label = ICON, count
	elseif look == "contrast" then
		pin.size, pin.label = size + 4, count or "!"
	elseif look == "minimal" then
		pin.size = math.max(8, math.floor(size * 0.6))
	else -- dots
		pin.label = count
	end
	return pin
end

local provider = {
	order = 47,
	group = "zonequests",
	pins = function(_, ctx)
		if ctx.kind ~= "world" or not (Z:Running() and Z.db.pins) then return end
		local list = {}
		for _, entry in ipairs(Z:GiverPins(ctx.uiMapID)) do list[#list + 1] = Z:PinData(entry) end
		return list
	end,
}
Z.pinProvider = provider

local layerDone
function Z:StartPins()
	if E.RegisterMapPinLayer and not layerDone then
		layerDone = true
		E:RegisterMapPinLayer("zonequests", {
			title = L["Quest givers"], order = 84, continent = false,
			available = function() return Z:Running() and Z.db.pins and true or false end,
			count = function(uiMapID) return Z:Running() and #Z:GiverPins(uiMapID) or 0 end,
			refresh = function() if E.RefreshMapPins then E:RefreshMapPins() end end,
		})
	end
	self:RefreshPins()
	self:StartZoneInfo()
end

function Z:StopPins()
	if self.pinsOn and E.RemoveMapPinProvider then E:RemoveMapPinProvider("zonequests") end
	self.pinsOn = false
	self:StopZoneInfo()
end

-- The option changed, or the quests did.
function Z:RefreshPins()
	self:InvalidatePins()
	if not self.active then return end
	if self.db.pins and not self.pinsOn and E.AddMapPinProvider then
		if E.DungeonMaps and rawget(_G, "WorldMapFrame") then E.DungeonMaps:AttachWorldMap() end
		E:AddMapPinProvider("zonequests", provider)
		self.pinsOn = true
	elseif not self.db.pins and self.pinsOn and E.RemoveMapPinProvider then
		E:RemoveMapPinProvider("zonequests")
		self.pinsOn = false
	elseif E.RefreshMapPins then
		E:RefreshMapPins()
	end
end

---------------------------------------------------------------------------
-- Zone Info: "Quests 34 / 81"
---------------------------------------------------------------------------
function Z:ZoneInfoLines(mapID)
	if not (self:Running() and self.db.zoneInfo) then return nil end
	if InCombatLockdown() and not self:Ready() then return nil end
	local total, done = LG:ZoneQuestCounts(mapID)
	if total == 0 then return nil end
	local sr, sg, sb = unpack(E.tokens.text.secondary)
	local r, g, b = 1, 1, 1
	if done >= total then r, g, b = unpack(E.tokens.text.good) end
	return { { left = L["Quests"], right = ("%d / %d"):format(done, total), lr = sr, lg = sg, lb = sb, rr = r, rg = g, rb = b } }
end

function Z:StartZoneInfo()
	local ZI = E.ZoneInfo
	if not (ZI and ZI.RegisterLines) then return end
	ZI:RegisterLines("zonequests", { order = 40,
		live = function() return Z:Running() and Z.db.zoneInfo and true or false end,
		lines = function(mapID) return Z:ZoneInfoLines(mapID) end })
end

function Z:StopZoneInfo()
	local ZI = E.ZoneInfo
	if ZI and ZI.UnregisterLines then ZI:UnregisterLines("zonequests") end
end
