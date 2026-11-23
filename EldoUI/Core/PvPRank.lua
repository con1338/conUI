-- EldoUI PvP rank: WoW: Forever's season rank track, read the way the
-- game's own rank window on Character > PvP reads it, for the Status Bars'
-- rank bar and the Info Bar's PvP rank block, so both always agree.
--
-- The rank is a season track of 14 ranks fed by Rank Points. Each week the
-- game raises the highest rank that week can reach; the track resets when
-- the season ends. The client keeps it as the renown of faction 2800.
--
--   E.PvPRank:Read()            the state below, or nil while the game has none
--   E.PvPRank:Title(rank)       the rank's title in the client's language
--   E.PvPRank:NextReward(rank)  { rank, name, icon } of the next rank with a reward
--   E.PvPRank:SeasonLeft()      seconds until the season ends, or nil
--   E.PvPRank:AddTooltip(tooltip, state)  the shared tooltip lines
--
-- Read() returns { rank, title, earned, needed, total, weekRank, weekTotal,
-- weekRaise, topRank, capped, atTop, capShare }: earned of needed Rank
-- Points into the next rank, the season total against the total this
-- week's cap allows, and where that cap falls on the current rank's bar
-- (capShare, 0 to 1, only when it falls inside it).
--
-- Rules (Forever): the player's own progress as the game reports it;
-- every value is checked for a secret before any math. Nothing is
-- predicted: no rank by date.
local _, E = ...
local L = E.L

local IsSecret = E.Secret
local FACTION = 2800
local RANKS = 14

local R = { FACTION = FACTION, RANKS = RANKS }
E.PvPRank = R

local function Plain(value)
	if IsSecret(value) or type(value) ~= "number" then return nil end
	return value
end

local function Factions()
	local factions = rawget(_G, "C_MajorFactions")
	return type(factions) == "table" and factions or nil
end

-- Total Rank Points the season needs to reach a rank (0 for none).
local function TotalFor(rank)
	if not rank or rank <= 0 then return 0 end
	local factions = Factions()
	if not (factions and factions.GetTotalReputationForRenownLevel) then return nil end
	local ok, total = pcall(factions.GetTotalReputationForRenownLevel, FACTION, rank)
	return ok and Plain(total) or nil
end
R.TotalFor = TotalFor

-- The title as the game's rank window builds it: PVP_RANK_<4 + rank>_<0
-- Horde, 1 Alliance>, with the female form where the client has one.
function R:Title(rank)
	if not rank or rank < 1 then return end
	local ok, side = pcall(UnitFactionGroup, "player")
	local key = ("PVP_RANK_%d_%d"):format(rank + 4, ok and side == "Alliance" and 1 or 0)
	local getText = rawget(_G, "GetText")
	if getText then
		local sexOK, sex = pcall(UnitSex, "player")
		local fine, text = pcall(getText, key, sexOK and Plain(sex) or nil)
		if fine and type(text) == "string" and not IsSecret(text) and text ~= "" and text ~= key then return text end
	end
	local text = rawget(_G, key)
	if type(text) == "string" and text ~= "" then return text end
end

function R:Read()
	local factions = Factions()
	if not (factions and factions.GetMajorFactionProgressionInfo) then return end
	local ok, info = pcall(factions.GetMajorFactionProgressionInfo, FACTION)
	if not ok or type(info) ~= "table" then return end
	local rank = Plain(info.renownLevel)
	if not rank or rank < 0 or rank > RANKS then return end
	local top = Plain(info.maxLevel)
	if not top or top < 1 or top > RANKS then top = RANKS end
	local state = { rank = rank, title = self:Title(rank), topRank = top, atTop = rank >= top }
	local earned, needed = Plain(info.renownReputationEarned), Plain(info.renownLevelThreshold)
	if not state.atTop then
		-- No threshold toward the next rank: the game has not sent the track.
		if not needed or needed <= 0 then return end
		state.earned, state.needed = math.max(0, math.min(earned or 0, needed)), needed
	end
	local base = TotalFor(rank)
	if base then state.total = base + (state.earned or 0) end
	local week = Plain(info.currentWeekProgressiveMaxLevel)
	if week and week >= 1 and week <= top then
		state.weekRank = week
		state.weekTotal = TotalFor(week)
		local before = Plain(info.previousWeekProgressiveMaxLevel)
		local beforeTotal = before and before >= 1 and TotalFor(before)
		if state.weekTotal and beforeTotal and state.weekTotal > beforeTotal then state.weekRaise = state.weekTotal - beforeTotal end
	end
	if not state.atTop and state.total and state.weekTotal then
		state.capped = state.total >= state.weekTotal
		local nextTotal = base and base + state.needed
		if base and nextTotal and state.weekTotal > base and state.weekTotal < nextTotal then
			state.capShare = (state.weekTotal - base) / state.needed
		end
	end
	return state
end

-- The next rank above `rank` that gives a reward, with the reward's name and
-- icon as the game reports them (the item's own when the reward names none).
function R:NextReward(rank)
	local factions = Factions()
	if not (factions and factions.GetRenownRewardsForLevel) then return end
	for level = (rank or 0) + 1, RANKS do
		local ok, rewards = pcall(factions.GetRenownRewardsForLevel, FACTION, level)
		if ok and type(rewards) == "table" then
			for _, reward in ipairs(rewards) do
				if type(reward) == "table" then
					local name, icon = reward.name, Plain(reward.icon) or reward.icon
					local itemID = Plain(reward.itemID)
					if (type(name) ~= "string" or IsSecret(name) or name == "") and itemID and C_Item then
						name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
						icon = icon or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID))
					end
					if type(name) == "string" and not IsSecret(name) and name ~= "" then
						return { rank = level, name = name, icon = (type(icon) == "number" or type(icon) == "string") and icon or nil }
					end
				end
			end
		end
	end
end

-- Seconds until the season ends; nil when the game does not know (it then
-- reports 0 and its own rank window hides the line too).
function R:SeasonLeft()
	local season = rawget(_G, "C_SeasonInfo")
	if not (type(season) == "table" and season.GetTimeUntilCurrentPVPSeasonEnd) then return end
	local ok, left = pcall(season.GetTimeUntilCurrentPVPSeasonEnd)
	left = ok and Plain(left) or nil
	if left and left > 0 then return left end
end

-- Days and hours, or hours and minutes in the last day.
local function Left(seconds)
	local days, hours = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
	if days > 0 then return L["%dd %dh"]:format(days, hours) end
	return E:FormatDuration(seconds, "long")
end

local function Number(value)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value)
end

local function RankName(rank, title)
	local text = L["Rank %d"]:format(rank)
	if title then text = text .. " - " .. title end
	return text
end

-- The rank, progress, weekly cap, season end, next reward and kill counts.
function R:AddTooltip(tooltip, state)
	local Kit = E.UIKit
	if not state then
		Kit.TipText(tooltip, L["The game has not sent your PvP rank yet."])
		return
	end
	if state.rank > 0 then
		Kit.TipTitle(tooltip, RankName(state.rank, state.title))
	else
		Kit.TipTitle(tooltip, L["No rank yet"])
	end
	if state.atTop then
		Kit.TipText(tooltip, L["The highest rank of the season."])
	else
		Kit.TipPair(tooltip, L["Rank Points"], ("%s / %s"):format(Number(state.earned), Number(state.needed)))
		if state.capped then
			tooltip:AddLine(L["Capped this week: more Rank Points count once next week's cap opens."], E:TokenColor("warn"))
		end
	end
	if state.total and state.weekTotal then
		Kit.TipPair(tooltip, L["Season total"], ("%s / %s"):format(Number(state.total), Number(state.weekTotal)))
	end
	if state.weekRank then Kit.TipPair(tooltip, L["This week's cap"], L["Rank %d"]:format(state.weekRank)) end
	if state.weekRaise then Kit.TipPair(tooltip, L["Cap increase this week"], Number(state.weekRaise)) end
	Kit.TipPair(tooltip, L["Highest rank this season"], L["Rank %d"]:format(state.topRank))
	local left = self:SeasonLeft()
	if left then Kit.TipPair(tooltip, L["Season ends in"], Left(left)) end
	local reward = not state.atTop and self:NextReward(state.rank)
	if reward then
		tooltip:AddLine(" ")
		Kit.TipPair(tooltip, L["Next reward"], L["Rank %d"]:format(reward.rank))
		local icon = reward.icon and ("|T%s:0|t "):format(tostring(reward.icon)) or ""
		Kit.TipTitle(tooltip, icon .. reward.name)
	end
	local today = rawget(_G, "GetPVPSessionStats") and select(2, pcall(GetPVPSessionStats))
	local okLife, lifetime, highest = false, nil, nil
	if rawget(_G, "GetPVPLifetimeStats") then okLife, lifetime, highest = pcall(GetPVPLifetimeStats) end
	today = Plain(today)
	lifetime = okLife and Plain(lifetime) or nil
	if today or lifetime then
		tooltip:AddLine(" ")
		if today then Kit.TipPair(tooltip, L["Honorable kills today"], Number(today)) end
		if lifetime then Kit.TipPair(tooltip, L["Honorable kills, lifetime"], Number(lifetime)) end
	end
	-- The highest rank ever, as the game's rank number (Rank 1 is 5).
	highest = okLife and Plain(highest) or nil
	if highest and highest >= 5 then
		Kit.TipPair(tooltip, L["Highest rank reached"], RankName(highest - 4, self:Title(highest - 4)))
	end
end
