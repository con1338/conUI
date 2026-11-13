-- Layout and style > Overview: your whole look on one page.
--
--   Your setup      the layout (its family, "Legacy: <title>" with the
--                   nearest family, or one of My layouts), role, skin and
--                   Blizzard windows; Undo puts back the last setup change
--   Layout          the layout picker (also on the Layouts page and in
--                   move mode): a pick asks first and applies at once
--   Complete look   "Keep my look" and one card per preset pack
--                   (Structured, Focus and Portrait Forge are the complete
--                   looks; Data/Packs.lua)
--   Parts > Layout  keep the layout you use, or take the one the look was
--                   made for (an explicit pick, never a side effect)
--   UI amount       keep, or Essential, Moderate or Full (Core/UIAmount.lua)
--   Blizzard windows keep, Original or Match skin
--   Summary         what Apply changes, one line per part
--
-- Every pick of a look or a part is a draft: nothing changes before
-- "Apply complete look", which runs the same path as a pack from the Share menu
-- (E:ApplyPackLook) with the layout, UI amount and windows picked here.
-- Each part on "Keep" is left exactly as it is.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local OV = {}
E.Overview = OV -- exposed for inspection

OV.KEEP = "keep"
OV.CARD = { width = 150, gap = 8, sample = 36, pad = 6 }
OV.WINDOWS = { order = { "keep", "original", "match" } }

local function NewDraft()
	return { pack = OV.KEEP, layout = OV.KEEP, amount = OV.KEEP, windows = OV.KEEP }
end
OV.draft = NewDraft()

function OV.Reset() OV.draft = NewDraft() end

local function General() return E.db.general end

local function LayoutTitle(key)
	return E:LayoutTitle(key)
end
OV.LayoutTitle = LayoutTitle

local function SkinTitle(id)
	local info = E.artStyleInfo[id]
	return info and L[info.title] or tostring(id)
end

function OV.Pack()
	local key = OV.draft.pack
	return key ~= OV.KEEP and E.packs[key] or nil
end

-- The skin a pack draws on its own layout.
local function PackSkin(pack)
	return pack.artStyle and (E:PackArtStyle(pack)) or E:LayoutSkin(E:PackLayout(pack))
end

-- The pack the profile matches now (layout, skin and UI amount), or nil.
function OV.CurrentPack()
	local general = General()
	for _, key in ipairs(E.packOrder) do
		local pack = E.packs[key]
		local sameSkin = pack.artStyle and not general.skinFollow and general.artStyle == E:PackArtStyle(pack)
			or (not pack.artStyle and general.skinFollow)
		if general.layout == E:PackLayout(pack) and sameSkin
			and (not pack.uiAmount or E:UIAmountMatch() == pack.uiAmount) then
			return key
		end
	end
	return nil
end

-- A card picks a look: the UI amount and windows it brings come with it,
-- the layout stays until picked below.
function OV.PickCard(key)
	local draft = OV.draft
	draft.pack = key
	local pack = OV.Pack()
	draft.layout = OV.KEEP
	draft.amount = pack and pack.uiAmount or OV.KEEP
	local windows = pack and pack.blizzardWindows
	draft.windows = (windows == "original" or windows == "match") and windows or OV.KEEP
end

-- The layout Apply would use.
function OV.TargetLayout()
	local pack = OV.Pack()
	if pack and OV.draft.layout == "pack" then return E:PackLayout(pack) end
	return General().layout
end

---------------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------------
function OV.SummaryLines()
	local draft, pack, lines = OV.draft, OV.Pack(), {}
	local UA = E.UIAmount
	if pack then
		lines[#lines + 1] = L["Look: %s, with the %s skin and its styles."]:format(L[pack.title], SkinTitle(PackSkin(pack)))
	else
		lines[#lines + 1] = L["Look: your skin and styles stay as they are."]
	end
	local current = General().layout
	if OV.TargetLayout() ~= current then
		lines[#lines + 1] = L["Layout: %s. Frames you dragged stay where you put them."]:format(LayoutTitle(OV.TargetLayout()))
	elseif pack and E:PackLayout(pack) ~= current then
		lines[#lines + 1] = L["Layout: stays %s. %s was made for %s; pick it under Layout."]:format(LayoutTitle(current), L[pack.title], LayoutTitle(E:PackLayout(pack)))
	else
		lines[#lines + 1] = L["Layout: stays %s."]:format(LayoutTitle(current))
	end
	if UA and UA.LEVELS[draft.amount] then
		local count = #E:UIAmountPlan(draft.amount)
		if count == 0 then
			lines[#lines + 1] = L["UI amount: %s, your modules already match it."]:format(UA.Title(draft.amount))
		else
			lines[#lines + 1] = L["UI amount: %s, %s."]:format(UA.Title(draft.amount),
				E:Plural(count, "switches %d module", "switches %d modules"):format(count))
		end
	else
		lines[#lines + 1] = L["UI amount: stays as set."]
	end
	if draft.windows == "original" then
		lines[#lines + 1] = L["Blizzard windows: Original. Taking a skin off needs a reload."]
	elseif draft.windows == "match" then
		lines[#lines + 1] = L["Blizzard windows: Match skin, for the windows you let EldoUI change."]
	else
		lines[#lines + 1] = L["Blizzard windows: stay as set."]
	end
	return lines
end

-- True when Apply would change something.
function OV.HasChanges()
	local draft = OV.draft
	if OV.Pack() then return true end
	if E.UIAmount.LEVELS[draft.amount] and #E:UIAmountPlan(draft.amount) > 0 then return true end
	if draft.windows ~= OV.KEEP and E.BlizzardWindowsMode and E:BlizzardWindowsMode() ~= draft.windows then return true end
	return false
end

function OV.Apply()
	local draft, pack = OV.draft, OV.Pack()
	local amount = E.UIAmount.LEVELS[draft.amount] and draft.amount or nil
	local windows = draft.windows ~= OV.KEEP and draft.windows or nil
	if pack then
		local copy = CopyTable(pack)
		copy.layout = OV.TargetLayout()
		copy.uiAmount, copy.blizzardWindows = amount, windows
		E:ApplyPackLook(copy)
	else
		if amount then E:ApplyUIAmount(amount) end
		if windows and E.SetBlizzardWindows then
			local _, needed = E:SetBlizzardWindows(windows, true)
			if needed and E.ConfigNeedsReload then E:ConfigNeedsReload("blizzardWindows", L["Blizzard windows"]) end
		end
	end
	OV.Reset()
	if E.RefreshConfig then E:RefreshConfig() end
end

---------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------
function OV.CardIds()
	local ids = { OV.KEEP }
	for _, key in ipairs(E.packOrder) do ids[#ids + 1] = key end
	return ids
end

local function MakeCard(canvas, id)
	local spec = OV.CARD
	local card = E.WindowKit.Choice(canvas, spec.width, 96, "", "", function(self)
		OV.PickCard(self.id)
		if E.RefreshConfig then E:RefreshConfig() end
	end)
	card.id = id
	card.sample = CreateFrame("Frame", nil, card)
	card.sample:SetPoint("TOPLEFT", spec.pad, -spec.pad)
	card.sample:SetPoint("TOPRIGHT", -spec.pad, -spec.pad)
	card.sample:SetHeight(spec.sample)
	card.sample:EnableMouse(false)
	card.title:ClearAllPoints()
	card.title:SetPoint("TOPLEFT", card.sample, "BOTTOMLEFT", 4, -6)
	card.title:SetPoint("TOPRIGHT", card.sample, "BOTTOMRIGHT", -18, -6)
	card.facts = E.WindowKit.Secondary(E:CreateText(card, E.tokens.size.small, "LEFT"))
	card.facts:SetPoint("TOPLEFT", card.desc, "BOTTOMLEFT", 0, -4)
	card.facts:SetWordWrap(true)
	card.check = card:CreateTexture(nil, "OVERLAY")
	card.check:SetSize(12, 12)
	card.check:SetPoint("TOPRIGHT", card.sample, "BOTTOMRIGHT", 0, -8)
	E.UIKit.SetGlyph(card.check, "check")
	return card
end

function OV.UpdateCards(canvas)
	if not canvas then return end
	local ids = OV.CardIds()
	canvas.cards, canvas.pool = canvas.cards or {}, canvas.pool or {}
	for _, card in ipairs(canvas.cards) do card:Hide() end
	wipe(canvas.cards)
	for index, id in ipairs(ids) do
		local card = canvas.pool[id] or MakeCard(canvas, id)
		canvas.pool[id] = card
		card:Show()
		canvas.cards[index] = card
	end
	local current = OV.CurrentPack()
	local UA = E.UIAmount
	for _, card in ipairs(canvas.cards) do
		local pack = E.packs[card.id]
		if pack then
			card.title:SetText(L[pack.title])
			card.desc:SetText(L[pack.desc or ""])
			card.facts:SetText(L["%s, %s, %s"]:format(LayoutTitle(E:PackLayout(pack)), SkinTitle(PackSkin(pack)),
				pack.uiAmount and UA.Title(pack.uiAmount) or L["UI amount as set"]))
			E:PaintSkinSample(card.sample, PackSkin(pack))
		else
			card.title:SetText(L["Keep my look"])
			card.desc:SetText(L["Your layout, skin and styles stay as they are."])
			card.facts:SetText(L["%s, %s"]:format(LayoutTitle(General().layout), SkinTitle(E:ArtStyle())))
			E:PaintSkinSample(card.sample, E:ArtStyle())
		end
		card:SetSelected(card.id == OV.draft.pack)
		card.check:SetShown(card.id == current)
		card.check:SetVertexColor(E:TokenColor("accent"))
	end
end

function OV.LayoutCards(canvas, width)
	local cards = canvas and canvas.cards
	if not cards or #cards == 0 then return 1 end
	local spec = OV.CARD
	local scale = E.TextScale and E:TextScale() or 1
	local least = math.floor(spec.width * math.sqrt(math.max(1, scale)))
	local columns = math.max(1, math.min(#cards, math.floor((width + spec.gap) / (least + spec.gap))))
	local cardWidth = math.floor((width - (columns - 1) * spec.gap) / columns)
	local height = 0
	for _, card in ipairs(cards) do
		card:SetWidth(cardWidth)
		local inner = math.max(cardWidth - 2 * spec.pad - 8, 1)
		card.title:SetWidth(math.max(inner - 14, 1))
		card.desc:SetWidth(inner)
		card.facts:SetWidth(inner)
		local need = spec.pad + spec.sample + 6 + math.ceil(card.title:GetStringHeight() or 0) + 4
			+ math.ceil(card.desc:GetStringHeight() or 0) + 4 + math.ceil(card.facts:GetStringHeight() or 0) + 8
		height = math.max(height, need)
	end
	for index, card in ipairs(cards) do
		card.minHeight = height
		card:SetHeight(height)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", canvas, "TOPLEFT", ((index - 1) % columns) * (cardWidth + spec.gap),
			-math.floor((index - 1) / columns) * (height + spec.gap))
	end
	local rows = math.ceil(#cards / columns)
	return rows * height + (rows - 1) * spec.gap
end

function OV.UpdateSummary(canvas, width)
	if not canvas then return 1 end
	canvas.lines = canvas.lines or {}
	width = width or canvas.width or 400
	canvas.width = width
	local texts = OV.SummaryLines()
	local y = 0
	for index = 1, math.max(#texts, #canvas.lines) do
		local line = canvas.lines[index]
		if texts[index] and not line then
			line = E:CreateText(canvas, E.tokens.size.body, "LEFT")
			line:SetWordWrap(true)
			canvas.lines[index] = line
		end
		if line then
			line:SetShown(texts[index] ~= nil)
			if texts[index] then
				line:SetText(texts[index])
				line:SetWidth(math.max(width, 1))
				line:ClearAllPoints()
				line:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -y)
				y = y + math.ceil(line:GetStringHeight() or 14) + 4
			end
		end
	end
	return math.max(1, y - 4)
end

---------------------------------------------------------------------------
-- The layout picker: one list for the Layouts page, this page and move
-- mode. The layout families first, then the legacy layouts a profile of
-- this account still uses, then My layouts (imported layouts and the
-- copies EldoUI saved of your dragged frames). A pick asks first, with
-- what it changes, and a profile that keeps its own look is asked once
-- whether it wants the layout's look (Keep is the default).
---------------------------------------------------------------------------
OV.PICKER = { width = 210, least = 56, gap = 8, heading = 18 }

function E:LayoutPickerGroups()
	local groups = {
		{ key = "families", title = L["Layouts"], entries = {} },
		{ key = "legacy", title = L["Legacy in use"], entries = {} },
		{ key = "mine", title = L["My layouts"], entries = {} },
	}
	local seen = {}
	local function Add(group, key, desc)
		local layout = rawget(self.layouts, key) or self.legacyLayouts[key]
		if seen[key] or type(layout) ~= "table" then return end
		seen[key] = true
		group.entries[#group.entries + 1] = { key = key, title = self:LayoutTitle(key), desc = desc or (layout.desc and L[layout.desc]) or "" }
	end
	for _, slot in ipairs(self.layoutFamilies) do
		local key = self:FamilyLayoutKey(slot.key)
		if key then Add(groups[1], key) end
	end
	local used = self:LegacyLayoutsInUse()
	for _, key in ipairs(self.legacyLayoutOrder) do
		if used[key] then
			local family = self:LayoutFamily(key)
			Add(groups[2], key, family and L["Kept as it was. Nearest family: %s."]:format(self:LayoutFamilyTitle(family))
				or L["Kept as it was."])
		end
	end
	for _, key in ipairs(self:AllLayoutKeys()) do
		local layout = rawget(self.layouts, key)
		if type(layout) == "table" then
			if layout.imported then
				Add(groups[3], key, layout.desc or L["Imported layout."])
			else
				Add(groups[1], key)
			end
		end
	end
	return groups
end

-- A pick from any of the three places asks first, then goes through the
-- same setup change as every other way to change the layout.
function E:PickLayout(key, origin)
	return self:ConfirmApplyLayout(key, { source = origin or "layouts" })
end

-- The picker as a menu, for move mode's panel.
function E:ShowLayoutPicker(owner)
	local Kit = self.UIKit
	if not (Kit and Kit.ContextMenu) then return end
	local current = self.db.general.layout
	return Kit.ContextMenu(owner, function(_, root)
		local first = true
		for _, group in ipairs(E:LayoutPickerGroups()) do
			if #group.entries > 0 then
				if not first then root:CreateDivider() end
				first = false
				root:CreateTitle(group.title)
				for _, entry in ipairs(group.entries) do
					local radio = root:CreateRadio(entry.title, function() return entry.key == current end,
						function() E:PickLayout(entry.key, "movemode") end)
					if entry.desc ~= "" then
						radio:SetTooltip(function(tooltip)
							Kit.TipTitle(tooltip, entry.title)
							Kit.TipText(tooltip, entry.desc)
						end)
					end
				end
			end
		end
	end, { at = "owner" })
end

local function MakePickerCard(canvas)
	return E.WindowKit.Choice(canvas, OV.PICKER.width, OV.PICKER.least, "", "", function(self)
		E:PickLayout(self.id, canvas.origin)
	end)
end

function OV.UpdatePicker(canvas, origin)
	if not canvas then return end
	canvas.origin = canvas.origin or origin
	canvas.cards, canvas.headings, canvas.pool = canvas.cards or {}, canvas.headings or {}, canvas.pool or {}
	for _, card in ipairs(canvas.cards) do card:Hide() end
	for _, heading in ipairs(canvas.headings) do heading:Hide() end
	wipe(canvas.cards)
	canvas.groups = {}
	local current = General().layout
	for _, group in ipairs(E:LayoutPickerGroups()) do
		if #group.entries > 0 then
			local index = #canvas.groups + 1
			local heading = canvas.headings[index]
			if not heading then
				heading = E.WindowKit.Secondary(E:CreateText(canvas, E.tokens.size.small, "LEFT"))
				heading:SetWordWrap(true)
				canvas.headings[index] = heading
			end
			heading:SetText(group.title)
			heading:Show()
			local list = { key = group.key, title = group.title, heading = heading, cards = {} }
			for _, entry in ipairs(group.entries) do
				local card = canvas.pool[entry.key] or MakePickerCard(canvas)
				canvas.pool[entry.key] = card
				card.id = entry.key
				card.title:SetText(entry.title)
				card.desc:SetText(entry.desc)
				card:SetSelected(entry.key == current)
				card:Show()
				canvas.cards[#canvas.cards + 1] = card
				list.cards[#list.cards + 1] = card
			end
			canvas.groups[index] = list
		end
	end
end

-- Lays the groups out for the page width; returns the height.
function OV.LayoutPicker(canvas, width)
	if not (canvas and canvas.groups) then return 1 end
	local spec = OV.PICKER
	local scale = E.TextScale and E:TextScale() or 1
	local least = math.floor(spec.width * math.sqrt(math.max(1, scale)))
	local columns = math.max(1, math.floor((width + spec.gap) / (least + spec.gap)))
	local cardWidth = math.floor((width - (columns - 1) * spec.gap) / columns)
	local y = 0
	for index, group in ipairs(canvas.groups) do
		if index > 1 then y = y + 2 * spec.gap end
		group.heading:SetWidth(math.max(width, 1))
		group.heading:ClearAllPoints()
		group.heading:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -y)
		y = y + math.max(spec.heading, math.ceil(group.heading:GetStringHeight() or 0) + 6)
		local rowTop, rowHeight = y, 0
		for position, card in ipairs(group.cards) do
			local column = (position - 1) % columns
			if column == 0 and position > 1 then
				rowTop = rowTop + rowHeight + spec.gap
				rowHeight = 0
			end
			card.minHeight = spec.least
			card:SetWidth(cardWidth)
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", canvas, "TOPLEFT", column * (cardWidth + spec.gap), -rowTop)
			rowHeight = math.max(rowHeight, card:FitHeight())
		end
		-- One height per row, so the cards of a row line up.
		local first = 1
		while first <= #group.cards do
			local last = math.min(first + columns - 1, #group.cards)
			local tallest = 0
			for at = first, last do tallest = math.max(tallest, group.cards[at]:GetHeight() or 0) end
			for at = first, last do
				group.cards[at].minHeight = tallest
				group.cards[at]:SetHeight(tallest)
			end
			first = last + 1
		end
		y = rowTop + rowHeight
	end
	return math.max(1, y)
end

-- The picker as a page row (the Layouts page and this page).
function OV.PickerOption(origin)
	return { type = "preview", label = "Layouts", noCaption = true, keywords = "layout preset family legacy imported",
		create = function(canvas) OV.UpdatePicker(canvas, origin) end,
		height = function(canvas, width)
			if not canvas then return 240 end
			OV.UpdatePicker(canvas, origin)
			return OV.LayoutPicker(canvas, width)
		end,
		update = function(canvas) OV.UpdatePicker(canvas, origin) end }
end

---------------------------------------------------------------------------
-- Your setup: the identity strip
---------------------------------------------------------------------------
function OV.IdentityLines()
	local id = E:SetupIdentity()
	return {
		L["Layout: %s"]:format(id.text),
		table.concat({ L["Role: %s"]:format(id.role), L["Skin: %s"]:format(id.skin),
			L["Blizzard windows: %s"]:format(id.windows) }, "  ·  "),
	}
end

function OV.UpdateIdentity(canvas, width)
	if not canvas then return 1 end
	canvas.lines = canvas.lines or {}
	width = width or canvas.width or 400
	canvas.width = width
	local y = 0
	for index, text in ipairs(OV.IdentityLines()) do
		local line = canvas.lines[index]
		if not line then
			line = E:CreateText(canvas, E.tokens.size.body, "LEFT")
			line:SetWordWrap(true)
			canvas.lines[index] = line
		end
		line:SetText(text)
		line:SetWidth(math.max(width, 1))
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -y)
		y = y + math.ceil(line:GetStringHeight() or 14) + 4
	end
	return math.max(1, y - 4)
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function AmountValues()
	local UA = E.UIAmount
	local values = { keep = L["Keep as set"] }
	for _, level in ipairs(E.uiAmountLevels.order) do values[level] = UA.Title(level) end
	return values
end

local function WindowsValues()
	local titles = E.Appearance and E.Appearance.WINDOWS.titles or {}
	return { keep = L[titles.keep or "Keep as set"], original = L[titles.original or "Original"], match = L[titles.match or "Match skin"] }
end

function OV.Options()
	return {
		{ type = "header", label = "Your setup" },
		{ type = "preview", label = "Your setup", noCaption = true, keywords = "identity family role skin windows legacy",
			create = function(canvas) OV.UpdateIdentity(canvas) end,
			height = function(canvas, width) return OV.UpdateIdentity(canvas, width) end,
			update = function(canvas) OV.UpdateIdentity(canvas) end },
		{ type = "execute", label = "Undo last setup change", noUndo = true,
			desc = "Puts back the setup from before the last layout, look, role or UI amount change on this profile. Settings you changed since stay yours.",
			disabled = function() return not (E.SetupUndoRecord and E:SetupUndoRecord()) and L["Nothing to undo on this profile."] or false end,
			func = function() E:UndoSetup() end },
		{ type = "header", label = "Layout", status = function() return L["Now: %s"]:format(LayoutTitle(General().layout)) end },
		OV.PickerOption("overview"),
		{ type = "header", label = "Complete look",
			status = function()
				local key = OV.CurrentPack()
				return key and L["Now: %s"]:format(L[E.packs[key].title]) or L["Your own mix"]
			end },
		{ type = "preview", label = "Complete look", noCaption = true, keywords = "pack look structured focus portrait forge preset",
			create = function(canvas) OV.UpdateCards(canvas) end,
			height = function(canvas, width)
				if not canvas then return 160 end
				OV.UpdateCards(canvas)
				return OV.LayoutCards(canvas, width)
			end,
			update = function(canvas) OV.UpdateCards(canvas) end },
		{ type = "header", label = "Parts" },
		{ type = "select", key = "layout", label = "Layout", wide = true, keywords = "layout preset",
			desc = "Keep the layout you use, or take the one the picked look was made for. Frames you dragged stay where you put them.",
			values = function()
				local pack = OV.Pack()
				return { keep = L["Keep %s"]:format(LayoutTitle(General().layout)),
					pack = L["Use %s"]:format(LayoutTitle(pack and E:PackLayout(pack) or General().layout)) }
			end,
			order = { "keep", "pack" },
			disabled = function()
				local pack = OV.Pack()
				if not pack then return L["Pick a look above first."] end
				if E:PackLayout(pack) == General().layout then return L["This look uses your layout."] end
				return false
			end },
		{ type = "select", key = "amount", label = "UI amount", wide = true, keywords = "essential moderate full",
			desc = "How much EldoUI shows. Keep as set leaves every module as it is.",
			values = AmountValues, order = { "keep", "essential", "moderate", "full" },
			valueDescs = function()
				local descs = { keep = L["Every module stays as it is."] }
				for _, level in ipairs(E.uiAmountLevels.order) do descs[level] = L[E.uiAmountLevels[level].desc] end
				return descs
			end },
		{ type = "select", key = "windows", label = "Blizzard windows", wide = true, keywords = "blizzard windows original skin",
			desc = "How Blizzard's own windows look. Only windows you let EldoUI change are touched.",
			values = WindowsValues, order = OV.WINDOWS.order,
			disabled = function() return not E.SetBlizzardWindows and L["Not available in this version."] or false end },
		{ type = "header", label = "Summary" },
		{ type = "preview", label = "Summary", noCaption = true,
			create = function(canvas) OV.UpdateSummary(canvas) end,
			height = function(canvas, width) return OV.UpdateSummary(canvas, width) end,
			update = function(canvas) OV.UpdateSummary(canvas) end },
		{ type = "execute", label = "Apply complete look", noUndo = true,
			desc = "Applies the summary above. Parts on Keep stay exactly as they are.",
			disabled = function() return not OV.HasChanges() and L["Nothing to change."] or false end,
			func = OV.Apply },
		{ type = "execute", label = "Start over", noUndo = true,
			desc = "Every pick on this page goes back to Keep.",
			disabled = function()
				local d = OV.draft
				return d.pack == OV.KEEP and d.amount == OV.KEEP and d.windows == OV.KEEP and L["Nothing picked yet."] or false
			end,
			func = function()
				OV.Reset()
				if E.RefreshConfig then E:RefreshConfig() end
			end },
	}
end

-- Shown translated: L["Overview"], L["Your setup"], L["Undo last setup change"],
-- L["Layouts"], L["Complete look"], L["Parts"], L["Layout"],
-- L["UI amount"], L["Blizzard windows"], L["Summary"], L["Apply complete look"],
-- L["Start over"], L["Structured"], L["Focus"], L["Portrait Forge"] and
-- the pack texts in Data/Packs.lua.

E:RegisterEvent("PLAYER_LOGIN", function()
	if not E.RegisterConfigPage then return end
	E:RegisterConfigPage("overview", "Overview", OV.Options(), function() return OV.draft end, function() end, 2.3)
end, OV, "pages")
