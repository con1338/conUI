-- Combat HUD: Blizzard's loss-of-control alert.
-- Skin (square icon, theme font, optional background art), mover and
-- scale for LossOfControlFrame. The text, icon and timer stay Blizzard's.
-- Hide uses Blizzard's own option (CVar lossOfControl).
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local K = E.CombatKit
local M = E.CombatHUD

local ID = "loss-of-control"
local GROUP = "loc"
local MOVER = "EldoUI_LossOfControl"

local F = { key = "loc", id = ID, title = "Loss of control",
	install = { skin = true, move = true }, reload = { skin = true, move = true } }
F.defaults = {
	scale = 100,
	hideArt = true,
	font = "THEME", nameSize = 0, timeSize = 0,
}

local function Allowed(action) return M.active and E:BlizzardAllowed(ID, action) end

local function Skin(db)
	local frame = LossOfControlFrame
	if db.hideArt then
		K.Alpha0(GROUP .. "art", frame.blackBg, frame.RedLineTop, frame.RedLineBottom)
	else
		K.Undo(GROUP .. "art")
	end
	K.TexCoord(GROUP, frame.Icon)
	K.Backdrop(GROUP, frame, frame.Icon, E.pixel)
	local font = K.FontPath(db.font)
	-- 0 keeps Blizzard's size.
	K.Font(GROUP, frame.AbilityName, db.nameSize > 0 and db.nameSize or nil, nil, font)
	if frame.TimeLeft then
		K.Font(GROUP, frame.TimeLeft.NumberText, db.timeSize > 0 and db.timeSize or nil, nil, font)
		K.Font(GROUP, frame.TimeLeft.SecondsText, db.timeSize > 0 and db.timeSize or nil, nil, font)
	end
end

function F:Setup()
	self.holder = K.Holder(M, MOVER, L["Loss of Control"], { "CENTER", "UIParent", "CENTER", 0, 120 }, 256, 58, { sample = { kind = "toast" } })
end

function F:Apply(db)
	local frame = LossOfControlFrame
	if not frame then return end
	if E:BlizzardHidden(ID) then
		if C_CVar.GetCVar("lossOfControl") then E:SetCVar("lossOfControl", "0", ID) end
	else
		E:ReleaseCVar("lossOfControl", ID)
	end
	if Allowed("skin") then
		Skin(db)
	else
		K.Undo(GROUP)
		K.Undo(GROUP .. "art")
	end
	if Allowed("move") then
		local holder = self.holder
		holder:SetSize(256 * db.scale / 100, 58 * db.scale / 100)
		K.Pin(frame, {
			anchor = function() return "CENTER", holder, "CENTER", 0, 0 end,
			scale = function() return M.db.loc.scale / 100 end,
			active = function() return Allowed("move") end,
		})
	else
		K.Unpin(frame)
	end
end

function F:Restore()
	if LossOfControlFrame then K.Unpin(LossOfControlFrame) end
	K.Undo(GROUP)
	K.Undo(GROUP .. "art")
end

local NotSkin, NotMove = M.Off(ID, "skin"), M.Off(ID, "move")

F.switches = {
	skin = L["Square icon with a 1 px border and the theme font."],
	move = L["Place the alert on its own mover (EldoUI_LossOfControl) and scale it here."],
	hide = L["Switch Blizzard's loss-of-control alert off (its own Interface option)."],
}
F.options = {
	{ type = "header", label = "Position", hidden = NotMove },
	{ type = "range", key = "loc.scale", label = "Scale", unit = "%", min = 50, max = 200, step = 5, hidden = NotMove,
		desc = "Size of the alert in percent (replaces Blizzard's Edit Mode size while Move is on)." },
	{ type = "header", label = "Look", hidden = NotSkin },
	{ type = "toggle", key = "loc.hideArt", label = "Hide background art", hidden = NotSkin,
		desc = "Removes the dark shadow and the red lines, leaving icon, name and time." },
	{ type = "media", mediaKind = "font", default = "THEME", defaultLabel = "Theme font", key = "loc.font", label = "Font", hidden = NotSkin,
		desc = "Font of the effect name and the time." },
	{ type = "range", key = "loc.nameSize", label = "Name size", min = 0, max = 32, step = 1, hidden = NotSkin,
		zeroText = "Game", desc = "Font size of the effect name. Game keeps Blizzard's size." },
	{ type = "range", key = "loc.timeSize", label = "Time size", min = 0, max = 32, step = 1, hidden = NotSkin,
		zeroText = "Game", desc = "Font size of the time left. Game keeps Blizzard's size." },
}

M:AddFeature(F)
