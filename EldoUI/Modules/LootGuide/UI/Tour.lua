-- EldoUI Loot Guide: the spotlight tour and the My
-- adventure tour.
--
-- The tours run on the core tour engine (Core/Tour.lua, E.Tour): the
-- screen dims except for a hole around the part being explained, an
-- accent frame marks it, and a callout beside it has the text with Back,
-- Next and Skip. This file holds the Loot Guide's steps and when they
-- start.
--
--   Kit.Tour(key, steps[, force])  steps = { { target = frame or fn,
--       title = "...", text = "...", before = fn, action = { label, fn } } }
--       Shows once per account (EldoUIDB.lootGuideTours); force shows it again.
--   LG:StartTour()   the main tour (welcome, Journal, dungeon map, Open
--       World, Best in Slot, filter, simulator, wishlist, search, Database,
--       Catalog, settings). Starts by itself the first time the window
--       opens outside combat and instances, after the first-run card.
--   LG:StartJournalTour()  the My Adventure tour (Today, Next trips, the
--       rail and its footer); starts by itself once, the first time Today
--       shows after the main tour was seen
--   LG:ResetTours()  every tour shows again (the "Start tour" option, and
--       Show tour helps again on the General options page)
--   /eui tour lootguide, /eui tour journal
--
-- A step whose part is not on screen (a page that is switched off, the
-- simulator folder missing) is skipped; when the shown part goes away (the
-- window closes) the tour ends. Combat ends the tour at once: the window
-- closes in combat and the tour never starts or goes on there. With Tour
-- helps off (General options) no tour starts by itself; Start tour and
-- /eui tour still show one.
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local L = E.L
local Tour = E.Tour

local OWNER = "lootguide"

---------------------------------------------------------------------------
-- Seen flags: account-wide (older builds kept them per character)
---------------------------------------------------------------------------
local function Seen()
	if type(EldoUIDB) ~= "table" then return {} end
	local seen = EldoUIDB.lootGuideTours
	if type(seen) ~= "table" then
		seen = {}
		EldoUIDB.lootGuideTours = seen
	end
	if not seen.migrated then
		seen.migrated = true
		for _, data in pairs(type(EldoUIDB.lootGuide) == "table" and EldoUIDB.lootGuide or {}) do
			if type(data) == "table" and type(data.tours) == "table" then
				for key, on in pairs(data.tours) do
					if on then seen[key] = true end
				end
			end
		end
	end
	return seen
end

function LG:TourSeen(key)
	return Seen()[key] == true
end

function LG:ResetTours()
	local seen = Seen()
	wipe(seen)
	seen.migrated = true
	for _, data in pairs(type(EldoUIDB) == "table" and type(EldoUIDB.lootGuide) == "table" and EldoUIDB.lootGuide or {}) do
		if type(data) == "table" and type(data.tours) == "table" then wipe(data.tours) end
	end
end

-- Show tour helps again (General options) brings these back too.
Tour:OnReset(function() LG:ResetTours() end)

---------------------------------------------------------------------------
-- The engine's tour, for the Loot Guide's own steps
---------------------------------------------------------------------------
local function Running()
	return Tour:Owner() == OWNER and Tour:Running() == "tour"
end

function LG:PlaceTour()
	if Running() then Tour:Place() end
end

function LG:TourStep(direction)
	if Running() then Tour:Step(direction) end
end

function LG:EndTour()
	if Running() then Tour:End("skip") end
end

function LG:TourRunning()
	if not Running() then return false end
	local _, key, index = Tour:Running()
	return true, key, index
end

-- Start a tour. Returns true when its first step shows.
function LG:RunTour(key, steps, force, title, skipTip)
	return Tour:Run(key, steps, { force = force, title = title, owner = OWNER, seen = Seen,
		skipTip = skipTip or L["Ends the tour. Start it again with Start tour on the Loot Guide settings page or /eui tour lootguide."] })
end

-- The mini-tours (pages call this the first time a part opens). Not over
-- the first-run card or another tour: the tour stays unseen and shows on
-- a later visit.
function Kit.Tour(key, steps, force)
	if Tour:Running() then return false end
	if LG:FirstRunShown() or (LG.FirstRunPending and LG:FirstRunPending()) then return false end
	return LG:RunTour(key, steps, force)
end

function Kit.TourFrame()
	return Tour:Callout("tour")
end

---------------------------------------------------------------------------
-- The main tour
---------------------------------------------------------------------------
local function Window()
	return LG:WindowFrame()
end

local function OpenPage(key)
	return function()
		if LG:IsPageOn(key) and LG:CurrentPage() ~= key then LG:Open(key) end
	end
end

local function Tab(key)
	return function() return LG:IsPageOn(key) and LG:TabButton(key) or nil end
end

local function PageFrame(key)
	local page = LG:GetPage(key)
	return page and page.frame
end

function LG:MainTourSteps()
	local steps = {}
	local function Add(step) steps[#steps + 1] = step end
	Add({ title = L["Welcome to the Loot Guide"], target = function() local w = Window() return w and w.topBar end,
		text = L["Your loot journal, Best in Slot planner and wishlist in one window. This short tour shows each part; Skip ends it, and Start tour on the settings page brings it back."],
		action = function()
			if not (LG:SimMode() and LG:SimAvailable()) then return end
			return { L["Sim Best in Slot"], function() LG:RunSim("bis") end,
				L["You rate items with the simulator: this runs your Best in Slot set now (out of combat, in small steps)."] }
		end })
	Add({ title = L["My Adventure"], before = OpenPage("adventure"), target = Tab("adventure"),
		text = L["Your character's journal: where to go next, what is waiting for you, your goals and notes, and the story so far. /eui tour journal shows it part by part."] })
	Add({ title = L["Journal"], before = OpenPage("journal"), target = Tab("journal"),
		text = L["Every dungeon and raid with its bosses, loot, drop chances and quests. Inside a dungeon the window opens on it."] })
	Add({ title = L["Dungeon map"], before = OpenPage("journal"), target = function()
			local frame = PageFrame("journal")
			local map = frame and frame.inst and frame.inst.map
			if map and map:IsVisible() then return map end
			return LG:IsPageOn("journal") and LG:TabButton("journal") or nil
		end,
		text = L["Open a dungeon in the Journal and press Dungeon map: the floors with numbered boss markers. Entrance pins the way in on your world map."] })
	Add({ title = L["Open World"], before = OpenPage("world"), target = Tab("world"),
		text = L["Rare mobs, world drops, zone quests and vendors by zone, for leveling between dungeons."] })
	Add({ title = L["Best in Slot"], before = OpenPage("bis"), target = Tab("bis"),
		text = L["The best item per slot from your list, what you wear, your two plan sets and your wishlist by slot. Click a slot to pick something else."] })
	Add({ title = L["Filter"], before = OpenPage("bis"), target = function()
			local frame = LG:BiSOn() and PageFrame("bis")
			return frame and frame.filterButton or nil
		end,
		text = L["Your spec, the armor you wear and where gear may come from. This one list counts everywhere: For You, tooltips and roll advice."] })
	Add({ title = L["Simulator"], before = OpenPage("bis"), target = function()
			local frame = LG:BiSOn() and LG:SimAvailable() and PageFrame("bis")
			return frame and frame.sim or nil
		end,
		text = L["Fights against a target dummy with your own character sheet: DPS numbers for your gear, Best in Slot and plan sets. /eui sim opens its window."] })
	Add({ title = L["Wishlist"], before = OpenPage("wishlist"), target = Tab("wishlist"),
		text = L["Star items anywhere to wish for them. You get an alert when one drops, is in a roll or in the dungeon you enter."] })
	Add({ title = L["Search"], target = function() local w = Window() return w and w.search or nil end,
		text = L["Dungeons, bosses, quests, zones, mobs and items. Results show as you type; Enter opens them all."] })
	Add({ title = L["Database"], before = OpenPage("database"), target = Tab("database"),
		text = L["Every item, mob, quest and vendor the loot data knows, with filters and sorting."] })
	Add({ title = L["Catalog"], before = OpenPage("catalogue"), target = Tab("catalogue"),
		text = L["Crafting, reputation, PvP, sets, collections and events: what each one gives you and what you still need."] })
	Add({ title = L["Help"], target = function() local w = Window() return w and w.help or nil end,
		text = L["The commands and the address for problems. Pages, drop chances, the rating mode, alerts and the window look are in /eui > Loot Guide."] })
	return steps
end

function LG:StartTour()
	if not self.active then return false end
	if InCombatLockdown() then
		E:Print(L["The tour runs out of combat."])
		return false
	end
	if not self:IsOpen() then self:Open(self:StartPage()) end
	if not self:IsOpen() then return false end
	self:EndTour()
	return self:RunTour("main", self:MainTourSteps(), true, L["Loot Guide tour"])
end

local function InInstance()
	local inside = IsInInstance and IsInInstance()
	if issecretvalue and issecretvalue(inside) then return true end
	return inside and true or false
end

-- First open: after the first-run card, outside combat and instances.
local function MaybeAutoStart()
	if LG:TourSeen("main") or Tour:Running() or InCombatLockdown() or InInstance() then return end
	if not LG:IsOpen() or (LG.FirstRunShown and LG:FirstRunShown()) then return end
	C_Timer.After(0.4, function()
		if LG:TourSeen("main") or Tour:Running() or InCombatLockdown() or not LG:IsOpen() then return end
		if LG.FirstRunShown and LG:FirstRunShown() then return end
		LG:RunTour("main", LG:MainTourSteps(), false, L["Loot Guide tour"])
	end)
end

local baseOpen = LG.Open
function LG:Open(key, arg)
	baseOpen(self, key, arg)
	-- A step's page switch must not start anything new.
	if not Tour:Running() then MaybeAutoStart() end
end

local baseFinish = LG.FinishFirstRun
function LG:FinishFirstRun(rating, list)
	baseFinish(self, rating, list)
	MaybeAutoStart()
end

---------------------------------------------------------------------------
-- The journal tour (My Adventure): Today, Next trips, the rail and
-- its footer. Starts by itself once, the first time Today shows after the
-- main tour was seen (outside combat and instances); /eui tour journal
-- and the Take the tour button on Today's welcome card start it again.
---------------------------------------------------------------------------

local function Adventure()
	local A = E.Adventure
	if A and A.Running and A:Running() and LG:IsPageOn("adventure") then return A end
end

local function Hub()
	local A = Adventure()
	return A and A.HubFrame and A:HubFrame() or nil
end

local function OpenSection(key)
	return function()
		local A = Adventure()
		if A and A:SectionShown(key) and not (LG:CurrentPage() == "adventure" and A:CurrentSection() == key) then A:OpenSection(key) end
	end
end

local function SectionPart(key, field)
	return function()
		local A = Adventure()
		local def = A and A:Section(key)
		local frame = def and def.frame
		if not (frame and frame:IsVisible()) then return nil end
		if type(field) == "function" then return field(frame) end
		return frame[field]
	end
end

local function RailRow(key)
	return function()
		local hub = Hub()
		if not (hub and hub:IsVisible() and hub.rail) then return nil end
		for _, row in ipairs(hub.rail:ShownRows()) do
			if row.item and row.item.def and row.item.def.key == key then return row end
		end
	end
end

local function Footer(field)
	return function()
		local hub = Hub()
		local footer = hub and hub.footer
		return footer and footer[field] or nil
	end
end

function LG:JournalTourSteps()
	local steps = {}
	local function Add(step) steps[#steps + 1] = step end
	Add({ title = L["My Adventure"], before = OpenSection("today"), target = Tab("adventure"),
		text = L["Your character's journal, the first tab of this window: where to go next, what is waiting for you, and everything you have done."] })
	Add({ title = L["Today"], before = OpenSection("today"), target = SectionPart("today", "header"),
		text = L["Who you are and how far this level is. The light part of the bar is rested experience; the time to the next level counts only your own last levels."] })
	Add({ title = L["Next trip"], before = OpenSection("today"), target = SectionPart("today", function(frame) return frame.blocks and frame.blocks.trip end),
		text = L["The best idea for right now and why it is here. A dungeon opens as a trip plan: the quests to pick up first, getting in, inside, and afterwards. Every button only shows you the way."] })
	Add({ title = L["Waiting for you"], before = OpenSection("today"), target = SectionPart("today", function(frame) return frame.blocks and frame.blocks.waiting end),
		text = L["Quests to hand in, attunements under way, your goals, reminders, and mail that runs out soon."] })
	Add({ title = L["Next trips"], before = OpenSection("next"), target = SectionPart("next", "kinds"),
		text = L["Every idea, best first, with filters for dungeons, quests, attunements, and zones, for your group and the time you have. Hover a card to see every reason; Not now puts it away until your next level."] })
	Add({ title = L["Goals"], target = RailRow("goals"),
		text = L["Set goals here, or with Set as goal on any idea. Their bars move by themselves as the game reports progress."] })
	Add({ title = L["Journey"], target = RailRow("journey"),
		text = L["Your story chapter by chapter: levels, places, first kills, finds, and the people you met. Keepsakes and the story so far sit beside it."] })
	Add({ title = L["Attunements"], target = RailRow("attune"),
		text = L["Every attunement and key step by step. Its next steps show up in Next trips and on Today."] })
	Add({ title = L["Write a note"], target = Footer("note"),
		text = L["A note remembers where and when you wrote it, and it can remind you later."] })
	Add({ title = L["Settings"], target = Footer("settings"),
		text = L["What the journal writes down, the look of its pages, and how the ideas are ranked. /eui tour journal shows this tour again."] })
	return steps
end

function LG:StartJournalTour()
	if not (self.active and Adventure()) then
		-- Name the part that is off: My Adventure itself or the Loot Guide.
		local A = E.Adventure
		local line = A and A.OffHint and A:OffHint()
		E:Print(line or E:ModuleOffHint(self.active and "Adventure" or "LootGuide"))
		return false
	end
	if InCombatLockdown() then
		E:Print(L["The tour runs out of combat."])
		return false
	end
	self:EndTour()
	if not (self:IsOpen() and self:CurrentPage() == "adventure") then self:Open("adventure", { section = "today" }) end
	OpenSection("today")()
	if not self:IsOpen() then return false end
	return self:RunTour("journal", self:JournalTourSteps(), true, L["My Adventure tour"], L["Ends the tour. Start it again with /eui tour journal."])
end

-- Today calls this each time it draws: the first time (after the main
-- tour), the journal tour starts.
function LG:MaybeJournalTour()
	if self:TourSeen("journal") or Tour:Running() or not self:TourSeen("main") or InCombatLockdown() or InInstance() then return end
	if self.journalTourQueued then return end
	self.journalTourQueued = true
	C_Timer.After(0.5, function()
		self.journalTourQueued = nil
		local A = Adventure()
		if not A or self:TourSeen("journal") or Tour:Running() or InCombatLockdown() or InInstance() then return end
		if not (self:IsOpen() and self:CurrentPage() == "adventure" and A:CurrentSection() == "today") then return end
		self:RunTour("journal", self:JournalTourSteps(), false, L["My Adventure tour"], L["Ends the tour. Start it again with /eui tour journal."])
	end)
end

-- /eui tour lootguide | journal (the core command lists every help)
local function StartMain()
	if not LG.active then
		E:Print(E:ModuleOffHint("LootGuide"))
		return
	end
	LG:StartTour()
end
local function StartJournal() LG:StartJournalTour() end
Tour:RegisterReplay("lootguide", L["Loot Guide tour"], StartMain)
Tour:RegisterReplay("journal", L["My Adventure tour"], StartJournal)
for _, word in ipairs({ "lg", "guide" }) do Tour:RegisterReplay(word, L["Loot Guide tour"], StartMain) end
for _, word in ipairs({ "adventure", "journey" }) do Tour:RegisterReplay(word, L["My Adventure tour"], StartJournal) end
