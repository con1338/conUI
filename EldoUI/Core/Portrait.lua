-- EldoUI portraits: one portrait element for the unit frames and the
-- party frames. A 2D picture, a 3D model or the class icon, in a holder
-- frame the caller places (beside the bars, in its own box, over the
-- health bar).
--
--   E.Portrait:Attach(owner, holder)        the 2D texture (and later the model) inside holder
--   E.Portrait:Update(owner, unit, opts[, force])
--       opts: style "2D" | "3D" | "CLASS", framing "FACE" | "BUST" | "BODY",
--             distance, rotation (degrees), height (3D model offset),
--             desaturate, deadGrey (gray while dead or offline), coords,
--             test (show the player's own portrait)
--       force: reload the 3D model (UNIT_MODEL_CHANGED, UNIT_PORTRAIT_UPDATE,
--             a new unit in the frame, a setting change, the frame shown)
--   E.Portrait:CheckVisibility(owner, unit, opts)  cheap check for polls and
--             UNIT_FLAGS / UNIT_PHASE / UNIT_CONNECTION: 3D <-> 2D when the
--             unit comes into or leaves view, no reload otherwise
--   E.Portrait:Release(owner)              hide and drop the model (frame off)
--
-- Rules (Forever applies the Midnight restrictions):
--   * The model is only reloaded when something forces it or the unit's GUID
--     changed. A GUID the game keeps secret is never stored or compared:
--     then only the forced triggers reload, so a poll never does.
--   * 3D only while UnitIsVisible says the unit is in view and SetUnit
--     reports success (it needs a declassified unit identity); otherwise the
--     2D picture. Offline units always get the 2D picture.
--   * Dead, ghost and offline are plain flags (no secret flags in the API
--     docs); they are still read through pcall and an issecretvalue test, so
--     a future secret build simply shows no gray.
--   * The holder and model are EldoUI children of the unit button, never
--     the secure button itself, so all of this may run in combat.
-- Written from scratch for EldoUI.
local _, E = ...

local P = {}
E.Portrait = P

local issecret = issecretvalue or function() return false end
local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local COORDS = { 0.15, 0.85, 0.15, 0.85 }

-- Camera framing: how much of the model the portrait shows.
P.FRAMING = { FACE = 1, BUST = 0.6, BODY = 0 }
P.stats = { reloads = 0 }

local Plain = E.PlainCall
P.Plain = Plain

-- Dead or ghost, and offline (players only), as plain flags.
function P.State(unit)
	if type(unit) ~= "string" then return false, false end
	local dead = Plain(UnitIsDeadOrGhost, unit) and true or false
	local offline = Plain(UnitIsPlayer, unit) and Plain(UnitIsConnected, unit) == false or false
	return dead, offline
end

function P:Attach(owner, holder)
	owner.portraitHolder = holder
	if not owner.portrait then
		owner.portrait = holder:CreateTexture(nil, "ARTWORK")
		owner.portrait:SetAllPoints()
		owner.portrait:SetTexCoord(unpack(COORDS))
	end
	return owner.portrait
end

local function Model(owner)
	local model = owner.model
	if not model then
		model = CreateFrame("PlayerModel", nil, owner.portraitHolder)
		-- Where the picture is: the caller placed it (and the unit graphics
		-- fit the model into their opening, Core/UnitGraphics.lua).
		model:SetAllPoints(owner.portrait)
		-- A click on the model belongs to the unit button under it.
		model:EnableMouse(false)
		-- The client drops a hidden model; Update reloads it when it shows again.
		if model.SetKeepModelOnHide then pcall(model.SetKeepModelOnHide, model, false) end
		model:Hide()
		owner.model = model
	end
	return model
end
P.Model = Model

-- The GUID as a plain string, or nil (secret, missing).
local function PlainGUID(unit)
	local ok, guid = pcall(UnitGUID, unit)
	if not ok or issecret(guid) or type(guid) ~= "string" then return nil end
	return guid
end

local function Show2D(owner, unit, opts, grey)
	local texture = owner.portrait
	if owner.model then owner.model:Hide() end
	owner.modelLive = nil
	texture:Show()
	texture:SetDesaturated(grey and true or false)
	if opts.style == "CLASS" and E:UnitShowsClassColor(unit) then
		local ok, _, class = pcall(UnitClass, unit)
		local coords = ok and not issecret(class) and type(class) == "string" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
		if coords then
			texture:SetTexture(CLASS_CIRCLES)
			texture:SetTexCoord(unpack(coords))
			owner.portraitMode = "CLASS"
			return "CLASS"
		end
	end
	texture:SetTexCoord(unpack(opts.coords or COORDS))
	if not pcall(SetPortraitTexture, texture, unit) then texture:SetTexture(nil) end
	owner.portraitMode = "2D"
	return "2D"
end

-- owner: inside a round opening the unit graphics frame the face a
-- little wider, so the head sits in the opening (Core/UnitGraphics.lua).
local function Camera(model, opts, grey, owner)
	local graphics = E.UnitGraphics
	local scale = graphics and graphics.ModelFraming and graphics:ModelFraming(owner) or 1
	pcall(model.SetPortraitZoom, model, (P.FRAMING[opts.framing or "FACE"] or 1) * scale)
	pcall(model.SetCamDistanceScale, model, tonumber(opts.distance) or 1)
	pcall(model.SetRotation, model, math.rad(tonumber(opts.rotation) or 0))
	if model.SetPosition then pcall(model.SetPosition, model, 0, 0, tonumber(opts.height) or 0) end
	pcall(model.SetDesaturation, model, grey and 1 or 0)
end

-- One decision: which picture this unit gets now, and whether the model
-- must load again. Returns "3D", "2D", "CLASS" or nil (no holder).
local Decide
function P:Update(owner, unit, opts, force)
	local before = owner and owner.portraitMode
	local mode = Decide(self, owner, unit, opts, force)
	-- The unit graphics shape their ornament round the picture shown (a
	-- mask round a picture, a border round a model): a switch between
	-- picture and model repaints them.
	if owner and mode ~= before and E.UnitGraphics and E.UnitGraphics.PictureChanged then
		E.UnitGraphics:PictureChanged(owner)
	end
	return mode
end

-- The model's camera again (the unit graphics moved it into or out of an
-- opening); nothing reloads.
function P.Reframe(owner)
	local last = owner and owner.portraitCamera
	if not (last and owner.model and owner.portraitMode == "3D") then return end
	Camera(owner.model, last.opts, last.grey, owner)
end

function Decide(self, owner, unit, opts, force)
	if not (owner and owner.portrait) then return nil end
	opts = opts or {}
	if opts.test then unit = "player" end
	if type(unit) ~= "string" then
		self:Release(owner)
		return nil
	end
	local dead, offline = P.State(unit)
	local grey = opts.desaturate or (opts.deadGrey and (dead or offline))
	if opts.style ~= "3D" or offline or not Plain(UnitIsVisible, unit) then
		return Show2D(owner, unit, opts, grey)
	end
	local model = Model(owner)
	local guid = PlainGUID(unit)
	local reload = force or not owner.modelLive or owner.modelUnit ~= unit or not model:IsShown()
	-- A plain GUID is compared with the last plain one; a secret one never is.
	if guid and owner.modelGUID ~= guid then reload = true end
	model:Show()
	if reload then
		P.stats.reloads = P.stats.reloads + 1
		pcall(model.ClearModel, model)
		local ok, success = pcall(model.SetUnit, model, unit)
		-- SetUnit answers false when the client won't show this unit (an
		-- identity it keeps hidden): the 2D picture then.
		if not ok or success == false then
			owner.modelGUID, owner.modelUnit = nil, nil
			return Show2D(owner, unit, opts, grey)
		end
		owner.modelGUID, owner.modelUnit, owner.modelLive = guid, unit, true
	end
	owner.portrait:Hide()
	owner.portraitCamera = { opts = opts, grey = grey }
	Camera(model, opts, grey, owner)
	owner.portraitMode = "3D"
	return "3D"
end

-- Polls and visibility events: only switch between 3D and 2D.
function P:CheckVisibility(owner, unit, opts)
	if not (owner and owner.portrait) or not opts or opts.style ~= "3D" then return owner and owner.portraitMode end
	local visible = Plain(UnitIsVisible, unit) and true or false
	local live = owner.portraitMode == "3D"
	if visible ~= live then return self:Update(owner, unit, opts, visible) end
	if live then return self:Update(owner, unit, opts, false) end
	return owner.portraitMode
end

function P:Release(owner)
	if not owner then return end
	if owner.model then
		pcall(owner.model.ClearModel, owner.model)
		owner.model:Hide()
	end
	owner.modelLive, owner.modelGUID, owner.modelUnit, owner.portraitMode = nil, nil, nil, nil
	owner.portraitCamera = nil
end
