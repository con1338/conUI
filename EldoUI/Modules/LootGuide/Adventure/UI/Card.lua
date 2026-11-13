-- EldoUI My Adventure: the character card.
--
--   +----------------------------------------------------------- 600 x 340 --+
--   | [portrait]  Hedda Stonebrew                     Journal kept since Mar 2 |
--   |             Dwarf Priest · level 60 · 5d 18h played                     |
--   |  ▁▂▃▄▅▆▇█▇▆▅▆▇██▇▆▇▆▅▆▇▇▆▇██▇▇▆▇▆▇█▇▆▅▅▆▅▇▇█   (the mini river)          |
--   |  612 quests · 23 deaths · 4 dungeons · 15 runs · 1 raid · 742g earned    |
--   |  First dungeon in the journal: The Deadmines (19) · Most time: ...      |
--   |  [icon] Lucifron  [icon] Edwin VanCleef  [icon] Attuned: Molten Core     |
--   |  From Loch Modan to Winterspring, in 5 days and 18 hours of play.       |
--   |                                            EldoUI Journal · WoW: Forever |
--   +-------------------------------------------------------------------------+
--
-- Facts only (Story/Export.lua X.Card). Companion names, the guild and the
-- realm are never on the card. "Show card" hides the Journal window and
-- shows the card on a dimmed screen at 1.25 scale with a hint for your own
-- screenshot key and a "Take a screenshot" button: only that click takes
-- one (A.Moments:Screenshot, with the hint and the button hidden for the
-- shot). Esc or a click elsewhere closes it and brings the window back.
-- The card also copies as text or Markdown, and one line of it goes into
-- the chat box for you to send.
--
--   A.Card:Show(), A.Card:Hide(), A.Card:IsShown()
--   A.Card:Data() -> card, book, set
--   A.Card:CopyText(), A.Card:CopyMarkdown(), A.Card:ToChat()
--   A.Card.Build(parent) -> card frame;  frame:SetCard(card, book, set[, look])
local _, E = ...
local L = E.L
local A = E.Adventure
local J = E.Journal
local LG = E.LootGuide
local K = E.AdventureKit
local T = E.tokens

local CARD = {}
A.Card = CARD

local function SV() return A.StoryView end
local function Story() return E.Story end

local WIDTH, HEIGHT, INSET = 600, 340, 16
local SCALE = 1.25
local KEEP_ICON = 26

function CARD:Data()
	local book, set = SV().Build()
	if not (book and set) then return nil end
	return SV().CardData(book, set), book, set
end

---------------------------------------------------------------------------
-- The card frame
---------------------------------------------------------------------------
local function PaintLook(frame, look)
	if look == "Parchment" and T.paper then
		local fill, rule = T.paper.fill or T.paper.card, SV().Ink("rule", look)
		frame:SetBackdropColor(fill[1], fill[2], fill[3], 1)
		frame:SetBackdropBorderColor(rule[1], rule[2], rule[3], 1)
		frame.paper:Show()
	else
		E:SetTemplate(frame, look ~= "Night")
		frame.paper:Hide()
	end
end

function CARD.Build(parent)
	local frame = K.Card(parent, { solid = true })
	frame:SetSize(WIDTH, HEIGHT)
	frame.paper = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	frame.paper:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	frame.paper:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	if not E:SetClientAtlas(frame.paper, "AdventureMap_TileBg_Parchment", E.media.flat) then
		local fill = T.paper and T.paper.fill
		if fill then frame.paper:SetVertexColor(fill[1], fill[2], fill[3], 1) end
	end
	frame.paper:SetHorizTile(true)
	frame.paper:SetVertTile(true)
	frame.paper:Hide()

	frame.portrait = K.Art(frame, 56)
	frame.portrait:SetPoint("TOPLEFT", INSET, -INSET)
	frame.name = K.Text(frame, T.size.windowTitle, "LEFT", "head", true)
	frame.name:SetPoint("TOPLEFT", frame.portrait, "TOPRIGHT", 12, -4)
	frame.name:SetWordWrap(false)
	frame.since = K.Text(frame, K.size.small, "RIGHT", "secondary")
	frame.since:SetPoint("TOPRIGHT", -INSET, -INSET - 2)
	frame.name:SetPoint("TOPRIGHT", frame.since, "TOPLEFT", -8, 2 - 4) -- the name's top: 4 under the portrait's, the date's is 2
	frame.line = K.Text(frame, K.size.label, "LEFT", "secondary")
	frame.line:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -6)
	frame.line:SetWidth(WIDTH - INSET - (INSET + 56 + 12)) -- to the card's inset, right of the portrait
	frame.line:SetWordWrap(false)

	frame.river = A.River.Create(frame, { height = 40, mini = true })
	frame.river:SetPoint("TOPLEFT", INSET, -(INSET + 56 + 12))
	frame.river:SetPoint("TOPRIGHT", -INSET, -(INSET + 56 + 12))

	frame.stats = K.Text(frame, K.size.body, "LEFT", "body")
	frame.stats:SetPoint("TOPLEFT", frame.river, "BOTTOMLEFT", 0, -10)
	frame.stats:SetPoint("TOPRIGHT", frame.river, "BOTTOMRIGHT", 0, -10)
	frame.stats:SetWordWrap(true)
	frame.firsts = K.Text(frame, K.size.small, "LEFT", "secondary")
	frame.firsts:SetPoint("TOPLEFT", frame.stats, "BOTTOMLEFT", 0, -8)
	frame.firsts:SetPoint("TOPRIGHT", frame.stats, "BOTTOMRIGHT", 0, -8)
	frame.firsts:SetWordWrap(true)
	frame.keeps = {}
	frame.closing = K.Text(frame, K.size.body, "LEFT", "body")
	frame.closing:SetPoint("BOTTOMLEFT", INSET, INSET + 18)
	frame.closing:SetPoint("BOTTOMRIGHT", -INSET, INSET + 18)
	frame.closing:SetWordWrap(true)
	frame.footer = K.Text(frame, K.size.small, "RIGHT", "dim")
	frame.footer:SetPoint("BOTTOMRIGHT", -INSET, INSET - 4)

	function frame:SetCard(card, book, set, look)
		look = look or SV().Look()
		self.card = card
		PaintLook(self, look)
		local portrait = self.portrait.icon
		if set and set.charKey == E.charKey and SetPortraitTexture then
			SetPortraitTexture(portrait, "player")
			E:TrimIcon(portrait)
		else
			K.SetIcon(portrait, J.ICON and J.ICON.level or "Interface\\Icons\\INV_Misc_Book_09")
		end
		self.name:SetText(card.name or "")
		SV().Paint(self.name, "head", look)
		-- The game's class color (not on paper, where it reads too light).
		if card.class and look ~= "Parchment" and E.GetClassColor then
			local r, g, b = E:GetClassColor(card.class)
			if r then self.name:SetTextColor(r, g, b) end
		end
		self.since:SetText(card.since or "")
		SV().Paint(self.since, "secondary", look)
		self.line:SetText(card.line or "")
		SV().Paint(self.line, "secondary", look)
		self.river:SetBook(book, set)
		self.stats:SetText(Story().Export.StatLine(card))
		SV().Paint(self.stats, "body", look)
		self.firsts:SetText(Story().Export.FirstsLine(card))
		SV().Paint(self.firsts, "secondary", look)
		-- Keepsakes: icon and name, in one row under the firsts.
		local x = 0
		for index = 1, math.max(#self.keeps, #card.keepsakes) do
			local entry = card.keepsakes[index]
			local keep = self.keeps[index]
			if entry and not keep then
				keep = CreateFrame("Frame", nil, self)
				keep:SetHeight(KEEP_ICON)
				keep.art = K.Art(keep, KEEP_ICON)
				keep.art:SetPoint("LEFT")
				keep.text = K.Text(keep, K.size.small, "LEFT", "body")
				keep.text:SetPoint("LEFT", keep.art, "RIGHT", 6, 0)
				keep.text:SetWordWrap(false)
				self.keeps[index] = keep
			end
			if keep then
				keep:SetShown(entry ~= nil)
				if entry then
					local fact = set and set.byId[entry.id]
					K.SetIcon(keep.art.icon, A.Cover.FactIcon(fact))
					if entry.quality then
						keep.art:SetBackdropBorderColor(LG.Kit.QualityColor(entry.quality))
					else
						keep.art:SetBackdropBorderColor(unpack(E.media.borderColor))
					end
					keep.text:SetText(entry.text)
					SV().Paint(keep.text, "body", look)
					local w = KEEP_ICON + 6 + math.min(math.ceil(keep.text:GetStringWidth()), 120)
					keep.text:SetWidth(w - KEEP_ICON - 6)
					keep:SetWidth(w)
					keep:ClearAllPoints()
					keep:SetPoint("TOPLEFT", self.firsts, "BOTTOMLEFT", x, -10)
					x = x + w + 14
				end
			end
		end
		self.closing:SetText(card.closing and ('"' .. card.closing .. '"') or "")
		SV().Paint(self.closing, "body", look)
		self.footer:SetText(card.footer or "")
		SV().Paint(self.footer, "dim", look)
	end
	return frame
end

---------------------------------------------------------------------------
-- Screenshot mode
---------------------------------------------------------------------------
local overlay

local function ScreenshotKey()
	local key = GetBindingKey and GetBindingKey("SCREENSHOT")
	if type(key) == "string" and key ~= "" then
		return GetBindingText and GetBindingText(key) or key
	end
	return nil
end

local function Overlay()
	if overlay then return overlay end
	overlay = CreateFrame("Button", "EldoUI_JournalCardOverlay", UIParent)
	overlay:SetAllPoints(UIParent)
	overlay:SetFrameStrata("FULLSCREEN_DIALOG")
	overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	overlay.dim = overlay:CreateTexture(nil, "BACKGROUND")
	overlay.dim:SetAllPoints()
	overlay.dim:SetColorTexture(0, 0, 0, 0.75)
	overlay.card = CARD.Build(overlay)
	overlay.card:SetScale(SCALE)
	overlay.card:SetPoint("CENTER", 0, 10)
	overlay.hint = K.Text(overlay, K.size.label, "CENTER", "secondary")
	overlay.hint:SetPoint("TOP", 0, -24)
	overlay.shot = LG.Kit.Button(overlay, L["Take a screenshot"], 150, T.height.button, function()
		if A.Moments and A.Moments.Screenshot then A.Moments:Screenshot({ overlay.hint, overlay.shot }) end
	end, L["Take a screenshot"], L["Takes one screenshot of the card, without this button and the hint. It goes to the Screenshots folder of your game."])
	E.UIKit.FitButton(overlay.shot, 150)
	overlay.shot:SetPoint("TOP", overlay.hint, "BOTTOM", 0, -10)
	overlay:SetScript("OnClick", function() CARD:Hide() end)
	overlay:SetScript("OnHide", function()
		if overlay.reopen then
			local where = overlay.reopen
			overlay.reopen = nil
			if A:Running() then LG:Open("adventure", where) end
		end
	end)
	overlay:Hide()
	-- Esc closes it like any game window.
	local special = rawget(_G, "UISpecialFrames")
	if type(special) == "table" then special[#special + 1] = "EldoUI_JournalCardOverlay" end
	return overlay
end
CARD.Overlay = function() return overlay end

function CARD:Show()
	if not (A.Running and A:Running()) then return false end
	local card, book, set = self:Data()
	if not card then return false end
	local frame = Overlay()
	frame.card:SetCard(card, book, set)
	local key = ScreenshotKey()
	frame.hint:SetText(key and (L["Press %s to take a screenshot. Click or press Esc to close."]):format(E:Highlight(key))
		or L["Take a screenshot with your screenshot key. Click or press Esc to close."])
	frame.shot:SetShown(type(rawget(_G, "Screenshot")) == "function")
	if LG:IsOpen() and LG:CurrentPage() == "adventure" then
		frame.reopen = { section = A:CurrentSection() }
		LG:Close()
	end
	frame:Show()
	if SV().Motion() then E:PopIn(frame.card, 0.96) end
	return true
end

function CARD:Hide()
	if overlay then overlay:Hide() end
end

function CARD:IsShown()
	return overlay ~= nil and overlay:IsShown()
end

function CARD:CopyText()
	local card = self:Data()
	if not card then return false end
	SV().Copy(L["Your character card"], Story().Export.CardText(card))
	return true
end

function CARD:CopyMarkdown()
	local card = self:Data()
	if not card then return false end
	SV().Copy(L["Your character card as Markdown"], Story().Export.CardMarkdown(card))
	return true
end

-- One line in the chat box; the player presses Enter to send it.
function CARD:ToChat()
	local card = self:Data()
	if not card then return false end
	return SV().ChatInsert(Story().Export.ChatLine(card))
end
