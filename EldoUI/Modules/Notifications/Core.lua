-- EldoUI Notifications: everything that pops up in the middle of the screen.
-- One module owns seven Blizzard elements, each behind its
-- own "Let EldoUI change this" switch on the Blizzard UI page:
--
--   alert-toasts          achievements, loot won, collections, level-up and
--                         boss banners; skin, move into one lane, hide per
--                         type, or EldoUI's own alert lane
--   talking-head          skin, hide, or move into the alert lane
--   raid-warning          font, move and scale; raid warnings can be hidden,
--                         boss emotes never
--   ui-errors             red error text: font, move, filter by category
--   zone-text             zone and subzone text: font, move, scale, hide
--   ready-check-popups    ready check, role poll and battleground pop-ups:
--                         skin, move, sound and flash, countdowns
--   tutorials-cinematics  tutorials and help tips off, Esc skips cutscenes
--
-- Plus two EldoUI extras that change no Blizzard frame, each off by default:
-- battleground messages as big text (Messages.lua) and pings
-- (Pings.lua: ping feed, pingable icons, ping keys).
--
-- With an element's master switch off this module never hooks, skins, moves
-- or hides it: every hook checks the switch each time it runs, and every
-- change is undone when the switch goes off.
--
-- This file holds the module, the shared helpers and the element plumbing.
-- The elements live in Alerts.lua, Messages.lua, Popups.lua and
-- Cinematics.lua; Options.lua holds the options page and the styles.
--
-- Written from scratch for EldoUI; no code, strings or data from other addons.
local _, E = ...
local L = E.L

local M = E:NewModule("Notifications", {
	title = "Alerts and Banners",
	aliases = { "Messages", "Alerts and Messages", "Notifications" }, -- earlier titles, for search and /eui
	category = "Interface",
	desc = "Toasts, banners, talking head, raid warnings, red error text, zone text, ready checks and cutscenes.",
	defaults = {
		alerts = {
			scale = 1,
			bannerScale = 1,
			growth = "DOWN",        -- the lane grows DOWN from its mover, or UP
			spacing = 4,
			hideGlow = true,        -- skin: no glow and shine flash
			-- Used while the element's Hide switch is on: which types go.
			hide = {
				achievement = true, loot = true, money = true, recipe = true, collection = true,
				instance = true, other = true, levelup = true, events = true, bossBanner = true, bnet = true,
			},
			-- Game toast settings: "game" leaves them alone.
			cvars = {
				enableLootToasts = "game", enableCollectionToasts = "game", enableLearnedRecipeToasts = "game",
				showToastOnline = "game", showToastOffline = "game", showToastBroadcast = "game",
				showToastFriendRequest = "game",
			},
			-- EldoUI's own alert lane (the element's Replace switch).
			lane = {
				achievement = true, levelup = true, levelupSpells = true, quest = true, loot = false, recipe = true,
				collection = true, boss = true,
				max = 4, duration = 5, width = 300, iconSize = 36, fontSize = 13,
				sound = false, soundID = "kit:UI_EPICLOOT_TOAST", holdInCombat = false,
			},
		},
		talkingHead = { anchor = "lane", scale = 1, hideMode = "all", textSize = 0 },
		raidWarning = { scale = 1 },
		errors = {
			mode = "filter",        -- filter, combat, always
			categories = { power = true, cooldown = true, range = false, target = false, facing = false, moving = false, busy = true },
			hideStatus = false,
			fontSize = 0,
			duration = 0,
			scale = 1,
		},
		zoneText = { scale = 1, hidePart = "both", zoneSize = 0, subZoneSize = 0, pvpSize = 0 },
		popups = { scale = 1, masterSound = true, soundID = "kit:READY_CHECK", flash = true, timers = true, summary = true, pingScale = 1, queueTimer = true },
		cinematics = { escSkip = true, skipSeen = false, tutorials = true, helpTips = true },
		-- Battleground messages as big text under the raid warnings.
		bgMessages = { enabled = false, fontSize = 22, duration = 5 },
		-- A profession at its rank cap (Professions.lua).
		professionCap = { enabled = true, early = false },
		-- Pings: EldoUI's own extras, each off until ticked.
		pings = {
			feed = false,
			content = { world = true, dungeon = true, raid = true, battleground = true, arena = true },
			rows = 6, fade = 30, fontSize = 12, width = 280, backdrop = true,
			sound = false, soundID = "kit:MAP_PING",
			pingableIcons = false,
			keys = false, keySpell1 = "", keySpell2 = "", keySpell3 = "", keySpell4 = "",
		},
	},
})

local U = {}
M.util = U
M.elements = {}       -- [id] = { apply = fn(state), restore = fn() }
M.elementOrder = {}
local touched = {}    -- [id] = true while EldoUI has changed the element

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
function U.Secret(value)
	return E:IsSecret(value)
end

-- The value, or nil when it is secret (never compare or join a secret).
function U.Safe(value)
	if U.Secret(value) then return nil end
	return value
end

function U.Allowed(id, action)
	return M.active and E:BlizzardAllowed(id, action)
end

function U.Accent()
	local color = E.media.accentColor
	return color[1], color[2], color[3]
end

-- Parked Blizzard frames sit under the core's hidden parent; the core's
-- SetParent post-hook keeps them there when Blizzard re-parents them, and
-- a protected frame waits for combat to end (E:HideBlizzardFrame).
U.hider = E.BlizzardKeep.hider
local parked = {}

function U.Park(frame, hide)
	if not frame then return end
	if hide and not parked[frame] then
		parked[frame] = true
		E:HideBlizzardFrame(frame, { check = function() return parked[frame] == true end })
	elseif not hide and parked[frame] then
		parked[frame] = nil
		E:UnhideBlizzardFrame(frame)
	end
end

function U.IsParked(frame)
	return parked[frame] ~= nil
end

---------------------------------------------------------------------------
-- Pins: keep a Blizzard frame on an EldoUI holder even when Blizzard
-- re-anchors it (E:PinBlizzardFrame, Core/Blizzard.lua). Edit Mode frames
-- override SetPoint/ClearAllPoints/SetScale in Lua; the core moves them
-- with the *Base originals, without telling Edit Mode, and re-applies after
-- every Edit Mode layout pass.
---------------------------------------------------------------------------
local pins = {}
local SocialPin, SocialScale

-- check() (optional) is asked on every re-anchor: false lets Blizzard win,
-- so a hook never moves a frame whose switch went off.
-- place() (optional) returns other points while they apply, nil for the
-- holder spot.
function U.Pin(frame, holder, point, relPoint, x, y, check, place)
	if not frame or not holder then return end
	local pin = pins[frame] or {}
	pins[frame] = pin
	pin.holder, pin.point, pin.relPoint, pin.x, pin.y = holder, point or "CENTER", relPoint or "CENTER", x or 0, y or 0
	pin.check = check
	pin.place = place
	pin.active = true
	local spec = {
		holder = holder,
		wants = function() return pin.active and (not pin.check or pin.check()) and true or false end,
		anchor = function()
			-- pin.place (optional) picks another spot for the moment.
			if pin.place then
				local p1, rel, p2, px, py = pin.place()
				if p1 then return p1, rel, p2, px, py end
			end
			return pin.point, pin.holder, pin.relPoint, pin.x, pin.y
		end,
	}
	pin.spec = spec
	local social
	if SocialPin then
		local ok, row = pcall(SocialPin, frame, pin, false)
		if ok then social = row end
	end
	E:PinBlizzardFrame(frame, spec)
	if social then pcall(SocialPin, frame, pin, true, social) end
end

function U.Unpin(frame)
	local pin = frame and pins[frame]
	if not pin or not pin.active then return end
	pin.active = false
	E:UnpinBlizzardFrame(frame)
end

function U.IsPinned(frame)
	return pins[frame] and pins[frame].active
end

---------------------------------------------------------------------------
-- Scale (Edit Mode frames: SetScaleBase, so Edit Mode keeps its offsets)
---------------------------------------------------------------------------
local scales = {}

-- A forbidden frame (the client can lock some Blizzard frames) errors on
-- every method call, IsProtected included, so it is left alone.
local function Locked(frame)
	return E.FrameCheck(frame, "IsForbidden") or (E.FrameCheck(frame, "IsProtected") and InCombatLockdown())
end

function U.SetScale(frame, scale)
	if not frame or not scale then return end
	if Locked(frame) then return end
	if scales[frame] == nil then scales[frame] = frame:GetScale() end
	local social
	if SocialScale then
		local ok, row = pcall(SocialScale, frame, false)
		if ok then social = row end
	end
	if frame.SetScaleBase then frame:SetScaleBase(scale) else frame:SetScale(scale) end
	if social then pcall(SocialScale, frame, true, social) end
end

function U.RestoreScale(frame)
	if not frame or scales[frame] == nil then return end
	if Locked(frame) then return end
	local scale = scales[frame]
	scales[frame] = nil
	if frame.SetScaleBase then frame:SetScaleBase(scale) else frame:SetScale(scale) end
end

---------------------------------------------------------------------------
-- Fonts: EldoUI's font and outline on a Blizzard font string; the original
-- comes back on restore. size 0/nil keeps the string's own size.
---------------------------------------------------------------------------
local fonts = {}

function U.SkinFont(fontString, size, outline)
	if not fontString or not fontString.GetFont then return end
	if not fonts[fontString] then
		local font, height, flags = fontString:GetFont()
		local sx, sy = fontString:GetShadowOffset()
		fonts[fontString] = { font, height, flags, sx, sy }
	end
	local original = fonts[fontString]
	local _, current = fontString:GetFont()
	local height = (size and size > 0) and size or current or original[2] or 14
	E:SetFont(fontString, height, outline or E.db.general.fontOutline or "OUTLINE")
end

function U.RestoreFont(fontString)
	local original = fontString and fonts[fontString]
	if not original then return end
	fonts[fontString] = nil
	if original[1] then fontString:SetFont(original[1], original[2], original[3] or "") end
	fontString:SetShadowOffset(original[4] or 0, original[5] or 0)
end

function U.FontSkinned(fontString)
	return fonts[fontString] ~= nil
end

---------------------------------------------------------------------------
-- Alpha and mouse on Blizzard art (restorable)
---------------------------------------------------------------------------
local alphas = {}

function U.SetAlpha(region, alpha)
	if not region then return end
	if alphas[region] == nil then alphas[region] = region:GetAlpha() end
	region:SetAlpha(alpha)
end

function U.RestoreAlpha(region)
	if not region or alphas[region] == nil then return end
	region:SetAlpha(alphas[region])
	alphas[region] = nil
end

---------------------------------------------------------------------------
-- CVars: through E:SetCVar so "Blizzard default" restores the player's own
-- value. One CVar back to the player's value (Core only restores by owner).
---------------------------------------------------------------------------
function U.SetCVar(name, value, id)
	if not (C_CVar and C_CVar.GetCVar) or C_CVar.GetCVar(name) == nil then return end
	E:SetCVar(name, value, id)
end

function U.RestoreCVar(name, owner)
	E:RestoreCVar(name, owner)
end

---------------------------------------------------------------------------
-- Holders: EldoUI frames with a mover that Blizzard frames are pinned to.
---------------------------------------------------------------------------
U.HOLDERS = {
	AlertLane = { name = "EldoUI_AlertLane", sample = { kind = "toast" }, title = "Alert Lane", width = 300, height = 52, point = { "TOP", "UIParent", "TOP", 0, -60 } },
	Banners = { name = "EldoUI_Banners", sample = { kind = "toast" }, title = "Banners and Level-up", width = 512, height = 120, point = { "TOP", "UIParent", "TOP", 0, -130 } },
	TalkingHead = { name = "EldoUI_TalkingHead", title = "Talking Head", width = 570, height = 155, point = { "BOTTOM", "UIParent", "BOTTOM", 0, 260 } },
	RaidWarning = { name = "EldoUI_RaidWarning", sample = { kind = "text" }, title = "Raid Warnings", width = 800, height = 80, point = { "TOP", "UIParent", "TOP", 0, -340 } },
	Errors = { name = "EldoUI_Errors", sample = { kind = "text" }, title = "Red Error Text", width = 512, height = 60, point = { "TOP", "UIParent", "TOP", 0, -200 } },
	ZoneText = { name = "EldoUI_ZoneText", sample = { kind = "text" }, title = "Zone Text", width = 512, height = 100, point = { "TOP", "UIParent", "TOP", 0, -110 } },
	ReadyCheck = { name = "EldoUI_ReadyCheck", title = "Ready Check", width = 323, height = 112, point = { "TOP", "UIParent", "TOP", 0, -430 } },
	-- Battle.net toasts (friend online, broadcasts), which Blizzard hangs on
	-- the chat window, and the GM ticket status box (top right): with Move
	-- both sit next to EldoUI's chat (right of its bottom edge), so every
	-- layout places them through its chat point. A toast that pops while a
	-- ticket is open goes on top of the ticket box (Alerts.lua).
	SocialToasts = { name = "EldoUI_SocialToasts", sample = { kind = "toast" }, title = "Battle.net Toasts", width = 250, height = 60,
		point = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 16, 340 },
		follows = { "EldoUI_Chat", { "BOTTOMLEFT", "EldoUI_ChatMover", "BOTTOMRIGHT", 8, 0 } } },
}
local holders = {}

function U.Holder(key)
	if holders[key] then return holders[key] end
	local info = U.HOLDERS[key]
	local holder = CreateFrame("Frame", info.name, UIParent)
	holder:SetSize(info.width, info.height)
	holder:SetFrameStrata("LOW")
	local previous = E.currentModule
	E.currentModule = M
	-- Follows another EldoUI mover when that one exists (its module is on).
	local point = info.point
	if info.follows and E.movers and E.movers[info.follows[1]] then point = info.follows[2] end
	E:CreateMover(holder, info.name, info.title, point, { sample = info.sample })
	E.currentModule = previous
	holders[key] = holder
	return holder
end

-- Read-only: where the game's social toasts sit. The pin row is the
-- generation: an older toast's relative anchor is never read through a
-- newer ticket. No message, account, ticket or toast content is read here.
do
	local methods = { "GetParent", "GetRect", "GetEffectiveScale", "IsShown", "IsVisible", "IsForbidden", "GetNumPoints", "GetPoint" }
	local function Number(value)
		return not U.Secret(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
	end
	local function Plain(value)
		return not U.Secret(value) and type(value) == "table" and type(getmetatable(value)) == "nil"
	end
	local function PinStore(value)
		if U.Secret(value) or type(value) ~= "table" then return false end
		local meta = getmetatable(value)
		if not Plain(meta) then return false end
		local mode = rawget(meta, "__mode")
		if U.Secret(mode) or type(mode) ~= "string" or mode ~= "k" then return false end
		for key in pairs(meta) do if U.Secret(key) or key ~= "__mode" then return false end end
		return true
	end
	local function Frame(value)
		return not U.Secret(value) and (type(value) == "table" or type(value) == "userdata")
	end
	local function Same(a, b)
		return not U.Secret(a) and not U.Secret(b) and a == b
	end
	local function Current(row)
		local pin, spec = row.pin, row.spec
		if not Plain(E.db) or not Plain(M.db) or not Plain(M.db.alerts)
			or not Plain(E.modules) or not Plain(E.movers) or not Plain(E.BlizzardKeep)
			or not PinStore(rawget(E.BlizzardKeep, "pins")) then return false end
		if not Same(E.db, row.db) or not Same(M.db, row.settings) or not Same(M.db.alerts, row.alerts)
			or not Same(E.profileName, row.profile) or not Same(E.modules, row.modules)
			or not Same(E.modules and E.modules.Notifications, M) or not Same(E.movers, row.movers)
			or not Same(E.BlizzardKeep, row.keep) or not Same(E.BlizzardKeep.pins, row.store)
			or not Same(M.active, true) or not Same(holders.SocialToasts, row.holder)
			or not Same(E.movers and E.movers[U.HOLDERS.SocialToasts.name], row.mover)
			or not Same(row.mover.frame, row.holder) or not Same(row.mover.module, "Notifications")
			or not Same(rawget(_G, "UIParent"), row.root)
			or not Same(row.root.GetEffectiveScale, row.rootScaleMethod)
			or not Same(rawget(_G, "TicketStatusFrame"), row.ticket)
			or not Same(rawget(_G, "TicketStatusFrameButton"), row.button)
			or not Same(rawget(_G, "BNToastFrame"), row.toast)
			or not Same(pins[row.frame], pin) or not Same(pin.social, row) or not Same(pin.spec, spec)
			or not Same(pin.active, true) or not Same(pin.holder, row.holder)
			or not Same(pin.point, row.point) or not Same(pin.relPoint, row.relPoint)
			or not Same(pin.x, row.x) or not Same(pin.y, row.y)
			or not Same(pin.check, row.check) or not Same(pin.place, row.place)
			or not Plain(spec) then return false end
		local expected = spec
		if row.admitting then expected = row.beforeSpec end
		if not Same(rawget(row.store, row.frame), expected) then return false end
		for key, value in pairs(spec) do
			if U.Secret(key) or type(key) ~= "string" or not Same(value, row.fields[key]) then return false end
		end
		for key, value in pairs(row.fields) do if not Same(spec[key], value) then return false end end
		if Frame(row.toast) and (not Same(row.toast.glow, row.glow) or not Same(row.toast.CloseButton, row.close)) then return false end
		if Same(row.frame, row.toast) and Frame(row.ticket) then
			local ticketPin = pins[row.ticket]
			if not ticketPin or not Same(ticketPin.spec, row.ticketSpec) then return false end
		end
		if row.nativeInput and (not Same(rawget(_G, "TicketStatusTitleText"), row.inputTitle)
			or not Same(rawget(_G, "TicketStatusTime"), row.inputTime)) then return false end
		for _, owner in ipairs(row.owners) do
			if not Same(owner.frame.GetParent, owner.method)
				or (owner.typeMethod and not Same(owner.frame.IsObjectType, owner.typeMethod)) then return false end
		end
		for _, part in ipairs(row.parts) do
			for _, key in ipairs(methods) do if not Same(part.frame[key], part[key]) then return false end end
		end
		return true
	end
	local function Call(row, part, key, ...)
		if not Current(row) then error("social ownership changed") end
		local values = { part[key](part.frame, ...) }
		if not Current(row) then error("social ownership changed") end
		return unpack(values)
	end
	local function Part(row, frame, role, relative)
		if not Frame(frame) then return end
		local part = { frame = frame, role = role, relative = relative }
		for _, key in ipairs(methods) do
			local method = frame[key]
			if U.Secret(method) or type(method) ~= "function" then return end
			part[key] = method
		end
		row.parts[#row.parts + 1] = part

		return part
	end
	SocialPin = function(frame, pin, finished, expected)
		if not Same(pin.holder, holders.SocialToasts) then return end
		if finished then
			local row = pin.social
			if row ~= expected then return end
			row.admitting = false
			if not row.ready or not Current(row) then return end
			-- Only identity/method snapshots precede the ordinary Core call.
			-- Additional getters run after it succeeds, so a one-shot native
			-- getter failure cannot be consumed by optional metadata first.
			local ok, ready = pcall(function()
				for _, owner in ipairs(row.owners) do
					if not Current(row) then return false end
					owner.parent = owner.method(owner.frame)
					if not Current(row) or not Frame(owner.parent) then return false end
				end
				for _, part in ipairs(row.parts) do
					part.parent = Call(row, part, "GetParent")
					if not Frame(part.parent) then return false end
					if part.role ~= "ticket" and part.role ~= "toast" then
						part.points = {}
						local count = Call(row, part, "GetNumPoints")
						if not Number(count) or count < 1 or count > 2 or count % 1 ~= 0 then return false end
						for index = 1, count do
							local point, rel, rp, x, y = Call(row, part, "GetPoint", index)
							-- The native ticket input is bounded by its two text
							-- regions; the direct parent route remains valid too.
							if part.role == "ticket-input" and index == 1 and Frame(row.inputTitle)
								and Frame(row.inputTime) and Same(rel, row.inputTitle) then
								if Same(row.inputTitle, row.inputTime) then return false end
								part.nativeInput, row.nativeInput = true, true
							end
							local expectedRel = part.relative
							if part.nativeInput then
								expectedRel = index == 1 and row.inputTitle or row.inputTime
								if count ~= 2 or not Same(point, index == 1 and "TOPLEFT" or "BOTTOMRIGHT")
									or not Same(rp, point) or not Same(x, index == 1 and -8 or 30)
									or not Same(y, index == 1 and 8 or -8) then return false end
							end
							if U.Secret(point) or type(point) ~= "string" or not Same(rel, expectedRel)
								or U.Secret(rp) or type(rp) ~= "string" or not Number(x) or not Number(y) then return false end
							part.points[index] = { point, rel, rp, x, y }
						end
						if part.nativeInput then
							for _, relative in ipairs({ row.inputTitle, row.inputTime }) do
								local method, typeMethod = relative.GetParent, relative.IsObjectType
								if U.Secret(method) or type(method) ~= "function" or U.Secret(typeMethod)
									or type(typeMethod) ~= "function" then return false end
								local owner = { frame = relative, method = method, typeMethod = typeMethod }
								row.owners[#row.owners + 1] = owner
								if not Current(row) or not Same(typeMethod(relative, "FontString"), true)
									or not Current(row) then return false end
								owner.parent = method(relative)
								if not Current(row) or not Same(owner.parent, row.ticket) then return false end
							end
						end
					end
				end
				return Current(row)
			end)
			row.ready = ok and ready == true
			if row.ready then row.complete = not Same(row.frame, row.ticket) end
			return
		end
		local ticket, toast = rawget(_G, "TicketStatusFrame"), rawget(_G, "BNToastFrame")
		if not Plain(E.db) or not Plain(M.db) or not Plain(M.db.alerts)
			or not Plain(E.modules) or not Plain(E.movers) or not Plain(E.BlizzardKeep)
			or not PinStore(rawget(E.BlizzardKeep, "pins")) then pin.social = false; return end
		local row = { pin = pin, spec = pin.spec, frame = frame, holder = pin.holder, parts = {}, fields = {}, owners = {},
			db = E.db, settings = M.db, alerts = M.db.alerts, profile = E.profileName,
			modules = E.modules, movers = E.movers, keep = E.BlizzardKeep, store = E.BlizzardKeep.pins,
			mover = E.movers and E.movers[U.HOLDERS.SocialToasts.name], root = rawget(_G, "UIParent"),
			ticket = ticket, toast = toast, button = rawget(_G, "TicketStatusFrameButton"),
				inputTitle = rawget(_G, "TicketStatusTitleText"), inputTime = rawget(_G, "TicketStatusTime"),
			point = pin.point, relPoint = pin.relPoint, x = pin.x, y = pin.y, check = pin.check, place = pin.place,
			admitting = true, beforeSpec = rawget(E.BlizzardKeep.pins, frame) }
		pin.social = row
		-- Invalid metadata never changes the ordinary pin operation or its error.
		local ok = pcall(function()
			if not row.mover or not Frame(row.root) or not Plain(row.settings) or not Plain(row.alerts)
				or U.Secret(row.profile) or (type(row.profile) ~= "nil" and type(row.profile) ~= "string") then return end
			row.rootScaleMethod = row.root.GetEffectiveScale
			if U.Secret(row.rootScaleMethod) or type(row.rootScaleMethod) ~= "function" then return end
			for key, value in pairs(pin.spec) do row.fields[key] = value end
			for _, owner in ipairs({ row.holder, row.mover }) do
				local method = owner.GetParent
				if U.Secret(method) or type(method) ~= "function" then return end
				row.owners[#row.owners + 1] = { frame = owner, method = method }
			end
			if type(toast) ~= "nil" then
				if not Frame(toast) then return end
				row.glow, row.close = toast.glow, toast.CloseButton
			end
			if type(ticket) ~= "nil" and not Frame(ticket) then return end
			if Same(frame, ticket) then
				if not Part(row, ticket, "ticket", row.holder) or not Part(row, row.button, "ticket-input", ticket) then return end
			elseif Same(frame, toast) then
				if Frame(ticket) then row.ticketSpec = pins[ticket] and pins[ticket].spec end
				if not Part(row, toast, "toast", row.holder) or not Part(row, row.glow, "toast-glow", toast)
					or not Part(row, row.close, "toast-close", toast) then return end
			else return end
			row.ready = Current(row)
		end)
		if not ok then row.ready = false end
		return row
	end
	SocialScale = function(frame, finished, expected)
		local row = pins[frame] and pins[frame].social
		if not row or not Same(frame, row.ticket) then return end
		if not finished then row.complete = false; return row end
		if row == expected and row.ready and Current(row) then row.complete = true end
	end
	local reading, readSerial = false, 0
	function M:SocialToastBounds()
		local unavailable = { kind = "unavailable" }
		readSerial = readSerial + 1
		if reading then return unavailable end
		local serial = readSerial
		reading = true
		local ok, result = pcall(function()
			if not Same(self, M) or not Same(M.active, true) then return unavailable end
			if not Plain(E.modules) or not Plain(E.movers) or not Plain(E.BlizzardKeep) then return unavailable end
			local holder = holders.SocialToasts
			local mover = E.movers and E.movers[U.HOLDERS.SocialToasts.name]
			if not Frame(holder) or not Frame(mover) or not Same(mover.frame, holder)
				or not Same(mover.module, "Notifications") or not Same(E.modules and E.modules.Notifications, self) then return unavailable end
			local ticket, toast = rawget(_G, "TicketStatusFrame"), rawget(_G, "BNToastFrame")
			if type(ticket) == "nil" and type(toast) == "nil" then
				-- The layer-move countdown box shares the spot only for a few
				-- seconds before a move, so it is not one of the spot's parts.
				local shard = rawget(_G, "ShardTransferImminentFrame")
				for frame, pin in pairs(pins) do
					if pin.holder == holder and not (shard ~= nil and Same(frame, shard)) then return unavailable end
				end
				return { kind = "nominal", frame = holder }
			end
			local rows, parts = {}, {}
			for _, frame in pairs({ ticket = ticket, toast = toast }) do
				if not Frame(frame) then return unavailable end
				local row = pins[frame] and pins[frame].social
				if not row or not row.ready or not row.complete or not Current(row) then return unavailable end
				rows[#rows + 1] = row
			end
			local root = rawget(_G, "UIParent")
			if not Frame(root) or U.Secret(root.GetEffectiveScale) or type(root.GetEffectiveScale) ~= "function" then return unavailable end
			local rootMethod = root.GetEffectiveScale
			local rootScale = rootMethod(root)
			if not Number(rootScale) or rootScale <= 0 then return unavailable end
			for _, row in ipairs(rows) do
				for _, owner in ipairs(row.owners) do
					if not Current(row) or not Same(owner.method(owner.frame), owner.parent) or not Current(row) then return unavailable end
					if owner.typeMethod and (not Same(owner.typeMethod(owner.frame, "FontString"), true)
						or not Current(row)) then return unavailable end
				end
				if row.check then
					local wanted = row.check()
					if not Same(wanted, true) or not Current(row) then return unavailable end
				end
				for _, part in ipairs(row.parts) do
					if not Same(Call(row, part, "IsForbidden"), false) or not Same(Call(row, part, "GetParent"), part.parent) then return unavailable end
					local n = Call(row, part, "GetNumPoints")
					if not Number(n) or n < 1 or n > 2 or n % 1 ~= 0 then return unavailable end
					for index = 1, n do
						local point, relative, relativePoint, x, y = Call(row, part, "GetPoint", index)
						if U.Secret(point) or type(point) ~= "string" or U.Secret(relativePoint) or type(relativePoint) ~= "string"
							or not Number(x) or not Number(y) then return unavailable end
						local expected = part.relative
						if part.nativeInput then expected = index == 1 and row.inputTitle or row.inputTime end
						if part.role == "toast" and Frame(ticket) then
							local ticketRow = pins[ticket].social
							if not ticketRow or not Current(ticketRow) then return unavailable end
							local shown = Call(ticketRow, ticketRow.parts[1], "IsShown")
							if U.Secret(shown) or type(shown) ~= "boolean" then return unavailable end
							if shown then expected = ticket end
						end
						if not Same(relative, expected) then return unavailable end
						if part.points then
							local saved = part.points[index]
							if n ~= #part.points or not saved or not Same(point, saved[1]) or not Same(relative, saved[2])
								or not Same(relativePoint, saved[3]) or not Same(x, saved[4]) or not Same(y, saved[5]) then return unavailable end
						end
						if part.role == "ticket" or part.role == "toast" then
							local rp, py = row.relPoint, row.y
							if expected == ticket then rp, py = "TOPLEFT", 8 end
							if n ~= 1 or not Same(point, row.point) or not Same(relativePoint, rp)
								or not Same(x, row.x) or not Same(y, py) then return unavailable end
						end
					end
					local l, b, w, h = Call(row, part, "GetRect")
					local scale = Call(row, part, "GetEffectiveScale")
					local shown, visible = Call(row, part, "IsShown"), Call(row, part, "IsVisible")
					if not Number(l) or not Number(b) or not Number(w) or not Number(h) or w <= 0 or h <= 0
						or not Number(scale) or scale <= 0 or U.Secret(shown) or U.Secret(visible)
						or type(shown) ~= "boolean" or type(visible) ~= "boolean" then return unavailable end
					local ratio = scale / rootScale
					if not Number(ratio) or ratio <= 0 then return unavailable end
					local rect = { role = part.role, frame = part.frame, l = l * ratio, b = b * ratio,
						r = (l + w) * ratio, t = (b + h) * ratio, shown = shown, visible = visible }
					if not Number(rect.l) or not Number(rect.b) or not Number(rect.r) or not Number(rect.t) then return unavailable end
					parts[#parts + 1] = rect
				end
			end
			for _, row in ipairs(rows) do if not Current(row) then return unavailable end end
			if not Same(root.GetEffectiveScale, rootMethod) or not Same(rootMethod(root), rootScale) then return unavailable end
			for _, row in ipairs(rows) do
				for _, owner in ipairs(row.owners) do
					if not Current(row) or not Same(owner.method(owner.frame), owner.parent) or not Current(row) then return unavailable end
				end
			end
			return { kind = "live", frame = holder, parts = parts }
		end)
		reading = false
		return ok and serial == readSerial and result or unavailable
	end
end

---------------------------------------------------------------------------
-- Events: one dispatcher, several listeners per event across the files.
---------------------------------------------------------------------------
local listeners = {}

function U.On(event, fn)
	listeners[event] = listeners[event] or {}
	table.insert(listeners[event], fn)
	if M.active then M:RegisterEvent(event, M.Dispatch) end
end

function M.Dispatch(_, event, ...)
	for _, fn in ipairs(listeners[event] or {}) do
		local ok, err = pcall(fn, event, ...)
		if not ok then geterrorhandler()(err) end
	end
end

---------------------------------------------------------------------------
-- Elements
---------------------------------------------------------------------------
-- def = { apply = function(state) end, restore = function() end,
--         handler = { reload = ..., install = ..., legacy = ... } }
function U.Element(id, def)
	M.elements[id] = def
	table.insert(M.elementOrder, id)
	local handler = def.handler or {}
	handler.owner = "Notifications"
	handler.refreshModule = false
	handler.apply = function() M:RefreshElement(id) end
	handler.undo = function() M:RefreshElement(id) end
	E:RegisterBlizzardHandler(id, handler)
end

function M:RefreshElement(id)
	local def = self.elements[id]
	if not def then return end
	if self.active and E:BlizzardAllowed(id) then
		touched[id] = true
		local ok, err = pcall(def.apply, E:BlizzardState(id))
		if not ok then geterrorhandler()(err) end
	elseif touched[id] then
		touched[id] = nil
		local ok, err = pcall(def.restore)
		if not ok then geterrorhandler()(err) end
	end
end

function M:RefreshAll()
	for _, id in ipairs(self.elementOrder) do self:RefreshElement(id) end
end

function M:RestoreAll()
	for _, id in ipairs(self.elementOrder) do
		if touched[id] then
			touched[id] = nil
			local ok, err = pcall(self.elements[id].restore)
			if not ok then geterrorhandler()(err) end
		end
	end
end

---------------------------------------------------------------------------
-- Settings that moved here from QoL and Tweaks (v0.5.0): the switches take
-- over what the old options did, once per profile.
---------------------------------------------------------------------------
local function TurnOn(id, actions)
	local state = E:BlizzardState(id)
	local data = E.blizzardElements[id]
	if not state or not data then return end
	state.enabled = true
	for action, on in pairs(actions) do
		if data.allowed[action] then state[action] = on end
	end
end

function M:MigrateOldSettings()
	local modules = E.db and E.db.modules
	if not modules then return end
	-- Tweaks' settings moved into QoL's table (Modules/QoL/Tweaks.lua) first.
	local qol, tweaks = modules.QoL, modules.Tweaks or modules.QoL
	if qol then
		if qol.hideZoneText then TurnOn("zone-text", { hide = true, skin = false }) end
		if qol.hideBossBanner or qol.hideEventToasts then
			TurnOn("alert-toasts", { hide = true, skin = false })
			for key in pairs(self.db.alerts.hide) do self.db.alerts.hide[key] = false end
			self.db.alerts.hide.bossBanner = qol.hideBossBanner and true or false
			self.db.alerts.hide.levelup = qol.hideEventToasts and true or false
			self.db.alerts.hide.events = qol.hideEventToasts and true or false
		end
		if qol.fastMovieSkip then
			TurnOn("tutorials-cinematics", { improve = true, skin = false, hide = false })
			self.db.cinematics.escSkip = true
		end
		qol.hideZoneText, qol.hideBossBanner, qol.hideEventToasts, qol.fastMovieSkip = nil, nil, nil, nil
	end
	if tweaks then
		local mode = tweaks.hideErrors
		if mode and mode ~= "off" then
			TurnOn("ui-errors", { hide = true, skin = false })
			self.db.errors.mode = (mode == "always" or mode == "combat") and mode or "filter"
			if type(tweaks.errors) == "table" then
				for key, on in pairs(tweaks.errors) do
					if self.db.errors.categories[key] ~= nil then self.db.errors.categories[key] = on and true or false end
				end
			end
		end
		tweaks.hideErrors, tweaks.errors = nil, nil
	end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnInitialize()
	self:MigrateOldSettings()
	E:AddCommand("notify", "test [lane|errors|warning|bg|pings]  preview EldoUI's alerts and messages", function(arg)
		-- "test lane", "lane" and a bare "test" all work.
		local words = (arg or ""):lower():gsub("^%s*test%f[%A]", "")
		M:Test(words:match("^%s*(%a*)"))
	end, "Layout & frames")
end

function M:OnEnable()
	for event in pairs(listeners) do self:RegisterEvent(event, M.Dispatch) end
	for _, fn in ipairs(self.onEnable or {}) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
	-- The order of PLAYER_LOGIN handlers is not fixed: apply the switches now.
	self:RefreshAll()
end

function M:OnDisable()
	self:RestoreAll()
	for _, fn in ipairs(self.onDisable or {}) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
end

function M:OnProfileChanged()
	if not self.active then return end
	self:MigrateOldSettings()
	self:RefreshAll()
	for _, fn in ipairs(self.onProfile or {}) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
end

-- Extra start and stop work from the element files.
function U.OnEnable(fn)
	M.onEnable = M.onEnable or {}
	table.insert(M.onEnable, fn)
end

function U.OnDisable(fn)
	M.onDisable = M.onDisable or {}
	table.insert(M.onDisable, fn)
end

-- Re-apply work for settings that are not Blizzard elements.
function U.OnProfile(fn)
	M.onProfile = M.onProfile or {}
	table.insert(M.onProfile, fn)
end

-- /eui notify test: each element file adds its own preview.
M.tests = {}
function M:Test(which)
	if not self.active then
		E:Print(E:ModuleOffHint("Notifications"))
		return
	end
	local ran = false
	for key, fn in pairs(self.tests) do
		if which == "" or which == nil or which == key then
			fn()
			ran = true
		end
	end
	if not ran then E:Print(L["Usage: /eui notify test [lane|errors|warning|bg|pings]"]) end
end
