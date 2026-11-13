-- EldoUI Info Bar: session rates. Three blocks for any bar or panel slot:
-- gold per hour (session earned, spent and the best hour in the tooltip),
-- XP per hour (XP this session, to the next level, rested apart) and the
-- time to the next level at that rate. One session for all of them, the
-- Gold block's session lines, the XP bar tooltip and My Adventure (the
-- core's E.PlayRates, Core/PlayRates.lua); right-click on a rate block
-- starts it again.
--
-- The rate is the session's average for its first hour, then the last 60
-- minutes. For the first two minutes it shows a dash. Only online time
-- counts. The session is kept per character over a reload, and starts
-- again after a log-out longer than the player's setting.
--
-- Rules (Forever): only the player's own money and XP, as the game reports
-- them; every value is checked for a secret before any math. Nothing is
-- posted to chat.
local _, E = ...
local L = E.L
local M = E.modules.InfoBar

local IsSecret = E.Secret
local BLOCKS = { "GoldRate", "XPRate", "LevelTime" }

M.defaults.sessionResume = 30 -- minutes: a longer log-out starts a new session

-- The session itself is the core's (Core/PlayRates.lua), shared with the
-- XP bar and My Adventure.
local Rates = E.PlayRates
M.rates = Rates
local NewSession = Rates.NewSession
local MIN_TIME = Rates.MIN_TIME

local function Plain(value)
	if IsSecret(value) or type(value) ~= "number" then return nil end
	return value
end

local function Grey(text) return E:TextHex("secondary") .. text .. "|r" end

-- The Gold block's session lines show the same session.
local function SyncGold()
	local gold, s = M.moneySession, Rates.session
	if not (gold and s) then return end
	local money = Plain(GetMoney())
	if money then gold.start, gold.last = money, money end
	gold.gained, gold.spent = s.earned, s.spent
end

local function RefreshBlocks()
	if not M.active then return end
	for _, name in ipairs(BLOCKS) do M:RefreshDataText(name) end
	M:RefreshDataText("Gold")
	if GameTooltip:IsShown() then
		local owner = GameTooltip:GetOwner()
		if owner and owner.dataName and owner:IsMouseOver() then M.ShowTooltip(owner) end
	end
end

-- A new session (right-click, or a reload that starts one) clears the Gold
-- block's session lines too.
Rates:OnChange(function()
	SyncGold()
	RefreshBlocks()
end)
M:AddExtra({ Enable = SyncGold })

---------------------------------------------------------------------------
-- The blocks
---------------------------------------------------------------------------
-- Money in the Money style with its sign, as exact as a bar block needs:
-- whole gold from 100 gold, gold and silver from 1 gold, else silver (or
-- copper under one silver).
local function MoneyText(copper)
	local amount = math.floor(math.abs(copper) + 0.5)
	if amount >= 1000000 then
		amount = math.floor(amount / 10000 + 0.5) * 10000
	elseif amount >= 100 then
		amount = math.floor(amount / 100 + 0.5) * 100
	end
	return (copper < 0 and "-" or "") .. E:FormatMoney(amount)
end

local function ResetHint() return { L["Right-click"], L["start a new session"] } end

local function SessionLine(tooltip)
	E.UIKit.TipPair(tooltip, L["Session"], E:FormatDuration(Rates:Elapsed(), "long"))
end

local function Counting(tooltip)
	E.UIKit.TipText(tooltip, L["The rate shows after 2 minutes of play."])
end

local function OnClick(_, mouseButton)
	if mouseButton == "RightButton" then Rates:Reset() end
end

local function AtCap()
	return E:AtMaxLevel() or (IsXPUserDisabled and IsXPUserDisabled())
end

local function CapTooltip(tooltip)
	if E:AtMaxLevel() then
		E.UIKit.TipText(tooltip, L["You are at the level cap."])
	else
		tooltip:AddLine(L["XP gain is switched off."], E:TokenColor("bad"))
	end
end

E:RegisterDataText("GoldRate", {
	title = "Gold per hour",
	label = "Gold/h",
	icon = "Interface\\MoneyFrame\\UI-GoldIcon",
	poll = true,
	interval = 5,
	events = { "PLAYER_MONEY" },
	text = function()
		local rate = Rates:Rate("money")
		if not rate then return Grey("–") end
		if rate < 0 then return M.Status("bad", MoneyText(rate)) end
		return M.Value(MoneyText(rate))
	end,
	tooltip = function(tooltip)
		local s = Rates.session or NewSession()
		SessionLine(tooltip)
		local rate = Rates:Rate("money")
		if rate then
			E.UIKit.TipPair(tooltip, L["Gold per hour"], MoneyText(rate))
		else
			Counting(tooltip)
		end
		tooltip:AddLine(" ")
		E.UIKit.TipPair(tooltip, L["Session earned"], E:FormatMoney(s.earned), 0.27, 0.87, 0.27)
		E.UIKit.TipPair(tooltip, L["Session spent"], E:FormatMoney(s.spent), 1, 0.27, 0.27)
		E.UIKit.TipPair(tooltip, L["Session net"], (s.earned >= s.spent and "+" or "") .. MoneyText(s.earned - s.spent))
		local best = Rates:BestHour()
		if best then E.UIKit.TipPair(tooltip, L["Best hour"], MoneyText(best)) end
	end,
	hint = ResetHint,
	combatClick = true,
	onClick = OnClick,
})

E:RegisterDataText("XPRate", {
	title = "XP per hour",
	label = "XP/h",
	poll = true,
	interval = 5,
	events = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "DISABLE_XP_GAIN", "ENABLE_XP_GAIN" },
	text = function()
		if AtCap() then return Grey(E:AtMaxLevel() and L["Max level"] or L["XP off"]) end
		local rate = Rates:Rate("xp")
		if not rate then return Grey("–") end
		return M.Value(E:FormatNumber(math.floor(rate + 0.5)))
	end,
	tooltip = function(tooltip)
		if AtCap() then
			CapTooltip(tooltip)
			return
		end
		local s = Rates.session or NewSession()
		SessionLine(tooltip)
		local rate = Rates:Rate("xp")
		if rate then
			E.UIKit.TipPair(tooltip, L["XP per hour"], BreakUpLargeNumbers(math.floor(rate + 0.5)))
			E.UIKit.TipPair(tooltip, L["Counted over"], Rates:BasisText())
		else
			Counting(tooltip)
		end
		E.UIKit.TipPair(tooltip, L["XP this session"], BreakUpLargeNumbers(s.xp))
		local current, maximum = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
		if current and maximum then
			tooltip:AddLine(" ")
			E.UIKit.TipPair(tooltip, L["To level %d"]:format(UnitLevel("player") + 1), BreakUpLargeNumbers(maximum - current))
			local rested = Plain(GetXPExhaustion and GetXPExhaustion())
			if rested and rested > 0 then
				E.UIKit.TipPair(tooltip, L["Rested"], BreakUpLargeNumbers(rested), 0.56, 0.72, 1)
			end
		end
	end,
	hint = ResetHint,
	combatClick = true,
	onClick = OnClick,
})

E:RegisterDataText("LevelTime", {
	title = "Time to level",
	label = "Level in",
	poll = true,
	interval = 5,
	events = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "DISABLE_XP_GAIN", "ENABLE_XP_GAIN" },
	text = function()
		if AtCap() then return Grey(E:AtMaxLevel() and L["Max level"] or L["XP off"]) end
		local seconds = Rates:TimeToLevel()
		if not seconds then return Grey("–") end
		return M.Value(E:FormatDuration(seconds, "long"))
	end,
	tooltip = function(tooltip)
		if AtCap() then
			CapTooltip(tooltip)
			return
		end
		SessionLine(tooltip)
		local seconds = Rates:TimeToLevel()
		if seconds then
			E.UIKit.TipPair(tooltip, L["Level %d in"]:format(UnitLevel("player") + 1), E:FormatDuration(seconds, "long"))
			E.UIKit.TipPair(tooltip, L["XP per hour"], BreakUpLargeNumbers(math.floor(Rates:Rate("xp") + 0.5)))
			E.UIKit.TipPair(tooltip, L["Counted over"], Rates:BasisText())
		elseif Rates:Elapsed() < MIN_TIME then
			Counting(tooltip)
		else
			E.UIKit.TipText(tooltip, L["No XP gained in the last hour."])
		end
		local current, maximum = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
		if current and maximum then
			E.UIKit.TipPair(tooltip, L["To level %d"]:format(UnitLevel("player") + 1), BreakUpLargeNumbers(maximum - current))
		end
	end,
	hint = ResetHint,
	combatClick = true,
	onClick = OnClick,
})

---------------------------------------------------------------------------
-- Options: one row on the Datatexts tab, before the other addons' feeds.
---------------------------------------------------------------------------
local SESSION_OPTIONS = {
	{ type = "header", label = "Session" },
	{ type = "range", key = "sessionResume", label = "New session after a log-out of", unit = "min", min = 5, max = 240, step = 5,
		desc = "One session counts gold and XP for these blocks, the XP bar and My Adventure, and goes on over a reload. A longer log-out starts a new one. Right-click a rate block to start one yourself." },
}

function M.InsertOptions(rows)
	local at = #M.options + 1
	for index, option in ipairs(M.options) do
		if option.type == "header" and option.label == "Other addons (LibDataBroker)" then at = index break end
	end
	for offset, option in ipairs(rows) do table.insert(M.options, at + offset - 1, option) end
end
M.InsertOptions(SESSION_OPTIONS)
