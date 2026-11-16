-- EldoUI My Adventure: the Today section, the landing page of the hub.
--
--   +----------------------------------------------------------------+
--   | [portrait] Mira Brightwood                [Next trips][Story]  |
--   |            Gnome Mage, level 24 · Chapter 24: Duskwood         |
--   |            [=========XP=====rested====          ]              |
--   |            62% of the way to 25 · rested 31% · ~1h 20m to 25   |
--   |----------------------------------------------------------------|
--   | [Where you left off: away 2 days, last time, the last moments] |
--   | NEXT TRIP ---------------------------------------------------- |
--   |  the top suggestion as a card; a dungeon opens as a trip plan  |
--   | ALSO GOOD ---------------------------------------------------- |
--   |  three more ideas, one per kind where possible                 |
--   | WAITING FOR YOU ---------------------------------------------- |
--   |  quests to hand in, attunements under way, goals, reminders,   |
--   |  trainer spells, mail running out, what to sort before a trip  |
--   | THIS SESSION ------------------------------------------------- |
--   |  2h 05m · level 23 to 24 · 9 quests   Best moment: ...         |
--   | LATELY ------------------------------------------------------- |
--   |  the last five moments, keepsakes first                        |
--   | WHAT IS AHEAD ------------------------------------------------ |
--   |  [25 Shadowfang Keep opens][30 Level 30][60 the level cap]     |
--   +----------------------------------------------------------------+
--
-- One look answers: who am I, where should I go now, what is waiting, and
-- what just happened. Everything comes from the game, the journal and the
-- where-next engine (J:Next, J:TripPlan, J:PrepChecklist, J:Pace,
-- J:PaceText, J:RestedPlan, J:Milestones); nothing is guessed, and every
-- button is navigation (Next trips' actions, A.NextUI.Run).
--
-- A fresh journal gets a welcome card with what EldoUI already knew from
-- its other records and the journal tour (Tour.lua). A level 1 character
-- and a character at the level cap both get pages written for them.
--
-- After a break ("Show the resume card after", resumeAfter seconds; 0 is
-- never) the page opens with "Where you left off": how long you were away,
-- the last session in one line (A:SessionRecap, the same recap Story so
-- far shows), the rested gained meanwhile and the last moments before you
-- left. "Got it" puts it away for this login (with Undo). "This session"
-- is the same recap for the session you play now.
--
-- Before a dungeon trip that is not the top card, "Waiting for you" says
-- what the prep checklist (J:PrepChecklist) finds missing: bag space,
-- repairs, food and water, ammo, the hearthstone. Display only.
--
-- A new keepsake (the "Keepsake" callback of Moments.lua) shows in Lately
-- at once, marked New for this session.
--
-- Route (A:OpenSection("today", arg)): nil, { welcome = true } to show
-- the welcome card again, or { resume = true } to show the resume card
-- again.
local _, E = ...
local L = E.L
local Key = E.Key
local A = E.Adventure
local J = E.Journal
local LG = E.LootGuide
local K = E.AdventureKit
local T = E.tokens

local KEY = "today"
local HEADER = 84
local PORTRAIT = 48
local MAIL_DAYS = 3
local LATELY = 5
local ALSO = 3
local RESUME_MOMENTS = 3
local RESUME_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_02"
local SESSION_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"

local Plain = A.Plain

local function Kit() return LG.Kit end
local function PageKit() return LG.PageKit end
local function NX() return A.NextUI end

local function Safe(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then
		geterrorhandler()(a)
		return nil
	end
	return a, b, c
end

local function Text(value)
	value = Plain(value)
	if type(value) == "string" and value ~= "" then return value end
	return nil
end

local function Num(value)
	value = Plain(value)
	return type(value) == "number" and value or nil
end

local function UIState()
	local rec = J.Char and J:Char()
	return rec and type(rec.ui) == "table" and rec.ui or nil
end

local PrepRow   -- "Waiting for you" before a dungeon trip (below)

---------------------------------------------------------------------------
-- The header: who you are and how far this level is
---------------------------------------------------------------------------
-- The zone this level's chapter is named after: most time at this level,
-- else where you are.
local function ChapterZone(level)
	local rec = J:Char()
	local record = rec and type(rec.levels) == "table" and rec.levels[level]
	local best, most
	for zone, seconds in pairs(type(record) == "table" and type(record.zones) == "table" and record.zones or {}) do
		seconds = tonumber(seconds) or 0
		if type(zone) == "string" and (not most or seconds > most or (seconds == most and zone < best)) then best, most = zone, seconds end
	end
	if best then return best end
	return Text(GetRealZoneText and GetRealZoneText())
end
A.TodayChapterZone = ChapterZone

local function PlayerName()
	local first, last = E:NameParts("player")
	first, last = Text(first), Text(last)
	if first and last then return ("%s %s"):format(first, last) end
	return first or Text(UnitName("player")) or L["Today"]
end

local function BuildHeader(frame)
	local header = CreateFrame("Frame", nil, frame)
	header:SetHeight(HEADER)
	header.portrait = K.Art(header, PORTRAIT)
	header.portrait:SetPoint("TOPLEFT", 0, -2)
	header.name = K.Text(header, T.size.windowTitle, "LEFT", "head", true)
	-- The name and the line under it stop before the buttons at the top
	-- right (HeaderActions); the bar and the line under it take the width.
	header.name:SetPoint("TOPLEFT", PORTRAIT + 12, 0)
	header.name:SetPoint("TOPRIGHT", -8, 0)
	header.name:SetWordWrap(false)
	header.who = K.Text(header, K.size.label, "LEFT", "secondary")
	header.who:SetPoint("TOPLEFT", header.name, "BOTTOMLEFT", 0, -4)
	header.who:SetPoint("TOPRIGHT", header.name, "BOTTOMRIGHT", 0, -4)
	header.who:SetWordWrap(false)
	header.xp = K.Track(header, 8)
	header.xp:SetPoint("TOPLEFT", header.who, "BOTTOMLEFT", 0, -8)
	header.xp:SetPoint("TOPRIGHT", header.who, "BOTTOMRIGHT", 8, -8)
	header.rested = header.xp:CreateTexture(nil, "ARTWORK", nil, -1)
	header.rested:SetPoint("TOPLEFT", header.xp, "TOPLEFT", E:PixelFor(header.xp), -E:PixelFor(header.xp))
	header.rested:SetPoint("BOTTOMLEFT", header.xp, "BOTTOMLEFT", E:PixelFor(header.xp), E:PixelFor(header.xp))
	header.xpHit = CreateFrame("Frame", nil, header)
	header.xpHit:SetPoint("TOPLEFT", header.xp, "TOPLEFT", 0, 4)
	header.xpHit:SetPoint("BOTTOMRIGHT", header.xp, "BOTTOMRIGHT", 0, -16)
	header.xpHit:EnableMouse(true)
	header.line = K.Text(header, K.size.small, "LEFT", "secondary")
	header.line:SetPoint("TOPLEFT", header.xp, "BOTTOMLEFT", 0, -6)
	header.line:SetPoint("TOPRIGHT", header.xp, "BOTTOMRIGHT", 0, -6)
	header.line:SetWordWrap(false)
	header.rule = Kit().Divider(header)
	header.rule:SetPoint("BOTTOMLEFT")
	header.rule:SetPoint("BOTTOMRIGHT")
	header.buttons = {}
	return header
end

local function HeaderActions(frame)
	local header = frame.header
	local actions = {}
	if A:SectionShown("story") then
		actions[#actions + 1] = { L["Story so far"], function() A:OpenSection("story") end, L["Your character's story in a few pages."] }
	end
	if A:SectionShown("next") then
		actions[#actions + 1] = { L["Next trips"], function() A:OpenSection("next") end, L["Every idea for where to go next, with filters."] }
	end
	local anchor
	local reserve = 8 -- the room the buttons take at the right, with the gap
	for index = 1, math.max(#header.buttons, #actions) do
		local data = actions[index]
		local button = header.buttons[index]
		if data and not button then
			button = Kit().Button(header, "", 80, T.height.button)
			header.buttons[index] = button
		end
		if button then
			button:SetShown(data ~= nil)
			if data then
				button:SetText(data[1])
				E.UIKit.FitButton(button, 60)
				button:SetScript("OnClick", data[2])
				Kit().Tooltip(button, data[1], data[3])
				button:ClearAllPoints()
				if anchor then
					button:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
				else
					button:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
				end
				anchor = button
				reserve = reserve + button:GetWidth() + 8
			end
		end
	end
	header.name:SetPoint("TOPRIGHT", header, "TOPRIGHT", -reserve, 0)
	header.xp:SetPoint("TOPRIGHT", header.who, "BOTTOMRIGHT", reserve, -8)
end

local function DrawHeader(frame)
	local header = frame.header
	if SetPortraitTexture then pcall(SetPortraitTexture, header.portrait.icon, "player") end
	E:TrimIcon(header.portrait.icon)
	header.name:SetText(PlayerName())
	local pace = Safe(J.Pace, J) or {}
	local level = pace.level or Num(UnitLevel("player")) or 1
	local who = {}
	local race, class = Text(UnitRace("player")), Text(UnitClass("player"))
	if race then who[#who + 1] = race end
	if class then who[#who + 1] = class end
	local line = #who > 0 and (L["%s, level %s"]):format(table.concat(who, " "), K.Num(level)) or (L["Level %s"]):format(K.Num(level))
	local zone = ChapterZone(level)
	if zone then line = line .. "  ·  " .. (L["Chapter %d: %s"]):format(level, zone) end
	header.who:SetText(line)
	-- The XP bar with the rested part.
	local xp, xpMax, rested = pace.xp or 0, pace.xpMax or 0, pace.rested or 0
	local bits = {}
	if pace.atMax then
		header.xp:SetProgress(1, 1)
		header.rested:Hide()
		bits[#bits + 1] = (L["Level %d, the level cap."]):format(level)
		header.xpTip = L["Every level is behind you. The journal keeps writing down your runs, finds, and standings."]
	else
		header.xp:SetProgress(xp, math.max(xpMax, 1))
		local width = header.xp:GetWidth() or 0
		if rested > 0 and xpMax > 0 and width > 0 then
			local c = E.media.accentColor
			header.rested:SetColorTexture(c[1], c[2], c[3], 0.35)
			header.rested:SetWidth(math.max(1, (width - 2 * E:PixelFor(header.xp)) * math.min(xp + rested, xpMax) / xpMax))
			header.rested:Show()
		else
			header.rested:Hide()
		end
		if pace.percent then bits[#bits + 1] = (L["%s%% of the way to level %d"]):format(tostring(pace.percent), level + 1) end
		if (pace.restedPercent or 0) > 0 then bits[#bits + 1] = (L["rested %d%% of a level"]):format(pace.restedPercent) end
		if pace.text then bits[#bits + 1] = pace.text end
		local plan = Safe(J.RestedPlan, J)
		header.xpTip = plan and table.concat(plan.lines or {}, "\n") or nil
	end
	if pace.atLevel and pace.atLevel > 0 then bits[#bits + 1] = (L["%s at this level"]):format(A.Fmt.Span(pace.atLevel)) end
	header.line:SetText(table.concat(bits, "  ·  "))
	Kit().Tooltip(header.xpHit, L["Experience"], header.xpTip)
	HeaderActions(frame)
end

---------------------------------------------------------------------------
-- What goes on the page
---------------------------------------------------------------------------
-- Up to `count` cards after the first, one per kind where there are enough.
local function AlsoGood(cards, count)
	local out, kinds, used = {}, {}, {}
	if cards[1] then kinds[cards[1].kind] = true end
	for index = 2, #cards do
		local card = cards[index]
		if #out >= count then break end
		if not kinds[card.kind] then
			kinds[card.kind] = true
			used[index] = true
			out[#out + 1] = card
		end
	end
	for index = 2, #cards do
		if #out >= count then break end
		if not used[index] then out[#out + 1] = cards[index] end
	end
	table.sort(out, function(a, b) return (a.score or 0) > (b.score or 0) end)
	return out
end
A.TodayAlsoGood = AlsoGood

local function Action(card, key)
	for _, action in ipairs(card.actions or {}) do
		if action.key == key then return action end
	end
end

local function Attunements()
	local AT = E.Attunements
	if not (AT and AT.Running and AT:Running() and AT.Summary) then return {} end
	local list = {}
	-- Only the ones in reach: an attunement that starts far above your
	-- level is not under way yet, whatever an early step says.
	local level = Num(UnitLevel("player")) or 1
	local window = tonumber(LG.db and LG.db.levelWindow) or 3
	for _, item in ipairs(Safe(AT.Summary, AT) or {}) do
		local entry = Safe(AT.Get, AT, item.key)
		local minLevel = type(entry) == "table" and tonumber(entry.minLevel) or nil
		local reach = not minLevel or level >= minLevel - window
		if reach and item.state ~= "done" and (item.done or 0) > 0 and (item.total or 0) > 0 then list[#list + 1] = item end
	end
	table.sort(list, function(a, b)
		if (a.percent or 0) ~= (b.percent or 0) then return (a.percent or 0) > (b.percent or 0) end
		return tostring(a.name) < tostring(b.name)
	end)
	return list
end

-- Mail that runs out within a few days (the Characters record).
local function MailRunningOut(now)
	local C = E.Characters
	local record = C and C.Get and Safe(C.Get, C, E.charKey)
	local meta = type(record) == "table" and type(record.mailMeta) == "table" and record.mailMeta or {}
	local count, soonest = 0, nil
	for _, entry in ipairs(meta) do
		local expires = type(entry) == "table" and tonumber(entry.expires)
		local worth = type(entry) == "table" and ((tonumber(entry.items) or 0) > 0 or (tonumber(entry.money) or 0) > 0)
		if expires and worth and expires > now and expires - now <= MAIL_DAYS * 86400 then
			count = count + 1
			if not soonest or expires < soonest then soonest = expires end
		end
	end
	return count, soonest
end
A.TodayMail = MailRunningOut

local function TrainerSpells()
	local TR = E.Training
	if not (TR and TR.active and type(TR.Totals) == "function") then return nil end
	local totals = Safe(TR.Totals, TR)
	return type(totals) == "table" and tonumber(totals.count) or nil
end

local function FirstLine(text)
	text = Text(text) or ""
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h%[?(.-)%]?|h", "%1")
	text = text:match("^[^\n]*") or text
	return text
end

-- Rows for "Waiting for you": { { icon, title, sub, onClick, link, progress } }
local function Waiting(frame, cards)
	local rows = {}
	local owner = frame
	local nx = NX()
	-- Quests to hand in (the engine's turn-in cards, by place).
	for _, card in ipairs(cards) do
		if card.kind == "turnin" then
			local map = Action(card, "map")
			rows[#rows + 1] = { icon = nx.Icon(card), title = card.title, sub = card.subtitle,
				onClick = function() J:NextAct(card, "open") end, tip = card.reasons and card.reasons[2],
				link = map and { L["Map"], function() nx.Run(card, map, owner) end, nx.ACTION_TIP.map } or nil }
		end
	end
	-- Attunements under way.
	local AT = E.Attunements
	for index, item in ipairs(Attunements()) do
		if index > 2 then break end
		local nextTitle = item.next and AT.StepTitle and Safe(AT.StepTitle, AT, item.next)
		rows[#rows + 1] = { icon = (J.ICON or {}).attune, title = item.name,
			sub = nextTitle and (L["Next: %s"]):format(nextTitle) or E:Plural(item.total, "%d of %d step done", "%d of %d steps done"):format(item.done, item.total),
			progress = { item.done, item.total }, right = ("%d / %d"):format(item.done, item.total),
			onClick = function() AT:Open(item.key) end }
	end
	-- Goals, the closest to done first.
	local G = A.Goals
	if G and G.List then
		local active = G:List()
		local list = {}
		for _, goal in ipairs(active or {}) do
			local have, need, hint, track = G:Progress(goal)
			list[#list + 1] = { goal = goal, have = have, need = need, hint = hint, track = track, frac = need > 0 and have / need or 0 }
		end
		table.sort(list, function(a, b)
			if a.frac ~= b.frac then return a.frac > b.frac end
			return (a.goal.id or 0) < (b.goal.id or 0)
		end)
		for index, entry in ipairs(list) do
			if index > 3 then break end
			local goal = entry.goal
			rows[#rows + 1] = { icon = G:Icon(goal), title = G:Label(goal), sub = entry.hint,
				progress = goal.kind ~= "todo" and { entry.have, entry.need } or nil,
				right = goal.kind ~= "todo" and (entry.track or ("%s / %s"):format(BreakUpLargeNumbers(entry.have), BreakUpLargeNumbers(entry.need))) or nil,
				onClick = function() A:OpenSection("goals", goal.id) end }
		end
		if #list > 3 then
			rows[#rows + 1] = { icon = false, title = E:Plural(#list - 3, "%d more goal", "%d more goals"):format(#list - 3),
				sub = L["All of them on the Goals page."], onClick = function() A:OpenSection("goals") end }
		end
	end
	-- Reminders that wait for their moment.
	local N = A.Notes
	if N and N.Waiting then
		local waiting = Safe(N.Waiting, N) or {}
		for index, note in ipairs(waiting) do
			if index > 3 then break end
			rows[#rows + 1] = { icon = (J.ICON or {}).note, title = FirstLine(note.text),
				sub = N.TriggerLabel and Safe(N.TriggerLabel, N, note.trigger, note.repeats) or L["A reminder"],
				onClick = function() A:OpenSection("notes", J:Address("note", note.id)) end }
		end
	end
	-- Before a dungeon trip further down the list: what is missing.
	local prep = PrepRow(cards)
	if prep then rows[#rows + 1] = prep end
	-- Trainer spells (the Training module's count).
	local spells = TrainerSpells()
	if spells and spells > 0 then
		rows[#rows + 1] = { icon = (J.ICON or {}).spell, title = E:Plural(spells, "%d spell at your trainer", "%d spells at your trainer"):format(spells),
			sub = L["You can learn them now."] }
	end
	-- Mail that runs out.
	local mail, soonest = MailRunningOut(time())
	if mail > 0 then
		rows[#rows + 1] = { icon = "Interface/Icons/INV_Letter_15", title = E:Plural(mail, "%d letter runs out soon", "%d letters run out soon"):format(mail),
			sub = (L["The first one on %s. Take its items or money from a mailbox."]):format(A.Fmt.Day(soonest)) }
	end
	return rows
end
A.TodayWaiting = Waiting

-- The last moments, keepsakes first.
local function Lately(count)
	local rows = Safe(J.Timeline, J) or {}
	local keep, rest = {}, {}
	local looked = 0
	for index = #rows, 1, -1 do
		local row = rows[index]
		looked = looked + 1
		if looked > 40 then break end
		if J:IsKeepsake(row) then keep[#keep + 1] = row else rest[#rest + 1] = row end
	end
	local out = {}
	for _, row in ipairs(keep) do
		if #out >= count then break end
		out[#out + 1] = row
	end
	for _, row in ipairs(rest) do
		if #out >= count then break end
		out[#out + 1] = row
	end
	return out, #rows
end
A.TodayLately = Lately

-- Keepsakes written down this session (Moments.lua "Keepsake"): New in Lately.
local fresh = {}
A.TodayFresh = fresh

-- A fresh journal: no welcome yet and only a few moments of its own.
local function Welcome(frame)
	local ui = UIState()
	local rec = J:Char()
	if not (ui and rec) then return false end
	if frame.forceWelcome then return true end
	if ui.todayWelcomed then return false end
	return #(J:Rows() or {}) <= 5
end

-- "A", "A and B", "A, B, and C" (US serial comma).
local function ListText(names)
	if #names <= 1 then return names[1] or "" end
	if #names == 2 then return (L["%s and %s"]):format(names[1], names[2]) end
	return (L["%s, and %s"]):format(table.concat(names, ", ", 1, #names - 1), names[#names])
end

-- The welcome text: what EldoUI already knew, and from which records.
local function WelcomeText(atMax)
	local rows = Safe(J.Timeline, J) or {}
	local known, names, seen = 0, {}, {}
	for _, row in ipairs(rows) do
		if row.src and row.src ~= "journal" then
			known = known + 1
			local source = J.Source and Safe(J.Source, J, row.src)
			local title = type(source) == "table" and Text(source.title) or nil
			if title and not seen[title] then
				seen[title] = true
				names[#names + 1] = title
			end
		end
	end
	local from = atMax and L["From now on, runs, first kills, finds, and standings are written down as they happen."]
		or L["From now on, levels, places, first kills, and finds are written down as they happen."]
	if known == 0 then
		return from .. " " .. L["This page shows where to go next and what is waiting for you."], 0
	end
	local knew
	if names[1] then
		knew = E:Plural(known, "EldoUI already knew %d moment of yours from %s: it is on your Journey.",
			"EldoUI already knew %d moments of yours from %s: they are on your Journey."):format(known, ListText(names))
	else
		knew = E:Plural(known, "EldoUI already knew %d moment of yours from its other records: it is on your Journey.",
			"EldoUI already knew %d moments of yours from its other records: they are on your Journey."):format(known)
	end
	return knew .. " " .. from, known
end
A.TodayWelcomeText = WelcomeText

-- "Where you left off": the last session and the break since. nil while
-- the break is shorter than the setting, or once it was put away for this
-- login.
local function ResumeData(frame)
	local force = frame and frame.forceResume
	local after = tonumber(A.db and A.db.resumeAfter) or 0
	local rec = J:Char()
	if not rec or (after <= 0 and not force) then return nil end
	local sessions = type(rec.sessions) == "table" and rec.sessions or {}
	local last = sessions[#sessions]
	local logout = type(last) == "table" and tonumber(last.logout) or nil
	local R = A.Record
	local login = R and type(R.state) == "table" and tonumber(R.state.login) or nil
	if not (logout and login) or login < logout then return nil end
	local away = login - logout
	if not force then
		if away < after then return nil end
		local ui = UIState()
		if ui and ui.resumeDone == login then return nil end
	end
	local data = { login = login, logout = logout, away = away, level = tonumber(last.level), moments = {} }
	data.recap = type(A.SessionRecap) == "function" and Safe(A.SessionRecap, A, "last") or nil
	-- The last moments before you left (newest first), where you were, and
	-- the rested time the journal wrote down when you came back.
	local rows = Safe(J.Timeline, J) or {}
	for index = #rows, 1, -1 do
		local row = rows[index]
		local t = tonumber(row.t)
		if t and t <= logout then
			if not data.zone then data.zone = Text(row.zone) end
			if #data.moments < RESUME_MOMENTS then data.moments[#data.moments + 1] = row end
			if #data.moments >= RESUME_MOMENTS and data.zone then break end
		elseif t and t >= login and row.kind == "rested" and tonumber(row.pct) then
			data.rested = tonumber(row.pct)
		end
	end
	return data
end
A.TodayResume = ResumeData

local function AwayText(seconds)
	local fmt = A.Pace and A.Pace.FormatDuration
	return (fmt and fmt(seconds)) or A.Fmt.Span(seconds)
end

local function ResumeText(data)
	local lines = {}
	local away = AwayText(data.away)
	if data.zone and data.level then
		lines[1] = (L["You were away %s. You left off in %s at level %d."]):format(away, data.zone, data.level)
	elseif data.zone then
		lines[1] = (L["You were away %s. You left off in %s."]):format(away, data.zone)
	else
		lines[1] = (L["You were away %s."]):format(away)
	end
	if data.recap and data.recap.line then
		lines[#lines + 1] = (L["Last time: %s."]):format(data.recap.line)
		if data.recap.best then lines[#lines + 1] = (L["Best moment: %s"]):format(data.recap.best) end
	end
	if data.rested and data.rested > 0 then
		lines[#lines + 1] = (L["Rested while you were away: %d%% of a level."]):format(data.rested)
	end
	return table.concat(lines, "\n")
end
A.TodayResumeText = ResumeText

-- A dungeon trip lower on the list than the top card (the top card shows
-- its own "Packed?" list), and what its prep checklist finds missing.
-- Nothing is bought or used.
PrepRow = function(cards)
	if not (A.db and A.db.prepChecklist) or type(J.PrepChecklist) ~= "function" then return nil end
	local trip
	for index = 2, math.min(#cards, ALSO + 1) do
		if cards[index].kind == "dungeon" then
			trip = cards[index]
			break
		end
	end
	if not trip then return nil end
	local missing = {}
	for _, item in ipairs(Safe(J.PrepChecklist, J) or {}) do
		if type(item) == "table" and not item.ok and Text(item.text) then missing[#missing + 1] = item.text end
	end
	if #missing == 0 then return nil end
	return { icon = (J.ICON or {}).dungeon or "Interface\\Icons\\INV_Misc_Key_03",
		title = E:Plural(#missing, "Before %s: %d thing to sort", "Before %s: %d things to sort"):format(trip.title or L["the dungeon"], #missing),
		sub = table.concat(missing, " "),
		onClick = function() A:OpenSection("next", { card = trip.id }) end, card = trip, prep = missing }
end
A.TodayPrepRow = PrepRow

---------------------------------------------------------------------------
-- Milestones: "what is ahead" tiles
---------------------------------------------------------------------------
local TILE_W = 150

local function MilestoneBlock(child)
	local block = CreateFrame("Frame", nil, child)
	block.tiles = {}
	return block
end

local function Tile(block, index)
	local tile = block.tiles[index]
	if tile then return tile end
	tile = CreateFrame("Frame", nil, block)
	tile.box = K.Card(tile, { solid = true })
	tile.box:SetAllPoints()
	tile.box:SetFrameLevel(math.max(tile:GetFrameLevel() - 1, 0))
	tile.badge = K.LevelBadge(tile, 32)
	tile.badge:SetPoint("LEFT", 8, 0)
	tile.label = K.Text(tile, K.size.small, "LEFT", "body")
	tile.label:SetPoint("TOPLEFT", 48, -8)
	tile.label:SetPoint("TOPRIGHT", -8, -8)
	tile.label:SetWordWrap(true)
	tile.label:SetMaxLines(2)
	tile.eta = K.Text(tile, K.size.caption, "LEFT", "secondary")
	tile.eta:SetPoint("BOTTOMLEFT", 48, 8)
	tile.eta:SetPoint("BOTTOMRIGHT", -8, 8)
	tile.eta:SetWordWrap(false)
	tile:EnableMouse(true)
	block.tiles[index] = tile
	return tile
end

local function DrawMilestones(flow, list)
	local block = flow:Take("today-milestones", MilestoneBlock)
	local width = flow:Width()
	local columns = math.max(1, math.min(#list, math.floor((width + 8) / (TILE_W + 8))))
	local tileW = math.floor((width - (columns - 1) * 8) / columns)
	local rowsNeeded = math.ceil(#list / columns)
	for index, item in ipairs(list) do
		local tile = Tile(block, index)
		local col, row = (index - 1) % columns, math.floor((index - 1) / columns)
		tile:ClearAllPoints()
		tile:SetPoint("TOPLEFT", block, "TOPLEFT", col * (tileW + 8), -row * 56)
		tile:SetSize(tileW, 48)
		tile.badge:SetLevel(item.level, false)
		tile.label:SetText(item.label or "")
		local levels = E:Plural(item.levels, "%d level away", "%d levels away"):format(item.levels)
		local fmt = A.Pace and A.Pace.FormatDuration
		local eta = item.eta and fmt and fmt(item.eta)
		tile.eta:SetText(eta and ("%s  ·  ~%s"):format(levels, eta) or levels)
		local tip
		if item.kind == "max" and J.CapText then
			tip = J:CapText()
		elseif item.xp then
			tip = eta and (L["%s XP to go: about %s of play at your pace."]):format(E:FormatNumber(item.xp), eta)
				or (L["%s XP to go."]):format(E:FormatNumber(item.xp))
		end
		if item.xp and tip then
			tip = tip .. "\n" .. (eta and L["Rested XP and finished quests count as a head start."]
				or L["A time shows once you have a few levels or some play this session behind you."])
		end
		Kit().Tooltip(tile, item.label, tip or eta and (L["About %s of play at your recent pace. It counts your own last levels only."]):format(eta)
			or item.far and L["More than 5 levels away. Later levels take longer than your recent ones, so no time is shown."]
			or L["Your own level times show here once you have a few levels behind you."])
		tile:Show()
	end
	for index = #list + 1, #block.tiles do block.tiles[index]:Hide() end
	flow:Place(block, rowsNeeded * 56 - 8, 0, 10)
	return block
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local function Build(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints()
	frame.header = BuildHeader(frame)
	frame.header:SetPoint("TOPLEFT")
	frame.header:SetPoint("TOPRIGHT")
	frame.flow = PageKit().Flow(frame)
	frame.flow:SetPoint("TOPLEFT", 0, -(HEADER + 8))
	frame.flow:SetPoint("BOTTOMRIGHT")
	-- Redraw when the width changed (a draw that resizes nothing never loops).
	frame.flow.onResize = function(flow)
		if frame:IsVisible() and math.floor(flow:Width()) ~= frame.drawnWidth then frame:Draw(true) end
	end

	local function Redraw() frame:Draw(true) end

	function frame:Draw(keepScroll)
		if not self:IsShown() then
			self.dirty = true
			return
		end
		self.dirty = false
		self.drawnWidth = math.floor(self.flow:Width())
		local nx = NX()
		DrawHeader(self)
		local flow = self.flow
		flow:Begin()
		self.blocks = {}
		local width = flow:Width()
		local result = nx and J:Next(nx.Opts()) or { cards = {} }
		self.result = result
		local cards = result.cards or {}
		local pace = Safe(J.Pace, J) or {}
		local level = pace.level or 1

		-- A fresh journal: welcome, what EldoUI already knew, the tour.
		local welcomed = Welcome(self)
		if welcomed then
			local text, known = WelcomeText(pace.atMax)
			local buttons = {}
			if LG.StartJournalTour then
				buttons[#buttons + 1] = { L["Take the tour"], function() LG:StartJournalTour() end, L["A short tour of My Adventure."] }
			end
			if known > 0 and A:SectionShown("journey") then
				buttons[#buttons + 1] = { L["Open the Journey"], function() A:OpenSection("journey") end, L["Your whole story, chapter by chapter."] }
			end
			buttons[#buttons + 1] = { L["Got it"], function()
				local ui = UIState()
				if ui then ui.todayWelcomed = true end
				self.forceWelcome = nil
				self:Draw(true)
				E.UIKit.Toast(self, L["Welcome card put away."], { action = { L["Undo"], function()
					local state = UIState()
					if state then state.todayWelcomed = nil end
					self.forceWelcome = true
					self:Draw(true)
				end } })
			end, L["Puts this card away."] }
			self.blocks.welcome = nx.Note(flow, L["Your journal starts today"], text, buttons, A.HUB_ICON)
		end

		-- Back after a break: where you left off (never with the welcome).
		local resume = not welcomed and ResumeData(self) or nil
		self.resume = resume
		if resume then
			local buttons = {}
			if A:SectionShown("journey") then
				local day = A.Fmt.DayKey(resume.logout)
				buttons[#buttons + 1] = { L["Open that day"], function() A:OpenSection("journey", { view = "day", day = day }) end,
					L["The Journey's day view on the day you last played."] }
			end
			buttons[#buttons + 1] = { L["Got it"], function()
				local ui = UIState()
				if ui then ui.resumeDone = resume.login end
				self.forceResume = nil
				self:Draw(true)
				E.UIKit.Toast(self, L["Put away until your next break."], { action = { L["Undo"], function()
					local state = UIState()
					if state and state.resumeDone == resume.login then state.resumeDone = nil end
					self:Draw(true)
				end } })
			end, L["Puts this card away until your next break."] }
			self.blocks.resume = nx.Note(flow, L["Where you left off"], ResumeText(resume), buttons, RESUME_ICON)
			for _, row in ipairs(resume.moments) do
				local title, sub, icon = A:LineText(row)
				nx.Row(flow, { icon = icon or A.HUB_ICON, title = title, sub = sub, right = A.Fmt.When(row.t), indent = 12,
					titleRole = J:IsKeepsake(row) and "head" or nil, onClick = function() self:OpenRow(row) end })
			end
			flow:Space(4)
		end

		-- The next trip.
		local top = cards[1]
		local blankTrip = false
		self.blocks.tripCaption = nx.Caption(flow, L["Next trip"], (L["for level %d"]):format(level))
		if top then
			local block = flow:Take("ak-card", nx.Card)
			local height = block:Set(top, { width = width, plan = true, owner = self, redraw = Redraw })
			flow:Place(block, height, 0, 10)
			self.blocks.trip = block
		elseif pace.atMax then
			self.blocks.trip = nx.Note(flow, L["Every level is behind you"],
				L["What is left are raids, attunements, and reputation. Next trips shows them once you turn on raids, and the Attunements page has every key."],
				A:SectionShown("next") and { { L["Next trips"], function() A:OpenSection("next") end } } or nil, A.HUB_ICON)
		elseif level <= 1 then
			blankTrip = true
			self.blocks.trip = nx.Note(flow, L["The first page is still blank"],
				L["Go and explore. Look for the people with a yellow mark over their heads near where you started: they have your first quests."],
				nil, A.HUB_ICON)
		elseif result.data == "none" and not LG:HasData() then
			self.blocks.trip = nx.Note(flow, L["No suggestions yet"],
				L["The guide needs the loot data (the EldoUI_LootData addon) or the game's dungeon finder list to suggest trips."], nil, A.HUB_ICON)
		else
			self.blocks.trip = nx.Note(flow, L["Nothing to suggest right now"],
				L["No dungeon, quest, or attunement step fits your level and group at the moment."],
				A:SectionShown("next") and { { L["Next trips"], function() A:OpenSection("next") end } } or nil, A.HUB_ICON)
		end

		-- Also good.
		local also = AlsoGood(cards, ALSO)
		if also[1] then
			nx.Caption(flow, L["Also good"], #cards > 1 and E:Plural(#cards - 1, "%d more idea", "%d more ideas"):format(#cards - 1) or nil)
			for _, card in ipairs(also) do
				local map = Action(card, "map")
				nx.Row(flow, { icon = nx.Icon(card), title = card.title, sub = card.reasons and card.reasons[1] or card.subtitle,
					right = nx.KindName(card.kind), onClick = function() A:OpenSection("next", { card = card.id }) end,
					tipTitle = card.title, tip = card.subtitle,
					link = map and { map.label or L["Map"], function() nx.Run(card, map, self) end, nx.ACTION_TIP.map } or nil })
			end
			if A:SectionShown("next") and #cards > ALSO + 1 then
				nx.Row(flow, { icon = false, title = E:Plural(#cards, "All %d idea", "All %d ideas"):format(#cards), sub = L["Filters for dungeons, quests, attunements, and zones."],
					onClick = function() A:OpenSection("next") end })
			end
		end

		-- Waiting for you.
		local waiting = Waiting(self, cards)
		self.blocks.waiting = nx.Caption(flow, L["Waiting for you"], #waiting > 0 and tostring(#waiting) or nil)
		self.waitingRows = waiting
		if waiting[1] then
			for _, item in ipairs(waiting) do nx.Row(flow, item) end
		else
			local buttons
			if A:SectionShown("goals") then buttons = { { L["New goal"], function() A:OpenSection("goals", "new") end, L["Something to work towards."] } } end
			nx.Note(flow, L["Nothing is waiting"], L["No quest is ready to hand in, and your goals and reminders are quiet."], buttons, (J.ICON or {}).goal)
		end

		-- This session: the same recap as Story so far and the login card.
		local recap = not welcomed and type(A.SessionRecap) == "function" and Safe(A.SessionRecap, A, "current") or nil
		self.sessionRecap = recap
		if recap and recap.line then
			self.blocks.session = nx.Caption(flow, L["This session"], nil)
			local journey = A:SectionShown("journey")
			nx.Row(flow, { icon = SESSION_ICON, title = recap.line,
				sub = recap.best and (L["Best moment: %s"]):format(recap.best) or L["What the journal wrote down since you last logged out."],
				onClick = journey and function() A:OpenSection("journey", { view = "day", day = A.Fmt.DayKey(time()) }) end or nil })
		end

		-- Lately.
		local lately, total = Lately(LATELY)
		self.latelyRows = lately
		nx.Caption(flow, L["Lately"], total > 0 and E:Plural(total, "%d moment in your journal", "%d moments in your journal"):format(total) or nil)
		if lately[1] then
			for _, row in ipairs(lately) do
				local title, sub, icon = A:LineText(row)
				local new = row.src == "journal" and row.seq and fresh[row.seq]
				nx.Row(flow, { icon = icon or A.HUB_ICON, title = title, sub = sub, right = new and L["New"] or A.Fmt.When(row.t),
					titleRole = J:IsKeepsake(row) and "head" or nil, onClick = function() self:OpenRow(row) end })
			end
			if A:SectionShown("journey") then
				nx.Row(flow, { icon = false, title = L["Open the Journey"], sub = L["Your whole story, chapter by chapter."],
					onClick = function() A:OpenSection("journey") end })
			end
		elseif pace.atMax then
			nx.Note(flow, L["The first page is still blank"],
				L["Runs, first kills, finds, and standings are written here as they happen."], nil, (J.ICON or {}).scroll)
		else
			-- At level 1 the trip note above already says the page is blank.
			nx.Note(flow, blankTrip and L["Nothing written down yet"] or L["The first page is still blank"],
				L["Go and explore. Levels, places, first kills, and finds are written here as they happen."], nil, (J.ICON or {}).scroll)
		end

		-- What is ahead.
		local milestones = Safe(J.Milestones, J, 4) or {}
		self.milestones = milestones
		if milestones[1] then
			nx.Caption(flow, L["What is ahead"], pace.median and L["at your recent pace"] or nil)
			self.blocks.milestones = DrawMilestones(flow, milestones)
		end
		flow:Finish(keepScroll)
		if LG.MaybeJournalTour then LG:MaybeJournalTour() end
	end

	-- A row opens its moment on the Journey, else what it is about.
	function frame:OpenRow(row)
		if row.src == "journal" and row.seq and A:SectionShown("journey") then
			return A:OpenSection("journey", { seq = row.seq })
		elseif A.OpenRow then
			return A:OpenRow(row)
		end
	end

	-- A new keepsake shows in Lately at once.
	if J.RegisterCallback then
		J.RegisterCallback(frame, "Keepsake", function(_, row)
			if type(row) ~= "table" or not row.seq then return end
			fresh[row.seq] = true
			frame.dirty = true
			if frame:IsVisible() then frame:Draw(true) end
		end)
	end

	frame:SetScript("OnShow", function(self) if self.dirty then self:Draw(true) end end)
	return frame
end

local function Show(frame, arg)
	if type(arg) == "table" and arg.welcome then frame.forceWelcome = true end
	if type(arg) == "table" and arg.resume then frame.forceResume = true end
	frame:Draw(arg == nil)
end

local function Refresh(frame, changed)
	if changed.adventure or changed.quests or changed.attune or changed.data or changed.settings or changed.player
		or changed.rank or changed.journey or changed.gear then
		frame:Draw(true)
	end
end

A:RegisterSection(KEY, {
	title = "Today",
	icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
	desc = "Where to go next, what is waiting for you, and what just happened.",
	words = { "today", "home", "landing" },
	build = Build,
	show = Show,
	refresh = Refresh,
})

-- The resume card's row on the options page (Where next tab). Options.lua
-- loads after this file, so the row joins at init.
local optionsAdded = false
A:AddPart("todayOptions", { order = 90, init = function()
	if optionsAdded or type(A.AddOptionRows) ~= "function" then return end
	optionsAdded = true
	A:AddOptionRows("next", {
		{ type = "select", key = "resumeAfter", label = L["Where you left off"],
			values = { [0] = L["Never"], [3600] = L["After an hour away"], [14400] = L["After 4 hours away"],
				[43200] = L["After 12 hours away"], [86400] = L["After a day away"] },
			order = { 0, 3600, 14400, 43200, 86400 },
			desc = L["After a break, Today starts with a card about your last session: where you were, your level, and its best moment. Never: no card."] },
	})
end })
