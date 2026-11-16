-- Move-mode stand-ins: while "Show test frames" is on, every frame that
-- shows nothing at that moment (a cast bar with no cast, an empty toast
-- lane, a cooldown row out of combat, a pet bar without a pet) gets a sample
-- drawn on its spot, in the current look, so the whole layout can be judged
-- with the boxes hidden. A module's own test (unit frames, party and raid,
-- timer bars...) comes first: the stand-in only fills a frame that is
-- still empty and steps aside as soon as the frame shows something.
--
-- A stand-in is decoration only: plain frames on UIParent that never take
-- the mouse, never touch the frame itself and go away when the test frames
-- are turned off, move mode ends or combat starts.
--
-- The look comes from the mover's `sample` (E:CreateMover opts):
--   sample = { kind = "bar" | "bars" | "icons" | "text" | "toast" | "unit" | "panel",
--              text = L["..."], -- shown instead of the frame's name
--              count = 5,       -- icons: how many (else as many as fit)
--              shows = function() return true end, -- the frame shows
--                               -- something the frame tree can't tell
--                               -- (auras the client draws, for example)
--              config = function(mover) return kind, spec end }
--                               -- the module draws its stand-in from its
--                               -- own settings, like its options preview
--                               -- (E:ConfigSample below), so the sample has
--                               -- the frame's size, spacing and growth
--   sample = false -- a window opened on demand: no stand-in, its box shows
--                  -- where it opens
-- Without one, the shape decides: a thin wide frame is a bar, a row of
-- squares is icons, anything else a panel.
--
-- What a frame shows is read from it and its children. A module that draws
-- on a mover with frames of another parent (rows on UIParent hung on the
-- holder, a Blizzard frame placed on it) names them once:
--   E:AddMoverContent("EldoUI_LootToasts", row)
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local samples = {} -- mover name -> stand-in frame
local ticker
local on = false

-- Real game icons for the stand-ins, so a test frame reads like the
-- frame in a fight (never a question mark). The pool follows the frame:
-- auras, items or abilities.
local function Icons(list)
	local out = {}
	for index, name in ipairs(list) do out[index] = "Interface\\Icons\\" .. name end
	return out
end
local ICON_POOLS = {
	spells = Icons({ "Ability_Warrior_Cleave", "Spell_Nature_Lightning", "Spell_Frost_FrostBolt02",
		"Spell_Shadow_ShadowBolt", "Spell_Holy_FlashHeal", "Ability_DualWield", "Spell_Fire_SealOfFire",
		"Spell_Frost_FrostNova", "Ability_Hunter_SniperShot", "Spell_Nature_Rejuvenation",
		"Spell_Holy_PowerWordShield", "Ability_Warrior_Challange" }),
	buffs = Icons({ "Spell_Holy_PowerWordShield", "Spell_Nature_Rejuvenation", "Spell_Holy_Renew",
		"Spell_Holy_SealOfSacrifice", "Spell_Nature_ResistNature", "Spell_Holy_PrayerOfHealing" }),
	debuffs = Icons({ "Spell_Shadow_ShadowWordPain", "Spell_Nature_Sleep", "Spell_Shadow_Twilight",
		"Spell_Frost_FrostNova", "Spell_Shadow_RaiseDead", "Spell_Nature_Poisoncleansingtotem" }),
	items = Icons({ "INV_Misc_Food_15", "INV_Misc_Rune_01", "INV_Scroll_03", "INV_Misc_PocketWatch_01",
		"INV_Misc_Bag_10", "INV_Misc_Coin_01" }),
}
local ITEM_WORDS = { "Consumable", "Items", "Trinkets", "Bag", "Quest", "Farm", "Fishing", "Loot" }

local function IconPool(mover)
	local name = mover and mover.name or ""
	if name:find("Debuff", 1, true) or name:find("LossOfControl", 1, true) then return ICON_POOLS.debuffs end
	if name:find("Buff", 1, true) or name:find("AuraGroup", 1, true) or name:find("TempEnchants", 1, true) then
		return ICON_POOLS.buffs
	end
	for _, word in ipairs(ITEM_WORDS) do
		if name:find(word, 1, true) then return ICON_POOLS.items end
	end
	return ICON_POOLS.spells
end
local ICON_COORDS = { 0.08, 0.92, 0.08, 0.92 }

---------------------------------------------------------------------------
-- Does a frame show anything right now? A shown texture, text or bar in it
-- or a few levels of its children. Secret values count as shown.
---------------------------------------------------------------------------
local function Faded(object)
	local alpha = object:GetAlpha()
	if E:IsSecret(alpha) then return false end
	return type(alpha) == "number" and alpha <= 0.01
end

local function RegionShows(region)
	if not region:IsShown() or Faded(region) then return false end
	local kind = region:GetObjectType()
	if kind == "FontString" then
		local text = region:GetText()
		if E:IsSecret(text) then return true end
		return text ~= nil and text ~= ""
	elseif kind == "Texture" then
		local atlas, readable = E.FrameAtlas(region)
		if not readable or (atlas ~= nil and atlas ~= "") then return true end
		if region:GetTexture() ~= nil then return true end
		return false
	end
	return false
end

local function Shows(frame, depth)
	if E.FrameCheck(frame, "IsForbidden") then return true end
	if not frame:IsShown() or Faded(frame) then return false end
	if frame:GetObjectType() == "StatusBar" then return true end
	for _, region in ipairs({ frame:GetRegions() }) do
		if RegionShows(region) then return true end
	end
	if depth >= 5 then return false end
	for _, child in ipairs({ frame:GetChildren() }) do
		if Shows(child, depth + 1) then return true end
	end
	return false
end

local content = setmetatable({}, { __mode = "k" }) -- frame -> mover name

function E:AddMoverContent(name, frame)
	if type(name) == "string" and type(frame) == "table" then content[frame] = name end
end

local function Readable(frame)
	local ok, shows = pcall(function() return frame:IsVisible() and Shows(frame, 0) end)
	return not ok or shows and true or false
end

-- Blizzard frames EldoUI pins onto a holder count for that holder.
local pinnedOn = {} -- holder -> list of Blizzard frames
local function CollectPins()
	wipe(pinnedOn)
	if not E.EachBlizzardPin then return end
	for frame, spec in E:EachBlizzardPin() do
		local ok, holder = pcall(function()
			if spec.holder then return spec.holder end
			local _, relativeTo = frame:GetPoint(1)
			return relativeTo
		end)
		if ok and type(holder) == "table" then
			pinnedOn[holder] = pinnedOn[holder] or {}
			table.insert(pinnedOn[holder], frame)
		end
	end
end

-- Does the mover's frame (or a frame named for it, or a Blizzard frame
-- pinned on it) show anything? A frame we can't read counts as shown: no
-- stand-in over it.
function E:MoverFrameShows(mover)
	local frame = mover and mover.frame
	if not frame then return true end
	local spec = mover.sample
	if type(spec) == "table" and spec.shows then
		local ok, shows = pcall(spec.shows)
		if not ok or shows then return true end
	end
	if Readable(frame) then return true end
	for other, name in pairs(content) do
		if name == mover.name and Readable(other) then return true end
	end
	for _, other in ipairs(pinnedOn[frame] or {}) do
		if Readable(other) then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- The stand-ins
---------------------------------------------------------------------------
local function Kind(mover)
	local spec = mover.sample
	if type(spec) == "table" and type(spec.config) == "function" then return "config" end
	if type(spec) == "table" and spec.kind then return spec.kind end
	local w, h = mover:GetSize()
	if h <= 24 and w >= h * 3 then return "bar" end
	local long, short = math.max(w, h), math.min(w, h)
	if short <= 64 and long >= short * 2 then return "icons" end
	if long <= 64 then return "icons" end
	return "panel"
end

local function Label(mover)
	local spec = mover.sample
	if type(spec) == "table" and spec.text then return spec.text end
	return L[mover.title]
end

local function Text(parent, size, color)
	local text = E:CreateText(parent, size, "LEFT")
	text:SetTextColor(unpack(color or E.tokens.text.body))
	return text
end

local function TextSize(height, low, high)
	return math.max(low, math.min(high, math.floor(height * 0.5)))
end

-- An icon square in the HUD's look: the slot background, the icon inside.
local function Icon(parent, size, texture)
	local slot = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	slot:SetSize(size, size)
	E:SetTemplate(slot)
	slot.icon = slot:CreateTexture(nil, "ARTWORK")
	slot.icon:SetPoint("TOPLEFT", E.pixel or 1, -(E.pixel or 1))
	slot.icon:SetPoint("BOTTOMRIGHT", -(E.pixel or 1), E.pixel or 1)
	slot.icon:SetTexture(texture or ICON_POOLS.spells[1])
	slot.icon:SetTexCoord(unpack(ICON_COORDS))
	return slot
end

local function ClearParts(sample)
	for _, part in ipairs(sample.parts) do part:Hide() end
	wipe(sample.parts)
end

local function Keep(sample, part)
	sample.parts[#sample.parts + 1] = part
	return part
end

local Draw = {}

function Draw.bar(sample, mover, w, h)
	local bar = Keep(sample, E:CreateStatusBar(sample))
	bar:SetAllPoints()
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0.65)
	bar:SetStatusBarColor(unpack(E.media.accentColor))
	if h >= 10 then
		local size = TextSize(h, 9, E.tokens.size.body)
		local name = Text(bar, size)
		name:SetPoint("LEFT", 4, 0)
		name:SetPoint("RIGHT", -36, 0)
		name:SetText(Label(mover))
		sample.named = true
		local value = Text(bar, size)
		value:SetPoint("RIGHT", -4, 0)
		value:SetText("3.2")
	end
end

-- A stack of timer bars, as many as fit (at most five).
function Draw.bars(sample, mover, w, h)
	local height = math.max(8, math.min(20, h))
	local gap = 3
	local count = math.max(1, math.min(5, math.floor((h + gap) / (height + gap))))
	for index = 1, count do
		local bar = Keep(sample, E:CreateStatusBar(sample))
		bar:SetPoint("TOPLEFT", 0, -(index - 1) * (height + gap))
		bar:SetPoint("TOPRIGHT", 0, -(index - 1) * (height + gap))
		bar:SetHeight(height)
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1 - index * 0.15)
		bar:SetStatusBarColor(unpack(E.media.accentColor))
		if index == 1 and height >= 10 then
			local name = Text(bar, TextSize(height, 9, E.tokens.size.body))
			name:SetPoint("LEFT", 4, 0)
			name:SetPoint("RIGHT", -4, 0)
			name:SetText(Label(mover))
			sample.named = true
		end
	end
end

function Draw.icons(sample, mover, w, h)
	local spec = type(mover.sample) == "table" and mover.sample or {}
	local vertical = h > w
	local long, short = vertical and h or w, vertical and w or h
	local gap = math.max(2, math.floor(short / 12))
	local count = spec.count or math.floor((long + gap) / (short + gap))
	count = math.max(1, math.min(12, count))
	local size = math.min(short, math.floor((long - gap * (count - 1)) / count))
	-- The row sits in the middle of the frame.
	local start = (long - (count * size + (count - 1) * gap)) / 2
	local pool = IconPool(mover)
	for index = 1, count do
		local slot = Keep(sample, Icon(sample, size, pool[(index - 1) % #pool + 1]))
		local offset = start + (index - 1) * (size + gap)
		if vertical then
			slot:SetPoint("TOP", sample, "TOP", 0, -offset)
		else
			slot:SetPoint("LEFT", sample, "LEFT", offset, 0)
		end
	end
end

function Draw.text(sample, mover, w, h)
	local text = Keep(sample, CreateFrame("Frame", nil, sample))
	text:SetAllPoints()
	local line = Text(text, TextSize(h, 12, 24), E.tokens.text.gold)
	line:SetPoint("CENTER")
	line:SetJustifyH("CENTER")
	line:SetText(Label(mover))
	sample.named = true
end

function Draw.toast(sample, mover, w, h)
	local card = Keep(sample, CreateFrame("Frame", nil, sample, "BackdropTemplate"))
	card:SetAllPoints()
	E:SetTemplate(card, true)
	local iconSize = math.max(12, math.min(h - 8, 40))
	local slot = Icon(card, iconSize, IconPool(mover)[1])
	slot:SetPoint("LEFT", 4, 0)
	local title = Text(card, E.tokens.size.body)
	title:SetPoint("BOTTOMLEFT", slot, "RIGHT", 6, 1)
	title:SetPoint("BOTTOMRIGHT", card, "RIGHT", -6, 1)
	title:SetText(Label(mover))
	sample.named = true
	local note = Text(card, E.tokens.size.small, E.tokens.text.secondary)
	note:SetPoint("TOPLEFT", slot, "RIGHT", 6, -1)
	note:SetPoint("TOPRIGHT", card, "RIGHT", -6, -1)
	note:SetText(L["Test frame"])
end

function Draw.unit(sample, mover, w, h)
	local card = Keep(sample, CreateFrame("Frame", nil, sample, "BackdropTemplate"))
	card:SetAllPoints()
	E:SetTemplate(card)
	local pixel = E.pixel or 1
	local health = E:CreateStatusBar(card)
	health:SetPoint("TOPLEFT", pixel, -pixel)
	health:SetPoint("BOTTOMRIGHT", -pixel, pixel)
	health:SetMinMaxValues(0, 1)
	health:SetValue(0.8)
	local r, g, b = E:GetClassColor(select(2, UnitClass("player")))
	health:SetStatusBarColor(r or 0.5, g or 0.5, b or 0.5)
	local name = Text(health, TextSize(h, 9, E.tokens.size.body))
	name:SetPoint("LEFT", 4, 0)
	name:SetPoint("RIGHT", -4, 0)
	name:SetText(Label(mover))
	sample.named = true
end

-- Drawn by the module from its settings (sample.config), the way its
-- options preview is; nothing when it returns no kind.
function Draw.config(sample, mover)
	local kind, spec = mover.sample.config(mover)
	if kind then E:ConfigSample(sample, kind, spec) end
	if sample.configSample then sample.configSample:SetShown(kind ~= nil) end
	sample.named = false
end

function Draw.panel(sample, mover, w, h)
	local card = Keep(sample, CreateFrame("Frame", nil, sample, "BackdropTemplate"))
	card:SetAllPoints()
	E:SetTemplate(card, true)
	local title = Text(card, E.tokens.size.label, E.tokens.text.secondary)
	title:SetPoint("TOPLEFT", 6, -5)
	title:SetPoint("TOPRIGHT", -6, -5)
	title:SetText(Label(mover))
	sample.named = true
end

local function Strata(mover)
	local strata = mover.frame and mover.frame:GetFrameStrata()
	-- Never over the move panel and the boxes (DIALOG).
	if strata == "DIALOG" or strata == "FULLSCREEN" or strata == "FULLSCREEN_DIALOG" or strata == "TOOLTIP" then
		return "HIGH"
	end
	return strata or "MEDIUM"
end

local function ShowSample(mover)
	local sample = samples[mover.name]
	if not sample then
		sample = CreateFrame("Frame", nil, UIParent)
		sample:EnableMouse(false)
		sample.parts = {}
		samples[mover.name] = sample
	end
	local w, h = mover:GetSize()
	if E:IsSecret(w) or E:IsSecret(h) then return end
	-- Drawn once per size: shown again as it is. One the module draws from
	-- its settings is drawn again each time, so a new setting shows at once.
	if sample.drawn and sample.w == w and sample.h == h and sample.kind ~= "config" then
		sample:Show()
		return
	end
	sample:ClearAllPoints()
	sample:SetAllPoints(mover)
	sample:SetFrameStrata(Strata(mover))
	ClearParts(sample)
	sample.w, sample.h, sample.drawn = w, h, true
	sample.kind = Kind(mover)
	sample.named = false
	if w > 1 and h > 1 then Draw[sample.kind](sample, mover, w, h) end
	sample:Show()
end

local function HideSample(name)
	local sample = samples[name]
	if sample then sample:Hide() end
end

-- A frame takes part while its mover is shown, its module is on and the
-- move-mode filter (a module's own move mode) and the view (combat mode
-- or all frames) accept it. A box hidden for the session or a group picked
-- in the panel keeps its stand-in: those only tidy the boxes.
local function TakesPart(mover)
	if mover.sample == false or not mover:IsShown() or not E:MoveModeAccepts(mover) then return false end
	if E.MoverInMoveView and not E:MoverInMoveView(mover) then return false end
	local module = mover.module and E.modules[mover.module]
	return not module or module.active and true or false
end

-- Show a stand-in on every frame that takes part and shows nothing. The
-- box learns whether its frame shows something and whether that names the
-- frame (Core/Movers.lua moves the box name out of the way).
local function Refresh()
	if not on then return end
	CollectPins()
	for name, mover in pairs(E.movers) do
		local part = TakesPart(mover)
		local shows = part and E:MoverFrameShows(mover)
		if part and not shows then
			ShowSample(mover)
		else
			HideSample(name)
		end
		local sample = samples[name]
		local standIn = sample and sample:IsShown() and sample.drawn
		if E.SetMoverContent then
			E:SetMoverContent(mover, shows or standIn, shows or (standIn and sample.named))
		end
	end
end

-- state true: stand-ins on (move mode with test frames); false: all gone.
function E:ShowMoverSamples(state)
	on = state and true or false
	if ticker then ticker:Cancel() ticker = nil end
	if not on then
		for name in pairs(samples) do HideSample(name) end
		if E.SetMoverContent then
			for _, mover in pairs(E.movers) do E:SetMoverContent(mover, false, false) end
		end
		return
	end
	Refresh()
	-- A module's sample that ends (a toast fading) gives its spot back to
	-- the stand-in, a real one arriving takes it.
	if C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(0.5, Refresh) end
end

-- The stand-in of one mover while it is shown, for plugins.
function E:GetMoverSample(name)
	local sample = samples[name]
	return sample and sample:IsShown() and sample or nil
end

-- A new look (accent, bar texture, font) while they show draws them again.
E:OnThemeChanged("moverSamples", function()
	for _, sample in pairs(samples) do sample.drawn = nil end
	Refresh()
end)

---------------------------------------------------------------------------
-- Options previews (DESIGN.md 5): the same sample parts, drawn into a
-- module page's preview strip from the page's own settings, so a change
-- shows at once. Sample data only: fixed names, numbers and game icons,
-- never a live unit, and nothing here is secure or takes the mouse.
--   E:ConfigSample(canvas, kind, spec) -> stage
-- Call it from a preview row's update (every redraw reuses the parts of
-- the last one). The sample is drawn at its real size and scaled down
-- only when it would not fit the strip; spec.align (an anchor point such
-- as "LEFT" or "TOPRIGHT") puts it at that edge or corner instead of the
-- middle, and spec.fade (0-1) draws it see-through.
--   unit     { width, height, powerHeight, name, health (0-1), healthText,
--              nameJustify ("LEFT" | "CENTER" | "RIGHT" | false), color,
--              powerColor, fontSize, reverse }
--   party    the unit fields, plus count, spacing, vertical; names and
--              class colors come from a fixed sample group
--   plate    { width, height, name, health, color, fontSize, castHeight, castColor,
--              castText, level }
--   pips     { count, filled, width, height, spacing, color, barHeight,
--              barColor }
--   icons    { count, size, spacing, columns, pool ("spells" | "buffs" |
--              "debuffs" | "items"), timers, counts, keys, fontSize,
--              edges (list of { r, g, b }), cooldown (0-1 on the first),
--              zoom (percent of the icon edge cut away), borders (false: none) }
--   grid     { columns, rows, size, spacing, qualities, counts }
--   minimap  { size, round, zone (text, or false), clock, fontSize }
--   tooltip  { width, lines = { { text, color }, ... }, fontSize, headerSize, alpha,
--              barHeight (a health bar under it), barColor }
--   toast    { width, height, title, text, icon, quality, fontSize }
--   feed     { width, rowHeight, items = { { icon, text, quality } }, fontSize }
--   bar      { width, height, value (0-1), color, left, right, fontSize }
---------------------------------------------------------------------------
local Sample = {}

-- Parts are kept per stage and kind and shown again on the next draw.
local function Part(stage, kind, make)
	local list = stage.pool[kind]
	if not list then
		list = {}
		stage.pool[kind] = list
	end
	local index = (stage.used[kind] or 0) + 1
	stage.used[kind] = index
	local part = list[index]
	if not part then
		part = make(stage)
		list[index] = part
	end
	part:ClearAllPoints()
	part:Show()
	return part
end

local function SampleText(owner, size, color)
	local text = E:CreateText(owner, size, "LEFT")
	text:SetWordWrap(false)
	text:SetTextColor(unpack(color or E.tokens.text.body))
	return text
end

local function MakeBar(stage)
	local bar = E:CreateStatusBar(stage)
	bar:SetMinMaxValues(0, 1)
	bar.left = SampleText(bar, E.tokens.size.body)
	bar.right = SampleText(bar, E.tokens.size.body)
	bar.center = SampleText(bar, E.tokens.size.body)
	bar.center:SetJustifyH("CENTER")
	return bar
end

local function MakeSlot(stage)
	local slot = Icon(stage, 32)
	slot.count = SampleText(slot, E.tokens.size.small)
	slot.count:SetPoint("BOTTOMRIGHT", -2, 2)
	slot.key = SampleText(slot, E.tokens.size.small, E.tokens.text.secondary)
	slot.key:SetPoint("TOPRIGHT", -2, -2)
	slot.timer = SampleText(slot, E.tokens.size.small)
	slot.timer:SetPoint("TOP", slot, "BOTTOM", 0, -2)
	slot.shade = slot:CreateTexture(nil, "OVERLAY")
	slot.shade:SetPoint("BOTTOMLEFT", slot.icon)
	slot.shade:SetPoint("BOTTOMRIGHT", slot.icon)
	slot.shade:SetColorTexture(0, 0, 0, 0.6)
	return slot
end

-- A slot showing only its icon (no count, key, timer or cooldown shade).
local function PlainSlot(slot, texture, quality)
	slot.icon:SetTexture(E:ClientIcon(texture))
	slot.icon:SetTexCoord(unpack(E.tokens.iconCoords))
	slot.count:SetText("")
	slot.key:SetText("")
	slot.timer:SetText("")
	slot.shade:Hide()
	local r, g, b = E.UIKit.QualityColor(quality)
	if r then slot:SetBackdropBorderColor(r, g, b, 1) else slot:SetBackdropBorderColor(unpack(E.media.borderColor)) end
	return r, g, b
end

local function MakeBox(stage)
	local box = CreateFrame("Frame", nil, stage, "BackdropTemplate")
	E:SetTemplate(box, true)
	return box
end

-- A plain box: a box reused from the minimap sample keeps its map picture
-- otherwise, stretched over a tooltip or a toast.
local function PlainBox(box)
	if box.map then box.map:Hide() end
	return box
end

local function MakeText(stage)
	return SampleText(stage, E.tokens.size.body)
end

-- Text inside a box (a tooltip line, a toast title) lives on the box, so it
-- draws over the box's background. Each stage has one box of each draw.
local function BoxText(stage, box)
	return Part(stage, "boxText", function() return SampleText(box, E.tokens.size.body) end)
end

local function SetFontSize(text, size)
	E:SetFont(text, size or E.tokens.size.body)
end

local function Bar(stage, spec, width, height, value, color)
	local bar = Part(stage, "bar", MakeBar)
	bar:SetSize(width, height)
	bar:SetStatusBarTexture(E.media.statusbar)
	bar:SetReverseFill(spec and spec.reverse and true or false)
	bar:SetValue(value or 1)
	local r, g, b = unpack(E.tokens.text.secondary)
	if type(color) == "table" then r, g, b = color[1], color[2], color[3] end
	bar:SetStatusBarColor(r, g, b)
	for _, text in ipairs({ bar.left, bar.right, bar.center }) do
		text:SetText("")
		text:ClearAllPoints()
	end
	return bar
end

local function ClassColor(class)
	local r, g, b = E:GetClassColor(class)
	if not r then r, g, b = unpack(E.tokens.text.secondary) end
	return { r, g, b }
end

local function PowerColor(token)
	local r, g, b = E:GetPowerColor(token or "MANA")
	if not r then r, g, b = unpack(E.media.accentColor) end
	return { r, g, b }
end

-- One unit frame at x, y of the stage: health with its texts, the power
-- bar under it. Returns its height.
local function UnitAt(stage, spec, x, y, name, value, color)
	local width, height = spec.width or 200, spec.height or 36
	local power = math.max(0, spec.powerHeight or 0)
	local size = spec.fontSize or E.tokens.size.body
	local health = Bar(stage, spec, width, height, value, color)
	health:SetPoint("TOPLEFT", stage, "TOPLEFT", x, -y)
	local justify = spec.nameJustify
	if justify == nil then justify = "LEFT" end
	if justify then
		local text = health.left
		if justify == "CENTER" then text = health.center elseif justify == "RIGHT" then text = health.right end
		SetFontSize(text, size)
		text:SetPoint(justify, justify == "RIGHT" and -4 or (justify == "LEFT" and 4 or 0), 0)
		text:SetText(name or "")
	end
	if spec.healthText and justify ~= "RIGHT" then
		SetFontSize(health.right, size)
		health.right:SetPoint("RIGHT", -4, 0)
		health.right:SetText(spec.healthText)
	end
	if power > 0 then
		local bar = Bar(stage, nil, width, power, 0.7, spec.powerColor or PowerColor("MANA"))
		bar:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -2)
		return height + power + 2
	end
	return height
end

function Sample.unit(stage, spec)
	local h = UnitAt(stage, spec, 0, 0, spec.name or UnitName("player") or "", spec.health or 0.8,
		spec.color or ClassColor(select(2, UnitClass("player"))))
	return spec.width or 200, h
end

-- A sample group: the same five every time, so a change is easy to see.
local GROUP = {
	{ "Thrall", "SHAMAN", 0.95 }, { "Jaina", "MAGE", 0.6 }, { "Anduin", "PRIEST", 1 },
	{ "Valeera", "ROGUE", 0.35 }, { "Varian", "WARRIOR", 0.8 },
}

function Sample.party(stage, spec)
	local count = math.max(1, math.min(spec.count or 5, 10))
	local gap = spec.spacing or 4
	local width = spec.width or 80
	local w, h, x, y = 0, 0, 0, 0
	for index = 1, count do
		local member = GROUP[(index - 1) % #GROUP + 1]
		local cell = UnitAt(stage, spec, x, y, member[1], member[3], spec.color or ClassColor(member[2]))
		w, h = math.max(w, x + width), math.max(h, y + cell)
		if spec.vertical then y = y + cell + gap else x = x + width + gap end
	end
	return w, h
end

function Sample.plate(stage, spec)
	local width, height = spec.width or 120, spec.height or 10
	local size = spec.fontSize or E.tokens.size.label
	local name = Part(stage, "text", MakeText)
	SetFontSize(name, size)
	name:SetText(spec.name or "")
	name:SetTextColor(unpack(E.tokens.text.body))
	name:SetPoint("TOPLEFT", stage, "TOPLEFT", 0, 0)
	local top = size + 4
	local health = Bar(stage, nil, width, height, spec.health or 0.65, spec.color or { E:GetReactionColor(2) })
	health:SetPoint("TOPLEFT", stage, "TOPLEFT", 0, -top)
	if spec.level then
		local level = Part(stage, "text", MakeText)
		SetFontSize(level, size)
		level:SetText(spec.level)
		level:SetTextColor(unpack(E.tokens.text.body))
		level:SetPoint("TOPRIGHT", stage, "TOPLEFT", width, 0)
	end
	local total = top + height
	if (spec.castHeight or 0) > 0 then
		local cast = Bar(stage, nil, width, spec.castHeight, 0.45, spec.castColor or E.media.accentColor)
		cast:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -4)
		if spec.castHeight >= 8 then
			SetFontSize(cast.left, math.max(8, math.min(size, spec.castHeight)))
			cast.left:SetPoint("LEFT", 2, 0)
			cast.left:SetText(spec.castText or "")
		end
		total = total + 4 + spec.castHeight
	end
	return width, total
end

function Sample.pips(stage, spec)
	local count = math.max(1, math.min(spec.count or 5, 10))
	local filled = math.min(count, spec.filled or 3)
	local width, height, gap = spec.width or 200, spec.height or 10, spec.spacing or 3
	local each = math.max(4, (width - gap * (count - 1)) / count)
	local color = spec.color or PowerColor("COMBO_POINTS")
	for index = 1, count do
		local pip = Bar(stage, nil, each, height, index <= filled and 1 or 0, color)
		pip:SetPoint("TOPLEFT", stage, "TOPLEFT", (index - 1) * (each + gap), 0)
	end
	local total = height
	if (spec.barHeight or 0) > 0 then
		local bar = Bar(stage, nil, width, spec.barHeight, 0.7, spec.barColor or PowerColor("ENERGY"))
		bar:SetPoint("TOPLEFT", stage, "TOPLEFT", 0, -(height + gap + 2))
		total = total + gap + 2 + spec.barHeight
	end
	return width, total
end

local TIMERS = { "12s", "4m", "38s", "1h", "6s", "2m", "45s", "9s", "20m", "3s", "1m", "15s" }

-- spec.height: a button lower than it is wide (flat shapes); flipX and
-- flipY: the row grows to the left or upward; columnsFirst fills each
-- column before the next, as an action bar does.
function Sample.icons(stage, spec)
	local count = math.max(1, math.min(spec.count or 6, 24))
	local size, gap = spec.size or 32, spec.spacing or 4
	local height = spec.height or size
	local perRow = math.max(1, math.min(spec.columns or count, count))
	local pool = ICON_POOLS[spec.pool or "spells"] or ICON_POOLS.spells
	local font = spec.fontSize or E.tokens.size.small
	-- Time text below or above the icon, and a time bar under it, take
	-- room between the rows; text on the icon takes none.
	local timerPoint = spec.timerPoint or "BELOW"
	local outside = timerPoint == "BELOW" or timerPoint == "ABOVE"
	local bar = (spec.timeBar or 0) > 0 and spec.timeBar or 0
	local below = (spec.timers and outside and (font + 4) or 0) + (bar > 0 and (bar + 2) or 0)
	local rows = math.ceil(count / perRow)
	local columns = spec.columnsFirst and math.ceil(count / rows) or perRow
	for index = 1, count do
		local slot = Part(stage, "slot", MakeSlot)
		slot:SetSize(size, height)
		local column, row
		if spec.columnsFirst then
			column, row = math.floor((index - 1) / rows), (index - 1) % rows
		else
			column, row = (index - 1) % perRow, math.floor((index - 1) / perRow)
		end
		if spec.flipX then column = columns - 1 - column end
		if spec.flipY then row = rows - 1 - row end
		slot:SetPoint("TOPLEFT", stage, "TOPLEFT", column * (size + gap), -row * (height + gap + below))
		PlainSlot(slot, pool[(index - 1) % #pool + 1])
		local edge = spec.edges and #spec.edges > 0 and spec.edges[(index - 1) % #spec.edges + 1]
		if edge then slot:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1) end
		if spec.borders == false then slot:SetBackdropBorderColor(0, 0, 0, 0) end
		if spec.zoom then
			local cut = math.max(0, math.min(0.3, spec.zoom / 100))
			slot.icon:SetTexCoord(E:IconCoords(cut, size, height))
		end
		SetFontSize(slot.count, spec.countSize or font)
		SetFontSize(slot.key, font)
		SetFontSize(slot.timer, font)
		local countPoint = spec.countPoint or "BOTTOMRIGHT"
		slot.count:ClearAllPoints()
		slot.count:SetPoint(countPoint, slot, countPoint, spec.countX or (spec.countPoint and 0 or -2), spec.countY or (spec.countPoint and 0 or 2))
		slot.timer:ClearAllPoints()
		if timerPoint == "BELOW" then
			slot.timer:SetPoint("TOP", slot, "BOTTOM", spec.timerX or 0, (spec.timerY or 0) - 2 - (bar > 0 and (bar + 1) or 0))
		elseif timerPoint == "ABOVE" then
			slot.timer:SetPoint("BOTTOM", slot, "TOP", spec.timerX or 0, (spec.timerY or 0) + 2)
		else
			slot.timer:SetPoint(timerPoint, slot, timerPoint, spec.timerX or 0, spec.timerY or 0)
		end
		if bar > 0 then
			slot.timeBar = slot.timeBar or slot:CreateTexture(nil, "OVERLAY")
			slot.timeBar:ClearAllPoints()
			slot.timeBar:SetPoint("TOPLEFT", slot, "BOTTOMLEFT", 0, -1)
			slot.timeBar:SetSize(size * (1 - ((index - 1) % 4) * 0.2), bar)
			slot.timeBar:SetColorTexture(E:TokenColor("accent"))
			slot.timeBar:Show()
		elseif slot.timeBar then
			slot.timeBar:Hide()
		end
		-- "Gray out others'": every other sample stands for someone else's.
		slot.icon:SetDesaturated(spec.grayOthers and index % 2 == 0 or false)
		slot.count:SetText(spec.counts and index % 3 == 1 and tostring(index + 1) or "")
		slot.key:SetText(spec.keys and tostring(index % 10) or "")
		slot.timer:SetText(spec.timers and TIMERS[(index - 1) % #TIMERS + 1] or "")
		local shade = index == 1 and spec.cooldown or 0
		slot.shade:SetHeight(math.max(0.01, (height - 2) * shade))
		slot.shade:SetShown(shade > 0)
	end
	return columns * size + (columns - 1) * gap, rows * (height + below) + (rows - 1) * gap
end

function Sample.grid(stage, spec)
	local columns, rows = math.max(1, spec.columns or 6), math.max(1, spec.rows or 2)
	local size, gap = spec.size or 32, spec.spacing or 4
	local pool = ICON_POOLS.items
	for index = 1, columns * rows do
		local slot = Part(stage, "slot", MakeSlot)
		slot:SetSize(size, size)
		local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
		slot:SetPoint("TOPLEFT", stage, "TOPLEFT", column * (size + gap), -row * (size + gap))
		local empty = index % 5 == 0
		PlainSlot(slot, pool[(index - 1) % #pool + 1], spec.qualities and not empty and (index % 4 + 1) or nil)
		if empty then slot.icon:SetTexture(nil) end
		SetFontSize(slot.count, spec.fontSize or E.tokens.size.small)
		slot.count:SetText(spec.counts ~= false and not empty and index % 3 == 0 and tostring(index * 2) or "")
	end
	return columns * size + (columns - 1) * gap, rows * size + (rows - 1) * gap
end

function Sample.minimap(stage, spec)
	local size = spec.size or 80
	local font = spec.fontSize or E.tokens.size.label
	local top = 0
	if spec.zone ~= false then
		local zone = Part(stage, "text", MakeText)
		SetFontSize(zone, font)
		zone:SetText(spec.zone or "")
		zone:SetTextColor(unpack(E.tokens.text.body))
		zone:SetPoint("TOP", stage, "TOPLEFT", size / 2, 0)
		top = font + 4
	end
	local box = Part(stage, "box", MakeBox)
	box:SetSize(size, size)
	box:SetPoint("TOPLEFT", stage, "TOPLEFT", 0, -top)
	if not box.map then
		box.map = box:CreateTexture(nil, "ARTWORK")
		box.map:SetPoint("TOPLEFT", 2, -2)
		box.map:SetPoint("BOTTOMRIGHT", -2, 2)
		box.mask = box:CreateMaskTexture()
		box.mask:SetAllPoints(box.map)
		box.mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	end
	box.map:SetTexture(E:ClientIcon("Interface\\Icons\\INV_Misc_Map_01"))
	box.map:Show()
	box.map:SetTexCoord(unpack(E.tokens.iconCoords))
	if spec.round and not box.masked then
		box.map:AddMaskTexture(box.mask)
		box.masked = true
	elseif not spec.round and box.masked then
		box.map:RemoveMaskTexture(box.mask)
		box.masked = false
	end
	local bottom = 0
	if spec.clock then
		local clock = Part(stage, "text", MakeText)
		SetFontSize(clock, font)
		clock:SetText(spec.clock)
		clock:SetTextColor(unpack(E.tokens.text.body))
		clock:SetPoint("TOP", box, "BOTTOM", 0, -3)
		bottom = font + 4
	end
	return size, top + size + bottom
end

function Sample.tooltip(stage, spec)
	local width = spec.width or 220
	local font = spec.fontSize or E.tokens.size.body
	local box = PlainBox(Part(stage, "box", MakeBox))
	box:SetPoint("TOPLEFT", stage, "TOPLEFT")
	if spec.alpha then E:SetTemplateAlpha(box, spec.alpha) end
	local y = 8
	for index, line in ipairs(spec.lines or {}) do
		local text = BoxText(stage, box)
		local size = index == 1 and (spec.headerSize or font + 1) or font
		SetFontSize(text, size)
		text:SetText(line[1] or "")
		local c = line[2] or E.tokens.text.body
		text:SetTextColor(c[1], c[2], c[3])
		text:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -y)
		text:SetWidth(width - 16)
		y = y + size + 4
	end
	box:SetSize(width, y + 4)
	local height = y + 4
	if (spec.barHeight or 0) > 0 then
		local bar = Bar(stage, nil, width - 2, spec.barHeight, 0.8, spec.barColor or { E:GetReactionColor(5) })
		bar:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 1, -2)
		height = height + 2 + spec.barHeight
	end
	return width, height
end

function Sample.toast(stage, spec)
	local width, height = spec.width or 240, spec.height or 48
	local font = spec.fontSize or E.tokens.size.body
	local box = PlainBox(Part(stage, "box", MakeBox))
	box:SetSize(width, height)
	box:SetPoint("TOPLEFT", stage, "TOPLEFT")
	local slot = Part(stage, "slot", MakeSlot)
	local size = math.max(12, height - 12)
	slot:SetSize(size, size)
	slot:SetPoint("LEFT", box, "LEFT", 6, 0)
	slot:SetFrameLevel(box:GetFrameLevel() + 1)
	local r, g, b = PlainSlot(slot, spec.icon or ICON_POOLS.items[1], spec.quality)
	local title = BoxText(stage, box)
	SetFontSize(title, font)
	title:SetText(spec.title or "")
	if r then title:SetTextColor(r, g, b) else title:SetTextColor(unpack(E.tokens.text.body)) end
	title:SetPoint("BOTTOMLEFT", slot, "RIGHT", 8, 1)
	title:SetWidth(width - size - 24)
	local note = BoxText(stage, box)
	SetFontSize(note, math.max(8, font - 2))
	note:SetText(spec.text or "")
	note:SetTextColor(unpack(E.tokens.text.secondary))
	note:SetPoint("TOPLEFT", slot, "RIGHT", 8, -1)
	note:SetWidth(width - size - 24)
	return width, height
end

function Sample.feed(stage, spec)
	local width, rowHeight = spec.width or 220, spec.rowHeight or 20
	local font = spec.fontSize or E.tokens.size.label
	local y = 0
	for _, row in ipairs(spec.items or {}) do
		local slot = Part(stage, "slot", MakeSlot)
		slot:SetSize(rowHeight, rowHeight)
		slot:SetPoint("TOPLEFT", stage, "TOPLEFT", 0, -y)
		PlainSlot(slot, row[1] or ICON_POOLS.items[1])
		local text = Part(stage, "text", MakeText)
		SetFontSize(text, font)
		text:SetText(row[2] or "")
		local r, g, b = E.UIKit.QualityColor(row[3])
		if r then text:SetTextColor(r, g, b) else text:SetTextColor(unpack(E.tokens.text.body)) end
		text:SetPoint("LEFT", slot, "RIGHT", 6, 0)
		text:SetWidth(width - rowHeight - 6)
		y = y + rowHeight + 3
	end
	return width, math.max(1, y - 3)
end

function Sample.bar(stage, spec)
	local width, height = spec.width or 200, spec.height or 14
	local bar = Bar(stage, spec, width, height, spec.value or 0.6, spec.color)
	bar:SetPoint("TOPLEFT", stage, "TOPLEFT")
	for _, side in ipairs({ "left", "right" }) do
		local text = bar[side]
		if spec[side] then
			SetFontSize(text, spec.fontSize or E.tokens.size.small)
			text:SetPoint(side == "left" and "LEFT" or "RIGHT", bar, side == "left" and "LEFT" or "RIGHT", side == "left" and 4 or -4, 0)
			text:SetText(spec[side])
		end
	end
	return width, height
end

-- Never larger than the strip: scaled down evenly to fit both its width
-- and its height, never up, so a tall or wide sample keeps its shape.
-- The game sizes a strip that was just placed on its next layout pass, so
-- until then the sample fits the strip's last known size; with none yet it
-- waits unseen for one frame. Every new strip size (a new window size, a
-- page laid out again) fits it again.
local function FitSample(canvas, late)
	local stage = canvas.configSample
	if not (stage and stage.width and stage.spec) then return end
	local cw, ch = canvas:GetWidth() or 0, canvas:GetHeight() or 0
	if cw > 0 and ch > 0 then
		stage.fitWidth, stage.fitHeight = cw, ch
	else
		cw, ch = stage.fitWidth, stage.fitHeight
	end
	local fit = 1
	if cw and ch then fit = math.min(1, cw / stage.width, ch / stage.height) end
	stage:SetScale(math.max(0.01, fit))
	stage:ClearAllPoints()
	local point = stage.spec.align or "CENTER"
	stage:SetPoint(point, canvas, point)
	if cw or late or not (C_Timer and C_Timer.After) then
		stage:SetAlpha(stage.spec.fade or 1)
	else
		stage:SetAlpha(0)
		if not stage.fitPending then
			stage.fitPending = true
			C_Timer.After(0, function()
				stage.fitPending = nil
				FitSample(canvas, true)
			end)
		end
	end
end

E.ConfigSampleKinds = Sample -- exposed for inspection
E.ConfigSampleIcons = ICON_POOLS -- the stand-ins' icon lists, for previews

function E:ConfigSample(canvas, kind, spec)
	local draw = Sample[kind]
	if not (canvas and draw) then return end
	local stage = canvas.configSample
	if not stage then
		stage = CreateFrame("Frame", nil, canvas)
		stage:EnableMouse(false)
		stage.pool = {}
		canvas.configSample = stage
		canvas:HookScript("OnSizeChanged", function(strip) FitSample(strip) end)
	end
	stage.used = {}
	for _, list in pairs(stage.pool) do
		for _, part in ipairs(list) do part:Hide() end
	end
	spec = spec or {}
	stage:SetScale(1)
	local w, h = draw(stage, spec)
	w, h = math.max(1, w or 1), math.max(1, h or 1)
	stage:SetSize(w, h)
	stage.kind, stage.spec, stage.width, stage.height = kind, spec, w, h
	FitSample(canvas)
	stage:Show()
	return stage
end
