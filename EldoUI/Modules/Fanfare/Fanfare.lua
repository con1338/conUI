-- Fanfare (earlier title Sound and Fun): play a sound, show big text, flash
-- the screen edges or pop an icon when something happens in the game,
-- built from lists: each trigger is "When" (a source
-- from Sources.lua), "Only if" (simple conditions) and "Do" (sound, text,
-- flash, icon, a line in your own chat). There is no custom code and no raw
-- event names, so it stays within the Midnight addon rules.
--
-- Rules it keeps:
--   * Presentation only. Nothing is sent to chat or the group, nothing acts.
--   * Secret values (whisper sender in chat lockdown) can be shown, never
--     compared: a condition that would need to read one does not fire.
--   * Throttled: per-trigger cooldown, 0.25 s between sounds, at most 3
--     texts waiting, flash caps in E:ScreenFlash, quiet for 5 s after login.
local _, E = ...
local L = E.L

local F = E.fanfare

-- "Take a screenshot": per trigger, off by default.
F.triggerDefaults.actions.screenshot = { enabled = false }
local SCREENSHOT_GAP = 10

local M = E:NewModule("Fanfare", {
	title = "Fanfare",
	aliases = { "Sound and Fun" }, -- earlier title, for search and /eui
	desc = "Sounds, big text, screen flashes and icons for moments in the game: level up, epic loot, whispers, queue pops, boss kills and more. You choose which moments play which effects.",
	category = "Interface",
	frames = { "EldoUI_FanfareSplash" },
	movers = { "EldoUI_Fanfare" },
	blizzard = {},
	savedKeys = { "profile.modules.Fanfare", "private.fanfare" },
	optionsPage = "module:Fanfare",
	presets = { "Arcade", "ClassicHero", "Meme", "MinimalCues", "RaidLeader", "SilentVisual", "Subtle" },
	reload = false,
	defaults = {
		enabled = false,
		style = "Subtle",
		seeded = 0,
		styled = false,
		mute = false,
		channel = "default",
		combatGimmicks = false,
		queueMax = 3,
		soundGap = 0.25,
		splash = { font = "Bebas Neue", size = 56, outline = "THICKOUTLINE", hold = 1.6, anim = "pop", banner = true, width = 600 },
		flash = { style = "edges", alpha = 0.35, duration = 0.4 },
		icon = { size = 56 },
		order = {},
		triggers = {},
	},
})

-- "Reset to defaults" keeps the player's own data and window places
-- (E:ResetModuleSettings, Core/Config.lua).
M.keepOnReset = { "triggers", "order", "seeded" }
M.keepOnResetNote = E.Key("Your own triggers are kept too; the built-in ones go back to how they ship.")
-- After the reset the built-in triggers go back to how they ship.
function M:AfterReset()
	if type(self.db.triggers) ~= "table" then return end
	self:RestoreBuiltins()
end
F.module = M

local LOGIN_GRACE = 5

-- Layouts where the splash must stay smaller or quiet (design.md §2.2).
local LAYOUT_LIMITS = {
	EldoCozy = { size = 52 },
	EldoCozy1000 = { size = 52 },
	EldoPlates = { size = 44, width = 560, noCombat = true },
	EldoPlates2000 = { size = 44, width = 560, noCombat = true },
	EldoJoe = { width = 760 },
}

local COLORS = {
	danger = { 0.898, 0.282, 0.302 },
	warn = { 0.941, 0.706, 0.161 },
	success = { 0.30, 0.85, 0.40 },
	white = { 1, 1, 1 },
	gold = { 1, 0.82, 0 },
}

local Secret = E.Secret

local function Now() return GetTime() end

---------------------------------------------------------------------------
-- Saved triggers
---------------------------------------------------------------------------
-- Fill missing fields and drop wrong types, so built-ins, new triggers and
-- imported ones all have the same shape. Returns false for a trigger that
-- can't be used (unknown source).
local function Normalize(trigger)
	if type(trigger) ~= "table" then return false end
	E.ApplyDefaults(trigger, F.triggerDefaults)
	if type(trigger.actions) ~= "table" then trigger.actions = CopyTable(F.triggerDefaults.actions) end
	for action, defaults in pairs(F.triggerDefaults.actions) do
		if type(trigger.actions[action]) ~= "table" then trigger.actions[action] = CopyTable(defaults) end
	end
	for key, default in pairs(F.triggerDefaults) do
		if type(default) ~= "table" and type(trigger[key]) ~= type(default) then trigger[key] = default end
	end
	for _, part in ipairs({ "conditions" }) do
		for key, default in pairs(F.triggerDefaults[part]) do
			if type(trigger[part][key]) ~= type(default) then trigger[part][key] = default end
		end
	end
	for action, defaults in pairs(F.triggerDefaults.actions) do
		local t = trigger.actions[action]
		for key, default in pairs(defaults) do
			if type(t[key]) ~= type(default) then t[key] = CopyTable and type(default) == "table" and CopyTable(default) or default end
		end
	end
	return F.sources[trigger.source] ~= nil
end
F.Normalize = Normalize

-- A built-in as the player gets it: its name and texts in their language.
-- Names and texts saved in English earlier are shown translated too.
local function BuiltinCopy(id)
	local copy = CopyTable(F.builtins[id])
	copy.name = E:Translate(copy.name)
	local splash, chat = copy.actions.splash, copy.actions.chat
	splash.text, splash.sub = E:Translate(splash.text), E:Translate(splash.sub)
	chat.text = E:Translate(chat.text)
	return copy
end

-- New built-ins are added once; the player's edits are never overwritten.
function M:Seed()
	local db = self.db
	if (db.seeded or 0) >= F.BUILTIN_VERSION and next(db.triggers) then return end
	for _, id in ipairs(F.builtinOrder) do
		if db.triggers[id] == nil then db.triggers[id] = BuiltinCopy(id) end
		if not tContains(db.order, id) then table.insert(db.order, id) end
	end
	db.seeded = F.BUILTIN_VERSION
end

function M:Triggers()
	local list = {}
	for id, trigger in pairs(self.db.triggers) do
		if type(trigger) == "table" and not trigger.deleted then table.insert(list, id) end
	end
	local position = {}
	for i, id in ipairs(self.db.order) do position[id] = i end
	table.sort(list, function(a, b)
		local pa, pb = position[a] or 9999, position[b] or 9999
		if pa ~= pb then return pa < pb end
		return a < b
	end)
	return list
end

---------------------------------------------------------------------------
-- Event dispatcher: one frame, only the events enabled triggers need
---------------------------------------------------------------------------
local dispatcher = CreateFrame("Frame")
local index = {}        -- source key -> { trigger ids }
local registered = {}   -- event -> true
local eventSources = {} -- event -> { source keys }
local loginTime = 0

function M:Rebuild()
	local before = {}
	for key in pairs(index) do before[key] = true end
	wipe(index)
	if self.active then
		for id, trigger in pairs(self.db.triggers) do
			if type(trigger) == "table" and not trigger.deleted and Normalize(trigger) and trigger.enabled then
				index[trigger.source] = index[trigger.source] or {}
				table.insert(index[trigger.source], id)
			end
		end
	end
	F.SyncQuestSources(index)
	local needed = {}
	wipe(eventSources)
	for key in pairs(index) do
		-- A source that watches for a change notes what the game shows now.
		local prime = F.sources[key].prime
		if prime and not before[key] then
			local ok, err = pcall(prime)
			if not ok then geterrorhandler()(("Fanfare source %s: %s"):format(key, tostring(err))) end
		end
		for _, event in ipairs(F.sources[key].events) do
			needed[event] = true
			eventSources[event] = eventSources[event] or {}
			table.insert(eventSources[event], key)
		end
	end
	for event in pairs(registered) do
		if not needed[event] then
			dispatcher:UnregisterEvent(event)
			registered[event] = nil
		end
	end
	for event in pairs(needed) do
		if not registered[event] then
			-- An event this client lacks just stays off.
			if pcall(dispatcher.RegisterEvent, dispatcher, event) then
				registered[event] = true
			else
				E:Debug("Fanfare: event not available:", event)
			end
		end
	end
end

-- Does an enabled trigger with a sound listen to this source? Other modules
-- ask, so the same moment never plays two EldoUI sounds.
function M:Owns(sourceKey)
	for _, id in ipairs(index[sourceKey] or {}) do
		local trigger = self.db.triggers[id]
		if trigger and trigger.actions.sound.id ~= "none" then return true end
	end
	return false
end

function E:FanfareOwns(sourceKey)
	return M.active and M:Owns(sourceKey) or false
end

---------------------------------------------------------------------------
-- Conditions ("Only if")
---------------------------------------------------------------------------
local function Find(list, value)
	if Secret(value) or type(value) ~= "string" then return false end
	value = value:lower()
	for word in list:gmatch("[^,]+") do
		word = strtrim(word):lower()
		if word ~= "" and value:find(word, 1, true) then return true end
	end
	return false
end

local function SenderMatches(list, sender)
	if Secret(sender) or type(sender) ~= "string" or sender == "" then return false end
	local short = sender:lower()
	for word in list:gmatch("[^,]+") do
		word = strtrim(word):lower()
		if word == short then return true end
		if word == "friends" and C_FriendList and C_FriendList.GetFriendInfo then
			local ok, info = pcall(C_FriendList.GetFriendInfo, sender)
			if ok and info then return true end
		elseif word == "guild" and C_GuildInfo and C_GuildInfo.MemberExistsByName then
			local ok, yes = pcall(C_GuildInfo.MemberExistsByName, sender)
			if ok and not Secret(yes) and yes then return true end
		end
	end
	return false
end

local function YesNo(setting, value)
	if setting == "any" then return true end
	if Secret(value) then return false end
	return (setting == "yes") == (value and true or false)
end

function M:ConditionsPass(trigger, payload)
	local c, key = trigger.conditions, trigger.source
	local function Allows(name) return F:SourceAllows(key, name) end
	if c.instance ~= "any" then
		local inInstance, kind = IsInInstance()
		if c.instance == "world" and inInstance then return false end
		if c.instance == "anyInstance" and not inInstance then return false end
		if c.instance == "dungeon" and kind ~= "party" then return false end
		if (c.instance == "raid" or c.instance == "pvp" or c.instance == "arena" or c.instance == "scenario") and kind ~= c.instance then return false end
	end
	if c.combat ~= "any" then
		local inCombat = InCombatLockdown()
		if (c.combat == "in") ~= inCombat then return false end
	end
	if c.group ~= "any" then
		local raid, group = IsInRaid(), IsInGroup()
		if c.group == "solo" and group then return false end
		if c.group == "party" and (not group or raid) then return false end
		if c.group == "raid" and not raid then return false end
		if c.group == "grouped" and not group then return false end
	end
	if not YesNo(c.resting, IsResting()) then return false end
	if c.zone ~= "" and not (Find(c.zone, GetRealZoneText()) or Find(c.zone, GetSubZoneText())) then return false end
	if Allows("minQuality") and c.minQuality > 0 and (payload.quality or 0) < c.minQuality then return false end
	if Allows("sender") and c.sender ~= "" and not SenderMatches(c.sender, payload.sender) then return false end
	-- "Who": friends, guild members or both; a test payload has no kind.
	if Allows("who") and payload.who then
		local who = c.who or "friends"
		if who == "friends" and payload.who ~= "friend" then return false end
		if who == "guild" and payload.who ~= "guild" then return false end
	end
	local level = UnitLevel("player")
	if c.minLevel > 0 and level < c.minLevel then return false end
	if c.maxLevel > 0 and level > c.maxLevel then return false end
	if not YesNo(c.mounted, IsMounted()) then return false end
	if c.chance < 100 and math.random(100) > c.chance then return false end
	return true
end

---------------------------------------------------------------------------
-- Text with {tokens}. Joined with "..", so secret values still display.
---------------------------------------------------------------------------
local function TokenValue(token, payload, trigger)
	local value = payload[token]
	-- Secret test first: comparing a secret value with nil errors.
	if Secret(value) then return value end
	if type(value) == "nil" then
		if token == "name" then value = E:Translate(trigger.name)
		elseif token == "player" then value = E:PlayerName()
		elseif token == "level" then value = UnitLevel("player")
		elseif token == "zone" then value = GetRealZoneText()
		elseif token == "subzone" then value = GetSubZoneText()
		elseif token == "class" then value = UnitClass("player")
		end
	end
	if Secret(value) then return value end
	if type(value) == "number" then return tostring(value) end
	if type(value) == "string" then return value end
	return ""
end

function M:Fill(template, payload, trigger)
	if type(template) ~= "string" or template == "" then return "" end
	local out, pos = "", 1
	while true do
		local first, last, token = template:find("{(%a+)}", pos)
		if not first then return out .. template:sub(pos) end
		out = out .. template:sub(pos, first - 1) .. TokenValue(token, payload, trigger)
		pos = last + 1
	end
end

local function ColorFor(mode, custom, payload)
	if mode == "accent" then return E.media.accentColor end
	if mode == "quality" and payload.quality and C_Item.GetItemQualityColor then
		local r, g, b = C_Item.GetItemQualityColor(payload.quality)
		if r then return { r, g, b } end
	end
	if mode == "class" then return { E:ClassColor("player") } end
	if mode == "whisper" and ChatTypeInfo and ChatTypeInfo.WHISPER then
		local info = ChatTypeInfo.WHISPER
		return { info.r, info.g, info.b }
	end
	if mode == "custom" and type(custom) == "table" then return custom end
	return COLORS[mode] or COLORS.white
end

---------------------------------------------------------------------------
-- Splash text and icon pop
---------------------------------------------------------------------------
local splash, icon
local queue, current, holdTimer = {}, nil, nil

local function Limits()
	return LAYOUT_LIMITS[E.db.general.layout] or {}
end

-- Layout positions shrink on screens under 1440 units tall; the text box
-- shrinks with them so it keeps the same gap to the frames around it.
local function Scale()
	if not E.db.general.layoutFit then return 1 end
	return math.min(1, (UIParent:GetHeight() or 1440) / 1440)
end
M.Scale = Scale

local function CreateSplash()
	splash = CreateFrame("Frame", "EldoUI_FanfareSplash", UIParent)
	splash:SetSize(640, 120)
	splash:SetFrameStrata("HIGH")
	splash:EnableMouse(false)
	splash:Hide()
	splash.banner = CreateFrame("Frame", nil, splash)
	splash.banner:SetPoint("TOPLEFT", 0, -10)
	splash.banner:SetPoint("BOTTOMRIGHT", 0, 10)
	splash.banner:SetFrameLevel(splash:GetFrameLevel())
	splash.line = splash.banner:CreateTexture(nil, "ARTWORK")
	splash.line:SetTexture(E.media.flat)
	splash.line:SetHeight(2)
	splash.line:SetPoint("BOTTOMLEFT")
	splash.line:SetPoint("BOTTOMRIGHT")
	splash.glow = splash:CreateTexture(nil, "BACKGROUND")
	splash.glow:SetTexture(E.media.glow)
	splash.glow:SetAllPoints(splash)

	splash.text = splash:CreateFontString(nil, "OVERLAY")
	splash.text:SetWordWrap(false)
	splash.sub = splash:CreateFontString(nil, "OVERLAY")
	splash.sub:SetWordWrap(false)

	splash.icon = CreateFrame("Frame", nil, splash)
	splash.icon:SetSize(56, 56)
	E:SetTemplate(splash.icon)
	splash.icon.texture = splash.icon:CreateTexture(nil, "ARTWORK")
	splash.icon.texture:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	splash.icon.texture:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(splash.icon.texture)

	E:CreateMover(splash, "EldoUI_Fanfare", L["Fanfare Text"], { "CENTER", "UIParent", "CENTER", 0, 260 }, { sample = { kind = "text" } })
end

function M:StyleSplash()
	if not splash then return end
	local db = self.db.splash
	local scale = Scale()
	local width = math.min(db.width, Limits().width or db.width)
	splash:SetSize(math.floor(width * scale), math.floor(120 * scale))
	E:SetPanelTemplate(splash.banner, true)
	local style = E:ArtStyle()
	local modern = style == "Modern"
	local blizzard = style == "Blizzard"
	splash.banner:SetShown(db.banner)
	splash.line:SetShown(db.banner and modern)
	splash.line:SetVertexColor(unpack(E.media.accentColor))
	splash.glow:SetShown(blizzard and not db.banner)
	local size = math.floor(self.db.icon.size * scale)
	splash.icon:SetSize(size, size)
	E:SetTemplate(splash.icon)
end

local function Layout(entry)
	local db = M.db.splash
	local trigger, payload = entry.trigger, entry.payload
	local s = trigger.actions.splash
	local limits = Limits()
	local size = (s.size and s.size > 0) and s.size or db.size
	if limits.size then size = math.min(size, limits.size) end
	size = math.max(12, math.floor(size * Scale()))
	local font = (s.font and s.font ~= "default") and s.font or db.font
	E:SetMediaFont(splash.text, font, size, db.outline)
	E:SetMediaFont(splash.sub, "default", math.max(12, math.floor(size * 0.4)), "OUTLINE")
	splash.text:SetText(entry.text)
	splash.sub:SetText(entry.sub)
	splash.sub:SetShown(entry.sub ~= "")

	local color = ColorFor(s.colorMode, s.color, payload)
	if s.colorMode == "accent" and E:ArtStyle() == "Blizzard" and not db.banner then color = COLORS.gold end
	splash.text:SetTextColor(color[1], color[2], color[3])
	splash.sub:SetTextColor(unpack(E.media.text.secondary))
	splash.glow:SetVertexColor(color[1], color[2], color[3], 0.35)

	-- Long text shrinks to fit (down to 60 %) and never wraps.
	local maxWidth = splash:GetWidth() - 32
	local showIcon = entry.icon ~= nil
	local iconSize = math.floor(M.db.icon.size * Scale())
	if showIcon then maxWidth = maxWidth - iconSize - 12 end
	local textWidth = splash.text:GetStringWidth()
	if not Secret(textWidth) and textWidth > maxWidth and textWidth > 0 then
		local scaled = math.max(math.floor(size * 0.6), math.floor(size * maxWidth / textWidth))
		E:SetMediaFont(splash.text, font, scaled, db.outline)
	end

	splash.text:ClearAllPoints()
	splash.sub:ClearAllPoints()
	splash.icon:ClearAllPoints()
	local offsetX = showIcon and math.floor((iconSize + 12) / 2) or 0
	if entry.text == "" and showIcon then
		splash.icon:SetPoint("CENTER")
	else
		splash.text:SetPoint("CENTER", offsetX, entry.sub ~= "" and 10 or 0)
		splash.sub:SetPoint("TOP", splash.text, "BOTTOM", 0, -4)
		if showIcon then splash.icon:SetPoint("RIGHT", splash.text, "LEFT", -12, entry.sub ~= "" and -10 or 0) end
	end
	splash.text:SetShown(entry.text ~= "")
	splash.banner:SetShown(db.banner and entry.text ~= "")
	splash.icon:SetShown(showIcon)
	if showIcon then
		splash.icon.texture:SetTexture(entry.icon)
		local border = s.colorMode == "quality" and color or E.media.accentColor
		splash.icon:SetBackdropBorderColor(border[1], border[2], border[3], 1)
	end
end

local ShowNext

local function Finish()
	holdTimer = nil
	E:SlideOut(splash, "UP", function()
		current = nil
		ShowNext()
	end)
end

ShowNext = function()
	if current or #queue == 0 or not splash then return end
	current = table.remove(queue, 1)
	Layout(current)
	local anim = current.trigger.actions.splash.anim
	if anim == "default" then anim = M.db.splash.anim end
	if anim == "pop" then E:PopIn(splash, 0.6)
	elseif anim == "bounce" then E:PopIn(splash, 1.3)
	elseif anim == "none" then splash:SetAlpha(1); splash:Show()
	else E:SlideIn(splash, "DOWN") end
	if current.icon and anim ~= "pop" and anim ~= "none" then E:PopIn(splash.icon, 0.6) end
	local hold = current.trigger.actions.splash.hold
	if not hold or hold <= 0 then hold = M.db.splash.hold end
	holdTimer = C_Timer.NewTimer(hold, Finish)
end

function M:QueueSplash(entry)
	if not splash then return end
	-- The same trigger again replaces what shows and restarts its time.
	if current and current.id == entry.id then
		if holdTimer then holdTimer:Cancel() end
		current = nil
		table.insert(queue, 1, entry)
		ShowNext()
		return
	end
	if #queue >= self.db.queueMax then return end
	table.insert(queue, entry)
	ShowNext()
end

function M:ClearSplash()
	wipe(queue)
	if holdTimer then holdTimer:Cancel(); holdTimer = nil end
	current = nil
	if splash then splash:Hide() end
end

---------------------------------------------------------------------------
-- Firing a trigger
---------------------------------------------------------------------------
local lastFired, lastSound, lastScreenshot = {}, 0, nil

-- True while the game runs a boss encounter.
local function EncounterRunning()
	local api = C_InstanceEncounter
	if api and type(api.IsEncounterInProgress) == "function" then
		local ok, running = pcall(api.IsEncounterInProgress)
		return ok and running == true
	end
	return false
end

local function IconFor(trigger, payload)
	local texture = trigger.actions.icon.texture
	if texture and texture ~= "auto" and texture ~= "" then return tonumber(texture) or texture end
	return payload.icon or F.sources[trigger.source].icon or E.media.icon
end

-- test = true ignores conditions, cooldown and login quiet time.
function M:Fire(id, payload, test)
	local trigger = self.db.triggers[id]
	if not trigger or not Normalize(trigger) then return false end
	payload = payload or {}
	local now = Now()
	if not test then
		if not F.sources[trigger.source].noGrace and now - loginTime < LOGIN_GRACE then return false end
		if lastFired[id] and now - lastFired[id] < (trigger.cooldown or 0) then return false end
		if not self:ConditionsPass(trigger, payload) then return false end
	end
	lastFired[id] = now
	local actions = trigger.actions

	local sound = actions.sound
	if sound.id ~= "none" and not self.db.mute and (test or now - lastSound >= self.db.soundGap) then
		lastSound = now
		local channel = E:SoundChannel(sound.channel == "default" and self.db.channel or sound.channel)
		local willPlay, _, entry = E:PlayMedia(sound.id, channel, { fallback = sound.fallback ~= "none" and sound.fallback or nil, preview = test })
		if test then
			-- Say what happened, so a silent test can be told apart from a muted one.
			if willPlay then
				E:Print(L["Playing %s on the %s channel."]:format(entry and entry.name or sound.id, channel))
			else
				E:Print(L["The game did not play %s (%s). Restart the game if EldoUI's sound files are new, and check the %s volume."]:format(
					E:MediaLabel("sound", sound.id), sound.id, channel))
			end
		end
	elseif test then
		E:Print(sound.id == "none" and L["This trigger has no sound."] or L["Fanfare sounds are muted (/eui fx mute)."])
	end

	-- A screenshot a moment later, so the text and icon are in it; at most
	-- one every SCREENSHOT_GAP seconds. Only the player's own picture.
	if actions.screenshot and actions.screenshot.enabled and Screenshot
		and (not lastScreenshot or now - lastScreenshot >= SCREENSHOT_GAP) then
		lastScreenshot = now
		C_Timer.After(0.5, function() Screenshot() end)
	end

	-- Visuals in combat only when allowed (never on the nameplate layout
	-- unless the trigger itself asks for it).
	local visuals = true
	if InCombatLockdown() and not test then
		visuals = trigger.allowInCombat or (self.db.combatGimmicks and not Limits().noCombat)
	end
	if not visuals then return true end

	if actions.flash.enabled and self.db.flash.style ~= "off" then
		local style = actions.flash.style
		if style == "default" then style = self.db.flash.style end
		local alpha = actions.flash.alpha > 0 and actions.flash.alpha or self.db.flash.alpha
		E:ScreenFlash(ColorFor(actions.flash.colorMode, actions.flash.color, payload), alpha, self.db.flash.duration, style)
	end
	-- The center text and icon stay off during a boss encounter: the boss
	-- info box and the boss warnings use the middle of the screen then. The
	-- sound and the screen flash still play.
	local showIcon = actions.icon.enabled
	if (actions.splash.enabled or showIcon) and (test or not EncounterRunning()) then
		self:QueueSplash({
			id = id, trigger = trigger, payload = payload,
			text = actions.splash.enabled and self:Fill(E:Translate(actions.splash.text), payload, trigger) or "",
			sub = actions.splash.enabled and self:Fill(E:Translate(actions.splash.sub), payload, trigger) or "",
			icon = showIcon and IconFor(trigger, payload) or nil,
		})
	end
	if actions.chat.enabled and actions.chat.text ~= "" then
		-- Your own chat frame only; nothing is ever sent.
		DEFAULT_CHAT_FRAME:AddMessage(E.color .. "EldoUI|r: " .. self:Fill(actions.chat.text, payload, trigger))
	end
	return true
end

dispatcher:SetScript("OnEvent", function(_, event, ...)
	for _, key in ipairs(eventSources[event] or {}) do
		local source = F.sources[key]
		local ok, payload = pcall(source.payload, event, ...)
		if not ok then
			geterrorhandler()(("Fanfare source %s: %s"):format(key, tostring(payload)))
		elseif payload then
			for _, id in ipairs(index[key] or {}) do
				local fired, err = pcall(M.Fire, M, id, payload)
				if not fired then geterrorhandler()(err) end
			end
		end
	end
end)

-- Run the triggers on one source with a payload another module made
-- (Rare Alerts feeds "rare"), the same way the event dispatcher does,
-- conditions and cooldowns included. Returns how many triggers fired.
function M:Emit(sourceKey, payload)
	if not self.active or not F.sources[sourceKey] then return 0 end
	local fired = 0
	for _, id in ipairs(index[sourceKey] or {}) do
		local ok, result = pcall(M.Fire, M, id, payload or {})
		if not ok then
			geterrorhandler()(result)
		elseif result then
			fired = fired + 1
		end
	end
	return fired
end

-- Test button and /eui fx test: the trigger's sample, no conditions.
function M:Test(id)
	local trigger = self.db.triggers[id]
	if not trigger or not Normalize(trigger) then return false end
	-- Sample values are kept in English and shown in the language picked.
	local sample = {}
	for token, value in pairs(F.sources[trigger.source].sample or {}) do sample[token] = E:Translate(value) end
	return self:Fire(id, sample, true)
end

---------------------------------------------------------------------------
-- Editing (used by Options.lua)
---------------------------------------------------------------------------
local function NewId(base)
	base = (base or "trigger"):lower():gsub("[^a-z0-9_]", "")
	if base == "" or base:match("^%d") then base = "t" .. base end
	local id, n = base, 1
	while M.db.triggers[id] do n = n + 1; id = base .. n end
	return id
end

function M:NewTrigger()
	local id = NewId("custom")
	local trigger = CopyTable(F.triggerDefaults)
	trigger.name = L["My trigger"]
	trigger.actions.sound.id = "eldo:EldoChime"
	trigger.actions.splash.enabled = true
	trigger.actions.splash.text = "{name}" -- no-L: {token} only
	self.db.triggers[id] = trigger
	table.insert(self.db.order, id)
	self.db.editing = id
	self:Rebuild()
	return id
end

function M:DuplicateTrigger(id)
	local source = self.db.triggers[id]
	if not source then return end
	local copy = CopyTable(source)
	copy.builtin = nil
	copy.name = L["%s (copy)"]:format(E:Translate(copy.name))
	local newId = NewId(id)
	self.db.triggers[newId] = copy
	table.insert(self.db.order, newId)
	self.db.editing = newId
	self:Rebuild()
	return newId
end

-- Built-ins are hidden (they can come back); the player's own are removed.
function M:DeleteTrigger(id)
	local trigger = self.db.triggers[id]
	if not trigger then return end
	if trigger.builtin then trigger.deleted = true else self.db.triggers[id] = nil end
	for i, other in ipairs(self.db.order) do
		if other == id and not trigger.builtin then table.remove(self.db.order, i) break end
	end
	self.db.editing = self:Triggers()[1]
	self:Rebuild()
end

function M:RestoreBuiltins()
	for _, id in ipairs(F.builtinOrder) do
		local trigger = BuiltinCopy(id)
		-- A later preview fills these defaults even when Fanfare is off.
		Normalize(trigger)
		self.db.triggers[id] = trigger
		if not tContains(self.db.order, id) then table.insert(self.db.order, id) end
	end
	self:Rebuild()
end

-- Undo each built-in setting that still has the value Reset gave it.
-- Lists like colors stay together when the player changes them.
local function UndoBuiltin(value, before, reset)
	if E.DeepEqual(before, reset) then return value end
	if E.DeepEqual(value, reset) then return type(before) == "table" and CopyTable(before) or before end
	if type(value) ~= "table" or type(before) ~= "table" or type(reset) ~= "table"
		or value[1] ~= nil or before[1] ~= nil or reset[1] ~= nil then return value end
	local restored = {}
	for key, setting in pairs(value) do restored[key] = setting end
	for key, setting in pairs(reset) do restored[key] = UndoBuiltin(value[key], before[key], setting) end
	for key, setting in pairs(before) do
		if reset[key] == nil then restored[key] = UndoBuiltin(value[key], setting, nil) end
	end
	return restored
end

function M:AfterResetUndo(before, reset)
	local db = self.db
	if type(db.triggers) ~= "table" or type(db.order) ~= "table" then return end
	local oldTriggers = type(before.triggers) == "table" and before.triggers or {}
	local triggers = {}
	for id, trigger in pairs(db.triggers) do triggers[id] = trigger end
	for _, id in ipairs(F.builtinOrder) do
		local trigger = triggers[id]
		if type(trigger) ~= "table" or trigger.builtin == id then
			triggers[id] = UndoBuiltin(trigger, oldTriggers[id], reset.triggers[id])
		end
	end
	db.triggers = triggers

	-- Keep later moves and list changes. Drop slots Reset added for built-ins
	-- that Undo removes from the list again.
	local order = {}
	local oldOrder = type(before.order) == "table" and before.order or {}
	for _, id in ipairs(db.order) do
		if not F.builtins[id] or triggers[id] ~= nil or tContains(oldOrder, id) then
			order[#order + 1] = id
		end
	end
	db.order = order
end

function M:MoveTrigger(id, delta)
	local order = self.db.order
	for i, other in ipairs(order) do
		if other == id then
			local j = i + delta
			if order[j] then order[i], order[j] = order[j], order[i] end
			return
		end
	end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnInitialize()
	self:Seed()
end

function M:OnEnable()
	if not splash then CreateSplash() end
	self:Seed()
	-- First time on: the Subtle style.
	if not self.db.styled then
		self.db.styled = true
		E:ApplyStyle("Fanfare", self.db.style or "Subtle")
	end
	-- Switched on later in a session: no quiet time.
	if loginTime == 0 then loginTime = Now() end
	if F.ResetEdges then F.ResetEdges() end
	if F.ResetSeen then F.ResetSeen() end
	self:StyleSplash()
	self:Rebuild()
end

function M:OnDisable()
	self:Rebuild()
	self:ClearSplash()
end

function M:OnProfileChanged()
	self:Seed()
	self:StyleSplash()
	self:Rebuild()
end

E:RegisterEvent("PLAYER_LOGIN", function() loginTime = Now() end, M)
E:RegisterEvent("UI_SCALE_CHANGED", function() if M.active then M:StyleSplash() end end, M)
E:RegisterEvent("DISPLAY_SIZE_CHANGED", function() if M.active then M:StyleSplash() end end, M)
-- A boss pull clears the center text (a pull countdown's last number).
E:RegisterEvent("ENCOUNTER_START", function() if M.active then M:ClearSplash() end end, M)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
local function FindTrigger(text)
	text = (text or ""):lower()
	if text == "" then return nil end
	if M.db.triggers[text] then return text end
	for _, id in ipairs(M:Triggers()) do
		if M.db.triggers[id].name:lower():find(text, 1, true) == 1 then return id end
	end
end

E:AddCommand("fx", "test <trigger> | list | mute  Fanfare triggers", function(arg)
	local command, rest = (arg or ""):match("^(%S*)%s*(.-)$")
	command = command:lower()
	if not M.db then return end
	if command == "list" then
		for _, id in ipairs(M:Triggers()) do
			local trigger = M.db.triggers[id]
			E:Print(("%s%-3s|r  %s  " .. E:TextHex("secondary") .. "(%s, %s)|r"):format(trigger.enabled and E:TextHex("good") or E:TextHex("secondary"),
				trigger.enabled and L["on"] or L["off"], E:Translate(trigger.name), id, F.sources[trigger.source] and L[F.sources[trigger.source].label] or "?"))
		end
	elseif command == "mute" then
		M.db.mute = not M.db.mute
		E:Print(M.db.mute and L["Fanfare sounds muted."] or L["Fanfare sounds on."])
	elseif command == "test" then
		local id = FindTrigger(rest)
		if not id then return E:Print(L["Usage: /eui fx test <trigger>  (see /eui fx list)"]) end
		if not M.active then E:Print(L["Fanfare is off; testing anyway."]) end
		if not splash then CreateSplash(); M:StyleSplash() end
		M:Test(id)
	else
		E:Print(L["Usage: /eui fx list | test <trigger> | mute"])
	end
end, "Tools")

E:AddCommand("sound", "<id>  play a sound from the media library (eldo:Tada, kit:READY_CHECK, lsm:Air Horn)", function(arg)
	local id = strtrim(arg or "")
	if id == "" then return E:Print(L["Usage: /eui sound <id>  (see /eui media sound)"]) end
	local played, _, entry = E:PlayMedia(id, nil, { preview = true })
	if not E:GetMedia("sound", id) then
		E:Print(L["No sound with the id %s (see /eui media sound)."]:format(id))
		if E.errors and E.errors.Add then
			E.errors:Add("warning", ("EldoUI: /eui sound: no sound with the id %s in the media library (see /eui media sound)."):format(id))
		end
	elseif not played then
		E:Print(L["The game would not play %s."]:format((entry and entry.name) or id))
	end
end, "Tools")

E:AddCommand("media", "[sound|font|statusbar] [filter]  list the media library", function(arg)
	local kind, filter = (arg or ""):match("^(%S*)%s*(.-)$")
	kind = kind ~= "" and kind:lower() or "sound"
	if not E.mediaRegistry[kind] then return E:Print(L["Kinds: sound, font, statusbar, border, background"]) end
	filter = filter:lower()
	local lines = {}
	for id, entry in E:IterateMedia(kind) do
		if filter == "" or id:lower():find(filter, 1, true) or entry.source:lower():find(filter, 1, true) then
			table.insert(lines, ("%s\t%s\t%s"):format(id, entry.name, entry.source))
		end
	end
	E:ShowCopyBox(L["Media: %s (%d)"]:format(kind, #lines), L["Id, name and source. Use the id with /eui sound."], table.concat(lines, "\n"))
end, "Tools")
