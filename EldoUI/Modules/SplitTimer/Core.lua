-- EldoUI Split Timer: a leveling race against your own best.
--
--   Timer      A small frame on its own mover (EldoUI_SplitTimer, under
--              the minimap): the time on this level, the difference to
--              the reference for this level (green ahead, red behind)
--              and, when on, your total played time.
--   Ding card  At each level-up a card in the alert lane: "Level 23 in
--              1:12:40 (-4:05 vs best)".
--   Splits     A Characters window tab (Modules/SplitTimer/Splits.lua)
--              that compares two characters level by level.
--
-- References (option): "best" is the best time per level over all your
-- other characters (a "best of all" ghost: the totals add those times up),
-- "pb" your personal best run (the other character that reached your next
-- level in the least played time), "char" one character you pick.
--
-- Data: the core character store's level log (Core/CharacterStore.lua):
-- `levels[level] = { took, played, ... }` and the played time from the
-- game's own /played answer (`played`, `playedLevel`, `playedAt`). The
-- Characters module records them; nothing new is tracked here. Nothing
-- acts for the player.
-- Written from scratch for EldoUI; no code, strings or data from other addons.
local _, E = ...
local L = E.L

local MOVER = "EldoUI_SplitTimer"
local POINT = { "TOPRIGHT", "UIParent", "TOPRIGHT", -40, -258 }

local M = E:NewModule("SplitTimer", {
	title = "Split Timer",
	desc = "A leveling timer that races your own best: time on this level, the difference to your best character, a card at each level-up and a Splits tab in the Characters window.",
	category = "Quality of Life",
	frames = { "EldoUI_SplitTimerFrame" },
	movers = { "EldoUI_SplitTimer" },
	savedKeys = { "profile.modules.SplitTimer" },
	optionsPage = "module:SplitTimer",
	presets = { "Compact", "ForeverBronze", "Large", "Minimal", "Speedrun", "TextOnly" },
	reload = false,
	defaults = {
		timer = true,              -- the on-screen timer
		reference = "best",        -- "best", "pb" or "char"
		refChar = "",              -- character key for "char"
		showTotal = true,          -- the total played line
		showLabel = true,          -- "Level 23" and "vs best" labels
		dingCard = true,           -- the card at each level-up
		hideAtMax = true,          -- no timer at the level cap
		oneLine = false,           -- everything on one line
		panel = true,              -- the panel behind the timer
		fontSize = 16,             -- the level time
		smallSize = 11,            -- the other lines
		width = 180,
		accentTime = false,        -- the level time in the accent color
		splitsFolded = {},         -- Splits tab: folded sections (a, b, levels)
		visibility = E:VisibilityDefaults(), -- the shared visibility rules
	},
})
E.SplitTimer = M
E:RegisterVisibilityFacet(MOVER, "rules", { module = "SplitTimer", setting = "visibility" })
-- The timer counts on the shared ticker, once a second while it shows.
local TICK = "SplitTimer:tick"
M.MOVER, M.POINT = MOVER, POINT

local function Store() return E.Characters end
M.Store = Store

local function Now()
	local store = Store()
	return store and store.Now and store.Now() or time()
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
-- 4512 -> "1:15:12"; 300 -> "5:00"; 90061 -> "1d 1:01:01".
function M.Clock(seconds)
	if type(seconds) ~= "number" then return "" end
	seconds = math.max(math.floor(seconds + 0.5), 0)
	local days, hours = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
	local minutes, secs = math.floor(seconds % 3600 / 60), seconds % 60
	local text
	if hours > 0 or days > 0 then
		text = ("%d:%02d:%02d"):format(hours, minutes, secs)
	else
		text = ("%d:%02d"):format(minutes, secs)
	end
	if days > 0 then text = L["%dd"]:format(days) .. " " .. text end
	return text
end

-- -245 -> "-4:05"; 12 -> "+0:12"; 0 -> "0:00" (even, no sign).
function M.Delta(seconds)
	if type(seconds) ~= "number" then return "" end
	if math.floor(math.abs(seconds) + 0.5) == 0 then return M.Clock(0) end
	local sign = seconds < 0 and "-" or "+"
	return sign .. M.Clock(math.abs(seconds))
end

---------------------------------------------------------------------------
-- Splits and references
---------------------------------------------------------------------------
local function Levels(record)
	return record and type(record.levels) == "table" and record.levels or nil
end

-- The time spent on the level before `level` (the split) for a record.
function M.Took(record, level)
	local levels = Levels(record)
	local row = levels and levels[level]
	return type(row) == "table" and type(row.took) == "number" and row.took > 0 and row.took or nil
end

-- Total played time at the level-up to `level`.
function M.PlayedAt(record, level)
	local levels = Levels(record)
	local row = levels and levels[level]
	return type(row) == "table" and type(row.played) == "number" and row.played or nil
end

-- Other characters that logged at least one level.
function M:OtherKeys()
	local store = Store()
	local list = {}
	if not store then return list end
	for _, key in ipairs(store:Keys()) do
		local record = store:Get(key)
		if key ~= E.charKey and Levels(record) and next(record.levels) then list[#list + 1] = key end
	end
	return list
end

-- The best time per level over `keys`: { [level] = { took, key } }.
function M:BestOfAll(keys)
	local store = Store()
	local best = {}
	for _, key in ipairs(keys or self:OtherKeys()) do
		local record = store:Get(key)
		for level in pairs(Levels(record) or {}) do
			local took = type(level) == "number" and M.Took(record, level)
			if took and (not best[level] or took < best[level].took) then best[level] = { took = took, key = key } end
		end
	end
	return best
end

-- The ghost's total at `level`: the best times from level 2 up added.
-- Nil when a level in between has no time from any character.
function M.GhostTotal(best, level)
	local total = 0
	for step = 2, level do
		if not best[step] then return nil end
		total = total + best[step].took
	end
	return total
end

-- Personal best: the other character that reached `level` in the least
-- played time.
function M:PersonalBest(level)
	local store = Store()
	local bestKey, bestPlayed
	for _, key in ipairs(self:OtherKeys()) do
		local played = M.PlayedAt(store:Get(key), level)
		if played and (not bestPlayed or played < bestPlayed) then bestKey, bestPlayed = key, played end
	end
	return bestKey
end

-- The reference for `level`: { took, played, label } (either may be nil).
function M:Reference(level)
	local store = Store()
	if not store or type(level) ~= "number" then return {} end
	local mode = self.db.reference
	if mode == "char" then
		local record = self.db.refChar ~= "" and self.db.refChar ~= E.charKey and store:Get(self.db.refChar)
		if record then
			return { took = M.Took(record, level), played = M.PlayedAt(record, level), label = record.name, key = self.db.refChar }
		end
		mode = "pb"
	end
	if mode == "pb" then
		local key = self:PersonalBest(level)
		local record = key and store:Get(key)
		if not record then return { label = L["your best"] } end
		return { took = M.Took(record, level), played = M.PlayedAt(record, level), label = L["your best"], key = key }
	end
	local best = self:BestOfAll()
	return { took = best[level] and best[level].took, played = M.GhostTotal(best, level), label = L["best"] }
end

---------------------------------------------------------------------------
-- Live values
---------------------------------------------------------------------------
-- Time on the current level: the game's own level time from the last
-- /played answer plus the time since (while online).
function M.LevelTime(record)
	if not record or type(record.playedLevel) ~= "number" or type(record.playedAt) ~= "number" then return nil end
	if record.loggedOut then return record.playedLevel end
	return record.playedLevel + math.max(Now() - record.playedAt, 0)
end

-- Everything the timer shows: level, levelTime, total, liveDelta (time on
-- this level minus the reference's time for it; negative = ahead),
-- splitDelta (your total at your last level-up minus the reference's).
function M:Snapshot()
	local store = Store()
	local me = store and store:Get(E.charKey)
	if not me then return nil end
	local level = me.level or 1
	local snap = { level = level, levelTime = M.LevelTime(me), total = store:Played(me) }
	local nextRef = self:Reference(level + 1)
	snap.label = nextRef.label
	if snap.levelTime and nextRef.took then snap.liveDelta = snap.levelTime - nextRef.took end
	snap.refTook = nextRef.took
	local mine = M.PlayedAt(me, level)
	local ref = self:Reference(level)
	if mine and ref.played then snap.splitDelta = mine - ref.played end
	return snap
end

function M:AtMax()
	local store = Store()
	local me = store and store:Get(E.charKey)
	local max = store and store.MaxLevel and store.MaxLevel()
	return me and max and (me.level or 0) >= max or false
end

function M:Recording()
	local store = Store()
	return store and store.Recording and store:Recording() or false
end

---------------------------------------------------------------------------
-- The timer frame
---------------------------------------------------------------------------
local function Paint(fs, color)
	fs:SetTextColor(color[1], color[2], color[3])
end

-- Ahead is good, behind is bad, exactly even and no split are plain
-- text. The color never stands alone: the time carries its sign (-4:05
-- ahead, +0:12 behind) and "no split" says it in words.
local function DeltaColor(delta)
	if type(delta) ~= "number" then return E.tokens.text.secondary end
	if delta == 0 then return E.tokens.text.body end
	return delta < 0 and E.tokens.text.good or E.tokens.text.bad
end
M.DeltaColor = DeltaColor

function M:BuildFrame()
	if self.frame then return self.frame end
	local frame = CreateFrame("Frame", "EldoUI_SplitTimerFrame", UIParent)
	frame:SetSize(self.db.width, 40)
	frame:SetFrameStrata("LOW")
	-- The panel is a child frame, and a child frame draws over every text
	-- of its parent. The texts therefore sit on their own layer one level
	-- above the panel, so the panel stays behind them and never dims them.
	frame.bg = CreateFrame("Frame", nil, frame)
	frame.bg:SetAllPoints()
	E:SetTemplate(frame.bg, true)
	frame.content = CreateFrame("Frame", nil, frame)
	frame.content:SetAllPoints()
	frame.content:SetFrameLevel(frame.bg:GetFrameLevel() + 1)
	local content = frame.content
	frame.label = E:CreateText(content, self.db.smallSize, "LEFT")
	frame.time = E:CreateText(content, self.db.fontSize, "RIGHT")
	frame.delta = E:CreateText(content, self.db.smallSize, "LEFT")
	frame.deltaLabel = E:CreateText(content, self.db.smallSize, "LEFT")
	frame.total = E:CreateText(content, self.db.smallSize, "RIGHT")
	frame.texts = { frame.label, frame.time, frame.delta, frame.deltaLabel, frame.total }
	self.frame = frame
	self.mover = E:CreateMover(frame, MOVER, L["Split Timer"], POINT)
	-- A new art style, accent, font or panel color repaints the timer at
	-- once while it shows, not only at its next one-second tick.
	E:RegisterThemed(frame, function()
		if M.active then M:ApplyLook() end
	end)
	self:ApplyLook()
	return frame
end

local PAD = 5

-- Two rows: "Level 23" and the level time; the difference ("-4:05 vs
-- best") and the total played time. One line: level, time, difference.
-- Sizes follow the text scale (Large text), so the rows never overlap.
function M:ApplyLook()
	local frame = self.frame
	if not frame then return end
	local db = self.db
	-- Over the world without the panel, the texts always keep an outline
	-- (the General outline, or a plain one when that is off) and a shadow,
	-- so they read over bright and dark ground alike. On the see-through
	-- panel they follow the General font settings and get the soft shadow
	-- when they have no outline.
	local general = E.db and E.db.general or E.defaults.general
	local outline = nil
	if not db.panel and (general.fontOutline == nil or general.fontOutline == "") then outline = "OUTLINE" end
	E:SetFont(frame.time, db.fontSize, outline)
	for _, fs in ipairs({ frame.label, frame.delta, frame.deltaLabel, frame.total }) do E:SetFont(fs, db.smallSize, outline) end
	for _, fs in ipairs(frame.texts) do
		fs:SetAlpha(1)
		E:SetSeeThroughText(fs, true)
	end
	frame.bg:SetShown(db.panel)
	for _, fs in ipairs(frame.texts) do fs:ClearAllPoints() end
	local scale = E:TextScale()
	local big, small = db.fontSize * scale, db.smallSize * scale
	local height
	if db.oneLine then
		height = math.max(big, small) + PAD * 2
		frame.label:SetPoint("LEFT", PAD, 0)
		frame.time:SetPoint("LEFT", frame.label, "RIGHT", 6, 0)
		frame.delta:SetPoint("LEFT", frame.time, "RIGHT", 6, 0)
		frame.deltaLabel:Hide()
		frame.total:Hide()
		frame.label:Show()
	else
		height = PAD * 2 + big + 2 + small
		frame.label:SetPoint("LEFT", frame, "TOPLEFT", PAD, -PAD - big / 2)
		frame.time:SetPoint("TOPRIGHT", -PAD, -PAD)
		frame.delta:SetPoint("BOTTOMLEFT", PAD, PAD)
		frame.deltaLabel:SetPoint("LEFT", frame.delta, "RIGHT", 4, 0)
		frame.total:SetPoint("BOTTOMRIGHT", -PAD, PAD)
		frame.label:SetShown(db.showLabel)
		frame.deltaLabel:SetShown(db.showLabel)
		frame.total:SetShown(db.showTotal)
	end
	frame.baseWidth = math.floor(math.max(100, tonumber(db.width) or 180) * scale + 0.5)
	frame:SetSize(frame.baseWidth, height)
	self:UpdateVisibility()
end

-- The frame is at least as wide as its widest row, so a long time or
-- label never runs into its neighbor.
local function TextWidth(fs)
	if not fs:IsShown() then return 0 end
	return fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth() or 0
end

function M:FitWidth()
	local frame = self.frame
	if not frame then return end
	local need
	if self.db.oneLine then
		need = TextWidth(frame.label) + 6 + TextWidth(frame.time) + 6 + TextWidth(frame.delta)
	else
		local top = TextWidth(frame.label) + 8 + TextWidth(frame.time)
		local bottom = TextWidth(frame.delta) + 4 + TextWidth(frame.deltaLabel) + 8 + TextWidth(frame.total)
		need = math.max(top, bottom)
	end
	frame:SetWidth(math.max(frame.baseWidth or 100, math.ceil(need + PAD * 2)))
end

function M:ShouldShow()
	if not (self.active and self.db.timer) then return false end
	if not self:Recording() then return false end
	if self.db.hideAtMax and self:AtMax() then return false end
	return true
end

function M:UpdateVisibility()
	local frame = self.frame
	if not frame then return end
	local show = self:ShouldShow()
	frame:SetShown(show)
	if self.mover then self.mover:SetShown(show) end
	if show then
		self:Update()
		if not E.Ticker:IsSubscribed(TICK) then
			E.Ticker:Subscribe(TICK, 1, function()
				if M.active and frame:IsShown() then M:Update() else E.Ticker:Unsubscribe(TICK) end
			end, M)
		end
	else
		E.Ticker:Unsubscribe(TICK)
	end
end

-- The timer follows the shared visibility rules (alpha only).
function M:ApplyVisibility()
	local frame = self.frame
	if not frame then return end
	local block = self.db.visibility
	if type(block) ~= "table" then
		block = E:VisibilityDefaults()
		self.db.visibility = block
	end
	if self.visibilityBlock ~= block then E:DetachVisibility(frame) end
	if E:IsVisibilityAttached(frame) then
		E:UpdateVisibility(frame)
	else
		E:AttachVisibility(frame, block, { forceShow = function() return E:IsMoveMode() end })
	end
	self.visibilityBlock = block
end

function M:Update()
	local frame = self.frame
	if not (frame and self.active and frame:IsShown()) then return false end
	local snap = self:Snapshot()
	if not snap then return false end
	local db = self.db
	local secondary = E.tokens.text.secondary
	frame.label:SetText(db.oneLine and L["Lv %d"]:format(snap.level) or L["Level %d"]:format(snap.level))
	Paint(frame.label, secondary)
	frame.time:SetText(snap.levelTime and M.Clock(snap.levelTime) or "--:--")
	if db.accentTime then
		local accent = E.media.accentText
		frame.time:SetTextColor(accent[1], accent[2], accent[3])
	else
		Paint(frame.time, E.tokens.text.body)
	end
	frame.delta:SetText(snap.liveDelta and M.Delta(snap.liveDelta) or L["no split"])
	Paint(frame.delta, DeltaColor(snap.liveDelta))
	frame.deltaLabel:SetText(L["vs %s"]:format(snap.label or L["best"]))
	Paint(frame.deltaLabel, secondary)
	if db.showTotal and not db.oneLine then
		local total = snap.total and M.Clock(snap.total) or "--"
		frame.total:SetText(db.showLabel and L["Total %s"]:format(total) or total)
		Paint(frame.total, secondary)
	end
	self:FitWidth()
	self.snapshot = snap
	return true
end

---------------------------------------------------------------------------
-- The ding card
---------------------------------------------------------------------------
function M:DingText(level)
	local store = Store()
	local me = store and store:Get(E.charKey)
	local took = M.Took(me, level)
	if not took then return nil end
	local text = L["Level %d in %s"]:format(level, M.Clock(took))
	local ref = self:Reference(level)
	if ref.took then text = text .. " " .. L["(%s vs %s)"]:format(M.Delta(took - ref.took), ref.label or L["best"]) end
	return text
end

function M:OnLevels(key)
	if key ~= E.charKey or not self.active then return end
	local store = Store()
	local me = store and store:Get(E.charKey)
	local level = me and me.level
	-- One card per new level; a level the store reads again is no ding.
	if not level or (self.dingLevel and level <= self.dingLevel) then return end
	self.dingLevel = level
	self:UpdateVisibility()
	if not self.db.dingCard then return end
	local text = self:DingText(level)
	if text then M:PushAlert({ title = L["Split Timer"], text = text, icon = 236567, key = "splittimer" }) end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function M:OnEnable()
	self:BuildFrame()
	local store = Store()
	local me = store and store:Get(E.charKey)
	self.dingLevel = me and me.level
	if store and store.RegisterCallback and not self.watching then
		self.watching = true
		store.RegisterCallback(M, "Updated", function(_, key, section)
			if not M.active then return end
			if section == "levels" then M:OnLevels(key) else M:UpdateVisibility() end
		end)
	end
	self:RegisterEvent("PLAYER_LEVEL_UP", function() C_Timer.After(0.5, function() M:UpdateVisibility() end) end)
	self:UpdateVisibility()
	self:ApplyVisibility()
end

function M:OnDisable()
	self:UnregisterEvent("PLAYER_LEVEL_UP")
	E.Ticker:UnsubscribeOwner(M)
	if self.frame then E:DetachVisibility(self.frame) end
	self.visibilityBlock = nil
	if self.frame then self.frame:Hide() end
	if self.mover then self.mover:Hide() end
end

function M:OnProfileChanged()
	if not self.active then return end
	self:ApplyLook()
	self:ApplyVisibility()
end

E:RegisterDiagnostics("SplitTimer", function()
	if not M.initialized then return {} end
	local snap = M.snapshot or {}
	return { ("   Split Timer: %s, shown %s, reference %s, level %s, live %s, split %s, %d other characters"):format( -- no-L
		M.active and "on" or "off", tostring(M.frame and M.frame:IsShown()), tostring(M.db.reference), tostring(snap.level),
		tostring(snap.liveDelta), tostring(snap.splitDelta), #M:OtherKeys()) }
end)
