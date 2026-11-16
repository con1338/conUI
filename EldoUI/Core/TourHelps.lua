-- EldoUI tour helps: the places that explain themselves once.
--
-- Each help here is registered with the tour engine (Core/Tour.lua) and
-- offered when its place comes up. Every one shows once (per layout for
-- the layout helps), never in combat, an instance or over the setup, and
-- the Tour helps switch on the General options page turns them all off.
--
--   options:tourhelps    the first time General options opens: the switch
--                        that turns the helps off
--   setup:finished       after the setup is finished: where to change things
--   chat:tabs            after that, when the setup made chat tabs
--   layout:hiddenbar<n>  a layout hides an action bar that keeps its keys:
--                        a copy of the bar is drawn where it sits, with the
--                        help above it (the real bar is never touched)
--   layout:mouseover     a layout's bars that show on mouse-over
--   move:first           the first time move mode opens
--   options:layouts      the first time the Layouts page opens
--   options:blizzard     the first time the Blizzard UI page opens
--   keys:applied         after a key set is applied
local _, E = ...
local L = E.L
local Tour = E.Tour

local function Bars()
	local bars = E.modules and E.modules.ActionBars
	if bars and bars.active and type(bars.db) == "table" and type(bars.db.bars) == "table" then return bars end
end

-- "4", "4 and 5", "3, 4 and 5".
local function JoinList(items)
	if #items <= 1 then return items[1] or "" end
	return L["%s and %s"]:format(table.concat(items, ", ", 1, #items - 1), items[#items])
end

---------------------------------------------------------------------------
-- General options: the switch itself
---------------------------------------------------------------------------
Tour:Register("options:tourhelps", {
	form = "spot", word = "options", page = "general", pageKey = "tours.enabled",
	offer = function(_, force)
		return Tour:Spot("options:tourhelps", {
			force = force,
			target = function() return E:ConfigOptionFrame("general", "tours.enabled") end,
			title = L["Tour helps"],
			text = L["Tour helps explain new things once, like this one. Turn them off here; Show tour helps again brings them back."],
		})
	end,
	replay = function(def) C_Timer.After(0.2, function() def.offer(def, true) end) end,
})

---------------------------------------------------------------------------
-- Options pages that need a word the first time they open
---------------------------------------------------------------------------
local PAGE_HELPS = {
	layouts = { key = "options:layouts", word = "layouts", title = "Layouts and styles",
		text = "A layout places all your frames at once. A style changes the look of one part. UI amount picks how many helpers are on. A pack sets all three in one click." }, -- no-L: translated where shown (L[help.text])
	blizzard = { key = "options:blizzard", word = "blizzard", title = "Blizzard UI",
		text = "Each part of Blizzard's own UI has one switch. Off leaves it as Blizzard made it. Skin, Move, Hide, Replace and Improve say what EldoUI may do with it." }, -- no-L: translated where shown (L[help.text])
}

local function PageTitle()
	local window = E:ConfigWindowFrame()
	return window and window.title or nil
end

for pageId, help in pairs(PAGE_HELPS) do
	Tour:Register(help.key, {
		form = "spot", word = help.word, page = pageId,
		offer = function(_, force)
			return Tour:Spot(help.key, { force = force, target = PageTitle, title = L[help.title], text = L[help.text] })
		end,
		replay = function(def) C_Timer.After(0.2, function() def.offer(def, true) end) end,
	})
end

-- Shown translated: L["Layouts and styles"], L["Blizzard UI"],
-- L["A layout places all your frames at once. A style changes the look of one part. UI amount picks how many helpers are on. A pack sets all three in one click."],
-- L["Each part of Blizzard's own UI has one switch. Off leaves it as Blizzard made it. Skin, Move, Hide, Replace and Improve say what EldoUI may do with it."]

E:OnConfigPageShown(function(pageId)
	-- The page draws its rows first.
	C_Timer.After(0.2, function()
		if pageId == "general" then
			Tour:Offer("options:tourhelps")
		elseif PAGE_HELPS[pageId] then
			Tour:Offer(PAGE_HELPS[pageId].key)
		end
	end)
end)

---------------------------------------------------------------------------
-- The setup is finished
---------------------------------------------------------------------------
local CHAT_TAB_TITLES = { "Whispers", "Loot", "Channels" }

-- The first chat tab the setup made that is on screen.
local function SetupChatTab()
	if type(FCF_GetChatWindowInfo) ~= "function" then return nil end
	local wanted = {}
	for _, title in ipairs(CHAT_TAB_TITLES) do wanted[L[title]] = true end
	for index = 1, NUM_CHAT_WINDOWS or 10 do
		local name = FCF_GetChatWindowInfo(index)
		local tab = _G["ChatFrame" .. index .. "Tab"]
		if type(name) == "string" and wanted[name] and tab and tab:IsVisible() then return tab end
	end
end

Tour:Register("chat:tabs", {
	form = "spot", word = "chat",
	offer = function(_, force)
		if not SetupChatTab() then return false end
		return Tour:Spot("chat:tabs", {
			force = force, target = SetupChatTab, side = "TOP",
			title = L["Chat tabs"],
			text = L["Whispers, loot and the public channels have their own tabs now, so your main chat stays readable. Right-click a tab to change or close it."],
		})
	end,
	replay = function(def) def.offer(def, true) end,
})

Tour:Register("setup:finished", {
	form = "spot", word = "setup",
	offer = function(_, force)
		return Tour:Spot("setup:finished", {
			force = force,
			title = L["Your UI is ready"],
			text = L["Change it any time: /eui opens the options, /eui move lets you drag frames and /eui kb sets your keys. /eui install undo brings back the UI you had before."],
			buttons = {
				{ L["Move frames"], function() E:ToggleMoveMode(true) end, L["Drag any frame to a new place (/eui move)."] },
			},
			-- The chat tabs come next, when the setup made them.
			onClose = function(how)
				if how ~= "combat" then C_Timer.After(0.5, function() Tour:Offer("chat:tabs") end) end
			end,
		})
	end,
	replay = function(def) def.offer(def, true) end,
})

-- Finish (not Skip) leaves the setup's run in place until the window closes.
hooksecurefunc(E.Installer, "SetupDone", function()
	if E.Installer.GetSession() then Tour:Offer("setup:finished") end
end)

---------------------------------------------------------------------------
-- Move mode
---------------------------------------------------------------------------
Tour:Register("move:first", {
	form = "spot", word = "move",
	offer = function(_, force)
		return Tour:Spot("move:first", {
			force = force, target = function() return _G.EldoUI_Nudge end,
			title = L["Move mode"],
			text = L["Drag any frame to move it. Right-click a frame for its options. Done or Escape keeps your changes and leaves."],
		})
	end,
	replay = function(def)
		if not E:IsMoveMode() then E:ToggleMoveMode(true) end
		C_Timer.After(0.2, function() def.offer(def, true) end)
	end,
})

hooksecurefunc(E, "ToggleMoveMode", function()
	if E:IsMoveMode() then C_Timer.After(0.3, function() Tour:Offer("move:first") end) end
end)

---------------------------------------------------------------------------
-- Key sets
---------------------------------------------------------------------------
Tour:Register("keys:applied", {
	form = "spot", word = "keys",
	offer = function(_, scope, force)
		return Tour:Spot("keys:applied", {
			force = force, scope = scope,
			title = L["Your keys are set"],
			text = L["Each bar has its own keys now. The key preview on the Keybinds page in /eui shows every one, and Undo last key set there puts your old keys back."],
		})
	end,
	replay = function(def) def.offer(def, nil, true) end,
})

-- Once per key set, after an Apply the player made (not a quiet one).
if E.OnKeymapChange then
	E:OnKeymapChange(function(kind, plan, _, opts)
		if kind == "applied" and plan and not (opts and opts.quiet) then Tour:Offer("keys:applied", plan.id) end
	end)
end

---------------------------------------------------------------------------
-- Layouts: hidden action bars
---------------------------------------------------------------------------
-- The long cooldowns that may sit on a hidden button (each 2 minutes or
-- more, its key shown by the Cooldown Manager). The key map marks them
-- (longCooldown); this short list is read when it does not.
local LONG_COOLDOWNS = {
	[19263] = true, -- Deterrence
	[3045] = true,  -- Rapid Fire
	[19574] = true, -- Bestial Wrath
	[20484] = true, [20739] = true, [20742] = true, [20747] = true, [20748] = true, -- Rebirth
}

local longCooldowns
local function AddLong(set, entry)
	if type(entry) ~= "table" then return end
	if entry.spells then
		if entry.longCooldown then
			for _, id in ipairs(entry.spells) do set[id] = true end
		end
		return
	end
	for _, sub in ipairs(entry) do AddLong(set, sub) end
end

-- The player's class's long cooldowns, from the key map when it has them.
local function LongCooldowns()
	if longCooldowns then return longCooldowns end
	local C = E.keybindCategories
	local _, class = UnitClass("player")
	local set, any = {}, false
	if C and type(C.classes) == "table" and class and C.classes[class] then
		for _, entry in pairs(C.classes[class]) do AddLong(set, entry) end
		any = next(set) ~= nil
	end
	longCooldowns = any and set or LONG_COOLDOWNS
	return longCooldowns
end

local function SpellName(id)
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
	if type(name) == "string" and not E:IsSecret(name) then return name end
end

local function KeyText(key)
	return key and E:KeybindKeyText(key) or nil
end

local function SlotOf(bars, index, button)
	local info = bars.BARS and bars.BARS[index]
	return info and (info.page - 1) * 12 + button
end

-- The rule's long cooldowns on bar `index`: "Rapid Fire (Ctrl-2)", ...
local function BarCooldowns(bars, index)
	local list = {}
	local info = bars.BARS and bars.BARS[index]
	if not info or type(GetActionInfo) ~= "function" then return list end
	local long = LongCooldowns()
	for button = 1, 12 do
		local kind, id = GetActionInfo(SlotOf(bars, index, button))
		if kind == "spell" and not E:IsSecret(id) and long[id] then
			local name = SpellName(id)
			local key = GetBindingKey(info.binding .. button)
			if name then list[#list + 1] = key and L["%s (%s)"]:format(name, KeyText(key)) or name end
		end
	end
	return list
end

-- True when every key on the bar uses Ctrl (the usual home of bar 3).
local function CtrlKeys(bars, index)
	local info = bars.BARS and bars.BARS[index]
	local any = false
	for button = 1, 12 do
		local key = info and GetBindingKey(info.binding .. button)
		if key then
			if not key:match("^CTRL%-") then return false end
			any = true
		end
	end
	return any
end

-- The drawn copy of a hidden bar: its icons and keys on plain frames
-- where the bar sits. It never touches the real bar and goes away with
-- the help (and so with combat).
local copy

local function CopyFrame()
	if copy then return copy end
	local Kit = E.UIKit
	copy = CreateFrame("Frame", "EldoUITourBarCopy", UIParent)
	copy:SetFrameStrata("FULLSCREEN_DIALOG")
	copy:SetFrameLevel(90)
	copy:EnableMouse(false)
	copy:Hide()
	copy.buttons = {}
	copy.NewButton = function(self)
		local button = CreateFrame("Frame", nil, self)
		E:SetTemplate(button)
		button.icon = button:CreateTexture(nil, "ARTWORK")
		button.icon:SetPoint("TOPLEFT", 1, -1)
		button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		E:TrimIcon(button.icon)
		button.key = Kit.Text(button, E.tokens.size.tiny, "RIGHT")
		button.key:SetPoint("TOPRIGHT", -2, -2)
		self.buttons[#self.buttons + 1] = button
		return button
	end
	return copy
end

local function HideCopy()
	if copy then copy:Hide() end
end

local function Clamp(value, low, high, fallback)
	value = tonumber(value) or fallback
	return math.max(low, math.min(high, math.floor(value)))
end

local function DrawCopy(bars, index)
	local mover = E.movers and E.movers["EldoUI_ActionBar" .. index]
	local barDB = bars.db.bars[index]
	local info = bars.BARS and bars.BARS[index]
	if not (mover and mover:GetLeft() and barDB and info) then return nil end
	local frame = CopyFrame()
	local count = Clamp(barDB.buttons, 1, 12, 12)
	local perRow = Clamp(barDB.perRow, 1, count, count)
	local rows = math.ceil(count / perRow)
	local spacing = tonumber(barDB.spacing) or 4
	local size = (tonumber(barDB.size) or 36) * (tonumber(barDB.scale) or 100) / 100
	frame:SetSize(perRow * size + (perRow - 1) * spacing, rows * size + (rows - 1) * spacing)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", mover, "CENTER")
	local getTexture = C_ActionBar and C_ActionBar.GetActionTexture or GetActionTexture
	for button = 1, count do
		local cell = frame.buttons[button] or frame:NewButton()
		local column, row = (button - 1) % perRow, math.floor((button - 1) / perRow)
		cell:SetSize(size, size)
		cell:ClearAllPoints()
		cell:SetPoint("TOPLEFT", frame, "TOPLEFT", column * (size + spacing), -row * (size + spacing))
		local texture = getTexture and getTexture(SlotOf(bars, index, button))
		cell.icon:SetTexture(texture)
		cell.icon:SetShown(texture ~= nil)
		local key = GetBindingKey(info.binding .. button)
		cell.key:SetText(key and KeyText(key) or "")
		cell:SetBackdropBorderColor(unpack(E.media.borderColor))
		cell:Show()
	end
	for button = count + 1, #frame.buttons do frame.buttons[button]:Hide() end
	frame:Show()
	return frame
end

local function HiddenBarText(bars, index)
	local keys = CtrlKeys(bars, index)
	local text
	if index == 3 then
		text = keys and L["Your between-pulls bar: buffs, travel and resurrection. Point at it out of combat to use it; Ctrl and your keys work any time."]
			or L["Your between-pulls bar: buffs, travel and resurrection. Point at it out of combat to use it; its keys work any time."]
	else
		text = L["This layout keeps bar %d out of sight. Point at it out of combat to use it; its keys work any time."]:format(index)
	end
	local cooldowns = BarCooldowns(bars, index)
	if #cooldowns == 1 then
		text = text .. "\n\n" .. L["%s: the Cooldown Manager shows its key."]:format(cooldowns[1])
	elseif #cooldowns > 1 then
		text = text .. "\n\n" .. L["%s: the Cooldown Manager shows their keys."]:format(JoinList(cooldowns))
	end
	return text
end

local function HiddenBarHelp(index)
	local key = "layout:hiddenbar" .. index
	if Tour:Get(key) then return key end
	Tour:Register(key, {
		form = "spot", word = "hiddenbar" .. index,
		offer = function(_, scope, force)
			local bars = Bars()
			if not bars then return false end
			local buttons
			if bars.SetHiddenBarMouseover then
				buttons = { { L["Keep it hidden"], function() bars:SetHiddenBarMouseover(index, false) end,
					L["The bar stays out of sight, also when you point at it. Its keys still work. Action Bars brings it back."] } }
			end
			return Tour:Spot(key, {
				force = force, scope = scope, side = "TOP",
				target = function() return DrawCopy(bars, index) end,
				title = L["Bar %d is here"]:format(index), -- no-plural: a bar number
				text = HiddenBarText(bars, index),
				buttons = buttons,
				onClose = HideCopy,
			})
		end,
		replay = function(def)
			local bars = Bars()
			if not bars then
				E:Print(E:ModuleOffHint("ActionBars"))
				return
			end
			def.offer(def, E.db.general.layout, true)
		end,
	})
	return key
end

---------------------------------------------------------------------------
-- Layouts: bars that show on mouse-over
---------------------------------------------------------------------------
local function MouseoverBars(bars, skip)
	local list = {}
	for index, barDB in ipairs(bars.db.bars) do
		local fade = barDB.fade
		if barDB.enabled and not skip[index] and type(fade) == "table" and fade.show == "mouseover" then list[#list + 1] = index end
	end
	return list
end

Tour:Register("layout:mouseover", {
	form = "spot", word = "mouseover",
	offer = function(_, scope, skip, force)
		local bars = Bars()
		if not bars then return false end
		local list = MouseoverBars(bars, skip or {})
		if #list == 0 then return false end
		local names = {}
		for _, index in ipairs(list) do names[#names + 1] = tostring(index) end
		local text = #list == 1
			and L["Bar %s appears when you point at its spot. Its buttons and keys always work."]:format(names[1])
			or L["Bars %s appear when you point at their spot. Their buttons and keys always work."]:format(JoinList(names))
		return Tour:Spot("layout:mouseover", {
			force = force, scope = scope, side = "TOP",
			target = function() return E.movers and E.movers["EldoUI_ActionBar" .. list[1]] end,
			title = #list == 1 and L["A bar that shows on mouse-over"] or L["Bars that show on mouse-over"],
			text = text,
			buttons = { { #list == 1 and L["Always show it"] or L["Always show them"], function()
				E:RunOutOfCombat(function()
					for _, index in ipairs(list) do E:ApplyVisibilityPreset(bars.db.bars[index].fade, "always") end
					bars:ApplyChanges()
					if E.RefreshConfig then E:RefreshConfig() end
				end, "TourHelps:bars")
			end, L["The bar shows all the time. Action Bars > Visibility changes it again."] } },
		})
	end,
	replay = function(def) def.offer(def, E.db.general.layout, nil, true) end,
})

---------------------------------------------------------------------------
-- When the layout helps are offered: after a layout is applied, at login
-- and after the setup. Each shows once per layout.
---------------------------------------------------------------------------
-- A bar holds something worth a help when one of its buttons has an
-- action or a key.
local function BarInUse(bars, index)
	local info = bars.BARS and bars.BARS[index]
	if not info then return false end
	local hasAction = C_ActionBar and C_ActionBar.HasAction or HasAction
	for button = 1, 12 do
		local slot = SlotOf(bars, index, button)
		if (hasAction and hasAction(slot)) or GetBindingKey(info.binding .. button) then return true end
	end
	return false
end

-- The bars this layout keeps out of sight: switched on by the player,
-- not shown by the layout. Only once hidden bars keep their keys (the
-- bars can then be kept hidden) does the help say they work.
local function HiddenBars(bars)
	local list = {}
	if not bars.SetHiddenBarMouseover then return list end
	for index, barDB in ipairs(bars.db.bars) do
		if barDB.enabled and barDB.shown == false and BarInUse(bars, index) then list[#list + 1] = index end
	end
	return list
end

local function OfferLayoutHelps()
	local bars = Bars()
	local layout = E.db and E.db.general and E.db.general.layout
	if not (bars and layout) then return end
	-- Only once hidden bars keep their keys does the help say they work.
	local hidden = {}
	for _, index in ipairs(HiddenBars(bars)) do
		hidden[index] = true
		Tour:Offer(HiddenBarHelp(index), layout)
	end
	Tour:Offer("layout:mouseover", layout, hidden)
end
Tour.OfferLayoutHelps = function() OfferLayoutHelps() end

E:RegisterLayoutCallback(function()
	-- A help still waiting for the layout before is no longer true.
	Tour:Unqueue("layout:")
	C_Timer.After(0.5, OfferLayoutHelps)
end)

E:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, _, login, reload)
	if login or reload then C_Timer.After(5, OfferLayoutHelps) end
end, Tour)

hooksecurefunc(E.Installer, "SetupDone", function()
	C_Timer.After(1, OfferLayoutHelps)
end)

---------------------------------------------------------------------------
-- Styles, keybind mode, profile rules and UI amount
--
--   style:first      the first style the player picks in the options
--   keybind:first    the first time keybind mode opens
--   profile:rule     the first profile switch a profile rule makes
--   uiamount         a UI amount that switched modules off (once per level)
---------------------------------------------------------------------------
-- The options page on screen, for the helps that need to know it.
local shownPage
E:OnConfigPageShown(function(pageId) shownPage = pageId end)

Tour:Register("style:first", {
	form = "spot", word = "styles", page = "styles",
	offer = function(_, force)
		return Tour:Spot("style:first", {
			force = force, target = PageTitle,
			title = L["Styles"],
			text = L["A style sets the look of this part in one click. Picking another style replaces it, settings included, so pick the style first and fine-tune after."],
		})
	end,
	replay = function(def) C_Timer.After(0.2, function() def.offer(def, true) end) end,
})

-- A style the player picked on its module page or on the Style presets
-- page (the setup and the layouts apply theirs silently).
hooksecurefunc(E, "ApplyStyle", function(_, moduleName, styleKey, silent)
	if silent or not E:ConfigWindowFrame() then return end
	if shownPage ~= "styles" and shownPage ~= "module:" .. tostring(moduleName) then return end
	local module = E.modules[moduleName]
	if not (module and module.db and module.db.style == styleKey) then return end
	C_Timer.After(0.2, function() Tour:Offer("style:first") end)
end)

Tour:Register("keybind:first", {
	form = "spot", word = "keybind",
	offer = function(_, force)
		return Tour:Spot("keybind:first", {
			force = force, target = function() return _G.EldoUI_KeybindBanner end,
			title = L["Keybind mode"],
			text = L["Point at a button and press a key, a mouse button or the wheel to bind it. Escape over a button clears its keys; Escape anywhere else saves and leaves. Discard leaves without your changes."],
		})
	end,
	replay = function(def)
		if not E:IsKeybindMode() then E:ToggleKeybindMode(true) end
		C_Timer.After(0.2, function() def.offer(def, true) end)
	end,
})

hooksecurefunc(E, "ToggleKeybindMode", function()
	if E:IsKeybindMode() then C_Timer.After(0.3, function() Tour:Offer("keybind:first") end) end
end)

-- Offered by E:CheckProfileRules after a rule switched the profile.
Tour:Register("profile:rule", {
	form = "spot", word = "profilerules",
	offer = function(_, profile, force)
		return Tour:Spot("profile:rule", {
			force = force,
			title = L["Profile rules"],
			text = L["EldoUI switched to your profile %s because one of your profile rules asked for it. The rules pick a profile by talent group, or by solo, party, raid and battleground; Profile rules in /eui changes them."]
				:format(E:Highlight(tostring(profile or E.profileName))),
		})
	end,
	replay = function(def) def.offer(def, E.profileName, true) end,
})

-- Offered by E:ApplyUIAmount when a level the player applied in the
-- options switched modules off.
Tour:Register("uiamount", {
	form = "spot", word = "uiamount",
	offer = function(_, level, force)
		local UA = E.UIAmount
		if not (UA and UA.LEVELS[level]) then return false end
		local buttons
		if E:UIAmountUndoCount() > 0 then
			buttons = { { L["Undo UI amount"], function()
				E:UndoUIAmount()
				if E.RefreshConfig then E:RefreshConfig() end
			end, L["Switches back what the last UI amount changed. A module you switched yourself since stays as you set it."] } }
		end
		return Tour:Spot("uiamount", {
			force = force, scope = level,
			target = E:ConfigWindowFrame() and PageTitle or nil,
			title = L["UI amount"],
			text = L["%s switched some EldoUI modules off. They are fully gone after a reload. Undo UI amount switches back what it changed."]:format(E:Highlight(UA.Title(level))),
			buttons = buttons,
		})
	end,
	replay = function(def)
		-- Only a level that keeps modules off has something to say.
		local level = E.db and E.db.general and E.db.general.uiAmount
		if not (E.UIAmount and E.UIAmount.LEVELS[level]) then return end
		for _, on in pairs(E:UIAmountTargets(level)) do
			if not on then
				def.offer(def, level, true)
				return
			end
		end
	end,
})
