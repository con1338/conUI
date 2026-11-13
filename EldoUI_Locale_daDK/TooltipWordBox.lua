-- Danish word help in item tooltips: a small framed box on the edge of an
-- item tooltip with the Danish word for what the item is ("Le" on a
-- scythe). The English name stays exactly as the game shows it; the box
-- only adds a word.
--
-- Off until the player turns it on: Tooltip > Danish word help. This file
-- ships in the Danish pack, so it loads only with Dansk picked under
-- General > EldoUI language; with any other language none of it exists.
--
-- How a word is found (the reviewed word list is TooltipWords.lua):
--   * The head noun is the last word of the name's base: the text before
--     " of ", " - " or "(", and for "Pattern: Red Linen Robe" the part
--     before the colon. Only a head noun on the word list gets a box;
--     nothing is guessed or translated on the fly.
--   * No box for a name that starts with "The" or "Enchant", has a
--     possessive or a comma, for Epic quality or better, or for an item on
--     the skip list: those are names, not ordinary words.
--   * The item names are English, so the box needs the English game client.
--
-- What it touches: only the item's ID, name and quality, read through the
-- game's tooltip post-call, and only when they are plain values (a secret
-- or not yet loaded name gets no box; the game runs the post-call again
-- when the item loads). The box is EldoUI's own frame, kept in this file's
-- own table and parented to the tooltip so it hides, scales and fades with
-- it. Blizzard's lines, text and width stay as they are, and the box never
-- widens the tooltip: it is cut to the tooltip's width with "...".
local E = EldoUI
if not E then return end
local _, P = ...
local L = E.L
local Kit = E.UIKit

local WORDS = P.tooltipWords or {}
local SKIPS = P.tooltipSkips or {}

local EPIC = 4
local ENGLISH_CLIENT = { enUS = true, enGB = true }
local MAX_WIDTH = 140   -- the widest box, in pixels
local MIN_WIDTH = 24    -- the narrowest cut box: the flag and a letter or two
local SIDE_GAP = 8      -- inset from the tooltip's left edge; the cap keeps it 8 px from the right too
local PAD = 5           -- text padding inside the box
local FLAG_W, FLAG_H, FLAG_GAP = 11, 8, 3
local MIN_HEIGHT = 16
local REFRESH = 0.1     -- seconds between layout checks while the box shows

local H = {}
E.TooltipWordHelp = H

local function Plain(value)
	if value == nil or (issecretvalue and issecretvalue(value)) then return nil end
	return value
end

-- The base of an item name: before " of ", " - " or "(", then before ":".
local function BaseOf(name)
	local cut = #name + 1
	local at = name:lower():find("%s+of%s+")
	if at and at < cut then cut = at end
	at = name:find("%s+%-%s+")
	if at and at < cut then cut = at end
	at = name:find("%s*%(")
	if at and at < cut then cut = at end
	local base = name:sub(1, cut - 1)
	local colon = base:find(":", 1, true)
	if colon then base = base:sub(1, colon - 1) end
	return base
end

-- The head noun of an item name, or nil when the name never gets a box.
function H.HeadWord(name)
	if type(name) ~= "string" or name == "" then return nil end
	local lower = name:lower()
	if lower:find("^the%f[%W]") or lower:find("^enchant%f[%W]") then return nil end
	if name:find("'", 1, true) or name:find(",", 1, true) then return nil end
	return BaseOf(name):match("(%S+)%s*$")
end

-- The Danish word an item gets, or nil.
function H.Tag(name, quality, itemID)
	if itemID and SKIPS[itemID] then return nil end
	if (tonumber(quality) or 0) >= EPIC then return nil end
	local head = H.HeadWord(name)
	return head and WORDS[head] or nil
end

-- On while the language is Dansk, the game client is English, the
-- Blizzard UI page lets EldoUI add to tooltips, and the player ticked it.
function H.Enabled()
	if E:GetLanguage() ~= "daDK" or not ENGLISH_CLIENT[GetLocale()] then return false end
	if E.BlizzardAllowed and not E:BlizzardAllowed("tooltips", "improve") then return false end
	local module = E.modules and E.modules.Tooltip
	local db = module and module.db
	return type(db) == "table" and db.danishWords == true
end

---------------------------------------------------------------------------
-- The box
---------------------------------------------------------------------------
local boxes = {}  -- tooltip -> its box
local cache = {}  -- item ID -> { tag or false, quality }

local function Edges(frame)
	if E.FrameCheck(frame, "IsAnchoringRestricted") then return end
	local ok, top, bottom = pcall(function() return frame:GetTop(), frame:GetBottom() end)
	if ok and type(top) == "number" and type(bottom) == "number" then return top, bottom end
end

local function Width(frame)
	local ok, width = pcall(frame.GetWidth, frame)
	if ok and type(width) == "number" and not (issecretvalue and issecretvalue(width)) then return width end
end

-- Fit the box to its word and the tooltip: never wider than the tooltip
-- minus the side gaps, never wider than MAX_WIDTH, one line cut with "...".
-- On the top edge, or on the bottom edge when the top would leave the screen.
function H.Layout(box)
	local tooltip = box.tooltip
	-- Measured again each time: a new font or Large text changes it.
	if box.text.GetUnboundedStringWidth then
		local ok, natural = pcall(box.text.GetUnboundedStringWidth, box.text)
		if ok and type(natural) == "number" then box.natural = natural end
	end
	local flagWidth = box.flag:IsShown() and (FLAG_W + FLAG_GAP) or 0
	local cap = MAX_WIDTH
	local tooltipWidth = Width(tooltip)
	if tooltipWidth then cap = math.min(cap, tooltipWidth - 2 * SIDE_GAP) end
	cap = math.max(cap, MIN_WIDTH)
	local width = math.min(math.ceil(box.natural) + flagWidth + 2 * PAD, cap)
	box.text:SetWidth(math.max(width - flagWidth - 2 * PAD, 1))
	local okHeight, textHeight = pcall(box.text.GetStringHeight, box.text)
	textHeight = okHeight and type(textHeight) == "number" and textHeight or 0
	box:SetSize(width, math.max(MIN_HEIGHT, math.ceil(textHeight) + 6))

	local below = false
	local top = Edges(tooltip)
	local screenTop = Edges(UIParent)
	if top and screenTop then
		local scale = tooltip:GetEffectiveScale() / UIParent:GetEffectiveScale()
		below = (top + box:GetHeight()) * scale > screenTop
	end
	if box.below ~= below then
		box.below = below
		box:ClearAllPoints()
		if below then
			box:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", SIDE_GAP, 1)
		else
			box:SetPoint("BOTTOMLEFT", tooltip, "TOPLEFT", SIDE_GAP, -1)
		end
	end
end

local function OnUpdate(box, elapsed)
	box.elapsed = box.elapsed + elapsed
	if box.elapsed < REFRESH then return end
	box.elapsed = 0
	H.Layout(box)
end

function H.Box(tooltip)
	local box = boxes[tooltip]
	if box then return box end
	box = CreateFrame("Frame", nil, tooltip)
	E:SetTemplate(box, true)
	box:EnableMouse(false)
	box:SetFrameLevel((tooltip:GetFrameLevel() or 0) + 5)
	box.tooltip = tooltip
	box.flag = box:CreateTexture(nil, "ARTWORK")
	box.flag:SetSize(FLAG_W, FLAG_H)
	box.flag:SetPoint("LEFT", PAD, 0)
	box.text = Kit.Text(box, 10, "LEFT", "secondary")
	box.text:SetWordWrap(false)
	if box.text.SetMaxLines then box.text:SetMaxLines(1) end
	box.natural, box.elapsed = 0, 0
	box:Hide()
	box:SetScript("OnUpdate", OnUpdate)
	-- A reused tooltip starts empty: its old box goes with the old item.
	tooltip:HookScript("OnTooltipCleared", function() box:Hide() end)
	boxes[tooltip] = box
	return box
end

local function QualityColor(quality)
	if C_Item and C_Item.GetItemQualityColor then
		local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
		if ok and type(r) == "number" then return r, g, b end
	end
	local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color then return color.r, color.g, color.b end
end

-- Show `word` on the tooltip's box; the border takes the item quality color.
function H.Show(tooltip, word, quality)
	local box = H.Box(tooltip)
	local path, left, right, top, bottom = E:LocaleFlag("daDK")
	if path then
		box.flag:SetTexture(path)
		box.flag:SetTexCoord(left, right, top, bottom)
		box.flag:Show()
	else
		box.flag:Hide()
	end
	box.text:ClearAllPoints()
	if box.flag:IsShown() then
		box.text:SetPoint("LEFT", box.flag, "RIGHT", FLAG_GAP, 0)
	else
		box.text:SetPoint("LEFT", PAD, 0)
	end
	box.text:SetWidth(0)
	box.text:SetText(word)
	local okWidth, natural = pcall(box.text.GetUnboundedStringWidth or box.text.GetStringWidth, box.text)
	box.natural = okWidth and type(natural) == "number" and natural or 0
	local r, g, b = QualityColor(quality)
	if r then box:SetBackdropBorderColor(r, g, b, 0.75) end
	box.below = nil
	H.Layout(box)
	box.elapsed = REFRESH -- once more on the next frame, when the tooltip has its final size
	box:Show()
	return box
end

-- The tooltip's box, or nil before its first word.
function H.BoxOf(tooltip)
	return boxes[tooltip]
end

function H.Hide(tooltip)
	local box = boxes[tooltip]
	if box then box:Hide() end
end

-- The game's post-call for every item tooltip.
function H.OnItem(tooltip)
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
	H.Hide(tooltip)
	if not H.Enabled() or E.FrameCheck(tooltip, "IsForbidden") or not tooltip.GetItem then return end
	local ok, _, _, id = pcall(tooltip.GetItem, tooltip)
	id = ok and Plain(id)
	if type(id) ~= "number" then return end
	local entry = cache[id]
	if not entry then
		if not (C_Item and C_Item.GetItemInfo) then return end
		local okInfo, name, _, quality = pcall(C_Item.GetItemInfo, id)
		name, quality = okInfo and Plain(name), okInfo and Plain(quality)
		if type(name) ~= "string" then return end -- not loaded yet: the game calls again
		entry = { H.Tag(name, quality, id) or false, tonumber(quality) or 1 }
		cache[id] = entry
	end
	if entry[1] then H.Show(tooltip, entry[1], entry[2]) end
end

-- Forget the words worked out so far.
function H.ClearCache()
	wipe(cache)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
		and Enum.TooltipDataType.Item then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, H.OnItem)
end

---------------------------------------------------------------------------
-- The setting: its own section at the end of the Tooltip page, after the
-- info area rows (which other parts of EldoUI add to as they load). No
-- stored default: a profile without the setting has it off.
---------------------------------------------------------------------------
local function NeedsEnglishClient()
	return not ENGLISH_CLIENT[GetLocale()] and L["Needs the English game client: the words are matched to the English item names."]
end

local function AddOption()
	local module = E.modules and E.modules.Tooltip
	if not (module and type(module.options) == "table") then return end
	for _, row in ipairs(module.options) do
		if row.key == "danishWords" then return end
	end
	local hidden = function() return E:GetLanguage() ~= "daDK" end
	local options = module.options
	options[#options + 1] = { type = "header", label = "Danish word help", hidden = hidden }
	options[#options + 1] = { type = "toggle", key = "danishWords", label = "Danish word on item tooltips", hidden = hidden,
		desc = "A small box on the edge of an item tooltip with the Danish word for what the item is, such as Le on a scythe. The English name stays. Names never get a box.",
		disabled = E.BlizzardNeeds and E:BlizzardNeeds("tooltips", "improve", NeedsEnglishClient) or NeedsEnglishClient }
end
AddOption()
