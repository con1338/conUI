-- EldoUI Enemy Spotter: a small movable list of hostile players whose
-- nameplates are (or were just) on screen: name in class color, level,
-- and how long ago they were seen.
--
-- How it stays within the rules: it only reads what a visible nameplate
-- already shows (NAME_PLATE_UNIT_ADDED/REMOVED, UnitIsPlayer, UnitIsEnemy,
-- UnitName, UnitClass, UnitLevel). A unit with any secret value is skipped.
-- The list never targets, clicks or acts on anyone.
local _, E = ...
local L = E.L

local M = E:NewModule("EnemySpotter", {
	title = "Enemy Spotter",
	desc = "A small list of hostile players seen on nameplates, with class color, level and how long ago.",
	category = "Combat",
	conflicts = { "DarkfoxxEnemySpotter" },
	frames = { "EldoUI_EnemySpotter" },
	movers = { "EldoUI_EnemySpotter" },
	blizzard = {},
	savedKeys = { "profile.modules.EnemySpotter" },
	optionsPage = "module:EnemySpotter",
	presets = { "Battleground", "Compact", "Large", "Minimal", "Standard" },
	reload = false,
	defaults = {
		enabled = false,
		maxRows = 8,
		width = 200,
		rowHeight = 18,
		fontSize = 12,
		forget = 60,         -- seconds after the nameplate went away
		sound = false,
		soundID = "kit:RAID_WARNING", -- media registry id (v0.7 and older: `soundKit`, a SOUNDKIT name)
		autoHide = true,
		hideInInstances = true,
		showLevel = true,
		showTitle = true,
		background = true,
	},
})

-- The sound comes from the media registry (E:PlayMedia), see the options.

local enemies = {} -- [name] = { name, class, level, seen, visible }
local plates = {}  -- [unit] = name

local IsSecret = E.Secret
local TICK = "EldoUI.EnemySpotter.list" -- the shared ticker key of the list

-- Call fn(...) and return its first value, or nil when it fails or is secret.
local Read = E.PlainCall

---------------------------------------------------------------------------
-- Nameplate events
---------------------------------------------------------------------------
function M:PlateAdded(unit)
	if self.db.hideInInstances and IsInInstance() then return end
	local isPlayer = Read(UnitIsPlayer, unit)
	if not isPlayer then return end
	local enemy = Read(UnitIsEnemy, "player", unit)
	if not enemy then return end
	local okName, name, realm = pcall(UnitName, unit)
	if not okName or IsSecret(name) or IsSecret(realm) or not name then return end
	local okClass, _, class = pcall(UnitClass, unit)
	if not okClass or IsSecret(class) then return end
	local level = Read(UnitLevel, unit)
	if realm and realm ~= "" then name = name .. "-" .. realm end

	local entry = enemies[name]
	local fresh = not entry
	entry = entry or { name = name }
	entry.class, entry.level, entry.seen, entry.visible = class, level, GetTime(), true
	enemies[name] = entry
	plates[unit] = name
	if fresh and self.db.sound then
		local now = GetTime()
		if not self.lastSound or now - self.lastSound > 2 then
			self.lastSound = now
			E:PlayMedia(self.db.soundID, nil, { fallback = "kit:RAID_WARNING" })
		end
	end
	self:Update()
end

function M:PlateRemoved(unit)
	local name = plates[unit]
	-- A plate the list never held (an NPC, a friend): nothing changed.
	if not name then return end
	plates[unit] = nil
	local entry = enemies[name]
	if entry then
		entry.visible = false
		entry.seen = GetTime()
		-- Another plate may still show the same name.
		for _, other in pairs(plates) do
			if other == name then entry.visible = true end
		end
	end
	self:Update()
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local function Ago(seconds)
	if seconds < 1 then return L["now"] end
	if seconds < 60 then return L["%ds"]:format(seconds) end
	return L["%dm"]:format(seconds / 60)
end

function M:CreateFrame()
	local frame = CreateFrame("Frame", "EldoUI_EnemySpotter", UIParent)
	frame:SetFrameStrata("LOW")
	frame:SetSize(self.db.width, 40)
	frame:EnableMouse(false) -- display only: nothing here can be clicked
	frame.title = E:CreateText(frame, self.db.fontSize, "LEFT")
	frame.title:SetPoint("TOPLEFT", 6, -4)
	frame.rows = {}
	self.frame = frame
	E:CreateMover(frame, "EldoUI_EnemySpotter", L["Enemy Spotter"], { "TOPLEFT", "UIParent", "TOPLEFT", 19, -190 }, { sample = { kind = "panel" } })
end

function M:Row(index)
	local row = self.frame.rows[index]
	if not row then
		row = CreateFrame("Frame", nil, self.frame)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		row.name = E:CreateText(row, self.db.fontSize, "LEFT")
		row.level = E:CreateText(row, self.db.fontSize, "RIGHT")
		row.ago = E:CreateText(row, self.db.fontSize - 1, "RIGHT")
		self.frame.rows[index] = row
	end
	return row
end

-- The "seen ... ago" times count up and old names leave the list, so the
-- list redraws once a second on the shared ticker while it holds a name.
-- An empty list does not change on its own and needs no redraw.
function M:WatchList()
	if self.active and next(enemies) ~= nil then
		if not E.Ticker:IsSubscribed(TICK) then E.Ticker:Subscribe(TICK, 1, function() M:Update() end, self) end
	else
		E.Ticker:Unsubscribe(TICK)
	end
end

-- Bumped when the theme changes, so every row takes the new fonts.
local styleGen = 0
E:OnThemeChanged("EnemySpotter", function() styleGen = styleGen + 1 end)

local list = {}
local function ByShownThenSeen(a, b)
	if a.visible ~= b.visible then return a.visible end
	return a.seen > b.seen
end

function M:Update()
	local frame = self.frame
	if not (frame and self.active) then return end
	local db = self.db
	-- A profile from an import or an older version can lack a size, so
	-- every number falls back to its default.
	local defaults = self.defaults
	local function Num(key) return tonumber(db[key]) or defaults[key] end
	local width, rowHeight, fontSize = Num("width"), Num("rowHeight"), Num("fontSize")
	local now = GetTime()
	wipe(list)
	for name, entry in pairs(enemies) do
		if not entry.visible and now - entry.seen > Num("forget") then
			enemies[name] = nil
		else
			list[#list + 1] = entry
		end
	end
	table.sort(list, ByShownThenSeen)
	-- Hidden in an instance, the list waits for the next plate or zone
	-- change instead of redrawing every second.
	local inInstance = db.hideInInstances and IsInInstance()
	if inInstance then E.Ticker:Unsubscribe(TICK) else self:WatchList() end

	local hidden = inInstance or (db.autoHide and #list == 0 and not E:IsMoveMode())
	if hidden then
		frame:SetAlpha(0)
		return
	end
	frame:SetAlpha(1)

	local top = 4
	if db.showTitle then
		E:SetFont(frame.title, fontSize)
		frame.title:SetText(L["Enemies (%d)"]:format(#list))
		frame.title:SetTextColor(E:TokenColor("accent")) -- accent at draw time
		frame.title:Show()
		top = fontSize + 10
	else
		frame.title:Hide()
	end

	local shown = math.min(#list, Num("maxRows"))
	-- Place, size and fonts change only with the settings or the theme;
	-- the per-second redraw sets text, color and alpha.
	local style = ("%s:%s:%s:%s:%s:%d"):format(width, rowHeight, fontSize, top, tostring(db.showLevel), styleGen)
	for index = 1, shown do
		local entry = list[index]
		local row = self:Row(index)
		if row.style ~= style then
			row.style = style
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -top - (index - 1) * rowHeight)
			row:SetSize(width - 8, rowHeight)
			row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
			E:SetNameTextFont(row.name, fontSize)
			E:SetFont(row.level, fontSize)
			E:SetFont(row.ago, math.max(fontSize - 1, 9))
			row.ago:ClearAllPoints()
			row.ago:SetPoint("RIGHT", row, "RIGHT", -2, 0)
			row.ago:SetWidth(34)
			row.level:ClearAllPoints()
			row.level:SetPoint("RIGHT", row.ago, "LEFT", -4, 0)
			row.level:SetWidth(28)
			row.name:ClearAllPoints()
			row.name:SetPoint("LEFT", row, "LEFT", 2, 0)
			row.name:SetPoint("RIGHT", db.showLevel and row.level or row.ago, "LEFT", -4, 0)
		end

		row.ago:SetText(entry.visible and L["now"] or Ago(now - entry.seen))
		row.ago:SetTextColor(unpack(E.media.text.secondary))

		if db.showLevel then
			local level = entry.level
			local text = (level and level > 0) and tostring(level) or "??"
			row.level:SetText(text)
			local color = (level and level > 0 and GetCreatureDifficultyColor) and E:DifficultyColor(GetCreatureDifficultyColor(level))
			if color then row.level:SetTextColor(color.r, color.g, color.b) else row.level:SetTextColor(E:TokenColor("bad")) end
			row.level:Show()
		else
			row.level:Hide()
		end

		row.name:SetText(entry.name)
		local color = E:ClassColorObject(entry.class)
		if color then row.name:SetTextColor(color.r, color.g, color.b) else row.name:SetTextColor(1, 1, 1) end
		row:SetAlpha(entry.visible and 1 or 0.6)
		row:Show()
	end
	for index = shown + 1, #frame.rows do frame.rows[index]:Hide() end

	frame:SetSize(width, top + math.max(shown, 1) * rowHeight + 4)
	self:UpdateBackground()
end

-- The see-through panel and, under the WoW Forever art style, its thin
-- frame line. Drawn only when the setting changes or the theme does,
-- not on every refresh of the list.
function M:UpdateBackground(force)
	local frame = self.frame
	if not frame then return end
	local want = self.db.background and true or false
	if not force and frame.eldoBackground == want then return end
	frame.eldoBackground = want
	if want then
		E:SetTemplate(frame, true)
	elseif frame.SetBackdrop then
		frame:SetBackdrop(nil)
	end
	E:SetStyleEdge(frame, want)
end

-- v0.7 and older saved a SOUNDKIT name in `soundKit`.
function M:MigrateSound()
	local db = self.db
	if db.soundKit ~= nil then
		if type(db.soundKit) == "string" and db.soundKit ~= "" then db.soundID = "kit:" .. db.soundKit end
		db.soundKit = nil
	end
end

function M:OnInitialize()
	self:MigrateSound()
end

---------------------------------------------------------------------------
-- Enable / disable
---------------------------------------------------------------------------
function M:OnEnable()
	if not self.frame then self:CreateFrame() end
	self:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, _, unit) M:PlateAdded(unit) end)
	self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, _, unit) M:PlateRemoved(unit) end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		wipe(plates)
		wipe(enemies)
		M:Update()
	end)
	self.frame:Show()
	self:Update()
end

function M:OnDisable()
	self:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
	self:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	wipe(plates)
	wipe(enemies)
	E.Ticker:UnsubscribeOwner(self)
	if self.frame then self.frame:Hide() end
end

-- Move mode shows an empty list at once, and hides it again after.
hooksecurefunc(E, "ToggleMoveMode", function()
	if M.active then M:Update() end
end)

-- Re-apply size, fonts and theme colors.
function M:OnProfileChanged()
	self:MigrateSound()
	styleGen = styleGen + 1
	if not self.active then return end
	self:UpdateBackground(true)
	self:Update()
end

---------------------------------------------------------------------------
-- Style presets
---------------------------------------------------------------------------
E:RegisterStyles("EnemySpotter", {
	{ key = "Standard", title = "Standard", desc = "200 px list with title, level and background.",
		settings = { width = 200, rowHeight = 18, fontSize = 12, showTitle = true, showLevel = true, background = true, maxRows = 8 } },
	{ key = "Compact", title = "Compact", desc = "Narrow 160 px list with small text.",
		settings = { width = 160, rowHeight = 15, fontSize = 11, showTitle = true, showLevel = true, background = true, maxRows = 6 } },
	{ key = "Minimal", title = "Minimal", desc = "Names and times only, no title, no background.",
		settings = { width = 170, rowHeight = 16, fontSize = 12, showTitle = false, showLevel = false, background = false, maxRows = 6 } },
	{ key = "Large", title = "Large", desc = "Wide 240 px list with 14 pt text and up to 12 rows.",
		settings = { width = 240, rowHeight = 22, fontSize = 14, showTitle = true, showLevel = true, background = true, maxRows = 12 } },
	{ key = "Battleground", title = "World PvP", desc = "Long list for open-world PvP: 15 rows, quick to forget.",
		settings = { width = 200, rowHeight = 16, fontSize = 12, showTitle = true, showLevel = true, background = true, maxRows = 15, forget = 30 } },
})

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
M.options = {
	{ type = "description", label = "Lists hostile players whose nameplates you see; never targets them. Needs enemy nameplates. Off by default: turn it on under Modules." },
	{ type = "header", label = "Behavior" },
	{ type = "range", key = "forget", label = "Forget after", unit = "s", min = 10, max = 300, step = 10, desc = "How long a player stays listed after their nameplate went away." },
	{ type = "toggle", key = "autoHide", label = "Hide when empty", desc = "Hide the list while no enemies are listed." },
	{ type = "toggle", key = "hideInInstances", label = "Hide in instances", desc = "Off in dungeons, raids and battlegrounds." },
	{ type = "toggle", key = "sound", label = "Sound on a new enemy", desc = "Play a sound when a new hostile player appears. Off by default." },
	{ type = "media", mediaKind = "sound", key = "soundID", label = "Sound", dependsOn = "sound",
		desc = "Which sound to play: EldoUI's sounds, the game's or a SharedMedia pack's." },
	{ type = "header", label = "Look" },
	{ type = "range", key = "maxRows", label = "Rows", min = 3, max = 20, step = 1, desc = "The most players shown at once." },
	{ type = "range", unit = "px", key = "width", label = "Width", min = 120, max = 320, step = 4, desc = "Width of the list in pixels." },
	{ type = "range", unit = "px", key = "rowHeight", label = "Row height", min = 14, max = 28, step = 1, desc = "Height of each player's line in the list." },
	{ type = "range", key = "fontSize", label = "Text size", min = 9, max = 18, step = 1, desc = "Text size in the list." },
	{ type = "toggle", key = "showTitle", label = "Title", desc = "Show \"Enemies (n)\" above the list." },
	{ type = "toggle", key = "showLevel", label = "Level", desc = "Show each player's level, colored by difficulty." },
	{ type = "toggle", key = "background", label = "Background", desc = "A see-through panel behind the list." },
	{ type = "execute", label = "Move", desc = "Unlock EldoUI frames to drag the list.", func = function() E:MoveFrame("EldoUI_EnemySpotter") end },
}
