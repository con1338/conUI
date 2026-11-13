-- EldoUI My Adventure: the Quests section, the quest ledger in the Journal
-- window's look.
--
--   Quests                                                      [Archive 2]
--   214 quests handed in, 182,400 experience and 41g 20s earned. Most of
--   them in Westfall.
--   -----------------------------------------------------------------------
--   [Handed in][In progress 12][Before the journal 312]   [Day][Level][Zone][Type]
--   [ Search quests                                                       ]
--   WEDNESDAY, OCTOBER 8   9 quests · 12,400 XP -------------------------- v
--   | [!] The Defias Brotherhood                              1,250 XP |
--   |     Westfall · level 22 · 1g 20s                                  |
--   |   +-----------------------------------------------------------+ |
--   |   | Find the Defias hideout ...                               | |
--   |   | From Gryan Stoutmantle, Sentinel Hill · to Gryan ...      | |
--   |   | Picked up Oct 3, 14:02 · handed in 15:12 · took 1h 10m    | |
--   |   | Done with Aria Swift                 Quest details  Archive | |
--   |   +-----------------------------------------------------------+ |
--
-- Views: handed in (the journal's own record of every hand-in: where,
-- when, the XP and money, who gave it and who took it, what it asked and
-- who did it with you), in progress (your quest log now, with where and
-- when you took each one), before the journal (the game's own list of
-- completed quests from the Characters record, undated: the game does not
-- say when), abandoned (quests that left your log without a hand-in, from
-- J:Abandoned(): where and when you took each one and when it left) and
-- the archive. Group by day, level, zone or type; search
-- every word; click a quest for its story. Past 2,000 hand-ins the oldest
-- leave the list; their counts stay on their level and zone, and the page
-- says so.
--
-- Navigation only: "Quest details" opens the quest in the Loot Guide.
-- Nothing is accepted, abandoned or handed in for you.
--
-- Routes: show(frame, arg) with nil, "journal:quest:<id>", { quest = id[, t] },
-- { view = "done"|"open"|"before"|"abandoned"|"archive" }, { group = key, open = group label },
-- { search = text }.
--
-- Portions adapted from Forever Journal by Ugge Zen, MIT License (see
-- THIRD_PARTY_NOTICES.md): the quest page with its two views, the
-- groupings, the details under a row and their texts.
--
-- MIT License
--
-- Copyright (c) 2026 Ugge Zen
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
local _, E = ...
local L = E.L
local Key = E.Key
local A = E.Adventure
local J = E.Journal
local LG = E.LootGuide
local K = E.AdventureKit
local T = E.tokens
local Fmt = A.Fmt
local LP = A.LogPages
local S = A.Store

local KEY = "quests"
local ICON = "Interface\\Icons\\INV_Scroll_03"
local DONE_ICON = "Interface\\GossipFrame\\ActiveQuestIcon"
local OPEN_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local GROUP_CAP = 150          -- rows per group before "Show all n"
local OPEN_GROUPS = 3          -- the newest groups start open

local Text = LP.Text

---------------------------------------------------------------------------
-- Details under a row: wrapped lines and quiet links, in a card
--   { kind = "akDetail", lines = { { text, role, size } }, links = { { label, fn, tip } }, indent }
---------------------------------------------------------------------------
local DETAIL_PAD = 10

local function DetailWidth(item, width)
	return math.max(width - (item.indent or 0) - 2 * DETAIL_PAD, 1)
end

K.ROWS.akDetail = {
	height = function(item, width)
		local h = DETAIL_PAD
		for _, line in ipairs(item.lines or {}) do
			h = h + E.UIKit.TextHeight(line[1] or "", DetailWidth(item, width), line[3] or K.size.small) + 4
		end
		if item.links and item.links[1] then h = h + 20 end
		return h + DETAIL_PAD + 6
	end,
	create = function(row)
		row:EnableMouse(false)
		row.card = K.Card(row, { accent = true })
		row.lines, row.links = {}, {}
	end,
	update = function(row, item)
		row.card:ClearAllPoints()
		row.card:SetPoint("TOPLEFT", row, "TOPLEFT", item.indent or 0, -2)
		row.card:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 4)
		local anchor
		for index = 1, math.max(#row.lines, #(item.lines or {})) do
			local data = item.lines and item.lines[index]
			local fs = row.lines[index]
			if data and not fs then
				fs = K.Text(row.card, K.size.small, "LEFT", "secondary")
				fs:SetWordWrap(true)
				row.lines[index] = fs
			end
			if fs then
				fs:SetShown(data ~= nil)
				if data then
					K.InkFont(fs, data[3] or K.size.small)
					fs:SetText(data[1] or "")
					K.Paint(fs, data[2] or "secondary")
					fs:ClearAllPoints()
					if anchor then
						fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
						fs:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
					else
						fs:SetPoint("TOPLEFT", row.card, "TOPLEFT", DETAIL_PAD + 2, -DETAIL_PAD)
						fs:SetPoint("TOPRIGHT", row.card, "TOPRIGHT", -DETAIL_PAD, -DETAIL_PAD)
					end
					anchor = fs
				end
			end
		end
		local right
		for index = 1, math.max(#row.links, #(item.links or {})) do
			local data = item.links and item.links[index]
			local link = row.links[index]
			if data and not link then
				link = CreateFrame("Button", nil, row.card)
				link:SetHeight(16)
				link.text = K.Text(link, K.size.small, "RIGHT", "secondary")
				link.text:SetPoint("RIGHT")
				link:SetScript("OnEnter", function(self) K.Paint(self.text, "accent") end)
				link:SetScript("OnLeave", function(self) K.Paint(self.text, "secondary") end)
				row.links[index] = link
			end
			if link then
				link:SetShown(data ~= nil)
				if data then
					link.text:SetText(data[1])
					K.Paint(link.text, "secondary")
					link:SetWidth(math.ceil(link.text:GetStringWidth()) + 2)
					E:PadHitRect(link, 4)
					link:SetScript("OnClick", function()
						local ok, err = pcall(data[2])
						if not ok then geterrorhandler()(err) end
					end)
					LG.Kit.Tooltip(link, data[1], data[3])
					link:ClearAllPoints()
					if right then
						link:SetPoint("RIGHT", right, "LEFT", -12, 0)
					else
						link:SetPoint("BOTTOMRIGHT", row.card, "BOTTOMRIGHT", -DETAIL_PAD, DETAIL_PAD - 2)
					end
					right = link
				end
			end
		end
	end,
}

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
local function Rec()
	return J:Char()
end

local function QuestTitle(id, stored)
	if Text(stored) then return stored end
	local quest = LG.Quest and LG:Quest(id)
	if quest and Text(quest.title) then return quest.title end
	local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
	if Text(title) then return title end
	return nil
end

local function Where(zone, sub)
	zone, sub = Text(zone), Text(sub)
	if zone and sub and sub ~= zone then return ("%s, %s"):format(sub, zone) end
	return zone or sub
end

local function Uid(quest)
	return ("%s:%s"):format(tostring(quest.t), tostring(quest.id))
end

-- Hand-ins, newest first.
local function Done(archived)
	local rec = Rec()
	local out = {}
	for index = #(rec and rec.quests or {}), 1, -1 do
		local quest = rec.quests[index]
		if type(quest) == "table" and tonumber(quest.id) and ((quest.archived and true or false) == (archived and true or false)) then
			out[#out + 1] = quest
		end
	end
	return out
end

-- Hand-ins the journal knows of beyond its list (past the cap): the counts
-- stay on the levels.
local function Counted()
	local rec = Rec()
	local total = 0
	for _, level in pairs(rec and rec.levels or {}) do
		if type(level) == "table" then total = total + (tonumber(level.quests) or 0) end
	end
	return total
end

-- Quests that left the log without a hand-in, newest first.
local function Abandoned()
	return J.Abandoned and J:Abandoned() or {}
end

-- Quests the game remembers as done that the journal never saw handed in.
local function Before()
	local C = E.Characters
	local record = C and C.Get and C:Get(E.charKey)
	local history = type(record) == "table" and type(record.quests) == "table" and record.quests.history
	if type(history) ~= "string" or not C.UnpackIDs then return {}, 0 end
	local rec = Rec()
	local known = {}
	for _, quest in ipairs(rec and rec.quests or {}) do
		if type(quest) == "table" and tonumber(quest.id) then known[tonumber(quest.id)] = true end
	end
	local out, unnamed = {}, 0
	for id in pairs(C.UnpackIDs(history)) do
		if not known[id] then
			local data = LG.Quest and LG:Quest(id)
			local title = data and Text(data.title)
			if title then
				local N = A.Next
				local zone = N and N.QuestZone and N.ZoneName and N.ZoneName(N.QuestZone(data)) or nil
				if not zone and data.instance and LG:InstanceInfo(data.instance) then zone = LG:InstanceInfo(data.instance).name end
				out[#out + 1] = { id = id, title = title, level = tonumber(data.level), zone = zone }
			else
				unnamed = unnamed + 1
			end
		end
	end
	table.sort(out, function(a, b)
		if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
		return a.title < b.title
	end)
	return out, unnamed
end

---------------------------------------------------------------------------
-- Settings and state
---------------------------------------------------------------------------
local VIEWS = {
	{ "done", Key("Handed in"), Key("Every quest you handed in since the journal began, with where, when, and what it gave.") },
	{ "open", Key("In progress"), Key("Your quest log now, with where and when you took each quest.") },
	{ "before", Key("Before the journal"), Key("Quests the game remembers you finished before the journal began. The game does not say when.") },
	{ "abandoned", Key("Abandoned"), Key("Quests that left your log without a hand-in: abandoned, failed, or removed by the game. With where and when you took each one.") },
}
local GROUPS = {
	{ "day", Key("Day"), Key("One group per day, newest first.") },
	{ "level", Key("Level"), Key("One group per level, highest first.") },
	{ "zone", Key("Zone"), Key("One group per zone, the latest first.") },
	{ "type", Key("Type"), Key("Dungeon, group, elite, and solo quests; in progress: ready or still to do.") },
}
local VIEW_KEYS = { done = true, open = true, before = true, abandoned = true, archive = true }
local GROUP_KEYS = { day = true, level = true, zone = true, type = true }

local function UIState()
	local rec = Rec()
	local ui = rec and rec.ui
	if type(ui) ~= "table" then
		LP.session = LP.session or {}
		ui = LP.session
	end
	if type(ui.quests) ~= "table" then ui.quests = {} end
	local s = ui.quests
	if not VIEW_KEYS[s.view or ""] then s.view = "done" end
	return s
end

local function Group()
	local group = A.db and A.db.questGroup
	return GROUP_KEYS[group or ""] and group or "day"
end

local function SetGroup(group)
	if A.db and GROUP_KEYS[group] then A.db.questGroup = group end
end

local function Rewards()
	return not (A.db and A.db.questRewards == false)
end

---------------------------------------------------------------------------
-- Groups
---------------------------------------------------------------------------
local function DoneType(quest)
	if Text(quest.instance) then return L["Dungeon quests"] end
	if type(quest.with) == "table" and next(quest.with) then return L["Done with others"] end
	if Text(quest.tag) then return quest.tag end
	return L["On your own"]
end

-- key, label, sort value (bigger first) for a hand-in.
local function DoneGroup(quest, group)
	if group == "level" then
		local level = tonumber(quest.l)
		if not level then return "other", L["Other"], -1 end
		return "level:" .. level, (L["Level %d"]):format(level), level
	elseif group == "zone" then
		local zone = Text(quest.z)
		if not zone then return "other", L["Other"], -1 end
		return "zone:" .. zone, zone, tonumber(quest.t) or 0
	elseif group == "type" then
		local kind = DoneType(quest)
		return "type:" .. kind, kind, tonumber(quest.t) or 0
	end
	if type(quest.t) ~= "number" then return "other", L["Other"], -1 end
	return "day:" .. Fmt.DayKey(quest.t), Fmt.Day(quest.t), quest.t
end

local function OpenGroup(quest, group)
	local start = quest.start
	if group == "type" then
		if quest.ready then return "type:ready", L["Ready to hand in"], 2 end
		return "type:todo", L["Still to do"], 1
	end
	if not start then return "other", L["Other"], -1 end
	if group == "level" then
		local level = tonumber(start.l)
		if not level then return "other", L["Other"], -1 end
		return "level:" .. level, (L["Level %d"]):format(level), level
	elseif group == "zone" then
		local zone = Text(start.z)
		if not zone then return "other", L["Other"], -1 end
		return "zone:" .. zone, zone, tonumber(start.t) or 0
	end
	if type(start.t) ~= "number" then return "other", L["Other"], -1 end
	return "day:" .. Fmt.DayKey(start.t), Fmt.Day(start.t), start.t
end

local function BeforeGroup(quest, group)
	if group == "zone" then
		if not quest.zone then return "other", L["Other"], -1 end
		return "zone:" .. quest.zone, quest.zone, 0
	end
	if not quest.level then return "other", L["Other"], -1 end
	return "level:" .. quest.level, (L["Quest level %d"]):format(quest.level), quest.level
end

-- An abandoned quest: by the day it left the log, the level or the zone you took it in.
local function AbandonedGroup(quest, group)
	if group == "level" then
		local level = tonumber(quest.l)
		if not level then return "other", L["Other"], -1 end
		return "level:" .. level, (L["Level %d"]):format(level), level
	elseif group == "zone" then
		local zone = Text(quest.z)
		if not zone then return "other", L["Other"], -1 end
		return "zone:" .. zone, zone, tonumber(quest.t) or 0
	end
	if type(quest.t) ~= "number" then return "other", L["Other"], -1 end
	return "day:" .. Fmt.DayKey(quest.t), Fmt.Day(quest.t), quest.t
end

-- entries grouped: { { key, label, rank, entries } } sorted, "Other" last.
local function Grouped(entries, fn, group)
	local byKey, list = {}, {}
	for _, entry in ipairs(entries) do
		local key, label, rank = fn(entry, group)
		local bucket = byKey[key]
		if not bucket then
			bucket = { key = key, label = label, rank = rank, entries = {} }
			byKey[key] = bucket
			list[#list + 1] = bucket
		end
		bucket.rank = math.max(bucket.rank, rank)
		bucket.entries[#bucket.entries + 1] = entry
	end
	table.sort(list, function(a, b)
		if (a.key == "other") ~= (b.key == "other") then return b.key == "other" end
		if a.rank ~= b.rank then return a.rank > b.rank end
		return a.label < b.label
	end)
	return list
end

---------------------------------------------------------------------------
-- Matching
---------------------------------------------------------------------------
local function DoneText(quest)
	return E:FoldText(table.concat({ QuestTitle(quest.id, quest.title) or "", Text(quest.z) or "", Text(quest.s) or "",
		Text(quest.objective) or "", Text(quest.giver) or "", Text(quest.taker) or "", Text(quest.tag) or "", DoneType(quest) }, " "))
end

local function AbandonedText(quest)
	return E:FoldText(table.concat({ QuestTitle(quest.id, quest.title) or "", Text(quest.z) or "", Text(quest.s) or "",
		Text(quest.giver) or "" }, " "))
end

local function OpenText(quest)
	local start = quest.start or {}
	return E:FoldText(table.concat({ quest.title or "", Text(start.objective) or "", Text(start.z) or "", Text(start.s) or "",
		Text(start.giver) or "" }, " "))
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
-- lines: texts, and click hints as { action, what }.
local function QuestTip(id, level, lines)
	return function(tooltip)
		local shown = false
		if id and tooltip.SetHyperlink then
			shown = pcall(tooltip.SetHyperlink, tooltip, ("quest:%d:%d"):format(id, tonumber(level) or -1))
		end
		local hints = {}
		for _, line in ipairs(lines or {}) do
			if type(line) == "table" then
				hints[#hints + 1] = line
			else
				if not shown then tooltip:AddLine(" ") shown = true end
				tooltip:AddLine(line, unpack(T.text.secondary))
			end
		end
		E:TooltipHint(tooltip, unpack(hints))
		tooltip:Show()
	end
end

local function NamesOf(set)
	local keys = {}
	for key in pairs(type(set) == "table" and set or {}) do keys[#keys + 1] = key end
	table.sort(keys)
	return keys
end

local function DetailLinks(frame, id, quest)
	local links = {}
	if LG.Quest and LG:Quest(id) then
		links[#links + 1] = { L["Quest details"], function() LG:Open("detail", { quest = id }) end,
			L["Opens the quest in the Loot Guide: where to get it, what it needs, and its rewards."] }
	end
	if quest then
		if quest.archived then
			links[#links + 1] = { L["Restore"], function() frame:Archive(quest, false) end, L["Puts this quest back on the page."] }
		else
			links[#links + 1] = { L["Archive"], function() frame:Archive(quest, true) end, L["Hides this quest from the page. The archive keeps it."] }
		end
	end
	return links
end

local function DoneDetail(frame, quest, indent)
	local lines = {}
	local objective = Text(quest.objective)
	if objective then lines[#lines + 1] = { objective, "body", K.size.label } end
	local giver, taker = Text(quest.giver), Text(quest.taker)
	local from = Where(quest.fromZone, nil)
	local at = Where(quest.z, quest.s)
	if giver then
		local text = from and (L["From %s, %s"]):format(giver, from) or (L["From %s"]):format(giver)
		if taker then text = text .. " · " .. (at and (L["to %s, %s"]):format(taker, at) or (L["to %s"]):format(taker)) end
		lines[#lines + 1] = { text }
	elseif taker then
		lines[#lines + 1] = { L["Started without a quest giver"] .. " · " .. (at and (L["to %s, %s"]):format(taker, at) or (L["to %s"]):format(taker)) }
	end
	if tonumber(quest.started) and type(quest.t) == "number" then
		lines[#lines + 1] = { (L["Picked up %s · handed in %s · took %s"]):format(("%s, %s"):format(Fmt.Short(quest.started), Fmt.Clock(quest.started)),
			Fmt.Clock(quest.t), Fmt.Span(quest.t - quest.started)) }
	elseif type(quest.t) == "number" then
		lines[#lines + 1] = { (L["Handed in %s"]):format(("%s, %s"):format(Fmt.Day(quest.t), Fmt.Clock(quest.t))) }
	end
	local with = NamesOf(quest.with)
	if #with > 0 then
		local H = A.History
		lines[#lines + 1] = { (L["Done with %s"]):format(H and H.Names(with, 6) or table.concat(with, ", ")), "body" }
	end
	local rewards = {}
	if tonumber(quest.xp) and quest.xp > 0 then rewards[#rewards + 1] = (L["%s XP"]):format(BreakUpLargeNumbers(quest.xp)) end
	local money = LP.Money(quest.m)
	if money then rewards[#rewards + 1] = money end
	if #rewards > 0 then lines[#lines + 1] = { (L["Earned %s"]):format(table.concat(rewards, " · ")) } end
	if not (objective or giver or taker or quest.started) then
		lines[#lines + 1] = { L["Handed in before the journal kept a quest's story."], "dim" }
	end
	return { kind = "akDetail", lines = lines, links = DetailLinks(frame, quest.id, quest), indent = indent }
end

local function DoneRow(frame, quest)
	local title = QuestTitle(quest.id, quest.title) or (L["Quest %d"]):format(quest.id)
	local bits = {}
	local where = Where(quest.z, quest.s)
	if where then bits[#bits + 1] = where end
	if tonumber(quest.l) then bits[#bits + 1] = (L["level %d"]):format(quest.l) end
	local group = Group()
	if group ~= "day" and type(quest.t) == "number" then bits[#bits + 1] = Fmt.Short(quest.t) end
	if group == "day" and type(quest.t) == "number" then bits[#bits + 1] = Fmt.Clock(quest.t) end
	local money = Rewards() and LP.Money(quest.m)
	if money then bits[#bits + 1] = money end
	local xp = Rewards() and tonumber(quest.xp) and quest.xp > 0 and (L["%s XP"]):format(BreakUpLargeNumbers(quest.xp)) or nil
	local uid = Uid(quest)
	return { kind = "ledger", icon = DONE_ICON, title = title, sub = table.concat(bits, " · "), time = xp, quest = quest, uid = uid,
		titleRole = frame.expanded[uid] and "head" or nil,
		tip = QuestTip(quest.id, quest.l, { { L["Click"], L["the story of this quest"] }, { L["Right-click"], L["more"] } }), tipTitle = title,
		onClick = function(_, button, owner)
			if button == "RightButton" then frame:Menu(quest, owner) else frame:Toggle(uid) end
		end }
end

local function OpenDetail(quest, indent)
	local start = quest.start or {}
	local lines = {}
	local objective = Text(start.objective)
	if not objective and A.Chronicle and A.Chronicle.Objectives then objective = A.Chronicle.Objectives(quest.questID) end
	if objective then lines[#lines + 1] = { objective, "body", K.size.label } end
	local giver, where = Text(start.giver), Where(start.z, start.s)
	if giver then
		lines[#lines + 1] = { where and (L["From %s, %s"]):format(giver, where) or (L["From %s"]):format(giver) }
	elseif where then
		lines[#lines + 1] = { (L["Picked up in %s"]):format(where) }
	end
	if type(start.t) == "number" then
		lines[#lines + 1] = { (L["Picked up %s · %s ago"]):format(("%s, %s"):format(Fmt.Short(start.t), Fmt.Clock(start.t)),
			Fmt.Span(time() - start.t)) }
	else
		lines[#lines + 1] = { L["Taken before the journal kept track."], "dim" }
	end
	local with = NamesOf(start.with)
	if #with > 0 then
		local H = A.History
		lines[#lines + 1] = { (L["Doing it with %s"]):format(H and H.Names(with, 6) or table.concat(with, ", ")), "body" }
	end
	return { kind = "akDetail", lines = lines, links = DetailLinks(nil, quest.questID, nil), indent = indent }
end

local function OpenRow(frame, quest)
	local start = quest.start
	local bits = {}
	if start then
		local where = Where(start.z, start.s)
		if where then bits[#bits + 1] = (L["Picked up in %s"]):format(where) end
		if type(start.t) == "number" then
			bits[#bits + 1] = Fmt.When(start.t)
			bits[#bits + 1] = (L["%s on it"]):format(Fmt.Span(time() - start.t))
		end
		if tonumber(start.l) then bits[#bits + 1] = (L["level %d"]):format(start.l) end
	else
		if quest.level then bits[#bits + 1] = (L["Quest level %d"]):format(quest.level) end
		bits[#bits + 1] = L["taken before the journal kept track"]
	end
	local right
	if quest.ready then
		right = K.InkHex("good") .. L["Ready"] .. "|r"
	elseif quest.need > 0 then
		right = ("%d / %d"):format(quest.have, quest.need)
	end
	local uid = "open:" .. quest.questID
	return { kind = "ledger", icon = OPEN_ICON, title = quest.title, sub = table.concat(bits, " · "), time = right, uid = uid,
		titleRole = frame.expanded[uid] and "head" or nil, open = quest,
		tip = QuestTip(quest.questID, quest.level, { { L["Click"], L["where you took it"] } }), tipTitle = quest.title,
		onClick = function() frame:Toggle(uid) end }
end

local function BeforeRow(quest)
	local bits = {}
	if quest.level then bits[#bits + 1] = (L["Quest level %d"]):format(quest.level) end
	if quest.zone then bits[#bits + 1] = quest.zone end
	bits[#bits + 1] = L["the game remembers it as done"]
	return { kind = "ledger", icon = DONE_ICON, title = quest.title, sub = table.concat(bits, " · "), uid = "before:" .. quest.id,
		tip = QuestTip(quest.id, quest.level, { L["Done before the journal began. The game does not say when."],
			LG.Quest and LG:Quest(quest.id) and { L["Click"], L["open it in the Loot Guide"] } or nil }), tipTitle = quest.title,
		onClick = (LG.Quest and LG:Quest(quest.id)) and function() LG:Open("detail", { quest = quest.id }) end or nil }
end

local function AbandonedRow(quest)
	local id = tonumber(quest.id)
	local title = QuestTitle(id, quest.title) or (L["Quest %d"]):format(id or 0)
	local bits = {}
	local where = Where(quest.z, quest.s)
	if where then bits[#bits + 1] = (L["Picked up in %s"]):format(where) end
	if tonumber(quest.l) then bits[#bits + 1] = (L["level %d"]):format(quest.l) end
	if tonumber(quest.started) and type(quest.t) == "number" and quest.t >= quest.started then
		bits[#bits + 1] = (L["in your log for %s"]):format(Fmt.Span(quest.t - quest.started))
	end
	local lines = {}
	if Text(quest.giver) then lines[#lines + 1] = (L["From %s"]):format(quest.giver) end
	if type(quest.t) == "number" then
		lines[#lines + 1] = (L["Left your log %s"]):format(("%s, %s"):format(Fmt.Short(quest.t), Fmt.Clock(quest.t)))
	end
	local known = id and LG.Quest and LG:Quest(id)
	if known then lines[#lines + 1] = { L["Click"], L["open it in the Loot Guide"] } end
	return { kind = "ledger", icon = OPEN_ICON, title = title, sub = table.concat(bits, " · "),
		time = type(quest.t) == "number" and Fmt.Clock(quest.t) or nil, uid = ("abandoned:%s:%s"):format(tostring(quest.t), tostring(id)),
		tip = QuestTip(id, quest.l, lines), tipTitle = title,
		onClick = known and function() LG:Open("detail", { quest = id }) end or nil }
end

-- Ledger cards of a group; an expanded quest breaks the card for its story.
local function Cards(frame, items, rows)
	local run = {}
	local function Flush()
		LP.Card(items, run)
		run = {}
	end
	for _, row in ipairs(rows) do
		run[#run + 1] = row
		if frame.expanded[row.uid] then
			Flush()
			items[#items + 1] = row.quest and DoneDetail(frame, row.quest, 24) or row.open and OpenDetail(row.open, 24) or nil
		end
	end
	Flush()
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function GroupItems(frame, groups, makeRow, notes, prefix)
	local items = {}
	local words = frame.words
	local force = #words > 0
	for index, bucket in ipairs(groups) do
		local foldKey = ("quests:%s:%s"):format(prefix, bucket.key)
		local open = force or frame.forceOpen == bucket.label or K.FoldOpen(foldKey, index <= OPEN_GROUPS)
		bucket.foldKey, bucket.index = foldKey, #items + 1
		items[#items + 1] = { kind = "fold", key = foldKey, label = bucket.label, note = notes(bucket), open = open,
			onToggle = function() frame:Draw(true) end }
		if open then
			items[#items + 1] = { kind = "space", height = 4 }
			local rows = {}
			for position, entry in ipairs(bucket.entries) do
				if position > GROUP_CAP and not frame.all[foldKey] then
					break
				end
				rows[#rows + 1] = makeRow(frame, entry)
			end
			Cards(frame, items, rows)
			if #bucket.entries > GROUP_CAP and not frame.all[foldKey] then
				items[#items + 1] = { kind = "more", text = (L["Show all %d"]):format(#bucket.entries), onClick = function()
					frame.all[foldKey] = true
					frame:Draw(true)
				end }
			end
		end
		items[#items + 1] = { kind = "space", height = 8 }
	end
	return items
end

local function DoneNote(bucket)
	local xp = 0
	for _, quest in ipairs(bucket.entries) do xp = xp + (tonumber(quest.xp) or 0) end
	local text = E:Plural(#bucket.entries, "%d quest", "%d quests"):format(#bucket.entries)
	if xp > 0 and Rewards() then text = text .. " · " .. (L["%s XP"]):format(BreakUpLargeNumbers(xp)) end
	return text
end

local function OpenNote(bucket)
	local ready = 0
	for _, quest in ipairs(bucket.entries) do if quest.ready then ready = ready + 1 end end
	local text = E:Plural(#bucket.entries, "%d quest", "%d quests"):format(#bucket.entries)
	if ready > 0 then text = text .. " · " .. E:Plural(ready, "%d ready", "%d ready"):format(ready) end
	return text
end

local function AbandonedNote(bucket)
	return E:Plural(#bucket.entries, "%d quest", "%d quests"):format(#bucket.entries)
end

local function BeforeNote(bucket)
	return E:Plural(#bucket.entries, "%d quest", "%d quests"):format(#bucket.entries)
end

local function DoneSentence(done)
	local xp, money, zones = 0, 0, {}
	for _, quest in ipairs(done) do
		xp = xp + (tonumber(quest.xp) or 0)
		money = money + (tonumber(quest.m) or 0)
		local zone = Text(quest.z)
		if zone then zones[zone] = (zones[zone] or 0) + 1 end
	end
	local total = math.max(#done, Counted())
	if total == 0 then return L["No quests handed in yet."] end
	local top, topCount = nil, 0
	for zone, count in pairs(zones) do
		if count > topCount or (count == topCount and top and zone < top) then top, topCount = zone, count end
	end
	local sentence = LP.Count(total, "%s quest handed in", "%s quests handed in")
	local coins = LP.Money(money)
	if xp > 0 and coins then
		sentence = (L["%s, %s experience and %s earned."]):format(sentence, K.Num(BreakUpLargeNumbers(xp)), coins)
	elseif xp > 0 then
		sentence = (L["%s and %s experience earned."]):format(sentence, K.Num(BreakUpLargeNumbers(xp)))
	else
		sentence = sentence .. "."
	end
	if top and topCount > 1 then sentence = sentence .. " " .. (L["Most of them in %s."]):format(K.Num(top)) end
	if total > #done + 0 and Counted() > #(Rec() and Rec().quests or {}) then
		local older = Counted() - #(Rec().quests)
		sentence = sentence .. " " .. E:Plural(older, "The oldest %d is kept as a count on its level.",
			"The oldest %d are kept as counts on their levels."):format(older)
	end
	return sentence
end

local function Draw(frame, keepScroll)
	local s = UIState()
	local group = Group()
	frame.words = LP.Words(K.Query(KEY .. ":" .. (s.view == "open" and "open" or "done")))
	local view = s.view
	local done = Done(false)
	local archived = Done(true)
	local open = J.OpenQuests and J:OpenQuests() or {}
	local before, unnamed = {}, 0
	if view == "before" then before, unnamed = Before() end
	local beforeCount = frame.beforeCount
	if view == "before" or beforeCount == nil then
		local list, nameless = before, unnamed
		if view ~= "before" then list, nameless = Before() end
		beforeCount = #list + nameless
		frame.beforeCount = beforeCount
	end
	local abandoned = Abandoned()
	if view == "before" and beforeCount == 0 then view = "done" s.view = "done" end
	if view == "abandoned" and #abandoned == 0 then view = "done" s.view = "done" end
	if view == "archive" and #archived == 0 then view = "done" s.view = "done" end

	-- Controls
	frame.view:SetActive(view ~= "archive" and view or nil)
	frame.view:SetLabel("open", #open > 0 and (L["In progress"] .. " " .. K.InkHex("secondary") .. #open .. "|r") or L["In progress"])
	frame.view:SetLabel("before", beforeCount > 0 and (L["Before the journal"] .. " " .. K.InkHex("secondary") .. beforeCount .. "|r") or L["Before the journal"])
	frame.view:SetLabel("abandoned", #abandoned > 0 and (L["Abandoned"] .. " " .. K.InkHex("secondary") .. #abandoned .. "|r") or L["Abandoned"])
	for _, button in ipairs(frame.view.buttons) do
		if button.key == "before" then button:SetShown(beforeCount > 0) end
		if button.key == "abandoned" then button:SetShown(#abandoned > 0) end
	end
	if frame.view.Layout then frame.view:Layout() end
	local effectiveGroup = group
	if view == "before" and (group == "day" or group == "type") then effectiveGroup = "level" end
	if view == "abandoned" and group == "type" then effectiveGroup = "day" end
	frame.group:SetActive(effectiveGroup)
	for _, button in ipairs(frame.group.buttons) do
		button:SetShown((view ~= "before" or button.key == "level" or button.key == "zone")
			and (view ~= "abandoned" or button.key ~= "type"))
	end
	frame.group:Layout()
	local searchKey = KEY .. ":" .. (view == "open" and "open" or "done")
	if frame.search.key ~= searchKey then
		frame.search.key = searchKey
		frame.search:SetText(K.Query(searchKey))
		if frame.search.Instructions then
			frame.search.Instructions:SetText(view == "open" and L["Search your quest log"] or L["Search quests"])
		end
		frame.words = LP.Words(K.Query(searchKey))
	end

	-- Header
	frame.header:SetTitle(view == "archive" and L["Archived quests"] or L["Quests"])
	local actions = {}
	if view == "archive" then
		actions[1] = { L["Back"], function() frame:SetView("done") end, L["Back to the quests you handed in."] }
	elseif #archived > 0 then
		actions[1] = { (L["Archive %d"]):format(#archived), function() frame:SetView("archive") end, L["The quests you archived, with Restore."] }
	end
	frame.header:SetActions(actions)

	local words = frame.words
	local items = {}
	if view == "open" then
		local ready = 0
		for _, quest in ipairs(open) do if quest.ready then ready = ready + 1 end end
		if #open > 0 then
			local sentence = LP.Count(#open, "%s quest in your log", "%s quests in your log")
			if ready > 0 then sentence = sentence .. ", " .. LP.Count(ready, "%s ready to hand in", "%s ready to hand in") end
			frame.header:SetSentence(sentence .. ".")
		else
			frame.header:SetSentence(L["Your quest log is empty."])
		end
		local shown = {}
		for _, quest in ipairs(open) do
			if #words == 0 or LP.Hits(OpenText(quest), words) then shown[#shown + 1] = quest end
		end
		items = GroupItems(frame, Grouped(shown, OpenGroup, group), OpenRow, OpenNote, "open:" .. group)
		if #open == 0 then
			frame.list:SetEmpty(L["Your quest log is empty"], L["Pick up a quest and it shows here until you hand it in."], OPEN_ICON)
		else
			frame.list:SetEmpty(L["Nothing matches"], L["No quest in your log matches that search."], OPEN_ICON,
				{ { L["Clear the search"], function() frame:SetSearch("") end } })
		end
	elseif view == "abandoned" then
		frame.header:SetSentence(E:Plural(#abandoned, "%s quest left your log without a hand-in.",
			"%s quests left your log without a hand-in."):format(K.Num(BreakUpLargeNumbers(#abandoned))))
		local shown = {}
		for _, quest in ipairs(abandoned) do
			if #words == 0 or LP.Hits(AbandonedText(quest), words) then shown[#shown + 1] = quest end
		end
		items[#items + 1] = { kind = "akText", text = L["Abandoned, failed, or removed by the game. The journal only lists them; nothing is picked up again for you."] }
		local grouped = GroupItems(frame, Grouped(shown, AbandonedGroup, effectiveGroup), function(_, quest) return AbandonedRow(quest) end,
			AbandonedNote, "abandoned:" .. effectiveGroup)
		for _, item in ipairs(grouped) do items[#items + 1] = item end
		if #shown == 0 then items = {} end
		frame.list:SetEmpty(L["Nothing matches"], L["No quest matches that search."], OPEN_ICON,
			{ { L["Clear the search"], function() frame:SetSearch("") end } })
	elseif view == "before" then
		frame.header:SetSentence(E:Plural(beforeCount, "The game remembers %s quest you finished before the journal began.",
			"The game remembers %s quests you finished before the journal began."):format(K.Num(BreakUpLargeNumbers(beforeCount))))
		local shown = {}
		for _, quest in ipairs(before) do
			if #words == 0 or LP.Hits(E:FoldText(quest.title .. " " .. (quest.zone or "")), words) then shown[#shown + 1] = quest end
		end
		items[#items + 1] = { kind = "akText", text = L["From the game's list of completed quests (the Characters record). Undated: the game does not say when you did them."] }
		local grouped = GroupItems(frame, Grouped(shown, BeforeGroup, effectiveGroup), function(_, quest) return BeforeRow(quest) end,
			BeforeNote, "before:" .. effectiveGroup)
		for _, item in ipairs(grouped) do items[#items + 1] = item end
		if unnamed > 0 then
			items[#items + 1] = { kind = "akText", text = E:Plural(unnamed, "And %d more the Loot Guide's quest data has no name for.",
				"And %d more the Loot Guide's quest data has no name for."):format(unnamed) }
		end
		if #shown == 0 then items = {} end
		frame.list:SetEmpty(L["Nothing matches"], L["No quest matches that search."], DONE_ICON,
			{ { L["Clear the search"], function() frame:SetSearch("") end } })
	else
		local list = view == "archive" and archived or done
		frame.header:SetSentence(view == "archive" and LP.Count(#archived, "%s archived quest.", "%s archived quests.") or DoneSentence(done))
		local shown = {}
		for _, quest in ipairs(list) do
			if #words == 0 or LP.Hits(DoneText(quest), words) then shown[#shown + 1] = quest end
		end
		items = GroupItems(frame, Grouped(shown, DoneGroup, group), DoneRow, DoneNote, (view == "archive" and "archive:" or "done:") .. group)
		if #list == 0 then
			local buttons = #open > 0 and { { L["Show the quests in progress"], function() frame:SetView("open") end } } or nil
			frame.list:SetEmpty(L["No quests handed in yet"], L["Each quest you hand in is written here, with where and when."], DONE_ICON, buttons)
		else
			frame.list:SetEmpty(L["Nothing matches"], L["No quest matches that search."], DONE_ICON,
				{ { L["Clear the search"], function() frame:SetSearch("") end } })
		end
	end
	frame.viewShown = view
	frame.items = items
	frame.list:SetData(items, keepScroll)
	frame.forceOpen = nil
end

---------------------------------------------------------------------------
-- The section
---------------------------------------------------------------------------
local function Build(parent)
	local frame
	frame = LP.Page(parent, {
		controlsHeight = 46,
		empty = { L["No quests handed in yet"], "", DONE_ICON },
		controls = function(page, bar)
			page.view = K.Switch(bar, VIEWS, UIState().view, function(view) page:SetView(view) end)
			page.view:SetPoint("TOPLEFT", 0, 0)
			page.group = K.Switch(bar, GROUPS, Group(), function(group)
				SetGroup(group)
				page:Draw()
			end)
			page.group:SetPoint("TOPRIGHT", 0, 0)
			page.search = K.Search(bar, KEY .. ":done", L["Search quests"], function() page:Draw() end)
			page.search:SetPoint("TOPLEFT", 0, -26)
			page.search:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -26)
		end,
	})
	frame.expanded, frame.all = {}, {}

	function frame:Draw(keepScroll)
		if not self:IsShown() then
			self.dirty = true
			return
		end
		self.dirty = false
		local started = debugprofilestop()
		Draw(self, keepScroll)
		self.buildMs = debugprofilestop() - started
	end

	function frame:SetView(view)
		if not VIEW_KEYS[view or ""] then return end
		UIState().view = view
		self.beforeCount = nil
		self:Draw()
	end

	function frame:Toggle(uid)
		self.expanded[uid] = not self.expanded[uid] or nil
		self:Draw(true)
	end

	function frame:SetSearch(text)
		self.search:SetText(text or "")
		self.search:GetScript("OnTextChanged")(self.search, true)
	end

	function frame:Archive(quest, on)
		local rec = S.Own()
		if not rec then return end
		quest.archived = on and time() or nil
		S.Bump(rec)
		A:MarkDirty("quests")
		self:Draw(true)
	end

	function frame:Menu(quest, owner)
		E.UIKit.ContextMenu(owner or self, function(_, root)
			root:CreateTitle(QuestTitle(quest.id, quest.title) or (L["Quest %d"]):format(quest.id))
			root:CreateButton(self.expanded[Uid(quest)] and L["Hide the story"] or L["Show the story"], function() self:Toggle(Uid(quest)) end)
			if LG.Quest and LG:Quest(quest.id) then
				root:CreateButton(L["Quest details"], function() LG:Open("detail", { quest = quest.id }) end)
			end
			if Text(quest.z) and A:SectionShown("places") then
				root:CreateButton((L["Open %s in Places"]):format(quest.z), function() A:OpenSection("places", { place = quest.z }) end)
			end
			if quest.archived then
				root:CreateButton(L["Restore"], function() self:Archive(quest, false) end)
			else
				root:CreateButton(L["Archive"], function() self:Archive(quest, true) end)
			end
		end)
	end

	-- Scroll to and open one quest (a hand-in, else one in the log).
	function frame:ShowQuest(questID, t)
		questID = tonumber(questID)
		if not questID then return false end
		local target
		for _, quest in ipairs(Done(false)) do
			if quest.id == questID and (not t or quest.t == t) then
				target = quest
				break
			end
		end
		local s = UIState()
		local uid, groupKey
		if target then
			s.view = "done"
			uid = Uid(target)
			groupKey = select(1, DoneGroup(target, Group()))
			K.SetFoldOpen(("quests:done:%s:%s"):format(Group(), groupKey), true)
		else
			for _, quest in ipairs(J.OpenQuests and J:OpenQuests() or {}) do
				if quest.questID == questID then target = quest end
			end
			if not target then return false end
			s.view = "open"
			uid = "open:" .. questID
			groupKey = select(1, OpenGroup(target, Group()))
			K.SetFoldOpen(("quests:open:%s:%s"):format(Group(), groupKey), true)
		end
		self.expanded[uid] = true
		self:SetSearch("")
		self:Draw()
		for index, item in ipairs(self.items or {}) do
			if item.uid == uid then
				self.list:ScrollTo(index, "center")
				self.shownQuest = uid
				return true
			end
		end
		return false
	end

	frame:SetScript("OnShow", function(self) if self.dirty then self:Draw(true) end end)
	return frame
end

local function Show(frame, arg)
	if type(arg) == "string" then
		local kind, id = J:ParseAddress(arg)
		if kind == "quest" then arg = { quest = id } elseif VIEW_KEYS[arg] then arg = { view = arg } else arg = { search = arg } end
	end
	if type(arg) == "table" then
		if arg.view and VIEW_KEYS[arg.view] then UIState().view = arg.view end
		if arg.group and GROUP_KEYS[arg.group] then
			SetGroup(arg.group)
			UIState().view = "done"
		end
		if arg.open then
			frame.forceOpen = arg.open
			K.SetFoldOpen(("quests:done:%s:zone:%s"):format(Group(), tostring(arg.open)), true)
		end
		if arg.search then frame:SetSearch(arg.search) end
		if arg.quest then
			frame:ShowQuest(arg.quest, tonumber(arg.t))
			return
		end
	end
	frame:Draw(true)
	if type(arg) == "table" and arg.open then
		for index, item in ipairs(frame.items or {}) do
			if item.kind == "fold" and item.label == arg.open then
				frame.list:ScrollTo(index, "top")
				break
			end
		end
	end
end

local function Refresh(frame, changed)
	if changed.adventure or changed.quests or changed.settings or changed.data then frame:Draw(true) end
end

local function ReadyCount()
	local ready = 0
	for _, quest in ipairs(J.OpenQuests and J:OpenQuests() or {}) do
		if quest.ready then ready = ready + 1 end
	end
	return ready
end

A:RegisterSection(KEY, {
	title = "Quests",
	icon = ICON,
	desc = "Every quest you handed in, with where, when, who gave it, and who came along; your quest log; and the quests the game remembers from before.",
	words = { "quests", "quest", "questlog", "hand-ins" },
	count = function()
		local ready = ReadyCount()
		return ready > 0 and ready or nil
	end,
	build = Build,
	show = Show,
	refresh = Refresh,
	search = function(text)
		local words = LP.Words(text)
		if #words == 0 then return {} end
		local out = {}
		for _, quest in ipairs(Done(false)) do
			if LP.Hits(DoneText(quest), words) then
				local title = QuestTitle(quest.id, quest.title) or (L["Quest %d"]):format(quest.id)
				local where = Where(quest.z, quest.s)
				out[#out + 1] = { title = title, sub = where and (L["Handed in: %s"]):format(where) or L["Handed in"], icon = DONE_ICON,
					arg = { quest = quest.id, t = quest.t } }
				if #out >= 20 then break end
			end
		end
		return out
	end,
})
