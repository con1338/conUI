-- EldoUI tracking bars: bars the player builds for one spell each.
--   Aura, time left   the aura's own duration bar (an aura slot's button
--                     drives a status bar inside the client, W.SlotBar)
--   Aura, stacks      the aura's stack count as a bar (application bar,
--                     W.SlotStackBar): one bar, one segment per stack, or
--                     folded, with color ranges and a max-stack color
--   Cooldown          drains while a spell or item is on cooldown
--   Charges           one segment per charge, a thin recharge strip under it
--
-- Nothing here reads an aura or computes a time:
--   * aura bars are aura container slots filtered to the bar's spell; the
--     client shows the slot while the aura is up and fills its bar from
--     the aura's duration or stack count. A faded copy of the bar under
--     the slot is the "missing" look; nothing checks the aura.
--   * cooldown bars run from the game's duration object, read through the
--     combat kit's one cooldown source (K.Cooldowns in Kit.lua), which also
--     says when the game reports a change (spells: the game's duration ->
--     StatusBar:SetTimerDuration; items: a duration made from the game's
--     start and duration, passed on untouched). Whether a cooldown runs
--     comes from the game's own isActive / isOnGCD flags; the global
--     cooldown alone is "ready".
--   * charge bars get the charge count straight from the game into
--     SetValue / SetText (it may be secret); the number of charges is read
--     out of combat, while it is plain.
--   * color by time left is a color curve the client evaluates (the
--     time text of aura bars, the fill of cooldown bars).
-- Aura Groups keep their list bars; both use the same bar look
-- (E.AuraWidget.StyleBar), so the two read as one product.
--
-- Placement: bars sit in one block or on their own mover. The block hangs
-- under the main cooldown row on the cooldown stack (K.CooldownStack,
-- "tracking": under the item row, above a cast bar there; it also keeps
-- clear of the utility row), or on its own mover EldoUI_TrackingBars. A
-- bar may take the width of the essential or utility cooldown row and
-- follows it. Free bars use EldoUI_TrackingBar<N>.
local _, E = ...
local K = E.CombatKit
local CD = K.Cooldowns
local W = E.AuraWidget
local L = E.L

local MAX_BARS = 30
local BLOCK_MOVER = "EldoUI_TrackingBars"
local GROUP = "trackbars"
local COLOR_TICK = "trackbars:colors"
local COLOR_RATE = 0.1      -- color-by-time updates per second while a cooldown bar runs
local UNIT_EVENTS = { target = "PLAYER_TARGET_CHANGED", focus = "PLAYER_FOCUS_CHANGED" }

-- A new bar's settings (also fills missing fields of saved bars).
local function NewBar()
	return {
		enabled = true,
		kind = "aura",            -- aura | cooldown | charges
		spell = "",               -- spell name or ID (item:ID for item cooldowns)
		unit = "player",          -- aura bars: player | target | focus | pet
		auraKind = "HELPFUL",     -- HELPFUL | HARMFUL
		mine = true,
		mode = "duration",        -- aura bars: duration | stacks
		stackMode = "continuous", -- continuous | segments | folded
		maxStacks = 5,
		color2 = { 1, 0.55, 0.1 },
		ranges = {
			{ enabled = false, from = 3, color = { 1, 0.82, 0 } },
			{ enabled = false, from = 4, color = { 1, 0.5, 0.1 } },
			{ enabled = false, from = 5, color = { 1, 0.25, 0.25 } },
		},
		useMaxColor = false,
		maxColor = { 0.3, 1, 0.4 },
		ticks = "",
		width = 220, height = 18,
		matchRow = "essential",   -- none | essential | utility
		texture = "",
		color = { 0.3, 0.6, 1 },
		icon = "LEFT",            -- LEFT | RIGHT | NONE
		showName = true,
		showTime = true,
		showCount = true,
		decimals = 1,
		reverse = false,
		vertical = false,
		colorByTime = false,
		timeUnit = "seconds",     -- seconds | percent
		lowTime = 5,
		lowColor = { 1, 0.3, 0.3 },
		inactive = "fade",        -- show | fade | hide
		inactiveAlpha = 30,
		readyText = "",
		own = false,              -- own mover instead of the block
		visibility = E:VisibilityDefaults(),
	}
end

local M = E:NewModule("TrackingBars", {
	title = "Tracking Bars",
	desc = L["Bars you build for one spell each: an aura's time left or stacks, a spell's or item's cooldown, or its charges. They hang under the cooldown rows; the game fills every bar."],
	category = "Combat",
	frames = {},
	movers = { "EldoUI_TrackingBars" }, -- and one per bar the player places on its own
	blizzard = {},
	savedKeys = { "profile.modules.TrackingBars" },
	optionsPage = "module:TrackingBars",
	presets = { "Airy", "Free", "Large", "Tight", "Under" },
	reload = false,
	defaults = {
		enabled = false,
		bars = {},
		edit = 1,
		placement = "stack",      -- stack (under the main cooldown row) | mover
		spacing = 2,
		fontSize = 11,
		texture = "",
	},
})

E:RegisterGlowUser("trackingBars", {
	title = "Tracking Bars",
	desc = "A tracking bar whose spell the game lights up (a proc or a reactive spell). Only the game's own spell alert starts it.",
	order = 24,
	default = { style = "pixel", colorMode = "custom", color = { 1, 0.82, 0 } },
})

local built = {}         -- index -> entry
local block              -- the frame the block bars hang in
local blockHolder        -- the block's own mover frame
local pendingRebuild = false

---------------------------------------------------------------------------
-- Settings helpers
---------------------------------------------------------------------------
local TEMPLATE = NewBar()

local function Fill(bar)
	for key, value in pairs(TEMPLATE) do
		if bar[key] == nil then bar[key] = type(value) == "table" and CopyTable(value) or value end
	end
	if type(bar.ranges) ~= "table" then bar.ranges = CopyTable(TEMPLATE.ranges) end
	for index = 1, 3 do
		if type(bar.ranges[index]) ~= "table" then bar.ranges[index] = CopyTable(TEMPLATE.ranges[index]) end
	end
	return bar
end

local function Bars()
	local list = M.db and M.db.bars
	if type(list) ~= "table" then return {} end
	return list
end

local function BarDB(index)
	local bar = Bars()[index]
	if type(bar) ~= "table" then return nil end
	return Fill(bar)
end

-- The bar's spell or item: "spell", id | "item", id | nil.
function M.Source(bar)
	local text = strtrim(tostring(bar and bar.spell or ""))
	if text == "" then return nil end
	local item = tonumber(text:match("^[Ii]tem:(%d+)$") or text:match("|Hitem:(%d+)"))
	if item then return "item", item end
	local id = tonumber(text:match("|Hspell:(%d+)")) or tonumber(text)
	if not id and C_Spell.GetSpellIDForSpellIdentifier then
		local ok, found = pcall(C_Spell.GetSpellIDForSpellIdentifier, text)
		if ok and found and K.Plain(found) then id = found end
	end
	if not id and E.ResolveSpell then id = E:ResolveSpell(text) end
	if id and K.Plain(id) and C_Spell.GetSpellTexture(id) then return "spell", id end
end

local function Describe(kind, id)
	if kind == "item" then
		local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
		return type(name) == "string" and name or ("item:" .. id), C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
	end
	local name = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
	return type(name) == "string" and name or ("spell:" .. id), C_Spell.GetSpellTexture(id)
end

local function Texture(bar)
	local name = (bar.texture ~= "" and bar.texture) or (M.db.texture ~= "" and M.db.texture) or nil
	return K.TexturePath(name)
end

local function Ticks(text)
	local list = {}
	for word in tostring(text or ""):gmatch("[^,;%s]+") do
		local n = tonumber(word)
		if n then list[#list + 1] = n end
	end
	return list
end

---------------------------------------------------------------------------
-- Width: a cooldown row's width when the bar matches one.
---------------------------------------------------------------------------
local function RowWidth(which)
	if which == "essential" then return K.CooldownStack.Width() end
	if which == "utility" then
		local mover = E.movers and E.movers.EldoUI_CooldownsUtility
		if mover and mover.GetWidth then
			local ok, width = pcall(mover.GetWidth, mover)
			if ok and type(width) == "number" and K.Plain(width) and width > 20 then return math.floor(width + 0.5) end
		end
	end
	return nil
end

-- Length along the fill and thickness across it.
local function Size(bar)
	local length = (bar.matchRow ~= "none" and RowWidth(bar.matchRow)) or tonumber(bar.width) or 220
	local thickness = tonumber(bar.height) or 18
	length = math.max(40, math.min(800, length))
	thickness = math.max(4, math.min(60, thickness))
	return length, thickness
end

-- Root frame size and the room the icon takes (insets of the bar part).
local function Geometry(bar)
	local length, thickness = Size(bar)
	local px = E.pixel or 1
	local icon = bar.icon ~= "NONE" and thickness or 0
	local inset = { left = px, right = px, top = px, bottom = px }
	local width, height
	if bar.vertical then
		width, height = thickness, length
		if icon > 0 then
			if bar.icon == "RIGHT" then inset.top = icon + px else inset.bottom = icon + px end
		end
	else
		width, height = length, thickness
		if icon > 0 then
			if bar.icon == "RIGHT" then inset.right = icon + px else inset.left = icon + px end
		end
	end
	return width, height, inset, icon
end

---------------------------------------------------------------------------
-- Formatter and curves (built once per setting, the client runs them)
---------------------------------------------------------------------------
local formatters = {}
local function TimeFormatter(decimals)
	decimals = decimals == 0 and 0 or 1
	if formatters[decimals] ~= nil then return formatters[decimals] or nil end
	formatters[decimals] = false
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding) then return nil end
	local up = Enum.NumericRuleFormatRounding.Up
	local rules = {}
	if decimals == 1 then
		rules[#rules + 1] = { threshold = 0, step = 0.1, rounding = up, format = "%.1f" }
		rules[#rules + 1] = { threshold = 10, step = 1, rounding = up, format = "%.0f" }
	else
		rules[#rules + 1] = { threshold = 0, step = 1, rounding = up, format = "%.0f" }
	end
	rules[#rules + 1] = { threshold = 60, format = L["%.0fm"], components = { { div = 60, step = 1, rounding = up } } }
	rules[#rules + 1] = { threshold = 3600, format = L["%.0fh"], components = { { div = 3600, step = 1, rounding = up } } }
	local ok, formatter = pcall(function()
		local f = C_StringUtil.CreateNumericRuleFormatter()
		f:SetBreakpoints(rules)
		return f
	end)
	formatters[decimals] = ok and formatter or false
	return formatters[decimals] or nil
end

local curves = {}
-- Low color at and under `low` (seconds, or a share 0-1), the normal
-- color above it. Step curve: the client picks the color.
local function TimeCurve(low, lowColor, normal)
	if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
	local key = table.concat({ low, lowColor[1] or 1, lowColor[2] or 1, lowColor[3] or 1, normal[1] or 1, normal[2] or 1, normal[3] or 1 }, ":")
	if curves[key] ~= nil then return curves[key] or nil end
	curves[key] = false
	local ok, curve = pcall(function()
		local c = C_CurveUtil.CreateColorCurve()
		if Enum.LuaCurveType and c.SetType then c:SetType(Enum.LuaCurveType.Step) end
		c:AddPoint(0, CreateColor(lowColor[1] or 1, lowColor[2] or 1, lowColor[3] or 1, 1))
		c:AddPoint(low, CreateColor(normal[1] or 1, normal[2] or 1, normal[3] or 1, 1))
		return c
	end)
	curves[key] = ok and curve or false
	return curves[key] or nil
end

local function BarCurve(bar, normal)
	if not bar.colorByTime then return nil end
	local low = math.max(0, tonumber(bar.lowTime) or 5)
	if bar.timeUnit == "percent" then low = math.min(low, 100) / 100 end
	return TimeCurve(low, bar.lowColor or { 1, 0.3, 0.3 }, normal)
end

---------------------------------------------------------------------------
-- The bar look (shared by every kind): a 1 px box behind the bar part,
-- the icon at one end, the name and the time on the bar.
---------------------------------------------------------------------------
local function Box(parent, inset)
	local box = CreateFrame("Frame", nil, parent)
	box:SetPoint("TOPLEFT", parent, "TOPLEFT", inset.left - (E.pixel or 1), -(inset.top - (E.pixel or 1)))
	box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(inset.right - (E.pixel or 1)), inset.bottom - (E.pixel or 1))
	E:SetTemplate(box, true)
	box:SetFrameLevel(math.max(parent:GetFrameLevel() - 1, 0))
	return box
end

local function IconTexture(parent, bar, iconSize)
	if iconSize <= 0 then return nil end
	local icon = parent:CreateTexture(nil, "ARTWORK")
	icon:SetSize(iconSize, iconSize)
	local side
	if bar.vertical then
		side = bar.icon == "RIGHT" and "TOP" or "BOTTOM"
	else
		side = bar.icon == "RIGHT" and "RIGHT" or "LEFT"
	end
	icon:SetPoint(side, parent, side, 0, 0)
	E:TrimIcon(icon)
	local back = parent:CreateTexture(nil, "BACKGROUND")
	back:SetPoint("TOPLEFT", icon, "TOPLEFT", -(E.pixel or 1), E.pixel or 1)
	back:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", E.pixel or 1, -(E.pixel or 1))
	local c = E.media.borderColor
	back:SetColorTexture(c[1] or 0, c[2] or 0, c[3] or 0, 1)
	return icon
end

local function NameText(parent, anchor, bar)
	if not bar.showName or bar.vertical then return nil end
	local text = parent:CreateFontString(nil, "OVERLAY")
	E:SetFont(text, M.db.fontSize or E.tokens.size.small, "OUTLINE")
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	text:SetPoint("LEFT", anchor, "LEFT", 4, 0)
	text:SetPoint("RIGHT", anchor, "RIGHT", -40, 0)
	return text
end

-- Our own copy of a bar: the "missing" look under an aura slot, and the
-- whole bar for cooldown and charge bars. Each bar index keeps one such
-- frame for its whole life: a settings change, a new row width or a UI
-- scale change restyles it in place instead of making new frames.
M.ownStats = { created = 0 }

local function PlaceBox(box, parent, inset)
	local px = E.pixel or 1
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", parent, "TOPLEFT", inset.left - px, -(inset.top - px))
	box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(inset.right - px), inset.bottom - px)
	E:SetTemplate(box, true)
	box:SetFrameLevel(math.max(parent:GetFrameLevel() - 1, 0))
end

local function OwnFrame(entry)
	local frame = entry.ownFrame
	if frame then return frame end
	M.ownStats.created = M.ownStats.created + 1
	frame = CreateFrame("Frame", nil, entry.root)
	frame:SetAllPoints(entry.root)
	frame.box = CreateFrame("Frame", nil, frame)
	frame.bar = CreateFrame("StatusBar", nil, frame)
	frame.overlay = CreateFrame("Frame", nil, frame)
	frame.overlay:SetAllPoints(frame)
	frame.segments = {}
	entry.ownFrame = frame
	return frame
end

local function StyleIcon(frame, bar, iconSize, iconFile)
	if iconSize <= 0 then
		if frame.icon then
			frame.icon:Hide()
			frame.iconBack:Hide()
		end
		return
	end
	if not frame.icon then
		frame.icon = frame:CreateTexture(nil, "ARTWORK")
		E:TrimIcon(frame.icon)
		frame.iconBack = frame:CreateTexture(nil, "BACKGROUND")
	end
	local icon, back = frame.icon, frame.iconBack
	local px = E.pixel or 1
	icon:SetSize(iconSize, iconSize)
	local side
	if bar.vertical then
		side = bar.icon == "RIGHT" and "TOP" or "BOTTOM"
	else
		side = bar.icon == "RIGHT" and "RIGHT" or "LEFT"
	end
	icon:ClearAllPoints()
	icon:SetPoint(side, frame, side, 0, 0)
	icon:SetTexture(iconFile)
	icon:Show()
	back:ClearAllPoints()
	back:SetPoint("TOPLEFT", icon, "TOPLEFT", -px, px)
	back:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", px, -px)
	local c = E.media.borderColor
	back:SetColorTexture(c[1] or 0, c[2] or 0, c[3] or 0, 1)
	back:Show()
end

local function StyleName(frame, bar, name)
	if not bar.showName or bar.vertical then
		if frame.name then frame.name:Hide() end
		return
	end
	if not frame.name then
		frame.name = frame.overlay:CreateFontString(nil, "OVERLAY")
		frame.name:SetJustifyH("LEFT")
		frame.name:SetWordWrap(false)
		frame.name:SetPoint("LEFT", frame.bar, "LEFT", 4, 0)
		frame.name:SetPoint("RIGHT", frame.bar, "RIGHT", -40, 0)
	end
	E:SetFont(frame.name, M.db.fontSize or E.tokens.size.small, "OUTLINE")
	frame.name:SetText(name or "")
	frame.name:Show()
end

-- The kind-specific parts a restyle doesn't use are hidden and cleared.
local function HideParts(frame, keep)
	if keep ~= "cooldown" then
		if frame.countdown then
			frame.countdown:Clear()
			frame.countdown:Hide()
		end
		if frame.ready then frame.ready:Hide() end
	end
	if keep ~= "charges" then
		for _, line in ipairs(frame.segments) do line:Hide() end
		if frame.recharge then frame.recharge:Hide() end
		if frame.count then frame.count:Hide() end
		if frame.max then frame.max:Hide() end
		if frame.chargeDone then
			frame.chargeDone:Clear()
			frame.chargeDone:Hide()
		end
	end
end

local function OwnBar(entry, bar, name, iconFile)
	local _, _, inset, iconSize = Geometry(bar)
	local frame = OwnFrame(entry)
	frame:SetAlpha(1)
	frame:Show()
	PlaceBox(frame.box, frame, inset)
	frame.bar:ClearAllPoints()
	frame.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", inset.left, -inset.top)
	frame.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset.right, inset.bottom)
	W.StyleBar(frame.bar, { texture = Texture(bar), color = bar.color, vertical = bar.vertical, reverse = bar.reverse })
	if not bar.vertical and frame.bar.SetRotatesTexture then frame.bar:SetRotatesTexture(false) end
	frame.bar:SetMinMaxValues(0, 1)
	frame.bar:SetValue(0)
	frame.overlay:SetFrameLevel(frame.bar:GetFrameLevel() + 3)
	StyleIcon(frame, bar, iconSize, iconFile)
	StyleName(frame, bar, name)
	HideParts(frame, bar.kind)
	return frame
end

local function Release(entry)
	if entry.container then W.Release(entry.container) end
	entry.container = nil
	if entry.own then
		HideParts(entry.own, nil)
		entry.own:Hide()
		entry.own = nil
	end
	entry.cooldown = nil
	entry.duration = nil
	entry.sig = nil
end

---------------------------------------------------------------------------
-- Aura bars: one container, one slot (time left) or one slot per layer
-- (stacks), all on the same aura.
---------------------------------------------------------------------------
local function AuraBar(entry, bar, index, id, name, iconFile)
	local root = entry.root
	local width, height, inset, iconSize = Geometry(bar)
	-- The missing look: our own faded copy under the slot.
	entry.own = OwnBar(entry, bar, name, iconFile)
	if not W.SlotsAvailable() then return end
	local filter, candidateFilters = E:AuraSpellSlotSpec(id, bar.auraKind == "HARMFUL" and "HARMFUL" or "HELPFUL", bar.mine)
	if not filter then return end
	local fontSize = M.db.fontSize or 11
	local function Dress(button, statusBar)
		-- Frame look, icon and name inside the button: the client shows
		-- them only while the aura is up.
		Box(button, inset)
		local icon = IconTexture(button, bar, iconSize)
		if icon then
			if not (button.SetIcon and pcall(button.SetIcon, button, icon)) then icon:SetTexture(iconFile) end
		end
		local text = NameText(button, statusBar, bar)
		if text then
			if not (button.SetSpellName and pcall(button.SetSpellName, button, text)) then text:SetText(name or "") end
		end
	end
	local function Place(button, layer)
		button:ClearAllPoints()
		button:SetAllPoints(root)
		button:SetFrameLevel(root:GetFrameLevel() + 4 + (layer or 0) * 2)
	end
	local slots = {}
	local key = "b" .. index
	if bar.mode == "stacks" then
		local ranges = {}
		for _, range in ipairs(bar.ranges) do
			if range.enabled then ranges[#ranges + 1] = { from = range.from, color = range.color } end
		end
		local layers = W.SlotStackBar({
			width = width, height = height, inset = inset, max = bar.maxStacks, mode = bar.stackMode,
			color = bar.color, color2 = bar.color2, ranges = ranges, maxColor = bar.useMaxColor and bar.maxColor or nil,
			texture = Texture(bar), vertical = bar.vertical, reverse = bar.reverse, marks = Ticks(bar.ticks),
			count = bar.showCount and { size = fontSize, point = "RIGHT" } or nil,
		}, Place, Dress)
		for _, layer in ipairs(layers) do
			slots[#slots + 1] = { key = key .. layer.key, filter = filter, candidateFilters = candidateFilters, initialize = layer.initialize }
		end
	else
		local initialize = W.SlotBar({
			width = width, height = height, inset = inset, color = bar.color, texture = Texture(bar),
			vertical = bar.vertical, reverse = bar.reverse,
			duration = (bar.showTime and not bar.vertical) and { size = fontSize, point = "RIGHT" } or nil,
			count = bar.showCount and { size = fontSize, point = "LEFT" } or nil,
			timeCurve = BarCurve(bar, { 1, 1, 1 }),
			timeFormatter = TimeFormatter(bar.decimals),
		}, Place, Dress)
		slots[1] = { key = key .. "D", filter = filter, candidateFilters = candidateFilters, initialize = initialize }
	end
	entry.container = W.CreateSlots(root, { unit = bar.unit or "player", slots = slots,
		poolKey = ("trackingbar:%d:%s"):format(index, tostring(entry.sig)) })
end

---------------------------------------------------------------------------
-- Cooldown and charge bars: our own bar, run by the client.
---------------------------------------------------------------------------
local function TimerOptions(elapsed)
	local interpolation = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
	local timer = Enum.StatusBarTimerDirection
	return interpolation, timer and (elapsed and timer.ElapsedTime or timer.RemainingTime)
end

local ItemDuration, ItemFlags = CD.ItemDuration, CD.ItemFlags

local UpdateEntry -- forward

local function CountdownOn(entry, frame, bar)
	-- A hidden-swipe Cooldown writes the time text and says when it is done.
	local cooldown = frame.countdown
	if not cooldown then
		cooldown = CreateFrame("Cooldown", nil, frame.overlay, "CooldownFrameTemplate")
		cooldown:SetAllPoints(frame.bar)
		cooldown:SetDrawSwipe(false)
		cooldown:SetDrawEdge(false)
		if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
		cooldown:SetScript("OnCooldownDone", function() C_Timer.After(0, function() UpdateEntry(entry) end) end)
		frame.countdown = cooldown
	end
	cooldown:Show()
	cooldown:SetHideCountdownNumbers(not (bar.showTime and not bar.vertical))
	local formatter = TimeFormatter(bar.decimals)
	if formatter and cooldown.SetCountdownFormatter then pcall(cooldown.SetCountdownFormatter, cooldown, formatter) end
	if cooldown.GetCountdownFontString then
		local text = cooldown:GetCountdownFontString()
		if text then
			E:SetFont(text, M.db.fontSize or E.tokens.size.small, "OUTLINE")
			text:ClearAllPoints()
			text:SetPoint("RIGHT", frame.bar, "RIGHT", -3, 0)
		end
	end
	return cooldown
end

local function CooldownBar(entry, bar, name, iconFile)
	local frame = OwnBar(entry, bar, name, iconFile)
	entry.own = frame
	entry.cooldown = CountdownOn(entry, frame, bar)
	if not frame.ready then
		frame.ready = frame.overlay:CreateFontString(nil, "OVERLAY")
		frame.ready:SetPoint("RIGHT", frame.bar, "RIGHT", -3, 0)
	end
	E:SetFont(frame.ready, M.db.fontSize or E.tokens.size.small, "OUTLINE")
	frame.ready:SetText(bar.readyText or "")
	frame.ready:Hide()
end

local function ChargeBar(entry, bar, name, iconFile)
	local frame = OwnBar(entry, bar, name, iconFile)
	entry.own = frame
	local max = entry.maxCharges or 1
	frame.bar:SetMinMaxValues(0, max)
	-- Segment gaps (static: the number of charges is plain out of combat).
	local _, _, inset = Geometry(bar)
	local length = Size(bar)
	local along = length - (bar.vertical and (inset.top + inset.bottom) or (inset.left + inset.right))
	local c = E.media.borderColor
	for n = 1, math.max(max - 1, #frame.segments) do
		local line = frame.segments[n]
		if n <= max - 1 then
			if not line then
				line = frame.overlay:CreateTexture(nil, "OVERLAY")
				frame.segments[n] = line
			end
			line:SetColorTexture(c[1] or 0, c[2] or 0, c[3] or 0, 1)
			line:ClearAllPoints()
			local at = n / max * along
			if bar.vertical then
				line:SetHeight(math.max(E.pixel or 1, 1))
				line:SetPoint("LEFT", frame.bar, bar.reverse and "TOPLEFT" or "BOTTOMLEFT", 0, bar.reverse and -at or at)
				line:SetPoint("RIGHT", frame.bar, bar.reverse and "TOPRIGHT" or "BOTTOMRIGHT", 0, bar.reverse and -at or at)
			else
				line:SetWidth(math.max(E.pixel or 1, 1))
				line:SetPoint("TOP", frame.bar, bar.reverse and "TOPRIGHT" or "TOPLEFT", bar.reverse and -at or at, 0)
				line:SetPoint("BOTTOM", frame.bar, bar.reverse and "BOTTOMRIGHT" or "BOTTOMLEFT", bar.reverse and -at or at, 0)
			end
			line:Show()
		elseif line then
			line:Hide()
		end
	end
	-- The recharge strip: a thin bar along the bottom edge, run by the
	-- client from the charge duration.
	if not frame.recharge then
		frame.recharge = CreateFrame("StatusBar", nil, frame.overlay)
		frame.recharge:SetPoint("BOTTOMLEFT", frame.bar, "BOTTOMLEFT")
		frame.recharge:SetPoint("BOTTOMRIGHT", frame.bar, "BOTTOMRIGHT")
		frame.recharge:SetAlpha(0.6)
	end
	frame.recharge:SetHeight(math.max(2, math.floor((tonumber(bar.height) or 18) / 6)))
	W.StyleBar(frame.recharge, { texture = Texture(bar), color = { 1, 1, 1 }, reverse = bar.reverse })
	frame.recharge:SetMinMaxValues(0, 1)
	frame.recharge:SetValue(0)
	frame.recharge:Hide()
	if not frame.count then
		frame.count = frame.overlay:CreateFontString(nil, "OVERLAY")
		frame.count:SetJustifyH("RIGHT")
		frame.max = frame.overlay:CreateFontString(nil, "OVERLAY")
		frame.max:SetPoint("RIGHT", frame.bar, "RIGHT", -3, 0)
		frame.count:SetPoint("RIGHT", frame.max, "LEFT", 0, 0)
	end
	E:SetFont(frame.count, M.db.fontSize or E.tokens.size.small, "OUTLINE")
	E:SetFont(frame.max, M.db.fontSize or E.tokens.size.small, "OUTLINE")
	frame.max:SetText("/" .. max)
	frame.count:SetShown(bar.showCount and true or false)
	frame.max:SetShown(bar.showCount and true or false)
	-- The charge widget's done callback: a charge came back.
	if not frame.chargeDone then
		local done = CreateFrame("Cooldown", nil, frame.overlay)
		done:SetAllPoints(frame.bar)
		done:SetAlpha(0)
		if done.SetDrawSwipe then done:SetDrawSwipe(false) end
		if done.SetHideCountdownNumbers then done:SetHideCountdownNumbers(true) end
		done:SetScript("OnCooldownDone", function() C_Timer.After(0, function() UpdateEntry(entry) end) end)
		frame.chargeDone = done
	end
	frame.chargeDone:Show()
	entry.cooldown = frame.chargeDone
end

-- Inactive look: show, fade or hide (aura bars: only the missing copy).
local function Inactive(entry, bar, inactive)
	local alpha = math.max(0, math.min(100, tonumber(bar.inactiveAlpha) or 30)) / 100
	if bar.kind == "aura" then
		if entry.own then
			entry.own:SetShown(bar.inactive ~= "hide")
			entry.own:SetAlpha(bar.inactive == "fade" and alpha or 1)
		end
		return
	end
	local frame = entry.own
	if not frame then return end
	if not inactive then
		frame:SetAlpha(1)
		frame:Show()
	elseif bar.inactive == "hide" then
		frame:Hide()
	else
		frame:Show()
		frame:SetAlpha(bar.inactive == "fade" and alpha or 1)
	end
end

local function ColorTick()
	local any = false
	for _, entry in pairs(built) do
		if entry.duration and entry.curve and entry.active and entry.own then
			any = true
			local method = entry.percent and "EvaluateRemainingPercent" or "EvaluateRemainingDuration"
			local fn = entry.duration[method]
			if type(fn) == "function" then
				local ok, color = pcall(fn, entry.duration, entry.curve)
				if ok and type(color) == "table" and color.GetRGB then
					pcall(entry.own.bar.SetStatusBarColor, entry.own.bar, color:GetRGB())
				end
			end
		end
	end
	if not any then E.Ticker:Unsubscribe(COLOR_TICK) end
end

local function WatchColors()
	if E.Ticker:IsSubscribed(COLOR_TICK) then return end
	E.Ticker:Subscribe(COLOR_TICK, COLOR_RATE, ColorTick, "TrackingBars")
end

UpdateEntry = function(entry)
	local bar = entry.bar
	if not (bar and entry.own) then return end
	if bar.kind == "aura" then
		Inactive(entry, bar, true)
		return
	end
	local frame = entry.own
	if bar.kind == "cooldown" then
		local active, gcd
		if entry.sourceKind == "item" then active, gcd = ItemFlags(entry.id) else active, gcd = K.SpellFlags(entry.id) end
		if active == nil then return end -- the game didn't say: keep the look
		local running = active and not gcd
		if running then
			local duration
			if entry.sourceKind == "item" then
				duration = ItemDuration(entry.id)
			else
				duration = CD.SpellDuration(entry.id)
			end
			if duration then
				local interpolation, direction = TimerOptions(bar.reverse)
				pcall(frame.bar.SetTimerDuration, frame.bar, duration, interpolation, direction)
				if entry.cooldown.SetCooldownFromDurationObject then
					pcall(entry.cooldown.SetCooldownFromDurationObject, entry.cooldown, duration)
				end
			end
			entry.duration = duration
			entry.active = true
			frame.ready:Hide()
			if entry.curve and duration then WatchColors() end
		else
			entry.active = false
			entry.duration = nil
			frame.bar:SetMinMaxValues(0, 1)
			frame.bar:SetValue(0)
			local c = bar.color or { 1, 1, 1 }
			frame.bar:SetStatusBarColor(c[1] or 1, c[2] or 1, c[3] or 1, 1)
			if entry.cooldown then entry.cooldown:Clear() end
			frame.ready:SetText(bar.readyText or "")
			frame.ready:SetShown((bar.readyText or "") ~= "")
		end
		Inactive(entry, bar, not running)
		return
	end
	-- Charges.
	local info = CD.SpellCharges(entry.id)
	if type(info) ~= "table" then return end
	-- The count may be secret in combat: straight into the bar and the text.
	pcall(frame.bar.SetValue, frame.bar, info.currentCharges)
	frame.count:SetText(info.currentCharges)
	local charging = info.isActive
	if not K.Plain(charging) or type(charging) == "nil" then return end
	if charging then
		local duration = CD.SpellDuration(entry.id, true)
		if duration then
			local interpolation, direction = TimerOptions(true)
			pcall(frame.recharge.SetTimerDuration, frame.recharge, duration, interpolation, direction)
			if entry.cooldown.SetCooldownFromDurationObject then
				pcall(entry.cooldown.SetCooldownFromDurationObject, entry.cooldown, duration)
			end
		end
		frame.recharge:Show()
	else
		frame.recharge:Hide()
		entry.cooldown:Clear()
	end
	entry.active = charging and true or false
	Inactive(entry, bar, not charging)
end

---------------------------------------------------------------------------
-- Build one bar (out of combat)
---------------------------------------------------------------------------
local function Signature(bar, length, thickness)
	local parts = { bar.kind, tostring(bar.spell), bar.unit, bar.auraKind, tostring(bar.mine), bar.mode, bar.stackMode,
		tostring(bar.maxStacks), length, thickness, Texture(bar), bar.icon, tostring(bar.showName), tostring(bar.showTime),
		tostring(bar.showCount), tostring(bar.decimals), tostring(bar.reverse), tostring(bar.vertical), tostring(bar.colorByTime),
		bar.timeUnit, tostring(bar.lowTime), tostring(bar.useMaxColor), bar.ticks, M.db.fontSize, E.pixel or 1 }
	for _, color in ipairs({ bar.color, bar.color2, bar.maxColor, bar.lowColor }) do
		parts[#parts + 1] = table.concat({ color[1] or 1, color[2] or 1, color[3] or 1 }, ",")
	end
	for _, range in ipairs(bar.ranges) do
		parts[#parts + 1] = ("%s:%s:%s"):format(tostring(range.enabled), tostring(range.from), table.concat(range.color or {}, ","))
	end
	for index, value in ipairs(parts) do parts[index] = tostring(value) end
	return table.concat(parts, "|")
end

local function Entry(index)
	local entry = built[index]
	if entry then return entry end
	entry = { index = index }
	entry.fader = CreateFrame("Frame", nil, UIParent)
	entry.fader:SetAllPoints(UIParent)
	entry.fader:SetFrameStrata("MEDIUM")
	entry.root = CreateFrame("Frame", nil, entry.fader)
	entry.root:SetSize(220, 18)
	built[index] = entry
	return entry
end

local function OwnHolder(index)
	local name = "EldoUI_TrackingBar" .. index
	local holder = K.GetHolder(name)
	if not holder then
		-- Free bars start under the main cooldown row, one per line.
		-- "Match size": the bar's length or thickness, whichever
		-- lies along that side; a length that follows a row is left alone.
		local function Side(along)
			return function()
				local bar = BarDB(index)
				if not bar then return end
				if (bar.vertical and true or false) ~= along then
					return { key = ("bars.%d.height"):format(index), min = 6, max = 40 }
				end
				if bar.matchRow == nil or bar.matchRow == "none" then
					return { key = ("bars.%d.width"):format(index), min = 60, max = 600 }
				end
			end
		end
		holder = K.Holder(M, name, L["Tracking Bar %d"]:format(index),
			{ "TOP", "EldoUI_CooldownsMover", "BOTTOM", 0, -120 - (index - 1) * 26 }, 220, 18,
			{ sizeKeys = { width = Side(false), height = Side(true) } })
	end
	return holder
end

local function BuildBar(index)
	local bar = BarDB(index)
	local entry = built[index]
	local kind, id = M.Source(bar)
	local on = M.active and bar and bar.enabled and kind ~= nil
	if bar and bar.kind ~= "cooldown" and kind == "item" then on = false end -- items have no aura or charges
	if not on then
		if entry then
			Release(entry)
			entry.bar = nil
			entry.root:Hide()
			E:DetachVisibility(entry.fader)
			if entry.glowing then E:HideGlow(entry.root) entry.glowing = nil end
		end
		local holder = K.GetHolder("EldoUI_TrackingBar" .. index)
		if holder then holder:Hide() end
		return
	end
	entry = Entry(index)
	entry.bar = bar
	entry.sourceKind, entry.id = kind, id
	if bar.kind == "charges" and not InCombatLockdown() then
		local _, _, _, maxCharges = K.SpellFlags(id)
		entry.maxCharges = maxCharges and maxCharges > 1 and maxCharges or (entry.maxCharges or 2)
	end
	local width, height = Geometry(bar)
	local length, thickness = Size(bar)
	local sig = Signature(bar, length, thickness) .. ":" .. tostring(entry.maxCharges)
	entry.root:SetSize(width, height)
	if entry.sig ~= sig then
		Release(entry)
		entry.sig = sig
		local name, iconFile = Describe(kind, id)
		entry.name = name
		if bar.kind == "aura" then
			AuraBar(entry, bar, index, id, name, iconFile)
		elseif bar.kind == "cooldown" then
			CooldownBar(entry, bar, name, iconFile)
		else
			ChargeBar(entry, bar, name, iconFile)
		end
		local normal = bar.color or { 1, 1, 1 }
		entry.curve = bar.kind == "cooldown" and BarCurve(bar, normal) or nil
		entry.percent = bar.timeUnit == "percent"
	end
	-- Unit: a target or focus bar shows only while the unit exists.
	local exists = bar.kind ~= "aura" or bar.unit == "player" or UnitExists(bar.unit)
	entry.root:SetShown(exists and true or false)
	E:AttachVisibility(entry.fader, bar.visibility, { watch = entry.root })
	local holder = K.GetHolder("EldoUI_TrackingBar" .. index)
	if bar.own then
		holder = OwnHolder(index)
		holder:SetSize(width, height)
		holder:Show()
		entry.root:ClearAllPoints()
		entry.root:SetPoint("CENTER", holder, "CENTER")
	elseif holder then
		holder:Hide()
	end
	UpdateEntry(entry)
end

---------------------------------------------------------------------------
-- The block: every bar that is not on its own mover, in list order.
---------------------------------------------------------------------------
local function BlockBars()
	local list = {}
	for index = 1, math.min(#Bars(), MAX_BARS) do
		local entry, bar = built[index], BarDB(index)
		if entry and entry.bar and bar and not bar.own then list[#list + 1] = entry end
	end
	return list
end

local function UtilityRoom(anchor)
	-- The utility row hangs right under the main row in most layouts:
	-- the block keeps clear of it while it shows anything.
	local holder = K.GetHolder("EldoUI_CooldownsUtility")
	if not (holder and holder:IsShown() and anchor and anchor.GetBottom) then return 0 end
	local filled = false
	local CM = E:GetModule("CooldownManager")
	local icons = CM and CM.rowIcons and CM.rowIcons.utility
	for _, button in ipairs(icons or {}) do
		if button:IsShown() and (button.spellID or button.itemID) then filled = true break end
	end
	local viewer = UtilityCooldownViewer
	if not filled and viewer and viewer.itemFramePool then
		local ok, count = pcall(viewer.itemFramePool.GetNumActive, viewer.itemFramePool)
		filled = ok and K.Plain(count) and count > 0 or false
	end
	if not filled then return 0 end
	local rowBottom, top, bottom = anchor:GetBottom(), holder:GetTop(), holder:GetBottom()
	if not (K.Plain(rowBottom, top, bottom) and rowBottom and top and bottom) then return 0 end
	-- Only a row sitting directly under the main row (within 24 px).
	if top > rowBottom + 1 or top < rowBottom - 24 then return 0 end
	return math.max(0, math.floor(rowBottom - bottom + 0.5))
end

local function Gap()
	local base = 4
	if M.db.placement ~= "stack" then return base end
	local stack = K.CooldownStack
	local room = UtilityRoom(stack.Anchor())
	if room <= 0 then return base end
	-- Room already taken by the members closer to the row counts.
	local offset = stack.Offset("tracking")
	return base + math.max(0, room - offset)
end

-- The block is EldoUI's own frame: admit it to the shared geometry reader,
-- so the cooldown stack can measure it (the pieces under it keep clear of
-- it and bars set to match the row follow the row's width).
local blockAdmitted
local function AdmitBlockGeometry()
	if blockAdmitted or not block then return end
	local source = rawget(E, "MoverAuthoritySource")
	if type(source) ~= "function" then return end
	local ok, _, _, _, _, _, _, admit = pcall(source)
	if not ok or type(admit) ~= "function" then return end
	local admitted, read = pcall(admit, block, true)
	blockAdmitted = admitted and read ~= nil
end

local function LayoutBlock()
	if not block then
		block = CreateFrame("Frame", nil, UIParent)
		block:SetSize(220, 18)
	end
	AdmitBlockGeometry()
	if not blockHolder then
		-- The mover shows only while the block uses it: bars that hang
		-- under the cooldown rows leave it out of move mode.
		blockHolder = K.Holder(M, BLOCK_MOVER, L["Tracking Bars"], { "CENTER", "UIParent", "CENTER", 0, -317 }, 220, 18,
			{ followShown = true })
	end
	local list = BlockBars()
	local spacing = math.max(0, tonumber(M.db.spacing) or 2)
	local width, height = 0, 0
	for _, entry in ipairs(list) do
		local w, h = entry.root:GetSize()
		width = math.max(width, w)
		height = height + h + (height > 0 and spacing or 0)
	end
	local y = 0
	for _, entry in ipairs(list) do
		entry.root:ClearAllPoints()
		entry.root:SetPoint("TOP", block, "TOP", 0, -y)
		y = y + entry.root:GetHeight() + spacing
	end
	block:SetSize(math.max(width, 20), math.max(height, 4))
	local any = M.active and #list > 0
	block:SetShown(any and true or false)
	block:ClearAllPoints()
	local onStack = M.db.placement == "stack"
	if onStack then
		local stack = K.CooldownStack
		local anchor = stack.Anchor()
		if anchor then
			block:SetPoint("TOP", anchor, "BOTTOM", 0, -(stack.Offset("tracking") + Gap()))
		else
			block:SetPoint("CENTER", blockHolder, "CENTER")
		end
	else
		block:SetPoint("CENTER", blockHolder, "CENTER")
	end
	blockHolder:SetSize(math.max(width, 20), math.max(height, 4))
	blockHolder:SetShown(any and not onStack or false)
end

function M:Layout()
	if InCombatLockdown() then
		pendingRebuild = true
		return
	end
	pendingRebuild = false
	for index = 1, MAX_BARS do
		if Bars()[index] or built[index] then BuildBar(index) end
	end
	LayoutBlock()
	K.CooldownStack.Changed()
end

-- The cooldown row's width or the stack changed.
function M:Relayout()
	if not self.active then return end
	self:Layout()
end

function M:UpdateAll()
	for _, entry in pairs(built) do
		if entry.bar then UpdateEntry(entry) end
	end
end

-- Read-only view of the bars.
M.built = built
function M.Block() return block end

---------------------------------------------------------------------------
-- Glow: only when the game lights the spell up.
---------------------------------------------------------------------------
local function GlowEvent(_, event, spellID)
	if not spellID or not K.Plain(spellID) then return end
	for _, entry in pairs(built) do
		if entry.bar and entry.id == spellID and entry.sourceKind == "spell" then
			if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
				entry.glowing = true
				E:ShowUserGlow(entry.root, "trackingBars")
			elseif entry.glowing then
				entry.glowing = nil
				E:HideGlow(entry.root)
			end
		end
	end
end

local function UnitChanged(unit)
	for _, entry in pairs(built) do
		local bar = entry.bar
		if bar and bar.kind == "aura" and bar.unit == unit then
			if entry.container then W.Refresh(entry.container) end
			entry.root:SetShown(UnitExists(unit) and true or false)
		end
	end
end

---------------------------------------------------------------------------
-- Adding and removing bars
---------------------------------------------------------------------------
function M:AddBar()
	local bars = self.db.bars
	if #bars >= MAX_BARS then
		self:Print(L["You have the most bars there can be (30)."])
		return nil
	end
	bars[#bars + 1] = NewBar()
	self.db.edit = #bars
	-- Adding a bar turns the module on.
	if not self.active then E:SetModuleEnabled("TrackingBars", true) end
	self:Layout()
	if E.RefreshConfig then E:RefreshConfig() end
	return #bars
end

function M:RemoveBar(index)
	index = tonumber(index or self.db.edit)
	local bars = self.db.bars
	if not (index and bars[index]) then return end
	E:RunOutOfCombat(function()
		for i = 1, MAX_BARS do
			if built[i] then
				Release(built[i])
				built[i].bar = nil
				built[i].root:Hide()
			end
		end
		table.remove(bars, index)
		self.db.edit = math.max(1, math.min(index, #bars))
		self:Layout()
		if E.RefreshConfig then E:RefreshConfig() end
	end)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
-- The block's mover exists from the start, so move mode and the layouts
-- know it; it shows only while the block is on its own mover.
function M:OnInitialize()
	LayoutBlock()
end

function M:OnEnable()
	-- Cooldowns and charges come from the combat kit's cooldown source.
	CD.Subscribe(GROUP, function() M:UpdateAll() end)
	E:RegisterEvent("SPELLS_CHANGED", function() E:RunOutOfCombat(function() M:Layout() end, "trackingBars:layout") end, GROUP)
	E:RegisterEvent("PLAYER_REGEN_ENABLED", function() if pendingRebuild then M:Layout() end end, GROUP)
	E:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", GlowEvent, GROUP)
	E:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", GlowEvent, GROUP)
	for unit, event in pairs(UNIT_EVENTS) do E:RegisterEvent(event, function() UnitChanged(unit) end, GROUP) end
	E:RegisterEvent("UNIT_PET", function(_, _, owner) if owner == "player" then UnitChanged("pet") end end, GROUP)
	E:RunOutOfCombat(function() M:Layout() end)
end

function M:OnDisable()
	CD.Unsubscribe(GROUP)
	E.Ticker:Unsubscribe(COLOR_TICK)
	for _, event in ipairs({ "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
		"PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_PET" }) do
		E:UnregisterEvent(event, GROUP)
	end
	E:RunOutOfCombat(function() M:Layout() end)
end

function M:OnProfileChanged()
	E:RunOutOfCombat(function() M:Layout() end)
end

-- On the cooldown stack: under the item row, above a cast bar there.
K.CooldownStack.Register("tracking", {
	frame = function()
		if not (M.active and M.db and M.db.placement == "stack" and block and block:IsShown()) then return nil end
		return block
	end,
	gap = function() return M.db and Gap() or 4 end,
	relayout = function() if M.active then M:Relayout() end end,
})

---------------------------------------------------------------------------
-- Styles: the look of the bars (the bars themselves stay).
---------------------------------------------------------------------------
E:RegisterStyles("TrackingBars", {
	{ key = "Under", title = "Under the cooldowns", desc = "One block hanging under the main cooldown row, 2 px apart.",
		settings = { placement = "stack", spacing = 2, fontSize = 11 } },
	{ key = "Free", title = "Own mover", desc = "The block sits on its own mover (Tracking bars) wherever you drag it.",
		settings = { placement = "mover", spacing = 2, fontSize = 11 } },
	{ key = "Tight", title = "Tight", desc = "Bars touch each other, small text.",
		settings = { spacing = 0, fontSize = 10 } },
	{ key = "Airy", title = "Airy", desc = "4 px between bars, larger text.",
		settings = { spacing = 4, fontSize = 13 } },
	{ key = "Large", title = "Large text", desc = "3 px between bars and the largest text, easy to read at a glance.",
		settings = { spacing = 3, fontSize = 15 } },
})

---------------------------------------------------------------------------
-- Options: one bar at a time (Bar), the rows below edit that bar.
---------------------------------------------------------------------------
local function Editing()
	local index = M.db and tonumber(M.db.edit) or 1
	local count = #Bars()
	if count == 0 then return nil end
	return math.max(1, math.min(count, index))
end
local function B(field) return function() return ("bars.%d.%s"):format(Editing() or 1, field) end end
local function Edit() return BarDB(Editing() or 1) or TEMPLATE end
local function NoBar() return Editing() == nil end
local function NotAura() return NoBar() or Edit().kind ~= "aura" end
local function NotStacks() return NotAura() or Edit().mode ~= "stacks" end
local function NotRanges() return NotStacks() or Edit().stackMode == "folded" end
local function NotFolded() return NotStacks() or Edit().stackMode ~= "folded" end
local function NotCooldown() return NoBar() or Edit().kind ~= "cooldown" end
local function NoTimeColor() return NoBar() or Edit().kind == "charges" or (Edit().kind == "aura" and Edit().mode == "stacks") end
local function NoLowRows() return NoTimeColor() or not Edit().colorByTime end
local function Range(i, field) return function() return ("bars.%d.ranges.%d.%s"):format(Editing() or 1, i, field) end end
local function RangeOff(i) return function() return NotRanges() or not Edit().ranges[i].enabled end end

local KIND_LABEL = { aura = "aura", cooldown = "cooldown", charges = "charges" }
local function BarValues()
	local values = {}
	for index = 1, #Bars() do
		local bar = BarDB(index)
		local kind, id = M.Source(bar)
		local name = kind and Describe(kind, id) or L["(no spell yet)"]
		values[index] = ("%d. %s (%s)"):format(index, name, KIND_LABEL[bar.kind] or bar.kind)
	end
	if not next(values) then values[1] = L["(no bars yet)"] end
	return values
end
local function Textures() local values = K.TextureValues(); values[""] = L["Module texture"]; return values end
local function ModuleTextures() local values = K.TextureValues(); values[""] = L["Theme texture"]; return values end

M.options = {
	{ type = "tab", label = L["Bars"] },
	{ type = "description", label = L["Each bar follows one spell: an aura's time or stacks, a cooldown or charges. Aura bars work for your buffs and your debuffs on enemies."] },
	{ type = "description", label = L["This game client has no aura slots, so aura bars can't show here (cooldown and charge bars still work)."],
		hidden = function() return W.SlotsAvailable() end },
	{ type = "execute", label = L["Add bar"], func = function() M:AddBar() end,
		desc = L["Creates a new bar and turns Tracking Bars on. Then type a spell name or ID below."] },
	{ type = "execute", label = L["Remove bar"], confirm = L["Delete this bar and its spell list? This can't be undone."], func = function() M:RemoveBar() end, hidden = NoBar,
		desc = L["Deletes the bar chosen below."] },
	{ type = "select", key = "edit", label = L["Bar"], values = BarValues, hidden = NoBar,
		desc = L["The bar the rows below change."] },
	E:CopySettingsOptions({ path = function() return "bars." .. (Editing() or 1) end,
		values = function()
			local values = {}
			for index = 1, #Bars() do values["bars." .. index] = BarValues()[index] end
			return values
		end,
		keep = { "enabled", "kind", "spell", "unit", "auraKind", "mine", "mode" },
		hidden = function() return #Bars() < 2 end,
		desc = L["Copy the look of another bar onto this one (size, colors, texture, icon, text, stacks), with a preview of what changes first. What it tracks and its switch stay as they are."] })[1],
	{ type = "header", label = L["What it shows"], hidden = NoBar },
	{ type = "toggle", key = B("enabled"), label = L["Show this bar"], hidden = NoBar,
		desc = L["Turns this bar on or off without deleting it."] },
	{ type = "select", key = B("kind"), label = L["Type"], hidden = NoBar,
		values = { aura = L["Aura"], cooldown = L["Cooldown"], charges = L["Charges"] },
		desc = L["Aura: a buff or debuff's time left or stacks. Cooldown: drains while the spell or item is on cooldown. Charges: one segment per charge."] },
	{ type = "input", key = B("spell"), label = L["Spell"], hidden = NoBar,
		desc = L["A spell name or ID (shift-click a spell link works too). Cooldown bars also take an item as item:ID."] },
	{ type = "select", key = B("unit"), label = L["Unit"], hidden = NotAura,
		values = { player = L["You"], target = L["Target"], focus = L["Focus"], pet = L["Pet"] },
		desc = L["Whose auras to watch: you, your target, focus or pet."] },
	{ type = "select", key = B("auraKind"), label = L["Aura"], hidden = NotAura,
		values = { HELPFUL = L["Buff"], HARMFUL = L["Debuff"] },
		desc = L["Whether the spell is looked for as a buff or a debuff."] },
	{ type = "toggle", key = B("mine"), label = L["Only mine"], hidden = NotAura,
		desc = L["Only auras you cast. Off: the same spell from anyone counts."] },
	{ type = "select", key = B("mode"), label = L["Show as"], hidden = NotAura,
		values = { duration = L["Time left"], stacks = L["Stacks"] },
		desc = L["Time left drains while the aura is up; stacks fills with the aura's stack count."] },
	{ type = "header", label = L["Stacks"], hidden = NotStacks },
	{ type = "select", key = B("stackMode"), label = L["Stack style"], hidden = NotStacks,
		values = { continuous = L["One bar"], segments = L["One segment per stack"], folded = L["Folded"] },
		desc = L["One bar, one segment per stack, or folded (the stacks above half color over the first half)."] },
	{ type = "range", key = B("maxStacks"), label = L["Stacks for a full bar"], min = 1, max = 30, step = 1, hidden = NotStacks,
		desc = L["How many stacks fill the bar. Set it to the aura's most stacks."] },
	{ type = "color", key = B("color2"), label = L["Second color"], hidden = NotFolded,
		desc = L["The color of the stacks above half in the folded style."] },
	{ type = "input", key = B("ticks"), label = L["Tick marks"], hidden = NotStacks,
		desc = L["Stack counts where a thin line is drawn, separated by commas (for example 3, 5)."] },
	{ type = "toggle", key = Range(1, "enabled"), label = L["Color range 1"], hidden = NotRanges,
		desc = L["A color for the whole bar from a stack count up. Later ranges win."] },
	{ type = "range", key = Range(1, "from"), label = L["From stack"], min = 1, max = 30, step = 1, hidden = RangeOff(1),
		desc = L["The stack count this color starts at."] },
	{ type = "color", key = Range(1, "color"), label = L["Color"], hidden = RangeOff(1),
		desc = L["The bar's color from this stack count up."] },
	{ type = "toggle", key = Range(2, "enabled"), label = L["Color range 2"], hidden = NotRanges,
		desc = L["A second color from a higher stack count up."] },
	{ type = "range", key = Range(2, "from"), label = L["From stack"], min = 1, max = 30, step = 1, hidden = RangeOff(2),
		desc = L["The stack count this color starts at."] },
	{ type = "color", key = Range(2, "color"), label = L["Color"], hidden = RangeOff(2),
		desc = L["The bar's color from this stack count up."] },
	{ type = "toggle", key = Range(3, "enabled"), label = L["Color range 3"], hidden = NotRanges,
		desc = L["A third color from a higher stack count up."] },
	{ type = "range", key = Range(3, "from"), label = L["From stack"], min = 1, max = 30, step = 1, hidden = RangeOff(3),
		desc = L["The stack count this color starts at."] },
	{ type = "color", key = Range(3, "color"), label = L["Color"], hidden = RangeOff(3),
		desc = L["The bar's color from this stack count up."] },
	{ type = "toggle", key = B("useMaxColor"), label = L["Color at most stacks"], hidden = NotRanges,
		desc = L["A color of its own once the bar is full."] },
	{ type = "color", key = B("maxColor"), label = L["Full color"], hidden = function() return NotRanges() or not Edit().useMaxColor end,
		desc = L["The bar's color at the most stacks."] },
	{ type = "header", label = L["Look"], hidden = NoBar },
	{ type = "select", key = B("matchRow"), label = L["Match cooldown row width"], hidden = NoBar,
		values = { none = L["No, own width"], essential = L["Essential row"], utility = L["Utility row"] },
		desc = L["Take the width of a cooldown row and follow it when it changes."] },
	{ type = "range", unit = "px", key = B("width"), label = L["Width"], min = 60, max = 600, step = 2,
		hidden = function() return NoBar() or Edit().matchRow ~= "none" end,
		desc = L["The bar's length."] },
	{ type = "range", unit = "px", key = B("height"), label = L["Height"], min = 6, max = 40, step = 1, hidden = NoBar,
		desc = L["The bar's thickness."] },
	{ type = "color", key = B("color"), label = L["Color"], hidden = NoBar,
		desc = L["The bar's fill color."] },
	{ type = "select", key = B("texture"), label = L["Texture"], values = Textures, hidden = NoBar,
		desc = L["The bar's texture. Module texture uses the one on the Layout tab."] },
	{ type = "select", key = B("icon"), label = L["Icon"], hidden = NoBar,
		values = { LEFT = L["At the start"], RIGHT = L["At the end"], NONE = L["None"] },
		desc = L["Where the spell's icon sits."] },
	{ type = "toggle", key = B("showName"), label = L["Name"], hidden = NoBar,
		desc = L["The spell's name on the bar (not on vertical bars)."] },
	{ type = "toggle", key = B("showTime"), label = L["Time"], hidden = function() return NoBar() or Edit().kind == "charges" or (Edit().kind == "aura" and Edit().mode == "stacks") end,
		desc = L["The time left on the bar (not on vertical bars)."] },
	{ type = "toggle", key = B("showCount"), label = L["Count"], hidden = function() return NoBar() or Edit().kind == "cooldown" end,
		desc = L["The stack count, or charges as charges/most."] },
	{ type = "select", key = B("decimals"), label = L["Decimals"], cog = true, values = { [0] = L["12"], [1] = L["4.5 under 10 s"] },
		hidden = function() return NoBar() or Edit().kind == "charges" end,
		desc = L["Show tenths of a second under ten seconds, or whole seconds only."] },
	{ type = "toggle", key = B("reverse"), label = L["Reverse fill"], cog = true, hidden = NoBar,
		desc = L["Fill from the other end."] },
	{ type = "toggle", key = B("vertical"), label = L["Vertical"], cog = true, hidden = NoBar,
		desc = L["A standing bar that fills upwards; width is its length and height its thickness."] },
	{ type = "header", label = L["Color by time left"], hidden = NoTimeColor },
	{ type = "toggle", key = B("colorByTime"), label = L["Enable"], hidden = NoTimeColor,
		desc = L["Change color as the time runs out: aura bars color their time text, cooldown bars their fill. The game does the math."] },
	{ type = "select", key = B("timeUnit"), label = L["Measured in"], hidden = NoLowRows,
		values = { seconds = L["Seconds left"], percent = L["Percent left"] },
		desc = L["Whether the limit below is in seconds or in percent of the whole time."] },
	{ type = "range", key = B("lowTime"), label = L["Below"], min = 1, max = 60, step = 1, hidden = NoLowRows,
		desc = L["From this much time left on, the color below is used."] },
	{ type = "color", key = B("lowColor"), label = L["Color near the end"], hidden = NoLowRows,
		desc = L["The color when little time is left."] },
	{ type = "header", label = L["When inactive"], hidden = NoBar },
	{ type = "select", key = B("inactive"), label = L["Show"], hidden = NoBar,
		values = { show = L["Show"], fade = L["Fade"], hide = L["Hide"] },
		desc = L["Show, fade or hide the bar while the aura is missing, the spell is ready or every charge is back."] },
	{ type = "range", key = B("inactiveAlpha"), label = L["Faded opacity"], unit = "%", min = 5, max = 90, step = 5,
		hidden = function() return NoBar() or Edit().inactive ~= "fade" end,
		desc = L["How visible a faded bar is."] },
	{ type = "input", key = B("readyText"), label = L["Ready text"], hidden = NotCooldown,
		desc = L["A word shown on the bar while the spell is ready (for example Ready). Empty shows nothing."] },
	{ type = "header", label = L["Position"], hidden = NoBar },
	{ type = "toggle", key = B("own"), label = L["Own mover"], hidden = NoBar,
		desc = L["Take this bar out of the block onto its own mover (Tracking bar N in move mode)."] },
}

-- The chosen bar's visibility block: the shared rows, pointed at the bar.
for _, row in ipairs(E:VisibilityOptions("visibility", { db = function() return Edit() end, hidden = NoBar })) do
	local key = row.key
	if type(key) == "string" then row.key = function() return ("bars.%d.%s"):format(Editing() or 1, key) end end
	if row.type == "header" then row.label = L["Visibility"] end
	table.insert(M.options, row)
end

local layoutOptions = {
	{ type = "tab", label = L["Layout"] },
	{ type = "select", key = "placement", label = L["Block position"],
		values = { stack = L["Under the cooldown rows"], mover = L["Own mover (Tracking bars)"] },
		desc = L["Under the cooldown rows: the block hangs under the main row, after the item row and before a cast bar placed there, and moves with them. Own mover: drag it in move mode."] },
	{ type = "range", unit = "px", key = "spacing", label = L["Spacing"], min = 0, max = 12, step = 1,
		desc = L["Space between the bars of the block."] },
	{ type = "range", key = "fontSize", label = L["Text size"], min = 8, max = 18, step = 1,
		desc = L["Size of the name, time and count on every bar."] },
	{ type = "select", key = "texture", label = L["Texture"], values = ModuleTextures,
		desc = L["The texture of every bar that has no texture of its own."] },
}
for _, row in ipairs(layoutOptions) do table.insert(M.options, row) end
