-- EldoUI aura widget: icons for a unit's auras drawn by the game's own aura
-- container (CreateFrame("AuraContainer") with CustomAuraContainerTemplate).
--
-- Why: on WoW: Forever, addon code may not read auras in combat at all
-- (C_UnitAuras.GetAuraDataByIndex throws while auras are secret), and the
-- secure aura header is not loaded. The aura container filters, sorts and
-- lays out the auras in the client and hands EldoUI each icon button once,
-- to dress up. Its buttons also show the tooltip and, when asked, cancel a
-- buff on right-click inside Blizzard's code, in and out of combat.
--
-- Nothing here reads an aura. Used by the Auras module (player buffs and
-- debuffs), the unit frames (target, focus, boss auras), the group frames
-- (debuffs, HoTs, defensives, dispel highlight) and the nameplates (your
-- debuffs, enemy buffs, crowd control).
--
-- Rules for callers:
--   * create and release containers out of combat (settings.combat lets a
--     caller try in combat, e.g. nameplates that appear mid-fight; the
--     attempt is protected and returns nil when the client refuses);
--   * a settings change means another container (buttons belong to the
--     client once made; EldoUI never reaches into them later). A released
--     container waits in a pool and is handed out again only for the very
--     same settings (W.PoolKey), so trying layouts or styles reuses the
--     containers they released instead of making new ones (the client
--     never frees a frame);
--   * a caller that changes a container after it is made (E:ApplyAuraFilters)
--     names its own pool with settings.pool, so nobody else gets it back;
--   * never anchor other frames to a container (it forbids untrusted
--     layout scripts); anchor the container to your own holder instead.
--
-- Filter groups: pass settings.groups from E:AuraFilterGroups (one
-- container group each, with the client's candidate filters) instead of
-- settings.filters. W.SplitOwn turns each group into "yours" and "other
-- people's" groups (own auras first, others optionally desaturated).
-- Expiring auras: the duration text can take the shared cooldown
-- colors (the client formats and colors it) and blink in its last
-- seconds: a color curve over the remaining time that the client
-- evaluates, so Lua never sees the time. A thin time bar under the icon and
-- a bar mode (auras as timer bars with the spell name) use the
-- client's own duration bar (StatusBar:SetTimerDuration inside the client).
-- Effects: settings.fx from E.FrameFX.AuraFX(effects) adds a pop-in
-- (AddAuraShownAnimation) and an expiring pulse (AddPandemicActiveAnimation,
-- the game's own late window); fx.red turns the time text red through
-- E:UnitCurve("auraExpiring"). The client plays and times them all.
local _, E = ...
local L = E.L

local W = {}
E.AuraWidget = W

local TEMPLATE = "CustomAuraContainerTemplate"
local available

-- True when this client can make aura containers.
function W.Available()
	if available == nil then
		local ok, probe = pcall(CreateFrame, "AuraContainer", nil, UIParent, TEMPLATE)
		available = (ok and probe) and true or false
		if ok and probe then probe:Hide() end
	end
	return available
end

-- Short duration text ("12", "4m", "2h", "1d"), built by the client from a
-- time Lua never sees.
local formatter
local function DurationFormatter()
	if formatter ~= nil then return formatter or nil end
	formatter = false
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
	local ok, object = pcall(C_StringUtil.CreateNumericRuleFormatter)
	if not ok or not object then return nil end
	local up = Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up
	local rules = {
		{ threshold = 0, format = "%d" },
		{ threshold = 60, format = "%dm", components = { { div = 60, rounding = up } } },
		{ threshold = 3600, format = "%dh", components = { { div = 3600, rounding = up } } },
		{ threshold = 86400, format = "%dd", components = { { div = 86400, rounding = up } } },
	}
	if pcall(object.SetBreakpoints, object, rules) then formatter = object end
	return formatter or nil
end

local function Call(object, method, ...)
	local fn = object[method]
	if type(fn) ~= "function" then return false end
	return (pcall(fn, object, ...))
end

-- Blizzard's dispel colors (debuff type -> color), "None" for no type.
local function DispelColors()
	if not CreateColor then return nil end
	local map = {}
	local names = { Magic = "MAGIC", Curse = "CURSE", Disease = "DISEASE", Poison = "POISON", Bleed = "BLEED", None = "NONE" }
	for key, suffix in pairs(names) do
		local color = _G["DEBUFF_TYPE_" .. suffix .. "_COLOR"]
		if color then map[key] = CreateColor(color.r, color.g, color.b, 1) end
	end
	return next(map) and map or nil
end

-- A color map from plain { r, g, b } tables (settings are copied, so they
-- hold no color objects).
local function ColorMap(colors)
	if not (CreateColor and type(colors) == "table") then return nil end
	local map = {}
	for key, rgb in pairs(colors) do
		if type(rgb) == "table" then map[key] = CreateColor(rgb[1] or 1, rgb[2] or 1, rgb[3] or 1, rgb[4] or 1) end
	end
	return next(map) and map or nil
end


local function Edges(button, thickness)
	local edges = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local texture = button:CreateTexture(nil, "OVERLAY", nil, 3)
		texture:SetColorTexture(1, 1, 1, 1)
		if side == "TOP" or side == "BOTTOM" then
			texture:SetPoint(side .. "LEFT", button, side .. "LEFT")
			texture:SetPoint(side .. "RIGHT", button, side .. "RIGHT")
			texture:SetHeight(thickness)
		else
			texture:SetPoint("TOP" .. side, button, "TOP" .. side)
			texture:SetPoint("BOTTOM" .. side, button, "BOTTOM" .. side)
			texture:SetWidth(thickness)
		end
		texture:Hide()
		edges[#edges + 1] = texture
	end
	return edges
end

-- Dispel-type symbols next to the dispel color (DESIGN.md "Never color
-- alone"): the game's own short names (DEBUFF_SYMBOL_*: Ma, Cu, Di, Po,
-- Bl). The client writes the symbol of each aura into the text through
-- SetDispelTypeText, so a secret dispel type is fine. Shown while Shape
-- marks are on (General > Accessibility); settings.dispelSymbol = false
-- turns them off for one container.
function W.DispelSymbols()
	return {
		Magic = _G.DEBUFF_SYMBOL_MAGIC or L["Ma"],
		Curse = _G.DEBUFF_SYMBOL_CURSE or L["Cu"],
		Disease = _G.DEBUFF_SYMBOL_DISEASE or L["Di"],
		Poison = _G.DEBUFF_SYMBOL_POISON or L["Po"],
		Bleed = _G.DEBUFF_SYMBOL_BLEED or L["Bl"],
		Enrage = L["En"],
		None = "",
	}
end

function W.DispelSymbolsOn(settings)
	if settings and settings.dispelSymbol == false then return false end
	return E:StatusMark("warn") ~= ""
end

-- The symbol text on one aura button, in a corner (`point`).
function W.AddDispelSymbol(button, point, size)
	local text = E:CreateText(button, size, point:find("LEFT") and "LEFT" or "RIGHT", "OVERLAY")
	local x = point:find("LEFT") and 2 or -2
	local y = point:find("TOP") and -2 or point:find("BOTTOM") and 2 or 0
	text:SetPoint(point, button, point, x, y)
	text:SetDrawLayer("OVERLAY", 7)
	local body = E.tokens.text.body or { 1, 1, 1 }
	text:SetTextColor(body[1] or 1, body[2] or 1, body[3] or 1)
	if not Call(button, "SetDispelTypeText", text, {
		showWhenHarmful = true, showWhenHelpful = false, showWithoutDispelType = false,
		customDispelTextMap = W.DispelSymbols(),
	}) then
		text:Hide()
		return nil
	end
	button.dispelSymbol = text
	return text
end

-- Four edge textures handed to the client as dispel-type textures: it
-- shows and colors them per aura (the dispel type may be secret).
local function AddEdges(button, thickness, options)
	if not Enum.CustomAuraButtonDispelTypeTextureStyle then return false end
	options.style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset
	for _, edge in ipairs(Edges(button, thickness)) do
		if not Call(button, "AddDispelTypeTexture", edge, options) then return false end
	end
	return true
end

-- The shared cooldown-number look (Modules/ActionBars/Cooldowns.lua): the
-- same colors and thresholds as the action bars, so countdowns look the
-- same everywhere. Callers keep their own on/off.
function W.CooldownLook(size)
	return E:CooldownLook(size)
end

-- Style a countdown with the shared look when the helper is loaded.
function W.StyleCooldown(cooldown, size)
	if not (cooldown and E.StyleCooldownText) then return false end
	E:StyleCooldownText(cooldown, W.CooldownLook(size))
	return true
end

-- Where the stack count and the duration text sit on an icon.
--   point: corner of the icon ("BOTTOMRIGHT", "CENTER", ...); the duration
--   text also takes "BELOW" and "ABOVE" (outside the icon).
local OUTSIDE = { BELOW = { "TOP", "BOTTOM", 0, -2 }, ABOVE = { "BOTTOM", "TOP", 0, 2 } }
local function PlaceText(text, button, point, x, y, default)
	point = point or default
	text:ClearAllPoints()
	local outside = OUTSIDE[point]
	if outside then
		text:SetPoint(outside[1], button, outside[2], outside[3] + (x or 0), outside[4] + (y or 0))
	else
		text:SetPoint(point, button, point, x or 0, y or 0)
	end
end

-- The duration text's color over the remaining time, evaluated by the
-- client: full white, and in the last `seconds` alternating between full
-- and faint every half second (the "about to run out" blink). Lua never
-- reads the time; the curve goes to the client's duration text binding.
local blinkCurves = {}
local function BlinkCurve(seconds)
	seconds = math.floor(math.max(0, math.min(tonumber(seconds) or 0, 30)) * 2 + 0.5) / 2
	if seconds <= 0 or not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
	if blinkCurves[seconds] ~= nil then return blinkCurves[seconds] or nil end
	blinkCurves[seconds] = false
	local ok, curve = pcall(C_CurveUtil.CreateColorCurve)
	if not ok or not curve then return nil end
	local built = pcall(function()
		if Enum.LuaCurveType and curve.SetType then curve:SetType(Enum.LuaCurveType.Step) end
		local step, bright = 0, true
		while step < seconds do
			curve:AddPoint(step, CreateColor(1, 1, 1, bright and 1 or 0.25))
			bright = not bright
			step = step + 0.5
		end
		curve:AddPoint(seconds, CreateColor(1, 1, 1, 1))
	end)
	if built then blinkCurves[seconds] = curve end
	return blinkCurves[seconds] or nil
end
W.BlinkCurve = BlinkCurve

-- Options for SetDurationText: the shared cooldown colors when
-- `timeColors` is on, the short plain format otherwise; plus the blink
-- curve when `blink` (seconds) is set.
local function DurationTextOptions(settings)
	local options = {}
	if settings.timeColors and E.GetCooldownFormatter then
		options.textFormatter = E:GetCooldownFormatter(W.CooldownLook(settings.durationSize))
	end
	options.textFormatter = options.textFormatter or DurationFormatter()
	local curve = BlinkCurve(settings.blink)
	-- "Aura expiring": the time turns red under N seconds, from the
	-- shared UnitFX curve; the client evaluates it on the remaining time.
	local red = settings.fx and settings.fx.red
	if red and E.UnitCurve then curve = E:UnitCurve("auraExpiring", { seconds = red }) or curve end
	local property = Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration
	if curve and property then options.textColor = { curve = curve, property = property } end
	return options
end

-- Effects the client plays on the button: a pop-in when it shows an
-- aura, and a soft pulse while the aura is in its refresh (pandemic)
-- window. The animation groups are complete before the client gets them
-- (it adopts them and forbids changes afterwards). EldoUI never learns
-- which aura is shown or how long it has left.
local function AddEffects(button, fx)
	if type(fx) ~= "table" or not button.CreateAnimationGroup then return end
	if fx.pop then
		local group = button:CreateAnimationGroup()
		local grow = group:CreateAnimation("Scale")
		grow:SetOrder(1)
		grow:SetScaleFrom(0.6, 0.6)
		grow:SetScaleTo(1.1, 1.1)
		grow:SetDuration(0.15)
		grow:SetSmoothing("OUT")
		local settle = group:CreateAnimation("Scale")
		settle:SetOrder(2)
		settle:SetScaleFrom(1.1, 1.1)
		settle:SetScaleTo(1, 1)
		settle:SetDuration(0.1)
		local fade = group:CreateAnimation("Alpha")
		fade:SetOrder(1)
		fade:SetFromAlpha(0)
		fade:SetToAlpha(1)
		fade:SetDuration(0.15)
		Call(button, "AddAuraShownAnimation", group)
	end
	if fx.pulse then
		local group = button:CreateAnimationGroup()
		group:SetLooping("BOUNCE")
		local fade = group:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.45)
		fade:SetDuration(0.5)
		fade:SetSmoothing("IN_OUT")
		Call(button, "AddPandemicActiveAnimation", group)
	end
end
W.AddEffects = AddEffects

-- A status bar the client runs from the aura's duration object.
local function DurationBar(button, color)
	local bar = CreateFrame("StatusBar", nil, button)
	bar:SetStatusBarTexture(E.media.statusbar)
	local c = color or E.media.accentColor
	bar:SetStatusBarColor(c[1] or 1, c[2] or 1, c[3] or 1, 1)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	local back = bar:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints(bar)
	back:SetColorTexture(unpack(E.media.backdropColor))
	local direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
	if not Call(button, "SetDurationBar", bar, { direction = direction }) then
		Call(button, "SetDurationBar", bar, {})
	end
	return bar
end

local function Mouse(button, settings)
	if settings.cancel then Call(button, "SetCancelAuraButtons", "RightButtonUp") end
	-- tooltip = false leaves the mouse to the frame underneath (a unit
	-- button that must stay clickable, a nameplate).
	Call(button, "SetMouseClickEnabled", settings.cancel and true or false)
	Call(button, "SetMouseMotionEnabled", settings.tooltip ~= false)
	if settings.tooltipAnchor then Call(button, "SetTooltipAnchorPoint", settings.tooltipAnchor) end
end

-- Bar mode: the aura as a timer bar, icon on the left, spell name and time
-- on the bar. settings.bar = { width, height, color, dispelColor }.
local function BarInitializer(settings, group)
	return function(button)
		local spec = settings.bar
		local width, height = spec.width or 160, spec.height or 16
		button:SetSize(width, height)
		local border = button:CreateTexture(nil, "BACKGROUND")
		border:SetAllPoints(button)
		border:SetColorTexture(unpack(E.media.borderColor))

		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
		icon:SetSize(math.max(height - 2 * E.pixel, 1), math.max(height - 2 * E.pixel, 1))
		E:TrimIcon(icon)
		if group and group.desaturate then icon:SetDesaturated(true) end
		Call(button, "SetIcon", icon)

		local bar = DurationBar(button, spec.color)
		bar:SetPoint("TOPLEFT", icon, "TOPRIGHT", E.pixel, 0)
		bar:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
		-- Debuffs: the client tints the fill by dispel type (the type may
		-- be secret); auras without a type keep the bar color.
		if spec.dispelColor and Enum.CustomAuraButtonDispelTypeTextureStyle then
			local fill = bar:GetStatusBarTexture()
			local colors = DispelColors()
			if fill and colors then
				local c = spec.color or E.media.accentColor
				colors.None = CreateColor(c[1] or 1, c[2] or 1, c[3] or 1, 1)
				Call(button, "AddDispelTypeTexture", fill, {
					style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
					showWhenHarmful = true, showWhenHelpful = false, showWithoutDispelType = true,
					customDispelColorMap = colors,
				})
			end
		end

		local overlay = CreateFrame("Frame", nil, button)
		overlay:SetAllPoints(button)
		overlay:SetFrameLevel(bar:GetFrameLevel() + 2)
		local size = math.max(math.min(height - 4, 13), 8)
		local name = overlay:CreateFontString(nil, "OVERLAY")
		E:SetFont(name, size)
		name:SetJustifyH("LEFT")
		name:SetWordWrap(false)
		name:SetPoint("LEFT", bar, "LEFT", 3, 0)
		name:SetPoint("RIGHT", bar, "RIGHT", -(size * 3), 0)
		Call(button, "SetSpellName", name)

		if settings.duration ~= "NONE" then
			local text = overlay:CreateFontString(nil, "OVERLAY")
			E:SetFont(text, size)
			text:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
			if not Call(button, "SetDurationText", text, DurationTextOptions(settings)) then
				Call(button, "SetDurationText", text, {})
			end
		end
		if (settings.countSize or 0) > 0 then
			local count = overlay:CreateFontString(nil, "OVERLAY")
			E:SetFont(count, settings.countSize, "OUTLINE")
			count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 1)
			Call(button, "SetApplicationCount", count, {})
		end
		Mouse(button, settings)
	end
end

-- Called by the client once per new button, possibly in combat. Every
-- setting comes from the copy taken when the container was made.
--   settings.edgeOnly  no icon, timer or count: only the dispel-type edges
--                      (a whole-frame dispel highlight)
--   settings.square    { r, g, b[, a] }: a flat colored square instead of
--                      the aura's icon (the timer swipe stays)
--   settings.bar       bar mode (see BarInitializer)
--   group.desaturate   a gray icon (other people's auras, W.SplitOwn)
-- Aura pop-in (settings.popIn): each time the client shows a button
-- for a new aura it grows in from a smaller size and fades in. An EldoUI
-- animation on the button; it never shows, hides, moves or reads it.
local popIns = setmetatable({}, { __mode = "k" }) -- button -> its animation (set up once)
local popOn = setmetatable({}, { __mode = "k" })  -- button -> the pop-in is wanted
-- On Forever the client's aura buttons have secret aspects, so HookScript on
-- them is refused: the first refusal turns pop-in off for the session and
-- hides its option row (W.popInBlocked, Core/UnitFX.lua).
function W.PopIn(button, on)
	popOn[button] = on and true or nil
	if not on or W.popInBlocked or popIns[button] or not button.CreateAnimationGroup then return end
	local group = button:CreateAnimationGroup()
	popIns[button] = group
	local grow = group:CreateAnimation("Scale")
	grow:SetScaleFrom(0.6, 0.6)
	grow:SetScaleTo(1, 1)
	grow:SetDuration(0.15)
	grow:SetSmoothing("OUT")
	local fade = group:CreateAnimation("Alpha")
	fade:SetFromAlpha(0)
	fade:SetToAlpha(1)
	fade:SetDuration(0.15)
	local hooked = pcall(button.HookScript, button, "OnShow", function()
		if popOn[button] and E.db.general.animations then
			group:Stop()
			group:Play()
		end
	end)
	if not hooked then W.popInBlocked = true end
end

local RING_ONCE = { static = true }

local function Initializer(settings, group)
	if settings.bar then return BarInitializer(settings, group) end
	return function(button)
		local width, height = settings.width or settings.size, settings.height or settings.size
		button:SetSize(width, height)

		if settings.edgeOnly then
			AddEdges(button, settings.edgeSize or math.max(E.pixel * 2, 1), {
				showWhenHarmful = true, showWhenHelpful = false, showWithoutDispelType = true,
				customDispelColorMap = ColorMap(settings.dispelColors) or DispelColors(),
			})
			if settings.symbols then W.AddDispelSymbol(button, "RIGHT", 9) end
			Call(button, "SetMouseClickEnabled", false)
			Call(button, "SetMouseMotionEnabled", false)
			return
		end

		local border = button:CreateTexture(nil, "BACKGROUND")
		border:SetAllPoints(button)
		border:SetColorTexture(unpack(E.media.borderColor))

		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
		icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
		if settings.square then
			-- Our own texture; the client never gets it, so the aura's icon
			-- never replaces the color.
			local c = settings.square
			icon:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
		else
			E:TrimIcon(icon)
			if group and group.desaturate then icon:SetDesaturated(true) end
			Call(button, "SetIcon", icon)
			-- The skin's thin icon ring (containers are built again when the look changes).
			E:PaintSurface(button, "icon", "auras", RING_ONCE)
		end

		local mode = settings.duration
		local swipe = mode == "SWIPE" or mode == "BOTH" or mode == "SWIPEONLY"
		local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
		cooldown:SetAllPoints(icon)
		cooldown:SetReverse(true)
		cooldown:SetDrawEdge(false)
		cooldown:SetDrawSwipe(swipe)
		-- A red time (Aura expiring) or a blink replaces the cooldown
		-- numbers, which take no color curve, with the duration text below:
		-- one countdown per icon, and the blink shows.
		local redTime = mode == "SWIPE" and settings.fx and settings.fx.red
		local textTime = mode == "SWIPE" and (redTime or (tonumber(settings.blink) or 0) > 0) and true or false
		cooldown:SetHideCountdownNumbers(mode ~= "SWIPE" or textTime)
		if mode == "SWIPE" and not textTime then
			-- One look for countdowns everywhere: the shared EldoUI
			-- numbers, unless the caller opts out.
			if settings.cooldownLook == false or not W.StyleCooldown(cooldown, settings.durationSize) then
				local countdown = cooldown.GetCountdownFontString and cooldown:GetCountdownFontString()
				if countdown then E:SetFont(countdown, settings.durationSize) end
			end
			local point = settings.durationPoint
			if point and not OUTSIDE[point] and cooldown.GetCountdownFontString then
				local countdown = cooldown:GetCountdownFontString()
				if countdown then PlaceText(countdown, button, point, settings.durationX, settings.durationY, "CENTER") end
			end
		end
		if mode ~= "NONE" then Call(button, "SetDurationCooldown", cooldown) end

		-- Fonts are set before the client gets the font strings.
		if not settings.square and (settings.countSize or 0) > 0 then
			local count = button:CreateFontString(nil, "OVERLAY", nil, 7)
			E:SetFont(count, settings.countSize, "OUTLINE")
			if settings.countPoint then
				PlaceText(count, button, settings.countPoint, settings.countX, settings.countY, "BOTTOMRIGHT")
			else
				count:SetPoint("BOTTOMRIGHT", -1, 2)
			end
			Call(button, "SetApplicationCount", count, {})
		end

		-- Colored edges on helpful auras (enemy buffs on nameplates):
		-- stealable ones in one color, the others by dispel type (Magic,
		-- Enrage, ...) from the caller's map.
		if settings.buffEdges and Enum.CustomAuraButtonDispelTypeStealableFilter then
			local edges = settings.buffEdges
			local thickness = math.max(E.pixel * 2, 1)
			local stealable = ColorMap({ None = edges.stealable, Magic = edges.stealable, Curse = edges.stealable,
				Disease = edges.stealable, Poison = edges.stealable, Enrage = edges.stealable, [""] = edges.stealable })
			if stealable then
				AddEdges(button, thickness, {
					showWhenHarmful = false, showWhenHelpful = true, showWithoutDispelType = true,
					stealableFilter = Enum.CustomAuraButtonDispelTypeStealableFilter.Stealable,
					customDispelColorMap = stealable,
				})
			end
			local byType = ColorMap(edges.types)
			if byType then
				AddEdges(button, thickness, {
					showWhenHarmful = false, showWhenHelpful = true, showWithoutDispelType = false,
					stealableFilter = Enum.CustomAuraButtonDispelTypeStealableFilter.NotStealable,
					customDispelColorMap = byType,
				})
			end
		end

		if mode == "TEXT" or mode == "BOTH" then
			local text = button:CreateFontString(nil, "OVERLAY", nil, 7)
			E:SetFont(text, settings.durationSize, "OUTLINE")
			-- Under the icon the text goes below the time bar, not over it.
			local barRoom = ((settings.timeBar or 0) > 0 and (settings.durationPoint or "BELOW") == "BELOW") and (settings.timeBar + E.pixel) or 0
			PlaceText(text, button, settings.durationPoint, settings.durationX, (settings.durationY or 0) - barRoom, "BELOW")
			if not Call(button, "SetDurationText", text, DurationTextOptions(settings)) then
				Call(button, "SetDurationText", text, {})
			end
		elseif textTime then
			-- In the numbers' place, in the shared countdown look unless the
			-- caller opts out ("Color by time left" is not offered here).
			local text = button:CreateFontString(nil, "OVERLAY", nil, 7)
			E:SetFont(text, settings.durationSize, "OUTLINE")
			PlaceText(text, button, settings.durationPoint, settings.durationX, settings.durationY, "CENTER")
			local look = setmetatable({ timeColors = settings.cooldownLook ~= false }, { __index = settings })
			Call(button, "SetDurationText", text, DurationTextOptions(look))
		end

		-- A thin bar under the icon that empties as the aura runs out.
		if (settings.timeBar or 0) > 0 and mode ~= "NONE" then
			local bar = DurationBar(button, settings.timeBarColor)
			bar:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -E.pixel)
			bar:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -E.pixel)
			bar:SetHeight(settings.timeBar)
		end

		if settings.dispelBorder and Enum.CustomAuraButtonDispelTypeTextureStyle then
			local colors = DispelColors()
			if colors then
				local options = {
					style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
					showWhenHarmful = true,
					showWhenHelpful = false,
					showWithoutDispelType = true,
					customDispelColorMap = colors,
				}
				for _, edge in ipairs(Edges(button, math.max(E.pixel * 2, 1))) do
					if not Call(button, "AddDispelTypeTexture", edge, options) then
						Call(button, "ClearDispelTypeTextures")
						break
					end
				end
			end
			if settings.symbols then W.AddDispelSymbol(button, "TOPLEFT", math.max(7, math.floor(math.min(width, height) * 0.36))) end
		end

		W.PopIn(button, settings.popIn)
		AddEffects(button, settings.fx)
		Mouse(button, settings)
	end
end

local SORT = { TIME = "Expiration", NAME = "Name", INDEX = "Default" }
local CORNER = {
	LEFT = { DOWN = "TOPRIGHT", UP = "BOTTOMRIGHT" },
	RIGHT = { DOWN = "TOPLEFT", UP = "BOTTOMLEFT" },
}

-- Extra room under each row for the duration text.
function W.TextRoom(settings)
	if settings.bar then return 0 end
	local room = 0
	local point = settings.durationPoint
	if (settings.duration == "TEXT" or settings.duration == "BOTH") and (point == nil or point == "BELOW" or point == "ABOVE") then
		room = settings.durationSize + 3
	end
	if (settings.timeBar or 0) > 0 and settings.duration ~= "NONE" then
		room = room + settings.timeBar + 2
	end
	return room
end

-- "Yours first": each group without its own cast-by rule becomes two
-- groups, your auras and then everyone else's (the client checks the
-- caster through the PLAYER filter flag). desaturate grays the second
-- group. groups: E:AuraFilterGroups entries; returns a new list.
function W.SplitOwn(groups, ownFirst, desaturate)
	if not (ownFirst or desaturate) then return groups end
	local mine, others = {}, {}
	for _, group in ipairs(groups) do
		local filter = group.filter or "HELPFUL"
		if filter:find("PLAYER", 1, true) then
			mine[#mine + 1] = group
		else
			local own = CopyTable(group)
			own.filter = filter .. "|PLAYER"
			mine[#mine + 1] = own
			local other = CopyTable(group)
			other.filter = filter .. "|!PLAYER"
			other.desaturate = desaturate and true or nil
			others[#others + 1] = other
		end
	end
	local out = {}
	for _, group in ipairs(mine) do out[#out + 1] = group end
	for _, group in ipairs(others) do out[#out + 1] = group end
	for index, group in ipairs(out) do group.key = "group" .. index end
	return out
end

-- The corner the icons grow from; anchor the container there.
function W.Corner(settings)
	local row = CORNER[settings.growth] or CORNER.RIGHT
	return row[settings.wrap] or row.DOWN
end

---------------------------------------------------------------------------
-- Pool of released containers. The client never frees a frame, so a
-- container that is no longer used waits here, hidden and unparented, until
-- a container with the same settings is asked for again. Keeping it costs
-- nothing more than dropping it would: the pool never holds more containers
-- than were made.
---------------------------------------------------------------------------
local pool = {}                                      -- key -> released containers
local poolKeys = setmetatable({}, { __mode = "k" })  -- container -> its key
local pooled = setmetatable({}, { __mode = "k" })    -- container -> true while it waits

-- The key a container is pooled under: every setting its buttons are built
-- from (W.Signature without the unit, which W.SetUnit changes freely), the
-- pop-in, and the caller's own pool name.
function W.PoolKey(settings)
	return W.Signature(settings, true) .. ":" .. tostring(settings.popIn and true or false) .. ":" .. tostring(settings.pool or "")
end

-- Let W.Release keep `container` for `key`.
function W.PoolAs(container, key)
	if container and key then poolKeys[container] = key end
end

-- A released container made for `key`, moved onto `parent` and shown, or
-- nil when none waits.
function W.FromPool(key, parent)
	local list = key and pool[key]
	local container = list and table.remove(list)
	if not container then return nil end
	pooled[container] = nil
	container:SetParent(parent)
	local level = parent:GetFrameLevel()
	if type(level) == "number" and not (issecretvalue and issecretvalue(level)) then container:SetFrameLevel(level + 1) end
	return container
end

-- How many released containers wait in the pool (for the diagnostics).
function W.PoolSize()
	local count = 0
	for _, list in pairs(pool) do count = count + #list end
	return count
end

-- Make a container on `parent`.
--   settings: unit, groups (E:AuraFilterGroups entries: key, filter,
--   candidateFilters, maxFrameCount, sortMethod, sortDirection; set at
--   creation) or filters (list of filter strings, one group each), max,
--   perGroup (icons per filter; default max / #filters), perRow, size
--   (or width + height), spacing, growth ("LEFT"/"RIGHT"), wrap
--   ("DOWN"/"UP"), attach (the container point pinned to the same point of
--   `parent`; default the growth corner, "TOP"/"BOTTOM"/"CENTER" keep a
--   row centered), sort ("TIME"/"NAME"/"INDEX"), reverse, duration
--   ("TEXT"/"SWIPE"/"SWIPEONLY"/"BOTH"/"NONE"), durationSize, countSize
--   (0 = no stack count), cooldownLook (false keeps the plain countdown),
--   dispelBorder, dispelColors, edgeOnly, edgeSize, square, buffEdges
--   ({ stealable = rgb, types = { Magic = rgb, Enrage = rgb, ... } }),
--   cancel, tooltip, tooltipAnchor, combat.
-- Returns the container, or nil when the client refuses.
function W.Create(parent, settings)
	if not W.Available() then return nil end
	if InCombatLockdown() and not settings.combat then return nil end
	local poolKey = W.PoolKey(settings)
	local reused = not InCombatLockdown() and W.FromPool(poolKey, parent)
	if reused then
		local attach = settings.attach or W.Corner(settings)
		reused:ClearAllPoints()
		reused:SetPoint(attach, parent, attach)
		reused:Show()
		Call(reused, "SetUnit", settings.unit or "player")
		return reused
	end
	local copy = CopyTable(settings)
	copy.symbols = (copy.edgeOnly or copy.dispelBorder) and W.DispelSymbolsOn(copy) or nil
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, TEMPLATE)
	if not ok or not container then return nil end
	local sortMethod = _G.AuraContainerSortMethod and _G.AuraContainerSortMethod[SORT[copy.sort] or "Default"]
	local sortDirection = _G.AuraContainerSortDirection
		and (copy.reverse and _G.AuraContainerSortDirection.Reverse or _G.AuraContainerSortDirection.Normal)
	local elementWidth = copy.bar and copy.bar.width or copy.width or copy.size
	local elementHeight = copy.bar and copy.bar.height or copy.height or copy.size
	local layout = {
		elementWidth = elementWidth,
		elementHeight = elementHeight,
		elementSpacing = copy.spacing,
		lineSpacing = copy.spacing + W.TextRoom(copy),
	}
	-- settings.groups (filter groups) or the older plain filter list.
	local groups = copy.groups
	if not groups then
		groups = {}
		local filters = copy.filters or { "HELPFUL" }
		local perGroup = copy.perGroup or math.max(math.floor(copy.max / #filters), 1)
		for index, filter in ipairs(filters) do
			groups[index] = { key = "group" .. index, filter = filter, maxFrameCount = perGroup }
		end
	end
	for index, group in ipairs(groups) do
		local options = {
			maxFrameCount = math.max(group.maxFrameCount or copy.max or 1, 1),
			sortMethod = group.sortMethod or sortMethod,
			sortDirection = group.sortDirection or sortDirection,
			candidateFilters = group.candidateFilters,
			initializeFrame = Initializer(copy, group),
			layout = layout,
		}
		local key = group.key or ("group" .. index)
		local added = pcall(container.AddAuraGroup, container, key, group.filter or "HELPFUL", options)
		if not added and options.candidateFilters then
			-- The game refused the candidate filters: the filter string alone.
			options.candidateFilters = nil
			added = pcall(container.AddAuraGroup, container, key, group.filter or "HELPFUL", options)
		end
		if not added then
			container:Hide()
			return nil
		end
	end
	local flow = AnchorUtil and AnchorUtil.FlowDirection
	Call(container, "SetFlowLayoutPadding", 0, 0, 0, 0)
	if flow then
		Call(container, "SetFlowLayoutGrowthDirection",
			copy.growth == "LEFT" and flow.Left or flow.Right,
			copy.wrap == "UP" and flow.Up or flow.Down)
	end
	local corner = W.Corner(copy)
	Call(container, "SetFlowLayoutAnchorPoint", corner)
	Call(container, "SetFlowLayoutMaximumLineSize", math.max(copy.perRow, 1) * (elementWidth + copy.spacing))
	-- The container sizes itself to its icons, so pinning its middle
	-- ("TOP", "CENTER", ...) keeps a row centered on that point.
	local attach = copy.attach or corner
	container:ClearAllPoints()
	container:SetPoint(attach, parent, attach)
	container:Show()
	-- The unit goes last: groups added after the first parse stay empty.
	Call(container, "SetUnit", copy.unit or "player")
	W.PoolAs(container, poolKey)
	return container
end

---------------------------------------------------------------------------
-- Aura slots: one fixed place per spell.
-- A slot holds at most one aura and keeps its place. The client shows the
-- slot's button while a matching aura is on the unit and hides it
-- otherwise; there is no "empty" state, so EldoUI never learns whether the
-- aura is there. A "missing" look is drawn by the caller *under* the slot
-- (a faded copy of the spell's icon that the live button covers).
-- Every look and anchor is set inside the initializer: the one moment the
-- button may be touched (afterwards it can be forbidden while auras are
-- secret).
--
--   W.SlotsAvailable()                  containers with slots and spell lists
--   W.CreateSlots(parent, settings)     settings.unit, settings.combat,
--                                       settings.slots = { { key, filter,
--                                       candidateFilters, initialize }, ... },
--                                       settings.poolKey (released containers
--                                       with the same key come back)
--   W.SlotIcon(settings, place, extra)  initializer: the W.Create icon look
--                                       (or bar look with settings.bar), then
--                                       place(button), then extra(button)
--   W.SlotBar(spec, place)              initializer for an invisible button
--                                       that only drives a status bar
--   W.SlotGlow(target, glowKey)         initializer: no icon, covers `target`
--                                       and carries a glow while the aura is on
---------------------------------------------------------------------------
function W.SlotsAvailable()
	if not W.Available() then return false end
	if E.AuraFiltersSupported and not E:AuraFiltersSupported() then return false end
	return true
end

-- The pool key of a slot container: the caller's settings.poolKey (it
-- must cover the parent and everything the slots and their initializers
-- are built from) and the theme the initializers bake in. nil when the
-- caller gives none: the container is not kept.
function W.SlotsPoolKey(settings)
	if settings.poolKey == nil then return nil end
	return "slots:" .. tostring(settings.poolKey) .. ":" .. tostring(settings.unit or "player") .. ":" .. W.ThemeKey()
end

function W.CreateSlots(parent, settings)
	if not W.Available() then return nil end
	if InCombatLockdown() and not settings.combat then return nil end
	-- A released container with the same slots comes back: the client
	-- never frees frames, so each rebuild would otherwise leave one behind.
	local poolKey = W.SlotsPoolKey(settings)
	local reused = poolKey and not InCombatLockdown() and W.FromPool(poolKey, parent)
	if reused then
		reused:ClearAllPoints()
		reused:SetPoint("TOPLEFT", parent, "TOPLEFT")
		reused:SetSize(1, 1)
		reused:Show()
		Call(reused, "SetUnit", settings.unit or "player")
		return reused
	end
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, TEMPLATE)
	if not ok or not container or type(container.AddAuraSlot) ~= "function" then
		if ok and container then container:Hide() end
		return nil
	end
	container:ClearAllPoints()
	container:SetPoint("TOPLEFT", parent, "TOPLEFT")
	container:SetSize(1, 1)
	-- The container itself never takes the mouse; each aura button decides
	-- (settings.tooltip and settings.cancel).
	Call(container, "EnableMouse", false)
	for _, slot in ipairs(settings.slots or {}) do
		local added = pcall(container.AddAuraSlot, container, slot.key, slot.filter or "HELPFUL", {
			candidateFilters = slot.candidateFilters,
			sortMethod = slot.sortMethod,
			sortDirection = slot.sortDirection,
			initializeFrame = slot.initialize,
		})
		if not added then
			W.Release(container)
			return nil
		end
	end
	container:Show()
	Call(container, "SetUnit", settings.unit or "player")
	W.PoolAs(container, poolKey)
	return container
end

-- A glow that the client switches on with its pandemic ("refresh window")
-- flag: a child frame of the button handed over as a pandemic region. The
-- client shows it only while it marks the aura as refreshable; on auras it
-- never marks, it never shows. Nothing is computed here.
local function RefreshGlow(button, glowKey)
	if not (glowKey and button.AddPandemicRegion) then return end
	local region = CreateFrame("Frame", nil, button)
	region:SetAllPoints(button)
	region:Hide()
	E:ShowUserGlow(region, glowKey)
	if not Call(button, "AddPandemicRegion", region) then
		E:HideGlow(region)
	end
end

function W.SlotIcon(settings, place, extra)
	local copy = CopyTable(settings)
	local init = Initializer(copy, nil)
	return function(button)
		init(button)
		if place then place(button) end
		RefreshGlow(button, copy.refreshGlow)
		if extra then extra(button) end
	end
end

-- The shared bar look: texture, color, orientation and fill side
-- of a status bar. Used by the slot bars below and by EldoUI's own bars
-- (Tracking Bars), so aura, stack, cooldown and charge bars look alike.
--   spec.texture (path, default the theme bar texture), color ({ r, g, b }),
--   vertical, reverse (fill from the far end)
function W.StyleBar(bar, spec)
	spec = spec or {}
	bar:SetStatusBarTexture(spec.texture or E.media.statusbar)
	local c = spec.color or E.media.accentColor
	bar:SetStatusBarColor(c[1] or 1, c[2] or 1, c[3] or 1, 1)
	bar:SetOrientation(spec.vertical and "VERTICAL" or "HORIZONTAL")
	bar:SetReverseFill(spec.reverse and true or false)
	if spec.vertical and bar.SetRotatesTexture then bar:SetRotatesTexture(true) end
end

-- spec: width, height, color ({ r, g, b }), reverse (fill instead of
-- drain), duration ({ size, point } for a time text on the bar), count
-- ({ size, point }). Optional: texture, vertical, inset ({ left,
-- right, top, bottom }: room around the bar inside the button, e.g. for an
-- icon), timeCurve (a color curve over the remaining seconds for the time
-- text, evaluated by the client), timeFormatter (a numeric rule formatter
-- for the time text). extra(button, bar) runs inside the
-- initializer after the bar is made (icon, name, frame look), the one
-- moment the button may be touched.
function W.SlotBar(spec, place, extra)
	local timeCurve, timeFormatter = spec.timeCurve, spec.timeFormatter
	local copy = CopyTable(spec)
	copy.timeCurve, copy.timeFormatter = nil, nil
	return function(button)
		button:SetSize(copy.width or 160, copy.height or 12)
		local bar = CreateFrame("StatusBar", nil, button)
		local inset = copy.inset
		if inset then
			bar:SetPoint("TOPLEFT", button, "TOPLEFT", inset.left or 0, -(inset.top or 0))
			bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -(inset.right or 0), inset.bottom or 0)
		else
			bar:SetAllPoints(button)
		end
		W.StyleBar(bar, { texture = copy.texture, color = copy.color, vertical = copy.vertical })
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		local timer = Enum.StatusBarTimerDirection
		local direction = timer and (copy.reverse and timer.ElapsedTime or timer.RemainingTime)
		if not Call(button, "SetDurationBar", bar, { direction = direction }) then
			Call(button, "SetDurationBar", bar, {})
		end
		if copy.duration then
			local text = bar:CreateFontString(nil, "OVERLAY")
			E:SetFont(text, copy.duration.size or E.tokens.size.small, "OUTLINE")
			PlaceText(text, bar, copy.duration.point or "RIGHT", copy.duration.point == "LEFT" and 3 or -3, 0, "RIGHT")
			local options = DurationTextOptions({ durationSize = copy.duration.size, timeColors = copy.duration.timeColors })
			local property = Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration
			if timeCurve and property then options.textColor = { curve = timeCurve, property = property } end
			if timeFormatter then options.textFormatter = timeFormatter end
			if not Call(button, "SetDurationText", text, options) then
				Call(button, "SetDurationText", text, {})
			end
		end
		if copy.count then
			local count = bar:CreateFontString(nil, "OVERLAY")
			E:SetFont(count, copy.count.size or E.tokens.size.small, "OUTLINE")
			PlaceText(count, bar, copy.count.point or "LEFT", 3, 0, "LEFT")
			Call(button, "SetApplicationCount", count, {})
		end
		Call(button, "SetMouseClickEnabled", false)
		Call(button, "SetMouseMotionEnabled", false)
		if place then place(button) end
		if extra then extra(button, bar) end
	end
end

---------------------------------------------------------------------------
-- Stack bars: an aura's stack count as a bar, drawn by the client.
-- The aura button's application bar (SetApplicationBar) gets min 0, max
-- maxApplications and the stack count as its value inside the client;
-- Lua never sees the count. Each color layer is one more aura slot on the
-- same aura (two slots of one container may match the same aura), with
-- its own bar, so the client fills every layer from the same count:
--   continuous  one bar over the whole length
--   segments    the same bar with a thin gap at every stack
--   folded      stacks above half fill a second color over the first half
--   ranges      a color from stack N up: two layers per threshold, the
--               whole fill recolored once the count reaches N:
--                 track  the plain bar, masked to the part past N
--                 step   a long bar shifted so its edge crosses the part
--                        up to N exactly when the count goes from N-1 to N
--               (geometry and masks only; nothing compares the count)
-- Masks are MaskTextures made on the layer's own button, the clip that
-- works inside aura buttons (a clipping ancestor would hide the button).
--
--   W.SlotStackBar(spec, place, extra) -> { { key, initialize }, ... }
--     One entry per layer, bottom layer first; add each as a slot with the
--     same filter (keys must differ). spec: width, height, max (stacks for
--     a full bar), mode ("continuous" | "segments" | "folded"), color,
--     color2 (folded), ranges ({ { from = N, color = rgb }, ... }),
--     maxColor (from max up), texture, vertical, reverse, inset (as
--     W.SlotBar), marks ({ N, ... }: thin lines at these stack counts),
--     count ({ size, point }: the stack count on the bottom layer).
--     place(button, layerIndex) anchors each button; extra(button, bar)
--     dresses the bottom layer (icon, name, frame).
-- At most W.STACK_LAYERS layers; extra thresholds are dropped.
---------------------------------------------------------------------------
W.STACK_LAYERS = 10

local function Window(button, from, to, inset, vertical, reverse, length)
	local mask = button:CreateMaskTexture(nil, "BACKGROUND")
	mask:SetTexture(E.media.flat, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
	local a, b = from * length, to * length
	local l, r, t, bt = inset.left or 0, inset.right or 0, inset.top or 0, inset.bottom or 0
	if vertical then
		if reverse then
			mask:SetPoint("TOPLEFT", button, "TOPLEFT", l, -(t + a))
			mask:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", -r, -(t + b))
		else
			mask:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", l, bt + a)
			mask:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", -r, bt + b)
		end
	elseif reverse then
		mask:SetPoint("TOPRIGHT", button, "TOPRIGHT", -(r + a), -t)
		mask:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT", -(r + b), bt)
	else
		mask:SetPoint("TOPLEFT", button, "TOPLEFT", l + a, -t)
		mask:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", l + b, bt)
	end
	return mask
end

-- One layer's bar: `offset` and `size` along the fill axis in fractions of
-- the bar length, measured from the side the fill starts at.
local function LayerBar(button, layer, spec, inset, length, thickness)
	local bar = CreateFrame("StatusBar", nil, button)
	local o, s = layer.offset * length, layer.size * length
	local l, r, t, bt = inset.left or 0, inset.right or 0, inset.top or 0, inset.bottom or 0
	if spec.vertical then
		bar:SetSize(thickness, math.max(s, 1))
		if spec.reverse then
			bar:SetPoint("TOPLEFT", button, "TOPLEFT", l, -(t + o))
		else
			bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", l, bt + o)
		end
	else
		bar:SetSize(math.max(s, 1), thickness)
		if spec.reverse then
			bar:SetPoint("TOPRIGHT", button, "TOPRIGHT", -(r + o), -t)
		else
			bar:SetPoint("TOPLEFT", button, "TOPLEFT", l + o, -t)
		end
	end
	W.StyleBar(bar, { texture = spec.texture, color = layer.color, vertical = spec.vertical, reverse = spec.reverse })
	bar:SetMinMaxValues(0, layer.max)
	bar:SetValue(0)
	return bar
end

-- The layer list for a spec (pure geometry).
function W.StackLayers(spec)
	local max = math.max(1, math.floor(tonumber(spec.max) or 5))
	local base = spec.color or E.media.accentColor
	local layers = {}
	if spec.mode == "folded" and max >= 2 then
		local half = math.ceil(max / 2)
		layers[1] = { offset = 0, size = 1, max = half, color = base }
		-- Count - half over the same length: a bar twice as long that
		-- starts one length before the fill side, cut to the bar.
		layers[2] = { offset = -1, size = 2, max = 2 * half, color = spec.color2 or { 1, 0.5, 0.1 }, window = { 0, 1 } }
		return layers, max
	end
	layers[1] = { offset = 0, size = 1, max = max, color = base }
	local thresholds = {}
	for _, range in ipairs(spec.ranges or {}) do
		local from = math.floor(tonumber(range.from) or 0)
		if from >= 1 and from <= max and type(range.color) == "table" then thresholds[#thresholds + 1] = { from = from, color = range.color } end
	end
	if type(spec.maxColor) == "table" then thresholds[#thresholds + 1] = { from = max, color = spec.maxColor } end
	table.sort(thresholds, function(a, b) return a.from < b.from end)
	for _, threshold in ipairs(thresholds) do
		if #layers + 2 > W.STACK_LAYERS then break end
		local n = threshold.from
		-- track: the fill past N.
		if n < max then
			layers[#layers + 1] = { offset = 0, size = 1, max = max, color = threshold.color, window = { n / max, 1 } }
		end
		-- step: n bars long, starting (n-1) stacks' worth of that length
		-- before the fill side; full over [0, N] from count N on.
		layers[#layers + 1] = { offset = -(n - 1) * n / max, size = n, max = max, color = threshold.color, window = { 0, n / max } }
	end
	return layers, max
end

function W.SlotStackBar(spec, place, extra)
	local copy = CopyTable(spec)
	local layers, max = W.StackLayers(copy)
	local entries = {}
	for index, layer in ipairs(layers) do
		local isBase, isTop = index == 1, index == #layers
		entries[index] = { key = "L" .. index, initialize = function(button)
			local width, height = copy.width or 160, copy.height or 12
			button:SetSize(width, height)
			local inset = copy.inset or {}
			local along = copy.vertical and height - (inset.top or 0) - (inset.bottom or 0) or width - (inset.left or 0) - (inset.right or 0)
			local across = copy.vertical and width - (inset.left or 0) - (inset.right or 0) or height - (inset.top or 0) - (inset.bottom or 0)
			along, across = math.max(along, 1), math.max(across, 1)
			local bar = LayerBar(button, layer, copy, inset, along, across)
			-- The client sets the range and the value from the stack count.
			if not Call(button, "SetApplicationBar", bar, { maxApplications = layer.max }) then
				bar:SetAlpha(0) -- a client without application bars: draw nothing rather than a wrong bar
			end
			if layer.window then
				local fill = bar:GetStatusBarTexture()
				if fill and fill.AddMaskTexture then
					fill:AddMaskTexture(Window(button, layer.window[1], layer.window[2], inset, copy.vertical, copy.reverse, along))
				end
			end
			if isTop then
				-- Segment gaps and marks on the top layer, over every fill.
				local lines = {}
				if copy.mode == "segments" and max > 1 then
					for n = 1, max - 1 do lines[#lines + 1] = n end
				end
				for _, n in ipairs(copy.marks or {}) do
					n = tonumber(n)
					if n and n > 0 and n < max then lines[#lines + 1] = n end
				end
				local overlay = CreateFrame("Frame", nil, button)
				overlay:SetAllPoints(button)
				overlay:SetFrameLevel(bar:GetFrameLevel() + 2)
				for _, n in ipairs(lines) do
					local line = overlay:CreateTexture(nil, "OVERLAY")
					local c = E.media.borderColor
					line:SetColorTexture(c[1] or 0, c[2] or 0, c[3] or 0, 1)
					local at = n / max * along
					local px = math.max(E.pixel or 1, 1)
					if copy.vertical then
						line:SetSize(across, px)
						if copy.reverse then
							line:SetPoint("TOPLEFT", button, "TOPLEFT", inset.left or 0, -((inset.top or 0) + at))
						else
							line:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", inset.left or 0, (inset.bottom or 0) + at)
						end
					else
						line:SetSize(px, across)
						if copy.reverse then
							line:SetPoint("TOPRIGHT", button, "TOPRIGHT", -((inset.right or 0) + at), -(inset.top or 0))
						else
							line:SetPoint("TOPLEFT", button, "TOPLEFT", (inset.left or 0) + at, -(inset.top or 0))
						end
					end
				end
			end
			if isBase and copy.count then
				local count = bar:CreateFontString(nil, "OVERLAY")
				E:SetFont(count, copy.count.size or E.tokens.size.small, "OUTLINE")
				PlaceText(count, button, copy.count.point or "RIGHT", copy.count.point == "LEFT" and 3 or -3, 0, "RIGHT")
				Call(button, "SetApplicationCount", count, {})
			end
			Call(button, "SetMouseClickEnabled", false)
			Call(button, "SetMouseMotionEnabled", false)
			if place then place(button, index) end
			if isBase and extra then extra(button, bar) end
		end }
	end
	return entries
end

function W.SlotGlow(target, glowKey)
	return function(button)
		button:ClearAllPoints()
		button:SetAllPoints(target)
		local level = target:GetFrameLevel()
		if type(level) == "number" and not (issecretvalue and issecretvalue(level)) then button:SetFrameLevel(level) end
		Call(button, "SetMouseClickEnabled", false)
		Call(button, "SetMouseMotionEnabled", false)
		E:ShowUserGlow(button, glowKey)
	end
end

-- Stop and drop a container (out of combat). A container made by
-- W.Create (or marked with W.PoolAs) waits in the pool for the same
-- settings.
function W.Release(container)
	if not container then return end
	Call(container, "SetUnit", "none")
	container:Hide()
	container:ClearAllPoints()
	container:SetParent(nil)
	local key = poolKeys[container]
	if key and not pooled[container] then
		local list = pool[key]
		if not list then
			list = {}
			pool[key] = list
		end
		list[#list + 1] = container
		pooled[container] = true
	end
end

-- Ask the client to rebuild the icons (e.g. a new target in the frame).
function W.Refresh(container)
	if container then Call(container, "UpdateAllAuras") end
end

-- Point a container at another unit ("none" empties it). Allowed in
-- combat: it only changes which unit the client reads.
function W.SetUnit(container, unit)
	if container then Call(container, "SetUnit", unit or "none") end
end

local function Flat(value)
	if type(value) ~= "table" then return tostring(value) end
	local keys = {}
	for key in pairs(value) do keys[#keys + 1] = tostring(key) end
	table.sort(keys)
	local parts = {}
	for _, key in ipairs(keys) do
		local item = value[key]
		if item == nil then item = value[tonumber(key)] end
		parts[#parts + 1] = key .. "=" .. Flat(item)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

-- The look baked into each icon when its container is built: border and
-- panel colors, accent (time bars), font and outline, bar texture
-- (E:ThemeKey) and the shared cooldown-number look. Part of every
-- signature, so a theme change (E:RefreshTheme -> OnProfileChanged)
-- rebuilds the containers with the new look.
function W.ThemeKey()
	return (E.ThemeKey and E:ThemeKey() or "") .. "|" .. Flat(W.CooldownLook())
end

-- A string that changes whenever a setting that needs a new container does.
-- The unit is left out when `withoutUnit` is set (callers that follow unit
-- changes with W.SetUnit).
function W.Signature(settings, withoutUnit)
	local filters = table.concat(settings.filters or {}, "+")
	return table.concat({ withoutUnit and "" or tostring(settings.unit), filters, settings.max, tostring(settings.perGroup),
		settings.perRow, tostring(settings.size), tostring(settings.width), tostring(settings.height), settings.spacing,
		tostring(settings.growth), tostring(settings.wrap), tostring(settings.attach), tostring(settings.sort),
		tostring(settings.reverse), tostring(settings.duration), settings.durationSize or 0, settings.countSize or 0,
		tostring(settings.cooldownLook), tostring(settings.dispelBorder), Flat(settings.dispelColors),
		tostring(settings.edgeOnly), tostring(settings.edgeSize), Flat(settings.square), Flat(settings.buffEdges),
		tostring(settings.cancel), tostring(settings.tooltip), tostring(settings.tooltipAnchor), E.pixel or 1,
		Flat(settings.groups), tostring(settings.countPoint), tostring(settings.countX), tostring(settings.countY),
		tostring(settings.durationPoint), tostring(settings.durationX), tostring(settings.durationY),
		tostring(settings.timeColors), tostring(settings.blink), tostring(settings.timeBar),
		Flat(settings.timeBarColor), Flat(settings.bar), Flat(settings.fx), W.ThemeKey(),
		tostring((settings.edgeOnly or settings.dispelBorder) and W.DispelSymbolsOn(settings) or false) }, ":")
end
