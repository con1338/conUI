-- EldoUI Info Bar: a full-width bar along the bottom edge (and an optional
-- second bar, EldoUI_InfoBar2) with small data blocks ("datatexts"):
-- friends, guild, profession, hearthstone, clock, class, bags, durability,
-- gold, currencies, FPS and latency, plus XP, reputation, honor, zone,
-- coordinates, speed, mail, spec, item level, played time, memory and CPU,
-- and the micro menu as "Menu" (Modules/MicroMenu.lua).
-- Plugins add their own blocks with EldoUI:RegisterDataText(name, definition).
--
-- Custom datatext panels: up to eight named panels, each with its
-- own slots, size, direction, backdrop, strata, tooltip side and shared
-- visibility rules, on its own mover (EldoUI_DataPanel1..8) or docked
-- inside the chat window (top edge) or the minimap (bottom edge). More datatexts: date, combat time,
-- in combat, instance difficulty, volume, battleground score, ammo, quests,
-- character stats, custom currencies, DPS/HPS from Blizzard's damage meter,
-- a spacer and an EldoUI button. Per-datatext label (hide, custom, icon)
-- and value/label colors.
--
-- Rules (Forever): stat values are secret while unit stats are restricted
-- (in combat). They are only handed to string.format/SetText, never
-- compared, colored by value or measured; "–" when they can't be shown.
-- DPS/HPS only re-display Blizzard's C_DamageMeter session, no combat log.
local _, E = ...
local L = E.L

local Key = E.Key
local MAX_PANELS = 8
local MAX_PANEL_SLOTS = 8
local SLOTS = 6 -- datatext slots per section of a full-width bar

local M = E:NewModule("InfoBar", {
	title = "Info Bar",
	desc = "Full-width bars and your own datatext panels with clock, gold, durability, stats and more.",
	conflicts = { "EllesmereUIDataBars" },
	frames = {
		"EldoUI_InfoBar", "EldoUI_InfoBar2", "EldoUI_InfoBarHearth", "EldoUI_DataPanel1", "EldoUI_DataPanel2",
		"EldoUI_DataPanel3", "EldoUI_DataPanel4", "EldoUI_DataPanel5", "EldoUI_DataPanel6",
		"EldoUI_DataPanel7", "EldoUI_DataPanel8",
	},
	movers = {
		"EldoUI_InfoBar", "EldoUI_InfoBar2", "EldoUI_DataPanel1", "EldoUI_DataPanel2", "EldoUI_DataPanel3",
		"EldoUI_DataPanel4", "EldoUI_DataPanel5", "EldoUI_DataPanel6", "EldoUI_DataPanel7",
		"EldoUI_DataPanel8",
	},
	blizzard = {},
	savedKeys = { "profile.modules.InfoBar" },
	optionsPage = "module:InfoBar",
	presets = { "Bold", "Class", "Full", "Levelling", "Quiet", "Slim", "TwoBars" },
	reload = false,
	defaults = {
		height = 28,
		fontSize = 14,
		-- Six slots per section ("" = empty), one per slot row on the page.
		left = { "Friends", "Guild", "Profession", "Hearthstone", "Class", "" },
		center = { "Time", "", "", "", "", "" },
		right = { "Bags", "Durability", "Gold", "FPS", "Latency", "Memory" },
		shiftDrag = true,
		goldFilter = "all",
		latencyWarn = 150,
		latencyBad = 300,
		cpuWarn = 2,
		cpuBad = 5,
		coordDecimals = 1,
		-- Formats
		timeSource = "local",   -- local | realm
		dateFormat = "dmy",     -- dmy | mdy | iso | long
		goldFormat = "gold",    -- gold (gold only) | full (g s c) | short (12.3k)
		statDecimals = 1,
		ammoWarn = 200,
		bgSwap = false,         -- battlegrounds: the main bar's center shows the score
		labelColor = "accent",  -- accent | class | white | gray
		valueColor = "white",   -- white | class | accent
		currency1 = 0, currency2 = 0, currency3 = 0, currency4 = 0,
		dt = {},                -- per datatext: { label = "default"|"none"|"custom"|"icon", custom = "" }
		dtEdit = "Durability",  -- the datatext the label rows edit
		-- Look of the main bar (bar 2 has the same keys under bar2).
		width = 0,              -- 0 = full screen width
		backdrop = true,
		backdropAlpha = 50,
		visibility = E:VisibilityDefaults(),
		tooltipAnchor = "AUTO",
		collapsed = "open",     -- open | tab (folded to a small tab) | hidden
		collapseControl = true, -- the small fold button at the bar's right end
		-- LibDataBroker feeds from other addons (only when one of them loads the library).
		ldb = true,
		ldbIcons = true,
		ldbLabels = false,
		-- The blocks offered to other addons' LibDataBroker displays
		-- (Modules/InfoBar/Broker.lua); "" is an empty slot.
		ldbBlocks = { "", "", "", "", "", "", "", "" },
		bar2 = {
			enabled = false,
			dock = "chat",      -- chat (the top edge of the chat window) | none (its own mover)
			height = 24,
			fontSize = 13,
			-- On its own mover the bar takes the free stretch of the top edge
			-- the layouts keep for it, between the farming bar and the mirror
			-- timers (0 = full width; in the chat window it is as wide as the
			-- chat).
			width = 390,
			backdrop = true,
			backdropAlpha = 50,
			visibility = E:VisibilityDefaults(),
			tooltipAnchor = "AUTO",
			collapsed = "open",
			collapseControl = true,
			left = { "Zone", "Coords", "", "", "", "" },
			center = { "XP", "", "", "", "", "" },
			right = { "Reputation", "Mail", "CPU", "", "", "" },
		},
		-- Set once per profile: a bar 2 that was on before it could dock keeps its mover.
		bar2DockChecked = false,
		-- Custom panels; see PANEL_DEFAULTS.
		panels = {},
		editPanel = 1,
	},
})

-- Keys every custom panel has.
local PANEL_DEFAULTS = {
	name = "Panel",
	enabled = true,
	numSlots = 3,
	slots = {},
	width = 300,
	height = 24,
	vertical = false,
	backdrop = true,
	backdropAlpha = 60,
	border = true,
	fontSize = 13,
	strata = "LOW",
	tooltipAnchor = "AUTO",
	display = "text",       -- text (slots side by side or stacked) | dashboard (rows with bars)
	attach = "none",        -- none (own mover) | chat | minimap
	attachWidth = true,     -- attached: as wide as the chat or minimap
	visibility = E:VisibilityDefaults(),
}

---------------------------------------------------------------------------
-- Datatext registry (public API)
--
-- EldoUI:RegisterDataText("Name", {
--     title   = "Shown name",           -- optional, for the options and tooltip
--     events  = { "EVENT_NAME", ... }, -- optional, refresh on these events
--                                       -- (UNIT_* events arrive for "player" only)
--     poll    = true,                   -- optional, refresh every second
--     interval = 5,                     -- optional, seconds between polls
--     pollWhen = function() return true end, -- optional: poll only while this
--                                       -- returns true (no field: always)
--     text    = function() return "shown text" end,
--     tooltip = function(tooltip) tooltip:AddLine("...") end, -- optional
--     onClick = function(button) end,                         -- optional (also runs
--                                       -- from the bar's "»" menu while the block has
--                                       -- no room; button is then hidden)
--     hint    = { "Click", "open X" },   -- optional click hint at the end of the tooltip
--                                       -- (or a list of them, or a function returning
--                                       -- one or nil); an older "Click: open X" text works too
--     label   = "Dur",                  -- optional label before the value (the
--                                       -- player can hide it or replace it)
--     labelAfter = true,                -- optional: the label follows the value
--     icon    = texture,                -- optional: shown when the label is set to "icon"
--     onMouseWheel = function(button, delta) end,             -- optional
--     combatClick = true,               -- optional: clicks also work in combat
--     secretWidth = 90,                 -- optional: width while the text is secret
-- })
---------------------------------------------------------------------------
E.dataTexts = {}

function E:RegisterDataText(name, definition)
	assert(type(definition.text) == "function", "RegisterDataText needs a text function")
	self.dataTexts[name] = definition
	if M.active then M:Rebuild() end
end

-- A data text title with a part filled in ("Stat: %s"), worked out when it
-- is read so it shows in the language picked after the files load.
local function FilledTitle(definition, text, fill)
	definition.title = nil
	return setmetatable(definition, { __index = function(_, field)
		if field == "title" then return L[text]:format(E:Translate(fill)) end
	end })
end

-- Money in the Money style (Fonts and text page).
local function CoinString(copper) return E:FormatMoney(copper) end

-- Semantic colors (DESIGN.md): green good, yellow warning, red danger.
-- Rebuilt when the color-blind safe colors are switched.
local GREEN, YELLOW, RED, GREY
E:OnStatusColors(function()
	GREEN, YELLOW, RED, GREY = E:TextHex("good"), E:TextHex("warn"), E:TextHex("bad"), E:TextHex("secondary")
end)

local IsSecret = E.Secret

local function DB()
	return M.db or M.defaults
end

local function Hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- Color code for a color mode (accent, class, white, gray). Read when
-- drawing, so a new accent shows at once.
local function ModeColor(mode)
	if mode == "class" then return Hex(E:ClassColor("player")) end
	if mode == "white" then return "|cffffffff" end
	if mode == "grey" then return GREY end
	if mode == "accent" then return Hex(unpack(E.media.accentText)) end
	return nil
end

-- Values go through string.format, never `..` math, so a secret value
-- (a stat in combat) can still be shown.
local function Value(text)
	return ("%s%s|r"):format(ModeColor(DB().valueColor) or "|cffffffff", text)
end

local function Label(text)
	return ("%s%s|r"):format(ModeColor(DB().labelColor) or ModeColor("accent"), text)
end

-- A value in its status color. A warning or danger also gets its shape
-- mark (E:StatusText), so the color never carries the meaning alone.
local function Status(kind, text)
	if kind == "warn" or kind == "bad" then return E:StatusText(kind, text) end
	return (kind == "good" and GREEN or "|cffffffff") .. text .. "|r"
end
-- The same look for the blocks in Modules/InfoBar/.
M.Value, M.Label, M.Status = Value, Label, Status

-- The status of a value by "lower is worse" (durability) or "higher is
-- worse" (latency): "bad", "warn", "good" or nil (plain).
local function Threshold(value, warn, bad, higherIsWorse)
	if higherIsWorse then
		if value >= bad then return "bad" elseif value >= warn then return "warn" end
		return "good"
	end
	if value <= bad then return "bad" elseif value <= warn then return "warn" end
	return nil
end

-- Durability follows the shared thresholds (General > Clock and
-- durability), the same as on the character window and the ready report.
local DURABILITY_STATUS = { low = "bad", warn = "warn" }
local function DurabilityText(percent)
	return Status(DURABILITY_STATUS[E:DurabilityLevel(percent) or ""], ("%d%%"):format(percent))
end

---------------------------------------------------------------------------
-- Built-in datatexts. They only show data the game gives every addon.
---------------------------------------------------------------------------
-- Clock text in the chosen format (24 h or 12 h) for local or realm time.
-- The clock format is shared (General > Clock and durability).
local function LocalClock()
	local now = date("*t")
	return E:FormatClock(now.hour, now.min)
end

local function RealmClock()
	local hour, minute = GetGameTime()
	return E:FormatClock(hour, minute)
end

E:RegisterDataText("Time", {
	poll = true,
	text = function()
		local db = DB()
		if db.timeSource == "realm" then return Value(RealmClock()) end
		return Value(LocalClock())
	end,
	tooltip = function(tooltip)
		tooltip:AddDoubleLine(L["Local time"], LocalClock(), 1, 1, 1, 1, 1, 1)
		tooltip:AddDoubleLine(L["Realm time"], RealmClock(), 1, 1, 1, 1, 1, 1)
		E:TooltipHint(tooltip, { L["Click"], L["calendar"] })
	end,
	-- Opens a normal game window: works in combat too.
	combatClick = true,
	onClick = function()
		if not C_AddOns.IsAddOnLoaded("Blizzard_Calendar") then C_AddOns.LoadAddOn("Blizzard_Calendar") end
		if ToggleCalendar then ToggleCalendar() end
	end,
})

E:RegisterDataText("FPS", {
	poll = true,
	label = "fps",
	labelAfter = true,
	text = function()
		return Value(("%d"):format(GetFramerate()))
	end,
	tooltip = function(tooltip)
		E.UIKit.TipPair(tooltip, L["Frames per second"], ("%.0f"):format(GetFramerate()))
		if C_CVar and C_CVar.GetCVar then
			local cap = tonumber(C_CVar.GetCVar("maxFPS"))
			if cap and cap > 0 then E.UIKit.TipPair(tooltip, L["Frame cap"], tostring(cap)) end
		end
	end,
	hint = { Key("Click"), Key("show or hide the game's own frame rate counter") },
	-- Opens a normal game window: works in combat too.
	combatClick = true,
	onClick = function()
		if FramerateFrame and FramerateFrame.Toggle then FramerateFrame:Toggle() end
	end,
})

E:RegisterDataText("Latency", {
	poll = true,
	label = "ms",
	labelAfter = true,
	text = function()
		local _, _, home, world = GetNetStats()
		local ms = math.max(home, world)
		local db = DB()
		return Status(Threshold(ms, db.latencyWarn, db.latencyBad, true), ("%d"):format(ms))
	end,
	tooltip = function(tooltip)
		local _, _, home, world = GetNetStats()
		local down, up = GetNetStats()
		tooltip:AddDoubleLine(L["Home"], home .. " ms", 1, 1, 1, 1, 1, 1)
		tooltip:AddDoubleLine(L["World"], world .. " ms", 1, 1, 1, 1, 1, 1)
		if type(down) == "number" and type(up) == "number" then
			E.UIKit.TipPair(tooltip, L["Download / upload"], L["%.1f / %.1f KB/s"]:format(down, up))
		end
		tooltip:AddLine(" ")
		E.UIKit.TipText(tooltip, L["Home: chat and your realm. World: combat and the world around you."])
	end,
})

---------------------------------------------------------------------------
-- Durability
---------------------------------------------------------------------------
-- Repair cost per slot from the tooltip data, when the client gives it.
-- Only read on hover (at most 18 lookups), never on a timer.
local function SlotRepairCost(slot)
	if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
	local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
	if not ok or type(data) ~= "table" then return nil end
	local cost = data.repairCost
	if IsSecret(cost) or type(cost) ~= "number" or cost <= 0 then return nil end
	return cost
end

E:RegisterDataText("Durability", {
	events = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" },
	label = "Dur",
	icon = "Interface\\Minimap\\Tracking\\Repair",
	text = function()
		local lowest = 100
		for slot = 1, 18 do
			local current, maximum = GetInventoryItemDurability(slot)
			if current and maximum and maximum > 0 then
				lowest = math.min(lowest, current / maximum * 100)
			end
		end
		return DurabilityText(lowest)
	end,
	tooltip = function(tooltip)
		local any, totalCost = false, 0
		for slot = 1, 18 do
			local current, maximum = GetInventoryItemDurability(slot)
			if current and maximum and maximum > 0 and current < maximum then
				any = true
				local percent = current / maximum * 100
				local link = GetInventoryItemLink("player", slot) or L["Slot %d"]:format(slot)
				local right = DurabilityText(percent)
				local cost = SlotRepairCost(slot)
				if cost then
					totalCost = totalCost + cost
					right = CoinString(cost) .. "  " .. right
				end
				tooltip:AddDoubleLine(link, right, 1, 1, 1, 1, 1, 1)
			end
		end
		if not any then
			E.UIKit.TipText(tooltip, L["Nothing is damaged."])
		elseif totalCost > 0 then
			tooltip:AddLine(" ")
			E.UIKit.TipPair(tooltip, L["Repair cost"], CoinString(totalCost))
		end
	end,
	-- Opens the character window: out of combat only (M.ClickBlock).
	hint = { Key("Click"), Key("character window") },
	onClick = function()
		ToggleCharacter("PaperDollFrame")
	end,
})

---------------------------------------------------------------------------
-- Gold: every character from EldoUIDB.inventory, with filters and session
---------------------------------------------------------------------------
local session = { start = nil, last = nil, gained = 0, spent = 0 }
-- The session rates (Modules/InfoBar/Rates.lua) restore and reset it.
M.moneySession = session

-- The Gold datatext's characters and text.
local GoldData = {}

local GOLD_FILTERS = { "all", "realm", "current" }
GoldData.GOLD_FILTER_NAMES = E:TranslateValues({ all = E.Key("All characters"), realm = E.Key("This realm"), current = E.Key("This character") })

function GoldData.SplitCharKey(key)
	local name, realm = tostring(key):match("^(.-) %- (.+)$")
	return name or tostring(key), realm
end

-- Character list for the tooltip: { name, realm, class, money, current }.
function GoldData.GoldCharacters(filter)
	local list = {}
	local myRealm = GetRealmName()
	-- Every recorded character (Core/CharacterStore.lua); "This realm" is
	-- the ruleset on Forever.
	local store = E.Characters
	if filter ~= "current" and store and type(EldoUIDB) == "table" then
		for _, key in ipairs(store:Keys(filter == "realm" and "realm" or "account")) do
			local data = store:Get(key)
			if key ~= E.charKey and data and type(data.money) == "number" then
				local name, realm = GoldData.SplitCharKey(key)
				table.insert(list, { name = data.name or name, realm = data.realm or realm, class = data.class, money = data.money })
			end
		end
	end
	local _, class = UnitClass("player")
	table.insert(list, { name = E:PlayerName(), realm = myRealm, class = class, money = GetMoney(), current = true })
	table.sort(list, function(a, b) return a.money > b.money end)
	return list
end

-- Gold in the chosen format: whole gold, gold/silver/copper, or short (12.3k g).
-- Under one gold, every format shows the silver and copper, so a new
-- character's money counts from the first coin instead of staying at 0.
function GoldData.GoldText(money)
	local format = DB().goldFormat
	if format == "full" or money < 10000 then return CoinString(money) end
	if format == "short" then
		local gold = math.floor(money / 10000)
		local text = gold >= 1000 and E:FormatNumber(gold) or BreakUpLargeNumbers(gold)
		return text .. E:TokenHex(E.tokens.money.gold) .. "g|r"
	end
	return CoinString(money - money % 10000)
end

E:RegisterDataText("Gold", {
	events = { "PLAYER_MONEY" },
	icon = "Interface\\MoneyFrame\\UI-GoldIcon",
	text = function()
		return Value(GoldData.GoldText(GetMoney()))
	end,
	tooltip = function(tooltip)
		local filter = DB().goldFilter or "all"
		E.UIKit.TipText(tooltip, GoldData.GOLD_FILTER_NAMES[filter] or filter)
		local total = 0
		for _, char in ipairs(GoldData.GoldCharacters(filter)) do
			local r, g, b = 1, 1, 1
			local color = E:ClassColorObject(char.class)
			if color then r, g, b = color.r, color.g, color.b end
			local label = char.name
			if filter == "all" and char.realm and char.realm ~= GetRealmName() then label = label .. " - " .. char.realm end
			if char.current then label = label .. " *" end
			tooltip:AddDoubleLine(label, CoinString(char.money), r, g, b, 1, 1, 1)
			total = total + char.money
		end
		tooltip:AddLine(" ")
		tooltip:AddDoubleLine(L["Total"], CoinString(total), 1, 1, 1, 1, 1, 1)
		if session.start then
			local net = session.gained - session.spent
			E.UIKit.TipPair(tooltip, L["Session earned"], CoinString(session.gained), 0.27, 0.87, 0.27)
			E.UIKit.TipPair(tooltip, L["Session spent"], CoinString(session.spent), 1, 0.27, 0.27)
			local sign = net < 0 and "-" or "+"
			local nr, ng, nb = 0.27, 0.87, 0.27
			if net < 0 then nr, ng, nb = 1, 0.27, 0.27 end
			E.UIKit.TipPair(tooltip, L["Session net"], sign .. CoinString(math.abs(net)), nr, ng, nb)
		end
		local alts = E.modules.Characters
		E:TooltipHint(tooltip, { L["Click"], L["bags"] }, { L["Right-click"], L["change filter"] },
			alts and alts.active and { L["Shift-click"], L["Alts window"] } or nil)
	end,
	-- Opens a normal game window: works in combat too.
	combatClick = true,
	onClick = function(button, mouseButton)
		if mouseButton == "RightButton" then
			local db = DB()
			local index = tIndexOf(GOLD_FILTERS, db.goldFilter) or 1
			db.goldFilter = GOLD_FILTERS[index % #GOLD_FILTERS + 1]
			if button and button:IsMouseOver() then M.ShowTooltip(button) end
			return
		end
		-- Shift-click: the Alts window (Characters module).
		local alts = E.modules.Characters
		if IsShiftKeyDown() and alts and alts.active then
			alts:Toggle("overview")
			return
		end
		ToggleAllBags()
	end,
})

local function TrackMoney()
	local money = GetMoney()
	if not session.start then
		session.start, session.last = money, money
		return
	end
	local delta = money - session.last
	if delta > 0 then session.gained = session.gained + delta else session.spent = session.spent - delta end
	session.last = money
end

---------------------------------------------------------------------------
-- Bags: free / total
---------------------------------------------------------------------------
E:RegisterDataText("Bags", {
	events = { "BAG_UPDATE_DELAYED" },
	label = "Free",
	icon = "Interface\\Buttons\\Button-Backpack-Up",
	text = function()
		local free, total = 0, 0
		for _, bag in ipairs(E.BagCache:BagIDs()) do
			free = free + E.BagCache:Free(bag)
			total = total + E.BagCache:NumSlots(bag)
		end
		local kind = (total > 0 and free == 0) and "bad" or (free <= 4 and "warn") or nil
		return Status(kind, ("%d"):format(free)) .. Value("/" .. total)
	end,
	tooltip = function(tooltip)
		for _, bag in ipairs(E.BagCache:BagIDs()) do
			local slots = E.BagCache:NumSlots(bag)
			if slots > 0 then
				local free = E.BagCache:Free(bag)
				local name = bag == 0 and (BACKPACK_TOOLTIP or L["Backpack"]) or (C_Container.GetBagName and C_Container.GetBagName(bag)) or L["Bag %d"]:format(bag)
				tooltip:AddDoubleLine(name, L["%d/%d free"]:format(free, slots), 1, 1, 1, 1, 1, 1)
			end
		end
	end,
	-- Opens a normal game window: works in combat too.
	combatClick = true,
	hint = { Key("Click"), Key("open your bags") },
	onClick = function()
		ToggleAllBags()
	end,
})

---------------------------------------------------------------------------
-- Currencies: tracked (backpack) currencies, marked at their cap
---------------------------------------------------------------------------
-- Which cap a currency has reached: "total", "weekly" or nil.
local function CurrencyCap(info)
	if type(info) ~= "table" then return nil end
	local quantity = info.quantity or 0
	if (info.maxQuantity or 0) > 0 and quantity >= info.maxQuantity then return "total" end
	if (info.maxWeeklyQuantity or 0) > 0 and (info.quantityEarnedThisWeek or 0) >= info.maxWeeklyQuantity then return "weekly" end
	return nil
end

local function CurrencyAtCap(info)
	return CurrencyCap(info) ~= nil
end

local function CurrencyInfo(id)
	if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) or not id then return nil end
	local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
	return ok and info or nil
end

E:RegisterDataText("Currencies", {
	events = { "CURRENCY_DISPLAY_UPDATE", "HONOR_XP_UPDATE" },
	text = function()
		if not (C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo) then return Label(L["Currencies"]) end
		local parts = {}
		for index = 1, 3 do
			local watched = C_CurrencyInfo.GetBackpackCurrencyInfo(index)
			if not watched then break end
			local info = CurrencyInfo(watched.currencyTypesID)
			local amount = BreakUpLargeNumbers(watched.quantity or 0)
			local icon = watched.iconFileID and ("|T%s:0:0:0:0:64:64:5:59:5:59|t "):format(watched.iconFileID) or ""
			table.insert(parts, icon .. (CurrencyAtCap(info) and E:StatusText("bad", amount) or ("|cffffffff" .. amount .. "|r")))
		end
		if #parts == 0 then return Label(L["Currencies"]) end
		return table.concat(parts, "  ")
	end,
	tooltip = function(tooltip)
		if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize) then
			E.UIKit.TipText(tooltip, L["Not available in this client."])
			return
		end
		local shown = 0
		for index = 1, C_CurrencyInfo.GetCurrencyListSize() do
			local entry = C_CurrencyInfo.GetCurrencyListInfo(index)
			if entry and entry.isHeader then
				if shown > 0 then tooltip:AddLine(" ") end
				E.UIKit.TipText(tooltip, entry.name)
			elseif entry and entry.name then
				shown = shown + 1
				local cap = CurrencyCap(entry)
				local amount = BreakUpLargeNumbers(entry.quantity or 0)
				if (entry.maxQuantity or 0) > 0 then amount = amount .. " / " .. BreakUpLargeNumbers(entry.maxQuantity) end
				local icon = entry.iconFileID and ("|T%s:0|t "):format(entry.iconFileID) or ""
				-- A capped row says which cap, in words, with its mark.
				if cap == "weekly" then
					amount = E:StatusText("bad", L["%s (weekly cap)"]:format(amount))
				elseif cap then
					amount = E:StatusText("bad", L["%s (at the cap)"]:format(amount))
				end
				tooltip:AddDoubleLine(icon .. entry.name, amount, 1, 1, 1, 1, 1, 1)
			end
		end
		if shown == 0 then E.UIKit.TipText(tooltip, L["No currencies yet."]) end
		tooltip:AddLine(" ")
		E.UIKit.TipText(tooltip, L["Tick \"Show on backpack\" in the currency tab to show one here."])
	end,
	-- Opens the character window: out of combat only (M.ClickBlock).
	onClick = function()
		if ToggleCharacter and _G.TokenFrame then ToggleCharacter("TokenFrame") end
	end,
})

---------------------------------------------------------------------------
-- Hearthstone: bind location and cooldown. Clicking it uses the stone
-- through a secure overlay button (see M:SyncHearthOverlay).
---------------------------------------------------------------------------
local HEARTHSTONES = { 6948 }

local function HearthstoneID()
	for _, id in ipairs(HEARTHSTONES) do
		if (C_Item.GetItemCount(id) or 0) > 0 then return id end
	end
end

-- Seconds left on the cooldown, or 0 when ready. nil when unreadable.
local function HearthCooldown(id)
	if not id or not (C_Container and C_Container.GetItemCooldown) then return nil end
	local start, duration = C_Container.GetItemCooldown(id)
	if IsSecret(start) or IsSecret(duration) or not start or not duration then return nil end
	if start == 0 or duration <= 1.5 then return 0 end
	return math.max(0, start + duration - GetTime())
end

local function FormatTime(seconds)
	if seconds >= 3600 then return L["%dh %02dm"]:format(seconds / 3600, seconds % 3600 / 60) end
	return ("%d:%02d"):format(seconds / 60, seconds % 60)
end

E:RegisterDataText("Hearthstone", {
	poll = true,
	events = { "HEARTHSTONE_BOUND", "BAG_UPDATE_COOLDOWN" },
	label = "Hearth",
	icon = 134414,
	text = function()
		local id = HearthstoneID()
		local location = GetBindLocation() or "?"
		if not id then return GREY .. location .. "|r" end
		local left = HearthCooldown(id)
		if left and left > 0 then return YELLOW .. FormatTime(left) .. "|r" end
		return Value(location)
	end,
	tooltip = function(tooltip)
		local id = HearthstoneID()
		E.UIKit.TipPair(tooltip, L["Bound to"], GetBindLocation() or "?")
		if not id then
			tooltip:AddLine(L["No Hearthstone in your bags."], E:TokenColor("bad"))
			return
		end
		local left = HearthCooldown(id)
		if left and left > 0 then
			E.UIKit.TipPair(tooltip, L["Cooldown"], FormatTime(left), 1, 0.8, 0)
		elseif left then
			E.UIKit.TipPair(tooltip, L["Cooldown"], L["Ready"], 0.27, 0.87, 0.27)
		end
		tooltip:AddLine(" ")
		E:TooltipHint(tooltip, { L["Click"], L["use the Hearthstone"] })
	end,
})

E:RegisterDataText("Class", {
	events = { "PLAYER_LEVEL_UP" },
	text = function()
		local className = UnitClass("player")
		local r, g, b = E:ClassColor("player")
		return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, className or "")
			.. Value((" %d"):format(UnitLevel("player")))
	end,
	tooltip = function(tooltip)
		local className = UnitClass("player")
		local race = UnitRace and UnitRace("player")
		local r, g, b = E:ClassColor("player")
		tooltip:AddDoubleLine(UnitName("player") or "", className or "", 1, 1, 1, r, g, b)
		if race then E.UIKit.TipPair(tooltip, L["Race"], race) end
		E.UIKit.TipPair(tooltip, LEVEL or L["Level"], tostring(UnitLevel("player")))
	end,
	hint = { Key("Click"), Key("character window") },
	-- Opens the character window: out of combat only (M.ClickBlock).
	onClick = function()
		if ToggleCharacter then ToggleCharacter("PaperDollFrame") end
	end,
})

-- Friends and guild tooltips: who is online, in class color, with level
-- and zone (what the friends list and guild roster show).
local SOCIAL_ROWS = 20 -- at most this many names per list

-- Class color for a class file name ("MAGE") or a localized name ("Mage").
local function ClassHex(classFile, className)
	if not classFile and type(className) == "string" then
		for file, localized in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do
			if localized == className then classFile = file break end
		end
		if not classFile then
			for file, localized in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do
				if localized == className then classFile = file break end
			end
		end
	end
	if classFile and E.GetClassColor then
		local r, g, b = E:GetClassColor(classFile)
		if r then return Hex(r, g, b) end
	end
	local color = E:ClassColorObject(classFile)
	if color then return Hex(color.r, color.g, color.b) end
	return "|cffffffff"
end

-- A character name without the realm where the game would leave it out.
local function ShortName(name, context)
	if type(name) ~= "string" then return nil end
	local short = Ambiguate and Ambiguate(name, context)
	return (type(short) == "string" and short ~= "") and short or name
end

-- One "name  level · zone" row.
local function SocialRow(tooltip, name, classFile, className, level, zone)
	local left = ClassHex(classFile, className) .. (name or "?") .. "|r"
	if type(level) == "number" and level > 0 then left = left .. GREY .. (" %d"):format(level) .. "|r" end
	tooltip:AddDoubleLine(left, type(zone) == "string" and zone or "", 1, 1, 1, 0.65, 0.65, 0.65)
end

function M.FriendsTooltip(tooltip)
	local shown, more = 0, 0
	local list = C_FriendList
	local count = list and list.GetNumFriends and list.GetNumFriends() or 0
	local header = false
	for index = 1, count do
		local info = list.GetFriendInfoByIndex and list.GetFriendInfoByIndex(index)
		if type(info) == "table" and info.connected then
			if not header then
				E.UIKit.TipText(tooltip, L["Online"])
				header = true
			end
			if shown < SOCIAL_ROWS then
				shown = shown + 1
				SocialRow(tooltip, ShortName(info.name, "short"), nil, info.className, info.level, info.area)
			else
				more = more + 1
			end
		end
	end
	local bnetHeader = false
	if C_BattleNet and C_BattleNet.GetFriendAccountInfo then
		local total = E:BNetFriendCount()
		for index = 1, total do
			local account = C_BattleNet.GetFriendAccountInfo(index)
			local game = type(account) == "table" and account.gameAccountInfo
			if game and game.isOnline then
				if not bnetHeader then
					if header then tooltip:AddLine(" ") end
					E.UIKit.TipText(tooltip, "Battle.net") -- no-L: service name
					bnetHeader = true
				end
				if shown < SOCIAL_ROWS then
					shown = shown + 1
					local name = account.accountName or account.battleTag or "?"
					if game.characterName and game.characterName ~= "" then
						name = ("%s (%s)"):format(name, game.characterName)
					end
					local zone = game.areaName
					if (not zone or zone == "") and game.richPresence then zone = game.richPresence end
					SocialRow(tooltip, name, nil, game.className, game.characterLevel, zone)
				else
					more = more + 1
				end
			end
		end
	end
	if not header and not bnetHeader then E.UIKit.TipText(tooltip, L["No friends online."]) end
	if more > 0 then E.UIKit.TipText(tooltip, L["and %d more"]:format(more)) end
end

function M.GuildTooltip(tooltip)
	if not IsInGuild() then
		E.UIKit.TipText(tooltip, L["You are not in a guild."])
		return
	end
	-- Ask the server for a fresh roster (it throttles this itself); the
	-- list below updates on the next hover.
	if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
	local guildName, rankName = GetGuildInfo("player")
	if guildName then tooltip:AddDoubleLine("<" .. guildName .. ">", rankName or "", 1, 1, 1, 0.65, 0.65, 0.65) end
	-- The game blocks the guild message itself while chat is locked down
	-- (encounters, keys, PvP): it is left out then, not read and dropped.
	local motd = not E:CommRestricted() and C_GuildInfo and C_GuildInfo.GetMOTD and C_GuildInfo.GetMOTD()
	if type(motd) == "string" and motd ~= "" then
		tooltip:AddLine(" ")
		tooltip:AddLine(motd, E:TokenColor("good", true))
	end
	local total, online = GetNumGuildMembers()
	tooltip:AddLine(" ")
	E.UIKit.TipText(tooltip, L["Online %d of %d"]:format(online or 0, total or 0))
	local shown, more = 0, 0
	for index = 1, total or 0 do
		local name, _, _, level, className, zone, _, _, isOnline, _, classFile = GetGuildRosterInfo(index)
		if isOnline then
			if shown < SOCIAL_ROWS then
				shown = shown + 1
				SocialRow(tooltip, ShortName(name, "guild"), classFile, className, level, zone)
			else
				more = more + 1
			end
		end
	end
	if more > 0 then E.UIKit.TipText(tooltip, L["and %d more"]:format(more)) end
end

E:RegisterDataText("Friends", {
	events = { "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED" },
	label = "Friends",
	icon = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon",
	text = function()
		local online = C_FriendList.GetNumOnlineFriends() or 0
		if BNGetNumFriends then
			local _, bnetOnline = BNGetNumFriends()
			online = online + (tonumber(bnetOnline) or 0)
		end
		return Value(online)
	end,
	tooltip = function(tooltip) M.FriendsTooltip(tooltip) end,
	hint = { Key("Click"), Key("friends list") },
	-- Opens a normal game window: works in combat too.
	combatClick = true,
	onClick = function()
		ToggleFriendsFrame(1)
	end,
})

E:RegisterDataText("Guild", {
	events = { "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" },
	label = "Guild",
	icon = "Interface\\GossipFrame\\TabardGossipIcon",
	text = function()
		if not IsInGuild() then return GREY .. L["none"] .. "|r" end
		local _, online = GetNumGuildMembers()
		return Value(online or 0)
	end,
	tooltip = function(tooltip) M.GuildTooltip(tooltip) end,
	hint = { Key("Click"), Key("guild window") },
	-- Opens a normal game window: works in combat too.
	combatClick = true,
	onClick = function()
		if ToggleGuildFrame then ToggleGuildFrame() end
	end,
})

E:RegisterDataText("Profession", {
	events = { "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE" },
	text = function()
		if not GetProfessions then return "" end
		local first = GetProfessions()
		if not first then return Label(L["No profession"]) end
		local name, _, rank, maxRank = GetProfessionInfo(first)
		return Label(name .. " ") .. Value(("%d/%d"):format(rank, maxRank))
	end,
	tooltip = function(tooltip)
		if not GetProfessions then return end
		-- Any slot may be empty, so walk all five instead of stopping at a gap.
		local slots = { GetProfessions() }
		for slot = 1, 5 do
			local index = slots[slot]
			if index then
				local name, _, rank, maxRank = GetProfessionInfo(index)
				tooltip:AddDoubleLine(name, ("%d/%d"):format(rank, maxRank), 1, 1, 1, 1, 1, 1)
			end
		end
	end,
	-- The hint only shows when the game has the professions book to open.
	hint = function() return ToggleProfessionsBook and { L["Click"], L["professions book"] } or nil end,
	onClick = function()
		if ToggleProfessionsBook then ToggleProfessionsBook() end
	end,
})


---------------------------------------------------------------------------
-- Progress datatexts: XP, reputation and honor. Not combat
-- data; values are still checked for secrets before any math.
---------------------------------------------------------------------------
local function Plain(value)
	if IsSecret(value) or type(value) ~= "number" then return nil end
	return value
end

local function Percent(value, maximum)
	if not value or not maximum or maximum <= 0 then return 0 end
	return value / maximum * 100
end

E:RegisterDataText("XP", {
	events = { "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "DISABLE_XP_GAIN", "ENABLE_XP_GAIN" },
	text = function()
		if E:AtMaxLevel() then return Label(L["Level"] .. " ") .. Value(UnitLevel("player")) end
		local current, maximum = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
		if not current or not maximum then return Label(L["XP"]) end
		local text = Label(L["XP"] .. " ") .. Value(("%.1f%%"):format(Percent(current, maximum)))
		local rested = Plain(GetXPExhaustion and GetXPExhaustion())
		if rested and rested > 0 then text = text .. "  " .. E:TokenHex(E.tokens.bar.rested) .. L["R %.0f%%"]:format(Percent(rested, maximum)) .. "|r" end
		return text
	end,
	tooltip = function(tooltip)
		local level = UnitLevel("player")
		E.UIKit.TipPair(tooltip, LEVEL or L["Level"], tostring(level))
		if E:AtMaxLevel() then
			E.UIKit.TipText(tooltip, L["You are at the level cap."])
			return
		end
		local current, maximum = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
		if not current or not maximum then return end
		E.UIKit.TipPair(tooltip, L["XP"], ("%s / %s"):format(BreakUpLargeNumbers(current), BreakUpLargeNumbers(maximum)))
		E.UIKit.TipPair(tooltip, L["To level %d"]:format(level + 1), BreakUpLargeNumbers(maximum - current))
		local rested = Plain(GetXPExhaustion and GetXPExhaustion())
		if rested and rested > 0 then
			E.UIKit.TipPair(tooltip, L["Rested"], ("%s (%.0f%%)"):format(BreakUpLargeNumbers(rested), Percent(rested, maximum)), 0.56, 0.72, 1)
		end
		if IsXPUserDisabled and IsXPUserDisabled() then tooltip:AddLine(L["XP gain is switched off."], E:TokenColor("bad")) end
	end,
	hint = { Key("Click"), Key("character window") },
	-- Opens the character window: out of combat only (M.ClickBlock).
	onClick = function()
		if ToggleCharacter then ToggleCharacter("PaperDollFrame") end
	end,
})

local function WatchedFaction()
	if not (C_Reputation and C_Reputation.GetWatchedFactionData) then return nil end
	local faction = C_Reputation.GetWatchedFactionData()
	if not faction or not faction.name or faction.name == "" then return nil end
	return faction
end

E:RegisterDataText("Reputation", {
	events = { "UPDATE_FACTION" },
	text = function()
		local faction = WatchedFaction()
		if not faction then return Label(L["Reputation"]) end
		local low, high, value = Plain(faction.currentReactionThreshold), Plain(faction.nextReactionThreshold), Plain(faction.currentStanding)
		local name = faction.name
		if E:Utf8Len(name) > 18 then name = E:Utf8Sub(name, 16) .. ".." end
		local color = "|cffffffff"
		local c = E:ReactionColorObject(faction.reaction)
		if c then
			color = ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
		end
		if not low or not high or not value or high <= low then return Label(name .. " ") .. color .. L["max"] .. "|r" end
		return Label(name .. " ") .. color .. ("%.0f%%"):format(Percent(value - low, high - low)) .. "|r"
	end,
	tooltip = function(tooltip)
		local faction = WatchedFaction()
		if not faction then
			E.UIKit.TipText(tooltip, L["No faction watched."])
			E.UIKit.TipText(tooltip, L["Tick \"Show as experience bar\" in the reputation list."])
			return
		end
		local standing = _G["FACTION_STANDING_LABEL" .. tostring(faction.reaction)] or ""
		tooltip:AddDoubleLine(faction.name, standing, 1, 1, 1, 1, 1, 1)
		local low, high, value = Plain(faction.currentReactionThreshold), Plain(faction.nextReactionThreshold), Plain(faction.currentStanding)
		if low and high and value and high > low then
			E.UIKit.TipPair(tooltip, L["Progress"], ("%s / %s"):format(BreakUpLargeNumbers(value - low), BreakUpLargeNumbers(high - low)))
		end
		tooltip:AddLine(" ")
		E:TooltipHint(tooltip, { L["Click"], L["open the reputation list"] })
	end,
	-- Opens the character window: out of combat only (M.ClickBlock).
	onClick = function()
		if ToggleCharacter then ToggleCharacter("ReputationFrame") end
	end,
})

-- Honor: Forever's honor points and the most you can hold.
local HONOR_IDS = { Constants and Constants.CurrencyConsts and Constants.CurrencyConsts.CLASSIC_HONOR_CURRENCY_ID,
	Constants and Constants.CurrencyConsts and Constants.CurrencyConsts.HONOR_CURRENCY_ID }

local function HonorCurrency()
	for _, id in ipairs(HONOR_IDS) do
		local info = id and CurrencyInfo(id)
		if info and info.name and info.name ~= "" then return info end
	end
end

E:RegisterDataText("Honor", {
	events = { "CURRENCY_DISPLAY_UPDATE" },
	text = function()
		local info = HonorCurrency()
		local amount = info and Plain(info.quantity)
		if amount then return Label((HONOR or L["Honor"]) .. " ") .. Value(BreakUpLargeNumbers(amount)) end
		return Label(HONOR or L["Honor"])
	end,
	tooltip = function(tooltip)
		local info = HonorCurrency()
		if info then
			local amount = BreakUpLargeNumbers(Plain(info.quantity) or 0)
			local cap = Plain(info.maxQuantity) or 0
			if cap > 0 then amount = amount .. " / " .. BreakUpLargeNumbers(cap) end
			tooltip:AddDoubleLine(info.name, amount, 1, 1, 1, 1, 1, 1)
		else
			E.UIKit.TipText(tooltip, L["No honor yet."])
		end
		-- The Loot Guide's PvP planner, when that module is on.
		local guide = E.LootGuide
		if guide and guide.active and guide.PvPTooltipLine then guide:PvPTooltipLine(tooltip) end
	end,
	hint = { Key("Click"), Key("PvP tab") },
	onClick = function()
		local guide = E.LootGuide
		if IsShiftKeyDown() and guide and guide.active and guide.OpenSection then
			guide:OpenSection("pvp")
			return
		end
		E:OpenPvPPage()
	end,
})

---------------------------------------------------------------------------
-- Place: zone, coordinates, speed
---------------------------------------------------------------------------
local function ZoneColorCode()
	local pvpType = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo()
	if pvpType == "sanctuary" then return E:TextHex("accent") end
	if pvpType == "friendly" then return E:TextHex("good") end
	if pvpType == "hostile" then return E:TextHex("bad") end
	if pvpType == "contested" then return E:TextHex("warn") end
	return "|cffffffff"
end

E:RegisterDataText("Zone", {
	events = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" },
	text = function()
		local text = GetMinimapZoneText and GetMinimapZoneText() or GetZoneText()
		return ZoneColorCode() .. (text or "") .. "|r"
	end,
	tooltip = function(tooltip)
		E.UIKit.TipPair(tooltip, L["Zone"], GetRealZoneText() or "")
		local sub = GetSubZoneText()
		if sub and sub ~= "" then E.UIKit.TipPair(tooltip, L["Area"], sub) end
		local pvpType, faction
		if C_PvP and C_PvP.GetZonePVPInfo then
			local _
			pvpType, _, faction = C_PvP.GetZonePVPInfo()
		end
		if pvpType then E.UIKit.TipPair(tooltip, L["Status"], faction and (pvpType .. " (" .. faction .. ")") or pvpType) end
		tooltip:AddLine(" ")
		E:TooltipHint(tooltip, { L["Click"], L["world map"] })
	end,
	-- A click on the block goes through the game's own map button (a secure
	-- overlay, so the game opens it, in combat too). This runs only from
	-- the "»" menu or without that button, and only out of combat.
	onClick = function()
		if ToggleWorldMap then ToggleWorldMap() end
	end,
})

-- Coordinates are nil inside instances: then "--", never a guess.
local function PlayerCoords()
	local mapID = C_Map and C_Map.GetBestMapForUnit("player")
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not position then return nil end
	local x, y = position:GetXY()
	if IsSecret(x) or IsSecret(y) or not x or not y or (x == 0 and y == 0) then return nil end
	return x * 100, y * 100
end

-- The coordinate format per precision setting, made once.
M.coordPatterns = {}

E:RegisterDataText("Coords", {
	title = "Coordinates",
	poll = true,
	interval = 0.2,
	text = function()
		local x, y = PlayerCoords()
		if not x then return GREY .. "--, --|r" end
		local decimals = DB().coordDecimals or 1
		local patterns = M.coordPatterns
		local pattern = patterns[decimals]
		if not pattern then
			pattern = ("%%.%df, %%.%df"):format(decimals, decimals)
			patterns[decimals] = pattern
		end
		return Value(pattern:format(x, y))
	end,
	tooltip = function(tooltip)
		E.UIKit.TipPair(tooltip, L["Zone"], GetRealZoneText() or "")
		if not PlayerCoords() then E.UIKit.TipText(tooltip, L["The game gives no position here."]) end
		tooltip:AddLine(" ")
		E:TooltipHint(tooltip, { L["Click"], L["world map"] })
	end,
	-- A click on the block goes through the game's own map button (a secure
	-- overlay, so the game opens it, in combat too). This runs only from
	-- the "»" menu or without that button, and only out of combat.
	onClick = function()
		if ToggleWorldMap then ToggleWorldMap() end
	end,
})

E:RegisterDataText("Speed", {
	poll = true,
	interval = 0.5,
	label = "Speed",
	text = function()
		local speed = GetUnitSpeed and GetUnitSpeed("player")
		if IsSecret(speed) or not speed then return GREY .. "--|r" end
		return Value(("%d%%"):format(speed / (BASE_MOVEMENT_SPEED or 7) * 100 + 0.5))
	end,
	tooltip = function(tooltip)
		if not GetUnitSpeed then return end
		local current, run, flight, swim = GetUnitSpeed("player")
		local base = BASE_MOVEMENT_SPEED or 7
		local function Row(label, speed)
			if type(speed) ~= "number" or IsSecret(speed) then return end
			E.UIKit.TipPair(tooltip, label, ("%d%%"):format(speed / base * 100 + 0.5))
		end
		Row(L["Now"], current)
		Row(L["Running"], run)
		Row(L["Swimming"], swim)
		if type(flight) == "number" and not IsSecret(flight) and flight > 0 then Row(L["Flying"], flight) end
		tooltip:AddLine(" ")
		E.UIKit.TipText(tooltip, L["100% is normal running speed."])
	end,
	hint = { Key("Click"), Key("character window") },
	-- Opens the character window: out of combat only (M.ClickBlock).
	onClick = function()
		if ToggleCharacter then ToggleCharacter("PaperDollFrame") end
	end,
})

---------------------------------------------------------------------------
-- Spec, item level, played time
---------------------------------------------------------------------------
-- Mail: Modules/InfoBar/Mail.lua (every character's saved mail).

local function SpecName()
	local info = C_SpecializationInfo
	if info and info.GetSpecialization and info.GetSpecializationInfo then
		local ok, index = pcall(info.GetSpecialization)
		if ok and index and index > 0 then
			local ok2, _, name, _, icon = pcall(info.GetSpecializationInfo, index)
			if ok2 and name then return name, icon end
		end
	end
	local group = info and info.GetActiveSpecGroup and info.GetActiveSpecGroup()
	if group then return (TALENTS or L["Talents"]) .. " " .. group end
end

-- Talent Planner (T7): Shift-click opens it, the tooltip names the
-- plan's next point while the module is on.
local function TalentPlanner()
	local planner = E.Talents
	return planner and planner.active and planner or nil
end

local function TalentPlannerTooltip(tooltip)
	local planner = TalentPlanner()
	if not planner then return end
	local unspent = planner:Unspent()
	if unspent > 0 then E.UIKit.TipPair(tooltip, L["Unspent points"], unspent) end
	local step = planner:NextStep()
	if step then E.UIKit.TipPair(tooltip, L["Next in your plan"], planner:StepText(step)) end
end

E:RegisterDataText("Spec", {
	events = { "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_LOOT_SPEC_UPDATED", "PLAYER_LEVEL_UP" },
	text = function()
		local name, icon = SpecName()
		if not name then return Label(TALENTS or L["Talents"]) end
		local iconText = icon and ("|T%s:0:0:0:0:64:64:5:59:5:59|t "):format(icon) or ""
		return iconText .. Value(name)
	end,
	tooltip = function(tooltip)
		local name = SpecName()
		E.UIKit.TipPair(tooltip, L["Active"], name or "-")
		if GetLootSpecialization and C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
			local lootSpec = GetLootSpecialization()
			local lootName
			if lootSpec and lootSpec > 0 and GetSpecializationInfoByID then lootName = select(2, GetSpecializationInfoByID(lootSpec)) end
			E.UIKit.TipPair(tooltip, L["Loot"], lootName or L["Current (%s)"]:format(name or "-"))
		end
		TalentPlannerTooltip(tooltip)
		tooltip:AddLine(" ")
		E:TooltipHint(tooltip, { L["Click"], L["talents"] })
		if TalentPlanner() then E:TooltipHint(tooltip, { L["Shift-click"], L["Talent Planner"] }) end
	end,
	onClick = function()
		if IsShiftKeyDown() and TalentPlanner() then
			TalentPlanner():TogglePlanner()
			return
		end
		local button = _G.TalentMicroButton
		if button and button:IsEnabled() then button:Click() end
	end,
})

E:RegisterDataText("ItemLevel", {
	title = "Item level",
	events = { "PLAYER_AVG_ITEM_LEVEL_UPDATE", "PLAYER_EQUIPMENT_CHANGED" },
	label = "iLvl",
	text = function()
		if not GetAverageItemLevel then return GREY .. "--|r" end
		local _, equipped = GetAverageItemLevel()
		equipped = Plain(equipped)
		if not equipped then return GREY .. "--|r" end
		return Value(("%.1f"):format(equipped))
	end,
	tooltip = function(tooltip)
		if not GetAverageItemLevel then return end
		local overall, equipped = GetAverageItemLevel()
		if Plain(equipped) then E.UIKit.TipPair(tooltip, L["Equipped"], ("%.1f"):format(equipped)) end
		if Plain(overall) then E.UIKit.TipPair(tooltip, L["Best in bags"], ("%.1f"):format(overall)) end
	end,
	-- Opens the character window: out of combat only (M.ClickBlock).
	onClick = function()
		ToggleCharacter("PaperDollFrame")
	end,
})

-- Played time: this session from the clock, totals from the last
-- TIME_PLAYED_MSG (which the game sends after /played or a click here).
local sessionStart = GetTime()
local played = {}

local function FormatDuration(seconds) return E:FormatDuration(seconds, "long") end

E:RegisterDataText("Played", {
	poll = true,
	interval = 30,
	label = "Session",
	text = function()
		return Value(FormatDuration(GetTime() - sessionStart))
	end,
	tooltip = function(tooltip)
		E.UIKit.TipPair(tooltip, L["This session"], FormatDuration(GetTime() - sessionStart))
		if played.total then
			local since = GetTime() - played.at
			E.UIKit.TipPair(tooltip, L["Total"], FormatDuration(played.total + since))
			E.UIKit.TipPair(tooltip, L["This level"], FormatDuration(played.level + since))
		else
			E:TooltipHint(tooltip, { L["Click"], L["ask the game for your total time (also shown in chat)"] })
		end
	end,
	-- Opens a normal game window: works in combat too.
	combatClick = true,
	onClick = function()
		-- Ctrl-click: the level log in the Alts window.
		local alts = E.modules.Characters
		if IsControlKeyDown() and alts and alts.active then
			alts:Open("levels")
			return
		end
		if RequestTimePlayed then RequestTimePlayed() end
	end,
})

---------------------------------------------------------------------------
-- Alts (Characters module): your characters from the character
-- store (Core/CharacterStore.lua).
---------------------------------------------------------------------------
local function AltsModule()
	local module = E.modules.Characters
	return module and module.active and module or nil
end

E:RegisterDataText("Alts", {
	events = { "PLAYER_MONEY", "PLAYER_LEVEL_UP" },
	label = "Alts",
	icon = "Interface\\Icons\\INV_Misc_Head_Human_01",
	text = function()
		local module = AltsModule()
		local store = E.Characters
		if not (module and store) then return Value("-") end
		local keys = module:Keys()
		if module.db.datatext == "gold" then
			local gold = 0
			for _, key in ipairs(keys) do gold = gold + (store:Get(key).money or 0) end
			return Value(module.Money(gold, true))
		end
		return Value(tostring(#keys))
	end,
	tooltip = function(tooltip)
		local module = AltsModule()
		local store = E.Characters
		if not (module and store) then
			E.UIKit.TipText(tooltip, L["Turn on the Alts module (Items and Economy) to list your characters here."])
			return
		end
		local total = 0
		for _, key in ipairs(store:Keys("realm")) do
			local record = store:Get(key)
			total = total + (record.money or 0)
			local r, g, b = module.ClassColor(record.class)
			local right = ("%d  %s"):format(record.level or 0, module.Money(record.money, true))
			local pct, estimated = module.RestedPercent(record)
			if pct and (record.level or 0) < store.MaxLevel() then right = ("%s  %s"):format(right, module.Accent(("%s%d%%"):format(estimated and "~" or "", pct))) end
			local locks = module.LockoutCount(record)
			if locks > 0 then right = ("%s  %s"):format(right, module.Grey((locks == 1 and L["%d lock"] or L["%d locks"]):format(locks))) end
			tooltip:AddDoubleLine(("%s %s"):format(record.name or key, module.Grey(module.Ago(record))), right, r, g, b, 1, 1, 1)
		end
		tooltip:AddLine(" ")
		tooltip:AddDoubleLine(L["Total"], module.Money(total, true), 1, 1, 1, 1, 1, 1)
		E:TooltipHint(tooltip, { L["Click"], L["Alts window"] }, { L["Right-click"], L["agenda"] })
	end,
	onClick = function(_, mouseButton)
		local module = AltsModule()
		if not module then
			E:Print(E:ModuleOffHint("Characters"))
			return
		end
		if mouseButton == "RightButton" then
			module:Open("agenda")
		else
			module:Toggle()
		end
	end,
})

---------------------------------------------------------------------------
-- Performance: memory and CPU of addons (the game's own counters)
---------------------------------------------------------------------------
local function FormatMemory(kb)
	if kb >= 1024 then return ("%.1f MB"):format(kb / 1024) end
	return ("%.0f KB"):format(kb)
end

local function Loaded(index)
	return C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(index)
end

-- Every loaded addon with its memory in KB, largest first, and the total.
local function AddOnMemory()
	local list, total = {}, 0
	if not (GetAddOnMemoryUsage and C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetAddOnInfo) then return list, total end
	for index = 1, C_AddOns.GetNumAddOns() do
		if Loaded(index) then
			local name = C_AddOns.GetAddOnInfo(index)
			local kb = tonumber(GetAddOnMemoryUsage(index)) or 0
			total = total + kb
			list[#list + 1] = { name = name, value = kb }
		end
	end
	table.sort(list, function(a, b)
		if a.value ~= b.value then return a.value > b.value end
		return tostring(a.name) < tostring(b.name)
	end)
	return list, total
end

-- EldoUI and its plugin folders (EldoUI_*) together.
local function OwnShare(list)
	local own = 0
	for _, entry in ipairs(list) do
		local name = tostring(entry.name or "")
		if name == E.name or name:find("^EldoUI_") then own = own + entry.value end
	end
	return own
end

-- The game's addon profiler (always on in the client) or, when the player
-- turned on script profiling, the older per-addon CPU counters.
local function Profiler()
	local profiler = C_AddOnProfiler
	if not (profiler and profiler.IsEnabled and profiler.IsEnabled()) then return nil end
	if not (Enum and Enum.AddOnProfilerMetric) then return nil end
	return profiler
end

local function ScriptProfiling()
	if not (GetAddOnCPUUsage and UpdateAddOnCPUUsage and C_CVar and C_CVar.GetCVar) then return false end
	return C_CVar.GetCVar("scriptProfile") == "1"
end

-- Top addons by CPU: { name, text } rows, or nil when no counter runs.
local function CPURows(limit)
	local profiler = Profiler()
	if profiler and profiler.GetTopKAddOnsForMetric then
		local rows = {}
		for _, entry in ipairs(profiler.GetTopKAddOnsForMetric(Enum.AddOnProfilerMetric.RecentAverageTime, limit) or {}) do
			rows[#rows + 1] = { name = entry.addOnName, text = ("%.3f ms"):format(tonumber(entry.metricValue) or 0) } -- no-L: unit only
		end
		return rows, L["CPU, average per frame"]
	end
	if ScriptProfiling() then
		UpdateAddOnCPUUsage()
		local list = {}
		for index = 1, C_AddOns.GetNumAddOns() do
			if Loaded(index) then
				list[#list + 1] = { name = C_AddOns.GetAddOnInfo(index), value = tonumber(GetAddOnCPUUsage(index)) or 0 }
			end
		end
		table.sort(list, function(a, b) return a.value > b.value end)
		local rows = {}
		for index = 1, math.min(#list, limit) do
			rows[index] = { name = list[index].name, text = ("%.0f ms"):format(list[index].value) } -- no-L: unit only
		end
		return rows, L["CPU since login"]
	end
	return nil
end

-- A shown tooltip redraws on a slow timer while the mouse stays on its block.
-- Owners with a redraw queued live in a table of their own: the owner can
-- be one of Blizzard's frames, which takes no fields from addons.
local MEMORY_REFRESH = 5
local refreshQueued = setmetatable({}, { __mode = "k" })
local function RefreshWhileShown(tooltip)
	local owner = tooltip.GetOwner and tooltip:GetOwner()
	if not owner or refreshQueued[owner] or not (C_Timer and C_Timer.After) then return end
	refreshQueued[owner] = true
	C_Timer.After(MEMORY_REFRESH, function()
		refreshQueued[owner] = nil
		if tooltip:IsShown() and tooltip:GetOwner() == owner and owner:IsMouseOver() then M.ShowTooltip(owner) end
	end)
end

-- One reading of every addon's memory, shared by the bar text and the
-- tooltip so both show the same total. Reading each addon's share is slow,
-- so it runs at most once per bar poll (and after a click frees memory),
-- never on its own in combat; the tooltip's redraws read the kept copy.
local memorySnapshot = { list = {}, total = 0, own = 0, poll = 30 }
function memorySnapshot.Read(force)
	local snapshot, now = memorySnapshot, GetTime()
	local due = not snapshot.time or now - snapshot.time >= snapshot.poll - 1
	if force or (due and not InCombatLockdown()) then
		if UpdateAddOnMemoryUsage then UpdateAddOnMemoryUsage() end
		local list, total = AddOnMemory()
		snapshot.list, snapshot.total, snapshot.own, snapshot.time = list, total, OwnShare(list), now
	end
	return snapshot
end

-- The bar shows the total of all addons, the same number as the tooltip's
-- All addons line; without the game's per-addon counters, the Lua total.
E:RegisterDataText("Memory", {
	title = "Addon memory",
	poll = true,
	interval = memorySnapshot.poll,
	label = "Mem",
	text = function()
		local snapshot = memorySnapshot.Read()
		if #snapshot.list == 0 then return Value(FormatMemory(collectgarbage("count"))) end
		return Value(FormatMemory(snapshot.total))
	end,
	tooltip = function(tooltip)
		local snapshot = memorySnapshot.Read()
		local list, total = snapshot.list, snapshot.total
		for index = 1, math.min(#list, 10) do
			tooltip:AddDoubleLine(list[index].name, FormatMemory(list[index].value), 1, 1, 1, 1, 1, 1)
		end
		tooltip:AddLine(" ")
		E.UIKit.TipPair(tooltip, L["All addons"], FormatMemory(total))
		if #list > 0 then E.UIKit.TipPair(tooltip, L["EldoUI"], FormatMemory(snapshot.own)) end
		local rows, title = CPURows(5)
		if rows then
			tooltip:AddLine(" ")
			E.UIKit.TipText(tooltip, title)
			for _, row in ipairs(rows) do tooltip:AddDoubleLine(row.name, row.text, 1, 1, 1, 1, 1, 1) end
		end
		E:TooltipHint(tooltip, { L["Click"], L["free unused memory"] })
		RefreshWhileShown(tooltip)
	end,
	onClick = function(button)
		collectgarbage("collect")
		memorySnapshot.Read(true)
		if button and M.UpdateButton then M.UpdateButton(button) end
		if button and button:IsMouseOver() then M.ShowTooltip(button) end
	end,
})

E:RegisterDataText("CPU", {
	poll = true,
	interval = 2,
	label = "CPU",
	text = function()
		local profiler = Profiler()
		if not profiler then return GREY .. L["off"] .. "|r" end
		local ms = profiler.GetOverallMetric(Enum.AddOnProfilerMetric.RecentAverageTime) or 0
		local db = DB()
		local kind = ms >= (db.cpuBad or 5) and "bad" or (ms >= (db.cpuWarn or 2) and "warn" or nil)
		return Status(kind, ("%.2f"):format(ms)) .. GREY .. "ms|r"
	end,
	tooltip = function(tooltip)
		local profiler = Profiler()
		if not profiler then
			E.UIKit.TipText(tooltip, L["The game's addon profiler is not available."])
			return
		end
		local metric = Enum.AddOnProfilerMetric.RecentAverageTime
		E.UIKit.TipText(tooltip, L["Average time per frame, last 60 frames"])
		local top = profiler.GetTopKAddOnsForMetric and profiler.GetTopKAddOnsForMetric(metric, 12) or {}
		for _, entry in ipairs(top) do
			tooltip:AddDoubleLine(entry.addOnName, ("%.3f ms"):format(entry.metricValue or 0), 1, 1, 1, 1, 1, 1) -- no-L: unit only
		end
		tooltip:AddLine(" ")
		E.UIKit.TipPair(tooltip, L["All addons"], ("%.2f ms"):format(profiler.GetOverallMetric(metric) or 0))
		if profiler.GetApplicationMetric then
			E.UIKit.TipPair(tooltip, L["Whole game"], ("%.2f ms"):format(profiler.GetApplicationMetric(metric) or 0))
		end
		E.UIKit.TipPair(tooltip, L["Addon Lua memory"], FormatMemory(collectgarbage("count")))
	end,
	hint = { Key("Click"), Key("the addon list") },
	onClick = function()
		if AddonList and ShowUIPanel then
			if AddonList:IsShown() then HideUIPanel(AddonList) else ShowUIPanel(AddonList) end
		end
	end,
})

---------------------------------------------------------------------------
-- More datatexts. Every one shows data the game gives every addon,
-- or our own timer between two events (combat time).
---------------------------------------------------------------------------
local function Refresh(button)
	if button and M.UpdateButton then M.UpdateButton(button) end
	if button and button:IsMouseOver() then M.ShowTooltip(button) end
end

local function GreyHint(tooltip, text)
	tooltip:AddLine(" ")
	E.UIKit.TipText(tooltip, text)
end

-- A value that may be secret, ready for string.format: nil becomes "–".
-- Only type() is asked; a secret is never compared or tested.
local DASH = "–"
local function Shown(value)
	if type(value) == "nil" then return DASH end
	return value
end

-- The result may be a secret string: test it with Missing(), never with
-- `if text` or `text or x`.
local function SafeFormat(pattern, ...)
	local ok, text = pcall(string.format, pattern, ...)
	if ok then return text end
end

local function Missing(value)
	return type(value) == "nil"
end

local function OpenCalendar()
	if not C_AddOns.IsAddOnLoaded("Blizzard_Calendar") then C_AddOns.LoadAddOn("Blizzard_Calendar") end
	if ToggleCalendar then ToggleCalendar() end
end

-- Date --------------------------------------------------------------------
local DATE_FORMATS = { dmy = "%d.%m.%Y", mdy = "%m/%d/%Y", iso = "%Y-%m-%d" }

E:RegisterDataText("Date", {
	poll = true,
	interval = 30,
	text = function()
		-- "long" names the weekday and month in the client language.
		if DB().dateFormat == "long" then
			local now = time()
			return Value(E:WeekdayName(date("*t", now).wday, true) .. " " .. E:ShortDay(now))
		end
		return Value(date(DATE_FORMATS[DB().dateFormat] or DATE_FORMATS.dmy))
	end,
	tooltip = function(tooltip)
		E.UIKit.TipTitle(tooltip, E:LongDay(time(), true))
		E.UIKit.TipText(tooltip, L["The date format is on the Datatexts tab."])
		E:TooltipHint(tooltip, { L["Click"], L["calendar"] })
	end,
	-- Opens a normal game window: works in combat too.
	combatClick = true,
	onClick = OpenCalendar,
})

-- Combat time and the in-combat indicator -------------------------------
-- The fight length comes from E:GetCombatTime (CombatHUD/DamageMeter.lua):
-- Blizzard's meter session when it has one, else the player's own combat
-- state. A small own timer covers a client without that file.
local ownCombat = { start = nil, last = 0 }

function M:TrackCombat(inCombat)
	if inCombat then
		ownCombat.start = GetTime()
	elseif ownCombat.start then
		ownCombat.last = GetTime() - ownCombat.start
		ownCombat.start = nil
	end
end

local function CombatSeconds()
	if E.GetCombatTime then
		local ok, seconds, inCombat = pcall(E.GetCombatTime, E)
		if ok and type(seconds) == "number" and not IsSecret(seconds) then return seconds, inCombat end
	end
	local inCombat = ownCombat.start ~= nil
	return inCombat and (GetTime() - ownCombat.start) or ownCombat.last, inCombat
end

local function CombatClock(seconds)
	if E.FormatCombatTime then return E:FormatCombatTime(seconds) end
	return E:FormatDuration(seconds, "minutes")
end

E:RegisterDataText("CombatTime", {
	title = "Combat time",
	label = "Fight",
	poll = true,
	interval = 0.5,
	events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" },
	text = function()
		local seconds, inCombat = CombatSeconds()
		if inCombat then return ("%s%s|r"):format(YELLOW, CombatClock(seconds)) end
		return Value(CombatClock(seconds))
	end,
	tooltip = function(tooltip)
		local seconds, inCombat = CombatSeconds()
		E.UIKit.TipPair(tooltip, inCombat and L["This fight"] or L["Last fight"], CombatClock(seconds))
		GreyHint(tooltip, L["Time since you entered combat; after the fight the last fight's length stays. The same timer as the Combat HUD's combat timer."])
	end,
})

E:RegisterDataText("Combat", {
	title = "In combat",
	poll = true,
	interval = 0.5,
	events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" },
	text = function()
		if InCombatLockdown() then return RED .. L["In combat"] .. "|r" end
		return GREY .. L["Out of combat"] .. "|r"
	end,
	tooltip = function(tooltip)
		E.UIKit.TipTitle(tooltip, InCombatLockdown() and L["You are in combat."] or L["You are out of combat."])
	end,
})

-- Instance difficulty -----------------------------------------------------
local function DifficultyName(id)
	if not (id and GetDifficultyInfo) then return nil end
	local name = GetDifficultyInfo(id)
	if type(name) == "string" and name ~= "" then return name end
end

E:RegisterDataText("Difficulty", {
	title = "Instance difficulty",
	events = { "PLAYER_DIFFICULTY_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE" },
	text = function()
		local name, instanceType, difficultyID, difficultyName = GetInstanceInfo()
		if not instanceType or instanceType == "none" then
			local chosen = DifficultyName(GetDungeonDifficultyID and GetDungeonDifficultyID())
			return GREY .. (chosen or L["World"]) .. "|r"
		end
		if type(difficultyName) == "string" and difficultyName ~= "" then return Value(difficultyName) end
		return Value(DifficultyName(difficultyID) or name or "?")
	end,
	tooltip = function(tooltip)
		local name, instanceType, difficultyID, difficultyName, maxPlayers = GetInstanceInfo()
		if not instanceType or instanceType == "none" then
			E.UIKit.TipText(tooltip, L["Not in an instance."])
			local dungeon = DifficultyName(GetDungeonDifficultyID and GetDungeonDifficultyID())
			local raid = DifficultyName(GetRaidDifficultyID and GetRaidDifficultyID())
			if dungeon then E.UIKit.TipPair(tooltip, L["Dungeon difficulty"], dungeon) end
			if raid then E.UIKit.TipPair(tooltip, L["Raid difficulty"], raid) end
			return
		end
		E.UIKit.TipPair(tooltip, L["Instance"], name or "?")
		E.UIKit.TipPair(tooltip, L["Difficulty"], (difficultyName ~= "" and difficultyName) or DifficultyName(difficultyID) or "?")
		if type(maxPlayers) == "number" and maxPlayers > 0 then
			E.UIKit.TipPair(tooltip, L["Players"], tostring(maxPlayers))
		end
	end,
})

-- Volume (master). Shares the CVar owner with the QoL volume panel, so
-- "Blizzard default" there also undoes changes made here.
local function CVarNumber(name)
	if not (C_CVar and C_CVar.GetCVar) then return nil end
	return tonumber(C_CVar.GetCVar(name))
end

local function SoundOn()
	return CVarNumber("Sound_EnableAllSound") ~= 0
end

E:RegisterDataText("Volume", {
	label = "Vol",
	icon = "Interface\\Common\\VoiceChat-Speaker",
	poll = true,
	interval = 2,
	events = { "CVAR_UPDATE" },
	combatClick = true,
	text = function()
		local volume = CVarNumber("Sound_MasterVolume")
		if not volume then return GREY .. "--|r" end
		if not SoundOn() then return RED .. L["muted"] .. "|r" end
		return Value(("%d%%"):format(volume * 100 + 0.5))
	end,
	tooltip = function(tooltip)
		local volume = CVarNumber("Sound_MasterVolume")
		if volume then E.UIKit.TipPair(tooltip, L["Master volume"], ("%d%%"):format(volume * 100 + 0.5)) end
		E.UIKit.TipPair(tooltip, L["Sound"], SoundOn() and L["On"] or L["Muted"])
		E:TooltipHint(tooltip, { L["Mouse wheel"], L["master volume up or down"] }, { L["Click"], L["sound on or off"] }, { L["Right-click"], L["the volume panel"] })
	end,
	onMouseWheel = function(button, delta)
		local volume = CVarNumber("Sound_MasterVolume")
		if not volume then return end
		volume = math.max(0, math.min(1, volume + (delta > 0 and 0.05 or -0.05)))
		E:SetCVar("Sound_MasterVolume", ("%.2f"):format(volume), "QoL")
		Refresh(button)
	end,
	onClick = function(button, mouseButton)
		if mouseButton == "RightButton" then
			local qol = E:GetModule("QoL")
			if qol and qol.active and qol.ToggleVolume and not InCombatLockdown() then qol:ToggleVolume() end
			return
		end
		E:SetCVar("Sound_EnableAllSound", SoundOn() and "0" or "1", "QoL")
		Refresh(button)
	end,
})

-- Battleground score (the scoreboard API). Values may be secret during a
-- match: they only go through string.format.
local lastScoreRequest = 0

local function InBattleground()
	if C_PvP and C_PvP.IsBattleground then
		local ok, result = pcall(C_PvP.IsBattleground)
		if ok and not IsSecret(result) then return result and true or false end
	end
	local _, instanceType = GetInstanceInfo()
	return instanceType == "pvp"
end

local function BattlegroundScore()
	if not (C_PvP and C_PvP.GetScoreInfoByPlayerGuid) or not InBattleground() then return nil end
	local ok, info = pcall(C_PvP.GetScoreInfoByPlayerGuid, UnitGUID("player"))
	if ok and type(info) == "table" then return info end
end

E:RegisterDataText("Battleground", {
	title = "Battleground score",
	label = "BG",
	poll = true,
	interval = 5,
	events = { "UPDATE_BATTLEFIELD_SCORE", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" },
	secretWidth = 80,
	text = function()
		if not InBattleground() then return GREY .. "--|r" end
		-- Ask for fresh scores every few seconds (the answer is an event).
		local request = _G.RequestBattlefieldScoreData
		if request and GetTime() - lastScoreRequest >= 5 then
			lastScoreRequest = GetTime()
			pcall(request)
		end
		local info = BattlegroundScore()
		if not info then return GREY .. DASH .. "|r" end
		local text = SafeFormat("%s / %s / %s", Shown(info.killingBlows), Shown(info.honorableKills), Shown(info.deaths))
		if Missing(text) then return GREY .. DASH .. "|r" end
		return Value(text)
	end,
	tooltip = function(tooltip)
		local info = BattlegroundScore()
		if not info then
			E.UIKit.TipText(tooltip, L["Shows your killing blows, honorable kills and deaths in a battleground."])
			return
		end
		local function Line(label, value)
			local text = SafeFormat("%s", Shown(value))
			if Missing(text) then text = DASH end
			E.UIKit.TipPair(tooltip, label, text)
		end
		local function Big(value)
			if Missing(value) then return value end
			local ok, text = pcall(E.FormatNumber, E, value)
			if ok then return text end
			return value
		end
		Line(L["Killing blows"], info.killingBlows)
		Line(L["Honorable kills"], info.honorableKills)
		Line(L["Deaths"], info.deaths)
		Line(L["Honor gained"], info.honorGained)
		Line(L["Damage done"], Big(info.damageDone))
		Line(L["Healing done"], Big(info.healingDone))
		E:TooltipHint(tooltip, { L["Click"], L["the scoreboard"] })
	end,
	onClick = function()
		if _G.TogglePVPScoreboardOrResults then _G.TogglePVPScoreboardOrResults() end
	end,
})

-- Ammo (every class with a bow, gun or crossbow): the same count as the
-- Bags ammo warning, and whether the ammo fits the weapon.
local function AmmoCount()
	local bags = E:GetModule("Bags")
	if bags and bags.AmmoCount then return bags:AmmoCount() end
end

E:RegisterDataText("Ammo", {
	label = "Ammo",
	events = { "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED" },
	text = function()
		local count, mismatch = AmmoCount()
		if not count then return GREY .. "--|r" end
		local warn = DB().ammoWarn or 200
		local kind = (count == 0 and "bad") or ((mismatch or count <= warn) and "warn") or nil
		return Status(kind, BreakUpLargeNumbers(count))
	end,
	tooltip = function(tooltip)
		local count, mismatch = AmmoCount()
		if not count then
			E.UIKit.TipText(tooltip, L["No bow, gun or crossbow equipped."])
			return
		end
		local link = INVSLOT_AMMO and GetInventoryItemLink("player", INVSLOT_AMMO)
		tooltip:AddDoubleLine(link or L["No ammo equipped"], BreakUpLargeNumbers(count), 1, 1, 1, 1, 1, 1)
		if mismatch then tooltip:AddLine(E:TextHex("warn") .. L["This ammo doesn't fit your ranged weapon."] .. "|r") end
		-- One gray footer: the color note sits under the ammo line, the click hint ends the tooltip.
		E.UIKit.TipText(tooltip, L["Yellow at %d or less, red when you run out."]:format(DB().ammoWarn or 200))
	end,
	hint = { Key("Click"), Key("open your bags") },
	-- Opens a normal game window: works in combat too.
	combatClick = true,
	onClick = function()
		if ToggleAllBags then ToggleAllBags() end
	end,
})

-- Quests in the log -------------------------------------------------------
local function QuestCounts()
	local log = C_QuestLog
	if not (log and log.GetNumQuestLogEntries) then return nil end
	local _, quests = log.GetNumQuestLogEntries()
	local maximum = log.GetMaxNumQuestsCanAccept and log.GetMaxNumQuestsCanAccept() or _G.MAX_QUESTS or 25
	return Plain(quests), Plain(maximum)
end

E:RegisterDataText("Quests", {
	label = "Quests",
	events = { "QUEST_LOG_UPDATE" },
	text = function()
		local quests, maximum = QuestCounts()
		if not quests then return GREY .. "--|r" end
		return Status((maximum and quests >= maximum) and "bad" or nil, quests) .. Value("/" .. (maximum or "?"))
	end,
	tooltip = function(tooltip)
		local log = C_QuestLog
		local shown = 0
		if log and log.GetNumQuestLogEntries and log.GetInfo then
			local entries = Plain((log.GetNumQuestLogEntries())) or 0
			for index = 1, entries do
				local info = log.GetInfo(index)
				if type(info) == "table" and info.title and not info.isHeader and not info.isHidden then
					shown = shown + 1
					if shown <= 20 then
						local right = info.isComplete and (GREEN .. L["done"] .. "|r") or (info.level and tostring(info.level) or "")
						tooltip:AddDoubleLine(info.title, right, 1, 1, 1, 1, 1, 1)
					end
				end
			end
		end
		if shown == 0 then E.UIKit.TipText(tooltip, L["Your quest log is empty."]) end
		E:TooltipHint(tooltip, { L["Click"], L["quest log"] })
	end,
	-- A click on the block goes through the game's own quest log button (a secure
	-- overlay, so the game opens it, in combat too). This runs only from
	-- the "»" menu or without that button, and only out of combat.
	onClick = function()
		if ToggleQuestLog then ToggleQuestLog() end
	end,
})

-- Spacer and EldoUI button ------------------------------------------------
E:RegisterDataText("Spacer", {
	title = "Spacer (empty gap)",
	fixedWidth = 40,
	text = function() return "" end,
})

E:RegisterDataText("EldoUI", {
	title = "EldoUI",
	text = function() return Label("EldoUI") end,
	tooltip = function(tooltip)
		E:TooltipHint(tooltip, { L["Click"], L["move frames"] })
		E:TooltipHint(tooltip, { L["Right-click"], L["keybind mode"] })
		E.UIKit.TipText(tooltip, L["Type /eui in chat for the settings."])
	end,
	-- The settings open only with /eui (Core/Config.lua).
	onClick = function(_, mouseButton)
		if mouseButton == "RightButton" then E:ToggleKeybindMode() else E:ToggleMoveMode() end
	end,
})

-- Custom currencies: four slots, each showing the currency picked for it.
local function CurrencyText(id)
	local info = CurrencyInfo(id)
	if not info or not info.name then return nil end
	local quantity = Plain(info.quantity) or 0
	local icon = info.iconFileID and ("|T%s:0:0:0:0:64:64:5:59:5:59|t "):format(info.iconFileID) or ""
	if CurrencyAtCap(info) then return icon .. E:StatusText("bad", BreakUpLargeNumbers(quantity)) end
	return icon .. Value(BreakUpLargeNumbers(quantity))
end

for slot = 1, 4 do
	local key = "currency" .. slot
	E:RegisterDataText("Currency" .. slot, FilledTitle({
		events = { "CURRENCY_DISPLAY_UPDATE" },
		text = function()
			local id = DB()[key]
			if not id or id == 0 then return GREY .. L["Currency %d"]:format(slot) .. "|r" end
			return CurrencyText(id) or (GREY .. "--|r")
		end,
		tooltip = function(tooltip)
			local id = DB()[key]
			local info = id and id ~= 0 and CurrencyInfo(id)
			if not info then
				E.UIKit.TipText(tooltip, L["Pick a currency for slot %d on the Datatexts tab."]:format(slot))
				return
			end
			local amount = BreakUpLargeNumbers(Plain(info.quantity) or 0)
			if (info.maxQuantity or 0) > 0 then amount = amount .. " / " .. BreakUpLargeNumbers(info.maxQuantity) end
			tooltip:AddDoubleLine(info.name, amount, 1, 1, 1, 1, 1, 1)
			if (info.maxWeeklyQuantity or 0) > 0 then
				tooltip:AddDoubleLine(L["This week"], ("%s / %s"):format(BreakUpLargeNumbers(info.quantityEarnedThisWeek or 0),
					BreakUpLargeNumbers(info.maxWeeklyQuantity)), 0.65, 0.65, 0.65, 1, 1, 1)
			end
			local cap = CurrencyCap(info)
			if cap == "weekly" then
				tooltip:AddLine(E:StatusText("bad", L["At the weekly cap."]))
			elseif cap then
				tooltip:AddLine(E:StatusText("bad", L["At the cap."]))
			end
		end,
		-- Opens the character window: out of combat only (M.ClickBlock).
		onClick = function()
			if ToggleCharacter and _G.TokenFrame then ToggleCharacter("TokenFrame") end
		end,
	}, E.Key("Custom currency %d"), slot))
end

-- The currency list for the options: id -> name (expanded headers only).
local function CurrencyChoices()
	local values = { [0] = L["(none)"] }
	local api = C_CurrencyInfo
	if api and api.GetCurrencyListSize and api.GetCurrencyListInfo and api.GetCurrencyListLink then
		for index = 1, api.GetCurrencyListSize() do
			local entry = api.GetCurrencyListInfo(index)
			if entry and not entry.isHeader and entry.name then
				local link = api.GetCurrencyListLink(index)
				local id = link and tonumber(link:match("currency:(%d+)"))
				if id then values[id] = entry.name end
			end
		end
	end
	local db = DB()
	for slot = 1, 4 do
		local id = db["currency" .. slot]
		if id and id ~= 0 and not values[id] then
			local info = CurrencyInfo(id)
			values[id] = info and info.name or L["Currency %d"]:format(id)
		end
	end
	return values
end

-- DPS / HPS: Blizzard's own damage meter, current fight. The numbers are
-- Blizzard's (server side); they may be secret in combat and are only
-- passed to AbbreviateNumbers and SetText. The block keeps its helpers to
-- itself, since this file's main chunk is close to Lua's local limit.
do
	local function MeterSource(meterKey)
		local api = C_DamageMeter
		local sessionTypes, meterTypes = Enum and Enum.DamageMeterSessionType, Enum and Enum.DamageMeterType
		if not (api and api.GetCombatSessionFromType and sessionTypes and meterTypes and meterTypes[meterKey]) then return nil end
		local ok, meterSession = pcall(api.GetCombatSessionFromType, sessionTypes.Current, meterTypes[meterKey])
		if not ok or type(meterSession) ~= "table" or type(meterSession.combatSources) ~= "table" then return nil end
		local found
		pcall(function()
			for _, source in ipairs(meterSession.combatSources) do
				if source.isLocalPlayer then found = source break end
			end
		end)
		return found
	end

	-- Abbreviated number text (maybe secret), or nil.
	local function MeterNumber(value)
		if Missing(value) then return nil end
		local ok, text = pcall(E.FormatNumber, E, value)
		if ok then return text end
		return SafeFormat("%.0f", value)
	end

	-- The meter's numbers change with its own events and, in combat, with the
	-- fight's length. Each block reads its session after such an event or once
	-- a second in combat, and keeps its text in between: an idle bar out of
	-- combat reads nothing. The kept text may be secret; it only goes to
	-- SetText.
	M.METER_EVENTS = { "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET" }
	local meterState = {}
	local function MarkMeters()
		for _, state in pairs(meterState) do state.dirty = true end
	end
	M.MarkMeters = MarkMeters

	local function MeterText(meterKey)
		local source = MeterSource(meterKey)
		if not source then return GREY .. "0|r " end
		local text = MeterNumber(source.amountPerSecond)
		if Missing(text) then return GREY .. "0|r " end
		return ("%s "):format(Value(text))
	end

	local function MeterDataText(name, meterKey, title, empty)
		local state = { dirty = true, read = 0 }
		meterState[meterKey] = state
		E:RegisterDataText(name, {
			title = title,
			label = name,
			labelAfter = true,
			poll = true,
			interval = 1,
			pollWhen = function() return state.dirty or InCombatLockdown() end,
			secretWidth = 70,
			events = { "DAMAGE_METER_CURRENT_SESSION_UPDATED", "PLAYER_REGEN_ENABLED" },
			text = function()
				local now = GetTime()
				if state.text == nil or ((state.dirty or InCombatLockdown()) and now - state.read >= 0.95) then
					state.dirty, state.read = false, now
					state.text = MeterText(meterKey)
				end
				return state.text
			end,
			tooltip = function(tooltip)
				local source = MeterSource(meterKey)
				if not source then
					E.UIKit.TipText(tooltip, empty)
				else
					local perSecond, total = MeterNumber(source.amountPerSecond), MeterNumber(source.totalAmount)
					if Missing(perSecond) then perSecond = DASH end
					if Missing(total) then total = DASH end
					E.UIKit.TipPair(tooltip, L["Per second"], perSecond)
					E.UIKit.TipPair(tooltip, L["Total"], total)
				end
				GreyHint(tooltip, L["Your own numbers from Blizzard's damage meter (current fight)."])
			end,
		})
	end
	MeterDataText("DPS", "DamageDone", Key("DPS (damage meter)"), Key("No damage in the current fight yet."))
	MeterDataText("HPS", "HealingDone", Key("HPS (damage meter)"), Key("No healing in the current fight yet."))
end

-- Character stats: the lists, the events and the texts.
local StatData = {}

---------------------------------------------------------------------------
-- Character stats. The stat functions are secret while unit stats
-- are restricted (in combat): a value is formatted, never compared, added
-- or colored. Values built from several parts (attack power, defense,
-- the best spell school) are shown only while they are plain, "–" else.
---------------------------------------------------------------------------
StatData.SPELL_SCHOOLS = { 2, 3, 4, 5, 6, 7 } -- holy, fire, nature, frost, shadow, arcane

local function StatAt(index, ...)
	return (select(index, ...))
end

-- Best value over the spell schools, only when every one is plain.
function StatData.BestSchool(fn)
	if not fn then return nil end
	local best
	for _, school in ipairs(StatData.SPELL_SCHOOLS) do
		local value = Plain(fn(school))
		if not value then return nil end
		if not best or value > best then best = value end
	end
	return best
end

local function Sum(...)
	local total = 0
	for index = 1, select("#", ...) do
		local value = Plain((select(index, ...)))
		if not value then return nil end
		total = total + value
	end
	return total
end

-- percent: the value is a percentage (statDecimals apply).
StatData.STATS = {
	{ key = "Strength", title = "Strength", label = "Str", get = function() return StatAt(2, UnitStat("player", 1)) end },
	{ key = "Agility", title = "Agility", label = "Agi", get = function() return StatAt(2, UnitStat("player", 2)) end },
	{ key = "Stamina", title = "Stamina", label = "Sta", get = function() return StatAt(2, UnitStat("player", 3)) end },
	{ key = "Intellect", title = "Intellect", label = "Int", get = function() return StatAt(2, UnitStat("player", 4)) end },
	{ key = "Spirit", title = "Spirit", label = "Spi", get = function() return StatAt(2, UnitStat("player", 5)) end },
	{ key = "Armor", title = "Armor", label = "Armor", get = function() return StatAt(2, UnitArmor("player")) end },
	{ key = "AttackPower", title = "Attack power", label = "AP", get = function() return Sum(UnitAttackPower("player")) end },
	{ key = "RangedAttackPower", title = "Ranged attack power", label = "RAP",
		get = function() return UnitRangedAttackPower and Sum(UnitRangedAttackPower("player")) end },
	{ key = "Crit", title = "Melee crit", label = "Crit", percent = true, get = function() return GetCritChance and GetCritChance() end },
	{ key = "RangedCrit", title = "Ranged crit", label = "RCrit", percent = true, get = function() return GetRangedCritChance and GetRangedCritChance() end },
	{ key = "SpellCrit", title = "Spell crit", label = "SCrit", percent = true, get = function() return StatData.BestSchool(GetSpellCritChance) end },
	{ key = "Hit", title = "Hit", label = "Hit", percent = true, get = function() return GetHitModifier and GetHitModifier() end },
	{ key = "SpellHit", title = "Spell hit", label = "SHit", percent = true, get = function() return GetSpellHitModifier and GetSpellHitModifier() end },
	{ key = "Haste", title = "Haste", label = "Haste", percent = true, get = function() return GetHaste and GetHaste() end },
	{ key = "SpellPower", title = "Spell power", label = "SP", get = function() return StatData.BestSchool(GetSpellBonusDamage) end },
	{ key = "HealingPower", title = "Healing power", label = "Heal", get = function() return GetSpellBonusHealing and GetSpellBonusHealing() end },
	{ key = "Dodge", title = "Dodge", label = "Dodge", percent = true, get = function() return GetDodgeChance and GetDodgeChance() end },
	{ key = "Parry", title = "Parry", label = "Parry", percent = true, get = function() return GetParryChance and GetParryChance() end },
	{ key = "Block", title = "Block", label = "Block", percent = true, get = function() return GetBlockChance and GetBlockChance() end },
	{ key = "Defense", title = "Defense", label = "Def", get = function() return UnitDefenseSkill and Sum(UnitDefenseSkill("player")) end },
	{ key = "ManaRegen", title = "Mana regen", label = "MP5", get = function()
		if not GetManaRegen then return nil end
		local base = Plain((GetManaRegen()))
		return base and base * 5 -- per 5 seconds, only while plain
	end },
	{ key = "Avoidance", title = "Avoidance", label = "Avoid", percent = true, get = function() return GetAvoidance and GetAvoidance() end },
}

-- Resistances, in the character sheet's order. school is the game's damage
-- class for UnitResistance; the value is the effective total (its second
-- return), as the sheet shows it.
for _, row in ipairs({ { "Arcane", 6 }, { "Fire", 2 }, { "Frost", 4 }, { "Nature", 3 }, { "Shadow", 5 } }) do
	local school = row[2]
	StatData.STATS[#StatData.STATS + 1] = { key = row[1] .. "Resistance", title = row[1] .. " resistance", label = row[1],
		school = school, get = function() return UnitResistance and StatAt(2, UnitResistance("player", school)) end }
end

-- The character sheet's average reduction: 0.75 x resistance / (5 x caster
-- level), at most 75 percent. Nil unless both numbers are plain.
function StatData.ResistAverage(value, level)
	value, level = Plain(value), Plain(level)
	if not value or not level or level < 1 then return nil end
	return math.max(0, math.min(75, 75 * value / (5 * level)))
end

-- Tooltip of one resistance datatext: the total, what gear and effects add,
-- and the sheet's average against your level and a boss three levels up.
function StatData.ResistTip(tooltip, stat)
	local ok, base, total, bonus, minus = pcall(UnitResistance, "player", stat.school)
	if not ok then return end
	E.UIKit.TipPair(tooltip, L[stat.title], Shown(StatData.StatText(stat)))
	bonus, minus = Plain(bonus), Plain(minus)
	if Plain(base) and bonus and bonus > 0 then
		E.UIKit.TipPair(tooltip, L["From gear and effects"], GREEN .. "+" .. bonus .. "|r")
	end
	if minus and minus < 0 then
		E.UIKit.TipPair(tooltip, L["Lowered by effects"], RED .. minus .. "|r")
	end
	local level = UnitLevel("player")
	local own, boss = StatData.ResistAverage(total, level), StatData.ResistAverage(total, Plain(level) and level + 3)
	if own and boss then
		tooltip:AddLine(" ")
		E.UIKit.TipPair(tooltip, L["Average reduction, level %d"]:format(level), ("%.0f%%"):format(own))
		E.UIKit.TipPair(tooltip, L["Average reduction, level %d"]:format(level + 3), ("%.0f%%"):format(boss))
		GreyHint(tooltip, L["The character sheet's average: a single spell can be resisted more, less or not at all."])
	end
	E:TooltipHint(tooltip, { L["Click"], L["character sheet"] })
end

StatData.STAT_EVENTS = { "UNIT_STATS", "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "COMBAT_RATING_UPDATE",
	"UNIT_RESISTANCES", "PLAYER_DAMAGE_DONE_MODS", "UNIT_SPELL_HASTE", "UNIT_ATTACK_SPEED", "SPELL_POWER_CHANGED",
	"PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED" }

-- The stat as text, or nil when the game gives nothing that can be shown.
function StatData.StatText(stat)
	local ok, value = pcall(stat.get)
	if not ok or Missing(value) then return nil end
	if stat.percent then
		local decimals = math.max(0, math.min(2, tonumber(DB().statDecimals) or 1))
		return SafeFormat(("%%.%df%%%%"):format(decimals), value)
	end
	return SafeFormat("%.0f", value)
end

function StatData.StatSheet(tooltip)
	for _, stat in ipairs(StatData.STATS) do
		if not stat.school then
			local text = StatData.StatText(stat)
			if not Missing(text) then E.UIKit.TipPair(tooltip, L[stat.title], text) end
		end
	end
	GreyHint(tooltip, L["In combat the game hides some stats from addons; they show \"%s\" until the fight ends."]:format(DASH))
	E:TooltipHint(tooltip, { L["Click"], L["character sheet"] })
end

for _, stat in ipairs(StatData.STATS) do
	E:RegisterDataText(stat.key, FilledTitle({
		label = stat.label,
		stat = true,
		poll = true,
		interval = 2,
		secretWidth = 72,
		events = StatData.STAT_EVENTS,
		text = function()
			local text = StatData.StatText(stat)
			if Missing(text) then return GREY .. DASH .. "|r" end
			return Value(text)
		end,
		tooltip = stat.school and function(tooltip) StatData.ResistTip(tooltip, stat) end or StatData.StatSheet,
		-- Opens the character window: out of combat only (M.ClickBlock).
		onClick = function() ToggleCharacter("PaperDollFrame") end,
	}, E.Key("Stat: %s"), stat.title))
end

-- Stat block for a class (the "Add a stats panel" button).
StatData.STAT_SETS = {
	melee = { "Strength", "Agility", "Stamina", "Armor", "AttackPower", "Crit", "Hit", "Dodge" },
	ranged = { "Agility", "Stamina", "Armor", "RangedAttackPower", "RangedCrit", "Hit", "Intellect", "ManaRegen" },
	caster = { "Intellect", "Spirit", "Stamina", "SpellPower", "SpellCrit", "SpellHit", "ManaRegen", "Armor" },
	hybrid = { "Strength", "Agility", "Intellect", "Stamina", "Armor", "AttackPower", "SpellPower", "Crit" },
	tank = { "Stamina", "Armor", "Defense", "Dodge", "Parry", "Block", "Strength", "Hit" },
}
StatData.CLASS_STATS = { WARRIOR = "melee", ROGUE = "melee", HUNTER = "ranged", MAGE = "caster", PRIEST = "caster",
	WARLOCK = "caster", DRUID = "hybrid", SHAMAN = "hybrid", PALADIN = "hybrid", DEATHKNIGHT = "tank" }

function StatData.ClassStats()
	local _, class = UnitClass("player")
	return StatData.STAT_SETS[StatData.CLASS_STATS[class] or "hybrid"]
end

---------------------------------------------------------------------------
-- Dashboard rows: what a datatext shows as one or more rows of a panel in
-- "Dashboard" display (icon, label, value and a thin bar). A datatext may
-- give
--   bar  = function() return current, maximum, status end
--          one row (its title and text) with a bar; status is "warn",
--          "bad" or nil and colors the bar
--   rows = function() return { { icon, label, value, current, max,
--          status, color = { r, g, b }, open = function() end }, ... } end
--          its own rows (one per currency, profession and so on)
-- Without either it is one row with its title and text and no bar. Every
-- number is the game's own: a secret one is passed to the bar untouched,
-- never compared, and the row then has no warning color.
---------------------------------------------------------------------------
-- The status of a share filled toward a cap: at the cap "bad", from 90 %
-- "warn" (a currency that stops counting, bags that are full).
local function FillStatus(current, maximum)
	current, maximum = Plain(current), Plain(maximum)
	if not current or not maximum or maximum <= 0 then return nil end
	if current >= maximum then return "bad" end
	if current / maximum >= 0.9 then return "warn" end
	return nil
end

-- A row's value with its status mark, so the color never carries the
-- meaning alone.
local function RowValue(text, status)
	if status == "warn" or status == "bad" then return E:StatusText(status, text) end
	return Value(text)
end

local function CurrencyRow(info, fallbackName)
	local name = E:SafeString(info and info.name, fallbackName or L["Currency"])
	local row = { icon = info and E.Plain(info.iconFileID), label = name }
	local quantity = info and Plain(info.quantity)
	if not quantity then
		row.value = Value(DASH)
		return row
	end
	local maximum = Plain(info.maxQuantity)
	local weekly, earned = Plain(info.maxWeeklyQuantity), Plain(info.quantityEarnedThisWeek)
	if maximum and maximum > 0 then
		row.current, row.max = quantity, maximum
		row.value = ("%s / %s"):format(BreakUpLargeNumbers(quantity), BreakUpLargeNumbers(maximum))
	elseif weekly and weekly > 0 and earned then
		-- Only a weekly cap: the bar shows this week's share of it.
		row.current, row.max = earned, weekly
		row.value = BreakUpLargeNumbers(quantity)
	else
		row.value = BreakUpLargeNumbers(quantity)
	end
	row.status = FillStatus(row.current, row.max)
	row.value = RowValue(row.value, row.status)
	return row
end

local function OpenCurrencies()
	if ToggleCharacter and _G.TokenFrame then ToggleCharacter("TokenFrame") end
end

-- A profession's own window, on the player's click and out of combat.
-- Professions without a crafting window (fishing) open the professions book.
function M.OpenProfession(skillLine)
	if InCombatLockdown() then return false end
	local trade = C_TradeSkillUI
	if type(skillLine) == "number" and trade and type(trade.OpenTradeSkill) == "function" then
		local ok, opened = pcall(trade.OpenTradeSkill, skillLine)
		if ok and opened then return true end
	end
	if ToggleProfessionsBook then ToggleProfessionsBook() end
	return true
end

local DASHBOARD_ROWS = {
	Durability = function()
		local lowest
		for slot = 1, 18 do
			local current, maximum = GetInventoryItemDurability(slot)
			current, maximum = Plain(current), Plain(maximum)
			if current and maximum and maximum > 0 then
				lowest = math.min(lowest or 100, current / maximum * 100)
			end
		end
		lowest = lowest or 100
		local status = DURABILITY_STATUS[E:DurabilityLevel(lowest) or ""]
		return { { icon = E.dataTexts.Durability.icon, label = L["Durability"], value = DurabilityText(lowest),
			current = lowest, max = 100, status = status } }
	end,
	Bags = function()
		local free, total = 0, 0
		for _, bag in ipairs(E.BagCache:BagIDs()) do
			free = free + E.BagCache:Free(bag)
			total = total + E.BagCache:NumSlots(bag)
		end
		-- The bar fills as the bags fill; it warns with 4 slots left.
		local status = (total > 0 and free == 0) and "bad" or (total > 0 and free <= 4 and "warn") or nil
		return { { icon = E.dataTexts.Bags.icon, label = L["Bags"], value = RowValue(L["%d free"]:format(free), status),
			current = total - free, max = math.max(total, 1), status = status } }
	end,
	Currencies = function()
		local rows = {}
		local api = C_CurrencyInfo
		if api and api.GetBackpackCurrencyInfo then
			for index = 1, 8 do
				local watched = api.GetBackpackCurrencyInfo(index)
				if not watched then break end
				local row = CurrencyRow(CurrencyInfo(watched.currencyTypesID) or watched, watched.name)
				row.open = OpenCurrencies
				rows[#rows + 1] = row
			end
		end
		if #rows == 0 then
			rows[1] = { label = L["Currencies"], value = GREY .. L["None tracked"] .. "|r", open = OpenCurrencies }
		end
		return rows
	end,
	Reputation = function()
		local faction = WatchedFaction()
		if not faction then
			return { { label = L["Reputation"], value = GREY .. L["None watched"] .. "|r" } }
		end
		local low, high, value = Plain(faction.currentReactionThreshold), Plain(faction.nextReactionThreshold), Plain(faction.currentStanding)
		local standing = _G["FACTION_STANDING_LABEL" .. tostring(Plain(faction.reaction) or "")]
		local row = { label = E:SafeString(faction.name, L["Reputation"]), value = Value(standing or "") }
		local c = E:ReactionColorObject(Plain(faction.reaction))
		if c then row.color = { c.r, c.g, c.b } end
		if low and high and value and high > low then
			row.current, row.max = value - low, high - low
			row.value = Value(("%s  %.0f%%"):format(standing or "", Percent(value - low, high - low)))
		else
			row.current, row.max = 1, 1 -- the last standing: a full bar
		end
		return { row }
	end,
	Profession = function()
		local rows = {}
		if not (GetProfessions and GetProfessionInfo) then return rows end
		-- Two primary, First Aid, Fishing, Cooking; any may be nil.
		local slots = { GetProfessions() }
		for slot = 1, 6 do
			local index = slots[slot]
			if index then
				local name, icon, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
				rank, maxRank = Plain(rank), Plain(maxRank)
				if type(name) == "string" and rank and maxRank then
					local line = Plain(skillLine)
					rows[#rows + 1] = { icon = E.Plain(icon), label = name, value = Value(("%d / %d"):format(rank, maxRank)),
						current = rank, max = math.max(maxRank, 1), open = function() return M.OpenProfession(line) end }
				end
			end
		end
		if #rows == 0 then rows[1] = { label = L["Professions"], value = GREY .. L["None learned"] .. "|r" } end
		return rows
	end,
	XP = function()
		local level = Plain(UnitLevel("player")) or 0
		if E:AtMaxLevel() then return { { label = L["Level %d"]:format(level), value = Value(L["max"]), current = 1, max = 1 } } end
		local current, maximum = UnitXP("player"), UnitXPMax("player")
		local plainCurrent, plainMax = Plain(current), Plain(maximum)
		local text = (plainCurrent and plainMax) and ("%.1f%%"):format(Percent(plainCurrent, plainMax)) or DASH
		-- Secret XP still fills the bar: the game takes it as it is.
		return { { label = L["Level %d"]:format(level), value = Value(text), current = current, max = maximum } }
	end,
}
for slot = 1, 4 do
	DASHBOARD_ROWS["Currency" .. slot] = function()
		local id = DB()["currency" .. slot]
		local info = id and id ~= 0 and CurrencyInfo(id)
		if not info then return { { label = L["Custom currency %d"]:format(slot), value = GREY .. L["None picked"] .. "|r" } } end
		local row = CurrencyRow(info)
		row.open = OpenCurrencies
		return { row }
	end
end
for name, rows in pairs(DASHBOARD_ROWS) do
	if E.dataTexts[name] then E.dataTexts[name].rows = rows end
end

-- The rows of one datatext, from its `rows`, its `bar` or its title and text.
local function DashboardRows(name, definition)
	if type(definition.rows) == "function" then
		local ok, rows = pcall(definition.rows)
		if ok and type(rows) == "table" then return rows end
	end
	local ok, text = pcall(definition.text)
	if not ok then text = E:TextHex("bad") .. L["error"] .. "|r" end
	local row = { icon = definition.icon, label = L[definition.title or name], value = text }
	if type(definition.bar) == "function" then
		local okBar, current, maximum, status = pcall(definition.bar)
		if okBar then row.current, row.max, row.status = current, maximum, status end
	end
	return { row }
end
M.DashboardRows = DashboardRows

function M.DashboardPolls(dash)
	for _, name in ipairs(dash.names) do
		local definition = E.dataTexts[name]
		if definition and definition.poll and (not definition.pollWhen or definition.pollWhen()) then return true end
	end
	return false
end

-- Sample rows for the options preview, in the player's words and colors.
local function SampleDashboardRows()
	local c = E:ReactionColorObject(6)
	return {
		{ icon = E.dataTexts.Durability.icon, label = L["Durability"], value = DurabilityText(38), current = 38, max = 100,
			status = DURABILITY_STATUS[E:DurabilityLevel(38) or ""] },
		{ icon = E.dataTexts.Bags.icon, label = L["Bags"], value = RowValue(L["%d free"]:format(3), "warn"), current = 69, max = 72, status = "warn" },
		{ icon = "Interface\\Icons\\INV_BannerPVP_02", label = L["Honor"], value = RowValue("1,980 / 2,000", "warn"), current = 1980, max = 2000, status = "warn" },
		{ label = L["Argent Dawn"], value = Value(("%s  %.0f%%"):format(_G.FACTION_STANDING_LABEL6 or L["Honored"], 62)),
			current = 7440, max = 12000, color = c and { c.r, c.g, c.b } },
		{ icon = "Interface\\Icons\\Trade_Tailoring", label = L["Tailoring"], value = Value("212 / 300"), current = 212, max = 300 },
	}
end

---------------------------------------------------------------------------
-- Holders: the two bars and the custom panels. Bar 1 keeps its settings at
-- the top of the module's settings (as in v0.5.0); bar 2 has the same keys
-- under `bar2`; panel i lives in `panels[i]`.
---------------------------------------------------------------------------
-- Movers, by the mover family rule (Core/Movers.lua): the bars are
-- EldoUI_InfoBar and EldoUI_InfoBar2, panel i is EldoUI_DataPanel<i>.
local BAR_BASE, PANEL_BASE = "EldoUI_InfoBar", "EldoUI_DataPanel"
E:RegisterMoverFamily(BAR_BASE, { module = "InfoBar", slots = 2, bareFirst = true })
E:RegisterMoverFamily(PANEL_BASE, { module = "InfoBar", slots = MAX_PANELS })
local BAR_MOVERS = E:MoverFamilyNames(BAR_BASE)
local BAR_TITLES = E:TranslateValues({ E.Key("Info Bar"), E.Key("Second Info Bar") })
local BAR_DEFAULTS = {
	{ "BOTTOM", "UIParent", "BOTTOM", 0, 0 },
	{ "TOP", "UIParent", "TOP", 0, 0 },
}
local SIDES = { "left", "center", "right" }

local function BarDB(index)
	local db = DB()
	if index == 1 then return db end
	return db.bar2
end

local function PanelMoverName(index)
	return E:MoverFamilyName(PANEL_BASE, index)
end

-- Panel 1 sits left of the top center (each layout gives it a spot of its
-- own); every other panel hangs 6 under the one before, so the panels form
-- one column and never land on the same spot. Layouts keep room for four;
-- the player places more with move mode.
local PANEL_GAP = 6
local function PanelDefaultPoint(index)
	if index > 1 then return { "TOP", PanelMoverName(index - 1) .. "Mover", "BOTTOM", 0, -PANEL_GAP } end
	return { "TOP", "UIParent", "TOP", -182, -40 }
end

-- Fill a panel's missing keys (new panels, older profiles, styles).
local function FillPanel(panel)
	E.ApplyDefaults(panel, PANEL_DEFAULTS)
	panel.numSlots = math.max(1, math.min(MAX_PANEL_SLOTS, tonumber(panel.numSlots) or 3))
	return panel
end

-- The settings table of a bar or panel frame.
local function HolderDB(holder)
	if not holder then return nil end
	if holder.panelIndex then return DB().panels[holder.panelIndex] end
	return BarDB(holder.barIndex)
end

-- Is this holder meant to be on screen at all?
local function HolderEnabled(holder)
	local db = HolderDB(holder)
	if not db then return false end
	if holder.panelIndex then return db.enabled ~= false end
	return holder.barIndex == 1 or db.enabled
end

local function BarOf(frame)
	while frame and not frame.isHolder do frame = frame:GetParent() end
	return frame
end

-- The lines of a block's tooltip: its title, its own lines, its click
-- hints and, in combat, a note when its click has to wait. `secure`: the
-- block sits under a secure overlay, whose click works in combat. Also
-- fills the tooltips of the blocks other addons show (InfoBar/Broker.lua).
local function TooltipLines(tooltip, name, definition, secure)
	local r, g, b = unpack(E.media.accentColor)
	tooltip:AddLine(L[definition.title or name], r, g, b)
	definition.tooltip(tooltip)
	local hint = definition.hint
	if type(hint) == "function" then hint = hint() end
	-- hint: { action, what } or a list of them. A plain text (older
	-- plugins) written as "Click: open X" becomes the same hint; any other
	-- text shows as a gray line.
	if type(hint) == "string" then
		local action, what = L[hint]:match("^([^:]+):%s*(.+)$")
		if action and #action <= 24 then hint = { action, what } end
	end
	if type(hint) == "table" then
		if type(hint[1]) == "table" then E:TooltipHint(tooltip, unpack(hint)) else E:TooltipHint(tooltip, hint) end
	elseif hint then
		tooltip:AddLine(" ")
		E.UIKit.TipText(tooltip, L[hint])
	end
	-- A click the game blocks in combat says so instead of doing nothing
	-- (a block under a secure overlay works in combat).
	if definition.onClick and not definition.combatClick and not secure and InCombatLockdown() then
		local warn = E.tokens.text.warn
		if not hint then tooltip:AddLine(" ") end
		tooltip:AddLine(L["Clicks work again after combat."], warn[1], warn[2], warn[3], true)
	end
end
M.TooltipLines = TooltipLines

local function ShowTooltip(button)
	local definition = E.dataTexts[button.dataName]
	if definition and definition.onEnter then
		definition.onEnter(button)
		return
	end
	if not definition or not definition.tooltip then return end
	GameTooltip:SetOwner(button, M:TooltipAnchor(BarOf(button)), 0, 4)
	GameTooltip:ClearLines()
	local overlay = M.overlays and M.overlays[button.dataName]
	TooltipLines(GameTooltip, button.dataName, definition, overlay and overlay.target == button)
	GameTooltip:Show()
end
M.ShowTooltip = ShowTooltip

-- Tooltips open away from the screen edge the holder sits on.
function M:TooltipAnchor(holder)
	local db = HolderDB(holder)
	local anchor = db and db.tooltipAnchor or "AUTO"
	if anchor == "AUTO" then
		local _, y = holder:GetCenter()
		anchor = (y and y > UIParent:GetHeight() / 2) and "BOTTOM" or "TOP"
	end
	if anchor == "LEFT" then return "ANCHOR_LEFT" end
	if anchor == "RIGHT" then return "ANCHOR_RIGHT" end
	return anchor == "BOTTOM" and "ANCHOR_BOTTOM" or "ANCHOR_TOP"
end

local function HideTooltip(button)
	local definition = E.dataTexts[button.dataName]
	if definition and definition.onLeave then definition.onLeave(button) end
	GameTooltip_Hide()
end

-- Per-datatext label settings ({ label = mode, custom = text }).
local function DataTextSettings(name)
	local dt = DB().dt
	return type(dt) == "table" and dt[name] or nil
end

-- The label part of a block, by the player's label setting.
local function LabelPart(name, definition)
	local settings = DataTextSettings(name)
	local mode = settings and settings.label or "default"
	if mode == "none" then return nil end
	if mode == "custom" then
		local custom = settings.custom
		if type(custom) == "string" and custom ~= "" then return Label(custom) end
		return nil
	end
	if mode == "icon" and definition.icon then
		return ("|T%s:0|t"):format(tostring(definition.icon))
	end
	local label = definition.label
	if type(label) == "function" then label = label() end
	if type(label) == "string" and label ~= "" then return Label(L[label]) end
end

local function UpdateButton(button)
	local definition = E.dataTexts[button.dataName]
	if not definition then
		-- Not an Info Bar block: a block's click from another addon's
		-- display (InfoBar/Broker.lua) passes that display's frame.
		if button.dataName == nil then return end
		button.text:SetText("")
		button.shownText = ""
		return
	end
	local ok, text = pcall(definition.text)
	if not ok then
		text = E:TextHex("bad") .. L["error"] .. "|r"
	elseif not IsSecret(text) and type(text) ~= "string" then
		text = tostring(text or "")
	end
	local label = LabelPart(button.dataName, definition)
	if label then
		-- string.format, so a secret value can still be shown.
		if definition.labelAfter then
			text = ("%s%s"):format(text, label)
		else
			text = ("%s %s"):format(label, text)
		end
	end
	-- A poll with the same readable text draws nothing new; a secret text
	-- can't be compared and always draws.
	if IsSecret(text) or button.shownText ~= text then
		button.text:SetText(text)
		button.shownText = not IsSecret(text) and text or nil
	end
	if button.fixedWidth then return end -- panel slots keep their size

	-- Bars: as wide as the text. A secret text can't be measured: keep the
	-- width it had, or the block's own guess.
	local width
	if definition.fixedWidth then
		width = definition.fixedWidth
	elseif IsSecret(text) then
		width = button.plainWidth or definition.secretWidth or 90
	else
		local measured = button.text:GetStringWidth()
		if IsSecret(measured) then
			width = button.plainWidth or definition.secretWidth or 90
		else
			width = measured + 24
			button.plainWidth = width
		end
	end
	-- A block a few pixels narrower keeps its width, so a changing digit
	-- (FPS, latency, coordinates) never moves its neighbors; wider text
	-- gets its room at once.
	local fit = button.section and button.fitWidth
	if fit and width < fit and fit - width <= 6 then width = fit end
	button:SetWidth(width)

	-- A block on a bar that changed width asks for one fit of its bar
	-- (M.FitBar); the same width again does no fit work.
	if button.section and button.fitWidth ~= width then
		button.fitWidth = width
		M.QueueFit(button:GetParent())
	end
end
M.UpdateButton = UpdateButton

---------------------------------------------------------------------------
-- Shift+drag a bar or panel (moves its mover, saved like move mode does)
---------------------------------------------------------------------------
local function HolderMover(holder)
	if not holder then return nil end
	if holder.panelIndex then
		local db = HolderDB(holder)
		if db and db.attach ~= "none" and holder.attachTo then return nil end -- docked panels follow their frame
		return E.movers[PanelMoverName(holder.panelIndex)]
	end
	return E.movers[BAR_MOVERS[holder.barIndex]]
end

local function StartBarDrag(frame)
	if not M.db.shiftDrag or not IsShiftKeyDown() or InCombatLockdown() then return end
	local holder = BarOf(frame.target or frame) or M.bars[1]
	local mover = HolderMover(holder)
	if not mover then return end
	GameTooltip_Hide()
	mover:StartMoving()
	M.dragging = mover
end

local function StopBarDrag()
	local mover = M.dragging
	if not mover then return end
	M.dragging = nil
	mover:StopMovingOrSizing()
	local left, bottom = mover:GetLeft(), mover:GetBottom()
	if left then E:SaveMoverFromRect(mover, left, bottom) end
	M:SyncHearthOverlay()
end

local function EnableDrag(frame)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", StartBarDrag)
	frame:SetScript("OnDragStop", StopBarDrag)
end

local function AllHolders()
	local list = {}
	for _, bar in ipairs(M.bars or {}) do list[#list + 1] = bar end
	for _, panel in ipairs(M.panelFrames or {}) do list[#list + 1] = panel end
	return list
end

---------------------------------------------------------------------------
-- Secure block overlays: the Hearthstone block uses the item, and the
-- blocks that open the world map or the quest log click the game's own
-- button for it (the zone text above the minimap, the quest log micro
-- button). The game's windows are then opened by the game's own code: a
-- map opened from addon code leaves the map's state tainted, and the
-- game's later opens of it (its own key included) get protected calls
-- blocked.
--
-- Each overlay is parented to UIParent and placed by screen position (not
-- anchored to the bar), so the bar never becomes part of a protected
-- anchor chain and can keep resizing its blocks in combat. Overlays are
-- only created and moved out of combat. The holder's visibility rule
-- becomes a secure state driver (E:VisibilityDriver), and the alpha
-- follows the holder's fade. One overlay per block kind, on the first
-- shown block of that kind.
---------------------------------------------------------------------------
do
	local function WorldMapButton() return E.UIKit.GameButton("worldmap") end
	local function QuestLogButton() return E.UIKit.GameButton("questlog") end

	local SECURE_BLOCKS = {
		Hearthstone = { name = "EldoUI_InfoBarHearth", item = true },
		Zone = { click = WorldMapButton },
		Coords = { click = WorldMapButton },
		Quests = { click = QuestLogButton },
	}
	M.SECURE_BLOCKS = SECURE_BLOCKS

	-- The game button a block clicks, or nil (no overlay; the block then opens
	-- the window itself, out of combat only).
	function M.SecureClickButton(dataName)
		local spec = SECURE_BLOCKS[dataName]
		return spec and spec.click and spec.click() or nil
	end

	M.overlays = M.overlays or {}

	function M:GetSecureOverlay(dataName)
		local overlay = self.overlays[dataName]
		if overlay then return overlay end
		local spec = SECURE_BLOCKS[dataName]
		if not spec or InCombatLockdown() then return nil end
		if spec.click and not spec.click() then return nil end
		overlay = CreateFrame("Button", spec.name, UIParent, "SecureActionButtonTemplate")
		overlay:SetFrameStrata("MEDIUM")
		overlay:RegisterForClicks("AnyUp", "AnyDown")
		if spec.item then
			overlay:SetAttribute("type1", "item")
			overlay:SetAttribute("item", "item:" .. HEARTHSTONES[1])
		else
			overlay:SetAttribute("type1", "click")
		end
		overlay:SetAttribute("shift-type1", "noop") -- Shift+drag moves the bar instead
		local highlight = overlay:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		local r, g, b = unpack(E.media.accentColor)
		highlight:SetColorTexture(r, g, b, 0.12)
		overlay.highlight = highlight
		overlay.dataName = dataName
		overlay:SetScript("OnEnter", function(frame) if frame.target then ShowTooltip(frame.target) end end)
		overlay:SetScript("OnLeave", function(frame) if frame.target then HideTooltip(frame.target) else GameTooltip_Hide() end end)
		EnableDrag(overlay)
		overlay:Hide()
		self.overlays[dataName] = overlay
		if dataName == "Hearthstone" then self.hearth = overlay end
		return overlay
	end

	-- Kept for callers that only know the Hearthstone overlay.
	function M:GetHearthOverlay()
		return self:GetSecureOverlay("Hearthstone")
	end

	local function HideOverlay(overlay)
		UnregisterStateDriver(overlay, "visibility")
		overlay.target = nil
		overlay:Hide()
	end

	local function PlaceOverlay(overlay, target)
		local spec = SECURE_BLOCKS[overlay.dataName]
		local r, g, b = unpack(E.media.accentColor) -- accent read at draw time
		overlay.highlight:SetColorTexture(r, g, b, 0.12)
		if spec.item then
			local id = HearthstoneID() or HEARTHSTONES[1]
			overlay:SetAttribute("item", "item:" .. id)
		else
			local button = spec.click()
			if not button then
				HideOverlay(overlay)
				return
			end
			overlay:SetAttribute("clickbutton", button)
		end
		local left, bottom = target:GetLeft(), target:GetBottom()
		if not left then return end
		local scale = target:GetEffectiveScale() / UIParent:GetEffectiveScale()
		local holder = BarOf(target)
		overlay.target = target
		overlay:SetFrameStrata(holder:GetFrameStrata() == "BACKGROUND" and "LOW" or holder:GetFrameStrata())
		overlay:SetFrameLevel(holder:GetFrameLevel() + 10)
		overlay:ClearAllPoints()
		overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
		overlay:SetSize(target:GetWidth() * scale, target:GetHeight() * scale)
		overlay.lastLeft, overlay.lastBottom, overlay.lastWidth = left, bottom, target:GetWidth()
		overlay:SetAlpha(holder:GetAlpha())
		overlay.mouseOn = holder:GetAlpha() > 0.01
		overlay:EnableMouse(overlay.mouseOn)
		local db = HolderDB(holder)
		local driver = db and E:VisibilityDriver(db.visibility)
		if driver then
			RegisterStateDriver(overlay, "visibility", driver)
		else
			UnregisterStateDriver(overlay, "visibility")
			overlay:Show()
		end
	end

	function M:SyncSecureOverlays()
		if InCombatLockdown() then
			self.overlayPending = true
			return
		end
		self.overlayPending = nil
		local targets = {}
		if self.active then
			for _, holder in ipairs(AllHolders()) do
				if holder:IsShown() then
					for _, button in ipairs(holder.buttons) do
						local name = button.dataName
						if button:IsShown() and name and SECURE_BLOCKS[name] and not targets[name] then targets[name] = button end
					end
				end
			end
		end
		for name in pairs(SECURE_BLOCKS) do
			local target, overlay = targets[name], self.overlays[name]
			if target then
				overlay = self:GetSecureOverlay(name)
				if overlay then PlaceOverlay(overlay, target) end
			elseif overlay then
				HideOverlay(overlay)
			end
		end
	end

	-- Kept under the old name: every caller re-syncs all overlays.
	function M:SyncHearthOverlay()
		return self:SyncSecureOverlays()
	end

	-- Cheap check from the 1-second tick: did a secure block move or resize?
	function M:CheckSecureOverlays()
		if InCombatLockdown() then return end
		if self.overlayPending then return self:SyncSecureOverlays() end
		for name, overlay in pairs(self.overlays) do
			local target = overlay.target
			if target and (not target:IsVisible() or target.dataName ~= name or target:GetLeft() ~= overlay.lastLeft
				or target:GetBottom() ~= overlay.lastBottom or target:GetWidth() ~= overlay.lastWidth) then
				return self:SyncSecureOverlays()
			end
		end
	end

	function M:CheckHearthOverlay()
		return self:CheckSecureOverlays()
	end
end

---------------------------------------------------------------------------
-- Holder frames: polling, events, buttons
---------------------------------------------------------------------------
-- One shown bar or panel, from the shared tick: each block refreshes on
-- its own interval (1 s unless it asks for another).
local function TickHolder(holder, elapsed)
	-- A dashboard redraws all its rows: after an event, and once a
	-- second while one of its datatexts polls.
	local dash = holder.dashboard
	if dash then
		holder.dashTick = (holder.dashTick or 0) + elapsed
		if holder.dashDirty or (holder.dashTick >= 1 and M.DashboardPolls(dash)) then
			holder.dashTick = 0
			M:UpdateDashboard(holder)
		end
	end
	for _, button in ipairs(holder.buttons) do
		local definition = E.dataTexts[button.dataName]
		-- A block the fit hid keeps its text and width current, so it
		-- comes back as soon as it has room.
		if (button:IsShown() or button.fitHidden) and definition and definition.poll then
			button.elapsed = (button.elapsed or 0) + elapsed
			if button.elapsed >= (definition.interval or 1) and (not definition.pollWhen or definition.pollWhen()) then
				button.elapsed = 0
				UpdateButton(button)
			end
		end
	end
	holder.tick = (holder.tick or 0) + elapsed
	if holder.tick >= 1 then
		holder.tick = 0
		if holder == M.bars[1] then M:CheckSecureOverlays() end
		if holder.panelIndex then M:CheckAttach(holder) end
		if holder.barIndex == 2 then M:CheckBarDock(holder) end
	end
end

-- Every tenth of a second while the module is on (E.Ticker, one tick for
-- all bars and panels); a bar or panel that isn't shown waits.
local TICK_KEY = "InfoBar:holders"
function M:TickHolders(elapsed)
	for _, bar in ipairs(self.bars or {}) do
		if bar:IsVisible() then TickHolder(bar, elapsed) end
	end
	for _, panel in ipairs(self.panelFrames or {}) do
		if panel:IsVisible() then TickHolder(panel, elapsed) end
	end
end

local function SetupHolder(holder)
	holder.isHolder = true
	holder.buttons = {}
	EnableDrag(holder)
	holder:SetScript("OnEvent", function(_, event)
		if holder.dashboard then
			holder.dashDirty = true
			return
		end
		for _, button in ipairs(holder.buttons) do
			local definition = E.dataTexts[button.dataName]
			if (button:IsShown() or button.fitHidden) and definition and definition.events and tContains(definition.events, event) then
				UpdateButton(button)
			end
		end
	end)
end

-- A block's own click: from the block, or from the "»" menu of a block
-- the bar had no room for (owner: where a combat note shows). Only blocks
-- marked combatClick work in combat. The character window is not one of
-- them: it reads your health and power, which the game keeps secret in
-- combat, and opened from addon code its status texts then raise an
-- error, so those blocks wait for the end of combat like the others.
function M.ClickBlock(button, mouseButton, owner)
	local definition = E.dataTexts[button.dataName]
	if not (definition and definition.onClick) then return end
	if definition.combatClick or not InCombatLockdown() then
		definition.onClick(button, mouseButton)
	elseif E.UIKit and E.UIKit.Toast then
		-- Move mode, talents and the like wait for the end of combat.
		E.UIKit.Toast(owner or button, L["Not in combat."], { warn = true })
	end
end

local function GetButton(holder, index)
	local button = holder.buttons[index]
	if not button then
		button = CreateFrame("Button", nil, holder)
		button.text = E:CreateText(button)
		button.text:SetPoint("CENTER")
		button:RegisterForClicks("AnyUp")
		button:SetScript("OnEnter", ShowTooltip)
		button:SetScript("OnLeave", HideTooltip)
		button:SetScript("OnClick", function(self, mouseButton)
			if E:IsOptionsLinkClick(self, mouseButton) then return end
			if IsShiftKeyDown() and M.db.shiftDrag then return end
			M.ClickBlock(self, mouseButton)
		end)
		button:SetScript("OnMouseWheel", function(self, delta)
			local definition = E.dataTexts[self.dataName]
			if definition and definition.onMouseWheel then definition.onMouseWheel(self, delta) end
		end)
		EnableDrag(button)
		-- Alt-click: some datatexts use Ctrl-click for themselves.
		E:BindOptionsLink(button, function(self)
			local owner = self:GetParent()
			local tab = owner and owner.panelIndex and "Panels" or (owner and owner.barIndex == 2 and "Second bar") or "Main bar"
			return { page = "module:InfoBar", tab = tab }
		end, { modifier = "alt" })
		holder.buttons[index] = button
	end
	return button
end

-- Docked on the minimap with Background off, a panel's text keeps an
-- outline (the theme's own, or a plain one when the theme has none) so it
-- reads over a bright map; the plate stays off as chosen.
function M.DockOutline(holder)
	local db = holder and holder.panelIndex and holder.docked and HolderDB(holder)
	if not (db and db.attach == "minimap" and not db.backdrop) then return nil end
	local own = E.db.general.fontOutline
	if type(own) == "string" and own:find("OUTLINE", 1, true) then return nil end
	return "OUTLINE"
end

-- Point a button at a datatext and draw it once.
local function BindButton(holder, button, name, definition, fontSize, events)
	button.dataName = name
	button.elapsed = 0
	button.plainWidth, button.shownText = nil, nil
	E:SetFont(button.text, fontSize, M.DockOutline(holder))
	button:EnableMouseWheel(definition.onMouseWheel and true or false)
	button:Show()
	UpdateButton(button)
	for _, event in ipairs(definition.events or {}) do
		if not events[event] then
			events[event] = true
			-- Datatexts only show the player: UNIT_* events for other units
			-- (a raid of 40) would redraw every block for nothing.
			if event:find("^UNIT_") then
				pcall(holder.RegisterUnitEvent, holder, event, "player")
			else
				pcall(holder.RegisterEvent, holder, event)
			end
		end
	end
end

local function Usable(name)
	local definition = name and E.dataTexts[name]
	if not definition or (definition.broker and not M.db.ldb) then return nil end
	return definition
end

-- Background and border from the holder's settings.
local function PaintHolder(holder, db, border)
	if db.backdrop then
		E:SetTemplate(holder, true) -- theme colors may have changed
		local r, g, b = unpack(E.media.backdropColor)
		holder:SetBackdropColor(r, g, b, (db.backdropAlpha or 50) / 100)
		if border == false then holder:SetBackdropBorderColor(0, 0, 0, 0) end
	else
		E:SetTemplate(holder, true)
		holder:SetBackdropColor(0, 0, 0, 0)
		holder:SetBackdropBorderColor(0, 0, 0, 0)
	end
	E:SetStyleEdge(holder, db.backdrop and border ~= false) -- WoW Forever art style frame line
end

-- Visibility rules (the shared engine). Plain frames: alpha only; a holder faded
-- to nothing takes no mouse, so hidden blocks show no tooltips.
local function HolderAlpha(holder, alpha)
	local mouse = alpha > 0.01
	if holder.mouseOn ~= mouse then
		holder.mouseOn = mouse
		holder:EnableMouse(mouse)
		for _, button in ipairs(holder.buttons) do button:EnableMouse(mouse) end
		if holder.more then holder.more:EnableMouse(mouse) end
		for _, row in ipairs(holder.dashRows or {}) do row:EnableMouse(mouse) end
	end
	for name, overlay in pairs(M.overlays) do
		if overlay.target and BarOf(overlay.target) == holder then
			overlay:SetAlpha(alpha)
			-- The overlay is a secure button: its mouse follows the bar out
			-- of combat.
			if overlay.mouseOn ~= mouse then
				overlay.mouseOn = mouse
				E:RunOutOfCombat(function() overlay:EnableMouse(overlay:GetAlpha() > 0.01) end, "infobar-overlay-mouse-" .. name)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Folding a bar: "open", "tab" (a small tab at the bar's edge brings it
-- back, hovering the tab shows the bar) or "hidden" (/eui infobar show,
-- the key binding or the options bring it back). A folded bar keeps its
-- size and place and only fades out, so frames anchored to it never move.
---------------------------------------------------------------------------
local COLLAPSE_STATES = { open = true, tab = true, hidden = true }

local function CollapseState(index)
	local db = index and BarDB(index)
	local state = db and db.collapsed
	return COLLAPSE_STATES[state] and state or "open"
end

-- Full alpha of a holder: a folded bar is 0 unless move mode is on or the
-- mouse is on its tab.
local function HolderFullAlpha(holder)
	if not holder.barIndex or CollapseState(holder.barIndex) == "open" then return 1 end
	if holder.peek or E:IsMoveMode() then return 1 end
	return 0
end

local function AttachHolderVisibility(holder)
	local db = HolderDB(holder)
	if not db then return end
	if type(db.visibility) ~= "table" then db.visibility = E:VisibilityDefaults() end
	-- Attaching again is fine: it re-reads the block (a new table after a
	-- profile switch, a migration or a deleted panel).
	holder.mouseOn = nil
	holder:EnableMouse(true)
	E:AttachVisibility(holder, db.visibility, {
		forceShow = function() return E:IsMoveMode() end,
		alpha = function() return HolderFullAlpha(holder) end,
		onAlpha = HolderAlpha,
	})
end

-- Which screen edge a bar sits nearer to: "TOP" or "BOTTOM".
local function BarEdge(bar)
	local _, y = bar:GetCenter()
	return (y and y > UIParent:GetHeight() / 2) and "TOP" or "BOTTOM"
end

local SetPeek

-- A folded bar shows while its tab or the bar itself is under the mouse:
-- watched on the shared tick only while it peeks.
local function WatchPeek(bar)
	local key = "InfoBar:peek" .. bar.barIndex
	if not bar.peek then
		E.Ticker:Unsubscribe(key)
		return
	end
	E.Ticker:Subscribe(key, 0, function()
		if not bar.peek then
			E.Ticker:Unsubscribe(key)
		elseif not bar:IsMouseOver() and not (M.tabs[bar.barIndex] and M.tabs[bar.barIndex]:IsMouseOver()) then
			SetPeek(bar, nil)
		end
	end, M)
end

SetPeek = function(bar, peek)
	if bar.peek == peek then return end
	bar.peek = peek
	E:UpdateVisibility(bar)
	WatchPeek(bar)
end

M.tabs = {}

local FOLD_HINTS = {
	{ Key("Click"), Key("fold the bar to a small tab") },
	{ Key("Right-click"), Key("hide the bar") },
}
local TAB_HINTS = {
	{ Key("Click"), Key("show the bar") },
	{ Key("Right-click"), Key("hide the bar") },
}

function M:GetTab(index)
	local tab = self.tabs[index]
	if tab then return tab end
	local Kit = E.UIKit
	tab = Kit.IconButton(UIParent, 14, "chevron-up", function(_, mouseButton)
		M:SetCollapsed(index, mouseButton == "RightButton" and "hidden" or "open")
	end)
	Kit.Tooltip(tab, BAR_TITLES[index], L["The bar is folded. Hover this tab to see it."], TAB_HINTS)
	tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	tab:SetSize(36, 12)
	tab.icon:SetSize(10, 10)
	tab:SetFrameStrata("LOW")
	E:SetTemplate(tab, true)
	tab:HookScript("OnEnter", function()
		local bar = M.bars[index]
		if bar then SetPeek(bar, true) end
	end)
	tab:HookScript("OnLeave", function()
		local bar = M.bars[index]
		if bar and not bar:IsMouseOver() then SetPeek(bar, nil) end
	end)
	tab:Hide()
	self.tabs[index] = tab
	return tab
end

-- The tab follows the bar's state and edge.
function M:SyncTab(index)
	local bar = self.bars and self.bars[index]
	local want = self.active and bar and HolderEnabled(bar) and CollapseState(index) == "tab"
	if not want then
		if self.tabs[index] then self.tabs[index]:Hide() end
		if bar then bar.peek = nil end
		return
	end
	local tab = self:GetTab(index)
	local edge = BarEdge(bar)
	tab:ClearAllPoints()
	tab:SetPoint(edge .. "RIGHT", bar, edge .. "RIGHT", -8, 0)
	E.UIKit.SetGlyph(tab.icon, edge == "TOP" and "chevron-down" or "chevron-up")
	tab:Show()
end

-- The fold button at the bar's right end (made once, shown by setting).
local function CollapseControl(bar)
	local control = bar.collapseControl
	if not control then
		control = E.UIKit.IconButton(bar, 14, "chevron-down", function(_, mouseButton)
			M:SetCollapsed(bar.barIndex, mouseButton == "RightButton" and "hidden" or "tab")
		end)
		E.UIKit.Tooltip(control, BAR_TITLES[bar.barIndex], nil, FOLD_HINTS)
		control:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		control:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
		bar.collapseControl = control
	end
	E.UIKit.SetGlyph(control.icon, BarEdge(bar) == "TOP" and "chevron-up" or "chevron-down")
	return control
end

function M:SetCollapsed(index, state)
	index = index or 1
	local db = BarDB(index)
	if not (db and COLLAPSE_STATES[state]) then return end
	db.collapsed = state
	local bar = self.bars and self.bars[index]
	if bar then
		bar.peek = nil
		E:UpdateVisibility(bar)
	end
	self:SyncTab(index)
	if state == "hidden" then
		E:Print(L["%s hidden. Bring it back with %s or your key binding."]:format(BAR_TITLES[index], E:Highlight("/eui infobar show")))
	end
end

-- Key binding and /eui infobar: an open bar folds, a folded or hidden one opens.
function E:ToggleInfoBar(index)
	index = index or 1
	if not M.active then
		E:Print(E:ModuleOffHint("InfoBar"))
		return
	end
	M:SetCollapsed(index, CollapseState(index) == "open" and "tab" or "open")
end
E:NameBinding("BINDING_NAME_ELDOUI_INFOBAR_TOGGLE", E.Key("Show or fold the Info Bar"))

local COMMAND_STATES = { show = "open", open = "open", tab = "tab", fold = "tab", hide = "hidden" }
E:AddCommand("infobar", "[show | tab | hide] [2]  show the Info Bar, fold it to a small tab or hide it (2: the second bar)", function(arg)
	local word, number = tostring(arg or ""):lower():match("^%s*(%a*)%s*(%d*)")
	if word == "" then
		E:ToggleConfig("module:InfoBar")
		return
	end
	local state = COMMAND_STATES[word]
	if not state then
		E:Print(L["Use %s, %s or %s."]:format(E:Highlight("/eui infobar show"), E:Highlight("/eui infobar tab"), E:Highlight("/eui infobar hide")))
		return
	end
	if not M.active then
		E:Print(E:ModuleOffHint("InfoBar"))
		return
	end
	M:SetCollapsed(number == "2" and 2 or 1, state)
end, "Layout & frames")

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------
function M:CreateBar(index)
	local bar = CreateFrame("Frame", BAR_MOVERS[index], UIParent)
	bar.barIndex = index
	bar:SetFrameStrata("BACKGROUND")
	bar:SetSize(UIParent:GetWidth(), 28)
	E:SetTemplate(bar, true)
	SetupHolder(bar)
	bar.sections = {}
	for _, side in ipairs(SIDES) do
		local section = CreateFrame("Frame", nil, bar)
		section:SetHeight(1)
		section.buttons = {}
		bar.sections[side] = section
	end
	bar.sections.left:SetPoint("LEFT", bar, "LEFT", 8, 0)
	bar.sections.center:SetPoint("CENTER", bar, "CENTER")
	bar.sections.right:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
	self.bars[index] = bar
	local previous = E.currentModule
	E.currentModule = self
	E:CreateMover(bar, BAR_MOVERS[index], BAR_TITLES[index], BAR_DEFAULTS[index])
	E.currentModule = previous
	E:RegisterHideable(bar, BAR_MOVERS[index], { mouse = true })
	bar:HookScript("OnSizeChanged", function(frame) M.QueueFit(frame) end)
	return bar
end

-- Lay out the configured datatexts in the left, center and right sections.
function M:RebuildBar(bar)
	local db = BarDB(bar.barIndex)
	PaintHolder(bar, db)
	local width = (db.width and db.width > 0) and db.width or UIParent:GetWidth()
	bar:SetSize(width, db.height)
	self:PlaceBar(bar)
	bar:UnregisterAllEvents()
	for _, button in ipairs(bar.buttons) do
		button:Hide()
		button.fitHidden, button.fitWidth = nil, nil
	end

	local index, events = 0, {}
	for _, side in ipairs(SIDES) do
		local section = bar.sections[side]
		local previous
		section.buttons = {}
		local names = db[side] or {}
		-- In a battleground the main bar's center can swap to the score.
		if side == "center" and bar.barIndex == 1 and DB().bgSwap and InBattleground() then
			names = { "Battleground", "CombatTime" }
		end
		-- Every slot counts, so a datatext after an empty slot still shows.
		for slot = 1, math.max(SLOTS, #names) do
			local name = names[slot]
			local definition = Usable(name)
			if definition then
				index = index + 1
				local button = GetButton(bar, index)
				button.section = section
				button.fixedWidth = nil
				button.text:SetWidth(0)
				button.text:SetWordWrap(false)
				table.insert(section.buttons, button)
				button:SetHeight(db.height)
				button:ClearAllPoints()
				if previous then
					button:SetPoint("LEFT", previous, "RIGHT", 0, 0)
				else
					button:SetPoint("LEFT", section, "LEFT", 0, 0)
				end
				BindButton(bar, button, name, definition, db.fontSize, events)
				previous = button
			end
		end
		if not previous then section:SetWidth(1) end
	end
	local control = CollapseControl(bar)
	control:SetShown(db.collapseControl ~= false)
	bar.sections.right:ClearAllPoints()
	bar.sections.right:SetPoint("RIGHT", bar, "RIGHT", db.collapseControl ~= false and -22 or -8, 0)
	self:FitBar(bar)
	bar:Show()
	AttachHolderVisibility(bar)
	self:SyncTab(bar.barIndex)
end

---------------------------------------------------------------------------
-- Fitting a bar: its three sections never run into each other. Where two
-- sections would meet, the innermost blocks give way: first the center's
-- end that meets, then the side whose inner block reaches nearer the
-- bar's middle (the left section's last block, the right section's
-- first). While any block is hidden, the bar shows one "»" button at the
-- outer end of its right section: its tooltip lists the hidden blocks and
-- its menu runs their click. They come back in order once there is room.
-- Only plain widths enter the fit: a block keeps its last plain width, or
-- its own guess, while its text is secret. The player's block lists
-- never change.
---------------------------------------------------------------------------
M.FIT_GAP = 4 -- the least room between two sections
M.MORE_WIDTH = 16 -- the "»" button

-- The fit itself, with no frames: the bar's width, the insets { left,
-- right } from its edges and, per section, the block widths in their
-- configured order. Returns per section the blocks that show (first to
-- last; none when last < first) and count, so count minus the shown ones
-- are hidden.
function M.FitSections(width, insets, sections, gap, more)
	gap, more = gap or M.FIT_GAP, more or M.MORE_WIDTH
	local fit, total = {}, 0
	for _, side in ipairs(SIDES) do
		local widths = sections[side] or {}
		fit[side] = { first = 1, last = #widths, count = #widths, widths = widths }
		total = total + #widths
	end
	local function ShownCount(side) return fit[side].last - fit[side].first + 1 end
	local function AnyHidden()
		for _, side in ipairs(SIDES) do
			if ShownCount(side) < fit[side].count then return true end
		end
		return false
	end
	local function Width(side)
		local f, sum = fit[side], 0
		for index = f.first, f.last do sum = sum + f.widths[index] end
		if side == "right" and AnyHidden() then sum = sum + more end
		return sum
	end
	local middle = width / 2
	local leftEdge, rightEdge = insets.left or 0, width - (insets.right or 0)
	-- How far the middle of a side's innermost block is from the bar's
	-- middle (nil when it shows none). The "»" comes after the right
	-- section's blocks.
	local function Reach(side)
		local f = fit[side]
		if ShownCount(side) <= 0 then return nil end
		if side == "left" then
			local x = leftEdge
			for index = f.first, f.last - 1 do x = x + f.widths[index] end
			return math.abs(x + f.widths[f.last] / 2 - middle)
		end
		local x = rightEdge - Width("right")
		return math.abs(x + f.widths[f.first] / 2 - middle)
	end
	-- a meets b (a on the left): the center gives way first, at the end
	-- that meets; between the two sides, the one whose inner block reaches
	-- nearer the middle. False when neither can give way.
	local function GiveWay(a, b)
		if b == "center" and ShownCount("center") > 0 then
			fit.center.first = fit.center.first + 1
			return true
		elseif a == "center" and ShownCount("center") > 0 then
			fit.center.last = fit.center.last - 1
			return true
		end
		local reachA = a ~= "center" and Reach(a) or nil
		local reachB = b ~= "center" and Reach(b) or nil
		if reachA and (not reachB or reachA <= reachB) then
			fit[a].last = fit[a].last - 1
		elseif reachB then
			fit[b].first = fit[b].first + 1
		else
			return false
		end
		return true
	end
	for _ = 1, total do
		local leftWidth, centerWidth, rightWidth = Width("left"), Width("center"), Width("right")
		local leftEnd, rightStart = leftEdge + leftWidth, rightEdge - rightWidth
		local moved = false
		if centerWidth > 0 then
			local centerStart = middle - centerWidth / 2
			if leftEnd + (leftWidth > 0 and gap or 0) > centerStart then moved = GiveWay("left", "center") end
			if not moved and centerStart + centerWidth + (rightWidth > 0 and gap or 0) > rightStart then
				moved = GiveWay("center", "right")
			end
		elseif leftEnd + ((leftWidth > 0 and rightWidth > 0) and gap or 0) > rightStart then
			moved = GiveWay("left", "right")
		end
		if not moved then break end
	end
	return fit
end

-- A block's width or the bar's changed: one fit of that bar, on the next
-- frame, however many blocks asked.
function M.QueueFit(bar)
	if not (bar and bar.sections) or bar.fitQueued then return end
	bar.fitQueued = true
	C_Timer.After(0, function()
		if not bar.fitQueued then return end
		bar.fitQueued = nil
		if M.active then M:FitBar(bar) end
	end)
end

-- Lay a bar's blocks out by the fit: the blocks that show chained in
-- their sections, the others hidden behind their section's "»".
function M:FitBar(bar)
	bar.fitQueued = nil
	if not bar.sections then return end
	local width = bar:GetWidth()
	if IsSecret(width) or type(width) ~= "number" then return end
	self.fitRuns = (self.fitRuns or 0) + 1
	local db = BarDB(bar.barIndex)
	local widths = {}
	for _, side in ipairs(SIDES) do
		widths[side] = {}
		for index, button in ipairs(bar.sections[side].buttons) do widths[side][index] = button.fitWidth or 0 end
	end
	local fit = M.FitSections(width, { left = 8, right = db.collapseControl ~= false and 22 or 8 }, widths)
	local hearth
	local more, hidden = M.MoreButton(bar), {}
	for _, side in ipairs(SIDES) do
		local range = fit[side]
		for index, button in ipairs(bar.sections[side].buttons) do
			if index < range.first or index > range.last then hidden[#hidden + 1] = button end
		end
	end
	for _, side in ipairs(SIDES) do
		local section, range = bar.sections[side], fit[side]
		local previous, total = nil, 0
		local function Chain(frame, frameWidth)
			frame:ClearAllPoints()
			if previous then
				frame:SetPoint("LEFT", previous, "RIGHT", 0, 0)
			else
				frame:SetPoint("LEFT", section, "LEFT", 0, 0)
			end
			previous, total = frame, total + frameWidth
		end
		for index, button in ipairs(section.buttons) do
			local show = index >= range.first and index <= range.last
			if M.SECURE_BLOCKS[button.dataName] and show == (button.fitHidden and true or false) then hearth = true end
			button.fitHidden = (not show) or nil
			if show then
				button:Show()
				Chain(button, button.fitWidth or 0)
			else
				button:Hide()
			end
		end
		if side == "right" and #hidden > 0 then Chain(more, M.MORE_WIDTH) end
		section:SetWidth(math.max(total, 1))
	end
	more.hidden = hidden
	more:SetShown(#hidden > 0)
	-- The secure overlays follow their blocks.
	if hearth then self:SyncSecureOverlays() end
end

-- The bar's "»" button (made once per bar).
function M.MoreButton(bar)
	local more = bar.more
	if not more then
		more = CreateFrame("Button", nil, bar)
		more.text = E:CreateText(more)
		more.text:SetPoint("CENTER")
		more.text:SetText("»")
		more:RegisterForClicks("AnyUp")
		more:SetScript("OnEnter", M.ShowMoreTooltip)
		more:SetScript("OnLeave", GameTooltip_Hide)
		more:SetScript("OnClick", M.OpenMoreMenu)
		EnableDrag(more)
		more:Hide()
		bar.more = more
	end
	local db = BarDB(bar.barIndex)
	more:SetSize(M.MORE_WIDTH, db.height)
	E:SetFont(more.text, db.fontSize)
	more.text:SetTextColor(unpack(E.media.accentColor))
	more:EnableMouse(bar.mouseOn ~= false)
	return more
end

-- A block's shown name, and its datatext.
function M.BlockTitle(button)
	local definition = E.dataTexts[button.dataName]
	return L[definition and definition.title or button.dataName], definition
end

-- Its tooltip: the hidden blocks with what they show now.
function M.ShowMoreTooltip(more)
	GameTooltip:SetOwner(more, M:TooltipAnchor(more:GetParent()), 0, 4)
	GameTooltip:ClearLines()
	E.UIKit.TipTitle(GameTooltip, L["More info"])
	E.UIKit.TipText(GameTooltip, L["These blocks have no room on the bar right now."])
	for _, button in ipairs(more.hidden or {}) do
		-- A secret text is left out; only its block's name shows.
		local text = button.text:GetText()
		if IsSecret(text) or type(text) ~= "string" then text = "" end
		E.UIKit.TipPair(GameTooltip, (M.BlockTitle(button)), text)
	end
	E:TooltipHint(GameTooltip, { L["Click"], L["pick a block to click it"] })
	GameTooltip:Show()
end

-- Its menu: one entry per hidden block; picking one runs that block's
-- click, only on the player's own pick.
function M.OpenMoreMenu(more)
	if IsShiftKeyDown() and M.db.shiftDrag then return end
	GameTooltip_Hide()
	E.UIKit.ContextMenu(more, function(_, root)
		root:CreateTitle(L["More info"])
		for _, button in ipairs(more.hidden or {}) do
			local title, definition = M.BlockTitle(button)
			local entry = root:CreateButton(title, function() M.ClickBlock(button, "LeftButton", more) end)
			entry:SetEnabled(definition and definition.onClick and (definition.combatClick or not InCombatLockdown()) and true or false)
		end
	end)
end

-- Panels docked to other frames.
local Docking = {}

---------------------------------------------------------------------------
-- Custom panels
---------------------------------------------------------------------------
-- Attached panels dock inside their frame, the way a chat data panel sits
-- in its chat box: on the chat they fill the top edge of the chat box
-- (under the tabs, right of the side rail) and the messages make room; on
-- the minimap they line the map's bottom edge and the bottom corner icons
-- move up. The frame keeps its size, so no layout has to give up room
-- around it. Each frame holds a few panels; more stay on their own mover.
local DOCK_LIMIT = { chat = 3, minimap = 2 }
local DOCK_GAP = 2
Docking.DOCK_FULL = E:TranslateValues({
	chat = E.Key("The chat window holds three panels."),
	minimap = E.Key("The minimap holds two panels."),
	withBar = E.Key("The chat window holds three: the second info bar and two panels."),
})
Docking.STRATA_RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

-- A round minimap: docked panels stay inside the circle. The first one
-- sits a little up from the bottom, where the circle is still 60 % of its
-- width wide; each panel takes the width the circle has at its edge
-- farthest from the center. (Fields of the module, not locals: this file
-- is near Lua's limit of locals per chunk.)
M.ROUND_DOCK_SHARE = 0.6
function M.RoundDock(attach)
	if attach ~= "minimap" then return false end
	local map = E.modules.Minimap
	return map and map.active and map.mode == "replace" and map.db and map.db.shape == "round" or false
end
function M.RoundLift(box)
	local radius = box:GetWidth() / 2
	return radius - radius * math.sqrt(1 - M.ROUND_DOCK_SHARE * M.ROUND_DOCK_SHARE)
end
-- The circle's width for a panel `height` high whose bottom is `y` above
-- the bottom of the map, a pixel in from the edge.
function M.RoundChord(box, y, height)
	local radius = box:GetWidth() / 2
	local inner = radius - 1
	local far = math.max(math.abs(radius - y), math.abs(y + height - radius))
	if far >= inner then return 0 end
	return math.floor(2 * math.sqrt(inner * inner - far * far))
end

-- The box a panel docks in: the EldoUI chat box or minimap holder, plus
-- how far in from the left it starts (the chat's side rail). nil when the
-- frame isn't EldoUI's (the game's own chat window or minimap).
function Docking.DockBox(attach)
	if attach == "chat" then
		local chat = E.modules.Chat
		local frame = _G.EldoUI_Chat
		if chat and chat.active and chat.panel == frame and frame and frame:IsShown() and frame.bg then
			return frame.bg, chat.RailWidth and chat:RailWidth() or 0
		end
	elseif attach == "minimap" then
		local holder = _G.EldoUI_Minimap
		if holder and holder:IsShown() then return holder, 0 end
	end
	return nil
end

-- Where an attached panel hangs when its frame has no EldoUI box: above
-- the game's chat window or under the game's minimap.
function Docking.AttachTarget(attach)
	if attach == "chat" then return _G.ChatFrame1 end
	if attach == "minimap" then return _G.Minimap end
end

-- The panels docked on one frame, in index order, up to its limit.
local function DockedIndices(attach)
	local list = {}
	local limit = Docking.Limit(attach)
	if not limit then return list end
	for index, db in ipairs(DB().panels) do
		if db.enabled ~= false and db.attach == attach then
			list[#list + 1] = index
			if #list >= limit then break end
		end
	end
	return list
end

-- Where panel `index` docks: its attach target and its place in the stack
-- (nil when it is past the frame's limit, so it uses its own mover).
function Docking.DockSlot(index, attach)
	for slot, other in ipairs(DockedIndices(attach)) do
		if other == index then return slot end
	end
end

function M:CreatePanel(index)
	local panel = CreateFrame("Frame", PanelMoverName(index), UIParent)
	panel.panelIndex = index
	panel:SetSize(300, 24)
	E:SetTemplate(panel, true)
	SetupHolder(panel)
	self.panelFrames[index] = panel
	local previous = E.currentModule
	E.currentModule = self
	E:CreateMover(panel, PanelMoverName(index), L["Datatext Panel %d"]:format(index), PanelDefaultPoint(index))
	E.currentModule = previous
	E:RegisterHideable(panel, PanelMoverName(index), { mouse = true })
	return panel
end

-- The docked panel before this one on the same frame.
function Docking.PreviousDocked(index, attach)
	-- In the chat window the docked second bar comes first.
	local bar = attach == "chat" and M.bars and M.bars[2]
	local previous = bar and bar.attachTo and bar or nil
	for _, other in ipairs(DockedIndices(attach)) do
		if other == index then break end
		local frame = M.panelFrames[other]
		if frame and frame.attachTo then previous = frame end
	end
	return previous
end

-- The width a docked panel takes: the box (less the chat's side rail), or
-- its own width when "Same width" is off.
function Docking.DockWidth(panel, db)
	local target = panel.attachTo
	if not target then return db.width end
	local room = target:GetWidth() - (panel.dockInset or 0)
	if panel.dockRound then
		local height = db.vertical and db.height * db.numSlots or db.height
		if db.display == "dashboard" then height = math.max(panel:GetHeight() or 0, db.height) end
		room = M.RoundChord(target, panel.dockY or 0, height)
	end
	if not db.attachWidth then return panel.docked and math.min(db.width, room) or db.width end
	return room
end

-- Put the panel on its mover, or docked on its chat or minimap.
function M:PlacePanel(panel, db)
	local mover = E.movers[PanelMoverName(panel.panelIndex)]
	local slot = db.attach ~= "none" and Docking.DockSlot(panel.panelIndex, db.attach)
	local box, inset = nil, 0
	if slot then box, inset = Docking.DockBox(db.attach) end
	local target = slot and (box or Docking.AttachTarget(db.attach))
	panel:ClearAllPoints()
	if target then
		local previous = Docking.PreviousDocked(panel.panelIndex, db.attach)
		if box and db.attach == "chat" then
			-- Down from the top of the chat box, right of its rail.
			if previous then
				panel:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -DOCK_GAP)
			else
				panel:SetPoint("TOPLEFT", box, "TOPLEFT", inset, 0)
			end
		elseif box then
			-- Up from the bottom of the minimap (a round one: from a little
			-- up, inside the circle).
			local round = M.RoundDock(db.attach)
			local lift = round and M.RoundLift(box) or 0
			if previous then
				panel:SetPoint("BOTTOM", previous, "TOP", 0, DOCK_GAP)
				panel.dockY = (previous.dockY or 0) + previous:GetHeight() + DOCK_GAP
			else
				panel:SetPoint("BOTTOM", box, "BOTTOM", 0, lift)
				panel.dockY = lift
			end
			panel.dockRound, panel.dockLift = round, lift
		elseif db.attach == "chat" then
			panel:SetPoint("BOTTOM", previous or target, "TOP", 0, DOCK_GAP)
		else
			panel:SetPoint("TOP", previous or target, "BOTTOM", 0, -DOCK_GAP)
		end
		panel.attachTo, panel.dockInset, panel.docked = target, box and inset or 0, box ~= nil
		panel.attachWidth = target:GetWidth() - panel.dockInset
		-- Docked panels draw over their frame.
		if box then
			local strata = box:GetFrameStrata()
			if (Docking.STRATA_RANK[db.strata or "LOW"] or 2) < (Docking.STRATA_RANK[strata] or 2) then panel:SetFrameStrata(strata) end
			if panel:GetFrameStrata() == strata then
				local over = db.attach == "minimap" and _G.Minimap or box
				panel:SetFrameLevel(math.max(box:GetFrameLevel(), E.FrameLevel(over, 0)) + 10)
			end
		end
		if mover then mover:Hide() end
	else
		panel.attachTo, panel.attachWidth, panel.dockInset, panel.docked = nil, nil, nil, nil
		panel.dockRound, panel.dockLift, panel.dockY = nil, nil, nil
		if mover then
			mover:Show()
			panel:SetPoint("CENTER", mover, "CENTER")
		else
			panel:SetPoint(unpack(PanelDefaultPoint(panel.panelIndex)))
		end
	end
end

-- The second info bar docks in the chat window too (bar2.dock = "chat"),
-- like a chat data panel: it fills the top edge of the chat box, as wide
-- as the chat, the docked panels hang under it and it takes one of the
-- chat's three places. Without EldoUI's chat box it sits above the game's
-- chat window. So no layout gives up room for it at a screen edge.
function Docking.BarDocks()
	local bar2 = DB().bar2
	return bar2.enabled and bar2.dock == "chat" or false
end

-- How many panels dock on a frame (one place less in the chat window
-- while the second bar docks there).
function Docking.Limit(attach)
	local limit = DOCK_LIMIT[attach]
	if limit and attach == "chat" and Docking.BarDocks() then limit = limit - 1 end
	return limit
end

-- Put a bar on its mover, or bar 2 docked in the chat window.
function M:PlaceBar(bar)
	local box, inset, target = nil, 0, nil
	if bar.barIndex == 2 and self.active and Docking.BarDocks() then
		box, inset = Docking.DockBox("chat")
		target = box or Docking.AttachTarget("chat")
	end
	bar:ClearAllPoints()
	bar:SetFrameStrata("BACKGROUND")
	if not target then
		bar.attachTo, bar.attachWidth, bar.dockInset, bar.docked = nil, nil, nil, nil
		bar:SetPoint("CENTER", E.movers[BAR_MOVERS[bar.barIndex]], "CENTER")
		return
	end
	inset = box and inset or 0
	bar.attachTo, bar.dockInset, bar.docked = target, inset, box ~= nil
	bar.attachWidth = target:GetWidth() - inset
	bar:SetWidth(bar.attachWidth)
	-- The first time it docks, a tour help says where it went (a moment
	-- later, once the bar is drawn).
	if not self.dockHelpWaiting and not E.Tour:Seen("infobar:docked") then
		self.dockHelpWaiting = true
		C_Timer.After(1, function()
			M.dockHelpWaiting = nil
			E.Tour:Offer("infobar:docked")
		end)
	end
	if box then
		bar:SetPoint("TOPLEFT", box, "TOPLEFT", inset, 0)
		-- Drawn over the chat box, like the docked panels.
		local strata = box:GetFrameStrata()
		if (Docking.STRATA_RANK[strata] or 2) > Docking.STRATA_RANK.BACKGROUND then bar:SetFrameStrata(strata) end
		if bar:GetFrameStrata() == strata then bar:SetFrameLevel(box:GetFrameLevel() + 10) end
	else
		bar:SetPoint("BOTTOMLEFT", target, "TOPLEFT", 0, DOCK_GAP)
	end
end

-- Tour help: the second bar in the chat window, shown once per account.
do
	local function DockedBar()
		local bar = M.active and M.bars and M.bars[2]
		return bar and bar.attachTo and bar or nil
	end

	E.Tour:Register("infobar:docked", {
		form = "spot", word = "infobar",
		offer = function(_, force)
			if not DockedBar() then return false end
			return E.Tour:Spot("infobar:docked", {
				force = force, target = DockedBar,
				title = L["Second info bar"],
				text = L["Your second info bar sits at the top of the chat window, as wide as the chat. To put it somewhere else, set Place to Its own mover on the Second bar tab of /eui infobar."],
			})
		end,
		replay = function(def)
			if not M.active then
				E:Print(E:ModuleOffHint("InfoBar"))
			elseif not DockedBar() then
				E:Print(L["The second info bar is not in the chat window now."])
			else
				def.offer(def, true)
			end
		end,
	})
end

-- The second bar on the setup's layout maps (Core/InstallerMap.lua): on
-- the top edge of the chat box while it docks there, else on the layout's
-- spot. The style the map is drawn with counts first, then what the
-- layout sets, then the player's own settings.
function M:LayoutMapParts(map)
	local own = self.db and self.db.bar2 or self.defaults.bar2
	local preset = map.layout.modules and map.layout.modules.InfoBar
	preset = preset and type(preset.bar2) == "table" and preset.bar2 or {}
	local styled = {}
	local styleKey = map.styles.InfoBar
	for _, style in ipairs(styleKey and E.styles.InfoBar or {}) do
		if style.key == styleKey and type(style.settings.bar2) == "table" then styled = style.settings.bar2 end
	end
	local function Get(key)
		if styled[key] ~= nil then return styled[key] end
		if preset[key] ~= nil then return preset[key] end
		return own[key]
	end
	if not Get("enabled") or map.hidden[BAR_MOVERS[2]] then return nil end
	local height = tonumber(Get("height")) or 24
	if Get("dock") == "chat" then
		local chat = map.Rect("EldoUI_Chat")
		if not chat then return nil end
		return { { part = { name = BAR_MOVERS[2], kind = "strip", docked = true }, rect = { chat[1], chat[4] - height, chat[3], chat[4] } } }
	end
	local width = tonumber(Get("width")) or 0
	local rect = map.Place(BAR_MOVERS[2], width > 0 and width or map.width, height)
	return rect and { { part = { name = BAR_MOVERS[2], kind = "strip" }, rect = rect } } or nil
end

-- From the 1-second tick: follow a chat box that changed width, came or went.
function M:CheckBarDock(bar)
	local box, inset = nil, 0
	if Docking.BarDocks() then box, inset = Docking.DockBox("chat") end
	local target = Docking.BarDocks() and (box or Docking.AttachTarget("chat")) or nil
	inset = box and inset or 0
	if target ~= bar.attachTo or inset ~= (bar.dockInset or 0)
		or (target and target:GetWidth() - inset ~= bar.attachWidth) then
		self:Rebuild()
	end
end

-- Room the docked panels take inside the chat box or the minimap, so the
-- chat text and the minimap's corner icons stay clear of them.
function M:AttachedHeight(attach)
	if not (self.active and self.panelFrames) then return 0 end
	local total = 0
	local lift = 0
	-- The docked second bar keeps its place while it is folded or faded,
	-- so the messages don't jump.
	local bar = attach == "chat" and self.bars and self.bars[2]
	if bar and bar.attachTo and bar.docked then total = total + bar:GetHeight() + DOCK_GAP end
	for _, index in ipairs(DockedIndices(attach)) do
		local frame = self.panelFrames[index]
		if frame and frame.docked and frame:IsShown() then
			total = total + frame:GetHeight() + DOCK_GAP
			lift = math.max(lift, frame.dockLift or 0)
		end
	end
	return total > 0 and total + lift or 0
end

-- Tell the chat and the minimap when the room their panels take changed.
function M:SyncDock()
	self.dockHeights = self.dockHeights or {}
	for attach in pairs(DOCK_LIMIT) do
		local height = self:AttachedHeight(attach)
		if height ~= (self.dockHeights[attach] or 0) then
			self.dockHeights[attach] = height
			local module = attach == "chat" and E.modules.Chat or E.modules.Minimap
			if module and module.active then
				if attach == "chat" and module.RefreshBody then
					module:RefreshBody()
				elseif attach == "minimap" and module.LayoutCorners then
					module:LayoutCorners()
				end
			end
		end
	end
end

-- From the 1-second tick: follow a chat or minimap that changed width, or
-- a chat box that came or went.
function M:CheckAttach(panel)
	local db = HolderDB(panel)
	if not (db and panel.attachTo) then return end
	local box, inset = Docking.DockBox(db.attach)
	local target = box or Docking.AttachTarget(db.attach)
	if target ~= panel.attachTo or (inset or 0) ~= (panel.dockInset or 0)
		or (box and (panel.dockRound or false) ~= M.RoundDock(db.attach))
		or (target and target:GetWidth() - (inset or 0) ~= panel.attachWidth) then
		self:RebuildPanel(panel)
	end
	self:SyncDock()
end

function M:RebuildPanel(panel)
	local db = DB().panels[panel.panelIndex]
	if not db or db.enabled == false or not self.active then
		E:DetachVisibility(panel)
		panel:UnregisterAllEvents()
		panel:Hide()
		local mover = E.movers[PanelMoverName(panel.panelIndex)]
		if mover then mover:Hide() end
		return
	end
	FillPanel(db)
	PaintHolder(panel, db, db.border)
	panel:SetFrameStrata(db.strata or "LOW")
	self:PlacePanel(panel, db)
	-- Docked on the minimap, a panel's background keeps at least the
	-- see-through floor, so its text reads over a bright map.
	if panel.docked and db.attach == "minimap" and db.backdrop then
		local r, g, b, a = panel:GetBackdropColor()
		local floor = E.tokens.panel.transparentFloor
		if r and (a or 0) < floor then panel:SetBackdropColor(r, g, b, floor) end
	end

	local count = db.numSlots
	local width = db.width
	if panel.attachTo then width = Docking.DockWidth(panel, db) end
	width = math.max(100, width)
	if db.display == "dashboard" then
		self:BuildDashboard(panel, db, width)
		panel:Show()
		AttachHolderVisibility(panel)
		return
	end
	self:ClearDashboard(panel)
	local slotWidth, slotHeight
	if db.vertical then
		slotWidth, slotHeight = width, db.height
		panel:SetSize(width, db.height * count)
	else
		slotWidth, slotHeight = width / count, db.height
		panel:SetSize(width, db.height)
	end

	panel:UnregisterAllEvents()
	for _, button in ipairs(panel.buttons) do button:Hide() end
	local events = {}
	for slot = 1, count do
		local button = GetButton(panel, slot)
		button.section = nil
		button.fixedWidth = true
		button:SetSize(slotWidth, slotHeight)
		button.text:SetWidth(slotWidth - 6)
		button.text:SetWordWrap(false)
		button:ClearAllPoints()
		if db.vertical then
			button:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(slot - 1) * slotHeight)
		else
			button:SetPoint("TOPLEFT", panel, "TOPLEFT", (slot - 1) * slotWidth, 0)
		end
		local name = db.slots[slot]
		local definition = Usable(name)
		if definition then BindButton(panel, button, name, definition, db.fontSize, events) end
	end
	panel:Show()
	AttachHolderVisibility(panel)
end

-- The dashboard's rows (one table: a Lua chunk has room for 200 locals).
local DashRows = {}

---------------------------------------------------------------------------
-- Dashboard display: a panel as a compact list, one row per value with
-- its icon, label, value and a thin bar (see DashboardRows). The rows are
-- redrawn on their datatexts' events and once a second for polled ones.
-- Text is never measured and nothing is anchored on a value, so a secret
-- value only ever reaches SetText and the bar.
---------------------------------------------------------------------------
local DASH_PAD = 4      -- inner margin of the panel
DashRows.DASH_BAR = 2      -- bar thickness
DashRows.DASH_MAX_ROWS = 24

-- Paint one row from its data. Shared by the panels and the options preview.
function DashRows.PaintDashRow(row, data, rowHeight, fontSize)
	local iconSize = math.max(10, rowHeight - 8)
	local icon = data.icon
	row.icon:SetSize(iconSize, iconSize)
	if icon then
		row.icon:SetTexture(icon)
		row.icon:Show()
		row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	else
		row.icon:Hide()
		row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
	end
	local outline = M.DockOutline(row:GetParent())
	E:SetFont(row.label, fontSize, outline)
	E:SetFont(row.value, fontSize, outline)
	row.label:SetText(data.label or "")
	row.value:SetText(data.value or "")
	local current, maximum = data.current, data.max
	if type(current) == "nil" or type(maximum) == "nil" then
		row.bar:Hide()
		row.track:Hide()
		return
	end
	row.track:Show()
	row.bar:Show()
	-- Plain numbers or secret ones: both go straight to the bar.
	if E.Secret(maximum) or E.Secret(current) then
		row.bar:SetMinMaxValues(0, maximum)
		row.bar:SetValue(current)
	else
		row.bar:SetMinMaxValues(0, math.max(tonumber(maximum) or 1, 1e-9))
		row.bar:SetValue(math.max(0, math.min(tonumber(current) or 0, tonumber(maximum) or 0)))
	end
	local status = data.status
	if status == "warn" or status == "bad" then
		row.bar:SetStatusBarColor(E:TokenColor(status))
	elseif data.color then
		row.bar:SetStatusBarColor(data.color[1], data.color[2], data.color[3])
	else
		row.bar:SetStatusBarColor(unpack(E.media.accentColor, 1, 3))
	end
end

function DashRows.DashRowClick(row, mouseButton)
	if IsShiftKeyDown() and M.db.shiftDrag then return end
	-- A row of its own (a profession) opens just that, out of combat.
	if row.open then
		if InCombatLockdown() then
			if E.UIKit and E.UIKit.Toast then E.UIKit.Toast(row, L["Not in combat."], { warn = true }) end
			return
		end
		row.open()
		return
	end
	local definition = E.dataTexts[row.dataName]
	if not (definition and definition.onClick) then return end
	if definition.combatClick or not InCombatLockdown() then
		definition.onClick(row, mouseButton)
	elseif E.UIKit and E.UIKit.Toast then
		E.UIKit.Toast(row, L["Not in combat."], { warn = true })
	end
end

-- One row frame: a button the size of the row, so the whole row takes
-- the click, the tooltip and the hover shade.
function DashRows.CreateDashRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:RegisterForClicks("AnyUp")
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetPoint("LEFT", row, "LEFT", 6, DashRows.DASH_BAR)
	E:TrimIcon(row.icon)
	row.label = E:CreateText(row, E.tokens.size.label, "LEFT")
	row.label:SetWordWrap(false)
	row.label:SetTextColor(E:TokenColor("secondary"))
	row.value = E:CreateText(row, E.tokens.size.label, "RIGHT")
	row.value:SetWordWrap(false)
	row.value:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	row.track = row:CreateTexture(nil, "BORDER")
	row.track:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 2)
	row.track:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 2)
	row.track:SetHeight(DashRows.DASH_BAR)
	row.track:SetColorTexture(unpack(E.tokens.track))
	row.bar = CreateFrame("StatusBar", nil, row)
	row.bar:SetAllPoints(row.track)
	E:UseBarTexture(row.bar)
	return row
end
-- Size a row. Label and value share it by fixed parts (the label gets a
-- little more), never by measured text, so a secret value moves nothing.
DashRows.DASH_LABEL_SHARE = 0.58
function DashRows.SizeDashRow(row, width, height)
	row:SetSize(width, height)
	local split = math.floor(width * DashRows.DASH_LABEL_SHARE)
	row.label:SetPoint("RIGHT", row, "LEFT", split, 0)
	row.value:SetPoint("LEFT", row, "LEFT", split + 4, 0)
end
M.SizeDashRow = DashRows.SizeDashRow
M.CreateDashRow = DashRows.CreateDashRow
M.PaintDashRow = DashRows.PaintDashRow

function DashRows.DashRow(panel, index)
	panel.dashRows = panel.dashRows or {}
	local row = panel.dashRows[index]
	if not row then
		row = DashRows.CreateDashRow(panel)
		row:SetScript("OnClick", DashRows.DashRowClick)
		row:SetScript("OnEnter", ShowTooltip)
		row:SetScript("OnLeave", HideTooltip)
		row:SetScript("OnMouseWheel", function(self, delta)
			local definition = E.dataTexts[self.dataName]
			if definition and definition.onMouseWheel then definition.onMouseWheel(self, delta) end
		end)
		EnableDrag(row)
		panel.dashRows[index] = row
	end
	return row
end

function M:ClearDashboard(panel)
	panel.dashboard = nil
	for _, row in ipairs(panel.dashRows or {}) do row:Hide() end
end

-- Set a panel up as a dashboard: events of its datatexts, then the rows.
function M:BuildDashboard(panel, db, width)
	panel:UnregisterAllEvents()
	for _, button in ipairs(panel.buttons) do button:Hide() end
	local events, names = {}, {}
	for slot = 1, db.numSlots do
		local name = db.slots[slot]
		local definition = Usable(name)
		if definition then
			names[#names + 1] = name
			for _, event in ipairs(definition.events or {}) do
				if not events[event] then
					events[event] = true
					if event:find("^UNIT_") then
						pcall(panel.RegisterUnitEvent, panel, event, "player")
					else
						pcall(panel.RegisterEvent, panel, event)
					end
				end
			end
		end
	end
	panel.dashboard = { names = names, width = width, rowHeight = db.height, fontSize = db.fontSize }
	self:UpdateDashboard(panel)
end

-- Redraw every row; the panel grows or shrinks with the number of rows.
function M:UpdateDashboard(panel)
	local dash = panel.dashboard
	if not dash then return end
	panel.dashDirty = nil
	local count = 0
	for _, name in ipairs(dash.names) do
		local definition = E.dataTexts[name]
		if definition then
			for _, data in ipairs(DashboardRows(name, definition)) do
				if count >= DashRows.DASH_MAX_ROWS then break end
				count = count + 1
				local row = DashRows.DashRow(panel, count)
				row.dataName, row.open = name, data.open
				DashRows.SizeDashRow(row, dash.width - DASH_PAD * 2, dash.rowHeight)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", panel, "TOPLEFT", DASH_PAD, -DASH_PAD - (count - 1) * dash.rowHeight)
				row:EnableMouseWheel(definition.onMouseWheel and true or false)
				row:EnableMouse(panel.mouseOn ~= false)
				DashRows.PaintDashRow(row, data, dash.rowHeight, dash.fontSize)
				row:Show()
			end
		end
	end
	for index = count + 1, #(panel.dashRows or {}) do panel.dashRows[index]:Hide() end
	panel:SetSize(dash.width, math.max(count, 1) * dash.rowHeight + DASH_PAD * 2)
end

function M:RebuildPanels()
	self.panelFrames = self.panelFrames or {}
	local panels = DB().panels
	for index = 1, MAX_PANELS do
		local frame = self.panelFrames[index]
		if panels[index] and not frame and self.active then frame = self:CreatePanel(index) end
		if frame then self:RebuildPanel(frame) end
	end
	self:SyncDock()
end

-- Add a panel (optionally with slots filled). Returns its index.
function M:AddPanel(name, slots, extra)
	local panels = self.db.panels
	if #panels >= MAX_PANELS then
		E:Print(L["You already have %d panels, the most there can be."]:format(MAX_PANELS))
		return nil
	end
	local panel = FillPanel({ name = name or ("Panel " .. (#panels + 1)) })
	panel.visibility = E:VisibilityDefaults()
	panel.slots = {}
	for index, slot in ipairs(slots or { "Time", "Gold", "Durability" }) do panel.slots[index] = slot end
	panel.numSlots = math.max(1, math.min(MAX_PANEL_SLOTS, #panel.slots))
	for key, value in pairs(extra or {}) do panel[key] = value end
	table.insert(panels, panel)
	self.db.editPanel = #panels
	if self.active then self:RebuildPanels() end
	self:SyncHearthOverlay()
	return #panels
end

-- A dashboard: durability, bags, tracked currencies, the watched
-- reputation and the professions as rows with bars, under the minimap's
-- column of the screen by default (its mover; layouts may place it).
function M:AddDashboardPanel()
	return self:AddPanel("Dashboard", { "Durability", "Bags", "Currencies", "Reputation", "Profession" },
		{ display = "dashboard", width = 240, height = 22, fontSize = 12 })
end

function M:AddStatsPanel()
	local stats = StatData.ClassStats()
	return self:AddPanel("Stats", stats, { vertical = true, width = 130, height = 16, fontSize = 11, numSlots = #stats })
end

-- Delete a panel. Later panels move up one place, and their saved mover
-- positions move with them.
function M:DeletePanel(index)
	local panels = self.db.panels
	if not panels[index] then return end
	table.remove(panels, index)
	E:ShiftMoverSlots(PANEL_BASE, index)
	self.db.editPanel = math.max(1, math.min(self.db.editPanel or 1, #panels))
	if self.active then self:RebuildPanels() end
	self:SyncHearthOverlay()
end

---------------------------------------------------------------------------
-- LibDataBroker bridge
--
-- EldoUI does not ship LibDataBroker. When another addon has loaded
-- LibDataBroker-1.1 through LibStub, every "data source" and "launcher" it
-- publishes becomes a datatext named "LDB: <name>" that can go in any slot.
-- The feed is plain addon data; EldoUI only shows what the object reports.
---------------------------------------------------------------------------
local LDB_PREFIX = "LDB: "

local function BrokerText(name, object)
	local db = M.db
	local text = object.text
	if object.type == "launcher" or text == nil or text == "" then
		text = object.label or name
	elseif db.ldbLabels and object.label then
		text = Label(tostring(object.label) .. " ") .. tostring(text)
	end
	text = tostring(text)
	local icon = object.icon
	if db.ldbIcons and icon and icon ~= "" then
		text = "|T" .. tostring(icon) .. ":0|t " .. text
	end
	return text
end

local function UsesDataText(key)
	local db = DB()
	for index = 1, 2 do
		local bar = BarDB(index)
		if bar and (index == 1 or bar.enabled) then
			for _, side in ipairs(SIDES) do
				local names = bar[side] or {}
				-- Every slot, also after an empty one.
				for slot = 1, math.max(SLOTS, #names) do
					if names[slot] == key then return true end
				end
			end
		end
	end
	for _, panel in ipairs(db.panels or {}) do
		if type(panel.slots) == "table" then
			for slot = 1, MAX_PANEL_SLOTS do
				if panel.slots[slot] == key then return true end
			end
		end
	end
	return false
end
M.UsesDataText = UsesDataText

function M:RefreshDataText(key)
	for _, holder in ipairs(AllHolders()) do
		for _, button in ipairs(holder.buttons) do
			if (button:IsShown() or button.fitHidden) and button.dataName == key then UpdateButton(button) end
		end
	end
end

function M:RegisterBroker(name, object)
	if type(name) ~= "string" or type(object) ~= "table" then return end
	if object.type ~= "data source" and object.type ~= "launcher" then return end
	-- EldoUI's own blocks offered to other addons (InfoBar/Broker.lua).
	if M.broker and M.broker.Owns(name) then return end
	local key = LDB_PREFIX .. name
	if E.dataTexts[key] then return end
	E.dataTexts[key] = {
		title = "LDB: " .. tostring(object.label or name),
		broker = true,
		text = function() return BrokerText(name, object) end,
		tooltip = (object.OnTooltipShow and not object.OnEnter) and function(tooltip) object.OnTooltipShow(tooltip) end or nil,
		onEnter = object.OnEnter and function(button) object.OnEnter(button) end or nil,
		onLeave = object.OnLeave and function(button) object.OnLeave(button) end or nil,
		onClick = object.OnClick and function(button, mouseButton) object.OnClick(button, mouseButton) end or nil,
	}
	-- A feed that registers after the bars were built: rebuild once, if a slot wants it.
	if self.active and UsesDataText(key) and not self.brokerRebuild then
		self.brokerRebuild = true
		C_Timer.After(0, function()
			M.brokerRebuild = nil
			if M.active then M:Rebuild() end
		end)
	end
end

function M:HookBrokers()
	if self.ldb or not self.db.ldb then return end
	local ldb = _G.LibStub and _G.LibStub("LibDataBroker-1.1", true)
	if not ldb or not ldb.RegisterCallback or not ldb.DataObjectIterator then return end
	self.ldb = ldb
	for name, object in ldb:DataObjectIterator() do self:RegisterBroker(name, object) end
	ldb.RegisterCallback(self, "LibDataBroker_DataObjectCreated", function(_, name, object)
		if M.db.ldb then M:RegisterBroker(name, object) end
	end)
	ldb.RegisterCallback(self, "LibDataBroker_AttributeChanged", function(_, name, attribute)
		if not M.active or not M.db.ldb or (M.broker and M.broker.Owns(name)) then return end
		if attribute == "text" or attribute == "label" or attribute == "icon" or attribute == "value" then
			M:RefreshDataText(LDB_PREFIX .. name)
		end
	end)
	if self.brokerWatcher then self.brokerWatcher:UnregisterAllEvents() end
end

-- Other addons can load the library after EldoUI, so look again as they load.
function M:WatchBrokers()
	if self.ldb or not self.db.ldb then return end
	self:HookBrokers()
	if self.ldb then return end
	if not self.brokerWatcher then
		self.brokerWatcher = CreateFrame("Frame")
		self.brokerWatcher:SetScript("OnEvent", function() M:HookBrokers() end)
	end
	self.brokerWatcher:RegisterEvent("ADDON_LOADED")
	self.brokerWatcher:RegisterEvent("PLAYER_LOGIN")
end

---------------------------------------------------------------------------
-- Blocks in Modules/InfoBar/ (session rates, mail, rolls): each one starts
-- and stops with the module.
---------------------------------------------------------------------------
M.extras = {}
function M:AddExtra(extra)
	table.insert(self.extras, extra)
	if self.active and extra.Enable then extra:Enable() end
end

function M:RunExtras(method)
	for _, extra in ipairs(M.extras) do
		if extra[method] then extra[method](extra) end
	end
end

---------------------------------------------------------------------------
-- Building everything
---------------------------------------------------------------------------
function M:Rebuild()
	local db = self.db
	if not self.bars[1] then self:CreateBar(1) end
	self:RebuildBar(self.bars[1])
	if E.movers[BAR_MOVERS[1]] then E.movers[BAR_MOVERS[1]]:Show() end
	if db.bar2.enabled then
		if not self.bars[2] then self:CreateBar(2) end
		self:RebuildBar(self.bars[2])
		-- Docked in the chat window, the bar has no box of its own.
		E.movers[BAR_MOVERS[2]]:SetShown(not self.bars[2].attachTo)
	elseif self.bars[2] then
		E:DetachVisibility(self.bars[2])
		self:PlaceBar(self.bars[2])
		self.bars[2]:Hide()
		self:SyncTab(2)
		self.bars[2]:UnregisterAllEvents()
		-- No "Second info bar" box in move mode while the bar is off.
		E.movers[BAR_MOVERS[2]]:Hide()
	end
	self:RebuildPanels()
	self:SyncHearthOverlay()
	-- The frames that give way to the second bar (the flight timer's spot
	-- rule) move when it gets or loses a box of its own.
	local boxed = self:Bar2HasBox()
	if boxed ~= (self.bar2Boxed or false) then
		self.bar2Boxed = boxed
		if E.ApplyWidePoints then E:ApplyWidePoints() end
	end
end

-- Does the second bar have a box of its own at the screen edge? Not while
-- it is off or docked in the chat window.
function M:Bar2HasBox()
	local bar, mover = self.bars[2], E.movers[BAR_MOVERS[2]]
	return self.active and self.db and self.db.bar2.enabled and bar ~= nil and not bar.attachTo and mover ~= nil and mover:IsShown() or false
end

-- Settings from before the shared visibility rules: "show on
-- mouseover" + faded opacity and "hide in combat" become a visibility block.
local function MigrateVisibility(db)
	if type(db) ~= "table" then return end
	local mouseover, combatHide, fadeAlpha = db.mouseover, db.combatHide, db.fadeAlpha
	if mouseover == nil and combatHide == nil and fadeAlpha == nil then return end
	if combatHide then
		db.visibility = E:VisibilityFromLegacy("nocombat", 0)
	elseif mouseover then
		db.visibility = E:VisibilityFromLegacy("mouseover", (tonumber(fadeAlpha) or 0) / 100)
	end
	db.mouseover, db.combatHide, db.fadeAlpha = nil, nil, nil
end

local function MigrateSettings(db)
	MigrateVisibility(db)
	MigrateVisibility(db.bar2)
	-- The second bar docks in the chat window now; one that was already on
	-- stays on its own mover, where the player has it.
	if not db.bar2DockChecked then
		if db.bar2.enabled then db.bar2.dock = "none" end
		db.bar2DockChecked = true
	end
	if type(db.panels) ~= "table" then db.panels = {} end
	for index = #db.panels, 1, -1 do
		if type(db.panels[index]) ~= "table" then table.remove(db.panels, index) end
	end
	while #db.panels > MAX_PANELS do table.remove(db.panels) end
	for _, panel in ipairs(db.panels) do FillPanel(panel) end
	if type(db.dt) ~= "table" then db.dt = {} end
end

function M:OnInitialize()
	MigrateSettings(self.db)
end

-- Combat: the combat-time block's own timer and the hearth overlay.
function M:OnCombat(inCombat)
	self:TrackCombat(inCombat)
	M.MarkMeters()
	if not inCombat and self.overlayPending then self:SyncSecureOverlays() end
end

function M:OnEnable()
	self.bars = self.bars or {}
	self.panelFrames = self.panelFrames or {}
	MigrateSettings(self.db)
	self:Rebuild()
	TrackMoney()
	self:RegisterEvent("PLAYER_MONEY", TrackMoney)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() M:OnCombat(true) end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() M:OnCombat(false) end)
	-- Battleground swap: rebuild when entering or leaving one.
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
		local inBattleground = InBattleground()
		if M.db.bgSwap and inBattleground ~= M.inBattleground then M:Rebuild() end
		M.inBattleground = inBattleground
	end)
	-- Events missed while the module was off: read the meter again.
	M.MarkMeters()
	for _, event in ipairs(M.METER_EVENTS) do self:RegisterEvent(event, M.MarkMeters) end
	self:RegisterEvent("TIME_PLAYED_MSG", function(_, _, total, level)
		if Plain(total) and Plain(level) then
			played.total, played.level, played.at = total, level, GetTime()
		end
	end)
	self:WatchBrokers()
	E.Ticker:Subscribe(TICK_KEY, 0.1, function(elapsed) M:TickHolders(elapsed) end, self)
	-- A full-width bar follows a new resolution or UI scale (after the scale
	-- itself is applied).
	local function Resize()
		C_Timer.After(0, function() if M.active then M:Rebuild() end end)
	end
	self:RegisterEvent("DISPLAY_SIZE_CHANGED", Resize)
	self:RegisterEvent("UI_SCALE_CHANGED", Resize)
	-- Movers of attached panels: re-place them when the chat or minimap moves.
	if not self.attachWatch then
		self.attachWatch = true
		for _, moverName in ipairs({ "EldoUI_Chat", "EldoUI_Minimap" }) do
			E:RegisterMoverCallback(moverName, function()
				if not M.active then return end
				if M.bars[2] and M.bars[2]:IsShown() then M:CheckBarDock(M.bars[2]) end
				M:RebuildPanels()
				M:SyncHearthOverlay()
			end)
		end
	end
	-- Refresh everything once the world has loaded (guild, friends, bags).
	C_Timer.After(2, function() if self.active then self:Rebuild() end end)
	if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
	self:RunExtras("Enable")
end

function M:OnDisable()
	E.Ticker:UnsubscribeOwner(self)
	self:RunExtras("Disable")
	for _, holder in ipairs(AllHolders()) do
		E:DetachVisibility(holder)
		holder:UnregisterAllEvents()
		holder:Hide()
	end
	for index in ipairs(self.panelFrames or {}) do
		local mover = E.movers[PanelMoverName(index)]
		if mover then mover:Hide() end
	end
	-- The chat text and the minimap icons take back the docked panels' room.
	self:SyncDock()
	for _, name in ipairs(BAR_MOVERS) do
		if E.movers[name] then E.movers[name]:Hide() end
	end
	-- The flight timer takes back its own spot.
	if self.bar2Boxed then
		self.bar2Boxed = false
		if E.ApplyWidePoints then E:ApplyWidePoints() end
	end
	for _, tab in pairs(self.tabs) do tab:Hide() end
	self:UnregisterEvent("PLAYER_MONEY")
	self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self:UnregisterEvent("TIME_PLAYED_MSG")
	self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
	StopBarDrag()
	E:RunOutOfCombat(function()
		if M.active then return end
		for _, overlay in pairs(M.overlays) do
			UnregisterStateDriver(overlay, "visibility")
			overlay.target = nil
			overlay:Hide()
		end
	end)
end

function M:OnProfileChanged()
	MigrateSettings(self.db)
	if self.active then self:Rebuild() end
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function DataTextValues()
	local values = { [""] = L["(empty)"] }
	for name, definition in pairs(E.dataTexts) do
		if not definition.broker or M.db.ldb then values[name] = definition.title or name end
	end
	return values
end

local function SlotOptions(prefix, side, label, hidden)
	local options = { { type = "header", label = label, hidden = hidden } }
	for slot = 1, SLOTS do
		table.insert(options, { type = "select", key = prefix .. side .. "." .. slot, label = "%s slot %d", labelFill = { label, slot }, values = DataTextValues,
			desc = "The datatext shown in slot %d of the %s section.", descFill = function() return { slot, E:InSentence(L[label]) } end, hidden = hidden })
	end
	return options
end

local function BarLookOptions(prefix, hidden)
	local rows = {
		{ type = "range", key = prefix .. "width", label = "Width", min = 0, max = 2560, step = 10, zeroText = "Full", desc = "Width in pixels. Full spans the whole screen.", hidden = hidden },
		{ type = "range", key = prefix .. "height", label = "Height", min = 16, max = 48, step = 1, desc = "Height of the bar in pixels.", hidden = hidden },
		{ type = "range", key = prefix .. "fontSize", label = "Text size", min = 8, max = 20, step = 1, desc = "Text size of every datatext on this bar.", hidden = hidden },
		{ type = "toggle", key = prefix .. "backdrop", label = "Background", desc = "Draw the bar's dark background and border. Off leaves only the text.", hidden = hidden,
			cog = {
				{ type = "range", key = prefix .. "backdropAlpha", label = "Background opacity", unit = "%", min = 0, max = 100, step = 5, desc = "How see-through the background is." },
			} },
		{ type = "select", key = prefix .. "collapsed", label = "Bar shown", values = { open = "Open", tab = "Folded to a tab", hidden = "Hidden" }, order = { "open", "tab", "hidden" },
			desc = "Fold the bar to a small tab at its right end (hover the tab to see the bar, click it to open) or hide it. Frames placed against the bar stay where they are. Also /eui infobar and a key binding.", hidden = hidden },
		{ type = "toggle", key = prefix .. "collapseControl", label = "Fold button", desc = "A small arrow at the bar's right end: click folds the bar to a tab, right-click hides it.", hidden = hidden },
		{ type = "select", key = prefix .. "tooltipAnchor", label = "Tooltips open", desc = "Above or below the bar; pick below for a bar along the top edge.",
			values = { AUTO = "Away from the screen edge", TOP = "Above the bar", BOTTOM = "Below the bar" }, hidden = hidden },
	}
	for _, row in ipairs(E:VisibilityOptions(prefix .. "visibility", { db = function() return M.db end, hidden = hidden })) do
		table.insert(rows, row)
	end
	return rows
end

local function Bar2Off() return not M.db.bar2.enabled end

M.options = {
	{ type = "tab", label = "Main bar" },
	{ type = "header", label = "Bar" },
}
for _, option in ipairs(BarLookOptions("")) do table.insert(M.options, option) end
table.insert(M.options, { type = "toggle", key = "shiftDrag", label = "Shift+drag to move", desc = "Hold Shift and drag anywhere on a bar or panel to move it. Saved like move mode; not in combat." })
for _, section in ipairs({ { "left", "Left" }, { "center", "Center" }, { "right", "Right" } }) do
	for _, option in ipairs(SlotOptions("", section[1], section[2])) do table.insert(M.options, option) end
end

table.insert(M.options, { type = "tab", label = "Second bar" })
-- Grayed like the Two bars style where the layout has no free edge for a
-- second bar; a bar that is on can always be turned off.
local function Bar2NoRoom()
	if M.db.bar2.enabled then return nil end
	local fits, reason = E:StyleFits(E.db and E.db.general.layout, "InfoBar", "TwoBars")
	if not fits then return reason end
end
table.insert(M.options, { type = "toggle", key = "bar2.enabled", label = "Second info bar", desc = "A second bar with its own datatexts. It sits in the top edge of the chat window, or on its own mover.",
	disabled = Bar2NoRoom })
table.insert(M.options, { type = "select", key = "bar2.dock", label = "Place", hidden = Bar2Off,
	values = { chat = "In the chat window (top edge)", none = "Its own mover" }, order = { "chat", "none" },
	desc = "In the chat window: the bar fills the top edge of the chat box, as wide as the chat, and the messages and docked panels make room. Its own mover: drag it in move mode." })
for _, option in ipairs(BarLookOptions("bar2.", Bar2Off)) do
	-- Docked, the bar takes the chat window's width.
	if option.key == "bar2.width" then
		option.disabled = function()
			if M.db.bar2.dock == "chat" then return L["In the chat window the bar is as wide as the chat."] end
		end
	end
	table.insert(M.options, option)
end
for _, section in ipairs({ { "left", "Left" }, { "center", "Center" }, { "right", "Right" } }) do
	for _, option in ipairs(SlotOptions("bar2.", section[1], section[2], Bar2Off)) do table.insert(M.options, option) end
end

-- Panels tab: rows edit whichever panel is picked in "Edit panel".
local function SelectedIndex()
	local panels = M.db.panels
	local index = tonumber(M.db.editPanel) or 1
	if not panels[index] then index = #panels > 0 and 1 or nil end
	return index
end

local function SelectedPanel()
	local index = SelectedIndex()
	return index and M.db.panels[index]
end

local function NoPanel() return SelectedPanel() == nil end

-- Hidden unless the picked panel shows as a dashboard.
local function NotDashboard()
	local panel = SelectedPanel()
	return not panel or panel.display ~= "dashboard"
end

local function PanelKey(field)
	return function() return ("panels.%d.%s"):format(SelectedIndex() or 1, field) end
end

local function PanelValues()
	local values = {}
	for index, panel in ipairs(M.db.panels) do
		values[index] = ("%d. %s"):format(index, panel.name or L["Panel %d"]:format(index))
	end
	return values
end

local function AfterPanelChange()
	if M.active then M:RebuildPanels() end
	E:RefreshConfig()
end

local PANEL_OPTIONS = {
	{ type = "tab", label = "Panels" },
	{ type = "header", label = "Your panels" },
	{ type = "description", label = "Up to eight datatext panels of your own, anywhere on screen with a mover, or docked in the chat window or on the minimap." },
	{ type = "execute", label = "Add a panel", testSafe = true,
		desc = "A new horizontal panel with three slots (clock, gold, durability) at the top of the screen. Change it below.",
		func = function() M:AddPanel() AfterPanelChange() end },
	{ type = "execute", label = "Add a stats panel", testSafe = true,
		desc = "A new vertical panel with eight character stats picked for your class. In combat the game hides some stats; they show a dash until the fight ends.",
		func = function() M:AddStatsPanel() AfterPanelChange() end },
	{ type = "execute", label = "Add a dashboard", testSafe = true,
		desc = "A new panel in Dashboard display: durability, bag space, your tracked currencies, the reputation you watch and your professions, each as a row with a bar. Change its rows below.",
		func = function() M:AddDashboardPanel() AfterPanelChange() end },
	{ type = "execute", label = "Move panels", desc = "Unlock EldoUI frames to drag the panels (not attached ones).", func = function() E:ToggleMoveMode() end },
	{ type = "select", key = "editPanel", label = "Edit panel", values = PanelValues, hidden = NoPanel,
		desc = "The panel the rows below change." },
	E:CopySettingsOptions({ path = function() return "panels." .. (SelectedIndex() or 1) end,
		values = function()
			local values = {}
			for index, label in pairs(PanelValues()) do values["panels." .. index] = label end
			return values
		end,
		keep = { "name", "enabled" }, hidden = function() return #M.db.panels < 2 end,
		desc = "Copy the slots, look and place of another panel onto this one, with a preview of what changes first. Its name, Shown switch and position stay as they are." })[1],
	{ type = "header", label = "Panel", hidden = NoPanel },
	{ type = "input", key = PanelKey("name"), label = "Name", hidden = NoPanel, desc = "A name for this panel, shown in the list above." },
	{ type = "toggle", key = PanelKey("enabled"), label = "Shown", hidden = NoPanel, desc = "Show this panel. Off keeps its settings without showing it." },
	{ type = "range", key = PanelKey("numSlots"), label = "Slots", min = 1, max = MAX_PANEL_SLOTS, step = 1, hidden = NoPanel,
		desc = "How many datatexts the panel has. The slots share its width (or height when vertical) evenly." },
}
for slot = 1, MAX_PANEL_SLOTS do
	table.insert(PANEL_OPTIONS, { type = "select", key = PanelKey("slots." .. slot), label = "Slot %d", labelFill = slot, values = DataTextValues,
		desc = "The datatext in slot %d of this panel.", descFill = slot,
		hidden = function()
			local panel = SelectedPanel()
			return not panel or slot > (tonumber(panel.numSlots) or 0)
		end })
end
local PANEL_LOOK = {
	{ type = "header", label = "Panel look", hidden = NoPanel },
	{ type = "select", key = PanelKey("display"), label = "Display", hidden = NoPanel,
		values = { ["text"] = "Text", dashboard = "Dashboard" }, order = { "text", "dashboard" },
		desc = "Text: each slot shows its datatext as a short line. Dashboard: one row per value with an icon and a thin bar (durability, bag space, currencies), yellow then red when running low." },
	{ type = "preview", label = "Dashboard preview", height = 5 * 22 + 8, hidden = NotDashboard,
		desc = "How a dashboard looks with sample values, in your art style and accent.",
		create = function(canvas)
			if not canvas then return end
			local holder = CreateFrame("Frame", nil, canvas)
			holder:SetPoint("TOPLEFT", 0, 0)
			holder:SetSize(240, 5 * 22 + 8)
			E:SetPanelTemplate(holder, true)
			holder.rows = {}
			for index = 1, 5 do
				local row = M.CreateDashRow(holder)
				M.SizeDashRow(row, 232, 22)
				row:SetPoint("TOPLEFT", holder, "TOPLEFT", 4, -4 - (index - 1) * 22)
				row:EnableMouse(false)
				holder.rows[index] = row
			end
			canvas.dash = holder
		end,
		update = function(canvas)
			local holder = canvas and canvas.dash
			if not holder then return end
			local panel = SelectedPanel()
			local fontSize = panel and tonumber(panel.fontSize) or 12
			for index, data in ipairs(SampleDashboardRows()) do
				local row = holder.rows[index]
				if row then M.PaintDashRow(row, data, 22, math.min(fontSize, 14)) end
			end
		end },
	{ type = "toggle", key = PanelKey("vertical"), label = "Vertical", hidden = function() return NoPanel() or not NotDashboard() end,
		desc = "Stack the slots top to bottom instead of side by side." },
	{ type = "range", key = PanelKey("width"), label = "Width", min = 100, max = 1200, step = 10, hidden = NoPanel, desc = "Width of the panel in pixels." },
	{ type = "range", key = PanelKey("height"), label = "Slot height", min = 14, max = 48, step = 1, hidden = NoPanel, desc = "Height of each slot in pixels." },
	{ type = "range", key = PanelKey("fontSize"), label = "Text size", min = 8, max = 20, step = 1, hidden = NoPanel, desc = "Text size in this panel." },
	{ type = "toggle", key = PanelKey("backdrop"), label = "Background", hidden = NoPanel,
		desc = "Draw a background behind the panel. Off leaves only the text, which can be hard to read on a bright minimap.",
		cog = {
			{ type = "range", key = PanelKey("backdropAlpha"), label = "Background opacity", unit = "%", min = 0, max = 100, step = 5, desc = "How see-through the background is." },
			{ type = "toggle", key = PanelKey("border"), label = "Border", desc = "Draw the thin border around the panel." },
		} },
	{ type = "select", key = PanelKey("strata"), label = "Layer", hidden = NoPanel,
		values = { BACKGROUND = "Background", LOW = "Low", MEDIUM = "Medium", HIGH = "High" },
		desc = "Which layer the panel draws on: higher layers cover lower ones." },
	{ type = "select", key = PanelKey("tooltipAnchor"), label = "Tooltips open", hidden = NoPanel,
		values = { AUTO = "Away from the screen edge", TOP = "Above", BOTTOM = "Below", LEFT = "Left", RIGHT = "Right" },
		desc = "Where the tooltips of this panel's blocks open." },
	{ type = "select", key = PanelKey("attach"), label = "Place", hidden = NoPanel,
		values = { none = "Its own mover", chat = "In the chat window (top edge)", minimap = "On the minimap (bottom edge)" },
		order = { "none", "chat", "minimap" },
		-- A full chat window or minimap can't take one more.
		valueDisabled = function(value)
			local index = SelectedIndex()
			if not (index and DOCK_LIMIT[value]) or Docking.DockSlot(index, value) then return nil end
			if #DockedIndices(value) >= Docking.Limit(value) then
				return value == "chat" and Docking.BarDocks() and Docking.DOCK_FULL.withBar or Docking.DOCK_FULL[value]
			end
		end,
		desc = "Its own mover: drag it in move mode. In the chat window (up to three, the docked second info bar counts as one) or on the minimap (two): it sits inside the edge, moves along and the frame makes room." },
	{ type = "toggle", key = PanelKey("attachWidth"), label = "Same width as the chat or minimap", desc = "Docked panels take the width of the chat window (right of its side buttons) or of the minimap.",
		hidden = function()
			local panel = SelectedPanel()
			return not panel or panel.attach == "none"
		end },
}
for _, option in ipairs(PANEL_LOOK) do table.insert(PANEL_OPTIONS, option) end
-- The shared visibility rows, re-pointed at the selected panel.
for _, row in ipairs(E:VisibilityOptions("visibility", { db = SelectedPanel, hidden = NoPanel, label = "Panel visibility" })) do
	if type(row.key) == "string" then
		local field = row.key
		row.key = PanelKey(field)
	end
	table.insert(PANEL_OPTIONS, row)
end
table.insert(PANEL_OPTIONS, { type = "execute", label = "Delete this panel", hidden = NoPanel,
	desc = "Remove the panel picked above (asks first). Panels after it move up one place.",
	func = function()
		local index = SelectedIndex()
		local panel = index and M.db.panels[index]
		if not panel then return end
		local work = function() M:DeletePanel(index) AfterPanelChange() end
		E:ConfigConfirm(L["Delete the panel \"%s\"?"]:format(panel.name or index), work,
			{ title = L["Delete panel"], accept = DELETE or L["Delete"], danger = true })
	end })
for _, option in ipairs(PANEL_OPTIONS) do table.insert(M.options, option) end

-- Datatexts tab: formats, colors, labels and the custom currencies.
local function LabelledValues()
	local values = {}
	for name, definition in pairs(E.dataTexts) do
		if definition.label or definition.icon then values[name] = definition.title or name end
	end
	return values
end

local function EditedDataText()
	local name = M.db.dtEdit
	if not (name and E.dataTexts[name]) then name = "Durability" end
	return name
end

-- The label rows edit dt.<name>; make sure that table exists first.
local function DataTextKey(field)
	return function()
		local name = EditedDataText()
		M.db.dt = M.db.dt or {}
		if type(M.db.dt[name]) ~= "table" then M.db.dt[name] = { label = "default", custom = "" } end
		return ("dt.%s.%s"):format(name, field)
	end
end

local DATATEXT_OPTIONS = {
	{ type = "tab", label = "Datatexts" },
	{ type = "header", label = "Colors" },
	{ type = "select", key = "labelColor", label = "Label color", values = { accent = "Accent", class = "Class color", white = "White", grey = "Gray" },
		desc = "Color of the labels (\"Dur\", \"Gold\" and so on)." },
	{ type = "select", key = "valueColor", label = "Value color", values = { white = "White", class = "Class color", accent = "Accent" },
		desc = "Color of plain values. Warnings keep their own colors (yellow, red)." },
	{ type = "range", key = "latencyWarn", label = "Latency warning", unit = "ms", min = 50, max = 500, step = 10, desc = "Latency turns yellow at this value." },
	{ type = "range", key = "latencyBad", label = "Latency bad", unit = "ms", min = 100, max = 1000, step = 10, desc = "Latency turns red at this value." },
	{ type = "execute", label = "Durability colors", keywords = "durability warning low",
		desc = "When durability turns yellow and red is set once for every module, on the General page (Clock and durability).",
		func = function() E:ToggleConfig("general") end },
	{ type = "range", key = "cpuWarn", label = "CPU warning", unit = "ms", min = 0.5, max = 10, step = 0.5, desc = "The CPU datatext turns yellow when all addons together take this long per frame." },
	{ type = "range", key = "cpuBad", label = "CPU high", unit = "ms", min = 1, max = 20, step = 0.5, desc = "The CPU datatext turns red at this value." },
	{ type = "range", key = "ammoWarn", label = "Ammo warning", min = 0, max = 1000, step = 50, desc = "The Ammo datatext turns yellow at or below this many." },
	{ type = "toggle", key = "bgSwap", label = "Battleground score in battlegrounds",
		desc = "In a battleground the main bar's center shows your score and the fight time instead of its usual blocks." },
	{ type = "header", label = "Labels" },
	{ type = "select", key = "dtEdit", label = "Datatext", values = LabelledValues, desc = "The datatext whose label the next two rows change." },
	{ type = "select", key = DataTextKey("label"), label = "Label", values = { default = "Standard", none = "No label", custom = "My own text", icon = "Icon" },
		desc = "Standard: EldoUI's short label. No label: the value only. My own text: the text below. Icon: a small icon (where the datatext has one)." },
	{ type = "input", key = DataTextKey("custom"), label = "Own label text", desc = "Shown in front of the value when the label is set to \"My own text\".",
		hidden = function()
			local settings = DataTextSettings(EditedDataText())
			return not settings or settings.label ~= "custom"
		end },
	{ type = "header", label = "Time and date" },
	{ type = "execute", label = "Clock format", keywords = "24-hour 12-hour time",
		desc = "24-hour or 12-hour time is set once for every EldoUI clock, on the General page (Clock and durability).",
		func = function() E:ToggleConfig("general") end },
	{ type = "select", key = "timeSource", label = "Clock shows", values = { ["local"] = "Your computer's time", realm = "Realm time" },
		desc = "Which time the Time datatext shows; its tooltip lists both." },
	{ type = "select", key = "dateFormat", label = "Date format", values = { dmy = "31.12.2026", mdy = "12/31/2026", iso = "2026-12-31", long = "Thu Dec 31" },
		desc = "How the Date datatext writes the date." },
	{ type = "header", label = "Gold" },
	{ type = "select", key = "goldFormat", label = "Gold format", values = { gold = "Gold only", full = "Gold, silver, copper", short = "Short (12.3k g)" },
		desc = "How the Gold datatext shows your money." },
	{ type = "select", key = "goldFilter", label = "Characters in the gold tooltip",
		values = { all = "All characters", realm = "This realm", current = "This character" },
		desc = "Which characters the gold tooltip lists. Right-click the gold datatext to switch." },
	{ type = "header", label = "Numbers" },
	{ type = "select", key = "coordDecimals", label = "Coordinate precision", desc = "Decimals in the Coords datatext.",
		values = { [0] = "45, 62", [1] = "45.3, 62.1", [2] = "45.27, 62.08" } },
	{ type = "select", key = "statDecimals", label = "Stat decimals", desc = "Decimals of percentage stats (crit, hit, dodge and so on).",
		values = { [0] = "12%", [1] = "12.3%", [2] = "12.34%" } },
	{ type = "header", label = "Custom currencies" },
	{ type = "description", label = "Put \"Custom currency 1-4\" in any slot and pick its currency here. The list shows the currencies of open headers in your currency tab." },
}
for slot = 1, 4 do
	table.insert(DATATEXT_OPTIONS, { type = "select", key = "currency" .. slot, label = "Custom currency %d", labelFill = slot, values = CurrencyChoices,
		desc = "The currency the \"Custom currency %d\" datatext shows.", descFill = slot })
end
local LDB_OPTIONS = {
	{ type = "header", label = "Other addons (LibDataBroker)" },
	{ type = "toggle", key = "ldb", label = "Show LibDataBroker feeds", desc = "When another addon provides LibDataBroker, its feeds can be picked as \"LDB: name\" in any slot. Turning this off takes effect after a reload.", reload = true },
	{ type = "toggle", key = "ldbIcons", label = "Feed icons", desc = "Show each feed's icon in front of its text.", hidden = function() return not M.db.ldb end },
	{ type = "toggle", key = "ldbLabels", label = "Feed labels", desc = "Show each feed's label in front of its value.", hidden = function() return not M.db.ldb end },
}
-- The other way round: Info Bar blocks for other addons' displays
-- (InfoBar/Broker.lua), once an addon has loaded LibDataBroker.
local function BrokerLoaded()
	return _G.LibStub ~= nil and _G.LibStub("LibDataBroker-1.1", true) ~= nil
end
local function OfferedValues()
	local values = { [""] = L["(empty)"] }
	for name, definition in pairs(E.dataTexts) do
		if not definition.broker then values[name] = definition.title or name end
	end
	return values
end
table.insert(LDB_OPTIONS, { type = "description", hidden = BrokerLoaded,
	label = "Titan Panel, ChocolateBar and other LibDataBroker displays can show Info Bar blocks once one of them is loaded." })
for slot = 1, #M.defaults.ldbBlocks do
	table.insert(LDB_OPTIONS, { type = "select", key = "ldbBlocks." .. slot, label = "Block %d for other addons", labelFill = slot,
		values = OfferedValues, hidden = function() return not BrokerLoaded() end,
		desc = "A block other addons can show: Titan Panel, ChocolateBar and the like list it as \"EldoUI: name\". It is kept up to date while it is chosen here, also in combat. A block taken out again stays in their list until a reload." })
end
for _, option in ipairs(LDB_OPTIONS) do table.insert(DATATEXT_OPTIONS, option) end
for _, option in ipairs(DATATEXT_OPTIONS) do table.insert(M.options, option) end

---------------------------------------------------------------------------
-- Style presets: the datatexts, the bar height, the text size and the
-- label colors. A style never moves a bar (the layout owns the places).
---------------------------------------------------------------------------
local FULL = { left = { "Friends", "Guild", "Profession" }, center = { "Time" }, right = { "Class", "Bags", "Durability", "Gold", "FPS", "Latency", "Memory" } }
local SLIM = { left = {}, center = { "Time" }, right = { "Gold", "FPS", "Latency", "Memory" } }
local function Info(slots, height, fontSize, labelColor)
	return { left = slots.left, center = slots.center, right = slots.right, height = height or 28, fontSize = fontSize or 14,
		labelColor = labelColor or "accent", valueColor = "white" }
end

E:RegisterStyles("InfoBar", {
	{ key = "Full", title = "Full", desc = "Every datatext on the info bar.", settings = Info(FULL) },
	{ key = "Slim", title = "Minimal", desc = "Clock, gold, FPS and latency only, on a 24 px bar.", settings = Info(SLIM, 24, 13) },
	{ key = "Bold", title = "Bold", desc = "Taller bar with 16 pt text.", settings = Info(FULL, 34, 16) },
	{ key = "Class", title = "Class colors", desc = "Every datatext, labels in your class color and white values.",
		settings = Info(FULL, 28, 14, "class") },
	{ key = "Quiet", title = "Quiet", desc = "Every datatext on a 24 px bar, gray labels and white values.",
		settings = Info(FULL, 24, 13, "grey") },
	{ key = "TwoBars", title = "Two bars", desc = "Social and money on the info bar, place and progress on a second bar.",
		settings = {
			height = 28, fontSize = 14,
			left = { "Friends", "Guild", "Menu" }, center = { "Time" }, right = { "Bags", "Durability", "Gold", "FPS", "Latency" },
			bar2 = { enabled = true, height = 24, fontSize = 13,
				left = { "Zone", "Coords" }, center = { "XP" }, right = { "Reputation" } },
		} },
	{ key = "Levelling", title = "Leveling", desc = "Info bar with XP, zone and coordinates for questing.",
		settings = {
			height = 28, fontSize = 14,
			left = { "Zone", "Coords", "Hearthstone" }, center = { "XP" }, right = { "Bags", "Durability", "Gold", "Latency" },
			bar2 = { enabled = false },
		} },
}, { restores = { "bar2.enabled" } })
