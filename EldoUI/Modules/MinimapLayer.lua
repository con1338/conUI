-- EldoUI Minimap: the layer chip and layer hops.
--
-- The chip shows the layer you are on as a short code in a corner of the
-- map. The code is read from the GUIDs of the creatures around you: on the
-- live realms the server part of a Creature or Vehicle GUID (its third
-- part) is the same for every creature of one layer and differs between
-- layers. It is an observed fingerprint, not an official layer number. A
-- layer is believed once two creatures agree, and a new one replaces it
-- only with three of the last five. Pets, totems and other units a player
-- controls carry the place they were made and are never read; GUIDs are
-- read only while they are plain values and never in an instance.
--
-- A hop: joining a group led by a player on another layer of the same zone
-- moves you to that layer (the game may count down first); you leave the
-- group again. EldoUI shares the hop network of the most used layer addon,
-- whose messages it speaks, written from scratch (its names and message
-- prefix live in Data/AddonFit.lua):
--   * Hop to another layer asks the game who is in your zone (the player
--     search, on your click) and sends each of them a hidden addon whisper
--     with your zone and the layer you leave. Only players running EldoUI or
--     that addon read it; nothing shows in anyone's chat.
--   * A player who helps ("Help others hop") on another layer of your zone
--     answers "heard" and invites you. You accept in the game's own popup;
--     EldoUI never accepts an invite for you.
--   * Once your layer changed, Leave group is one click, or EldoUI leaves a
--     few seconds later when you turned that on.
-- A player asked lately who never answered is not asked again for six
-- hours, a helper invites at most six players in ten minutes, and nothing
-- is sent in combat or in an instance. A message EldoUI does not
-- understand is ignored.
--
-- With the layer addon installed (and "Use the layer addon" on), EldoUI's
-- network side stays silent and a click on the chip opens that addon's
-- own window, so one character never answers a request twice.
local _, E = ...
local L = E.L
local M = E.modules.Minimap
if not M then return end

local NET = E.LayerNetwork or {}
local IsSecret = E.Secret
local Read = E.PlainCall

local Layer = {
	seen = {},          -- [zone] = { [key] = { id = whole id, at = GetTime() } }
	votes = {},         -- the keys of the last creatures read, newest last
	voted = {},         -- [guid] = true: creatures already read on this layer
	replied = {},       -- [asker] = GetTime() of our last "heard" (as helper)
	invited = {},       -- [asker] = GetTime() of our last invite (as helper)
	hosted = {},        -- [name] = true: players this session invited
	sent = {},          -- GetTime() of each invite, for the helper's limit
	cards = {},         -- [asker] = { sender, timer } (as helper)
	book = {},          -- [name] = true: players who answered as helpers this session
}
M.Layer = Layer

E:RegisterPrivate("layerHop", { asked = {} })

local VOTES = 5               -- creatures kept for the vote
local STALE_FOR = 10          -- creatures in view at a move belong to the layer left
local ASK_COOLDOWN = 10       -- seconds between two hop requests
local ASK_TTL = 120           -- a request waits this long for an invite
local SEARCH_WAIT = 5         -- seconds for the player search to answer
local SEARCH_LATE = 30        -- a late answer to our search is ignored after this
local BURST = 8               -- whispers per second
local MAX_ASKED = 49          -- players asked per request
local ASKED_FOR = 6 * 3600    -- a player who did not answer is not asked again for this long
local ASKED_KEEP = 3000       -- names kept for that rule
local AGAIN_WAIT = 3          -- seconds after the whispers before helpers with an unread layer are asked again
local AGAIN_LATE = 10         -- ... or after a helper on another layer had this long to invite
local SAME_AFTER = 15         -- in a helper's group without a move this long: the helper is on your layer
local LEAVE_AFTER = 4         -- seconds after the move before the group is left (automatic leave)
local MARK_TIME = 60          -- the chip stays marked this long after a hop
local REPLY_COOLDOWN = 10     -- seconds between two "heard" replies to one asker
local INVITE_COOLDOWN = 60    -- seconds before the same asker is invited again
local HOST_CAP = 6            -- invites a helper sends ...
local HOST_WINDOW = 600       -- ... in this many seconds
local DECIDE_WAIT = 20        -- seconds a helper's card waits for a click
local PARTY_MAX = 5
-- The player search filters by class: each later click asks one class of
-- the zone, so a crowded zone shows other players each time.
local CLASSES = { 1, 2, 3, 4, 5, 7, 8, 9, 11 }
local WHO_LISTS = { "LFGWhoListFrame", "FriendsFrame" }
local ZONE_MAP = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3

local function Now() return GetTime() end

---------------------------------------------------------------------------
-- Reading the layer
---------------------------------------------------------------------------
-- The whole id of a GUID ("6843-8": server part and zone part) and its
-- layer key (the server part), for a Creature or Vehicle; nil otherwise.
function Layer.IdFromGUID(guid)
	if IsSecret(guid) or type(guid) ~= "string" or guid == "" then return nil end
	local kind, _, server, _, zone = strsplit("-", guid)
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	if type(server) ~= "string" or not server:match("^%d+$") or tonumber(server) == 0 then return nil end
	if type(zone) ~= "string" or not zone:match("^%d+$") then return nil end
	return server .. "-" .. zone, server
end

function Layer.KeyFromGUID(guid)
	local _, key = Layer.IdFromGUID(guid)
	return key
end

-- The layer key of a whole id another player sent ("6843-8" or "6843").
local function KeyOf(id)
	if type(id) ~= "string" then return nil end
	return id:match("^(%d+)%-") or id:match("^(%d+)$")
end
Layer.KeyOf = KeyOf

local function InInstance()
	local ok, inside = pcall(IsInInstance)
	if not ok or IsSecret(inside) then return true end
	return inside and true or false
end

local function InCombat()
	return InCombatLockdown() or Read(UnitAffectingCombat, "player") and true or false
end

-- The zone you stand in as its zone map: a cave or a building counts as
-- its zone, since the layer is the zone's. Every client shares the number.
function Layer.Zone()
	local map = C_Map and C_Map.GetBestMapForUnit and Read(C_Map.GetBestMapForUnit, "player")
	if type(map) ~= "number" or map <= 0 then return nil end
	local zone = map
	for _ = 1, 6 do
		local info = C_Map.GetMapInfo and Read(C_Map.GetMapInfo, zone)
		if type(info) ~= "table" or type(info.mapType) ~= "number" or IsSecret(info.mapType) then break end
		if info.mapType == ZONE_MAP then return zone end
		local up = info.parentMapID
		if info.mapType < ZONE_MAP or IsSecret(up) or type(up) ~= "number" or up <= 0 then break end
		zone = up
	end
	return map
end

local function ZoneName(zone)
	local info = zone and C_Map and C_Map.GetMapInfo and Read(C_Map.GetMapInfo, zone)
	local name = type(info) == "table" and info.name
	if IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
	return name
end

function Layer.Reset()
	Layer.key, Layer.id, Layer.zone = nil, nil, nil
	wipe(Layer.votes)
	wipe(Layer.voted)
end

-- "2:41" for a number of seconds.
local function Clock(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- The keys seen in a zone, the current one first, then the newest.
function Layer.Known(zone)
	local seen = Layer.seen[zone or Layer.zone or 0]
	local keys = {}
	if not seen then return keys end
	for key in pairs(seen) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b)
		if a == Layer.key then return true end
		if b == Layer.key then return false end
		return seen[a].at > seen[b].at
	end)
	return keys
end

local function Short(key)
	key = tostring(key or "")
	return #key > 4 and key:sub(-4) or key
end
Layer.Short = Short

local function Remember(zone, key, id)
	local seen = Layer.seen[zone] or {}
	Layer.seen[zone] = seen
	seen[key] = { id = id, at = Now() }
end

-- One creature seen. unit, when given, is checked for a player's control.
function Layer.Observe(guid, unit)
	if not M.active or InInstance() then return end
	local id, key = Layer.IdFromGUID(guid)
	if not id then return end
	if unit and Read(UnitPlayerControlled, unit) then return end
	local stale = Layer.stale
	if stale and Now() < stale.untilAt and stale.guid[guid] then return end
	local zone = Layer.Zone()
	if not zone then return end
	if zone ~= Layer.zone then
		Layer.key, Layer.id, Layer.zone = nil, nil, zone
		wipe(Layer.votes)
		wipe(Layer.voted)
	end
	if Layer.voted[guid] then
		if key == Layer.key then Remember(zone, key, id) end
		return
	end
	Layer.voted[guid] = true
	local votes = Layer.votes
	votes[#votes + 1] = key
	if #votes > VOTES then table.remove(votes, 1) end
	if key == Layer.key then
		Layer.id = id
		Remember(zone, key, id)
		return
	end
	local count = 0
	for _, vote in ipairs(votes) do
		if vote == key then count = count + 1 end
	end
	if count < (Layer.key and 3 or 2) then return end
	local before = Layer.key
	local moved = not before and Layer.movedFrom
	Layer.key, Layer.id = key, id
	Remember(zone, key, id)
	wipe(Layer.voted)
	Layer.voted[guid] = true
	if before then
		Layer.Changed(before, key)
	elseif moved then
		Layer.movedFrom = nil
		if moved.zone == zone and moved.key ~= key then Layer.Changed(moved.key, key) end
	end
	Layer.Refresh()
end

local function ObserveUnit(unit)
	local guid = Read(UnitGUID, unit)
	if guid then Layer.Observe(guid, unit) end
end

-- The units in view, read again: after a move or when a request arrives.
function Layer.Scan()
	for index = 1, 40 do
		local unit = "nameplate" .. index
		if Read(UnitExists, unit) then ObserveUnit(unit) end
	end
	ObserveUnit("target")
	ObserveUnit("mouseover")
end

-- The creatures in view when the game moves you are the old layer's: they
-- do not count for STALE_FOR seconds.
local function MarkStale()
	local guids = {}
	for guid in pairs(Layer.voted) do guids[guid] = true end
	local function Add(unit)
		if not Read(UnitExists, unit) then return end
		local guid = Read(UnitGUID, unit)
		if type(guid) == "string" then guids[guid] = true end
	end
	for index = 1, 40 do Add("nameplate" .. index) end
	Add("target")
	Add("mouseover")
	Layer.stale = { untilAt = Now() + STALE_FOR, guid = guids }
end

function Layer.Changed(before, after)
	Layer.changedAt = Now()
	local hop = Layer.request
	if hop and hop.from == before and (hop.state == "invited" or hop.state == "joined") then
		hop.state = "changed"
		Layer.Arrived()
	end
	if M.db.layerNotice then
		E:Print(L["Your layer changed: %s to %s."]:format(Short(before), Short(after)))
	end
end

---------------------------------------------------------------------------
-- The layer addon next to EldoUI
---------------------------------------------------------------------------
function Layer.AddonLoaded()
	return NET.folder and C_AddOns and C_AddOns.IsAddOnLoaded and Read(C_AddOns.IsAddOnLoaded, NET.folder) and true or false
end

function Layer.Integrated()
	return M.db.layerAddon and Layer.AddonLoaded()
end

local function OpenAddon()
	local handler = NET.slash and SlashCmdList and SlashCmdList[NET.slash]
	if type(handler) == "function" then pcall(handler, "") end
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
local function Send(target, text)
	if not NET.prefix or E:CommRestricted() then return false end
	return E:SendComm(NET.prefix, text, "WHISPER", target, { raw = true }) and true or false
end

-- A name as the game shows it to you (no realm for your own realm).
local function Shown(name)
	local shown = Ambiguate and Read(Ambiguate, name, "none")
	if type(shown) ~= "string" or shown == "" then return name end
	return shown
end

-- A sender's name without the realm: "First Surname".
local function Bare(name)
	if IsSecret(name) or type(name) ~= "string" then return nil end
	return name:match("^([^%-]+)") or name
end

-- The route of a request: "<LS 1429 not 6843-8 48.2,42.5>" - the zone, the
-- layer left (or "want <id>" for one layer) and where you stand on the
-- zone map in percent, which helpers that keep their farming spot read.
local function Route(zone, want, leave, x, y)
	local parts = { "<LS", tostring(zone) }
	if want then parts[#parts + 1] = "want " .. want elseif leave then parts[#parts + 1] = "not " .. leave end
	if x and y then parts[#parts + 1] = ("%.1f,%.1f"):format(x * 100, y * 100) end
	return table.concat(parts, " ") .. ">"
end

-- The route read back, or nil: { zone, want, avoid, avoids }.
function Layer.ParseRoute(text)
	if IsSecret(text) or type(text) ~= "string" then return nil end
	local body = text:match("<LS([^<>]*)>")
	if not body then return nil end
	local zone = body:match("^%s*(%d+)%s") or body:match("^%s*(%d+)%s*$")
	if not zone then return nil end
	local avoids = {}
	for id in body:gmatch("not%s+(%d+%-%d+)") do avoids[#avoids + 1] = id end
	return { zone = zone, want = body:match("want%s+(%d+%-%d+)"), avoid = avoids[1], avoids = avoids }
end

local function MapSpot(zone)
	local pos = C_Map and C_Map.GetPlayerMapPosition and Read(C_Map.GetPlayerMapPosition, zone, "player")
	if type(pos) ~= "table" then return nil end
	local x, y = pos.x, pos.y
	if type(pos.GetXY) == "function" then
		local ok, a, b = pcall(pos.GetXY, pos)
		if ok then x, y = a, b end
	end
	if IsSecret(x) or IsSecret(y) or type(x) ~= "number" or type(y) ~= "number" then return nil end
	if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
	return x, y
end

---------------------------------------------------------------------------
-- Asking for a hop
---------------------------------------------------------------------------
local function SearchAvailable()
	local who = C_FriendList
	return type(who) == "table" and type(who.SendWho) == "function" and type(who.GetNumWhoResults) == "function"
		and type(who.GetWhoInfo) == "function"
end

-- Why a hop can't start now, or nil.
function Layer.CantAsk()
	if not M.active then return L["The minimap is off."] end
	if InInstance() then return L["Layers don't apply in an instance."] end
	if InCombat() then return L["Not in combat."] end
	if not (Layer.key and Layer.zone) then return L["Your layer isn't known yet. Look at a creature nearby first."] end
	if Read(IsInGroup) then return L["Leave your group first."] end
	if not SearchAvailable() then return L["This game client has no player search."] end
	if E:CommRestricted() then return L["The game is holding back addon messages right now."] end
	local last = Layer.askedAt
	if last and Now() - last < ASK_COOLDOWN then return L["Wait a few seconds before you ask again."] end
end

local function Status(text)
	local hop = Layer.request
	if hop then hop.status = text end
	Layer.Refresh()
end

local function AskedStore()
	local store = E:GetPrivate("layerHop")
	if type(store) ~= "table" then return {} end
	if type(store.asked) ~= "table" then store.asked = {} end
	return store.asked
end

-- Forget the names asked longer ago than ASKED_FOR, and keep at most ASKED_KEEP.
local function PruneAsked()
	local asked, now, names = AskedStore(), time(), {}
	for name, at in pairs(asked) do
		if type(at) ~= "number" or now - at >= ASKED_FOR then asked[name] = nil else names[#names + 1] = name end
	end
	if #names > ASKED_KEEP then
		table.sort(names, function(a, b) return asked[a] > asked[b] end)
		for index = ASKED_KEEP + 1, #names do asked[names[index]] = nil end
	end
	return asked
end

-- The game's own who lists stay closed while our search is out.
local function HushLists()
	Layer.muted = Layer.muted or {}
	for _, name in ipairs(WHO_LISTS) do
		local frame = _G[name]
		if type(frame) == "table" and not Layer.muted[name] and type(frame.IsEventRegistered) == "function" then
			local registered = Read(frame.IsEventRegistered, frame, "WHO_LIST_UPDATE")
			local shown = Read(frame.IsVisible, frame)
			if registered and not shown and pcall(frame.UnregisterEvent, frame, "WHO_LIST_UPDATE") then
				Layer.muted[name] = frame
			end
		end
	end
end

local function ReleaseLists()
	Layer.searching = nil
	for name, frame in pairs(Layer.muted or {}) do
		pcall(frame.RegisterEvent, frame, "WHO_LIST_UPDATE")
		Layer.muted[name] = nil
	end
	local toUI = C_FriendList and C_FriendList.SetWhoToUi
	if type(toUI) ~= "function" then return end
	for _, name in ipairs(WHO_LISTS) do
		local frame = _G[name]
		if type(frame) == "table" and type(frame.IsVisible) == "function" and Read(frame.IsVisible, frame) then return end
	end
	pcall(toUI, false)
end

-- Asks the game who is in your zone: one class of it after the first
-- click, so each click can reach other players. Runs only from a click.
local function Search(zone)
	local who = C_FriendList
	local name = ZoneName(zone)
	local tag = _G.WHO_TAG_ZONE
	if IsSecret(tag) or type(tag) ~= "string" or tag == "" then tag = "z-" end
	local text = name and (tag .. '"' .. name .. '"') or ""
	Layer.round = ((Layer.round or -1) + 1) % (#CLASSES + 1)
	local class = Layer.round > 0 and CLASSES[Layer.round] or nil
	local origin = Enum and Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social or 1
	HushLists()
	if type(who.SetWhoToUi) == "function" then pcall(who.SetWhoToUi, true) end
	local ok = pcall(who.SendWho, text, origin, { classIDs = class and { class } or {}, raceIDs = {}, uiMapIDs = { zone } })
	if not ok and name then ok = pcall(who.SendWho, text, origin) end
	if not ok then ReleaseLists() end
	return ok
end

function Layer.Ask(wanted)
	local why = Layer.CantAsk()
	if why then E:Print(why) return false end
	if Layer.request and Layer.request.state ~= "done" then return false end
	local want
	if wanted and wanted ~= "*" then
		local entry = Layer.seen[Layer.zone] and Layer.seen[Layer.zone][wanted]
		want = entry and entry.id or nil
	end
	local x, y = MapSpot(Layer.zone)
	local hop = { want = want, from = Layer.key, zone = Layer.zone, replies = {}, queue = {}, sent = 0,
		state = "searching", at = Now(),
		line = "inv layer " .. Route(Layer.zone, want, not want and Layer.id or nil, x, y) }
	Layer.request, Layer.askedAt = hop, Now()
	if not Search(Layer.zone) then
		Layer.Finish(L["The player search did not start. Try again in a moment."])
		return false
	end
	Layer.searching = hop
	Status(L["Looking for players in your zone..."])
	C_Timer.After(SEARCH_WAIT, function()
		if Layer.request == hop and hop.state == "searching" then
			Layer.Finish(L["The player search got no answer. Try again in a moment."])
		end
	end)
	C_Timer.After(SEARCH_LATE, function() if Layer.searching == hop then ReleaseLists() end end)
	return true
end

-- WHO_LIST_UPDATE: the answer to our own search, the players to ask. The
-- players in your zone first, players who helped before ahead of them,
-- your guild last; nobody asked lately who never answered.
function Layer.OnWhoList()
	local hop = Layer.searching
	if not hop then return end
	ReleaseLists()
	if Layer.request ~= hop or hop.state ~= "searching" then return end
	local who = C_FriendList
	local count = tonumber(Read(who.GetNumWhoResults)) or 0
	local asked = PruneAsked()
	local zoneName = ZoneName(hop.zone)
	local guild = Read(IsInGuild) and Read(GetGuildInfo, "player") or nil
	local first, here, rest, mates, skipped, seen = {}, {}, {}, {}, 0, {}
	for index = 1, math.min(count, 50) do
		local info = Read(who.GetWhoInfo, index)
		local name = type(info) == "table" and info.fullName
		if type(name) == "string" and not IsSecret(name) and name ~= "" and not seen[name] and not E:IsMe(name) then
			seen[name] = true
			local bare = Bare(name)
			local known = Layer.book[bare]
			if asked[name] and not known then
				skipped = skipped + 1
			elseif known then
				first[#first + 1] = name
			elseif type(guild) == "string" and info.fullGuildName == guild then
				mates[#mates + 1] = name
			elseif zoneName and info.area == zoneName then
				here[#here + 1] = name
			else
				rest[#rest + 1] = name
			end
		end
	end
	for _, list in ipairs({ first, here, rest, mates }) do
		for _, name in ipairs(list) do
			if #hop.queue < MAX_ASKED then hop.queue[#hop.queue + 1] = name end
		end
	end
	if #hop.queue == 0 then
		Layer.Finish(skipped > 0 and L["Everyone found here was asked lately. Try again later or in a busier zone."]
			or L["Nobody else was found in this zone. Try again in a moment."])
		return
	end
	hop.state = "asked"
	hop.askedAt = Now()
	Layer.Whisper(hop)
	C_Timer.After(ASK_TTL, function()
		if Layer.request == hop and hop.state == "asked" then Layer.Finish(L["No player invited you this time."]) end
	end)
end

-- BURST whispers a second until the list is done or someone invites.
function Layer.Whisper(hop)
	if Layer.request ~= hop or hop.state ~= "asked" then return end
	local asked = AskedStore()
	local count = 0
	while hop.queue[1] and count < BURST do
		local name = table.remove(hop.queue, 1)
		if Send(name, hop.line) then
			hop.sent = hop.sent + 1
			asked[name] = time()
		end
		count = count + 1
	end
	Status(E:Plural(hop.sent, "Asked %d player in your zone. Waiting for an invite...",
		"Asked %d players in your zone. Waiting for an invite..."):format(hop.sent))
	if hop.queue[1] then
		C_Timer.After(1, function() Layer.Whisper(hop) end)
		return
	end
	hop.doneAt = Now()
	C_Timer.After(AGAIN_WAIT, function() Layer.AskAgain(hop) end)
	C_Timer.After(AGAIN_LATE, function() Layer.AskAgain(hop) end)
end

-- Helpers who answered without knowing their own layer skip a request
-- that names the layer you leave. When no invite came, each of them is
-- asked once more without it.
function Layer.AskAgain(hop)
	if Layer.request ~= hop or hop.state ~= "asked" or hop.want or not hop.doneAt then return end
	local since = Now() - hop.doneAt
	local other = false
	for _, reply in pairs(hop.replies) do
		if reply.host and reply.layer and KeyOf(reply.layer) ~= hop.from and reply.zone == tostring(hop.zone) then other = true end
	end
	if other and since < AGAIN_LATE then return end
	local x, y = MapSpot(hop.zone)
	local line = "inv layer " .. Route(hop.zone, nil, nil, x, y)
	for _, reply in pairs(hop.replies) do
		if reply.host and not reply.layer and not reply.same and not reply.again and reply.zone == tostring(hop.zone) then
			reply.again = true
			Send(reply.sender, line)
		end
	end
end

function Layer.Cancel()
	local hop = Layer.request
	if not hop or hop.state == "done" then return end
	Layer.Finish(L["Hop canceled."])
end

function Layer.Finish(text)
	local hop = Layer.request
	if not hop then return end
	hop.state = "done"
	wipe(hop.queue)
	if Layer.searching == hop then ReleaseLists() end
	if text then E:Print(text) end
	Layer.request = nil
	E:DismissAlert("EldoUI.LayerLeave")
	Layer.Refresh()
end

-- "heard <you>|<their layer>|<their zone>|<h when they can invite>" and
-- "same" from a helper on your own layer.
local function OnReply(sender, text)
	local hop = Layer.request
	local bare = Bare(sender)
	if not bare then return end
	if text == "same" then
		Layer.book[bare] = true
		if hop and hop.state ~= "done" then
			local reply = hop.replies[bare] or { sender = sender }
			reply.same, reply.host = true, true
			hop.replies[bare] = reply
		end
		return
	end
	local target, layer, zone, host = text:match("^heard (.-)|([^|]*)|([^|]*)|([^|]*)$")
	if not target or not E:IsMe(target) then return end
	if host == "h" then Layer.book[bare] = true end
	if not hop or hop.state == "done" then return end
	local reply = hop.replies[bare] or { sender = sender }
	reply.layer = layer ~= "-" and layer or nil
	reply.zone = zone ~= "-" and zone or nil
	reply.host = reply.host or host == "h"
	hop.replies[bare] = reply
	if reply.host and not reply.layer then Layer.AskAgain(hop) end
end

-- PARTY_INVITE_REQUEST while a request waits: accepting is the player's,
-- in the game's own popup.
function Layer.Invited(name)
	local hop = Layer.request
	if not hop or hop.state ~= "asked" or IsSecret(name) or type(name) ~= "string" then return end
	hop.state, hop.inviter = "invited", name
	wipe(hop.queue)
	Status(L["%s invites you. Accept in the game's popup."]:format(Shown(name)))
	C_Timer.After(ASK_TTL, function()
		if Layer.request == hop and hop.state == "invited" then Layer.Finish(L["No hop this time."]) end
	end)
end

-- GROUP_JOINED: in the helper's group. The game moves you to its layer;
-- without a move after SAME_AFTER seconds the helper is on your layer.
function Layer.Joined()
	local hop = Layer.request
	if not hop or hop.state ~= "invited" then return end
	hop.state, hop.joinedAt = "joined", Now()
	Status(L["In the group. The game moves you to the helper's layer."])
	for _, delay in ipairs({ 1, 3, 6 }) do C_Timer.After(delay, Layer.Scan) end
	local tries = 0
	local function Judge()
		if Layer.request ~= hop or hop.state ~= "joined" then return end
		tries = tries + 1
		-- A move the game counts down to, or a new layer not read yet.
		if (hop.moving or Layer.MoveLeft() or not Layer.key) and tries < 24 then C_Timer.After(5, Judge) return end
		Layer.Scan()
		if Layer.key == hop.from then
			hop.state = "changed"
			Layer.Arrived(true)
		end
	end
	C_Timer.After(SAME_AFTER, Judge)
end

function Layer.GroupLeft()
	local hop = Layer.request
	if hop and (hop.state == "joined" or hop.state == "changed") then
		Layer.Finish()
		Layer.markedUntil = Now() + MARK_TIME
		Layer.Refresh()
	end
end

-- Your layer changed in the helper's group (same = it did not change):
-- leave the group with a click, or by itself with "Leave the group by
-- itself" on.
function Layer.Arrived(same)
	local hop = Layer.request
	if same then
		Status(L["This player is on your layer, so nothing changed."])
	else
		Status(L["You are on a new layer."])
	end
	if M.db.layerAutoLeave then
		E:Print(same and L["This player is on your layer. Leaving the group."]
			or L["You are on a new layer. Leaving the group in a few seconds."])
		C_Timer.After(same and 0 or LEAVE_AFTER, function()
			if Layer.request == hop and Read(IsInGroup) then Layer.Leave() end
		end)
		return
	end
	M:PushAlert({
		key = "EldoUI.LayerLeave", title = same and L["Layer unchanged"] or L["Layer changed"],
		text = same and L["This player is on your layer. Leave the group and ask again."]
			or L["You are on a new layer. Leave the group to stay here."],
		icon = 134400, duration = 30,
		actions = {
			{ label = L["Leave group"], func = function() Layer.Leave() end },
			{ label = L["Stay"] },
		},
	})
end

function Layer.Leave()
	if C_PartyInfo and C_PartyInfo.LeaveParty then pcall(C_PartyInfo.LeaveParty) end
	if Layer.request then Layer.Finish() end
	Layer.markedUntil = Now() + MARK_TIME
	Layer.Refresh()
end

---------------------------------------------------------------------------
-- The game's own layer move
---------------------------------------------------------------------------
-- WoW: Forever can schedule the move (SHARD_TRANSFER_IMMINENT, the time
-- left in GetEvictionTimeRemaining), show its own window with a countdown
-- and a Transfer now button, and move you (SHARD_TRANSFER) or call it off
-- (SHARD_TRANSFER_CANCELLED). EldoUI shows the countdown and waits for it;
-- moving early is always the game's own button.
function Layer.MoveLeft()
	if not Layer.moveEnds then return end
	local left = Layer.moveEnds - Now()
	if left <= 0 then return end
	return left
end

function Layer.MoveScheduled()
	local left = tonumber(Read(GetEvictionTimeRemaining))
	Layer.moveEnds = left and left > 0 and Now() + left or nil
	local hop = Layer.request
	if hop and (hop.state == "invited" or hop.state == "joined") then
		hop.moving = true
		Status(L["The game moves you to the group's layer."])
	end
	Layer.Refresh()
end

function Layer.MoveCancelled()
	local left = tonumber(Read(GetEvictionTimeRemaining))
	Layer.moveEnds = left and left > 0 and Now() + left or nil
	local hop = Layer.request
	if hop and hop.moving and not Layer.moveEnds then
		hop.moving = nil
		E:Print(L["The game called off the layer move."])
	end
	Layer.Refresh()
end

function Layer.Moved()
	Layer.moveEnds = nil
	Layer.movedAt = Now()
	MarkStale()
	-- The old key no longer holds; the next creatures name the new one.
	if Layer.key then Layer.movedFrom = { key = Layer.key, zone = Layer.zone } end
	Layer.key, Layer.id = nil, nil
	wipe(Layer.votes)
	wipe(Layer.voted)
	local hop = Layer.request
	if hop then hop.moving = nil end
	for _, delay in ipairs({ 2, 5, STALE_FOR + 2 }) do C_Timer.After(delay, Layer.Scan) end
	Layer.Refresh()
end

---------------------------------------------------------------------------
-- Helping others
---------------------------------------------------------------------------
-- "First Surname" of a group member.
local function MemberName(unit)
	return E.UnitWhisperName and E:UnitWhisperName(unit) or Read(UnitName, unit)
end

local function Listed()
	if C_LFGList and C_LFGList.HasActiveEntryInfo and Read(C_LFGList.HasActiveEntryInfo) then return true end
	return false
end

-- Whether this character can invite a player who asked, right now.
function Layer.CanHost()
	if InInstance() or InCombat() or Listed() or Layer.MoveLeft() then return false end
	local hop = Layer.request
	if hop and hop.state ~= "done" then return false end
	local now, kept = Now(), {}
	for _, at in ipairs(Layer.sent) do
		if now - at < HOST_WINDOW then kept[#kept + 1] = at end
	end
	Layer.sent = kept
	if #kept >= HOST_CAP then return false end
	if not Read(IsInGroup) then return true end
	if Read(IsInRaid) or not Read(UnitIsGroupLeader, "player") then return false end
	if (Read(GetNumGroupMembers) or PARTY_MAX) >= PARTY_MAX then return false end
	-- Only a group of players who came for a hop: never anyone else's group.
	for index = 1, PARTY_MAX - 1 do
		local unit = "party" .. index
		if Read(UnitExists, unit) then
			local name = MemberName(unit)
			if not (name and Layer.hosted[Bare(name)]) then return false end
		end
	end
	return true
end

-- Whether this character answers hop requests.
function Layer.Helping()
	return M.active and M.db.layerHelp and not Layer.Integrated() and true or false
end

function Layer.Invite(sender)
	local bare = Bare(sender)
	if not bare or not Layer.CanHost() or not (C_PartyInfo and C_PartyInfo.InviteUnit) then return false end
	-- The game invites by "First Surname"; the realm stays out.
	local called, result = pcall(C_PartyInfo.InviteUnit, bare)
	if not called or (not IsSecret(result) and result == false) then return false end
	Layer.invited[bare] = Now()
	Layer.hosted[bare] = true
	Layer.sent[#Layer.sent + 1] = Now()
	return true
end

function Layer.Decide(bare, invite)
	local card = Layer.cards[bare]
	if not card then return end
	if card.timer then card.timer:Cancel() end
	Layer.cards[bare] = nil
	if invite then Layer.Invite(card.sender) end
end

-- A card for a request: Invite or Not now. One card at a time.
local function Offer(sender, bare)
	if M.db.layerHelpAuto then
		Layer.Invite(sender)
		return
	end
	if next(Layer.cards) then return end
	local card = { sender = sender }
	Layer.cards[bare] = card
	M:PushAlert({
		key = "EldoUI.LayerHelp", title = L["Layer hop"],
		text = L["%s wants to hop to your layer."]:format(Shown(sender)),
		icon = 134400, duration = DECIDE_WAIT,
		actions = {
			{ label = L["Invite"], func = function() Layer.Decide(bare, true) end },
			{ label = L["Not now"], func = function() Layer.Decide(bare, false) end },
		},
	})
	card.timer = C_Timer.NewTimer(DECIDE_WAIT, function()
		if Layer.cards[bare] == card then
			Layer.cards[bare] = nil
			E:DismissAlert("EldoUI.LayerHelp")
		end
	end)
end

-- A request by hidden whisper: "inv layer <LS zone not/want id x,y>".
function Layer.OnAsk(sender, text)
	if not Layer.Helping() then return end
	local bare = Bare(sender)
	local route = Layer.ParseRoute(text)
	if not (bare and route) then return end
	local zone = Layer.Zone()
	if zone and zone ~= Layer.zone then Layer.Reset() end
	if not Layer.key then Layer.Scan() end
	local now = Now()
	local can = Layer.CanHost()
	if not (Layer.replied[bare] and now - Layer.replied[bare] < REPLY_COOLDOWN) then
		Layer.replied[bare] = now
		local heard = ("heard %s|%s|%s|%s"):format(bare, Layer.key and Layer.id or "-", zone and tostring(zone) or "-", can and "h" or "-")
		Send(sender, heard)
	end
	if not (can and zone and tostring(zone) == route.zone) then return end
	if route.want and KeyOf(route.want) ~= Layer.key then return end
	if route.avoid then
		if not Layer.key then return end
		if KeyOf(route.avoid) == Layer.key then
			Send(sender, "same")
			return
		end
	end
	for index = 2, #route.avoids do
		if KeyOf(route.avoids[index]) == Layer.key then return end
	end
	if Layer.invited[bare] and now - Layer.invited[bare] < INVITE_COOLDOWN then return end
	Offer(sender, bare)
end

-- CHAT_MSG_ADDON on the layer prefix: whispers from another player only.
function Layer.OnMessage(prefix, text, channel, sender)
	if IsSecret(prefix) or IsSecret(text) or IsSecret(channel) or IsSecret(sender) then return end
	if prefix ~= NET.prefix or channel ~= "WHISPER" or type(text) ~= "string" or type(sender) ~= "string" or #text > 255 then return end
	if not M.active or Layer.Integrated() or E:IsMe(sender) then return end
	if text:find("^inv layer") then
		Layer.OnAsk(sender, text)
	else
		OnReply(sender, text)
	end
	Layer.Refresh()
end

---------------------------------------------------------------------------
-- The chip
---------------------------------------------------------------------------
local function Ago(seconds)
	if seconds < 60 then return L["%d s ago"]:format(seconds) end
	return L["%d min ago"]:format(seconds / 60)
end

function Layer.ShowTooltip(chip)
	GameTooltip:SetOwner(chip, "ANCHOR_BOTTOMLEFT")
	local r, g, b = unpack(E.media.accentColor)
	GameTooltip:AddLine(L["Layer hop"], r, g, b)
	if Layer.key then
		E.UIKit.TipPair(GameTooltip, L["You are on"], Short(Layer.key))
		local seen = Layer.seen[Layer.zone] and Layer.seen[Layer.zone][Layer.key]
		if seen then E.UIKit.TipPair(GameTooltip, L["Last seen"], Ago(math.floor(Now() - seen.at))) end
		local others = {}
		for _, key in ipairs(Layer.Known()) do
			if key ~= Layer.key then others[#others + 1] = Short(key) end
		end
		if #others > 0 then E.UIKit.TipPair(GameTooltip, L["Also seen here"], table.concat(others, ", ")) end
	end
	local changed = math.max(Layer.changedAt or 0, Layer.movedAt or 0)
	if changed > 0 then E.UIKit.TipPair(GameTooltip, L["Last layer change"], Ago(math.floor(Now() - changed))) end
	local hop = Layer.request
	local left = Layer.MoveLeft()
	if left then
		E.UIKit.TipTitle(GameTooltip, L["The game moves you in %s."]:format(Clock(left)), true)
		E.UIKit.TipText(GameTooltip, L["Or click Transfer now in the game's window."])
	elseif hop and hop.status then
		E.UIKit.TipTitle(GameTooltip, hop.status, true)
	end
	E.UIKit.TipText(GameTooltip, L["Read from the creatures around you. It is not an official layer number."])
	GameTooltip:AddLine(" ")
	if Layer.Integrated() then
		E:TooltipHint(GameTooltip, { L["Click"], L["open %s"]:format(NET.folder) })
	else
		E:TooltipHint(GameTooltip, { L["Click"], L["hop to another layer"] })
	end
	GameTooltip:Show()
end

function Layer.OpenMenu(chip)
	if Layer.Integrated() then OpenAddon() return end
	local Kit = E.UIKit
	Kit.ContextMenu(chip, function(_, root)
		root:CreateTitle(L["Layer hop"])
		local hop = Layer.request
		if hop and hop.state == "changed" then
			root:CreateButton(L["Leave group"], function() Layer.Leave() end)
		elseif hop then
			root:CreateButton(L["Cancel the hop"], function() Layer.Cancel() end)
		else
			local why = Layer.CantAsk()
			local any = root:CreateButton(L["Hop to another layer"], function() Layer.Ask("*") end)
			any:SetEnabled(why == nil)
			if why then any:SetTooltip(function(tooltip) Kit.TipText(tooltip, why) end) end
			for _, key in ipairs(Layer.Known()) do
				if key ~= Layer.key then
					local entry = root:CreateButton(L["Hop to layer %s"]:format(Short(key)), function() Layer.Ask(key) end)
					entry:SetEnabled(why == nil)
				end
			end
		end
	end, { at = "owner" })
end

function Layer.CreateChip(overlay)
	local chip = CreateFrame("Button", nil, overlay)
	chip:RegisterForClicks("LeftButtonUp")
	chip.text = E:CreateText(chip, M.db.textSize)
	chip.text:SetPoint("CENTER")
	chip:SetScript("OnClick", function(clicked, button)
		if E:IsOptionsLinkClick(clicked, button) then return end
		Layer.OpenMenu(clicked)
	end)
	chip:SetScript("OnEnter", Layer.ShowTooltip)
	chip:SetScript("OnLeave", GameTooltip_Hide)
	-- The shared hover and pressed look: the chip can be clicked.
	E:SkinHoverPress(chip)
	E:BindOptionsLink(chip, { page = "module:Minimap", key = "layer" })
	chip:Hide()
	Layer.chip = chip
	return chip
end

-- Whether the chip takes its corner now.
function Layer.ChipShown()
	return M.active and M.improved and M.db.layer and (Layer.key ~= nil or Layer.movedFrom ~= nil) and not InInstance() and true or false
end

function Layer.Refresh()
	local chip = Layer.chip
	if not chip then return end
	local show = Layer.ChipShown()
	if show then
		E:SetFont(chip.text, M.db.textSize)
		-- Moved by the game, the new layer not read yet.
		local text = Layer.key and L["L %s"]:format(Short(Layer.key)) or L["L ?"]
		local hop = Layer.request
		local marked = (Layer.markedUntil and Now() < Layer.markedUntil) or (hop and hop.state ~= "done")
		if marked then
			local r, g, b = unpack(E.media.accentColor)
			chip.text:SetTextColor(r, g, b)
		else
			chip.text:SetTextColor(1, 1, 1)
		end
		chip.text:SetText(text)
		chip:SetSize(math.max(20, (chip.text:GetStringWidth() or 0) + 6), math.max(14, (M.db.textSize or 13) + 4))
		-- The same plate as the zone, coordinates and clock: readable over
		-- a bright map.
		if M.UpdatePlate then M:UpdatePlate(chip.text) end
	end
	if chip:IsShown() ~= show then
		chip:SetShown(show)
		if M.LayoutCorners then M:LayoutCorners() end
	end
end

---------------------------------------------------------------------------
-- Turning it on and off
---------------------------------------------------------------------------
local EVENTS = {
	PLAYER_TARGET_CHANGED = function() ObserveUnit("target") end,
	UPDATE_MOUSEOVER_UNIT = function() ObserveUnit("mouseover") end,
	NAME_PLATE_UNIT_ADDED = function(_, _, unit) if not IsSecret(unit) and type(unit) == "string" then ObserveUnit(unit) end end,
	PLAYER_SOFT_ENEMY_CHANGED = function() ObserveUnit("softenemy") end,
	PLAYER_SOFT_INTERACT_CHANGED = function() ObserveUnit("softinteract") end,
	ZONE_CHANGED_NEW_AREA = function()
		if Layer.Zone() ~= Layer.zone then Layer.Reset() end
		Layer.Refresh()
	end,
	PLAYER_ENTERING_WORLD = function()
		Layer.Reset()
		Layer.Refresh()
		C_Timer.After(2, Layer.Scan)
	end,
	CHAT_MSG_ADDON = function(_, _, ...) Layer.OnMessage(...) end,
	WHO_LIST_UPDATE = function() Layer.OnWhoList() end,
	PARTY_INVITE_REQUEST = function(_, _, name) Layer.Invited(name) end,
	GROUP_JOINED = function() Layer.Joined() end,
	GROUP_LEFT = function() Layer.GroupLeft() end,
	SHARD_TRANSFER_IMMINENT = function() Layer.MoveScheduled() end,
	SHARD_TRANSFER_CANCELLED = function() Layer.MoveCancelled() end,
	SHARD_TRANSFER = function() Layer.Moved() end,
}

-- An event this client does not know is left out.
local function EventKnown(event)
	local utils = C_EventUtils
	if not (utils and utils.IsEventValid) then return true end
	return Read(utils.IsEventValid, event) and true or false
end

function Layer.Apply()
	local on = M.active and (M.db.layer or M.db.layerHelp)
	for event, handler in pairs(EVENTS) do
		if on and EventKnown(event) then E:RegisterEvent(event, handler, Layer) else E:UnregisterEvent(event, Layer) end
	end
	if on and NET.prefix and C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, NET.prefix)
	end
	if not M.db.layerHelp then
		for bare in pairs(Layer.cards) do Layer.Decide(bare, false) end
		E:DismissAlert("EldoUI.LayerHelp")
	end
	Layer.Refresh()
end

function Layer.Disable()
	for event in pairs(EVENTS) do E:UnregisterEvent(event, Layer) end
	if Layer.request then Layer.Finish() end
	for _, card in pairs(Layer.cards) do if card.timer then card.timer:Cancel() end end
	if next(Layer.cards) then E:DismissAlert("EldoUI.LayerHelp") end
	wipe(Layer.cards)
	if Layer.searching then ReleaseLists() end
	if Layer.chip then Layer.chip:Hide() end
end
