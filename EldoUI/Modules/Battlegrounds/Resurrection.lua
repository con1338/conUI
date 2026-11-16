-- Battleground Timers: the next resurrection wave.
--
-- A dead player waiting at a battleground spirit healer is brought back in
-- waves. The game counts down to the next one (GetAreaSpiritHealerTime, the
-- same value its own pop-up reads); this part shows it as a "Next
-- resurrection" bar at the top of the stack in your faction's color, from
-- entering the healer's range until you are back on your feet or walk out
-- of range. When a wave passes and you are still waiting, the bar reads
-- the game's time again. A late join or a reload while waiting starts the
-- bar from the game's time. A secret value hides the bar.
--
-- Presentation only: it never accepts, cancels or releases anything, and
-- Blizzard's pop-up stays as it is.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local M = E:GetModule("Battlegrounds")
local Read = M.Read

local R = M:AddPart({ name = "resurrection" })
M.Resurrection = R

local KEY = "resurrect"
local REREAD = 0.5 -- seconds after a wave before the time is read again

-- Seconds to the next wave, or nil (not waiting, not known, or secret).
function R.WaveTime()
	if not GetAreaSpiritHealerTime then return nil end
	local left = Read(GetAreaSpiritHealerTime)
	left = tonumber(left)
	if not left or left <= 0 then return nil end
	return left
end

local function Stop()
	R.waiting = nil
	if R.timer then R.timer:Cancel() end
	R.timer = nil
	M:Stop(KEY)
end
R.Stop = Stop

-- Start or move the bar to the game's time; while still waiting, look
-- again just after the wave.
function R:Update()
	if self.timer then self.timer:Cancel() end
	self.timer = nil
	if not (self.waiting and M.map and M.db.resurrect) then
		M:Stop(KEY)
		return
	end
	local left = R.WaveTime()
	if not left then
		M:Stop(KEY)
		return
	end
	if not M:BarNear(KEY, left, 1) then
		M:Bar(KEY, { kind = M.Side(Read(UnitFactionGroup, "player")) or "other", pin = true,
			label = L["Next resurrection"], duration = left, icon = "Interface\\Icons\\Spell_Holy_Resurrection",
			tooltip = L["Time until the spirit healer brings back everyone waiting, as the game counts it."] })
	end
	if C_Timer and C_Timer.NewTimer then
		self.timer = C_Timer.NewTimer(left + REREAD, function()
			R.timer = nil
			R:Update()
		end)
	end
end

local function InRange()
	R.waiting = true
	R:Update()
end

function R:Enable()
	M:RegisterEvent("AREA_SPIRIT_HEALER_IN_RANGE", InRange)
	M:RegisterEvent("AREA_SPIRIT_HEALER_OUT_OF_RANGE", Stop)
	M:RegisterEvent("PLAYER_ALIVE", Stop)
	M:RegisterEvent("PLAYER_UNGHOST", Stop)
end

function R:Disable()
	M:UnregisterEvent("AREA_SPIRIT_HEALER_IN_RANGE")
	M:UnregisterEvent("AREA_SPIRIT_HEALER_OUT_OF_RANGE")
	M:UnregisterEvent("PLAYER_ALIVE")
	M:UnregisterEvent("PLAYER_UNGHOST")
	Stop()
end

-- A late join or a reload while waiting: the game's time already runs.
function R:Enter()
	if Read(UnitIsDeadOrGhost, "player") and R.WaveTime() then InRange() end
end

function R:Leave()
	Stop()
end

function R:Refresh()
	if self.waiting then self:Update() else M:Stop(KEY) end
end
