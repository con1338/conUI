-- EldoUI My Adventure: moment cards in the alert lane: queue, combat and dungeon hold, sounds, Fanfare de-dup, screenshot button.
--
-- A moment is a short card for something the journal just wrote down: a
-- new chapter (level), a new place, a first dungeon, a keepsake, a goal
-- reached, rested time, a reminder, a note saved, and the briefs of
-- Briefs.lua (arrival, door, "you missed one", what opens at a level).
-- Every card shows recorded facts only, and its buttons only navigate
-- (open the journal, take a screenshot) or change the journal (Done,
-- Snooze on a reminder). Nothing acts in the game.
--
-- API (E.Adventure.Moments):
--   M:Push(data) -> "card" | "lane" | "notifications" | "waiting" | "held" | nil
--       data = { kind, title, text, icon, seconds, sound, key, always,
--                actions = { { label, func, tip } }, note, address, fanfare,
--                camera, now }
--         kind     level, zone, dungeon, goal, rested, keepsake, note (the
--                  "momentKinds" ticks), reminder, brief, summary, sample
--         always   shows even while "Moments" is off (reminders, briefs)
--         key      a newer moment with the same key replaces the older one
--         address  "journal:..." the Show button opens
--         fanfare  the Fanfare source that already reacts to the same
--                  game event ("levelup", "bosskill"): with a sound there,
--                  the card stays quiet
--         camera   adds the screenshot button (keepsake and level moments)
--         now      skips the combat and dungeon hold
--         closable the card keeps its x even in the Alerts & Messages lane
--                  (the door brief and "you missed one")
--       nil: moments are off, or the kind is switched off.
--       Other kinds (recap from Story so far, screenshot) show like any
--       moment without a tick of their own.
--   M:Dismiss(key)    closes a card (the door brief ends with the first pull)
--   M:Screenshot([hide])   one screenshot on a click: the frames in `hide`
--                     (a frame or a list) are see-through for the shot, then
--                     one quiet card says it was taken. Never automatic.
--   M.ScreenshotKey() the player's own screenshot key as text, or nil
--   M:Sample()        a sample moment for the options page
--   M:Shown()         the moments shown this session, newest last (diag, tests)
--   M:Held()          what waits for combat to end and what the dungeon holds
--   M:OnLane()        true while the "Journal Moments" mover sits on the lane
--
-- Callbacks (E.Journal.RegisterCallback): "Moment"(data) when a card
-- shows; "Keepsake"(row) as soon as a keepsake is written down, even while
-- its card is held or moments are off (Today's Lately follows it).
--
-- Where a card shows: while the "Journal Moments" mover sits on its layout
-- spot (the Alert Lane's, layoutAlias), every moment goes through
-- E:PushAlert, so it queues and stacks with the lane's other cards. Once
-- the player drags the mover elsewhere, moments draw their own card there,
-- in the same look, one at a time.
--
-- When it shows:
--   * Moments other than reminders and briefs wait for combat to end.
--   * In a dungeon or raid they are held, and one summary shows when you
--     leave ("Shadowfang Keep: 3 bosses, 2 firsts, 1 keepsake"), unless
--     "Moments in dungeons" is "as they happen". The first-time card at
--     the door and the briefs are never held.
--   * "New place" stays off while Zone Info's zone toast is on, and
--     "Level" while Fanfare shows its level-up text.
--
-- One sound per moment: the kind's sound (a media row), on the Master
-- channel when "Play when game effects are muted" is on, unless Sound and
-- Fun already plays one for it: a level-up or boss-kill trigger with a
-- sound, or a "Journal moment" trigger with a sound (moments are handed to
-- Fanfare while "Moments in Fanfare" is on).
local _, E = ...
local L = E.L
local Key = E.Key
local A = E.Adventure
local J = E.Journal

local Plain = A.Plain

local M = {}
A.Moments = M

A.defaults.momentFanfare = true

M.MAX_SHOWN_LOG = 20
M.QUIET_SECONDS = 5           -- after the journal starts: rows of the login catch-up stay quiet
M.MERGE_SECONDS = 6           -- a brief this soon after its moment joins the same card
M.SOUND_GAP = 0.5
M.HELD_MAX = 30

-- The "momentKinds" ticks; other kinds have no tick of their own.
M.KINDS = { "zone", "level", "dungeon", "goal", "rested", "keepsake", "note" }
local TICKED = {}
for _, kind in ipairs(M.KINDS) do TICKED[kind] = true end

-- Never held in combat or in a dungeon.
local NEVER_HELD = { reminder = true, brief = true, summary = true, sample = true }
-- Not held in a dungeon: the first-time card belongs to the door, the
-- session recap to the login.
local DOOR = { dungeon = true, recap = true }

M.ICON = {
	level = "Interface/Icons/Spell_Holy_HolyBolt", zone = "Interface/Icons/INV_Misc_Map_01",
	dungeon = "Interface/Icons/INV_Misc_Key_03", goal = "Interface/Icons/Achievement_Quests_Completed_08",
	rested = "Interface/Icons/Spell_Nature_Sleep", reminder = "Interface/Icons/INV_Misc_PocketWatch_01",
	note = "Interface/Icons/INV_Feather_05", keepsake = "Interface/Icons/INV_Misc_Book_09", -- no-L
	brief = "Interface/Icons/INV_Misc_Map02", summary = "Interface/Icons/INV_Misc_Book_09",
	recap = "Interface/Icons/INV_Misc_Book_11", screenshot = "Interface/Icons/INV_Misc_Spyglass_03",
}

local function Settings()
	return A.db or A.defaults
end

local function Kinds()
	local kinds = Settings().momentKinds
	return type(kinds) == "table" and kinds or {}
end

local function Fold(text)
	if type(text) ~= "string" or E:IsSecret(text) then return "" end
	return E:FoldText(text)
end

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c, d, e, f, g, h
end

local function Span(seconds)
	local Fmt = A.Fmt
	if Fmt and Fmt.Span then return Fmt.Span(seconds) end
	seconds = math.floor(tonumber(seconds) or 0)
	return ("%dh %dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

---------------------------------------------------------------------------
-- Other modules that show the same moment
---------------------------------------------------------------------------
local function Covers(source)
	if type(E.FanfareCovers) ~= "function" or type(source) ~= "string" then return false, false end
	local ok, sound, text = pcall(E.FanfareCovers, E, source)
	if not ok then return false, false end
	return sound and true or false, text and true or false
end
M.Covers = Covers

-- "Level" stays off while Fanfare shows its own level-up text, and while
-- the Talent Planner's level-up reminder (one card for the whole level)
-- is on.
function M:LevelCovered()
	local TP = E.Talents
	if TP and type(TP.OwnsLevelUp) == "function" and TP:OwnsLevelUp() then return true end
	local _, text = Covers("levelup")
	return text
end

-- Whether a level-up shows a level moment here (the alert lane's own level
-- toast stands back then, so a level-up has one card).
function M:ShowsLevel()
	local db = Settings()
	if not (A.started and db.moments) or Kinds().level == false then return false end
	return not self:LevelCovered()
end

-- "New place" stays off while Zone Info's zone toast is on.
function M:PlaceCovered()
	local zoneInfo = E.GetModule and E:GetModule("ZoneInfo")
	return zoneInfo and zoneInfo.active and type(zoneInfo.db) == "table" and zoneInfo.db.toast and true or false
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local state = {
	combat = {},        -- moments waiting for combat to end
	dungeon = nil,      -- { name, bosses, firsts, keepsakes, goals, levels, held = n }
	parts = {},         -- key -> { at, parts = { [slot] = text }, data }
	shown = {},         -- the session's moments, newest last
	lastSound = -10,
	quietUntil = 0,
}
M.state = state

function M:Shown()
	return state.shown
end

function M:Held()
	return state.combat, state.dungeon
end

---------------------------------------------------------------------------
-- The mover and the card off the lane
---------------------------------------------------------------------------
local MOVER = "EldoUI_JournalMoments"
local WIDTH, HEIGHT = 300, 52
local anchor, card
local cardQueue = {}

function M:OnLane()
	local positions = E.db and E.db.movers
	return not (type(positions) == "table" and positions[MOVER] ~= nil)
end

local function CreateAnchor()
	if anchor then return end
	anchor = CreateFrame("Frame", MOVER, UIParent)
	anchor:SetSize(WIDTH, HEIGHT)
	anchor:EnableMouse(false)
	anchor:Hide()
	local previous = E.currentModule
	E.currentModule = A
	M.mover = E:CreateMover(anchor, MOVER, L["Journal Moments"], { "TOP", "UIParent", "TOP", -560, -300 },
		{ layoutAlias = "EldoUI_AlertLane", group = "Other", enabledPath = { "enabled" }, sample = { kind = "text" } })
	E.currentModule = previous
end
M.CreateAnchor = CreateAnchor

local ShowOwn

local function CloseOwn(instant)
	if not card or not card:IsShown() then return end
	if card.timer then
		card.timer:Cancel()
		card.timer = nil
	end
	local function Done()
		card:Hide()
		card.data = nil
		anchor:Hide()
		if cardQueue[1] then ShowOwn(table.remove(cardQueue, 1)) end
	end
	if instant then
		Done()
	else
		E:SlideOut(card, "UP", Done)
	end
end

local function ArmTimer(seconds)
	if card.timer then card.timer:Cancel() end
	card.timer = C_Timer.NewTimer(seconds, function()
		card.timer = nil
		-- Stays while the mouse is over it.
		if card:IsShown() and card:IsMouseOver() then
			ArmTimer(1)
		else
			CloseOwn()
		end
	end)
end

local function CreateCard()
	card = CreateFrame("Button", nil, anchor)
	card:SetFrameStrata("DIALOG")
	card:SetWidth(WIDTH)
	card:SetPoint("TOP", anchor, "TOP", 0, 0)
	card:RegisterForClicks("RightButtonUp")
	card:SetClampedToScreen(true)
	E:SetPanelTemplate(card, false)
	card.iconBox = CreateFrame("Frame", nil, card)
	card.iconBox:SetSize(36, 36)
	card.iconBox:SetPoint("TOPLEFT", 8, -8)
	E:SetTemplate(card.iconBox)
	card.icon = card.iconBox:CreateTexture(nil, "ARTWORK")
	card.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	card.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(card.icon)
	card.close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
	card.close:SetSize(18, 18)
	card.close:SetPoint("TOPRIGHT", -2, -2)
	E:SkinCloseButton(card.close)
	card.close:SetScript("OnClick", function() CloseOwn() end)
	card.title = E:CreateText(card, E.tokens.size.small, "LEFT")
	card.title:SetPoint("TOPLEFT", card.iconBox, "TOPRIGHT", 8, -1)
	card.title:SetPoint("TOPRIGHT", card.close, "TOPLEFT", -4, -7) -- the title's top is 7 under the close button's
	card.text = E:CreateText(card, E.tokens.size.body, "LEFT")
	card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
	card.text:SetPoint("TOPRIGHT", card.title, "BOTTOMRIGHT", 2 + 18 + 4 - 10, -3) -- 10 from the card's right
	card.text:SetWordWrap(true)
	card.text:SetJustifyV("TOP")
	card.buttons = {}
	card:SetScript("OnClick", function(_, button)
		if button == "RightButton" then CloseOwn() end
	end)
	card:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(E.media.accentColor)) end)
	card:SetScript("OnLeave", function(self) E:SetPanelTemplate(self, false) end)
	card:Hide()
end

ShowOwn = function(data)
	CreateAnchor()
	if not card then CreateCard() end
	card.data = data
	E:SetPanelTemplate(card, false)
	card.icon:SetTexture(E.ClientIcon and E:ClientIcon(data.icon) or data.icon)
	E:SetFont(card.title, E.tokens.size.small)
	E:SetFont(card.text, E.tokens.size.body)
	card.title:SetText(data.title or "")
	card.title:SetTextColor(E:TokenColor("accent"))
	card.text:SetText(data.text or "")
	card.text:SetTextColor(unpack(E.tokens.text.body))
	local textHeight = math.max(card.text:GetStringHeight() or 14, 14)
	local top = math.max(36, 14 + 3 + textHeight)
	local actions = type(data.actions) == "table" and data.actions or {}
	local x, shown = 0, 0
	for index = 1, math.max(#card.buttons, math.min(#actions, 3)) do
		local action = index <= 3 and actions[index] or nil
		local button = card.buttons[index]
		if action and not button then
			button = E.UIKit.Button(card, "", 80)
			E:BindOptionsLink(button, { page = "module:Adventure", key = "moments" })
			card.buttons[index] = button
		end
		if button then
			button:SetShown(action ~= nil)
			if action then
				button:SetText(action.label or OKAY)
				E.UIKit.FitButton(button, 70)
				button:SetScript("OnClick", function(self, mouse)
					if E:IsOptionsLinkClick(self, mouse) then return end
					-- "now": the card is gone before the action runs (a screenshot).
					if action.now then CloseOwn(true) end
					if type(action.func) == "function" then
						local ok, err = pcall(action.func, data, card)
						if not ok then geterrorhandler()(err) end
					end
					if not action.now then CloseOwn() end
				end)
				E.UIKit.Tooltip(button, action.label, action.tip)
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", card.iconBox, "TOPRIGHT", 8 + x, -(top + 6))
				x = x + button:GetWidth() + 4
				shown = shown + 1
			end
		end
	end
	card:SetHeight(8 + top + (shown > 0 and 32 or 8))
	anchor:Show()
	E:SlideIn(card, "UP")
	ArmTimer(tonumber(data.duration) or 8)
	return card
end

-- Off the lane: one card at a time, the rest wait (same key: replaced).
local function QueueOwn(data)
	if card and card:IsShown() and card.data and data.key ~= nil and card.data.key == data.key then
		ShowOwn(data)
		return "card"
	end
	if data.key ~= nil then
		for index = #cardQueue, 1, -1 do
			if cardQueue[index].key == data.key then table.remove(cardQueue, index) end
		end
	end
	if card and card:IsShown() then
		cardQueue[#cardQueue + 1] = data
		while #cardQueue > M.HELD_MAX do table.remove(cardQueue, 1) end
		return "waiting"
	end
	ShowOwn(data)
	return "card"
end

function M:Dismiss(key)
	if key == nil then return false end
	local found = false
	for index = #cardQueue, 1, -1 do
		if cardQueue[index].key == key then
			table.remove(cardQueue, index)
			found = true
		end
	end
	if card and card:IsShown() and card.data and card.data.key == key then
		CloseOwn()
		found = true
	end
	if type(E.AlertCards) == "function" then
		local cards, waiting = E:AlertCards()
		for index = #(waiting or {}), 1, -1 do
			if waiting[index].key == key then
				table.remove(waiting, index)
				found = true
			end
		end
		for _, alert in ipairs(cards or {}) do
			if alert.data and alert.data.key == key and not alert.closing and alert.close then
				local click = alert.close:GetScript("OnClick")
				if click then
					click(alert.close)
					found = true
				end
			end
		end
	end
	return found
end

---------------------------------------------------------------------------
-- Showing a moment
---------------------------------------------------------------------------
local function Remember(data, route, actions)
	local log = state.shown
	local labels = {}
	for index, action in ipairs(actions or {}) do labels[index] = action.label end
	log[#log + 1] = { kind = data.kind, title = data.title, text = data.text, key = data.key, route = route,
		sound = data.played, actions = labels, at = GetTime() }
	while #log > M.MAX_SHOWN_LOG do table.remove(log, 1) end
end

-- One sound per moment (see the top of the file).
local function PlaySound(data)
	data.played = nil
	local sound = data.sound
	if type(sound) ~= "string" or sound == "" or sound == "none" then return end
	if data.fanfare and (Covers(data.fanfare)) then return end
	if data.fanfareMoment then return end
	local now = GetTime()
	if now - state.lastSound < M.SOUND_GAP then return end
	state.lastSound = now
	E:PlayMedia(sound, Settings().soundMaster and "Master" or nil)
	data.played = sound
end

local function Actions(data)
	local list = {}
	for _, action in ipairs(type(data.actions) == "table" and data.actions or {}) do list[#list + 1] = action end
	if type(data.address) == "string" and #list < 3 then
		local address = data.address
		list[#list + 1] = { label = L["Show"], tip = L["Opens this moment in your journal."],
			func = function() J:Open(address) end }
	end
	if data.camera and Settings().screenshotButton and #list < 3 and type(rawget(_G, "Screenshot")) == "function" then
		list[#list + 1] = { label = L["Screenshot"], now = true,
			tip = L["Closes this card and takes a screenshot, the same as the game's screenshot key."],
			func = function() M:Screenshot() end }
	end
	return list
end

local function Show(data)
	-- Fanfare's "Journal moment" triggers fire with the card.
	data.fanfareMoment = nil
	local F = E.fanfare
	if Settings().momentFanfare ~= false and F and type(F.EmitMoment) == "function" then
		local ok, fired = pcall(F.EmitMoment, F, data)
		if ok and (tonumber(fired) or 0) > 0 and (Covers("journalmoment")) then data.fanfareMoment = true end
	end
	PlaySound(data)
	local alert = {
		title = data.title, text = data.text, icon = data.icon or M.ICON[data.kind] or M.ICON.keepsake,
		key = data.key, duration = tonumber(data.seconds) or Settings().momentSeconds, actions = Actions(data),
		moment = data.kind, closable = data.closable and true or nil,
	}
	if #alert.actions == 0 then alert.actions = nil end
	local route
	if M:OnLane() and type(E.PushAlert) == "function" then
		route = A:PushAlert(alert)
	else
		route = QueueOwn(alert)
	end
	Remember(data, route, alert.actions)
	A:Fire("Moment", data)
	return route
end

local function InDungeon()
	local R = A.Record
	if R and R.Instance then
		local name = R.Instance()
		return name
	end
	return nil
end

local function Hold(data)
	local held = state.dungeon
	if not held then return false end
	-- A moment and its brief (one key) count once.
	if data.key ~= nil then
		held.keys = held.keys or {}
		if held.keys[data.key] then return true end
		held.keys[data.key] = true
	end
	held.held = held.held + 1
	if data.kind == "keepsake" then held.keepsakes = held.keepsakes + 1 end
	if data.kind == "goal" then held.goals = held.goals + 1 end
	if data.kind == "level" then held.levels = held.levels + 1 end
	return true
end

function M:Push(data)
	if type(data) ~= "table" then return nil end
	local db = Settings()
	local kind = type(data.kind) == "string" and data.kind or "moment"
	data.kind = kind
	if not data.always then
		if not db.moments then return nil end
		if TICKED[kind] and Kinds()[kind] == false then return nil end
	end
	if not data.now and not NEVER_HELD[kind] then
		if InCombatLockdown() then
			local queue = state.combat
			if data.key ~= nil then
				for index = #queue, 1, -1 do
					if queue[index].key == data.key then table.remove(queue, index) end
				end
			end
			queue[#queue + 1] = data
			while #queue > M.HELD_MAX do table.remove(queue, 1) end
			return "held"
		end
		if not DOOR[kind] and db.momentsInDungeons ~= "now" and state.dungeon and Hold(data) then return "held" end
	end
	return Show(data)
end

-- After combat: the held moments in order (a dungeon may hold them now).
function M:FlushCombat()
	if InCombatLockdown() then return 0 end
	local queue = state.combat
	state.combat = {}
	for _, data in ipairs(queue) do self:Push(data) end
	return #queue
end

---------------------------------------------------------------------------
-- A card made of parts: a moment and its brief share one card (a level-up
-- and what opens at that level, a new place and its arrival brief).
---------------------------------------------------------------------------
local function PushParts(key, slot, text, data)
	local now = GetTime()
	local entry = state.parts[key]
	if not entry or now - entry.at > M.MERGE_SECONDS then
		entry = { at = now, parts = {} }
		state.parts[key] = entry
	end
	entry.parts[slot] = text
	if slot == "moment" or not entry.data then entry.data = data end
	local lines = {}
	for _, name in ipairs({ "moment", "brief" }) do
		if entry.parts[name] and entry.parts[name] ~= "" then lines[#lines + 1] = entry.parts[name] end
	end
	local push = {}
	for field, value in pairs(entry.data) do push[field] = value end
	push.key = key
	push.text = table.concat(lines, "\n")
	if data.always then push.always = true end
	-- The second part joins quietly.
	if entry.pushed then push.sound = nil end
	entry.pushed = true
	return M:Push(push)
end

---------------------------------------------------------------------------
-- What the journal reports
---------------------------------------------------------------------------
local function LevelText(level)
	local rec = J.Char and J:Char()
	local zone = Plain(Call(GetRealZoneText))
	local before = rec and type(rec.levels) == "table" and rec.levels[level - 1]
	local took = type(before) == "table" and tonumber(before.time) or nil
	local parts = {}
	if type(zone) == "string" and zone ~= "" then parts[#parts + 1] = zone end
	if took and took > 0 and level > 1 then parts[#parts + 1] = (L["%s in chapter %d"]):format(Span(took), level - 1) end
	return table.concat(parts, " · ")
end

function M:OnLevelUp(level)
	level = Plain(level)
	if type(level) ~= "number" then return nil end
	local db = Settings()
	-- Fanfare's level-up text shows it already.
	if self:LevelCovered() then return nil end
	local text, actions = LevelText(level), nil
	-- The spells and ranks the new level brings at the class trainer, under
	-- the alert lane's "New spells on level up" option.
	local spells = type(E.LevelUpSpells) == "function" and E:LevelUpSpells(level) or nil
	if spells then
		text = (text ~= "" and text .. "\n" or "") .. spells.line .. "\n" .. spells.names
		actions = { { label = L["Spells"], tip = L["Opens the spells your class trainer teaches that you don't know yet."],
			func = spells.open } }
	end
	return PushParts("journal-level-" .. level, "moment", text, {
		kind = "level", title = (L["Chapter %d"]):format(level), icon = M.ICON.level,
		seconds = db.momentSeconds, sound = type(db.sounds) == "table" and db.sounds.level or nil,
		fanfare = "levelup", camera = true, actions = actions,
	})
end

function M:OnRow(row)
	if type(row) ~= "table" or GetTime() < state.quietUntil then return nil end
	-- Pages follow a new keepsake at once, whatever happens to its card.
	if J:IsKeepsake(row) then A:Fire("Keepsake", row) end
	local db = Settings()
	local sounds = type(db.sounds) == "table" and db.sounds or {}
	local kind = row.kind
	local held = state.dungeon
	if held and (kind == "boss" or kind == "raidboss" or kind == "bossagain") then
		held.bosses = held.bosses + 1
		if row.first == true or kind == "raidboss" then held.firsts = held.firsts + 1 end
	end
	if kind == "zone" then
		if self:PlaceCovered() or type(row.zone) ~= "string" then return nil end
		local text = row.level and (L["First visit, level %d"]):format(row.level) or L["First visit"]
		return PushParts("journal-place-" .. Fold(row.zone), "moment", text, {
			kind = "zone", title = row.zone, icon = M.ICON.zone, seconds = db.momentSeconds, sound = sounds.zone,
			address = J:LinkFor(row),
		})
	elseif kind == "rested" then
		local pct = tonumber(row.pct)
		if not pct then return nil end
		return self:Push({ kind = "rested", title = L["Well rested"], text = (L["%d%% of a level"]):format(pct),
			icon = M.ICON.rested, seconds = db.momentSeconds, sound = sounds.rested, key = "journal-rested" })
	end
	if kind == "goal" or kind == "goalset" or kind == "raid" or kind == "dungeon" then return nil end
	if not J:IsKeepsake(row) then return nil end
	local def = J:Kind(kind)
	local text = type(A.LineText) == "function" and (Call(A.LineText, A, row)) or nil
	if type(text) ~= "string" or text == "" then text = row.boss or row.name or row.faction or row.profession or "" end
	return self:Push({
		kind = "keepsake", title = M.KEEPSAKE_TITLE[kind] or L["Keepsake"], text = text,
		icon = def and def.icon or M.ICON.keepsake, seconds = db.momentSeconds, sound = sounds.keepsake,
		key = "journal-keepsake-" .. tostring(row.seq), address = J:Address("moment", row.seq),
		fanfare = (kind == "boss" or kind == "raidboss") and "bosskill" or nil, camera = true,
	})
end

M.KEEPSAKE_TITLE = E:TranslateValues({
	boss = E.Key("First kill"), raidboss = E.Key("Raid boss down"), loot = E.Key("Epic find"), rep = E.Key("New standing"),
	skill = E.Key("Profession mastered"), mount = E.Key("New mount"), attuned = E.Key("Attuned"), title = E.Key("New title"),
	wish = E.Key("Wish come true"),
})

-- First time in a dungeon or raid: Record.lua keeps when each was first
-- seen; a first seen this moment gets a card at the door.
function M:CheckDoor()
	local name = InDungeon()
	local db = Settings()
	if name then
		if not state.dungeon or state.dungeon.name ~= name then
			if state.dungeon then self:LeaveDungeon() end
			state.dungeon = { name = name, bosses = 0, firsts = 0, keepsakes = 0, goals = 0, levels = 0, held = 0 }
		end
		local rec = J.Char and J:Char()
		local seen = rec and type(rec.instancesSeen) == "table" and tonumber(rec.instancesSeen[name])
		state.doors = state.doors or {}
		if seen and math.abs(time() - seen) <= 10 and not state.doors[name] then
			state.doors[name] = true
			local level = Plain(UnitLevel("player"))
			return self:Push({
				kind = "dungeon", title = (L["First time in %s"]):format(name),
				text = type(level) == "number" and (L["Level %d"]):format(level) or "",
				icon = M.ICON.dungeon, seconds = db.momentSeconds,
				sound = type(db.sounds) == "table" and db.sounds.dungeon or nil, key = "journal-door-" .. Fold(name),
			})
		end
	elseif state.dungeon then
		return self:LeaveDungeon()
	end
	return nil
end

-- "Shadowfang Keep: 3 bosses, 2 firsts, 1 keepsake", when anything happened.
function M:SummaryText(held)
	local parts = {}
	local function Add(n, one, other)
		if n > 0 then parts[#parts + 1] = E:Plural(n, one, other):format(n) end
	end
	Add(held.bosses, "%d boss", "%d bosses")
	Add(held.firsts, "%d first", "%d firsts")
	Add(held.keepsakes, "%d keepsake", "%d keepsakes")
	Add(held.goals, "%d goal reached", "%d goals reached")
	Add(held.levels, "%d level", "%d levels")
	return table.concat(parts, ", ")
end

function M:LeaveDungeon()
	local held = state.dungeon
	state.dungeon = nil
	if not held then return nil end
	local db = Settings()
	if db.momentsInDungeons == "now" or not db.moments then return nil end
	if held.held == 0 and held.bosses == 0 then return nil end
	local text = self:SummaryText(held)
	if text == "" then return nil end
	return self:Push({ kind = "summary", title = held.name, text = text, icon = M.ICON.summary,
		seconds = db.momentSeconds, sound = type(db.sounds) == "table" and db.sounds.dungeon or nil,
		key = "journal-summary-" .. Fold(held.name) })
end

-- Briefs.lua: arrival, door, "you missed one", what opens at a level.
local function BriefText(lines, from)
	local out = {}
	for index = from or 2, math.min(#lines, (from or 2) + 2) do out[#out + 1] = lines[index] end
	return table.concat(out, "\n")
end

function M:OnBrief(kind, brief)
	if type(brief) ~= "table" or type(brief.lines) ~= "table" or brief.empty then return nil end
	local db = Settings()
	local lines = brief.lines
	if kind == "levelup" then
		local level = tonumber(brief.level)
		if not level then return nil end
		local text = BriefText(lines, 2)
		if text == "" then return nil end
		if self:LevelCovered() then
			return self:Push({ kind = "brief", always = true, title = lines[1], text = text, icon = M.ICON.level,
				seconds = db.momentSeconds, key = "journal-level-" .. level })
		end
		return PushParts("journal-level-" .. level, "brief", text, {
			kind = "level", always = true, title = (L["Chapter %d"]):format(level), icon = M.ICON.level,
			seconds = db.momentSeconds, sound = type(db.sounds) == "table" and db.sounds.level or nil,
			fanfare = "levelup", camera = true,
		})
	elseif kind == "arrival" then
		local zone = type(brief.zone) == "string" and brief.zone or lines[1]
		return PushParts("journal-place-" .. Fold(zone), "brief", BriefText(lines, 2), {
			kind = "brief", always = true, title = lines[1], icon = M.ICON.zone, seconds = db.momentSeconds,
			address = brief.uiMapID and J:Address("place", brief.uiMapID) or nil,
		})
	elseif kind == "door" then
		return self:Push({ kind = "brief", always = true, title = lines[1], text = BriefText(lines, 2), icon = M.ICON.dungeon,
			seconds = tonumber(brief.seconds) or 20, key = "journal-doorbrief", closable = true })
	elseif kind == "missed" then
		return self:Push({ kind = "brief", always = true, title = L["You missed one"], text = BriefText(lines, 1),
			icon = M.ICON.brief, seconds = db.reminderSeconds, key = "journal-missed", closable = true })
	end
	return nil
end

function M:OnBriefEnd(kind)
	if kind == "door" then return self:Dismiss("journal-doorbrief") end
	return false
end

-- A sample for the options page ("Show a sample moment").
function M:Sample()
	local db = Settings()
	return self:Push({ kind = "sample", always = true, now = true, title = (L["Chapter %d"]):format(24),
		text = (L["%s in chapter %d"]):format(Span(7800), 23), icon = M.ICON.level, seconds = db.momentSeconds,
		sound = type(db.sounds) == "table" and db.sounds.level or nil, key = "journal-sample", camera = true })
end

---------------------------------------------------------------------------
-- Screenshots: on a click only. The frames to hide are
-- see-through until the game reports the shot, then one quiet card says it
-- was taken and where it went.
---------------------------------------------------------------------------
M.SCREENSHOT_WAIT = 3       -- seconds before a shot that never reported back is given up
local shot = { pending = false, hidden = {} }
local shotEvents = CreateFrame("Frame")

function M.ScreenshotKey()
	if type(GetBindingKey) ~= "function" then return nil end
	local key = Plain(Call(GetBindingKey, "SCREENSHOT"))
	if type(key) ~= "string" or key == "" then return nil end
	local text = type(GetBindingText) == "function" and Plain(Call(GetBindingText, key)) or nil
	return type(text) == "string" and text ~= "" and text or key
end

local function EndShot(ok)
	if not shot.pending then return end
	shot.pending = false
	shotEvents:UnregisterAllEvents()
	if shot.timer then
		shot.timer:Cancel()
		shot.timer = nil
	end
	for frame, alpha in pairs(shot.hidden) do frame:SetAlpha(alpha) end
	wipe(shot.hidden)
	if ok == nil then return end
	shot.taken = ok and time() or shot.taken
	local text
	if ok then
		local clock = A.Fmt and A.Fmt.Clock and A.Fmt.Clock(time()) or ""
		text = (L["Taken at %s. You find it in the Screenshots folder of your game."]):format(clock)
	else
		text = L["The game could not save it. Try your own screenshot key."]
	end
	local key = M.ScreenshotKey()
	if key then text = text .. "\n" .. (L["Your screenshot key: %s."]):format(key) end
	M:Push({ kind = "screenshot", always = true, now = true, title = ok and L["Screenshot taken"] or L["No screenshot"],
		text = text, icon = M.ICON.screenshot, seconds = 4, key = "journal-screenshot" })
end
M.EndShot = EndShot

shotEvents:SetScript("OnEvent", function(_, event)
	EndShot(event == "SCREENSHOT_SUCCEEDED")
end)

function M:Screenshot(hide)
	local take = rawget(_G, "Screenshot")
	if type(take) ~= "function" or shot.pending then return false end
	shot.pending = true
	local frames = type(hide) == "table" and hide.GetObjectType and { hide } or (type(hide) == "table" and hide or {})
	for _, frame in ipairs(frames) do
		if type(frame) == "table" and frame.SetAlpha and frame.GetAlpha and not shot.hidden[frame] then
			shot.hidden[frame] = frame:GetAlpha()
			frame:SetAlpha(0)
		end
	end
	shotEvents:RegisterEvent("SCREENSHOT_SUCCEEDED")
	shotEvents:RegisterEvent("SCREENSHOT_FAILED")
	shot.timer = C_Timer.NewTimer(M.SCREENSHOT_WAIT, function()
		shot.timer = nil
		EndShot(nil)
	end)
	-- The game takes it from the next frame it draws, without what was hidden
	-- above; the hidden frames come back when it reports.
	if not pcall(take) then EndShot(false) end
	return true
end

function M:ScreenshotPending()
	return shot.pending
end

---------------------------------------------------------------------------
-- Options rows for the "Moments and sounds" tab (Options.lua places them;
-- every row has a desc).
---------------------------------------------------------------------------
A.MomentOptions = {
	{ type = "toggle", key = "moments", label = "Enable", desc = "Cards for new places, level summaries, first dungeons, keepsakes, and goals. Reminders show even with this off." },
	{ type = "range", unit = "s", key = "momentSeconds", label = "Moments stay", desc = "Seconds a moment stays on screen.", min = 2, max = 12, step = 0.5 },
	{ type = "range", unit = "s", key = "reminderSeconds", label = "Reminders stay", desc = "Seconds a reminder stays on screen.", min = 3, max = 20, step = 1 },
	{ type = "select", key = "momentsInDungeons", label = "Moments in dungeons", desc = "Show them as they happen, or hold them and show one summary when you leave.",
		values = { now = "As they happen", after = "One summary when you leave" } },
	{ type = "toggle", key = "momentFanfare", label = "Moments in Fanfare", desc = "Fanfare's \"Journal moment\" triggers play or show with each moment. While such a trigger, or a level-up or boss-kill trigger, has a sound, the moment plays none of its own, so you hear one sound." },
	{ type = "toggle", key = "soundMaster", label = "Play when game effects are muted", desc = "Plays moment sounds on the Master channel." },
	{ type = "toggle", key = "screenshotButton", label = "Camera button on moments", desc = "A button on keepsake and level moments. A click closes the card and takes a screenshot without it. Nothing is taken by itself." },
	{ type = "execute", label = "Show a sample moment", desc = "Shows a level moment the way it looks with your settings.", func = function() M:Sample() end },
}

---------------------------------------------------------------------------
-- Part
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
M.events = events
events:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_REGEN_ENABLED" then
		M:FlushCombat()
	elseif event == "PLAYER_LEVEL_UP" then
		M:OnLevelUp(...)
	else
		C_Timer.After(1, function() if A.started then M:CheckDoor() end end)
	end
end)

A:AddPart("moments", {
	order = 35,
	start = function()
		CreateAnchor()
		M.mover:Show()
		state.quietUntil = GetTime() + M.QUIET_SECONDS
		state.dungeon = nil
		local name = InDungeon()
		if name then state.dungeon = { name = name, bosses = 0, firsts = 0, keepsakes = 0, goals = 0, levels = 0, held = 0 } end
		for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
			events:RegisterEvent(event)
		end
		if J.RegisterCallback then
			J.RegisterCallback(M, "Logged", function(_, charKey, row)
				if charKey == E.charKey then M:OnRow(row) end
			end)
			J.RegisterCallback(M, "Brief", function(_, kind, brief) M:OnBrief(kind, brief) end)
			J.RegisterCallback(M, "BriefEnd", function(_, kind) M:OnBriefEnd(kind) end)
		end
	end,
	stop = function()
		events:UnregisterAllEvents()
		EndShot(nil)
		if J.UnregisterCallback then
			J.UnregisterCallback(M, "Logged")
			J.UnregisterCallback(M, "Brief")
			J.UnregisterCallback(M, "BriefEnd")
		end
		wipe(state.combat)
		wipe(cardQueue)
		state.dungeon = nil
		CloseOwn(true)
		if M.mover then M.mover:Hide() end
	end,
})
