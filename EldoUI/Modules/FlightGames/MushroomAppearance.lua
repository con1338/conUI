-- Gnome Dash's hero: an animated gnome or dwarf character model, with the
-- race portrait while the model loads or when creature models are off.
local _, E = ...
local M = E.FlightGames
local Board = M.Board

-- Each form tries the game's own dressed character displays in order (a
-- gnome or dwarf with baked skin, hair and clothes) until one loads. files
-- are the race's model files as the client reports them for a loaded
-- display (the character model the game draws, then the newer model files
-- of the same race); a display that reports another model file is passed
-- over.
local Appearance = {
	small = { displays = { 146970, 13260, 7831 }, files = { [119159] = true, [900914] = true, [940356] = true },
		distance = 2.20, height = 0.76, icon = "Interface\\Icons\\Achievement_Character_Gnome_Male" },
	big = { displays = { 147595, 15565, 14404 }, files = { [118355] = true, [878772] = true, [950080] = true },
		distance = 2.58, height = 0.89, icon = "Interface\\Icons\\Achievement_Character_Dwarf_Male" },
	jumpAnimation = 38,
	-- Seconds one display may take to load before the next one is tried.
	loadWait = 4,
}
M.MushroomAppearance = Appearance

local Read = E.PlainCall or function(method, ...)
	if type(method) ~= "function" then return nil end
	local ok, value = pcall(method, ...)
	if ok and not (issecretvalue and issecretvalue(value)) then return value end
end

---------------------------------------------------------------------------
-- Two ways to draw the hero. A model scene gives the board its own camera
-- and light; a character model frame is the fallback when the scene draws
-- none of the displays. Both turn with the same yaw: +pi/2 faces the right
-- of the screen.
---------------------------------------------------------------------------
local Scene = {}
Scene.__index = Scene

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

function Scene.New(parent, style)
	local scene = CreateFrame("ModelScene", nil, parent)
	scene:SetAllPoints(parent)
	scene:SetAlpha(0)
	scene:EnableMouse(false)
	ConfigureCamera(scene, style)
	local actor = scene:CreateActor(nil, "ModelSceneActorTemplate")
	if not actor then
		scene:Hide()
		return nil
	end
	actor:Show()
	return setmetatable({ frame = scene, actor = actor }, Scene)
end

-- false when the client refuses the display; true or nothing otherwise.
function Scene:Load(display)
	Read(self.actor.ClearModel, self.actor)
	-- The display alone: never the player's own customizations, which a
	-- gnome or dwarf may lack and which then draw untextured.
	return Read(self.actor.SetModelByCreatureDisplayID, self.actor, display, false)
end

function Scene:Loaded()
	return Read(self.actor.IsLoaded, self.actor) == true
end

function Scene:ModelFile()
	return Read(self.actor.GetModelFileID, self.actor)
end

function Scene:Face(yaw)
	Read(self.actor.SetYaw, self.actor, yaw)
end

function Scene:Animate(animation)
	Read(self.actor.SetAnimation, self.actor, animation)
end

-- The pause stays on this scene; it never pauses other models.
function Scene:Pause(paused)
	Read(self.frame.SetPaused, self.frame, paused, false)
end

local Figure = {}
Figure.__index = Figure

function Figure.New(parent)
	local model = CreateFrame("PlayerModel", nil, parent)
	model:SetAllPoints(parent)
	model:SetAlpha(0)
	model:EnableMouse(false)
	local figure = setmetatable({ frame = model }, Figure)
	model:SetScript("OnModelLoaded", function() figure.loaded = true end)
	return figure
end

function Figure:Load(display)
	self.loaded = false
	Read(self.frame.ClearModel, self.frame)
	Read(self.frame.SetPortraitZoom, self.frame, 0)
	return Read(self.frame.SetDisplayInfo, self.frame, display)
end

function Figure:Loaded()
	if self.loaded then return true end
	local model = self:ModelFile()
	return type(model) == "number" and model > 0
end

function Figure:ModelFile()
	return Read(self.frame.GetModelFileID, self.frame)
end

function Figure:Face(yaw)
	Read(self.frame.SetFacing, self.frame, yaw)
end

function Figure:Animate(animation)
	Read(self.frame.SetAnimation, self.frame, animation)
end

function Figure:Pause(paused)
	Read(self.frame.SetPaused, self.frame, paused)
end

local VIEWS = { Scene, Figure }

---------------------------------------------------------------------------
-- The hero
---------------------------------------------------------------------------
local Hero = {}
Hero.__index = Hero

-- Builds the next view (scene first, then the model frame) and starts its
-- first display. False when no view is left.
function Hero:NextView(now)
	if self.view then
		self.view.frame:Hide()
		self.view = nil
	end
	while self.viewIndex < #VIEWS do
		self.viewIndex = self.viewIndex + 1
		local ok, view = pcall(VIEWS[self.viewIndex].New, self.frame, self.style)
		if ok and view then
			self.view, self.displayIndex = view, 0
			if self:NextDisplay(now) then return true end
			view.frame:Hide()
			self.view = nil
		end
	end
	return false
end

-- Starts the next display on the current view. False when none is left.
function Hero:NextDisplay(now)
	local displays = self.style.displays
	while self.displayIndex < #displays do
		self.displayIndex = self.displayIndex + 1
		local display = displays[self.displayIndex]
		local ok, result = pcall(self.view.Load, self.view, display)
		if ok and result ~= false then
			self.deadline = now + Appearance.loadWait
			return true
		end
		self:Note(display, "refused")
	end
	return false
end

-- What each display did, for the error log when none draws.
function Hero:Note(display, outcome)
	self.trail = self.trail or {}
	self.trail[#self.trail + 1] = ("%s %d %s"):format(self.viewIndex == 1 and "scene" or "frame", display, outcome)
end

-- Moves on to the next display, then the next view; the portrait stays
-- when nothing is left.
function Hero:Skip(now)
	if self:NextDisplay(now) or self:NextView(now) then return end
	self.unavailable = true
	if E.errors and E.errors.Add then
		E.errors:Add("warning", ("EldoUI Flight Games: Gnome Dash could not load a hero model (%s); the portrait is shown instead."):format(
			table.concat(self.trail or {}, ", ")))
	end
end

-- A display counts as drawn once loaded with one of the race's model
-- files, or with a model file the client does not tell.
function Hero:FinishLoading(now)
	local view = self.view
	local display = self.style.displays[self.displayIndex]
	if not view:Loaded() then
		if now >= self.deadline then
			self:Note(display, "not loaded")
			self:Skip(now)
		end
		return
	end
	local model = view:ModelFile()
	if type(model) == "number" and model > 0 and not self.style.files[model] then
		self:Note(display, "model " .. model)
		self:Skip(now)
		return
	end
	self.ready = true
	view:Face(self.facing or 0)
	view:Animate(self.animation or Board.ANIM.stand)
end

function Hero:ApplyPause()
	if not self.ready then return end
	local paused = not (self.running and self.showModel and self.frame:IsVisible())
	if self.paused == paused then return end
	self.paused = paused
	self.view:Pause(paused)
end

function Hero:Refresh()
	local want = self.visible and self.frame:IsVisible() and M.db and M.db.models
	if want and not self.started then
		self.started = true
		self.viewIndex = 0
		if not self:NextView(GetTime()) then self.unavailable = true end
	end
	if want and self.view and not self.ready and not self.unavailable then
		local now = GetTime()
		if not self.nextPoll or now >= self.nextPoll then
			self.nextPoll = now + 0.15
			self:FinishLoading(now)
		end
	end
	local showModel = want and self.ready and not self.unavailable and true or false
	if self.view then
		self.view.frame:SetShown(want and not self.unavailable and true or false)
		if self.showModel ~= showModel then self.view.frame:SetAlpha(showModel and 1 or 0) end
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
	if self.ready then self.view:Face(facing) end
end

function Hero:Animate(animation)
	if self.animation == animation then return end
	self.animation = animation
	if self.ready then self.view:Animate(animation) end
end

function Hero:SetRunning(running)
	self.running = running
	self:ApplyPause()
end
