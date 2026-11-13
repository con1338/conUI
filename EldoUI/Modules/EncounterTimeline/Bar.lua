-- Encounter Timeline: the timeline frame and its bar.
--
--   +---------+--+------------------------------------------------------+
--   |         |  | |  [ic]    :    [i]       :         :   [ic] [w][w]  |
--   |  [big]  |  | |          :      [i]     :         :        [w][+2] |
--   |         |  +------------------------------------------------------+
--   |         |       5 s           10 s      15 s
--   +---------+
--
-- One frame, one mover: the big icon of the next event (Soon.lua) sits at
-- the now end of the bar, centered on its middle line (left of a
-- horizontal bar, right of it with "Reverse travel"; below a vertical bar,
-- above it reversed). Further big icons line up away from the bar. The
-- frame's box covers the big icons, the bar and its tick numbers.
--
-- An icon sits at remaining / window * travel from the now-marker. Events
-- further out than the window wait in a small grid at the far end, with a
-- "+N" chip in the grid's next cell past waiting.max. Horizontal icons
-- travel left (right with "Reverse travel"), vertical ones down (up when
-- reversed). An event shown as a big icon leaves the bar, so every event
-- shows once.
--
-- Icons never overlap (design decision, written from scratch): timers
-- whose full-size icons would touch form a group. In a group every icon
-- takes an upper or a lower lane at a lane size that fits two lanes inside
-- the strip with a gap between them. A lane takes an icon only when the
-- one before it in that lane is a lane icon and a gap away. Each icon keeps
-- its lane while the group lasts, so nothing hops when the first timer
-- ends. When both lanes are taken, the icon moves along its lane, away from
-- now, until it clears the one before it, and shows its seconds so its time
-- stays readable; an icon pushed past the far end joins the waiting grid.
-- With "Two lanes" off the same rule runs in one lane at full size. Lane,
-- size and that shift ease in, so icons glide instead of jumping. The
-- waiting grid uses the same two lanes, one cell per icon. Everything is
-- clamped inside the strip. Stacking: the soonest icon is on top while two
-- glide past each other; the order follows the time left and only changes
-- when two timers really swap places.
--
-- Text never sits on the icon row: tick numbers go beside the strip (under
-- a horizontal bar, left of a vertical one).
--
-- Side names (vertical bar): every name sits in one column beside the
-- strip, level with its icon, whichever lane the icon takes, so a name
-- never runs over the other lane. Names are placed soonest first; a name
-- that would touch the one before it moves on by a line, and a name with
-- no room left before the bar's end is left out (its tooltip still has it).
-- When names are left out, the column's last line says how many ("+N").
--
-- The look comes from the design system: the strip is E:SetTemplate plus
-- E:SetStyleEdge, the panel E:SetPanelTemplate (follows the art style),
-- "none" leaves a 2 px track line in the border color. The now-marker is
-- the accent; ticks text.dim, tick numbers text.secondary, warning zones
-- text.warn / text.bad, numbers body -> warn -> bad.
local _, E = ...
local L = E.L
local M = E:GetModule("EncounterTimeline")

local WAIT_ALPHA = 0.6
local LANE_EASE = 0.15   -- seconds a lane, size or shift change takes
local NAME_WIDTH = 120   -- the side names of a vertical bar
local NAME_GAP = 6       -- px between the strip and the side names
local INSET = 2          -- px every icon keeps from the strip's edge
local GAP = 2            -- px between two icons, two lanes, two cells
local LEVEL_SPAN = 40    -- frame levels for the icons on the bar (above
                         -- the chip and the waiting grid's up to 6)
local LABEL_BAND = 12    -- room for the tick numbers under a horizontal bar
local LABEL_BAND_V = 16  -- and left of a vertical one
local BIG_GAP = 8        -- px between the bar and the first big icon
local SLOT_GAP = 4       -- px between two big icons
local BELOW_GAP = 20     -- px from the strip to big icons placed under it
M.BIG_GAP, M.SLOT_GAP, M.GAP = BIG_GAP, SLOT_GAP, GAP

-- Size and center offset of the two lanes: the largest icon that fits two
-- lanes in the strip with a gap between them, never larger than the icon
-- size.
function M:LaneMetrics(s)
	s = s or self.cache
	local size = math.max(8, math.min(s.iconSize, math.floor((s.thickness - 2 * INSET - GAP) / 2)))
	return size, size / 2 + GAP / 2
end

-- Columns of the waiting grid: two cells each, the chip's cell included.
local function WaitColumns(s)
	return math.ceil((s.waitMax + 1) / 2)
end

-- The geometry of the travel axis for the current settings: where the
-- now-marker sits, how long the travel is, and how much room the far end
-- keeps past it (half an icon, or the waiting grid).
function M:Geometry(s)
	s = s or self.cache or self:Settings()
	local half = s.iconSize / 2
	local nowPos = INSET + half
	local tail = half + INSET
	if s.waiting then
		local lane = self:LaneMetrics(s)
		local cols = WaitColumns(s)
		tail = half + GAP + cols * lane + (cols - 1) * GAP + INSET
	end
	local travel = math.max(20, s.length - nowPos - tail)
	return nowPos, travel, tail
end

-- Cell `index` of the waiting grid (waitMax + 1 is the chip's cell): along
-- the travel axis and across it. Cells fill the upper lane, then the
-- lower one, column by column, one cell per icon.
function M:WaitSlot(index, s)
	s = s or self.cache
	local nowPos, travel = self:Geometry(s)
	local lane, offset = self:LaneMetrics(s)
	local col = math.ceil(index / 2)
	local along = nowPos + travel + s.iconSize / 2 + GAP + (col - 1) * (lane + GAP) + lane / 2
	local across = (index % 2 == 1) and offset or -offset
	return along, across
end

-- Does the layout put the big icons under the bar? A layout with a tight
-- spot beside the bar (an older layout kept as it was) hangs its big icon
-- point under the bar's box; every other layout keeps them at the now end.
function M:BigBelow(s)
	if s.vertical or not E.GetLayoutPoint then return false end
	local point = E:GetLayoutPoint("EldoUI_EncounterTimelineBig")
	return type(point) == "table" and point[2] == "EldoUI_EncounterTimelineMover"
		and type(point[1]) == "string" and point[1]:sub(1, 3) == "TOP"
		and type(point[3]) == "string" and point[3]:sub(1, 6) == "BOTTOM"
end

-- The whole frame: its size, where the bar sits in it (bottom left) and
-- where the first big icon's center is, with the step to the next one.
-- Horizontal: the big icons at the now end, the bar centered on their
-- middle line, the tick numbers under the bar (or, where the layout says
-- so, the big icons under the bar's now end). Vertical: the big icons
-- below the now end (above it reversed), the strip centered over them,
-- the tick numbers left of it and the side names right of it.
function M:FrameLayout(s)
	s = s or self.cache or self:Settings()
	local out = self.frameLayout or {}
	self.frameLayout = out
	local labels = s.ticks and s.tickLabels
	local count = s.big and s.bigMax or 0
	local bigSize = count > 0 and s.bigSize or 0
	local bigLen = count > 0 and (count * s.bigSize + (count - 1) * SLOT_GAP + BIG_GAP) or 0
	local step = s.bigSize + SLOT_GAP
	if s.vertical then
		local band = labels and LABEL_BAND_V or 0
		local core = math.max(bigSize, s.thickness + 2 * band)
		local stripLeft = (core - s.thickness) / 2
		local barW = s.thickness + (s.names and NAME_WIDTH or 0)
		out.width = math.max(core, stripLeft + barW)
		out.height = bigLen + s.length
		out.barW, out.barH = barW, s.length
		out.barX = stripLeft
		out.slotX = core / 2
		if s.reverse then
			out.barY = 0
			out.slotY = s.length + BIG_GAP + s.bigSize / 2
			out.stepX, out.stepY = 0, step
		else
			out.barY = bigLen
			out.slotY = bigLen - BIG_GAP - s.bigSize / 2
			out.stepX, out.stepY = 0, -step
		end
	elseif count > 0 and self:BigBelow(s) then
		local slots = bigLen - BIG_GAP
		out.width = math.max(s.length, slots)
		out.height = s.thickness + BELOW_GAP + s.bigSize
		out.barW, out.barH = s.length, s.thickness
		out.barY = out.height - s.thickness
		out.slotY = s.bigSize / 2
		if s.reverse then
			out.barX = out.width - s.length
			out.slotX = out.width - s.bigSize / 2
			out.stepX, out.stepY = -step, 0
		else
			out.barX = 0
			out.slotX = s.bigSize / 2
			out.stepX, out.stepY = step, 0
		end
	else
		local band = labels and LABEL_BAND or 0
		out.width = bigLen + s.length
		out.height = math.max(bigSize, s.thickness + 2 * band)
		out.barW, out.barH = s.length, s.thickness
		out.barY = (out.height - s.thickness) / 2
		out.slotY = out.height / 2
		if s.reverse then
			out.barX = 0
			out.slotX = s.length + BIG_GAP + s.bigSize / 2
			out.stepX, out.stepY = step, 0
		else
			out.barX = bigLen
			out.slotX = bigLen - BIG_GAP - s.bigSize / 2
			out.stepX, out.stepY = -step, 0
		end
	end
	out.count = count
	return out
end

-- Ticks inside the window, never one on the window's far edge.
function M:TickCount(s)
	s = s or self.cache or self:Settings()
	if not s.ticks then return 0 end
	return math.floor((s.window - 0.001) / s.tickEvery)
end

-- Frame coordinates (from the bar's bottom left) of a point `along` the
-- travel axis from the now end, `across` px off the center line.
function M:AxisPoint(along, across, s)
	s = s or self.cache
	if s.vertical then
		local y = s.reverse and (s.length - along) or along
		return s.thickness / 2 + (across or 0), y
	end
	local x = s.reverse and (s.length - along) or along
	return x, s.thickness / 2 + (across or 0)
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local function Texture(parent, layer, sub)
	local tex = parent:CreateTexture(nil, layer, nil, sub)
	tex:SetTexture(E.media.flat)
	return tex
end

-- The bar inside the timeline frame (Core.lua makes the frame).
function M:CreateBar(parent)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetSize(320, 40)
	bar:EnableMouse(false)
	self.bar = bar

	local content = CreateFrame("Frame", nil, bar)
	content:SetAllPoints()
	content:EnableMouse(false)
	content:Hide()
	bar.content = content

	-- Backings: one frame per kind, so a panel's art style and a strip's
	-- edge never mix.
	bar.strip = CreateFrame("Frame", nil, content)
	bar.strip:SetAllPoints()
	bar.strip:SetFrameLevel(content:GetFrameLevel())
	bar.panel = CreateFrame("Frame", nil, content)
	bar.panel:SetAllPoints()
	bar.panel:SetFrameLevel(content:GetFrameLevel())

	bar.art = CreateFrame("Frame", nil, content)
	bar.art:SetAllPoints()
	bar.art:SetFrameLevel(content:GetFrameLevel() + 2)
	bar.track = Texture(bar.art, "BORDER")
	bar.zoneWarn = Texture(bar.art, "BORDER", 1)
	bar.zoneBad = Texture(bar.art, "BORDER", 2)
	bar.now = Texture(bar.art, "OVERLAY", 2)
	bar.ticks = {}

	bar.iconLayer = CreateFrame("Frame", nil, content)
	bar.iconLayer:SetAllPoints()
	bar.iconLayer:SetFrameLevel(content:GetFrameLevel() + 4)
	bar.iconLayer:EnableMouse(false)
	bar.icons = {}   -- row -> icon frame
	bar.pool = {}

	-- "+N" chip in the waiting grid's next cell. It sits under the icons,
	-- so an icon gliding past never has its number covered.
	local chip = CreateFrame("Frame", nil, content)
	chip:SetFrameLevel(bar.iconLayer:GetFrameLevel() + 1)
	chip:SetSize(22, 14)
	E:SetTemplate(chip)
	chip.text = E:CreateText(chip, E.tokens.size.small)
	chip.text:SetPoint("CENTER")
	chip:EnableMouse(false)
	chip:Hide()
	bar.chip = chip

	-- "+N" at the end of the side name column: names left out for room.
	bar.moreNames = E:CreateText(bar.iconLayer, E.tokens.size.label, "LEFT")
	bar.moreNames:SetWordWrap(false)
	bar.moreNames:Hide()
	return bar
end

-- A tick mark with its number and its highlight.
local function Tick(bar, index)
	local tick = bar.ticks[index]
	if tick then return tick end
	tick = {}
	tick.line = Texture(bar.art, "ARTWORK")
	tick.flash = Texture(bar.art, "OVERLAY", 1)
	tick.flash:Hide()
	tick.label = E:CreateText(bar.art, E.tokens.size.tiny)
	bar.ticks[index] = tick
	return tick
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------
local TYPE_NAMES = { "Adds", "AoE", "Targeted", "Interrupt", "Role", "Stage", "Personal" }
-- Shown translated: L["Adds"], L["AoE"], L["Targeted"], L["Interrupt"], L["Role"], L["Stage"], L["Personal"]
M.TYPE_NAMES = TYPE_NAMES

-- The tooltip of a bar icon or a big icon: the spell's own tooltip when
-- the timer has a plain spell id, else its text; then the DBM type and
-- where the timer came from.
function M:ShowTooltip(owner, row)
	local mode = (self.cache or self:Settings()).tooltip
	if mode == "off" or not row then return end
	GameTooltip:SetOwner(owner, mode == "cursor" and "ANCHOR_CURSOR" or "ANCHOR_TOP")
	local shown = false
	if type(row.spellId) == "number" and GameTooltip.SetSpellByID then
		shown = pcall(GameTooltip.SetSpellByID, GameTooltip, row.spellId)
	end
	if not shown then
		-- A secret text is fine here: SetText only displays it.
		GameTooltip:SetText(M.DisplayText(row.text, L["Timer"]), 1, 1, 1)
	end
	local secondary = E.tokens.text.secondary
	local colorType = M.Number(row.colorType)
	if colorType and TYPE_NAMES[colorType] then
		GameTooltip:AddLine(L["Type: %s"]:format(L[TYPE_NAMES[colorType]]), secondary[1], secondary[2], secondary[3])
	end
	local source = M.SOURCE_NAMES[row.source]
	if source then
		GameTooltip:AddLine(L["From: %s"]:format(L[source]), secondary[1], secondary[2], secondary[3])
	end
	if type(row.from) == "string" then
		GameTooltip:AddLine(L["Started by %s"]:format(row.from), secondary[1], secondary[2], secondary[3])
	end
	GameTooltip:Show()
end

local function IconEnter(icon) M:ShowTooltip(icon, icon.row) end

-- A text for SetText: a secret passes through untouched (only a widget
-- may read it), a plain string as it is, anything else the fallback.
function M.DisplayText(text, fallback)
	if M.IsSecret(text) then return text end
	if type(text) == "string" then return text end
	return fallback
end

function M:NewBarIcon()
	local bar = self.bar
	local icon = table.remove(bar.pool)
	if icon then return icon end
	icon = CreateFrame("Frame", nil, bar.iconLayer)
	E:SetTemplate(icon)
	icon.tex = icon:CreateTexture(nil, "ARTWORK")
	E:Hairline(icon.tex, "inset", 1)
	E:TrimIcon(icon.tex)
	icon.num = E:CreateText(icon, E.tokens.size.label)
	icon.num:SetPoint("CENTER", 0, 0)
	icon.name = E:CreateText(icon, E.tokens.size.label, "LEFT")
	icon.name:SetPoint("LEFT", icon, "RIGHT", NAME_GAP, 0)
	icon.name:SetWidth(NAME_WIDTH - NAME_GAP * 2)
	icon.name:SetWordWrap(false)
	icon:SetScript("OnEnter", IconEnter)
	icon:SetScript("OnLeave", GameTooltip_Hide)
	icon:EnableMouse(false)
	-- Right-click: Hide the timeline; Ctrl-click: its tooltip setting.
	E:RegisterHideable(icon, "EldoUI_EncounterTimeline")
	E:BindOptionsLink(icon, { page = "module:EncounterTimeline", key = "tooltip" })
	return icon
end

function M:ReleaseBarIcon(row)
	local bar = self.bar
	local icon = bar and bar.icons[row]
	if not icon then return end
	bar.icons[row] = nil
	icon.row = nil
	icon.drawnSize, icon.level, icon.nameAlong = nil, nil, nil
	icon:Hide()
	icon:SetScale(1)
	bar.pool[#bar.pool + 1] = icon
end

-- Size, font, mouse and border of one icon for the current settings.
function M:StyleIcon(icon, s)
	icon:SetSize(s.iconSize, s.iconSize)
	icon.drawnSize, icon.nameAlong = nil, nil
	E:SetMediaFont(icon.num, s.font, s.fontSize, "OUTLINE")
	E:SetMediaFont(icon.name, s.font, s.fontSize)
	icon.name:SetShown(s.names)
	icon:EnableMouse(s.tooltip ~= "off")
	icon.styled = self.styleKey
end

-- The border color of an icon: the boss mod's, the accent, or the plain
-- border.
function M:BorderColor(row, s)
	if s.border == "accent" then return E.media.accentColor end
	if s.border == "bossmod" and row.color then return row.color end
	return E.media.borderColor
end

function M:PaintIcon(icon, row, s)
	local texture = row.icon
	if icon.texture ~= texture then
		icon.texture = texture
		icon.tex:SetTexture(texture or M.QUESTION_ICON)
	end
	local c = self:BorderColor(row, s)
	icon:SetBackdropBorderColor(c[1], c[2], c[3], 1)
	if s.names then icon.name:SetText(M.DisplayText(row.text, "")) end
end

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------
function M:ApplyBarLook()
	local bar = self.bar
	if not bar then return end
	local s = self.cache or self:Settings()
	self.styleKey = (self.styleKey or 0) + 1
	-- The frame takes the size of the big icons, the bar and its tick
	-- numbers together; the bar sits in it (see the header).
	local layout = self:FrameLayout(s)
	if self.frame then self.frame:SetSize(layout.width, layout.height) end
	bar:SetSize(layout.barW, layout.barH)
	bar:ClearAllPoints()
	bar:SetPoint("BOTTOMLEFT", bar:GetParent(), "BOTTOMLEFT", layout.barX, layout.barY)

	-- Backing
	E:SetTemplate(bar.strip, true)
	E:SetStyleEdge(bar.strip, s.backing == "strip")
	bar.strip:SetShown(s.backing == "strip")
	bar.strip:ClearAllPoints()
	bar.panel:ClearAllPoints()
	-- The backing covers the bar, not the side names.
	if s.vertical then
		bar.strip:SetPoint("TOPLEFT")
		bar.strip:SetPoint("BOTTOMLEFT")
		bar.strip:SetWidth(s.thickness)
	else
		bar.strip:SetAllPoints()
	end
	bar.panel:SetAllPoints(bar.strip)
	if s.backing == "panel" then E:SetPanelTemplate(bar.panel, true) end
	bar.panel:SetShown(s.backing == "panel")

	local nowPos, travel = self:Geometry(s)
	local border, accent, text = E.media.borderColor, E.media.accentColor, E.tokens.text

	-- Track line (backing "none")
	local track = bar.track
	track:ClearAllPoints()
	track:SetVertexColor(border[1], border[2], border[3], 1)
	local x1, y1 = self:AxisPoint(nowPos, 0, s)
	local x2, y2 = self:AxisPoint(s.length - 4, 0, s)
	if s.vertical then
		track:SetPoint("BOTTOM", bar, "BOTTOMLEFT", x1, math.min(y1, y2))
		track:SetHeight(math.abs(y2 - y1))
		E:Hairline(track, "w", 2)
	else
		track:SetPoint("LEFT", bar, "BOTTOMLEFT", math.min(x1, x2), y1)
		track:SetWidth(math.abs(x2 - x1))
		E:Hairline(track, "h", 2)
	end
	track:SetShown(s.backing == "none")

	-- Now-marker: the accent, 2 px across the bar.
	local now = bar.now
	now:ClearAllPoints()
	now:SetVertexColor(accent[1], accent[2], accent[3], 0.8)
	local nx, ny = self:AxisPoint(nowPos, 0, s)
	now:SetPoint("CENTER", bar, "BOTTOMLEFT", nx, ny)
	if s.vertical then
		now:SetWidth(s.thickness - 4)
		E:Hairline(now, "h", 2)
	else
		now:SetHeight(s.thickness - 4)
		E:Hairline(now, "w", 2)
	end

	-- Warning zones: the last warn and bad seconds of the track.
	local function Zone(tex, fromSeconds, toSeconds, color, alpha)
		tex:ClearAllPoints()
		local fromAlong = nowPos + math.min(fromSeconds, s.window) / s.window * travel
		local toAlong = nowPos + math.min(toSeconds, s.window) / s.window * travel
		local ax, ay = self:AxisPoint(fromAlong, 0, s)
		local bx, by = self:AxisPoint(toAlong, 0, s)
		if s.vertical then
			tex:SetPoint("BOTTOM", bar, "BOTTOMLEFT", ax, math.min(ay, by))
			tex:SetSize(s.thickness - 2, math.max(1, math.abs(by - ay)))
		else
			tex:SetPoint("LEFT", bar, "BOTTOMLEFT", math.min(ax, bx), ay)
			tex:SetSize(math.max(1, math.abs(bx - ax)), s.thickness - 2)
		end
		tex:SetVertexColor(color[1], color[2], color[3], alpha)
		tex:SetShown(s.zones)
	end
	Zone(bar.zoneBad, 0, s.bad, text.bad, 0.10)
	Zone(bar.zoneWarn, s.bad, s.warn, text.warn, 0.06)

	-- Ticks
	local count = self:TickCount(s)
	local dim, secondary = text.dim, text.secondary
	local white = E.tokens.hover.control
	for index = 1, math.max(count, #bar.ticks) do
		local tick = Tick(bar, index)
		local shown = index <= count
		tick.line:SetShown(shown)
		tick.label:SetShown(shown and s.tickLabels)
		tick.flash:Hide()
		if shown then
			local seconds = index * s.tickEvery
			local along = nowPos + seconds / s.window * travel
			local tx, ty = self:AxisPoint(along, 0, s)
			tick.line:ClearAllPoints()
			tick.line:SetPoint("CENTER", bar, "BOTTOMLEFT", tx, ty)
			tick.line:SetVertexColor(dim[1], dim[2], dim[3], 0.6)
			tick.flash:ClearAllPoints()
			tick.flash:SetPoint("CENTER", bar, "BOTTOMLEFT", tx, ty)
			tick.flash:SetVertexColor(1, 1, 1, white)
			if s.vertical then
				tick.line:SetWidth(s.thickness - 8)
				E:Hairline(tick.line, "h", 1)
				tick.flash:SetSize(s.thickness - 4, 6)
			else
				tick.line:SetHeight(s.thickness - 8)
				E:Hairline(tick.line, "w", 1)
				tick.flash:SetSize(6, s.thickness - 4)
			end
			E:SetFont(tick.label, E.tokens.size.tiny)
			tick.label:SetTextColor(secondary[1], secondary[2], secondary[3])
			tick.label:SetText(("%d"):format(seconds))
			tick.label:ClearAllPoints()
			-- Beside the strip, never on the icon row.
			if s.vertical then
				tick.label:SetPoint("RIGHT", bar, "BOTTOMLEFT", -2, ty)
			else
				tick.label:SetPoint("TOP", bar, "BOTTOMLEFT", tx, -1)
			end
			tick.seconds = seconds
		end
	end
	bar.tickCount = count

	-- Chip
	E:SetTemplate(bar.chip)
	E:SetFont(bar.chip.text, E.tokens.size.small)
	bar.chip.text:SetTextColor(secondary[1], secondary[2], secondary[3])

	for row, icon in pairs(bar.icons) do
		self:StyleIcon(icon, s)
		self:PaintIcon(icon, row, s)
	end
	self:ShowContent()
end

-- The bar's drawing shows only while it has something to show.
function M:ShowContent()
	local bar = self.bar
	if not bar then return end
	local any = false
	if self.active then
		for _, row in pairs(self.rows) do
			if self:Wanted(row) then any = true break end
		end
	end
	bar.content:SetShown(any)
	if self.soon then self.soon.content:SetShown(any and (self.cache or self:Settings()).big) end
end

-- Short white flash on a tick mark the icon just passed.
function M:FlashTick(index)
	local bar = self.bar
	local tick = bar and bar.ticks[index]
	if not (tick and index <= (bar.tickCount or 0)) then return end
	tick.flash:Show()
	tick.flashUntil = GetTime() + 0.2
end

---------------------------------------------------------------------------
-- Every frame
---------------------------------------------------------------------------
local onBar, waiting = {}, {}
local laneLast = {}

-- One step of an eased value; a value with no past snaps to its target.
local function Ease(current, target, ease)
	if current == nil then return target end
	local value = current + (target - current) * ease
	if math.abs(target - value) < 0.05 then return target end
	return value
end

local function Clamp(value, low, high)
	if high < low then return (low + high) / 2 end
	if value < low then return low end
	if value > high then return high end
	return value
end

-- Forget where a row was drawn: it snaps into place when it shows again.
local function ForgetPlace(row)
	row.slot, row.drawnAlong, row.offset, row.offsetTarget = nil, nil, nil, nil
	row.lane, row.laneTarget, row.size, row.sizeTarget = nil, nil, nil, nil
	row.side, row.pushed = nil, nil
end

-- Targets for the icons on the bar: lane, size and along position, by the
-- close-timer rule in the header. Returns how many rows fit before the far
-- end; the rest were pushed past it and join the waiting grid.
function M:PlanBar(s, nowPos, travel)
	local farEnd = nowPos + travel
	local full = s.iconSize
	local laneSize, laneOffset = self:LaneMetrics(s)
	local laneStep = laneSize + GAP
	local fullStep = full + GAP
	for _, row in ipairs(onBar) do
		row.base = nowPos + row.left / s.window * travel
	end
	local fit = #onBar
	for index, row in ipairs(onBar) do
		local prev, nextRow = onBar[index - 1], onBar[index + 1]
		-- Against where the previous icon goes, so a shifted group pushes on.
		local joinsPrev = prev and row.base - prev.planAlong < fullStep
		local crowded = joinsPrev or (nextRow and nextRow.base - row.base < fullStep)
		if not joinsPrev then laneLast[1], laneLast[-1] = nil, nil end
		local along, across, size = row.base, 0, full
		if crowded and s.lanes then
			size = laneSize
			local function Room(side)
				local last = laneLast[side]
				if not last then return math.huge end
				return along - last
			end
			local side = row.side
			if not (side and Room(side) >= laneStep - 0.01) then
				-- A free lane, or else the one whose last icon is furthest
				-- back: the icon moves on along it until it clears that one.
				local up, down = Room(1), Room(-1)
				side = (down > up) and -1 or 1
			end
			if laneLast[side] then along = math.max(along, laneLast[side] + laneStep) end
			row.side = side
			across = side * laneOffset
			laneLast[side] = along
		else
			row.side = nil
			if prev then along = math.max(along, prev.planAlong + fullStep) end
		end
		row.pushed = along > row.base + 0.5
		row.planAlong = along
		row.planAcross, row.planSize = across, size
		if along > farEnd + 0.01 and fit == #onBar then fit = index - 1 end
	end
	return fit
end

-- Move a row's icon toward its targets and draw it. `slot` names where it
-- belongs ("bar" or a waiting cell); `base` is its natural place there.
function M:PlaceIcon(icon, row, slot, base, s, ease)
	if row.slot ~= slot then
		row.offset = row.drawnAlong and (row.drawnAlong - base) or nil
		row.slot = slot
	end
	row.offsetTarget = row.planAlong - base
	row.offset = Ease(row.offset, row.offsetTarget, ease)
	row.laneTarget = row.planAcross
	row.lane = Ease(row.lane, row.laneTarget, ease)
	row.sizeTarget = row.planSize
	row.size = Ease(row.size, row.sizeTarget, ease)

	local half = row.size / 2
	local room = s.thickness / 2 - INSET
	local across = Clamp(row.lane, half - room, room - half)
	local along = Clamp(base + row.offset, INSET + half, s.length - INSET - half)
	row.drawnAlong = along
	if icon.drawnSize ~= row.size then
		icon.drawnSize = row.size
		icon:SetSize(row.size, row.size)
	end
	local x, y = self:AxisPoint(along, across, s)
	icon:ClearAllPoints()
	icon:SetPoint("CENTER", self.bar, "BOTTOMLEFT", x, y)
end

local function SetLevel(icon, level)
	if icon.level ~= level then
		icon.level = level
		icon:SetFrameLevel(level)
	end
end

-- The side names, in one column beside the strip (see the header).
local named = {}
local spots = {}
function M:PlaceNames(s)
	local bar = self.bar
	local line = s.fontSize + 4
	local last, hidden = nil, 0
	for index, icon in ipairs(named) do
		local along = icon.row and icon.row.drawnAlong
		if along then
			if last then along = math.max(along, last + line) end
			along = math.max(along, line / 2)
		end
		if along and along <= s.length - line / 2 then
			last = along
			spots[index] = along
		else
			spots[index] = false
			hidden = hidden + 1
		end
	end
	-- Names left out: the last line of the column is the "+N", so the
	-- names that would share it are left out too.
	local moreAt = s.length - line / 2
	if hidden > 0 then
		for index = #named, 1, -1 do
			local along = spots[index]
			if along and along > moreAt - line then
				spots[index] = false
				hidden = hidden + 1
			end
		end
	end
	for index, icon in ipairs(named) do
		local along, name = spots[index], icon.name
		if along then
			if icon.nameAlong ~= along then
				icon.nameAlong = along
				local _, y = self:AxisPoint(along, 0, s)
				name:ClearAllPoints()
				name:SetPoint("LEFT", bar, "BOTTOMLEFT", s.thickness + NAME_GAP, y)
			end
			name:Show()
		else
			icon.nameAlong = nil
			name:Hide()
		end
	end
	local more = bar.moreNames
	if hidden > 0 then
		local _, y = self:AxisPoint(moreAt, 0, s)
		E:SetMediaFont(more, s.font, s.fontSize)
		more:SetTextColor(unpack(E.tokens.text.secondary))
		more:ClearAllPoints()
		more:SetPoint("LEFT", bar, "BOTTOMLEFT", s.thickness + NAME_GAP, y)
		more:SetText(("+%d"):format(hidden))
		more:Show()
	else
		more:Hide()
	end
	wipe(named)
	wipe(spots)
end

function M:LayoutBar(now, numbers)
	local bar = self.bar
	if not bar then return end
	local s = self.cache
	self:ShowContent()
	for _, tick in ipairs(bar.ticks) do
		if tick.flashUntil and now >= tick.flashUntil then
			tick.flash:Hide()
			tick.flashUntil = nil
		end
	end
	if not bar.content:IsShown() then return end
	local nowPos, travel = self:Geometry(s)
	local dt = now - (self.lastLayout or now)
	self.lastLayout = now
	local ease = (s.motion and dt > 0) and math.min(1, dt / LANE_EASE) or 1
	wipe(onBar)
	wipe(waiting)
	self.layoutPass = (self.layoutPass or 0) + 1
	local pass = self.layoutPass
	local rows = self:ShownRows(now)
	-- Events in the big icons leave the bar (and do not come back for
	-- their end fade), so every event shows once.
	local inSoon = self:SoonRows(rows, s)
	for _, row in ipairs(rows) do
		if inSoon[row] then
			row.handedOff = true
		elseif not (row.handedOff and (row.ending or row.stopping)) then
			row.handedOff = nil
			if row.left > s.window then
				waiting[#waiting + 1] = row
			else
				onBar[#onBar + 1] = row
			end
		end
	end

	local text = E.tokens.text
	local layer = bar.iconLayer:GetFrameLevel()
	local fit = self:PlanBar(s, nowPos, travel)
	-- Icons pushed past the far end wait first in the grid.
	for index = #onBar, fit + 1, -1 do
		table.insert(waiting, 1, table.remove(onBar, index))
	end
	for index, row in ipairs(onBar) do
		local icon = self:IconFor(row, s)
		local fade = self:FadeProgress(row, now)
		self:PlaceIcon(icon, row, "bar", row.base, s, ease)
		-- Soonest on top: the level follows the order of the time left.
		SetLevel(icon, layer + 9 + math.max(0, LEVEL_SPAN - index))
		local alpha = 1
		if row.pausedAt and not row.sample then alpha = E.tokens.disabledAlpha end
		icon:SetAlpha(alpha * (1 - fade))
		icon.tex:SetDesaturated(row.pausedAt ~= nil and not row.sample)
		-- A pushed icon shows its seconds, so its time stays readable.
		if numbers then self:IconNumber(icon, row, s, text, row.pushed) end
		icon.pass = pass
		icon:Show()
		if s.names then named[#named + 1] = icon end
	end

	-- The waiting grid: soonest first, the rest as "+N". It sits under the
	-- bar's icons, so a timer that just left it glides over.
	local stacked = s.waiting and math.min(#waiting, s.waitMax) or 0
	local laneSize = self:LaneMetrics(s)
	for index = 1, stacked do
		local row = waiting[index]
		local icon = self:IconFor(row, s)
		local along, across = self:WaitSlot(index, s)
		row.planAlong, row.planAcross, row.planSize = along, across, laneSize
		row.side, row.pushed = nil, nil
		self:PlaceIcon(icon, row, "wait" .. index, along, s, ease)
		SetLevel(icon, layer + 2 + (s.waitMax - index))
		icon:SetAlpha(WAIT_ALPHA * (1 - self:FadeProgress(row, now)))
		icon.tex:SetDesaturated(row.pausedAt ~= nil and not row.sample)
		if numbers then self:IconNumber(icon, row, s, text, true) end
		icon.pass = pass
		icon:Show()
		if s.names then named[#named + 1] = icon end
	end
	if s.names then
		self:PlaceNames(s)
	else
		bar.moreNames:Hide()
	end
	-- Rows a switch hides now (or past the grid, or in the big icons) keep
	-- no icon on the bar.
	for row, icon in pairs(bar.icons) do
		if icon.pass ~= pass then
			icon:Hide()
			ForgetPlace(row)
		end
	end
	local extra = #waiting - stacked
	local chip = bar.chip
	if s.waiting and extra > 0 then
		-- The chip takes the grid's next cell.
		local along, across = self:WaitSlot(stacked + 1, s)
		chip:SetSize(laneSize, laneSize)
		local x, y = self:AxisPoint(along, across, s)
		chip.text:SetText("+" .. extra)
		chip:ClearAllPoints()
		chip:SetPoint("CENTER", bar, "BOTTOMLEFT", x, y)
		chip:Show()
	else
		chip:Hide()
	end
	bar.chipCount = (s.waiting and extra > 0) and extra or 0
	bar.waitingShown = stacked
end

-- The frame of a row (pooled), styled for the current settings.
function M:IconFor(row, s)
	local bar = self.bar
	local icon = bar.icons[row]
	if not icon then
		icon = self:NewBarIcon()
		bar.icons[row] = icon
		icon.row = row
		icon.texture = nil
		self:StyleIcon(icon, s)
	elseif icon.styled ~= self.styleKey then
		self:StyleIcon(icon, s)
	end
	icon.row = row
	self:PaintIcon(icon, row, s)
	return icon
end

-- The countdown number and its stage color.
-- always: a waiting or pushed icon shows its seconds whatever "Numbers
-- from" says (with numbers on).
function M:IconNumber(icon, row, s, text, always)
	local isWaiting = row.slot ~= "bar"
	local left = row.left
	local show = s.numbers > 0 and (always or left <= s.numbers) and left > 0
	if show then
		icon.num:SetText(self:FormatSeconds(left, s.tenths))
	else
		icon.num:SetText("")
	end
	local stage = self:Stage(left, s)
	if left <= 0 then stage = "bad" end
	if stage ~= row.stage and not row.sample and not isWaiting then
		if stage == "warn" then self.stats.warn = self.stats.warn + 1 end
		if stage == "bad" then self.stats.bad = self.stats.bad + 1 end
	end
	if not isWaiting then row.stage = stage end
	local c = self:StageColor(stage)
	if not stage then c = text.body end
	icon.num:SetTextColor(c[1], c[2], c[3])
end
