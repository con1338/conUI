-- Combat HUD: mirror timers (breath, fatigue, feign death) and the quest
-- timer. Skin, mover and size for Blizzard's MirrorTimerContainer
-- and QuestTimerFrame (Blizzard_QuestTimer, normally inside the objective
-- tracker). Times and labels stay Blizzard's.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local K = E.CombatKit
local M = E.CombatHUD

local ID = "mirror-quest-timers"
local GROUP = "timers"
local MIRROR_MOVER = "EldoUI_MirrorTimers"
local QUEST_MOVER = "EldoUI_QuestTimer"

local F = { key = "timers", id = ID, title = "Timers",
	install = { skin = true, move = true }, reload = { skin = true, move = true } }

F.defaults = {
	mirror = true,      -- EldoUI handles the mirror timers
	quest = true,       -- EldoUI handles the quest timer
	width = 220, height = 14,
	scale = 100,
	texture = "", font = "THEME", fontSize = 11,
	colorMode = "custom",
	colors = { BREATH = { 0.25, 0.55, 1 }, EXHAUSTION = { 1, 0.8, 0.2 }, FEIGNDEATH = { 1, 0.6, 0.2 }, DEATH = { 0.6, 0.6, 0.6 } },
	hideMirror = false,
	hideQuest = true,
}

local function DB() return M.db.timers end
local function Allowed(action) return M.active and E:BlizzardAllowed(ID, action) end
local function FontFile()
	return K.FontPath(DB().font)
end

---------------------------------------------------------------------------
-- Mirror timers
---------------------------------------------------------------------------
local timerType = setmetatable({}, { __mode = "k" }) -- timer frame -> "BREATH", ...
local setupHooked = setmetatable({}, { __mode = "k" })

local function TimerColor(kind)
	local db = DB()
	if db.colorMode == "accent" then
		local r, g, b = unpack(E.media.accentColor)
		return r, g, b
	elseif db.colorMode == "class" then
		return E:ClassColor("player")
	end
	local color = kind and db.colors[kind] or db.colors.BREATH
	return unpack(color)
end

local function SkinTimer(timer)
	if not Allowed("skin") or not DB().mirror then return end
	local db = DB()
	local bar = timer.StatusBar
	K.StripTextures(GROUP, timer)
	if bar then
		if db.colorMode ~= "blizzard" then
			K.BarTexture(GROUP, bar, K.TexturePath(db.texture ~= "" and db.texture or nil))
			bar:SetStatusBarColor(TimerColor(timerType[timer]))
		end
		K.Backdrop(GROUP, timer, bar, E.pixel, true)
	end
	K.Font(GROUP, timer.Text, db.fontSize, nil, FontFile())
end

local function SizeTimer(timer)
	if not Allowed("move") or not DB().mirror then return end
	local db = DB()
	local bar = timer.StatusBar
	if bar then bar:SetSize(db.width, db.height) end
	timer:SetSize(db.width + 11, db.height + 19)
end

local function HookTimer(timer)
	if setupHooked[timer] or type(timer.Setup) ~= "function" then return end
	setupHooked[timer] = true
	-- Setup puts Blizzard's bar texture back for every new timer.
	hooksecurefunc(timer, "Setup", function(self, kind)
		if K.Plain(kind) then timerType[self] = kind end
		SkinTimer(self)
	end)
end

local function MirrorTimers()
	local container = MirrorTimerContainer
	return container and container.mirrorTimers or {}
end

local function ApplyMirror(self, db)
	local container = MirrorTimerContainer
	if not container then return end
	local handled = db.mirror
	for _, timer in ipairs(MirrorTimers()) do
		HookTimer(timer)
		SkinTimer(timer)
		SizeTimer(timer)
	end
	if Allowed("move") and handled then
		local holder = self.mirrorHolder
		holder:SetSize((db.width + 11) * db.scale / 100, (db.height + 19) * db.scale / 100)
		K.Pin(container, {
			anchor = function() return "TOP", holder, "TOP", 0, 0 end,
			scale = function() return DB().scale / 100 end,
			active = function() return Allowed("move") and DB().mirror end,
		})
		if container.MarkDirty then container:MarkDirty() end
	else
		K.Unpin(container)
	end
	if E:BlizzardHidden(ID) and handled and db.hideMirror then
		K.Parent(container, K.hider)
	else
		K.RestoreParent(container)
	end
end

---------------------------------------------------------------------------
-- Quest timer
---------------------------------------------------------------------------
local questHooked = false

local function SkinQuest()
	local frame = QuestTimerFrame
	if not frame or not Allowed("skin") or not DB().quest then return end
	if frame.Border then
		K.StripTextures(GROUP, frame.Border)
		if frame.Border.NineSlice then K.Alpha0(GROUP, frame.Border.NineSlice) end
		for _, child in ipairs({ frame.Border:GetChildren() }) do K.StripTextures(GROUP, child) end
	end
	K.StripTextures(GROUP, frame)
	if frame.NineSlice then K.Alpha0(GROUP, frame.NineSlice) end
	if frame.Header then
		K.StripTextures(GROUP, frame.Header)
		K.Font(GROUP, frame.Header.Text, DB().fontSize + 1, nil, FontFile())
	end
	K.Backdrop(GROUP, frame, frame, 0, true)
	for _, row in ipairs(frame.activeElements or {}) do
		K.Font(GROUP, row.Name, DB().fontSize, nil, FontFile())
	end
end

local function ApplyQuest(self, db)
	local frame = QuestTimerFrame
	if not frame then return end
	if not questHooked and type(frame.UpdateQuestTimers) == "function" then
		questHooked = true
		hooksecurefunc(frame, "UpdateQuestTimers", SkinQuest)
	end
	SkinQuest()
	if Allowed("move") and db.quest then
		-- Out of the objective tracker and onto its own mover.
		local holder = self.questHolder
		K.Parent(frame, UIParent)
		K.Pin(frame, {
			anchor = function() return "TOP", holder, "TOP", 0, 0 end,
			scale = function() return DB().scale / 100 end,
			active = function() return Allowed("move") and DB().quest end,
		})
	else
		K.Unpin(frame)
	end
	if E:BlizzardHidden(ID) and db.quest and db.hideQuest then
		K.Parent(frame, K.hider)
	elseif not (Allowed("move") and db.quest) then
		K.RestoreParent(frame)
	end
end

---------------------------------------------------------------------------
-- Feature
---------------------------------------------------------------------------
function F:Setup()
	self.mirrorHolder = K.Holder(M, MIRROR_MOVER, L["Mirror Timers"], { "TOP", "UIParent", "TOP", 0, -110 }, 231, 33, { sample = { kind = "bar" } })
	self.questHolder = K.Holder(M, QUEST_MOVER, L["Quest Timer"], { "TOPRIGHT", "UIParent", "TOPRIGHT", -330, -300 }, 158, 72, { sample = { kind = "panel" } })
end

function F:Apply(db)
	if not Allowed("skin") then K.Undo(GROUP) end
	ApplyMirror(self, db)
	E:OnBlizzardAddOn("Blizzard_QuestTimer", function()
		if M.active and E:BlizzardAllowed(ID) then ApplyQuest(F, M.db.timers) end
	end)
end

function F:Restore()
	if MirrorTimerContainer then
		K.Unpin(MirrorTimerContainer)
		K.RestoreParent(MirrorTimerContainer)
	end
	if QuestTimerFrame then
		K.Unpin(QuestTimerFrame)
		K.RestoreParent(QuestTimerFrame)
	end
	K.Undo(GROUP)
end

local NotSkin, NotMove, NotHide = M.Off(ID, "skin"), M.Off(ID, "move"), M.Off(ID, "hide")
local function Off() return not E:BlizzardAllowed(ID) end
local function Textures() local v = K.TextureValues(); v[""] = L["Theme texture"]; return v end

F.switches = {
	skin = L["Flat bars, theme font and a plain box for the quest timer."],
	move = L["Own movers for the mirror timers and the quest timer, and the size below."],
	hide = L["Hide the timers checked below."],
}
-- The per-timer colors only matter with Color per timer.
local function NotCustom() return NotSkin() or DB().colorMode ~= "custom" end
F.options = {
	{ type = "toggle", key = "timers.mirror", label = "Mirror timers", hidden = Off,
		desc = "EldoUI skins and places the breath, fatigue and feign death bars. Off leaves them to Blizzard." },
	{ type = "toggle", key = "timers.quest", label = "Quest timer", hidden = Off,
		desc = "EldoUI skins the quest timer and moves it out of the objective tracker onto its own mover. Off leaves it to Blizzard." },
	{ type = "header", label = "Size", hidden = NotMove },
	{ type = "range", key = "timers.width", label = "Bar width", min = 100, max = 400, step = 1, hidden = NotMove,
		desc = "Width of the mirror timer bars." },
	{ type = "range", key = "timers.height", label = "Bar height", min = 6, max = 30, step = 1, hidden = NotMove,
		desc = "Height of the mirror timer bars." },
	{ type = "range", key = "timers.scale", label = "Scale", unit = "%", min = 50, max = 200, step = 5, hidden = NotMove,
		desc = "Scale of the mirror timers and the quest timer, in percent." },
	{ type = "header", label = "Look", hidden = NotSkin },
	{ type = "select", key = "timers.colorMode", label = "Bar color", hidden = NotSkin,
		values = { blizzard = "Blizzard art", custom = "Color per timer", class = "Class color", accent = "Accent color" },
		desc = "Blizzard art keeps Blizzard's bar textures." },
	{ type = "select", key = "timers.texture", label = "Bar texture", values = Textures, hidden = NotSkin, desc = "Texture of the timer bars." },
	{ type = "color", key = "timers.colors.BREATH", label = "Breath", hidden = NotCustom, desc = "Color of the breath bar when you are under water." },
	{ type = "color", key = "timers.colors.EXHAUSTION", label = "Fatigue", hidden = NotCustom, desc = "Color of the fatigue bar in deep water." },
	{ type = "color", key = "timers.colors.FEIGNDEATH", label = "Feign death", hidden = NotCustom, desc = "Color of the feign death bar." },
	{ type = "color", key = "timers.colors.DEATH", label = "Death", hidden = NotCustom, desc = "Color of the death timer bar, when the game shows one." },
	{ type = "media", mediaKind = "font", default = "THEME", defaultLabel = "Theme font", key = "timers.font", label = "Font", hidden = NotSkin, desc = "Font of the timer texts." },
	{ type = "range", key = "timers.fontSize", label = "Text size", min = 6, max = 20, step = 1, hidden = NotSkin,
		desc = "Size of the timer texts." },
	{ type = "header", label = "Hide", hidden = NotHide },
	{ type = "toggle", key = "timers.hideMirror", label = "Hide mirror timers", hidden = NotHide, desc = "Blizzard's breath, fatigue and feign death bars stay hidden." },
	{ type = "toggle", key = "timers.hideQuest", label = "Hide quest timer", hidden = NotHide, desc = "Blizzard's quest timer stays hidden." },
}

M:AddFeature(F)
