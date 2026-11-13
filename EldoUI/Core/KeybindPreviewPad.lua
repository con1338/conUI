-- EldoUI keys and spells, the Controller view of the Key sets window
-- (Core/KeybindPreview.lua): your class spells on the game's controller
-- bars, in the same order as the key map (Core/GamepadSpells.lua).
--
--   | [Keyboard] [Controller]                                     |
--   | Controller page 1                                           |
--   |   Top bar      [pad 1-4]   [the game's own]                 |
--   |   Left bar     [pad 1-4]   [face 1-4]                       |
--   |   Right bar    [pad 1-4]   [face 1-4]   (stance bar)        |
--   |   Bottom bar   [pad 1-4]   [face 1-4]                       |
--   | Controller page 2  ...                                      |
--   | Changes before you apply / Kept as they are                 |
--   |-------------------------------------------------------------|
--   | status                        [Take back spells] [Apply]    |
--
-- Each button shows its category tag, as on the keyboard, the spell it
-- gets and the game's glyph for its button (its name in words when the
-- game has no glyph). Opening and switching change nothing: Apply asks
-- once more and places only the spells shown.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local Key = E.Key
local P = E.KeybindPreview
local GAP = 4

function P.ControllerNotice(text, warn)
	E.UIKit.Toast(P.window, text, { point = "BOTTOM", y = 52, warn = warn })
end
local PAGES = 2
local BAR_ORDER = { "top", "left", "right", "bottom" }
local BAR_NAMES = { top = Key("Top bar"), left = Key("Left bar"), right = Key("Right bar"), bottom = Key("Bottom bar") }
-- A bar's two groups of four: the pad's and the face buttons'.
local BUTTON_WORDS = {
	Key("Pad left"), Key("Pad up"), Key("Pad right"), Key("Pad down"),
	Key("Face left"), Key("Face up"), Key("Face right"), Key("Face down"),
}
local GLYPHS = {
	"gamepad-actionbar-squareslot-generic-dpadleft-normal", "gamepad-actionbar-squareslot-generic-dpadup-normal",
	"gamepad-actionbar-squareslot-generic-dpadright-normal", "gamepad-actionbar-squareslot-generic-dpaddown-normal",
	"gamepad-actionbar-circleslot-xbox-x-normal", "gamepad-actionbar-circleslot-xbox-y-normal",
	"gamepad-actionbar-circleslot-xbox-b-normal", "gamepad-actionbar-circleslot-xbox-a-normal",
}
local STATUS_TEXT = {
	place = Key("goes on this empty button when you apply"),
	placed = Key("placed here by an earlier Apply"),
	onbar = Key("already on your controller bars: not moved"),
	kept = Key("not placed: the button holds your own action"),
	noslot = Key("not placed: the game has no controller button here"),
}

local function Kit() return E.UIKit end
local function Data() return E.gamepadBindings end

local function HasAtlas(name)
	local info = C_Texture and C_Texture.GetAtlasInfo
	if type(info) ~= "function" then return false end
	local ok, value = pcall(info, name)
	return ok and value ~= nil
end

---------------------------------------------------------------------------
-- Where a controller slot is, in words
---------------------------------------------------------------------------
local function SpotOf(slot)
	local data = Data()
	if not (data and E.GamepadStorageSlot) then return nil end
	for page = 1, 3 do
		for _, bar in ipairs(BAR_ORDER) do
			for button = 1, 8 do
				if E:GamepadStorageSlot(page, data.bars[bar] + button - 1) == slot then return page, bar, button end
			end
		end
	end
	return nil
end

-- "Controller page 1, right bar, button 3", or nil for a slot of no page.
function P.ControllerSlotWords(slot)
	local page, bar, button = SpotOf(slot)
	if not page then return nil end
	return L["Controller page %d, %s, button %d"]:format(page, L[BAR_NAMES[bar]]:lower(), button)
end

local function EntryWords(entry)
	if entry.stanceBar then
		return L["Controller stance bar of %s, button %d"]:format(entry.formName or "?", entry.button)
	end
	return L["Controller page %d, %s, button %d"]:format(entry.gamepadPage, L[BAR_NAMES[entry.gamepadBar]]:lower(), entry.gamepadButton)
end

local function StatusText(entry)
	if not entry then return nil end
	local status = entry.status
	if status == "otherform" then return L["waits: switch to %s and press Apply again"]:format(entry.formName or "?") end
	if status == "noform" then return L["waits: learn %s first"]:format(entry.formName or "?") end
	local text = STATUS_TEXT[status]
	if text then return E:Translate(text) end
	return P.IntendedText(entry)
end

---------------------------------------------------------------------------
-- The window part
---------------------------------------------------------------------------
local function BuildTile(win, parent, page, bar, button)
	local K = Kit()
	local tile = CreateFrame("Button", nil, parent)
	tile.page, tile.bar, tile.button = page, bar, button
	tile.slot = K.Icon(tile, 20)
	tile.slot:SetPoint("TOP", 0, -2)
	tile.glyph = tile:CreateTexture(nil, "OVERLAY")
	tile.glyph:SetPoint("TOPLEFT", 1, -1)
	tile.chord = K.Text(tile, E.tokens.size.small, "CENTER", "body")
	tile.chord:SetWordWrap(false)
	tile.short = K.Text(tile, E.tokens.size.small, "CENTER", "secondary")
	tile.short:SetWordWrap(false)
	tile.mark = K.Text(tile, E.tokens.size.small, "RIGHT", "header")
	tile.mark:SetPoint("TOPRIGHT", -2, -2)
	tile:SetScript("OnEnter", function(self)
		local entry = self.entry
		K.AnchorTooltip(self, GameTooltip)
		if self.reserved then
			K.TipTitle(GameTooltip, L["The game's own buttons"])
			K.TipText(GameTooltip, L["The game keeps these four buttons for its own actions."])
		elseif entry then
			K.TipTitle(GameTooltip, entry.info and E:Translate(entry.info.label) or L["Your choice."])
			K.TipPair(GameTooltip, L["Button"], E:Translate(BUTTON_WORDS[self.button]))
			K.TipPair(GameTooltip, L["Spell"], entry.name or P.IntendedText(entry))
			K.TipPair(GameTooltip, L["Apply"], StatusText(entry) or "")
			for _, other in ipairs(self.pages or {}) do
				K.TipPair(GameTooltip, other.formName or "?", ("%s: %s"):format(other.name or "?", StatusText(other) or ""))
			end
		else
			K.TipTitle(GameTooltip, L["Free"])
			K.TipText(GameTooltip, L["No class spell goes here: the button is yours to fill."])
		end
		GameTooltip:Show()
	end)
	tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return tile
end

function P.BuildController(win, c)
	local K = Kit()
	win.pad = { labels = {}, rows = {}, tiles = {}, lines = {}, kept = {} }
	for page = 1, PAGES do
		win.pad.labels[page] = K.SectionLabel(c, L["Controller page %d"]:format(page))
		win.pad.rows[page], win.pad.tiles[page] = {}, {}
		for _, bar in ipairs(BAR_ORDER) do
			win.pad.rows[page][bar] = K.Text(c, E.tokens.size.small, "LEFT", "secondary")
			win.pad.tiles[page][bar] = {}
			for button = 1, 8 do win.pad.tiles[page][bar][button] = BuildTile(win, c, page, bar, button) end
		end
	end
	win.pad.changesLabel = K.SectionLabel(c, L["Changes before you apply"])
	win.pad.keptLabel = K.SectionLabel(c, L["Kept as they are"])
end

function P.ShowControllerView(win, on)
	local pad = win.pad
	if not pad then return end
	for page = 1, PAGES do
		pad.labels[page]:SetShown(on)
		for _, bar in ipairs(BAR_ORDER) do
			pad.rows[page][bar]:SetShown(on)
			for _, tile in ipairs(pad.tiles[page][bar]) do tile:SetShown(on) end
		end
	end
	pad.changesLabel:SetShown(on)
	pad.keptLabel:SetShown(on)
	if not on then
		for _, list in ipairs({ pad.lines, pad.kept }) do
			for _, fs in ipairs(list) do fs:Hide() end
		end
	end
end

local function Lines(win, list, texts)
	for index, text in ipairs(texts) do
		local fs = list[index]
		if not fs then
			fs = Kit().Text(win.body, E.tokens.size.body, "LEFT", "body")
			list[index] = fs
		end
		fs:SetText("- " .. text)
		fs:Show()
	end
	for index = #texts + 1, #list do list[index]:Hide() end
end

local function Names(entries)
	local names = {}
	for _, entry in ipairs(entries) do names[#names + 1] = entry.name or tostring(entry.spell) end
	return table.concat(names, ", ")
end

function P.RefreshController(win)
	local K = Kit()
	local pad = win.pad
	local plan = E:GamepadSpellPlan()
	P.gamepadPlan = plan
	local data = Data()
	win:SetTitle(L["Key sets"], L["Controller"])
	win.summary:SetText(L["Your class spells on the game's controller bars, in the order of your key set: the fight's spells on page 1 and the spells between pulls on page 2. Each button shows its category, as on the keyboard. Nothing changes until you press Apply."])
	-- Each controller button's entry, and the stance pages under it.
	local spots = {}
	for _, entry in ipairs(plan.entries) do
		if entry.gamepadPage then spots[("%d:%s:%d"):format(entry.gamepadPage, entry.gamepadBar, entry.gamepadButton)] = entry end
	end
	local others = {}
	for _, entry in ipairs(plan.pageEntries) do
		local main = spots[("%d:%s:%d"):format(entry.gamepadPage or 0, entry.gamepadBar or "", entry.gamepadButton or 0)]
		if main then
			others[main] = others[main] or {}
			table.insert(others[main], entry)
		end
	end
	local stance = plan.stanceBar
	for page = 1, PAGES do
		for _, bar in ipairs(BAR_ORDER) do
			local text = L[BAR_NAMES[bar]]
			if bar == "top" then text = text .. "  " .. L["(the right group is the game's own)"] end
			if stance and stance.page == page and stance.bar == bar then
				text = text .. "  " .. L["(the stance bar takes its place in a stance or form)"]
			end
			pad.rows[page][bar]:SetText(text)
			for button, tile in ipairs(pad.tiles[page][bar]) do
				local entry = spots[("%d:%s:%d"):format(page, bar, button)]
				tile.entry, tile.pages = entry, entry and others[entry]
				tile.reserved = bar == "top" and button > 4
				local slot = entry and entry.slot or (not tile.reserved and E:GamepadStorageSlot(page, data.bars[bar] + button - 1))
				local held, heldIcon
				if slot then held, heldIcon = P.SlotAction(slot) end
				local icon = entry and (entry.status == "kept" and heldIcon or entry.icon) or heldIcon
				tile.slot:SetIcon(icon)
				tile.slot.icon:SetDesaturated(entry ~= nil and (entry.state == "unlearned" or entry.status == "otherform" or entry.status == "noform"))
				tile.chord:SetText(E:Translate(BUTTON_WORDS[button]))
				if HasAtlas(GLYPHS[button]) then
					tile.glyph:SetAtlas(GLYPHS[button])
					tile.glyph:Show()
				else
					tile.glyph:Hide()
				end
				local info = entry and entry.info
				tile.short:SetText(tile.reserved and L["Game"] or info and E:Translate(info.short) or "")
				tile.mark:SetText(entry and entry.status == "place" and "+" or "")
				tile:SetAlpha(tile.reserved and E.tokens.disabledAlpha or 1)
				tile.held = held
			end
		end
	end
	-- Changes and what stays.
	local changes, kept, waiting, learn = {}, {}, {}, {}
	if plan.unavailable then changes[#changes + 1] = L["The game's controller bars aren't available right now."] end
	if #plan.places > 0 then changes[#changes + 1] = L["Class spells on empty controller buttons: %s."]:format(Names(plan.places)) end
	for _, list in ipairs({ plan.entries, plan.pageEntries }) do
		for _, entry in ipairs(list) do
			if entry.status == "otherform" then
				waiting[entry.formName or "?"] = waiting[entry.formName or "?"] or {}
				table.insert(waiting[entry.formName or "?"], entry)
			elseif entry.status == "noform" then
				learn[entry.formName or "?"] = learn[entry.formName or "?"] or {}
				table.insert(learn[entry.formName or "?"], entry)
			elseif entry.status == "kept" then
				kept[#kept + 1] = ("%s: %s"):format(EntryWords(entry), E:Translate(STATUS_TEXT.kept))
			end
		end
	end
	local forms = {}
	for form in pairs(waiting) do forms[#forms + 1] = form end
	table.sort(forms)
	for _, form in ipairs(forms) do
		changes[#changes + 1] = L["%s: switch to it and press Apply again for %s."]:format(form, Names(waiting[form]))
	end
	forms = {}
	for form in pairs(learn) do forms[#forms + 1] = form end
	table.sort(forms)
	for _, form in ipairs(forms) do
		changes[#changes + 1] = L["%s: learn it first for %s."]:format(form, Names(learn[form]))
	end
	if #changes == 0 then changes[1] = L["Nothing changes: every class spell is on your controller bars already."] end
	if #kept == 0 then kept[1] = L["Nothing: every button in the plan is free to change."] end
	Lines(win, pad.lines, changes)
	Lines(win, pad.kept, kept)
	-- Footer.
	local count = #plan.places
	local blocked, why
	if count > 0 or plan.unavailable then blocked, why = E:GamepadSpellsBlocked(plan) end
	local status = E:Plural(count, "%d spell placed", "%d spells placed"):format(count)
	if blocked then status = why end
	win.footerText:SetText(status)
	win.apply:SetEnabled(not blocked and count > 0)
	win.takeBack:SetShown(E:HasGamepadSpells())
	K.Paint(win.footerText, blocked and "warn" or "secondary")
end

function P.LayoutController(win, c, width, y, labelH)
	local pad = win.pad
	local scale = E:TextScale()
	local small = E.tokens.size.small
	-- Eight buttons and a wider gap between the two groups, as wide as
	-- the keyboard view's buttons.
	local tileW = math.floor((width - 11 * GAP) / 12)
	local icon = math.floor(math.min(28 * scale, tileW - 8))
	local tileH = icon + math.ceil(small * scale) * 2 + 10
	local groupGap = math.floor(tileW / 2)
	local function Place(region, h)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
		y = y - (h or 0)
	end
	local function Wrap(fs, w)
		fs:SetWordWrap(true)
		fs:SetWidth(math.max(w, 10))
		return math.ceil(fs:GetStringHeight() or 0)
	end
	for page = 1, PAGES do
		Place(pad.labels[page], labelH)
		for _, bar in ipairs(BAR_ORDER) do
			Place(pad.rows[page][bar], Wrap(pad.rows[page][bar], width) + 4)
			for button, tile in ipairs(pad.tiles[page][bar]) do
				local x = (button - 1) * (tileW + GAP) + (button > 4 and groupGap or 0)
				tile:SetSize(tileW, tileH)
				tile:ClearAllPoints()
				tile:SetPoint("TOPLEFT", c, "TOPLEFT", x, y)
				tile.slot:SetSize(icon, icon)
				tile.glyph:SetSize(math.floor(icon / 2), math.floor(icon / 2))
				tile.chord:ClearAllPoints()
				tile.chord:SetPoint("TOP", tile.slot, "BOTTOM", 0, -2)
				tile.chord:SetWidth(tileW)
				tile.short:ClearAllPoints()
				tile.short:SetPoint("TOP", tile.chord, "BOTTOM", 0, -1)
				tile.short:SetWidth(tileW)
				for _, fs in ipairs({ tile.chord, tile.short }) do
					E:SetWindowFont(fs, small)
					local w = fs:GetStringWidth() or 0
					if w > tileW then E:SetWindowFont(fs, math.max(1, math.floor(small * tileW / w))) end
				end
			end
			y = y - tileH - GAP
		end
		y = y - 6
	end
	Place(pad.changesLabel, labelH)
	for _, fs in ipairs(pad.lines) do
		if fs:IsShown() then Place(fs, Wrap(fs, width) + 4) end
	end
	y = y - 6
	Place(pad.keptLabel, labelH)
	for _, fs in ipairs(pad.kept) do
		if fs:IsShown() then Place(fs, Wrap(fs, width) + 4) end
	end
	return y
end

-- The last question before the controller spells go on their buttons.
function P.ConfirmController()
	local plan = P.gamepadPlan
	if not (plan and #plan.places > 0) then return end
	local text = L["Put %s on empty controller buttons?\n\nOnly empty buttons get a spell and your own actions stay. Take back spells removes them again."]:format(
		E:Plural(#plan.places, "%d class spell", "%d class spells"):format(#plan.places))
	E:ShowConfirm({ title = L["Controller"], text = text, accept = L["Apply"], data = plan,
		onAccept = function(data)
			E:RunOutOfCombat(function()
				E:ApplyGamepadSpells(data, P.ControllerNotice)
				if P.Refresh then P.Refresh() end
			end, "KeybindPreview:padapply")
		end })
end
