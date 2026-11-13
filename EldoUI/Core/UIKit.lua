-- EldoUI UI kit (E.UIKit, also EldoUI.UIKit for plugins).
--
-- The parts EldoUI's own windows are built from, in the Loot Guide look
-- (DESIGN.md): one flat panel with an accent line under a 36 px top bar,
-- flat tabs with an accent underline, a footer line, designed empty states
-- and virtual lists. New windows (Characters, Instances, Talents, Routes)
-- build from these so every window reads as one product.
--
-- It is the one widget kit of EldoUI: E.WindowKit, the
-- plugin install kit and the Loot Guide kit use these parts.
--
--   UIKit.Text(parent, size, justify, kind)     kind: body, secondary, header, dim
--   UIKit.Title(parent, size)                   a window or dialog title (header font)
--   UIKit.Button(parent, text, opts)            kinds: secondary, primary, danger
--   UIKit.IconButton / RemoveButton / Icon / Chevron / SetGlyph (no letters as icons)
--   UIKit.Check / Switch / Slider / Input / Dropdown / OpenMenu
--   UIKit.ScrollBar / ScrollArea / SizeGrip / Divider
--   UIKit.Tooltip / AnchorTooltip / TooltipHint (one anchor rule, one look)
--   UIKit.CreateToolWindow(name, opts)          the compact window shell
--   UIKit.CreateDialog(name, opts) / Prompt     the popup shell (E:ShowConfirm uses it)
--   UIKit.Toast(owner, text, opts)              a short notice inside a window (instead of chat)
--   UIKit.Chip(parent, text)                    a small label box
--   UIKit.ChipBar(parent, opts)                 a row of toggle chips (filters)
--   UIKit.EmptyState(parent)                    icon, title, text, value lines, buttons
--   UIKit.CreateList(parent, opts)              a virtual list (only rows on screen exist);
--                                               fixed rows, or variable heights with row kinds
--   UIKit.TextHeight(text, width, size, opts)   wrapped text height (for variable rows)
--   UIKit.CreateTable(parent, columns, opts)    sortable columns over a list
--   UIKit.FoldDivider / ValueRow                section name between accent lines, label-value rows
--   UIKit.ListRow2 / ListRow2Template           two-line list rows (friends, guild, alts)
--   UIKit.IconRail(parent, opts)                slim icon-only buttons on a window's edge
--   UIKit.CreateTabbedWindow(opts)              the whole window (see below)
--
-- Colors: the accent is read when drawn; texts made here are repainted
-- when the theme changes (E:RefreshTheme).
--
-- Texts: tab and chip labels, column titles, tooltips and empty states come
-- from tables built while the files load, before the saved language is
-- read, so they arrive as English keys. The kit shows them translated
-- (E:Translate); a text already translated stays as it is.
local _, E = ...
local L = E.L

-- The game's SearchBoxTemplate shows Blizzard's own "Search", which
-- follows the client's language. EldoUI's own search boxes show their hint,
-- or "Search", in the language EldoUI uses. Returns the box.
function E:SearchHint(box, hint)
	if box and box.Instructions then box.Instructions:SetText(hint or L["Search"]) end
	return box
end

local Kit = {}
E.UIKit = Kit

-- The colors and sizes are the design tokens (Core/Media.lua).
Kit.TEXT = E.tokens.text.body
Kit.SECONDARY = E.tokens.text.secondary
Kit.DIM = E.tokens.text.dim
Kit.GOOD = E.tokens.text.good
Kit.WARN = E.tokens.text.warn
Kit.BAD = E.tokens.text.bad
Kit.ROW_HEIGHT = E.tokens.height.row

local painted = setmetatable({}, { __mode = "k" }) -- font string -> kind
local windows = {}                                  -- every tabbed window

local function HasAtlas(name)
	return type(name) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end
Kit.HasAtlas = HasAtlas

function Kit.Accent()
	local c = E.media.accentColor
	return c[1], c[2], c[3]
end

function Kit.Hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

function Kit.AccentHex()
	return E:TextHex("accent")
end

---------------------------------------------------------------------------
-- Small parts
---------------------------------------------------------------------------
local paintedColor = setmetatable({}, { __mode = "k" }) -- font string -> { r, g, b } the kit painted last

function Kit.Paint(fs, kind)
	local r, g, b
	if kind == "header" then
		r, g, b = Kit.Accent()
	elseif kind == "secondary" then
		r, g, b = unpack(Kit.SECONDARY)
	elseif kind == "dim" then
		r, g, b = unpack(Kit.DIM)
	elseif kind == "title" then
		r, g, b = 1, 1, 1
	elseif kind == "good" or kind == "warn" or kind == "bad" then
		r, g, b = unpack(E.tokens.text[kind])
	else
		r, g, b = unpack(Kit.TEXT)
	end
	fs:SetTextColor(r, g, b)
	paintedColor[fs] = { r, g, b }
end

-- Still showing the color the kit painted (not one a caller set after it,
-- such as a quality color or a warning)?
local function StillPainted(fs)
	local c = paintedColor[fs]
	if not c then return true end
	local ok, r, g, b = pcall(fs.GetTextColor, fs)
	if not ok or type(r) ~= "number" then return true end
	return math.abs(r - c[1]) < 0.01 and math.abs(g - c[2]) < 0.01 and math.abs(b - c[3]) < 0.01
end

-- kind: "body" (white, default), "secondary" (gray), "header" (accent), "dim",
-- "title" (white), "good", "warn" or "bad" (the status tokens).
-- Window text: no outline, a soft shadow (E:SetWindowFont).
function Kit.Text(parent, size, justify, kind, layer)
	size = size or E.tokens.size.body
	local fs = E:CreateText(parent, size, justify or "LEFT", layer)
	E:SetWindowFont(fs, size)
	fs.kitSize = size
	Kit.Paint(fs, kind)
	painted[fs] = kind or "body"
	return fs
end

-- A window or dialog title: the header font, white. size
-- defaults to the dialog title token; window titles pass
-- E.tokens.size.windowTitle.
function Kit.Title(parent, size, justify)
	local fs = Kit.Text(parent, size or E.tokens.size.dialogTitle, justify or "LEFT")
	fs.kitHeader = true
	E:SetWindowFont(fs, fs.kitSize, true)
	Kit.Paint(fs, "title")
	painted[fs] = "title"
	return fs
end

---------------------------------------------------------------------------
-- Soft changes (DESIGN.md 3a): a hover color, a selection tint or a
-- switch knob eases to its new look over E.tokens.motion.hover instead of
-- jumping. With General > Animations off, or while the part is hidden, it
-- changes at once. One shared updater runs only while something eases.
--   Kit.Animate()                                  true when fades run
--   Kit.Ease(owner, key, from, to, apply[, done])  from and to: lists of
--       numbers; apply(values) draws each step, done() runs at the end.
--       A new Ease on the same owner and key replaces the running one.
--   Kit.StopEase(owner[, key])                     jump to the end now
--   Kit.FadeTextColor(fs, r, g, b[, a])            from the color it shows
--   Kit.FadeVertexColor(texture, r, g, b[, a])
--   Kit.FadeBorderColor(frame, r, g, b[, a])       a backdrop's edge color
--   Kit.FadeAlpha(region, alpha[, done])
--   Kit.SoftSelect(row, selected, paint, parts[, ident])
--       paint(row, selected) draws the state at once; the parts (textures
--       of the selection look) fade in on select and out on deselect.
--       A row reused for another item (a new ident) changes at once.
---------------------------------------------------------------------------
-- owned: owner -> { key -> running ease }, weak, so no field is set on
-- the owner (a Blizzard font string or texture can be one).
Kit.ease = { list = {}, owned = setmetatable({}, { __mode = "k" }) }

--   Kit.Easing(owner, key)  the running ease of that owner and key, or nil
function Kit.Easing(owner, key)
	local owned = owner ~= nil and Kit.ease.owned[owner]
	return owned and owned[key] or nil
end

function Kit.Animate()
	return not (E.db and E.db.general and E.db.general.animations == false)
end

local function EaseShown(owner)
	if type(owner) ~= "table" or not owner.IsVisible then return true end
	local ok, shown = pcall(owner.IsVisible, owner)
	return not ok or shown and true or false
end

local function EaseCall(fn, ...)
	if not fn then return end
	local ok, err = pcall(fn, ...)
	if not ok then geterrorhandler()(err) end
end

local function EaseFinish(entry)
	Kit.ease.list[entry] = nil
	local owned = Kit.ease.owned[entry.owner]
	if owned and owned[entry.key] == entry then owned[entry.key] = nil end
	EaseCall(entry.apply, entry.to)
	EaseCall(entry.done)
end

local function EaseStep(_, elapsed)
	-- A step's done() may start another ease, so walk a snapshot.
	local entries = {}
	for entry in pairs(Kit.ease.list) do entries[#entries + 1] = entry end
	for _, entry in ipairs(entries) do
		entry.elapsed = entry.elapsed + (elapsed or 0)
		if not EaseShown(entry.owner) or entry.elapsed >= entry.duration then
			EaseFinish(entry)
		else
			local t = entry.elapsed / entry.duration
			t = 1 - (1 - t) * (1 - t) -- eases out, like the hover fades
			local values = entry.values
			for index = 1, #entry.to do
				local a = entry.from[index] or entry.to[index]
				values[index] = a + (entry.to[index] - a) * t
			end
			EaseCall(entry.apply, values)
		end
	end
	if next(Kit.ease.list) == nil and Kit.ease.driver then
		Kit.ease.driver:SetScript("OnUpdate", nil)
	end
end

function Kit.StopEase(owner, key)
	local owned = owner ~= nil and Kit.ease.owned[owner]
	if not owned then return end
	for k, entry in pairs(owned) do
		if key == nil or k == key then EaseFinish(entry) end
	end
end

local function Same(from, to)
	for index = 1, #to do
		if math.abs((from[index] or to[index]) - to[index]) > 0.001 then return false end
	end
	return true
end

function Kit.Ease(owner, key, from, to, apply, done)
	local owned = Kit.ease.owned[owner]
	local running = owned and owned[key]
	if running then
		Kit.ease.list[running] = nil
		owned[key] = nil
	end
	local duration = E.tokens.motion.hover or 0
	if not Kit.Animate() or duration <= 0 or not EaseShown(owner) or Same(from, to) then
		EaseCall(apply, to)
		EaseCall(done)
		return false
	end
	local entry = { owner = owner, key = key, from = from, to = to, values = {}, apply = apply, done = done,
		elapsed = 0, duration = duration }
	owned = owned or {}
	Kit.ease.owned[owner] = owned
	owned[key] = entry
	Kit.ease.list[entry] = true
	if not Kit.ease.driver then Kit.ease.driver = CreateFrame("Frame") end
	Kit.ease.driver:SetScript("OnUpdate", EaseStep)
	return true
end

local function ReadColor(region, getter)
	local ok, r, g, b, a = pcall(region[getter], region)
	if not ok or type(r) ~= "number" or E:IsSecret(r) then return nil end
	return { r, g, b, a or 1 }
end

function Kit.FadeTextColor(fs, r, g, b, a)
	local to = { r, g, b, a or 1 }
	local from = ReadColor(fs, "GetTextColor") or to
	Kit.Ease(fs, "textColor", from, to, function(v) fs:SetTextColor(v[1], v[2], v[3], v[4]) end)
end

function Kit.FadeVertexColor(texture, r, g, b, a)
	local to = { r, g, b, a or 1 }
	local from = ReadColor(texture, "GetVertexColor") or to
	Kit.Ease(texture, "vertexColor", from, to, function(v) texture:SetVertexColor(v[1], v[2], v[3], v[4]) end)
end

function Kit.FadeBorderColor(frame, r, g, b, a)
	local to = { r, g, b, a or 1 }
	local from = ReadColor(frame, "GetBackdropBorderColor") or to
	Kit.Ease(frame, "borderColor", from, to, function(v) frame:SetBackdropBorderColor(v[1], v[2], v[3], v[4]) end)
end

function Kit.FadeAlpha(region, alpha, done)
	local from = region.GetAlpha and region:GetAlpha() or alpha
	Kit.Ease(region, "alpha", { from }, { alpha }, function(v) region:SetAlpha(v[1]) end, done)
end

function Kit.SoftSelect(row, selected, paint, parts, ident)
	selected = selected and true or false
	local was, sameItem = row.kitSoftSelected, row.kitSoftIdent == ident
	row.kitSoftIdent = ident
	row.kitSoftSelected = selected
	if was == selected and sameItem then
		-- A repaint in the same state leaves a running fade alone.
		local fading = false
		for _, part in ipairs(parts) do
			if Kit.Easing(part, "alpha") then fading = true end
		end
		if selected or not fading then paint(row, selected) end
		return
	end
	if was == nil or not sameItem then
		for _, part in ipairs(parts) do Kit.StopEase(part, "alpha") part:SetAlpha(1) end
		paint(row, selected)
		return
	end
	if selected then
		paint(row, true)
		for _, part in ipairs(parts) do
			-- Starts from where a fade out left it, so a quick back and forth never jumps.
			if not Kit.Easing(part, "alpha") then part:SetAlpha(0) end
			Kit.FadeAlpha(part, 1)
		end
	else
		for index, part in ipairs(parts) do
			Kit.FadeAlpha(part, 0, function()
				if row.kitSoftSelected then return end
				part:SetAlpha(1)
				if index == #parts then paint(row, false) end
			end)
		end
	end
end

-- A short notice inside a window (DESIGN.md §5): confirmation of a click
-- that worked, or a problem with it, in the window instead of chat. The
-- window's panel look with a 2 px accent bar on the left (warn color for
-- a problem), body text, one or two lines (the box grows with them); it
-- slides in and fades after a moment. One per window: `owner.toast`
-- holds it, a new one replaces it.
--   Kit.Toast(owner, text[, opts])
--   opts: anchor (the toast sits on top of it, default owner), point
--         (anchor's point, default "TOP"), y (gap, default 12), warn,
--         maxWidth (default owner width - 48), time (seconds; default
--         Kit.ToastTime: longer for a longer text, twice that for a
--         warning), action = { label, onClick } (also { text = label,
--         onClick = fn }: a text button at the right, such as "Undo"; the
--         toast then stays at least Kit.TOAST_ACTION_TIME seconds and a
--         click on it closes the toast)
-- While the pointer is on the toast or its action it stays; it closes
-- Kit.TOAST_GRACE seconds after the pointer leaves (or when its time is
-- up, whichever is later).
--   Kit.ToastTime(text[, opts])   the seconds a toast with this text stays
Kit.TOAST_TIME = 2.5          -- the least time of a notice
Kit.TOAST_ACTION_TIME = 6     -- the least time of a notice with an action
Kit.TOAST_SHORT = 40          -- letters a short line reads in the least time
Kit.TOAST_PER_LETTER = 0.025  -- each letter past that (about 1 s per 8 words)
Kit.TOAST_MAX = 9             -- the most time a long text adds up to
Kit.TOAST_GRACE = 1.5         -- after the pointer leaves the toast

function Kit.ToastTime(text, opts)
	opts = opts or {}
	local time = opts.time
	if not time then
		local base = opts.action and Kit.TOAST_ACTION_TIME or Kit.TOAST_TIME
		local plain = type(text) == "string" and text or ""
		plain = plain:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
		local extra = math.max(0, #plain - Kit.TOAST_SHORT) * Kit.TOAST_PER_LETTER
		time = math.min(base + extra, math.max(base, Kit.TOAST_MAX))
	end
	return opts.warn and time * 2 or time
end

-- Closes the toast once its time is up and the pointer is off it.
local function ToastCheck(toast, token)
	if toast.token ~= token or not toast:IsShown() then return end
	if next(toast.hovers) then return end -- leaving starts the check again
	local left = (toast.closeAt or 0) - GetTime()
	if left > 0.05 then
		C_Timer.After(left, function() ToastCheck(toast, token) end)
		return
	end
	E:SlideOut(toast, "DOWN")
end

local function ToastEnter(toast, part)
	toast.hovers[part] = true
end

local function ToastLeave(toast, part)
	toast.hovers[part] = nil
	if next(toast.hovers) or not toast:IsShown() then return end
	local token = toast.token
	toast.closeAt = math.max(toast.closeAt or 0, GetTime() + Kit.TOAST_GRACE)
	C_Timer.After(math.max(Kit.TOAST_GRACE, toast.closeAt - GetTime()), function() ToastCheck(toast, token) end)
end

local function CreateToast(owner, opts)
	local toast = CreateFrame("Frame", nil, owner)
	toast:SetSize(200, E.tokens.height.settingsRow)
	toast:SetFrameLevel((opts.anchor or owner):GetFrameLevel() + 20)
	E:SetPanelTemplate(toast)
	-- 2 screen pixels like the tab and tree accents, inside the border.
	toast.bar = toast:CreateTexture(nil, "OVERLAY")
	toast.bar:SetPoint("TOPLEFT", E:PixelFor(toast), -E:PixelFor(toast))
	toast.bar:SetPoint("BOTTOMLEFT", E:PixelFor(toast), E:PixelFor(toast))
	E:Hairline(toast.bar, "w", 2)
	toast.text = E:CreateText(toast, E.tokens.size.body, "LEFT")
	toast.text:SetPoint("LEFT", 12, 0)
	toast.text:SetWordWrap(true)
	-- The pointer on the toast (or on its action) keeps it open.
	-- Hover only: clicks pass through to the rows under it.
	toast.hovers = {}
	toast:EnableMouse(true)
	if toast.SetMouseClickEnabled then toast:SetMouseClickEnabled(false) end
	toast:SetScript("OnEnter", function(self) ToastEnter(self, self) end)
	toast:SetScript("OnLeave", function(self) ToastLeave(self, self) end)
	toast:SetScript("OnHide", function(self) wipe(self.hovers) end)
	-- The action: accent text, the toast's own hit area on the right.
	toast.action = CreateFrame("Button", nil, toast)
	toast.action:SetPoint("TOPRIGHT")
	toast.action:SetPoint("BOTTOMRIGHT")
	toast.action.text = E:CreateText(toast.action, E.tokens.size.body, "CENTER")
	toast.action.text:SetPoint("CENTER")
	toast.action:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(E.tokens.text.body)) end)
	toast.action:SetScript("OnLeave", function(self) self.text:SetTextColor(E:TokenColor("accent")) end)
	E:SkinHoverPress(toast.action)
	toast.action:HookScript("OnEnter", function(self) ToastEnter(toast, self) end)
	toast.action:HookScript("OnLeave", function(self) ToastLeave(toast, self) end)
	toast.action:Hide()
	toast:Hide()
	toast.token = 0
	owner.toast = toast
	return toast
end

function Kit.Toast(owner, text, opts)
	if not owner then return nil end
	opts = opts or {}
	local toast = owner.toast or CreateToast(owner, opts)
	toast:ClearAllPoints()
	toast:SetPoint("BOTTOM", opts.anchor or owner, opts.point or "TOP", 0, opts.y or 12)
	toast.token = toast.token + 1
	local token = toast.token
	local c = opts.warn and E.tokens.text.warn or E.media.accentColor
	toast.bar:SetColorTexture(c[1], c[2], c[3], 1)
	toast.text:SetTextColor(unpack(E.tokens.text.body))
	-- One line, or two inside the width for a long text.
	toast.text:SetWidth(0)
	toast.text:SetText(text or "")
	local action = opts.action
	local actionWidth = 0
	if action then
		toast.action.text:SetText(action[1] or action.label or action.text or "")
		toast.action.text:SetTextColor(E:TokenColor("accent"))
		actionWidth = math.ceil(toast.action.text:GetStringWidth()) + 24
		toast.action:SetWidth(actionWidth)
		local onClick = action[2] or action.onClick
		toast.action:SetScript("OnClick", function()
			toast.token = toast.token + 1
			E:SlideOut(toast, "DOWN")
			if onClick then
				local ok, err = pcall(onClick)
				if not ok then geterrorhandler()(err) end
			end
		end)
	end
	toast.action:SetShown(action ~= nil)
	local limit = opts.maxWidth or math.max(200, (owner:GetWidth() or 0) - 48)
	local width = math.min(math.ceil(toast.text:GetStringWidth()) + 24 + actionWidth, limit)
	toast.text:SetWidth(width - 24 - actionWidth)
	toast:SetWidth(width)
	-- The box grows with its text (two lines, Large text), and a short
	-- notice after a long one gets the normal height back.
	local textHeight = math.ceil(toast.text:GetStringHeight() or 0) + 12
	toast:SetHeight(math.max(E.tokens.height.settingsRow, textHeight))
	E:SlideIn(toast, "UP")
	local time = Kit.ToastTime(text, opts)
	toast.closeAt = GetTime() + time
	C_Timer.After(time, function() ToastCheck(toast, token) end)
	return toast
end

---------------------------------------------------------------------------
-- Tooltips: one look and one anchor rule for every EldoUI control.
-- The tooltip opens right of the control, or left
-- of it when the screen has no room on the right. Title white, text in
-- the secondary gray, click hints one line per action.
--   Kit.AnchorTooltip(owner[, tooltip])   GameTooltip:SetOwner by the rule
--   Kit.Tooltip(frame, title, text)       text may be fn(tooltip)
--   Kit.TooltipHint(tooltip, { "Click", "opens it" }, { "Shift-click", ... })
--   (also E:TooltipHint(tooltip, ...))
---------------------------------------------------------------------------
Kit.TIP_ROOM = 320 -- what a tooltip needs right of its control

function Kit.AnchorTooltip(owner, tooltip)
	tooltip = tooltip or GameTooltip
	local anchor = "ANCHOR_RIGHT"
	local right = owner and owner.GetRight and owner:GetRight()
	if type(right) == "number" and UIParent and owner.GetEffectiveScale then
		local own, base = owner:GetEffectiveScale(), UIParent:GetEffectiveScale()
		local width = UIParent:GetWidth()
		if type(own) == "number" and type(base) == "number" and base > 0 and type(width) == "number" and width > 0
			and right * own / base + Kit.TIP_ROOM > width then
			anchor = "ANCHOR_LEFT"
		end
	end
	tooltip:SetOwner(owner, anchor)
	return anchor
end

-- wrap: true lets a long title fold onto more lines.
function Kit.TipTitle(tooltip, title, wrap)
	-- A secret title is shown as it is, never compared.
	if E:IsSecret(title) or title ~= nil then tooltip:AddLine(title, 1, 1, 1, wrap) end
end

function Kit.TipText(tooltip, text)
	local c = Kit.SECONDARY
	-- A secret text is shown as it is, never compared.
	if not E:IsSecret(text) and (text == nil or text == "") then return end
	tooltip:AddLine(text, c[1], c[2], c[3], true)
end

-- A label and its value on one line: the label in the secondary gray, the
-- value in white or in the color given (r, g, b).
function Kit.TipPair(tooltip, label, value, r, g, b)
	local c = Kit.SECONDARY
	if r == nil then r, g, b = 1, 1, 1 end
	tooltip:AddDoubleLine(label, value, c[1], c[2], c[3], r, g, b)
end

-- The text of a tooltip's last line (nil when it has none, cannot be read,
-- or holds a secret value), and the line count.
local function LastTipLine(tooltip)
	local count = tooltip.NumLines and tooltip:NumLines() or 0
	if type(count) ~= "number" or count < 1 then return nil, 0 end
	local name = tooltip.GetName and tooltip:GetName()
	local line = name and _G[name .. "TextLeft" .. count]
	local text = line and line.GetText and line:GetText()
	if E:IsSecret(text) or type(text) ~= "string" then return nil, count end
	return text, count
end

-- Where each tooltip's last hint block ended, kept here (weak keys) so
-- nothing is written into the game's tooltip frames.
local hintEnds = setmetatable({}, { __mode = "k" })

-- Click hints after a blank line: the action word in white, the rest in
-- the secondary gray, one line per action.
--   Kit.TooltipHint(tooltip, { L["Click"], L["open the calendar"] },
--       { L["Right-click"], L["alarm and stopwatch"] }, cond and { ... } or nil)
-- A nil or false entry is left out, so a hint can depend on a condition.
-- Texts kept in English while the files load are translated here.
-- Hints added right after other hints join their block (no second blank
-- line), and no blank line goes above them when the tooltip already ends
-- with one.
function Kit.TooltipHint(tooltip, ...)
	if not tooltip then return end
	local count, any = select("#", ...), false
	for index = 1, count do
		local hint = select(index, ...)
		if type(hint) == "table" and hint[1] then any = true break end
	end
	if not any then return end
	local last, lines = LastTipLine(tooltip)
	local ended = hintEnds[tooltip]
	local joins = last ~= nil and ended ~= nil and ended.lines == lines and ended.last == last
	if lines > 0 and last ~= " " and last ~= "" and not joins then tooltip:AddLine(" ") end
	local c = Kit.SECONDARY
	for index = 1, count do
		local hint = select(index, ...)
		if type(hint) == "table" and hint[1] then
			tooltip:AddLine(L["%s: %s"]:format("|cffffffff" .. tostring(E:Translate(hint[1])) .. "|r", tostring(E:Translate(hint[2] or ""))), c[1], c[2], c[3], true)
		end
	end
	ended = ended or {}
	ended.last, ended.lines = LastTipLine(tooltip)
	hintEnds[tooltip] = ended
end

function E:TooltipHint(tooltip, ...)
	Kit.TooltipHint(tooltip, ...)
end

-- The same hint as one line of text, for a tooltip built from a string:
--   Kit.HintText(L["Right-click"], L["reset it to the default"])
function Kit.HintText(action, what)
	return E:TokenHex(Kit.SECONDARY) .. L["%s: %s"]:format("|cffffffff" .. tostring(action) .. "|r", tostring(what or "")) .. "|r"
end

-- Tooltip on hover. `text` may be a function(tooltip) that fills it, and
-- `hints` a list of click hints for Kit.TooltipHint:
--   Kit.Tooltip(button, L["Icon"], L["What it is."], { { L["Click"], L["search an icon"] } })
function Kit.Tooltip(frame, title, text, hints)
	frame.kitTipTitle, frame.kitTipText, frame.kitTipHints = title, text, hints
	if frame.kitTipHooked then return end
	frame.kitTipHooked = true
	frame:HookScript("OnEnter", function(self)
		if not self.kitTipTitle and not self.kitTipText and not self.kitTipHints then return end
		Kit.AnchorTooltip(self)
		Kit.TipTitle(GameTooltip, E:Translate(self.kitTipTitle))
		if type(self.kitTipText) == "function" then
			local ok, err = pcall(self.kitTipText, GameTooltip)
			if not ok then geterrorhandler()(err) end
		else
			Kit.TipText(GameTooltip, E:Translate(self.kitTipText))
		end
		if type(self.kitTipHints) == "table" then Kit.TooltipHint(GameTooltip, unpack(self.kitTipHints)) end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- Options links (design decision): Ctrl-click on anything EldoUI draws
-- opens the options window on the page that owns it, scrolled to the
-- matching row, which flashes in the accent. The frame's tooltip says so
-- in one hint line.
--   E:BindOptionsLink(frame, target[, opts])
--     target  { page = "module:Reminders", key = "clickCast" }, or a
--             function(frame) that returns one (nil: no link right now).
--             `key` names the row (its option key), `tab` a tab by its
--             label, `label` the row's name for the hint ("open "%s"").
--     opts    { modifier = "alt" } where the game already uses Ctrl-click
--             on that frame (an item link, a dress-up); the hint names the
--             modifier.
--   E:OptionsLinkHint(tooltip, frame)  adds the hint to a tooltip built by
--             hand (once per tooltip; the bound frame's OnEnter does it).
--   E:IsOptionsLinkClick(frame, button) true for the link's click, so a
--             frame's own OnClick can leave that click alone.
-- Only hooks (HookScript), never a replaced script or a secure attribute.
-- Secure frames are left out: their clicks belong to the game and to the
-- player's own bindings, so they get neither the hint nor the click.
-- Opening waits for the end of combat, as /eui does.
---------------------------------------------------------------------------
local optionLinks = setmetatable({}, { __mode = "k" })
local linkHinted = setmetatable({}, { __mode = "k" })
Kit.MODIFIERS = {
	ctrl = { down = function() return IsControlKeyDown() end, hint = function() return L["Ctrl-click"] end },
	alt = { down = function() return IsAltKeyDown() end, hint = function() return L["Alt-click"] end },
}

local function LinkTarget(frame)
	local link = optionLinks[frame]
	if not link then return nil end
	local target = link.target
	if type(target) == "function" then
		local ok, result = pcall(target, frame)
		if not ok then
			geterrorhandler()(result)
			return nil
		end
		target = result
	end
	if type(target) ~= "table" or type(target.page) ~= "string" then return nil end
	return target, link
end

-- Secure frames (and frames made protected by a secure child) are skipped.
local function IsSecureFrame(frame)
	return E.FrameCheck(frame, "IsProtected")
end

-- Does the frame take clicks? A click-through frame gets no hint.
local function TakesClicks(frame)
	if frame.IsMouseClickEnabled then return frame:IsMouseClickEnabled() and true or false end
	return frame.IsMouseEnabled and frame:IsMouseEnabled() and true or false
end

-- Mouse scripts turn the mouse on by themselves: hooking them must not
-- make a click-through frame catch clicks, so its mouse state is put back.
local function KeepMouse(frame)
	if frame.IsMouseClickEnabled and frame.SetMouseClickEnabled then
		local clicks = frame:IsMouseClickEnabled()
		local motion = frame.IsMouseMotionEnabled and frame:IsMouseMotionEnabled()
		return function()
			frame:SetMouseClickEnabled(clicks and true or false)
			if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(motion and true or false) end
		end
	end
	local enabled = frame.IsMouseEnabled and frame:IsMouseEnabled()
	return function()
		if not enabled and frame.EnableMouse then frame:EnableMouse(false) end
	end
end

-- The same for other helpers that hook mouse scripts (Core/Hideable.lua):
-- restore = Kit.KeepMouse(frame) before the hooks, restore() after them.
Kit.KeepMouse = KeepMouse

function E:BindOptionsLink(frame, target, opts)
	if type(frame) ~= "table" or not frame.HookScript or target == nil then return false end
	if IsSecureFrame(frame) then return false end
	local modifier = opts and opts.modifier or "ctrl"
	if not Kit.MODIFIERS[modifier] then modifier = "ctrl" end
	local link = optionLinks[frame]
	if link then
		link.target, link.modifier = target, modifier
		return true
	end
	optionLinks[frame] = { target = target, modifier = modifier }
	local restore = KeepMouse(frame)
	frame:HookScript("OnEnter", function(hovered)
		if GameTooltip:IsShown() and GameTooltip:GetOwner() == hovered then
			E:OptionsLinkHint(GameTooltip, hovered)
			GameTooltip:Show()
		end
	end)
	frame:HookScript("OnMouseUp", function(clicked, button)
		if E:IsOptionsLinkClick(clicked, button) then E:OpenOptionsLink(clicked) end
	end)
	restore()
	return true
end

function E:OptionsLinkHint(tooltip, frame)
	if not tooltip or IsSecureFrame(frame) or not TakesClicks(frame) then return end
	local target, link = LinkTarget(frame)
	if not target then return end
	local lines = tooltip.NumLines and tooltip:NumLines() or 0
	local done = linkHinted[tooltip]
	if done and done.frame == frame and done.lines == lines then return end
	local what = target.label and L["open \"%s\""]:format(L[target.label]) or L["open its options"]
	Kit.TooltipHint(tooltip, { Kit.MODIFIERS[link.modifier].hint(), what })
	linkHinted[tooltip] = { frame = frame, lines = tooltip.NumLines and tooltip:NumLines() or 0 }
end

function E:IsOptionsLinkClick(frame, button)
	local link = optionLinks[frame]
	if not link or button ~= "LeftButton" then return false end
	local modifiers = Kit.MODIFIERS
	if not modifiers[link.modifier].down() then return false end
	-- Only that one modifier: Ctrl-Shift or Ctrl-Alt stay the frame's own.
	for name, modifier in pairs(modifiers) do
		if name ~= link.modifier and modifier.down() then return false end
	end
	if IsShiftKeyDown() then return false end
	return not IsSecureFrame(frame)
end

-- The link's click: the options window on its page and row (after combat
-- when clicked in combat).
function E:OpenOptionsLink(frame)
	local target = LinkTarget(frame)
	if not target or not self.OpenConfigFromLink then return false end
	GameTooltip:Hide()
	self:OpenConfigFromLink(target.page, target.key, target.tab)
	return true
end

-- Every bound frame and its target right now (for plugins).
function E:OptionsLinks()
	local list = {}
	for frame in pairs(optionLinks) do
		local target = LinkTarget(frame)
		list[#list + 1] = { frame = frame, target = target, modifier = optionLinks[frame].modifier }
	end
	return list
end

---------------------------------------------------------------------------
-- Glyphs: bundled white textures tinted at draw time, never letters.
--   Kit.SetGlyph(texture, name)   name: "chevron-down" / -up / -left /
--                                 -right, "check", "cross", "play", "pause",
--                                 "dot", "copy", "move", "keybind",
--                                 "gear", "profile"
--   Kit.Chevron(parent, dir, size) a chevron texture (dir: down, up, left, right)
---------------------------------------------------------------------------
local TEXTURES = "Interface\\AddOns\\EldoUI\\Media\\Textures\\"
local GLYPHS = {
	check = TEXTURES .. "EldoCheck.tga",
	cross = TEXTURES .. "EldoCross.tga",
	play = TEXTURES .. "EldoPlay.tga",
	pause = TEXTURES .. "EldoPause.tga",
	dot = TEXTURES .. "EldoDot.tga",
	chevron = TEXTURES .. "EldoChevron.tga",
	copy = TEXTURES .. "EldoCopy.tga",
	move = TEXTURES .. "EldoMove.tga",
	keybind = TEXTURES .. "EldoKey.tga",
	gear = TEXTURES .. "EldoGear.tga",
	profile = TEXTURES .. "EldoProfile.tga",
}
Kit.GLYPHS = GLYPHS
-- The chevron file points down; SetRotation turns it counter-clockwise.
local ROTATION = { down = 0, right = math.pi / 2, up = math.pi, left = -math.pi / 2 }

function Kit.SetGlyph(texture, name)
	local dir = type(name) == "string" and name:match("^chevron%-(%a+)$")
	if dir then
		texture:SetTexture(GLYPHS.chevron)
		texture:SetRotation(ROTATION[dir] or 0)
		return true
	end
	if GLYPHS[name] then
		texture:SetTexture(GLYPHS[name])
		texture:SetRotation(0)
		return true
	end
	return false
end

function Kit.IsGlyph(name)
	return type(name) == "string" and (GLYPHS[name] ~= nil or name:match("^chevron%-(%a+)$") ~= nil)
end

-- A glyph inside a text (|T escape), tinted: a check in a menu line
-- instead of the letters [x]. color = { r, g, b } (default secondary).
function Kit.InlineGlyph(name, size, color)
	local file = GLYPHS[name]
	if not file then return "" end
	local c = color or Kit.SECONDARY
	size = size or 12
	return ("|T%s:%d:%d:0:0:32:32:0:32:0:32:%d:%d:%d|t"):format(file, size, size,
		math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

function Kit.Chevron(parent, dir, size, layer)
	local texture = parent:CreateTexture(nil, layer or "OVERLAY")
	texture:SetSize(size or 10, size or 10)
	Kit.SetGlyph(texture, "chevron-" .. (dir or "down"))
	texture:SetVertexColor(unpack(Kit.SECONDARY))
	return texture
end

---------------------------------------------------------------------------
-- Buttons: one flat text button for every
-- EldoUI window. 22 px (26 for footers), label 12, the box is the hit
-- rect; hover lights the edge in the accent with a white overlay, a press
-- tints it, a disabled button dims its text and stops reacting.
--   Kit.Button(parent, text, width, height, onClick, tipTitle, tipText)
--   Kit.Button(parent, text, { width, height, large, kind, size, onClick,
--       tipTitle, tip })
-- kind: "secondary" (default), "primary" (accent edge and a faint accent
-- fill at rest: the one main action of a footer), "danger" (the edge turns
-- the bad color on hover: delete, reset). button.text is the label.
---------------------------------------------------------------------------
local buttonKinds = setmetatable({}, { __mode = "k" }) -- button -> kind

local function PaintButton(button)
	local kind = buttonKinds[button]
	local parts = E:GetSkin(button, "button")
	if not (kind and parts and parts.bd) then return end
	local enabled = not button.IsEnabled or button:IsEnabled()
	local over = enabled and button.kitHover
	local selected = button.kitSelected
	if selected or (kind == "primary" and enabled) then
		parts.bd:SetBackdropBorderColor(Kit.Accent())
	elseif kind == "danger" and over then
		parts.bd:SetBackdropBorderColor(unpack(Kit.BAD))
	elseif over then
		parts.bd:SetBackdropBorderColor(Kit.Accent())
	else
		parts.bd:SetBackdropBorderColor(unpack(E:ControlEdgeColor()))
	end
	if parts.kitTint then
		local r, g, b = Kit.Accent()
		local tint = 0
		if selected then
			tint = E.tokens.pressed
		elseif kind == "primary" and enabled then
			tint = E.tokens.hover.control
		end
		parts.kitTint:SetColorTexture(r, g, b, tint)
	end
end
Kit.PaintButton = PaintButton

-- Give any button the kit's kind paint (used by Kit.Button and by modules
-- that skin their own buttons with E:SkinButton).
function Kit.SetButtonKind(button, kind)
	local parts = E:GetSkin(button, "button") or E:SkinButton(button)
	if not parts then return end
	if not buttonKinds[button] then
		parts.kitTint = button:CreateTexture(nil, "BORDER")
		E:Hairline(parts.kitTint, "inset", 1, button)
		button:HookScript("OnEnter", function(self) self.kitHover = true PaintButton(self) end)
		button:HookScript("OnLeave", function(self) self.kitHover = false PaintButton(self) end)
		button:HookScript("OnEnable", PaintButton)
		button:HookScript("OnDisable", PaintButton)
		E:RegisterThemed(button, PaintButton)
	end
	buttonKinds[button] = kind or "secondary"
	PaintButton(button)
end

-- The selected look on a kit button (the style in use on a style row):
-- the accent edge and the pressed tint, on top of its kind. A grayed-out
-- button keeps it, so the mark still shows which one is in use.
function Kit.SetButtonSelected(button, selected)
	selected = selected and true or false
	if button.kitSelected == selected then return end
	button.kitSelected = selected
	PaintButton(button)
end

-- The kind Kit.SetButtonKind gave a button ("secondary" when none).
function Kit.GetButtonKind(button)
	return buttonKinds[button] or "secondary"
end

-- One button for every EldoUI window. The options form is the one to use:
--   Kit.Button(parent, { text, width, large, kind, onClick, tip, tipTitle, size })
-- width nil sizes the button from its label (it grows with Large text);
-- tip is the tooltip text, or { title, text }. large gives the footer
-- height (height.buttonLarge); never pass a height of your own.
-- secureClick = a function returning one of the game's own buttons
-- (Kit.GameButton): a click then runs that button's click through a
-- secure action button, so the game opens its window itself, and onClick
-- runs after it. Made out of combat only (a plain button otherwise).
-- Older forms still work: Kit.Button(parent, text, width, height, onClick,
-- tipTitle, tipText) and Kit.Button(parent, text, { ... }).
function Kit.Button(parent, text, width, height, onClick, tipTitle, tipText)
	local opts, fit
	if type(text) == "table" then
		opts, fit = text, text.width == nil
		text = opts.text or opts[1]
	elseif type(width) == "table" then
		opts = width
	end
	if opts then
		width, height, onClick, tipTitle, tipText = opts.width, opts.height, opts.onClick, opts.tipTitle, opts.tip
		if type(tipText) == "table" then tipTitle, tipText = tipText[1] or tipText.title, tipText[2] or tipText.text end
		if opts.large and not height then height = E.tokens.height.buttonLarge end
	end
	if type(height) ~= "number" then
		-- An old call that passed the click handler where the height goes.
		if type(height) == "function" and onClick == nil then onClick = height end
		height = nil
	end
	local secure = opts and opts.secureClick
	local target = secure and not InCombatLockdown() and secure() or nil
	local button = CreateFrame("Button", nil, parent, target and "SecureActionButtonTemplate" or nil)
	button:SetSize(width or 100, height or E.tokens.height.button)
	local label = button:CreateFontString(nil, "OVERLAY")
	label:SetPoint("LEFT", 6, 0)
	label:SetPoint("RIGHT", -6, 0)
	label:SetWordWrap(false)
	button:SetFontString(label)
	button.text, button.Text = label, label
	if button.SetPushedTextOffset then button:SetPushedTextOffset(0, 0) end
	E:SkinButton(button, { size = opts and opts.size or E.tokens.size.label, own = true })
	button:SetText(text or "")
	Kit.SetButtonKind(button, opts and opts.kind)
	if target then
		button:RegisterForClicks("AnyUp")
		button:SetAttribute("type1", "click")
		button:SetAttribute("clickbutton", target)
		button.secureTarget = target
		if onClick then button:SetScript("PostClick", onClick) end
	elseif onClick then
		button:SetScript("OnClick", onClick)
	end
	if tipTitle or tipText then Kit.Tooltip(button, tipTitle, tipText) end
	if fit then Kit.FitButton(button, opts.minWidth) end
	-- Large text: the label grows, and the button grows with it.
	button.kitFit = { fit = fit, minWidth = opts and opts.minWidth }
	E:RegisterThemed(button, function(self)
		PaintButton(self)
		Kit.RefitButton(self)
	end)
	Kit.RefitButton(button)
	return button
end

-- The game's own buttons that open a game window: "worldmap" (the zone
-- text above the minimap) and "questlog" (the quest log micro button).
-- A window opened from addon code leaves its state tainted, and the
-- game's later opens of it get protected calls blocked; a secure click on
-- the game's button lets the game open it. nil when the client has no
-- such button.
local GAME_BUTTONS = {
	worldmap = function() local cluster = rawget(_G, "MinimapCluster") return cluster and cluster.ZoneTextButton end,
	questlog = function() return rawget(_G, "QuestLogMicroButton") end,
}
function Kit.GameButton(kind)
	local get = GAME_BUTTONS[kind]
	if not get then return nil end
	local ok, button = pcall(get)
	if ok and type(button) == "table" and type(button.GetObjectType) == "function"
		and not E.FrameCheck(button, "IsForbidden") and button:GetObjectType() == "Button" then
		return button
	end
end

-- True while addon code may not open the world map: in combat, or while
-- the game's map restriction is on (the API wants the restriction type).
function E:MapRestricted()
	if InCombatLockdown() then return true end
	local restricted = C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
	local types = Enum and Enum.AddOnRestrictionType
	if restricted and types and types.Map then
		local ok, active = pcall(restricted, types.Map)
		if ok and not E:IsSecret(active) and active then return true end
	end
	return false
end

-- A zone's level range: the game's map data first, else EldoUI's zone
-- table (Data/Zones.lua), which WoW: Forever needs because its client
-- carries no levels for outdoor zones. Returns low, high and where they
-- came from ("game" or "data"), or nil. The world map, Zone Info and My
-- Adventure all read it here, so they always agree.
function E:ZoneLevelRange(uiMapID)
	if type(uiMapID) ~= "number" then return nil end
	local getLevels = C_Map and C_Map.GetMapLevels
	if getLevels then
		local ok, low, high = pcall(getLevels, uiMapID)
		if ok and not E:IsSecret(low) and not E:IsSecret(high) and type(low) == "number" and type(high) == "number"
			and low > 0 and high >= low then
			return low, high, "game"
		end
	end
	local zone = E.zoneData and E.zoneData.zones and E.zoneData.zones[uiMapID]
	if zone and type(zone.min) == "number" then return zone.min, zone.max or zone.min, "data" end
end

-- Opens the world map on a map (nil: the player's zone) through the game's
-- own request, which the game's map code answers itself, so its later
-- opens stay clean. No other route: false when that request is missing or
-- the map is restricted.
function E:OpenWorldMapAt(uiMapID)
	if self:MapRestricted() then return false end
	local open = C_Map and C_Map.OpenWorldMap
	if type(open) ~= "function" then return false end
	return (pcall(open, uiMapID))
end

-- Large text grows a kit button's label; the button then grows so the
-- label never clips, and goes back to its own size at 100 %. A size the
-- window set later (SetWidth, SetHeight) counts as the button's own size.
function Kit.RefitButton(button)
	local info = button and button.kitFit
	local label = info and button:GetFontString()
	if not label then return end
	-- Never measure a label that may hold a secret value.
	if E.IsSecret and E:IsSecret(label:GetText()) then return end
	-- Take the font objects' new size now.
	local normal = button.GetNormalFontObject and button:GetNormalFontObject()
	if normal then button:SetNormalFontObject(normal) end
	local width, height = button:GetWidth(), button:GetHeight()
	if info.setWidth and width ~= info.setWidth then info.fit = false end
	if info.width == nil or width ~= info.setWidth then info.width = width end
	if info.height == nil or height ~= info.setHeight then info.height = height end
	local scale = E.TextScale and E:TextScale() or 1
	local wantWidth, wantHeight = info.width, info.height
	if info.fit then
		-- Sized from its label at every text size.
		wantWidth = math.max(info.minWidth or 80, math.ceil(label:GetStringWidth() + 24))
	elseif scale > 1 then
		wantWidth = math.max(info.width, math.ceil(label:GetStringWidth() + 12))
	end
	if scale > 1 then
		local _, size = label:GetFont()
		wantHeight = math.max(info.height, math.ceil((size or 12) + 4))
	end
	if wantWidth ~= width then button:SetWidth(wantWidth) end
	if wantHeight ~= height then button:SetHeight(wantHeight) end
	info.setWidth, info.setHeight = wantWidth, wantHeight
end

-- Width a button needs for its label (at least `minimum`).
function Kit.FitButton(button, minimum)
	local label = button:GetFontString()
	button:SetWidth(math.max(minimum or 80, math.ceil((label and label:GetStringWidth() or 60) + 24)))
end

-- A square icon button with an accent hover. `art` is a texture path,
-- file ID, atlas or a glyph name (Kit.SetGlyph); `glyph` is a glyph name
-- too, or a short text fallback when there is no art.
-- opts (8th argument): plain = true keeps the art's own colors (item and
-- spell icons: trimmed, in a 1 px slot, no tint), mono = true draws a
-- colored game icon as a toolbar glyph (trimmed, desaturated, tinted like
-- a glyph: secondary gray, the accent on hover), danger = true turns the
-- glyph the bad color on hover (row delete), options = a target for
-- E:BindOptionsLink (Ctrl-click opens that setting; optionsModifier =
-- "alt" where the game uses Ctrl-click).
-- soft: the tint eases to its new color (a rail button's hover); a
-- theme repaint or the first paint changes it at once.
local function IconTint(button, hover, soft)
	if button.kitPlain then return end
	local r, g, b
	if hover then
		if button.kitDanger then r, g, b = unpack(Kit.BAD) else r, g, b = Kit.Accent() end
	else
		r, g, b = unpack(Kit.SECONDARY)
	end
	if soft and button.kitSoftTint then
		Kit.FadeVertexColor(button.icon, r, g, b)
		if button.glyph then Kit.FadeTextColor(button.glyph, r, g, b) end
		return
	end
	Kit.StopEase(button.icon, "vertexColor")
	button.icon:SetVertexColor(r, g, b)
	if button.glyph then
		Kit.StopEase(button.glyph, "textColor")
		button.glyph:SetTextColor(r, g, b)
	end
end

function Kit.IconButton(parent, size, art, onClick, tipTitle, tipText, glyph, opts)
	opts = opts or {}
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size, size)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("CENTER")
	button.icon = icon
	button.kitPlain, button.kitDanger = opts.plain and true or nil, opts.danger and true or nil
	button.kitMono = (opts.mono and not opts.plain) and true or nil
	if button.kitMono then
		icon:SetSize(size - 4, size - 4)
		E:TrimIcon(icon)
		icon:SetDesaturated(true)
	elseif opts.plain then
		icon:SetSize(size - 2 * E.pixel, size - 2 * E.pixel)
		E:TrimIcon(icon)
		button.slot = CreateFrame("Frame", nil, button)
		button.slot:SetAllPoints()
		button.slot:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
		E:SetTemplate(button.slot)
	else
		local inner = Kit.IsGlyph(art) and math.floor(size * 0.6) or size - 6
		icon:SetSize(inner, inner)
	end
	if Kit.IsGlyph(art) then
		Kit.SetGlyph(icon, art)
	elseif HasAtlas(art) then
		icon:SetAtlas(art)
	elseif art then
		icon:SetTexture(art)
	elseif Kit.IsGlyph(glyph) then
		Kit.SetGlyph(icon, glyph)
		icon:SetSize(math.floor(size * 0.6), math.floor(size * 0.6))
	elseif glyph then
		button.glyph = Kit.Text(button, 14, "CENTER")
		button.glyph:SetPoint("CENTER")
		button.glyph:SetText(glyph)
		icon:Hide()
	end
	-- Change the art later (a play button that turns into pause).
	function button:SetArt(newArt)
		if Kit.IsGlyph(newArt) then Kit.SetGlyph(self.icon, newArt) else self.icon:SetTexture(newArt) end
	end
	IconTint(button, false)
	button:SetScript("OnEnter", function(self) IconTint(self, true, true) end)
	button:SetScript("OnLeave", function(self) IconTint(self, false, true) end)
	-- A disabled one dims like every disabled control (E.tokens.disabledAlpha).
	button:HookScript("OnDisable", function(self) self:SetAlpha(E.tokens.disabledAlpha) end)
	button:HookScript("OnEnable", function(self) self:SetAlpha(1) end)
	if onClick and opts.options then
		-- The options link's click is not the button's own click.
		button:SetScript("OnClick", function(clicked, mouse, ...)
			if E:IsOptionsLinkClick(clicked, mouse) then return end
			onClick(clicked, mouse, ...)
		end)
	elseif onClick then
		button:SetScript("OnClick", onClick)
	end
	Kit.Tooltip(button, tipTitle, tipText)
	if opts.options then E:BindOptionsLink(button, opts.options, opts.optionsModifier and { modifier = opts.optionsModifier }) end
	-- Hover overlay and pressed tint on the whole (square) button, which is
	-- its hit rect; a small one gets the few pixels more (DESIGN.md 3a).
	E:SkinHoverPress(button, nil, opts.plain and button.slot or nil)
	E:PadHitRect(button, 3)
	E:RegisterThemed(button, function(self) IconTint(self, false) end)
	return button
end

-- The row delete every list uses: a small cross
-- glyph in the secondary gray that turns the bad color on hover.
function Kit.RemoveButton(parent, onClick, tipTitle, tipText, size)
	return Kit.IconButton(parent, size or 18, "cross", onClick, tipTitle or L["Remove"], tipText, nil, { danger = true })
end

function Kit.Divider(parent)
	local line = parent:CreateTexture(nil, "ARTWORK")
	E:Hairline(line, "h", 1)
	line:SetColorTexture(unpack(E.tokens.edge.divider))
	return line
end

---------------------------------------------------------------------------
-- Tab strip inside a page or a panel: flat tabs (E:SkinTabs, DESIGN.md 3)
-- in a row, gray text, the open one in accent text with a 2 px accent
-- underline. Place the first tab yourself; the others follow it.
--   local strip = Kit.TabStrip(parent, { { key, label, desc }, ... },
--       onSelect(key)[, { edge = "BOTTOM" | "TOP", size, height, gap }])
--   strip.tabs, strip.selected, strip:Select(key[, silent]), strip:Repaint()
---------------------------------------------------------------------------
function Kit.TabStrip(parent, defs, onSelect, opts)
	opts = opts or {}
	local strip = { tabs = {}, selected = nil }
	local function IsSelected(tab) return tab.kitKey == strip.selected end
	local previous
	for _, def in ipairs(defs or {}) do
		local tab = CreateFrame("Button", nil, parent)
		tab:SetHeight(opts.height or E.tokens.height.tab)
		tab.kitKey = def.key
		-- The skin gives the tab its font objects before the first text.
		E:SkinTabs({ tab }, { edge = opts.edge, size = opts.size or E.tokens.size.body, isSelected = IsSelected })
		tab:SetText(E:Translate(def.label) or def.key)
		local text = tab:GetFontString()
		tab:SetWidth(math.max(64, math.ceil((text and text:GetStringWidth() or 48) + 24)))
		if previous then tab:SetPoint("LEFT", previous, "RIGHT", opts.gap or 4, 0) end
		tab:SetScript("OnClick", function() strip:Select(def.key) end)
		if def.desc then Kit.Tooltip(tab, E:Translate(def.label), E:Translate(def.desc)) end
		previous = tab
		strip.tabs[#strip.tabs + 1] = tab
	end
	function strip:Select(key, silent)
		self.selected = key
		E:UpdateTabs()
		if not silent and onSelect then
			local ok, err = pcall(onSelect, key)
			if not ok then geterrorhandler()(err) end
		end
	end
	function strip:Repaint()
		E:UpdateTabs()
	end
	return strip
end

---------------------------------------------------------------------------
-- Icon slot: a trimmed icon inside a 1 px box;
-- the box takes the item quality color when one is given.
--   local slot = Kit.Icon(parent, size)
--   slot:SetIcon(fileOrPath), slot:SetQuality(quality or nil), slot.icon
---------------------------------------------------------------------------
function Kit.QualityColor(quality)
	if type(quality) ~= "number" then return nil end
	if C_Item and C_Item.GetItemQualityColor then
		local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
		if ok and type(r) == "number" then return r, g, b end
	end
	local colors = rawget(_G, "ITEM_QUALITY_COLORS")
	local c = colors and colors[quality]
	if c then return c.r, c.g, c.b end
end

function Kit.Icon(parent, size)
	local slot = CreateFrame("Frame", nil, parent)
	slot:SetSize(size or 20, size or 20)
	E:SetTemplate(slot)
	slot.icon = slot:CreateTexture(nil, "ARTWORK")
	E:Hairline(slot.icon, "inset", 1, slot)
	E:TrimIcon(slot.icon)
	function slot:SetIcon(texture)
		self.icon:SetTexture(texture)
	end
	function slot:SetQuality(quality)
		local r, g, b = Kit.QualityColor(quality)
		if r and quality and quality >= 2 then
			self:SetBackdropBorderColor(r, g, b)
			self.quality = quality
		else
			self:SetBackdropBorderColor(unpack(E.media.borderColor))
			self.quality = nil
		end
	end
	return slot
end

---------------------------------------------------------------------------
-- Check box with its label; `desc` becomes the tooltip.
--   Kit.Check(parent, label, desc, onClick(on)) -> check; check.label,
--   check:SetEnabledLook(on)
---------------------------------------------------------------------------
function Kit.Check(parent, label, desc, onClick)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	E:SkinCheckBox(check)
	check.label = E:CreateText(check, E.tokens.size.body, "LEFT")
	check.label:SetPoint("LEFT", check, "RIGHT", 4, 0)
	check.label:SetText(label or "")
	-- The label is part of the button: its hit rect runs over the label
	-- (a click on the words toggles), and hovering lights the label too.
	check:SetHitRectInsets(0, -math.max(40, math.ceil(check.label:GetStringWidth()) + 8), 0, 0)
	check:HookScript("OnEnter", function(self)
		if self:IsEnabled() then self.label:SetTextColor(1, 1, 1) end
	end)
	check:HookScript("OnLeave", function(self) self.label:SetTextColor(unpack(Kit.TEXT)) end)
	check.label:SetTextColor(unpack(Kit.TEXT))
	if desc and desc ~= "" then Kit.Tooltip(check, label, desc) end
	check:SetScript("OnClick", function(self)
		local on = self:GetChecked() and true or false
		PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		if onClick then onClick(on) end
	end)
	check.SetEnabledLook = function(self, on)
		self:SetEnabled(on)
		self:SetAlpha(on and 1 or E.tokens.disabledAlpha)
	end
	-- A new label; the hit rect follows its width.
	check.SetLabel = function(self, text)
		self.label:SetText(text or "")
		self:SetHitRectInsets(0, -math.max(40, math.ceil(self.label:GetStringWidth()) + 8), 0, 0)
	end
	return check
end

---------------------------------------------------------------------------
-- Switch: a square on/off track for feature rows. The knob
-- sits left when off and right in an accent track when on.
--   local sw = Kit.Switch(parent, { checked, onChange = fn(on), label,
--       tipTitle, tip, size = "small" })
--   sw:SetChecked(on), sw:GetChecked(), sw:SetEnabledLook(on),
--   sw:SetBlocked(on) (fainter than off: something else holds the job)
-- size "small" is the 24x12 switch of a list row (the options sidebar);
-- its hit rect is padded to 20 px, inside a 24 px row.
---------------------------------------------------------------------------
Kit.SWITCH_WIDTH, Kit.SWITCH_HEIGHT = 36, 18
Kit.SWITCH_SMALL_WIDTH, Kit.SWITCH_SMALL_HEIGHT = 24, 12

function Kit.Switch(parent, opts)
	opts = opts or {}
	local small = opts.size == "small"
	local sw = CreateFrame("Button", nil, parent)
	sw.small = small
	sw:SetSize(small and Kit.SWITCH_SMALL_WIDTH or Kit.SWITCH_WIDTH, small and Kit.SWITCH_SMALL_HEIGHT or Kit.SWITCH_HEIGHT)
	E:SetTemplate(sw, true)
	sw.track = sw:CreateTexture(nil, "BORDER")
	E:Hairline(sw.track, "inset", 1, sw)
	sw.knob = sw:CreateTexture(nil, "ARTWORK")
	local inset = small and 2 or 3
	local knob = (small and Kit.SWITCH_SMALL_HEIGHT or Kit.SWITCH_HEIGHT) - 2 * inset
	sw.knob:SetSize(knob, knob)
	if small then
		E:PadHitRect(sw, 4, 20)
	elseif opts.label then
		sw.label = Kit.Text(sw, E.tokens.size.body, "LEFT")
		sw.label:SetPoint("LEFT", sw, "RIGHT", 8, 0)
		sw.label:SetText(opts.label)
		sw:SetHitRectInsets(0, -math.max(40, math.ceil(sw.label:GetStringWidth()) + 8), -3, -3)
	else
		sw:SetHitRectInsets(0, 0, -3, -3)
	end
	-- The knob slides and the track and knob colors fade when the switch
	-- changes (Kit.Ease); a theme repaint or the first paint is at once.
	-- values: knob offset from the left, track r g b a, knob r g b a.
	local function Draw(v)
		sw.knob:ClearAllPoints()
		sw.knob:SetPoint("LEFT", v[1], 0)
		sw.track:SetColorTexture(v[2], v[3], v[4], v[5])
		sw.knob:SetColorTexture(v[6], v[7], v[8], v[9])
	end
	function sw:Paint()
		local on = self.checked
		local tr, tg, tb, ta = unpack(E.tokens.track)
		local right = (self:GetWidth() or 0) - inset - knob
		local to
		if self.blocked then
			to = { inset, tr, tg, tb, ta * 0.5, 1, 1, 1, 0.2 }
		elseif on then
			local r, g, b = Kit.Accent()
			to = { right, r, g, b, 0.85, 1, 1, 1, 1 }
		else
			local k = Kit.SECONDARY
			to = { inset, tr, tg, tb, ta, k[1], k[2], k[3], 1 }
		end
		local state = (self.blocked and "blocked") or (on and "on") or "off"
		local drawn = self.kitDrawn
		local function Apply(v)
			Draw(v)
			for index = 1, #v do drawn[index] = v[index] end
		end
		-- Only a flip between on and off moves; a lock shows at once.
		if drawn and self.kitState ~= state and state ~= "blocked" and self.kitState ~= "blocked" then
			Kit.Ease(self, "switch", { unpack(drawn) }, to, Apply)
		else
			Kit.StopEase(self, "switch")
			drawn = drawn or {}
			self.kitDrawn = drawn
			Apply(to)
		end
		self.kitState = state
		-- The hover border fades in and out; any other repaint (a click,
		-- a theme change) leaves a running fade alone or draws at once.
		local hover = (self.kitHover and self:IsEnabled()) and true or false
		local r, g, b, a
		if hover then
			r, g, b = Kit.Accent()
		else
			r, g, b, a = unpack(E.media.borderColor)
		end
		if self.kitHoverDrawn ~= nil and self.kitHoverDrawn ~= hover then
			Kit.FadeBorderColor(self, r, g, b, a)
		elseif not Kit.Easing(self, "borderColor") then
			self:SetBackdropBorderColor(r, g, b, a or 1)
		end
		self.kitHoverDrawn = hover
	end
	function sw:SetChecked(on)
		self.checked = on and true or false
		self:Paint()
	end
	function sw:GetChecked() return self.checked end
	function sw:SetBlocked(on)
		self.blocked = on and true or false
		self:Paint()
	end
	function sw:SetEnabledLook(on)
		self:SetEnabled(on)
		self:SetAlpha(on and 1 or E.tokens.disabledAlpha)
	end
	sw:SetScript("OnSizeChanged", function(self)
		if not Kit.Easing(self, "switch") then self:Paint() end
	end)
	sw:SetScript("OnEnter", function(self) self.kitHover = true self:Paint() end)
	sw:SetScript("OnLeave", function(self) self.kitHover = false self:Paint() end)
	sw:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
		PlaySound(self.checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		if opts.onChange then
			local ok, err = pcall(opts.onChange, self.checked)
			if not ok then geterrorhandler()(err) end
		end
	end)
	if opts.tipTitle or opts.tip then Kit.Tooltip(sw, opts.tipTitle or opts.label, opts.tip) end
	sw:SetChecked(opts.checked)
	E:RegisterThemed(sw, sw.Paint)
	return sw
end

---------------------------------------------------------------------------
-- Sliders apply when released (DESIGN.md 5). While the thumb is dragged
-- only the slider, its value text and an optional cheap preview move; the
-- setting is written and applied once, on mouse up. A click on the track,
-- the wheel, the keyboard or a typed value applies at once.
--   local Feed = Kit.SliderCommit(slider, { commit = fn(value),
--       preview = fn(value), live = true })
--   slider:SetScript("OnValueChanged", function(_, v) ... Feed(v) end)
-- live = true applies on every step instead; use it only where applying
-- costs nothing, and say why next to it.
---------------------------------------------------------------------------
local function SafeRun(fn, ...)
	if not fn then return end
	local ok, err = pcall(fn, ...)
	if not ok then geterrorhandler()(err) end
end

function Kit.SliderCommit(slider, opts)
	opts = opts or {}
	local pending, waiting = nil, false
	local function Release(self)
		if not self.kitDragging then return end
		self.kitDragging = false
		if waiting then
			waiting = false
			local value = pending
			pending = nil
			SafeRun(opts.commit, value)
		end
	end
	slider:HookScript("OnMouseDown", function(self, button)
		if button == nil or button == "LeftButton" then self.kitDragging = true end
	end)
	slider:HookScript("OnMouseUp", Release)
	slider:HookScript("OnHide", Release)
	-- The preview draws the first step of a frame at once and the newest
	-- value once more at the end of that frame, so a fast drag that steps
	-- many times in one frame keeps up with the mouse instead of redrawing
	-- the preview for every step.
	local previewValue, previewState = nil, nil -- nil, "drawn" or "queued"
	local function FrameEnd()
		local queued = previewState == "queued"
		previewState = nil
		-- A slider closed within that frame has nothing left to preview.
		if queued and slider:IsVisible() then SafeRun(opts.preview, previewValue) end
	end
	return function(value)
		if opts.preview then
			previewValue = value
			if not previewState then
				previewState = "drawn"
				SafeRun(opts.preview, value)
				C_Timer.After(0, FrameEnd)
			else
				previewState = "queued"
			end
		end
		if slider.kitDragging and not opts.live then
			pending, waiting = value, true
		else
			SafeRun(opts.commit, value)
		end
	end
end

---------------------------------------------------------------------------
-- Slider: a flat horizontal slider on E:SkinSlider
-- (track 8 px, accent fill and thumb).
--   local s = Kit.Slider(parent, { width, min, max, step, value,
--       onChange = fn(value), onPreview = fn(value), live, tipTitle, tip })
--   onChange runs when the slider is released (Kit.SliderCommit);
--   onPreview on every step of a drag; live = true runs onChange on every
--   step too.
--   s:SetValue(v) (no onChange while the code sets it), s:GetValue()
---------------------------------------------------------------------------
function Kit.Slider(parent, opts)
	opts = opts or {}
	local slider = CreateFrame("Slider", nil, parent)
	slider:SetOrientation("HORIZONTAL")
	slider:SetSize(opts.width or 160, 8)
	slider:SetMinMaxValues(opts.min or 0, opts.max or 1)
	slider:SetValueStep(opts.step or 0.01)
	slider:SetObeyStepOnDrag(true)
	slider:EnableMouseWheel(true)
	slider.parts = E:SkinSlider(slider)
	slider.kitSetting = true
	slider:SetValue(opts.value or opts.min or 0)
	slider.kitSetting = false
	local Feed = Kit.SliderCommit(slider, { commit = opts.onChange, preview = opts.onPreview, live = opts.live })
	slider:SetScript("OnValueChanged", function(self, value)
		if self.kitSetting then return end
		Feed(value)
	end)
	slider:SetScript("OnMouseWheel", function(self, delta)
		local low, high = self:GetMinMaxValues()
		self:SetValue(math.max(low, math.min(high, (self:GetValue() or 0) + delta * (opts.step or 0.01))))
	end)
	function slider:SetQuiet(value)
		self.kitSetting = true
		self:SetValue(value)
		self.kitSetting = false
	end
	if opts.tipTitle or opts.tip then Kit.Tooltip(slider, opts.tipTitle, opts.tip) end
	if slider.parts then E:RegisterThemed(slider, function() slider.parts.Paint() end) end
	return slider
end

---------------------------------------------------------------------------
-- Input: a flat edit box with the accent edge while typing
-- and a hint in the dim color while it is empty.
--   local box = Kit.Input(parent, { width, height, numeric, hint,
--       maxLetters, onEnter = fn(text), onChange = fn(text), tipTitle, tip })
---------------------------------------------------------------------------
function Kit.Input(parent, opts)
	opts = opts or {}
	local box = CreateFrame("EditBox", nil, parent)
	box:SetSize(opts.width or 160, opts.height or E.tokens.height.button)
	box:SetAutoFocus(false)
	box:SetTextInsets(6, 6, 0, 0)
	if opts.numeric then box:SetNumeric(true) end
	if opts.maxLetters then box:SetMaxLetters(opts.maxLetters) end
	E:SkinEditBox(box, { left = 0, right = 0, top = 0, bottom = 0, size = E.tokens.size.label })
	box.hint = Kit.Text(box, E.tokens.size.label, "LEFT", "dim")
	box.hint:SetPoint("LEFT", 6, 0)
	box.hint:SetPoint("RIGHT", -6, 0)
	box.hint:SetText(opts.hint or "")
	local function UpdateHint(self)
		self.hint:SetShown((self:GetText() or "") == "" and not self:HasFocus())
	end
	box:HookScript("OnEditFocusGained", UpdateHint)
	box:HookScript("OnEditFocusLost", UpdateHint)
	box:HookScript("OnTextChanged", function(self, user)
		UpdateHint(self)
		if user and opts.onChange then
			local ok, err = pcall(opts.onChange, self:GetText() or "")
			if not ok then geterrorhandler()(err) end
		end
	end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if opts.onEnter then
			local ok, err = pcall(opts.onEnter, self:GetText() or "")
			if not ok then geterrorhandler()(err) end
		end
	end)
	function box:SetHint(text)
		self.hint:SetText(text or "")
		UpdateHint(self)
	end
	if opts.tipTitle or opts.tip then Kit.Tooltip(box, opts.tipTitle, opts.tip) end
	UpdateHint(box)
	return box
end

---------------------------------------------------------------------------
-- Tab order: Tab moves to the next field of a form, Shift+Tab to the one
-- before, skipping fields that are hidden or switched off. A single-line
-- field selects its text on arrival; a multi-line one keeps it.
--   Kit.TabOrder(box1, box2, ...)
---------------------------------------------------------------------------
function Kit.TabOrder(...)
	local boxes = { ... }
	local function Usable(box)
		return box:IsVisible() and not (box.IsEnabled and not box:IsEnabled())
	end
	local function Step(from, dir)
		local count = #boxes
		for i, box in ipairs(boxes) do
			if box == from then
				for k = 1, count - 1 do
					local target = boxes[(i - 1 + dir * k) % count + 1]
					if Usable(target) then
						target:SetFocus()
						if not (target.IsMultiLine and target:IsMultiLine()) then target:HighlightText() end
						return
					end
				end
				return
			end
		end
	end
	for _, box in ipairs(boxes) do
		box:SetScript("OnTabPressed", function(self) Step(self, IsShiftKeyDown() and -1 or 1) end)
	end
	return boxes
end

---------------------------------------------------------------------------
-- Menus: the one menu look of EldoUI. A
-- flat list in the panel look with the theme font, the accent on chosen
-- entries, submenus that open to the side and a scroll bar for long
-- lists. Escape or a click anywhere else closes it; it stays on screen.
--
--   Kit.OpenMenu(owner, items[, opts])   a list from a table of items:
--     { text, checked = bool or fn(item), radio (a dot instead of a check),
--       disabled = bool or fn(item), isTitle, divider, spacer, danger (the
--       bad color: delete, reset), func = fn(item, mouseButton),
--       keepOpen (the list stays and redraws after func),
--       menu = { items } or fn() -> items (a submenu), maxHeight (of that
--       submenu), tooltip = text or fn(tooltip, item),
--       init = fn(row, item) -> width (extra parts on the row) }
--     opts: width (the least width), maxHeight (scrolls past it; the list
--       never grows past the screen), at = "cursor" (at the pointer;
--       default under owner, or at the pointer without one),
--       align = "right" (under owner, right edges lined up)
--   Kit.ContextMenu(owner, generator[, opts])   the same list, described
--     with the calls of the game's MenuUtil.CreateContextMenu, so a menu
--     moves to the kit look by changing that one name. generator(owner,
--     root) fills it:
--       root:CreateTitle(text)
--       root:CreateButton(text[, fn(data, input)][, data])  a button that
--         gets entries of its own is a submenu
--       root:CreateCheckbox(text, isSelected(data), setSelected(data)[, data])
--       root:CreateRadio(text, isSelected(data), setSelected(data)[, data])
--       root:CreateDivider(), root:CreateSpacer()
--     Every entry also takes :SetEnabled(bool or fn), :SetTooltip(
--     fn(tooltip, entry)), :AddInitializer(fn(row, entry) -> width) (the
--     row has row.fontString and row:AttachFrame(frameType)),
--     :SetScrollMode(maxHeight), :SetData(data) and :SetDanger().
--     Checkboxes keep the list open; buttons and radios close it. opts as
--     for Kit.OpenMenu, but at defaults to "cursor" (pass at = "owner" to
--     open under owner). A generator that asks for a call the kit does not
--     have gets the game's own menu instead. Returns the root entry
--     (root:Close() closes the list).
--   Kit.CloseMenu(), Kit.MenuShown(), Kit.GetMenu([level]) (the list, or
--     the submenu of that level: 2 is the first)
--   local dd = Kit.Dropdown(parent, { width, values = list or fn() ->
--       { { value, label }, ... }, get = fn() -> value, set = fn(value),
--       tipTitle, tip, icon = fn(value) -> texture, left, right, top,
--       bottom })
--     `icon` puts a small picture left of each choice (a language's
--     flag), in the list and in the box; a choice without one shows its
--     name only.
--   dd:Refresh() re-reads get(); dd.text, dd.chevron
---------------------------------------------------------------------------
Kit.MENU_ROW = E.tokens.height.button
Kit.MENU_GAP = 9          -- a divider or spacer row
Kit.MENU_MIN_WIDTH = 140
Kit.MENU_TEXT_LEFT = 24   -- where a row's text starts (after the check mark)
Kit.MENU_MAX_WIDTH = 420
Kit.MENU_DEPTH = 4        -- submenus inside submenus
local menus = {}          -- level -> list frame (1 is the list, then its submenus)
local menu                -- menus[1]
local closeHooked = setmetatable({}, { __mode = "k" })

local function SafeCall(fn, ...)
	local ok, result = pcall(fn, ...)
	if not ok then
		geterrorhandler()(result)
		return nil
	end
	return result
end

local function ItemValue(item, field)
	local value = item[field]
	if type(value) == "function" then value = SafeCall(value, item) end
	return value and true or false
end

local function CloseFrom(level)
	for index = #menus, level, -1 do
		local frame = menus[index]
		if frame and frame:IsShown() then frame:Hide() end
	end
end

local OpenLevel

local function BuildLevel(level)
	local frame = CreateFrame("Frame", level == 1 and "EldoUIKitMenu" or nil, UIParent)
	frame.level = level
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:Hide()
	E:SetPanelTemplate(frame)
	frame.area = Kit.ScrollArea(frame, { step = Kit.MENU_ROW * 3 })
	frame.area:SetPoint("TOPLEFT", 0, -4)
	frame.area:SetPoint("BOTTOMRIGHT", 0, 4)
	frame.rows = {}
	menus[level] = frame
	if level > 1 then
		frame:SetScript("OnHide", function(self)
			self.owner = nil
			CloseFrom(level + 1)
		end)
		return frame
	end
	-- A click anywhere else closes the list.
	frame.catcher = CreateFrame("Button", nil, UIParent)
	frame.catcher:SetAllPoints(UIParent)
	frame.catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	frame.catcher:SetFrameLevel(1)
	frame.catcher:RegisterForClicks("AnyUp")
	frame.catcher:SetScript("OnClick", function() frame:Hide() end)
	frame.catcher:Hide()
	frame:SetScript("OnShow", function(self) self.catcher:Show() end)
	frame:SetScript("OnHide", function(self)
		self.catcher:Hide()
		self.owner = nil
		CloseFrom(2)
	end)
	-- Escape closes the list alone; the window it opened from stays. The
	-- game's own Escape (UISpecialFrames) closes every EldoUI window at
	-- once, so it is only the fallback for combat, when the keys are off.
	table.insert(UISpecialFrames, "EldoUIKitMenu")
	frame.keys = Kit.KeyHandler(frame, function(_, key)
		if key ~= "ESCAPE" then return false end
		frame:Hide()
		return true
	end)
	return frame
end

-- row:AttachFrame(frameType): a frame on the row for an initializer (a
-- speaker button, a swatch); hidden again when the row is used for
-- another entry.
local function AttachFrame(row, frameType, template)
	row.attachedUsed = (row.attachedUsed or 0) + 1
	local key = (frameType or "Frame") .. ":" .. tostring(template or "") .. ":" .. row.attachedUsed
	local frame = row.attached[key]
	if not frame then
		frame = CreateFrame(frameType or "Frame", nil, row, template)
		row.attached[key] = frame
	end
	frame:ClearAllPoints()
	frame:Show()
	return frame
end

local function Pick(row, button)
	local item = row.item
	if not item or item.isTitle or item.divider or item.spacer or ItemValue(item, "disabled") then return end
	local frame = row.list
	if item.menu then
		OpenLevel(frame.level + 1, row, item.menu, { maxHeight = item.maxHeight })
		return
	end
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	if item.keepOpen then
		if item.func then SafeCall(item.func, item, button) end
		-- The marks of every open level follow the change.
		for level = 1, #menus do
			local list = menus[level]
			if list:IsShown() and list.Fill then list:Fill() end
		end
		return
	end
	menu:Hide()
	if item.func then SafeCall(item.func, item, button) end
end

local function RowEnter(row)
	local item = row.item
	local frame = row.list
	if not item then return end
	if item.menu and not ItemValue(item, "disabled") then
		OpenLevel(frame.level + 1, row, item.menu, { maxHeight = item.maxHeight })
	else
		CloseFrom(frame.level + 1)
	end
	local tip = item.tooltip
	if tip then
		Kit.AnchorTooltip(row)
		if type(tip) == "function" then
			SafeCall(tip, GameTooltip, item.desc or item)
		else
			GameTooltip:SetText(tostring(tip), 1, 1, 1, 1, true)
		end
		GameTooltip:Show()
	end
end

local function MenuRow(frame, index)
	local row = frame.rows[index]
	if row then return row end
	row = CreateFrame("Button", nil, frame.area.child)
	row.list = frame
	row:SetHeight(Kit.MENU_ROW)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.mark = row:CreateTexture(nil, "OVERLAY")
	row.mark:SetSize(10, 10)
	row.mark:SetPoint("LEFT", 8, 0)
	Kit.SetGlyph(row.mark, "check")
	row.text = Kit.Text(row, E.tokens.size.label, "LEFT")
	row.text:SetPoint("LEFT", Kit.MENU_TEXT_LEFT, 0)
	row.text:SetPoint("RIGHT", -8, 0)
	row.text:SetWordWrap(false)
	row.fontString = row.text
	row.arrow = Kit.Chevron(row, "right", 10)
	row.arrow:SetPoint("RIGHT", -6, 0)
	row.line = Kit.Divider(row)
	row.line:SetPoint("LEFT", 8, 0)
	row.line:SetPoint("RIGHT", -8, 0)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row.selected = row:CreateTexture(nil, "BACKGROUND")
	row.selected:SetAllPoints()
	row.attached = {}
	row.AttachFrame = AttachFrame
	row:SetScript("OnClick", Pick)
	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.rows[index] = row
	return row
end

local function TextWidth(fs)
	local width = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
	return type(width) == "number" and width or 0
end

-- Lays the rows out from frame.items; returns the width they need and
-- their height.
local function FillRows(frame)
	local items = frame.items or {}
	local y, need = 0, 0
	local r, g, b = Kit.Accent()
	for index = 1, math.max(#items, #frame.rows) do
		local item = items[index]
		local row = item and MenuRow(frame, index) or frame.rows[index]
		if item then
			row.item = item
			local gap = item.divider or item.spacer
			local height = gap and Kit.MENU_GAP or Kit.MENU_ROW
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -y)
			row:SetPoint("TOPRIGHT", 0, -y)
			row:SetHeight(height)
			row.line:SetShown(item.divider and true or false)
			-- An initializer may have changed the font, moved the text or added parts.
			if row.savedFont then
				row.text:SetFont(unpack(row.savedFont))
				row.savedFont = nil
			end
			for _, part in pairs(row.attached) do part:Hide() end
			row.attachedUsed = 0
			row.text:SetShown(not gap)
			row.text:SetText(item.text or "")
			local disabled = ItemValue(item, "disabled")
			if item.isTitle then
				Kit.Paint(row.text, "secondary")
			elseif disabled then
				Kit.Paint(row.text, "dim")
			elseif item.danger then
				Kit.Paint(row.text, "bad")
			else
				Kit.Paint(row.text)
			end
			local checked = not gap and ItemValue(item, "checked")
			Kit.SetGlyph(row.mark, item.radio and "dot" or "check")
			row.mark:SetShown(checked)
			row.mark:SetVertexColor(r, g, b)
			row.mark:SetAlpha(disabled and 0.5 or 1)
			row.selected:SetColorTexture(r, g, b, checked and E.tokens.hover.control or 0)
			row.arrow:SetShown(item.menu ~= nil)
			row.text:SetPoint("LEFT", Kit.MENU_TEXT_LEFT, 0)
			row.text:SetPoint("RIGHT", item.menu and -22 or -8, 0)
			row.hover:SetShown(not (disabled or item.isTitle or gap))
			local width = gap and 0 or (TextWidth(row.text) + 24 + (item.menu and 22 or 8))
			if item.init then
				row.savedFont = { row.text:GetFont() }
				local wanted = SafeCall(item.init, row, item)
				if type(wanted) == "number" then width = math.max(width, wanted) end
			end
			need = math.max(need, math.ceil(width))
			row:Show()
			y = y + height
		elseif row then
			row.item = nil
			row:Hide()
		end
	end
	return need, y
end

local function ScreenHeight()
	local height = UIParent:GetHeight()
	return type(height) == "number" and height > 0 and height or 768
end

-- Size and scroll from the rows: the list shows at most maxHeight (and
-- never more than the screen) and scrolls the rest.
local function Fill(frame)
	local need, height = FillRows(frame)
	local opts = frame.opts or {}
	local limit = math.min(opts.maxHeight or math.huge, ScreenHeight() - 40)
	local shown = math.min(height, math.max(Kit.MENU_ROW * 3, limit))
	local scrolls = height > shown + 0.5
	local bar = scrolls and (Kit.SCROLL_WIDTH + 4) or 0
	local width = math.max(opts.width or 0, Kit.MENU_MIN_WIDTH, need)
	width = math.min(width, math.max(Kit.MENU_MAX_WIDTH, opts.width or 0))
	local area = frame.area
	area.scroll:SetPoint("BOTTOMRIGHT", -bar, 0)
	area.child:SetSize(width, math.max(1, height))
	frame:SetSize(width + bar, shown + 8)
	area:Update()
	return width + bar, shown + 8
end

local function Anchor(frame, owner, opts)
	frame:ClearAllPoints()
	local width, height = frame:GetWidth(), frame:GetHeight()
	if frame.level > 1 and owner then
		-- A submenu beside its row, on the left when the right has no room.
		local right = owner:GetRight()
		local screen = UIParent:GetRight()
		if type(right) == "number" and type(screen) == "number" and right + width + 2 > screen then
			frame:SetPoint("TOPRIGHT", owner, "TOPLEFT", -2, 4)
		else
			frame:SetPoint("TOPLEFT", owner, "TOPRIGHT", 2, 4)
		end
		return
	end
	if owner and opts.at ~= "cursor" then
		local left, right = opts.align == "right" and "TOPRIGHT" or "TOPLEFT", opts.align == "right" and "BOTTOMRIGHT" or "BOTTOMLEFT"
		local bottom = owner:GetBottom()
		if type(bottom) == "number" and bottom - height - 2 < 0 then
			-- No room below: open above the owner.
			frame:SetPoint(opts.align == "right" and "BOTTOMRIGHT" or "BOTTOMLEFT", owner, opts.align == "right" and "TOPRIGHT" or "TOPLEFT", 0, 2)
		else
			frame:SetPoint(left, owner, right, 0, -2)
		end
		return
	end
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (x or 0) / scale, (y or 0) / scale)
end

OpenLevel = function(level, owner, items, opts)
	if level > Kit.MENU_DEPTH then return nil end
	local frame = menus[level] or BuildLevel(level)
	if level > 1 and frame:IsShown() and frame.owner == owner then return frame end
	CloseFrom(level + 1)
	if type(items) == "function" then items = SafeCall(items) end
	frame.items = type(items) == "table" and items or {}
	frame.opts = opts or {}
	frame.owner = owner
	frame.Fill = Fill
	Fill(frame)
	Anchor(frame, owner, frame.opts)
	frame.area:SetScroll(0)
	-- Above the click catcher, each submenu above its parent.
	frame:SetFrameLevel(menus[1].catcher:GetFrameLevel() + 10 * level)
	frame:Show()
	frame:Raise()
	E:SnapBorders(frame, true)
	return frame
end

function Kit.OpenMenu(owner, items, opts)
	opts = opts or {}
	menu = menu or BuildLevel(1)
	if menu:IsShown() and menu.owner == owner and owner ~= nil then
		menu:Hide()
		return menu
	end
	if menu:IsShown() then menu:Hide() end
	if owner and owner.HookScript and not closeHooked[owner] then
		-- A list never outlives the window or button it came from.
		closeHooked[owner] = true
		owner:HookScript("OnHide", function(self)
			if menu:IsShown() and menu.owner == self then menu:Hide() end
		end)
	end
	OpenLevel(1, owner, items, opts)
	return menu
end

-- The entries Kit.ContextMenu's generator builds. kind, text and the
-- arguments a, b, c keep the order of the MenuUtil call they came from.
local Entry = {}
local function NewEntry(root, kind, text, a, b, c)
	local entry = { root = root, kind = kind, text = text, a = a, b = b, c = c, children = {} }
	if kind == "CreateButton" then
		entry.data = b
	elseif kind == "CreateCheckbox" or kind == "CreateRadio" then
		entry.data = c
	end
	return setmetatable(entry, Entry)
end
Entry.__index = function(self, key)
	local method = Entry[key]
	if method ~= nil then return method end
	-- A MenuUtil call the kit list does not have: the menu opens as the
	-- game's own instead.
	if type(key) == "string" and key:match("^%u") then
		return function(entry)
			local root = rawget(entry, "root") or entry
			root.unsupported = root.unsupported or key
			return NewEntry(root, "unsupported")
		end
	end
	return nil
end
local function Add(self, kind, text, a, b, c)
	local entry = NewEntry(self.root or self, kind, text, a, b, c)
	self.children[#self.children + 1] = entry
	return entry
end
function Entry:CreateTitle(text) return Add(self, "CreateTitle", text) end
function Entry:CreateButton(text, callback, data) return Add(self, "CreateButton", text, callback, data) end
function Entry:CreateCheckbox(text, isSelected, setSelected, data) return Add(self, "CreateCheckbox", text, isSelected, setSelected, data) end
function Entry:CreateRadio(text, isSelected, setSelected, data) return Add(self, "CreateRadio", text, isSelected, setSelected, data) end
function Entry:CreateDivider() return Add(self, "CreateDivider") end
function Entry:CreateSpacer() return Add(self, "CreateSpacer") end
function Entry:SetEnabled(enabled) self.enabled = enabled end
function Entry:IsEnabled()
	local enabled = self.enabled
	if enabled == nil then return true end
	if type(enabled) == "function" then enabled = SafeCall(enabled, self) end
	return enabled and true or false
end
function Entry:SetTooltip(fn) self.tooltip = fn end
function Entry:AddInitializer(fn)
	self.inits = self.inits or {}
	self.inits[#self.inits + 1] = fn
end
function Entry:SetScrollMode(maxHeight) self.scrollHeight = maxHeight end
function Entry:SetData(data) self.data = data end
function Entry:GetData() return self.data end
function Entry:SetDanger(on) self.danger = on ~= false end
function Entry:GetText() return self.text end
function Entry:SetText(text) self.text = text end
function Entry:HasElements() return #self.children > 0 end
function Entry:Close() Kit.CloseMenu() end

local function EntryItems(parent)
	local items = {}
	for _, entry in ipairs(parent.children) do
		local kind = entry.kind
		local item = { text = entry.text, desc = entry, danger = entry.danger, tooltip = entry.tooltip }
		item.disabled = function() return not entry:IsEnabled() end
		if entry.inits then
			item.init = function(row)
				local width
				for _, fn in ipairs(entry.inits) do
					local wanted = SafeCall(fn, row, entry, menu)
					if type(wanted) == "number" then width = math.max(width or 0, wanted) end
				end
				return width
			end
		end
		if kind == "CreateTitle" then
			item.isTitle = true
		elseif kind == "CreateDivider" then
			item.divider = true
		elseif kind == "CreateSpacer" or kind == "unsupported" then
			item.spacer = true
		elseif kind == "CreateCheckbox" or kind == "CreateRadio" then
			item.radio = kind == "CreateRadio"
			item.keepOpen = kind == "CreateCheckbox"
			item.checked = function()
				return type(entry.a) == "function" and SafeCall(entry.a, entry.data) and true or false
			end
			item.func = function(_, button)
				if type(entry.b) == "function" then entry.b(entry.data, { buttonName = button }) end
			end
		elseif #entry.children > 0 then
			item.menu = function() return EntryItems(entry) end
			item.maxHeight = entry.scrollHeight
		else
			item.func = function(_, button)
				if type(entry.a) == "function" then entry.a(entry.data, { buttonName = button }) end
			end
		end
		items[#items + 1] = item
	end
	return items
end

function Kit.ContextMenu(owner, generator, opts)
	opts = opts or {}
	local root = NewEntry(nil, "root", "root")
	if type(generator) == "function" and not SafeCall(function() generator(owner, root) return true end) then
		return root
	end
	if root.unsupported and MenuUtil and MenuUtil.CreateContextMenu then
		Kit.CloseMenu()
		MenuUtil.CreateContextMenu(owner, generator)
		return root
	end
	if #root.children == 0 then return root end
	Kit.OpenMenu(owner, EntryItems(root), {
		at = opts.at or "cursor", align = opts.align, width = opts.width,
		maxHeight = root.scrollHeight or opts.maxHeight,
	})
	return root
end

function Kit.CloseMenu()
	if menu then menu:Hide() end
end

function Kit.MenuShown()
	return menu ~= nil and menu:IsShown()
end

function Kit.GetMenu(level)
	if level and level > 1 then return menus[level] end
	return menu
end

-- A dropdown of { value, text } entries; texts kept in English while the
-- files load are shown translated.
function Kit.Dropdown(parent, opts)
	opts = opts or {}
	local dd = CreateFrame("Button", nil, parent)
	dd:SetSize(opts.width or 160, E.tokens.height.button)
	E:SetTemplate(dd, true)
	dd.text = Kit.Text(dd, E.tokens.size.label, "LEFT")
	dd.text:SetPoint("LEFT", 8, 0)
	dd.text:SetPoint("RIGHT", -22, 0)
	dd.chevron = Kit.Chevron(dd, "down", 10)
	dd.chevron:SetPoint("RIGHT", -6, 0)
	E:SkinHoverPress(dd, nil, dd)
	-- Shows the picture of `value` on `icon`; false when it has none.
	local function SetIcon(icon, value)
		local ok, path, left, right, top, bottom = pcall(opts.icon, value)
		if not ok or (type(path) ~= "string" and type(path) ~= "number") or icon:SetTexture(path) == false then
			icon:Hide()
			return false
		end
		if left then icon:SetTexCoord(left, right, top, bottom) else icon:SetTexCoord(0, 1, 0, 1) end
		icon:Show()
		return true
	end
	if opts.icon then dd.icon = dd:CreateTexture(nil, "ARTWORK") end
	local function Values()
		local values = opts.values
		if type(values) == "function" then
			local ok, list = pcall(values)
			if not ok then
				geterrorhandler()(list)
				return {}
			end
			values = list
		end
		return type(values) == "table" and values or {}
	end
	function dd:Refresh()
		local current = opts.get and opts.get()
		local label = opts.placeholder or ""
		for _, entry in ipairs(Values()) do
			if entry[1] == current then label = entry[2] end
		end
		self.text:SetText(E:Translate(label))
		if self.icon then
			local size = math.max(12, math.floor(self:GetHeight() - 6))
			self.icon:SetSize(size, size)
			self.icon:SetPoint("LEFT", 8, 0)
			self.text:SetPoint("LEFT", SetIcon(self.icon, current) and (8 + size + 5) or 8, 0)
		end
	end
	dd:HookScript("OnEnter", function(self) self.chevron:SetVertexColor(Kit.Accent()) end)
	dd:HookScript("OnLeave", function(self) self.chevron:SetVertexColor(unpack(Kit.SECONDARY)) end)
	dd:SetScript("OnClick", function(self)
		local current = opts.get and opts.get()
		local items = {}
		for _, entry in ipairs(Values()) do
			local value = entry[1]
			items[#items + 1] = { text = E:Translate(entry[2]), checked = value == current, func = function()
				if opts.set then
					local ok, err = pcall(opts.set, value)
					if not ok then geterrorhandler()(err) end
				end
				self:Refresh()
			end }
			if opts.icon then
				items[#items].init = function(row)
					local holder = row:AttachFrame("Frame")
					local size = math.max(12, math.floor(row:GetHeight() - 8))
					holder:SetSize(size, size)
					holder:SetPoint("LEFT", row, "LEFT", Kit.MENU_TEXT_LEFT, 0)
					holder.icon = holder.icon or holder:CreateTexture(nil, "ARTWORK")
					holder.icon:SetAllPoints()
					if not SetIcon(holder.icon, value) then
						holder:Hide()
						return
					end
					row.text:SetPoint("LEFT", holder, "RIGHT", 6, 0)
					local width = row.text.GetUnboundedStringWidth and row.text:GetUnboundedStringWidth() or row.text:GetStringWidth()
					return math.ceil(tonumber(width) or 0) + Kit.MENU_TEXT_LEFT + size + 6 + 8
				end
			end
		end
		Kit.OpenMenu(self, items, { width = self:GetWidth() })
	end)
	if opts.tipTitle or opts.tip then Kit.Tooltip(dd, opts.tipTitle, opts.tip) end
	dd:Refresh()
	E:RegisterThemed(dd, function(self) self.chevron:SetVertexColor(unpack(Kit.SECONDARY)) end)
	return dd
end

---------------------------------------------------------------------------
-- Scroll bar and scroll area:
-- one thumb for every EldoUI scroll bar, the same one
-- E:SkinScrollBar draws on Blizzard bars. A 2 px track line and a thumb
-- in the look of E.tokens.scrollThumb (color at rest, the accent on hover
-- or drag, its width); hidden when there is nothing to scroll. The bar is
-- scrollThumb.bar wide with 3 px more hit width.
--   Kit.ScrollBar(parent, onValue(value)) -> Slider (vertical)
--   local area = Kit.ScrollArea(parent, { step = 40 })
--   area.scroll (ScrollFrame), area.child (put the content here and set
--   its height), area.bar, area:Update() after the child's height changed,
--   area:ScrollToTop()
---------------------------------------------------------------------------
Kit.SCROLL_WIDTH = E.tokens.scrollThumb.bar    -- the bar's frame (hit area)
Kit.THUMB_WIDTH = E.tokens.scrollThumb.width   -- the drawn thumb
Kit.THUMB_MIN = E.tokens.scrollThumb.min

-- The thumb color (E.tokens.scrollThumb): its color at rest, the accent
-- on hover or drag. The same painter as E:SkinScrollBar's.
function Kit.PaintThumb(thumb, hover)
	E:PaintScrollThumb(thumb, hover)
end

function Kit.ScrollBar(parent, onValue)
	local bar = CreateFrame("Slider", nil, parent)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(Kit.SCROLL_WIDTH)
	bar:SetPoint("TOPRIGHT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", 0, 0)
	bar:SetMinMaxValues(0, 0)
	bar:SetValueStep(1)
	bar:SetObeyStepOnDrag(true)
	bar.track = bar:CreateTexture(nil, "BACKGROUND")
	bar.track:SetPoint("TOP")
	bar.track:SetPoint("BOTTOM")
	E:Hairline(bar.track, "w", 2)
	bar.track:SetColorTexture(unpack(E.tokens.track))
	local thumb = bar:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(Kit.THUMB_WIDTH, Kit.THUMB_MIN)
	Kit.PaintThumb(thumb)
	bar:SetThumbTexture(thumb)
	bar.thumb = thumb
	-- An 8 px bar: 3 px more hit width each side, so the thumb is easy to grab.
	bar:SetHitRectInsets(-3, -3, 0, 0)
	bar:SetScript("OnEnter", function(self) Kit.PaintThumb(self.thumb, true) end)
	bar:SetScript("OnLeave", function(self) if not self.dragging then Kit.PaintThumb(self.thumb) end end)
	bar:SetScript("OnMouseDown", function(self) self.dragging = true Kit.PaintThumb(self.thumb, true) end)
	bar:SetScript("OnMouseUp", function(self)
		self.dragging = false
		Kit.PaintThumb(self.thumb, self:IsMouseOver())
	end)
	bar:SetScript("OnValueChanged", function(_, value)
		if onValue then onValue(math.floor((value or 0) + 0.5)) end
	end)
	E:RegisterThemed(bar, function(self) Kit.PaintThumb(self.thumb, self.dragging) end)
	return bar
end

function Kit.ScrollArea(parent, opts)
	opts = opts or {}
	local area = CreateFrame("Frame", nil, parent)
	local scroll = CreateFrame("ScrollFrame", nil, area)
	scroll:SetPoint("TOPLEFT")
	scroll:SetPoint("BOTTOMRIGHT", -(Kit.SCROLL_WIDTH + 4), 0)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)
	area.scroll, area.child = scroll, child
	area.bar = Kit.ScrollBar(area, function(value)
		if not area.syncing then scroll:SetVerticalScroll(value) end
	end)
	function area:Range()
		return math.max(math.floor((self.child:GetHeight() or 0) - (self.scroll:GetHeight() or 0) + 0.5), 0)
	end
	function area:Update()
		if self.updating then return end
		self.updating = true
		local width = self.scroll:GetWidth() or 0
		if width > 0 and math.abs((self.child:GetWidth() or 0) - width) > 0.5 then self.child:SetWidth(width) end
		local range = self:Range()
		local view, total = self.scroll:GetHeight() or 0, self.child:GetHeight() or 0
		self.syncing = true
		self.bar:SetMinMaxValues(0, range)
		self.bar:SetShown(range > 0)
		local value = math.min(self.scroll:GetVerticalScroll() or 0, range)
		self.scroll:SetVerticalScroll(value)
		self.bar:SetValue(value)
		self.syncing = false
		if total > 0 and view > 0 then
			self.bar.thumb:SetHeight(math.max(Kit.THUMB_MIN, math.floor(view * view / total)))
		end
		self.updating = false
	end
	function area:SetScroll(value)
		local range = self:Range()
		value = math.min(math.max(tonumber(value) or 0, 0), range)
		self.scroll:SetVerticalScroll(value)
		self.syncing = true
		self.bar:SetValue(value)
		self.syncing = false
	end
	function area:ScrollToTop() self:SetScroll(0) end
	area:EnableMouseWheel(true)
	area:SetScript("OnMouseWheel", function(self, delta)
		self:SetScroll((self.scroll:GetVerticalScroll() or 0) - delta * (opts.step or 40))
	end)
	area:SetScript("OnSizeChanged", function(self) self:Update() end)
	child:SetScript("OnSizeChanged", function() area:Update() end)
	return area
end

---------------------------------------------------------------------------
-- Size grip: the one resize grip of every EldoUI window. Three steps in
-- the bottom-right corner, secondary gray at rest, the accent while the
-- pointer is on it or it is dragged. Dragging changes the window's size;
-- the content reflows through its anchors and is never scaled.
--   Kit.SizeGrip(frame, { size = 16, resize = true, minWidth, minHeight,
--       maxWidth, maxHeight, store = fn() -> table, onStart, onStop, tip })
-- resize: the frame becomes resizable and the grip drags its size. The
-- smallest size is minWidth x minHeight (default: the frame's size when
-- the grip is made, so nothing is ever squeezed below its design), the
-- largest maxWidth x maxHeight (default: the screen at the frame's scale).
-- store: the size is kept there as w, h and comes back with
-- grip:Restore(); grip:ResetSize() goes back to the design size.
-- Without resize, onStart(grip) / onStop(grip) do the dragging.
-- bounds = false leaves the resize bounds to the caller.
---------------------------------------------------------------------------
Kit.GRIP_SIZE = E.tokens.grip.size

local function GripStore(opts)
	local store = opts.store
	if type(store) == "function" then
		local ok, value = pcall(store)
		store = ok and value or nil
	end
	return type(store) == "table" and store or nil
end

function Kit.SizeGrip(frame, opts)
	opts = opts or {}
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(opts.size or Kit.GRIP_SIZE, opts.size or Kit.GRIP_SIZE)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetFrameLevel(frame:GetFrameLevel() + 20)
	E:PadHitRect(grip, 2)
	grip.lines = {}
	for i = 1, 3 do
		local line = grip:CreateTexture(nil, "OVERLAY")
		line:SetWidth(i * 4)
		E:Hairline(line, "h", 2)
		-- Short step on top, long one at the bottom.
		line:SetPoint("BOTTOMRIGHT", -2, (3 - i) * 4 + 2)
		grip.lines[i] = line
	end
	function grip:Paint(hover)
		for _, line in ipairs(self.lines) do
			if hover then
				line:SetColorTexture(Kit.Accent())
			else
				local c = Kit.SECONDARY
				line:SetColorTexture(c[1], c[2], c[3], E.tokens.grip.rest)
			end
		end
	end
	grip:Paint(false)

	local designW, designH = frame:GetSize()
	designW, designH = opts.width or designW, opts.height or designH
	local minW = opts.minWidth or (designW and designW > 0 and designW) or 200
	local minH = opts.minHeight or (designH and designH > 0 and designH) or 120
	grip.minWidth, grip.minHeight = minW, minH
	-- The largest size: the given one, else the screen at the frame's scale.
	local function MaxSize()
		local scale = frame:GetScale() or 1
		if scale <= 0 then scale = 1 end
		local screenW = math.floor(((UIParent and UIParent:GetWidth()) or 1920) / scale)
		local screenH = math.floor(((UIParent and UIParent:GetHeight()) or 1080) / scale)
		return math.max(minW, opts.maxWidth or screenW), math.max(minH, opts.maxHeight or screenH)
	end
	local function SetBounds()
		if opts.bounds == false or not frame.SetResizeBounds then return end
		local maxW, maxH = MaxSize()
		frame:SetResizeBounds(minW, minH, maxW, maxH)
	end
	if opts.resize then
		frame:SetResizable(true)
		SetBounds()
	end

	-- Saved size: clamped to the bounds, so a smaller screen never gets a
	-- window larger than itself.
	function grip:Restore()
		local store = GripStore(opts)
		local w, h = store and tonumber(store.w), store and tonumber(store.h)
		if not (w and h) then return false end
		local maxW, maxH = MaxSize()
		frame:SetSize(math.max(minW, math.min(maxW, w)), math.max(minH, math.min(maxH, h)))
		return true
	end
	function grip:ResetSize()
		local store = GripStore(opts)
		if store then store.w, store.h = nil, nil end
		if designW and designH and designW > 0 and designH > 0 then frame:SetSize(designW, designH) end
	end
	function grip:SaveSize()
		local store = GripStore(opts)
		local w, h = frame:GetSize()
		if not (store and w and h) then return end
		w, h = math.floor(w + 0.5), math.floor(h + 0.5)
		-- Nothing saved while it is the design size.
		if designW and designH and math.abs(w - designW) < 1 and math.abs(h - designH) < 1 then
			store.w, store.h = nil, nil
		else
			store.w, store.h = w, h
		end
	end
	function grip:IsResized()
		local store = GripStore(opts)
		return store ~= nil and tonumber(store.w) ~= nil
	end

	grip:SetScript("OnEnter", function(self)
		self:Paint(true)
		if opts.tip ~= false then
			Kit.AnchorTooltip(self)
			Kit.TipTitle(GameTooltip, opts.tipTitle or L["Resize"])
			Kit.TipText(GameTooltip, opts.tip or L["Drag to change the window's size."])
			GameTooltip:Show()
		end
	end)
	grip:SetScript("OnLeave", function(self)
		if not self.sizing then self:Paint(false) end
		GameTooltip:Hide()
	end)
	grip:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then return end
		self.sizing = true
		self:Paint(true)
		GameTooltip:Hide()
		if opts.resize then
			SetBounds()
			frame:StartSizing("BOTTOMRIGHT")
		end
		if opts.onStart then opts.onStart(self) end
	end)
	local function Stop(self)
		if not self.sizing then return end
		self.sizing = false
		if opts.resize then
			frame:StopMovingOrSizing()
			self:SaveSize()
		end
		self:Paint(self:IsMouseOver())
		if opts.onStop then opts.onStop(self) end
	end
	grip:SetScript("OnMouseUp", Stop)
	grip:SetScript("OnHide", Stop)
	E:RegisterThemed(grip, function(self) self:Paint(self.sizing) end)
	return grip
end

-- A small box with a label ("Rare", "Heroic", "Set 1").
function Kit.Chip(parent, text)
	local chip = CreateFrame("Button", nil, parent)
	E:SetTemplate(chip, true)
	chip.text = Kit.Text(chip, 10, "CENTER", "secondary")
	chip.text:SetPoint("CENTER")
	function chip:SetLabel(label, r, g, b)
		self.text:SetText(E:Translate(label) or "")
		if r then self.text:SetTextColor(r, g, b) else Kit.Paint(self.text, "secondary") end
		self:SetSize(math.ceil(self.text:GetStringWidth()) + 10, 16)
	end
	chip:SetLabel(text)
	return chip
end

-- A row of toggle chips, e.g. filters above a list.
-- opts: chips = { { key, label, desc }, ... }, multi (several on at once;
-- default one), selected = { key = true } or a key, onChange(selected, key).
-- bar:GetSelected() -> { key = true }, bar:SetSelected(keys), bar:IsOn(key)
function Kit.ChipBar(parent, opts)
	opts = opts or {}
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(18)
	bar.chips = {}
	bar.selected = {}
	if type(opts.selected) == "table" then
		for key, on in pairs(opts.selected) do bar.selected[key] = on and true or nil end
	elseif opts.selected ~= nil then
		bar.selected[opts.selected] = true
	end
	local function Paint(chip)
		local on = bar.selected[chip.key]
		if on then
			chip.text:SetTextColor(E:TokenColor("accent"))
			chip:SetBackdropBorderColor(Kit.Accent())
		else
			Kit.Paint(chip.text, "secondary")
			chip:SetBackdropBorderColor(unpack(E.media.borderColor))
		end
	end
	function bar:Paint()
		for _, chip in ipairs(self.chips) do Paint(chip) end
	end
	function bar:IsOn(key) return self.selected[key] == true end
	function bar:GetSelected()
		local copy = {}
		for key in pairs(self.selected) do copy[key] = true end
		return copy
	end
	function bar:SetSelected(keys)
		wipe(self.selected)
		if type(keys) == "table" then
			for key, on in pairs(keys) do if on then self.selected[key] = true end end
		elseif keys ~= nil then
			self.selected[keys] = true
		end
		self:Paint()
	end
	function bar:Toggle(key)
		if opts.multi then
			self.selected[key] = not self.selected[key] or nil
		else
			local was = self.selected[key]
			wipe(self.selected)
			if not was then self.selected[key] = true end
		end
		self:Paint()
		if opts.onChange then
			local ok, err = pcall(opts.onChange, self:GetSelected(), key)
			if not ok then geterrorhandler()(err) end
		end
	end
	local x = 0
	for index, data in ipairs(opts.chips or {}) do
		local chip = Kit.Chip(bar, E:Translate(data[2] or data.label))
		chip.key = data[1] or data.key
		chip:SetHeight(18)
		chip:SetPoint("LEFT", bar, "LEFT", x, 0)
		x = x + chip:GetWidth() + 4
		chip:SetScript("OnClick", function(self) bar:Toggle(self.key) end)
		Kit.Tooltip(chip, E:Translate(data[2] or data.label), E:Translate(data[3] or data.desc))
		-- 18 px chips: hover and pressed on the box, 2 px more hit height.
		E:SkinHoverPress(chip)
		E:PadHitRect(chip, 2)
		bar.chips[index] = chip
	end
	bar:SetWidth(math.max(x - 4, 1))
	bar:Paint()
	E:RegisterThemed(bar, bar.Paint)
	return bar
end

---------------------------------------------------------------------------
-- Empty state: an icon, a title, a line of text, optional value lines and
-- up to two buttons.
--   empty:Set(title, text, icon, { { label, onClick, tip }, ... }, { { label, value }, ... })
---------------------------------------------------------------------------
function Kit.EmptyState(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints()
	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetSize(48, 48)
	frame.icon:SetPoint("BOTTOM", frame, "CENTER", 0, 40)
	E:TrimIcon(frame.icon)
	frame.iconBox = CreateFrame("Frame", nil, frame)
	frame.iconBox:SetPoint("TOPLEFT", frame.icon, -E.pixel, E.pixel)
	frame.iconBox:SetPoint("BOTTOMRIGHT", frame.icon, E.pixel, -E.pixel)
	E:SetTemplate(frame.iconBox, true)
	frame.iconBox:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
	frame.title = Kit.Text(frame, 16, "CENTER")
	frame.title:SetPoint("TOP", frame.icon, "BOTTOM", 0, -12)
	frame.text = Kit.Text(frame, E.tokens.size.label, "CENTER", "secondary")
	frame.text:SetPoint("TOP", frame.title, "BOTTOM", 0, -8)
	frame.text:SetWidth(460)
	frame.text:SetWordWrap(true)
	frame.text:SetSpacing(3)
	frame.block = CreateFrame("Frame", nil, frame)
	frame.block:SetSize(420, 1)
	frame.block:SetPoint("TOP", frame.text, "BOTTOM", 0, -12)
	frame.lines = {}
	frame.buttons = {}
	-- The text and value lines take the width of the frame they sit in (at
	-- most 460 and 420, 12 px from each side), so a hint in a narrow list
	-- wraps instead of being clipped by the list.
	function frame:FitWidth()
		local width = self:GetWidth() or 0
		if width <= 0 then return end
		local inner = math.max(width - 24, 40)
		self.text:SetWidth(math.min(460, inner))
		self.block:SetWidth(math.min(420, inner))
		for _, row in ipairs(self.lines) do row.value:SetWidth(math.min(204, math.max(inner / 2 - 6, 20))) end
	end
	frame:SetScript("OnSizeChanged", function(self) self:FitWidth() end)
	function frame:Set(title, text, icon, buttons, lines)
		self.icon:SetTexture(icon or E.media.icon)
		self.title:SetText(E:Translate(title) or "")
		self.text:SetText(E:Translate(text) or "")
		local count = lines and #lines or 0
		for index = 1, math.max(#self.lines, count) do
			local row = self.lines[index]
			local data = lines and lines[index]
			if data and not row then
				row = { label = Kit.Text(self.block, E.tokens.size.label, "RIGHT", "secondary"), value = Kit.Text(self.block, E.tokens.size.label, "LEFT") }
				row.label:SetPoint("TOPRIGHT", self.block, "TOP", -6, -(index - 1) * 18)
				row.value:SetPoint("TOPLEFT", self.block, "TOP", 6, -(index - 1) * 18)
				row.value:SetWidth(204)
				self.lines[index] = row
			end
			if row then
				row.label:SetShown(data ~= nil)
				row.value:SetShown(data ~= nil)
				if data then
					row.label:SetText(E:Translate(data[1]))
					row.value:SetText(data[2])
				end
			end
		end
		self.block:SetHeight(math.max(count * 18, 1))
		self:FitWidth()
		local shown = {}
		for index = 1, math.max(#self.buttons, buttons and #buttons or 0) do
			local data = buttons and buttons[index]
			local button = self.buttons[index]
			if data and not button then
				button = Kit.Button(self, "", 160)
				self.buttons[index] = button
			end
			if button then
				button:SetShown(data ~= nil)
				button:ClearAllPoints()
				if data then
					button:SetText(E:Translate(data[1]))
					Kit.FitButton(button, 120)
					button:SetScript("OnClick", data[2])
					Kit.Tooltip(button, E:Translate(data[1]), E:Translate(data[3]))
					shown[#shown + 1] = button
				end
			end
		end
		if #shown == 1 then
			shown[1]:SetPoint("TOP", self.block, "BOTTOM", 0, -16)
		elseif #shown >= 2 then
			shown[1]:SetPoint("TOPRIGHT", self.block, "BOTTOM", -4, -16)
			shown[2]:SetPoint("TOPLEFT", self.block, "BOTTOM", 4, -16)
		end
		self.shownButtons = shown
	end
	return frame
end

---------------------------------------------------------------------------
-- Virtual lists: only the rows on screen exist, and they are reused.
--
-- Fixed rows (every row one height):
--   Kit.CreateList(parent, { rowHeight = 20 or fn() -> px, create = fn(row),
--     update = fn(row, item, index), gap = 0, empty = { title, text, icon, buttons } })
--   list:SetData(items), list:Refresh(), list:ScrollTo(index), list:ShownRows()
--   list.offset is the number of items above the screen, list.data the items.
--   The wheel scrolls by pixels (opts.step, default two list rows):
--   list:GetScroll(), list:SetScroll(px), list.pixel (the part of the top
--   row scrolled past).
--
-- Variable rows (opts.height given): each item has its own height, and rows
-- are pooled per kind, so chapter headers, ledger rows and cards can share
-- one list. A row that stays on screen while scrolling keeps its content
-- (update runs again only after SetData, Refresh or Relayout).
--   Kit.CreateList(parent, {
--     height = fn(item, index, width) -> px,  -- keep it cheap (Kit.TextHeight helps)
--     kind   = fn(item, index) -> key,        -- optional, default "row"
--     create = fn(row, kind), update = fn(row, item, index, kind),
--     gap = 0, step = px per wheel notch (default two list rows),
--     empty = { title, text, icon, buttons }, onScroll = fn(list, px) })
--   list:SetData(items[, keepScroll]), list:Refresh()
--   list:Relayout()            heights changed (a fold opened); the top row stays put
--   list:ScrollTo(index[, align])  align "nearest" (default), "top" or "center"
--   list:SetScroll(px), list:GetScroll(), list:ContentHeight()
--   list:ItemTop(index), list:IndexAt(y), list:ShownRows(), list:RowFor(index)
--   list.created               rows built so far (reuse keeps it low)
-- With `empty`, an empty state shows while the list has no items
-- (list:SetEmpty(title, text, icon, buttons) changes it).
---------------------------------------------------------------------------
local SCROLL_WIDTH = Kit.SCROLL_WIDTH
local SCROLL_GAP = 4
local THUMB_MIN = Kit.THUMB_MIN

-- The scroll bar of both lists; onValue(value) when it moves.
local function CreateScrollBar(list, onValue)
	return Kit.ScrollBar(list, onValue)
end

local function UpdateEmpty(list, count)
	local empty = list.opts.empty
	if empty and count == 0 then
		if not list.emptyState then
			list.emptyState = Kit.EmptyState(list)
			list.emptyState:SetFrameLevel(list:GetFrameLevel() + 5)
		end
		list.emptyState:Set(empty[1] or empty.title, empty[2] or empty.text, empty[3] or empty.icon, empty[4] or empty.buttons)
		list.emptyState:Show()
	elseif list.emptyState then
		list.emptyState:Hide()
	end
end

local function SetEmpty(list, title, text, icon, buttons)
	list.opts.empty = { title, text, icon, buttons }
	list:Refresh()
end

local function CallUpdate(list, row, item, index, kind)
	if not list.opts.update then return end
	local ok, err = pcall(list.opts.update, row, item, index, kind)
	if not ok then geterrorhandler()(err) end
end

---------------------------------------------------------------------------
-- Variable rows
---------------------------------------------------------------------------
local function CreateVariableList(parent, opts)
	local list = CreateFrame("Frame", nil, parent)
	list.opts = opts
	list.variable = true
	list.data = {}
	list.tops, list.heights = {}, {}
	list.total = 0
	list.scroll = 0
	list.active = {}   -- index -> row on screen
	list.pools = {}    -- kind -> rows waiting to be reused
	list.created = 0
	list.dirty = true
	list:EnableMouseWheel(true)
	list:SetClipsChildren(true)

	list.bar = CreateScrollBar(list, function(value)
		if list.syncing or value == list.scroll then return end
		list.scroll = value
		list:Layout()
		if list.opts.onScroll then
			local ok, err = pcall(list.opts.onScroll, list, value)
			if not ok then geterrorhandler()(err) end
		end
	end)

	local function KindOf(self, item, index)
		if not self.opts.kind then return "row" end
		local ok, kind = pcall(self.opts.kind, item, index)
		if not ok then
			geterrorhandler()(kind)
			return "row"
		end
		return kind or "row"
	end

	local function Release(self, index, row)
		self.active[index] = nil
		row:Hide()
		row.item, row.index = nil, nil
		local pool = self.pools[row.kind]
		if not pool then
			pool = {}
			self.pools[row.kind] = pool
		end
		pool[#pool + 1] = row
	end

	local function Acquire(self, kind)
		local pool = self.pools[kind]
		local row = pool and table.remove(pool)
		if not row then
			row = CreateFrame("Button", nil, self)
			row.list, row.kind = self, kind
			self.created = self.created + 1
			if self.opts.create then
				local ok, err = pcall(self.opts.create, row, kind)
				if not ok then geterrorhandler()(err) end
			end
		end
		row:Show()
		return row
	end

	local function MeasureAt(self, width)
		local gap = self.opts.gap or 0
		local count = #self.data
		local y = 0
		for index = 1, count do
			local ok, height = pcall(self.opts.height, self.data[index], index, width)
			if not ok then
				geterrorhandler()(height)
				height = nil
			end
			height = math.max(math.ceil(tonumber(height) or Kit.ROW_HEIGHT), 0)
			self.tops[index], self.heights[index] = y, height
			y = y + height + (index < count and gap or 0)
		end
		for index = count + 1, #self.tops do
			self.tops[index], self.heights[index] = nil, nil
		end
		self.total = y
	end

	-- Heights at the full width; again at the width left beside the scroll
	-- bar when the content turns out taller than the list.
	function list:Measure()
		local width = math.max(self:GetWidth() or 0, 1)
		local view = self:GetHeight() or 0
		MeasureAt(self, width)
		self.barShown = self.total > view
		if self.barShown then MeasureAt(self, math.max(width - SCROLL_WIDTH - SCROLL_GAP, 1)) end
		self.rowWidth = self.barShown and math.max(width - SCROLL_WIDTH - SCROLL_GAP, 1) or width
		self.measuredWidth, self.measuredView = self:GetWidth() or 0, view
		self.dirty = false
	end

	function list:ContentHeight()
		if self.dirty then self:Measure() end
		return self.total
	end

	function list:MaxScroll()
		return math.max(self.total - (self:GetHeight() or 0), 0)
	end

	function list:GetScroll()
		return self.scroll
	end

	function list:ItemTop(index)
		if self.dirty then self:Measure() end
		return self.tops[index], self.heights[index]
	end

	-- The item at y pixels from the top of the content (the one below when
	-- y falls in a gap); 0 for an empty list.
	function list:IndexAt(y)
		local count = #self.data
		if count == 0 then return 0 end
		local low, high = 1, count
		while low < high do
			local middle = math.floor((low + high + 1) / 2)
			if self.tops[middle] <= y then low = middle else high = middle - 1 end
		end
		if low < count and self.tops[low] + self.heights[low] <= y then low = low + 1 end
		return low
	end

	-- Places the rows for the current scroll: rows that left the screen go
	-- back to their pool, rows that came in are taken from it.
	function list:Layout()
		local view = self:GetHeight() or 0
		local count = #self.data
		local first, last = 1, 0
		if count > 0 and view > 0 then
			first = self:IndexAt(self.scroll)
			last = first
			local bottom = self.scroll + view
			while last < count and self.tops[last + 1] < bottom do last = last + 1 end
		end
		for index, row in pairs(self.active) do
			if index < first or index > last then Release(self, index, row) end
		end
		local right = self.barShown and -(SCROLL_WIDTH + SCROLL_GAP) or 0
		for index = first, last do
			local item = self.data[index]
			local kind = KindOf(self, item, index)
			local row = self.active[index]
			if row and row.kind ~= kind then
				Release(self, index, row)
				row = nil
			end
			local fresh = row == nil
			if fresh then
				row = Acquire(self, kind)
				self.active[index] = row
			end
			row:ClearAllPoints()
			-- TOPRIGHT, not RIGHT: a RIGHT point would also fix the row's middle
			-- and stretch it to the list's middle, overriding its height.
			row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(self.tops[index] - self.scroll))
			row:SetPoint("TOPRIGHT", self, "TOPRIGHT", right, -(self.tops[index] - self.scroll))
			row:SetHeight(math.max(self.heights[index], 1))
			if fresh or self.stale or row.item ~= item then
				row.item, row.index = item, index
				CallUpdate(self, row, item, index, kind)
			end
		end
		self.first, self.last = first, last
		self.stale = false
	end

	local function SyncBar(self)
		local view = self:GetHeight() or 0
		local maximum = self:MaxScroll()
		self.syncing = true
		self.bar:SetMinMaxValues(0, maximum)
		self.bar:SetShown(maximum > 0)
		if self.bar:GetValue() ~= self.scroll then self.bar:SetValue(self.scroll) end
		self.syncing = false
		if self.total > 0 and view > 0 then
			self.bar.thumb:SetHeight(math.max(THUMB_MIN, math.floor(view * view / self.total)))
		end
	end

	function list:Refresh()
		if self.dirty or (self:GetWidth() or 0) ~= self.measuredWidth or (self:GetHeight() or 0) ~= self.measuredView then
			self:Measure()
		end
		self.scroll = math.min(math.max(self.scroll, 0), self:MaxScroll())
		SyncBar(self)
		self.stale = true
		self:Layout()
		UpdateEmpty(self, #self.data)
	end

	function list:SetData(items, keepScroll)
		for index, row in pairs(self.active) do Release(self, index, row) end
		self.data = items or {}
		self.dirty = true
		if not keepScroll then self.scroll = 0 end
		self:Refresh()
	end

	function list:Relayout()
		local index = self.first
		local into = index and self.tops[index] and (self.scroll - self.tops[index]) or 0
		self:Measure()
		if index and self.tops[index] then
			self.scroll = self.tops[index] + math.min(into, self.heights[index])
		end
		self:Refresh()
	end

	function list:SetScroll(px)
		if self.dirty then self:Measure() end
		local value = math.floor(math.min(math.max(tonumber(px) or 0, 0), self:MaxScroll()) + 0.5)
		if value == self.scroll then return end
		self.scroll = value
		SyncBar(self)
		self:Layout()
		if self.opts.onScroll then
			local ok, err = pcall(self.opts.onScroll, self, value)
			if not ok then geterrorhandler()(err) end
		end
	end

	function list:ScrollTo(index, align)
		if self.dirty then self:Measure() end
		local count = #self.data
		if count == 0 then return end
		index = math.min(math.max(math.floor(tonumber(index) or 1), 1), count)
		local top, height = self.tops[index], self.heights[index]
		local view = self:GetHeight() or 0
		local target
		if align == "top" then
			target = top
		elseif align == "center" then
			target = top - (view - height) / 2
		elseif top < self.scroll or height >= view then
			target = top
		elseif top + height > self.scroll + view then
			target = top + height - view
		else
			return
		end
		self:SetScroll(target)
	end

	function list:SetEmpty(title, text, icon, buttons)
		SetEmpty(self, title, text, icon, buttons)
	end

	function list:RowFor(index)
		return self.active[index]
	end

	function list:ShownRows()
		local shown = {}
		for index = self.first or 1, self.last or 0 do
			local row = self.active[index]
			if row then shown[#shown + 1] = row end
		end
		return shown
	end

	list:SetScript("OnMouseWheel", function(self, delta)
		self:SetScroll(self.scroll - delta * (self.opts.step or Kit.ROW_HEIGHT * 2))
	end)
	list:SetScript("OnSizeChanged", function(self) self:Refresh() end)
	-- A new font changes how tall wrapped text is.
	E:RegisterThemed(list, function(self)
		if #self.data > 0 then self:Relayout() end
	end)
	return list
end

---------------------------------------------------------------------------
-- Fixed rows
---------------------------------------------------------------------------
function Kit.CreateList(parent, opts)
	opts = opts or {}
	if opts.height then return CreateVariableList(parent, opts) end
	local list = CreateFrame("Frame", nil, parent)
	list.opts = opts
	list.rows = {}
	list.data = {}
	list.offset = 0
	list:EnableMouseWheel(true)
	list:SetClipsChildren(true)

	-- list.offset counts whole rows above the screen, list.pixel the part
	-- of the next row scrolled past: the wheel scrolls by pixels,
	-- the bar by rows.
	list.pixel = 0
	list.bar = CreateScrollBar(list, function(value)
		if list.syncing then return end
		if value ~= list.offset or list.pixel ~= 0 then
			list.offset, list.pixel = value, 0
			list:Refresh()
		end
	end)

	-- Pixels from the top of the content, and the most it can scroll.
	function list:GetScroll()
		return self.offset * (self:RowHeight() + (self.opts.gap or 0)) + self.pixel
	end

	function list:MaxScroll()
		local pitch = self:RowHeight() + (self.opts.gap or 0)
		return math.max(#self.data * pitch - (self.opts.gap or 0) - (self:GetHeight() or 0), 0)
	end

	function list:SetScroll(px)
		local pitch = math.max(self:RowHeight() + (self.opts.gap or 0), 1)
		local value = math.floor(math.min(math.max(tonumber(px) or 0, 0), self:MaxScroll()) + 0.5)
		local offset, pixel = math.floor(value / pitch), value % pitch
		if offset == self.offset and pixel == self.pixel then return end
		self.offset, self.pixel = offset, pixel
		self:Refresh()
	end

	list:SetScript("OnMouseWheel", function(self, delta)
		self:SetScroll(self:GetScroll() - delta * (self.opts.step or Kit.ROW_HEIGHT * 2))
	end)
	list:SetScript("OnSizeChanged", function(self) self:Refresh() end)

	function list:RowHeight()
		local height = self.opts.rowHeight
		if type(height) == "function" then height = height() end
		return height or Kit.ROW_HEIGHT
	end

	function list:Visible()
		local height = self:GetHeight() or 0
		return math.max(math.floor(height / (self:RowHeight() + (self.opts.gap or 0))), 1)
	end

	function list:SetEmpty(title, text, icon, buttons)
		SetEmpty(self, title, text, icon, buttons)
	end

	function list:SetData(items)
		self.data = items or {}
		self:Refresh()
	end

	function list:Refresh()
		local visible = self:Visible()
		local height = self:RowHeight()
		local gap = self.opts.gap or 0
		local pitch = math.max(height + gap, 1)
		-- The bar steps in rows; the last step reaches the very bottom.
		local maximum = math.max(#self.data - visible, 0)
		local scrollMax = self:MaxScroll()
		if self.offset * pitch + self.pixel > scrollMax then
			self.offset, self.pixel = math.floor(scrollMax / pitch), math.floor(scrollMax % pitch + 0.5)
		end
		if self.offset > maximum then self.offset, self.pixel = maximum, 0 end
		self.syncing = true
		self.bar:SetMinMaxValues(0, maximum)
		self.bar:SetShown(maximum > 0)
		if self.bar:GetValue() ~= self.offset then self.bar:SetValue(self.offset) end
		self.syncing = false
		local right = maximum > 0 and -(SCROLL_WIDTH + SCROLL_GAP) or 0
		-- A row more while one is cut at the top.
		local shown = self.pixel > 0 and visible + 1 or visible
		for index = 1, math.max(shown, #self.rows) do
			local row = self.rows[index]
			local item = self.data[self.offset + index]
			if index <= shown and item ~= nil then
				if not row then
					row = CreateFrame("Button", nil, self)
					row.list = self
					if self.opts.create then self.opts.create(row) end
					self.rows[index] = row
				end
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 0, -(index - 1) * pitch + self.pixel)
				row:SetPoint("TOPRIGHT", self, "TOPRIGHT", right, -(index - 1) * pitch + self.pixel)
				row:SetHeight(height)
				row.item, row.index = item, self.offset + index
				row:Show()
				CallUpdate(self, row, item, self.offset + index)
			elseif row then
				row.item = nil
				row:Hide()
			end
		end
		UpdateEmpty(self, #self.data)
	end

	-- Rows on screen (for refresh code).
	function list:ShownRows()
		local shown = {}
		for _, row in ipairs(self.rows) do
			if row:IsShown() and row.item ~= nil then shown[#shown + 1] = row end
		end
		return shown
	end

	function list:RowFor(index)
		for _, row in ipairs(self.rows) do
			if row:IsShown() and row.item ~= nil and row.index == index then return row end
		end
	end

	function list:ScrollTo(index)
		local visible = self:Visible()
		if index <= self.offset or (index == self.offset + 1 and self.pixel > 0) then
			self.bar:SetValue(math.max(index - 1, 0))
			if self.pixel > 0 then self.offset, self.pixel = math.max(index - 1, 0), 0; self:Refresh() end
		elseif index > self.offset + visible then
			self.bar:SetValue(index - visible)
		end
	end

	return list
end

---------------------------------------------------------------------------
-- Keyboard in EldoUI windows.
--   Kit.KeyHandler(owner, handle)  handle(name, key) -> true when it used
--     the key; name carries the modifiers ("CTRL-F", "SHIFT-UP", "ESCAPE").
-- The keys reach the handler only while `owner` is shown and out of
-- combat. A key it does not use goes on to the game, so movement and key
-- bindings keep working while the window is open. In combat the keyboard
-- is off and the restricted SetPropagateKeyboardInput is never called.
--   Kit.WindowKeys(window, spec)  Ctrl+F and the Esc order for a window
--     with a search box (below)
--   Kit.FocusRing(parent)  an accent edge that marks the keyboard's place
--     in a list (ring:Attach(frame), ring:Attach(nil) hides it)
---------------------------------------------------------------------------
local function KeyName(key)
	local name = key
	if IsShiftKeyDown() then name = "SHIFT-" .. name end
	if IsControlKeyDown() then name = "CTRL-" .. name end
	if IsAltKeyDown() then name = "ALT-" .. name end
	return name
end
Kit.KeyName = KeyName

function Kit.KeyHandler(owner, handle)
	local keys = CreateFrame("Frame", nil, owner)
	keys.handle = handle
	local function Arm()
		if InCombatLockdown() or not owner:IsShown() then
			keys:EnableKeyboard(false)
			return
		end
		keys:EnableKeyboard(true)
		keys:SetPropagateKeyboardInput(true)
	end
	keys.Arm = Arm
	keys:SetScript("OnKeyDown", function(self, key)
		-- Combat started before the event below turned the keyboard off.
		if InCombatLockdown() then return end
		local ok, used = pcall(self.handle, KeyName(key), key)
		if not ok then geterrorhandler()(used) end
		self:SetPropagateKeyboardInput(not (ok and used))
		-- A used key leaves the frame swallowing keys; hand them back right
		-- after, so a binding pressed as combat starts is never lost.
		if ok and used then
			C_Timer.After(0, function()
				if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
			end)
		end
	end)
	keys:RegisterEvent("PLAYER_REGEN_DISABLED")
	keys:RegisterEvent("PLAYER_REGEN_ENABLED")
	keys:SetScript("OnEvent", function(self, event)
		if event == "PLAYER_REGEN_DISABLED" then
			self:EnableKeyboard(false)
		else
			Arm()
		end
	end)
	owner:HookScript("OnShow", Arm)
	owner:HookScript("OnHide", function() keys:EnableKeyboard(false) end)
	Arm()
	return keys
end

-- The standard keys of an EldoUI window, on top of Kit.KeyHandler:
--   Kit.WindowKeys(window, spec)  spec.search: the window's search box, or
--     a function that returns the box to use now (nil when the page shown
--     has none); spec.handle(name, key): the window's own keys, asked
--     first, true when it used the key.
-- Ctrl+F puts the cursor in the search box. Esc clears a search first and
-- only then goes on to the game, which closes the window. Returns the key
-- frame (also window.keys); spec can be changed later through keys.spec.
-- A search box given as a frame (not a function) also gets Kit.SearchEscape.
-- Esc in a focused search box clears it first, then the next Esc closes
-- the window (a focused box gets Esc before any key handler).
function Kit.SearchEscape(box)
	if not box or box.eldoSearchEscape then return box end
	box.eldoSearchEscape = true
	box:HookScript("OnEscapePressed", function(self)
		if (self:GetText() or "") ~= "" then self:SetText("") end
		self:ClearFocus()
	end)
	return box
end

local function SearchBox(spec)
	local box = spec.search
	if type(box) == "function" then box = box() end
	if box and box.IsVisible and box:IsVisible() then return Kit.SearchEscape(box) end
end

function Kit.WindowKeys(window, spec)
	spec = spec or {}
	local keys = Kit.KeyHandler(window, function(name, key)
		local current = window.keys and window.keys.spec or spec
		if current.handle and current.handle(name, key) then return true end
		local box = SearchBox(current)
		if not box then return name == "ESCAPE" and Kit.LayerEscape(window) end
		if name == "CTRL-F" then
			box:SetFocus()
			box:HighlightText()
			return true
		elseif name == "ESCAPE" and strtrim(box:GetText() or "") ~= "" then
			box:SetText("")
			box:ClearFocus()
			return true
		end
		-- Then the front window closes alone (Kit.Layer).
		return name == "ESCAPE" and Kit.LayerEscape(window)
	end)
	if type(spec.search) == "table" then Kit.SearchEscape(spec.search) end
	keys.spec = spec
	window.keys = keys
	return keys
end

function Kit.FocusRing(parent)
	local ring = CreateFrame("Frame", nil, parent)
	ring:EnableMouse(false)
	E:SetTemplate(ring, true)
	local function Paint(self)
		self:SetBackdropColor(0, 0, 0, 0)
		self:SetBackdropBorderColor(Kit.Accent())
	end
	E:RegisterThemed(ring, Paint)
	function ring:Attach(target)
		if not target then
			self:Hide()
			return
		end
		self:SetParent(target)
		self:SetFrameLevel(target:GetFrameLevel() + 10)
		self:ClearAllPoints()
		self:SetAllPoints(target)
		E:SnapBorders(self, true)
		Paint(self)
		self:Show()
	end
	ring:Hide()
	return ring
end

---------------------------------------------------------------------------
-- How tall a text is when wrapped to `width` (for variable list heights).
--   Kit.TextHeight(text, width, size[, opts]) opts: header (header font),
--   spacing (line spacing), lines (cap the number of lines)
-- Measured once on a hidden font string and cached until the theme font
-- changes. Secret text is never measured: it counts as one line.
---------------------------------------------------------------------------
local textHeights, textHeightCount = {}, 0
local measureFrame, measureTexts

function Kit.ClearTextHeights()
	wipe(textHeights)
	textHeightCount = 0
end

function Kit.TextHeight(text, width, size, opts)
	size = size or E.tokens.size.body
	local spacing = opts and opts.spacing or 0
	local lineHeight = size + spacing
	if E:IsSecret(text) then return lineHeight end
	text = text ~= nil and tostring(text) or ""
	if text == "" then return 0 end
	local header = opts and opts.header and true or false
	width = math.max(math.floor(tonumber(width) or 0), 1)
	local key = ("%s:%d:%d:%s:%s"):format(header and "h" or "b", size, width, spacing, text)
	local height = textHeights[key]
	if not height then
		if not measureFrame then
			measureFrame = CreateFrame("Frame", nil, UIParent)
			measureFrame:SetSize(1, 1)
			measureFrame:Hide()
			measureTexts = {}
		end
		local fsKey = (header and "h" or "b") .. size
		local fs = measureTexts[fsKey]
		if not fs then
			fs = E:CreateText(measureFrame, size, "LEFT")
			if header then E:SetHeaderFont(fs, size) end
			fs:SetWordWrap(true)
			measureTexts[fsKey] = fs
		end
		fs:SetSpacing(spacing)
		fs:SetWidth(width)
		fs:SetText(text)
		height = math.max(math.ceil(fs:GetStringHeight() or 0), lineHeight)
		if textHeightCount >= 4000 then
			wipe(textHeights)
			textHeightCount = 0
		end
		textHeights[key] = height
		textHeightCount = textHeightCount + 1
	end
	local cap = opts and opts.lines
	if cap then height = math.min(height, cap * lineHeight) end
	return height
end

---------------------------------------------------------------------------
-- Table: a header of sortable columns over a virtual list.
-- columns: { { key, title, width (nil = fill), align, desc,
--   value = fn(item) (sort and default text), text = fn(item) -> text,
--   color = fn(item) -> r, g, b } }
-- opts: sortKey, sortDown, rowHeight, onClick(item, button, row),
--   onSort(key, down), createRow(row), updateRow(row, item), empty = { title, text, icon }
-- tbl:SetData(items), tbl:SortBy(key, down), tbl:Sorted() -> items in order
---------------------------------------------------------------------------
local HEADER = 22

function Kit.CreateTable(parent, columns, opts)
	opts = opts or {}
	local tbl = CreateFrame("Frame", nil, parent)
	tbl.columns = columns
	tbl.sortKey, tbl.sortDown = opts.sortKey or (columns[1] and columns[1].key), opts.sortDown or false
	tbl.header = CreateFrame("Frame", nil, tbl)
	tbl.header:SetPoint("TOPLEFT")
	tbl.header:SetPoint("TOPRIGHT")
	tbl.header:SetHeight(HEADER)
	local headerLine = Kit.Divider(tbl.header)
	headerLine:SetPoint("BOTTOMLEFT")
	headerLine:SetPoint("BOTTOMRIGHT")
	tbl.headerButtons = {}

	-- Columns before the fill column sit from the left edge, the ones
	-- after it from the right edge, so the fill column takes exactly the
	-- width the others leave, however wide the table is.
	local function Layout(frame, makeCell)
		local x, filled = 4, false
		local cells = {}
		for index, column in ipairs(columns) do
			local cell = makeCell(index, column)
			cell:ClearAllPoints()
			local rest = 0
			for later = index + 1, #columns do rest = rest + (columns[later].width or 0) end
			if filled then
				cell:SetPoint("LEFT", frame, "RIGHT", -(rest + (column.width or 0) + 4), 0)
				cell:SetWidth(math.max((column.width or 0) - 8, 1))
			elseif column.width then
				cell:SetPoint("LEFT", frame, "LEFT", x, 0)
				cell:SetWidth(column.width - 8)
				x = x + column.width
			else
				filled = true
				cell:SetPoint("LEFT", frame, "LEFT", x, 0)
				-- The same 8 px gap before the next column as a fixed cell keeps.
				cell:SetPoint("RIGHT", frame, "RIGHT", -(rest + 4 + (rest > 0 and 8 or 0)), 0)
			end
			cells[index] = cell
		end
		return cells
	end

	local function Sort()
		local column
		for _, c in ipairs(columns) do if c.key == tbl.sortKey then column = c end end
		local sorted = {}
		for index, item in ipairs(tbl.raw or {}) do sorted[index] = item end
		if column then
			local value = column.value or function(item) return item[column.key] end
			table.sort(sorted, function(a, b)
				local va, vb = value(a), value(b)
				if va == vb then return false end
				if va == nil then return false end
				if vb == nil then return true end
				if type(va) ~= type(vb) then va, vb = tostring(va), tostring(vb) end
				if type(va) == "boolean" then va, vb = va and 1 or 0, vb and 1 or 0 end
				if tbl.sortDown then return va > vb end
				return va < vb
			end)
		end
		tbl.sorted = sorted
		tbl.list:SetData(sorted)
		for index, button in ipairs(tbl.headerButtons) do
			local c = columns[index]
			local isSorted = c.key == tbl.sortKey
			button.text:SetText(E:Translate(c.title) or c.key)
			-- The sort direction is a chevron after the title, never a letter.
			button.arrow:SetShown(isSorted)
			button.sortDir = isSorted and (tbl.sortDown and "down" or "up") or nil
			if isSorted then
				Kit.SetGlyph(button.arrow, "chevron-" .. button.sortDir)
				button.arrow:ClearAllPoints()
				local width = math.min(math.ceil(button.text:GetStringWidth() or 0), math.max((button:GetWidth() or 0) - 12, 0))
				if (c.align or "LEFT") == "RIGHT" then
					button.arrow:SetPoint("RIGHT", button, "RIGHT", -(width + 4), 0)
				elseif c.align == "CENTER" then
					button.arrow:SetPoint("LEFT", button, "CENTER", math.floor(width / 2) + 4, 0)
				else
					button.arrow:SetPoint("LEFT", button, "LEFT", width + 4, 0)
				end
				button.text:SetTextColor(E:TokenColor("accent"))
				button.arrow:SetVertexColor(Kit.Accent())
			else
				Kit.Paint(button.text, "secondary")
			end
		end
	end

	function tbl:SortBy(key, down)
		if self.sortKey == key and down == nil then
			self.sortDown = not self.sortDown
		else
			self.sortKey, self.sortDown = key, down or false
		end
		Sort()
		if opts.onSort then opts.onSort(self.sortKey, self.sortDown) end
	end

	-- The header's columns end where the rows end: short of the scroll
	-- bar while it shows, so each title stays over its column.
	tbl.headerColumns = CreateFrame("Frame", nil, tbl.header)
	tbl.headerColumns:SetAllPoints()
	tbl.headerInset = 0
	Layout(tbl.headerColumns, function(index, column)
		local button = CreateFrame("Button", nil, tbl.header)
		button:SetHeight(HEADER)
		button.text = Kit.Text(button, E.tokens.size.small, column.align or "LEFT", "secondary")
		button.text:SetAllPoints()
		button.arrow = Kit.Chevron(button, "up", 8)
		button.arrow:Hide()
		button:SetScript("OnClick", function() tbl:SortBy(column.key) end)
		Kit.Tooltip(button, E:Translate(column.title), E:Translate(column.desc), { { L["Click"], L["sort by this column; click again to reverse"] } })
		tbl.headerButtons[index] = button
		return button
	end)

	tbl.list = Kit.CreateList(tbl, {
		rowHeight = opts.rowHeight,
		empty = opts.empty,
		create = function(row)
			row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			E:SkinRow(row)
			row.cells = Layout(row, function(_, column)
				local fs = Kit.Text(row, E.tokens.size.label, column.align or "LEFT")
				fs:SetWordWrap(false)
				return fs
			end)
			if opts.createRow then opts.createRow(row) end
			row:SetScript("OnClick", function(self, button)
				if opts.onClick and self.item then opts.onClick(self.item, button, self) end
			end)
		end,
		update = function(row, item)
			local bar = row.list and row.list.bar
			local inset = bar and bar:IsShown() and (SCROLL_WIDTH + SCROLL_GAP) or 0
			if inset ~= tbl.headerInset then
				tbl.headerInset = inset
				tbl.headerColumns:SetPoint("BOTTOMRIGHT", tbl.header, "BOTTOMRIGHT", -inset, 0)
			end
			for index, column in ipairs(columns) do
				local fs = row.cells[index]
				local text
				if column.text then
					text = column.text(item)
				else
					local value = column.value and column.value(item) or item[column.key]
					text = value ~= nil and tostring(value) or ""
				end
				fs:SetText(text or "")
				if column.color then fs:SetTextColor(column.color(item)) else Kit.Paint(fs) end
			end
			if opts.updateRow then opts.updateRow(row, item) end
		end,
	})
	tbl.list:SetPoint("TOPLEFT", 0, -HEADER)
	tbl.list:SetPoint("BOTTOMRIGHT")

	function tbl:SetData(items)
		self.raw = items or {}
		Sort()
	end
	function tbl:Sorted() return self.sorted or {} end
	E:RegisterThemed(tbl, function()
		for index, button in ipairs(tbl.headerButtons) do
			if columns[index].key == tbl.sortKey then
				button.text:SetTextColor(E:TokenColor("accent"))
				button.arrow:SetVertexColor(Kit.Accent())
			end
		end
		tbl.list:Refresh()
	end)
	function tbl:Refresh() self.list:Refresh() end
	return tbl
end

---------------------------------------------------------------------------
-- Window parts (DESIGN.md §0a rules 4 to 6), built once here so every
-- module window draws them the same way:
--
--   Kit.FoldDivider(parent, { label, folded, onToggle(folded, divider),
--       content, accent, tip })
--     A centered section name between two thin accent lines, with a fold
--     chevron on the right when it folds (onToggle or content given).
--     content (a frame) hides while folded. accent = true paints the name
--     in the accent: the fold header of a tracker-style list (rule 2).
--     divider:SetFolded(folded[, silent]), divider:IsFolded(),
--     divider:SetLabel(text)
--   Kit.ValueRow(parent, { label, value, kind, tip })
--     The rows under a fold divider: label left, value right.
--     row:SetLabel(text), row:SetValue(text[, kind or { r, g, b }])
--   Kit.ListRow2(parent, opts) / Kit.DressListRow2(row, opts)
--     A two-line list row (friends, guild, alts): icon left, the name in
--     its class or quality color with a status mark, a muted second line,
--     up to three small boxed action buttons on the right.
--     opts: iconSize, actions = { { key, art, glyph, tipTitle, tip,
--     onClick(item, row, mouse), danger, mono } }
--     row:SetRow({ icon, quality, name, class, color, status, statusText,
--     sub, dimmed, hide = { key = true }, disable = { key = true } })
--     A dimmed row (offline, unavailable) draws its icon and text at
--     tokens.disabledAlpha; its actions stay usable.
--     row:SetSelected(selected[, ident]) shows the accent selection tint
--     (it fades in and out; ident names the item the row shows).
--   Kit.TwoLineRowHeight()
--     The row height at the current text size (grows with Large text).
--   Kit.ListRow2Template(listOpts)
--     Kit.CreateList options whose rows are two-line rows; listOpts.row
--     holds the row opts, listOpts.update(row, item) calls row:SetRow.
--     The row height follows Kit.TwoLineRowHeight unless rowHeight is set.
--   Kit.IconRail(parent, { side, width, size, gap, buttons = { { key, art,
--       glyph, tipTitle, tip, onClick, options, mono } } })
--     A slim column of icon-only buttons on a window's edge (chat,
--     minimap); the tooltip names each one, a divider line faces the
--     content. rail.buttons[key], rail:Add(def), rail:Layout() (shown
--     buttons from the top, one under the other), rail:AnyShown().
---------------------------------------------------------------------------
-- soft: the chevron eases to its hover color (the mouse came or went);
-- the first paint and a theme repaint are at once.
local function PaintFold(divider, soft)
	local r, g, b = Kit.Accent()
	local alpha = E.tokens.foldLine
	divider.left:SetColorTexture(r, g, b, alpha)
	divider.right:SetColorTexture(r, g, b, alpha)
	local chevron = divider.chevron
	if chevron then
		local cr, cg, cb = r, g, b
		if not divider.kitHover then cr, cg, cb = unpack(Kit.SECONDARY) end
		if soft == true then
			Kit.FadeVertexColor(chevron, cr, cg, cb)
		else
			Kit.StopEase(chevron, "vertexColor")
			chevron:SetVertexColor(cr, cg, cb)
		end
	end
end

-- The lines run from the edges to the name (or meet in the middle
-- without one); the right one stops short of the chevron.
local function LayoutFold(divider)
	local label, left, right = divider.label, divider.left, divider.right
	local named = (label:GetText() or "") ~= ""
	left:ClearAllPoints()
	right:ClearAllPoints()
	left:SetPoint("LEFT", divider, "LEFT", 0, 0)
	if named then
		left:SetPoint("RIGHT", label, "LEFT", -8, 0)
		right:SetPoint("LEFT", label, "RIGHT", 8, 0)
	else
		left:SetPoint("RIGHT", divider, "CENTER", 0, 0)
		right:SetPoint("LEFT", divider, "CENTER", 0, 0)
	end
	if divider.chevron then
		right:SetPoint("RIGHT", divider.chevron, "LEFT", -6, 0)
	else
		right:SetPoint("RIGHT", divider, "RIGHT", 0, 0)
	end
end

function Kit.FoldDivider(parent, opts)
	opts = opts or {}
	local divider = CreateFrame("Button", nil, parent)
	divider:SetHeight(E.tokens.height.foldRow)
	divider.label = Kit.Text(divider, E.tokens.size.label, "CENTER", opts.accent and "header" or "body")
	divider.label:SetPoint("CENTER")
	divider.left = divider:CreateTexture(nil, "ARTWORK")
	E:Hairline(divider.left, "h", 1)
	divider.right = divider:CreateTexture(nil, "ARTWORK")
	E:Hairline(divider.right, "h", 1)
	divider.content = opts.content
	divider.folded = false
	local foldable = opts.onToggle ~= nil or opts.content ~= nil
	if foldable then
		divider.chevron = Kit.Chevron(divider, "down", 10)
		divider.chevron:SetPoint("RIGHT", divider, "RIGHT", -4, 0)
	end

	function divider:SetLabel(text)
		self.label:SetText(E:Translate(text) or "")
		LayoutFold(self)
	end

	function divider:IsFolded()
		return self.folded
	end

	function divider:SetFolded(folded, silent)
		self.folded = folded and true or false
		if self.chevron then Kit.SetGlyph(self.chevron, self.folded and "chevron-right" or "chevron-down") end
		if self.content then self.content:SetShown(not self.folded) end
		if not silent and opts.onToggle then
			local ok, err = pcall(opts.onToggle, self.folded, self)
			if not ok then geterrorhandler()(err) end
		end
	end

	-- The whole row is the hit rect of a folding divider; the name and
	-- the chevron light up in the accent while the mouse is over it.
	if foldable then
		divider:SetScript("OnClick", function(self) self:SetFolded(not self.folded) end)
		divider:SetScript("OnEnter", function(self) self.kitHover = true PaintFold(self, true) end)
		divider:SetScript("OnLeave", function(self) self.kitHover = false PaintFold(self, true) end)
	end
	if opts.tip then
		Kit.Tooltip(divider, opts.label, opts.tip, foldable and { { L["Click"], L["fold or unfold"] } } or nil)
	elseif not foldable then
		divider:EnableMouse(false)
	end
	E:RegisterThemed(divider, PaintFold)
	divider:SetLabel(opts.label)
	divider:SetFolded(opts.folded, true)
	PaintFold(divider)
	return divider
end

function Kit.ValueRow(parent, opts)
	opts = opts or {}
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(E.tokens.height.row)
	row.value = Kit.Text(row, E.tokens.size.label, "RIGHT")
	row.value:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.label = Kit.Text(row, E.tokens.size.label, "LEFT")
	row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.label:SetPoint("RIGHT", row.value, "LEFT", -8, 0)

	function row:SetLabel(text)
		self.label:SetText(E:Translate(text) or "")
	end

	-- kind: a text kind of Kit.Paint ("body", "secondary", "good", "warn",
	-- "bad" ...) or { r, g, b } (a class or quality color).
	function row:SetValue(text, kind)
		self.value:SetText(text or "")
		if type(kind) == "table" and type(kind[1]) == "number" then
			self.value:SetTextColor(kind[1], kind[2], kind[3])
		else
			painted[self.value] = kind or "body"
			Kit.Paint(self.value, kind)
		end
	end

	if opts.tip then
		row:EnableMouse(true)
		Kit.Tooltip(row, opts.label, opts.tip)
	end
	row:SetLabel(opts.label)
	row:SetValue(opts.value, opts.kind)
	return row
end

-- Where the name, its status mark and the second line may run: from the
-- icon to the first shown action button.
local function LayoutRow2(row)
	local right = 6
	for index = #row.actions, 1, -1 do
		local button = row.actions[index]
		button:ClearAllPoints()
		if button:IsShown() then
			button:SetPoint("RIGHT", row, "RIGHT", -right, 0)
			right = right + button:GetWidth() + 4
		end
	end
	local room = math.max((row:GetWidth() or 0) - row.kitTextLeft - right - 4, 1)
	row.sub:SetWidth(room)
	local status = row.status:GetText() or ""
	local statusWidth = status ~= "" and math.ceil(row.status:GetStringWidth() + 6) or 0
	local want = math.ceil(row.name:GetStringWidth() + 1)
	row.name:SetWidth(math.max(math.min(want, room - statusWidth), 1))
end

local function NameColor(data)
	if type(data.color) == "table" and type(data.color[1]) == "number" then return data.color[1], data.color[2], data.color[3] end
	if type(data.class) == "string" and E.GetClassColor then
		local r, g, b = E:GetClassColor(data.class)
		if type(r) == "number" then return r, g, b end
	end
	if data.quality ~= nil then return Kit.QualityColor(data.quality) end
end

local function Row2PaintSelect(row, selected)
	if selected then
		local r, g, b = Kit.Accent()
		row.select:SetColorTexture(r, g, b, E.tokens.pressed)
	end
	row.select:SetShown(selected and true or false)
end

function Kit.DressListRow2(row, opts)
	opts = opts or {}
	local iconSize = opts.iconSize or (E.tokens.height.twoLineRow - 8)
	row.kitTextLeft = 4 + iconSize + 8
	local hover = E:SkinHoverPress(row)
	if hover then hover:SetColorTexture(1, 1, 1, E.tokens.hover.row) end
	row.icon = Kit.Icon(row, iconSize)
	row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.name = Kit.Text(row, E.tokens.size.body, "LEFT")
	row.name:SetPoint("BOTTOMLEFT", row, "LEFT", row.kitTextLeft, 1)
	row.status = Kit.Text(row, E.tokens.size.small, "LEFT", "secondary")
	row.status:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
	row.sub = Kit.Text(row, E.tokens.size.small, "LEFT", "secondary")
	row.sub:SetPoint("TOPLEFT", row, "LEFT", row.kitTextLeft, -2)
	-- The selection look: an accent tint under the row that fades in and
	-- out (Kit.SoftSelect). ident names the item, so a row reused for
	-- another item changes at once.
	row.select = row:CreateTexture(nil, "BACKGROUND", nil, -5)
	row.select:SetAllPoints()
	row.select:Hide()
	function row:SetSelected(selected, ident)
		Kit.SoftSelect(self, selected, Row2PaintSelect, { self.select }, ident)
	end
	row.actions, row.actionByKey = {}, {}
	local size = E.tokens.height.button - 2
	for index = 1, math.min(#(opts.actions or {}), 3) do
		local def = opts.actions[index]
		local button = Kit.IconButton(row, size, def.art, function(_, mouse)
			if def.onClick then def.onClick(row.item, row, mouse) end
		end, def.tipTitle, def.tip, def.glyph, { danger = def.danger, mono = def.mono })
		-- Small boxed buttons: a 1 px box behind the glyph.
		button.box = CreateFrame("Frame", nil, button)
		button.box:SetAllPoints()
		button.box:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
		E:SetTemplate(button.box)
		button.kitKey = def.key or index
		row.actions[index] = button
		row.actionByKey[button.kitKey] = button
	end

	function row:SetRow(data)
		data = data or {}
		self.icon:SetIcon(data.icon)
		self.icon:SetQuality(data.quality)
		self.name:SetText(data.name or "")
		local r, g, b = NameColor(data)
		if r then
			self.name:SetTextColor(r, g, b)
		else
			Kit.Paint(self.name, "body")
		end
		-- The status mark carries a shape, never only a color.
		if data.status and data.statusText then
			self.status:SetText(E:StatusText(data.status, data.statusText))
		else
			self.status:SetText(data.statusText or "")
		end
		self.sub:SetText(data.sub or "")
		self.dimmed = data.dimmed and true or false
		local alpha = self.dimmed and E.tokens.disabledAlpha or 1
		for _, part in ipairs({ self.icon, self.name, self.status, self.sub }) do part:SetAlpha(alpha) end
		for _, button in ipairs(self.actions) do
			local key = button.kitKey
			button:SetShown(not (data.hide and data.hide[key]))
			local off = data.disable and data.disable[key]
			if off then button:Disable() else button:Enable() end
			button:SetAlpha(off and E.tokens.disabledAlpha or 1)
		end
		LayoutRow2(self)
	end

	row:HookScript("OnSizeChanged", LayoutRow2)
	row.kitRow2 = true
	return row
end

function Kit.ListRow2(parent, opts)
	local row = CreateFrame("Button", nil, parent) -- lint: no-click ok (DressListRow2 adds the hover; the caller sets the click)
	row:SetHeight(Kit.TwoLineRowHeight())
	return Kit.DressListRow2(row, opts)
end

-- The two-line row height at the current text size: it grows with
-- General > Accessibility > Large text so both lines keep their room.
function Kit.TwoLineRowHeight()
	return math.ceil(E.tokens.height.twoLineRow * (E.TextScale and E:TextScale() or 1))
end

function Kit.ListRow2Template(listOpts)
	listOpts = listOpts or {}
	local out = {}
	for key, value in pairs(listOpts) do out[key] = value end
	out.row = nil
	-- A list re-reads a function on each refresh, so a new text size
	-- reflows the rows.
	out.rowHeight = listOpts.rowHeight or Kit.TwoLineRowHeight
	out.create = function(row)
		Kit.DressListRow2(row, listOpts.row)
		if listOpts.create then listOpts.create(row) end
	end
	return out
end

function Kit.IconRail(parent, opts)
	opts = opts or {}
	local T = E.tokens.rail
	local rail = CreateFrame("Frame", nil, parent)
	rail:SetWidth(opts.width or T.width)
	rail.kitSide = opts.side == "RIGHT" and "RIGHT" or "LEFT"
	rail.kitSize, rail.kitGap = opts.size or T.button, opts.gap or T.gap
	-- The divider line faces the content: a rail on the left edge of a
	-- box has it on its right side.
	rail.line = rail:CreateTexture(nil, "ARTWORK")
	local edge = rail.kitSide == "LEFT" and "RIGHT" or "LEFT"
	rail.line:SetPoint("TOP" .. edge)
	rail.line:SetPoint("BOTTOM" .. edge)
	E:Hairline(rail.line, "w", 1)
	rail.line:SetColorTexture(unpack(E.tokens.edge.divider))
	rail.buttons, rail.order = {}, {}

	function rail:Add(def)
		local button = Kit.IconButton(self, self.kitSize, def.art, def.onClick, def.tipTitle, def.tip, def.glyph,
			{ options = def.options, mono = def.mono, danger = def.danger })
		-- The glyph's hover tint eases like the hover overlay does.
		button.kitSoftTint = true
		button.kitKey = def.key or (#self.order + 1)
		self.order[#self.order + 1] = button
		self.buttons[button.kitKey] = button
		return button
	end

	function rail:Layout()
		local anchor
		for _, button in ipairs(self.order) do
			button:ClearAllPoints()
			if anchor then
				button:SetPoint("TOP", anchor, "BOTTOM", 0, -self.kitGap)
			else
				button:SetPoint("TOP", self, "TOP", 0, -self.kitGap)
			end
			if button:IsShown() then anchor = button end
		end
	end

	function rail:AnyShown()
		for _, button in ipairs(self.order) do
			if button:IsShown() then return true end
		end
		return false
	end

	for _, def in ipairs(opts.buttons or {}) do rail:Add(def) end
	rail:Layout()
	return rail
end

-- The window shell (E.WindowKit) offers the same parts.
do
	local WK = E.WindowKit
	if WK then
		WK.FoldDivider = Kit.FoldDivider
		WK.ValueRow = Kit.ValueRow
		WK.ListRow2 = Kit.ListRow2
		WK.ListRow2Template = Kit.ListRow2Template
		WK.IconRail = Kit.IconRail
	end
end

---------------------------------------------------------------------------
-- Tabbed window
--
--   +--------------------------------------------------------------+
--   | Title   Tab  Tab  Tab                        [search] ? gear x|
--   |--------------------------------------------------------------|
--   |                 the open tab (or its empty state)            |
--   |--------------------------------------------------------------|
--   | footer text                                                // |
--   +--------------------------------------------------------------+
--
-- local win = UIKit.CreateTabbedWindow({
--   name = "EldoUICharacters",           -- global name (Esc closes it)
--   title = L["Characters"],
--   width = 920, height = 600,
--   minWidth, minHeight,                   -- smallest size (default: width, height)
--   store = function() return savedTable end, -- keeps { x, y, scale, w, h }
--   tabs = { { key, title, desc, count = fn, hidden = fn,
--              create = fn(content) -> frame, show = fn(frame, arg),
--              hide = fn(frame), refresh = fn(frame, changed),
--              empty = fn(frame) -> title, text, icon, buttons } },
--   help = { text = string or fn(tooltip), onClick = fn },
--   options = target,                   -- an E:BindOptionsLink target: Ctrl-click on the help button
--                                          -- (or the title bar) opens it
--   search = { tip = text, onSearch = fn(text) },
--   footer = fn() -> text,
--   transparent = bool or fn,
--   hideInCombat = true,                   -- hides in combat, back after it
--   backAfterCombat = false,               -- hidden at a pull, stays closed after it
--   sound = fn() -> bool,                  -- book sounds on open, close, page
--   keys = fn(name, key) -> used,          -- the window's own keys (Kit.WindowKeys)
-- })
-- Keys: Ctrl+F puts the cursor in the search box, Esc clears a search and
-- then closes the window, Ctrl+Tab and Ctrl+Shift+Tab switch tabs.
-- The corner grip resizes the window (the open tab reflows), Ctrl+mouse
-- wheel on the title bar zooms it; ResetPosition puts both back.
-- win:Open(key, arg), win:Close(), win:Toggle(), win:IsOpen(), win:Current(),
-- win:SetTabs(tabs), win:Refresh(changed), win:UpdateFooter(), win:ResetPosition(), win:ResetSize(),
-- win:CycleTab(step) (1 next, -1 previous)
-- Tabs that are not built have no tab (no placeholder pages).
---------------------------------------------------------------------------
local TOPBAR, FOOTER, PAD = 36, 24, 8
local SCALE_MIN, SCALE_MAX = 0.7, 1.5
local SOUND_OPEN, SOUND_CLOSE, SOUND_PAGE = "kit:IG_SPELLBOOK_OPEN", "kit:IG_SPELLBOOK_CLOSE", "kit:IG_ABILITY_PAGE_TURN"

local Window = {}

local function Clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

local function Call(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok then
		geterrorhandler()(a)
		return
	end
	return a, b, c, d
end

local function Value(option, ...)
	if type(option) == "function" then return Call(option, ...) end
	return option
end

function Window:Store()
	local store = Value(self.opts.store)
	return type(store) == "table" and store or self.memory
end

function Window:Scale()
	return Clamp(tonumber(self:Store().scale) or 1, SCALE_MIN, SCALE_MAX)
end

-- The frame's own scale: the player's zoom on top of one window unit per
-- screen pixel (E:WindowScale), shrunk to fit the screen.
function Window:EffectiveScale(user)
	return E:WindowScale(user or self:Scale(), self.opts.width, self.opts.height)
end

function Window:ApplyPosition()
	local frame = self.frame
	if not frame then return end
	local scale = self:EffectiveScale()
	frame:SetScale(scale)
	-- The saved size (the grip), never larger than the screen.
	if frame.grip and not frame.grip:Restore() then frame:SetSize(self.opts.width, self.opts.height) end
	-- 1-pixel edges stay one screen pixel at this scale (DESIGN.md 3a).
	if frame.kitSnapped ~= scale then
		frame.kitSnapped = scale
		E:SnapBorders(frame)
	end
	frame:ClearAllPoints()
	local store = self:Store()
	if tonumber(store.x) and tonumber(store.y) then
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", store.x / scale, store.y / scale)
	else
		frame:SetPoint("TOP", UIParent, "TOP", 0, -140 / scale)
	end
end

function Window:SavePosition()
	local frame = self.frame
	if not frame then return end
	local scale = frame:GetScale()
	local left, top = frame:GetLeft(), frame:GetTop()
	if not left or not top then return end
	local store = self:Store()
	store.x, store.y = math.floor(left * scale + 0.5), math.floor(top * scale + 0.5)
end

function Window:ResetPosition()
	local store = self:Store()
	store.x, store.y, store.scale, store.w, store.h = nil, nil, nil, nil, nil
	self:ApplyPosition()
end

-- Back to the design size (the grip's saved size is forgotten). A window
-- that brings its own ResetPosition calls this from it.
function Window:ResetSize()
	local frame = self.frame
	local store = self:Store()
	store.w, store.h = nil, nil
	if frame then frame:SetSize(self.opts.width, self.opts.height) end
end

function Window:Sound(id)
	if Value(self.opts.sound) then E:PlayMedia(id) end
end

-- The kit's resize grip (bottom-right corner): dragging changes the
-- window's size and the open tab reflows; the size is kept in the
-- window's store. The smallest size is the window's design size unless
-- opts.minWidth / minHeight allow less.
local function CreateGrip(win)
	local frame = win.frame
	local opts = win.opts
	return Kit.SizeGrip(frame, {
		resize = true, width = opts.width, height = opts.height,
		minWidth = opts.minWidth or opts.width, minHeight = opts.minHeight or opts.height,
		maxWidth = opts.maxWidth, maxHeight = opts.maxHeight,
		store = function() return win:Store() end,
		tipTitle = L["Window size"],
		tip = L["Drag to make the window bigger or smaller; the content follows. Ctrl+mouse wheel on the title bar zooms."],
		onStop = function()
			win:SavePosition()
			win:ApplyPosition()
		end,
	})
end

-- Ctrl+mouse wheel on the title bar zooms the whole window (70 to 150 %),
-- the same key as the Blizzard windows EldoUI moves; the top-left corner
-- stays put.
function Window:Zoom(delta)
	local frame = self.frame
	if not frame then return end
	local user = Clamp(math.floor((self:Scale() + delta * 0.05) * 100 + 0.5) / 100, SCALE_MIN, SCALE_MAX)
	local store = self:Store()
	store.scale = math.abs(user - 1) > 0.001 and user or nil
	self:SavePosition()
	self:ApplyPosition()
end

function Window:Build()
	if self.frame then return self.frame end
	local opts = self.opts
	local win = self
	local frame = CreateFrame("Frame", opts.name, UIParent)
	self.frame = frame
	frame:SetSize(opts.width, opts.height)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:Hide()
	if opts.name then table.insert(UISpecialFrames, opts.name) end
	E:SkinPanel(frame, { transparent = Value(opts.transparent), accentOffset = TOPBAR })

	local bar = CreateFrame("Frame", nil, frame)
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	bar:SetHeight(TOPBAR)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() frame:StartMoving() end)
	bar:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, false) end
		win:SavePosition()
		win:ApplyPosition()
	end)
	bar:EnableMouseWheel(true)
	bar:SetScript("OnMouseWheel", function(_, delta)
		if IsControlKeyDown() then win:Zoom(delta) end
	end)
	frame.topBar = bar
	frame.title = Kit.Title(bar, E.tokens.size.dialogTitle)
	frame.title:SetPoint("LEFT", 12, 0)
	frame.title:SetText(opts.title or "")

	frame.close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
	frame.close:SetPoint("RIGHT", -4, 0)
	E:SkinCloseButton(frame.close)
	frame.close:SetScript("OnClick", function() win:Close() end)
	Kit.Tooltip(frame.close, L["Close"], L["Esc closes the window too."])
	local right = frame.close
	-- No settings gear: the config window opens only with /eui (Core/Config.lua).
	-- The window's options link (E:BindOptionsLink): on the help button,
	-- whose tooltip names it; a window without one has it on the title bar.
	if opts.help then
		frame.help = Kit.IconButton(bar, 22, nil, function() Call(opts.help.onClick) end,
			opts.help.title or L["Help"], opts.help.text, "?", opts.options and { options = opts.options } or nil)
		frame.help:SetPoint("RIGHT", right, "LEFT", -2, 0)
		right = frame.help
	end
	if opts.options and not opts.help then
		Kit.Tooltip(bar, nil, function(tooltip)
			Kit.TipTitle(tooltip, frame.title:GetText())
			Kit.TipText(tooltip, L["Drag to move the window. Ctrl+mouse wheel zooms it."])
		end)
		E:BindOptionsLink(bar, opts.options)
	end
	local searchRoom = 0
	if opts.search then
		local box = CreateFrame("EditBox", nil, bar, "SearchBoxTemplate")
		E:SearchHint(box)
		box:SetSize(170, 20)
		box:SetAutoFocus(false)
		box:SetPoint("RIGHT", right, "LEFT", -10, 0)
		E:SkinEditBox(box)
		box:SetScript("OnEnterPressed", function(own)
			local text = strtrim(own:GetText() or "")
			own:ClearFocus()
			Call(opts.search.onSearch, text)
		end)
		Kit.Tooltip(box, L["Search"], opts.search.tip or L["Type and press Enter to search."])
		frame.search = box
		searchRoom = 190
	end
	frame.tabBar = CreateFrame("Frame", nil, bar)
	frame.tabBar:SetPoint("LEFT", frame.title, "RIGHT", 16, 0)
	frame.tabBar:SetPoint("RIGHT", right, "LEFT", -(8 + searchRoom), 0)
	frame.tabBar:SetHeight(24)

	frame.content = CreateFrame("Frame", nil, frame)
	frame.content:SetPoint("TOPLEFT", PAD, -(TOPBAR + PAD))
	frame.content:SetPoint("BOTTOMRIGHT", -PAD, FOOTER + 2)
	frame.empty = Kit.EmptyState(frame.content)
	frame.empty:SetFrameLevel(frame.content:GetFrameLevel() + 20)
	frame.empty:Hide()

	local footer = CreateFrame("Frame", nil, frame)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER)
	local line = Kit.Divider(footer)
	line:SetPoint("TOPLEFT", PAD, 0)
	line:SetPoint("TOPRIGHT", -PAD, 0)
	frame.footerText = Kit.Text(footer, E.tokens.size.small, "LEFT", "secondary")
	frame.footerText:SetPoint("LEFT", 12, 0)
	frame.footerText:SetPoint("RIGHT", -28, 0)
	frame.footer = footer
	frame.grip = CreateGrip(self)

	frame:SetScript("OnShow", function() win:Sound(SOUND_OPEN) end)
	frame:SetScript("OnHide", function()
		win:Sound(SOUND_CLOSE)
		local tab = win.current and win:GetTab(win.current)
		if tab and tab.frame and tab.hide then Call(tab.hide, tab.frame) end
	end)
	-- Keys (Kit.WindowKeys): Ctrl+F to the search box, Esc clears a search
	-- before it closes the window, Ctrl+Tab and Ctrl+Shift+Tab switch tabs.
	-- Layering (Kit.Layer): its Esc order runs through Kit.WindowKeys.
	frame.kitClose = function() win:Close() end
	Kit.Layer(frame, { escape = false })
	Kit.WindowKeys(frame, { search = frame.search, handle = function(name, key)
		if name == "CTRL-TAB" then return win:CycleTab(1) end
		if name == "CTRL-SHIFT-TAB" then return win:CycleTab(-1) end
		if opts.keys then return Call(opts.keys, name, key) and true or false end
		return false
	end })
	self:ApplyPosition()
	return frame
end

function Window:GetTab(key)
	for _, tab in ipairs(self.tabs) do
		if tab.key == key then return tab end
	end
end

-- Tabs that show: hidden() false.
function Window:VisibleTabs()
	local list = {}
	for _, tab in ipairs(self.tabs) do
		if not Value(tab.hidden) then list[#list + 1] = tab end
	end
	return list
end

function Window:SetTabs(tabs)
	self.tabs = tabs or {}
	if self.frame and self.frame:IsShown() then
		self:LayoutTabs()
		if self.current and not self:GetTab(self.current) then self:ShowTab(nil) end
	end
end

local function TabLabel(tab)
	local label = E:Translate(tab.title) or tab.key
	local count = Value(tab.count)
	if type(count) == "number" and count > 0 then label = ("%s %s%d|r"):format(label, E:TokenHex(Kit.SECONDARY), count) end
	return label
end

function Window:LayoutTabs()
	local frame = self.frame
	if not frame then return end
	local list = self:VisibleTabs()
	-- A window with one view shows only its title: a lone tab would do
	-- nothing when clicked.
	if #list < 2 then list = {} end
	local win = self
	local x = 0
	for index, tab in ipairs(list) do
		local button = self.tabButtons[index]
		if not button then
			button = CreateFrame("Button", nil, frame.tabBar)
			button:SetHeight(E.tokens.height.tab)
			button:SetScript("OnClick", function(own) win:Open(own.tabKey) end)
			-- The skin gives the tab its font objects before the first text.
			E:SkinTabs({ button }, { isSelected = function(own) return own.tabKey == win.current end, size = 13 })
			button:SetText(" ")
			self.tabButtons[index] = button
		end
		button.tabKey = tab.key
		button:SetText(TabLabel(tab))
		local text = button:GetFontString()
		button:SetWidth(math.max(64, math.ceil((text and text:GetStringWidth() or 60) + 24)))
		button:ClearAllPoints()
		button:SetPoint("LEFT", frame.tabBar, "LEFT", x, 0)
		x = x + button:GetWidth() + 2
		Kit.Tooltip(button, tab.title, tab.desc)
		button:Show()
	end
	for index = #list + 1, #self.tabButtons do self.tabButtons[index]:Hide() end
	E:UpdateTabs()
end

function Window:UpdateEmpty(tab)
	local empty = self.frame.empty
	if not (tab and tab.empty and tab.frame) then
		empty:Hide()
		return
	end
	local title, text, icon, buttons = Call(tab.empty, tab.frame)
	if title then
		empty:Set(title, text, icon, buttons)
		empty:Show()
	else
		empty:Hide()
	end
end

function Window:ShowTab(key, arg)
	local frame = self.frame
	local tab = key and self:GetTab(key)
	if tab and Value(tab.hidden) then tab = nil end
	for _, other in ipairs(self.tabs) do
		if other.frame and other ~= tab then
			if other.frame:IsShown() and other.hide then Call(other.hide, other.frame) end
			other.frame:Hide()
		end
	end
	if not tab then
		self.current = nil
		frame.empty:Hide()
		E:UpdateTabs()
		return
	end
	if not tab.frame then
		local built = Call(tab.create, frame.content)
		if type(built) ~= "table" then return end
		tab.frame = built
		if built:GetNumPoints() == 0 then built:SetAllPoints(frame.content) end
	end
	if self.current and self.current ~= tab.key and frame:IsShown() then self:Sound(SOUND_PAGE) end
	self.current = tab.key
	self:Store().lastTab = tab.key
	tab.frame:Show()
	if tab.show then Call(tab.show, tab.frame, arg) end
	-- Parts a tab built after the window took its scale.
	E:SnapBorders(tab.frame, true)
	self:UpdateEmpty(tab)
	E:UpdateTabs()
end

-- The next (step 1) or previous (step -1) shown tab, wrapping around.
-- True when it switched (false with one tab or none).
function Window:CycleTab(step)
	local list = self:VisibleTabs()
	if #list < 2 then return false end
	local at = 0
	for index, tab in ipairs(list) do
		if tab.key == self.current then at = index end
	end
	local target = list[(at - 1 + step) % #list + 1]
	if at == 0 and step < 0 then target = list[#list] end
	return self:Open(target.key) and true or false
end

function Window:UpdateFooter()
	if self.frame then self.frame.footerText:SetText(Value(self.opts.footer) or "") end
end

function Window:Restyle()
	local frame = self.frame
	if not frame then return end
	E:SetPanelTransparent(frame, Value(self.opts.transparent))
	E:UpdateTabs()
end

function Window:Open(key, arg)
	if self.opts.hideInCombat ~= false and InCombatLockdown() then
		-- Opens by itself when combat ends (PLAYER_REGEN_ENABLED below).
		self.combatOpen = { key = key or self.current, arg = arg }
		E:Print(L["%s opens when combat ends."]:format(self.opts.title or ""))
		return false
	end
	self.combatOpen = nil
	self:Build()
	local visible = self:VisibleTabs()
	local wanted = key and self:GetTab(key)
	if key and (not wanted or Value(wanted.hidden)) then key, arg = nil, nil end
	if not key then
		local last = self:Store().lastTab
		key = (last and self:GetTab(last) and not Value(self:GetTab(last).hidden)) and last or (visible[1] and visible[1].key)
	end
	self:LayoutTabs()
	self:UpdateFooter()
	-- The screen or UI scale may have changed since it was built.
	if not self.frame:IsShown() then
		self:ApplyPosition()
		-- The saved size, also for a window that places itself (a mover).
		if self.frame.grip then self.frame.grip:Restore() end
		E:SlideIn(self.frame, "DOWN")
	end
	self:ShowTab(key, arg)
	return true
end

function Window:Close()
	self.combatOpen = nil
	if self.frame and self.frame:IsShown() then E:SlideOut(self.frame, "DOWN") end
end

function Window:Toggle(key, arg)
	if self:IsOpen() and (key == nil or key == self.current) then self:Close() else self:Open(key, arg) end
end

function Window:IsOpen()
	return self.frame ~= nil and self.frame:IsShown()
end

function Window:Current()
	return self.current
end

-- After data changes: redraw the tab on show (and the tab labels).
function Window:Refresh(changed)
	if not self:IsOpen() then return end
	self:LayoutTabs()
	self:UpdateFooter()
	local tab = self.current and self:GetTab(self.current)
	if tab and tab.frame and tab.refresh then Call(tab.refresh, tab.frame, changed) end
	self:UpdateEmpty(tab)
end

function Kit.CreateTabbedWindow(opts)
	opts = opts or {}
	opts.width = opts.width or 920
	opts.height = opts.height or 600
	local win = { opts = opts, tabs = opts.tabs or {}, tabButtons = {}, memory = {} }
	for name, fn in pairs(Window) do win[name] = fn end
	windows[#windows + 1] = win
	return win
end

---------------------------------------------------------------------------
-- Window layering: one rule for every EldoUI window.
--   Kit.Layer(frame, { dialog = bool, escape = bool })
-- * A window that is clicked comes to the front, and the dialogs it opened
--   come along above it.
-- * A window shown while another EldoUI window is open belongs to that one
--   (its owner): it never sits under it (it takes the owner's strata when
--   its own is lower) and a dialog opens centered on it.
-- * Escape closes the front window first, while another EldoUI window is
--   open under it; the last one closes the usual way (UISpecialFrames).
-- Kit.TopWindow() is the front EldoUI window, Kit.Raise(frame) brings one
-- to the front. Windows built from the kit (tool windows, tabbed windows,
-- dialogs) and the options window are layered on their own.
---------------------------------------------------------------------------
local STRATA_RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
	FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local layered = setmetatable({}, { __mode = "k" }) -- frame -> { dialog, baseStrata, owner }
local stack = {} -- shown layered windows, front last

local function Unstack(frame)
	for i = #stack, 1, -1 do
		if stack[i] == frame then table.remove(stack, i) end
	end
end

function Kit.TopWindow(except)
	for i = #stack, 1, -1 do
		local frame = stack[i]
		if frame ~= except and frame:IsShown() then return frame end
	end
end

function Kit.IsLayered(frame)
	return layered[frame] ~= nil
end

local function Rank(frame)
	return STRATA_RANK[frame:GetFrameStrata() or ""] or 3
end

function Kit.Raise(frame, seen)
	local info = layered[frame]
	if not info or not frame:IsShown() then return end
	seen = seen or {}
	if seen[frame] then return end
	seen[frame] = true
	if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then return end -- EldoUI's own windows only
	Unstack(frame)
	stack[#stack + 1] = frame
	frame:Raise()
	-- Its dialogs stay above it.
	for other, otherInfo in pairs(layered) do
		if otherInfo.owner == frame and other ~= frame and other:IsShown() then Kit.Raise(other, seen) end
	end
end

-- Center `frame` on `owner`, in UIParent units, so a drag later works
-- like any other window.
local function CenterOn(frame, owner)
	local x, y = owner:GetCenter()
	if type(x) ~= "number" or type(y) ~= "number" then return end
	local ownerScale, scale = owner:GetEffectiveScale(), frame:GetEffectiveScale()
	if type(ownerScale) ~= "number" or type(scale) ~= "number" or scale <= 0 then return end
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * ownerScale / scale, y * ownerScale / scale)
end

local function OnShow(frame)
	local info = layered[frame]
	if not info then return end
	local owner = Kit.TopWindow(frame)
	-- Never a circle: a window can't belong to one that belongs to it.
	local up, steps = owner, 0
	while up and steps < 20 do
		if up == frame then owner = nil break end
		up = layered[up] and layered[up].owner
		steps = steps + 1
	end
	-- A window that belongs to another stays over it.
	info.owner = owner
	if owner then
		if Rank(frame) < Rank(owner) then frame:SetFrameStrata(owner:GetFrameStrata()) end
		if info.dialog then CenterOn(frame, owner) end
	end
	Kit.Raise(frame)
end

local function OnHide(frame)
	local info = layered[frame]
	if not info then return end
	Unstack(frame)
	info.owner = nil
	if frame:GetFrameStrata() ~= info.baseStrata then frame:SetFrameStrata(info.baseStrata) end
end

-- Esc on `frame`: closes it alone when it is the front window and another
-- EldoUI window is open under it. True when it did.
function Kit.LayerEscape(frame)
	if not layered[frame] or Kit.TopWindow() ~= frame or not Kit.TopWindow(frame) then return false end
	if frame.kitClose then frame.kitClose() elseif frame.Close then frame:Close() else frame:Hide() end
	return true
end

function Kit.Layer(frame, opts)
	if layered[frame] then return frame end
	opts = opts or {}
	layered[frame] = { dialog = opts.dialog and true or false, baseStrata = frame:GetFrameStrata() }
	frame:HookScript("OnShow", OnShow)
	frame:HookScript("OnHide", OnHide)
	frame:HookScript("OnMouseDown", function(self) Kit.Raise(self) end)
	-- escape = false: the window's own keys call Kit.LayerEscape (or it
	-- closes on Escape by itself, as dialogs do).
	if opts.escape ~= false then
		frame.kitLayerKeys = Kit.KeyHandler(frame, function(_, key)
			return key == "ESCAPE" and Kit.LayerEscape(frame)
		end)
	end
	if frame:IsShown() then OnShow(frame) end
	return frame
end

---------------------------------------------------------------------------
-- Tool window: the compact
-- shell of every small EldoUI window (editors, logs, pickers, lists).
--
--   +------------------------------------------------+
--   | Title                                        x |  header (Kit.TOOL_HEADER)
--   |================================================|  2 px accent line
--   |  content                                       |
--   |------------------------------------------------|  footer (optional)
--   |  footer buttons / status                    // |  size grip (optional)
--   +------------------------------------------------+
--
-- local win = Kit.CreateToolWindow(name, {
--   title, width, height, parent (UIParent), strata ("HIGH"),
--   escape (true: Esc closes it), movable (true), closable (true),
--   resizable (true: the kit grip, smallest at width x height; false for a
--       fixed form; or { minWidth, minHeight, maxWidth, maxHeight,
--       tipTitle, tip } with the grip's own tooltip),
--   footer (nil, or the footer height; Kit.TOOL_FOOTER fits one button row),
--   transparent, slide (true: slides in when shown),
--   store = fn() -> table (keeps x, y and the size as w, h; without one
--       a named window keeps its size in EldoUIDB.windowSizes),
--   point = { "CENTER", UIParent, "CENTER", 0, 0 } (when nothing is stored),
--   onClose = fn(win) })
-- win.header, win.title, win.headerLine, win.close, win.content,
-- win.footer, win.footerText, win.grip; win:SetTitle(text[, subline,
-- color]), win:Open(), win:Close() (slides out), win:Toggle(),
-- win:ResetPosition()
-- The subline sits after the title on the header line, small, in the
-- secondary gray or `color` like the full windows' subline: { r, g, b },
-- "accent", or a text token ("good", "warn", "bad", "gold").
---------------------------------------------------------------------------
Kit.TOOL_HEADER = 28
Kit.TOOL_FOOTER = 36
Kit.TOOL_PAD = 8
local toolWindows = setmetatable({}, { __mode = "k" })

local function ToolStore(win)
	local store = win.kitOpts.store
	if type(store) == "function" then
		local ok, value = pcall(store)
		store = ok and value or nil
	end
	return type(store) == "table" and store or nil
end

-- Where a window's size is kept: its own store, else one table per named
-- window for the account (EldoUIDB.windowSizes), so every resized window
-- opens at the size the player left it.
function Kit.WindowSizeStore(name, store)
	if type(store) == "table" then return store end
	if type(name) ~= "string" or type(EldoUIDB) ~= "table" then return nil end
	EldoUIDB.windowSizes = EldoUIDB.windowSizes or {}
	EldoUIDB.windowSizes[name] = EldoUIDB.windowSizes[name] or {}
	return EldoUIDB.windowSizes[name]
end

local function ToolApplyPosition(win)
	local opts = win.kitOpts
	local store = ToolStore(win)
	if win.grip then win.grip:Restore() end
	win:ClearAllPoints()
	if store and tonumber(store.x) and tonumber(store.y) then
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", store.x, store.y)
	elseif opts.point then
		win:SetPoint(unpack(opts.point))
	else
		win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
end

local function ToolSavePosition(win)
	local store = ToolStore(win)
	if not store then return end
	local left, top = win:GetLeft(), win:GetTop()
	if left and top then store.x, store.y = math.floor(left + 0.5), math.floor(top + 0.5) end
end

function Kit.PaintToolSubline(subtitle)
	local color = subtitle.kitColor
	if color == "accent" then
		subtitle:SetTextColor(Kit.Accent())
	elseif type(color) == "string" and E.tokens.text[color] then
		subtitle:SetTextColor(unpack(E.tokens.text[color]))
	elseif type(color) == "table" and type(color[1]) == "number" then
		subtitle:SetTextColor(color[1], color[2], color[3])
	else
		subtitle:SetTextColor(unpack(Kit.SECONDARY))
	end
end

function Kit.CreateToolWindow(name, opts)
	opts = opts or {}
	local win = CreateFrame("Frame", name, opts.parent or UIParent)
	win.kitOpts = opts
	win:SetSize(opts.width or 360, opts.height or 300)
	win:SetFrameStrata(opts.strata or "HIGH")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:Hide()
	E:SetPanelTemplate(win, opts.transparent)
	E:SetWindowEdge(win)
	if name and opts.escape ~= false then table.insert(UISpecialFrames, name) end

	local header = CreateFrame("Frame", nil, win)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(Kit.TOOL_HEADER)
	win.header = header
	win.title = Kit.Title(header, E.tokens.size.dialogTitle)
	win.title:SetPoint("LEFT", 12, 0)
	win.title:SetPoint("RIGHT", -32, 0)
	win.title:SetText(opts.title or "")
	win.headerLine = header:CreateTexture(nil, "ARTWORK")
	win.headerLine:SetPoint("BOTTOMLEFT", E:PixelFor(win), 0)
	win.headerLine:SetPoint("BOTTOMRIGHT", -E:PixelFor(win), 0)
	E:Hairline(win.headerLine, "h", 2)
	E:AccentTexture(win.headerLine, 1)

	if opts.movable ~= false then
		win:SetMovable(true)
		header:EnableMouse(true)
		header:RegisterForDrag("LeftButton")
		header:SetScript("OnDragStart", function() win:StartMoving() end)
		header:SetScript("OnDragStop", function()
			win:StopMovingOrSizing()
			if win.SetUserPlaced then pcall(win.SetUserPlaced, win, false) end
			ToolSavePosition(win)
		end)
	end

	if opts.closable ~= false then
		win.close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
		win.close:SetSize(22, 22)
		win.close:SetPoint("RIGHT", -4, 0)
		E:SkinCloseButton(win.close)
		win.close:SetScript("OnClick", function() win:Close() end)
	end

	local footerHeight = tonumber(opts.footer) or 0
	if footerHeight > 0 then
		local footer = CreateFrame("Frame", nil, win)
		footer:SetPoint("BOTTOMLEFT")
		footer:SetPoint("BOTTOMRIGHT")
		footer:SetHeight(footerHeight)
		local line = Kit.Divider(footer)
		line:SetPoint("TOPLEFT", Kit.TOOL_PAD, 0)
		line:SetPoint("TOPRIGHT", -Kit.TOOL_PAD, 0)
		win.footer = footer
		win.footerText = Kit.Text(footer, E.tokens.size.small, "LEFT", "secondary")
		win.footerText:SetPoint("LEFT", 12, 0)
		win.footerText:SetPoint("RIGHT", -28, 0)
		win.footerText:SetWordWrap(false)
	end

	win.content = CreateFrame("Frame", nil, win)
	win.content:SetPoint("TOPLEFT", Kit.TOOL_PAD, -(Kit.TOOL_HEADER + Kit.TOOL_PAD))
	win.content:SetPoint("BOTTOMRIGHT", -Kit.TOOL_PAD, footerHeight + Kit.TOOL_PAD)

	-- Every tool window resizes from the kit grip unless it says
	-- resizable = false (a fixed form whose content can't reflow).
	if opts.resizable ~= false then
		local bounds = type(opts.resizable) == "table" and opts.resizable or {}
		win.grip = Kit.SizeGrip(win, { resize = true, width = opts.width or 360, height = opts.height or 300,
			minWidth = bounds.minWidth or opts.width or 200, minHeight = bounds.minHeight or opts.height or 120,
			maxWidth = bounds.maxWidth, maxHeight = bounds.maxHeight, tipTitle = bounds.tipTitle, tip = bounds.tip,
			store = function() return Kit.WindowSizeStore(name, ToolStore(win)) end,
			onStop = function() ToolSavePosition(win) end })
	end

	function win:SetTitle(text, subline, color)
		self.title:SetText(text or "")
		local shown = type(subline) == "string" and subline ~= ""
		if shown and not self.subtitle then
			self.subtitle = Kit.Text(self.header, E.tokens.size.small, "LEFT", "secondary")
			self.subtitle:SetWordWrap(false)
			E:RegisterThemed(self.subtitle, Kit.PaintToolSubline)
		end
		self.title:ClearAllPoints()
		self.title:SetPoint("LEFT", 12, 0)
		if not shown then
			self.title:SetPoint("RIGHT", -32, 0)
			if self.subtitle then self.subtitle:Hide() end
			return
		end
		-- The title takes what it needs, at most two thirds of the line.
		local room = math.max((self:GetWidth() or 0) - 44, 1)
		self.title:SetWidth(math.max(math.min(math.ceil(self.title:GetStringWidth() + 1), math.floor(room * 2 / 3)), 1))
		local sub = self.subtitle
		sub:ClearAllPoints()
		sub:SetPoint("LEFT", self.title, "RIGHT", 8, 0)
		sub:SetPoint("RIGHT", self.header, "RIGHT", -32, 0)
		sub:SetText(subline)
		sub.kitColor = color
		Kit.PaintToolSubline(sub)
		sub:Show()
	end
	function win:Open()
		if not self:IsShown() then self:Show() end
		self:Raise()
		return self
	end
	function win:Close()
		if self:IsShown() then E:SlideOut(self, "DOWN") end
	end
	function win:Toggle()
		if self:IsShown() then self:Close() else self:Open() end
	end
	function win:ResetPosition()
		local store = ToolStore(self)
		if store then store.x, store.y = nil, nil end
		if self.grip then self.grip:ResetSize() else self:SetSize(opts.width or 360, opts.height or 300) end
		ToolApplyPosition(self)
	end
	win:HookScript("OnShow", function(self)
		if opts.slide ~= false then E:SlideIn(self, "DOWN") end
	end)
	if opts.onClose then
		win:HookScript("OnHide", function(self)
			local ok, err = pcall(opts.onClose, self)
			if not ok then geterrorhandler()(err) end
		end)
	end
	ToolApplyPosition(win)
	-- Layering (Kit.Layer): a window over the others' strata with no saved
	-- place (import, export, a text to copy) is a dialog and opens centered
	-- on the window that opened it; opts.dialog decides it outright.
	local dialog = opts.dialog
	if dialog == nil then
		dialog = opts.store == nil and (opts.strata == "DIALOG" or opts.strata == "FULLSCREEN_DIALOG")
	end
	win.kitClose = function() win:Close() end
	Kit.Layer(win, { dialog = dialog, escape = opts.escape })
	toolWindows[win] = true
	return win
end

function Kit.IsToolWindow(frame)
	return toolWindows[frame] == true
end

---------------------------------------------------------------------------
-- Dialog: one popup shell for questions,
-- notes and prompts. Header-font title, the 2 px accent line, a text, an
-- optional edit box and check, and a centered row of footer buttons on the
-- 4 px grid. Escape closes it; FULLSCREEN_DIALOG, so it never sits behind
-- the options window.
--   local d = Kit.CreateDialog(name, { width (400), title, text, strata,
--       escape (true), closeButton (false: an X in the header),
--       buttons = { { label, onClick = fn(d), kind, keepOpen } },
--       edit = { hint, numeric, maxLetters, multiline, height },
--       check = { label, desc } })
--   d:SetTitle(t), d:SetText(t), d:SetButtons(list), d:SetButtonFrames(frames),
--   d:Layout() (height from the text; the header grows with the title),
--   d:HeaderHeight(), d.title, d.text, d.edit, d.check, d.buttons,
--   d.headerLine, d.keys (Escape)
---------------------------------------------------------------------------
Kit.DIALOG_HEADER = 40
Kit.DIALOG_PAD = 16
Kit.DIALOG_BUTTON = 120

function Kit.CreateDialog(name, opts)
	opts = opts or {}
	local d = CreateFrame("Frame", name, UIParent)
	d.kitOpts = opts
	d:SetSize(opts.width or 400, 140)
	d:SetPoint("TOP", UIParent, "TOP", 0, -200)
	d:SetFrameStrata(opts.strata or "FULLSCREEN_DIALOG")
	d:SetToplevel(true)
	d:EnableMouse(true)
	d:SetClampedToScreen(true)
	d:SetMovable(true)
	d:RegisterForDrag("LeftButton")
	d:SetScript("OnDragStart", d.StartMoving)
	d:SetScript("OnDragStop", d.StopMovingOrSizing)
	d:Hide()
	E:SetPanelTemplate(d)
	E:SetWindowEdge(d)
	-- Escape closes the dialog alone, so a question over the options
	-- window never takes the window with it. UISpecialFrames stays as the
	-- fallback for combat, when the keys are off (Kit.KeyHandler).
	if name and opts.escape ~= false then
		table.insert(UISpecialFrames, name)
		d.keys = Kit.KeyHandler(d, function(_, key)
			if key ~= "ESCAPE" then return false end
			d:Hide()
			return true
		end)
	end
	-- Above the window that opened it, centered on it (Kit.Layer).
	Kit.Layer(d, { dialog = true, escape = false })
	local pad = Kit.DIALOG_PAD

	d.title = Kit.Title(d, E.tokens.size.dialogTitle)
	d.title:SetPoint("TOPLEFT", pad, -12)
	d.title:SetPoint("TOPRIGHT", -(pad + 24), -12)
	d.title:SetText(opts.title or "")
	d.headerLine = d:CreateTexture(nil, "ARTWORK")
	d.headerLine:SetPoint("TOPLEFT", E:PixelFor(d), -Kit.DIALOG_HEADER)
	d.headerLine:SetPoint("TOPRIGHT", -E:PixelFor(d), -Kit.DIALOG_HEADER)
	E:Hairline(d.headerLine, "h", 2)
	E:AccentTexture(d.headerLine, 1)
	if opts.closeButton then
		d.close = CreateFrame("Button", nil, d, "UIPanelCloseButton")
		d.close:SetSize(22, 22)
		d.close:SetPoint("TOPRIGHT", -8, -9)
		E:SkinCloseButton(d.close)
		d.close:SetScript("OnClick", function() d:Hide() end)
	end

	d.text = Kit.Text(d, E.tokens.size.body, "LEFT")
	d.text:SetPoint("TOPLEFT", pad, -(Kit.DIALOG_HEADER + 12))
	d.text:SetPoint("TOPRIGHT", -pad, -(Kit.DIALOG_HEADER + 12))
	d.text:SetWordWrap(true)
	d.text:SetSpacing(3)
	d.text:SetText(opts.text or "")

	if opts.edit then
		local edit = opts.edit
		if edit.multiline then
			d.editArea = Kit.ScrollArea(d)
			d.editArea:SetHeight(edit.height or 160)
			d.editBox = CreateFrame("Frame", nil, d)
			d.editBox:SetPoint("TOPLEFT", d.editArea, -4, 4)
			d.editBox:SetPoint("BOTTOMRIGHT", d.editArea, 4, -4)
			d.editBox:SetFrameLevel(math.max(d:GetFrameLevel(), 1))
			E:SetTemplate(d.editBox, true)
			local box = CreateFrame("EditBox", nil, d.editArea.child)
			box:SetMultiLine(true)
			box:SetAutoFocus(false)
			box:SetMaxLetters(edit.maxLetters or 0)
			box:SetPoint("TOPLEFT")
			box:SetPoint("TOPRIGHT")
			E:SetFont(box, E.tokens.size.label)
			box:SetScript("OnEscapePressed", function() d:Hide() end)
			box:SetScript("OnTextChanged", function(self)
				d.editArea.child:SetHeight(math.max(self:GetHeight() or 0, d.editArea:GetHeight() or 0))
				d.editArea:Update()
			end)
			box:SetScript("OnCursorChanged", function(_, _, y, _, height)
				local area = d.editArea
				local top = -y
				local view = area.scroll:GetHeight() or 0
				local scroll = area.scroll:GetVerticalScroll() or 0
				if top < scroll then
					area:SetScroll(top)
				elseif top + height > scroll + view then
					area:SetScroll(top + height - view)
				end
			end)
			d.editArea:HookScript("OnMouseDown", function() box:SetFocus() end)
			d.edit = box
		else
			d.edit = Kit.Input(d, { width = (opts.width or 400) - 2 * pad, numeric = edit.numeric, hint = edit.hint,
				maxLetters = edit.maxLetters, onEnter = function()
					local first = d.buttons and d.buttons[1]
					if first and first:IsShown() and first:IsEnabled() then first:Click() end
				end })
			d.edit:SetScript("OnEscapePressed", function() d:Hide() end)
		end
	end
	if opts.check then
		d.check = Kit.Check(d, opts.check.label, opts.check.desc)
		-- A long label wraps inside the dialog, its first line level with
		-- the box, instead of running past the edge (large text, Danish).
		d.check.label:ClearAllPoints()
		d.check.label:SetPoint("TOPLEFT", d.check, "TOPRIGHT", 4, -5)
		d.check.label:SetWidth((opts.width or 400) - 2 * pad - 24)
		d.check.label:SetWordWrap(true)
	end
	d.buttons = {}

	function d:SetTitle(text)
		self.title:SetText(text or "")
		self:Layout()
	end
	function d:SetText(text)
		self.text:SetText(text or "")
		self:Layout()
	end

	-- Lay out a row of ready-made buttons (the reload prompt's secure one).
	function d:SetButtonFrames(frames)
		self.buttonFrames = frames
		local shown = {}
		for _, button in ipairs(frames) do
			if button:IsShown() then shown[#shown + 1] = button end
		end
		local gap = 8
		local total = 0
		for _, button in ipairs(shown) do total = total + button:GetWidth() end
		total = total + gap * math.max(#shown - 1, 0)
		-- A row wider than the dialog (three long labels, large text, Danish)
		-- widens the dialog, so no button runs past its edges.
		self:SetWidth(math.max(self.kitOpts.width or 400, math.ceil(total) + 2 * pad))
		local x = -total / 2
		for _, button in ipairs(shown) do
			button:ClearAllPoints()
			button:SetPoint("BOTTOMLEFT", self, "BOTTOM", math.floor(x + 0.5), pad)
			x = x + button:GetWidth() + gap
		end
	end

	function d:SetButtons(list)
		for index = 1, math.max(#list, #self.buttons) do
			local data = list[index]
			local button = self.buttons[index]
			if data and not button then
				button = Kit.Button(self, "", { width = Kit.DIALOG_BUTTON, large = true })
				self.buttons[index] = button
			end
			if button then
				button:SetShown(data ~= nil)
				if data then
					button:SetText(data[1] or data.label or "")
					Kit.FitButton(button, Kit.DIALOG_BUTTON)
					Kit.SetButtonKind(button, data.kind or (index == 1 and #list > 1 and "primary") or nil)
					local onClick = data[2] or data.onClick
					local keepOpen = data.keepOpen
					button:SetScript("OnClick", function()
						if not keepOpen then self:Hide() end
						if onClick then
							local ok, err = pcall(onClick, self)
							if not ok then geterrorhandler()(err) end
						end
					end)
				end
			end
		end
		self:SetButtonFrames(self.buttons)
		self:Layout()
	end

	-- The header keeps 12 px below the title at every text size (Large
	-- text makes the title taller), and never gets smaller than 40.
	function d:HeaderHeight()
		local title = (self.title:GetText() or "") ~= "" and math.ceil(self.title:GetStringHeight() or 0) or 0
		return math.max(Kit.DIALOG_HEADER, 12 + title + 12)
	end

	function d:Layout()
		local header = self:HeaderHeight()
		local edge = E:PixelFor(self)
		self.headerLine:ClearAllPoints()
		self.headerLine:SetPoint("TOPLEFT", edge, -header)
		self.headerLine:SetPoint("TOPRIGHT", -edge, -header)
		self.text:ClearAllPoints()
		self.text:SetPoint("TOPLEFT", pad, -(header + 12))
		self.text:SetPoint("TOPRIGHT", -pad, -(header + 12))
		local height = header + 12
		local textHeight = (self.text:GetText() or "") ~= "" and math.ceil(self.text:GetStringHeight() or 0) or 0
		height = height + textHeight
		local below = self.text
		if self.editArea then
			self.editArea:ClearAllPoints()
			self.editArea:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 4, -12)
			self.editArea:SetPoint("TOPRIGHT", below, "BOTTOMRIGHT", -4, -12)
			height = height + 12 + self.editArea:GetHeight() + 4
			below = self.editArea
		elseif self.edit and self.edit:IsShown() then
			self.edit:ClearAllPoints()
			self.edit:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -12)
			height = height + 12 + self.edit:GetHeight()
			below = self.edit
		end
		if self.check and self.check:IsShown() then
			self.check:ClearAllPoints()
			self.check:SetPoint("TOPLEFT", below, "BOTTOMLEFT", -4, -8)
			local label = math.ceil(self.check.label:GetStringHeight() or 0) + 5
			height = height + 8 + math.max(self.check:GetHeight(), label)
			-- The click area ends where the wrapped words end, never past
			-- the dialog's edge.
			local words = math.min(math.ceil(self.check.label:GetStringWidth() or 0), self.check.label:GetWidth() or 0)
			self.check:SetHitRectInsets(0, -math.max(40, words + 8), 0, -math.max(0, label - self.check:GetHeight()))
		end
		local hasButtons = false
		for _, button in ipairs(self.buttonFrames or self.buttons) do
			if button:IsShown() then hasButtons = true end
		end
		height = height + pad + (hasButtons and (E.tokens.height.buttonLarge + pad) or 0)
		self:SetHeight(math.max(math.ceil(height / 4) * 4, 96))
	end

	d:HookScript("OnShow", function(self)
		self:Layout()
		E:SlideIn(self, "DOWN")
	end)
	-- A new text size while it is open: the header follows the title.
	E:RegisterThemed(d, function(self)
		if self:IsShown() then self:Layout() end
	end)
	if opts.buttons then d:SetButtons(opts.buttons) else d:Layout() end
	return d
end

---------------------------------------------------------------------------
-- Prompt: a dialog with a countdown bar under the text, for
-- answers the game times out (summons, ready checks).
--   local p = Kit.Prompt(name, { width, title, buttons })
--   p:SetCountdown(seconds or nil, total) draws the bar (secondary gray,
--   warn color in the last 10 seconds); p.bar
---------------------------------------------------------------------------
function Kit.Prompt(name, opts)
	local p = Kit.CreateDialog(name, opts)
	p.bar = CreateFrame("StatusBar", nil, p)
	p.bar:SetHeight(4)
	p.bar:SetPoint("TOPLEFT", p.text, "BOTTOMLEFT", 0, -8)
	p.bar:SetPoint("TOPRIGHT", p.text, "BOTTOMRIGHT", 0, -8)
	E:UseBarTexture(p.bar)
	p.bar:SetMinMaxValues(0, 1)
	p.bar.bg = p.bar:CreateTexture(nil, "BACKGROUND")
	p.bar.bg:SetAllPoints()
	p.bar.bg:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	p.bar:Hide()
	local layout = p.Layout
	function p:Layout()
		layout(self)
		if self.bar and self.bar:IsShown() then self:SetHeight(self:GetHeight() + 12) end
	end
	function p:SetCountdown(seconds, total)
		if type(seconds) ~= "number" or seconds <= 0 then
			self.bar:Hide()
			return
		end
		self.bar:Show()
		self.bar:SetMinMaxValues(0, math.max(total or seconds, 1))
		self.bar:SetValue(seconds)
		local c = seconds <= 10 and Kit.WARN or Kit.SECONDARY
		self.bar:SetStatusBarColor(c[1], c[2], c[3])
	end
	return p
end

---------------------------------------------------------------------------
-- Section cards (DESIGN.md 0a rule 4): a small uppercase label in the
-- secondary color with an optional muted hint, over one tinted box with a
-- 1 px edge that holds the section's rows, every second row striped. The
-- options window draws one card per section; the installer and the tool
-- windows use the same part for their groups.
--   local card = Kit.SectionCard(parent, { label, hint, rowHeight, bare })
--   (bare: the row tint and dividers only, for a card inside a small
--   panel that is already a box)
--   card.title, card.hint (nil without a label), card.body (the box, put
--   the rows in it; or place rows over the card from outside, its textures
--   draw under them), card:SetLabel(label, hint), card:SetRows(n[, height])
--   (n even rows from the top, sizes the card), card:Stripe(i, y, height,
--   odd[, split]) (one row at y inside the box, for mixed rows, with an
--   optional divider at x = split), card:HideStripes(from),
--   card:SetBodyHeight(h), card:Paint()
--   Kit.SectionLabel(parent, label[, hint]) -> title, hint: the label part
--   alone, for a section header without a card.
--   Kit.CardLook([style]) -> fill, edge, stripe for that art style.
---------------------------------------------------------------------------
Kit.CARD_LABEL = 22 -- height of the label line above a card

function Kit.CardLook(style)
	local card = E.tokens.card
	style = style or (E.db and E.ArtStyle and E:ArtStyle()) or "Modern"
	local own = card.styles and card.styles[style] or {}
	return own.fill or card.fill, own.edge or card.edge, own.stripe or card.stripe
end

-- Section labels are uppercase. Text with letters outside plain ASCII stays
-- as written, since the game's string functions only change ASCII letters
-- and a word would come out half in capitals.
function Kit.SectionText(text)
	text = tostring(text or "")
	if text:find("[\128-\255]") or text:find("|", 1, true) then return text end
	return text:upper()
end

function Kit.SectionLabel(parent, label, hint)
	local title = Kit.Text(parent, E.tokens.size.small, "LEFT", "secondary")
	title:SetWordWrap(false)
	title:SetMaxLines(1)
	title:SetText(Kit.SectionText(label))
	local muted = Kit.Text(parent, E.tokens.size.small, "LEFT", "secondary")
	muted:SetWordWrap(false)
	muted:SetMaxLines(1)
	muted:SetPoint("LEFT", title, "RIGHT", 8, 0)
	muted:SetText(hint or "")
	muted:SetShown(hint ~= nil and hint ~= "")
	title.hint = muted
	return title, muted
end

-- The card's textures sit on the card frame itself (under every row
-- placed over it), anchored to its body.
local function CardEdge(card, point, kind)
	local line = card:CreateTexture(nil, "BORDER")
	E:Hairline(line, kind, 1)
	if kind == "h" then
		line:SetPoint(point .. "LEFT", card.body)
		line:SetPoint(point .. "RIGHT", card.body)
	else
		line:SetPoint("TOP" .. point, card.body)
		line:SetPoint("BOTTOM" .. point, card.body)
	end
	return line
end

function Kit.SectionCard(parent, opts)
	opts = opts or {}
	local card = CreateFrame("Frame", nil, parent)
	card.kind = "sectionCard"
	card.rowHeight = opts.rowHeight or E.tokens.height.settingsRow
	card.bare = opts.bare and true or false
	card.body = CreateFrame("Frame", nil, card)
	card.fill = card:CreateTexture(nil, "BACKGROUND")
	card.fill:SetAllPoints(card.body)
	card.edges = { CardEdge(card, "TOP", "h"), CardEdge(card, "BOTTOM", "h"), CardEdge(card, "LEFT", "w"), CardEdge(card, "RIGHT", "w") }
	card.stripes = {}

	local function PlaceBox()
		card.body:ClearAllPoints()
		card.body:SetPoint("TOPLEFT", 0, card.title and -Kit.CARD_LABEL or 0)
		card.body:SetPoint("BOTTOMRIGHT")
	end
	function card:SetLabel(label, hint)
		if label and label ~= "" then
			if not self.title then
				self.title, self.hint = Kit.SectionLabel(self, label, hint)
				self.title:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 4, -Kit.CARD_LABEL + 6)
			end
			self.title:SetText(Kit.SectionText(label))
			self.hint:SetText(hint or "")
			self.hint:SetShown(hint ~= nil and hint ~= "")
			self.title:Show()
		elseif self.title then
			self.title:Hide()
			self.hint:Hide()
			self.title, self.hint = nil, nil
		end
		PlaceBox()
		if self.bodyHeight then self:SetBodyHeight(self.bodyHeight) end
	end
	function card:SetBodyHeight(height)
		self.bodyHeight = math.max(1, height or 1)
		self:SetHeight(self.bodyHeight + (self.title and Kit.CARD_LABEL or 0))
	end
	function card:Stripe(index, y, height, odd, split)
		local stripe = self.stripes[index]
		if not stripe then
			stripe = {
				bg = self:CreateTexture(nil, "BACKGROUND", nil, 1),
				line = self:CreateTexture(nil, "BORDER"),
				split = self:CreateTexture(nil, "BORDER"),
			}
			self.stripes[index] = stripe
		end
		local _, _, alpha = Kit.CardLook()
		stripe.odd = odd and true or false
		stripe.bg:SetColorTexture(1, 1, 1, odd and alpha or 0)
		stripe.bg:ClearAllPoints()
		stripe.bg:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, -y)
		stripe.bg:SetPoint("TOPRIGHT", self.body, "TOPRIGHT", 0, -y)
		stripe.bg:SetHeight(height)
		stripe.line:SetColorTexture(unpack(E.tokens.edge.divider))
		stripe.line:ClearAllPoints()
		local px = E:PixelFor(self)
		stripe.line:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, -(y + height - px))
		stripe.line:SetPoint("TOPRIGHT", self.body, "TOPRIGHT", 0, -(y + height - px))
		E:Hairline(stripe.line, "h", 1)
		stripe.split:SetColorTexture(unpack(E.tokens.edge.divider))
		stripe.split:ClearAllPoints()
		if split then
			stripe.split:SetPoint("TOPLEFT", self.body, "TOPLEFT", split, -(y + 8))
			stripe.split:SetHeight(math.max(1, height - 16))
			E:Hairline(stripe.split, "w", 1)
		end
		stripe.bg:Show()
		stripe.line:Show()
		stripe.split:SetShown(split ~= nil)
		return stripe
	end
	function card:HideStripes(from)
		for i = from or 1, #self.stripes do
			local stripe = self.stripes[i]
			stripe.bg:Hide(); stripe.line:Hide(); stripe.split:Hide()
		end
	end
	function card:SetRows(count, height)
		height = height or self.rowHeight
		for i = 1, count do self:Stripe(i, (i - 1) * height, height, i % 2 == 1) end
		self:HideStripes(count + 1)
		-- The last row's divider would sit on the card's own edge.
		if count > 0 then self.stripes[count].line:Hide() end
		self:SetBodyHeight(count * height)
	end
	function card:Paint()
		local fill, edge, alpha = Kit.CardLook()
		self.fill:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
		self.fill:SetShown(not self.bare)
		for _, line in ipairs(self.edges) do
			line:SetColorTexture(edge[1], edge[2], edge[3], edge[4] or 1)
			line:SetShown(not self.bare)
		end
		for _, stripe in ipairs(self.stripes) do
			stripe.bg:SetColorTexture(1, 1, 1, stripe.odd and alpha or 0)
		end
	end

	card:SetLabel(opts.label, opts.hint)
	card:Paint()
	card:SetBodyHeight(1)
	E:RegisterThemed(card, card.Paint)
	return card
end

---------------------------------------------------------------------------
-- Theme changes: repaint kit texts and windows.
---------------------------------------------------------------------------
function Kit.Restyle()
	Kit.ClearTextHeights()
	for fs, kind in pairs(painted) do
		if fs.SetTextColor then
			E:SetWindowFont(fs, fs.kitSize, fs.kitHeader)
			if StillPainted(fs) then Kit.Paint(fs, kind) end
		end
	end
	for _, win in ipairs(windows) do win:Restyle() end
end

-- Kit parts (buttons, switches, scroll bars ...) repaint through the theme
-- registry (E:RegisterThemed, Core/Media.lua); texts and windows here.
E:OnThemeChanged("uikit", Kit.Restyle)

-- A new UI scale or screen size: open windows keep one unit per screen
-- pixel.
E:RegisterPixelCallback(function()
	for _, win in ipairs(windows) do
		if win.frame and win.frame:IsShown() then win:ApplyPosition() end
	end
end)

E:RegisterEvent("PLAYER_REGEN_DISABLED", function()
	for _, win in ipairs(windows) do
		if win.opts.hideInCombat ~= false and win:IsOpen() then
			if win.opts.backAfterCombat ~= false then win.combatOpen = { key = win.current } end
			win.frame:Hide()
		end
	end
end, Kit)

-- A window combat hid, or one asked for in combat, comes back when combat
-- ends, on the same tab (its typed text stays in the page).
E:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	for _, win in ipairs(windows) do
		local pending = win.combatOpen
		if pending then
			win.combatOpen = nil
			if not win:IsOpen() then win:Open(pending.key, pending.arg) end
		end
	end
end, Kit)

---------------------------------------------------------------------------
-- One kit: E.WindowKit (the large-window shell in Core/Skin.lua)
-- and the plugin install kit share these parts instead of their own copies.
-- WindowKit keeps its own Button and Divider signatures.
---------------------------------------------------------------------------
do
	local WK = E.WindowKit
	if WK then
		WK.TooltipHint = Kit.TooltipHint
		WK.AnchorTooltip = Kit.AnchorTooltip
		WK.Switch = Kit.Switch
		WK.Slider = Kit.Slider
		WK.Input = Kit.Input
		WK.Dropdown = Kit.Dropdown
		WK.IconButton = Kit.IconButton
		WK.RemoveButton = Kit.RemoveButton
		WK.Icon = Kit.Icon
		WK.Chevron = Kit.Chevron
		WK.ScrollBar = Kit.ScrollBar
		WK.ScrollArea = Kit.ScrollArea
		WK.SizeGrip = Kit.SizeGrip
		WK.CreateToolWindow = Kit.CreateToolWindow
		WK.CreateDialog = Kit.CreateDialog
		WK.Prompt = Kit.Prompt
		WK.Title = Kit.Title
	end
end
