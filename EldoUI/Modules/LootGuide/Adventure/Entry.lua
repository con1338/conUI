-- EldoUI My Adventure: the ways into the journal from the game's own UI.
--
-- Every entry opens My Adventure in the Journal window, or the quick note
-- card, and nothing else: the journal never acts in the game.
--
--   Addon compartment   the Loot Guide's entry reads "Journal" while the
--                       journal runs (LG:SetCompartmentOwner): left-click
--                       My Adventure, right-click a quick note, Shift-click
--                       Next trips, Ctrl-click "Report new content" when
--                       there is some; the tooltip is the summary below
--   Info Bar datatext   "Journal" ("Journal · 3 to hand in"), same clicks
--   Menu datatext       a "Journal" line (Modules/MicroMenu.lua); Blizzard's
--                       micro buttons are never touched
--   Game menu (Esc)     EldoUI_GameMenuJournalButton under EldoUI's button
--                       (Modules/SystemUI.lua, "Journal button in the game
--                       menu", on by default)
--   Settings (Esc >     "My Adventure" quick button on EldoUI's page
--   Options > AddOns)   (Core/Options.lua)
--   Minimap button      EldoUI_JournalMinimapButton, off by default
--                       ("Minimap button"); the Minimap module's bin
--                       gathers it; drag it around the edge
--   Key bindings        Bindings.xml: open or close My Adventure, quick
--                       note, the journal tracker, Next trips
--   Quest menus         right-click a quest in the quest log or the
--                       objective tracker: "Show in your journal", "Set as
--                       a goal", "Write a note about it"
--   Tooltips            Tooltip page sections "My Adventure: finds" (item:
--                       when and where you found it) and "My Adventure:
--                       quests" (quest link: taken, handed in, part of your
--                       next trip); Zone Info's world map hover ("Your
--                       journal"); unit lines are Player Notes'
--   World map           Map Notes pack "journal": your notes where you
--                       wrote them (with "Notes on the world map")
--   Characters          a click on a quest in the Quests tab opens it here
--                       (Modules/Characters/Quests.lua)
--   Slash               /eui adventure [on | off | toggle | <section>],
--                       /eui journey check [from-to | stop], /eui journey
--                       report, /eui journey export [markdown | html | text |
--                       code], /eui journey import [code]; the rest of /eui journey is the hub's
--                       (UI/Hub.lua) and /eui jot is the quick note's
--                       (UI/QuickNote.lua)
--
-- API (E.Adventure.Entry):
--   X:ToggleHub(), X:OpenHub([section]), X:Click(mouseButton)
--   X:Summary()                 the summary rows { { label, value } } and the
--                               click hints { { action, what } }
--   X:FillTooltip(tooltip)      the summary as tooltip lines
--   X:DataText()                the datatext's text
--   X:ItemLine(itemID), X:QuestLines(questID), X:ZoneLines(uiMapID)
--   X:NotePoints(uiMapID)       the map pack's points
--   X:QuestFromMenu(owner)      the quest a quest menu was opened on
--   X:MinimapButton(), X:Apply() (settings changed: buttons and pack)
--   X:StartCheck(arg)           /eui journey check
-- Bindings: A:BindingToggle(), A:BindingNote(), A:BindingTracker(),
-- A:BindingNext() (Core/Bindings.lua).
local _, E = ...
local L = E.L
local A = E.Adventure
local J = E.Journal
local LG = E.LootGuide
local S = A.Store

local Plain = A.Plain

local X = {}
A.Entry = X

local HUB = "adventure"
local ICON = "Interface\\Icons\\INV_Misc_Book_09"
X.ICON = ICON
X.MINIMAP_NAME = "EldoUI_JournalMinimapButton"
X.GAME_MENU_NAME = "EldoUI_GameMenuJournalButton"
X.PACK = "journal"
X.DEFAULT_ANGLE = 200

local function Running()
	return A:Running()
end

local function Db()
	return A.db or A.defaults
end

local function Text(value)
	if type(value) ~= "string" or E:IsSecret(value) or value == "" then return nil end
	return value
end

local function Number(value)
	value = Plain(value)
	return type(value) == "number" and value or nil
end

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end

local function Color(kind)
	return E.tokens.text[kind] or E.tokens.text.body
end

local function Fmt()
	return A.Fmt
end

local function ShortDate(t)
	local fmt = Fmt()
	if fmt and fmt.Short then return fmt.Short(t) end
	return E:ShortDay(t)
end

local function Span(seconds)
	local fmt = Fmt()
	if fmt and fmt.Span then return fmt.Span(seconds) end
	return ("%dm"):format(math.floor((seconds or 0) / 60))
end

local function OffLine()
	return A:OffReason() or L["My Adventure is off."]
end

-- The off line with the command that turns the missing part on.
local function OffHint()
	return A:OffHint() or OffLine()
end

local function SayOff()
	E:Print(OffLine())
end

---------------------------------------------------------------------------
-- Opening
---------------------------------------------------------------------------
function X:OpenHub(section, arg)
	if not Running() then
		SayOff()
		return false
	end
	if section and A:SectionShown(section) then return A:OpenSection(section, arg) end
	LG:Open(HUB)
	return true
end

function X:ToggleHub()
	if not Running() then
		SayOff()
		return false
	end
	if LG:IsOpen() and LG:CurrentPage() == HUB then
		LG:Close()
		return false
	end
	LG:Open(HUB)
	return true
end

function X:Note()
	if not Running() then
		SayOff()
		return false
	end
	local card = A.QuickNote
	if card then card:Toggle() end
	return true
end

function X:Next()
	return self:OpenHub("next")
end

-- What the report would hold (nil while nothing new was seen).
local function HasReport()
	return LG.JourneyReportData and Call(LG.JourneyReportData, LG) ~= nil
end

function X:Report()
	if not (LG.ShowJourneyReport and Running()) then
		SayOff()
		return false
	end
	return LG:ShowJourneyReport()
end

-- Left-click: My Adventure; right-click: quick note; Shift: Next trips;
-- Ctrl: report new content (while there is some).
function X:Click(mouseButton)
	if not Running() then
		SayOff()
		return
	end
	if mouseButton == "RightButton" then
		self:Note()
	elseif IsShiftKeyDown() then
		self:Next()
	elseif IsControlKeyDown() and HasReport() then
		self:Report()
	else
		self:ToggleHub()
	end
end

---------------------------------------------------------------------------
-- The summary (compartment, datatext, minimap button, game menu button)
---------------------------------------------------------------------------
local function ReadyCount()
	local ready = 0
	for _, quest in ipairs(J.OpenQuests and Call(J.OpenQuests, J) or {}) do
		if quest.ready then ready = ready + 1 end
	end
	return ready
end

local function TopNext()
	if not J.NextTop then return nil end
	local card = Call(J.NextTop, J)
	return type(card) == "table" and Text(card.title) or nil
end

-- { rows = { { label, value } }, hints = { { action, what } }, title, off }
function X:Summary()
	local out = { title = L["Journal"], rows = {}, hints = {} }
	if not Running() then
		out.off = OffLine()
		return out
	end
	local rows = out.rows
	local pace = J.Pace and Call(J.Pace, J)
	local level = type(pace) == "table" and pace.level or Number(UnitLevel("player")) or 1
	local levelText = (L["Level %d"]):format(level)
	if type(pace) == "table" and type(pace.atLevel) == "number" and pace.atLevel > 0 then
		levelText = (L["%s, %s at this level"]):format(levelText, Span(pace.atLevel))
	end
	rows[#rows + 1] = { L["You"], levelText }
	if type(pace) == "table" and Text(pace.text) then rows[#rows + 1] = { L["Pace"], pace.text } end
	local trip = TopNext()
	if trip then rows[#rows + 1] = { L["Next trip"], trip } end
	local ready = ReadyCount()
	if ready > 0 then rows[#rows + 1] = { L["Ready to hand in"], tostring(ready) } end
	local G = A.Goals
	local goals = G and Call(G.CountActive, G) or 0
	if goals > 0 then rows[#rows + 1] = { L["Active goals"], tostring(goals) } end
	local N = A.Notes
	local waiting = N and Call(N.Waiting, N)
	local first = type(waiting) == "table" and waiting[1]
	if type(first) == "table" then
		local label = N.TriggerLabel and Call(N.TriggerLabel, N, first.trigger, first.repeats)
		local text = Text(first.text) and first.text:gsub("\n.*", "") or ""
		if E:Utf8Len(text) > 40 then text = E:Utf8Sub(text, 38) .. "..." end
		rows[#rows + 1] = { L["Next reminder"], label and ("%s: %s"):format(label, text) or text }
	end
	local status = LG.JourneyDataStatus and Call(LG.JourneyDataStatus, LG)
	local report = HasReport()
	if report and type(status) == "table" and status.seen > 0 then
		rows[#rows + 1] = { L["New content seen"], tostring(status.seen) }
	end
	local hints = out.hints
	hints[#hints + 1] = { L["Click"], L["open My Adventure"] }
	hints[#hints + 1] = { L["Right-click"], L["write a quick note"] }
	if A:SectionShown("next") then hints[#hints + 1] = { L["Shift-click"], L["open Next trips"] } end
	if report then hints[#hints + 1] = { L["Ctrl-click"], L["report the new content"] } end
	return out
end

function X:FillTooltip(tooltip)
	local summary = self:Summary()
	local white = Color("body")
	local soft = Color("secondary")
	tooltip:AddLine(summary.title, white[1], white[2], white[3])
	if summary.off then
		tooltip:AddLine(summary.off, soft[1], soft[2], soft[3], true)
		return
	end
	for _, row in ipairs(summary.rows) do
		tooltip:AddDoubleLine(row[1], row[2], soft[1], soft[2], soft[3], white[1], white[2], white[3])
	end
	E:TooltipHint(tooltip, unpack(summary.hints))
end

function X:DataText()
	if not Running() then return E:TokenHex(Color("dim")) .. L["Journal"] .. "|r" end
	local hex = E:TokenHex(Color("secondary"))
	local ready = ReadyCount()
	if ready > 0 then return L["Journal"] .. hex .. " · " .. (L["%d to hand in"]):format(ready) .. "|r" end
	local trip = TopNext()
	if trip then return L["Journal"] .. hex .. " · " .. trip .. "|r" end
	return L["Journal"]
end

---------------------------------------------------------------------------
-- Bindings (Core/Bindings.lua)
---------------------------------------------------------------------------
function A:BindingToggle()
	X:ToggleHub()
end

function A:BindingNote()
	X:Note()
end

function A:BindingTracker()
	if not Running() then
		SayOff()
		return
	end
	local tracker = self.Tracker
	if not tracker then return end
	local shown = tracker:Toggle()
	if shown then
		E:Print(L["Journal tracker shown. It appears while it has goals, reminders, or a next step to list."])
	else
		E:Print(L["Journal tracker hidden. The same key shows it again."])
	end
end

function A:BindingNext()
	X:Next()
end

---------------------------------------------------------------------------
-- Slash: /eui adventure (the module word) and the journey check
---------------------------------------------------------------------------
local function Switch(word)
	if word == "on" or word == "enable" then return true end
	if word == "off" or word == "disable" then return false end
	if word == "toggle" then return not A:IsEnabled() end
end

function X:ModuleCommand(msg)
	msg = strtrim(msg or "")
	local word = msg:lower()
	if word == "" then
		E:ToggleConfig("module:Adventure")
		return
	end
	local switch = Switch(word)
	if switch == nil then
		if not Running() then
			E:Print(OffHint())
			return
		end
		-- A section word opens it; anything else lists the words (a search
		-- is /eui journey <text>).
		local key = A.FindSection and A:FindSection(msg)
		if key then
			A:OpenSection(key)
			return
		end
		local words = {}
		for _, def in ipairs(A.Sections and A:Sections() or {}) do
			if not def.link and A:SectionShown(def.key) then words[#words + 1] = def.key end
		end
		E:Print((L["My Adventure has no section called %s. Sections: %s. To search, type %s."]):format(E:Highlight(msg),
			table.concat(words, ", "), E:Highlight("/eui journey <text>")))
		return
	end
	local _, conflict = E:GetModuleConflict(A)
	if switch and conflict then
		E:Print((L["My Adventure stays off while %s is loaded."]):format(conflict))
		return
	end
	E:SetModuleEnabled("Adventure", switch)
	E:Print((switch and L["My Adventure %son|r."] or L["My Adventure %soff|r."]):format(E:TokenHex(Color(switch and "good" or "bad"))))
	-- Switched on but the Loot Guide is off: say so, or "on" reads as a lie.
	if switch and not Running() then E:Print(OffHint()) end
	if E.RefreshConfig then E:RefreshConfig() end
end

E:AddCommand("adventure", "[on | off | toggle | <section>]  My Adventure: switch it, open its settings, or open a section", function(arg)
	X:ModuleCommand(arg)
end, "Tools")

-- After a WoW: Forever patch: does the game still know the data's quests?
-- The result opens in a copy box with the link to the public Journal data
-- report form.
function X:StartCheck(arg)
	arg = strtrim(arg or ""):lower()
	if not LG.JourneyCheck then return false end
	if arg == "stop" then
		if LG:JourneyCheckRunning() then
			LG:JourneyStopCheck()
		else
			E:Print(L["No check is running."])
		end
		return true
	end
	local asked, total = LG:JourneyCheckRunning()
	if asked then
		E:Print((E:Plural(total, "The check is running: %d of %d quest asked. %s stops it.", "The check is running: %d of %d quests asked. %s stops it.")):format(asked, total, E:Highlight("/eui journey check stop")))
		return true
	end
	local from, to = arg:match("^(%d+)%s*%-%s*(%d+)$")
	local opts = { from = tonumber(from), to = tonumber(to) }
	local ok, info = LG:JourneyCheck(opts, function(result)
		local text = LG:JourneyCheckText(result, LG:JourneyZoneCheck())
		X.lastCheckText = text
		E:ShowCopyBox(L["Journal data check"],
			L["Copy this block into a new journal-data issue: %s. Nothing is sent from the game."]:format(LG.JOURNAL_DATA_ISSUE_URL), text)
	end)
	if not ok then
		E:Print(info or L["The check could not start."])
		return false
	end
	E:Print((E:Plural(info, "Checking %d quest with the game, a few each second (never in combat). The result opens in a copy box.",
		"Checking %d quests with the game, a few each second (never in combat). The result opens in a copy box.")):format(info))
	return true
end

-- The hub owns /eui journey (UI/Hub.lua loads after this file). This file
-- adds "check" and "report" to it: the usage below is registered first,
-- and the handler wraps the hub's at init.
local JOURNEY_USAGE = "[section | data | check | report | export | import | text]  open or close My Adventure in the Journal window, on a section or searched; check the journal data after a patch; report new content; export your journal (markdown, html, text or code); import from Forever Journal or a code"
-- Shown translated: L["[section | data | check | report | export | import | text]  open or close My Adventure in the Journal window, on a section or searched; check the journal data after a patch; report new content; export your journal (markdown, html, text or code); import from Forever Journal or a code"]
E:AddCommand("journey", JOURNEY_USAGE, function() end, "Tools")

X.EXPORT_FORMATS = { markdown = true, html = true, text = true, code = true }

function X:JourneyCommand(arg)
	arg = strtrim(arg or "")
	local word, rest = arg:match("^(%S+)%s*(.-)$")
	word = word and word:lower() or ""
	if word == "check" then
		self:StartCheck(rest)
		return
	end
	if word == "report" then
		if Running() then self:Report() else SayOff() end
		return
	end
	if word == "export" then
		if not Running() then return SayOff() end
		local format = rest:lower()
		if format == "" then format = "markdown" end
		if not X.EXPORT_FORMATS[format] then
			E:Print((L["Export formats: %s."]):format("markdown, html, text, code"))
			return
		end
		if A.Export then A.Export:Show(format) end
		return
	end
	if word == "import" then
		if rest:lower() == "code" then
			if not Running() then return SayOff() end
			if A.Backup and A.Backup.AskImportCode then A.Backup:AskImportCode() end
		elseif A.Import then
			-- The import also runs while the module stands back for the other
			-- journal addon.
			A.Import:Ask()
		end
		return
	end
	-- The rest (a section, an address, "data", search text, or nothing) is
	-- the hub's own /eui journey (UI/Hub.lua, A.HubCommand).
	if A.HubCommand then return A.HubCommand(arg) end
	if not Running() then
		E:Print(OffHint())
		return
	end
	if word == "" then
		self:ToggleHub()
	else
		LG:Open(HUB, arg)
	end
end

---------------------------------------------------------------------------
-- Minimap button (off by default)
---------------------------------------------------------------------------
local minimapButton

local function Angle()
	local angle = tonumber(Db().minimapAngle)
	return angle or X.DEFAULT_ANGLE
end

local function OnMinimap(button)
	return Minimap and button:GetParent() == Minimap
end

local function PlaceMinimapButton(button)
	if not (Minimap and OnMinimap(button)) then return end
	local x, y = E:MinimapEdgePoint(Angle(), 2, 5, Minimap)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function DragUpdate(button)
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local mx, my = Minimap:GetCenter()
	if not (cx and mx) then return end
	local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
	A.db.minimapAngle = math.floor(angle % 360 + 0.5)
	PlaceMinimapButton(button)
end

-- The look follows the minimap: EldoUI's square panel on its square map,
-- the round tracking ring of addon buttons otherwise.
local function StyleMinimapButton(button)
	local square = E:MinimapShape() == "SQUARE"
	if button.square == square then return end
	button.square = square
	button.ring:SetShown(not square)
	button.back:SetShown(not square)
	button.icon:ClearAllPoints()
	if square then
		button:SetSize(24, 24)
		E:SetTemplate(button)
		button.icon:SetPoint("TOPLEFT", 2, -2)
		button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
		E:TrimIcon(button.icon)
	else
		button:SetSize(31, 31)
		if button.SetBackdrop then button:SetBackdrop(nil) end
		button.icon:SetSize(20, 20)
		button.icon:SetPoint("TOPLEFT", 7, -6)
		button.icon:SetTexCoord(0, 1, 0, 1)
	end
end

local function BuildMinimapButton()
	if minimapButton or not Minimap then return minimapButton end
	local button = CreateFrame("Button", X.MINIMAP_NAME, Minimap, "BackdropTemplate")
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	button.back = button:CreateTexture(nil, "BACKGROUND")
	button.back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	button.back:SetSize(20, 20)
	button.back:SetPoint("TOPLEFT", 7, -5)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetTexture(ICON)
	button.ring = button:CreateTexture(nil, "OVERLAY")
	button.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	button.ring:SetSize(53, 53)
	button.ring:SetPoint("TOPLEFT")
	button:SetScript("OnClick", function(own, mouse)
		if E:IsOptionsLinkClick(own, mouse) then return end
		X:Click(mouse)
	end)
	button:SetScript("OnEnter", function(own)
		GameTooltip:SetOwner(own, "ANCHOR_LEFT")
		X:FillTooltip(GameTooltip)
		if OnMinimap(own) then
			local soft = Color("secondary")
			GameTooltip:AddLine(L["Drag to move it around the minimap."], soft[1], soft[2], soft[3])
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	E:BindOptionsLink(button, { page = "module:Adventure", key = "minimap" })
	-- The cursor is followed only while you drag.
	button:SetScript("OnDragStart", function(own)
		if not OnMinimap(own) then return end
		own:LockHighlight()
		own:SetScript("OnUpdate", DragUpdate)
	end)
	button:SetScript("OnDragStop", function(own)
		own:SetScript("OnUpdate", nil)
		own:UnlockHighlight()
	end)
	minimapButton = button
	StyleMinimapButton(button)
	PlaceMinimapButton(button)
	return button
end

function X:MinimapButton()
	return minimapButton
end

local function ApplyMinimapButton()
	local wanted = Running() and Db().minimap and true or false
	if not wanted then
		if minimapButton then minimapButton:Hide() end
		return
	end
	local button = BuildMinimapButton()
	if not button then return end
	StyleMinimapButton(button)
	PlaceMinimapButton(button)
	button:Show()
	-- The Minimap module's bin takes addon buttons when it looks for them.
	local mm = E.modules and E.modules.Minimap
	if mm and mm.active and mm.CollectButtons and not InCombatLockdown() then Call(mm.CollectButtons, mm) end
end

---------------------------------------------------------------------------
-- Item and quest tooltips (Tooltip page sections, each with its mode)
---------------------------------------------------------------------------
local LOOT_KINDS = { loot = true, gear = true }
local itemIndex = { rev = false, map = {} }

-- The first time the journal saw an item: the row (found or put on).
local function ItemRow(itemID)
	local rec = J:Char()
	if not (rec and type(rec.events) == "table") then return nil end
	local rev = J:Rev()
	if itemIndex.rev ~= rev and not InCombatLockdown() then
		local map = {}
		for _, packed in ipairs(rec.events) do
			local _, _, kind = S.Head(packed)
			if LOOT_KINDS[kind] then
				local row = S.Unpack(rec, packed)
				local id = row and tonumber(row.item)
				if id and not map[id] then map[id] = row end
			end
		end
		itemIndex.rev, itemIndex.map = rev, map
	end
	return itemIndex.map[itemID]
end

-- "Found Oct 4 in The Deadmines, level 22" or nil.
function X:ItemLine(itemID)
	itemID = Number(itemID)
	if not (itemID and Running()) then return nil end
	local row = ItemRow(itemID)
	if not row then return nil end
	local where = Text(row.zone)
	local when = ShortDate(row.t)
	local level = Number(row.level)
	local text
	if row.kind == "gear" then
		text = where and (L["Put on %s in %s"]):format(when, where) or (L["Put on %s"]):format(when)
	else
		text = where and (L["Found %s in %s"]):format(when, where) or (L["Found %s"]):format(when)
	end
	if level then text = (L["%s, level %d"]):format(text, level) end
	return text
end

local function Where(zone, sub)
	zone, sub = Text(zone), Text(sub)
	if zone and sub and sub ~= zone then return ("%s, %s"):format(sub, zone) end
	return zone or sub
end

local function TripWith(questID)
	local engine = A.Next
	local result = engine and engine.last
	for _, card in ipairs(type(result) == "table" and result.cards or {}) do
		for _, id in ipairs(card.quests or {}) do
			if id == questID then return Text(card.title) end
		end
	end
end

-- Lines for a quest link: { { left, right } }.
function X:QuestLines(questID)
	questID = Number(questID)
	local out = {}
	if not (questID and Running()) then return out end
	local rec = J:Char()
	if not rec then return out end
	local done
	for index = #(rec.quests or {}), 1, -1 do
		local quest = rec.quests[index]
		if type(quest) == "table" and quest.id == questID then
			done = quest
			break
		end
	end
	if done then
		local where = Where(done.z, done.s)
		local text = (L["%s at level %d"]):format(ShortDate(done.t), Number(done.l) or 0)
		if where then text = (L["%s in %s"]):format(text, where) end
		out[#out + 1] = { L["Handed in"], text }
	else
		local start = type(rec.questStart) == "table" and rec.questStart[questID]
		if type(start) == "table" and Number(start.t) then
			local where = Where(start.z, start.s)
			local text = Number(start.l) and (L["%s at level %d"]):format(ShortDate(start.t), start.l) or ShortDate(start.t)
			if where then text = (L["%s in %s"]):format(text, where) end
			out[#out + 1] = { L["Taken"], text }
		end
	end
	local trip = not done and TripWith(questID)
	if trip then out[#out + 1] = { L["Part of your next trip"], trip } end
	return out
end

local sectionsDone = false

local function RegisterTooltipSections()
	if sectionsDone or not E.RegisterTooltipSection then return end
	sectionsDone = true
	E:RegisterTooltipSection("journalItem", { order = 52, title = L["My Adventure: finds"], default = "shift",
		desc = L["On an item: when and where your journal saw you find it or put it on, and at what level."],
		item = function(_, _, itemID, add)
			local line = X:ItemLine(itemID)
			if line then
				local soft, white = Color("secondary"), Color("body")
				add(L["Journal"], line, soft[1], soft[2], soft[3], white[1], white[2], white[3])
			end
		end })
	E:RegisterTooltipSection("journalQuest", { order = 53, title = L["My Adventure: quests"], default = "always",
		desc = L["On a quest link: when you took it or handed it in, at what level and where, and whether it is part of your next trip."],
		quest = function(_, questID, add)
			if not Running() or E:IsSecret(questID) or type(questID) ~= "number" then return end
			local soft, white = Color("secondary"), Color("body")
			for _, line in ipairs(X:QuestLines(questID)) do
				add(line[1], line[2], soft[1], soft[2], soft[3], white[1], white[2], white[3])
			end
		end })
end

---------------------------------------------------------------------------
-- Zone Info: the world map hover
---------------------------------------------------------------------------
local function MapName(uiMapID)
	local info = C_Map and C_Map.GetMapInfo and Call(C_Map.GetMapInfo, uiMapID)
	return type(info) == "table" and Text(info.name) or nil
end

local function ZonePlace(rec, uiMapID)
	local zones = type(rec.zones) == "table" and rec.zones or {}
	for name, place in pairs(zones) do
		if type(place) == "table" and tonumber(place.map) == uiMapID then return name, place end
	end
	local name = MapName(uiMapID)
	if name and type(zones[name]) == "table" then return name, zones[name] end
end

function X:ZoneLines(uiMapID)
	local out = {}
	uiMapID = Number(uiMapID)
	if not (uiMapID and Running()) then return out end
	local rec = J:Char()
	if not rec then return out end
	local soft, white = Color("secondary"), Color("body")
	local function Add(left, right)
		out[#out + 1] = { left = left, right = right, lr = soft[1], lg = soft[2], lb = soft[3], rr = white[1], rg = white[2], rb = white[3] }
	end
	local _, place = ZonePlace(rec, uiMapID)
	if place then
		local first, level = Number(place.first), Number(place.firstLevel)
		if first then
			Add(L["First came here"], level and (L["%s, level %d"]):format(ShortDate(first), level) or ShortDate(first))
		end
		local spent = Number(place.t)
		if spent and spent >= 60 then Add(L["Time here"], Span(spent)) end
		local quests = Number(place.quests)
		if quests and quests > 0 then Add(L["Quests handed in"], tostring(quests)) end
	end
	-- Your runs in the zone's dungeons (with Zone Info's dungeon lines on),
	-- one "Your runs" row each, so a dungeon's own line stays its only one.
	local Z, H = E.ZoneInfo, A.History
	local list = Z and Z.db and Z.db.showInstances and Z.Instances and Call(Z.Instances, Z, uiMapID)
	if type(list) == "table" and list[1] and H and H.Dungeons then
		local byName = {}
		for _, dungeon in ipairs(Call(H.Dungeons) or {}) do byName[dungeon.name] = dungeon end
		for _, inst in ipairs(list) do
			local dungeon = inst.name and byName[inst.name]
			local runs = dungeon and Number(dungeon.runs)
			if runs and runs > 0 then
				local text = E:Plural(runs, "%d run", "%d runs"):format(runs)
				if Number(dungeon.last) then text = (L["%s, last %s"]):format(text, ShortDate(dungeon.last)) end
				Add(L["Your runs"], ("%s: %s"):format(inst.name, text))
			end
		end
	end
	if out[1] then table.insert(out, 1, { left = L["Your journal"], lr = white[1], lg = white[2], lb = white[3] }) end
	return out
end

local function RegisterZoneLines()
	local Z = E.ZoneInfo
	if not (Z and Z.RegisterLines) then return end
	Z:RegisterLines("journal", { order = 50, option = "showJournal", live = Running,
		lines = function(uiMapID) return X:ZoneLines(uiMapID) end })
end

---------------------------------------------------------------------------
-- Map Notes pack: your notes on the world map, where you wrote them
---------------------------------------------------------------------------
local function MapNotes()
	return E.modules and E.modules.MapNotes
end

function X:NotePoints(uiMapID)
	local out = {}
	if not (Running() and Db().mapNotes) then return out end
	local N = A.Notes
	if not N then return out end
	local notes, waiting = N:List()
	for _, list in ipairs({ notes, waiting }) do
		for _, note in ipairs(list) do
			local x, y = Number(note.x), Number(note.y)
			if Number(note.map) == uiMapID and x and y and not note.done then
				local text = Text(note.text) or ""
				local label = text:gsub("\n.*", "")
				if E:Utf8Len(label) > 40 then label = E:Utf8Sub(label, 38) .. "..." end
				out[#out + 1] = { x = x, y = y, label = label ~= "" and label or L["Journal note"], kind = "note",
					note = text ~= label and text or nil, icon = note.trigger and N.ICON_REMINDER or N.ICON }
			end
		end
	end
	return out
end

local packDone = false

local function RegisterPack()
	local MN = MapNotes()
	if not (MN and MN.RegisterPack) or packDone then return end
	packDone = true
	MN:RegisterPack(X.PACK, { title = L["Journal notes"], kind = "note",
		points = function(uiMapID) return X:NotePoints(uiMapID) end })
end

local function UnregisterPack()
	local MN = MapNotes()
	if MN and MN.UnregisterPack and packDone then MN:UnregisterPack(X.PACK) end
	packDone = false
end

local function RefreshPack()
	local MN = MapNotes()
	if MN and MN.RefreshPack and packDone then Call(MN.RefreshPack, MN, X.PACK) end
end

---------------------------------------------------------------------------
-- Quest menus (quest log titles and the objective tracker)
---------------------------------------------------------------------------
-- The quest a menu was opened on: the quest log title button carries
-- questID; the tracker's menu belongs to its container, so the block
-- under the mouse says which quest it is (a block keeps its quest in id).
function X:QuestFromMenu(owner)
	local id = type(owner) == "table" and Number(owner.questID)
	if id then return id end
	local foci = GetMouseFoci and Call(GetMouseFoci)
	for _, region in ipairs(type(foci) == "table" and foci or {}) do
		local frame, depth = region, 0
		while type(frame) == "table" and depth < 5 do
			local questID = Number(frame.questID)
			if questID then return questID end
			if frame.parentModule and Number(frame.id) then return frame.id end
			frame = frame.GetParent and frame:GetParent() or nil
			depth = depth + 1
		end
	end
	return nil
end

local function QuestTitle(questID)
	local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and Call(C_QuestLog.GetTitleForQuestID, questID)
	return Text(title)
end

function X:AddQuestEntries(root, questID)
	if not (Running() and questID and root) then return end
	root:CreateDivider()
	root:CreateTitle(L["Journal"])
	root:CreateButton(L["Show in your journal"], function()
		J:Open(J:Address("quest", questID))
	end)
	if A.Goals then
		root:CreateButton(L["Set as a goal"], function()
			local goal, err = J:AddGoal({ kind = "quest", target = questID, text = QuestTitle(questID) })
			if not goal and err then E:Print(err) end
		end)
	end
	if A.QuickNote then
		root:CreateButton(L["Write a note about it"], function()
			local title = QuestTitle(questID)
			A.QuickNote:Open(title and (title .. ": ") or nil)
		end)
	end
end

local menusDone = false

local function HookQuestMenus()
	if menusDone or not (Menu and Menu.ModifyMenu) then return end
	menusDone = true
	for _, tag in ipairs({ "MENU_QUEST_MAP_LOG_TITLE", "MENU_QUEST_OBJECTIVE_TRACKER" }) do
		Menu.ModifyMenu(tag, function(owner, root)
			if not Running() then return end
			X:AddQuestEntries(root, X:QuestFromMenu(owner))
		end)
	end
end

---------------------------------------------------------------------------
-- Compartment, datatext, menu line, game menu and Settings buttons
---------------------------------------------------------------------------
local COMPARTMENT = {
	active = Running,
	text = function() return L["Journal"] end,
	click = function(mouseButton) X:Click(mouseButton) end,
	tooltip = function(tooltip) X:FillTooltip(tooltip) end,
}

local fixedDone = false

-- Entries that stay registered and show while the journal runs.
local function RegisterFixed()
	if fixedDone then return end
	fixedDone = true
	if E.RegisterDataText then
		E:RegisterDataText("Journal", {
			title = L["Journal"],
			events = { "PLAYER_LEVEL_UP", "QUEST_TURNED_IN" },
			poll = true,
			interval = 10,
			text = function() return X:DataText() end,
			tooltip = function(tooltip) X:FillTooltip(tooltip) end,
			onClick = function(_, mouseButton) X:Click(mouseButton) end,
		})
	end
	if E.RegisterMenuEntry then
		E:RegisterMenuEntry("journal", { order = 20, text = function() return L["Journal"] end, shown = Running,
			func = function() X:ToggleHub() end })
	end
	local SystemUI = E.modules and E.modules.SystemUI
	if SystemUI and SystemUI.RegisterMenuButton then
		SystemUI:RegisterMenuButton("journal", {
			name = X.GAME_MENU_NAME, order = 10,
			text = function() return L["Journal"] end,
			shown = function() return Running() and Db().gameMenu and true or false end,
			tooltip = function(tooltip)
				local white, soft = Color("body"), Color("secondary")
				tooltip:AddLine(L["Journal"], white[1], white[2], white[3])
				E:TooltipHint(tooltip, { L["Click"], L["open My Adventure"] })
				E:TooltipHint(tooltip, { L["Right-click"], L["write a quick note"] })
			end,
			onClick = function(mouseButton)
				if mouseButton == "RightButton" then X:Note() else X:OpenHub() end
			end,
		})
	end
	if E.RegisterSettingsButton then
		E:RegisterSettingsButton("journal", { order = 10, label = L["My Adventure"],
			desc = L["Opens My Adventure in the Journal window."], shown = Running,
			func = function() X:OpenHub() end })
	end
end

-- Settings changed (the Adventure page, a profile switch): the buttons and the pack again.
function X:Apply()
	ApplyMinimapButton()
	RefreshPack()
	if LG.SyncCompartment then LG:SyncCompartment() end
end

---------------------------------------------------------------------------
-- Part
---------------------------------------------------------------------------
A:AddPart("entry", {
	order = 90,
	init = function()
		-- Wrap the hub's /eui journey (it registered after this file loaded).
		E:AddCommand("journey", JOURNEY_USAGE, function(arg) X:JourneyCommand(arg) end, "Tools")
		RegisterFixed()
		-- The page (Options.lua) loads after this file.
		if A.AddOptionRows then
			A:AddOptionRows("tracker", {
				{ type = "header", label = L["Buttons"] },
				{ type = "toggle", key = "minimap", label = L["Minimap button"],
					desc = L["A Journal button on the minimap: left-click opens My Adventure, right-click writes a quick note, drag it to move it around the edge. The Minimap module's button bin gathers it."] },
				{ type = "toggle", key = "gameMenu", label = L["Journal button in the game menu"],
					desc = L["A Journal button under EldoUI's in the Esc menu: click opens My Adventure, right-click writes a quick note."] },
				{ type = "execute", label = L["Key bindings"], width = 200,
					desc = L["Opens EldoUI's keybind mode. My Adventure's keys (open or close it, quick note, the tracker, and Next trips) are also under Options > Keybindings > AddOns > EldoUI."],
					func = function() E:ToggleKeybindMode() end },
			})
			A:AddOptionRows("journal", {
				{ type = "toggle", key = "mapNotes", label = L["Notes on the world map"],
					desc = L["Notes show as pins on the world map and minimap where you wrote them, with the Map Notes switch. Needs the Map Notes module."] },
			})
		end
	end,
	start = function()
		if LG.SetCompartmentOwner then LG:SetCompartmentOwner(COMPARTMENT) end
		RegisterTooltipSections()
		HookQuestMenus()
		RegisterZoneLines()
		RegisterPack()
		if J.RegisterCallback then
			J.RegisterCallback(X, "Redraw", function(_, what)
				if type(what) ~= "table" then return end
				if what.settings or what.all then
					X:Apply()
				elseif what.notes then
					RefreshPack()
				end
			end)
		end
		X:Apply()
	end,
	stop = function()
		if J.UnregisterCallback then
			J.UnregisterCallback(X, "Redraw")
		end
		if LG.SetCompartmentOwner then LG:SetCompartmentOwner(nil) end
		if minimapButton then minimapButton:Hide() end
		UnregisterPack()
	end,
})
