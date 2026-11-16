-- XP from one level to the next, the number the game shows as the XP bar's
-- maximum at that level, for levels 1 to 59 (the curve WoW: Forever uses).
-- The game's own number always wins: at your level the XP bar's maximum is
-- read, and a level where it differs from this list is kept for the
-- character and noted once in the error log as a warning, so the list can
-- be corrected. Static data and your own XP only.
--
--   E.LevelXP.ToNext(level)              XP from `level` to the next, or nil
--   E.LevelXP.Learn(level, xpMax)        check the game's number at a level
--   E.LevelXP.ToLevel(target, level, left)
--                                        XP from where you are (`left` XP to
--                                        go at `level`) to `target`, or nil
--   E.LevelXP.Span(from, to)             XP from level `from` to level `to`
--   E.LevelXP.FinishedQuestXP()          XP in finished quests not handed in
--                                        yet, and how many quests
local _, E = ...

local X = {
	toNext = {
		400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600,
		8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
		25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
		50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
		95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
		153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800,
	},
}
E.LevelXP = X

E:RegisterPrivate("levelXP", { learned = {} })

local function Learned()
	local store = E:GetPrivate("levelXP")
	if not store then return nil end
	store.learned = type(store.learned) == "table" and store.learned or {}
	return store.learned
end

function X.ToNext(level)
	level = tonumber(level)
	if not level then return nil end
	local learned = Learned()
	return learned and tonumber(learned[level]) or X.toNext[level]
end

-- The game's number at `level`; a difference from the list is kept for this
-- character and logged once. Returns true when the list was wrong here.
function X.Learn(level, xpMax)
	level, xpMax = tonumber(level), tonumber(xpMax)
	if not (level and xpMax and xpMax > 0) then return false end
	local listed = X.toNext[level]
	local learned = Learned()
	if not listed or listed == xpMax or not learned then return false end
	if learned[level] ~= xpMax then
		learned[level] = xpMax
		if E.errors and E.errors.Add then
			E.errors:Add("warning", ("Level %d needs %d XP in the game, EldoUI's level list says %d."):format(level, xpMax, listed),
				nil, nil, nil, "EldoUI")
		end
	end
	return true
end

function X.Span(from, to)
	local total = 0
	for level = from, to - 1 do
		local xp = X.ToNext(level)
		if not xp then return nil end
		total = total + xp
	end
	return total
end

function X.ToLevel(target, level, left)
	target, level, left = tonumber(target), tonumber(level), tonumber(left)
	if not (target and level and left) or target <= level then return nil end
	local rest = X.Span(level + 1, target)
	return rest and left + rest or nil
end

local function Plain(value)
	if E.Secret(value) or type(value) ~= "number" then return nil end
	return value
end

-- XP waiting in finished quests that are not handed in yet: total, count.
function X.FinishedQuestXP()
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo and C_QuestLog.IsComplete) then return 0, 0 end
	if not GetQuestLogRewardXP then return 0, 0 end
	local total, count = 0, 0
	for index = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
		local info = C_QuestLog.GetInfo(index)
		local questID = info and not info.isHeader and info.questID
		if questID and C_QuestLog.IsComplete(questID) then
			local ok, xp = pcall(GetQuestLogRewardXP, questID)
			xp = ok and Plain(xp)
			if xp and xp > 0 then
				total = total + xp
				count = count + 1
			end
		end
	end
	return total, count
end
