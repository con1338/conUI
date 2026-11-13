-- EldoUI Group Frames: Blizzard's own party and raid frames.
-- Loaded right after Modules/GroupFrames.lua; adds to the same module.
--
-- Hides, skins and moves Blizzard's party frames, compact raid frames and
-- raid manager, only as far as the "party-frames" and "raid-frames"
-- switches on the Blizzard UI page allow (Core/Blizzard.lua). Protected
-- frames change out of combat. M:ApplyBlizzard and M:RestoreBlizzardAll
-- are called from the module itself; M.inner.SkinAllCompactFrames skins the
-- compact frames again after a roster change.
local _, E = ...
local M = E:GetModule("GroupFrames")
if not M then return end

---------------------------------------------------------------------------
-- Blizzard's party and raid frames (only with the element switches on)
---------------------------------------------------------------------------
local ELEMENTS = { party = "party-frames", raid = "raid-frames" }
-- Hidden frames go to the core's hidden parent and stay there when Edit
-- Mode or the raid manager re-parents them (E:HideBlizzardFrame: SetParent
-- post-hook, after combat for these protected frames).
local wantHidden = {}

local function BlizzardFrames(section)
	if section == "party" then return { PartyFrame, CompactPartyFrame } end
	return { CompactRaidFrameContainer }
end

local function HideFrame(frame)
	if not frame then return end
	wantHidden[frame] = true
	E:HideBlizzardFrame(frame, { check = function() return wantHidden[frame] == true end })
end

local function ShowFrame(frame)
	if not frame or not wantHidden[frame] then return end
	wantHidden[frame] = nil
	E:UnhideBlizzardFrame(frame)
end

local function HideBlizzard(section)
	for _, frame in pairs(BlizzardFrames(section)) do HideFrame(frame) end
end

local function RestoreBlizzard(section)
	for _, frame in pairs(BlizzardFrames(section)) do ShowFrame(frame) end
end

-- Light skin: EldoUI bar texture, dark backdrop and font. Kept in local
-- tables so no fields are written into Blizzard's frames.
local skinned = setmetatable({}, { __mode = "k" })
local hooked = false

local function SkinAllowedFor(frame)
	local name = frame.GetName and frame:GetName()
	-- The game's compact frame setup also runs for frames whose name is
	-- secret: those are never skinned.
	if type(name) ~= "string" or E:IsSecret(name) then return false end
	if name:find("^CompactParty") then return M.skinActive and M.skinActive.party end
	if name:find("^CompactRaid") then return M.skinActive and M.skinActive.raid end
	return false
end

local function SkinCompactFrame(frame)
	if not frame or E.FrameCheck(frame, "IsForbidden") or not SkinAllowedFor(frame) then return end
	pcall(function()
		if frame.healthBar then frame.healthBar:SetStatusBarTexture(E.media.statusbar) end
		if frame.powerBar then frame.powerBar:SetStatusBarTexture(E.media.statusbar) end
		if frame.background then
			frame.background:SetTexture(E.media.flat)
			frame.background:SetVertexColor(unpack(E.media.backdropColor))
		end
		if frame.name then
			local _, size = frame.name:GetFont()
			E:SetNameTextFont(frame.name, size or E.tokens.size.small)
		end
		if frame.statusText then
			local _, size = frame.statusText:GetFont()
			E:SetFont(frame.statusText, size or E.tokens.size.tiny)
		end
		if not skinned[frame] then
			local border = CreateFrame("Frame", nil, frame)
			border:SetPoint("TOPLEFT", -E.pixel, E.pixel)
			border:SetPoint("BOTTOMRIGHT", E.pixel, -E.pixel)
			border:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
			E:SetTemplate(border)
			skinned[frame] = border
		end
	end)
end

-- Blizzard's non-raid-style party frames (portraits): bar texture and font.
local function SkinPartyMemberFrames()
	if not (M.skinActive and M.skinActive.party) or not PartyFrame or not PartyFrame.PartyMemberFramePool then return end
	pcall(function()
		for member in PartyFrame.PartyMemberFramePool:EnumerateActive() do
			local container = member.HealthBarContainer
			if container and container.HealthBar then container.HealthBar:SetStatusBarTexture(E.media.statusbar) end
			if member.ManaBar then member.ManaBar:SetStatusBarTexture(E.media.statusbar) end
			if member.Name then
				local _, size = member.Name:GetFont()
				E:SetNameTextFont(member.Name, size or E.tokens.size.tiny)
			end
		end
	end)
end

local function SkinAllCompactFrames()
	for index = 1, 5 do
		SkinCompactFrame(_G["CompactPartyFrameMember" .. index])
		SkinCompactFrame(_G["CompactPartyFramePet" .. index])
	end
	for index = 1, 40 do SkinCompactFrame(_G["CompactRaidFrame" .. index]) end
	for group = 1, 8 do
		for member = 1, 5 do SkinCompactFrame(_G["CompactRaidGroup" .. group .. "Member" .. member]) end
	end
	SkinPartyMemberFrames()
end
M.inner.SkinAllCompactFrames = SkinAllCompactFrames

local function EnableBlizzardSkin()
	if not hooked then
		hooked = true
		for _, fn in ipairs({ "DefaultCompactUnitFrameSetup", "DefaultCompactMiniFrameSetup", "CompactUnitFrame_SetUpFrame" }) do
			if _G[fn] then hooksecurefunc(fn, SkinCompactFrame) end
		end
		if PartyFrame and PartyFrame.UpdateMemberFrames then
			hooksecurefunc(PartyFrame, "UpdateMemberFrames", SkinPartyMemberFrames)
		end
	end
	SkinAllCompactFrames()
end

-- Move: Blizzard's party and raid containers follow EldoUI's movers. Edit
-- Mode re-anchors them on its own; the core pin puts them back.
local function MoveTarget(frame)
	if frame == PartyFrame then
		return E:BlizzardAllowed("party-frames", "move") and M.holders.party
	elseif frame == CompactRaidFrameContainer then
		return E:BlizzardAllowed("raid-frames", "move") and M.holders.raid
	end
end

-- The core pin re-anchors with the plain widget methods (Edit Mode's
-- overrides never run from EldoUI), after every Edit Mode layout pass, and
-- after combat when Blizzard moved them during a fight.
local function MoveActive(frame)
	return M.active and MoveTarget(frame) and M:GetEngine() ~= "eldo" and true or false
end

local function AnchorBlizzard(frame)
	if not frame then return end
	E:PinBlizzardFrame(frame, {
		active = function() return MoveActive(frame) end,
		anchor = function()
			local holder = MoveTarget(frame)
			if holder then return "TOPLEFT", holder, "TOPLEFT", 0, 0 end
		end,
		scale = function() return M.db.blizzardScale or 1 end,
	})
end


-- Blizzard's raid manager side panel (markers, ready check, filters).
local managerSkinned = false

local function ApplyRaidManager()
	local manager = CompactRaidFrameManager
	if not manager then return end
	local mode = E:BlizzardAllowed("raid-frames") and M.db.raidManager or "blizzard"
	if mode == "hide" then
		HideFrame(manager)
		return
	end
	ShowFrame(manager)
	if mode == "skin" and E:BlizzardAllowed("raid-frames", "skin") and not managerSkinned and E.SkinPanel then
		managerSkinned = true
		pcall(function()
			E:SkinPanel(manager, { close = false, title = false, accentLine = false })
			local display = manager.displayFrame
			-- Icon buttons: the icon is the game's normal texture, so it stays
			-- (with the game's hover and pressed icons) over the EldoUI box.
			for _, key in ipairs({ "readyCheckButton", "rolePollButton", "countdownButton", "editMode", "settings", "hiddenModeToggle" }) do
				if display and display[key] then E:SkinButton(display[key], { keepTextures = true }) end
			end
			for _, name in ipairs({ "CompactRaidFrameManagerLeavePartyButton", "CompactRaidFrameManagerLeaveInstanceGroupButton" }) do
				if _G[name] then E:SkinButton(_G[name]) end
			end
		end)
	end
end

local function RestoreRaidManager()
	local manager = CompactRaidFrameManager
	ShowFrame(manager)
end

-- Hide (or replace) Blizzard's frames and skin/move them as the element
-- switches say. Out of combat only.
function M:ApplyBlizzard()
	local engine = self:GetEngine()
	self.skinActive = {}
	for section, element in pairs(ELEMENTS) do
		local eldoShown = engine == "eldo" and self.db[section].enabled
		local hide = E:BlizzardAllowed(element, "hide") or (eldoShown and E:BlizzardAllowed(element, "replace"))
		if hide then
			HideBlizzard(section)
		else
			RestoreBlizzard(section)
		end
		if engine ~= "eldo" and E:BlizzardAllowed(element, "skin") then
			local wantSkin = engine == "skin" or (self.db.engine == "auto" and self.fallback and self.db.skinBlizzard)
			self.skinActive[section] = wantSkin and true or nil
		end
	end
	if self.skinActive.party or self.skinActive.raid then EnableBlizzardSkin() end
	for _, frame in ipairs({ PartyFrame, CompactRaidFrameContainer }) do
		if MoveTarget(frame) then AnchorBlizzard(frame) end
	end
	ApplyRaidManager()
end

function M:RestoreBlizzardAll()
	self.skinActive = {}
	RestoreBlizzard("party")
	RestoreBlizzard("raid")
	RestoreRaidManager()
end

-- The per-element switches on the Blizzard UI page.
for section, element in pairs(ELEMENTS) do
	E:RegisterBlizzardHandler(element, {
		owner = "GroupFrames",
		apply = function() M:ApplyBlizzard() end,
		undo = function()
			RestoreBlizzard(section)
			if section == "raid" then RestoreRaidManager() end
		end,
		reload = { skin = true, move = true },
		install = { skin = true, replace = true, improve = true },
		-- v0.5.0 already hid or skinned Blizzard's frames when the module was on.
		legacy = function()
			local db = M.db
			return db and db.enabled ~= false and (db.hideBlizzard or db.skinBlizzard) and true or false
		end,
	})
end
