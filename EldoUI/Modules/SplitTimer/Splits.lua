-- EldoUI Split Timer: the Splits tab of the Characters window.
--
-- Two characters side by side. One fold section per run (the character,
-- and the one it is compared with) with label-left, value-right rows:
-- levels logged, the fastest and the slowest level and the played time at
-- the last level-up. Under them, level by level: the time each spent on
-- the level, the difference, the played time at each level-up and its
-- difference, and quests and kills of the first one. The second run can
-- be the "Best of all" ghost: the best time per level over every other
-- character (its totals add those times up). Data: the core store's level
-- log, as the Level log tab shows it. Each section remembers whether it is
-- folded (per profile).
local _, E = ...
local L = E.L
local Key = E.Key
local Kit = E.UIKit
local S = E.SplitTimer
local C = E.modules.Characters
if not C then return end

local GHOST = "*best"

local function Store() return E.Characters end
local function Grey(text) return C.Grey(text) end

local function DeltaText(delta)
	if type(delta) ~= "number" then return "" end
	if delta <= 0 then return C.Good(S.Delta(delta)) end
	return C.Bad(S.Delta(delta))
end

local function Name(key)
	if key == GHOST then return Kit.AccentHex() .. L["Best of all"] .. "|r" end
	local record = Store():Get(key)
	return record and C.ClassName(record, true) or "?"
end

-- Keys with a level log, for the pickers.
function S:SplitKeys()
	local list = {}
	for _, key in ipairs(C:LevelLogKeys()) do
		local record = Store():Get(key)
		if record and type(record.levels) == "table" and next(record.levels) then list[#list + 1] = key end
	end
	return list
end

-- One row per level either side logged: { level, a = { took, played,
-- kills, quests }, b = { took, played } }.
function S:SplitRows(keyA, keyB)
	local store = Store()
	local recordA = store:Get(keyA)
	local rows, levels = {}, {}
	for level in pairs(recordA and type(recordA.levels) == "table" and recordA.levels or {}) do
		if type(level) == "number" then levels[level] = true end
	end
	local best, recordB
	if keyB == GHOST then
		local others = {}
		for _, key in ipairs(self:SplitKeys()) do if key ~= keyA then others[#others + 1] = key end end
		best = self:BestOfAll(others)
		for level in pairs(best) do levels[level] = true end
	else
		recordB = store:Get(keyB)
		for level in pairs(recordB and type(recordB.levels) == "table" and recordB.levels or {}) do
			if type(level) == "number" then levels[level] = true end
		end
	end
	for level in pairs(levels) do
		local rowA = recordA and recordA.levels and recordA.levels[level]
		local a = { took = S.Took(recordA, level), played = S.PlayedAt(recordA, level),
			kills = type(rowA) == "table" and rowA.kills or nil, quests = type(rowA) == "table" and rowA.quests or nil }
		local b
		if best then
			b = { took = best[level] and best[level].took, played = S.GhostTotal(best, level), from = best[level] and best[level].key }
		else
			b = { took = S.Took(recordB, level), played = S.PlayedAt(recordB, level) }
		end
		rows[#rows + 1] = {
			level = level, a = a, b = b,
			delta = a.took and b.took and a.took - b.took or nil,
			totalDelta = a.played and b.played and a.played - b.played or nil,
		}
	end
	table.sort(rows, function(x, y) return x.level < y.level end)
	return rows
end

-- One run's summary from the split rows: how many levels it logged, its
-- fastest and slowest level and its played time at the last level-up.
function S.RunSummary(rows, side)
	local count, fastest, slowest, last = 0, nil, nil, nil
	for _, row in ipairs(rows) do
		local split = row[side]
		local took = split and split.took
		if took then
			count = count + 1
			if not fastest or took < fastest.took then fastest = { level = row.level, took = took } end
			if not slowest or took > slowest.took then slowest = { level = row.level, took = took } end
		end
		if split and split.played then last = { level = row.level, played = split.played } end
	end
	return { count = count, fastest = fastest, slowest = slowest, last = last }
end

local function Folded()
	local db = S.db
	if type(db.splitsFolded) ~= "table" then db.splitsFolded = {} end
	return db.splitsFolded
end

local function LevelValue(entry, field)
	if not entry then return Grey("--") end
	return ("%s  %s"):format(S.Clock(entry[field]), Grey(L["level %d"]:format(entry.level)))
end

local function FillRun(section, summary)
	section.rows.count:SetValue(tostring(summary.count))
	section.rows.fastest:SetValue(LevelValue(summary.fastest, "took"))
	section.rows.slowest:SetValue(LevelValue(summary.slowest, "took"))
	section.rows.last:SetValue(LevelValue(summary.last, "played"))
end

-- The two run sections side by side, the level list under them.
local function Layout(frame)
	local T = E.tokens.height
	local runs = 0
	for _, section in ipairs({ frame.runA, frame.runB }) do
		local height = T.foldRow + (section.divider:IsFolded() and 0 or 4 * T.row)
		runs = math.max(runs, height)
	end
	frame.levels:ClearAllPoints()
	frame.levels:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -(6 + runs + 6))
	frame.levels:SetPoint("TOPRIGHT", frame.toolbar, "BOTTOMRIGHT", 0, -(6 + runs + 6))
end
S.LayoutSplits = Layout

local function Update(frame)
	local keys = S:SplitKeys()
	if not frame.keyA or not Store():Get(frame.keyA) then frame.keyA = E.charKey end
	if frame.keyB ~= GHOST and (not frame.keyB or not Store():Get(frame.keyB) or frame.keyB == frame.keyA) then frame.keyB = GHOST end
	frame.pickA:SetText(Name(frame.keyA))
	frame.pickB:SetText(Name(frame.keyB))
	Kit.FitButton(frame.pickA, 140)
	Kit.FitButton(frame.pickB, 140)
	frame.pickA:SetEnabled(#keys > 0)
	frame.pickB:SetEnabled(#keys > 0)
	local rows = S:SplitRows(frame.keyA, frame.keyB)
	frame.rows = rows
	frame.tbl:SetData(rows)
	frame.runA.divider:SetLabel(Name(frame.keyA))
	frame.runB.divider:SetLabel(Name(frame.keyB))
	FillRun(frame.runA, S.RunSummary(rows, "a"))
	FillRun(frame.runB, S.RunSummary(rows, "b"))
	Layout(frame)
	local ahead, behind = 0, 0
	for _, row in ipairs(rows) do
		if row.delta then
			if row.delta <= 0 then ahead = ahead + 1 else behind = behind + 1 end
		end
	end
	if ahead + behind > 0 then
		frame.summary:SetText(L["%d levels faster, %d slower"]:format(ahead, behind))
	else
		frame.summary:SetText(L["Splits show once both sides have a level in common."])
	end
end
S.UpdateSplits = Update

local function Menu(anchor, frame, side)
	E.UIKit.ContextMenu(anchor, function(_, root)
		root:CreateTitle(side == "A" and L["Character"] or L["Compare with"])
		local field = side == "A" and "keyA" or "keyB"
		if side == "B" then
			root:CreateRadio(L["Best of all"], function() return frame.keyB == GHOST end, function()
				frame.keyB = GHOST
				Update(frame)
			end)
		end
		for _, key in ipairs(S:SplitKeys()) do
			local record = Store():Get(key)
			root:CreateRadio(("%s (%d)"):format(C.ClassName(record, true), record.level or 0), function() return frame[field] == key end, function()
				frame[field] = key
				Update(frame)
			end)
		end
	end, { at = "owner" })
end

-- A run's fold section: the run's name between the lines, four value rows.
local RUN_ROWS = {
	{ "count", Key("Levels logged"), Key("Levels with a time in the level log.") },
	{ "fastest", Key("Fastest level"), Key("The level that took the least played time.") },
	{ "slowest", Key("Slowest level"), Key("The level that took the most played time.") },
	{ "last", Key("Last level-up"), Key("Total played time when the last logged level was reached.") },
}

local function RunSection(frame, side)
	local section = { rows = {} }
	section.body = CreateFrame("Frame", nil, frame)
	section.divider = Kit.FoldDivider(frame, { content = section.body, folded = Folded()[side] and true or false,
		onToggle = function(folded)
			Folded()[side] = folded or nil
			Layout(frame)
		end })
	section.body:SetPoint("TOPLEFT", section.divider, "BOTTOMLEFT", 0, 0)
	section.body:SetPoint("TOPRIGHT", section.divider, "BOTTOMRIGHT", 0, 0)
	section.body:SetHeight(4 * E.tokens.height.row)
	for index, def in ipairs(RUN_ROWS) do
		local row = Kit.ValueRow(section.body, { label = def[2], tip = def[3] })
		row:SetPoint("TOPLEFT", section.body, "TOPLEFT", 0, -(index - 1) * E.tokens.height.row)
		row:SetPoint("TOPRIGHT", section.body, "TOPRIGHT", 0, -(index - 1) * E.tokens.height.row)
		section.rows[def[1]] = row
	end
	return section
end

C:AddTab({
	key = "splits", order = 56, title = "Splits",
	desc = L["Two characters level by level: time per level, total played at each level-up and the difference."],
	create = function(content)
		local frame = CreateFrame("Frame", nil, content)
		frame:SetAllPoints()
		frame.toolbar = CreateFrame("Frame", nil, frame)
		frame.toolbar:SetPoint("TOPLEFT")
		frame.toolbar:SetPoint("TOPRIGHT")
		frame.toolbar:SetHeight(22)
		frame.pickA = Kit.Button(frame.toolbar, "", 140, 20, function(button) Menu(button, frame, "A") end,
			L["Character"], L["The character whose splits you look at."])
		frame.pickA:SetPoint("LEFT", 2, 0)
		frame.vs = Kit.Text(frame.toolbar, 12, "CENTER", "secondary")
		frame.vs:SetText(L["vs"])
		frame.vs:SetPoint("LEFT", frame.pickA, "RIGHT", 6, 0)
		frame.pickB = Kit.Button(frame.toolbar, "", 140, 20, function(button) Menu(button, frame, "B") end,
			L["Compare with"], L["Another character, or Best of all: the best time per level over all your other characters."])
		frame.pickB:SetPoint("LEFT", frame.vs, "RIGHT", 6, 0)
		frame.summary = Kit.Text(frame.toolbar, 12, "RIGHT", "secondary")
		frame.summary:SetPoint("LEFT", frame.pickB, "RIGHT", 10, 0)
		frame.summary:SetPoint("RIGHT", -4, 0)
		local function Clock(value) return value and S.Clock(value) or Grey("--") end
		frame.tbl = Kit.CreateTable(frame, {
			{ key = "level", title = L["Level"], width = 56, align = "RIGHT", value = function(row) return row.level end },
			{ key = "took", title = L["Time"], width = 96, align = "RIGHT", value = function(row) return row.a.took or math.huge end,
				text = function(row) return Clock(row.a.took) end, desc = L["Time the first character spent on the level before this one."] },
			{ key = "refTook", title = L["Compared"], width = 96, align = "RIGHT", value = function(row) return row.b.took or math.huge end,
				text = function(row) return Clock(row.b.took) end, desc = L["The same for the second character or the Best of all ghost."] },
			{ key = "delta", title = L["Difference"], width = 92, align = "RIGHT", value = function(row) return row.delta or math.huge end,
				text = function(row) return DeltaText(row.delta) end, desc = L["Green: the first character was faster."] },
			{ key = "played", title = L["Total"], width = 110, align = "RIGHT", value = function(row) return row.a.played or math.huge end,
				text = function(row) return Clock(row.a.played) end, desc = L["Played time at the level-up."] },
			{ key = "refPlayed", title = L["Compared total"], width = 110, align = "RIGHT", value = function(row) return row.b.played or math.huge end,
				text = function(row) return Clock(row.b.played) end, desc = L["The Best of all total adds up the best times; it needs a time for every level before."] },
			{ key = "totalDelta", title = L["Total difference"], width = 110, align = "RIGHT", value = function(row) return row.totalDelta or math.huge end,
				text = function(row) return DeltaText(row.totalDelta) end },
			{ key = "quests", title = L["Quests"], width = 56, align = "RIGHT", value = function(row) return row.a.quests or 0 end,
				text = function(row) return row.a.quests and tostring(row.a.quests) or "" end },
			{ key = "kills", title = L["Kills"], value = function(row) return row.a.kills or 0 end,
				text = function(row) return row.a.kills and tostring(row.a.kills) or "" end },
		}, {
			sortKey = "level", sortDown = false, rowHeight = 18,
			empty = { L["No splits yet"], L["Each level-up with the Alts module on adds a split. Level a second character to compare, or compare with Best of all."] },
			createRow = function(row)
				row:HookScript("OnEnter", function(own)
					local item = own.item
					if not (item and item.b and item.b.from) then return end
					GameTooltip:SetOwner(own, "ANCHOR_RIGHT")
					GameTooltip:AddLine(L["Level %d"]:format(item.level))
					GameTooltip:AddLine(L["Best time by %s"]:format(Name(item.b.from)), unpack(Kit.SECONDARY))
					GameTooltip:Show()
				end)
				row:HookScript("OnLeave", GameTooltip_Hide)
			end,
		})
		-- The two runs side by side under the toolbar, the level list under them.
		frame.runA, frame.runB = RunSection(frame, "a"), RunSection(frame, "b")
		frame.runA.divider:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -6)
		frame.runA.divider:SetPoint("TOPRIGHT", frame.toolbar, "BOTTOM", -6, -6)
		frame.runB.divider:SetPoint("TOPLEFT", frame.toolbar, "BOTTOM", 6, -6)
		frame.runB.divider:SetPoint("TOPRIGHT", frame.toolbar, "BOTTOMRIGHT", 0, -6)
		frame.list = CreateFrame("Frame", nil, frame)
		frame.levels = Kit.FoldDivider(frame, { label = L["Level by level"], content = frame.list,
			folded = Folded().levels and true or false,
			onToggle = function(folded) Folded().levels = folded or nil end })
		frame.list:SetPoint("TOPLEFT", frame.levels, "BOTTOMLEFT", 0, -4)
		frame.list:SetPoint("BOTTOMRIGHT")
		frame.tbl:SetParent(frame.list)
		frame.tbl:SetPoint("TOPLEFT", frame.list, "TOPLEFT", 0, 0)
		frame.tbl:SetPoint("BOTTOMRIGHT", frame.list, "BOTTOMRIGHT", 0, 0)
		Layout(frame)
		return frame
	end,
	show = function(frame, arg)
		if type(arg) == "string" and Store():Get(arg) then frame.keyA = arg end
		Update(frame)
	end,
	refresh = function(frame) Update(frame) end,
})
