-- Rare Alerts: the notice for a sighting. One sound (repeated as
-- set, another sound for a rare with a collectable drop, one play of the
-- treasure sound for a treasure or event), a taskbar flash
-- while the game is in the background, an optional line in the player's
-- own chat frame, an optional gamepad pulse, and the hand-off to Fanfare.
--
-- One rare = one sound: when Fanfare is on and one of its triggers on
-- "Rare spotted" has a sound, that trigger plays and Rare Alerts stays
-- quiet. Nothing is ever sent to other players.
local _, E = ...
local L = E.L
local M = E.RareScanner

local REPEAT_GAP = 1.2 -- seconds between repeats of the sound

local function Fanfare()
	local module = E.modules.Fanfare
	if module and module.active then return module end
end

-- Does Fanfare play the sound for this rare?
function M:FanfarePlaysSound()
	return E.FanfareOwns and E:FanfareOwns("rare") or false
end

function M:PlaySound(info)
	local db = self.db
	if self.IsMarker(info) then
		-- Treasures and events: their own sound, played once.
		if not db.treasureSound then return 0 end
		E:PlayMedia(db.treasureID, E:SoundChannel(db.channel), { fallback = "eldo:Glass", preview = info.test })
		return 1
	end
	if not db.sound then return 0 end
	if not info.test and self:FanfarePlaysSound() then return 0 end
	local id, times = db.soundID, db.soundRepeat
	if info.notable and db.notableSound then id, times = db.notableID, db.notableRepeat end
	times = math.max(1, math.min(5, math.floor(tonumber(times) or 1)))
	local channel = E:SoundChannel(db.channel)
	E:PlayMedia(id, channel, { fallback = "eldo:EldoChime", preview = info.test })
	for i = 2, times do
		C_Timer.After(REPEAT_GAP * (i - 1), function()
			if M.active then E:PlayMedia(id, channel, { fallback = "eldo:EldoChime", preview = info.test }) end
		end)
	end
	return times
end

-- Gamepad pulse: only while the player already has a gamepad on; EldoUI
-- never changes the gamepad settings. A short "Low" pulse, a longer "High"
-- one for a rare with a collectable drop. A type name the client does not
-- know fails inside the pcall and the alert goes on.
local PULSE = { Low = 0.25, High = 0.6 }
function M:Pulse(info)
	local db = self.db
	if not db.vibrate then return false end
	local pad = rawget(_G, "C_GamePad")
	if not (pad and pad.SetVibration) then return false end
	if pad.IsEnabled and M.Read(pad.IsEnabled) ~= true then return false end
	local device = pad.GetActiveDeviceID and M.Read(pad.GetActiveDeviceID)
	if type(device) == "number" and device < 0 then return false end
	local kind = info.notable and "High" or "Low"
	local strength = math.max(0.1, math.min(1, tonumber(db.vibrateStrength) or 0.6))
	if not pcall(pad.SetVibration, kind, strength) then return false end
	if pad.StopVibration then
		C_Timer.After(PULSE[kind], function() pcall(pad.StopVibration) end)
	end
	return kind
end

-- "45.2, 33.8" from 0-1 map coordinates, or nil.
function M.Coords(x, y)
	if type(x) ~= "number" or type(y) ~= "number" then return nil end
	return ("%.1f, %.1f"):format(x * 100, y * 100)
end

-- The chat line: "EldoUI: Rare <name> (<zone> 45.2, 33.8) [Map]".
function M:ChatLine(info)
	local place = info.zone or ""
	local coords = self.Coords(info.x, info.y)
	if coords then place = place ~= "" and (place .. " " .. coords) or coords end
	local label = info.kind == "treasure" and L["Treasure %s"] or info.kind == "event" and L["Event %s"] or L["Rare %s"]
	local text = label:format(E:Highlight(info.name))
	if place ~= "" then text = text .. " (" .. place .. ")" end
	if coords and type(info.uiMapID) == "number" then
		text = text .. (" |cffffffff|Hworldmap:%d:%d:%d|h[%s]|h|r"):format(info.uiMapID,
			math.floor(info.x * 10000 + 0.5), math.floor(info.y * 10000 + 0.5), L["Map"])
	end
	return E.color .. "EldoUI|r: " .. text
end

function M:Notify(info)
	local db = self.db
	-- A quiet sighting (quiet zone or kind) shows its card and nothing else.
	if info.quiet then return end
	self:PlaySound(info)
	self:Pulse(info)
	if db.flashTaskbar and type(FlashClientIcon) == "function" then pcall(FlashClientIcon) end
	if db.chat and DEFAULT_CHAT_FRAME then
		-- Your own chat frame only; nothing is sent.
		DEFAULT_CHAT_FRAME:AddMessage(self:ChatLine(info))
	end
	if not info.test and not self.IsMarker(info) then
		local fanfare = Fanfare()
		if fanfare and fanfare.Emit then
			local ok, err = pcall(fanfare.Emit, fanfare, "rare", { name = info.name, zone = info.zone or "" })
			if not ok then geterrorhandler()(err) end
		end
	end
end
