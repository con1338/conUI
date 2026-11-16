-- EldoUI cooldown groups: the player's own groups of cooldown icons
-- instead of the fixed rows (Main, Utility, Trinkets, Mobility, Items).
--   * Off by default. Turning it on makes the five rows into groups with
--     the same icons, movers and settings, so nothing moves.
--   * New groups get their own mover (EldoUI_CooldownGroup<N>), a grid or
--     flex layout, size, spacing, icons per line, growth and wrap.
--   * In move mode every icon gets a small handle: drag it into another
--     group (between two icons to reorder) or onto empty screen to make it
--     a free icon with its own mover (EldoUI_CooldownIcon_<token>). Free
--     icons are placed relative to the main cooldown row, so they follow
--     it when the layout preset changes. Click the handle for the icon's
--     own settings (size, aspect ratio, zoom, border, shadow,
--     click-through, tooltip, icon art, up to three text labels written
--     with EldoUI's text tags, Core/Tags.lua).
--   * Close gaps: icons that can't show (spell not known, item not in the
--     bags, trinket without a use effect) leave no hole; with it off, or
--     in move mode with placeholders on, their spot stays. "Smooth
--     movement" slides the icons to their new spot (General > Animations
--     off: they jump). The icons are plain frames, never protected ones.
--   * Each group can have its own visibility block (Core/Visibility.lua);
--     otherwise it follows the row it stands in for, or the main row.
--   * A layout per talent group (off by default): each talent group keeps
--     its own groups, free icons and free icon positions; looks stay
--     shared.
--   * Style presets "Fixed rows", "Centered groups" and "Left groups"
--     (CooldownManager.lua) turn own groups off or on and line the groups
--     up centered or from the left.
-- EldoUI's own icons only (Blizzard's Cooldown Manager keeps its viewers).
-- The icons are built by CooldownRows.lua from the same pieces as the
-- rows: the game draws every cooldown, EldoUI only places and dresses
-- them.
local _, E = ...
local K = E.CombatKit
local L = E.L
local M = E:GetModule("CooldownManager")
local P = M.RowParts
local CLASS = P.CLASS

local MAIN_MOVER = "EldoUI_CooldownsMover" -- the main row's mover (free icons hang on it)
local GROUP_MOVER = "EldoUI_CooldownGroup"
local ICON_MOVER = "EldoUI_CooldownIcon_"
local MAX_GROUPS = 20
local VIEWER_OF = { main = "essential", utility = "utility" }
local TRINKET_SLOT = { [13] = true, [14] = true }
-- Width : height of an icon.
local ASPECTS = { ["1"] = 1, ["4:3"] = 4 / 3, ["16:9"] = 16 / 9, ["3:4"] = 3 / 4 }

M.defaults.cdgroups = {
	enabled = false,          -- own groups instead of the fixed rows
	dragHandles = true,
	fillGaps = true,
	showPlaceholders = true,
	perTalentGroup = false,
	smoothMove = false,       -- icons slide to their new spot
	edit = "main",            -- the group the Groups tab edits
	editIcon = "",            -- the icon the Icon tab edits
	classes = {},             -- [CLASS] = { layout = Layout, talents = { [n] = Layout } }
	icons = {},               -- [token] = the icon's own look
}
-- Layout = { nextId, groups = { Group, ... }, free = { [token] = true },
--            freePos = { [token] = saved mover position } }
-- Group  = { id, from (fixed row it stands in for, or nil), name, list,
--            size, spacing, perRow, growth, wrap, layout,
--            ownVisibility, visibility (a Core/Visibility.lua block) }

local function DB() return M.db and M.db.cdgroups end

---------------------------------------------------------------------------
-- Tokens: "spell:133", "item:5512", "slot:13" (a trinket slot)
---------------------------------------------------------------------------
-- One typed word -> token. Numbers are spells, or items with prefer "item".
local function Token(word, prefer)
	word = strtrim(tostring(word or ""))
	if word == "" then return nil end
	local kind, id = word:lower():match("^(%a+):(%d+)$")
	id = tonumber(id)
	if kind == "spell" or kind == "item" then return kind .. ":" .. id end
	if kind == "slot" then return TRINKET_SLOT[id] and ("slot:" .. id) or nil end
	local link = tonumber(word:match("|Hspell:(%d+)"))
	if link then return "spell:" .. link end
	link = tonumber(word:match("|Hitem:(%d+)"))
	if link then return "item:" .. link end
	local number = tonumber(word)
	if number then return (prefer == "item" and "item:" or "spell:") .. number end
	if prefer ~= "item" and C_Spell.GetSpellIDForSpellIdentifier then
		local ok, spell = pcall(C_Spell.GetSpellIDForSpellIdentifier, word)
		if ok and K.Plain(spell) and spell then return "spell:" .. spell end
	end
	if C_Item.GetItemInfoInstant then
		local ok, item = pcall(C_Item.GetItemInfoInstant, word)
		if ok and K.Plain(item) and tonumber(item) then return "item:" .. tonumber(item) end
	end
end

local function Parse(text, prefer)
	local tokens = {}
	for word in tostring(text or ""):gmatch("[^,;\n]+") do
		local token = Token(word, prefer)
		if token then tokens[#tokens + 1] = token end
	end
	return tokens
end

local function Join(tokens) return table.concat(tokens, ", ") end

local function Split(token)
	local kind, id = tostring(token or ""):match("^(%a+):(%d+)$")
	return kind, tonumber(id)
end

-- Name and icon for the settings and placeholders.
local function Describe(token)
	local kind, id = Split(token)
	if kind == "spell" then
		local name = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
		return K.Plain(name) and type(name) == "string" and name or token, C_Spell.GetSpellTexture(id)
	elseif kind == "item" then
		local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
		return K.Plain(name) and type(name) == "string" and name or token, C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
	elseif kind == "slot" then
		local item = GetInventoryItemID("player", id)
		local name = K.Plain(item) and item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(item)
		return L["%s (%s)"]:format(id == 13 and L["Trinket 1"] or L["Trinket 2"], K.Plain(name) and type(name) == "string" and name or L["empty"]),
			GetInventoryItemTexture("player", id)
	end
	return tostring(token), nil
end

---------------------------------------------------------------------------
-- Layouts
---------------------------------------------------------------------------
local ROW_NAMES = { main = L["Main row"], utility = L["Utility row"], trinkets = L["Trinkets"], mobility = L["Mobility"], items = L["Items"] }

-- The fixed rows as groups (the first time own groups are turned on, and
-- "Back to the fixed rows"). The rows' own lists are kept untouched, so
-- turning own groups off shows them as before.
local function FromRows()
	local layout = { nextId = 1, groups = {}, free = {}, freePos = {} }
	local function Add(from, tokens)
		layout.groups[#layout.groups + 1] = { id = layout.nextId, from = from, name = ROW_NAMES[from], list = Join(tokens) }
		layout.nextId = layout.nextId + 1
	end
	Add("main", Parse(P.ListText("main")))
	Add("utility", Parse(P.ListText("utility")))
	Add("trinkets", { "slot:13", "slot:14" })
	local mobility = strtrim(P.ListText("mobility"))
	if mobility ~= "" then
		Add("mobility", Parse(mobility))
	else
		local tokens = {}
		for _, id in ipairs(P.MOBILITY[CLASS] or {}) do tokens[#tokens + 1] = "spell:" .. id end
		Add("mobility", tokens)
	end
	Add("items", Parse(M.db.rows.items.list, "item"))
	return layout
end

local function Valid(layout)
	if type(layout) ~= "table" then return false end
	if type(layout.groups) ~= "table" then return false end
	if type(layout.free) ~= "table" then layout.free = {} end
	if type(layout.freePos) ~= "table" then layout.freePos = {} end
	local top = 0
	for _, group in ipairs(layout.groups) do top = math.max(top, tonumber(group.id) or 0) end
	layout.nextId = math.max(tonumber(layout.nextId) or 1, top + 1)
	return true
end

local function ClassData()
	local db = DB()
	if type(db.classes) ~= "table" then db.classes = {} end
	local data = db.classes[CLASS]
	if type(data) ~= "table" then
		data = {}
		db.classes[CLASS] = data
	end
	if not Valid(data.layout) then data.layout = FromRows() end
	if type(data.talents) ~= "table" then data.talents = {} end
	return data
end

-- The layout in use: the class's, or the talent group's own copy of it.
function M.GroupLayout()
	local data = ClassData()
	if not DB().perTalentGroup then return data.layout end
	local talent = E:TalentGroup()
	if not Valid(data.talents[talent]) then data.talents[talent] = CopyTable(data.layout) end
	return data.talents[talent]
end

-- Settings path of the layout in use (for option keys).
local function LayoutPath()
	if DB().perTalentGroup then return ("cdgroups.classes.%s.talents.%d"):format(CLASS, E:TalentGroup()) end
	return ("cdgroups.classes.%s.layout"):format(CLASS)
end

local function GroupKey(group) return group.from or ("g" .. group.id) end
local function FreeKey(token) return "f:" .. token end
local function FreeMover(token) return ICON_MOVER .. token:gsub(":", "_") end

local function FindGroup(layout, key)
	for index, group in ipairs(layout.groups) do
		if GroupKey(group) == key then return group, index end
	end
end

---------------------------------------------------------------------------
-- Icon looks (per token, shared by every layout)
---------------------------------------------------------------------------
local MAX_LABELS = 3
local LABEL_DEFAULT_POINTS = { "TOP", "BOTTOM", "INSIDE_BOTTOM" }

local function IconDefaults()
	local labels = {}
	for index = 1, MAX_LABELS do labels[index] = { text = "", point = LABEL_DEFAULT_POINTS[index] } end
	return { size = 0, aspect = "1", ownZoom = false, zoom = 8, border = "theme", borderColor = { 1, 0.82, 0 },
		shadow = false, ownShadow = false, shadowAlpha = E.tokens.shadow.alpha, shadowSize = E.tokens.shadow.size,
		clickThrough = false, tooltip = true, art = "", labels = labels }
end

-- Three label slots on every look; the single label of earlier builds
-- (label, labelPoint) becomes the first.
local function NormalizeLook(look)
	if type(look.labels) ~= "table" then look.labels = {} end
	for index = 1, MAX_LABELS do
		if type(look.labels[index]) ~= "table" then look.labels[index] = { text = "", point = LABEL_DEFAULT_POINTS[index] } end
		local label = look.labels[index]
		if type(label.text) ~= "string" then label.text = "" end
		if type(label.point) ~= "string" then label.point = LABEL_DEFAULT_POINTS[index] end
	end
	if look.label ~= nil then
		if strtrim(tostring(look.label)) ~= "" and look.labels[1].text == "" then
			look.labels[1].text = tostring(look.label)
			look.labels[1].point = type(look.labelPoint) == "string" and look.labelPoint or "TOP"
		end
		look.label, look.labelPoint = nil, nil
	end
	return look
end

local function IconLook(token)
	local icons = DB().icons
	local look = type(icons) == "table" and token and icons[token]
	return type(look) == "table" and NormalizeLook(look) or nil
end

---------------------------------------------------------------------------
-- Entries of a group: what CooldownRows builds (missing = a placeholder)
---------------------------------------------------------------------------
local function KeepMissing()
	local db = DB()
	return not db.fillGaps or (E:IsMoveMode() and db.showPlaceholders) and true or false
end

local function Entry(token, index)
	local kind, id = Split(token)
	if kind == "spell" then
		local own = P.OwnSpell(id)
		if own and C_Spell.GetSpellTexture(own) then return { spell = own, token = token, index = index } end
		return { missing = true, token = token, index = index, texture = C_Spell.GetSpellTexture(id) }
	elseif kind == "item" then
		local count = P.ItemCount(id)
		local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
		if count == 0 and M.db.rows.items.empty == "hide" then return { missing = true, token = token, index = index, texture = icon } end
		return { item = id, bag = true, empty = count == 0, token = token, index = index }
	elseif kind == "slot" then
		for _, trinket in ipairs(P.TrinketList()) do
			if trinket.slot == id then return { item = trinket.item, slot = id, token = token, index = index } end
		end
		return { missing = true, token = token, index = index, texture = GetInventoryItemTexture("player", id) }
	end
end

local function GroupEntries(group)
	local keep = KeepMissing()
	local list = {}
	for index, token in ipairs(Parse(group.list)) do
		local entry = Entry(token, index)
		if entry and (keep or not entry.missing) then list[#list + 1] = entry end
	end
	return list
end

---------------------------------------------------------------------------
-- Smooth movement: an icon that changes spot glides there from where it
-- was on screen. Only EldoUI's own icons (plain frames, never protected)
-- move, by their anchor offset; General > Animations off makes them jump.
---------------------------------------------------------------------------
local SLIDE_TIME = 0.2
local sliding = {}   -- icon -> { fromX, fromY, dx, dy, t }
local slider = CreateFrame("Frame", nil, UIParent)
slider:Hide()

local function Animations()
	return E.db and E.db.general and E.db.general.animations ~= false
end

local function SmoothOn()
	local db = DB()
	return db and db.smoothMove and Animations() and true or false
end

local function Anchor(item, offsetX, offsetY)
	local at = item.slideAt
	at.ax, at.ay = at.x + (offsetX or 0), -at.y + (offsetY or 0)
	item:ClearAllPoints()
	item:SetPoint("CENTER", at.container, "TOPLEFT", at.ax, at.ay)
end

-- False once something else (the fixed rows' grid) placed the icon.
local function StillOurs(item, at)
	local point, rel, _, x, y = item:GetPoint(1)
	return point == "CENTER" and rel == at.container and x == at.ax and y == at.ay
end

slider:SetScript("OnUpdate", function(self, elapsed)
	for item, slide in pairs(sliding) do
		local at = item.slideAt
		if not (at and item:IsShown() and StillOurs(item, at)) then
			sliding[item] = nil
		elseif InCombatLockdown() and item:IsProtected() then -- EldoUI's own icons
			sliding[item] = nil
			Anchor(item)
		else
			if not slide.dx then
				-- First frame: the new spot is laid out now; slide from the old one.
				local x, y = item:GetCenter()
				if K.Plain(x, y) and x and y then
					slide.dx, slide.dy = slide.fromX - x, slide.fromY - y
				else
					slide.dx, slide.dy = 0, 0
				end
			end
			slide.t = slide.t + (tonumber(elapsed) or 0)
			local progress = math.min(1, slide.t / SLIDE_TIME)
			local left = (1 - progress) * (1 - progress) -- ease out
			if progress >= 1 or (math.abs(slide.dx) < 0.5 and math.abs(slide.dy) < 0.5) then
				sliding[item] = nil
				Anchor(item)
			else
				Anchor(item, slide.dx * left, slide.dy * left)
			end
		end
	end
	if next(sliding) == nil then self:Hide() end
end)

-- Put an icon on its spot in the group; it slides there when smooth
-- movement is on and it was already on show in this group.
local function Place(item, container, x, y)
	local at = item.slideAt
	local fromX, fromY
	if at and at.container == container and SmoothOn() and not (InCombatLockdown() and item:IsProtected()) then -- EldoUI's own icons
		local cx, cy = item:GetCenter()
		if K.Plain(cx, cy) and cx and cy then fromX, fromY = cx, cy end
	end
	if not at then
		at = {}
		item.slideAt = at
	end
	at.container, at.x, at.y = container, x, y
	Anchor(item)
	if fromX then
		sliding[item] = { fromX = fromX, fromY = fromY, t = 0 }
		slider:Show()
	else
		sliding[item] = nil
	end
end

-- An icon that left the group starts fresh when it shows again.
local function Unplace(item)
	item.slideAt = nil
	sliding[item] = nil
end

---------------------------------------------------------------------------
-- Layout of a group: grid (even cells) or flex (each icon its own size).
-- Matches the rows' grid when no icon has a look of its own.
---------------------------------------------------------------------------
function M.GroupFlow(items, container, db)
	local size = math.max(8, tonumber(db.size) or 36)
	local spacing = math.max(0, tonumber(db.spacing) or 4)
	local perRow = math.max(1, math.floor(tonumber(db.perRow) or 8))
	local flex = db.layout == "flex"
	local vertical = db.growth == "UP" or db.growth == "DOWN"
	if #items == 0 then
		container:SetSize(size, size)
		return
	end
	-- Cell sizes: grid cells fit the largest icon, flex cells each icon.
	local cellW, cellH = size, size
	if not flex then
		for _, item in ipairs(items) do
			cellW, cellH = math.max(cellW, item.cellW or size), math.max(cellH, item.cellH or size)
		end
	end
	local lines = {}
	for index, item in ipairs(items) do
		local w, h = item.cellW or size, item.cellH or size
		local cw, ch = flex and w or cellW, flex and h or cellH
		local n = math.floor((index - 1) / perRow) + 1
		local line = lines[n]
		if not line then
			line = { items = {}, along = 0, across = 0 }
			lines[n] = line
		end
		local along, across = vertical and ch or cw, vertical and cw or ch
		line.items[#line.items + 1] = { item = item, w = w, h = h, along = along }
		line.along = line.along + along + (#line.items > 1 and spacing or 0)
		line.across = math.max(line.across, across)
	end
	local maxAlong, totalAcross = 0, 0
	for index, line in ipairs(lines) do
		maxAlong = math.max(maxAlong, line.along)
		totalAcross = totalAcross + line.across + (index > 1 and spacing or 0)
	end
	local width, height = maxAlong, totalAcross
	if vertical then width, height = totalAcross, maxAlong end
	local backwards = db.growth == "LEFT" or db.growth == "UP"
	local fromEnd = not vertical and db.wrap == "UP"
	local acrossAt = 0
	for _, line in ipairs(lines) do
		local start = 0
		if db.growth == "CENTER" then start = (maxAlong - line.along) / 2 end
		local at = start
		local mid = acrossAt + line.across / 2
		for _, cell in ipairs(line.items) do
			local centre = at + cell.along / 2
			if backwards then centre = maxAlong - centre end
			local x, y
			if vertical then
				x, y = mid, centre
				if db.growth == "UP" then y = maxAlong - (at + cell.along / 2) end
				if db.growth == "DOWN" then y = at + cell.along / 2 end
			else
				x, y = centre, fromEnd and (totalAcross - mid) or mid
			end
			local item = cell.item
			item:SetScale(1)
			item:SetSize(cell.w, cell.h)
			Place(item, container, x, y)
			at = at + cell.along + spacing
		end
		acrossAt = acrossAt + line.across + spacing
	end
	container:SetSize(math.max(width, 1), math.max(height, 1))
end

---------------------------------------------------------------------------
-- Dressing an icon: its own look, the label and the drag handle
---------------------------------------------------------------------------
local Dress -- forward (the handle's click needs the module functions below)

local function Cursor()
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	if not (K.Plain(x, y, scale) and x and y and scale and scale > 0) then return nil end
	return x / scale, y / scale
end

local ghost
local function Ghost()
	if ghost then return ghost end
	ghost = CreateFrame("Frame", nil, UIParent)
	ghost:SetFrameStrata("TOOLTIP")
	ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
	ghost.icon:SetAllPoints()
	E:TrimIcon(ghost.icon)
	ghost:SetAlpha(0.75)
	ghost:Hide()
	return ghost
end

local function StartDrag(button)
	if InCombatLockdown() or not button.token then return end
	local frame = Ghost()
	frame.source = { token = button.token, key = button.groupKey, index = button.listIndex }
	frame:SetSize(button:GetSize())
	frame.icon:SetTexture(button.icon:GetTexture())
	frame:Show()
	frame:SetScript("OnUpdate", function(self)
		local x, y = Cursor()
		if not x then return end
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	end)
end

local function StopDrag()
	local frame = ghost
	if not (frame and frame.source) then return end
	frame:SetScript("OnUpdate", nil)
	frame:Hide()
	local source = frame.source
	frame.source = nil
	local x, y = Cursor()
	if x then M:DropIcon(source, x, y) end
end

local function Handle(button)
	if button.dragHandle then return button.dragHandle end
	local handle = CreateFrame("Button", nil, button)
	handle:SetSize(14, 14)
	handle:SetPoint("TOPLEFT", button, "TOPLEFT", -3, 3)
	handle:SetFrameStrata("FULLSCREEN")
	E:SetTemplate(handle)
	local accent = E.media.accentColor or { 0.2, 0.67, 1 }
	handle:SetBackdropColor(accent[1] or 0.2, accent[2] or 0.67, accent[3] or 1, 0.9)
	handle.text = E:CreateText(handle, E.tokens.size.tiny)
	handle.text:SetPoint("CENTER", 0, 0)
	handle.text:SetText("+")
	handle:RegisterForDrag("LeftButton")
	handle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	handle:SetScript("OnDragStart", function() StartDrag(button) end)
	handle:SetScript("OnDragStop", StopDrag)
	handle:SetScript("OnClick", function(self, mouse)
		if E:IsOptionsLinkClick(self, mouse) then return end
		M:EditIcon(button.token)
	end)
	handle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(Describe(button.token))
		E:TooltipHint(GameTooltip, { L["Drag"], L["into another group, between two icons, or onto empty screen for a free icon"] },
			{ L["Click"], L["this icon's settings"] })
		GameTooltip:Show()
	end)
	handle:SetScript("OnLeave", function() GameTooltip:Hide() end)
	E:BindOptionsLink(handle, { page = "module:CooldownManager" })
	button.dragHandle = handle
	return handle
end

---------------------------------------------------------------------------
-- Labels: up to three texts per icon, written with EldoUI's text tags
-- (Core/Tags.lua). Unit tags read the player ("[power:percent]"); the
-- icon tags below read the icon the label sits on. Tag values go to
-- SetText as the game gives them (secret values included); nothing here
-- compares or measures them.
---------------------------------------------------------------------------
local labelIcon            -- the icon a label is rendered for (icon tags read it)
local labelled = setmetatable({}, { __mode = "k" })   -- icon -> { [index] = tag string }

local function IconSpell(button)
	return button and K.Plain(button.spellID) and button.spellID or nil
end

E:RegisterTag("cd:name", function()
	local button = labelIcon
	if not button then return "" end
	local spell = IconSpell(button)
	if spell then
		local name = C_Spell.GetSpellName and C_Spell.GetSpellName(spell)
		return type(name) == "string" and name or ""
	end
	local item = K.Plain(button.itemID) and button.itemID
	if item then
		local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(item)
		return type(name) == "string" and name or ""
	end
	return ""
end, nil, { category = "Cooldown icons", desc = L["On a cooldown icon's label: the name of its spell or item. Empty everywhere else."] })

E:RegisterTag("cd:key", function()
	local spell = IconSpell(labelIcon)
	return spell and M.SpellKeyBinding and M.SpellKeyBinding(spell) or ""
end, "UPDATE_BINDINGS ACTIONBAR_SLOT_CHANGED", { category = "Cooldown icons",
	desc = L["On a cooldown icon's label: the key bound to the action button that holds its spell. Empty everywhere else."] })

local function RenderLabel(button, index)
	local text = labelled[button] and labelled[button][index]
	local fontString = button.groupLabels and button.groupLabels[index]
	if not (text and fontString) then return end
	labelIcon = button
	E:RenderTag(fontString, text, "player")
	labelIcon = nil
end

local function RefreshLabels()
	for button, texts in pairs(labelled) do
		if button:IsVisible() then
			for index in pairs(texts) do RenderLabel(button, index) end
		end
	end
end

-- The events and the ticker the label tags need (after every rebuild).
local labelEvents, labelTicker = {}, nil
local function LabelEvent(_, event, unit)
	if event:sub(1, 5) == "UNIT_" and unit ~= "player" then return end
	if event == "UPDATE_BINDINGS" or event == "ACTIONBAR_SLOT_CHANGED" then
		-- The module drops its keybind cache on these; read after it.
		C_Timer.After(0.2, RefreshLabels)
		return
	end
	RefreshLabels()
end

local function UpdateLabelEvents()
	local wanted, timer = {}, false
	for button, texts in pairs(labelled) do
		if button:IsVisible() then
			for _, text in pairs(texts) do
				for _, event in ipairs(E:TagEvents(text)) do wanted[event] = true end
				if E:TagUsesTimer(text) then timer = true end
			end
		end
	end
	for event in pairs(labelEvents) do
		if not wanted[event] then
			E:UnregisterEvent(event, "cdglabels")
			labelEvents[event] = nil
		end
	end
	for event in pairs(wanted) do
		if not labelEvents[event] then
			E:RegisterEvent(event, LabelEvent, "cdglabels")
			labelEvents[event] = true
		end
	end
	if timer and not labelTicker then
		labelTicker = C_Timer.NewTicker(0.5, RefreshLabels)
	elseif not timer and labelTicker then
		labelTicker:Cancel()
		labelTicker = nil
	end
end

local function LabelString(button, index)
	button.groupLabels = button.groupLabels or {}
	local fontString = button.groupLabels[index]
	if fontString then return fontString end
	if not button.labelOverlay then
		local overlay = CreateFrame("Frame", nil, button)
		overlay:SetAllPoints()
		overlay:SetFrameLevel(button.cooldown:GetFrameLevel() + 3)
		button.labelOverlay = overlay
	end
	fontString = button.labelOverlay:CreateFontString(nil, "OVERLAY")
	button.groupLabels[index] = fontString
	return fontString
end

local LABEL_POINTS = {
	TOP = { "BOTTOM", "TOP", 0, 2 }, BOTTOM = { "TOP", "BOTTOM", 0, -2 },
	CENTER = { "CENTER", "CENTER", 0, 0 }, INSIDE_TOP = { "TOP", "TOP", 0, -2 }, INSIDE_BOTTOM = { "BOTTOM", "BOTTOM", 0, 2 },
	LEFT = { "RIGHT", "LEFT", -2, 0 }, RIGHT = { "LEFT", "RIGHT", 2, 0 },
}

local function DressLabels(button, look, size)
	local texts
	for index = 1, MAX_LABELS do
		local label = look and look.labels and look.labels[index]
		local text = label and strtrim(tostring(label.text or "")) or ""
		local fontString = (text ~= "" or (button.groupLabels and button.groupLabels[index])) and LabelString(button, index)
		if fontString then
			if text ~= "" then
				local where = LABEL_POINTS[label.point] or LABEL_POINTS.TOP
				fontString:SetFont(M.FontFile(), math.max(9, math.floor(size * 0.28)), M.Outline())
				fontString:ClearAllPoints()
				fontString:SetPoint(where[1], button, where[2], where[3], where[4])
				texts = texts or {}
				texts[index] = text
				fontString:Show()
			else
				fontString:SetText("")
				fontString:Hide()
			end
		end
	end
	labelled[button] = texts
	if texts then
		for index in pairs(texts) do RenderLabel(button, index) end
	end
end

-- Crop the icon art to the icon's shape (and zoom).
local function Crop(button, w, h, zoom)
	local z = math.max(0, math.min(0.3, zoom))
	local left, right, top, bottom = z, 1 - z, z, 1 - z
	local span = 1 - 2 * z
	if w > h then
		local keep = span * h / w
		top, bottom = 0.5 - keep / 2, 0.5 + keep / 2
	elseif h > w then
		local keep = span * w / h
		left, right = 0.5 - keep / 2, 0.5 + keep / 2
	end
	button.icon:SetTexCoord(left, right, top, bottom)
end

Dress = function(button, entry, row)
	local look = entry and IconLook(entry.token)
	local size = tonumber(row.db and row.db.size) or 36
	if look then
		local own = tonumber(look.size) or 0
		local base = own > 0 and own or size
		local ratio = ASPECTS[tostring(look.aspect)] or 1
		local w, h = base, base
		if ratio > 1 then h = math.floor(base / ratio + 0.5) elseif ratio < 1 then w = math.floor(base * ratio + 0.5) end
		if own > 0 or ratio ~= 1 then button.cellW, button.cellH = w, h else button.cellW, button.cellH = nil, nil end
		local zoom = look.ownZoom and (tonumber(look.zoom) or 0) / 100 or (M.db.zoom or 8) / 100
		if look.ownZoom or ratio ~= 1 then Crop(button, w, h, zoom) end
		local art = strtrim(tostring(look.art or ""))
		if art ~= "" and entry and not entry.missing then button.icon:SetTexture(tonumber(art) or art) end
	else
		button.cellW, button.cellH = nil, nil
	end
	-- Border.
	local border = look and look.border or "theme"
	if border == "custom" then
		local c = look.borderColor or { 1, 0.82, 0 }
		button:SetBackdropBorderColor(c[1] or 1, c[2] or 1, c[3] or 1, 1)
	elseif border == "none" then
		button:SetBackdropBorderColor(0, 0, 0, 0)
	else
		button:SetBackdropBorderColor(unpack(E.media.borderColor))
	end
	E:UpdateShadow(button, look and look.shadow and true or false,
		look and look.ownShadow and { alpha = look.shadowAlpha, size = look.shadowSize } or nil)
	button:EnableMouse(not (look and look.clickThrough))
	button.noTooltip = look and look.tooltip == false or nil
	-- Labels (none on a placeholder or an unused icon).
	DressLabels(button, entry and not entry.missing and look or nil, size)
	-- A button that now shows another icon (or none) does not slide.
	local token = entry and entry.token or nil
	if button.placedToken ~= token then Unplace(button) end
	button.placedToken = token
	button.groupDressed = entry ~= nil or nil
	-- Drag handle: move mode, out of combat.
	local db = DB()
	local handleOn = entry ~= nil and db.dragHandles and E:IsMoveMode() and not InCombatLockdown()
	if handleOn then
		Handle(button):Show()
	elseif button.dragHandle then
		button.dragHandle:Hide()
	end
end

-- Back to the plain row look (own groups turned off: the fixed rows reuse
-- the icons of the groups that stood in for them).
function M.UndressIcon(button)
	Dress(button, nil, {})
end

---------------------------------------------------------------------------
-- Group rows for CooldownRows.lua
---------------------------------------------------------------------------
local function GroupDB(group)
	if group.from then
		if VIEWER_OF[group.from] then return M.db.viewers[VIEWER_OF[group.from]] end
		return M.db.rows[group.from]
	end
	return group
end

local function GroupRow(group)
	local key = GroupKey(group)
	local row = { key = key, kind = "group", from = group.from, lookKey = group.from or "main", db = GroupDB(group),
		entries = function() return GroupEntries(group) end, layout = M.GroupFlow, dress = Dress }
	-- Own visibility: the group's block instead of its row's (or the main row's).
	if group.ownVisibility and type(group.visibility) == "table" then row.visibility = group.visibility end
	if not group.from then
		local name = GROUP_MOVER .. group.id
		row.holderName = name
		-- The mover shows and hides with its group, so a group that is off
		-- (or not in this profile) leaves no box in move mode.
		row.holder = function()
			return K.GetHolder(name) or K.Holder(M, name, L["Cooldown Group %d"]:format(group.id),
				{ "TOP", MAIN_MOVER, "BOTTOM", 0, -100 - ((group.id - 1) % 4) * 50 }, 100, 36, { followShown = true })
		end
	end
	return row
end

-- The free icon's saved position goes into the layout in use too, so a
-- talent group with its own layout keeps its own free icon spots.
local function RememberFree(token)
	local db = DB()
	if not (db and db.enabled) then return end
	local saved = E.db.movers and E.db.movers[FreeMover(token)]
	local layout = M.GroupLayout()
	if not layout.free[token] then return end
	-- No saved spot (a layout preset put it back): the default spot, everywhere.
	layout.freePos[token] = type(saved) == "table" and CopyTable(saved) or nil
end

local function SamePosition(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for index = 1, 5 do
		if a[index] ~= b[index] then return false end
	end
	return true
end

-- Free icon movers to the spots the layout in use remembers (after a
-- talent group swap). Out of combat only: E:SaveMoverPosition moves them.
local function RestoreFree(layout)
	for token, on in pairs(layout.free) do
		local pos = on and layout.freePos[token]
		local name = FreeMover(token)
		if type(pos) == "table" and not SamePosition(pos, E.db.movers[name]) then
			E:SaveMoverPosition(name, pos[1], pos[2], pos[3], tonumber(pos[4]) or 0, tonumber(pos[5]) or 0)
		end
	end
end

local watched = {}
-- A free icon dragged in move mode is saved relative to the main row, so
-- it follows the row when a layout preset moves it.
local function KeepOnMainRow(name, token)
	if watched[name] then return end
	watched[name] = true
	E:RegisterMoverCallback(name, function(mover, _, rel)
		if rel == MAIN_MOVER then
			RememberFree(token)
			return
		end
		local main = E.movers.EldoUI_Cooldowns
		if not (main and main.GetCenter and mover.GetCenter) then return end
		local mx, my = main:GetCenter()
		local x, y = mover:GetCenter()
		if not (K.Plain(mx, my, x, y) and mx and x) then return end
		E:SaveMoverPosition(name, "CENTER", MAIN_MOVER, "CENTER", x - mx, y - my)
	end)
end

local function FreeRow(token)
	local name = FreeMover(token)
	local essential = M.db.viewers.essential
	local db = { size = essential.size or 36, spacing = 0, perRow = 1, growth = "CENTER", wrap = "DOWN",
		countSize = essential.countSize, countdownSize = essential.countdownSize, keybindSize = essential.keybindSize }
	return { key = FreeKey(token), kind = "group", lookKey = "main", db = db, holderName = name,
		entries = function()
			local entry = Entry(token, 1)
			if entry and entry.missing and not KeepMissing() then return {} end
			return { entry }
		end,
		layout = M.GroupFlow, dress = Dress,
		holder = function()
			local holder = K.GetHolder(name)
			if not holder then
				-- Shows and hides with the icon, like an own group's mover.
				holder = K.Holder(M, name, L["Cooldown Icon: %s"]:format((Describe(token))), { "CENTER", MAIN_MOVER, "CENTER", 0, 90 }, db.size, db.size,
					{ followShown = true })
				KeepOnMainRow(name, token)
			end
			return holder
		end }
end

-- The rows to build while own groups are on (nil = the fixed rows).
function M.GroupRows()
	local db = DB()
	if not (db and db.enabled) then return nil end
	local layout = M.GroupLayout()
	local rows = {}
	for _, group in ipairs(layout.groups) do rows[#rows + 1] = GroupRow(group) end
	local free = {}
	for token, on in pairs(layout.free) do
		if on and Split(token) then free[#free + 1] = token end
	end
	table.sort(free)
	for _, token in ipairs(free) do rows[#rows + 1] = FreeRow(token) end
	return rows
end

---------------------------------------------------------------------------
-- Drag and drop
---------------------------------------------------------------------------
local function Rect(frame)
	if not (frame and frame:IsShown()) then return nil end
	local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
	if not (K.Plain(left, right, top, bottom) and left and right and top and bottom) then return nil end
	return left, right, top, bottom
end

local MARGIN = 6

-- The group under the point and where in it: group, insert position.
local function DropTarget(layout, x, y)
	for _, group in ipairs(layout.groups) do
		local key = GroupKey(group)
		local frame = M.rowFrames[key]
		local left, right, top, bottom = Rect(frame)
		if not left and not group.from then left, right, top, bottom = Rect(K.GetHolder(GROUP_MOVER .. group.id)) end
		if left and x >= left - MARGIN and x <= right + MARGIN and y >= bottom - MARGIN and y <= top + MARGIN then
			-- Nearest icon decides the spot: before it or after it.
			local db = GroupDB(group)
			local vertical = db.growth == "UP" or db.growth == "DOWN"
			local best, bestDistance
			for _, button in ipairs(M.rowIcons[key] or {}) do
				if button:IsShown() and button.listIndex then
					local cx, cy = button:GetCenter()
					if K.Plain(cx, cy) and cx then
						local distance = (cx - x) ^ 2 + (cy - y) ^ 2
						if not bestDistance or distance < bestDistance then best, bestDistance = button, distance end
					end
				end
			end
			if not best then return group, #Parse(group.list) + 1 end
			local cx, cy = best:GetCenter()
			local before
			if vertical then
				before = (db.growth == "UP") == (y < cy)
			else
				before = (db.growth == "LEFT") == (x > cx)
			end
			return group, before and best.listIndex or best.listIndex + 1
		end
	end
end

-- Take the icon out of where it was. Returns true when found.
local function TakeOut(layout, source)
	if source.key and source.key:sub(1, 2) == "f:" then
		local had = layout.free[source.token] and true or false
		layout.free[source.token] = nil
		layout.freePos[source.token] = nil
		return had
	end
	local group = FindGroup(layout, source.key)
	if not group then return false end
	local tokens = Parse(group.list)
	local at = tokens[source.index] == source.token and source.index or nil
	if not at then
		for index, token in ipairs(tokens) do
			if token == source.token then at = index break end
		end
	end
	if not at then return false end
	table.remove(tokens, at)
	group.list = Join(tokens)
	return true, group, at
end

-- Drop an icon at a screen point (UIParent units). source = { token, key
-- (group key or free key), index (position in the group's list) }.
function M:DropIcon(source, x, y)
	local db = DB()
	if InCombatLockdown() or not (db and db.enabled and source and source.token and x and y) then return false end
	local layout = M.GroupLayout()
	local target, position = DropTarget(layout, x, y)
	-- A second copy onto empty screen while the icon is already free there:
	-- refused, so neither copy nor the free icon's spot is lost.
	if not target and layout.free[source.token] and source.key ~= FreeKey(source.token) then
		self:Print(L["%s is already a free icon. Drag that one to move it."]:format((Describe(source.token))))
		return false
	end
	local found, fromGroup, fromIndex = TakeOut(layout, source)
	if not found then return false end
	if target then
		local tokens = Parse(target.list)
		if fromGroup == target and fromIndex and fromIndex < position then position = position - 1 end
		position = math.max(1, math.min(position, #tokens + 1))
		table.insert(tokens, position, source.token)
		target.list = Join(tokens)
	else
		-- Empty screen: a free icon there, placed relative to the main row.
		layout.free[source.token] = true
		local main = E.movers.EldoUI_Cooldowns
		local mx, my
		if main and main.GetCenter then mx, my = main:GetCenter() end
		if K.Plain(mx, my) and mx and my then
			E:SaveMoverPosition(FreeMover(source.token), "CENTER", MAIN_MOVER, "CENTER", x - mx, y - my)
		else
			E:SaveMoverPosition(FreeMover(source.token), "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", x, y)
		end
		RememberFree(source.token)
	end
	self:ApplyRows()
	if E.RefreshConfig then E:RefreshConfig() end
	return true
end

-- Pick one icon for its settings (handle click). The settings window opens
-- only with /eui; an open window shows the icon at once.
function M:EditIcon(token)
	if not token then return end
	DB().editIcon = token
	if E.ConfigOpenAllowed and not E:ConfigOpenAllowed() then
		E:Print(L["Icon picked. Its settings are in %s > Cooldown Manager."]:format(E:Highlight("/eui")))
	end
	if E.RefreshConfig then E:RefreshConfig() end
end

---------------------------------------------------------------------------
-- Groups: new, remove, back to the rows
---------------------------------------------------------------------------
function M:NewGroup()
	local layout = M.GroupLayout()
	if #layout.groups >= MAX_GROUPS then
		self:Print(L["You have the most groups there can be (%d)."]:format(MAX_GROUPS))
		return nil
	end
	local essential = M.db.viewers.essential
	local group = { id = layout.nextId, name = L["Group %d"]:format(layout.nextId), list = "",
		size = essential.size or 36, spacing = essential.spacing or 4, perRow = 8, growth = "CENTER", wrap = "DOWN", layout = "grid" }
	layout.nextId = layout.nextId + 1
	layout.groups[#layout.groups + 1] = group
	DB().edit = GroupKey(group)
	self:ApplyRows()
	if E.RefreshConfig then E:RefreshConfig() end
	return group
end

function M:RemoveGroup(key)
	local layout = M.GroupLayout()
	local group, index = FindGroup(layout, key or DB().edit)
	if not group or group.from then return false end
	table.remove(layout.groups, index)
	DB().edit = "main"
	self:ApplyRows()
	if E.RefreshConfig then E:RefreshConfig() end
	return true
end

function M:ResetGroups()
	local data = ClassData()
	local fresh = FromRows()
	if DB().perTalentGroup then data.talents[E:TalentGroup()] = fresh else data.layout = fresh end
	DB().edit = "main"
	self:ApplyRows()
	if E.RefreshConfig then E:RefreshConfig() end
end

---------------------------------------------------------------------------
-- Events: move mode (handles, placeholders) and talent group swaps
---------------------------------------------------------------------------
local function Rebuild()
	if M.active and DB() and DB().enabled and M.ApplyRows then M:ApplyRows() end
end

hooksecurefunc(E, "ToggleMoveMode", function()
	if not InCombatLockdown() then Rebuild() end
end)

-- After every rebuild: the free icons of this layout on their own spots,
-- and the label tags listening to the events they need.
hooksecurefunc(M, "ApplyRows", function()
	local db = DB()
	if db and db.enabled and M.active and not InCombatLockdown() then RestoreFree(M.GroupLayout()) end
	UpdateLabelEvents()
end)
hooksecurefunc(M, "HideRows", UpdateLabelEvents)

-- Style presets "Centered groups" and "Left groups" (CooldownManager.lua)
-- also line up the groups of your own: every layout of this class.
M.GROUP_STYLES = { CenteredGroups = "CENTER", LeftGroups = "RIGHT" }
hooksecurefunc(E, "ApplyStyle", function(_, moduleName, styleKey)
	local growth = moduleName == "CooldownManager" and M.GROUP_STYLES[styleKey]
	if not (growth and M.db and DB()) then return end
	local data = ClassData()
	local layouts = { data.layout }
	for _, layout in pairs(data.talents) do layouts[#layouts + 1] = layout end
	for _, layout in ipairs(layouts) do
		if Valid(layout) then
			for _, group in ipairs(layout.groups) do
				if not group.from then group.growth, group.wrap = growth, "DOWN" end
			end
		end
	end
	E:RunOutOfCombat(Rebuild)
end)
hooksecurefunc(M, "UpdateRowKeybinds", RefreshLabels)

local function TalentSwap()
	if DB() and DB().perTalentGroup then E:RunOutOfCombat(Rebuild) end
end
E:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", TalentSwap, "cdmgroups")
E:RegisterEvent("PLAYER_TALENT_UPDATE", TalentSwap, "cdmgroups")

---------------------------------------------------------------------------
-- Options: Groups and Icon tabs on the Cooldown Manager page
---------------------------------------------------------------------------
local function Off() return not (DB() and DB().enabled) end

local function Editing()
	local layout = M.GroupLayout()
	local group, index = FindGroup(layout, DB().edit)
	if not group then group, index = layout.groups[1], 1 end
	-- Every group carries a visibility block for its Visibility rows.
	if group and type(group.visibility) ~= "table" then group.visibility = E:VisibilityDefaults() end
	return group, index
end

local function G(field)
	return function()
		local _, index = Editing()
		return ("%s.groups.%d.%s"):format(LayoutPath(), index or 1, field)
	end
end
local function FromRow() local group = Editing() return Off() or not group or group.from ~= nil end
local function OwnGroup() local group = Editing() return Off() or not group or group.from == nil end

local function GroupValues()
	local values = {}
	if Off() then return { main = ROW_NAMES.main } end
	for _, group in ipairs(M.GroupLayout().groups) do
		values[GroupKey(group)] = tostring(group.name or GroupKey(group))
	end
	return values
end

-- Every icon of the layout in use, for the Icon tab.
local function IconValues()
	local values = {}
	if not Off() then
		local layout = M.GroupLayout()
		for _, group in ipairs(layout.groups) do
			for _, token in ipairs(Parse(group.list)) do values[token] = L["%s (%s)"]:format((Describe(token)), group.name or "") end
		end
		for token in pairs(layout.free) do values[token] = L["%s (free)"]:format((Describe(token))) end
	end
	if not next(values) then values[""] = L["(no icons yet)"] end
	return values
end

local function EditToken()
	local token = DB() and DB().editIcon
	if type(token) ~= "string" or not Split(token) then return nil end
	return token
end
local function NoIcon() return Off() or EditToken() == nil end

-- Keys of the Icon tab: the chosen icon's look, filled with defaults first
-- so every row shows the value in use.
local function I(field)
	return function()
		local token = EditToken() or "none"
		local icons = DB().icons
		if type(icons) ~= "table" then icons = {} DB().icons = icons end
		if token ~= "none" and type(icons[token]) ~= "table" then icons[token] = IconDefaults() end
		if token ~= "none" then NormalizeLook(icons[token]) end
		return ("cdgroups.icons.%s.%s"):format(token, field)
	end
end
local function EditLook() return IconLook(EditToken()) or IconDefaults() end

---------------------------------------------------------------------------
-- The edited group's icons as a list (DESIGN.md §0a rules 5 and 6): one
-- two-line row per icon (its art, its name, a muted line with what it is
-- and the key it is bound to; icons that can't show right now are
-- dimmed), small boxed buttons to move it up or down or take it out, and
-- a click on a row opens its look on the Icon tab. The group's tools sit
-- on a slim icon rail on the right: a new group, move mode to drag icons,
-- keybind mode to bind their keys.
---------------------------------------------------------------------------
local LIST_ROWS = 8 -- rows shown before the list scrolls
local LIST_INSET = 16 -- the block's inset around the list, top and bottom together

local function IconLine(token)
	local kind, id = Split(token)
	if kind == "spell" then
		local own = P.OwnSpell(id)
		local key = own and M.SpellKeyBinding and M.SpellKeyBinding(own)
		if not own then return L["Spell, not known yet"], true end
		if type(key) == "string" and key ~= "" then return L["Spell, key %s"]:format(key), false end
		return L["Spell, no key bound"], false
	elseif kind == "item" then
		local count = P.ItemCount(id)
		if count == 0 then return L["Item, none in your bags"], true end
		return count and L["Item, %d in your bags"]:format(count) or L["Item"], false
	elseif kind == "slot" then
		local item = GetInventoryItemID("player", id)
		return L["Trinket slot %d"]:format(id), not (K.Plain(item) and item)
	end
	return "", false
end

local function ListTokens()
	local group = Editing()
	return group and Parse(group.list) or {}, group
end

-- Move or take out the icon at index; the group's list text follows.
function M:EditGroupIcon(index, action)
	local tokens, group = ListTokens()
	if not (group and tokens[index]) then return false end
	if action == "up" and index > 1 then
		tokens[index], tokens[index - 1] = tokens[index - 1], tokens[index]
	elseif action == "down" and index < #tokens then
		tokens[index], tokens[index + 1] = tokens[index + 1], tokens[index]
	elseif action == "remove" then
		table.remove(tokens, index)
	else
		return false
	end
	group.list = Join(tokens)
	E:RunOutOfCombat(Rebuild)
	if E.RefreshConfig then E:RefreshConfig() end
	return true
end

-- The rows of the list: { token, index, name, icon, sub, dimmed, first, last }.
function M:GroupIconItems()
	local tokens = ListTokens()
	local items = {}
	for index, token in ipairs(tokens) do
		local name, icon = Describe(token)
		local sub, dimmed = IconLine(token)
		items[index] = { token = token, index = index, name = name, icon = icon, sub = sub, dimmed = dimmed,
			first = index == 1, last = index == #tokens }
	end
	return items
end

local iconList = { type = "preview", height = 96, hidden = Off }

local function ListHeight(count)
	local rows = math.min(math.max(count, 2), LIST_ROWS)
	return rows * E.UIKit.TwoLineRowHeight() + LIST_INSET
end

local function FillIconList(canvas, building)
	local items = M:GroupIconItems()
	-- The block grows with the group: a new height lays the page out again
	-- (while the page is being built, its layout reads the new one).
	local height = ListHeight(#items)
	if iconList.height ~= height then
		iconList.height = height
		if not building and E.RefreshConfig and not canvas.relayout then
			canvas.relayout = true
			E:RefreshConfig()
			canvas.relayout = nil
		end
	end
	canvas.list:SetHeight(height - LIST_INSET)
	canvas.list:SetData(items)
end

function iconList.create(canvas)
	if not canvas then return end
	local Kit = E.UIKit
	canvas.rail = Kit.IconRail(canvas, { side = "RIGHT", buttons = {
		{ key = "new", art = "copy", tipTitle = L["New group"], tip = L["Adds an empty group with its own mover (Cooldown Group N in move mode)."],
			onClick = function() M:NewGroup() end },
		{ key = "move", art = "move", tipTitle = L["Move mode"], tip = L["Drag icons between groups, or onto empty screen as free icons."],
			onClick = function() E:ToggleMoveMode(true) end },
		{ key = "keys", art = "keybind", tipTitle = L["Bind keys"], tip = L["Keybind mode: hover a button and press a key. The icons show the keys of their spells."],
			onClick = function() E:ToggleKeybindMode(true) end },
	} })
	canvas.rail:SetPoint("TOPRIGHT")
	canvas.rail:SetPoint("BOTTOMRIGHT")
	canvas.list = Kit.CreateList(canvas, Kit.ListRow2Template({
		empty = { title = L["No icons yet"], text = L["Add spells or items in the Icons row above, or drag icons here in move mode."] },
		row = { actions = {
			{ key = "up", art = "chevron-up", tipTitle = L["Move up"], tip = L["One place earlier in the group."],
				onClick = function(item) if item then M:EditGroupIcon(item.index, "up") end end },
			{ key = "down", art = "chevron-down", tipTitle = L["Move down"], tip = L["One place later in the group."],
				onClick = function(item) if item then M:EditGroupIcon(item.index, "down") end end },
			{ key = "remove", art = "cross", danger = true, tipTitle = L["Take out"], tip = L["Takes the icon out of this group."],
				onClick = function(item) if item then M:EditGroupIcon(item.index, "remove") end end },
		} },
		create = function(row)
			row:SetScript("OnClick", function(clicked)
				local item = clicked.item
				if not item then return end
				DB().editIcon = item.token
				E:ShowConfigTab("module:CooldownManager", "Icon")
			end)
			Kit.Tooltip(row, nil, nil, { { L["Click"], L["this icon's look"] } })
		end,
		update = function(row, item)
			row:SetRow({ icon = item.icon, name = item.name, sub = item.sub, dimmed = item.dimmed,
				hide = { up = item.first, down = item.last } })
		end,
	}))
	-- A set height (not a bottom anchor): the rows it holds are known
	-- before the page has placed the block.
	canvas.list:SetPoint("TOPLEFT")
	canvas.list:SetPoint("TOPRIGHT", canvas.rail, "TOPLEFT", -6, 0)
	iconList.canvas = canvas
	FillIconList(canvas, true)
end

function iconList.update(canvas)
	if canvas and canvas.list then FillIconList(canvas) end
end
M.GroupIconList = iconList

local GROWTH = { CENTER = L["Centered"], RIGHT = L["Left to right"], LEFT = L["Right to left"], DOWN = L["Top to bottom"], UP = L["Bottom to top"] }

local groupOptions = {
	{ type = "tab", label = L["Groups"] },
	{ type = "description", label = L["Put EldoUI's cooldown icons in your own groups. In move mode, drag an icon's handle to another group or the screen; click it for settings."] },
	{ type = "toggle", key = "cdgroups.enabled", label = L["Own groups"],
		desc = L["Arrange cooldown icons in your own groups. Off keeps the fixed rows."] },
	{ type = "toggle", key = "cdgroups.dragHandles", label = L["Drag handles in move mode"], hidden = Off,
		desc = L["Shows a small handle on every icon in move mode to drag it or open its settings."] },
	{ type = "toggle", key = "cdgroups.fillGaps", label = L["Close gaps"], hidden = Off,
		desc = L["When an icon can't show (spell not known, item not in your bags), the others move up. Off keeps its spot empty."] },
	{ type = "toggle", less = true, key = "cdgroups.showPlaceholders", label = L["Show placeholders in move mode"], hidden = Off,
		desc = L["Shows faded icons in move mode where hidden icons would sit."] },
	{ type = "toggle", key = "cdgroups.smoothMove", label = L["Smooth movement"], hidden = Off,
		desc = L["Icons slide to their new spot instead of jumping when an icon hides, shows or is dragged. With animations off (General) they jump."] },
	{ type = "toggle", key = "cdgroups.perTalentGroup", label = L["Separate layout per talent group"], hidden = Off,
		desc = L["Each talent group keeps its own groups, free icons and free icon spots. The icon looks stay shared."] },
	{ type = "header", label = L["Group"], hidden = Off },
	{ type = "select", key = "cdgroups.edit", label = L["Edit group"], values = GroupValues, hidden = Off,
		desc = L["The group the rows below change."] },
	{ type = "input", key = G("name"), label = L["Name"], hidden = Off,
		desc = L["The group's name in these settings."] },
	{ type = "input", key = G("list"), label = L["Icons"], hidden = Off,
		desc = L["The icons in order, separated by commas: spell names or IDs, item:ID for items, slot:13 and slot:14 for your trinkets. Dragging icons in move mode changes this list too."] },
	iconList,
	{ type = "description", label = L["This group stands in for one of the fixed rows: its size, layout and position are the row's (Layout and Own rows tabs)."], hidden = FromRow },
	{ type = "select", key = G("layout"), label = L["Layout"], hidden = OwnGroup,
		values = { grid = L["Grid (even cells)"], flex = L["Flex (each icon its own size)"] },
		desc = L["Grid keeps every cell the same size; flex lines icons up by their own size."] },
	{ type = "range", unit = "px", key = G("size"), label = L["Icon size"], min = 16, max = 80, step = 1, hidden = OwnGroup,
		desc = L["Width and height of each icon (an icon's own size wins)."] },
	{ type = "range", unit = "px", key = G("spacing"), label = L["Spacing"], min = 0, max = 20, step = 1, hidden = OwnGroup,
		desc = L["Space between icons."] },
	{ type = "range", key = G("perRow"), label = L["Icons per line"], min = 1, max = 20, step = 1, hidden = OwnGroup,
		desc = L["Icons in one line before a new one starts."] },
	{ type = "select", key = G("growth"), label = L["Growth direction"], values = GROWTH, hidden = OwnGroup,
		desc = L["Which way the icons line up from the group's mover."] },
	{ type = "select", key = G("wrap"), label = L["New lines"], values = { DOWN = "Below", UP = "Above" }, hidden = OwnGroup,
		desc = L["Where a new line starts when a line is full."] },
	{ type = "execute", label = L["Remove group"], confirm = true, hidden = OwnGroup, func = function() M:RemoveGroup() end,
		desc = L["Deletes this group; its icons no longer show. The groups made from the fixed rows can't be removed."] },
	{ type = "execute", label = L["Back to the fixed rows"], confirm = true, hidden = Off, cog = true, func = function() M:ResetGroups() end,
		desc = L["Throws away your groups and free icons (of this talent group when it has its own layout) and makes the fixed rows into groups again."] },

}

local iconOptions = {
	{ type = "tab", label = L["Icon"] },
	{ type = "description", label = L["Turn on Own groups on the Groups tab to give single icons their own look."], hidden = function() return not Off() end },
	{ type = "select", key = "cdgroups.editIcon", label = L["Icon"], values = IconValues, hidden = Off,
		desc = L["The icon the rows below change. Clicking an icon's handle in move mode picks it too."] },
	{ type = "range", key = I("size"), label = L["Size"], min = 0, max = 96, step = 1, hidden = NoIcon,
		zeroText = "Group", desc = L["The icon's own size. Group uses its group's size."] },
	{ type = "select", key = I("aspect"), label = L["Aspect ratio"], hidden = NoIcon,
		values = { ["1"] = L["Square"], ["4:3"] = L["Wide (4:3)"], ["16:9"] = L["Very wide (16:9)"], ["3:4"] = L["Tall (3:4)"] },
		desc = L["The icon's shape; the art is cropped to fit."] },
	{ type = "toggle", key = I("ownZoom"), label = L["Own zoom"], hidden = NoIcon,
		desc = L["Zoom this icon's art by its own amount instead of the module's."] },
	{ type = "range", key = I("zoom"), label = L["Zoom"], min = 0, max = 30, step = 1, hidden = function() return NoIcon() or not EditLook().ownZoom end,
		desc = L["How much of the art's edge is cut off, in percent."] },
	{ type = "select", key = I("border"), label = L["Border"], hidden = NoIcon,
		values = { theme = L["Theme"], custom = L["Own color"], none = L["None"] },
		desc = L["The icon's 1 px border: the theme color, an own color or none."] },
	{ type = "color", key = I("borderColor"), label = L["Border color"], hidden = function() return NoIcon() or EditLook().border ~= "custom" end,
		desc = L["The border color of this icon."] },
	{ type = "toggle", key = I("shadow"), label = L["Shadow"], hidden = NoIcon,
		desc = L["A soft dark shadow around the icon."] },
	{ type = "toggle", key = I("ownShadow"), label = L["Own shadow look"], hidden = function() return NoIcon() or not EditLook().shadow end,
		desc = L["Give this icon's shadow its own strength and size. Off follows Frame shadows on Global settings > Textures."] },
	{ type = "range", percent = true, key = I("shadowAlpha"), label = L["Shadow strength"], min = E.tokens.shadow.minAlpha, max = 1, step = 0.05,
		hidden = function() return NoIcon() or not (EditLook().shadow and EditLook().ownShadow) end,
		desc = L["How dark this icon's shadow is."] },
	{ type = "range", key = I("shadowSize"), label = L["Shadow size"], unit = "px", min = E.tokens.shadow.minSize, max = E.tokens.shadow.maxSize, step = 1,
		hidden = function() return NoIcon() or not (EditLook().shadow and EditLook().ownShadow) end,
		desc = L["How far this icon's shadow reaches beyond its edge."] },
	{ type = "toggle", key = I("clickThrough"), label = L["Click-through"], hidden = NoIcon,
		desc = L["Mouse clicks go through the icon to the world (no tooltip either)."] },
	{ type = "toggle", key = I("tooltip"), label = L["Show tooltip"], hidden = NoIcon,
		desc = L["The spell or item tooltip when the mouse is over the icon."] },
	{ type = "input", key = I("art"), label = L["Icon art"], hidden = NoIcon,
		desc = L["Another picture for the icon: a texture file ID or path. Empty uses the spell's or item's own icon."] },
}
-- Three labels, each a tag string and a place.
local LABEL_PLACES = { TOP = L["Above"], BOTTOM = L["Below"], LEFT = L["Left of it"], RIGHT = L["Right of it"], CENTER = L["Center"],
	INSIDE_TOP = L["Inside, top"], INSIDE_BOTTOM = L["Inside, bottom"] }
for index = 1, MAX_LABELS do
	local function NoText()
		if NoIcon() then return true end
		local label = EditLook().labels and EditLook().labels[index]
		return not label or strtrim(tostring(label.text or "")) == ""
	end
	table.insert(iconOptions, { type = "input", key = I(("labels.%d.text"):format(index)), label = "Label %d", labelFill = index, hidden = NoIcon,
		desc = index == 1
			and E.Key("A short text on or next to the icon: plain words or text tags, such as [cd:name], [cd:key] or [power:percent]. Empty shows nothing.")
			or E.Key("Another text on or next to the icon, written like Label 1. Empty shows nothing.") })
	table.insert(iconOptions, { type = "select", key = I(("labels.%d.point"):format(index)), label = "Label %d position", labelFill = index,
		hidden = NoText, values = LABEL_PLACES, desc = L["Where this label sits on or around the icon."] })
end
local iconTail = {
	{ type = "execute", label = L["Reset this icon"], hidden = NoIcon,
		func = function()
			local token = EditToken()
			if token and type(DB().icons) == "table" then DB().icons[token] = nil end
			Rebuild()
			if E.RefreshConfig then E:RefreshConfig() end
		end,
		desc = L["Back to the group's look for this icon."] },
}

-- The chosen group's visibility: its own block, or the row's.
local function NoOwnVisibility()
	if Off() then return true end
	local group = Editing()
	return not (group and group.ownVisibility)
end
table.insert(groupOptions, { type = "header", label = L["Visibility"], hidden = Off })
table.insert(groupOptions, { type = "toggle", key = G("ownVisibility"), label = L["Own visibility"], hidden = Off,
	desc = L["Give this group its own visibility rule. Off: a group made from a fixed row follows that row, any other group follows the main row."] })
for _, row in ipairs(E:VisibilityOptions("visibility", { label = false, db = function() return (Editing()) end, hidden = NoOwnVisibility })) do
	local key = row.key
	if type(key) == "string" then row.key = G(key) end
	table.insert(groupOptions, row)
end

for _, list in ipairs({ groupOptions, iconOptions, iconTail }) do
	for _, option in ipairs(list) do table.insert(M.options, option) end
end

-- Read-only views of the groups and their icons.
M.GroupToken, M.GroupParse = Token, Parse
