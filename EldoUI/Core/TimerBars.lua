-- EldoUI timer bar kit (E.TimerBars, also EldoUI.TimerBars for plugins).
--
-- A group is a stack of countdown bars that share one look: icon, label,
-- time left, color. Bars come from a pool and go back to it when they
-- expire or stop, so a busy battleground never builds new frames. One
-- driver frame updates every group (fill every frame, text ten times a
-- second) and only runs while a bar is on screen.
--
--   local group = E.TimerBars:CreateGroup(holder, { width = 220, height = 16 })
--   group:Start("flag", { label = "Flag respawn", icon = 134420, duration = 23,
--       color = { 0.2, 0.6, 1 }, onExpire = function(key, data) end })
--   group:Stop("flag")
--
-- Bar data: label, icon (file ID, path or atlas), duration (seconds),
-- expires (GetTime() at the end; default now + duration), color {r,g,b},
-- pinned (sorts first), fill ("drain" default, or "fill"), onExpire,
-- onClick(key, data, button), tooltip (text or function(tooltip, data)),
-- durationObject (a DurationObject from the game: the bar fills through
-- StatusBar:SetTimerDuration where the client has it, and the time text
-- shows only while the remaining time is a plain number), timeText (fixed
-- text in the time slot instead of a countdown, e.g. "-" for a frozen bar),
-- borderColor {r,g,b} (icon border).
--
-- A bar whose label, time or icon is a secret value is hidden: EldoUI does
-- no math on secrets. Bars use E:CreateStatusBar, so a new bar texture or
-- art style reaches them at once; colors and fonts are re-applied after
-- every art-style refresh.
--
-- Group options: width, height, spacing, growth ("DOWN" or "UP"), max
-- (bars shown; the rest wait), icon (show icons, default true), fontSize,
-- textAbove (label above a thin bar; default on below 10 px height),
-- iconSide ("LEFT" default, or "RIGHT"), texture (bar texture media id;
-- nil or "default" = the theme texture), font (font media id; nil, "THEME"
-- or "default" = the theme font), background (box behind each bar, default
-- true), mouse (bars take the mouse for tooltips and clicks, default true;
-- false = click-through), options (an options link target: Ctrl-click on
-- a bar opens that page; a bar's data.options wins).
local _, E = ...
local L = E.L

local TB = {}
E.TimerBars = TB

local TEXT_INTERVAL = 0.1
local groups = {}   -- every group, in creation order
local driver = CreateFrame("Frame")
driver:Hide()

local IsSecret = E.Secret

local function HasAtlas(name)
	return type(name) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- "1.5", "12", "1:05", "1h 05m" from seconds.
function TB.FormatTime(seconds)
	if type(seconds) ~= "number" or IsSecret(seconds) then return "" end
	if seconds < 0 then seconds = 0 end
	if seconds < 10 then return ("%.1f"):format(seconds) end
	if seconds < 60 then return ("%d"):format(math.floor(seconds)) end
	if seconds < 3600 then return ("%d:%02d"):format(math.floor(seconds / 60), math.floor(seconds % 60)) end
	return L["%dh %02dm"]:format(math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
end

-- Seconds left on a bar, or nil when unknown (secret or no time given).
local function Remaining(bar, now)
	local data = bar.data
	local object = data.durationObject
	if object and type(object.GetRemainingDuration) == "function" then
		local ok, left = pcall(object.GetRemainingDuration, object)
		if ok and not IsSecret(left) and type(left) == "number" then return left end
	end
	if IsSecret(data.expires) or type(data.expires) ~= "number" then return nil end
	return data.expires - now
end

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------
local function PaintBar(bar)
	local data = bar.data or {}
	local color = data.color
	local r, g, b = 0.4, 0.6, 1
	if type(color) == "table" then
		r, g, b = color[1] or color.r or r, color[2] or color.g or g, color[3] or color.b or b
	else
		r, g, b = unpack(E.media.accentColor)
	end
	local opts = bar.group.opts
	local texture = opts.texture and opts.texture ~= "" and opts.texture ~= "default" and E:FetchMedia("statusbar", opts.texture)
	bar.status:SetStatusBarTexture(texture or E.media.statusbar)
	bar.status:SetStatusBarColor(r, g, b, 1)
	if bar.status.bg then bar.status.bg:SetShown(opts.background ~= false) end
	if not E:IsThemeFont(opts.font) then
		E:SetMediaFont(bar.label, opts.font, opts.fontSize)
		E:SetMediaFont(bar.time, opts.font, opts.fontSize)
	else
		E:SetFont(bar.label, opts.fontSize)
		E:SetFont(bar.time, opts.fontSize)
	end
	bar.label:SetTextColor(1, 1, 1)
	bar.time:SetTextColor(1, 1, 1)
	E:SetTemplate(bar.iconBox)
	local border = data.borderColor
	if type(border) == "table" and bar.iconBox.SetBackdropBorderColor then
		bar.iconBox:SetBackdropBorderColor(border[1] or border.r or 0, border[2] or border.g or 0, border[3] or border.b or 0, 1)
	end
end

local function CreateBar(group)
	local bar = CreateFrame("Button", nil, group)
	bar.group = group
	bar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	bar.iconBox = CreateFrame("Frame", nil, bar)
	bar.iconBox:SetPoint("TOPLEFT")
	E:SetTemplate(bar.iconBox)
	bar.icon = bar.iconBox:CreateTexture(nil, "ARTWORK")
	bar.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	bar.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(bar.icon)
	bar.status = E:CreateStatusBar(bar)
	bar.status:SetMinMaxValues(0, 1)
	bar.label = E:CreateText(bar.status, group.opts.fontSize, "LEFT")
	bar.time = E:CreateText(bar.status, group.opts.fontSize, "RIGHT")
	bar:SetScript("OnClick", function(self, button)
		if E:IsOptionsLinkClick(self, button) then return end
		local data = self.data
		if data and data.onClick then
			local ok, err = pcall(data.onClick, self.key, data, button)
			if not ok then geterrorhandler()(err) end
		end
	end)
	bar:SetScript("OnEnter", function(self)
		local data = self.data
		if not (data and data.tooltip) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if type(data.tooltip) == "function" then
			pcall(data.tooltip, GameTooltip, data)
		else
			if not IsSecret(data.label) and data.label then E.UIKit.TipTitle(GameTooltip, data.label) end
			E.UIKit.TipText(GameTooltip, data.tooltip)
		end
		GameTooltip:Show()
	end)
	bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- Ctrl-click opens the owner's options (group option `options`, or a
	-- bar's own data.options).
	E:BindOptionsLink(bar, function(self)
		return self.data and self.data.options or self.group.opts.options
	end)
	return bar
end

-- Size and place the parts of one bar for the group look.
local function ShapeBar(bar)
	local opts = bar.group.opts
	local height = opts.height
	local above = opts.textAbove
	if above == nil then above = height < 10 end
	local textRoom = above and (opts.fontSize + 2) or 0
	bar:SetSize(opts.width, height + textRoom)
	local showIcon = opts.icon ~= false and bar.data and bar.data.icon ~= nil
	local iconSize = height + textRoom
	local right = opts.iconSide == "RIGHT"
	bar.iconBox:SetSize(iconSize, iconSize)
	bar.iconBox:ClearAllPoints()
	bar.iconBox:SetPoint(right and "TOPRIGHT" or "TOPLEFT")
	bar.iconBox:SetShown(showIcon)
	bar.status:ClearAllPoints()
	bar.status:SetPoint("BOTTOMLEFT", (showIcon and not right) and (iconSize + 3) or 0, 0)
	bar.status:SetPoint("BOTTOMRIGHT", (showIcon and right) and -(iconSize + 3) or 0, 0)
	bar:EnableMouse(opts.mouse ~= false)
	bar.status:SetHeight(height)
	bar.label:ClearAllPoints()
	bar.time:ClearAllPoints()
	if above then
		bar.label:SetPoint("BOTTOMLEFT", bar.status, "TOPLEFT", 1, 2)
		bar.time:SetPoint("BOTTOMRIGHT", bar.status, "TOPRIGHT", -1, 2)
		bar.label:SetPoint("BOTTOMRIGHT", bar.time, "BOTTOMLEFT", -4, 0)
	else
		bar.label:SetPoint("LEFT", bar.status, "LEFT", 4, 0)
		bar.time:SetPoint("RIGHT", bar.status, "RIGHT", -4, 0)
		bar.label:SetPoint("RIGHT", bar.time, "LEFT", -4, 0)
	end
end

-- Apply bar data to the widgets. Secret label, icon or time: hidden.
local function ApplyData(bar)
	local data = bar.data
	bar.secret = IsSecret(data.label) or IsSecret(data.icon) or IsSecret(data.duration) or IsSecret(data.expires) or IsSecret(data.timeText)
	if bar.secret then
		bar:Hide()
		return
	end
	bar.label:SetText(data.label or "")
	if data.icon then
		if HasAtlas(data.icon) then bar.icon:SetAtlas(data.icon) else bar.icon:SetTexture(E.ClientIcon and E:ClientIcon(data.icon) or data.icon) end
	end
	bar.usesTimer = false
	if data.durationObject and bar.status.SetTimerDuration then
		local ok = pcall(bar.status.SetTimerDuration, bar.status, data.durationObject)
		bar.usesTimer = ok
	end
	ShapeBar(bar)
	PaintBar(bar)
end

-- A bar beyond the group's max is hidden: it still ends on time, but its
-- fill is only set again once it is shown.
local function UpdateBar(bar, now, withText, hidden)
	local data = bar.data
	local left = Remaining(bar, now)
	if left and left <= 0 then return false end
	if not bar.usesTimer and not hidden then
		local duration = data.duration
		local value = 1
		if left and type(duration) == "number" and duration > 0 then value = math.max(0, math.min(1, left / duration)) end
		if data.fill == "fill" then value = 1 - value end
		bar.status:SetValue(value)
	end
	if withText then
		if data.timeText then bar.time:SetText(data.timeText) else bar.time:SetText(left and TB.FormatTime(left) or "") end
	end
	return true
end

---------------------------------------------------------------------------
-- Groups
---------------------------------------------------------------------------
local Group = {}

local DEFAULTS = { width = 200, height = 16, spacing = 3, growth = "DOWN", max = 10, icon = true, fontSize = 11 }

function TB:CreateGroup(parent, opts)
	local group = CreateFrame("Frame", nil, parent or UIParent)
	group.opts = {}
	for key, value in pairs(DEFAULTS) do group.opts[key] = value end
	for key, value in pairs(opts or {}) do group.opts[key] = value end
	group.bars = {}   -- key -> bar
	group.pool = {}
	group.order = {}  -- keys shown, in layout order
	group.sorted = {} -- reused by every sort
	for name, fn in pairs(Group) do group[name] = fn end
	group:SetSize(group.opts.width, group.opts.height)
	groups[#groups + 1] = group
	return group
end

-- Start a bar, or update the bar with that key.
function Group:Start(key, data)
	if key == nil or type(data) ~= "table" then return nil end
	local bar = self.bars[key]
	if not bar then
		bar = table.remove(self.pool) or CreateBar(self)
		self.bars[key] = bar
	end
	bar.key = key
	bar.data = data
	if not IsSecret(data.duration) and type(data.duration) == "number" and not IsSecret(data.expires) and type(data.expires) == "nil" then
		data.expires = GetTime() + data.duration
	end
	ApplyData(bar)
	self:LayoutSoon()
	return bar
end

-- Change fields of a running bar (label, color, expires, ...).
function Group:Update(key, fields)
	local bar = self.bars[key]
	if not bar then return nil end
	for field, value in pairs(fields or {}) do bar.data[field] = value end
	ApplyData(bar)
	self:LayoutSoon()
	return bar
end

function Group:Get(key)
	return self.bars[key]
end

-- Seconds left on a bar (nil when unknown or not running).
function Group:Remaining(key)
	local bar = self.bars[key]
	return bar and Remaining(bar, GetTime()) or nil
end

local function Release(group, key)
	local bar = group.bars[key]
	if not bar then return end
	group.bars[key] = nil
	bar:Hide()
	bar.data, bar.key = nil, nil
	group.pool[#group.pool + 1] = bar
end

function Group:Stop(key)
	if not self.bars[key] then return end
	Release(self, key)
	self:Layout()
end

function Group:StopAll()
	for key in pairs(self.bars) do Release(self, key) end
	self:Layout()
end

function Group:Count()
	local count = 0
	for _ in pairs(self.bars) do count = count + 1 end
	return count
end

-- Bars on screen, in order.
function Group:Shown()
	if self.layoutDue then self:Layout() end
	local list = {}
	for index, key in ipairs(self.order) do list[index] = self.bars[key] end
	return list
end

-- Pinned bars first, then the least time left; bars without a known time
-- after those, by key.
local function BySortOrder(a, b)
	local pa, pb = a.data.pinned and 1 or 0, b.data.pinned and 1 or 0
	if pa ~= pb then return pa > pb end
	local la, lb = a.sortLeft, b.sortLeft
	if la and lb and la ~= lb then return la < lb end
	if la and not lb then return true end
	if lb and not la then return false end
	return tostring(a.key) < tostring(b.key)
end

local function Sorted(group, now)
	local list = group.sorted
	wipe(list)
	group.sorts = (group.sorts or 0) + 1
	for _, bar in pairs(group.bars) do
		if not bar.secret then
			bar.sortLeft = Remaining(bar, now)
			list[#list + 1] = bar
		else
			bar:Hide()
		end
	end
	table.sort(list, BySortOrder)
	return list
end

-- True when the bars on screen would change order.
local function OrderChanged(group, now)
	local list = Sorted(group, now)
	local shown = math.min(#list, group.opts.max)
	if shown ~= #group.order then return true end
	for index = 1, shown do
		if list[index].key ~= group.order[index] then return true end
	end
	return false
end

-- Starts and updates in one frame share one layout, on the driver's next
-- frame (Shown() lays out at once when one is due).
function Group:LayoutSoon()
	self.layoutDue = true
	driver:Show()
end

function Group:Layout()
	self.layoutDue = nil
	self.layouts = (self.layouts or 0) + 1
	local opts = self.opts
	local now = GetTime()
	local list = Sorted(self, now)
	wipe(self.order)
	local offset = 0
	for index, bar in ipairs(list) do
		if index <= opts.max then
			bar:ClearAllPoints()
			if opts.growth == "UP" then
				bar:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, offset)
			else
				bar:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -offset)
			end
			offset = offset + bar:GetHeight() + opts.spacing
			UpdateBar(bar, now, true)
			bar:Show()
			self.order[#self.order + 1] = bar.key
		else
			bar:Hide()
		end
	end
	self:SetHeight(math.max(offset - opts.spacing, 1))
end

-- Change the look (width, height, spacing, growth, max, icon, fontSize,
-- textAbove, iconSide, texture, font, background, mouse) and redraw every
-- bar.
function Group:SetLook(opts)
	for key, value in pairs(opts or {}) do self.opts[key] = value end
	self:SetWidth(self.opts.width)
	self:Restyle()
end

function Group:Restyle()
	for _, bar in pairs(self.bars) do ApplyData(bar) end
	for _, bar in ipairs(self.pool) do
		if bar.data then PaintBar(bar) end
	end
	self:Layout()
end

---------------------------------------------------------------------------
-- Driver: one OnUpdate for every group, only while bars run.
---------------------------------------------------------------------------
local textClock = 0
driver:SetScript("OnUpdate", function(self, elapsed)
	textClock = textClock + elapsed
	local withText = textClock >= TEXT_INTERVAL
	if withText then textClock = 0 end
	local now = GetTime()
	local any = false
	for _, group in ipairs(groups) do
		local expired
		if group.layoutDue then group:Layout() end
		for key, bar in pairs(group.bars) do
			if bar.secret then
				-- Hidden (secret label, icon or time). It still ends when its
				-- own plain end time passes; one without keeps no driver
				-- running (its owner stops it).
				local expires = bar.data and bar.data.expires
				if not IsSecret(expires) and type(expires) == "number" then
					any = true
					if expires <= now then
						expired = expired or {}
						expired[#expired + 1] = key
					end
				end
			else
				any = true
				local shown = bar:IsShown()
				if not UpdateBar(bar, now, withText and shown, not shown) then
					expired = expired or {}
					expired[#expired + 1] = key
				end
			end
		end
		if expired then
			for _, key in ipairs(expired) do
				local bar = group.bars[key]
				local data = bar and bar.data
				Release(group, key)
				if data and data.onExpire then
					local ok, err = pcall(data.onExpire, key, data)
					if not ok then geterrorhandler()(err) end
				end
			end
			group:Layout()
		elseif withText and OrderChanged(group, now) then
			-- Bars started with different lengths can swap places.
			group:Layout()
		end
	end
	if not any then self:Hide() end
end)

-- True while the driver runs (for /eui diag and tests).
function TB.Running()
	return driver:IsShown() and true or false
end

-- The art style refresh re-applies the bar texture (E.statusBars); colors
-- and fonts follow here, through the theme registry (Core/Media.lua).
E:OnThemeChanged("timerbars", function()
	for _, group in ipairs(groups) do
		for _, bar in pairs(group.bars) do
			if not bar.secret then PaintBar(bar) end
		end
	end
end)
