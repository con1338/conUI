-- EldoUI XP and reputation bars.
--
-- EldoUI's own thin progress bars in one stack on the EldoUI_XPBar mover:
-- experience with rested XP and the XP of finished quests not yet handed in,
-- session XP per hour and time to level, the watched reputation, honor,
-- your threat on the target (from E:GetThreat, Modules/CombatHUD/Threat.lua)
-- and (Forever hunters) pet experience. Leveling is the main Forever
-- activity, so the XP bar is the first in the stack and hides at the level cap.
-- Extras: divider ticks, a vertical stack, hide in combat, a click
-- that opens the matching game panel, and (off by default) watching the
-- reputation you last gained.
--
-- Blizzard's own bars (MainStatusTrackingBarContainer and
-- SecondaryStatusTrackingBarContainer from Blizzard_StatusTrackingBar) are
-- the Blizzard UI element "status-tracking-bars". Its switches decide what
-- EldoUI may do with them:
--   replace  EldoUI's bars, Blizzard's hidden
--   skin     flat 1 px frame on Blizzard's bars (when not replaced)
--   move     Blizzard's bars sit on the EldoUI_XPBar mover (when not replaced)
--   hide     Blizzard's bars hidden, no EldoUI bars
-- XP, rested XP, reputation and honor are not combat data; the
-- values are still checked with issecretvalue before any math.
local _, E = ...
local L = E.L

local Key = E.Key
local ELEMENT = "status-tracking-bars"

local M = E:NewModule("StatusBars", {
	title = "XP and Reputation Bars",
	desc = "Experience, rested XP, reputation, honor and pet experience bars in one movable stack.",
	category = "Interface",
	frames = { "EldoUI_XPBar" },
	movers = { "EldoUI_XPBar" },
	blizzard = { "status-tracking-bars" },
	savedKeys = { "profile.modules.StatusBars" },
	optionsPage = "module:StatusBars",
	presets = { "Classic", "Compact", "Endgame", "Hidden", "Levelling", "Thin" },
	defaults = {
		width = 620,
		height = 8,
		spacing = 3,
		grow = "UP",            -- further bars stack above (UP) or below (DOWN) the first one
		textMode = "percent",   -- none, percent, current, remaining, full
		textShow = "hover",     -- always, hover
		textLabel = true,       -- "XP", faction name, ... in front of the numbers
		fontSize = 11,
		tooltip = true,
		ticks = 0,              -- divider lines on each bar (0-20)
		vertical = false,       -- bars stand upright, side by side
		fillTag = false,        -- upright bars: the percent in a small tag beside the fill end
		fillTagSide = "RIGHT",  -- RIGHT or LEFT of the stack
		visibility = E:VisibilityDefaults(), -- the shared visibility rules
		clickOpens = true,      -- left-click opens the matching panel
		xp = { enabled = true, rested = true, hideAtMax = true, quests = true, session = true, toCap = true, bonusMark = false,
			color = { 0.58, 0.0, 0.55 }, restedColor = { 0.0, 0.39, 0.88 }, questColor = { 1.0, 0.82, 0.0 } },
		rep = { enabled = true, reactionColor = true, color = { 0.0, 0.6, 0.1 }, onlyWhenMax = false, autoTrack = false },
		honor = { enabled = true, show = "pvp", color = { 1.0, 0.71, 0.0 } },   -- show: always, pvp
		pet = { enabled = true, color = { 0.58, 0.0, 0.55 } },
		threat = { enabled = false, statusColor = true, color = { 0.85, 0.25, 0.2 }, onlyGroup = false },
		blizzard = { textSize = 11 },
		details = { folded = {} }, -- the details window: folded sections, where it was left
	},
})
E:RegisterVisibilityFacet("EldoUI_XPBar", "rules", { module = "StatusBars", setting = "visibility" })

local BAR_KEYS = { "xp", "rep", "honor", "pet", "threat" }
local BAR_TITLES = E:TranslateValues({ xp = E.Key("Experience"), rep = E.Key("Reputation"), honor = E.Key("Honor"), pet = E.Key("Pet experience"), threat = E.Key("Threat") })

local IsSecret = E.Secret

-- Plain numbers only; anything secret or missing reads as nil.
local function Number(value)
	if IsSecret(value) or type(value) ~= "number" then return nil end
	return value
end

local function Short(value)
	return E:FormatNumber(value)
end

-- Length of a bar. Width 0 means the full screen width (height when vertical).
local function BarWidth(db)
	if db.width and db.width > 0 then return db.width end
	return math.floor((db.vertical and UIParent:GetHeight() or UIParent:GetWidth()) + 0.5)
end

local function Long(value)
	if BreakUpLargeNumbers then return BreakUpLargeNumbers(value) end
	return tostring(value)
end

---------------------------------------------------------------------------
-- Reading the game's data. Each reader returns a table or nil (bar hidden):
--   { min, max, value, extra (rested end), label, color = {r,g,b}, extraText }
---------------------------------------------------------------------------
-- XP waiting in finished quests that are not handed in yet (count, quests).
local function CompletedQuestXP() return E.LevelXP.FinishedQuestXP() end

-- Session statistics: the core's session count (E.PlayRates,
-- Core/PlayRates.lua), the same one the Info Bar and My Adventure read.
-- { elapsed, gained, perHour, toLevel, seconds, questXP, questCount,
-- rested }; perHour and seconds stay nil until two minutes and some XP
-- have gone by. Read only.
function M:Pace()
	local rates = E.PlayRates
	local current, maximum = Number(UnitXP("player")), Number(UnitXPMax("player"))
	local out = { gained = rates.session and rates.session.xp or 0, elapsed = rates:Elapsed(),
		rested = Number(GetXPExhaustion and GetXPExhaustion()) or 0 }
	if current and maximum and maximum > 0 then out.toLevel = math.max(0, maximum - current) end
	local perHour = rates:Rate("xp")
	if perHour and perHour > 0 then
		out.perHour = perHour
		out.seconds = rates:TimeToLevel()
	end
	out.questXP, out.questCount = CompletedQuestXP()
	return out
end

-- XP still needed to reach the level cap from the game's level list, and
-- the cap; nil at the cap, with the option off or past the list.
function M.XPToCap(data, left)
	if not (M.db.xp.toCap and E.LevelXP and data and data.level) then return nil end
	local maxLevel = Number(GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
	local level = Number(data.level)
	if not level or level >= maxLevel then return nil end
	return E.LevelXP.ToLevel(maxLevel, level, left), maxLevel
end

local function FormatHours(seconds)
	if seconds >= 3600 then return L["%dh %dm"]:format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)) end
	return L["%dm"]:format(math.max(1, math.floor(seconds / 60)))
end

local readers = {}
M.readers = readers -- read-only, for plugins

-- Another addon can draw its own XP and reputation bars: while one does
-- (Data/Competitors.lua), EldoUI's bar of that kind stays hidden.
function M:OnStandBack()
	self:Refresh()
end

function readers.xp(db)
	if IsXPUserDisabled and IsXPUserDisabled() then return nil end
	if E:StandsBack(M, "xp") then return nil end
	if db.xp.hideAtMax and E:AtMaxLevel() then return nil end
	local current, maximum = Number(UnitXP("player")), Number(UnitXPMax("player"))
	if not current or not maximum or maximum <= 0 then return nil end
	local data = { min = 0, max = maximum, value = current, label = L["XP"], color = db.xp.color }
	local rested = db.xp.rested and Number(GetXPExhaustion and GetXPExhaustion())
	if rested and rested > 0 then
		data.extra = math.min(maximum, current + rested)
		data.rested = rested
		data.extraColor = db.xp.restedColor
	end
	if db.xp.quests then
		local questXP, questCount = CompletedQuestXP()
		if questXP > 0 then
			data.quest = math.min(maximum, current + questXP)
			data.questXP, data.questCount = questXP, questCount
			data.questColor = db.xp.questColor
		end
	end
	data.level = UnitLevel("player")
	return data
end

-- Friendship factions use their own standing table.
local function FriendshipInfo(factionID)
	if not (C_GossipInfo and C_GossipInfo.GetFriendshipReputation) or not factionID then return nil end
	local ok, info = pcall(C_GossipInfo.GetFriendshipReputation, factionID)
	if ok and type(info) == "table" and (info.friendshipFactionID or 0) > 0 then return info end
end

function readers.rep(db)
	if E:StandsBack(M, "rep") then return nil end
	if not (C_Reputation and C_Reputation.GetWatchedFactionData) then return nil end
	if db.rep.onlyWhenMax and not E:AtMaxLevel() then return nil end
	local faction = C_Reputation.GetWatchedFactionData()
	if not faction or not faction.name or faction.name == "" then return nil end
	local low, high, value = Number(faction.currentReactionThreshold), Number(faction.nextReactionThreshold), Number(faction.currentStanding)
	local standing = _G["FACTION_STANDING_LABEL" .. tostring(faction.reaction)] or ""
	local friendship = FriendshipInfo(faction.factionID)
	if friendship then
		low, value = Number(friendship.reactionThreshold), Number(friendship.standing)
		high = Number(friendship.nextThreshold) or value
		standing = friendship.reaction or standing
	end
	if not low or not high or not value then return nil end
	if high <= low then low, high, value = 0, 1, 1 end -- top standing: a full bar
	local color = db.rep.color
	if db.rep.reactionColor then
		-- The shared reaction colors (Colors page overrides, then the game's).
		local r, g, b = E:GetReactionColor(faction.reaction)
		if r then color = { r, g, b } end
	end
	return { min = low, max = high, value = value, label = faction.name, standing = standing, color = color,
		factionID = faction.factionID, reaction = faction.reaction }
end

local function InPvP()
	if C_PvP and C_PvP.IsActiveBattlefield and C_PvP.IsActiveBattlefield() then return true end
	if IsInActiveWorldPVP and IsInActiveWorldPVP() then return true end
	local _, instanceType = IsInInstance()
	return instanceType == "pvp" or instanceType == "arena"
end

-- Honor: Forever's honor points, filling toward the most you can hold.
local HONOR_CURRENCIES = { 1901, 1792 }
local function HonorCurrency()
	local currency = C_CurrencyInfo
	if not (currency and currency.GetCurrencyInfo) then return nil end
	for _, id in ipairs(HONOR_CURRENCIES) do
		local ok, info = pcall(currency.GetCurrencyInfo, id)
		if ok and type(info) == "table" and type(info.name) == "string" and not IsSecret(info.name) and info.name ~= "" then return info end
	end
end

function readers.honor(db)
	if db.honor.show == "pvp" and not InPvP() then return nil end
	local info = HonorCurrency()
	local amount, cap = info and Number(info.quantity), info and Number(info.maxQuantity)
	if not amount or not cap or cap <= 0 then return nil end
	return { min = 0, max = cap, value = math.min(amount, cap), label = info.name, color = db.honor.color }
end
M.HonorCurrency = HonorCurrency

function readers.pet()
	if not (HasPetUI and GetPetExperience) then return nil end
	local hasUI, isHunterPet = HasPetUI()
	if not hasUI or not isHunterPet then return nil end
	local rawCurrent, rawMax = GetPetExperience()
	local current, maximum = Number(rawCurrent), Number(rawMax)
	if not current or not maximum or maximum <= 0 then return nil end
	return { min = 0, max = maximum, value = current, label = E:GameText(PET, L["Pet"]), level = UnitLevel("pet"), color = M.db.pet.color }
end

-- Your threat on the target, from the game (E:GetThreat): shown only while
-- the percent is readable; a secret value hides the bar.
function readers.threat(db)
	if not E.GetThreat then return nil end
	if db.threat.onlyGroup and not IsInGroup() then return nil end
	local status, percent, scaled, isTanking = E:GetThreat("player", "target")
	if not status or not percent then return nil end
	local color = db.threat.color
	if db.threat.statusColor then
		local r, g, b = E:GetThreatStatusColor(status)
		if r then color = { r, g, b } end
	end
	return { min = 0, max = 100, value = math.max(0, math.min(percent, 100)), percent = percent, scaled = scaled,
		tanking = isTanking, label = L["Threat"], color = color }
end

---------------------------------------------------------------------------
-- Watch the reputation you last gained (off by default). Each
-- faction's standing is remembered; when one goes up, it becomes the
-- watched faction. Reputation is not combat data.
---------------------------------------------------------------------------
local standings = {}

local function ScanReputation(track)
	if not (C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex) then return end
	local gained
	for index = 1, C_Reputation.GetNumFactions() or 0 do
		local data = C_Reputation.GetFactionDataByIndex(index)
		local id = data and Number(data.factionID)
		local standing = data and Number(data.currentStanding)
		if id and id ~= 0 and standing and (not data.isHeader or data.isHeaderWithRep) then
			local before = standings[id]
			if track and before and standing > before then gained = id end
			standings[id] = standing
		end
	end
	if not gained or not C_Reputation.SetWatchedFactionByID then return end
	local watched = C_Reputation.GetWatchedFactionData and C_Reputation.GetWatchedFactionData()
	if watched and watched.factionID == gained then return end
	-- The watch change sends its own UPDATE_FACTION: no second scan for it.
	M.repOwnWatch = true
	C_Reputation.SetWatchedFactionByID(gained)
	C_Timer.After(0, function() M.repOwnWatch = nil end)
end

-- Reputation gains come in bursts (every mob of a pull): one scan after.
local function TrackScan()
	if M.active and M.db.rep.enabled and M.db.rep.autoTrack then ScanReputation(true) end
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
-- Labels in the design's secondary gray (DESIGN.md 2), rested XP in a light
-- tint of the player's own rested color.
local SECONDARY = E:TextHex("secondary") .. "%s|r"

-- A color lightened toward white (0 = as it is, 1 = white).
local function Lighten(color, lighten)
	local r, g, b = color[1] or 1, color[2] or 1, color[3] or 1
	lighten = lighten or 0
	return r + (1 - r) * lighten, g + (1 - g) * lighten, b + (1 - b) * lighten
end

local function Hex(color, lighten)
	local r, g, b = Lighten(color, lighten)
	return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function BarText(key, data, db)
	local mode = db.textMode
	if mode == "none" then return "" end
	if key == "threat" then
		local numbers = ("%d%%"):format(math.floor(data.percent + 0.5))
		return db.textLabel and (SECONDARY:format(data.label) .. "  " .. numbers) or numbers
	end
	local span = data.max - data.min
	local into = data.value - data.min
	local percent = span > 0 and into / span * 100 or 100
	local numbers
	if mode == "percent" then
		numbers = ("%.1f%%"):format(percent)
	elseif mode == "current" then
		numbers = ("%s / %s"):format(Short(into), Short(span))
	elseif mode == "remaining" then
		numbers = L["%s to go"]:format(Short(math.max(0, span - into)))
	else
		numbers = ("%s / %s (%.1f%%)"):format(Short(into), Short(span), percent)
	end
	if key == "xp" and data.rested and mode ~= "remaining" then
		numbers = numbers .. "  " .. L["%s+%s rested|r"]:format(Hex(M.db.xp.restedColor or {}, 0.55), Short(data.rested))
	end
	if not db.textLabel then return numbers end
	local label = data.label
	if key == "rep" and data.standing and data.standing ~= "" then label = label .. " - " .. data.standing end
	return SECONDARY:format(label) .. "  " .. numbers
end
M.BarText = BarText

---------------------------------------------------------------------------
-- Tooltips: all detail lives here (DESIGN.md: keep bar text short).
---------------------------------------------------------------------------
local CLICK_HINTS = {
	xp = { Key("Click"), Key("open the map and quest log") },
	rep = { Key("Click"), Key("open the reputation list") },
	honor = { Key("Click"), Key("open the PvP tab") },
	pet = { Key("Click"), Key("open your pet's page") },
}

-- Forever has no pet tab of its own: the pet's stats, experience and
-- happiness are a side page of the character sheet (the pet button among
-- the stats, equipment sets and titles buttons). Opens the character
-- sheet and switches to that page; a click while it shows closes the
-- sheet again. Without the page, the character sheet alone opens.
local function PetSidebarTab()
	local pane, find, list = _G.CharacterStatsPanePetScrollBox, _G.GetPaperDollSideBarFrame, _G.PAPERDOLL_SIDEBARS
	if not (pane and type(find) == "function" and type(list) == "table") then return nil end
	for index = 1, #list do
		local ok, frame = pcall(find, index)
		if ok and frame == pane then return _G["PaperDollSidebarTab" .. index] end
	end
	return nil
end

local function OpenPetPage()
	local pane, sheet = _G.CharacterStatsPanePetScrollBox, _G.CharacterFrame
	if sheet and sheet:IsShown() and pane and pane:IsVisible() then
		ToggleCharacter("PaperDollFrame")
		return
	end
	ToggleCharacter("PaperDollFrame", true)
	local tab = PetSidebarTab()
	if tab and tab:IsVisible() and tab:IsEnabled() and not (pane and pane:IsShown()) then tab:Click() end
end

-- Left-click: the game panel that belongs to the bar (not in combat).
local function OpenPanel(key)
	if key == "rep" and ToggleCharacter then
		ToggleCharacter("ReputationFrame")
	elseif key == "pet" and ToggleCharacter then
		OpenPetPage()
	elseif key == "xp" then
		-- The game's own map request (the quest log sits on the map), never
		-- the toggle, which would leave the map's state tainted.
		E:OpenWorldMapAt()
	elseif key == "honor" then
		E:OpenPvPPage()
	end
end
local function TooltipLines(key, data)
	local tooltip = GameTooltip
	local r, g, b = unpack(E.media.accentColor)
	tooltip:AddLine(BAR_TITLES[key], r, g, b)
	if key == "threat" then
		E.UIKit.TipPair(tooltip, L["Of the tank's threat"], ("%d%%"):format(math.floor(data.percent + 0.5)))
		if data.scaled then
			E.UIKit.TipPair(tooltip, L["Towards pulling aggro"], ("%d%%"):format(math.floor(data.scaled + 0.5)))
		end
		if data.tanking then tooltip:AddLine(L["You have aggro."], E:TokenColor("bad")) end
		return
	end
	local span = data.max - data.min
	local into = data.value - data.min
	if key == "rep" then
		tooltip:AddDoubleLine(data.label, data.standing or "", 1, 1, 1, 1, 1, 1)
	elseif data.level then
		E.UIKit.TipPair(tooltip, E:GameText(LEVEL, L["Level"]), tostring(data.level))
	end
	E.UIKit.TipPair(tooltip, L["Progress"], ("%s / %s"):format(Long(into), Long(span)))
	if span > 0 then
		E.UIKit.TipPair(tooltip, L["Percent"], ("%.1f%%"):format(into / span * 100))
		E.UIKit.TipPair(tooltip, L["Remaining"], Long(math.max(0, span - into)))
	end
	if key == "xp" then
		if data.rested then
			-- The colors the player picked for the bar, lightened like the bar text.
			local cr, cg, cb = Lighten(M.db.xp.restedColor or {}, 0.55)
			tooltip:AddDoubleLine(L["Rested"], ("%s (%.0f%%)"):format(Long(data.rested), span > 0 and data.rested / span * 100 or 0),
				0.65, 0.65, 0.65, cr, cg, cb)
		end
		if data.questXP then
			local cr, cg, cb = Lighten(M.db.xp.questColor or {}, 0.25)
			E.UIKit.TipPair(tooltip, L["Finished quests (%d)"]:format(data.questCount or 0), Long(data.questXP), cr, cg, cb)
		end
		for _, bonus in ipairs(E.XPBonuses and E.XPBonuses() or {}) do
			E.UIKit.TipPair(tooltip, L["XP bonus"], M.XPBonusText(bonus), E:TokenColor("good"))
		end
		if IsResting and IsResting() then tooltip:AddLine(L["Resting: rested XP builds up."], E:TokenColor("secondary")) end
		local toCap, maxLevel = M.XPToCap(data, span - into)
		if toCap then E.UIKit.TipPair(tooltip, L["To level %d"]:format(maxLevel), Long(toCap)) end
		local rates = E.PlayRates
		if M.db.xp.session and rates.session then
			tooltip:AddLine(" ")
			E.UIKit.TipPair(tooltip, L["This session"], L["%s XP in %s"]:format(Long(rates.session.xp), FormatHours(rates:Elapsed())))
			local perHour = rates:Rate("xp")
			if perHour and perHour > 0 then
				E.UIKit.TipPair(tooltip, L["XP per hour"], Long(math.floor(perHour + 0.5)))
				E.UIKit.TipPair(tooltip, L["Time to level"], FormatHours(math.max(0, span - into) / perHour * 3600))
				if toCap then
					local ahead = (data.rested or 0) + (data.questXP or 0)
					E.UIKit.TipPair(tooltip, L["Time to level %d"]:format(maxLevel), FormatHours(math.max(0, toCap - ahead) / perHour * 3600))
				end
				E.UIKit.TipPair(tooltip, L["Counted over"], rates:BasisText())
			end
		end
	end
	local hint = M.db.clickOpens and CLICK_HINTS[key]
	local details = { L["Shift-click"], L["details window"] }
	if hint then E:TooltipHint(tooltip, hint, details) else E:TooltipHint(tooltip, details) end
end

---------------------------------------------------------------------------
-- EldoUI's bars
---------------------------------------------------------------------------
-- The tooltip opens toward the free side: below a bar in the top half of
-- the screen, above one in the bottom half, and beside an upright bar,
-- toward the wider side.
function M.TooltipAnchor(bar)
	local x, y = bar:GetCenter()
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	if not (x and y and width and height) then return "ANCHOR_TOP", 0, 4 end
	if M.db.vertical then
		if x > width / 2 then return "ANCHOR_LEFT", -4, 0 end
		return "ANCHOR_RIGHT", 4, 0
	end
	if y > height / 2 then return "ANCHOR_BOTTOM", 0, -4 end
	return "ANCHOR_TOP", 0, 4
end

local function ShowTooltip(bar)
	M:Hover(true)
	if not M.db.tooltip or not bar.data then return end
	GameTooltip:SetOwner(bar, M.TooltipAnchor(bar))
	GameTooltip:ClearLines()
	TooltipLines(bar.key, bar.data)
	GameTooltip:Show()
end

local function HideTooltip()
	M:Hover(false)
	GameTooltip_Hide()
end

---------------------------------------------------------------------------
-- Value tag at the fill end (upright bars, off by default): a small box
-- with the percent beside the stack, at the height the fill reaches, with
-- a pointer in the bar's color. It reads the same plain numbers as the bar
-- (the readers turn secret values into a hidden bar), and a bar without a
-- span shows no tag, so nothing ever divides by zero.
---------------------------------------------------------------------------
local function FillShare(data)
	if not data or type(data.max) ~= "number" or type(data.min) ~= "number" or type(data.value) ~= "number" then return nil end
	local span = data.max - data.min
	if span <= 0 then return nil end
	return math.max(0, math.min(1, (data.value - data.min) / span))
end
M.FillShare = FillShare

local function CreateTag(parent)
	local tag = CreateFrame("Frame", nil, parent)
	E:SetTemplate(tag, true)
	tag.text = E:CreateText(tag, E.tokens.size.small)
	tag.text:SetPoint("CENTER")
	tag.pointer = tag:CreateTexture(nil, "OVERLAY")
	E.UIKit.SetGlyph(tag.pointer, "play")
	tag:Hide()
	return tag
end
M.CreateTag = CreateTag

-- Text, size and pointer of a tag. side: the side of the bars the tag is
-- on (its pointer faces the bars). Returns the tag's height.
local function PaintTag(tag, share, color, side, fontSize)
	local look = E.tokens.bar.tag
	E:SetFont(tag.text, fontSize or E.tokens.size.small)
	tag.text:SetTextColor(E:TokenColor("body"))
	tag.text:SetText(("%d%%"):format(math.floor(share * 100 + 0.5)))
	local height = math.floor((fontSize or E.tokens.size.small) + look.padY * 2 + 0.5)
	tag:SetSize(math.max(height, math.ceil(tag.text:GetStringWidth()) + look.padX * 2), height)
	local pointer = tag.pointer
	pointer:ClearAllPoints()
	pointer:SetSize(look.pointer, look.pointer)
	if side == "LEFT" then
		pointer:SetRotation(0)
		pointer:SetPoint("LEFT", tag, "RIGHT", -look.tuck, 0)
	else
		pointer:SetRotation(math.pi)
		pointer:SetPoint("RIGHT", tag, "LEFT", look.tuck, 0)
	end
	pointer:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1)
	return height
end
M.PaintTag = PaintTag

-- Place each shown tag beside the stack at its bar's fill height; tags
-- that would overlap are pushed apart, inside the stack's length.
local placed = {}
function M:PlaceTags()
	local db = self.db
	local holder = self.holder
	if not (holder and self.bars) then return end
	local on = db.vertical and db.fillTag
	local length = BarWidth(db)
	local side = db.fillTagSide == "LEFT" and "LEFT" or "RIGHT"
	local look = E.tokens.bar.tag
	for index = #placed, 1, -1 do placed[index] = nil end
	for _, key in ipairs(BAR_KEYS) do
		local bar = self.bars[key]
		local share = on and bar:IsShown() and FillShare(bar.data)
		if share then
			local height = PaintTag(bar.tag, share, bar.data.color or {}, side, db.fontSize)
			placed[#placed + 1] = { tag = bar.tag, y = share * length, height = height }
		else
			bar.tag:Hide()
		end
	end
	table.sort(placed, function(a, b) return a.y < b.y end)
	local floor = 0
	for _, item in ipairs(placed) do
		local half = item.height / 2
		item.y = math.max(item.y, floor + half, half)
		floor = item.y + half + 1
	end
	-- Keep the top inside the stack, pushing the lower ones down again.
	local ceiling = length
	for index = #placed, 1, -1 do
		local item = placed[index]
		local half = item.height / 2
		item.y = math.min(item.y, ceiling - half)
		ceiling = item.y - half - 1
	end
	local offset = look.gap + look.pointer - look.tuck
	for _, item in ipairs(placed) do
		item.tag:ClearAllPoints()
		if side == "LEFT" then
			item.tag:SetPoint("RIGHT", holder, "BOTTOMLEFT", -offset, item.y)
		else
			item.tag:SetPoint("LEFT", holder, "BOTTOMRIGHT", offset, item.y)
		end
		item.tag:Show()
	end
end

function M:CreateBar(key)
	local bar = CreateFrame("Frame", nil, self.holder)
	bar.key = key
	bar:EnableMouse(true)
	bar.extra = E:CreateStatusBar(bar)       -- rested XP, drawn under the main fill
	bar.extra:SetAllPoints()
	bar.quest = CreateFrame("StatusBar", nil, bar)   -- XP of finished quests, between rested and the fill
	bar.quest:SetAllPoints()
	bar.quest:SetFrameLevel(bar.extra:GetFrameLevel() + 1)
	bar.quest:SetStatusBarTexture(E.media.statusbar)
	E.statusBars[bar.quest] = true
	bar.status = CreateFrame("StatusBar", nil, bar)
	bar.status:SetAllPoints()
	bar.status:SetFrameLevel(bar.quest:GetFrameLevel() + 1)
	bar.status:SetStatusBarTexture(E.media.statusbar)
	E.statusBars[bar.status] = true          -- follows the bar texture setting
	local overlay = CreateFrame("Frame", nil, bar)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(bar.status:GetFrameLevel() + 1)
	bar.text = E:CreateText(overlay, self.db.fontSize)
	bar.text:SetPoint("CENTER", 0, 0)
	bar.overlay = overlay
	bar.ticks = {}
	-- A thin accent line along the top edge while an XP bonus runs.
	bar.bonusMark = overlay:CreateTexture(nil, "OVERLAY")
	bar.bonusMark:SetTexture(E.media.flat)
	bar.bonusMark:Hide()
	bar.tag = CreateTag(self.holder)
	bar.tag:SetFrameLevel(overlay:GetFrameLevel() + 1)
	bar:SetScript("OnEnter", ShowTooltip)
	bar:SetScript("OnLeave", HideTooltip)
	bar:SetScript("OnMouseUp", function(frame, button)
		if button ~= "LeftButton" or E:IsOptionsLinkClick(frame, button) then return end
		-- Shift-click: the details window (fine in combat, it only shows text).
		if IsShiftKeyDown() then
			if frame.key ~= "threat" then M:ToggleDetails() end
			return
		end
		if InCombatLockdown() or not M.db.clickOpens then return end
		OpenPanel(frame.key)
	end)
	-- Right-click: Hide; Ctrl-click: this bar's switch on the module page.
	E:RegisterHideable(bar, "EldoUI_XPBar")
	E:BindOptionsLink(bar, function(own) return { page = "module:StatusBars", key = own.key .. ".enabled" } end)
	return bar
end

-- "+5% (Well Fed XP Boost), 23 min left"
function M.XPBonusText(bonus)
	local text = ("+%d%%"):format(math.floor(bonus.percent + 0.5))
	if bonus.name then text = text .. " (" .. bonus.name .. ")" end
	if bonus.left then text = text .. ", " .. L["%s left"]:format(E:FormatDuration(bonus.left, "long")) end
	return text
end

-- The XP bar's bonus line: read out of combat; in combat it keeps what
-- it showed before the fight.
function M.UpdateBonusMark(bar)
	local mark = bar.bonusMark
	if not mark then return end
	local db = M.db
	if bar.key ~= "xp" or not db.xp.bonusMark then
		mark:Hide()
		return
	end
	local bonuses = E.XPBonuses and E.XPBonuses()
	if bonuses then M.xpBonusOn = #bonuses > 0 end
	mark:ClearAllPoints()
	if db.vertical then
		mark:SetPoint("TOPRIGHT")
		mark:SetPoint("BOTTOMRIGHT")
		mark:SetWidth(math.max(1, E.pixel * 2))
	else
		mark:SetPoint("TOPLEFT")
		mark:SetPoint("TOPRIGHT")
		mark:SetHeight(math.max(1, E.pixel * 2))
	end
	mark:SetVertexColor(unpack(E.media.accentColor))
	mark:SetShown(M.xpBonusOn and true or false)
end

-- Text shows on horizontal bars only (upright bars keep it in the tooltip).
local function TextWanted(db, hovered)
	return db.textMode ~= "none" and not db.vertical and (db.textShow == "always" or hovered) and true or false
end

function M:UpdateBar(bar)
	local db = self.db
	local key = bar.key
	local data = db[key].enabled and readers[key](db) or nil
	bar.data = data
	if not data then
		bar:Hide()
		return false
	end
	local orientation = db.vertical and "VERTICAL" or "HORIZONTAL"
	bar.status:SetOrientation(orientation)
	bar.quest:SetOrientation(orientation)
	bar.extra:SetOrientation(orientation)
	bar.status:SetMinMaxValues(data.min, data.max)
	bar.status:SetValue(data.value)
	bar.status:SetStatusBarColor(data.color[1], data.color[2], data.color[3])
	if data.extra then
		bar.extra:SetMinMaxValues(data.min, data.max)
		bar.extra:SetValue(data.extra)
		local c = data.extraColor
		bar.extra:SetStatusBarColor(c[1], c[2], c[3], 0.6)
	else
		bar.extra:SetMinMaxValues(0, 1)
		bar.extra:SetValue(0)
	end
	if data.quest then
		bar.quest:SetMinMaxValues(data.min, data.max)
		bar.quest:SetValue(data.quest)
		local c = data.questColor
		bar.quest:SetStatusBarColor(c[1], c[2], c[3], 0.7)
	else
		bar.quest:SetMinMaxValues(0, 1)
		bar.quest:SetValue(0)
	end
	bar.text:SetText(BarText(key, data, db))
	bar.text:SetShown(TextWanted(db, self.hovered))
	M.UpdateBonusMark(bar)
	bar:Show()
	if GameTooltip:IsOwned(bar) then ShowTooltip(bar) end
	return true
end

-- Stack the shown bars from the anchored edge so the first one never moves.
function M:Layout()
	local db = self.db
	local holder = self.holder
	local enabled = 0
	for _, key in ipairs(BAR_KEYS) do
		if db[key].enabled then enabled = enabled + 1 end
	end
	local thickness = math.max(1, enabled * db.height + math.max(0, enabled - 1) * db.spacing)
	local length = BarWidth(db)
	if db.vertical then holder:SetSize(thickness, length) else holder:SetSize(length, thickness) end
	local offset = 0
	for _, key in ipairs(BAR_KEYS) do
		local bar = self.bars[key]
		if bar:IsShown() then
			bar:ClearAllPoints()
			if db.vertical then
				-- Upright bars side by side: "Upwards" adds them to the right.
				bar:SetSize(db.height, length)
				if db.grow == "DOWN" then
					bar:SetPoint("RIGHT", holder, "RIGHT", -offset, 0)
				else
					bar:SetPoint("LEFT", holder, "LEFT", offset, 0)
				end
			else
				bar:SetSize(length, db.height)
				if db.grow == "DOWN" then
					bar:SetPoint("TOP", holder, "TOP", 0, -offset)
				else
					bar:SetPoint("BOTTOM", holder, "BOTTOM", 0, offset)
				end
			end
			self:UpdateTicks(bar, length)
			offset = offset + db.height + db.spacing
		end
	end
	self:PlaceTags()
end

-- Divider lines across a bar, evenly spaced.
function M:UpdateTicks(bar, length)
	local db = self.db
	local count = db.ticks or 0
	for index = 1, math.max(count, #bar.ticks) do
		local tick = bar.ticks[index]
		if index <= count then
			if not tick then
				tick = bar.overlay:CreateTexture(nil, "ARTWORK")
				bar.ticks[index] = tick
			end
			local r, g, b = unpack(E.media.borderColor)
			tick:SetColorTexture(r, g, b, 0.7)
			tick:ClearAllPoints()
			local at = length * index / (count + 1)
			if db.vertical then
				tick:SetHeight(E:PixelFor(bar))
				tick:SetPoint("LEFT", bar, "BOTTOMLEFT", 0, at)
				tick:SetPoint("RIGHT", bar, "BOTTOMRIGHT", 0, at)
			else
				tick:SetWidth(E:PixelFor(bar))
				tick:SetPoint("TOP", bar, "TOPLEFT", at, 0)
				tick:SetPoint("BOTTOM", bar, "BOTTOMLEFT", at, 0)
			end
			tick:Show()
		elseif tick then
			tick:Hide()
		end
	end
end

-- A new UI scale or screen size: the ticks are sized again in whole
-- screen pixels.
if E.RegisterPixelCallback then
	E:RegisterPixelCallback(function()
		if M.active and M.holder and M.ownBars then M:Layout() end
	end)
end

function M:Refresh()
	if self.Details then self.Details.Update() end
	if not self.holder or not self.ownBars then return end
	for _, key in ipairs(BAR_KEYS) do self:UpdateBar(self.bars[key]) end
	self:Layout()
end

-- Hover-only text (the shared visibility rules fade the stack).
function M:Hover(over)
	self.hovered = over
	local db = self.db
	if db.textShow == "hover" and self.bars then
		for _, key in ipairs(BAR_KEYS) do
			local bar = self.bars[key]
			bar.text:SetShown(TextWanted(db, over) and bar.data ~= nil)
		end
	end
end

function M:CreateHolder()
	local holder = CreateFrame("Frame", "EldoUI_XPBar", UIParent)
	holder:SetFrameStrata("LOW")
	holder:SetSize(BarWidth(self.db), self.db.height)
	self.holder = holder
	self.bars = {}
	for _, key in ipairs(BAR_KEYS) do self.bars[key] = self:CreateBar(key) end
	-- Default: right on top of a bottom info bar, under the action bars
	-- (1440 reference).
	E:CreateMover(holder, "EldoUI_XPBar", L["XP and Reputation Bars"], { "BOTTOM", "UIParent", "BOTTOM", 0, 34 }, { sample = { kind = "bar" } })
end

local EVENTS = {
	"PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_UPDATE_RESTING",
	"UPDATE_FACTION", "CURRENCY_DISPLAY_UPDATE",
	"DISABLE_XP_GAIN", "ENABLE_XP_GAIN", "PLAYER_MAX_LEVEL_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
	"QUEST_LOG_UPDATE", "QUEST_TURNED_IN",
	-- A full-width bar follows a new resolution or UI scale.
	"DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED",
}
-- The pet's own events, for the player and the pet only: the game filters
-- them, so another raid member's pet never reaches the handler.
local PET_EVENTS = { "UNIT_PET_EXPERIENCE", "UNIT_PET" }
local PET_UNITS = { "player", "pet" }

local function OnEvent(_, event)
	if event == "UPDATE_FACTION" and M.db.rep.enabled and M.db.rep.autoTrack and not M.repOwnWatch then
		E:Debounce("StatusBars:rep", 0.5, TrackScan)
	end
	-- Several events arrive together (level up); draw once per frame.
	if M.refreshQueued then return end
	M.refreshQueued = true
	C_Timer.After(0, function()
		M.refreshQueued = false
		if M.active then M:Refresh() end
	end)
end

---------------------------------------------------------------------------
-- Bar details window: Shift-click a bar (or the button on the options
-- page). One fold section per bar that shows (experience, reputation,
-- honor, pet experience), each with label-left, value-right rows of what
-- the game reports: level or standing, current and max, remaining,
-- rested XP and finished quest XP. The line under the title names the
-- watched faction in its standing color. Each section remembers whether
-- it is folded (per profile). Nothing here is combat data.
---------------------------------------------------------------------------
local Details = { keys = { "xp", "rep", "honor", "pet" }, sections = {}, gap = 6 }
M.Details = Details

-- The rows of one section: { label, value[, kind] }.
function Details.Rows(key, data)
	local rows = {}
	local function Add(label, value, kind) rows[#rows + 1] = { label = label, value = value, kind = kind } end
	local span = data.max - data.min
	local into = data.value - data.min
	if key == "rep" then
		Add(L["Standing"], data.standing ~= "" and data.standing or "-")
	elseif data.level then
		Add(E:GameText(LEVEL, L["Level"]), tostring(data.level))
	end
	Add(L["Progress"], ("%s / %s"):format(Long(into), Long(span)))
	if span > 0 then
		Add(L["Percent"], ("%.1f%%"):format(into / span * 100))
		Add(L["Remaining"], Long(math.max(0, span - into)))
	end
	if key == "xp" then
		if data.rested then
			Add(L["Rested"], ("%s (%.0f%%)"):format(Long(data.rested), span > 0 and data.rested / span * 100 or 0), "good")
		end
		if data.questXP then Add(L["Finished quests (%d)"]:format(data.questCount or 0), Long(data.questXP)) end
	end
	return rows
end

local function DetailsStore()
	local db = M.db
	if type(db.details) ~= "table" then db.details = {} end
	if type(db.details.folded) ~= "table" then db.details.folded = {} end
	return db.details
end

function Details.Section(key)
	local section = Details.sections[key]
	if section then return section end
	local window = Details.window
	local Kit = E.UIKit
	section = { key = key, rows = {} }
	section.body = CreateFrame("Frame", nil, window.content)
	section.divider = Kit.FoldDivider(window.content, {
		label = BAR_TITLES[key], content = section.body,
		folded = DetailsStore().folded[key] and true or false,
		onToggle = function(folded)
			DetailsStore().folded[key] = folded or nil
			Details.Layout()
		end,
	})
	Details.sections[key] = section
	return section
end

-- Sections from the top, each divider with its rows under it; the window
-- takes the height of what shows.
function Details.Layout()
	local window = Details.window
	if not window then return end
	local content = window.content
	local T = E.tokens.height
	local y = 0
	for _, key in ipairs(Details.keys) do
		local section = Details.sections[key]
		if section and section.divider:IsShown() then
			local divider, body = section.divider, section.body
			divider:ClearAllPoints()
			divider:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
			divider:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
			y = y + T.foldRow
			body:ClearAllPoints()
			body:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, 0)
			body:SetPoint("TOPRIGHT", divider, "BOTTOMRIGHT", 0, 0)
			local shown = 0
			for _, row in ipairs(section.rows) do
				if row:IsShown() then
					row:ClearAllPoints()
					row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -shown * T.row)
					row:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -shown * T.row)
					shown = shown + 1
				end
			end
			body:SetHeight(math.max(shown * T.row, 1))
			if not divider:IsFolded() then y = y + shown * T.row end
			y = y + Details.gap
		end
	end
	window.empty:SetShown(y == 0)
	if y == 0 then y = T.row * 2 end
	-- Header (8 + 64), the gap over the content (16), the gap under it (12) and the edge (8).
	window:SetHeight(math.floor(108 + y + 0.5))
end

function Details.Update()
	local window = Details.window
	if not (window and window:IsShown()) then return end
	local db = M.db
	local Kit = E.UIKit
	local subline, color
	for _, key in ipairs(Details.keys) do
		local data = db[key].enabled and readers[key](db) or nil
		local section = (data or Details.sections[key]) and Details.Section(key)
		if section then
			section.divider:SetShown(data ~= nil)
			section.body:SetShown(data ~= nil and not section.divider:IsFolded())
			local rows = data and Details.Rows(key, data) or {}
			for index = 1, math.max(#rows, #section.rows) do
				local row, info = section.rows[index], rows[index]
				if info then
					if not row then
						row = Kit.ValueRow(section.body, {})
						section.rows[index] = row
					end
					row:SetLabel(info.label)
					row:SetValue(info.value, info.kind)
					row:Show()
				elseif row then
					row:Hide()
				end
			end
		end
		if key == "rep" and data then
			subline = data.standing ~= "" and ("%s - %s"):format(data.label, data.standing) or data.label
			local r, g, b = E:GetReactionColor(data.reaction)
			if type(r) == "number" then color = { r, g, b } end
		end
	end
	window:SetTitle(L["XP and reputation"], subline or L["No faction watched"], subline and color or nil)
	Details.Layout()
end

function Details.Create()
	if Details.window then return Details.window end
	local window = E.WindowKit.CreateWindow("EldoUIBarDetails", { width = 300, height = 200, footer = 0,
		options = { page = "module:StatusBars" } })
	window.footer:Hide()
	window.empty = E.UIKit.Text(window.content, E.tokens.size.label, "LEFT", "secondary")
	window.empty:SetPoint("TOPLEFT")
	window.empty:SetPoint("TOPRIGHT")
	window.empty:SetWordWrap(true)
	window.empty:SetText(L["No experience, reputation or honor to show right now."])
	-- The window opens where it was left.
	local function Save()
		local left, top = window:GetLeft(), window:GetTop()
		if left and top then DetailsStore().point = { math.floor(left + 0.5), math.floor(top + 0.5) } end
	end
	window:HookScript("OnDragStop", Save)
	window.header:HookScript("OnDragStop", Save)
	window:HookScript("OnShow", function() Details.Update() end)
	Details.window = window
	return window
end

function M:ToggleDetails(show)
	local window = Details.Create()
	if show == nil then show = not window:IsShown() end
	if not show then
		window:Hide()
		return
	end
	local point = DetailsStore().point
	window:ClearAllPoints()
	if type(point) == "table" and tonumber(point[1]) and tonumber(point[2]) then
		window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", point[1], point[2])
	else
		window:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	end
	window:Show()
	Details.Update()
end

---------------------------------------------------------------------------
-- Blizzard's bars (element "status-tracking-bars")
---------------------------------------------------------------------------
local skinned = {}  -- container -> backdrop frame
local placing = {}  -- container -> true while EldoUI places it

local function Containers()
	return { MainStatusTrackingBarContainer, SecondaryStatusTrackingBarContainer }
end

-- Back to Blizzard's own place (the core pin restores its points; Edit
-- Mode's next layout pass settles the rest).
local function Restore(frame)
	if not placing[frame] then return end
	placing[frame] = nil
	E:UnpinBlizzardFrame(frame)
end

-- Divider ticks are pooled frames Blizzard re-acquires; only bars carry barIndex.
local function HideDividers(container)
	for _, child in ipairs({ container:GetChildren() }) do
		if child.BarDividerTexture then child.BarDividerTexture:SetAlpha(0) end
	end
end

function M:SkinBlizzardBars()
	for _, container in ipairs(Containers()) do
		if container and not E.FrameCheck(container, "IsForbidden") then
			if container.BarFrameTexture then container.BarFrameTexture:SetAlpha(0) end
			HideDividers(container)
			if not skinned[container] then
				local bd = CreateFrame("Frame", nil, container)
				bd:SetPoint("TOPLEFT", 0, -1)
				bd:SetPoint("BOTTOMRIGHT", 0, 1)
				bd:SetFrameLevel(math.max(container:GetFrameLevel() - 1, 0))
				E:SetTemplate(bd, true)
				E:SetStyleEdge(bd) -- WoW Forever art style frame line
				skinned[container] = bd
				if container.UpdateDividers then
					hooksecurefunc(container, "UpdateDividers", function(frame)
						if E:BlizzardAllowed(ELEMENT, "skin") then HideDividers(frame) end
					end)
				end
			end
			skinned[container]:Show()
			for _, bar in ipairs(container.bars or {}) do
				local text = bar.OverlayFrame and bar.OverlayFrame.Text
				if text then E:SetFont(text, self.db.blizzard.textSize) end
				if bar.StatusBar and bar.StatusBar.Background then bar.StatusBar.Background:SetAlpha(0) end
			end
		end
	end
end

function M:UnskinBlizzardBars()
	for container, bd in pairs(skinned) do
		bd:Hide()
		if container.BarFrameTexture then container.BarFrameTexture:SetAlpha(1) end
		for _, child in ipairs({ container:GetChildren() }) do
			if child.BarDividerTexture then child.BarDividerTexture:SetAlpha(1) end
		end
		for _, bar in ipairs(container.bars or {}) do
			if bar.StatusBar and bar.StatusBar.Background then bar.StatusBar.Background:SetAlpha(1) end
		end
	end
end

-- Blizzard's bars on the EldoUI_XPBar mover: the main bar at the anchored
-- edge, the secondary one next to it. Both are Edit Mode systems that go
-- back into the bottom bar stack on every layout pass; the core pin
-- (E:PinBlizzardFrame) puts them back with the plain widget methods.
local function Placing()
	return M.active and not M.ownBars and M.holder ~= nil
		and E:BlizzardAllowed(ELEMENT, "move") and not E:BlizzardHidden(ELEMENT)
end

local function MainAnchor()
	local up = M.db.grow ~= "DOWN"
	return up and "BOTTOM" or "TOP", M.holder, up and "BOTTOM" or "TOP", 0, 0
end

local function SecondaryAnchor()
	local up = M.db.grow ~= "DOWN"
	local main = MainStatusTrackingBarContainer
	if main then
		return up and "BOTTOM" or "TOP", main, up and "TOP" or "BOTTOM", 0, up and 1 or -1
	end
	return up and "BOTTOM" or "TOP", M.holder, up and "BOTTOM" or "TOP", 0, 0
end

function M:AnchorBlizzardBars()
	if not self.holder then return end
	local main, secondary = MainStatusTrackingBarContainer, SecondaryStatusTrackingBarContainer
	if main then
		placing[main] = true
		E:PinBlizzardFrame(main, { holder = self.holder, active = Placing, anchor = MainAnchor })
	end
	if secondary then
		placing[secondary] = true
		E:PinBlizzardFrame(secondary, { active = Placing, anchor = SecondaryAnchor })
	end
end

-- Hidden or replaced: the bars' manager goes to the hidden parent, never the
-- bars. Blizzard's bars ask their parent for the manager whenever they show
-- or hide (Edit Mode does both), so they stay its children.
local function HideManager(hide)
	local manager = StatusTrackingBarManager
	if not manager then return end
	if hide then
		-- Kept hidden when something re-parents it (core SetParent hook).
		E:HideBlizzardFrame(manager, { check = function() return M.active and E:BlizzardHidden(ELEMENT) end })
	else
		E:UnhideBlizzardFrame(manager)
	end
end

-- Called out of combat whenever the element's switches or settings change.
function M:ApplyBlizzard()
	local hidden = E:BlizzardHidden(ELEMENT)
	HideManager(hidden)
	if hidden then return end
	if E:BlizzardAllowed(ELEMENT, "skin") then self:SkinBlizzardBars() else self:UnskinBlizzardBars() end
	if E:BlizzardAllowed(ELEMENT, "move") then
		self:AnchorBlizzardBars()
	else
		for _, container in ipairs(Containers()) do
			if container then Restore(container) end
		end
	end
end

function M:RestoreBlizzard()
	self:UnskinBlizzardBars()
	HideManager(false)
	for _, container in ipairs(Containers()) do
		if container then Restore(container) end
	end
end

E:RegisterBlizzardHandler(ELEMENT, {
	owner = "StatusBars",
	apply = function() M:ApplyBlizzard() end,
	undo = function() M:RestoreBlizzard() end,
	reload = { skin = true },
	install = { replace = true, skin = true, move = true },
	legacy = function() return false end, -- v0.5.0 never touched Blizzard's bars
})

-- Threat changes often in a fight: only the threat bar is redrawn, and the
-- stack is laid out again only when it appears or goes.
local threatQueued = false
local function OnThreatEvent()
	if threatQueued then return end
	threatQueued = true
	C_Timer.After(0.1, function()
		threatQueued = false
		if not (M.active and M.ownBars and M.db.threat.enabled) then return end
		local bar = M.bars.threat
		local wasShown = bar:IsShown()
		M:UpdateBar(bar)
		if bar:IsShown() ~= wasShown then M:Layout() else M:PlaceTags() end
	end)
end

local THREAT_EVENTS = { "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE" }
local threatFrame = CreateFrame("Frame")
threatFrame:SetScript("OnEvent", OnThreatEvent)

-- Shown state of the stack: EldoUI's bars or Blizzard's on the mover. When
-- it fades follows the shared visibility rules (Visibility section).
function M:UpdateShown()
	if not self.holder then return end
	local base = self.ownBars or E:BlizzardAllowed(ELEMENT, "move")
	self.holder:SetShown(base and true or false)
end

-- Settings before the shared visibility rules: "Hide in combat", "Show on
-- mouse-over" and its faded opacity (0-100) become one visibility block,
-- once. Mouse-over wins when both were on.
function M:MigrateVisibility()
	local db = self.db
	if type(db) ~= "table" or (db.mouseover == nil and db.hideInCombat == nil and db.fadeAlpha == nil) then return end
	if db.mouseover then
		db.visibility = E:VisibilityDefaults({ show = "mouseover", fadedAlpha = math.max(0, math.min(1, (tonumber(db.fadeAlpha) or 0) / 100)) })
	elseif db.hideInCombat then
		db.visibility = E:VisibilityDefaults({ show = "nocombat" })
	end
	E:NormalizeVisibility(db.visibility)
	db.mouseover, db.hideInCombat, db.fadeAlpha = nil, nil, nil
end

---------------------------------------------------------------------------
-- Module life cycle
---------------------------------------------------------------------------
function M:Apply()
	local db = self.db
	-- EldoUI's own bars show when Replace is on, or when the element is left
	-- alone entirely (then both are visible, like any EldoUI frame).
	local blizzardOn = E:BlizzardAllowed(ELEMENT)
	self.ownBars = (not blizzardOn) or E:BlizzardAllowed(ELEMENT, "replace")
	self:UpdateShown()
	threatFrame:UnregisterAllEvents()
	if self.ownBars and db.threat.enabled then
		for _, event in ipairs(THREAT_EVENTS) do threatFrame:RegisterEvent(event) end
	end
	for _, key in ipairs(BAR_KEYS) do
		local bar = self.bars[key]
		E:SetFont(bar.text, db.fontSize)
		E:SetTemplate(bar.extra.bg, true) -- theme colors may have changed
		E:SetStyleEdge(bar.extra.bg) -- WoW Forever art style frame line
		E:SetTemplate(bar.tag, true)
		if not self.ownBars then
			bar:Hide()
			bar.tag:Hide()
		end
	end
	if self.ownBars then
		self:Refresh()
	else
		-- Keep the mover the size of Blizzard's bars so dragging matches.
		local width = MainStatusTrackingBarContainer and MainStatusTrackingBarContainer:GetWidth() or BarWidth(db)
		self.holder:SetSize(width, 34)
	end
	E:AttachVisibility(self.holder, db.visibility, { forceShow = function() return E:IsMoveMode() end })
	self.holder:EnableMouse(db.visibility.show == "mouseover")
	if blizzardOn then self:ApplyBlizzard() end
end

function M:OnInitialize()
	self:MigrateVisibility()
end

function M:OnEnable()
	self:MigrateVisibility()
	if not self.holder then
		self:CreateHolder()
		self.holder:SetScript("OnEnter", function() M:Hover(true) end)
		self.holder:SetScript("OnLeave", function() M:Hover(false) end)
	end
	for _, event in ipairs(EVENTS) do self:RegisterEvent(event, OnEvent) end
	-- An XP bonus starting or ending (out of combat, only with the line on).
	local function BonusChanged()
		if self.db.xp.bonusMark and not InCombatLockdown() and self.bars and self.bars.xp then M.UpdateBonusMark(self.bars.xp) end
	end
	self:RegisterUnitEvent("UNIT_AURA", "player", BonusChanged)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", BonusChanged)
	for _, event in ipairs(PET_EVENTS) do self:RegisterUnitEvent(event, PET_UNITS, OnEvent) end
	ScanReputation(false)
	self:Apply()
end

function M:OnDisable()
	if self.Details and self.Details.window then self.Details.window:Hide() end
	for _, event in ipairs(EVENTS) do self:UnregisterEvent(event) end
	for _, event in ipairs(PET_EVENTS) do self:UnregisterUnitEvent(event, PET_UNITS) end
	self:UnregisterUnitEvent("UNIT_AURA", "player")
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	threatFrame:UnregisterAllEvents()
	if self.holder then
		E:DetachVisibility(self.holder)
		self.holder:Hide()
	end
	-- Blizzard's bars come back when EldoUI's go away.
	E:RunOutOfCombat(function()
		if not M.active then M:RestoreBlizzard() end
	end)
end

function M:OnProfileChanged()
	self:MigrateVisibility()
	if self.active then self:Apply() end
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
-- The value tag preview: two upright sample bars (experience at 65%,
-- reputation at 30%) with their tags on the chosen side.
local PREVIEW_BARS = { { key = "xp", share = 0.65 }, { key = "rep", share = 0.3 } }

local function CreateTagPreview(canvas)
	if not canvas then return end
	local stack = CreateFrame("Frame", nil, canvas)
	stack:SetPoint("CENTER")
	canvas.stack = stack
	canvas.bars = {}
	for index, sample in ipairs(PREVIEW_BARS) do
		local bar = E:CreateStatusBar(stack)
		bar:SetOrientation("VERTICAL")
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(sample.share)
		bar.tag = CreateTag(canvas)
		bar.share = sample.share
		bar.key = sample.key
		canvas.bars[index] = bar
	end
end

local function UpdateTagPreview(canvas, db)
	if not (canvas and canvas.stack and type(db) == "table") then return end
	local height = math.max(4, math.min(db.height or 8, 14))
	local spacing = db.spacing or 3
	local length = math.max(40, canvas:GetHeight() - 8)
	local side = db.fillTagSide == "LEFT" and "LEFT" or "RIGHT"
	local look = E.tokens.bar.tag
	canvas.stack:SetSize(#canvas.bars * height + (#canvas.bars - 1) * spacing, length)
	for index, bar in ipairs(canvas.bars) do
		bar:ClearAllPoints()
		bar:SetSize(height, length)
		bar:SetPoint("BOTTOMLEFT", canvas.stack, "BOTTOMLEFT", (index - 1) * (height + spacing), 0)
		bar:SetStatusBarTexture(E.media.statusbar)
		local color = db[bar.key] and db[bar.key].color or E.tokens.bar.rested
		if bar.key == "rep" and db.rep and db.rep.reactionColor then color = { E:GetReactionColor(5) } end
		bar:SetStatusBarColor(color[1], color[2], color[3])
		E:SetStyleEdge(bar.bg)
		PaintTag(bar.tag, bar.share, color, side, db.fontSize)
		bar.tag:ClearAllPoints()
		local offset = look.gap + look.pointer - look.tuck
		if side == "LEFT" then
			bar.tag:SetPoint("RIGHT", canvas.stack, "BOTTOMLEFT", -offset, bar.share * length)
		else
			bar.tag:SetPoint("LEFT", canvas.stack, "BOTTOMRIGHT", offset, bar.share * length)
		end
		-- Dimmed while the tag is off, so the preview still shows what it adds.
		bar.tag:Show()
		bar.tag:SetAlpha(db.fillTag and 1 or E.tokens.disabledAlpha)
	end
end

local TEXT_MODES = { none = "No text", percent = "Percent", current = "Current / max", remaining = "Remaining", full = "Current / max (percent)" }

local function BlizzardOff() return not E:BlizzardAllowed(ELEMENT) end

M.options = {
	{ type = "tab", label = "Bars" },
	{ type = "description", label = "EldoUI's bars show by themselves. Blizzard's XP and reputation bars follow \"XP, reputation and honor bars\" in Blizzard UI." },
	{ type = "execute", label = "Use EldoUI's bars instead of Blizzard's", desc = "Turns on the Blizzard UI switch for this element with Replace, so only EldoUI's bars show.",
		hidden = function() return E:BlizzardAllowed(ELEMENT, "replace") end,
		func = function()
			E:SetBlizzardElement(ELEMENT, "enabled", true)
			E:SetBlizzardElement(ELEMENT, "replace", true)
			if E.RefreshConfig then E:RefreshConfig() end
		end },
	{ type = "header", label = "Size" },
	{ type = "range", key = "width", label = "Length", desc = "Length of every bar in pixels. Full spans the whole screen.", zeroText = "Full", min = 0, max = 1200, step = 2 },
	{ type = "range", unit = "px", key = "height", label = "Thickness", desc = "Thickness of each bar in pixels.", min = 4, max = 30, step = 1 },
	{ type = "range", unit = "px", key = "spacing", label = "Gap between bars", desc = "Space between two stacked bars.", min = 0, max = 12, step = 1 },
	{ type = "select", key = "grow", label = "Stack direction", desc = "Where the second bar goes when more than one shows. With upright bars: Upwards adds them to the right, Downwards to the left.",
		values = { UP = "Upwards", DOWN = "Downwards" } },
	{ type = "range", key = "ticks", label = "Divider ticks", min = 0, max = 20, step = 1, zeroText = "None",
		desc = "Thin lines that cut each bar into equal parts. 19 gives Blizzard's classic 20 blocks." },
	{ type = "toggle", key = "vertical", label = "Upright bars",
		desc = "The bars stand upright side by side and fill from the bottom. Their text moves into the tooltip." },
	{ type = "header", label = "Value tag" },
	{ type = "preview", label = "Preview", height = 120, create = CreateTagPreview, update = UpdateTagPreview,
		desc = "Two upright sample bars with their value tags, in your current look." },
	{ type = "toggle", key = "fillTag", label = "Value tag at fill end", dependsOn = "vertical",
		desc = "Upright bars show their percent in a small tag beside the stack, at the height the fill reaches, with a pointer in the bar's color. The tag moves up as the bar fills." },
	{ type = "select", key = "fillTagSide", label = "Tag side", dependsOn = "fillTag",
		disabled = function() return not M.db.vertical and L["Turn on \"Upright bars\" first."] end,
		desc = "Which side of the bars the value tags sit on.", values = { LEFT = "Left", RIGHT = "Right" }, order = { "LEFT", "RIGHT" } },
	{ type = "header", label = "Text" },
	{ type = "select", key = "textMode", label = "Show", desc = "What the text on each bar shows.", values = TEXT_MODES },
	{ type = "select", key = "textShow", label = "Show text", desc = "Always, or only while the mouse is over the bars.",
		values = { always = "Always", hover = "On mouseover" } },
	{ type = "toggle", key = "textLabel", label = "Name in front", desc = "\"XP\", the faction name and standing, \"Honor\" or \"Pet\" before the numbers." },
	{ type = "range", key = "fontSize", label = "Text size", desc = "Size of the bar text.", min = 8, max = 18, step = 1 },
	{ type = "toggle", key = "tooltip", label = "Tooltip", desc = "Details (rested XP, remaining, standing) when you point at a bar." },
	{ type = "toggle", key = "clickOpens", label = "Click opens the panel",
		desc = "Left-click a bar to open the map and quest log (XP), the reputation list, the PvP tab (honor) or your pet's page. Not in combat." },
	{ type = "execute", label = "Bar details window", keywords = "details experience reputation honor rested standing",
		desc = "A small window with the numbers behind each bar: level or standing, progress, remaining, rested XP and finished quests, in foldable sections. Shift-click a bar opens it too.",
		func = function() M:ToggleDetails(true) end },

	{ type = "tab", label = "Experience" },
	{ type = "toggle", key = "xp.enabled", label = "Experience bar", desc = "Your XP towards the next level." },
	{ type = "toggle", key = "xp.rested", dependsOn = "xp.enabled", label = "Show rested XP", desc = "A lighter fill shows how far your rested bonus reaches." },
	{ type = "toggle", key = "xp.quests", dependsOn = "xp.enabled", label = "Show finished quest XP", desc = "A gold fill shows the XP waiting in finished quests you have not handed in yet." },
	{ type = "toggle", key = "xp.bonusMark", dependsOn = "xp.enabled", label = "XP bonus line", desc = "A thin line along the XP bar while an XP bonus runs, such as XP food or an event. The tooltip names each bonus and its time left either way." },
	{ type = "toggle", key = "xp.session", dependsOn = "xp.enabled", label = "Session statistics", desc = "The XP tooltip shows XP gained this session, XP per hour and the time to the next level." },
	{ type = "toggle", key = "xp.toCap", dependsOn = "xp.enabled", label = "XP to the level cap", desc = "The XP tooltip shows the XP still needed to reach the level cap and, with session statistics on, the time at this session's pace (rested XP and finished quests count as a head start)." },
	{ type = "toggle", key = "xp.hideAtMax", dependsOn = "xp.enabled", label = "Hide at max level", desc = "The XP bar disappears at the level cap; the reputation bar takes its place." },
	{ type = "color", key = "xp.color", dependsOn = "xp.enabled", label = "XP color", desc = "Fill color of the experience bar." },
	{ type = "color", key = "xp.restedColor", dependsOn = "xp.enabled", label = "Rested color", desc = "Color of the rested part." },
	{ type = "color", key = "xp.questColor", dependsOn = "xp.enabled", label = "Quest XP color", desc = "Color of the finished quest part." },
	{ type = "toggle", key = "pet.enabled", label = "Pet experience bar", desc = "Your hunter pet's experience (Forever pets level up with you)." },
	{ type = "color", key = "pet.color", dependsOn = "pet.enabled", label = "Pet XP color", desc = "Fill color of the pet experience bar." },

	{ type = "tab", label = "Reputation and honor" },
	{ type = "toggle", key = "rep.enabled", label = "Reputation bar", desc = "The faction you watch (tick \"Show as experience bar\" in the reputation list)." },
	{ type = "toggle", key = "rep.reactionColor", dependsOn = "rep.enabled", label = "Color by standing", desc = "Red for hostile through green for exalted, the game's standing colors." },
	{ type = "color", key = "rep.color", label = "Reputation color", desc = "Used when \"Color by standing\" is off.", dependsOn = "rep.enabled",
		disabled = function() return M.db.rep.reactionColor and L["Used while \"Color by standing\" is off."] end },
	{ type = "toggle", key = "rep.onlyWhenMax", dependsOn = "rep.enabled", label = "Only at max level", desc = "Show the reputation bar only once you stop gaining XP." },
	{ type = "toggle", key = "rep.autoTrack", dependsOn = "rep.enabled", label = "Watch the last reputation gained",
		desc = "Whenever you gain reputation with a faction, the bar switches to that faction (Blizzard's \"Show as experience bar\" setting)." },
	{ type = "toggle", key = "honor.enabled", label = "Honor bar", desc = "Your honor points, filling toward the most you can hold." },
	{ type = "select", key = "honor.show", dependsOn = "honor.enabled", label = "Show honor", desc = "Only in battlegrounds and world PvP, or all the time.",
		values = { pvp = "In PvP", always = "Always" } },
	{ type = "color", key = "honor.color", dependsOn = "honor.enabled", label = "Honor color", desc = "Fill color of the honor bar." },

	{ type = "tab", label = "Threat" },
	{ type = "toggle", key = "threat.enabled", label = "Threat bar",
		desc = "Your threat on your target, the same percent the game's target frame shows. Hidden when there is none, or when the game hides it." },
	{ type = "toggle", key = "threat.onlyGroup", label = "Only in a group", dependsOn = "threat.enabled",
		desc = "Show the threat bar only while you are in a party or raid." },
	{ type = "toggle", key = "threat.statusColor", label = "Threat status color", dependsOn = "threat.enabled",
		desc = "Yellow, orange and red from the game's threat status." },
	{ type = "color", key = "threat.color", label = "Threat color", dependsOn = "threat.enabled",
		disabled = function() return M.db.threat.statusColor and L["Used while \"Threat status color\" is off."] end,
		desc = "Fill color of the threat bar when the status color is off." },
	{ type = "execute", label = "Threat meter window", desc = "Opens the Combat HUD page with EldoUI's threat meter for your whole group.",
		func = function() if E.ToggleConfig then E:ToggleConfig("module:CombatHUD") end end },

	{ type = "tab", label = "Blizzard's bars" },
	{ type = "description", label = "For \"XP, reputation and honor bars\" in Blizzard UI with Skin or Move. Their width and height stay in Edit Mode." },
	{ type = "range", key = "blizzard.textSize", label = "Text size", desc = "Font size of the numbers on Blizzard's skinned bars.", min = 8, max = 18, step = 1, hidden = BlizzardOff },
	{ type = "execute", label = "Open Blizzard UI switches", desc = "Open the switches for Blizzard's bars.",
		func = function() if E.ToggleConfig then E:ToggleConfig("blizzard") end end },
}

-- The shared visibility rows close the Bars tab.
do
	local at = #M.options + 1
	for index, row in ipairs(M.options) do
		if row.type == "tab" and row.label == "Experience" then at = index break end
	end
	for _, row in ipairs(E:VisibilityOptions("visibility", { db = function() return M.db end })) do
		table.insert(M.options, at, row)
		at = at + 1
	end
end

---------------------------------------------------------------------------
-- Layout lengths that changed. EldoUI Center and Nameplate Focus made the
-- bar as long as the whole bottom row, side grids included; those grids
-- hide their empty buttons or show only on mouse over, so the bar now
-- follows action bar 1. A profile on one of those layouts that still has
-- the old length takes the new one, once. A length the player picked stays.
---------------------------------------------------------------------------
M.LAYOUT_WIDTH_BEFORE = { EldoCenter = 980, EldoPlates = 992 }

function M.MigrateLayoutWidth(profile)
	local modules = type(profile) == "table" and type(profile.modules) == "table" and profile.modules
	local own = modules and type(modules.StatusBars) == "table" and modules.StatusBars
	if not own then return end
	local general = type(profile.general) == "table" and profile.general or {}
	local key = general.layout or (E.defaults.general and E.defaults.general.layout)
	local before = M.LAYOUT_WIDTH_BEFORE[key]
	if not before or tonumber(own.width) ~= before then return end
	local layout = E.layouts and E.layouts[key]
	local values = layout and layout.modules and layout.modules.StatusBars
	if type(values) == "table" and tonumber(values.width) then own.width = values.width end
end
E:RegisterProfileMigration(M.MigrateLayoutWidth, "StatusBars:layoutWidth", 1)

---------------------------------------------------------------------------
-- Style presets (the layout places the bar)
---------------------------------------------------------------------------
E:RegisterStyles("StatusBars", {
	{ key = "Thin", title = "Thin line", desc = "620 x 6, text on mouseover. The quietest look.",
		settings = { width = 620, height = 6, textShow = "hover", textMode = "percent",
			visibility = { preset = "always", show = "always", fadedAlpha = 0, fadeTime = 0.2, delay = 0 } } },
	{ key = "Classic", title = "Classic full width", desc = "Across the whole screen width with numbers always shown, like the old Blizzard bar.",
		settings = { width = 0, height = 12, textShow = "always", textMode = "full", fontSize = 11, ticks = 19, vertical = false } },
	{ key = "Levelling", title = "Leveling", desc = "Bigger bar with rested XP and the remaining XP always in view.",
		settings = { width = 620, height = 14, textShow = "always", textMode = "remaining", ticks = 9, vertical = false, xp = { rested = true, quests = true } } },
	{ key = "Hidden", title = "Mouse-over only", desc = "Invisible until you point at it.",
		settings = { width = 620, height = 8, textShow = "hover",
			visibility = { preset = "mouseover", show = "mouseover", fadedAlpha = 0, fadeTime = 0.2, delay = 0.5 } } },
	{ key = "Endgame", title = "Endgame", desc = "Reputation and honor only; XP hides at the cap.",
		settings = { width = 620, height = 8, textShow = "hover", vertical = false, xp = { hideAtMax = true }, rep = { enabled = true, autoTrack = true }, honor = { enabled = true, show = "always" }, threat = { enabled = true } } },
	{ key = "Compact", title = "Compact", desc = "Short 400 px bars with current / max text.",
		settings = { width = 400, height = 10, textShow = "always", textMode = "current", fontSize = 10 } },
}, { restores = { "threat.enabled", "honor.show" } })
