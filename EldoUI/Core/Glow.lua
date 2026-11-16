-- EldoUI glow engine: one set of glow styles for every part of the
-- UI that lights a frame up (action bar procs, cooldown rows, reminders,
-- aura highlights, dispel highlights, the quest item button).
--
--   E:ShowGlow(frame, style, opts)   style: blizzard | pixel | sparkle | pulse | none
--   E:HideGlow(frame)
--   E:IsGlowShown(frame)
--   E:UpdateGlowLayout(frame)        after the frame changed size
--   E:RegisterGlowUser(key, info)    a row on General > Glows (see below)
--   E:ShowUserGlow(frame, key, opts) glow with that row's style and color
--   E:GlowSettings(key)              style, opts for a row
--   E:ApplyGlowPreset(name)          "blizzard" | "pixel" | "pulse"
--   E:SetGlowPaused(frame, paused)   stop (or resume) a moving glow's OnUpdate while
--                                    it can't be seen (a closed UnitFX gate)
--
-- With motion reduced (E:MotionOn(), Core/Animation.lua) every style draws
-- as a still border in its color and thickness: nothing runs an OnUpdate.
--
-- opts: color = { r, g, b[, a] }, lines (4-16), speed (0.1-1, laps or
-- pulses per second / 4), thickness (1-4 px), inset (-4..4 px, positive
-- = inside the frame), level (frame level above the frame, default 6),
-- scale (blizzard: size of the flipbook relative to the frame, 1.4),
-- tint (blizzard: color the game's flipbook with `color` instead of its
-- own gold).
--
-- Every user row also has a layer (below the frame's text, above it, or on
-- top of everything on the frame) and, for the Blizzard style, a "Blizzard
-- default colors" switch.
--
-- Rules: a glow is decoration only. EldoUI never decides when something
-- should glow from combat data: callers start glows from the game's own
-- signals (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE, an aura container
-- match, a reminder, the cooldown manager's state).
-- Every texture is EldoUI's own, on EldoUI's own child frame; the Blizzard
-- style uses the game's ActionButtonSpellAlertTemplate on our child frame.
-- Written from scratch for EldoUI (no glow library is embedded).
local _, E = ...
local L = E.L

local issecret = issecretvalue or function() return false end

E.GLOW_STYLES = {
	blizzard = "Blizzard proc",
	pixel = "Pixel lines",
	sparkle = "Sparkle",
	pulse = "Pulse",
	none = "None",
}

local GLOW_DEFAULTS = {
	style = "pixel",
	colorMode = "accent",   -- accent | class | custom
	color = { 1, 0.82, 0 },
	lines = 8,
	speed = 0.25,
	thickness = 2,
	inset = 0,
	layer = "above",        -- below | above | top (see GLOW_LAYERS)
	blizzardColors = true,  -- blizzard style: the game's own colors
}

-- Frame level of the glow above the glowing frame, per layer. Icons keep
-- their cooldown swipe one level up and their text two to three levels up.
local GLOW_LAYERS = { below = 2, above = 6, top = 12 }
E.GLOW_LAYERS = {
	below = "Below the icon text",
	above = "Above the icon text",
	top = "On top of everything",
}

E.defaults.glows = E.defaults.glows or {}

---------------------------------------------------------------------------
-- Per-frame glow holder: our own child frame with pooled textures.
---------------------------------------------------------------------------
local glows = setmetatable({}, { __mode = "k" })   -- frame -> holder

local function Usable(frame)
	return type(frame) == "table" and frame.GetObjectType and not E.FrameCheck(frame, "IsForbidden")
end

local function Plain(...)
	for i = 1, select("#", ...) do
		if issecret((select(i, ...))) then return false end
	end
	return true
end

local function Clamp(value, low, high, default)
	value = tonumber(value) or default
	return math.max(low, math.min(high, value))
end

local function Texture(holder, index)
	local pool = holder.pool
	local texture = pool[index]
	if not texture then
		texture = holder:CreateTexture(nil, "OVERLAY", nil, 7)
		pool[index] = texture
	end
	return texture
end

local function HideTextures(holder, from)
	for index = from or 1, #holder.pool do holder.pool[index]:Hide() end
end

local function ColorOf(opts)
	local c = opts.color or E.media.accentColor
	return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end

---------------------------------------------------------------------------
-- Perimeter walk shared by the pixel and sparkle styles. Distance 0 is the
-- top-left corner; the walk goes clockwise. Returns the point on the edge
-- (x right, y down from the top-left corner) and the edge index.
---------------------------------------------------------------------------
local function PointAt(distance, w, h)
	local p = 2 * (w + h)
	distance = distance % p
	if distance < w then return distance, 0, 1 end
	distance = distance - w
	if distance < h then return w, distance, 2 end
	distance = distance - h
	if distance < w then return w - distance, h, 3 end
	distance = distance - w
	return 0, h - distance, 4
end

-- Edge lengths in walk order, and where each edge starts on the walk.
local function EdgeStart(edge, w, h)
	if edge == 1 then return 0 end
	if edge == 2 then return w end
	if edge == 3 then return w + h end
	return 2 * w + h
end

local function EdgeLength(edge, w, h)
	return (edge == 1 or edge == 3) and w or h
end

-- A piece of line on one edge from walk distance a to b (same edge).
local function DrawPiece(texture, holder, edge, a, b, w, h, t)
	local length = b - a
	if length <= 0.01 then texture:Hide() return end
	texture:ClearAllPoints()
	if edge == 1 then
		texture:SetPoint("TOPLEFT", holder, "TOPLEFT", a, 0)
		texture:SetSize(length, t)
	elseif edge == 2 then
		texture:SetPoint("TOPLEFT", holder, "TOPLEFT", w - t, -a)
		texture:SetSize(t, length)
	elseif edge == 3 then
		texture:SetPoint("TOPLEFT", holder, "TOPLEFT", w - b, -(h - t))
		texture:SetSize(length, t)
	else
		texture:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(h - b))
		texture:SetSize(t, length)
	end
	texture:Show()
end

---------------------------------------------------------------------------
-- Styles. Each has Start(holder), Update(holder, elapsed) and is drawn on
-- the holder that covers the frame (plus inset).
---------------------------------------------------------------------------
local Styles = {}

Styles.pixel = {
	Start = function(holder)
		local lines = math.floor(Clamp(holder.opts.lines, 4, 16, 8))
		local r, g, b, a = ColorOf(holder.opts)
		for i = 1, lines * 2 do Texture(holder, i):SetColorTexture(r, g, b, a) end
	end,
	Update = function(holder, elapsed)
		local opts = holder.opts
		local w, h = holder:GetSize()
		if not Plain(w, h) or w < 2 or h < 2 then return end
		local lines = math.floor(Clamp(opts.lines, 4, 16, 8))
		local t = Clamp(opts.thickness, 1, 4, 2) * E.pixel
		local p = 2 * (w + h)
		holder.progress = ((holder.progress or 0) + elapsed * Clamp(opts.speed, 0.1, 1, 0.25)) % 1
		-- Each line covers half its share of the perimeter, at most one edge.
		local length = math.min(p / lines * 0.5, math.min(w, h))
		for i = 1, lines do
			local start = (holder.progress + (i - 1) / lines) * p
			local _, _, edge = PointAt(start, w, h)
			local edgeFrom = EdgeStart(edge, w, h)
			local local1 = (start % p) - edgeFrom
			local edgeLength = EdgeLength(edge, w, h)
			local first, second = Texture(holder, i * 2 - 1), Texture(holder, i * 2)
			if local1 + length <= edgeLength then
				DrawPiece(first, holder, edge, local1, local1 + length, w, h, t)
				second:Hide()
			else
				-- The line turns a corner: the rest goes on the next edge.
				DrawPiece(first, holder, edge, local1, edgeLength, w, h, t)
				local nextEdge = edge % 4 + 1
				DrawPiece(second, holder, nextEdge, 0, local1 + length - edgeLength, w, h, t)
			end
		end
		HideTextures(holder, lines * 2 + 1)
	end,
}

Styles.sparkle = {
	Update = function(holder, elapsed)
		local opts = holder.opts
		local w, h = holder:GetSize()
		if not Plain(w, h) or w < 2 or h < 2 then return end
		local dots = math.floor(Clamp(opts.lines, 4, 16, 8))
		local size = (Clamp(opts.thickness, 1, 4, 2) + 1) * E.pixel
		local speed = Clamp(opts.speed, 0.1, 1, 0.25)
		local p = 2 * (w + h)
		holder.progress = ((holder.progress or 0) + elapsed * speed) % 1
		holder.clock = (holder.clock or 0) + elapsed
		local r, g, b, a = ColorOf(opts)
		for i = 1, dots do
			local x, y = PointAt((holder.progress + (i - 1) / dots) * p, w, h)
			local dot = Texture(holder, i)
			-- Every other dot is larger; each twinkles on its own phase.
			local big = i % 2 == 0
			local twinkle = 0.45 + 0.55 * (0.5 + 0.5 * math.sin((holder.clock * speed * 8) + i * 1.7))
			dot:SetColorTexture(r, g, b, a * twinkle)
			dot:SetSize(big and size + E.pixel or size, big and size + E.pixel or size)
			dot:ClearAllPoints()
			dot:SetPoint("CENTER", holder, "TOPLEFT", x, -y)
			dot:Show()
		end
		HideTextures(holder, dots + 1)
	end,
}

-- A full border on the holder, in `color` (default: the glow's).
local BORDER_EDGES = {
	{ "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
	{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
}
local function Border(holder, color)
	local t = Clamp(holder.opts.thickness, 1, 4, 2) * E.pixel
	local r, g, b, a = ColorOf(color and { color = color } or holder.opts)
	for index, edge in ipairs(BORDER_EDGES) do
		local texture = Texture(holder, index)
		texture:ClearAllPoints()
		texture:SetPoint(edge[1], holder, edge[1])
		texture:SetPoint(edge[2], holder, edge[2])
		if edge[3] then texture:SetHeight(t) else texture:SetWidth(t) end
		texture:SetColorTexture(r, g, b, a)
		texture:Show()
	end
	HideTextures(holder, 5)
end

Styles.pulse = {
	Start = function(holder) Border(holder) end,
	Update = function(holder, elapsed)
		holder.clock = (holder.clock or 0) + elapsed
		local frequency = Clamp(holder.opts.speed, 0.1, 1, 0.25) * 4
		holder:SetAlpha(0.35 + 0.65 * (0.5 + 0.5 * math.cos(holder.clock * frequency * 2 * math.pi)))
	end,
}

-- Reduced motion: a steady border in the glow's color (the game's proc
-- gold for the Blizzard style in its own colors), no OnUpdate.
local PROC_GOLD = { 1, 0.82, 0, 1 }
Styles.still = {
	Start = function(holder)
		holder:SetAlpha(1)
		Border(holder, holder.wanted == "blizzard" and not holder.opts.tint and PROC_GOLD or nil)
	end,
}

-- Blizzard style colors: the game's own gold, or the row's color on a
-- grayed copy of the flipbook ("Blizzard default colors" off).
local function TintAlert(holder)
	local alert = holder.alert
	if not alert or not alert.GetRegions then return end
	local tint = holder.opts.tint
	local r, g, b = ColorOf(holder.opts)
	for _, region in ipairs({ alert:GetRegions() }) do
		if region.SetVertexColor and region.SetDesaturated then
			region:SetDesaturated(tint and true or false)
			if tint then region:SetVertexColor(r, g, b) else region:SetVertexColor(1, 1, 1) end
		end
	end
end

-- The game's own proc flipbook (the atlas from the client), on our frame.
Styles.blizzard = {
	Start = function(holder)
		HideTextures(holder)
		local alert = holder.alert
		if alert == nil then
			local ok, frame = pcall(CreateFrame, "Frame", nil, holder, "ActionButtonSpellAlertTemplate")
			alert = ok and frame or false
			holder.alert = alert
		end
		if not alert then
			-- Template missing: fall back to the pulse.
			holder.style = "pulse"
			return Styles.pulse.Start(holder)
		end
		alert:ClearAllPoints()
		alert:SetPoint("CENTER", holder:GetParent(), "CENTER")
		local w, h = holder:GetParent():GetSize()
		local scale = Clamp(holder.opts.scale, 1, 2, 1.4)
		if Plain(w, h) then alert:SetSize(w * scale, h * scale) end
		TintAlert(holder)
		alert:Show()
		if alert.ProcStartAnim then alert.ProcStartAnim:Play() end
	end,
	Stop = function(holder)
		local alert = holder.alert
		if not alert then return end
		if alert.ProcStartAnim then alert.ProcStartAnim:Stop() end
		if alert.ProcLoop then alert.ProcLoop:Stop() end
		alert:Hide()
	end,
}

local UPDATE_INTERVAL = 1 / 30
local function OnUpdate(holder, elapsed)
	local style = Styles[holder.style]
	if not style or not style.Update then return end
	holder.updateElapsed = (holder.updateElapsed or 0) + elapsed
	if elapsed > 0 and holder.updateElapsed < UPDATE_INTERVAL then return end
	local accumulated = holder.updateElapsed
	holder.updateElapsed = 0
	style.Update(holder, accumulated)
end

local function Holder(frame)
	local holder = glows[frame]
	if not holder then
		holder = CreateFrame("Frame", nil, frame)
		holder.pool = {}
		holder:Hide()
		glows[frame] = holder
	end
	return holder
end

local function Layout(frame, holder)
	local inset = Clamp(holder.opts.inset, -4, 4, 0) * E.pixel
	holder:ClearAllPoints()
	holder:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
	holder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
	local level = frame:GetFrameLevel()
	if Plain(level) then holder:SetFrameLevel(level + (tonumber(holder.opts.level) or 6)) end
end

local function StopStyle(holder)
	holder.updateElapsed = nil
	local style = Styles[holder.style]
	if style and style.Stop then style.Stop(holder) end
	holder:SetScript("OnUpdate", nil)
	holder:SetAlpha(1)
	HideTextures(holder)
end

function E:ShowGlow(frame, style, opts)
	if not Usable(frame) then return end
	if style == nil or style == "none" or not Styles[style] then
		return self:HideGlow(frame)
	end
	local holder = Holder(frame)
	holder.wanted = style
	if E.MotionOn and not E:MotionOn() then style = "still" end
	local restart = holder.style ~= style or not holder:IsShown()
	if restart and holder.style then StopStyle(holder) end
	holder.opts = opts or {}
	holder.style = style
	Layout(frame, holder)
	holder:Show()
	local def = Styles[style]
	if restart or style ~= "blizzard" then
		if def.Start then def.Start(holder) end
	end
	if Styles[holder.style].Update then
		holder:SetScript("OnUpdate", (not holder.paused) and OnUpdate or nil)
		OnUpdate(holder, 0)
	end
end

-- A glow inside a UnitFX gate that is known to be closed (alpha 0 from a
-- plain value) costs nothing: its OnUpdate stops until the gate opens.
-- The look stays as it was; ShowGlow and RefreshGlows keep the pause.
function E:SetGlowPaused(frame, paused)
	if not Usable(frame) then return end
	local holder = Holder(frame)
	holder.paused = paused and true or nil
	local style = holder.style and Styles[holder.style]
	if style and style.Update then
		holder:SetScript("OnUpdate", (not holder.paused) and OnUpdate or nil)
	end
end

function E:IsGlowPaused(frame)
	local holder = glows[frame]
	return holder ~= nil and holder.paused == true
end

function E:HideGlow(frame)
	local holder = glows[frame]
	if not holder or not holder.style then return end
	StopStyle(holder)
	holder.style = nil
	holder.wanted = nil
	holder.user = nil
	holder:Hide()
end

function E:IsGlowShown(frame)
	local holder = glows[frame]
	return holder ~= nil and holder.style ~= nil
end

function E:UpdateGlowLayout(frame)
	local holder = glows[frame]
	if not holder or not holder.style then return end
	Layout(frame, holder)
	if holder.style == "blizzard" and holder.alert then
		local w, h = frame:GetSize()
		local scale = Clamp(holder.opts.scale, 1, 2, 1.4)
		if Plain(w, h) then holder.alert:SetSize(w * scale, h * scale) end
	end
end

---------------------------------------------------------------------------
-- Glow users: one row each on General > Glows.
--   E:RegisterGlowUser("procs", {
--       title = "Action bar procs", desc = "...", order = 10,
--       default = { style = "blizzard", colorMode = "custom", color = { 1, 0.82, 0 } },
--       button = true,   -- a square button: the Blizzard proc art fits
--   })
---------------------------------------------------------------------------
E.glowUsers = {}
local userOrder = {}

local function UserDefaults(info)
	local defaults = CopyTable(GLOW_DEFAULTS)
	for key, value in pairs(info.default or {}) do
		defaults[key] = type(value) == "table" and CopyTable(value) or value
	end
	if not info.button and defaults.style == "blizzard" then defaults.style = "pixel" end
	return defaults
end

function E:RegisterGlowUser(key, info)
	info = info or {}
	info.key = key
	info.order = info.order or 50
	if not self.glowUsers[key] then table.insert(userOrder, key) end
	self.glowUsers[key] = info
	table.sort(userOrder, function(a, b)
		local ua, ub = E.glowUsers[a], E.glowUsers[b]
		if ua.order ~= ub.order then return ua.order < ub.order end
		return a < b
	end)
	self.defaults.glows[key] = UserDefaults(info)
	-- Registered after the settings loaded (a plugin): fill its row now.
	if self.db then
		self.db.glows = self.db.glows or {}
		self.db.glows[key] = self.ApplyDefaults(self.db.glows[key] or {}, self.defaults.glows[key])
	end
	if self.glowPage then self:BuildGlowPage() end
end

function E:IterateGlowUsers()
	local i = 0
	return function()
		i = i + 1
		local key = userOrder[i]
		if key then return key, E.glowUsers[key] end
	end
end

local function UserDB(key)
	local all = E.db and E.db.glows
	return all and all[key] or E.defaults.glows[key] or GLOW_DEFAULTS
end

local function ResolveColor(db)
	if db.colorMode == "class" then
		local r, g, b = E:ClassColor("player")
		return { r, g, b, 1 }
	elseif db.colorMode == "custom" and type(db.color) == "table" then
		return { db.color[1], db.color[2], db.color[3], 1 }
	end
	local c = E.media.accentColor
	return { c[1], c[2], c[3], 1 }
end

-- style and opts for a glow user, `overrides` merged on top.
function E:GlowSettings(key, overrides)
	local db = UserDB(key)
	local info = self.glowUsers[key]
	local style = db.style or "pixel"
	if style == "blizzard" and info and not info.button then style = "pixel" end
	local opts = {
		color = ResolveColor(db),
		lines = db.lines, speed = db.speed, thickness = db.thickness, inset = db.inset,
		level = GLOW_LAYERS[db.layer] or GLOW_LAYERS.above,
		tint = style == "blizzard" and db.blizzardColors == false or nil,
	}
	for k, v in pairs(overrides or {}) do opts[k] = v end
	return style, opts
end

function E:ShowUserGlow(frame, key, overrides)
	local style, opts = self:GlowSettings(key, overrides)
	self:ShowGlow(frame, style, opts)
	local holder = glows[frame]
	if holder and holder.style then
		holder.user = key
		holder.overrides = overrides
	end
end

-- Settings changed: every glow shown for a user takes the new look.
function E:RefreshGlows()
	for frame, holder in pairs(glows) do
		-- Aura slot buttons can be forbidden while auras are secret: they
		-- take the new look when the client hands them out again.
		if holder.user and holder.style and Usable(frame) then
			local style, opts = self:GlowSettings(holder.user, holder.overrides)
			if style ~= holder.wanted then
				self:ShowUserGlow(frame, holder.user, holder.overrides)
			else
				holder.opts = opts
				Layout(frame, holder)
				local def = Styles[holder.style]
				if holder.style == "blizzard" then
					TintAlert(holder)
				elseif def.Start then
					def.Start(holder)
				end
			end
		end
	end
	if self.glowPreview and self.glowPreview:IsShown() then self:ShowGlowPreview(true) end
end

-- Motion reduced or back: every shown glow is drawn again in its new form.
if E.OnMotionChanged then
	E:OnMotionChanged(function()
		for frame, holder in pairs(glows) do
			if holder.style and holder.wanted and Usable(frame) then E:ShowGlow(frame, holder.wanted, holder.opts) end
		end
	end)
end

-- A new accent (General, or the class color) recolors accent glows.
hooksecurefunc(E, "UpdateAccent", function() if E.db then E:RefreshGlows() end end)

---------------------------------------------------------------------------
-- Presets: each sets every row at once.
---------------------------------------------------------------------------
E.GLOW_PRESETS = {
	blizzard = { title = "Blizzard", desc = "The game's proc art on buttons, pixel lines everywhere else. Gold for procs.",
		apply = function(key, db, info)
			db.style = info.button and "blizzard" or "pixel"
			db.blizzardColors = true
			db.lines, db.speed, db.thickness, db.inset = 8, 0.25, 2, 0
		end },
	pixel = { title = "Clean pixel", desc = "Thin lines that run round the frame in the accent color.",
		apply = function(_, db)
			db.style = "pixel"
			db.colorMode = "accent"
			db.lines, db.speed, db.thickness, db.inset = 8, 0.25, 1, 0
		end },
	pulse = { title = "Subtle pulse", desc = "A slow pulsing border, no movement round the frame.",
		apply = function(_, db)
			db.style = "pulse"
			db.lines, db.speed, db.thickness, db.inset = 8, 0.15, 2, 0
		end },
}

function E:ApplyGlowPreset(name)
	local preset = self.GLOW_PRESETS[name]
	if not preset or not self.db then return false end
	self.db.glows = self.db.glows or {}
	for key, info in self:IterateGlowUsers() do
		local db = self.db.glows[key] or CopyTable(self.defaults.glows[key])
		self.db.glows[key] = db
		-- A row that is switched off (style None) stays off: a preset
		-- changes the look, not which glows are on.
		if db.style ~= "none" then preset.apply(key, db, info) end
	end
	self:RefreshGlows()
	return true
end

---------------------------------------------------------------------------
-- Live preview: one icon per glow user, each with its glow, for a few
-- seconds near the top of the screen. Changes on the page show at once.
---------------------------------------------------------------------------
local PREVIEW_SIZE = 40

function E:ShowGlowPreview(keep)
	local panel = self.glowPreview
	if not panel then
		panel = CreateFrame("Frame", nil, UIParent)
		panel:SetFrameStrata("FULLSCREEN_DIALOG")
		panel:SetPoint("TOP", UIParent, "TOP", 0, -96)
		panel:EnableMouse(true)
		panel:SetScript("OnMouseUp", function(frame) frame:Hide() end)
		panel.title = E:CreateText(panel, E.tokens.size.label, "CENTER")
		panel.title:SetPoint("TOP", 0, -8)
		panel.title:SetText(L["Glow preview (click to close)"])
		panel.icons = {}
		self.glowPreview = panel
	end
	E:SetPanelTemplate(panel)
	local count = 0
	for key, info in self:IterateGlowUsers() do
		count = count + 1
		local icon = panel.icons[count]
		if not icon then
			icon = CreateFrame("Frame", nil, panel)
			icon:SetSize(PREVIEW_SIZE, PREVIEW_SIZE)
			icon.texture = icon:CreateTexture(nil, "ARTWORK")
			icon.texture:SetPoint("TOPLEFT", E.pixel, -E.pixel)
			icon.texture:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
			E:TrimIcon(icon.texture)
			icon.label = E:CreateText(icon, E.tokens.size.tiny, "CENTER")
			icon.label:SetPoint("TOP", icon, "BOTTOM", 0, -4)
			icon.label:SetWidth(PREVIEW_SIZE + 40)
			panel.icons[count] = icon
		end
		E:SetTemplate(icon)
		icon.texture:SetTexture(info.icon or E.media.icon)
		icon.label:SetText(info.title and L[info.title] or key)
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 24 + (count - 1) * (PREVIEW_SIZE + 48), -32)
		icon:Show()
		self:ShowUserGlow(icon, key)
	end
	for index = count + 1, #panel.icons do
		self:HideGlow(panel.icons[index])
		panel.icons[index]:Hide()
	end
	panel:SetSize(math.max(220, 48 + count * (PREVIEW_SIZE + 48) - 48), PREVIEW_SIZE + 64)
	panel:Show()
	if not keep then
		panel.token = (panel.token or 0) + 1
		local token = panel.token
		C_Timer.After(12, function()
			if panel.token == token then panel:Hide() end
		end)
	end
end

---------------------------------------------------------------------------
-- General > Glows page
---------------------------------------------------------------------------
local function GlowRows(options, key, info)
	local p = key .. "."
	local function DB() return UserDB(key) end
	local function Off() return DB().style == "none" end
	table.insert(options, { type = "header", label = info.title or key })
	if info.desc then table.insert(options, { type = "description", label = info.desc }) end
	local styles = {}
	for style, label in pairs(E.GLOW_STYLES) do
		if style ~= "blizzard" or info.button then styles[style] = label end
	end
	table.insert(options, { type = "select", key = p .. "style", label = "Style", values = styles,
		desc = "Blizzard proc: the game's own proc animation (buttons only). Pixel lines: lines running round the frame. Sparkle: dots circling the frame. Pulse: a border that fades in and out. None: no glow." })
	table.insert(options, { type = "select", key = p .. "layer", label = "Layer", values = E.GLOW_LAYERS, cog = true,
		desc = "Where the glow sits: under the icon's numbers and keybind, over them, or on top of everything on the frame.",
		hidden = Off })
	local function GameColours() return DB().style == "blizzard" and DB().blizzardColors ~= false end
	if info.button then
		table.insert(options, { type = "toggle", key = p .. "blizzardColors", label = "Blizzard default colors",
			desc = "On: the Blizzard proc art keeps the game's own gold. Off: it takes the color below instead.",
			hidden = function() return Off() or DB().style ~= "blizzard" end })
	end
	table.insert(options, { type = "select", key = p .. "colorMode", label = "Color",
		values = { accent = "Accent color", class = "Class color", custom = "Custom color" },
		desc = "Accent follows the theme accent (General). Class uses your class color. Custom uses the color you pick.",
		hidden = function() return Off() or GameColours() end })
	table.insert(options, { type = "color", key = p .. "color", label = "Custom color",
		desc = "Color of the glow when Color is set to Custom color.",
		hidden = function() return Off() or GameColours() or DB().colorMode ~= "custom" end })
	local function NoShape() return Off() or DB().style == "blizzard" end
	table.insert(options, { type = "range", key = p .. "lines", label = "Lines", min = 4, max = 16, step = 1, cog = true,
		desc = "How many lines (Pixel lines) or dots (Sparkle) run round the frame.",
		hidden = function() return NoShape() or DB().style == "pulse" end })
	table.insert(options, { type = "range", key = p .. "speed", label = "Speed", min = 0.1, max = 1, step = 0.05, cog = true,
		desc = "Laps per second for lines and dots; for Pulse, a higher value pulses faster.", hidden = NoShape })
	table.insert(options, { type = "range", unit = "px", key = p .. "thickness", label = "Thickness", min = 1, max = 4, step = 1, cog = true,
		desc = "Line, dot or border thickness in pixels.", hidden = NoShape })
	table.insert(options, { type = "range", unit = "px", key = p .. "inset", label = "Inset", min = -4, max = 4, step = 1, cog = true,
		desc = "Moves the glow inside the frame edge (positive) or outside it (negative), in pixels.", hidden = NoShape })
end

function E:BuildGlowPage()
	local options = {
		{ type = "description", label = "One look for every glow in EldoUI. A glow starts only when the game signals something: a proc, an aura or a reminder." },
		{ type = "execute", label = "Preview", desc = "Shows every glow below on a sample icon for a few seconds. Changes show at once.", testSafe = true,
			func = function() E:ShowGlowPreview() end },
		{ type = "header", label = "Presets" },
	}
	for _, name in ipairs({ "blizzard", "pixel", "pulse" }) do
		local preset = self.GLOW_PRESETS[name]
		table.insert(options, { type = "execute", label = preset.title, desc = preset.desc, testSafe = true,
			func = function() E:ApplyGlowPreset(name); E:RefreshConfig() end })
	end
	local any = false
	for key, info in self:IterateGlowUsers() do
		GlowRows(options, key, info)
		any = true
	end
	if not any then
		table.insert(options, { type = "description", label = "No module that glows is switched on." })
	end
	if self.glowPage then
		-- Rebuild in place (a plugin registered a glow user later).
		self.glowPage.options = options
		self.glowPage.tabs = nil
		return self.glowPage
	end
	local page = self:RegisterConfigPage("glows", E.Key("Glows"), options,
		function()
			E.db.glows = E.db.glows or {}
			return E.db.glows
		end,
		function() E:RefreshGlows() end, 1.2)
	page.desc = L["Style and color of every glow: procs, highlights, reminders."]
	self.glowPage = page
	return page
end

E:RegisterEvent("PLAYER_LOGIN", function() E:BuildGlowPage() end, E.GLOW_PRESETS, "modules")
