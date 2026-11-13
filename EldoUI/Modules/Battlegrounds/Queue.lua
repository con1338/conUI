-- Battleground Timers: queue, time to enter and battle start bars.
--
-- Queue: UPDATE_BATTLEFIELD_STATUS(index) -> GetBattlefieldStatus(index).
--   queued   the game's estimated wait minus the time waited (both in ms);
--            past the estimate, or a paused queue, the bar freezes on "-"
--   confirm  the battleground is ready: "Enter <map>" with the time from
--            GetBattlefieldPortExpiration (seconds)
--   active   inside: that queue's bars go (another queue keeps its bar)
--   none     the queue was left
-- The bars restart only when the game's number moves by more than a few
-- seconds, so they count down smoothly. A /reload while queued finds the
-- queues again (every index up to GetMaxBattlefieldID).
-- Start: START_TIMER(timerType, seconds) with Enum.StartTimerType
-- PvPBeginTimer only; STOP_TIMER_OF_TYPE ends it.
-- No sound here: the ready sound lives in Notifications (pop-ups).
-- Nothing accepts, leaves or re-queues.
local _, E = ...
local L = E.L
local M = E:GetModule("Battlegrounds")
local Read, IsSecret = M.Read, M.IsSecret

local Q = M:AddPart({ name = "queue" })
M.Queue = Q

local QUEUE_SLACK = 10   -- seconds a queue estimate may drift before the bar restarts
local PORT_SLACK = 2
local START_SLACK = 1

local function PvPBeginType()
	local enum = Enum and Enum.StartTimerType
	return enum and enum.PvPBeginTimer or 0
end

---------------------------------------------------------------------------
-- Icons for queues: the battleground's own icon from the game's list.
---------------------------------------------------------------------------
local icons -- name -> icon
local function QueueIcon(mapName)
	if not icons then
		icons = {}
		local count = Read(GetNumBattlegroundTypes) or 0
		local getInfo = C_PvP and C_PvP.GetBattlegroundInfo
		for index = 1, count do
			local info = Read(getInfo, index)
			if type(info) == "table" and type(info.name) == "string" and not IsSecret(info.name)
				and not IsSecret(info.icon) and info.icon then
				icons[info.name] = info.icon
			end
		end
	end
	return icons[mapName] or M:FactionIcon()
end

---------------------------------------------------------------------------
-- Queues
---------------------------------------------------------------------------
function Q:StopQueue(index)
	M:Stop("queue:" .. index)
	M:Stop("port:" .. index)
end

function Q:Update(index)
	local db = M.db
	local status, mapName, _, _, suspended = Read(GetBattlefieldStatus, index)
	-- issecretvalue before any comparison: comparing a secret errors.
	if IsSecret(status) or IsSecret(mapName) or IsSecret(suspended) then status, mapName, suspended = nil, nil, nil end
	if type(mapName) ~= "string" or mapName == "" then mapName = L["Battleground"] end
	if status == "queued" then
		M:Stop("port:" .. index)
		if not db.queue.wait then
			M:Stop("queue:" .. index)
			return
		end
		local estimate = Read(GetBattlefieldEstimatedWaitTime, index)
		local waited = Read(GetBattlefieldTimeWaited, index)
		local data = { kind = "queue", label = mapName, icon = QueueIcon(mapName),
			tooltip = L["The game's estimated wait for this queue."] }
		local left = (type(estimate) == "number" and type(waited) == "number") and (estimate - waited) / 1000 or nil
		if suspended or not left or estimate <= 0 or left <= 1 then
			M:Freeze("queue:" .. index, data, "-")
		else
			local current = M:Get("queue:" .. index)
			if current and not current.frozenText and M:BarNear("queue:" .. index, left, QUEUE_SLACK) then return end
			data.duration = left
			M:Bar("queue:" .. index, data)
		end
	elseif status == "confirm" then
		M:Stop("queue:" .. index)
		if not db.queue.port then
			M:Stop("port:" .. index)
			return
		end
		local seconds = Read(GetBattlefieldPortExpiration, index)
		if type(seconds) ~= "number" or seconds <= 0 then
			M:Stop("port:" .. index)
			return
		end
		if M:BarNear("port:" .. index, seconds, PORT_SLACK) then return end
		M:Bar("port:" .. index, { kind = "port", label = L["Enter %s"]:format(mapName), duration = seconds, icon = QueueIcon(mapName),
			tooltip = L["Time left to enter the battleground. Use Blizzard's pop-up to enter."] })
	elseif status == "active" then
		-- Only this queue: a second queue may still be waiting.
		self:StopQueue(index)
	else

		self:StopQueue(index)
	end
end

function Q:MaxQueues()
	local max = Read(GetMaxBattlefieldID)
	return type(max) == "number" and max > 0 and math.min(max, 10) or 3
end

function Q:UpdateAll()
	for index = 1, self:MaxQueues() do self:Update(index) end
end

---------------------------------------------------------------------------
-- Battle start
---------------------------------------------------------------------------
function Q:StartTimer(timerType, seconds)
	if timerType ~= PvPBeginType() then return end
	if not M.db.start or type(seconds) ~= "number" or IsSecret(seconds) or seconds <= 0 then return end
	if M:BarNear("start", seconds, START_SLACK) then return end
	M:Bar("start", { kind = "start", label = L["Battle begins"], duration = seconds,
		tooltip = L["Time until the gates open."] })
end

---------------------------------------------------------------------------
-- Part hooks
---------------------------------------------------------------------------
function Q:Enable()
	M:RegisterEvent("UPDATE_BATTLEFIELD_STATUS", function(_, _, index)
		if type(index) == "number" and not IsSecret(index) then Q:Update(index) else Q:UpdateAll() end
	end)
	M:RegisterEvent("START_TIMER", function(_, _, timerType, seconds)
		if IsSecret(timerType) then return end
		Q:StartTimer(timerType, seconds)
	end)
	M:RegisterEvent("STOP_TIMER_OF_TYPE", function(_, _, timerType)
		if not IsSecret(timerType) and timerType == PvPBeginType() then M:Stop("start") end
	end)
	self:UpdateAll()
end

function Q:Disable()
	M:UnregisterEvent("UPDATE_BATTLEFIELD_STATUS")
	M:UnregisterEvent("START_TIMER")
	M:UnregisterEvent("STOP_TIMER_OF_TYPE")
end

function Q:Leave()
	M:Stop("start")
	self:UpdateAll()
end

function Q:Refresh()
	if not M.db.start then M:Stop("start") end
	self:UpdateAll()
end
