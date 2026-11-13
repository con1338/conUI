-- EldoUI minimap host: the game's own minimap shown large inside an EldoUI
-- frame for a while (the dungeon view's Live mode), then put back exactly.
--
--   E:HostMinimap(owner, frame)   moves the minimap into frame, square to
--                                 its shorter side, at the widest zoom;
--                                 false in combat or while another owner
--                                 has it
--   E:FitHostedMinimap(owner)     follows a new frame size
--   E:ReleaseMinimap(owner)       puts back parent, points, size, scale,
--                                 strata, level and zoom; in combat it
--                                 waits for the end of the fight
--   E:MinimapHostOwner()          who has it now, or nil
--
-- The map, the arrow, the group blips and the room pictures are the
-- client's own drawing: nothing reads or adds a position. The minimap is
-- not a protected frame, but it is only moved out of combat. The Minimap
-- module leaves it alone while hosted and lays it out again on release.
local _, E = ...

local host = { owner = nil, saved = nil }

local function Map()
	return rawget(_G, "Minimap")
end

-- Force the map texture to redraw at a new size.
local function Redraw(map)
	local ok, zoom = pcall(map.GetZoom, map)
	if not ok or type(zoom) ~= "number" then return end
	map:SetZoom(zoom > 0 and zoom - 1 or zoom + 1)
	map:SetZoom(zoom)
end

local function Save(map)
	local saved = { parent = map:GetParent(), points = {}, scale = map:GetScale(), strata = map:GetFrameStrata(),
		level = map:GetFrameLevel(), zoom = map.GetZoom and map:GetZoom() }
	saved.width, saved.height = map:GetSize()
	for index = 1, map:GetNumPoints() do saved.points[index] = { map:GetPoint(index) } end
	return saved
end

function E:MinimapHostOwner()
	return host.owner
end

function E:FitHostedMinimap(owner)
	local map = Map()
	if not (map and host.owner == owner and host.frame) or InCombatLockdown() then return false end
	local width, height = host.frame:GetSize()
	local size = math.max(64, math.floor(math.min(width or 0, height or 0)))
	map:SetSize(size, size)
	Redraw(map)
	return true
end

function E:HostMinimap(owner, frame)
	local map = Map()
	if not (map and owner and frame) or InCombatLockdown() then return false end
	if host.owner and host.owner ~= owner then return false end
	if not host.saved then host.saved = Save(map) end
	host.owner, host.frame = owner, frame
	map:SetParent(frame)
	map:ClearAllPoints()
	map:SetPoint("CENTER", frame, "CENTER")
	map:SetScale(1)
	map:SetFrameStrata(frame:GetFrameStrata())
	map:SetFrameLevel((frame:GetFrameLevel() or 1) + 5)
	if map.SetZoom then map:SetZoom(0) end
	self:FitHostedMinimap(owner)
	map:Show()
	return true
end

function E:ReleaseMinimap(owner)
	local map = Map()
	if not (map and host.owner and host.owner == owner) then return false end
	if InCombatLockdown() then
		self:RunOutOfCombat(function() E:ReleaseMinimap(owner) end)
		return false
	end
	local saved = host.saved
	host.owner, host.frame, host.saved = nil, nil, nil
	if saved then
		map:SetParent(saved.parent)
		map:ClearAllPoints()
		for _, point in ipairs(saved.points) do map:SetPoint(unpack(point)) end
		map:SetScale(saved.scale or 1)
		if saved.width and saved.height then map:SetSize(saved.width, saved.height) end
		if saved.strata then map:SetFrameStrata(saved.strata) end
		if saved.level then map:SetFrameLevel(saved.level) end
		if map.SetZoom and type(saved.zoom) == "number" then map:SetZoom(saved.zoom) end
	end
	-- The Minimap module puts its own layout back on top.
	local module = self.modules and self.modules.Minimap
	if module and module.active and module.ApplyMap then pcall(module.ApplyMap, module) end
	Redraw(map)
	return true
end
