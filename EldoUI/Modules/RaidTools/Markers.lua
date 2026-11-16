-- EldoUI Raid Tools: the world marker buttons show which markers are on
-- the ground.
--
-- The game sends no event when a world marker is placed or removed, so a
-- slow check reads IsRaidMarkerActive about once a second: only in a group,
-- only while the bar shows, never in combat. A placed marker's button is
-- lit and its tooltip says Placed; the others are dimmed.
local _, E = ...
local L = E.L
local M = E.modules.RaidTools

function M.MarkerStatus(button)
	return button.placed and L["Placed"] or L["Not placed"]
end

-- A placed world marker's button is lit; one not on the ground is dimmed.
function M:UpdateMarkers()
	local bar = self.bar
	if not bar or not bar.markers or InCombatLockdown() then return end
	local read = _G.IsRaidMarkerActive
	for _, button in ipairs(bar.markers) do
		local placed = false
		if read and IsInGroup() then
			local ok, value = pcall(read, button.marker)
			placed = ok and E.Plain(value) == true
		end
		button.placed = placed
		button.icon:SetDesaturated(not placed)
		button.icon:SetAlpha(placed and 1 or 0.45)
	end
	self:SyncMarkerWatch()
end

function M:SyncMarkerWatch()
	local bar = self.bar
	M.WatchMarkers(self.active and bar and #bar.markers > 0 and bar:IsVisible() and self.db.worldMarkers
		and not InCombatLockdown() and type(_G.IsRaidMarkerActive) == "function" and IsInGroup())
end

-- The once-a-second check: on while wanted, off otherwise.
function M.WatchMarkers(on)
	local bar, ticker = M.bar, E.Ticker
	if not bar then return end
	if on then
		if not ticker:IsSubscribed(bar) then ticker:Subscribe(bar, 1, function() M:UpdateMarkers() end, M) end
	else
		ticker:Unsubscribe(bar)
	end
end
