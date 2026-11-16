-- EldoUI Integrations: layouts place the windows of other popular addons.
--
-- Details! (meter windows 1 and 2), RestedXP guides (RXPFrame), BigWigs
-- (bars, emphasized bars, messages, countdown) and Questie (its quest tracker) each get
-- a "proxy mover": an invisible EldoUI frame with a mover, so layout presets,
-- move mode and the Positions page place them like any EldoUI frame. The
-- addon's own window is then put on the proxy through that addon's public
-- functions or its global frame, out of combat. When the player drags the
-- addon's own window instead, the mover follows (both ways).
--
-- Rules for this file:
--   * Every addon has its own switch and only does anything while that
--     addon is loaded. EldoUI never copies or changes their code, and never
--     writes their saved settings except where noted (Questie's grow corner,
--     its own option).
--   * Details and Questie windows hold secure buttons, so every move runs
--     through E:RunOutOfCombat (Queue below).
--   * Nothing here reads combat data; it only moves and frames windows.
--   * A change to another addon's own settings (RestedXP's step card,
--     Questie's grow corner, Guidelime's window spot) happens only when the
--     player applies it, keeps every value it writes as it was before, and
--     has an Undo (section "Changes to a companion's own settings").
--   * Another addon's first-run window (a welcome window, a first choice)
--     is never hidden, clicked or answered: the EldoUI setup waits for it
--     (section "First-run windows of the companions").
--   * One exception to "never changes their code": on a client in another
--     language, "Fit RestedXP to this game language" wraps a few RestedXP
--     functions so its English paid guides work there
--     (Modules/IntegrationsRXPLocale.lua, which says what and why).
--
-- Checked against these releases for WoW: Forever 1.60.1:
--   Details! Damage Meter  Details.20261107.15402.172
--   RestedXP Guides        v4.11.26 (the classic guide and the beta guide window)
--   BigWigs                v427.6
--   Questie                12.1.0 with QuestieDB 1.0.6
--   Guidelime              6.008
-- A newer release keeps working as long as the calls named in each
-- section are still there; a missing one leaves that addon alone.
local _, E = ...
local L = E.L

local Key = E.Key
local M = E:NewModule("Integrations", {
	title = "Integrations",
	desc = "Layouts place Details!, RestedXP guides, BigWigs bars and Questie's tracker, with an EldoUI look where the addon allows it.",
	category = "Interface",
	frames = {
		"EldoUI_Details1", "EldoUI_Details2", "EldoUI_BigWigsBars", "EldoUI_BigWigsEmphasize",
		"EldoUI_BigWigsMessages", "EldoUI_BigWigsCountdown", "EldoUI_RXP", "EldoUI_Questie",
	},
	movers = {
		"EldoUI_Details1", "EldoUI_Details2", "EldoUI_BigWigsBars", "EldoUI_BigWigsEmphasize",
		"EldoUI_BigWigsMessages", "EldoUI_BigWigsCountdown", "EldoUI_RXP", "EldoUI_Questie",
	},
	blizzard = {},
	savedKeys = { "profile.modules.Integrations", "EldoUIDB.companionChanges" },
	optionsPage = "module:Integrations",
	presets = { "Full", "Glass", "Off", "Positions", "Stacked" },
	reload = false,
	defaults = {
		details = {
			enabled = true,
			move = true,        -- put the windows on the EldoUI_Details movers
			window2 = false,    -- also place window 2 (stacked meters)
			size = false,       -- set the window size from EldoUI (else Details keeps its own)
			width = 440, height = 240,
			width2 = 440, height2 = 240,
			titleHeight = 20,   -- Details' title bar sits above its window frame
			skin = true,        -- EldoUI panel around the windows
			transparent = false,
			padding = 2,
		},
		rxp = {
			enabled = true,
			move = true,
			theme = true,       -- offer an "EldoUI" theme in RXP's theme list
			cardDown = true,    -- the step card opens under the guide on a spot in the top half
			locale = true,      -- fit RestedXP to a client in another language (IntegrationsRXPLocale.lua)
		},
		bigwigs = {
			enabled = true,
			barsWidth = 220, barsHeight = 160,
			emphWidth = 260, emphHeight = 120,
			messages = true,
			countdown = true,   -- mover for the pull/encounter countdown
			resend = true,      -- offer to send the anchors again after a layout click
			style = true,       -- the profile picks the "EldoUI" bar style
			timing = true,      -- the profile carries the role's timing and bar counts
			-- previousProfile: the BigWigs profile in use before the first EldoUI
			-- import, for "Restore my previous BigWigs profile"
		},
		questie = {
			enabled = true,
			move = true,
			corner = true,      -- set Questie's grow corner to match the layout
			width = 260, height = 400,
		},
	},
})

local ADDONS = {
	details = "Details",
	rxp = "RXPGuides",
	bigwigs = "BigWigs",
	questie = "Questie",
}

M.proxies = {}
M.rxpHooks = setmetatable({}, { __mode = "k" }) -- guide windows hooked once each
local queued = {}
local early = {} -- proxy frames created at file load (BigWigs), see below

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Round(value) return math.floor(value + 0.5) end

local function Loaded(key)
	return C_AddOns.IsAddOnLoaded(ADDONS[key]) and true or false
end

-- The integration is switched on, its addon is loaded and the module runs.
function M:On(key)
	return self.active and self.db[key].enabled and Loaded(key)
end

-- Runs fn now, or once after combat. A placement started by a pull (the
-- player dragged the other addon's window) is skipped, so the two sides
-- never fight.
local function Queue(key, fn)
	if M.pulling then return end
	if not InCombatLockdown() then
		fn()
		return
	end
	if queued[key] then return end
	queued[key] = true
	E:RunOutOfCombat(function()
		queued[key] = nil
		fn()
	end)
end

local function Run(fn)
	local ok, err = pcall(fn)
	if not ok then geterrorhandler()(err) end
end

-- A frame's rectangle in UIParent units, and its scale relative to UIParent.
-- GetRect and GetEffectiveScale can be secret on Forever: a secret answer
-- (or none) leaves the window alone (the addon fit's read, Core/AddonFit.lua).
local function RectOf(frame)
	return E.addonFit.RectOf(frame)
end

local function Usable(frame)
	return type(frame) == "table" and type(frame.GetObjectType) == "function"
		and not E.FrameCheck(frame, "IsForbidden")
end

-- Creates (once) the invisible proxy frame and its mover. The proxy has a
-- global name, so other addons (BigWigs) can anchor to it by name.
function M:Proxy(name, title, width, height, defaultPoint, opts)
	local proxy = self.proxies[name]
	if proxy then
		proxy:Show()
		if E.movers[name] then E.movers[name]:Show() end
		return proxy
	end
	proxy = early[name] or CreateFrame("Frame", name, UIParent)
	proxy:SetSize(width, height)
	proxy:EnableMouse(false)
	self.proxies[name] = proxy
	local previous = E.currentModule
	E.currentModule = self -- tag the mover with this module for exports
	E:CreateMover(proxy, name, title, defaultPoint, opts)
	E.currentModule = previous
	return proxy
end

-- An integration that is off (or its addon gone) hides its proxy and mover,
-- so move mode shows no empty box for it.
function M:HideProxy(name)
	if self.proxies[name] then self.proxies[name]:Hide() end
	if E.movers[name] then E.movers[name]:Hide() end
end

local function SetProxySize(name, width, height)
	local proxy = M.proxies[name]
	if proxy and width and height and width > 1 and height > 1 then
		proxy:SetSize(Round(width), Round(height))
	end
end

-- Saves the mover so that its `corner` sits at (x, y) in UIParent units.
local function PullCorner(name, corner, x, y)
	local mover = E.movers[name]
	if not mover then return end
	local width, height = mover:GetSize()
	local left = corner:find("LEFT") and x or (x - width)
	local bottom = corner:find("BOTTOM") and y or (y - height)
	M.pulling = true
	E:SaveMoverFromRect(name, left, bottom)
	M.pulling = false
end

---------------------------------------------------------------------------
-- Changes to a companion's own settings
---------------------------------------------------------------------------
-- EldoUI writes another addon's settings only when the player applies a
-- change, never on its own. Each change (M.changes, filled by the sections
-- below) names:
--   title    what it does, in the player's words
--   Target() the table it writes in, the name of that addon's profile
--            the table belongs to and how many other characters share it
--   character true for a setting of this character only (no profile)
--   Wanted() field = value for every field it writes
--   labels   field = the setting's name, for the question before Apply
--   Describe(value), unset   optional: a value, and no value, in words
--   Refresh() optional: lets the addon show the new values
-- Before the first write the value of every field is kept as it was, or
-- marked as not set at all, per change and per profile of that addon, in
-- this account's saved data. Undo puts each one back. A field the player
-- changed in the other addon after the Apply is theirs: Undo leaves it and
-- says so. Applying again (a new layout) keeps the values from before the
-- very first Apply.
-- The title, the setting names and the unset text are given in English
-- and read in the language shown at the time.
local GuidelimeData, GuidelimeSpot, GuidelimePlaced
M.changes = setmetatable({}, { __newindex = function(changes, key, change)
	E:TranslateFields({ change }, "title", "unset")
	if type(change.labels) == "table" then E:TranslateValues(change.labels) end
	rawset(changes, key, change)
end })

E:RegisterStore("companionChanges", { owner = "Integrations",
	shape = "per change and per profile of the other addon: each field's value before EldoUI's Apply and the value it wrote" })

-- The only reader and writer of EldoUIDB.companionChanges.
local function ChangeStore(key, place, record)
	if type(EldoUIDB) ~= "table" then return nil end
	local all = type(EldoUIDB.companionChanges) == "table" and EldoUIDB.companionChanges or nil
	if record == nil then
		local list = all and all[key]
		return type(list) == "table" and type(list[place]) == "table" and list[place] or nil
	end
	all = all or {}
	EldoUIDB.companionChanges = all
	all[key] = type(all[key]) == "table" and all[key] or {}
	all[key][place] = record or nil
	if not next(all[key]) then all[key] = nil end
	if not next(all) then EldoUIDB.companionChanges = nil end
end
M.ChangeStore = ChangeStore

local function Same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in pairs(a) do
		if not Same(v, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

local function Copy(value)
	return type(value) == "table" and CopyTable(value) or value
end

-- The other addon's name, for messages.
local function ChangeAddon(change)
	return change and (change.addonTitle or ADDONS[change.addon]) or ""
end

-- The change's table, its place and the number of other characters on it.
local function ChangeTarget(change)
	if not change then return end
	if change.On then
		if not change.On() then return end
	elseif not M:On(change.addon) then
		return
	end
	local ok, target, place, shared = pcall(change.Target)
	if not ok or type(target) ~= "table" then return end
	-- A setting of this character only: kept under the character's name.
	if change.character then return target, E.charKey, 0 end
	return target, type(place) == "string" and place or "", tonumber(shared) or 0
end

-- What Apply would do now: { place, shared, applied, rows = { field,
-- label, from, to } } for every field whose value differs, or nil.
function M:ChangePlan(key)
	local change = self.changes[key]
	local target, place, shared = ChangeTarget(change)
	if not target then return nil end
	local ok, wanted = pcall(change.Wanted)
	if not ok or type(wanted) ~= "table" then return nil end
	local plan = { key = key, place = place, shared = shared, rows = {},
		applied = ChangeStore(key, place) ~= nil }
	for field, value in pairs(wanted) do
		local current = rawget(target, field)
		if not Same(current, value) then
			plan.rows[#plan.rows + 1] = { field = field, label = change.labels and change.labels[field] or field,
				from = Copy(current), to = Copy(value) }
		end
	end
	table.sort(plan.rows, function(a, b) return a.field < b.field end)
	return plan
end

-- True while an Apply of this change is kept for the profile in use.
function M:ChangeApplied(key)
	local _, place = ChangeTarget(self.changes[key])
	return place ~= nil and ChangeStore(key, place) ~= nil
end

local function Refresh(change)
	if type(change.Refresh) ~= "function" then return end
	local ok, err = pcall(change.Refresh)
	if not ok then geterrorhandler()(err) end
end

-- Writes the change. `seen` (optional) is the plan the player was shown:
-- when the other addon's values moved since, nothing is written and the
-- result is false, "stale". `quiet`: the caller shows the result itself
-- (no Refresh). Returns true when the values are in place.
function M:ApplyChange(key, seen, quiet)
	local change = self.changes[key]
	-- The other addon may move its windows in answer: after combat.
	if InCombatLockdown() then
		E:RunOutOfCombat(function() M:ApplyChange(key, seen, quiet) end)
		return false, "combat"
	end
	local plan = self:ChangePlan(key)
	if not plan then return false, "missing" end
	if seen then
		if seen.place ~= plan.place or #seen.rows ~= #plan.rows then return false, "stale" end
		for index, row in ipairs(plan.rows) do
			local was = seen.rows[index]
			if was.field ~= row.field or not Same(was.from, row.from) or not Same(was.to, row.to) then return false, "stale" end
		end
	end
	if #plan.rows == 0 and plan.applied then return true end
	local target = ChangeTarget(change)
	local record = ChangeStore(key, plan.place) or { fields = {} }
	record.at = time()
	record.shared = plan.shared
	for _, row in ipairs(plan.rows) do
		local kept = record.fields[row.field]
		if not kept then
			kept = { had = row.from ~= nil, before = Copy(row.from) }
			record.fields[row.field] = kept
		end
		kept.after = Copy(row.to)
		target[row.field] = Copy(row.to)
	end
	-- Fields already right count as EldoUI's from now on, so Undo knows
	-- what was there.
	local ok, wanted = pcall(change.Wanted)
	if ok and type(wanted) == "table" then
		for field, value in pairs(wanted) do
			if not record.fields[field] then
				local current = rawget(target, field)
				record.fields[field] = { had = current ~= nil, before = Copy(current), after = Copy(value) }
			end
		end
	end
	ChangeStore(key, plan.place, record)
	if not quiet then Refresh(change) end
	return true
end

-- Puts back every field the Apply wrote, unless the player changed it in
-- the other addon since. Returns true and the labels of the fields kept.
function M:UndoChange(key)
	local change = self.changes[key]
	if InCombatLockdown() then
		E:RunOutOfCombat(function() M:UndoChange(key) end)
		return false, "combat"
	end
	local target, place = ChangeTarget(change)
	if not target then return false, "missing" end
	local record = ChangeStore(key, place)
	if not record then return false, "none" end
	if key == "guidelime" and GuidelimePlaced and GuidelimePlaced() then self.stepGuideSessionOnSpot = true end
	local kept = {}
	for field, saved in pairs(record.fields or {}) do
		if Same(rawget(target, field), saved.after) then
			if saved.had then target[field] = Copy(saved.before) else target[field] = nil end
		else
			kept[#kept + 1] = change.labels and change.labels[field] or field
		end
	end
	table.sort(kept)
	ChangeStore(key, place, false)
	Refresh(change)
	return true, kept
end

-- For the options page: the change can be shown (its addon and table are
-- there), offered (Apply would change something), and its state in words.
function M:ChangeShown(key)
	return self:ChangePlan(key) ~= nil
end

function M:ChangeOffered(key)
	local plan = self:ChangePlan(key)
	return plan ~= nil and #plan.rows > 0
end

function M:ChangeStatus(key)
	local change = self.changes[key]
	local plan = self:ChangePlan(key)
	if not plan then return "" end
	local addon = ChangeAddon(change)
	if plan.applied then
		if change.character then return L["Changed by EldoUI for this character. Undo puts the earlier values back."] end
		return L["Changed by EldoUI in the %s profile \"%s\". Undo puts the earlier values back."]:format(addon, plan.place)
	end
	if #plan.rows == 0 then return L["%s is set like this already."]:format(addon) end
	return L["%s keeps its own setting: EldoUI changes nothing until you apply."]:format(addon)
end

-- Where the change lands, in words: this character, or a profile of the
-- other addon and how many other characters share it.
function M:ChangeScope(change, plan)
	if change.character then return L["This changes the setting for this character only."] end
	if plan.shared > 0 then
		return E:Plural(plan.shared, "This changes the profile \"%s\", which %d other character uses too.",
			"This changes the profile \"%s\", which %d other characters use too."):format(plan.place, plan.shared)
	end
	return L["This changes the profile \"%s\"."]:format(plan.place)
end

-- The question before Apply: what changes, where, and for whom.
function M:ChangeQuestion(plan)
	local change = self.changes[plan.key]
	local lines = {}
	for _, row in ipairs(plan.rows) do
		local describe = change.Describe or tostring
		lines[#lines + 1] = L["%s: from %s to %s"]:format(row.label, row.from == nil and (change.unset or L["not set (the addon's default)"]) or describe(row.from), describe(row.to))
	end
	lines[#lines + 1] = M:ChangeScope(change, plan)
	lines[#lines + 1] = L["Undo on this page puts every value back as it was."]
	return table.concat(lines, "\n")
end

-- The Apply button: asks first, then applies what it showed.
function M:AskApplyChange(key)
	local change = self.changes[key]
	local plan = change and self:ChangePlan(key)
	if not plan then
		self:Print(L["%s is not loaded, or this integration is off."]:format(ChangeAddon(change)))
		return
	end
	if #plan.rows == 0 then
		self:Print(L["%s is set like this already."]:format(ChangeAddon(change)))
		return
	end
	E:ShowConfirm({
		key = "EldoUI_CompanionChange",
		title = change.title,
		text = self:ChangeQuestion(plan),
		accept = L["Apply"],
		onAccept = function()
			local ok, why = M:ApplyChange(key, plan)
			if ok then
				M:Print(L["%s: done. Undo on the Integrations page puts it back."]:format(change.title))
			elseif why == "stale" then
				M:Print(L["%s changed in the meantime, so nothing was changed. Look at the new values and apply again."]:format(ChangeAddon(change)))
			elseif why == "combat" then
				M:Print(L["%s: applied when combat ends."]:format(change.title))
			end
			if E.RefreshConfig then E:RefreshConfig() end
		end,
	})
end

function M:UndoChangeAndSay(key)
	local change = self.changes[key]
	local ok, kept = self:UndoChange(key)
	if ok then
		if #kept > 0 then
			self:Print(L["%s: undone. You changed %s yourself since, so that stays as you set it."]:format(change.title, table.concat(kept, ", ")))
		else
			self:Print(L["%s: undone, every value is back as it was."]:format(change.title))
		end
	elseif kept == "combat" then
		self:Print(L["%s: undone when combat ends."]:format(change.title))
	else
		self:Print(L["EldoUI has nothing to undo here."])
	end
	if E.RefreshConfig then E:RefreshConfig() end
	return ok
end

---------------------------------------------------------------------------
-- Movers, by the mover family rule (Core/Movers.lua): one per Details!
-- window (EldoUI_Details1, EldoUI_Details2) and one per boss-mod zone
-- (EldoUI_BigWigsBars, ...Emphasize, ...Messages, ...Countdown). The
-- RestedXP guide and the Questie tracker have one mover each.
---------------------------------------------------------------------------
local DETAILS_BASE, BIGWIGS_BASE = "EldoUI_Details", "EldoUI_BigWigs"
E:RegisterMoverFamily(DETAILS_BASE, { module = "Integrations", slots = 2 })
E:RegisterMoverFamily(BIGWIGS_BASE, { module = "Integrations", keys = { "Bars", "Emphasize", "Messages", "Countdown" } })

---------------------------------------------------------------------------
-- Details! Damage Meter: windows 1 and 2 on EldoUI_Details1 / 2
---------------------------------------------------------------------------
local DETAILS = {
	{ name = E:MoverFamilyName(DETAILS_BASE, 1), title = "Details! Window 1", alias = "EldoUI_Details",
		point = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -19, 19 } },
	{ name = E:MoverFamilyName(DETAILS_BASE, 2), title = "Details! Window 2",
		point = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -19, 267 } },
}

local function DetailsAddon()
	local details = _G.Details
	if type(details) == "table" and type(details.GetWindow) == "function" then return details end
end

-- Details' window object, only while it exists and is open.
local function DetailsWindow(id)
	local details = DetailsAddon()
	if not details then return end
	local ok, window = pcall(details.GetWindow, details, id)
	if not ok or type(window) ~= "table" or not Usable(window.baseframe) then return end
	if type(window.IsEnabled) == "function" then
		local okEnabled, enabled = pcall(window.IsEnabled, window)
		if okEnabled and not enabled then return end
	end
	return window
end

local function DetailsScale(window)
	local scale = tonumber(window.window_scale) or 1
	return scale > 0 and scale or 1
end

function M:DetailsWanted(id)
	return self:On("details") and self.db.details.move and (id == 1 or self.db.details.window2)
end

-- The proxy is the visible box: Details' frame plus its title bar.
function M:SizeDetailsProxy(id)
	local cfg = self.db.details
	if cfg.size then
		if id == 1 then
			SetProxySize(DETAILS[id].name, cfg.width, cfg.height)
		else
			SetProxySize(DETAILS[id].name, cfg.width2, cfg.height2)
		end
		return
	end
	local window = DetailsWindow(id)
	if not window then return end
	local _, _, width, height = RectOf(window.baseframe)
	if width then SetProxySize(DETAILS[id].name, width, height + cfg.titleHeight) end
end

function M:PlaceDetails(id)
	if not self:DetailsWanted(id) then return end
	local def = DETAILS[id]
	Queue(def.name, function()
		local window, mover = DetailsWindow(id), E.movers[def.name]
		if not (window and mover and M:DetailsWanted(id)) then return end
		M:SizeDetailsProxy(id)
		local left, right, top, bottom = mover:GetLeft(), mover:GetRight(), mover:GetTop(), mover:GetBottom()
		if not left then return end
		local width, height = right - left, top - bottom - M.db.details.titleHeight
		if height < 20 then height = top - bottom end
		local cx, cy = (left + right) / 2, bottom + height / 2
		local screenW, screenH = UIParent:GetSize()
		local scale = DetailsScale(window)
		M.placing = true
		-- Details' own restore: center offset from UIParent's center and the
		-- size in the window's own units; it saves the spot in its profile.
		Run(function()
			window:RestoreMainWindowPosition({ x = cx - screenW / 2, y = cy - screenH / 2,
				largura = width / scale, altura = height / scale })
			window:SaveMainWindowPosition()
		end)
		M.placing = false
		M:SkinDetails(id)
	end)
end

-- The player dragged or resized Details' own window: the mover follows.
function M:PullDetails(id)
	if not self:DetailsWanted(id) then return end
	if InCombatLockdown() then
		E:RunOutOfCombat(function() M:PullDetails(id) end)
		return
	end
	local window = DetailsWindow(id)
	if not window then return end
	local left, bottom, width, height = RectOf(window.baseframe)
	if not left then return end
	local cfg = self.db.details
	if cfg.size then
		if id == 1 then
			cfg.width, cfg.height = Round(width), Round(height + cfg.titleHeight)
		else
			cfg.width2, cfg.height2 = Round(width), Round(height + cfg.titleHeight)
		end
	end
	self.pulling = true
	SetProxySize(DETAILS[id].name, width, height + cfg.titleHeight)
	E:SaveMoverFromRect(DETAILS[id].name, left, bottom)
	self.pulling = false
	self:SkinDetails(id)
end

-- A window counts as moved when it no longer sits on its mover's box (the
-- box is the window plus its title bar on top).
local function DetailsMoved(id)
	local window, mover = DetailsWindow(id), E.movers[DETAILS[id].name]
	if not (window and mover) then return false end
	local left, bottom, width, height = RectOf(window.baseframe)
	local boxLeft, boxBottom, boxWidth, boxHeight = RectOf(mover)
	if not (left and boxLeft) then return false end
	height = height + M.db.details.titleHeight
	return math.abs(left - boxLeft) > 0.5 or math.abs(bottom - boxBottom) > 0.5
		or math.abs(width - boxWidth) > 0.5 or math.abs(height - boxHeight) > 0.5
end

-- Details' windows can be snapped into a group: dragging or resizing one
-- moves or sizes the others along, but only the one in hand ends with
-- StopMovingOrSizing. held is that window; every other window's mover
-- follows when its window moved with it, so a reload keeps the group
-- together, and a window that stayed keeps its layout spot.
function M:PullAllDetails(held)
	if self.placing then return end
	for id = 1, #DETAILS do
		if id == held or DetailsMoved(id) then self:PullDetails(id) end
	end
end

function M:HookDetails(id)
	local window = DetailsWindow(id)
	if not window then return end
	local base = window.baseframe
	self.hookedFrames = self.hookedFrames or {}
	if self.hookedFrames[base] then return end
	self.hookedFrames[base] = true
	-- Details ends its own drag and resize with StopMovingOrSizing, then
	-- snaps and saves; read the result a moment later.
	hooksecurefunc(base, "StopMovingOrSizing", function()
		if M.placing then return end
		C_Timer.After(0.1, function() M:PullAllDetails(id) end)
	end)
end

-- An EldoUI panel behind the window and its title bar. It is our own frame
-- parented to Details' window, so it shows and hides with it.
M.borders = {}

function M:SkinDetails(id)
	local cfg = self.db.details
	if not (self:On("details") and cfg.skin) then
		for _, border in pairs(self.borders) do border:Hide() end
		return
	end
	local window = DetailsWindow(id)
	if not window then return end
	local base = window.baseframe
	local border = self.borders[base]
	if not border then
		border = CreateFrame("Frame", nil, base)
		border:EnableMouse(false)
		self.borders[base] = border
	end
	-- The border lives in the window's scale; convert UIParent units.
	local effective = E.PlainCall(base.GetEffectiveScale, base)
	local scale = type(effective) == "number" and effective / UIParent:GetEffectiveScale() or 1
	if scale <= 0 then scale = 1 end
	local pad, title = cfg.padding / scale, cfg.titleHeight / scale
	border:ClearAllPoints()
	border:SetPoint("TOPLEFT", base, "TOPLEFT", -pad, title + pad)
	border:SetPoint("BOTTOMRIGHT", base, "BOTTOMRIGHT", pad, -pad)
	border:SetFrameStrata(base:GetFrameStrata())
	border:SetFrameLevel(math.max(0, base:GetFrameLevel() - 1))
	E:SetPanelTemplate(border, cfg.transparent)
	border:Show()
end

function M:RefreshDetails()
	for id = 1, #DETAILS do
		if self:DetailsWanted(id) then
			self:HookDetails(id)
			self:PlaceDetails(id)
		end
		self:SkinDetails(id)
	end
end

function M:SetupDetails()
	if not self:On("details") then
		for _, def in ipairs(DETAILS) do
			self:HideProxy(def.name)
		end
		return
	end
	local cfg = self.db.details
	for id, def in ipairs(DETAILS) do
		if self:DetailsWanted(id) then
			local width = id == 1 and cfg.width or cfg.width2
			local height = id == 1 and cfg.height or cfg.height2
			-- "Match size" in move mode while EldoUI sets the window size.
			local suffix = id == 1 and "" or tostring(id)
			local function SizeKey(axis, min, max)
				return function() return M.db.details.size and { key = "details." .. axis .. suffix, min = min, max = max } or nil end
			end
			self:Proxy(def.name, def.title, width, height, def.point, {
				layoutAlias = def.alias,
				onMoved = function() M:PlaceDetails(id) end,
				sizeKeys = { width = SizeKey("width", 150, 800), height = SizeKey("height", 80, 600) },
			})
		elseif self.proxies[def.name] then
			self:HideProxy(def.name)
		end
	end
	-- Details' own event bus: after it starts, opens a window or applies a
	-- profile (an imported profile carries the exporter's positions).
	local details = DetailsAddon()
	if details and not self.detailsListener and type(details.CreateEventListener) == "function" then
		local ok, listener = pcall(details.CreateEventListener, details)
		if ok and type(listener) == "table" and type(listener.RegisterEvent) == "function" then
			self.detailsListener = listener
			local function Later()
				C_Timer.After(0.5, function() M:RefreshDetails() end)
			end
			for _, event in ipairs({ "DETAILS_STARTED", "DETAILS_INSTANCE_OPEN", "DETAILS_PROFILE_APPLYED" }) do
				pcall(listener.RegisterEvent, listener, event, Later)
			end
			-- A window sized along with its group gets no StopMovingOrSizing.
			local function Pull()
				if M.placing then return end
				C_Timer.After(0.1, function() M:PullAllDetails() end)
			end
			for _, event in ipairs({ "DETAILS_INSTANCE_ENDRESIZE", "DETAILS_INSTANCE_SIZECHANGED" }) do
				pcall(listener.RegisterEvent, listener, event, Pull)
			end
		end
	end
	C_Timer.After(1, function() M:RefreshDetails() end)
end

---------------------------------------------------------------------------
-- RestedXP Guides: RXPFrame on EldoUI_RXP, and an "EldoUI" theme
---------------------------------------------------------------------------
-- RestedXP's beta guide window (its "new interface" option, off unless the
-- player turns it on in RestedXP) is a window of its own, with its own
-- saved spot: the global RXPV2GuideWindow is the widget and its `frame`
-- the window. Its current steps sit in another widget, named
-- "RXPActiveStepsFrame" plus the character's name, attached above or under
-- the window. EldoUI never turns that option on and never builds either
-- window; it places the window once RestedXP has made it.
local function WidgetFrame(widget)
	if Usable(widget) then return widget end
	local frame = type(widget) == "table" and widget.frame
	if Usable(frame) then return frame end
end

function M.RXPBetaWindow()
	return WidgetFrame(_G.RXPV2GuideWindow)
end

local function RXPBetaSteps(window)
	local name = UnitName("player")
	local steps = type(name) == "string" and WidgetFrame(_G["RXPActiveStepsFrame" .. name])
	if not (steps and steps:IsShown() and steps.GetPoint) then return end
	-- Only while it hangs on the window (RestedXP can also keep it apart).
	local _, relative = steps:GetPoint(1)
	if relative == window then return steps end
end

-- The guide window EldoUI places: the beta window while RestedXP uses it,
-- else the classic one (RXPFrame).
local function RXPWindow()
	local beta = M.RXPBetaWindow()
	if beta then return beta, true end
	local frame = _G.RXPFrame
	if Usable(frame) then return frame, false end
end

---------------------------------------------------------------------------
-- The guide provider: one leveling guide on the layout's guide spot
---------------------------------------------------------------------------
-- The player picks one provider, on Eldostar's options page or in the
-- setup's Other addons step; the pick is kept in Eldostar's settings
-- (`provider`) and read here, where the guide spot is owned:
--   auto      an enabled RestedXP wins, else Eldostar
--   eldostar  Eldostar, EldoUI's own guide window
--   rxp       RestedXP (placed while its integration places it)
--   guidelime Guidelime (its saved spot is applied explicitly, for reload)
--   off       no guide on the spot
-- An explicit pick stays as the player made it: a RestedXP installed or
-- removed later changes only what Automatic picks. EldoUI never hides or
-- turns off the guide addon it did not pick; it only stops placing it,
-- and the status texts below say so.
--   E:GuideProviderChoice()  the saved pick ("auto" when none)
--   E:GuideProvider()        the selected, available guide, or nil (nobody)
--   E:GuideProviderChanged() every guide owner follows a new pick
--   E:GuideProviderStatus()  one line on what the pick does right now
local GUIDE_CHOICES = { auto = true, eldostar = true, rxp = true, guidelime = true, off = true }
E.GUIDE_PROVIDER_ORDER = { "auto", "eldostar", "rxp", "guidelime", "off" }
E.GUIDE_PROVIDER_TITLES = {
	auto = Key("Automatic"), eldostar = Key("Eldostar"), rxp = Key("RestedXP"), off = Key("Off"),
	guidelime = Key("Guidelime"),
}
E.GUIDE_PROVIDER_DESCS = {
	auto = Key("RestedXP when it is installed and on, else Eldostar."),
	eldostar = Key("Eldostar, EldoUI's own guide window."),
	rxp = Key("RestedXP, placed on the guide spot by the layout."),
	guidelime = Key("Guidelime; Apply on the Other addons step saves its guide spot for the next reload."),
	off = Key("No guide on the guide spot."),
}
-- The provider row on Eldostar's page and in the setup.
E.GUIDE_PROVIDER_ROW_DESC = Key("Which leveling guide takes the layout's guide spot. Automatic: RestedXP when it is installed and on, else Eldostar. EldoUI never turns the other guide addon off: it only stops placing it.")

local function EldostarModule()
	local module = E.modules.Eldostar
	if module and type(module.db) == "table" then return module end
end

-- RestedXP is usable while it is loaded (an addon switched off in the
-- addon list never loads).
function E:RestedXPUsable()
	return C_AddOns.IsAddOnLoaded("RXPGuides") and true or false
end

function E:GuideProviderChoice()
	local module = EldostarModule()
	local choice = module and module.db.provider
	return GUIDE_CHOICES[choice] and choice or "auto"
end

local function WantedGuideProvider()
	local choice = E:GuideProviderChoice()
	if choice == "off" then return nil end
	if choice == "guidelime" then return C_AddOns.IsAddOnLoaded("Guidelime") and "guidelime" or nil end
	local rxp = E:RestedXPUsable()
	if choice == "rxp" then return rxp and "rxp" or nil end
	local module = EldostarModule()
	local eldostar = module and module:IsEnabled() and true or false
	if choice == "eldostar" then return eldostar and "eldostar" or nil end
	if rxp then return "rxp" end
	return eldostar and "eldostar" or nil
end

function E:GuideProvider()
	if M.guideReloadPending or M.rxpReleaseBlocked or M.rxpAnchorWrite then return nil end
	return WantedGuideProvider()
end

function E:GuideProviderChanged()
	M.guideChangeSerial = (M.guideChangeSerial or 0) + 1
	if M.UpdateGuideHandoff then M:UpdateGuideHandoff() end
	if M.active then
		local ok, err = pcall(M.SetupRXP, M)
		if not ok then geterrorhandler()(err) end
	end
	local module = EldostarModule()
	if module and module.UpdateProvider then
		local ok, err = pcall(module.UpdateProvider, module)
		if not ok then geterrorhandler()(err) end
	end
end

-- What the pick does right now, in one or two lines (Eldostar's page, the
-- RestedXP tab and the setup step).
function E:GuideProviderStatus(choice)
	choice = GUIDE_CHOICES[choice] and choice or self:GuideProviderChoice()
	if M.guideReloadPending then return L["Reload to finish changing the guide on the guide spot. Guidelime keeps its open window until then."] end
	if M.rxpReleaseBlocked then return L["The previous guide placement is waiting to be released safely."] end
	if choice == "guidelime" then
		if not C_AddOns.IsAddOnLoaded("Guidelime") then return L["Guidelime is not loaded, so no guide is placed until it is."] end
		if GuidelimePlaced and GuidelimePlaced() then return L["Guidelime is selected. Its saved guide spot takes effect after a reload."] end
		return L["Guidelime is selected. Apply its placement on the Other addons step, then reload to use the guide spot."]
	end
	local rxp = self:RestedXPUsable()
	local module = EldostarModule()
	local eldostarOn = module and module:IsEnabled()
	if choice == "off" then
		if rxp then return L["No guide on the guide spot. RestedXP stays on and keeps its own spot."] end
		return L["No guide on the guide spot."]
	end
	if choice == "rxp" then
		if rxp then return L["RestedXP is your guide. Eldostar stays off."] end
		return L["RestedXP is not loaded, so no guide shows until it is."]
	end
	if choice == "eldostar" then
		if not eldostarOn then return L["Eldostar is switched off on the Modules page, so no guide shows."] end
		if rxp then return L["Eldostar is your guide. RestedXP stays on and keeps its own spot: EldoUI does not place it."] end
		return L["Eldostar is your guide."]
	end
	if rxp then return L["RestedXP is installed and on, so Automatic uses RestedXP. Eldostar stays off."] end
	if not eldostarOn then return L["Eldostar is switched off on the Modules page, so no guide shows."] end
	return L["RestedXP is not loaded, so Automatic uses Eldostar."]
end

function M:RXPWanted()
	return self:On("rxp") and self.db.rxp.move and E:GuideProvider() == "rxp"
end

-- Only anchor points are managed here. A later drag or another owner's anchor change
-- is kept; neither the foreign window's size nor its visibility is owned here.
local rxpPlacements = setmetatable({}, { __mode = "k" })
local function RXPPoints(frame)
	if not Usable(frame) then return end
	local count = E.PlainCall(frame.GetNumPoints, frame)
	if type(count) ~= "number" or count < 0 or count > 32 or count ~= math.floor(count) then return end
	local ok, parent = pcall(frame.GetParent, frame)
	if not ok or E:IsSecret(parent) then return end
	local result = { parent = parent, points = {} }
	for index = 1, count do
		local good, point, relative, relativePoint, x, y = pcall(frame.GetPoint, frame, index)
		if not good or E:IsSecret(point) or E:IsSecret(relative) or E:IsSecret(relativePoint) or E:IsSecret(x) or E:IsSecret(y)
			or type(point) ~= "string" or type(relativePoint) ~= "string" or type(x) ~= "number" or type(y) ~= "number"
			or x ~= x or y ~= y or math.abs(x) == math.huge or math.abs(y) == math.huge then return end
		result.points[index] = { point, relative, relativePoint, x, y }
	end
	return result
end

local function SameRXPPoints(a, b)
	if not a or not b or a.parent ~= b.parent or #a.points ~= #b.points then return false end
	for index, point in ipairs(a.points) do
		for field = 1, 5 do if point[field] ~= b.points[index][field] then return false end end
	end
	return true
end

local function RXPPlacementContext()
	return { profile = E.db, profileName = E.profileName, db = M.db, active = M.active,
		choice = E:GuideProviderChoice(), serial = M.guideChangeSerial,
		enabled = M.db.rxp.enabled, move = M.db.rxp.move }
end

local function SameRXPContext(context)
	return E.db == context.profile and E.profileName == context.profileName and M.db == context.db
		and M.active == context.active and E:GuideProviderChoice() == context.choice
		and M.guideChangeSerial == context.serial and M.db.rxp.enabled == context.enabled and M.db.rxp.move == context.move
end

function M:ReleaseRXPPlacement()
	if self.rxpAnchorWrite then self.rxpReleaseBlocked = true return end
	if not next(rxpPlacements) then self.rxpReleaseBlocked = nil return end
	if InCombatLockdown() then
		self.rxpReleaseBlocked = true
		Queue("RXP:release", function() M:ReleaseRXPPlacement(); E:GuideProviderChanged() end)
		return
	end
	local keep = WantedGuideProvider() == "rxp" and self:On("rxp") and self.db.rxp.move and RXPWindow() or nil
	self.rxpReleaseBlocked = nil
	local context = RXPPlacementContext()
	for frame, lease in pairs(rxpPlacements) do
		if frame ~= keep then
			local current = RXPPoints(frame)
			if not current or not lease.after then
				self.rxpReleaseBlocked = true
			else
				if SameRXPPoints(current, lease.after) then
					self.rxpAnchorWrite = true
					local expected = { parent = current.parent, points = {} }
					local complete = false
					local ok, err = pcall(function()
						frame:ClearAllPoints()
						local changed = RXPPoints(frame)
						if not SameRXPPoints(changed, expected) then return end
						lease.after = changed
						if not SameRXPContext(context) then return end
						for index, point in ipairs(lease.before.points) do
							frame:SetPoint(unpack(point, 1, 5))
							expected.points[index] = point
							changed = RXPPoints(frame)
							if not SameRXPPoints(changed, expected) then return end
							lease.after = changed
							if not SameRXPContext(context) then return end
						end
						complete = true
					end)
					self.rxpAnchorWrite = nil
					if not ok or not complete then
						self.rxpReleaseBlocked = true
						if not ok then error(err) end
						return
					end
				end
				rxpPlacements[frame] = nil
			end
		end
	end
end

-- The whole guide as the player sees it, in UIParent units: the guide
-- window plus the parts RXP attaches to it (the current step card above
-- or below it, Top or Bottom in RXP's settings). Returns left, bottom,
-- width, height of the union, the window's own left and top, and its
-- scale.
function M.RXPFootprint(frame)
	local fLeft, fBottom, fWidth, fHeight, scale = RectOf(frame)
	if not fLeft then return end
	local left, bottom, right, top = fLeft, fBottom, fLeft + fWidth, fBottom + fHeight
	local parts = { frame:GetChildren() }
	-- The beta window's current steps are a window of their own.
	parts[#parts + 1] = RXPBetaSteps(frame)
	for _, child in ipairs(parts) do
		if Usable(child) and child:IsShown() then
			local cLeft, cBottom, cWidth, cHeight = RectOf(child)
			if cLeft and cWidth > 1 and cHeight > 1 then
				left, bottom = math.min(left, cLeft), math.min(bottom, cBottom)
				right, top = math.max(right, cLeft + cWidth), math.max(top, cBottom + cHeight)
			end
		end
	end
	return left, bottom, right - left, top - bottom, fLeft, fBottom + fHeight, scale
end

-- Before the setup is done the game's own player frame may still sit on
-- the layout's guide spot. While a fresh profile waits for its setup and
-- the native player frame shows there, the guide goes just under that
-- frame instead. Only the guide moves: its mover keeps the layout's spot,
-- which the guide takes once the setup is finished or skipped.
-- left, top: where the guide's top-left corner would go; width, height:
-- its footprint. Returns the top to use instead, or nil. Every guide on
-- the guide spot uses it (Eldostar's window too).
M.RXP_GAP = 8 -- UI units between the player frame and the guide under it
function E:GuideSpotSafeTop(left, top, width, height)
	if not (E.db and E.db.needsSetup) then return nil end
	local player = _G.PlayerFrame
	if not (Usable(player) and player:IsVisible()) then return nil end
	local pLeft, pBottom, pWidth, pHeight = RectOf(player)
	if not pLeft then return nil end
	local bottom = top - height
	local overlaps = left < pLeft + pWidth and left + width > pLeft and bottom < pBottom + pHeight and top > pBottom
	if not overlaps then return nil end
	return pBottom - M.RXP_GAP
end

-- The step card on a guide spot in the top half of the screen. RestedXP
-- puts its current step card above the guide unless that runs off the top
-- of the screen; EldoUI places the whole guide inside its spot, so near
-- the top the card would always fit above it and the guide would open
-- upward. With "Step card under the guide near the top" on, a card above
-- the guide moves under it (the same points RestedXP's own Bottom choice
-- uses) whenever RestedXP lays it out. In the bottom half RestedXP's own
-- choice stays. Only the classic guide window; nothing is saved in
-- RestedXP's settings.
function M:FollowStepCard()
	local frame = _G.RXPFrame
	if not Usable(frame) or M.RXPBetaWindow() then return end
	local card = rawget(frame, "CurrentStepFrame")
	if not (Usable(card) and card.GetPoint) then return end
	local mover = E.movers.EldoUI_RXP
	local wanted = self:RXPWanted() and self.db.rxp.cardDown and mover
	local mTop, mBottom = wanted and mover:GetTop(), wanted and mover:GetBottom()
	local down = mTop and mBottom and (mTop + mBottom) / 2 > UIParent:GetHeight() / 2
	if not down then
		-- Switched off or moved to the bottom half: RestedXP lays it out again.
		if self.rxpCardDown then
			self.rxpCardDown = nil
			if type(frame.SetStepFrameAnchor) == "function" then frame.SetStepFrameAnchor() end
		end
		return
	end
	local _, relative, relativePoint = card:GetPoint(1)
	if relative == frame and relativePoint == "BOTTOMLEFT" then return end
	self.rxpCardDown = true
	card:ClearAllPoints()
	card:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 3, 0)
	card:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -3, 0)
	rawset(card, "anchor", "BOTTOM")
end

function M:PlaceRXP()
	if not self:RXPWanted() then
		self:FollowStepCard()
		return
	end
	Queue("EldoUI_RXP", function()
		local frame, mover = RXPWindow(), E.movers.EldoUI_RXP
		if not (frame and mover and M:RXPWanted()) then return end
		M:ReleaseRXPPlacement()
		if not M:RXPWanted() then return end
		M:FollowStepCard()
		local before = RXPPoints(frame)
		if not before then return end
		local lease = rxpPlacements[frame]
		if not lease or not SameRXPPoints(before, lease.after) then lease = { before = before } end
		-- The beta window may have come since the last time.
		M:HookRXP()
		local left, bottom, width, height, fLeft, fTop, scale = M.RXPFootprint(frame)
		if not left then return end
		SetProxySize("EldoUI_RXP", width, height)
		local x, top = mover:GetLeft(), mover:GetTop()
		if not x then return end
		local safe = E:GuideSpotSafeTop(x, top, width, height)
		M.rxpHeld = safe ~= nil
		top = safe or top
		-- The window's own corner sits inside the footprint (a step card
		-- above it pushes it down). Offsets are in the frame's own scale
		-- (RXP's window scale setting).
		x, top = x + (fLeft - left), top - ((bottom + height) - fTop)
		if not M:RXPWanted() then return end
		local context = RXPPlacementContext()
		local empty = { parent = before.parent, points = {} }
		lease.after = before
		rxpPlacements[frame] = lease
		M.rxpAnchorWrite = true
		local complete = false
		local ok, err = pcall(function()
			frame:ClearAllPoints()
			local cleared = RXPPoints(frame)
			if not SameRXPPoints(cleared, empty) then return end
			lease.after = cleared
			if not SameRXPContext(context) then return end
			local point = { "TOPLEFT", UIParent, "TOPLEFT", x / scale, (top - UIParent:GetHeight()) / scale }
			frame:SetPoint(unpack(point, 1, 5))
			local placed = RXPPoints(frame)
			if not SameRXPPoints(placed, { parent = before.parent, points = { point } }) then return end
			lease.after = placed
			if not SameRXPContext(context) then return end
			complete = true
		end)
		M.rxpAnchorWrite = nil
		if not complete then M.rxpReleaseBlocked = true end
		if not ok then error(err) end
	end)
end

function M:PullRXP()
	if not self:RXPWanted() or InCombatLockdown() then return end
	local frame = RXPWindow()
	if not frame then return end
	local left, bottom, width, height = M.RXPFootprint(frame)
	if not left then return end
	self.pulling = true
	SetProxySize("EldoUI_RXP", width, height)
	E:SaveMoverFromRect("EldoUI_RXP", left, bottom)
	self.pulling = false
	-- A drag into the top half turns the step card under the guide.
	if self.db.rxp.cardDown then
		local _, relative, relativePoint = (rawget(frame, "CurrentStepFrame") or frame):GetPoint(1)
		self:FollowStepCard()
		local _, now, nowPoint = (rawget(frame, "CurrentStepFrame") or frame):GetPoint(1)
		if now ~= relative or nowPoint ~= relativePoint then self:RefitRXP() end
	end
end

function M:RefitRXP()
	if self.rxpRefit or self.pulling or not self:RXPWanted() then return end
	-- A guide that keeps changing its shape in answer to being placed
	-- (near a screen edge RXP may flip the step card) is placed at most
	-- six times in two seconds.
	local now = GetTime()
	if not self.rxpRefitAt or now - self.rxpRefitAt > 2 then self.rxpRefitAt, self.rxpRefits = now, 0 end
	self.rxpRefits = self.rxpRefits + 1
	if self.rxpRefits > 6 then return end
	self.rxpRefit = true
	C_Timer.After(0.1, function()
		M.rxpRefit = nil
		M:PlaceRXP()
	end)
end

-- Hooks on the guide window, once per window (the beta window can come
-- after the classic one), and on RestedXP's step card switch.
function M:HookRXP()
	local frame = RXPWindow()
	if not frame then return end
	local hooks = self.rxpHooks
	-- The step card switch is a field of the classic window; with the beta
	-- window on, RestedXP still calls it there and hands the work on.
	local classic = _G.RXPFrame
	if Usable(classic) and not hooks[classic] then
		hooks[classic] = "switch"
		if type(classic.SetStepFrameAnchor) == "function" then
			hooksecurefunc(classic, "SetStepFrameAnchor", function()
				M:FollowStepCard()
				M:RefitRXP()
			end)
		end
	end
	if hooks[frame] == "window" then return end
	hooks[frame] = "window"
	-- RXP ends its own drag and resize with StopMovingOrSizing.
	hooksecurefunc(frame, "StopMovingOrSizing", function()
		C_Timer.After(0.1, function() M:PullRXP() end)
	end)
	-- The guide changes its shape without a drag: the step card moves
	-- between Top and Bottom, a guide loads, a step gets longer, the
	-- window is resized or scaled. Each change places it again from
	-- the mover a moment later, once for a burst of changes.
	frame:HookScript("OnSizeChanged", function() M:RefitRXP() end)
	local step = rawget(frame, "CurrentStepFrame")
	if Usable(step) and type(step.HookScript) == "function" then
		step:HookScript("OnSizeChanged", function() M:RefitRXP() end)
		step:HookScript("OnShow", function() M:RefitRXP() end)
		step:HookScript("OnHide", function() M:RefitRXP() end)
	end
end

function M:SetupRXP()
	self:ReleaseRXPPlacement()
	if not self:RXPWanted() then
		self:HideProxy("EldoUI_RXP")
		return
	end
	self:Proxy("EldoUI_RXP", L["RestedXP Guide"], 300, 400,
		{ "TOPRIGHT", "UIParent", "TOPRIGHT", -400, -358 },
		{ onMoved = function() M:PlaceRXP() end })
	self:HookRXP()
	-- The setup was finished or skipped: the guide leaves the spot it
	-- took under the game's player frame for the layout's spot.
	if E.Installer and type(E.Installer.SetupDone) == "function" and not self.rxpSetupHooked then
		self.rxpSetupHooked = true
		hooksecurefunc(E.Installer, "SetupDone", function()
			if M.rxpHeld and M.active then M:PlaceRXP() end
		end)
	end
	-- RXP restores its saved spot while it starts; place it after that.
	C_Timer.After(2, function() M:PlaceRXP() end)
end

-- The theme: RXP reads every table in the global RXPGuides_Themes when it
-- starts (EldoUI loads first, alphabetically) and offers it in its theme
-- list. Missing keys fall back to RXP's own default theme, so no RXP
-- texture is named here. The table is filled from EldoUI's media at login.
local rxpTheme
if C_AddOns.DoesAddOnExist("RXPGuides") then
	rxpTheme = { name = "EldoUI", author = "EldoUI", displayName = "EldoUI" }
	_G.RXPGuides_Themes = _G.RXPGuides_Themes or {}
	table.insert(_G.RXPGuides_Themes, rxpTheme)
end

local function Clamp(value) return math.min(1, math.max(0, value)) end

function M:UpdateRXPTheme()
	if not rxpTheme then return end
	local list = _G.RXPGuides_Themes
	-- Read the settings, not `active`: this runs before the module enables.
	local wanted = self.db.enabled and self.db.rxp.enabled and self.db.rxp.theme
	if type(list) == "table" then
		local index = tIndexOf(list, rxpTheme)
		-- Before RXP has read the list, switching off takes the theme out.
		if not wanted and index then table.remove(list, index) end
		if wanted and not index and not self.rxpThemeRead then table.insert(list, rxpTheme) end
	end
	if not wanted then return end
	local media = E.media
	local bg = media.backdropColor
	local r, g, b = unpack(media.accentColor)
	rxpTheme.background = { bg[1], bg[2], bg[3], 1 }
	rxpTheme.bottomFrameBG = { Clamp(bg[1] * 1.5 + 0.02), Clamp(bg[2] * 1.5 + 0.02), Clamp(bg[3] * 1.5 + 0.02), 1 }
	rxpTheme.bottomFrameHighlight = { r * 0.45, g * 0.45, b * 0.45, 1 }
	rxpTheme.mapPins = { r, g, b, 1 }
	rxpTheme.tooltip = ("|cFF%02X%02X%02X"):format(Round(r * 255), Round(g * 255), Round(b * 255)) -- no-L: color code for the RestedXP theme, not text
	rxpTheme.textColor = { 1, 1, 1 }
	rxpTheme.font = media.font
	rxpTheme.bgTextures = { edge = media.flat, bottom = media.flat }
end

-- The current step card under the guide instead of above it. RestedXP
-- keeps its settings in profiles (the saved table RXPSettings: `profiles`
-- by name, `profileKeys` naming each character's profile); its option
-- "Current step frame anchor" is the profile field anchorOrientation,
-- "top" (the default, not stored) or "bottom". After writing it, EldoUI
-- calls RXPFrame.SetStepFrameAnchor() so the window follows.
local function RXPSettingsProfile()
	local saved = rawget(_G, "RXPSettings")
	if type(saved) ~= "table" or type(saved.profiles) ~= "table" then return end
	local keys = type(saved.profileKeys) == "table" and saved.profileKeys or {}
	local name = keys[E.charKey]
	if type(name) ~= "string" then name = "Default" end
	local profile = saved.profiles[name]
	if type(profile) ~= "table" then return end
	local shared = 0
	for character, used in pairs(keys) do
		if used == name and character ~= E.charKey then shared = shared + 1 end
	end
	return profile, name, shared
end

M.changes.rxpStepCard = {
	addon = "rxp",
	title = "RestedXP: step card under the guide",
	Target = RXPSettingsProfile,
	Wanted = function() return { anchorOrientation = "bottom" } end,
	labels = { anchorOrientation = Key("Current step card") },
	unset = Key("above the guide (RestedXP's default)"),
	Describe = function(value)
		if value == "bottom" then return L["under the guide"] end
		if value == "top" then return L["above the guide"] end
		return tostring(value)
	end,
	Refresh = function()
		local frame = _G.RXPFrame
		if Usable(frame) and type(frame.SetStepFrameAnchor) == "function" then frame.SetStepFrameAnchor() end
		M:RefitRXP()
	end,
}

-- The setup's Other addons step offers the change as its own row. It is
-- ticked at the start of a run only for a fresh EldoUI setup on a
-- RestedXP profile that never set the card, so a choice made in RestedXP
-- is never overruled.
function M:RXPStepCardFresh()
	local plan = self:ChangePlan("rxpStepCard")
	local row = plan and plan.rows[1]
	return row ~= nil and row.from == nil and not plan.applied and E.db and E.db.needsSetup and true or false
end

function M:RefreshSetupTicks()
	local setup = E.addonSetups and E.addonSetups.RestedXP
	if setup then setup.preselect = self:RXPStepCardFresh() end
end

E:RegisterAddonSetup("RestedXP", {
	title = "RestedXP: step card under the guide",
	available = function() return M:ChangePlan("rxpStepCard") ~= nil end,
	profile = function() return "bottom" end, -- built by EldoUI, nothing to capture
	preselect = false, -- M:RefreshSetupTicks
	import = function()
		local plan = M:ChangePlan("rxpStepCard")
		local ok, why = M:ApplyChange("rxpStepCard")
		if not ok and why ~= "combat" then return false, L["RestedXP is not ready"] end
		if plan and #plan.rows > 0 then
			local change = M.changes.rxpStepCard
			M:Print(L["%s: done. Undo on the Integrations page puts it back."]:format(change.title))
			M:Print(M:ChangeScope(change, plan))
		end
		return true
	end,
	restore = function()
		local ok = M:UndoChange("rxpStepCard")
		if ok then return true end
		return false, L["EldoUI has nothing to undo here."]
	end,
})

---------------------------------------------------------------------------
-- BigWigs: bars follow EldoUI movers through BigWigs' custom anchor
---------------------------------------------------------------------------
-- BigWigs anchors its bars to any named frame (normalPosition[5]). EldoUI
-- creates the named proxies at login, before BigWigs loads its plugins.
-- Pointing BigWigs at them goes through BigWigsAPI.RegisterProfile, which
-- shows BigWigs' own accept/decline popup; after that the bars follow the
-- movers with no further code. Messages and the countdown can only use
-- screen offsets, so their spots are sent as numbers: again after moving
-- those movers, and (offered) after every layout click.
-- The timer and message movers are shared with the DBM module
-- (Modules/DBM.lua, `dbm = true`): they show while either boss mod uses
-- them, so their titles name the boss-mod zone, not one addon. The
-- keys stay EldoUI_BigWigs*, because layouts and saved positions use them.
local BIGWIGS = {
	{ name = E:MoverFamilyName(BIGWIGS_BASE, "Bars"), sample = { kind = "bars" }, title = "Boss Timers", w = "barsWidth", h = "barsHeight", dbm = true,
		point = { "CENTER", "UIParent", "CENTER", 600, 40 } },
	{ name = E:MoverFamilyName(BIGWIGS_BASE, "Emphasize"), sample = { kind = "bars" }, title = "Boss Timers: Soon", w = "emphWidth", h = "emphHeight", dbm = true,
		point = { "CENTER", "UIParent", "CENTER", 0, 190 } },
	{ name = E:MoverFamilyName(BIGWIGS_BASE, "Messages"), sample = { kind = "text" }, title = "Boss Messages", width = 400, height = 60, option = "messages", dbm = true,
		point = { "TOP", "UIParent", "TOP", 0, -180 } },
	{ name = E:MoverFamilyName(BIGWIGS_BASE, "Countdown"), sample = { kind = "text" }, title = "Boss Countdown", width = 120, height = 80, option = "countdown",
		point = { "CENTER", "UIParent", "CENTER", 0, 235 } },
}

-- The DBM module places DBM's frames on the shared movers.
local function DBMWantsMovers()
	local dbm = E.modules.DBM
	return dbm and dbm.WantsMovers and dbm:WantsMovers() or false
end

-- BigWigs checks the named anchor frame when its bar plugin loads and resets
-- the anchor to the screen for good when the frame is missing. So the named
-- frames exist from file load (EldoUI loads after BigWigs, OptionalDeps);
-- their movers come when the module enables.
for _, def in ipairs(BIGWIGS) do
	local frame = CreateFrame("Frame", def.name, UIParent)
	frame:SetSize(1, 1)
	frame:EnableMouse(false)
	early[def.name] = frame
end

function M:SetupBigWigs()
	local on = self:On("bigwigs")
	local dbm = self.active and DBMWantsMovers()
	local cfg = self.db.bigwigs
	for _, def in ipairs(BIGWIGS) do
		local wanted = (on and (not def.option or cfg[def.option])) or (dbm and def.dbm)
		if wanted then
			local width, height = def.width or cfg[def.w], def.height or cfg[def.h]
			-- Areas with a size setting can "Match size" in move mode.
			local sizeKeys = def.w and {
				width = { key = "bigwigs." .. def.w, min = 120, max = 500 },
				height = { key = "bigwigs." .. def.h, min = 40, max = def.h == "emphHeight" and 400 or 500 },
			} or nil
			self:Proxy(def.name, def.title, width, height, def.point, { sizeKeys = sizeKeys, sample = def.sample })
			SetProxySize(def.name, width, height)
		elseif self.proxies[def.name] then
			self:HideProxy(def.name)
		end
	end
end

-- The mover of a numbers-only anchor (messages, countdown), when its option
-- is on and it has a place on the screen.
function M:BigWigsMover(option, name)
	local mover = self.db.bigwigs[option] and E.movers[name]
	local proxy = self.proxies[name]
	if mover and proxy and proxy:IsShown() and mover:GetTop() then return mover end
end

---------------------------------------------------------------------------
-- BigWigs bar style "EldoUI": a 1-pixel EldoUI box around each bar (the
-- accent on emphasized bars), EldoUI's bar texture and font. Read from the
-- theme each time a bar starts, so it follows style preset changes. Only
-- BigWigs' public bar style API (BigWigsAPI:RegisterBarStyle); BarStopped
-- puts back what the style changed, so another style takes over cleanly.
---------------------------------------------------------------------------
local STYLE_KEY = "EldoUI"

local function StyleBar(bar)
	local border = bar:Get("eldoui:border")
	if not border then
		border = CreateFrame("Frame", nil, bar)
		E:SetTemplate(border, true)
		bar:Set("eldoui:border", border)
	end
	border:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
	border:ClearAllPoints()
	border:SetPoint("TOPLEFT", bar, "TOPLEFT", -E.pixel, E.pixel)
	border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", E.pixel, -E.pixel)
	if bar:Get("bigwigs:emphasized") then
		border:SetBackdropBorderColor(unpack(E.media.accentColor))
	else
		border:SetBackdropBorderColor(unpack(E.media.borderColor))
	end
	border:Show()
	local statusbar = bar.candyBarBar
	local texture = statusbar and statusbar.GetStatusBarTexture and statusbar:GetStatusBarTexture()
	if texture and bar:Get("eldoui:texture") == nil then
		bar:Set("eldoui:texture", texture:GetTexture() or false)
	end
	if E.media.statusbar then bar:SetTexture(E.media.statusbar) end
	for _, key in ipairs({ "candyBarLabel", "candyBarDuration" }) do
		local text = bar[key]
		if text and text.GetFont then
			local font, size, flags = text:GetFont()
			if font and bar:Get("eldoui:font:" .. key) == nil then bar:Set("eldoui:font:" .. key, { font, size, flags }) end
			-- Direct on purpose: BigWigs keeps its own size; the original is restored below.
			if size then text:SetFont(E.media.font, size, flags or "") end
		end
	end
end

local function UnstyleBar(bar)
	local border = bar:Get("eldoui:border")
	if border then border:Hide() end
	local texture = bar:Get("eldoui:texture")
	if texture then bar:SetTexture(texture) end
	bar:Set("eldoui:texture", nil)
	for _, key in ipairs({ "candyBarLabel", "candyBarDuration" }) do
		local saved, text = bar:Get("eldoui:font:" .. key), bar[key]
		if saved and text and text.SetFont then text:SetFont(saved[1], saved[2], saved[3] or "") end
		bar:Set("eldoui:font:" .. key, nil)
	end
end

-- A bar the style can't touch (a part BigWigs made secret, an older
-- LibCandyBar) keeps BigWigs' own look instead of erroring every bar.
local function Safely(fn)
	return function(bar)
		local ok, err = pcall(fn, bar)
		if not ok and E.Debug then E:Debug("BigWigs bar style: " .. tostring(err)) end
	end
end

M.bigWigsStyle = {
	apiVersion = 1,
	version = 1,
	ApplyStyle = Safely(StyleBar),
	BarStopped = Safely(UnstyleBar),
	GetStyleName = function() return "EldoUI" end,
}

-- Adds "EldoUI" to BigWigs' bar style list (once; BigWigs refuses the same
-- version twice). Returns true when the style is in the list.
function M:RegisterBigWigsStyle()
	local api = _G.BigWigsAPI
	if type(api) ~= "table" or type(api.RegisterBarStyle) ~= "function" then return false end
	if type(api.GetBarStyle) == "function" then
		local ok, style = pcall(api.GetBarStyle, api, STYLE_KEY)
		if ok and style then return true end
	end
	return pcall(api.RegisterBarStyle, api, STYLE_KEY, self.bigWigsStyle) and true or false
end

-- Role timing: when bars count as "soon" and how many show. Timing
-- and density only, never positions. Tanks get the earliest warning, damage
-- dealers the fewest bars.
M.BIGWIGS_TIMING = {
	tank = { emphasizeTime = 10, visibleBarLimit = 8, visibleBarLimitEmph = 4 },
	healer = { emphasizeTime = 8, visibleBarLimit = 10, visibleBarLimitEmph = 4 },
	damage = { emphasizeTime = 7, visibleBarLimit = 6, visibleBarLimitEmph = 3 },
}

-- The role the timing is for: the role layer in use, else the game's
-- suggestion (spec, group role, class).
function M:BigWigsRole()
	local role = E.GetRole and E:GetRole()
	if not role or role == "none" then role = E.DetectRole and E:DetectRole() end
	-- Melee and Ranged share the damage timing.
	if role and E.RoleGroup then role = E:RoleGroup(role) end
	return self.BIGWIGS_TIMING[role] and role or nil
end

-- The BigWigs profile EldoUI makes: one per layout, "EldoUI - <Layout>".
function M:BigWigsProfileName()
	local layout = E.layouts and E.layouts[E.db.general.layout]
	local title = layout and layout.title and L[layout.title] or tostring(E.db.general.layout or "")
	local name = "EldoUI - " .. title
	name = E:Utf8Sub(name, 50)
	return name
end

-- Builds a BigWigs profile string with the anchor positions and, when on,
-- the bar style and the role timing, in the format BigWigs' own sharing
-- uses ("BW2:" + base64(deflate(CBOR))). No colors (a partial color section
-- would reset BigWigs' color groups), sounds, BossBlock or comms.
function M:BigWigsAnchorString()
	local codec = C_EncodingUtil
	if not (codec and codec.SerializeCBOR and codec.CompressString and codec.EncodeBase64) then return end
	local data = {
		version = "BW2",
		barPositions = {
			normalPosition = { "TOP", "TOP", 0, 0, "EldoUI_BigWigsBars" },
			expPosition = { "TOP", "TOP", 0, 0, "EldoUI_BigWigsEmphasize" },
		},
	}
	local screenW, screenH = UIParent:GetSize()
	local messages = self:BigWigsMover("messages", "EldoUI_BigWigsMessages")
	if messages then
		local cx = (messages:GetLeft() + messages:GetRight()) / 2
		data.messagePositions = {
			normalPosition = { "TOP", "TOP", Round(cx - screenW / 2), Round(messages:GetTop() - screenH) },
		}
	end
	-- The countdown is centered on its anchor (BigWigs Plugins/Countdown.lua).
	local countdown = self:BigWigsMover("countdown", "EldoUI_BigWigsCountdown")
	if countdown then
		local cx = (countdown:GetLeft() + countdown:GetRight()) / 2
		local cy = (countdown:GetBottom() + countdown:GetTop()) / 2
		data.countdownPositions = {
			position = { "CENTER", "CENTER", Round(cx - screenW / 2), Round(cy - screenH / 2) },
		}
	end
	local cfg = self.db.bigwigs
	local settings = {}
	if cfg.style and self:RegisterBigWigsStyle() then settings.barStyle = STYLE_KEY end
	local role = cfg.timing and self:BigWigsRole()
	if role then
		for key, value in pairs(self.BIGWIGS_TIMING[role]) do settings[key] = value end
	end
	if next(settings) then data.barSettings = settings end
	local deflate = Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
	local ok, encoded = pcall(function()
		return codec.EncodeBase64(codec.CompressString(codec.SerializeCBOR(data), deflate))
	end)
	if ok and type(encoded) == "string" then return "BW2:" .. encoded end
end

-- Hands a profile string to BigWigs as "EldoUI - <Layout>". BigWigs shows
-- its own accept/decline popup; declining changes nothing. The profile in
-- use before the first EldoUI import is remembered for Restore. onDone
-- (optional) gets true or false. Returns whether BigWigs took the request.
function M:SendBigWigsProfile(text, onDone)
	local api = _G.BigWigsAPI
	if type(api) ~= "table" or type(api.RegisterProfile) ~= "function" then return false, L["This BigWigs version has no profile API."] end
	local cfg = self.db.bigwigs
	local name = self:BigWigsProfileName()
	local okName, before = pcall(api.GetProfileName)
	before = okName and type(before) == "string" and before or nil
	local ok, err = pcall(api.RegisterProfile, "EldoUI", text, name, function(accepted)
		if accepted then
			-- Switching between EldoUI layout profiles keeps the player's own one.
			if before and before ~= name and not before:find("^EldoUI %- ") then cfg.previousProfile = before end
			M:Print(L["BigWigs bars now follow the EldoUI movers. Move them with /eui move."])
		else
			M:Print(L["BigWigs anchors left unchanged."])
		end
		if onDone then onDone(accepted and true or false) end
	end)
	if not ok then return false, L["BigWigs refused the anchors: %s"]:format(tostring(err)) end
	return true
end

-- "Restore my previous BigWigs profile": BigWigs asks in its own popup,
-- then switches back. EldoUI's profiles stay (deleting one would switch
-- BigWigs to Default).
function M:RestoreBigWigsProfile()
	local api = _G.BigWigsAPI
	local previous = self.db.bigwigs.previousProfile
	if type(api) ~= "table" or type(api.SwapProfile) ~= "function" or type(previous) ~= "string" then
		self:Print(L["There is no earlier BigWigs profile to go back to."])
		return false
	end
	local okName, current = pcall(api.GetProfileName)
	if okName and current == previous then
		self:Print(L["BigWigs already uses %s."]:format(previous))
		return false
	end
	local ok, shown = pcall(api.SwapProfile, "EldoUI", previous, function(accepted)
		if accepted then M:Print(L["BigWigs is back on %s."]:format(previous)) end
	end)
	if not ok or shown == false then
		self:Print(L["BigWigs has no profile called %s any more."]:format(previous))
		return false
	end
	return true
end

-- Only on a click: BigWigs asks the player before it changes anything.
function M:SendBigWigsAnchors()
	if not self:On("bigwigs") then
		self:Print(L["BigWigs is not loaded, or this integration is off."])
		return
	end
	if InCombatLockdown() then
		self:Print(L["Try again after combat."])
		return
	end
	local api = _G.BigWigsAPI
	if type(api) ~= "table" or type(api.RegisterProfile) ~= "function" then
		self:Print(L["This BigWigs version has no profile API."])
		return
	end
	local text = self:BigWigsAnchorString()
	if not text then
		self:Print(L["Could not build the anchor string on this client."])
		return
	end
	local ok, err = self:SendBigWigsProfile(text)
	if not ok then self:Print(err) end
end

-- A layout click moves the messages and countdown movers, which BigWigs
-- only knows as numbers: offer to send them again (BigWigs asks in its own
-- popup). Installer previews apply layouts silently and offer nothing.
E:RegisterLayoutCallback(function(_, _, silent)
	if silent or not M:On("bigwigs") or not M.db.bigwigs.resend or InCombatLockdown() then return end
	C_Timer.After(0.5, function()
		if M:On("bigwigs") and not InCombatLockdown() then M:SendBigWigsAnchors() end
	end)
end)

-- Dragging the messages or countdown mover in move mode: one offer when
-- move mode closes, never one per drag.
local movedInMoveMode = false
for _, name in ipairs({ E:MoverFamilyName(BIGWIGS_BASE, "Messages"), E:MoverFamilyName(BIGWIGS_BASE, "Countdown") }) do
	E:RegisterMoverCallback(name, function()
		if E:IsMoveMode() then movedInMoveMode = true end
	end)
end
hooksecurefunc(E, "ToggleMoveMode", function()
	if E:IsMoveMode() or not movedInMoveMode then return end
	movedInMoveMode = false
	if not M:On("bigwigs") or not M.db.bigwigs.resend or InCombatLockdown() then return end
	C_Timer.After(0.5, function()
		if M:On("bigwigs") and not InCombatLockdown() then M:SendBigWigsAnchors() end
	end)
end)

---------------------------------------------------------------------------
-- Questie: its tracker (Questie_BaseFrame) on EldoUI_Questie
---------------------------------------------------------------------------
-- Uses the layout's quest tracker spot (alias EldoUI_Quests): only one
-- tracker shows at a time. When the Quest Tracker module already puts
-- Questie on its own mover (Blizzard UI "objective-tracker" move switch and
-- its Questie option), this integration stands back.
local function QuestieTracker()
	local frame = _G.Questie_BaseFrame
	if Usable(frame) then return frame end
end

local function QuestieProfile()
	local questie = _G.Questie
	local db = type(questie) == "table" and rawget(questie, "db")
	return type(db) == "table" and type(db.profile) == "table" and db.profile or nil
end

function M:TrackerModuleOwnsQuestie()
	local tracker = E:GetModule("ObjectiveTracker")
	return tracker and tracker.active and tracker.db and tracker.db.questie and tracker.db.questie.move
		and E:BlizzardAllowed("objective-tracker", "move") and true or false
end

function M:QuestieWanted()
	if not (self:On("questie") and self.db.questie.move) or self:TrackerModuleOwnsQuestie() then return false end
	local profile = QuestieProfile()
	return not (profile and profile.trackerEnabled == false)
end

-- The corner on the layout's side of the screen.
local function LayoutCorner()
	local pos = E.db.movers.EldoUI_Questie or E:GetMoverDefaultPoint("EldoUI_Questie")
	local point = pos and pos[1] or "TOPRIGHT"
	return (point:find("BOTTOM") and "BOTTOM" or "TOP") .. (point:find("LEFT") and "LEFT" or "RIGHT")
end

-- The corner the tracker grows from: Questie's own setting. EldoUI
-- changes it only through the change below, after the player applied it.
local function QuestieCorner()
	local profile = QuestieProfile()
	local corner = profile and profile.trackerSetpoint
	return type(corner) == "string" and corner or "TOPLEFT"
end

-- Questie keeps its settings in AceDB profiles: Questie.db.keys.profile is
-- the profile in use, Questie.db.sv.profileKeys names each character's.
local function QuestieTarget()
	local profile = QuestieProfile()
	if not profile then return end
	local db = rawget(_G.Questie, "db")
	local keys = type(db.keys) == "table" and db.keys or {}
	local name = type(keys.profile) == "string" and keys.profile or "Default"
	local shared = 0
	local sv = type(db.sv) == "table" and db.sv or {}
	for character, used in pairs(type(sv.profileKeys) == "table" and sv.profileKeys or {}) do
		if used == name and character ~= E.charKey then shared = shared + 1 end
	end
	return profile, name, shared
end

local CORNER_WORDS = E:TranslateValues({
	TOPLEFT = E.Key("top left"), TOPRIGHT = E.Key("top right"), BOTTOMLEFT = E.Key("bottom left"), BOTTOMRIGHT = E.Key("bottom right"),
})

M.changes.questieCorner = {
	addon = "questie",
	title = "Questie: grow from the layout's corner",
	Target = QuestieTarget,
	Wanted = function() return { trackerSetpoint = LayoutCorner() } end,
	labels = { trackerSetpoint = Key("Tracker grows from") },
	unset = Key("top left (Questie's default)"),
	Describe = function(value) return CORNER_WORDS[value] or tostring(value) end,
	Refresh = function() M:PlaceQuestie() end,
}

-- After the player applied the corner, a new layout moves it along (option
-- "Keep it in line with the layout"), unless the player picked another
-- corner in Questie since: that one is theirs.
function M:KeepQuestieCorner()
	if not (self.db.questie.corner and self:ChangeApplied("questieCorner")) then return end
	local target, place = ChangeTarget(self.changes.questieCorner)
	local record = target and ChangeStore("questieCorner", place)
	local kept = record and record.fields and record.fields.trackerSetpoint
	if kept and rawget(target, "trackerSetpoint") == kept.after and kept.after ~= LayoutCorner() then
		self:ApplyChange("questieCorner", nil, true)
	end
end

function M:PlaceQuestie()
	if not self:QuestieWanted() then return end
	Queue("EldoUI_Questie", function()
		local frame, mover = QuestieTracker(), E.movers.EldoUI_Questie
		if not (frame and mover and M:QuestieWanted() and mover:GetLeft()) then return end
		M:KeepQuestieCorner()
		local corner = QuestieCorner()
		local _, _, _, _, scale = RectOf(frame)
		scale = scale or 1
		local screenW, screenH = UIParent:GetSize()
		local x = corner:find("LEFT") and mover:GetLeft() or (mover:GetRight() - screenW)
		local y = corner:find("TOP") and (mover:GetTop() - screenH) or mover:GetBottom()
		-- Questie keeps whatever spot the frame has when it next saves.
		frame:ClearAllPoints()
		frame:SetPoint(corner, UIParent, corner, x / scale, y / scale)
	end)
end

function M:PullQuestie()
	if not self:QuestieWanted() or InCombatLockdown() then return end
	local frame = QuestieTracker()
	if not frame then return end
	local left, bottom, width, height = RectOf(frame)
	if not left then return end
	local corner = QuestieCorner()
	local x = corner:find("LEFT") and left or (left + width)
	local y = corner:find("BOTTOM") and bottom or (bottom + height)
	PullCorner("EldoUI_Questie", corner, x, y)
end

function M:HookQuestie()
	local frame = QuestieTracker()
	if not frame or self.questieHooked then return frame ~= nil end
	self.questieHooked = true
	hooksecurefunc(frame, "StopMovingOrSizing", function()
		C_Timer.After(0.2, function() M:PullQuestie() end)
	end)
	return true
end

-- Questie builds its tracker a while after it is ready; look a few times.
function M:WatchQuestie()
	if self.questieTicker then return end
	if self:HookQuestie() then
		self:PlaceQuestie()
		return
	end
	local tries = 0
	self.questieTicker = C_Timer.NewTicker(2, function(ticker)
		tries = tries + 1
		local found = M:HookQuestie()
		if found or tries >= 30 then
			ticker:Cancel()
			M.questieTicker = nil
			if found then M:PlaceQuestie() end
		end
	end)
end

function M:SetupQuestie()
	if not self:QuestieWanted() then
		self:HideProxy("EldoUI_Questie")
		return
	end
	local cfg = self.db.questie
	self:Proxy("EldoUI_Questie", L["Questie Tracker"], cfg.width, cfg.height,
		{ "TOPRIGHT", "UIParent", "TOPRIGHT", -90, -358 },
		{ layoutAlias = "EldoUI_Quests", onMoved = function() M:PlaceQuestie() end,
			sizeKeys = { width = { key = "questie.width", min = 160, max = 500 }, height = { key = "questie.height", min = 100, max = 900 } } })
	SetProxySize("EldoUI_Questie", cfg.width, cfg.height)
	local questie = _G.Questie
	local api = type(questie) == "table" and rawget(questie, "API")
	if not self.questieReady and type(api) == "table" and type(api.RegisterOnReady) == "function" then
		self.questieReady = true
		pcall(api.RegisterOnReady, function() M:WatchQuestie() end)
	else
		self:WatchQuestie()
	end
end

---------------------------------------------------------------------------
-- First-run windows of the companions
---------------------------------------------------------------------------
-- At a first start Details! opens its welcome window (a new account) or
-- its profile chooser (a new character on an account with several Details
-- profiles), and Questie asks how to show quest objectives. Closing or
-- answering such a window changes real data or settings: Details clears
-- its recorded fights when its welcome window closes, and each Questie
-- answer changes its map icons and the game's own objective setting. So
-- EldoUI never hides, clicks or answers them, and changes nothing that
-- decides whether they open. The EldoUI setup waits while one shows or is
-- about to (Installer.RegisterWait); a setup nobody has started yet steps
-- aside when one opens over it, and comes back on the same step after.
-- EldoUI only reads whether each window shows.
M.FIRST_RUN_DUE = 12     -- seconds a window that is due gets to appear
M.FIRST_RUN_LONGEST = 120 -- the longest EldoUI waits for one that never comes
M.FIRST_RUN_TICK = 0.5

-- Details' profile chooser has no name of its own; its confirm button has.
local function DetailsProfileChooser()
	local button = WidgetFrame(_G.DetailsProfilerProfileConfirmButton)
		or WidgetFrame(type(_G.DetailsProfilerProfileConfirmButton) == "table" and _G.DetailsProfilerProfileConfirmButton.button)
	local parent = button and button:GetParent()
	if Usable(parent) and parent ~= UIParent then return parent end
end

local function DetailsProfileCount()
	local details = DetailsAddon()
	if not (details and type(details.GetProfileList) == "function") then return 0 end
	local ok, list = pcall(details.GetProfileList, details)
	return ok and type(list) == "table" and #list or 0
end

local function QuestieGlobal()
	local questie = _G.Questie
	local db = type(questie) == "table" and rawget(questie, "db")
	return type(db) == "table" and type(db.global) == "table" and db.global or nil
end

-- addon: the integration it belongs to; Frame(): the window, once made;
-- Due(): true while that addon will open it this session.
M.FIRST_RUN = {
	{ key = "detailsWelcome", addon = "details",
		Frame = function() return WidgetFrame(_G.DetailsWelcomeWindow) end,
		Due = function()
			local details = DetailsAddon()
			return details and details.is_first_run == true or false
		end },
	{ key = "detailsProfiles", addon = "details",
		Frame = DetailsProfileChooser,
		Due = function()
			local details = DetailsAddon()
			return details and details.character_first_run == true and not details.is_first_run
				and not details.always_use_profile and DetailsProfileCount() > 1 or false
		end },
	{ key = "questieObjectives", addon = "questie", late = true,
		Frame = function() return WidgetFrame(_G.QuestieTutorialChooseObjectiveType) end,
		Due = function()
			local global = QuestieGlobal()
			return global ~= nil and not global.tutorialObjectiveTypeChosen and C_CVar.GetCVar("questPOI") ~= nil
		end },
}
local firstRun = { seen = {}, hooked = setmetatable({}, { __mode = "k" }) }
M.firstRun = firstRun

-- Called by the hooks and the watch below: the window opened or closed.
local function FirstRunChanged(shown)
	local installer = E.Installer
	if shown then
		if installer and installer.StepAside then installer.StepAside() end
	elseif installer and installer.WaitChanged then
		installer.WaitChanged()
	end
end

local function WatchFrame(entry, frame)
	if firstRun.hooked[frame] then return end
	firstRun.hooked[frame] = true
	frame:HookScript("OnShow", function()
		firstRun.seen[entry.key] = true
		FirstRunChanged(true)
	end)
	frame:HookScript("OnHide", function() FirstRunChanged(false) end)
end

-- Still to come: due, not made or shown yet, inside its time. Questie
-- makes its window once it is ready and out of combat, so its time counts
-- from then.
local function FirstRunPending(entry, now)
	if firstRun.seen[entry.key] or not firstRun.started then return false end
	if now - firstRun.started > M.FIRST_RUN_LONGEST then return false end
	if not (M:On(entry.addon) and entry.Due()) then return false end
	local from = firstRun.started
	if entry.late and firstRun.questieAsked then
		if not firstRun.questieReady or InCombatLockdown() then return true end
		from = math.max(firstRun.questieReady, firstRun.combatEnded or 0)
	end
	return now - from <= M.FIRST_RUN_DUE
end

-- The key of a first-run window that shows or is about to, or nil. A
-- window seen open for the first time steps the setup aside.
function M:FirstRunBusy()
	if not self.active then return nil end
	local now = GetTime()
	for _, entry in ipairs(self.FIRST_RUN) do
		local ok, frame = pcall(entry.Frame)
		frame = ok and frame or nil
		if frame then WatchFrame(entry, frame) end
		if frame and frame:IsShown() then
			if not firstRun.seen[entry.key] then
				firstRun.seen[entry.key] = true
				FirstRunChanged(true)
			end
			return entry.key
		end
		local okDue, pending = pcall(FirstRunPending, entry, now)
		if okDue and pending then return entry.key end
	end
	return nil
end

-- A short watch from login while a window is due: it finds each window
-- when it is made (and hooks it once) and lets the setup go on when
-- nothing is due or open any more. It stops then, and after
-- FIRST_RUN_LONGEST seconds at the latest.
function M:WatchFirstRun()
	if self.firstRunTicker or not firstRun.started or not self:FirstRunBusy() then return end
	self.firstRunTicker = C_Timer.NewTicker(self.FIRST_RUN_TICK, function()
		if M:FirstRunBusy() and GetTime() - firstRun.started <= M.FIRST_RUN_LONGEST then return end
		M:StopFirstRunWatch()
		FirstRunChanged(false)
	end)
end

function M:StopFirstRunWatch()
	if self.firstRunTicker then self.firstRunTicker:Cancel() end
	self.firstRunTicker = nil
end

-- Questie says when it is ready (it makes its first-run window then).
function M:WatchQuestieReady()
	if firstRun.questieAsked or not Loaded("questie") then return end
	local questie = _G.Questie
	local api = type(questie) == "table" and rawget(questie, "API")
	if type(api) ~= "table" or type(api.RegisterOnReady) ~= "function" then return end
	firstRun.questieAsked = true
	local ok = pcall(api.RegisterOnReady, function()
		firstRun.questieReady = firstRun.questieReady or GetTime()
		M:WatchFirstRun()
	end)
	if not ok then firstRun.questieReady = firstRun.questieReady or GetTime() end
end

if E.Installer and E.Installer.RegisterWait then
	E.Installer.RegisterWait("companions", function() return M:FirstRunBusy() ~= nil end)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:Setup()
	if self.UpdateGuideHandoff then self:UpdateGuideHandoff() end
	self:SetupDetails()
	self:SetupRXP()
	self:SetupRXPLocale()
	self:SetupBigWigs()
	if self:On("bigwigs") then self:RegisterBigWigsStyle() end
	self:SetupQuestie()
	self:UpdateRXPTheme()
	self:RefreshSetupTicks()
	self:WatchQuestieReady()
	self:WatchFirstRun()
end

function M:PlaceAll()
	self:RefreshDetails()
	self:PlaceRXP()
	self:PlaceQuestie()
end

function M:OnInitialize()
	-- Fill the RXP theme before RXP reads it (RXP loads after EldoUI).
	self:UpdateRXPTheme()
end

function M:OnEnable()
	-- The first-run windows count their time from the first start.
	firstRun.started = firstRun.started or GetTime()
	self:Setup()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		M:WatchFirstRun()
		C_Timer.After(1, function()
			if M.active then M:PlaceAll() end
		end)
	end)
	-- Questie makes its first-run window once a fight is over.
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		firstRun.combatEnded = GetTime()
		M:WatchFirstRun()
	end)
	self:RegisterEvent("ADDON_LOADED", function(_, _, name)
		if name == "RXPGuides" then
			M.rxpThemeRead = true
			-- Before RestedXP picks a guide at login.
			M:SetupRXPLocale()
			-- Automatic may pick RestedXP now.
			E:GuideProviderChanged()
		elseif name == "Guidelime" then
			E:GuideProviderChanged()
		elseif name == "Questie" or name == "Details" then
			if M.active then M:Setup() end
		end
	end)
	if C_AddOns.IsAddOnLoaded("RXPGuides") then self.rxpThemeRead = true end
end

function M:OnDisable()
	self:ReleaseRXPPlacement()
	-- The Questie watcher stops with the module; it starts again on enable.
	if self.questieTicker then
		self.questieTicker:Cancel()
		self.questieTicker = nil
	end
	self:StopFirstRunWatch()
	-- A setup that waited for a window EldoUI no longer watches goes on.
	FirstRunChanged(false)
	for name in pairs(self.proxies) do self:HideProxy(name) end
	for _, border in pairs(self.borders) do border:Hide() end
	self:UpdateRXPTheme()
	-- RestedXP's own group names come back, its own answers pass unchanged.
	self:SetupRXPLocale()
	E:GuideProviderChanged()
end

function M:OnProfileChanged()
	if not self.active then return end
	self:Setup()
	self:PlaceAll()
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function NotLoaded(key)
	return function() return not Loaded(key) end
end

-- Saved data this page reads: the Details! profile in use before an
-- EldoUI setup switched it (written by the setup step, Modules/Setups.lua),
-- so "Restore" can give it back.
E:RegisterStore("detailsPreviousProfile", { owner = "Setups" })

-- The Details profile rows show only while one of them can be used.
local function DetailsProfileRows()
	return E:GetAddonSetupStatus("Details") == "ready"
		or (Loaded("details") and type(EldoUIDB.detailsPreviousProfile) == "string")
end

-- Who places the RestedXP guide right now, and what the theme switch does.
function M:RXPStatusText()
	local cfg = self.db.rxp
	local lines = {}
	if not (self.db.enabled and cfg.enabled) then
		lines[1] = L["Integration off: EldoUI leaves RestedXP alone."]
	elseif cfg.move and E:GuideProvider() ~= "rxp" then
		-- Another pick holds the guide spot: RestedXP is left where it is.
		lines[1] = L["Not placed: the guide spot goes to the guide you picked on Eldostar's page."]
	elseif cfg.move then
		lines[1] = L["Placed by EldoUI: the guide and its step card follow the \"RestedXP Guide\" mover."]
		if self.RXPBetaWindow() then lines[#lines + 1] = L["RestedXP's new guide window is on: EldoUI places that window."] end
		if self.rxpHeld then lines[#lines + 1] = L["Until setup is done, it waits under the player frame."] end
	else
		lines[1] = L["Kept in RestedXP: the guide stays where RestedXP puts it."]
	end
	if self.db.enabled and cfg.enabled and cfg.theme then
		lines[#lines + 1] = L["EldoUI theme: pick it in RestedXP's theme list."]
	end
	return table.concat(lines, "\n")
end

-- The state of an addon a layout can place, for the setup's Other addons
-- step: "missing" (not loaded), "managed" (the layout places it) or
-- "kept" (it keeps its own spot). want: the pick in the setup, if any.
function E:AddonPlacementStatus(entry, want)
	if not C_AddOns.IsAddOnLoaded(entry.addon) then return "missing" end
	if want == nil then want = self:GetAddonPlacement(entry) end
	if entry.key == "guidelime" or entry.key == "rxp" then
		if M.guideReloadPending or M.rxpReleaseBlocked then return "kept", self:GuideProviderStatus() end
		local provider = entry.key == "rxp" and "rxp" or "guidelime"
		if self:GuideProvider() ~= provider then return "kept", L["Not placed: another guide is selected for the guide spot."] end
		if entry.key == "guidelime" then return want and "managed" or "kept", self:GuideProviderStatus() end
	end
	return want and "managed" or "kept"
end

-- A line at the top of each tab while that addon is missing.
local function Status(key)
	return {
		type = "description",
		label = "%s is not loaded. These settings apply when it is.", labelFill = ADDONS[key],
		tone = "warning",
		hidden = function() return Loaded(key) end,
	}
end

M.options = {
	{ type = "tab", label = "Details!" },
	Status("details"),
	{ type = "header", label = "Details! Damage Meter" },
	{ type = "toggle", key = "details.enabled", label = "Details! integration",
		desc = "Lets EldoUI place and frame Details' windows. Off: EldoUI leaves Details alone." },
	{ type = "toggle", key = "details.move", label = "Place with the layout",
		desc = "Puts Details' window 1 on the \"Details! Window 1\" mover, so layouts, move mode and the Positions page place it. Dragging the window in Details moves the mover too." },
	{ type = "toggle", key = "details.window2", label = "Place window 2 too",
		desc = "Stacked meters: window 2 gets its own mover, above window 1 in every layout. Ungroup the windows in Details if it snapped them together." },
	{ type = "toggle", key = "details.size", label = "Set the window size",
		desc = "Sizes the windows from the values below. Off: Details keeps its own size and the mover takes it over." },
	{ type = "range", key = "details.width", label = "Window 1 width", min = 150, max = 800, step = 1,
		desc = "Width of window 1 in UI units, when \"Set the window size\" is on." },
	{ type = "range", key = "details.height", label = "Window 1 height", min = 80, max = 600, step = 1,
		desc = "Height of window 1 including its title bar, when \"Set the window size\" is on." },
	{ type = "range", key = "details.width2", label = "Window 2 width", min = 150, max = 800, step = 1,
		desc = "Width of window 2, when it is placed and sized by EldoUI." },
	{ type = "range", key = "details.height2", label = "Window 2 height", min = 80, max = 600, step = 1,
		desc = "Height of window 2 including its title bar, when it is placed and sized by EldoUI." },
	{ type = "range", key = "details.titleHeight", label = "Title bar height", min = 0, max = 40, step = 1,
		desc = "Room left above the window for Details' title bar. Set it to 0 if your Details skin has the bar at the bottom." },
	{ type = "header", label = "Look" },
	{ type = "toggle", key = "details.skin", label = "EldoUI frame",
		desc = "Draws an EldoUI panel (art style, border and colors from the General page) around the Details windows." },
	{ type = "toggle", key = "details.transparent", label = "See-through background",
		desc = "The EldoUI panel behind the windows lets the game show through a little. How much: General > Panel opacity." },
	{ type = "range", key = "details.padding", label = "Frame padding", min = 0, max = 12, step = 1,
		desc = "Gap between the window and the EldoUI frame around it." },
	{ type = "header", label = "Profile", hidden = function() return not DetailsProfileRows() end },
	{ type = "execute", label = "Use the EldoUI Details profile", width = 260,
		desc = "Imports EldoUI's Details profile for this layout through Details' own import, as \"EldoUI - <layout>\", and switches Details to it. Your own Details profiles stay in its list. Not in combat.",
		hidden = function() return E:GetAddonSetupStatus("Details") ~= "ready" end,
		func = function() E:ApplyAddonSetups({ Details = true }) end },
	{ type = "execute", label = "Switch back to my Details profile", width = 260,
		desc = "Details uses the profile you had before EldoUI's import again. The EldoUI profiles stay in Details' list.",
		hidden = function() return not (Loaded("details") and type(EldoUIDB.detailsPreviousProfile) == "string") end,
		func = function() E:RestoreDetailsProfile() end },

	{ type = "tab", label = "RestedXP" },
	Status("rxp"),
	{ type = "header", label = "RestedXP Guides" },
	{ type = "description", label = function() return M:RXPStatusText() end, hidden = NotLoaded("rxp") },
	{ type = "execute", label = "Choose the guide", width = 200,
		desc = "Opens Eldostar's page, where you pick the one guide that takes the layout's guide spot: Automatic, Eldostar, RestedXP, Guidelime or Off.",
		func = function() E:ToggleConfig("module:Eldostar", true, "provider") end },
	{ type = "toggle", key = "rxp.enabled", label = "RestedXP integration",
		desc = "Lets EldoUI place the guide window and offer its theme. Off: EldoUI leaves RestedXP alone." },
	{ type = "toggle", key = "rxp.move", label = "Place with the layout",
		desc = "Puts the guide window on the \"RestedXP Guide\" mover. Dragging it in RestedXP moves the mover too." },
	{ type = "toggle", key = "rxp.cardDown", label = "Step card under the guide near the top",
		desc = "When the guide's spot is in the top half of the screen, its current step card opens under the guide, so the guide grows down from its spot. Lower on the screen RestedXP's own choice stays." },
	{ type = "toggle", key = "rxp.theme", label = "EldoUI theme", reload = true,
		desc = "Adds an \"EldoUI\" theme (EldoUI colors, accent and font) to RestedXP's theme list. Pick it in RestedXP's settings. Takes effect after a reload." },
	{ type = "toggle", key = "rxp.locale", label = "Fit RestedXP to this game language",
		desc = "RestedXP's paid guides are in English. On a client in another language EldoUI looks up the NPC names of the target macro in QuestieDB and keeps quest experience out of the monster count of the leveling report. On a German client it also fixes RestedXP's group names and leads the free guides on into the paid ones. RestedXP's own files stay as they are.",
		hidden = function() return not M:RXPLocaleShown() end },
	{ type = "description", label = function() return M:RXPLocaleStatus() end,
		hidden = function() return not (M:RXPLocaleShown() and M:RXPLocaleStatus() ~= "") end },
	{ type = "header", label = "RestedXP's own settings", hidden = function() return not M:ChangeShown("rxpStepCard") end },
	{ type = "description", label = function() return M:ChangeStatus("rxpStepCard") end,
		hidden = function() return not M:ChangeShown("rxpStepCard") end },
	{ type = "execute", label = "Step card under the guide", width = 240,
		desc = "Changes RestedXP's \"Current step frame anchor\" to Bottom, so the current step shows under the guide. EldoUI asks first and shows which RestedXP profile changes. Undo puts the old value back.",
		hidden = function() return not M:ChangeOffered("rxpStepCard") end,
		func = function() M:AskApplyChange("rxpStepCard") end },
	{ type = "execute", label = "Undo the step card change", width = 240,
		desc = "Puts RestedXP's \"Current step frame anchor\" back as it was before EldoUI's change. A value you changed in RestedXP since stays yours.",
		hidden = function() return not M:ChangeApplied("rxpStepCard") end,
		func = function() M:UndoChangeAndSay("rxpStepCard") end },

	{ type = "tab", label = "BigWigs" },
	Status("bigwigs"),
	{ type = "header", label = "BigWigs" },
	{ type = "toggle", key = "bigwigs.enabled", label = "BigWigs integration",
		desc = "Creates the EldoUI frames BigWigs can anchor its bars to. On WoW: Forever BigWigs shows its own timers (pull, break, custom bars); boss packs are not out for Forever yet." },
	{ type = "range", key = "bigwigs.barsWidth", label = "Bar area width", min = 120, max = 500, step = 1,
		desc = "Width of the \"Boss Timers\" mover (BigWigs and DBM). With BigWigs' \"copy width of custom anchor\" on, the bars take this width; DBM's timer bars always do." },
	{ type = "range", key = "bigwigs.barsHeight", label = "Bar area height", min = 40, max = 500, step = 1,
		desc = "Height of the \"Boss Timers\" mover. The bars grow down from its top." },
	{ type = "range", key = "bigwigs.emphWidth", label = "Emphasized area width", min = 120, max = 500, step = 1,
		desc = "Width of the \"Boss Timers: Soon\" mover, where BigWigs' emphasized and DBM's enlarged timers go." },
	{ type = "range", key = "bigwigs.emphHeight", label = "Emphasized area height", min = 40, max = 400, step = 1,
		desc = "Height of the \"Boss Timers: Soon\" mover." },
	{ type = "toggle", key = "bigwigs.messages", label = "BigWigs messages mover",
		desc = "A mover for BigWigs' messages. BigWigs can't follow it live: send the anchors again after you move it." },
	{ type = "toggle", key = "bigwigs.countdown", label = "Countdown mover",
		desc = "A mover for BigWigs' pull and encounter countdown, right above your character in every layout. Like the messages, BigWigs gets its spot when you send the anchors." },
	{ type = "toggle", key = "bigwigs.resend", label = "Send again after a layout click",
		desc = "On: after a layout click or a drag of the BigWigs movers, BigWigs asks in its own popup whether to take the new spots. Off: send them with the button below." },
	{ type = "toggle", key = "bigwigs.style", label = "EldoUI bar style",
		desc = "BigWigs' bars get EldoUI's thin border, texture and font, with the accent on bars about to end. Bar colors and sounds stay as set in BigWigs." },
	{ type = "toggle", key = "bigwigs.timing", label = "Timing for my role",
		desc = "Bars move to the \"soon\" area 10 seconds before they end for tanks, 8 for healers and 7 for damage dealers, and the bar count suits the role." },
	{ type = "execute", label = "Re-apply to BigWigs", width = 220,
		desc = "Asks BigWigs, in its own popup, to switch to an \"EldoUI - <layout>\" profile with its bars, messages and countdown on EldoUI's movers. Declining changes nothing.",
		func = function() M:SendBigWigsAnchors() end,
		hidden = NotLoaded("bigwigs") },
	{ type = "execute", label = "Restore my previous BigWigs profile", width = 260,
		desc = "Switches BigWigs back to the profile you used before EldoUI set it up. BigWigs asks first, and the EldoUI profiles stay in its list.",
		func = function() M:RestoreBigWigsProfile() end,
		hidden = function() return not Loaded("bigwigs") or type(M.db.bigwigs.previousProfile) ~= "string" end },

	{ type = "tab", label = "Questie" },
	Status("questie"),
	{ type = "header", label = "Questie" },
	{ type = "description", label = "The Quest Tracker module can also put Questie on its own mover. While it does, this integration stands back.",
		hidden = function() return not M:TrackerModuleOwnsQuestie() end },
	{ type = "toggle", key = "questie.enabled", label = "Questie integration",
		desc = "Lets EldoUI place Questie's quest tracker. Off: EldoUI leaves Questie alone." },
	{ type = "toggle", key = "questie.move", label = "Place with the layout",
		desc = "Puts Questie's tracker on the \"Questie Tracker\" mover, at the layout's quest tracker spot. Dragging it in Questie moves the mover too." },
	{ type = "description", label = function() return M:ChangeStatus("questieCorner") end,
		hidden = function() return not M:ChangeShown("questieCorner") end },
	{ type = "execute", label = "Grow from the layout's corner", width = 240,
		desc = "Changes Questie's own \"grow from\" corner to the layout's side of the screen, so a growing tracker stays on screen. EldoUI asks first; Undo puts the old corner back.",
		hidden = function() return not M:ChangeOffered("questieCorner") end,
		func = function() M:AskApplyChange("questieCorner") end },
	{ type = "toggle", key = "questie.corner", label = "Keep it in line with the layout",
		desc = "After you applied the layout's corner: a layout on the other side of the screen moves Questie's grow corner along. A corner you pick in Questie yourself stays.",
		hidden = function() return not M:ChangeApplied("questieCorner") end },
	{ type = "execute", label = "Undo: Questie's own corner", width = 240,
		desc = "Puts Questie's \"grow from\" corner back as it was before EldoUI's change. A corner you picked in Questie since stays yours.",
		hidden = function() return not M:ChangeApplied("questieCorner") end,
		func = function() M:UndoChangeAndSay("questieCorner") end },
	{ type = "range", key = "questie.width", label = "Area width", min = 160, max = 500, step = 1,
		desc = "Width of the \"Questie Tracker\" mover. Questie sizes the tracker itself; its corner sits at the mover's corner." },
	{ type = "range", key = "questie.height", label = "Area height", min = 100, max = 900, step = 1,
		desc = "Height of the \"Questie Tracker\" mover." },
}

-- Every row of an integration waits on its own switch; a few also wait on
-- another row of it (the window size rows on "Set the window size").
-- `dependsOn` names the first of those switches that is off.
local function Needs(...)
	local keys = { ... }
	return function()
		for _, key in ipairs(keys) do
			local group, field = key:match("^(%w+)%.(%w+)$")
			local db = M.db and M.db[group]
			if not (db and db[field]) then return key end
		end
		return keys[#keys]
	end
end
local NEEDS = {
	["details.width"] = { "details.enabled", "details.size" },
	["details.height"] = { "details.enabled", "details.size" },
	["details.width2"] = { "details.enabled", "details.window2", "details.size" },
	["details.height2"] = { "details.enabled", "details.window2", "details.size" },
}
for _, row in ipairs(M.options) do
	local key = type(row.key) == "string" and row.key
	local group = key and key:match("^(%w+)%.")
	if group and key ~= group .. ".enabled" and not row.dependsOn then
		row.dependsOn = Needs(unpack(NEEDS[key] or { group .. ".enabled" }))
	end
end

---------------------------------------------------------------------------
-- The setup's Other addons step: one row per addon a layout places
---------------------------------------------------------------------------
-- Each entry names the addon that has to be loaded, the module that places
-- it and that module's switches. The row is ticked while every switch is
-- on. Ticking turns them all on; unticking turns only the last one off, so
-- the rest of that integration (such as the frame around Details) stays as
-- it is. Nothing changes until the step is applied.
-- An entry with `get` and `set` instead of switches places the addon
-- through its own saved position (`layoutPoint` names the layout's spot).

-- Guidelime's guide window has no name to move, so it is placed the way
-- its own "Reset position" button does it: through the three position
-- values in its per-character saved table, read when the window is built
-- (after the next /reload). Only those three values are written, only
-- when the player ticks the row and applies the step, and as a change
-- with Undo (above): unticking puts back the spot Guidelime had before.
local GUIDELIME_POINT = "EldoUI_RXP" -- the guide spot every layout has

GuidelimeData = function()
	local data = rawget(_G, "GuidelimeDataChar")
	if type(data) == "table" then return data end
end

-- The layout's guide spot as Guidelime stores a position: one corner of
-- the window on the same corner of the screen.
GuidelimeSpot = function()
	local point = E:GetLayoutPoint(GUIDELIME_POINT)
	if type(point) ~= "table" or point[2] ~= "UIParent" or point[1] ~= point[3] then return nil end
	return point[1], point[4], point[5]
end

GuidelimePlaced = function()
	local data, relative, x, y = GuidelimeData(), GuidelimeSpot()
	if not (data and relative) then return false end
	local savedX, savedY = tonumber(data.mainFrameX), tonumber(data.mainFrameY)
	return data.mainFrameRelative == relative and savedX ~= nil and savedY ~= nil
		and math.abs(savedX - x) < 0.5 and math.abs(savedY - y) < 0.5
end

M.changes.guidelime = {
	addonTitle = "Guidelime",
	title = "Guidelime: window on the layout's guide spot",
	character = true,
	-- Its saved data only exists while Guidelime is loaded.
	On = function() return GuidelimeData() ~= nil end,
	Target = GuidelimeData,
	Wanted = function()
		if not M.active or E:GuideProvider() ~= "guidelime" then return nil end
		local relative, x, y = GuidelimeSpot()
		if not relative then return nil end
		return { mainFrameRelative = relative, mainFrameX = x, mainFrameY = y }
	end,
	labels = { mainFrameRelative = Key("Window corner"), mainFrameX = Key("Window across"), mainFrameY = Key("Window up and down") },
}

-- Ticked: the layout's guide spot. Unticked: the spot Guidelime had before
-- EldoUI's change. Without a record of that spot (placed by an older
-- EldoUI) nothing is written; Guidelime's own Reset position still works.
local function SetGuidelimePlaced(on)
	if on then
		if E:GuideProvider() ~= "guidelime" then
			M:Print(L["Select Guidelime as the guide provider before applying its guide spot."])
			return
		end
		M:ApplyChange("guidelime")
	elseif M:ChangeApplied("guidelime") then
		M:UndoChange("guidelime")
	else
		M:Print(L["EldoUI has no record of Guidelime's earlier spot, so the window stays where it is. Guidelime's own Reset position button moves it."])
	end
end

-- Its public position fields are applied when its private window is built.
-- Undo is safe now, but another managed guide waits for a new session rather
-- than hiding, disabling or reaching into the other addon's private window.
function M:UpdateGuideHandoff()
	if E:GuideProviderChoice() == "guidelime" then self.guideReloadPending = nil return end
	if self.stepGuideSessionOnSpot then self.guideReloadPending = true end
	if not self:ChangeApplied("guidelime") then return end
	self.stepGuideSessionOnSpot = true
	self.guideReloadPending = true
	if InCombatLockdown() then
		Queue("Guide:handoff", function() M:UpdateGuideHandoff(); E:GuideProviderChanged() end)
	else
		self:UndoChange("guidelime")
	end
end

E.addonPlacements = {
	{ key = "details", title = "Details!", addon = "Details", module = "Integrations", switches = { "details.enabled", "details.move" },
		label = L["Place Details! in this layout"],
		desc = L["Details' meter window goes to the layout's meter spot, and move mode places it like any EldoUI frame. Unchecked, Details keeps its own spot."] },
	{ key = "rxp", title = "RestedXP", addon = "RXPGuides", module = "Integrations", switches = { "rxp.enabled", "rxp.move" },
		label = L["Place RestedXP in this layout"],
		desc = L["The RestedXP guide window goes to the layout's guide spot, and move mode places it like any EldoUI frame. Unchecked, RestedXP keeps its own spot."] },
	{ key = "bigwigs", title = "BigWigs", addon = "BigWigs", module = "Integrations", switches = { "bigwigs.enabled" },
		label = L["Place BigWigs in this layout"],
		desc = L["Gives BigWigs' bars, messages and countdown a spot in the layout. BigWigs asks in its own window before it takes them. Unchecked, EldoUI leaves BigWigs alone."] },
	{ key = "dbm", title = "Deadly Boss Mods", addon = "DBM-Core", module = "DBM", switches = { "place" },
		label = L["Place Deadly Boss Mods in this layout"],
		desc = L["DBM's timers, warnings and info frame follow the layout's boss mod spots while its EldoUI profile is in use. Unchecked, DBM keeps its own spots."] },
	{ key = "questie", title = "Questie", addon = "Questie", module = "Integrations", switches = { "questie.enabled", "questie.move" },
		label = L["Place Questie in this layout"],
		desc = L["Questie's quest tracker goes to the layout's quest tracker spot, and move mode places it like any EldoUI frame. Unchecked, Questie keeps its own spot."] },
	{ key = "guidelime", title = "Guidelime", addon = "Guidelime", module = "Integrations", layoutPoint = GUIDELIME_POINT,
		get = GuidelimePlaced, set = SetGuidelimePlaced,
		label = L["Place Guidelime in this layout"],
		desc = L["Guidelime's guide window goes to the layout's guide spot after the next /reload. EldoUI only sets Guidelime's own saved window position, as its Reset position button does. Unchecking it later puts back the spot it had before."] },
}

local function PlacementModule(entry)
	local module = E.modules[entry.module]
	if module and type(module.db) == "table" then return module end
end

-- The table and key of one switch ("details.move" or "place").
local function PlacementSwitch(db, path)
	local group, field = path:match("^(%w+)%.(%w+)$")
	if group then return type(db[group]) == "table" and db[group] or nil, field end
	return db, path
end

-- The row shows while the addon is loaded and the module that places it is on.
function E:AddonPlacementShown(entry)
	local module = PlacementModule(entry)
	return module and module.db.enabled ~= false and C_AddOns.IsAddOnLoaded(entry.addon) and true or false
end

-- True while the layout places this addon.
function E:GetAddonPlacement(entry)
	local module = PlacementModule(entry)
	if not module then return false end
	if entry.get then return entry.get() and true or false end
	for _, path in ipairs(entry.switches) do
		local target, field = PlacementSwitch(module.db, path)
		if not (target and target[field]) then return false end
	end
	return true
end

-- Turns the placement on or off, then lets the module place (or leave)
-- the windows, out of combat.
function E:SetAddonPlacement(entry, on)
	local module = PlacementModule(entry)
	if not module then return end
	if entry.set then
		entry.set(on and true or false)
		return
	end
	local switches = entry.switches
	for index, path in ipairs(switches) do
		local target, field = PlacementSwitch(module.db, path)
		if target and (on or index == #switches) then target[field] = on and true or false end
	end
	E:RunOutOfCombat(function()
		if module.active and module.OnProfileChanged then
			local ok, err = pcall(module.OnProfileChanged, module)
			if not ok then geterrorhandler()(err) end
		end
	end)
end

-- The rows of `picks` (key = true or false) that differ from the switch
-- as it is now: { entry, on } each.
function E:AddonPlacementChanges(picks)
	local changes = {}
	for _, entry in ipairs(self.addonPlacements) do
		local want = picks[entry.key]
		if want ~= nil and self:AddonPlacementShown(entry) and want ~= self:GetAddonPlacement(entry) then
			changes[#changes + 1] = { entry = entry, on = want }
		end
	end
	return changes
end

-- Every profile path a placement row can write, for the setup's list of
-- what each step owns.
function E:AddonPlacementPaths(list)
	for _, entry in ipairs(self.addonPlacements) do
		for _, path in ipairs(entry.switches or {}) do list[#list + 1] = ("modules.%s.%s"):format(entry.module, path) end
	end
	return list
end

---------------------------------------------------------------------------
-- Style presets
---------------------------------------------------------------------------
E:RegisterStyles("Integrations", {
	{ key = "Full", title = "Full", desc = "Every integration on: layouts place the windows, Details gets the EldoUI frame and size, RestedXP offers the EldoUI theme.",
		settings = {
			details = { enabled = true, move = true, window2 = false, size = true, width = 440, height = 240, skin = true, transparent = false },
			rxp = { enabled = true, move = true, theme = true },
			bigwigs = { enabled = true, messages = true },
			questie = { enabled = true, move = true, corner = true },
		} },
	{ key = "Stacked", title = "Stacked meters", desc = "Two Details windows stacked in the meter corner, each 440 x 200, with the EldoUI frame.",
		settings = {
			details = { enabled = true, move = true, window2 = true, size = true, width = 440, height = 200, width2 = 440, height2 = 200, skin = true },
		} },
	{ mode = true, key = "Positions", title = "Positions only", desc = "Layouts place every window, but each addon keeps its own look.",
		settings = {
			details = { enabled = true, move = true, size = false, skin = false },
			rxp = { enabled = true, move = true, theme = false },
			bigwigs = { enabled = true },
			questie = { enabled = true, move = true, corner = true },
		} },
	{ key = "Glass", title = "Glass", desc = "Compact see-through EldoUI frame around a 360 x 180 Details window.",
		settings = {
			details = { enabled = true, move = true, size = true, width = 360, height = 180, skin = true, transparent = true, padding = 0 },
			rxp = { enabled = true, theme = true },
		} },
	{ mode = true, key = "Off", title = "Hands off", desc = "EldoUI leaves Details, RestedXP, BigWigs and Questie exactly as they are.",
		settings = {
			details = { enabled = false },
			rxp = { enabled = false },
			bigwigs = { enabled = false },
			questie = { enabled = false },
		} },
})
