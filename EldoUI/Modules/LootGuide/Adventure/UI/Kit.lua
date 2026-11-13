-- EldoUI My Adventure: the journal widgets (design.md 1 and 3).
--
-- Every hub page builds from these, so the Journey, Places, Quests,
-- Fellowship, Goals and Notes pages read as one book inside the Journal
-- window. They are made from E.UIKit, LG.Kit, LG.PageKit and the design
-- tokens; nothing here picks its own color, font or size. On the paper
-- page (the Storybook style) every part reads its ink from K.Ink, which
-- returns E.tokens.paper.* when those tokens exist and E.tokens.text.*
-- otherwise. Text on paper is ink: the theme font without the outline and
-- without the shadow (K.InkFont), because a dark edge around dark letters
-- on light paper closes their counters. The panel looks keep the profile's
-- outline and shadow.
--
-- The kit is E.AdventureKit; while the Adventure module is loaded the same
-- functions are also on it (A.Header, A.Pill, ...).
--
-- Page parts
--   K.Header(parent)                 page header: title, sentence, actions, divider
--   K.Switch(parent, options, active, onPick)   segmented choice (Level / Day / Zone)
--   K.Search(parent, key, hint, onChange)       page search; the query is kept per key
--   K.Fold(parent, onToggle)         a fold row (caption, note, rule, chevron)
--   K.FoldOpen(key, default), K.SetFoldOpen(key, open)   fold state per character
--   K.LevelBadge(parent, size)       a chapter number in a square box
--   K.Pill(parent, text, kind)       Now, First kill, Ready (accent, good, warn, bad, plain)
--   K.StatPill(parent)               "41 kills": a number and a label in a chip
--   K.Track(parent, height)          progress bar (accent, good when reached)
--   K.SplitBar(parent, height)       one bar of colored parts (time split)
--   K.Tally(parent, width)           number and label rows in a box
--   K.Card(parent, opts)             a card box (see-through panel or paper)
--   K.InfoCard(parent)               clickable card: icon, title, lines, track, right label
--   K.HoverLinks(row, links)         quiet text links shown while the row is hovered
--   K.Provenance(parent)             "from Instances" chip: where a fact came from
--   K.Empty(parent)                  a designed empty state
--   K.UndoToast(owner, text, id)     "Removed. Undo" over the page (E.Journal:Undo)
--   K.Art(parent, size)              an icon box (LG.PageKit P.Art)
-- Journal list (a variable-height E.UIKit list; only rows on screen exist)
--   K.CreateJournalList(parent, opts) items { kind = <row kind>, ... }:
--     space, fold, chapter, chapterClosed, ledger, line, note, standing,
--     victory, find, more (fields at each kind in K.ROWS)
--   K.ROWS[kind] = { height = fn(item, width), create = fn(row), update = fn(row, item) }
--   Lazy rows: an item { kind, lazy = fn(item) -> the real item } is built
--   only when it comes on screen (once); until then it is measured as one
--   line of its kind (K.LAZY_SHAPE). K.LazyRows(count, fn(i), kind) makes
--   a list of them; list:SetData({ count = fn() -> n, item = fn(i), kind })
--   (the provider form) does the same for a whole list. K.stats.built
--   counts the items built.
--   Timeline: an item with `spine = true` draws the 2 px line through the
--   chapter badges; chapter rows take spine = { up = bool, down = bool }.
local _, E = ...
local LG = E.LootGuide
local L = E.L
local T = E.tokens

local K = {}
E.AdventureKit = K

local function Kit() return LG.Kit end
local function PageKit() return LG.PageKit end

local texts = setmetatable({}, { __mode = "k" })     -- font string -> true
local restylers = setmetatable({}, { __mode = "k" }) -- object -> repaint fn
local queries = {}                                   -- page search text per key
local sessionFolds = {}                              -- fold state with no journal yet

-- Layout numbers (DESIGN.md 3: steps of 4).
K.SPINE_X = 20          -- the timeline's left edge (through the badge centers)
K.SPINE_WIDTH = 2
K.CHAPTER_INDENT = 58   -- where a chapter's title and moments start
K.CARD_INSET = 12
K.TIME_WIDTH = 56

---------------------------------------------------------------------------
-- Type ramp. The journal is a window you sit in and read, so its body,
-- row and caption text sits a few steps above the shared sizes (E.tokens
-- size.*): K.size.small, label, body and section are the token plus
-- K.TextStep(); K.size.caption is the small caption over folds and pills.
-- Titles keep the shared sizes. Heights that hold text read these too, so
-- rows, chips and cards grow with their text.
---------------------------------------------------------------------------
local STEPPED = { small = true, label = true, body = true, section = true }

function K.TextStep()
	local journal = T.journal
	return journal and tonumber(journal.textStep) or 2
end

K.size = setmetatable({}, { __index = function(_, key)
	if key == "caption" then return T.size.small + K.TextStep() - 1 end
	local base = T.size[key]
	if type(base) ~= "number" then return nil end
	return STEPPED[key] and base + K.TextStep() or base
end })

---------------------------------------------------------------------------
-- Ink and density
---------------------------------------------------------------------------
-- The paper page is on while the Adventure page setting says "paper" and
-- the paper tokens exist. K.paper overrides it (option previews).
function K.OnPaper()
	if K.paper ~= nil then return K.paper and T.paper ~= nil end
	local A = E.Adventure
	local db = A and A.db
	return db and db.page == "paper" and T.paper ~= nil or false
end

local PANEL_INK = { head = "body", link = "secondary" }

-- role: body, secondary, dim, head, link, good, warn, bad, accent, rule
-- -> { r, g, b[, a] }
function K.Ink(role)
	role = role or "body"
	if role == "accent" then return E.media.accentColor end
	if K.OnPaper() then
		local ink = T.paper[role]
		if ink then return ink end
	end
	if role == "rule" then return T.edge.divider end
	return T.text[PANEL_INK[role] or role] or T.text.body
end

-- A color escape in an ink, for words inside a sentence (numbers in body).
function K.InkHex(role)
	return E:TokenHex(K.Ink(role))
end

function K.Num(value, role)
	return K.InkHex(role or "body") .. tostring(value) .. "|r"
end

function K.Compact()
	return LG.db and LG.db.density == "compact" or false
end

-- Does this text sit on paper? Story texts (the Book, the part covers,
-- the stats spread, the character card) follow the Book's look, which
-- StoryView.Paint stores on them; every other kit text follows the page
-- style (K.OnPaper).
local function OnPaperText(fs)
	if fs.akLook ~= nil then return fs.akLook == "Parchment" and T.paper ~= nil end
	return K.OnPaper()
end
K.OnPaperText = OnPaperText

-- Set a kit text's font: on paper the ink font (the theme font with no
-- outline and no shadow), else the theme font with the profile's outline
-- and shadow. size and header default to what the text had; paper
-- defaults to where the text sits. The text keeps size, header and paper
-- so a theme change or a look switch puts the same font back.
function K.InkFont(fs, size, header, paper)
	if not fs then return end
	size = size or fs.akSize or K.size.body
	if header ~= nil then fs.akHeader = header and true or false end
	if paper == nil then paper = OnPaperText(fs) end
	fs.akSize, fs.akPaper = size, paper and true or false
	if fs.akPaper then
		if fs.akHeader then E:SetHeaderFont(fs, size, "") else E:SetFont(fs, size, "") end
		fs:SetShadowOffset(0, 0)
	elseif fs.akHeader then
		E:SetHeaderFont(fs, size)
	else
		E:SetFont(fs, size)
	end
end

function K.Paint(fs, role)
	if not fs then return end
	fs.akRole = role or fs.akRole or "body"
	local SV = fs.akLook ~= nil and E.Adventure and E.Adventure.StoryView
	local c = SV and SV.Ink(fs.akRole, fs.akLook) or K.Ink(fs.akRole)
	fs:SetTextColor(c[1], c[2], c[3])
	local paper = OnPaperText(fs)
	if fs.akSize and fs.akPaper ~= paper then K.InkFont(fs, nil, nil, paper) end
	if paper then fs:SetShadowOffset(0, 0) end
end

-- header: the theme's header font (titles, chapter names).
function K.Text(parent, size, justify, role, header, layer)
	local fs = E:CreateText(parent, size or K.size.body, justify or "LEFT", layer)
	K.InkFont(fs, size or K.size.body, header)
	texts[fs] = true
	K.Paint(fs, role)
	return fs
end

local function SetSize(fs, size)
	K.InkFont(fs, size)
	K.Paint(fs)
end

-- Repaint every kit text and box (theme change, paper on or off).
function K.Restyle()
	for fs in pairs(texts) do
		K.InkFont(fs)
		K.Paint(fs)
	end
	for object, fn in pairs(restylers) do
		local ok, err = pcall(fn, object)
		if not ok then geterrorhandler()(err) end
	end
end

-- Theme changes come through the theme registry (Core/Media.lua); the
-- paper switch calls K.Restyle itself.
E:OnThemeChanged("adventure", function() K.Restyle() end)

-- A light wash of the paper color over a tiled parchment texture
-- (E.tokens.paper.wash), so the grain of the paper stays but calms down
-- under long reading text. K.ShowPaper shows or hides both together.
function K.PaperWash(parent, paper, sublevel)
	local wash = parent:CreateTexture(nil, "BACKGROUND", nil, sublevel)
	wash:SetAllPoints(paper)
	wash:SetTexture(E.media.flat)
	local fill = T.paper and T.paper.fill
	if fill then wash:SetVertexColor(fill[1], fill[2], fill[3], T.paper.wash or 0) end
	wash:Hide()
	paper.wash = wash
	return wash
end

function K.ShowPaper(paper, shown)
	if not paper then return end
	paper:SetShown(shown)
	local wash = paper.wash
	if wash then wash:SetShown(shown and T.paper ~= nil and (tonumber(T.paper.wash) or 0) > 0) end
end

local function HoverTexture(frame)
	local hover = frame:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, T.hover.row)
	return hover
end

local function SetIcon(texture, icon)
	if icon == nil then
		texture:Hide()
		return
	end
	if type(icon) == "string" and Kit().HasAtlas(icon) then
		texture:SetAtlas(icon)
	else
		texture:SetTexture(E:ClientIcon(icon))
		E:TrimIcon(texture)
	end
	texture:Show()
end
K.SetIcon = SetIcon

-- A rule (1 px line) in the rule ink.
local function Rule(parent, kind, layer)
	local line = parent:CreateTexture(nil, layer or "ARTWORK")
	E:Hairline(line, kind or "h", 1)
	local c = K.Ink("rule")
	line:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
	line.akRule = true
	return line
end
K.Rule = Rule

local function PaintRule(line)
	local c = K.Ink("rule")
	line:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

---------------------------------------------------------------------------
-- Boxes
---------------------------------------------------------------------------
-- A card box: the see-through panel template, or on paper the paper card
-- fill with a rule edge. opts: solid (not see-through), accent (2 px
-- accent bar down the left).
local function PaintCard(card)
	if K.OnPaper() then
		local fill, edge = T.paper.card or K.Ink("body"), K.Ink("rule")
		card:SetBackdropColor(fill[1], fill[2], fill[3], fill[4] or 1)
		card:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
	else
		E:SetTemplate(card, not card.akSolid)
	end
	if card.bar then
		local c = E.media.accentColor
		card.bar:SetColorTexture(c[1], c[2], c[3], 1)
	end
end

function K.Card(parent, opts)
	opts = opts or {}
	local card = CreateFrame("Frame", nil, parent)
	card.akSolid = opts.solid and true or false
	E:SetTemplate(card, not card.akSolid)
	if opts.accent then
		card.bar = card:CreateTexture(nil, "OVERLAY")
		card.bar:SetPoint("TOPLEFT", E:PixelFor(card), -E:PixelFor(card))
		card.bar:SetPoint("BOTTOMLEFT", E:PixelFor(card), E:PixelFor(card))
		E:Hairline(card.bar, "w", 2)
	end
	function card:SetAccent(on)
		if self.bar then self.bar:SetShown(on and true or false) end
	end
	PaintCard(card)
	restylers[card] = PaintCard
	return card
end

function K.Art(parent, size)
	local art = PageKit().Art(parent, size)
	E:TrimIcon(art.icon)
	return art
end

---------------------------------------------------------------------------
-- Header: title (window title size, header font), a sentence under it
-- (wraps to two lines, the full text in a tooltip when cut), actions on
-- the right and a divider at the bottom. 52 px.
--   header:SetTitle(text[, r, g, b]), header:SetSentence(text)
--   header:SetActions({ { label, onClick, tip }, ... })  right to left
---------------------------------------------------------------------------
K.HEADER_HEIGHT = 52

function K.Header(parent)
	local header = CreateFrame("Frame", nil, parent)
	header:SetHeight(K.HEADER_HEIGHT)
	header.title = K.Text(header, T.size.windowTitle, "LEFT", "head", true)
	header.title:SetPoint("TOPLEFT", 0, 0)
	header.title:SetWordWrap(false)
	header.sentence = K.Text(header, K.size.label, "LEFT", "secondary")
	header.sentence:SetPoint("TOPLEFT", 0, -26)
	header.sentence:SetWordWrap(true)
	header.sentence:SetMaxLines(2)
	header.tip = CreateFrame("Frame", nil, header)
	header.tip:SetAllPoints(header.sentence)
	header.line = Kit().Divider(header)
	header.line:SetPoint("BOTTOMLEFT")
	header.line:SetPoint("BOTTOMRIGHT")
	header.buttons = {}

	function header:Layout()
		local right = 0
		for _, button in ipairs(self.buttons) do
			if button:IsShown() then right = right + button:GetWidth() + 8 end
		end
		self.title:SetPoint("TOPRIGHT", self, "TOPRIGHT", -right, 0)
		self.sentence:SetPoint("TOPRIGHT", self, "TOPRIGHT", -right, -26)
	end

	-- Titles, sentences and button labels may come as English keys from
	-- tables built while the files load: they are translated here.
	function header:SetTitle(text, r, g, b)
		self.title:SetText(E:Translate(text) or "")
		if r then self.title:SetTextColor(r, g, b) else K.Paint(self.title, "head") end
	end

	function header:SetSentence(text)
		text = E:Translate(text)
		self.sentence:SetText(text or "")
		self.fullSentence = text
		-- The tooltip only matters when two lines do not hold it.
		local cut = (self.sentence:GetNumLines() or 0) >= 2 and self.sentence:IsTruncated()
		self.tip:EnableMouse(cut and true or false)
		Kit().Tooltip(self.tip, nil, cut and text or nil)
	end

	function header:SetActions(actions)
		local anchor
		for index = 1, math.max(#self.buttons, actions and #actions or 0) do
			local data = actions and actions[index]
			local button = self.buttons[index]
			if data and not button then
				button = Kit().Button(self, "", 80, T.height.button)
				self.buttons[index] = button
			end
			if button then
				button:SetShown(data ~= nil)
				if data then
					button:SetText(E:Translate(data[1] or data.label))
					E.UIKit.FitButton(button, 60)
					button:SetScript("OnClick", data[2] or data.onClick)
					Kit().Tooltip(button, data[1] or data.label, data[3] or data.tip)
					button:ClearAllPoints()
					if anchor then
						button:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
					else
						button:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
					end
					anchor = button
				end
			end
		end
		self:Layout()
	end
	return header
end

---------------------------------------------------------------------------
-- Switch: adjacent toggles, 2 px apart; the active one in the accent.
--   options = { { key, label, tip }, ... }; switch:SetActive(key), :GetActive()
--   switch:SetLabel(key, text) (a count after a label)
---------------------------------------------------------------------------
function K.Switch(parent, options, active, onPick)
	local switch = CreateFrame("Frame", nil, parent)
	switch:SetHeight(18)
	switch.buttons = {}
	local x = 0
	for index, option in ipairs(options or {}) do
		local key = option[1] or option.key
		local button = PageKit().Toggle(switch, option[2] or option.label, function()
			if switch.active == key then return end
			switch:SetActive(key)
			if onPick then
				local ok, err = pcall(onPick, key)
				if not ok then geterrorhandler()(err) end
			end
		end, option[2] or option.label, option[3] or option.tip)
		button.key = key
		E:SkinHoverPress(button)
		E:PadHitRect(button, 2)
		switch.buttons[index] = button
	end
	function switch:Layout()
		x = 0
		-- Hidden buttons (a view with nothing in it) leave no gap.
		for _, button in ipairs(self.buttons) do
			button:ClearAllPoints()
			button:SetPoint("LEFT", self, "LEFT", x, 0)
			if button:IsShown() then x = x + button:GetWidth() + 2 end
		end
		self:SetWidth(math.max(x - 2, 1))
	end
	function switch:SetActive(key)
		self.active = key
		for _, button in ipairs(self.buttons) do button:SetOn(button.key == key) end
	end
	function switch:GetActive() return self.active end
	function switch:SetLabel(key, text)
		for _, button in ipairs(self.buttons) do
			if button.key == key then button:SetLabel(text) end
		end
		self:Layout()
	end
	switch:Layout()
	switch:SetActive(active)
	restylers[switch] = function(self) self:SetActive(self.active) end
	return switch
end

---------------------------------------------------------------------------
-- Search: the game's search box in the EldoUI look, 20 px. The query is
-- kept per page key for the session; onChange(text) after each typed key.
---------------------------------------------------------------------------
function K.Search(parent, key, hint, onChange)
	local box = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
	box:SetHeight(20)
	box:SetAutoFocus(false)
	E:SkinEditBox(box)
	box.key = key
	E:SearchHint(box, hint)
	if hint and box.Instructions then
		local c = K.Ink("dim")
		box.Instructions:SetTextColor(c[1], c[2], c[3])
	end
	Kit().Tooltip(box, L["Search"], hint)
	box:HookScript("OnTextChanged", function(self, typed)
		if not typed then return end
		queries[self.key] = self:GetText() or ""
		if onChange then
			local ok, err = pcall(onChange, queries[self.key])
			if not ok then geterrorhandler()(err) end
		end
	end)
	box:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
	function box:Query() return queries[self.key] or "" end
	box:SetText(queries[key] or "")
	return box
end

function K.Query(key)
	return queries[key] or ""
end

---------------------------------------------------------------------------
-- Folds: state per character (the journal's ui.collapsed), else per
-- session until the journal exists.
---------------------------------------------------------------------------
local function FoldStore()
	local J = E.Journal
	local rec = J and J.Char and J:Char()
	local ui = rec and rec.ui
	if type(ui) == "table" then
		if type(ui.collapsed) ~= "table" then ui.collapsed = {} end
		return ui.collapsed
	end
	return sessionFolds
end

-- collapsed[key]: true = closed, false = opened by hand, nil = default.
function K.FoldOpen(key, default)
	local state = FoldStore()[key]
	if state == nil then return default ~= false end
	return state == false
end

function K.SetFoldOpen(key, open)
	FoldStore()[key] = not open
end

-- The fold row (22 px): upper-case caption in the accent, a note in
-- secondary, a rule to the chevron, the chevron (down open, right
-- closed). The whole row toggles.
--   fold:Set(label, note, open), fold.onToggle(fold, open)
K.FOLD_HEIGHT = 22

local function CreateFold(fold)
	fold:RegisterForClicks("LeftButtonUp")
	HoverTexture(fold)
	fold.caption = K.Text(fold, K.size.caption, "LEFT", "accent")
	fold.caption:SetPoint("LEFT", 0, 0)
	fold.caption:SetWordWrap(false)
	fold.note = K.Text(fold, K.size.small, "LEFT", "secondary")
	fold.note:SetPoint("LEFT", fold.caption, "RIGHT", 8, 0)
	fold.note:SetWordWrap(false)
	fold.chevron = fold:CreateTexture(nil, "ARTWORK")
	fold.chevron:SetSize(10, 10)
	fold.chevron:SetPoint("RIGHT", -4, 0)
	fold.chevron:SetTexture(E.media.chevron)
	fold.rule = Rule(fold)
	fold.rule:SetPoint("LEFT", fold.note, "RIGHT", 8, 0)
	fold.rule:SetPoint("RIGHT", fold.chevron, "LEFT", -8, 0)
	function fold:Set(label, note, open)
		self.caption:SetText(E:CaptionText(label or ""))
		K.Paint(self.caption, "accent")
		self.note:SetText(note or "")
		self.open = open and true or false
		self.chevron:SetRotation(self.open and 0 or math.pi / 2)
		local c = K.Ink("secondary")
		self.chevron:SetVertexColor(c[1], c[2], c[3])
		PaintRule(self.rule)
	end
	fold:SetScript("OnClick", function(self)
		self.open = not self.open
		self.chevron:SetRotation(self.open and 0 or math.pi / 2)
		if self.onToggle then
			local ok, err = pcall(self.onToggle, self, self.open)
			if not ok then geterrorhandler()(err) end
		end
	end)
	fold:Set("", nil, true)
	return fold
end

function K.Fold(parent, onToggle)
	local fold = CreateFrame("Button", nil, parent)
	fold:SetHeight(K.FOLD_HEIGHT)
	CreateFold(fold)
	fold.onToggle = onToggle
	return fold
end

---------------------------------------------------------------------------
-- Level badge: the chapter number in a square box (header font), accent
-- border on the current chapter.
---------------------------------------------------------------------------
local function PaintBadge(badge)
	if badge.current then
		badge:SetBackdropBorderColor(Kit().Accent())
	else
		badge:SetBackdropBorderColor(unpack(E.media.borderColor))
	end
end

function K.LevelBadge(parent, size)
	local badge = CreateFrame("Frame", nil, parent)
	E:SetTemplate(badge)
	badge.number = K.Text(badge, 15, "CENTER", "body", true)
	badge.number:SetPoint("CENTER", 0, 0)
	function badge:SetBadgeSize(px)
		self:SetSize(px, px)
		SetSize(self.number, px >= 40 and 15 or 12)
	end
	function badge:SetLevel(level, current)
		self.number:SetText(level ~= nil and tostring(level) or "")
		self.current = current and true or false
		PaintBadge(self)
	end
	badge:SetBadgeSize(size or 42)
	badge:SetLevel(nil, false)
	restylers[badge] = PaintBadge
	return badge
end

---------------------------------------------------------------------------
-- Pills and stat pills (16 px chips).
---------------------------------------------------------------------------
local PILL_INK = { accent = "accent", good = "good", warn = "warn", bad = "bad" }

local function PaintPill(pill)
	local role = PILL_INK[pill.kind] or "secondary"
	local c = K.Ink(role)
	pill.text:SetTextColor(c[1], c[2], c[3])
	if pill.kind and pill.kind ~= "plain" then
		pill:SetBackdropBorderColor(c[1], c[2], c[3])
	else
		pill:SetBackdropBorderColor(unpack(E.media.borderColor))
	end
end

function K.Pill(parent, text, kind)
	local pill = CreateFrame("Frame", nil, parent)
	E:SetTemplate(pill, true)
	pill.text = K.Text(pill, K.size.caption, "CENTER", "secondary")
	pill.text:SetPoint("CENTER", 0, 0)
	function pill:Set(label, how)
		self.text:SetText(E:Translate(label) or "")
		self.kind = how
		self:SetSize(math.ceil(self.text:GetStringWidth()) + 10, 16)
		PaintPill(self)
	end
	pill:Set(text, kind)
	restylers[pill] = PaintPill
	return pill
end

-- "41 kills": the number in body, the label in secondary.
function K.StatPill(parent)
	local pill = CreateFrame("Frame", nil, parent)
	E:SetTemplate(pill, true)
	pill:SetHeight(18)
	pill.value = K.Text(pill, K.size.small, "LEFT", "body")
	pill.value:SetPoint("LEFT", 6, 0)
	pill.label = K.Text(pill, K.size.small, "LEFT", "secondary")
	pill.label:SetPoint("LEFT", pill.value, "RIGHT", 4, 0)
	function pill:Set(value, label, tip)
		label = E:Translate(label)
		self.value:SetText(value ~= nil and tostring(value) or "")
		self.label:SetText(label or "")
		self:SetWidth(math.ceil(self.value:GetStringWidth() + self.label:GetStringWidth()) + 16)
		self:EnableMouse(tip ~= nil)
		Kit().Tooltip(self, tip and label, tip)
	end
	pill:Set(nil, nil)
	restylers[pill] = function(self) PaintCard(self) end
	return pill
end

---------------------------------------------------------------------------
-- Track: a progress bar that follows the bar texture. 6 px on cards, 16 px
-- with "have / need" inside. Accent while in progress, good when reached.
--   track:SetProgress(have, need[, label])
---------------------------------------------------------------------------
function K.Track(parent, height)
	local track = E:CreateStatusBar(parent)
	track:SetHeight(height or 6)
	track:SetMinMaxValues(0, 1)
	track:SetValue(0)
	track.label = K.Text(track, K.size.small, "CENTER", "body")
	track.label:SetPoint("CENTER", 0, 0)
	function track:SetProgress(have, need, label)
		have, need = tonumber(have) or 0, tonumber(need) or 0
		local frac = need > 0 and math.min(math.max(have / need, 0), 1) or 0
		self:SetValue(frac)
		self.reached = need > 0 and have >= need
		local c = self.reached and K.Ink("good") or E.media.accentColor
		self:SetStatusBarColor(c[1], c[2], c[3])
		local tall = (self:GetHeight() or 0) >= 12
		if label == nil and tall and need > 0 then label = ("%s / %s"):format(BreakUpLargeNumbers(have), BreakUpLargeNumbers(need)) end
		self.label:SetText(tall and label or "")
		self.label:SetShown(tall)
	end
	track:SetProgress(0, 0)
	restylers[track] = function(self) self:SetProgress(self:GetValue(), 1, self.label:GetText()) end
	return track
end

-- One bar made of parts: { { value, color = { r, g, b }, label }, ... }.
-- The caller picks colors from the game or the tokens.
function K.SplitBar(parent, height)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(height or 6)
	E:SetTemplate(bar, true)
	bar.segments = {}
	function bar:SetParts(parts)
		local total = 0
		for _, part in ipairs(parts or {}) do total = total + math.max(tonumber(part[1] or part.value) or 0, 0) end
		local width = math.max((self:GetWidth() or 0) - 2 * E:PixelFor(self), 0)
		local x = E:PixelFor(self)
		for index = 1, math.max(#self.segments, parts and #parts or 0) do
			local part = parts and parts[index]
			local seg = self.segments[index]
			if part and not seg then
				seg = self:CreateTexture(nil, "ARTWORK")
				self.segments[index] = seg
			end
			if seg then
				local value = part and math.max(tonumber(part[1] or part.value) or 0, 0) or 0
				local w = total > 0 and width * value / total or 0
				seg:SetShown(part ~= nil and w >= 1)
				if part and w >= 1 then
					local c = part.color or part[2] or K.Ink("secondary")
					seg:SetColorTexture(c[1], c[2], c[3], 1)
					seg:ClearAllPoints()
					seg:SetPoint("TOPLEFT", self, "TOPLEFT", x, -E:PixelFor(self))
					seg:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, E:PixelFor(self))
					seg:SetWidth(w)
					x = x + w
				end
			end
		end
		self.parts = parts
	end
	bar:SetScript("OnSizeChanged", function(self) if self.parts then self:SetParts(self.parts) end end)
	return bar
end

---------------------------------------------------------------------------
-- Tally: a box of rows "label ........ number" (20 px rows, 10 px inset).
--   tally:SetRows({ { value, label, onClick, tip }, ... })
---------------------------------------------------------------------------
function K.Tally(parent, width)
	local tally = K.Card(parent, { solid = true })
	tally:SetWidth(width or 210)
	tally.rows = {}
	function tally:SetRows(rows)
		local count = rows and #rows or 0
		for index = 1, math.max(#self.rows, count) do
			local data = rows and rows[index]
			local row = self.rows[index]
			if data and not row then
				row = CreateFrame("Button", nil, self)
				row:SetHeight(20)
				row:SetPoint("TOPLEFT", 10, -(8 + (index - 1) * 20))
				row:SetPoint("TOPRIGHT", -10, -(8 + (index - 1) * 20))
				row.label = K.Text(row, K.size.small, "LEFT", "secondary")
				row.label:SetPoint("LEFT")
				row.value = K.Text(row, K.size.body, "RIGHT", "body")
				row.value:SetPoint("RIGHT")
				row.hover = HoverTexture(row)
				self.rows[index] = row
			end
			if row then
				row:SetShown(data ~= nil)
				if data then
					row.value:SetText(data[1] ~= nil and tostring(data[1]) or "")
					row.label:SetText(data[2] or "")
					row:SetScript("OnClick", data[3])
					row:EnableMouse(data[3] ~= nil or data[4] ~= nil)
					row.hover:SetShown(data[3] ~= nil)
					Kit().Tooltip(row, data[4] and data[2], data[4])
				end
			end
		end
		self:SetHeight(16 + count * 20)
	end
	tally:SetRows({})
	return tally
end

---------------------------------------------------------------------------
-- Hover links: Archive / Edit / Pin / Done as quiet 11 pt text buttons
-- that turn accent on hover, laid right to left 12 px apart, shown only
-- while the row (or a link) is under the mouse. links = { { label, onClick, tip } }
-- The hit rect is the text plus 4 px (DESIGN.md 3a).
---------------------------------------------------------------------------
local function LinksVisible(row)
	local over = row:IsMouseOver()
	for _, link in ipairs(row.akLinks or {}) do over = over or (link:IsShown() and link:IsMouseOver()) end
	return over
end

local function SyncLinks(row)
	local show = row.akLinksForced or LinksVisible(row)
	for index, link in ipairs(row.akLinks or {}) do link:SetShown(show and row.akLinkData[index] ~= nil) end
end

function K.HoverLinks(row, links)
	row.akLinks = row.akLinks or {}
	row.akLinkData = links or {}
	local anchor
	for index = 1, math.max(#row.akLinks, #row.akLinkData) do
		local data = row.akLinkData[index]
		local link = row.akLinks[index]
		if data and not link then
			link = CreateFrame("Button", nil, row)
			link:SetHeight(16)
			link.text = K.Text(link, K.size.small, "RIGHT", "secondary")
			link.text:SetPoint("RIGHT")
			link:SetScript("OnEnter", function(self) K.Paint(self.text, "accent") end)
			link:SetScript("OnLeave", function(self)
				K.Paint(self.text, "secondary")
				C_Timer.After(0, function() SyncLinks(row) end)
			end)
			row.akLinks[index] = link
		end
		if link then
			link:Hide()
			if data then
				link.text:SetText(E:Translate(data[1] or data.label))
				link:SetWidth(math.ceil(link.text:GetStringWidth()))
				E:PadHitRect(link, 4)
				link:SetScript("OnClick", data[2] or data.onClick)
				Kit().Tooltip(link, data[1] or data.label, data[3] or data.tip)
				link:ClearAllPoints()
				if anchor then
					link:SetPoint("RIGHT", anchor, "LEFT", -12, 0)
				else
					link:SetPoint("TOPRIGHT", row, "TOPRIGHT", -K.CARD_INSET, -4)
				end
				anchor = link
			end
		end
	end
	if not row.akLinksHooked then
		row.akLinksHooked = true
		row:HookScript("OnEnter", SyncLinks)
		row:HookScript("OnLeave", function(self) C_Timer.After(0, function() SyncLinks(self) end) end)
		row:HookScript("OnHide", function(self) for _, link in ipairs(self.akLinks) do link:Hide() end end)
	end
end

---------------------------------------------------------------------------
-- Provenance chip: where a fact came from ("from Instances").
---------------------------------------------------------------------------
function K.Provenance(parent)
	local chip = K.Pill(parent, "", "plain")
	chip:EnableMouse(true)
	function chip:SetSource(title, tip)
		self:Set(title and (L["from %s"]):format(title) or "", "plain")
		self:SetShown(title ~= nil)
		Kit().Tooltip(self, L["Where this comes from"], tip or L["The journal shows what the game and your other EldoUI modules wrote down. Nothing is guessed."])
	end
	return chip
end

---------------------------------------------------------------------------
-- Empty state and undo
---------------------------------------------------------------------------
-- empty:Set(title, text, icon, buttons) as LG.Kit.EmptyState.
function K.Empty(parent)
	return Kit().EmptyState(parent)
end

-- A short "Removed" notice with Undo over the page (DESIGN.md 5): the row
-- comes back through E.Journal:Undo(trashID).
function K.UndoToast(owner, text, trashID, onUndo)
	return E.UIKit.Toast(owner, text or L["Removed from your journal."], {
		action = { L["Undo"], function()
			local J = E.Journal
			local ok = J and J.Undo and J:Undo(trashID)
			if onUndo then onUndo(ok) end
		end },
	})
end

---------------------------------------------------------------------------
-- Info card (places, dungeons, companions): icon, title, two lines, an
-- optional track with a right label. Clickable with the row hover.
--   card:Set({ icon, title, titleColor = { r, g, b }, lines = { a, b },
--     progress = { have, need, label }, right, onClick, tip })
---------------------------------------------------------------------------
function K.InfoCard(parent)
	local card = CreateFrame("Button", nil, parent)
	card.box = K.Card(card)
	card.box:SetAllPoints()
	card.box:SetFrameLevel(math.max(card:GetFrameLevel() - 1, 0))
	card.hover = HoverTexture(card)
	card.art = K.Art(card, 36)
	card.art:SetPoint("TOPLEFT", K.CARD_INSET, -K.CARD_INSET)
	card.title = K.Text(card, K.size.section + 2, "LEFT", "head", true)
	card.title:SetWordWrap(false)
	card.line1 = K.Text(card, K.size.small, "LEFT", "secondary")
	card.line1:SetWordWrap(false)
	card.line2 = K.Text(card, K.size.small, "LEFT", "secondary")
	card.line2:SetWordWrap(false)
	card.track = K.Track(card, 6)
	card.right = K.Text(card, K.size.small, "RIGHT", "secondary")
	function card:Set(data)
		data = data or {}
		local left = K.CARD_INSET
		if data.icon ~= nil then
			SetIcon(self.art.icon, data.icon)
			self.art:Show()
			left = K.CARD_INSET + 36 + 10
		else
			self.art:Hide()
		end
		self.title:ClearAllPoints()
		self.title:SetPoint("TOPLEFT", left, -10)
		self.title:SetPoint("TOPRIGHT", -K.CARD_INSET, -10)
		self.title:SetText(data.title or "")
		local tc = data.titleColor
		if tc then self.title:SetTextColor(tc[1], tc[2], tc[3]) else K.Paint(self.title, "head") end
		local lines = data.lines or {}
		self.line1:ClearAllPoints()
		self.line1:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -4)
		self.line1:SetPoint("TOPRIGHT", self.title, "BOTTOMRIGHT", 0, -4)
		self.line1:SetText(lines[1] or "")
		local below = self.line1
		if data.progress then
			self.track:ClearAllPoints()
			self.track:SetPoint("TOPLEFT", self.line1, "BOTTOMLEFT", 0, -8)
			self.track:SetPoint("TOPRIGHT", self.line1, "BOTTOMRIGHT", -(76 - K.CARD_INSET), -8)
			self.track:SetProgress(data.progress[1], data.progress[2])
			self.track:Show()
			self.right:ClearAllPoints()
			self.right:SetPoint("LEFT", self.track, "RIGHT", 8, 0)
			self.right:SetPoint("RIGHT", -K.CARD_INSET, 0)
			self.right:SetText(data.right or data.progress[3] or "")
			self.right:Show()
			below = self.track
		else
			self.track:Hide()
			self.right:SetShown(data.right ~= nil)
			self.right:ClearAllPoints()
			self.right:SetPoint("TOPRIGHT", -K.CARD_INSET, -12)
			self.right:SetText(data.right or "")
		end
		self.line2:ClearAllPoints()
		self.line2:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -6)
		self.line2:SetPoint("TOPRIGHT", below, "BOTTOMRIGHT", below == self.track and (76 - K.CARD_INSET) or 0, -6)
		self.line2:SetText(lines[2] or "")
		self:SetScript("OnClick", data.onClick)
		self.hover:SetShown(data.onClick ~= nil)
		Kit().Tooltip(self, data.tip and data.title, data.tip)
	end
	return card
end

---------------------------------------------------------------------------
-- Journal list rows. Each kind gives height(item, width), create(row) and
-- update(row, item). Fields per kind:
--   space          height
--   fold           key, label, note, open, onToggle(item, open)
--   chapter        level, title, sentence, current, now (pill), open,
--                  onToggle(item, open), spine = { up, down }
--   chapterClosed  level, title, meta, time, current, onToggle, spine
--   ledger         icon, title, sub, time, position (first, middle, last,
--                  only), onClick(item, button), tip (string or fn(tooltip)),
--                  links (hover links), indent, spine
--   line           icon, text, time, onClick, tip, indent, spine (24 px)
--   note           text, sub, pinned, indent, spine (pinned note keepsake)
--   standing       icon, faction, standing, color, time, indent, spine
--   victory        instance, time, bosses = { { name, sub, icon,
--                  displayID } }, loot = { item data for P.SetItem },
--                  footer, indent, spine
--   find           item (P.SetItem data), position, indent, spine
--   more           text, onClick, indent, spine ("Show all 431")
---------------------------------------------------------------------------
local ROWS = {}
K.ROWS = ROWS

local function Indent(item)
	return item.indent or 0
end

-- The timeline segment through a row.
local function Spine(row)
	if not row.spine then
		row.spine = row:CreateTexture(nil, "BACKGROUND", nil, 1)
		row.spine:SetWidth(K.SPINE_WIDTH)
	end
	return row.spine
end

local function PaintSpine(texture)
	local c = K.OnPaper() and K.Ink("rule") or T.edge.window
	texture:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

local function UpdateSpine(row, item)
	local on = item.spine and item.spine ~= false
	if not on then
		if row.spine then row.spine:Hide() end
		return
	end
	local spine = Spine(row)
	spine:ClearAllPoints()
	spine:SetPoint("TOPLEFT", row, "TOPLEFT", K.SPINE_X, 0)
	spine:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", K.SPINE_X, 0)
	PaintSpine(spine)
	spine:Show()
end

-- Card segments: a ledger card spans several rows, each draws its slice.
local function CardSlice(row)
	if row.slice then return row.slice end
	local slice = {}
	slice.fill = row:CreateTexture(nil, "BACKGROUND", nil, 2)
	slice.left = row:CreateTexture(nil, "BORDER")
	slice.right = row:CreateTexture(nil, "BORDER")
	slice.top = row:CreateTexture(nil, "BORDER")
	slice.bottom = row:CreateTexture(nil, "BORDER")
	slice.divider = row:CreateTexture(nil, "BORDER")
	E:Hairline(slice.left, "w", 1)
	E:Hairline(slice.right, "w", 1)
	E:Hairline(slice.top, "h", 1)
	E:Hairline(slice.bottom, "h", 1)
	E:Hairline(slice.divider, "h", 1)
	row.slice = slice
	return slice
end

local function UpdateSlice(row, item)
	local slice = CardSlice(row)
	local x = Indent(item)
	local position = item.position or "only"
	local fill, edge
	if K.OnPaper() then
		fill, edge = T.paper.card or K.Ink("body"), K.Ink("rule")
	else
		local bd = E.media.backdropColor
		fill = { bd[1], bd[2], bd[3], E:PanelAlpha(true) }
		edge = E.media.borderColor
	end
	slice.fill:ClearAllPoints()
	slice.fill:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
	slice.fill:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
	slice.fill:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
	for _, side in ipairs({ "left", "right", "top", "bottom" }) do
		slice[side]:SetColorTexture(edge[1], edge[2], edge[3], edge[4] or 1)
	end
	slice.left:ClearAllPoints()
	slice.left:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
	slice.left:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 0)
	slice.right:ClearAllPoints()
	slice.right:SetPoint("TOPRIGHT")
	slice.right:SetPoint("BOTTOMRIGHT")
	local top = position == "first" or position == "only"
	local bottom = position == "last" or position == "only"
	slice.top:ClearAllPoints()
	slice.top:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
	slice.top:SetPoint("TOPRIGHT")
	slice.top:SetShown(top)
	slice.bottom:ClearAllPoints()
	slice.bottom:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 0)
	slice.bottom:SetPoint("BOTTOMRIGHT")
	slice.bottom:SetShown(bottom)
	-- Rows inside one card are divided by a rule, inset like the content.
	slice.divider:ClearAllPoints()
	slice.divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x + K.CARD_INSET, 0)
	slice.divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -K.CARD_INSET, 0)
	PaintRule(slice.divider)
	slice.divider:SetShown(not bottom)
	for _, part in pairs(slice) do if part ~= slice.divider and part ~= slice.top and part ~= slice.bottom then part:Show() end end
end

local function HideSlice(row)
	if not row.slice then return end
	for _, part in pairs(row.slice) do part:Hide() end
end

local function RowTooltip(row, item)
	Kit().Tooltip(row, item.tipTitle or (item.tip and (item.title or item.text)), item.tip)
end

local function RowClick(row, item)
	if item.onClick then
		row:SetScript("OnClick", function(self, button)
			local data = self.item
			if type(data) == "table" and data.built then data = data.built end
			local ok, err = pcall(item.onClick, data, button, self)
			if not ok then geterrorhandler()(err) end
		end)
	else
		row:SetScript("OnClick", nil)
	end
	if row.hover then row.hover:SetShown(item.onClick ~= nil) end
end

-- Rows take the mouse only for a click, a tooltip or hover links.
local function MouseFor(row, item)
	row:EnableMouse((item.onClick or item.tip or (item.links and item.links[1])) and true or false)
end

local function ToggleClick(row)
	row:SetScript("OnClick", function(self)
		local data = self.item
		if not data then return end
		data.open = not data.open
		if data.key then K.SetFoldOpen(data.key, data.open) end
		if data.onToggle then
			local ok, err = pcall(data.onToggle, data, data.open, self)
			if not ok then geterrorhandler()(err) end
		end
	end)
end

-- space ------------------------------------------------------------------
ROWS.space = {
	height = function(item) return item.height or 8 end,
	create = function(row) row:EnableMouse(false) end,
	update = function(row, item) UpdateSpine(row, item) end,
}

-- fold -------------------------------------------------------------------
ROWS.fold = {
	height = function() return K.FOLD_HEIGHT end,
	create = function(row) CreateFold(row) end,
	update = function(row, item)
		row:Set(item.label, item.note, item.open)
		row.caption:ClearAllPoints()
		row.caption:SetPoint("LEFT", Indent(item), 0)
		row.onToggle = function(_, open)
			item.open = open
			if item.key then K.SetFoldOpen(item.key, open) end
			if item.onToggle then item.onToggle(item, open, row) end
		end
		UpdateSpine(row, item)
	end,
}

-- chapter (open) -----------------------------------------------------------
local function ChapterParts(row, small)
	row:RegisterForClicks("LeftButtonUp")
	row.hover = HoverTexture(row)
	row.badge = K.LevelBadge(row, small and 32 or 42)
	row.title = K.Text(row, small and K.size.body or 15, "LEFT", small and "body" or "head", not small)
	row.title:SetWordWrap(false)
	row.chevron = row:CreateTexture(nil, "ARTWORK")
	row.chevron:SetSize(10, 10)
	row.chevron:SetTexture(E.media.chevron)
	row.now = K.Pill(row, L["Now"], "accent")
	row.spineUp = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.spineUp:SetWidth(K.SPINE_WIDTH)
	row.spineDown = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.spineDown:SetWidth(K.SPINE_WIDTH)
	ToggleClick(row)
end

local function ChapterSpine(row, item)
	local spine = type(item.spine) == "table" and item.spine or {}
	row.spineUp:ClearAllPoints()
	-- The badge is centered on the spine, so both ends keep its left edge.
	row.spineUp:SetPoint("TOPLEFT", row, "TOPLEFT", K.SPINE_X, 0)
	row.spineUp:SetPoint("BOTTOMLEFT", row.badge, "CENTER", -K.SPINE_WIDTH / 2, 0)
	row.spineDown:ClearAllPoints()
	row.spineDown:SetPoint("TOPLEFT", row.badge, "CENTER", -K.SPINE_WIDTH / 2, 0)
	row.spineDown:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", K.SPINE_X, 0)
	PaintSpine(row.spineUp)
	PaintSpine(row.spineDown)
	row.spineUp:SetShown(spine.up and true or false)
	row.spineDown:SetShown(spine.down and true or false)
end

local function ChapterTitle(row, item)
	row.title:SetText(item.title or "")
	row.now:SetShown(item.now and true or false)
	if item.now then
		row.now:Set(L["Now"], "accent")
		row.now:ClearAllPoints()
		row.now:SetPoint("LEFT", row.title, "LEFT", math.min(math.ceil(row.title:GetStringWidth()), row.title:GetWidth() or 0) + 8, 0)
	end
	row.chevron:SetRotation(item.open and 0 or math.pi / 2)
	local c = K.Ink("secondary")
	row.chevron:SetVertexColor(c[1], c[2], c[3])
	Kit().Tooltip(row, item.title, nil, { { L["Click"], item.open and L["fold this chapter"] or L["open this chapter"] } })
end

ROWS.chapter = {
	height = function(item, width)
		local small = K.Compact()
		local base = small and 44 or 56
		if not item.sentence or item.sentence == "" then return base - 12 end
		return math.max(base, 6 + 20 + E.UIKit.TextHeight(item.sentence, width - K.CHAPTER_INDENT - 24, K.size.small) + 6)
	end,
	create = function(row) ChapterParts(row, false) end,
	update = function(row, item)
		local small = K.Compact()
		row.badge:SetBadgeSize(small and 32 or 42)
		row.badge:ClearAllPoints()
		row.badge:SetPoint("TOPLEFT", K.SPINE_X + K.SPINE_WIDTH / 2 - (small and 16 or 21), -6)
		row.badge:SetLevel(item.level, item.current)
		row.title:ClearAllPoints()
		row.title:SetPoint("TOPLEFT", K.CHAPTER_INDENT, -8)
		row.title:SetPoint("TOPRIGHT", -60, -8)
		row.chevron:ClearAllPoints()
		row.chevron:SetPoint("TOPRIGHT", -6, -12)
		if not row.sentence then
			row.sentence = K.Text(row, K.size.small, "LEFT", "secondary")
			row.sentence:SetWordWrap(true)
		end
		row.sentence:ClearAllPoints()
		row.sentence:SetPoint("TOPLEFT", K.CHAPTER_INDENT, -28)
		row.sentence:SetPoint("TOPRIGHT", -24, -28)
		row.sentence:SetText(item.sentence or "")
		ChapterTitle(row, item)
		ChapterSpine(row, item)
	end,
}

-- chapter (closed): one 40 px row ------------------------------------------
ROWS.chapterClosed = {
	height = function() return K.Compact() and 34 or 40 end,
	create = function(row)
		ChapterParts(row, true)
		row.meta = K.Text(row, K.size.small, "LEFT", "secondary")
		row.meta:SetWordWrap(false)
		row.time = K.Text(row, K.size.small, "RIGHT", "secondary")
	end,
	update = function(row, item)
		row.badge:SetBadgeSize(K.Compact() and 26 or 32)
		row.badge:ClearAllPoints()
		row.badge:SetPoint("LEFT", K.SPINE_X + K.SPINE_WIDTH / 2 - (K.Compact() and 13 or 16), 0)
		row.badge:SetLevel(item.level, item.current)
		row.title:ClearAllPoints()
		row.title:SetPoint("LEFT", K.CHAPTER_INDENT, 0)
		row.title:SetWidth(200)
		row.meta:ClearAllPoints()
		row.meta:SetPoint("LEFT", K.CHAPTER_INDENT + 210, 0)
		row.meta:SetPoint("RIGHT", row.time, "LEFT", -8, 0)
		row.meta:SetText(item.meta or "")
		row.chevron:ClearAllPoints()
		row.chevron:SetPoint("RIGHT", -6, 0)
		row.time:ClearAllPoints()
		row.time:SetPoint("RIGHT", row.chevron, "LEFT", -8, 0)
		row.time:SetText(item.time or "")
		ChapterTitle(row, item)
		ChapterSpine(row, item)
	end,
}

-- ledger: one moment inside a card -------------------------------------------


local function TextLeft(item)
	local icon = K.Compact() and 24 or 30
	return Indent(item) + K.CARD_INSET + (item.icon ~= nil and (icon + 12) or 0)
end

-- Row height, icon size and the padding above and below the text.
local function LedgerSizes()
	if K.Compact() then return 34, 24, 3 end
	return 44, 30, 8
end

local function LedgerContent(item, width)
	local textWidth = width - TextLeft(item) - K.TIME_WIDTH - K.CARD_INSET
	local title = E.UIKit.TextHeight(item.title, textWidth, K.size.body)
	local sub = (item.sub and item.sub ~= "") and (K.size.small + 4) or 0
	return title + sub
end

ROWS.ledger = {
	height = function(item, width)
		local base, _, pad = LedgerSizes()
		return math.max(base, LedgerContent(item, width) + 2 * pad)
	end,
	create = function(row)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.hover = HoverTexture(row)
		row.art = K.Art(row, 30)
		row.title = K.Text(row, K.size.body, "LEFT", "body")
		row.title:SetWordWrap(true)
		row.sub = K.Text(row, K.size.small, "LEFT", "secondary")
		row.sub:SetWordWrap(false)
		row.time = K.Text(row, K.size.small, "RIGHT", "secondary")
	end,
	update = function(row, item, width)
		local base, icon, pad = LedgerSizes()
		UpdateSlice(row, item)
		local x = Indent(item) + K.CARD_INSET
		-- The text block sits in the middle of the row (one line or two).
		local top = math.max(pad, math.floor(((row:GetHeight() or base) - LedgerContent(item, width or row:GetWidth() or 0)) / 2))
		if item.icon ~= nil then
			row.art:SetSize(icon, icon)
			row.art:ClearAllPoints()
			row.art:SetPoint("TOPLEFT", row, "TOPLEFT", x, -math.floor((base - icon) / 2))
			SetIcon(row.art.icon, item.icon)
			row.art:Show()
		else
			row.art:Hide()
		end
		row.time:ClearAllPoints()
		row.time:SetPoint("TOPRIGHT", row, "TOPRIGHT", -K.CARD_INSET, -top)
		row.time:SetWidth(K.TIME_WIDTH)
		row.time:SetText(item.time or "")
		row.title:ClearAllPoints()
		row.title:SetPoint("TOPLEFT", row, "TOPLEFT", TextLeft(item), -top)
		row.title:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(K.CARD_INSET + K.TIME_WIDTH), -top)
		row.title:SetText(item.title or "")
		K.Paint(row.title, item.titleRole or "body")
		row.sub:ClearAllPoints()
		row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
		row.sub:SetPoint("TOPRIGHT", row.title, "BOTTOMRIGHT", K.TIME_WIDTH, -4)
		row.sub:SetText(item.sub or "")
		RowClick(row, item)
		RowTooltip(row, item)
		K.HoverLinks(row, item.links)
		MouseFor(row, item)
		UpdateSpine(row, item)
	end,
}

-- line: a 24 px event line -------------------------------------------------
ROWS.line = {
	height = function() return 24 end,
	create = function(row)
		row:RegisterForClicks("LeftButtonUp")
		row.hover = HoverTexture(row)
		row.art = K.Art(row, 18)
		row.text = K.Text(row, K.size.label, "LEFT", "body")
		row.text:SetWordWrap(false)
		row.time = K.Text(row, K.size.small, "RIGHT", "secondary")
	end,
	update = function(row, item)
		local x = Indent(item)
		row.art:ClearAllPoints()
		row.art:SetPoint("LEFT", x, 0)
		SetIcon(row.art.icon, item.icon)
		row.art:SetShown(item.icon ~= nil)
		row.time:ClearAllPoints()
		row.time:SetPoint("RIGHT", -4, 0)
		row.time:SetText(item.time or "")
		row.text:ClearAllPoints()
		row.text:SetPoint("LEFT", x + (item.icon ~= nil and 24 or 0), 0)
		row.text:SetPoint("RIGHT", row.time, "LEFT", -8, 0)
		row.text:SetText(item.text or "")
		RowClick(row, item)
		RowTooltip(row, item)
		MouseFor(row, item)
		UpdateSpine(row, item)
	end,
}

-- note: a pinned note keepsake (accent bar, text, "where · when") -------------
local function NoteWidth(item, width)
	return width - Indent(item) - 2 * K.CARD_INSET - 2
end

ROWS.note = {
	height = function(item, width)
		local text = E.UIKit.TextHeight(item.text, NoteWidth(item, width), K.size.body, { spacing = 2 })
		local sub = (item.sub and item.sub ~= "") and (K.size.small + 6) or 0
		return 10 + text + sub + 10 + 6
	end,
	create = function(row)
		row.card = K.Card(row, { accent = true })
		row.text = K.Text(row.card, K.size.body, "LEFT", "body")
		row.text:SetWordWrap(true)
		row.text:SetSpacing(2)
		row.sub = K.Text(row.card, K.size.small, "LEFT", "secondary")
		row.sub:SetWordWrap(false)
	end,
	update = function(row, item)
		row.card:ClearAllPoints()
		row.card:SetPoint("TOPLEFT", row, "TOPLEFT", Indent(item), -3)
		row.card:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 3)
		row.card:SetAccent(item.pinned ~= false)
		row.text:ClearAllPoints()
		row.text:SetPoint("TOPLEFT", K.CARD_INSET + 2, -10)
		row.text:SetPoint("TOPRIGHT", -K.CARD_INSET, -10)
		row.text:SetText(item.text or "")
		row.sub:ClearAllPoints()
		row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -6)
		row.sub:SetPoint("TOPRIGHT", row.text, "BOTTOMRIGHT", 0, -6)
		row.sub:SetText(item.sub or "")
		K.HoverLinks(row, item.links)
		MouseFor(row, item)
		UpdateSpine(row, item)
	end,
}

-- standing: "<Faction> now counts you as" + the standing in its color -------
ROWS.standing = {
	height = function() return 72 end,
	create = function(row)
		row:EnableMouse(false)
		row.card = K.Card(row)
		row.art = K.Art(row.card, 40)
		row.art:SetPoint("LEFT", K.CARD_INSET, 0)
		row.lead = K.Text(row.card, K.size.small, "LEFT", "secondary")
		row.lead:SetPoint("TOPLEFT", row.art, "TOPRIGHT", 12, -2)
		row.lead:SetWordWrap(false)
		row.standing = K.Text(row.card, 16, "LEFT", "body", true)
		row.standing:SetPoint("TOPLEFT", row.lead, "BOTTOMLEFT", 0, -4)
		row.time = K.Text(row.card, K.size.small, "RIGHT", "secondary")
		row.time:SetPoint("TOPRIGHT", -K.CARD_INSET, -10)
		-- The art sits in the middle of the 64 high card, so the lead line starts
		-- 4 lower than the time.
		row.lead:SetPoint("TOPRIGHT", row.time, "TOPLEFT", -8, -4)
	end,
	update = function(row, item)
		row.card:ClearAllPoints()
		row.card:SetPoint("TOPLEFT", row, "TOPLEFT", Indent(item), -4)
		row.card:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 4)
		SetIcon(row.art.icon, item.icon or "Interface\\Icons\\INV_Misc_Note_02")
		row.lead:SetText((L["%s now counts you as"]):format(item.faction or ""))
		row.standing:SetText(item.standing or "")
		-- The reaction color for the standing: custom ones from the Colors
		-- page, the game's otherwise.
		local c = item.color or (item.standingID and E:ReactionColorObject(item.standingID))
		if c then row.standing:SetTextColor(c.r or c[1], c.g or c[2], c.b or c[3]) else K.Paint(row.standing, "body") end
		row.time:SetText(item.time or "")
		UpdateSpine(row, item)
	end,
}

-- victory: first kills of one run --------------------------------------------
local VICTORY_HEAD, VICTORY_BOSS, VICTORY_FOOT = 24, 56, 20

local function LootHeight()
	return math.max(Kit().RowHeight(), 20) + 2
end

ROWS.victory = {
	height = function(item)
		local bosses = item.bosses and #item.bosses or 0
		local loot = item.loot and #item.loot or 0
		local foot = (item.footer and item.footer ~= "") and VICTORY_FOOT or 0
		return 4 + VICTORY_HEAD + bosses * VICTORY_BOSS + loot * LootHeight() + foot + 8
	end,
	create = function(row)
		row:EnableMouse(false)
		row.card = K.Card(row)
		row.head = row.card:CreateTexture(nil, "BACKGROUND", nil, 3)
		row.head:SetPoint("TOPLEFT", E.pixel, -E.pixel)
		row.head:SetPoint("TOPRIGHT", -E.pixel, -E.pixel)
		row.head:SetHeight(VICTORY_HEAD)
		row.instance = K.Text(row.card, K.size.section, "LEFT", "head", true)
		row.instance:SetPoint("LEFT", row.head, "LEFT", K.CARD_INSET, 0)
		row.instance:SetWordWrap(false)
		row.date = K.Text(row.card, K.size.small, "RIGHT", "secondary")
		row.date:SetPoint("RIGHT", row.head, "RIGHT", -K.CARD_INSET, 0)
		row.instance:SetPoint("RIGHT", row.date, "LEFT", -8, 0)
		row.foot = K.Text(row.card, K.size.small, "LEFT", "secondary")
		row.bosses, row.loot = {}, {}
	end,
	update = function(row, item)
		row.card:ClearAllPoints()
		row.card:SetPoint("TOPLEFT", row, "TOPLEFT", Indent(item), -4)
		row.card:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 4)
		local inset = K.OnPaper() and K.Ink("rule") or T.inset
		row.head:SetColorTexture(inset[1], inset[2], inset[3], inset[4] or 1)
		row.instance:SetText(item.instance or "")
		row.date:SetText(item.time or "")
		local y = VICTORY_HEAD + 4
		local bosses = item.bosses or {}
		for index = 1, math.max(#row.bosses, #bosses) do
			local data = bosses[index]
			local boss = row.bosses[index]
			if data and not boss then
				boss = CreateFrame("Frame", nil, row.card)
				boss:SetHeight(VICTORY_BOSS)
				boss.art = K.Art(boss, 44)
				boss.art:SetPoint("LEFT", K.CARD_INSET, 0)
				boss.name = K.Text(boss, K.size.section + 2, "LEFT", "head", true)
				boss.name:SetPoint("TOPLEFT", boss.art, "TOPRIGHT", 12, -6)
				boss.name:SetPoint("TOPRIGHT", boss, "RIGHT", -K.CARD_INSET, 22 - 6) -- the 44 px art is centered
				boss.name:SetWordWrap(false)
				boss.sub = K.Text(boss, K.size.small, "LEFT", "secondary")
				boss.sub:SetPoint("TOPLEFT", boss.name, "BOTTOMLEFT", 0, -4)
				boss.sub:SetPoint("TOPRIGHT", boss.name, "BOTTOMRIGHT", 0, -4)
				boss.sub:SetWordWrap(false)
				row.bosses[index] = boss
			end
			if boss then
				boss:SetShown(data ~= nil)
				if data then
					boss:ClearAllPoints()
					boss:SetPoint("TOPLEFT", row.card, "TOPLEFT", 0, -y)
					boss:SetPoint("TOPRIGHT", row.card, "TOPRIGHT", 0, -y)
					local setPortrait = rawget(_G, "SetPortraitTextureFromCreatureDisplayID")
					if data.displayID and setPortrait then
						setPortrait(boss.art.icon, data.displayID)
						E:TrimIcon(boss.art.icon)
					else
						SetIcon(boss.art.icon, data.icon or "Interface\\Icons\\INV_Misc_Head_Dragon_01")
					end
					boss.name:SetText(data.name or "")
					boss.sub:SetText(data.sub or "")
					y = y + VICTORY_BOSS
				end
			end
		end
		local loot = item.loot or {}
		local lootHeight = LootHeight()
		for index = 1, math.max(#row.loot, #loot) do
			local data = loot[index]
			local cell = row.loot[index]
			if data and not cell then
				cell = PageKit().ItemCell(row.card)
				row.loot[index] = cell
			end
			if cell then
				cell:SetShown(data ~= nil)
				if data then
					cell:ClearAllPoints()
					cell:SetPoint("TOPLEFT", row.card, "TOPLEFT", K.CARD_INSET + 56, -y)
					cell:SetPoint("TOPRIGHT", row.card, "TOPRIGHT", -K.CARD_INSET, -y)
					cell:SetHeight(lootHeight - 2)
					PageKit().SetItem(cell, data)
					y = y + lootHeight
				end
			end
		end
		row.foot:ClearAllPoints()
		row.foot:SetPoint("TOPLEFT", row.card, "TOPLEFT", K.CARD_INSET, -(y + 2))
		row.foot:SetText(item.footer or "")
		UpdateSpine(row, item)
	end,
}

-- find: an item inside the ledger card ----------------------------------------
ROWS.find = {
	height = function() return math.max(Kit().RowHeight(), 20) + 8 end,
	create = function(row)
		row:EnableMouse(false)
		row.cell = PageKit().ItemCell(row)
	end,
	update = function(row, item)
		UpdateSlice(row, item)
		row.cell:ClearAllPoints()
		row.cell:SetPoint("LEFT", row, "LEFT", Indent(item) + K.CARD_INSET, 0)
		row.cell:SetPoint("RIGHT", row, "RIGHT", -K.CARD_INSET, 0)
		row.cell:SetHeight(math.max(Kit().RowHeight(), 20))
		PageKit().SetItem(row.cell, item.item or {})
		UpdateSpine(row, item)
	end,
}

-- more: "Show all 431" ---------------------------------------------------------
ROWS.more = {
	height = function() return 22 end,
	create = function(row)
		row:RegisterForClicks("LeftButtonUp")
		row.text = K.Text(row, K.size.small, "LEFT", "secondary")
		row:SetScript("OnEnter", function(self) K.Paint(self.text, "accent") end)
		row:SetScript("OnLeave", function(self) K.Paint(self.text, "secondary") end)
	end,
	update = function(row, item)
		row.text:ClearAllPoints()
		row.text:SetPoint("LEFT", Indent(item) + K.CARD_INSET, 0)
		row.text:SetText(item.text or "")
		K.Paint(row.text, "secondary")
		row:SetHitRectInsets(0, math.max((row:GetWidth() or 0) - Indent(item) - K.CARD_INSET - math.ceil(row.text:GetStringWidth()) - 4, 0), 0, 0)
		RowClick(row, item)
		UpdateSpine(row, item)
	end,
}

-- "Show all 431 moments" for a long group.
function K.MoreText(count)
	return (E:Plural(count, "Show all %d moment", "Show all %d moments")):format(count)
end

-- Lazy rows ------------------------------------------------------------------
K.stats = { built = 0 }

-- What a row not built yet is measured as: one line of its kind.
local SAMPLE = "M"   -- one line of text, measured
K.LAZY_SHAPE = { ledger = { title = SAMPLE, sub = SAMPLE, icon = true }, line = { text = SAMPLE } }

local function Built(item)
	if type(item) ~= "table" or type(item.lazy) ~= "function" then return item end
	local built = item.built
	if built then return built end
	local ok, made = pcall(item.lazy, item)
	if not ok then geterrorhandler()(made) end
	built = ok and type(made) == "table" and made or { kind = "space", height = 1 }
	-- The place the page gave it (card position, indent) stays.
	for key, value in pairs(item) do
		if built[key] == nil and key ~= "lazy" and key ~= "built" then built[key] = value end
	end
	built.kind = ROWS[built.kind] and built.kind or item.kind
	item.built = built
	K.stats.built = K.stats.built + 1
	return built
end
K.Built = Built

-- count rows of one kind, each built by fn(i) when it comes on screen.
function K.LazyRows(count, fn, kind)
	local rows = {}
	for index = 1, math.max(tonumber(count) or 0, 0) do
		rows[index] = { kind = kind or "ledger", lazy = function() return fn(index) end }
	end
	return rows
end

local lazyHeights = {}   -- "kind|width" -> px (cleared on a restyle)

local function LazyHeight(item, width)
	local key = tostring(item.kind) .. "|" .. tostring(math.floor(width or 0))
	local height = lazyHeights[key]
	if not height then
		local def = ROWS[item.kind]
		height = def and def.height(K.LAZY_SHAPE[item.kind] or item, width) or T.height.row
		lazyHeights[key] = height
	end
	return height
end

-- The list: one variable-height E.UIKit list whose rows are pooled per kind.
--   K.CreateJournalList(parent, { empty = { title, text, icon, buttons }, onScroll })
--   list:SetData(items[, keepScroll]); the page rebuilds items after a toggle
--   list:SetData({ count = fn, item = fn(i), kind }[, keepScroll]); the
--   provider form: only the rows on screen are built
function K.CreateJournalList(parent, opts)
	opts = opts or {}
	local list
	list = E.UIKit.CreateList(parent, {
		height = function(item, _, width)
			if type(item.lazy) == "function" and not item.built then return LazyHeight(item, width) end
			item = Built(item)
			local def = ROWS[item.kind]
			return def and def.height(item, width) or T.height.row
		end,
		kind = function(item) return ROWS[item.kind] and item.kind or "space" end,
		create = function(row, kind)
			ROWS[kind].create(row)
		end,
		update = function(row, item, _, kind)
			ROWS[kind].update(row, Built(item), list.rowWidth)
		end,
		gap = opts.gap or 0,
		step = opts.step,
		empty = opts.empty,
		onScroll = opts.onScroll,
	})
	local setData = list.SetData
	function list:SetData(items, keepScroll)
		if type(items) == "table" and type(items.count) == "function" and type(items.item) == "function" then
			items = K.LazyRows(items.count(), items.item, items.kind)
		end
		return setData(self, items, keepScroll)
	end
	-- Paper on or off, a new font or density: rows draw again.
	restylers[list] = function(self)
		wipe(lazyHeights)
		if #self.data > 0 then self:Relayout() end
	end
	return list
end

-- While the Adventure module is loaded the kit is on it too (A.Header, ...).
local A = E.Adventure
if A then
	A.Kit = K
	for name, value in pairs(K) do
		if type(value) == "function" and A[name] == nil then A[name] = value end
	end
end
