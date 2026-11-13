-- EldoUI Loot Sim: the job scheduler.
--
-- One job at a time runs as a coroutine in small steps: each frame it may
-- use the Sim speed budget (smooth 4 ms, fast 8 ms, turbo 16 ms), then it
-- yields until the next frame. The engine checks the budget every few
-- hundred events and between fights. When combat starts the job pauses at
-- once (it never runs a step in combat) and goes on when combat ends.
--
-- Scheduler.Start(job) job = { name, run = fn(job), onDone, onError, onUpdate }
--   inside run: job:Step() between pieces of work, job.progress = 0..1
-- Scheduler.Stop(), Scheduler.Current(), Scheduler.IsPaused()
local _, S = ...
local D = S.Data

local Scheduler = {}
S.Scheduler = Scheduler

local current      -- the running job
local paused = false
local frame
local stepStart = 0
local lastCheck = 0   -- when the job last checked the budget
local budget = 8

local function Now()
	return debugprofilestop and debugprofilestop() or 0
end

local function Budget()
	local LG = S.E and S.E.LootGuide
	local speed = LG and LG.SimSpeed and LG:SimSpeed() or "fast"
	return D.SPEEDS[speed] or D.SPEEDS.fast
end
Scheduler.Budget = Budget

local function InCombat()
	return InCombatLockdown and InCombatLockdown() or false
end

-- Called by the job (and the engine's hook): yields when the next piece
-- of work would not fit in this frame's budget. The piece since the last
-- check is the estimate, so a step ends inside the budget instead of one
-- piece past it.
local function Check()
	if not current or coroutine.running() ~= current.thread then return end
	local now = Now()
	local piece = now - lastCheck
	lastCheck = now
	if now - stepStart + piece >= budget then
		coroutine.yield()
	end
end
Scheduler.Check = Check

local function Notify(job, what, ...)
	local fn = job[what]
	if type(fn) == "function" then
		local ok, err = pcall(fn, job, ...)
		if not ok then geterrorhandler()(err) end
	end
end

local function Finish(job, ok, err)
	if current == job then current = nil end
	if frame then frame:Hide() end
	if ok then
		job.done = true
		job.progress = 1
		Notify(job, "onDone")
	else
		job.failed = err
		geterrorhandler()(("EldoUI Loot Sim job %s: %s"):format(tostring(job.name), tostring(err)))
		Notify(job, "onError", err)
	end
end

local function OnUpdate()
	local job = current
	if not job then
		frame:Hide()
		return
	end
	if paused or InCombat() then return end
	budget = Budget()
	stepStart = Now()
	lastCheck = stepStart
	local ok, err = coroutine.resume(job.thread, job)
	job.lastStep = Now() - stepStart
	job.maxStep = math.max(job.maxStep or 0, job.lastStep)
	if not ok then
		Finish(job, false, err)
	elseif coroutine.status(job.thread) == "dead" then
		Finish(job, true)
	else
		Notify(job, "onUpdate")
	end
end
Scheduler.OnUpdate = OnUpdate

function Scheduler.Start(job)
	if InCombat() then return false, "combat" end
	if current then Scheduler.Stop() end
	job.progress = 0
	job.Step = Check
	job.thread = coroutine.create(function(self)
		self.run(self)
	end)
	current = job
	if not frame then
		frame = CreateFrame("Frame")
		frame:SetScript("OnUpdate", OnUpdate)
		frame:RegisterEvent("PLAYER_REGEN_DISABLED")
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		frame:SetScript("OnEvent", function(_, event)
			paused = event == "PLAYER_REGEN_DISABLED"
			if current then Notify(current, "onUpdate") end
		end)
	end
	paused = false
	frame:Show()
	Notify(job, "onUpdate")
	return true
end

function Scheduler.Stop()
	local job = current
	if not job then return false end
	current = nil
	job.stopped = true
	if frame then frame:Hide() end
	Notify(job, "onStop")
	return true
end

function Scheduler.Current()
	return current
end

function Scheduler.IsPaused()
	return current ~= nil and (paused or InCombat())
end
