-- Gnome Dash's private preview models and native portrait fallbacks.
local _, E = ...
local M = E.FlightGames
local Board = M.Board

-- Each form is one of the game's own dressed character displays (a gnome
-- rogue and a dwarf warrior), which carry their skin, hair and clothes.
-- male and female are the race's model files a loaded display must use.
local Appearance = {
	small = { display = 146970, male = 900914, female = 940356, distance = 2.20, height = 0.76,
		icon = "Interface\\Icons\\Achievement_Character_Gnome_Male" },
	big = { display = 147595, male = 878772, female = 950080, distance = 2.58, height = 0.89,
		icon = "Interface\\Icons\\Achievement_Character_Dwarf_Male" },
	jumpAnimation = 38,
}
M.MushroomAppearance = Appearance

local Hero = {}
Hero.__index = Hero

local Read = E.PlainCall or function(method, ...)
	if type(method) ~= "function" then return nil end
	local ok, value = pcall(method, ...)
	if ok and not (issecretvalue and issecretvalue(value)) then return value end
end

local function ConfigureCamera(scene, style)
	scene:SetCameraNearClip(0.05)
	scene:SetCameraFarClip(12)
	scene:SetCameraFieldOfView(0.78)
	scene:SetCameraPosition(-style.distance, 0, style.height)
	scene:SetCameraOrientationByAxisVectors(1, 0, 0, 0, -1, 0, 0, 0, 1)
	scene:SetLightVisible(true)
	scene:SetLightAmbientColor(0.78, 0.78, 0.78)
	scene:SetLightDiffuseColor(0.70, 0.70, 0.70)
	scene:SetLightDirection(1, -1, -1)
end

function Hero:BuildScene()
	local scene = CreateFrame("ModelScene", nil, self.frame)
	self.scene = scene
	scene:SetAllPoints(self.frame)
	scene:SetAlpha(0)
	scene:EnableMouse(false)
	ConfigureCamera(scene, self.style)
	local actor = scene:CreateActor(nil, "ModelSceneActorTemplate")
	if not actor then return false end
	self.actor = actor
	actor:Show()
	actor:SetYaw(self.facing or 0)
	self.modelDeadline = GetTime() + 3
	-- The display alone: never the player's own character in another race,
	-- whose customizations that race lacks and which then draws untextured.
	return Read(actor.SetModelByCreatureDisplayID, actor, self.style.display, false) == true
end

function Hero:FinishLoading(now)
	local actor = self.actor
	local loaded = Read(actor.IsLoaded, actor) == true
	if not loaded and now < self.modelDeadline then return end
	local model = loaded and Read(actor.GetModelFileID, actor)
	if model ~= self.style.male and model ~= self.style.female then
		self.unavailable = true
		return
	end
	self.ready = true
	Read(actor.SetAnimation, actor, self.animation or Board.ANIM.stand)
end

function Hero:ApplyPause()
	if not self.ready then return end
	local paused = not (self.running and self.showModel and self.frame:IsVisible())
	if self.paused == paused then return end
	self.paused = paused
	Read(self.scene.SetPaused, self.scene, paused, false)
end

function Hero:Refresh()
	local want = self.visible and self.frame:IsVisible() and M.db and M.db.models
	if want and not self.scene and not self.unavailable then
		local ok, created = pcall(self.BuildScene, self)
		self.unavailable = not (ok and created)
	end
	if want and self.actor and not self.ready and not self.unavailable then
		local now = GetTime()
		if not self.nextPoll or now >= self.nextPoll then
			self.nextPoll = now + 0.15
			self:FinishLoading(now)
		end
	end
	local showModel = want and self.ready and not self.unavailable and true or false
	if self.scene then
		self.scene:SetShown(want and not self.unavailable and true or false)
		if self.showModel ~= showModel then self.scene:SetAlpha(showModel and 1 or 0) end
	end
	self.showModel = showModel
	self.icon:SetShown(not showModel)
	self:ApplyPause()
end

function Appearance.NewHero(parent, role, size)
	local style = Appearance[role]
	if not style then return nil end
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(size, size)
	frame:SetFrameLevel(parent:GetFrameLevel() + 2)
	frame:EnableMouse(false)
	frame:Hide()
	local icon = Board.Sprite(frame, size, size, "OVERLAY")
	icon:SetPoint("TOPLEFT")
	E:SetClientFile(icon, style.icon, "Interface\\Icons\\INV_Misc_QuestionMark")
	E:TrimIcon(icon)
	local hero = setmetatable({ frame = frame, icon = icon, style = style }, Hero)
	frame:SetScript("OnHide", function() hero:ApplyPause() end)
	frame:SetScript("OnShow", function() hero:Refresh() end)
	return hero
end

function Hero:Place(x, y)
	if self.x == x and self.y == y then return end
	self.x, self.y = x, y
	Board.Place(self.frame, x, y)
end

function Hero:SetShown(on)
	local visible = on and true or false
	if self.visible ~= visible then
		self.visible = visible
		self.frame:SetShown(visible)
	end
	self:Refresh()
end

function Hero:SetAlpha(alpha)
	self.frame:SetAlpha(alpha)
end

function Hero:Face(facing)
	if self.facing == facing then return end
	self.facing = facing
	if self.actor then Read(self.actor.SetYaw, self.actor, facing) end
end

function Hero:Animate(animation)
	if self.animation == animation then return end
	self.animation = animation
	if self.ready then Read(self.actor.SetAnimation, self.actor, animation) end
end

function Hero:SetRunning(running)
	self.running = running
	self:ApplyPause()
end
