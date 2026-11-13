-- EldoUI My Adventure: the "My Adventure" tab of the Journal window.
--
--   +----------------+-------------------------------------------------+
--   | TODAY          |                                                 |
--   |  Goals      2  |                                                 |
--   |  Notes         |          the open section                       |
--   | STORY          |                                                 |
--   |  Journey       |                                                 |
--   |  Keepsakes     |                                                 |
--   | ATLAS          |                                                 |
--   |  Attunements 1 |                                                 |
--   |  Dungeons    > |                                                 |
--   |----------------|                                                 |
--   | Kept since ... |                                                 |
--   | [Write a note] |                                                 |
--   | Settings       |                                                 |
--   +----------------+-------------------------------------------------+
--
-- The tab is a LG.Kit.SectionHost with a 180 px rail grouped under the
-- three books Today, Story and Atlas. It is the first tab
-- while the journal runs and is gone while it does not (no placeholder).
-- The window footer shows the journal data line (LG:JourneyDataText()).
--
-- Sections: every page of the hub registers itself, from any file and at
-- any time (file load or a part's start):
--
--   A:RegisterSection(key, {
--       title   = L["Goals"],            the rail label (sentence case)
--       icon    = <texture or file ID>,  16 px in the rail
--       desc    = L["..."],              the rail row's tooltip
--       build   = function(parent, host) return frame end,   once, on first open
--       show    = function(frame, arg) end,     each open; arg from a route
--       hide    = function(frame) end,          optional
--       refresh = function(frame, changed) end, Loot Guide bus messages
--                                               (changed.adventure, .attune, ...)
--                                               while the section is open
--       count   = function() return n or "text" end,   gray number in the rail
--       tabCount = true,                 the count also adds to the tab's number
--       hidden  = function() return bool end,          hide the row for now
--       words   = { "goals", "goal" },   /eui journey <word> and /lg <word>
--       search  = function(text) return { { title, sub, icon, arg }, ... } end,
--                                        rows for the window's search box
--       group, order,                    optional: the plan's sections have
--                                        their place already (see PLACES)
--       link    = function(def) end,     a row that opens something else (no page)
--   })
--   A:UnregisterSection(key)
-- A def left in A.hubSections[key] joins too (read when the rail is
-- built), so a file may register before this one loads. The counts of
-- "goals" and "notes" add to the tab's number without tabCount.
--   A:Section(key), A:Sections()         one def / the defs in rail order
--   A:SectionShown(key)                  it has a row in the rail now
--   A:OpenSection(key[, arg])            the window on the hub at that section
--   A:CurrentSection()                   the open section's key (or nil)
--   A:RefreshHub()                       rail counts and texts again
--
-- A section without `build` (and without `link`) has no row: a page that
-- is not built yet never shows. The same registry for other modules:
--   LG:RegisterHubSection(hub, key, def), LG:UnregisterHubSection(hub, key),
--   LG:OpenHubSection(hub, key, arg), LG:HubContent(hub) (the section area),
--   LG:HubRoute(key, arg) (Window.lua: LG:Open on a section key).
-- Attunements uses it: with the journal running it is the Atlas section
-- "attune", otherwise its own tab (Attunements/Core.lua, A:PlaceHome).
--
-- Routes into the tab (LG:Open("adventure", arg)):
--   nil                        the section from "Open on" (first open of the
--                              session), else the one you had open
--   "journey", "goals", ...    a section key or one of its words
--   { section = key, arg = x } a section with its own argument
--   "journal:<kind>:<id>"      an address (E.Journal:Open falls back here)
--   any other text             the Journey, searched for that text
--
-- /eui journey [section | address | data | text] opens or closes the tab.
--
-- Back and forward: every section you open goes on one stack for the
-- session (30 places). The arrows in the rail footer, Alt+Left /
-- Backspace and Alt+Right walk it; a page you go back to opens where you
-- had scrolled it.
--   A:HubBack(), A:HubForward() -> true when it moved
--   A:HubCanGo(step) (-1 back, 1 forward), A:HubHistory() -> list, at
--
-- Keyboard (out of combat only, and only while the pointer is over the
-- Journal window or the focus ring shows; every other key goes on to the
-- game, so movement and action keys are never taken):
--   Up / Down     move the focus ring through the rail (Home / End: first, last)
--   Enter         opens the section with the ring
--   Esc           hides the ring first, then closes the window as usual
--   Alt+Left, Backspace / Alt+Right   back / forward
--   A:HubKey(key) -> handled (the handler; tests), A:HubFocus() -> key
local _, E = ...
local L = E.L
local Key = E.Key
local A = E.Adventure
local J = E.Journal
local LG = E.LootGuide
local K = E.AdventureKit
local T = E.tokens

-- A texture in a text role's color (the footer arrows).
local function Tint(texture, role)
	local c = K.Ink(role)
	texture:SetVertexColor(c[1], c[2], c[3])
end

local HUB = "adventure"
local RAIL_WIDTH = 180
local FOOTER_HEIGHT = 74
local ICON = "Interface\\Icons\\INV_Misc_Book_09"
A.HUB_ICON = ICON

local GROUPS = {
	{ key = "today", title = "Today" },
	{ key = "story", title = "Story" },
	{ key = "atlas", title = "Atlas" },
}
A.HUB_GROUPS = GROUPS

-- Where the plan's sections sit, whichever file registers first.
local PLACES = {
	today = { "today", 10 }, next = { "today", 20 }, goals = { "today", 30 }, notes = { "today", 40 },
	journey = { "story", 10 }, book = { "story", 20 }, keepsakes = { "story", 30 }, places = { "story", 40 },
	quests = { "story", 50 }, fellowship = { "story", 60 }, story = { "story", 70 },
	attune = { "atlas", 10 }, dungeons = { "atlas", 20 }, world = { "atlas", 30 }, reputation = { "atlas", 40 },
}
local GROUP_RANK = { today = 1, story = 2, atlas = 3 }

-- What an address kind opens when no page registered an opener for it.
local ADDRESS_SECTION = {
	moment = "journey", goal = "goals", note = "notes", place = "places", fellow = "fellowship", quest = "quests",
}

---------------------------------------------------------------------------
-- The registry (one per hub; the Loot Guide window has one hub today)
---------------------------------------------------------------------------
local hubs = {}

local function Registry(hub)
	local reg = hubs[hub]
	if not reg then
		reg = { defs = {}, order = {} }
		hubs[hub] = reg
	end
	return reg
end

local function Rank(def)
	return GROUP_RANK[def.group] or 4
end

local function Sort(reg)
	table.sort(reg.order, function(a, b)
		local da, db = reg.defs[a], reg.defs[b]
		if Rank(da) ~= Rank(db) then return Rank(da) < Rank(db) end
		if da.order ~= db.order then return da.order < db.order end
		return a < b
	end)
end

local function Usable(def)
	return type(def) == "table" and (type(def.build) == "function" or type(def.link) == "function")
end

local function Visible(def)
	if not Usable(def) then return false end
	if not def.hidden then return true end
	local ok, hidden = pcall(def.hidden)
	return not (ok and hidden)
end

local Store

-- Sections a file left in A.hubSections[key] (an older way to register,
-- used by files that load before this one or without the hook) join the
-- registry the first time the rail is read.
local function Adopt(hub)
	if hub ~= HUB or type(A.hubSections) ~= "table" then return end
	local reg = Registry(hub)
	for key, def in pairs(A.hubSections) do
		if type(key) == "string" and type(def) == "table" and not reg.defs[key] then Store(hub, key, def) end
	end
end

-- Defs in rail order; only the ones that can show something.
local function Defs(hub)
	Adopt(hub)
	local reg = Registry(hub)
	local list = {}
	for _, key in ipairs(reg.order) do
		local def = reg.defs[key]
		if Usable(def) then list[#list + 1] = def end
	end
	return list
end

local page        -- the SectionHost frame once the tab was opened
local session = { opened = false }

local function Changed(hub)
	if hub ~= HUB or not page then return end
	page:SetSections(Defs(HUB))
	if page:IsVisible() then
		local current = page:Current()
		if not (current and Visible(page:Section(current))) then page:Open(nil) end
	end
end

function Store(hub, key, def)
	local reg = Registry(hub)
	local old = reg.defs[key]
	if old and old ~= def and old.frame then
		if old.frame:IsShown() and old.hide then pcall(old.hide, old.frame) end
		old.frame:Hide()
	end
	def.key = key
	local place = PLACES[key]
	-- A section the plan does not know goes to Atlas, like a plugin page.
	if not GROUP_RANK[def.group or ""] then def.group = place and place[1] or "atlas" end
	def.order = tonumber(def.order) or (place and place[2]) or 50
	if not old then reg.order[#reg.order + 1] = key end
	reg.defs[key] = def
	Sort(reg)
	return def
end

function LG:RegisterHubSection(hub, key, def)
	assert(type(hub) == "string" and type(key) == "string" and type(def) == "table",
		"LootGuide:RegisterHubSection(hub, key, { title, build = function(parent) ... end })")
	Store(hub, key, def)
	Changed(hub)
	return def
end

function LG:UnregisterHubSection(hub, key)
	local reg = hubs[hub]
	local def = reg and reg.defs[key]
	if not def then return end
	if def.frame then
		if def.frame:IsShown() and def.hide then pcall(def.hide, def.frame) end
		def.frame:Hide()
	end
	reg.defs[key] = nil
	if hub == HUB and type(A.hubSections) == "table" and A.hubSections[key] == def then A.hubSections[key] = nil end
	for index, other in ipairs(reg.order) do
		if other == key then
			table.remove(reg.order, index)
			break
		end
	end
	Changed(hub)
end

function LG:HubSection(hub, key)
	Adopt(hub)
	local reg = hubs[hub]
	return reg and reg.defs[key]
end

-- The area sections draw in (nil until the tab was first opened).
function LG:HubContent(hub)
	if hub == HUB and page then return page.content end
end

function LG:OpenHubSection(hub, key, arg)
	if hub ~= HUB then return end
	self:Open(HUB, { section = key, arg = arg })
end

-- LG:Open on a key that is a hub section and no page (Window.lua).
function LG:HubRoute(key, arg)
	if type(key) ~= "string" or not self:GetPage(HUB) then return nil end
	local def = self:HubSection(HUB, key)
	if not (def and Usable(def) and not def.link) then return nil end
	return HUB, { section = key, arg = arg }
end

function A:RegisterSection(key, def)
	return LG:RegisterHubSection(HUB, key, def)
end

function A:UnregisterSection(key)
	LG:UnregisterHubSection(HUB, key)
end

function A:Section(key)
	return LG:HubSection(HUB, key)
end

function A:Sections()
	return Defs(HUB)
end

-- The section has a row in the rail now (built, not hidden).
function A:SectionShown(key)
	return Visible(self:Section(key))
end

function A:OpenSection(key, arg)
	if not self:Running() then return false end
	LG:Open(HUB, { section = key, arg = arg })
	return true
end

function A:CurrentSection()
	if page and page:IsVisible() then return page:Current() end
end

-- The hub frame (tests, tours).
function A:HubFrame()
	return page
end

---------------------------------------------------------------------------
-- Which section opens
---------------------------------------------------------------------------
local function UI()
	local rec = J.Char and J:Char()
	return rec and rec.ui
end

local function Saved()
	local ui = UI()
	return ui and ui.section or session.section
end

local function Remember(key)
	session.section = key
	local ui = UI()
	if ui then ui.section = key end
end

-- "Open on": Today (the landing page once it is built), a section, or
-- the last one you had open.
local function StartSection()
	local want = A.db and A.db.openOn or "today"
	if want == "last" then want = Saved() end
	local def = want and A:Section(want)
	if def and Visible(def) and not def.link then return want end
	return nil
end

-- A section key from a typed word: key, one of its words, or its title.
function A:FindSection(word)
	if type(word) ~= "string" then return nil end
	local folded = E:FoldText(strtrim(word))
	if folded == "" then return nil end
	local defs = Defs(HUB)
	for _, def in ipairs(defs) do
		if Visible(def) and not def.link then
			if def.key == folded or E:FoldText(E:Translate(def.title) or "") == folded or E:FoldText(def.title or "") == folded then return def.key end
			for _, alias in ipairs(type(def.words) == "table" and def.words or {}) do
				if E:FoldText(alias) == folded then return def.key end
			end
		end
	end
	if #folded >= 3 then
		for _, def in ipairs(defs) do
			if Visible(def) and not def.link and E:FoldText(E:Translate(def.title) or ""):sub(1, #folded) == folded then return def.key end
		end
	end
end

---------------------------------------------------------------------------
-- Dates and times for every hub page (A.Fmt): the game's own month and
-- weekday names, the clock as the Info Bar shows it.
--   Fmt.Clock(t) "14:02"   Fmt.Short(t) "Oct 8"   Fmt.Long(t) "October 8"
--   Fmt.Day(t) "Wednesday, October 8"   Fmt.When(t) clock today, else Short
--   Fmt.Span(seconds) "2h 10m"   Fmt.DayKey(t) "2026-10-08"
---------------------------------------------------------------------------
local Fmt = {}
A.Fmt = Fmt

-- Thin names for the shared Core helpers (Core/Dates.lua): the game's
-- month and weekday names and the clock of the General page.
function Fmt.DayKey(t)
	return type(t) == "number" and E:DayKey(t) or ""
end

function Fmt.Clock(t)
	return type(t) == "number" and E:FormatTime(t) or ""
end

function Fmt.Short(t)
	return type(t) == "number" and E:ShortDay(t) or ""
end

function Fmt.Long(t)
	return type(t) == "number" and E:LongDay(t) or ""
end

function Fmt.Day(t)
	return type(t) == "number" and E:LongDay(t, true) or ""
end

function Fmt.When(t)
	return type(t) == "number" and E:When(t) or ""
end

function Fmt.Span(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours, minutes = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
	if hours > 0 then return L["%dh %dm"]:format(hours, minutes) end
	if minutes > 0 then return L["%dm"]:format(minutes) end
	return L["%ds"]:format(seconds)
end

---------------------------------------------------------------------------
-- The rail footer: "Kept since", "Write a note", "Settings"
---------------------------------------------------------------------------
-- The quick note card (Notes files): A.QuickNote:Open().
local function QuickNote()
	local card = A.QuickNote
	if type(card) == "table" and type(card.Open) == "function" then return function() card:Open() end end
	return nil
end
A.HubQuickNote = QuickNote

local UpdateNav   -- the back and forward arrows (below)

local function UpdateFooter(footer)
	if not footer then return end
	if UpdateNav then UpdateNav(footer) end
	local rec = J.Char and J:Char()
	if rec and type(rec.started) == "number" then
		footer.kept:SetText((L["Kept since %s"]):format(Fmt.Long(rec.started)))
	else
		footer.kept:SetText(L["Your journal starts today"])
	end
	-- The quick note card belongs to the Notes files; no card, no button.
	local canNote = QuickNote() ~= nil
	footer.note:SetShown(canNote)
	footer.settings:ClearAllPoints()
	footer.forward:ClearAllPoints()
	-- The arrows share the Settings line, at the footer's right.
	if canNote then
		footer.settings:SetPoint("TOPLEFT", footer.note, "BOTTOMLEFT", 0, -6)
		footer.forward:SetPoint("TOPRIGHT", footer.note, "BOTTOMRIGHT", 0, -6)
	else
		footer.settings:SetPoint("TOPLEFT", footer.kept, "BOTTOMLEFT", 0, -8)
		footer.forward:SetPoint("TOPRIGHT", footer.kept, "BOTTOMRIGHT", 0, -8)
	end
end

local function BuildFooter(footer)
	footer.kept = K.Text(footer, K.size.small, "LEFT", "secondary")
	footer.kept:SetPoint("TOPLEFT", 8, -10)
	footer.kept:SetPoint("TOPRIGHT", -8, -10)
	footer.kept:SetWordWrap(false)
	footer.note = LG.Kit.Button(footer, L["Write a note"], RAIL_WIDTH - 16, T.height.button, function()
		local open = QuickNote()
		if open then open() end
	end, L["Write a note"], L["A note remembers where and when you wrote it. It can remind you later."])
	footer.note:SetPoint("TOPLEFT", footer.kept, "BOTTOMLEFT", 0, -6)
	footer.settings = CreateFrame("Button", nil, footer)
	footer.settings:SetHeight(16)
	footer.settings.text = K.Text(footer.settings, K.size.small, "LEFT", "secondary")
	footer.settings.text:SetPoint("LEFT")
	footer.settings.text:SetText(L["Settings"])
	footer.settings:SetWidth(math.ceil(footer.settings.text:GetStringWidth()) + 4)
	E:PadHitRect(footer.settings, 4)
	footer.settings:SetScript("OnEnter", function(self) K.Paint(self.text, "accent") end)
	footer.settings:SetScript("OnLeave", function(self) K.Paint(self.text, "secondary") end)
	-- EldoUI's settings open only from chat (/eui), so the link says how.
	local function SettingsHint() return L["Type %s in chat for the My Adventure settings."]:format(E:Highlight("/eui adventure")) end
	footer.settings:SetScript("OnClick", function(self)
		E.UIKit.Toast(self:GetParent(), SettingsHint(), { anchor = self, point = "TOP", y = 8 })
	end)
	LG.Kit.Tooltip(footer.settings, L["Settings"], function(tip) E.UIKit.TipText(tip, SettingsHint()) end)
	-- Back and forward, on the Settings line at the right.
	local function Arrow(step, rotation, title, text)
		local button = CreateFrame("Button", nil, footer)
		button:SetSize(16, 16)
		button.icon = button:CreateTexture(nil, "ARTWORK")
		button.icon:SetSize(10, 10)
		button.icon:SetPoint("CENTER")
		button.icon:SetTexture(E.media.chevron)
		button.icon:SetRotation(rotation)
		E:PadHitRect(button, 4)
		button:SetScript("OnEnter", function(self) if self:IsEnabled() then Tint(self.icon, "accent") end end)
		button:SetScript("OnLeave", function(self) Tint(self.icon, self:IsEnabled() and "secondary" or "dim") end)
		button:SetScript("OnClick", function() if step < 0 then A:HubBack() else A:HubForward() end end)
		LG.Kit.Tooltip(button, title, text)
		return button
	end
	footer.forward = Arrow(1, math.pi / 2, L["Forward"], L["The section you came back from. Alt+Right does the same."])
	footer.forward:SetPoint("TOPRIGHT", footer.kept, "BOTTOMRIGHT", 0, -8)
	footer.back = Arrow(-1, -math.pi / 2, L["Back"], L["The section you had open before. Alt+Left or Backspace does the same."])
	footer.back:SetPoint("RIGHT", footer.forward, "LEFT", -6, 0)
	UpdateFooter(footer)
end

---------------------------------------------------------------------------
-- Back and forward (one stack for the session)
---------------------------------------------------------------------------
local HISTORY_MAX = 30
local history = { list = {}, at = 0 }
local walking = false

-- A section page's scroll: its journal list, or its flow of blocks.
local function GetScroll(frame)
	if not frame then return nil end
	local list = frame.list
	if type(list) == "table" and type(list.GetScroll) == "function" then return list:GetScroll() end
	local flow = frame.flow
	if type(flow) == "table" and flow.bar and flow.bar.GetValue then return flow.bar:GetValue() end
	return nil
end

local function SetScroll(frame, value)
	if not (frame and value) then return end
	local list = frame.list
	if type(list) == "table" and type(list.SetScroll) == "function" then
		list:SetScroll(value)
		return
	end
	local flow = frame.flow
	if type(flow) == "table" and flow.bar and flow.bar.SetValue then flow.bar:SetValue(value) end
end

local function KeepScroll()
	local entry = history.list[history.at]
	local def = entry and page and page:Section(entry.key)
	if def and def.frame and def.frame:IsShown() then entry.scroll = GetScroll(def.frame) end
end

local function Visit(key, arg)
	local current = history.list[history.at]
	-- The same section again without an argument is the same place.
	if current and current.key == key and arg == nil then return end
	for index = #history.list, history.at + 1, -1 do history.list[index] = nil end
	history.list[#history.list + 1] = { key = key, arg = arg }
	while #history.list > HISTORY_MAX do table.remove(history.list, 1) end
	history.at = #history.list
end

-- The next place in that direction whose section still shows.
local function Target(step)
	local index = history.at + step
	while history.list[index] do
		local def = page and page:Section(history.list[index].key)
		if def and Visible(def) and not def.link then return index end
		index = index + step
	end
	return nil
end

function A:HubCanGo(step)
	return page ~= nil and Target(step < 0 and -1 or 1) ~= nil
end

function A:HubHistory()
	return history.list, history.at
end

local function Walk(step)
	local index = page and page:IsVisible() and Target(step) or nil
	if not index then return false end
	KeepScroll()
	local entry = history.list[index]
	history.at = index
	walking = true
	local frame = page:Open(entry.key, entry.arg)
	walking = false
	if frame and entry.scroll then SetScroll(frame, entry.scroll) end
	UpdateNav(page.footer)
	return true
end

function A:HubBack() return Walk(-1) end
function A:HubForward() return Walk(1) end

UpdateNav = function(footer)
	if not (footer and footer.back) then return end
	for _, pair in ipairs({ { footer.back, -1 }, { footer.forward, 1 } }) do
		local button, can = pair[1], page ~= nil and Target(pair[2]) ~= nil
		button:SetEnabled(can)
		Tint(button.icon, can and "secondary" or "dim")
	end
end

---------------------------------------------------------------------------
-- Keyboard: a focus ring through the rail (out of combat only)
---------------------------------------------------------------------------
local focus          -- the section key with the ring
local placing = false

local function Ring()
	local ring = page.ring
	if ring then return ring end
	ring = CreateFrame("Frame", nil, page.rail)
	ring:SetFrameLevel(page.rail:GetFrameLevel() + 10)
	ring:EnableMouse(false)
	ring.edges = {}
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h" },
		{ "TOPLEFT", "BOTTOMLEFT", "w" }, { "TOPRIGHT", "BOTTOMRIGHT", "w" } }) do
		local edge = ring:CreateTexture(nil, "OVERLAY")
		edge:SetPoint(side[1])
		edge:SetPoint(side[2])
		E:Hairline(edge, side[3], 1)
		E:AccentTexture(edge, 1)
		ring.edges[#ring.edges + 1] = edge
	end
	ring:Hide()
	page.ring = ring
	return ring
end

-- The rail rows that can take the ring, in rail order.
local function FocusList()
	local list = {}
	for index, item in ipairs(page and page.items or {}) do
		if item.def then list[#list + 1] = { key = item.def.key, index = index } end
	end
	return list
end

-- scroll: bring the ring's row into view (a key press); a plain redraw of
-- the rail only moves the ring along.
local function PlaceRing(scroll)
	if placing or not page then return end
	local ring = Ring()
	ring:Hide()
	if not focus then return end
	placing = true
	for _, entry in ipairs(FocusList()) do
		if entry.key == focus then
			if scroll == true then page.rail:ScrollTo(entry.index) end
			local row = page.rail:RowFor(entry.index)
			if row then
				ring:ClearAllPoints()
				ring:SetAllPoints(row)
				ring:Show()
			end
			break
		end
	end
	placing = false
end

local function SetFocus(key)
	focus = key
	PlaceRing(true)
end

function A:HubFocus()
	return focus
end

local function MoveFocus(step, to)
	local list = FocusList()
	if #list == 0 then return false end
	local at
	for index, entry in ipairs(list) do
		if entry.key == (focus or page:Current()) then at = index end
	end
	if to == "first" then
		at = 1
	elseif to == "last" then
		at = #list
	elseif not focus then
		at = at or 1
	else
		at = math.min(math.max((at or 0) + step, 1), #list)
	end
	SetFocus(list[at].key)
	return true
end

-- The pointer is over the Journal window (keys are only taken then).
local function Pointer()
	local window = LG.WindowFrame and LG:WindowFrame()
	if window and window:IsMouseOver() then return true end
	return page ~= nil and page:IsMouseOver()
end

function A:HubKey(key)
	if not (page and page:IsVisible()) or InCombatLockdown() or type(key) ~= "string" then return false end
	local typing = rawget(_G, "GetCurrentKeyBoardFocus")
	if type(typing) == "function" and typing() then return false end
	if key == "ESCAPE" then
		if focus then
			SetFocus(nil)
			return true
		end
		return false
	end
	if not (focus or Pointer()) then return false end
	local alt = IsAltKeyDown()
	if (alt and key == "LEFT") or key == "BACKSPACE" then return Walk(-1) end
	if alt and key == "RIGHT" then return Walk(1) end
	if alt or IsControlKeyDown() or IsShiftKeyDown() then return false end
	if key == "UP" then return MoveFocus(-1) end
	if key == "DOWN" then return MoveFocus(1) end
	if key == "HOME" then return MoveFocus(0, "first") end
	if key == "END" then return MoveFocus(0, "last") end
	if (key == "ENTER" or key == "NUMPADENTER") and focus then
		page:Pick(focus)
		return true
	end
	return false
end

-- Keys only while it shows and out of combat (SetPropagateKeyboardInput
-- is restricted in combat); a key it does not use goes on to the game.
local keyEvents = CreateFrame("Frame")
local function KeyboardOn(on)
	if not page then return end
	on = on and page:IsVisible() and not InCombatLockdown()
	page:EnableKeyboard(on and true or false)
	if not on then SetFocus(nil) end
end

keyEvents:SetScript("OnEvent", function(_, event)
	KeyboardOn(event == "PLAYER_REGEN_ENABLED")
end)

local function HookKeys(host)
	host:EnableKeyboard(false)
	host:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then return end
		local handled = A:HubKey(key)
		self:SetPropagateKeyboardInput(not handled)
	end)
	local function Shown()
		keyEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
		keyEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
		KeyboardOn(true)
	end
	host:HookScript("OnShow", Shown)
	host:HookScript("OnHide", function()
		keyEvents:UnregisterAllEvents()
		focus = nil
		if host.ring then host.ring:Hide() end
		host:EnableKeyboard(false)
	end)
	hooksecurefunc(host.rail, "Layout", function() PlaceRing() end)
	-- Built while the window shows: no OnShow comes for this first time.
	if host:IsVisible() then Shown() end
end

---------------------------------------------------------------------------
-- The paper page: parchment behind the rail and the open section while
-- K.OnPaper() is on (the client's parchment tile, else the paper fill).
-- K.Restyle() shows or hides it; a change of the page setting restyles.
---------------------------------------------------------------------------
local function PaintPaper(host)
	local paper = host and host.paper
	if not paper then return end
	K.ShowPaper(paper, K.OnPaper())
end

local function Paper(host)
	local paper = host:CreateTexture(nil, "BACKGROUND", nil, -7)
	paper:SetAllPoints()
	if not E:SetClientAtlas(paper, "AdventureMap_TileBg_Parchment", E.media.flat) then
		local fill = T.paper and T.paper.fill
		if fill then paper:SetVertexColor(fill[1], fill[2], fill[3], 1) end
	end
	paper:SetHorizTile(true)
	paper:SetVertTile(true)
	host.paper = paper
	K.PaperWash(host, paper, -6)
	PaintPaper(host)
end

local seenPage
hooksecurefunc(K, "Restyle", function() PaintPaper(page) end)
hooksecurefunc(A, "OnProfileChanged", function()
	local value = A.db and A.db.page
	if value ~= seenPage then
		seenPage = value
		if page then K.Restyle() end
	end
end)

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local function Create(content)
	local host = LG.Kit.SectionHost(content, {
		railWidth = RAIL_WIDTH,
		groups = GROUPS,
		selected = Saved,
		onSelect = Remember,
		footer = BuildFooter,
		footerHeight = FOOTER_HEIGHT,
		empty = { L["Nothing to show yet"], L["The journal's pages are switched off or still loading."], ICON },
	})
	host.hub = HUB
	page = host
	seenPage = A.db and A.db.page
	Paper(host)
	-- Every open is a place on the back and forward stack; the ring follows.
	local baseOpen = host.Open
	function host:Open(key, arg)
		if not walking then KeepScroll() end
		local frame = baseOpen(self, key, arg)
		local current = self:Current()
		if current and not walking then Visit(current, arg) end
		if focus and current then focus = current end
		PlaceRing()
		UpdateNav(self.footer)
		return frame
	end
	HookKeys(host)
	host:SetSections(Defs(HUB))
	UpdateNav(host.footer)
	return host
end

-- arg -> section key, section argument
local function Route(arg)
	if type(arg) == "table" then
		return arg.section, arg.arg
	end
	if type(arg) ~= "string" or arg == "" then return nil end
	local kind, id = J:ParseAddress(arg)
	if kind then
		if kind == "section" then return tostring(id), nil end
		local section = ADDRESS_SECTION[kind]
		if section and Visible(A:Section(section)) then return section, arg end
		if kind == "moment" then return "journey", { seq = tonumber(id) } end
		return "journey", { address = arg }
	end
	local key = A:FindSection(arg)
	if key then return key, nil end
	return "journey", { search = arg }
end

local function Show(frame, arg)
	frame:SetSections(Defs(HUB))
	UpdateFooter(frame.footer)
	local key, sectionArg = Route(arg)
	if not key then
		local current = frame:Current()
		if session.opened and current and Visible(frame:Section(current)) then
			key = current
		else
			key = StartSection()
		end
	end
	session.opened = true
	frame:Open(key, sectionArg)
end

local function Hide(frame)
	frame:HideCurrent()
end

local function Refresh(frame, changed)
	if changed.adventure or changed.attune or changed.settings or changed.pages or changed.data or changed.quests then
		frame:SetSections(Defs(HUB))
		UpdateFooter(frame.footer)
		local current = frame:Current()
		if current and not Visible(frame:Section(current)) then frame:Open(nil) end
	end
	local def = frame:Section(frame:Current())
	if def and def.frame and def.frame:IsShown() and def.refresh then
		local ok, err = pcall(def.refresh, def.frame, changed)
		if not ok then geterrorhandler()(err) end
	end
end

function A:RefreshHub()
	if page then
		page:Refresh()
		UpdateFooter(page.footer)
	end
end

-- The tab's number: goals you work on and reminders that wait (the
-- sections that say tabCount).
-- Goals you work on and notes that wait count on the tab without asking.
local TAB_COUNT = { goals = true, notes = true }

local function TabCount()
	local total = 0
	for _, def in ipairs(Defs(HUB)) do
		if (def.tabCount or TAB_COUNT[def.key]) and def.count and Visible(def) then
			local ok, value = pcall(def.count)
			if ok and type(value) == "number" then total = total + value end
		end
	end
	return total
end

local PAGE = {
	title = "My Adventure",
	desc = "Your character's journal: what you did and where, keepsakes, goals, notes, attunements, and where to go next.",
	order = 5,
	create = Create,
	show = Show,
	hide = Hide,
	refresh = Refresh,
	count = TabCount,
	alias = function(text)
		local key = A:FindSection(text)
		return key and { section = key } or nil
	end,
}
A.HUB_PAGE = PAGE

---------------------------------------------------------------------------
-- Atlas: rows that jump to the window's reference tabs (no page here)
---------------------------------------------------------------------------
local function PageOff(key)
	return function() return not LG:IsPageOn(key) end
end

A:RegisterSection("dungeons", {
	title = "Dungeons", icon = "Interface\\Icons\\INV_Misc_Key_03",
	desc = "Opens the Dungeons tab: every dungeon and raid with its bosses, loot and quests.",
	link = function() LG:Open("journal") end, hidden = PageOff("journal"),
})
A:RegisterSection("world", {
	title = "Open World", icon = "Interface\\Icons\\INV_Misc_Map_01",
	desc = "Opens the Open World tab: zones, rares and world drops.",
	link = function() LG:Open("world") end, hidden = PageOff("world"),
})
A:RegisterSection("reputation", {
	title = "Reputation", icon = "Interface\\Icons\\INV_Misc_Note_02",
	desc = "Opens the Catalog on Reputation: every faction and its rewards.",
	link = function() LG:OpenSection("reputation") end,
	hidden = function() return not (LG:IsPageOn("catalogue") and LG.CatalogueSection and LG:CatalogueSection("reputation")) end,
})

---------------------------------------------------------------------------
-- Address openers for the kinds the window itself can show. Places,
-- Quests and Fellowship (later files) register their own and win; kinds
-- without an opener open the tab on the matching section (Route).
---------------------------------------------------------------------------
-- "section" ids that are not hub sections: the Catalog's.
local CATALOGUE = { reputation = "reputation", crafting = "crafting", pvp = "pvp" }

J:RegisterAddress("section", function(id)
	id = tostring(id)
	local def = A:Section(id)
	if def and Visible(def) and not def.link then return A:OpenSection(id) end
	if CATALOGUE[id] and LG.CatalogueSection and LG:CatalogueSection(CATALOGUE[id]) and LG:IsPageOn("catalogue") then
		LG:OpenSection(CATALOGUE[id])
		return true
	end
	return false
end)

J:RegisterAddress("moment", function(id)
	return A:OpenSection("journey", { seq = tonumber(id) })
end)

J:RegisterAddress("instance", function(id)
	if not LG:IsPageOn("journal") then return false end
	local key = LG.FindInstance and LG:FindInstance(tostring(id))
	if not key then return false end
	LG:Open("journal", key)
	return true
end)

J:RegisterAddress("item", function(id)
	local itemID = tonumber(id)
	if not itemID then return false end
	local key, arg = LG:ItemRoute(itemID)
	if key == "search" then key, arg = "item", itemID end
	LG:Open(key, arg)
	return true
end)

J:RegisterAddress("quest", function(id)
	local questID = tonumber(id)
	if not questID then return false end
	local def = A:Section("quests")
	if def and Visible(def) then return A:OpenSection("quests", { quest = questID }) end
	local quest = LG.Quest and LG:Quest(questID)
	if quest and quest.instance and LG:IsPageOn("journal") and LG:InstanceInfo(quest.instance) then
		LG:Open("journal", { key = quest.instance, quest = questID })
	else
		LG:Open("detail", { quest = questID })
	end
	return true
end)

---------------------------------------------------------------------------
-- /eui journey
---------------------------------------------------------------------------
local function Command(arg)
	arg = strtrim(arg or "")
	if not A:Running() then
		E:Print(A:OffHint() or L["My Adventure is off."])
		return
	end
	local word = arg:lower()
	if word == "" then
		if LG:IsOpen() and LG:CurrentPage() == HUB then LG:Close() else LG:Open(HUB) end
	elseif word == "data" then
		E:Print(LG.JourneyDataText and LG:JourneyDataText() or LG:DataStatusText())
	else
		LG:Open(HUB, arg)
	end
end

-- Entry.lua wraps /eui journey (check, report, export, import) and hands
-- every other word to this handler.
A.HubCommand = Command

E:AddCommand("journey", "[section | data | text]  open or close My Adventure in the Journal window, on a section or searched", Command, "Tools")

---------------------------------------------------------------------------
-- Part: the tab exists while the journal runs
---------------------------------------------------------------------------
-- The tab is the start page for players who kept the Loot Guide's own
-- default (For You); asked once per profile, and only then.
local function ClaimStart()
	local db = A.db
	if not db or db.startClaimed or not LG.db then return end
	db.startClaimed = true
	if LG.db.startPage == "foryou" then LG.db.startPage = HUB end
end

A:AddPart("hub", {
	order = 80,
	start = function()
		ClaimStart()
		LG:RegisterPage(HUB, PAGE)
		local At = E.Attunements
		if At and At.PlaceHome then At:PlaceHome() end
		if LG.SyncWindowNames then LG:SyncWindowNames() end
		LG:Fire("pages")
	end,
	stop = function()
		local wasOpen = LG:IsOpen() and LG:CurrentPage() == HUB
		if page then
			page:HideCurrent()
			page:Hide()
		end
		session.opened = false
		LG:UnregisterPage(HUB)
		local At = E.Attunements
		if At and At.PlaceHome then At:PlaceHome() end
		if LG.SyncWindowNames then LG:SyncWindowNames() end
		if wasOpen then LG:Open(LG:StartPage()) end
		LG:Fire("pages")
	end,
})
