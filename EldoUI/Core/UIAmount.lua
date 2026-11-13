-- UI amount: Essential, Moderate or Full (levels and module list in
-- Data/UIAmounts.lua), and its page under Layout and style.
--
--   E:UIAmountPlan(level)      what a level would change, without changing
--                              anything: { { module, title, from, to } },
--                              then the modules it leaves alone and why
--   E:UIAmountMatch()          the level the modules match now, or nil
--   E:UIAmountRecommended(key) the level a layout was made for
--   E:ApplyUIAmount(level)     switch the listed modules to that level
--   E:UndoUIAmount()           switch back what UI amount changed, except
--                              the modules you switched yourself since
--
-- general.uiAmount is the last level applied ("keep": none, the start of
-- every profile, so an existing setup stays as it is until you pick).
-- general.uiAmountRestore[module] = { from, to } is what an apply wrote:
-- undo puts back `from` only while the module is still `to`. A module you
-- switch yourself afterwards is yours and leaves the record.
-- A module another addon stands in for is left alone. Modules switch on
-- and off through the module switch, which waits for the end of combat.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local UA = {}
E.UIAmount = UA -- read by the Overview page

UA.LEVELS = { essential = true, moderate = true, full = true }
UA.KEEP = "keep"
UA.CARD = { width = 168, gap = 8 }

E.defaults.general.uiAmount = UA.KEEP

local function General() return E.db and E.db.general end

function UA.Title(level)
	local info = UA.LEVELS[level] and E.uiAmountLevels[level]
	if info then return L[info.title] end
	if level == "custom" then return L["Custom"] end
	return L["Keep as set"]
end

-- Why a listed module is left alone, or nil.
function UA.Skip(name)
	local module = E.modules[name]
	if not (module and module.db) then return L["not loaded"] end
	if E.uiAmountNever[name] then return L["part of playing your class or role"] end
	if not E.GetModuleConflict then return nil end
	local conflict, title = E:GetModuleConflict(module)
	if conflict then return L["%s does this job"]:format(title or tostring(conflict)) end
	return nil
end

local function IsOn(name)
	local module = E.modules[name]
	return module and module.db and module.db.enabled and true or false
end

-- { [module] = on } for the listed modules a level may switch.
function E:UIAmountTargets(level)
	local targets = {}
	if not UA.LEVELS[level] then return targets end
	for _, row in ipairs(self.uiAmountModules) do
		if not UA.Skip(row.module) then targets[row.module] = row[level] and true or false end
	end
	return targets
end

local function ModuleTitle(name)
	local module = E.modules[name]
	return module and L[module.title] or name
end

function E:UIAmountPlan(level)
	local changes, skipped = {}, {}
	if not UA.LEVELS[level] then return changes, skipped end
	for _, row in ipairs(self.uiAmountModules) do
		local reason = UA.Skip(row.module)
		local want = row[level] and true or false
		if reason then
			if reason ~= L["not loaded"] and IsOn(row.module) ~= want then
				skipped[#skipped + 1] = { module = row.module, title = ModuleTitle(row.module), reason = reason }
			end
		elseif IsOn(row.module) ~= want then
			changes[#changes + 1] = { module = row.module, title = ModuleTitle(row.module), from = not want, to = want }
		end
	end
	table.sort(changes, function(a, b) return a.title < b.title end)
	return changes, skipped
end

function E:UIAmountMatch()
	for _, level in ipairs(self.uiAmountLevels.order) do
		local same = true
		for name, want in pairs(self:UIAmountTargets(level)) do
			if IsOn(name) ~= want then same = false break end
		end
		if same then return level end
	end
	return nil
end

function E:UIAmountRecommended(layoutKey)
	layoutKey = layoutKey or (General() and General().layout)
	local level = self.uiAmountRecommended[layoutKey]
	if not UA.LEVELS[level] and self.LayoutFamily then
		level = self.uiAmountRecommended[self:LayoutFamily(layoutKey)]
	end
	return UA.LEVELS[level] and level or "moderate"
end

function UA.Record()
	local general = General()
	if not general then return {} end
	if type(general.uiAmountRestore) ~= "table" then general.uiAmountRestore = {} end
	return general.uiAmountRestore
end

-- Returns how many modules it switched and whether one went off (a
-- module switched off is fully gone after a reload).
function E:ApplyUIAmount(level)
	local general = General()
	if not (general and UA.LEVELS[level]) then return 0, false end
	local record = UA.Record()
	local targets = self:UIAmountTargets(level)
	local changed, off = 0, false
	for _, row in ipairs(self.uiAmountModules) do
		local name = row.module
		local want = targets[name]
		local own = record[name]
		local now = IsOn(name)
		-- Switched by hand since: the player's now.
		if own and (type(own) ~= "table" or own.to ~= now) then
			record[name], own = nil, nil
		end
		if want ~= nil and want ~= now then
			self:SetModuleEnabled(name, want)
			if own and own.from == want then
				record[name] = nil
			elseif own then
				own.to = want
			else
				record[name] = { from = now, to = want }
			end
			changed = changed + 1
			if not want then off = true end
		end
	end
	general.uiAmount = level
	if off and self.ConfigNeedsReload then self:ConfigNeedsReload("uiAmount", L["UI amount"]) end
	-- Picked in the options: the first level that switches modules off
	-- says how to get them back.
	if off and self.Tour and self:ConfigWindowFrame() then self.Tour:Offer("uiamount", level) end
	return changed, off
end

-- How many modules undo would switch back.
function E:UIAmountUndoCount()
	local count = 0
	for name, own in pairs(General() and UA.Record() or {}) do
		if type(own) == "table" and E.modules[name] and IsOn(name) == own.to then count = count + 1 end
	end
	return count
end

function E:UndoUIAmount()
	local general = General()
	if not general then return 0 end
	local record = UA.Record()
	local count = 0
	for name, own in pairs(record) do
		if type(own) == "table" and E.modules[name] and IsOn(name) == own.to then
			self:SetModuleEnabled(name, own.from)
			count = count + 1
		end
	end
	wipe(record)
	general.uiAmount = UA.KEEP
	return count
end

-- What the header shows: the level the modules match, else Custom.
function E:UIAmountState()
	return self:UIAmountMatch() or "custom"
end

---------------------------------------------------------------------------
-- The page: three cards, what the picked one changes, Apply and Undo.
-- A card only picks; nothing changes before Apply.
---------------------------------------------------------------------------
UA.draft = nil

local function Accent() return E:TokenColor("accent") end

local function MakeCard(canvas, level)
	local Kit = E.WindowKit
	local card = Kit.Choice(canvas, UA.CARD.width, 80, UA.Title(level), L[E.uiAmountLevels[level].desc], function()
		UA.draft = level
		if E.RefreshConfig then E:RefreshConfig() end
	end)
	card.level = level
	card.badge = E:CreateText(card, E.tokens.size.small, "LEFT")
	card.badge:SetPoint("TOPLEFT", card.desc, "BOTTOMLEFT", 0, -6)
	card.badge:SetWordWrap(true)
	card.badge:SetText(L["Recommended for this layout"])
	card.check = card:CreateTexture(nil, "OVERLAY")
	card.check:SetSize(12, 12)
	card.check:SetPoint("TOPRIGHT", -8, -9)
	E.UIKit.SetGlyph(card.check, "check")
	card.title:SetPoint("TOPRIGHT", -24, -8)
	return card
end

function UA.UpdateCards(canvas)
	if not canvas then return end
	if not canvas.cards then
		canvas.cards = {}
		for index, level in ipairs(E.uiAmountLevels.order) do canvas.cards[index] = MakeCard(canvas, level) end
	end
	local recommended, now = E:UIAmountRecommended(), E:UIAmountMatch()
	for _, card in ipairs(canvas.cards) do
		card.badge:SetShown(card.level == recommended)
		card.badge:SetTextColor(Accent())
		card.check:SetShown(card.level == now)
		card.check:SetVertexColor(Accent())
		card:SetSelected(card.level == UA.draft)
	end
end

-- Cards side by side when they fit, else one under the other.
function UA.LayoutCards(canvas, width)
	local cards = canvas and canvas.cards
	if not cards then return 1 end
	local spec = UA.CARD
	local scale = E.TextScale and E:TextScale() or 1
	local least = math.floor(spec.width * math.sqrt(math.max(1, scale)))
	local columns = math.max(1, math.min(#cards, math.floor((width + spec.gap) / (least + spec.gap))))
	local cardWidth = math.floor((width - (columns - 1) * spec.gap) / columns)
	local height = 0
	for _, card in ipairs(cards) do
		card:SetWidth(cardWidth)
		card.desc:SetWidth(math.max(cardWidth - 20, 1))
		card.badge:SetWidth(math.max(cardWidth - 20, 1))
		local need = 8 + math.ceil(card.title:GetStringHeight() or 0) + 4 + math.ceil(card.desc:GetStringHeight() or 0)
			+ 6 + math.ceil(card.badge:GetStringHeight() or 0) + 8
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

-- The lines under the cards: what the picked level changes.
function UA.ChangeLines(level)
	if not UA.LEVELS[level] then
		return { L["Pick a level above to see what it changes. Nothing changes until you apply it."] }
	end
	local changes, skipped = E:UIAmountPlan(level)
	local on, off = {}, {}
	for _, change in ipairs(changes) do
		if change.to then on[#on + 1] = change.title else off[#off + 1] = change.title end
	end
	local lines = {}
	if #changes == 0 then lines[1] = L["Your modules already match %s."]:format(UA.Title(level)) end
	if #on > 0 then lines[#lines + 1] = L["Switches on: %s."]:format(table.concat(on, ", ")) end
	if #off > 0 then lines[#lines + 1] = L["Switches off: %s."]:format(table.concat(off, ", ")) end
	for _, skip in ipairs(skipped) do
		lines[#lines + 1] = L["Left as it is: %s (%s)."]:format(skip.title, skip.reason)
	end
	if #off > 0 then lines[#lines + 1] = L["A module switched off is fully gone after a reload."] end
	return lines
end

function UA.UpdateList(canvas, width)
	if not canvas then return 1 end
	canvas.lines = canvas.lines or {}
	width = width or canvas.width or 400
	canvas.width = width
	local texts = UA.ChangeLines(UA.draft)
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

function UA.Options()
	return {
		{ type = "header", label = "UI amount",
			status = function()
				local state = E:UIAmountState()
				if state == "custom" then return L["Your own mix"] end
				return L["Now: %s"]:format(UA.Title(state))
			end },
		{ type = "preview", label = "UI amount", noCaption = true, keywords = "essential moderate full amount modules density",
			create = function(canvas) UA.UpdateCards(canvas) end,
			height = function(canvas, width)
				if not canvas then return 120 end
				UA.UpdateCards(canvas)
				return UA.LayoutCards(canvas, width)
			end,
			update = function(canvas) UA.UpdateCards(canvas) end },
		{ type = "header", label = "What it changes",
			status = function() return UA.LEVELS[UA.draft] and UA.Title(UA.draft) or "" end },
		{ type = "preview", label = "What it changes", noCaption = true,
			create = function(canvas) UA.UpdateList(canvas) end,
			height = function(canvas, width) return UA.UpdateList(canvas, width) end,
			update = function(canvas) UA.UpdateList(canvas) end },
		{ type = "execute", label = "Apply UI amount", noUndo = true,
			desc = "Switches the modules listed above. Your frames, skin, key bindings and other addons stay as they are.",
			disabled = function()
				if not UA.LEVELS[UA.draft] then return L["Pick a level first."] end
				if #E:UIAmountPlan(UA.draft) == 0 then return L["Nothing to change."] end
				return false
			end,
			func = function()
				E:ApplyUIAmount(UA.draft)
				UA.draft = nil
				if E.RefreshConfig then E:RefreshConfig() end
			end },
		{ type = "execute", label = "Undo UI amount", noUndo = true,
			desc = "Switches back what the last UI amount changed. A module you switched yourself since stays as you set it.",
			disabled = function() return E:UIAmountUndoCount() == 0 and L["Nothing to undo."] or false end,
			func = function()
				E:UndoUIAmount()
				if E.RefreshConfig then E:RefreshConfig() end
			end },
		{ type = "description", label = "A level only switches EldoUI modules on or off. It never moves frames or changes your skin, key bindings or other addons." },
	}
end

-- Shown translated: L["UI amount"], L["What it changes"], L["Apply UI amount"],
-- L["Undo UI amount"], L["Essential"], L["Moderate"], L["Full"] and the
-- level texts in Data/UIAmounts.lua.

E:RegisterEvent("PLAYER_LOGIN", function()
	if not E.RegisterConfigPage then return end
	UA.proxy = UA.proxy or {}
	E:RegisterConfigPage("uiamount", "UI amount", UA.Options(), function() return UA.proxy end, function() end, 2.5)
end, UA, "pages")
