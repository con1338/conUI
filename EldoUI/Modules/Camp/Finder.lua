-- EldoUI Camp Helper: the camp finder. Off by default.
--
-- Guild and group members who use EldoUI can tell each other where a camp
-- is, one click at a time:
--   Ask for a camp    sends one line to your guild or group:
--                       "R1\t<your zone's map id>"
--   someone asks you  "When someone asks" = Ask me: a toast with a Send
--                     button, only while you know a fire to share; Never:
--                     nothing happens. There is no answer without a click.
--   Share this camp   sends one line about the fire you last hovered or lit:
--                       "C1\t<map>\t<x>\t<y>\t<tier>\t<slots>\t<seen>\t<age>"
--                     x and y in thousandths of the map, age in seconds.
-- A shared camp shows as a toast (Waypoint button) and on the camp panel
-- for ten minutes, the life of a fire. Nothing is saved.
--
-- Limits: every line is far below the 255 bytes of one addon message; an
-- ask goes out at most every 30 seconds and a share every 10; a toast for
-- the same asker at most once a minute; at most 20 camps are kept. Lines
-- come only from guild, group and friends (E:RegisterComm trusted), and
-- nothing is sent while the game holds addon messages back (boss fights,
-- Mythic+ and PvP matches): the click says so instead of queuing a camp
-- that is stale by the time it goes out.
--
-- Reduced form of the finder in other camp addons: no public channel and no
-- automatic broadcast or reply, so only people you know see your camp and
-- only when you click.
local _, E = ...
local L = E.L
local M = E.Camp
local D = E.CampData

local PREFIX = "EUI_CAMP"
local ASK_GAP, SHARE_GAP, TOAST_GAP = 30, 10, 60
local MAX_FINDS = 20
local MAX_LINE = 120
local ICON = 135805

M.FINDER_PREFIX = PREFIX
M.finds = {}          -- sender -> { sender, mapID, x, y, tier, slots, seen, at }
local askedBy = {}    -- sender -> GetTime() of their last toast
local last = { ask = -1e9, share = -1e9 }
M.finderLast = last

local issecret = issecretvalue or function() return false end
local floor, max, min = math.floor, math.max, math.min

local function Clean(value)
	if issecret(value) then return nil end
	return value
end

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
end

local function Short(name)
	if type(name) ~= "string" then return "?" end
	local short = Try(Ambiguate, name, "short")
	if type(short) == "string" and short ~= "" then return short end
	return (name:gsub("%-.*$", ""))
end

local function MapName(mapID)
	local info = mapID and C_Map and C_Map.GetMapInfo and Try(C_Map.GetMapInfo, mapID)
	local name = type(info) == "table" and Clean(info.name)
	return type(name) == "string" and name ~= "" and name or (L["Map %s"]):format(tostring(mapID))
end
M.FinderMapName = MapName

local function Ago(seconds)
	seconds = max(0, floor((seconds or 0) + 0.5))
	if seconds < 60 then return L["just now"] end
	return (L["%s ago"]):format(M.Clock(seconds))
end

local function TierName(tier)
	if tier == 1 then return L["Basic campfire"] end
	if tier == 2 then return L["Journeyman campfire"] end
	if tier == 3 then return L["Expert campfire"] end
	return L["Campfire"]
end

local function Channel()
	return M.db.finderChannel == "GROUP" and "GROUP" or "GUILD"
end

local function ChannelReady(channel)
	if channel == "GUILD" then return IsInGuild and IsInGuild() and true or false end
	return IsInGroup and IsInGroup() and true or false
end

-- Why Ask and Share would reach nobody right now, for the grayed rows.
function M:FinderChannelReason()
	local channel = Channel()
	if ChannelReady(channel) then return nil end
	if channel == "GUILD" then return L["Join a guild first, or pick Group under Ask and share with."] end
	return L["Join a group first, or pick Guild under Ask and share with."]
end

---------------------------------------------------------------------------
-- The fire you can share
---------------------------------------------------------------------------
-- The fire you last hovered or lit, while it can still burn and its place
-- is known (none inside instances: the game gives no position there).
function M:ShareableFire()
	local fire = self.fire
	if not (fire and fire.mapID and fire.x and fire.y) then return nil end
	if GetTime() - fire.time > D.FIRE_LIFETIME then return nil end
	return fire
end

function M:ShareLine()
	local fire = self:ShareableFire()
	if not fire then return nil end
	local info = fire.info
	local line = ("C1\t%d\t%d\t%d\t%d\t%d\t%d\t%d"):format(fire.mapID, floor(fire.x * 1000 + 0.5), floor(fire.y * 1000 + 0.5),
		info and info.tier or 0, info and info.slots or 0, min(self:SeenCount(), 20), floor(GetTime() - fire.time))
	return line
end

---------------------------------------------------------------------------
-- Sending: each one a click
---------------------------------------------------------------------------
-- Returns true, or false and the reason it printed.
local function Blocked()
	if not M.active then
		E:Print(E:ModuleOffHint("Camp"))
		return "off"
	end
	if not M.db.finder then
		E:Print(L["Ask and share camps is unchecked on the Camp Helper page (%s)."]:format(E:Highlight("/eui")))
		return "off"
	end
	if E:CommRestricted() then
		E:Print(L["Addon messages are paused here. Try again when the fight or match is over."])
		return "locked"
	end
end

function M:FinderAsk()
	local why = Blocked()
	if why then return false, why end
	local now = GetTime()
	if now - last.ask < ASK_GAP then
		E:Print((L["You asked a moment ago. Ask again in %s."]):format(self.Clock(ASK_GAP - (now - last.ask))))
		return false, "wait"
	end
	local channel = Channel()
	if not ChannelReady(channel) then
		E:Print(channel == "GUILD" and L["You are not in a guild."] or L["You are not in a group."])
		return false, "channel"
	end
	local mapID = C_Map and C_Map.GetBestMapForUnit and Clean(Try(C_Map.GetBestMapForUnit, "player"))
	local ok = E:SendComm(PREFIX, ("R1\t%d"):format(type(mapID) == "number" and mapID or 0), channel)
	if not ok then
		E:Print(L["The message could not be sent."])
		return false, "send"
	end
	last.ask = now
	E:Print(channel == "GUILD" and L["Asked your guild for a camp. Members who use EldoUI choose whether to answer."]
		or L["Asked your group for a camp. Members who use EldoUI choose whether to answer."])
	return true
end

-- channel nil: the finder's channel; "WHISPER" with a target answers one player.
function M:FinderShare(channel, target)
	local why = Blocked()
	if why then return false, why end
	local line = self:ShareLine()
	if not line then
		E:Print(L["No campfire to share. Hover a fire (or light one) first; inside instances the game gives no position."])
		return false, "fire"
	end
	local now = GetTime()
	if now - last.share < SHARE_GAP then
		E:Print((L["You shared a moment ago. Share again in %s."]):format(self.Clock(SHARE_GAP - (now - last.share))))
		return false, "wait"
	end
	channel = channel or Channel()
	if channel ~= "WHISPER" and not ChannelReady(channel) then
		E:Print(channel == "GUILD" and L["You are not in a guild."] or L["You are not in a group."])
		return false, "channel"
	end
	local ok = E:SendComm(PREFIX, line, channel, target)
	if not ok then
		E:Print(L["The message could not be sent."])
		return false, "send"
	end
	last.share = now
	if channel == "WHISPER" then
		E:Print((L["Sent your camp to %s."]):format(Short(target)))
	else
		E:Print(channel == "GUILD" and L["Shared your camp with your guild."] or L["Shared your camp with your group."])
	end
	return true
end

---------------------------------------------------------------------------
-- Camps others shared
---------------------------------------------------------------------------
function M:PruneFinds()
	local now = GetTime()
	local list = {}
	for sender, find in pairs(self.finds) do
		if now - find.at > D.FIRE_LIFETIME then
			self.finds[sender] = nil
		else
			list[#list + 1] = find
		end
	end
	table.sort(list, function(a, b) return a.at > b.at end)
	for index = MAX_FINDS + 1, #list do self.finds[list[index].sender] = nil end
	for index = #list, MAX_FINDS + 1, -1 do list[index] = nil end
	return list
end

-- Shared camps, newest first.
function M:Finds()
	if not (self.active and self.db.finder) then return {} end
	return self:PruneFinds()
end

function M:FindText(find)
	return (L["%s: %s in %s, %s"]):format(Short(find.sender), TierName(find.tier), MapName(find.mapID), Ago(GetTime() - find.at))
end

-- A waypoint to a shared camp: the Waypoints module's arrow when it is on,
-- else the game's own map pin.
function M:PinFind(find)
	if not find then return false end
	local title = (L["%s's camp"]):format(Short(find.sender))
	local W = E.Waypoints
	if W and W.active and W.Add then
		return W:Add(find.mapID, find.x, find.y, { title = title, persistent = false, source = "camp" }) ~= nil
	end
	local mapPoint = rawget(_G, "UiMapPoint")
	local point = mapPoint and mapPoint.CreateFromCoordinates and Try(mapPoint.CreateFromCoordinates, find.mapID, find.x, find.y)
	if not (point and C_Map and C_Map.SetUserWaypoint) then return false end
	if C_Map.CanSetUserWaypointOnMap and Try(C_Map.CanSetUserWaypointOnMap, find.mapID) == false then return false end
	Try(C_Map.SetUserWaypoint, point)
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then Try(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
	E:Print((L["Map pin set: %s, %s."]):format(title, MapName(find.mapID)))
	return true
end

local function Fields(text)
	local out = {}
	for part in (text .. "\t"):gmatch("([^\t]*)\t") do out[#out + 1] = part end
	return out
end

local function Int(text, low, high)
	local n = tonumber(text)
	if not n or n ~= floor(n) or n < low or n > high then return nil end
	return n
end

function M:OnCamp(fields, sender)
	local mapID, x, y = Int(fields[2], 1, 100000), Int(fields[3], 0, 1000), Int(fields[4], 0, 1000)
	local tier, slots, seen, age = Int(fields[5], 0, 3), Int(fields[6], 0, 10), Int(fields[7], 0, 20), Int(fields[8], 0, 3600)
	if not (mapID and x and y and tier and slots and seen and age) or age > D.FIRE_LIFETIME then return end
	local find = { sender = sender, mapID = mapID, x = x / 1000, y = y / 1000, tier = tier > 0 and tier or nil,
		slots = slots > 0 and slots or nil, seen = seen, at = GetTime() - age }
	self.finds[sender] = find
	self:PruneFinds()
	M:PushAlert({
		key = "camp:find:" .. sender, title = L["Camp shared"], icon = ICON, duration = 20,
		text = self:FindText(find),
		actions = {
			{ label = L["Waypoint"], tip = L["Points you to this camp: the Waypoints arrow, or the game's map pin."], func = function() M:PinFind(find) end },
		},
	})
	self:RefreshPanel()
end

function M:OnAsk(fields, sender)
	if self.db.finderAnswer ~= "ask" or not self:ShareableFire() then return end
	local now = GetTime()
	if askedBy[sender] and now - askedBy[sender] < TOAST_GAP then return end
	askedBy[sender] = now
	local mapID = Int(fields[2], 1, 100000)
	local text = mapID and (L["%s asks for a camp near %s."]):format(Short(sender), MapName(mapID))
		or (L["%s asks for a camp."]):format(Short(sender))
	M:PushAlert({
		key = "camp:ask:" .. sender, title = L["Camp asked"], icon = ICON, duration = 30, text = text,
		actions = {
			{ label = L["Send"], tip = L["Whispers one line with the place and tier of your camp. Nothing else is sent."], func = function()
				M:FinderShare("WHISPER", sender)
			end },
		},
	})
end

local function OnComm(payload, sender)
	if not (M.active and M.db.finder) or type(payload) ~= "string" or #payload > MAX_LINE then return end
	local fields = Fields(payload)
	if fields[1] == "R1" then
		M:OnAsk(fields, sender)
	elseif fields[1] == "C1" then
		M:OnCamp(fields, sender)
	end
end
M.OnFinderComm = OnComm

function M:EnableFinder()
	if self.db.finder then
		E:RegisterComm(PREFIX, OnComm, { trusted = true })
	else
		E:UnregisterComm(PREFIX)
		wipe(self.finds)
	end
end

-- Panel rows for shared camps: { icon, label, value, color, find }.
function M:FinderRows()
	local rows = {}
	for _, find in ipairs(self:Finds()) do
		rows[#rows + 1] = { ICON, (L["%s's camp"]):format(Short(find.sender)), MapName(find.mapID), color = "body", find = find }
		if #rows >= 3 then break end
	end
	return rows
end

function M:ListFinds()
	local finds = self:Finds()
	if #finds == 0 then
		E:Print(L["No shared camps in the last ten minutes."])
		return
	end
	for _, find in ipairs(finds) do E:Print(self:FindText(find)) end
end
