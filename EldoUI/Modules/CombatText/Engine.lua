-- Combat Text engine: scroll areas (one EldoUI mover each), one shared line
-- pool, one updater, merging, rate limits and formatting.
--
-- Public API (also for plugins, through the global EldoUI):
--   EldoUI.CombatText:Show(text, areaKey, opts)
--       text     plain text, or a secret value from the game (drawn as is)
--       areaKey  "incoming", "target", "notify", "static" or "customN"
--       opts     { color = { r, g, b }, sticky = bool, icon = fileID,
--                  fontSize = n, sound = mediaID }
--   EldoUI.CombatText:RegisterAnimation(key, def)   (Animations.lua)
--
-- Secret rules: a line's text is set with SetFormattedText; payload values
-- the game keeps secret go in as they are (the game draws them). Lua sums,
-- compares and colors only values issecretvalue says are plain. Lines are
-- never measured: positions come from the box size and a fixed line height,
-- and the icon hangs on the text (a leaf, nothing else anchors to a line).
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local M = E:GetModule("CombatText")
local issecret = M.issecret

local MAX_LINES = 96       -- every scroll line on screen at once
local BACKLOG = 1.2        -- seconds a line may wait for room before it is joined
local DROP_AFTER = 2.5     -- seconds of backlog after which extra lines are dropped
local CODES = { amount = true, name = true, spell = true, type = true, count = true, item = true, total = true, text = true }

local holders = {}   -- area key -> holder frame
local runtime = {}   -- area key -> { lastStart, lastLine }
local active = {}    -- lines on screen (or waiting for their start)
local pool = {}
local buckets = {}   -- merge buckets: area .. event -> { payload, count }
local driver = CreateFrame("Frame")
driver:Hide()

M.engineStats = { shown = 0, merged = 0, dropped = 0 }

---------------------------------------------------------------------------
-- Areas
---------------------------------------------------------------------------
local function MoverName(key)
	local index = key:match("^custom(%d)$")
	if index then return "EldoUI_SCTCustom" .. index end
	return M.AREA_MOVERS[key]
end
M.MoverName = MoverName

-- Custom areas start in the loot & info slot and stack downwards.
local function DefaultPoint(key)
	local index = tonumber(key:match("^custom(%d)$") or "")
	if index then
		local above = index == 1 and "EldoUI_SCTStaticMover" or ("EldoUI_SCTCustom%dMover"):format(index - 1)
		return { "TOP", above, "BOTTOM", 0, -8 }
	end
	return M.AREA_POINTS[key]
end

local function Holder(key)
	local holder = holders[key]
	if holder then return holder end
	local area = M.db.areas[key]
	holder = CreateFrame("Frame", nil, UIParent)
	holder:SetSize(area.width, area.height)
	holder:SetFrameStrata("MEDIUM")
	holder:SetFrameLevel(40)
	holders[key] = holder
	local previous = E.currentModule
	E.currentModule = M
	local path = "areas." .. key .. "."
	E:CreateMover(holder, MoverName(key), L["Combat Text: %s"]:format(M:AreaTitle(key)), DefaultPoint(key),
		{ enabledPath = { "areas", key, "enabled" }, sample = { kind = "text" },
			sizeKeys = { width = { key = path .. "width", min = 60, max = 800 }, height = { key = path .. "height", min = 30, max = 600 } },
			menu = function(root, mover) if M.AreaMenu then M.AreaMenu(root, mover) end end })
	E.currentModule = previous
	return holder
end

function M:GetAreaFrame(key)
	return holders[key]
end

local function Runtime(key)
	local rt = runtime[key]
	if not rt then
		rt = { lastStart = 0 }
		runtime[key] = rt
	end
	return rt
end

-- Holders and movers follow the settings: size, title, shown.
function M:ApplyAreas()
	local running = self:ScrollRunning()
	local wanted = {}
	-- The four built-in areas always have their mover (so a layout can
	-- place them); custom ones only while they exist.
	for _, key in ipairs(self.AREA_KEYS) do
		if self.active and not holders[key] then Holder(key) end
	end
	for _, key in ipairs(self:AreaKeys()) do
		local area = self.db.areas[key]
		wanted[key] = true
		-- In Combat Text's own move mode an area that is off shows too, so
		-- it can be placed before it is turned on.
		if running and (area.enabled or self.areaMode) then
			local holder = Holder(key)
			holder:SetSize(area.width, area.height)
			holder:Show()
			local mover = E.movers[MoverName(key)]
			if mover then
				mover:Show()
				E:SetMoverTitle(mover.name, L["Combat Text: %s"]:format(self:AreaTitle(key)))
			end
		end
	end
	for key, holder in pairs(holders) do
		local area = wanted[key] and self.db.areas[key]
		if not (running and area and (area.enabled or self.areaMode)) then
			self:ReleaseArea(key)
			holder:Hide()
			local mover = E.movers[MoverName(key)]
			if mover then mover:Hide() end
		end
	end
end

-- A new custom area (up to four). Returns its key, or nil when all four exist.
function M:AddCustomArea()
	for index = 1, self.CUSTOM_MAX do
		local key = "custom" .. index
		if type(self.db.areas[key]) ~= "table" then
			self.db.areas[key] = self.CustomAreaDefaults(index)
			self.db.editArea = key
			self:ApplyAreas()
			return key
		end
	end
end

function M:DeleteCustomArea(key)
	if not (type(key) == "string" and key:match("^custom%d$")) then return false end
	self:ReleaseArea(key)
	self.db.areas[key] = nil
	-- The drag goes from both stores: the normal one and Gamepad Mode UI's,
	-- so the next custom area (the same key) starts at its default place.
	local name = MoverName(key)
	E.db.movers[name] = nil
	local gamepad = type(E.db.gamepadUI) == "table" and E.db.gamepadUI.movers
	if type(gamepad) == "table" then gamepad[name] = nil end
	for eventKey, ev in pairs(self.db.events) do
		if ev.area == key then ev.area = self.eventInfo[eventKey] and self.eventInfo[eventKey].area or "notify" end
	end
	if self.db.editArea == key then self.db.editArea = "incoming" end
	self:ApplyAreas()
	return true
end

---------------------------------------------------------------------------
-- Lines
---------------------------------------------------------------------------
local function NewLine()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(10, 10)
	frame:Hide()
	local text = frame:CreateFontString(nil, "OVERLAY")
	E:UseNameFont(text)
	text:SetWordWrap(false)
	local icon = frame:CreateTexture(nil, "OVERLAY")
	E:TrimIcon(icon)
	icon:Hide()
	return { frame = frame, text = text, icon = icon }
end

local function Release(index)
	local line = active[index]
	if not line then return end
	table.remove(active, index)
	line.frame:Hide()
	line.frame:ClearAllPoints()
	line.text:SetText("")
	line.icon:Hide()
	local rt = runtime[line.area]
	if rt and rt.lastLine == line then rt.lastLine = nil end
	line.args, line.payload, line.anim, line.sound = nil, nil, nil, nil
	pool[#pool + 1] = line
end

local function ReleaseLine(line)
	for index = #active, 1, -1 do
		if active[index] == line then return Release(index) end
	end
end

function M:ReleaseArea(key)
	for index = #active, 1, -1 do
		if not key or active[index].area == key then Release(index) end
	end
	if key then
		local rt = runtime[key]
		if rt then rt.lastStart, rt.lastLine = 0, nil end
	else
		for _, rt in pairs(runtime) do rt.lastStart, rt.lastLine = 0, nil end
	end
end

function M:ReleaseAll()
	self:ReleaseArea(nil)
	wipe(buckets)
end

local function Acquire()
	if #active >= MAX_LINES then Release(1) end
	local line = table.remove(pool) or NewLine()
	active[#active + 1] = line
	return line
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
local compiled = {}  -- template -> { fmt, fields }

local function Compile(template)
	local entry = compiled[template]
	if entry then return entry end
	local fields = {}
	local fmt = tostring(template or ""):gsub("%%", "%%%%"):gsub("{(%a+)}", function(code)
		if CODES[code] then
			fields[#fields + 1] = code
			return "%s"
		end
	end)
	entry = { fmt = fmt, fields = fields }
	compiled[template] = entry
	return entry
end

-- A number as the player chose (short 12.3K, grouped 12,345, plain). The
-- game's helpers take secret values; their result is drawn as it is.
function M:FormatNumber(value)
	local mode = self.db.scroll.numbers
	-- issecret first: comparing a secret with anything (nil included) errors.
	if issecret(value) then
		if mode == "short" and AbbreviateNumbers then return AbbreviateNumbers(value) end
		if mode == "grouped" and BreakUpLargeNumbers then return BreakUpLargeNumbers(value) end
		return value
	end
	if type(value) == "nil" then return "" end
	if type(value) ~= "number" then return tostring(value) end
	if mode == "short" and AbbreviateNumbers then return AbbreviateNumbers(value) end
	if mode == "grouped" and BreakUpLargeNumbers then return BreakUpLargeNumbers(value) end
	return tostring(math.floor(value + 0.5))
end

local function Render(line)
	local entry = Compile(line.template)
	local payload = line.payload or {}
	local args, anySecret = {}, false
	for index, field in ipairs(entry.fields) do
		local value = payload[field]
		if field == "amount" then value = M:FormatNumber(value) end
		if issecret(value) then
			anySecret = true
		elseif type(value) == "nil" then
			value = ""
		elseif type(value) ~= "string" then
			value = tostring(value)
		end
		args[index] = value
	end
	local fmt = entry.fmt
	if (line.count or 1) > 1 and M.db.scroll.mergeCount then
		fmt = fmt .. " \195\151%d" -- " ×N"
		args[#args + 1] = line.count
	end
	if anySecret then
		line.text:SetFormattedText(fmt, unpack(args, 1, #args))
	else
		local text = fmt:format(unpack(args, 1, #args))
		-- Codes left empty leave "()" and double spaces behind.
		text = text:gsub("%(%s*%)", ""):gsub("%[%s*%]", ""):gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
		line.text:SetText(text)
	end
end
M.RenderLine = Render

-- School colors (EldoUI's own palette; schoolMask only when plain).
local SCHOOL_COLORS = {
	[1] = { 1, 0.27, 0.27 },     -- physical
	[2] = { 1, 0.9, 0.5 },       -- holy
	[4] = { 1, 0.5, 0.1 },       -- fire
	[8] = { 0.45, 1, 0.35 },     -- nature
	[16] = { 0.5, 0.85, 1 },     -- frost
	[32] = { 0.7, 0.45, 1 },     -- shadow
	[64] = { 1, 0.55, 1 },       -- arcane
}
local MULTI_SCHOOL = { 1, 0.75, 0.45 }
M.SCHOOL_COLORS = SCHOOL_COLORS

function M:SchoolColor(school)
	if issecret(school) or type(school) ~= "number" or school == 0 then return nil end
	return SCHOOL_COLORS[school] or MULTI_SCHOOL
end

local function Outline()
	local outline = M.db.scroll.outline
	return outline == "NONE" and "" or outline
end

-- Lay a line out inside its area box: text by the area's alignment, icon
-- on the chosen side (anchored to the text, never measured).
local function LayoutLine(line, area, holder, size, fontId, iconTexture)
	local frame, text, icon = line.frame, line.text, line.icon
	local lineHeight = size + 6
	line.lineHeight = lineHeight
	frame:SetParent(holder)
	frame:SetFrameLevel(holder:GetFrameLevel() + 5)
	frame:SetSize(area.width, lineHeight)
	E:SetMediaFont(text, fontId, size, Outline())
	local align = area.align
	text:SetJustifyH(align)
	text:ClearAllPoints()
	icon:ClearAllPoints()
	if iconTexture then
		icon:SetTexture(iconTexture)
		icon:SetSize(size, size)
		icon:Show()
		local side = area.iconSide
		if align == "LEFT" then
			if side == "LEFT" then
				icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
				text:SetPoint("LEFT", icon, "RIGHT", 3, 0)
			else
				text:SetPoint("LEFT", frame, "LEFT", 0, 0)
				icon:SetPoint("LEFT", text, "RIGHT", 3, 0)
			end
		elseif align == "RIGHT" then
			if side == "RIGHT" then
				icon:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
				text:SetPoint("RIGHT", icon, "LEFT", -3, 0)
			else
				text:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
				icon:SetPoint("RIGHT", text, "LEFT", -3, 0)
			end
		else
			text:SetPoint("CENTER", frame, "CENTER", 0, 0)
			if side == "LEFT" then icon:SetPoint("RIGHT", text, "LEFT", -3, 0) else icon:SetPoint("LEFT", text, "RIGHT", 3, 0) end
		end
	else
		icon:Hide()
		text:SetPoint(align, frame, align, 0, 0)
	end
end

---------------------------------------------------------------------------
-- The updater
---------------------------------------------------------------------------
-- Event sounds: lines that arrive together (a burst of loot or heals)
-- with the same sound get it once, on the first of them; it plays when
-- that line shows, which can be a moment after it arrived.
local SOUND_GAP = 0.5
local soundAt = {}
local function WantsSound(sound)
	local now = GetTime()
	if soundAt[sound] and now - soundAt[sound] < SOUND_GAP then return false end
	soundAt[sound] = now
	return true
end

local function Update()
	local now = GetTime()
	for index = #active, 1, -1 do
		local line = active[index]
		local holder = holders[line.area]
		if not holder then
			Release(index)
		elseif now < line.t0 then
			line.frame:Hide()
		else
			local p = (now - line.t0) / line.duration
			if p >= 1 then
				Release(index)
			else
				local width, height = holder:GetSize()
				local x, y, alpha, scale = line.anim.position(p, line, width, height)
				if not scale or scale <= 0 then scale = 1 end
				local frame = line.frame
				frame:SetScale(scale)
				frame:ClearAllPoints()
				frame:SetPoint("CENTER", holder, "BOTTOM", (x or 0) / scale, (y or 0) / scale)
				frame:SetAlpha(math.max(0, math.min(1, alpha or 1)) * line.alpha)
				frame:Show()
				-- The event's sound comes with its line, once the line shows.
				if line.sound then
					E:PlayMedia(line.sound)
					line.sound = nil
				end
			end
		end
	end
	if #active == 0 then driver:Hide() end
end
driver:SetScript("OnUpdate", Update)

---------------------------------------------------------------------------
-- Placing a line
---------------------------------------------------------------------------
local function AreaSpeed(area)
	local speed = (area.speed and area.speed > 0) and area.speed or M.db.scroll.speed
	return math.max(10, speed) / 100
end

-- spec: area, template, payload, count, color, sticky, icon, fontSize, sound, key
local function Place(spec)
	local area = M.db.areas[spec.area]
	if not area then return end
	local holder = Holder(spec.area)
	local scroll = M.db.scroll
	local rt = Runtime(spec.area)
	local now = GetTime()
	local sticky = spec.sticky and true or false
	local size = spec.fontSize and spec.fontSize > 0 and spec.fontSize
		or (sticky and ((area.critFontSize > 0 and area.critFontSize) or scroll.critFontSize))
		or ((area.fontSize > 0 and area.fontSize) or scroll.fontSize)
	local fontId = (area.font ~= "default" and area.font) or (sticky and scroll.critFont) or scroll.font
	local animKey = sticky and area.sticky or area.animation
	-- With motion reduced a big hit holds still instead of popping.
	if animKey == "pop" and not E:MotionOn() then animKey = "hold" end
	local anim = M.animations[animKey] or M.animations[sticky and "pop" or "straight"]
	local speed = AreaSpeed(area)
	local duration = anim.duration / speed
	local lineHeight = size + 6
	local t0 = now

	if not sticky and anim.key ~= "stack" then
		-- Room between scrolling lines: the line height at the area's pace,
		-- and no more than `rate` new lines a second.
		local pace = math.max(1, area.height - lineHeight) / duration
		local gap = math.max(lineHeight / pace, 1 / math.max(1, area.rate))
		t0 = math.max(now, rt.lastStart + gap)
		local waiting = rt.lastLine
		if t0 - now > BACKLOG and waiting and waiting.key == spec.key and waiting.t0 > now and spec.key then
			-- Too many lines: join this one into the newest waiting line.
			local a, b = waiting.payload and waiting.payload.amount, spec.payload and spec.payload.amount
			if type(a) == "number" and type(b) == "number" and not issecret(a) and not issecret(b) then
				waiting.payload.amount = a + b
			elseif issecret(b) or type(b) ~= "nil" then
				waiting.payload.amount = b
			end
			waiting.count = (waiting.count or 1) + (spec.count or 1)
			Render(waiting)
			M.engineStats.merged = M.engineStats.merged + 1
			return waiting
		end
		if t0 - now > DROP_AFTER then
			M.engineStats.dropped = M.engineStats.dropped + 1
			return nil
		end
	end

	-- The oldest lines of this area make room.
	local count = 0
	for _, line in ipairs(active) do if line.area == spec.area then count = count + 1 end end
	while count >= math.max(1, area.maxLines) do
		for index, line in ipairs(active) do
			if line.area == spec.area then
				Release(index)
				break
			end
		end
		count = count - 1
	end

	local line = Acquire()
	line.area, line.key = spec.area, spec.key
	line.template, line.payload, line.count = spec.template, spec.payload or {}, spec.count or 1
	line.anim, line.duration, line.t0 = anim, duration, t0
	line.sticky = sticky
	line.up = area.direction == "up"
	line.bend = area.curve == "right" and 1 or -1
	rt.side = -(rt.side or 1)
	line.side = rt.side
	line.shake = area.shake and E:MotionOn()
	line.alpha = (scroll.alpha or 100) / 100
	line.slot = 0
	if sticky then
		-- Lowest free sticky slot in this area.
		local used = {}
		for _, other in ipairs(active) do
			if other ~= line and other.area == spec.area and other.sticky then used[other.slot] = true end
		end
		while used[line.slot] do line.slot = line.slot + 1 end
	elseif anim.key == "stack" then
		for _, other in ipairs(active) do
			if other ~= line and other.area == spec.area and not other.sticky then other.slot = other.slot + 1 end
		end
	else
		rt.lastStart = t0
		rt.lastLine = line
	end
	local iconTexture = scroll.icons and spec.icon or nil
	LayoutLine(line, area, holder, size, fontId, iconTexture)
	line.lineHeight = lineHeight
	local color = spec.color or { 1, 1, 1 }
	line.text:SetTextColor(color[1], color[2], color[3])
	Render(line)
	line.frame:Hide()
	driver:Show()
	M.engineStats.shown = M.engineStats.shown + 1
	line.sound = (spec.sound and spec.sound ~= "none" and scroll.sounds and WantsSound(spec.sound)) and spec.sound or nil
	return line
end

---------------------------------------------------------------------------
-- Events -> lines
---------------------------------------------------------------------------
local function InGroup()
	return IsInGroup and IsInGroup() or false
end

-- Where event `key` shows right now (area key and settings), or nil.
function M:EventArea(key, info)
	local ev = self.db.events[key]
	local areaKey = ev.area
	local moved = false
	if info.boss and self:InEncounter() then areaKey, moved = "incoming", true end
	local area = self.db.areas[areaKey]
	if not (area and area.enabled) then return nil end
	if area.hideInGroup and InGroup() then return nil end
	return areaKey, area, moved
end

local function Display(key, areaKey, payload, count, moved)
	local ev = M.db.events[key]
	local info = M.eventInfo[key]
	local color = ev.color
	if info.school and M.db.scroll.schoolColors then
		color = M:SchoolColor(payload.school) or color
	end
	return Place({
		key = key, area = areaKey, template = ev.text and L[ev.text], payload = payload, count = count,
		-- "Sticky critical hits" off lets critical lines scroll like the rest.
		color = color, sticky = (ev.sticky and (M.db.scroll.stickyCrits or not key:find("Crit$"))) or moved, icon = payload.icon,
		fontSize = ev.fontSize, sound = ev.sound,
	})
end

local function Flush(bucketKey)
	local bucket = buckets[bucketKey]
	buckets[bucketKey] = nil
	if not bucket or not M:ScrollRunning() then return end
	Display(bucket.key, bucket.area, bucket.payload, bucket.count, bucket.moved)
end

-- The one entry point for every feed: event `key` with its payload
-- ({ amount, name, spell, type, count, item, total, text, icon, school }).
function M:Emit(key, payload)
	if not self:ScrollRunning() then return end
	local info = self.eventInfo[key]
	local ev = self.db.events[key]
	if not (info and ev and ev.on) then return end
	local areaKey, _, moved = self:EventArea(key, info)
	if not areaKey then return end
	payload = payload or {}
	local amount = payload.amount
	local scroll = self.db.scroll
	if scroll.minAmount > 0 and type(amount) == "number" and not issecret(amount) and amount < scroll.minAmount then return end
	if info.merge and scroll.merge and scroll.mergeWindow > 0 then
		local bucketKey = areaKey .. "|" .. key
		local bucket = buckets[bucketKey]
		if bucket then
			local a = bucket.payload.amount
			if type(a) == "number" and type(amount) == "number" and not issecret(a) and not issecret(amount) then
				bucket.payload.amount = a + amount
			elseif issecret(amount) or type(amount) ~= "nil" then
				-- A secret amount can't be added up: the newest one shows, with the count.
				bucket.payload.amount = amount
			end
			local s1, s2 = bucket.payload.school, payload.school
			if issecret(s1) or issecret(s2) or s1 ~= s2 then bucket.payload.school = nil end
			bucket.count = bucket.count + 1
			self.engineStats.merged = self.engineStats.merged + 1
			return
		end
		buckets[bucketKey] = { key = key, area = areaKey, payload = payload, count = 1, moved = moved }
		C_Timer.After(scroll.mergeWindow, function() Flush(bucketKey) end)
		return
	end
	return Display(key, areaKey, payload, 1, moved)
end

-- Public: any text into an area.
function M:Show(text, areaKey, opts)
	if not self:ScrollRunning() then return nil end
	opts = opts or {}
	areaKey = areaKey or "notify"
	local area = self.db.areas[areaKey]
	if not (area and area.enabled) then return nil end
	if not issecret(text) then
		if type(text) == "nil" then return nil end
		text = tostring(text)
	end
	return Place({
		key = opts.key, area = areaKey, template = "{text}", payload = { text = text }, count = 1,
		color = opts.color, sticky = opts.sticky, icon = opts.icon, fontSize = opts.fontSize, sound = opts.sound,
	})
end

-- A sample line in every area that is on (out of combat, from /eui sct test).
function M:RunTest()
	for _, key in ipairs(self:AreaKeys()) do
		local area = self.db.areas[key]
		if area.enabled then
			self:Show(L["%s: sample line"]:format(self:AreaTitle(key)), key, { color = E.media.accentColor })
		end
	end
	if self.db.areas.incoming.enabled then
		self:Emit("inDamage", { amount = 1234, school = 4 })
		self:Emit("inHealCrit", { amount = 2468 })
	end
end

---------------------------------------------------------------------------
-- Part
---------------------------------------------------------------------------
M:AddPart("Engine", {
	enable = function() M:ApplyAreas() end,
	disable = function()
		M:ReleaseAll()
		for key, holder in pairs(holders) do
			holder:Hide()
			local mover = E.movers[MoverName(key)]
			if mover then mover:Hide() end
		end
		driver:Hide()
	end,
	refresh = function()
		M:ReleaseAll()
		M:ApplyAreas()
	end,
})
M.ReleaseLine = ReleaseLine

-- For /eui diag: the lines on screen (read only).
function M:Lines()
	return active
end
