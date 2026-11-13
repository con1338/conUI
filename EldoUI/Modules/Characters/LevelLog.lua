-- EldoUI Characters: the Level log tab.
--
-- One row per level a character gained while EldoUI was on: when, where,
-- how long the level took in played time, the played time at the ding,
-- XP kills and quests turned in during the level, and gold at the ding.
-- The current level shows on top with its count so far. Data: the core
-- store's `levels` and `levelNow` (Core/CharacterStore.lua): kills come
-- from the game's XP chat line, quests from QUEST_TURNED_IN, played time
-- from the game's own /played answer.
local _, E = ...
local L = E.L
local Kit = E.UIKit
local M = E.modules.Characters

local function Store() return E.Characters end

local function Grey(text) return M.Grey(text) end

-- Rows for one character, newest level first.
function M:LevelRows(key)
	local record = Store():Get(key)
	local rows = {}
	if not record then return rows end
	for level, row in pairs(type(record.levels) == "table" and record.levels or {}) do
		if type(level) == "number" and type(row) == "table" then
			rows[#rows + 1] = { level = level, row = row }
		end
	end
	local now = record.levelNow
	if type(now) == "table" and now.level == record.level and (record.level or 0) < Store().MaxLevel() then
		local since = now.since
		if key ~= E.charKey and record.loggedOut then since = nil end
		rows[#rows + 1] = { level = record.level, current = true, row = { kills = now.kills, quests = now.quests, since = since } }
	end
	return rows
end

-- Characters with at least one level row.
function M:LevelLogKeys()
	local list = {}
	for _, key in ipairs(self:Keys()) do
		local record = Store():Get(key)
		if key == E.charKey or (type(record.levels) == "table" and next(record.levels)) then list[#list + 1] = key end
	end
	return list
end

local function Average(rows)
	local total, count = 0, 0
	for _, item in ipairs(rows) do
		if not item.current and item.row.took and item.row.took > 0 then
			total, count = total + item.row.took, count + 1
		end
	end
	return count > 0 and total / count or nil, count
end

local function DateText(at)
	if not at then return "" end
	return E:ShortDate(at)
end

local function Update(frame)
	local keys = M:LevelLogKeys()
	local key = frame.key
	if not key or not Store():Get(key) then key = E.charKey end
	frame.key = key
	local record = Store():Get(key)
	frame.pick:SetText(record and M.ClassName(record, true) or "?")
	Kit.FitButton(frame.pick, 140)
	local rows = M:LevelRows(key)
	frame.rows = rows
	frame.tbl:SetData(rows)
	local average, count = Average(rows)
	if count > 0 then
		frame.summary:SetText(L["%d levels logged · %s per level on average"]:format(count, M.Duration(average)))
	else
		frame.summary:SetText(L["Levels show here from the next level-up on."])
	end
	frame.pick:SetEnabled(#keys > 1)
end
M.UpdateLevelLog = Update

function M:ShowLevelLogMenu(anchor, frame)
	E.UIKit.ContextMenu(anchor, function(_, root)
		root:CreateTitle(L["Character"])
		for _, key in ipairs(M:LevelLogKeys()) do
			local record = Store():Get(key)
			root:CreateRadio(("%s (%d)"):format(M.ClassName(record, true), record.level or 0), function() return frame.key == key end, function()
				frame.key = key
				Update(frame)
			end)
		end
	end, { at = "owner" })
end

M:AddTab({
	key = "levels", order = 55, title = "Level log",
	desc = "Each level a character gained: when, where, how long it took, kills and quests.",
	create = function(content)
		local frame = CreateFrame("Frame", nil, content)
		frame:SetAllPoints()
		frame.toolbar = CreateFrame("Frame", nil, frame)
		frame.toolbar:SetPoint("TOPLEFT")
		frame.toolbar:SetPoint("TOPRIGHT")
		frame.toolbar:SetHeight(22)
		frame.pick = Kit.Button(frame.toolbar, "", 140, 20, function(button) M:ShowLevelLogMenu(button, frame) end,
			L["Character"], L["Pick whose level log to show. Characters show here once they gain a level with EldoUI on."])
		frame.pick:SetPoint("LEFT", 2, 0)
		frame.summary = Kit.Text(frame.toolbar, 12, "LEFT", "secondary")
		frame.summary:SetPoint("LEFT", frame.pick, "RIGHT", 10, 0)
		frame.summary:SetPoint("RIGHT", -4, 0)
		frame.tbl = Kit.CreateTable(frame, {
			{ key = "level", title = L["Level"], width = 60, align = "RIGHT", value = function(item) return item.level + (item.current and 0.5 or 0) end,
				text = function(item) return item.current and (Kit.AccentHex() .. item.level .. "|r") or tostring(item.level) end },
			{ key = "at", title = L["Reached"], width = 130, value = function(item) return item.row.at or math.huge end,
				text = function(item) return item.current and Grey(L["in progress"]) or DateText(item.row.at) end },
			{ key = "zone", title = L["Zone"], value = function(item) return item.row.zone or "" end },
			{ key = "took", title = L["Took"], width = 90, align = "RIGHT", value = function(item) return item.row.took or 0 end,
				text = function(item)
					if item.current then return item.row.since and Grey(M.Duration(Store().Now() - item.row.since)) or "" end
					return item.row.took and M.Duration(item.row.took) or ""
				end },
			{ key = "played", title = L["Played"], width = 90, align = "RIGHT", value = function(item) return item.row.played or 0 end,
				text = function(item) return item.row.played and M.Duration(item.row.played) or "" end },
			{ key = "kills", title = L["Kills"], width = 60, align = "RIGHT", value = function(item) return item.row.kills or 0 end },
			{ key = "quests", title = L["Quests"], width = 60, align = "RIGHT", value = function(item) return item.row.quests or 0 end },
			{ key = "money", title = L["Gold"], width = 100, align = "RIGHT", value = function(item) return item.row.money or 0 end,
				text = function(item) return item.row.money and M.Money(item.row.money, true) or "" end },
		}, {
			sortKey = "level", sortDown = true, rowHeight = 18,
			empty = { L["No levels yet"], L["Each level-up from now on adds a row: the time, zone, how long the level took, kills and quests."] },
		})
		frame.tbl:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -6)
		frame.tbl:SetPoint("BOTTOMRIGHT")
		return frame
	end,
	show = function(frame, arg)
		if type(arg) == "string" and Store():Get(arg) then frame.key = arg end
		Update(frame)
	end,
	refresh = function(frame) Update(frame) end,
})
