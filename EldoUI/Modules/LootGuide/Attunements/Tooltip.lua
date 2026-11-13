-- EldoUI Attunements: the other places attunements show.
--
--   Tooltip sections (Tooltip page, Always / Shift / Ctrl / Alt / Never):
--     attuneItem (Shift)   an item that is a step: "<entry>, step n of m",
--                          whether you have it, the next step
--     attuneUnit (Always)  an NPC that gives, takes or is the target of a
--                          step; read from the unit's GUID only when the
--                          game shows it (a secret GUID adds nothing)
--   Map pins ("Next step on the map", off by default): the place where the
--     next step of each attunement you are on starts; click for the arrow.
--   Journal: one line in an instance's header ("Attunement: 3 of 4 steps")
--     and "Part of attunement" in the quest detail.
--   Characters > Grids: an Attunements grid (one row per raid, key and
--     chain, one column per character).
local _, E = ...
local LG = E.LootGuide
local P = LG.PageKit
local L = E.L
local A = E:GetModule("Attunements")

local MAX_LINES = 3

local function Good() return unpack(E.tokens.text.good) end
local function Warn() return unpack(E.tokens.text.warn) end

-- Hits in entries the tab shows, one per entry.
local function ShownHits(hits, kinds)
	local out, seen = {}, {}
	for _, hit in ipairs(hits) do
		local entry = A:Get(hit.key)
		if entry and not seen[hit.key] and (not kinds or kinds[hit.step.kind]) and entry.group ~= "dungeons" and A:Shown(entry)
			and A:StepVisible(hit.step) then
			seen[hit.key] = true
			out[#out + 1] = hit
		end
	end
	return out
end

local ITEM_KINDS = { item = true, goal = true }
local UNIT_KINDS = { pickup = true, quest = true, turnin = true, kill = true, drop = true }

local function ItemSection(_, _, itemID, add)
	if not A:Running() then return end
	itemID = tonumber(itemID)
	if not itemID then return end
	local hits = ShownHits(A:ForItem(itemID), ITEM_KINDS)
	local reader = A:Reader()
	for index, hit in ipairs(hits) do
		if index > MAX_LINES then break end
		add(L["Attunement"], (L["%s, step %d of %d"]):format(A:Name(hit.key), hit.index, hit.total))
		local have = reader and reader:Count(itemID) or 0
		if have >= (hit.step.count or 1) then
			add(L["You have it"], nil, Good())
		else
			add(L["Not yet"], nil, Warn())
		end
		if IsShiftKeyDown() then
			local nextStep = A:NextSteps(hit.key)[1]
			if nextStep then add(L["Next"], A:StepTitle(nextStep)) end
		end
	end
end

local function UnitSection(_, unit, add)
	if not A:Running() or type(unit) ~= "string" then return end
	local guid = UnitGUID and UnitGUID(unit)
	if A.Secret(guid) then return end
	local npc = LG.NpcFromGUID and LG.NpcFromGUID(guid)
	if not npc then return end
	local hits = ShownHits(A:ForNpc(npc), UNIT_KINDS)
	for index, hit in ipairs(hits) do
		if index > MAX_LINES - 1 then break end
		local kind = hit.step.kind
		local pattern = (kind == "pickup" or kind == "quest") and L["Gives step %d: %s"] or kind == "turnin" and L["Takes step %d: %s"]
			or L["Step %d: %s"]
		add(L["Attunement"], pattern:format(hit.index, A:Name(hit.key)))
		local state = A:StepState(hit.key, hit.step.id) or "unknown"
		local r, g, b = A:StateColor(state)
		add(A.STATE_TITLE[state] or state, nil, r, g, b)
	end
end

A.TooltipItem, A.TooltipUnit = ItemSection, UnitSection

local sectionsDone
local function RegisterSections()
	if sectionsDone or not E.RegisterTooltipSection then return end
	sectionsDone = true
	E:RegisterTooltipSection("attuneItem", { order = 50, title = L["Attunements: items"], default = "shift",
		desc = L["On an item that is a step of an attunement: which one, whether you have it, and with Shift the next step."],
		item = ItemSection })
	E:RegisterTooltipSection("attuneUnit", { order = 51, title = L["Attunements: characters"], default = "always",
		desc = L["On a character that gives, takes or is the target of an attunement step: which step and how far you are. Nothing shows when the game hides who it is."],
		unit = UnitSection })
end

function A:StartTooltips()
	RegisterSections()
	self:StartPins()
	self:StartJournal()
end

function A:StopTooltips()
	self:StopPins()
end

---------------------------------------------------------------------------
-- Map pins
---------------------------------------------------------------------------
local PIN_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"

-- { { entry key, step, place } } for the entries you are on.
function A:PinSteps()
	local out = {}
	if not self:Running() then return out end
	for _, key in ipairs(self:List()) do
		local entry = self:Get(key)
		local done, _, _, state = self:Progress(key)
		if entry.group ~= "dungeons" and state ~= "done" and (done > 0 or state == "active") then
			for _, step in ipairs(self:NextSteps(key)) do
				local place = self:StepPlace(step)
				if place and place.uiMapID then
					out[#out + 1] = { key = key, step = step, place = place }
					break
				end
			end
		end
	end
	return out
end

local pinProvider = {
	order = 46,
	group = "attunements",
	pins = function(_, ctx)
		if ctx.kind ~= "world" or not (A:Running() and A.db.mapPins) then return end
		local list = {}
		for _, row in ipairs(A:PinSteps()) do
			if row.place.uiMapID == ctx.uiMapID then
				local key, step, place = row.key, row.step, row.place
				list[#list + 1] = { x = place.x, y = place.y, id = "attune:" .. key, icon = PIN_ICON, size = 18,
					tooltip = function(tooltip)
						local sr, sg, sb = unpack(E.tokens.text.secondary)
						E.UIKit.TipTitle(tooltip, A:Name(key))
						E.UIKit.TipTitle(tooltip, (L["Next: %s"]):format(A:StepTitle(step)), true)
						tooltip:AddLine(A.PlaceText(place) or "", sr, sg, sb, true)
						tooltip:AddLine(" ")
						E:TooltipHint(tooltip, { L["Click"], L["set the arrow to it"] })
					end,
					onClick = function(_, button)
						if button == "LeftButton" then LG:SetWaypoint(place, A:StepTitle(step)) end
					end }
			end
		end
		return list
	end,
}

local layerDone
function A:StartPins()
	if E.RegisterMapPinLayer and not layerDone then
		layerDone = true
		E:RegisterMapPinLayer("attunements", {
			title = L["Attunements"], order = 85, continent = false,
			available = function() return A:Running() and A.db.mapPins and true or false end,
			count = function(uiMapID)
				local count = 0
				for _, row in ipairs(A:PinSteps()) do
					if row.place.uiMapID == uiMapID then count = count + 1 end
				end
				return count
			end,
			refresh = function() if E.RefreshMapPins then E:RefreshMapPins() end end,
		})
	end
	if self.db.mapPins and E.AddMapPinProvider then
		E:AddMapPinProvider("attunements", pinProvider)
		self.pinsOn = true
	end
	LG:On("attunepins", function(changed)
		if (changed.attune or changed.settings) and A.pinsOn and E.RefreshMapPins then E:RefreshMapPins() end
	end)
end

function A:StopPins()
	LG:Off("attunepins")
	if self.pinsOn and E.RemoveMapPinProvider then E:RemoveMapPinProvider("attunements") end
	self.pinsOn = false
end

-- The option changed.
function A:RefreshPins()
	if not self:Running() then return end
	if self.db.mapPins and not self.pinsOn and E.AddMapPinProvider then
		E:AddMapPinProvider("attunements", pinProvider)
		self.pinsOn = true
	elseif not self.db.mapPins and self.pinsOn then
		E:RemoveMapPinProvider("attunements")
		self.pinsOn = false
	elseif E.RefreshMapPins then
		E:RefreshMapPins()
	end
end

---------------------------------------------------------------------------
-- Journal: the instance header line and the quest detail line
---------------------------------------------------------------------------
local journalDone
function A:StartJournal()
	if journalDone then return end
	journalDone = true
	if P.AddInstanceHeaderExtra then
		P.AddInstanceHeaderExtra("attunements", function(instance)
			if not (A:Running() and A.db.instanceLine) then return end
			local key = A:ForInstance(instance)[1]
			if not key then return end
			local done, total, _, state = A:Progress(key)
			if total == 0 then return end
			local text
			if state == "done" then
				text = A.CheckMark() .. " " .. L["Attuned"]
			else
				text = E:Plural(total, "Attunement: %d of %d step", "Attunement: %d of %d steps"):format(done, total)
			end
			return {
				text = text,
				tipTitle = A:Name(key),
				tip = L["Opens the Attunements tab on it."],
				onClick = function() A:Open(key) end,
			}
		end)
	end
	if P.AddQuestDetailExtra then
		P.AddQuestDetailExtra("attunements", function(flow, questID, pane)
			if not A:Running() or pane.inAttunements then return end
			local seen = {}
			for _, hit in ipairs(A:ForQuest(questID)) do
				local entry = A:Get(hit.key)
				if entry and entry.group ~= "dungeons" and not seen[hit.key] and A:FactionFits(entry) then
					seen[hit.key] = true
					local key, stepId = hit.key, hit.step.id
					P.FlowLine(flow, A.Secondary(L["Part of attunement"]) .. "  " .. A:Name(key)
						.. "  " .. A.Secondary((L["step %d of %d"]):format(hit.index, hit.total)), nil,
						{ L["Open"], function() A:Open({ key = key, step = stepId }) end, L["Open"], L["Opens the Attunements tab on this step."] })
				end
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Characters > Grids
---------------------------------------------------------------------------
local GRID = {
	key = "attunements", title = "Attunements", desc = "Attunements and keys of each character, as of its last login.",
	rows = function()
		local rows = {}
		for _, key in ipairs(A:MainKeys(true)) do
			local entry = A:Get(key)
			local label = A:Name(key)
			-- Alliance and Horde versions share a name: say which is which.
			if entry and entry.side then label = ("%s (%s)"):format(label, entry.side == "Horde" and L["Horde"] or L["Alliance"]) end
			rows[#rows + 1] = {
				key = key,
				label = label,
				cell = function(record) return A:CellText(key, A:KeyOfRecord(record), record) end,
				tip = function(tooltip, record)
					local charKey = A:KeyOfRecord(record)
					local done, total, percent, state = A:Progress(key, charKey)
					local r, g, b = A:StateColor(state)
					E.UIKit.TipTitle(tooltip, A:Name(key))
					tooltip:AddLine(record and record.name or "?", unpack(E.tokens.text.secondary))
					tooltip:AddLine(A.STATE_TITLE[state] or state, r, g, b)
					if total > 0 then E.UIKit.TipTitle(tooltip, E:Plural(total, "%d of %d step (%d%%)", "%d of %d steps (%d%%)"):format(done, total, percent)) end
					return true
				end,
			}
		end
		return rows
	end,
}

function A:StartGrid()
	local module = E.modules and E.modules.Characters
	if module and module.AddGrid then module:AddGrid(GRID) end
end

function A:StopGrid()
	local module = E.modules and E.modules.Characters
	if module and module.RemoveGrid then module:RemoveGrid("attunements") end
end
