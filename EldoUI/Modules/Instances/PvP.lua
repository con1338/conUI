-- EldoUI Instances: battleground log.
--
-- Battlegrounds and arenas are logged as runs of kind "pvp". They never
-- count toward the hourly limit and show in orange in the log.
--
-- What a battleground run records, all from what the game shows you:
--   * honor and honorable kills from your own honor lines
--     (CHAT_MSG_COMBAT_HONOR_GAIN through E.ChatParse "honor"), or the
--     honor currency's change when no line could be read;
--   * the result: PVP_MATCH_COMPLETE's winner against your team (your
--     own score row's team, else UnitFactionGroup), "Won" or "Lost";
--   * your own score row (killing blows, deaths, damage, healing) from
--     C_PvP.GetScoreInfoByPlayerGuid, read only once the match is over and
--     the game no longer restricts addons in the match. Fields that arrive
--     as secret values are left out.
-- The end-of-match line goes to your own chat only.
local _, E = ...
local L = E.L
local M = E.Instances
local P = E.ChatParse
local C = M.COLORS

local IsSecret, Plain = M.IsSecret, M.Plain

local floor = math.floor

local function Number(value)
	if IsSecret(value) then return nil end
	if type(value) == "number" then return value end
	if type(value) == "string" then return tonumber((value:gsub("[^%d%.%-]", ""))) end
	return nil
end

local function PvPRun()
	local run = M.current
	if run and run.kind == "pvp" then return run end
	return nil
end

---------------------------------------------------------------------------
-- Honor currency: kept out of the "Currencies" stat, recorded here.
---------------------------------------------------------------------------
local HONOR_IDS = { [1792] = true, [1901] = true, [1585] = true }
do
	local consts = Constants and Constants.CurrencyConsts
	if consts then
		for _, key in ipairs({ "HONOR_CURRENCY_ID", "CLASSIC_HONOR_CURRENCY_ID", "ACCOUNT_WIDE_HONOR_CURRENCY_ID" }) do
			if type(consts[key]) == "number" then HONOR_IDS[consts[key]] = true end
		end
	end
end

function M:IsHonorCurrency(currencyID)
	return HONOR_IDS[currencyID] == true
end

-- The honor of a run: the honor lines, or the currency change when that
-- is larger (one of the two may be missing on a ruleset).
function M:RunHonor(run)
	return math.max(run.honor or 0, run.honorCurrency or 0)
end

local function OnHonorLine(_, text)
	local run = PvPRun()
	if not run then return end
	local fields = P:Parse("honor", text)
	if not fields then return end
	if fields.victim and not fields.dishonor then run.hk = (run.hk or 0) + 1 end
	local honor = Number(fields.honor)
	if honor and honor > 0 then run.honor = (run.honor or 0) + floor(honor + 0.5) end
end

local function OnCurrency(_, currencyID, _, change)
	local run = PvPRun()
	if not run then return end
	currencyID, change = Plain(currencyID), Plain(change)
	if type(currencyID) ~= "number" or type(change) ~= "number" or change <= 0 then return end
	if not M:IsHonorCurrency(currencyID) then return end
	run.honorCurrency = (run.honorCurrency or 0) + change
end

---------------------------------------------------------------------------
-- Result and own score row
---------------------------------------------------------------------------
local TEAM_OF_FACTION = { Horde = 0, Alliance = 1 }

local function MatchRestricted()
	local restricted, types = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
	if not (restricted and restricted.IsAddOnRestrictionActive and types and types.PvPMatch) then return false end
	local ok, active = pcall(restricted.IsAddOnRestrictionActive, types.PvPMatch)
	if not ok or IsSecret(active) then return true end
	return active == true
end

local function OwnScore()
	if not (C_PvP and C_PvP.GetScoreInfoByPlayerGuid) then return nil end
	local guid = UnitGUID("player")
	if IsSecret(guid) or not guid then return nil end
	local info = M.Try(C_PvP.GetScoreInfoByPlayerGuid, guid)
	if IsSecret(info) or type(info) ~= "table" then return nil end
	return info
end

local SCORE_FIELDS = {
	{ "killingBlows", "kb" }, { "honorableKills", "hk" }, { "deaths", "deaths" },
	{ "honorGained", "honor" }, { "damageDone", "damage" }, { "healingDone", "healing" },
}

-- Your score row, copied once the match is over and unrestricted.
function M:ReadScore(run)
	if not (run and run.kind == "pvp" and run.matchDone) or run.score then return end
	if MatchRestricted() then return end
	local info = OwnScore()
	if not info then return end
	local score = {}
	for _, field in ipairs(SCORE_FIELDS) do
		local value = Plain(info[field[1]])
		if type(value) == "number" then score[field[2]] = value end
	end
	if next(score) == nil then return end
	run.score = score
	local team = Plain(info.faction)
	if type(team) == "number" then run.team = team end
	self:SetResult(run)
	self:Changed("runs")
end

-- Won or lost: the winner against your team.
function M:SetResult(run)
	if type(run.winner) ~= "number" then return end
	local team = run.team
	if type(team) ~= "number" then
		local faction = UnitFactionGroup("player")
		if IsSecret(faction) then return end
		team = TEAM_OF_FACTION[faction]
	end
	if type(team) ~= "number" then return end
	run.result = run.winner == team and "won" or "lost"
end

local function OnMatchComplete(_, winner, duration)
	local run = PvPRun()
	if not run or run.matchDone then return end
	winner = Plain(winner)
	if type(winner) ~= "number" and C_PvP and C_PvP.GetActiveMatchWinner then
		winner = Plain(M.Try(C_PvP.GetActiveMatchWinner))
	end
	run.matchDone = true
	if type(winner) == "number" then run.winner = winner end
	duration = Plain(duration)
	if type(duration) == "number" and duration > 0 then run.matchDuration = duration end
	M:SetResult(run)
	M:ReadScore(run)
	M:Changed("runs")
end

local function TryScore()
	local run = PvPRun()
	if run then M:ReadScore(run) end
end

M:Listen("CHAT_MSG_COMBAT_HONOR_GAIN", "pvp", OnHonorLine)
M:Listen("CURRENCY_DISPLAY_UPDATE", "pvp", OnCurrency)
M:Listen("PVP_MATCH_COMPLETE", "pvp", OnMatchComplete)
M:Listen("UPDATE_BATTLEFIELD_SCORE", "pvp", TryScore)
M:Listen("ADDON_RESTRICTION_STATE_CHANGED", "pvp", function(_, _, state) E:AfterRestrictionEnds(state, TryScore) end)
M:Listen("PLAYER_LEAVING_WORLD", "pvp", TryScore)

---------------------------------------------------------------------------
-- Display hooks used by Stats.lua and Log.lua
---------------------------------------------------------------------------
local RESULT_TEXT = E:TranslateValues({ won = E.Key("Won"), lost = E.Key("Lost") })

local function ResultText(run, plain)
	local text = RESULT_TEXT[run.result]
	if not text then return nil end
	if plain then return text end
	return (run.result == "won" and C.GREEN or C.RED) .. text .. "|r"
end

function M:RowResult(run)
	if run.kind ~= "pvp" then return nil end
	return ResultText(run)
end

local function HonorKills(run)
	return (run.score and run.score.hk) or run.hk or 0
end

function M:PvPPieces(run, Add, On, opts)
	local result = ResultText(run, opts and opts.plain)
	if result then Add("result", result) end
	if On("honor") then
		local honor = self:RunHonor(run)
		if honor > 0 then Add("honor", (L["+%s honor"]):format(self.Big(honor))) end
		local hk = HonorKills(run)
		if hk > 0 then Add("honor", (L["%d honorable kills"]):format(hk)) end
	end
end

function M:AddPvPStats(tooltip, run)
	local function Line(label, value)
		E.UIKit.TipPair(tooltip, label, value)
	end
	local result = ResultText(run)
	if result then Line(L["Result"], result) end
	local honor = self:RunHonor(run)
	if honor > 0 then Line(L["Honor"], "+" .. self.Big(honor)) end
	local hk = HonorKills(run)
	if hk > 0 then Line(L["Honorable kills"], tostring(hk)) end
	local score = run.score
	if score then
		if score.kb then Line(L["Killing blows"], tostring(score.kb)) end
		if score.deaths then Line(L["Deaths"], tostring(score.deaths)) end
		if (score.damage or 0) > 0 then Line(L["Damage done"], self.Big(score.damage)) end
		if (score.healing or 0) > 0 then Line(L["Healing done"], self.Big(score.healing)) end
	end
end

-- End-of-match line, own chat only.
function M:PvPSummary(run)
	local hasData = run.result or self:RunHonor(run) > 0 or HonorKills(run) > 0
	if not hasData and self.db.summaryOnlyActivity then return end
	local line = self:StatLine(run)
	if line == "" then return end
	self:Notice((L["Left %s: %s"]):format(self:RunTitle(run), line))
end
