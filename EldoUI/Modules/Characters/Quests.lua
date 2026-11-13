-- EldoUI Characters: quests of every character.
--
-- The Quests tab has two views: "Quests" lists every quest in your
-- characters' logs once, with who has it and who is ready to turn it in;
-- "Characters" sums up each character (quests in the log, ready to turn
-- in, dailies done since the daily reset, completed quests). On a quest
-- link's tooltip, a few lines say which of your characters have the
-- quest or completed it. With My Adventure on, a click on a quest opens it
-- in your journal. Data: the store's quest log rows and the game's
-- completed-quest list, both read without selecting or expanding anything.
local _, E = ...
local L = E.L
local Kit = E.UIKit
local M = E.modules.Characters

local function Store() return E.Characters end

local function Grey(text) return M.Grey(text) end

local historyCache = {}
local function History(key, record)
	local quests = type(record.quests) == "table" and record.quests
	local packed = quests and quests.history
	if type(packed) ~= "string" then return nil end
	local cached = historyCache[key]
	if cached and cached.source == packed then return cached.set, cached.count end
	local set, count = Store().UnpackIDs(packed), 0
	for _ in pairs(set) do count = count + 1 end
	historyCache[key] = { source = packed, set = set, count = count }
	return set, count
end

-- When the dailies last reset (from the game's seconds-until-reset).
local function DailyResetAt()
	local now = Store().Now()
	local left = C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset()
	if type(left) == "number" and left > 0 then return now + left - 86400 end
	return now - 86400
end

-- { onIt = {keys}, ready = {keys}, done = {keys} } for one quest.
function M:QuestOwners(questID)
	local result = { onIt = {}, ready = {}, done = {} }
	if type(questID) ~= "number" then return result end
	for _, key in ipairs(Store():Keys("account")) do
		local record = Store():Get(key)
		local quests = type(record.quests) == "table" and record.quests or {}
		local found
		for _, entry in ipairs(type(quests.log) == "table" and quests.log or {}) do
			if entry.id == questID then found = entry end
		end
		if found then
			table.insert(found.done and result.ready or result.onIt, key)
		else
			local set = History(key, record)
			if set and set[questID] then result.done[#result.done + 1] = key end
		end
	end
	return result
end

local function Names(keys)
	local parts = {}
	for _, key in ipairs(keys) do parts[#parts + 1] = M.ClassName(Store():Get(key), true) end
	return table.concat(parts, ", ")
end

function M:QuestLines(questID)
	local owners = self:QuestOwners(questID)
	local lines = {}
	if #owners.ready > 0 then lines[#lines + 1] = { L["Ready to turn in"], Names(owners.ready), Kit.GOOD } end
	if #owners.onIt > 0 then lines[#lines + 1] = { L["On this quest"], Names(owners.onIt) } end
	if #owners.done > 0 then lines[#lines + 1] = { L["Completed by"], Names(owners.done), Kit.SECONDARY } end
	return lines
end

-- A quest section of the shared info area (Modules/Tooltip.lua): it shows
-- with the Tooltip module on or off, in the same rows as every other
-- extra line.
local function QuestSection(_, questID, add)
	if not (M.active and M.db.questTooltip) then return end
	if type(questID) ~= "number" or (issecretvalue and issecretvalue(questID)) then return end
	for _, line in ipairs(M:QuestLines(questID)) do
		local color = line[3] or Kit.SECONDARY
		add(line[1], line[2], color[1], color[2], color[3])
	end
end

local function HookQuestTooltip()
	if M.questTooltipHooked then return end
	M.questTooltipHooked = true
	E:RegisterTooltipSection("altQuests", { order = 42, title = "Alts: quests", default = "always",
		desc = "On quest links: which of your characters are on the quest, ready to turn it in or completed it (Alts module).",
		quest = QuestSection })
end

-- My Adventure: with the journal running, a click on a quest opens
-- it on the journal's Quests page (where you took it, who gave it, who
-- came along). Navigation only.
local function Journal()
	local adventure = E.Adventure
	if adventure and adventure.Running and adventure:Running() then return E.Journal end
end

function M:QuestJournalLinked()
	return Journal() ~= nil
end

function M:OpenQuestInJournal(questID)
	local J = Journal()
	if not (J and type(questID) == "number") then return false end
	return J:Open(J:Address("quest", questID))
end

-- Every quest in the scope's logs, once: { id, title, level, daily, keys, ready }.
function M:QuestRows()
	local rows, byID = {}, {}
	for _, key in ipairs(self:Keys()) do
		local record = Store():Get(key)
		local quests = type(record.quests) == "table" and record.quests or {}
		for _, entry in ipairs(type(quests.log) == "table" and quests.log or {}) do
			local row = byID[entry.id]
			if not row then
				row = { id = entry.id, title = entry.title or ("#" .. entry.id), level = entry.level, daily = entry.daily, keys = {}, ready = {} }
				byID[entry.id] = row
				rows[#rows + 1] = row
			end
			row.keys[#row.keys + 1] = key
			if entry.done then row.ready[key] = true end
		end
	end
	return rows
end

-- One row per character: log size, ready, dailies since reset, completed.
function M:QuestCharacterRows()
	local rows = {}
	local reset = DailyResetAt()
	for _, key in ipairs(self:Keys()) do
		local record = Store():Get(key)
		local quests = type(record.quests) == "table" and record.quests or {}
		local log, ready, dailies = 0, 0, 0
		for _, entry in ipairs(type(quests.log) == "table" and quests.log or {}) do
			log = log + 1
			if entry.done then ready = ready + 1 end
		end
		for _, at in pairs(type(quests.daily) == "table" and quests.daily or {}) do
			if at >= reset then dailies = dailies + 1 end
		end
		local _, completed = History(key, record)
		rows[#rows + 1] = { key = key, record = record, log = log, ready = ready, dailies = dailies, completed = completed }
	end
	return rows
end

local function OwnersText(row)
	local parts = {}
	for _, key in ipairs(row.keys) do
		local text = M.ClassName(Store():Get(key))
		if row.ready[key] then text = text .. M.Good(" *") end
		parts[#parts + 1] = text
	end
	return table.concat(parts, ", ")
end

local COLUMNS = {
	quests = {
		{ key = "title", title = "Quest", value = function(row) return row.title end,
			text = function(row) return row.title .. (row.daily and Grey(" (" .. L["daily"] .. ")") or "") end },
		{ key = "level", title = "Level", width = 60, align = "RIGHT", value = function(row) return row.level or 0 end },
		{ key = "owners", title = "Characters (* ready)", width = 360, value = function(row) return #row.keys end, text = OwnersText },
	},
	chars = {
		{ key = "name", title = "Character", value = function(row) return row.record.name or "" end,
			text = function(row) return M.ClassIcon(row.record.class, 14) .. M.ClassName(row.record) end },
		{ key = "log", title = "In log", width = 80, align = "RIGHT", value = function(row) return row.log end },
		{ key = "ready", title = "Ready", width = 80, align = "RIGHT", value = function(row) return row.ready end,
			text = function(row) return row.ready > 0 and M.Good(row.ready) or "0" end },
		{ key = "dailies", title = "Dailies today", width = 110, align = "RIGHT", value = function(row) return row.dailies end },
		{ key = "completed", title = "Completed", width = 100, align = "RIGHT", value = function(row) return row.completed or -1 end,
			text = function(row) return row.completed and tostring(row.completed) or Grey("?") end },
	},
}

local function Build(frame, view)
	for _, tbl in pairs(frame.tables) do tbl:Hide() end
	local tbl = frame.tables[view]
	if not tbl then
		tbl = Kit.CreateTable(frame, COLUMNS[view], {
			sortKey = view == "quests" and "level" or "name", rowHeight = 18,
			onClick = function(row, button, widget)
				if row.key and button == "RightButton" then M:ShowCharacterMenu(widget, row.key) end
				if row.id and IsModifiedClick("CHATLINK") and GetQuestLink then
					local link = GetQuestLink(row.id)
					if link then E:InsertLink(link) end
				elseif row.id and button == "LeftButton" and M:QuestJournalLinked() then
					M:OpenQuestInJournal(row.id)
				end
			end,
			createRow = function(widget)
				widget:HookScript("OnEnter", function(own)
					local row = own.item
					if not row then return end
					GameTooltip:SetOwner(own, "ANCHOR_RIGHT")
					if row.id then
						GameTooltip:SetHyperlink(("quest:%d:%d"):format(row.id, row.level or -1))
						if M:QuestJournalLinked() then
							local hint = E.tokens.text.secondary
							E:TooltipHint(GameTooltip, { L["Click"], L["show it in your journal"] })
						end
					else
						M:CharacterTooltip(GameTooltip, row.key)
					end
					GameTooltip:Show()
				end)
				widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
			end,
			empty = view == "quests" and { L["No quests"], L["None of these characters had a quest in the log at logout."] }
				or { L["No characters"], L["No character in this scope."] },
		})
		tbl:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -6)
		tbl:SetPoint("BOTTOMRIGHT")
		frame.tables[view] = tbl
	end
	tbl:Show()
	return tbl
end

local function Update(frame)
	local view = next(frame.view:GetSelected()) or "quests"
	local rows = view == "quests" and M:QuestRows() or M:QuestCharacterRows()
	frame.rows = rows
	Build(frame, view):SetData(rows)
end
M.UpdateQuests = Update

M:AddTab({
	key = "quests", order = 45, title = "Quests",
	desc = "Quests in your characters' logs, who is ready to turn in, dailies and completed quests.",
	create = function(content)
		local frame = CreateFrame("Frame", nil, content)
		frame:SetAllPoints()
		frame.tables = {}
		frame.toolbar = CreateFrame("Frame", nil, frame)
		frame.toolbar:SetPoint("TOPLEFT")
		frame.toolbar:SetPoint("TOPRIGHT")
		frame.toolbar:SetHeight(20)
		frame.view = Kit.ChipBar(frame.toolbar, {
			selected = "quests",
			chips = {
				{ "quests", L["Quests"], L["Every quest in the logs once, with the characters that have it. * = ready to turn in."] },
				{ "chars", L["Characters"], L["Each character: quests in the log, ready to turn in, dailies since the daily reset, completed quests."] },
			},
			onChange = function(selected, key)
				if not next(selected) then frame.view:SetSelected(key) end
				Update(frame)
			end,
		})
		frame.view:SetPoint("LEFT", 2, 0)
		return frame
	end,
	show = function(frame, arg)
		if arg == "quests" or arg == "chars" then frame.view:SetSelected(arg) end
		Update(frame)
	end,
	refresh = function(frame) Update(frame) end,
	enable = function() HookQuestTooltip() end,
})
