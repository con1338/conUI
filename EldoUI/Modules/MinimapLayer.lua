-- EldoUI Minimap: the layer chip and layer hops.
--
-- The chip shows the layer you are on as a short code in a corner of the
-- map. The code is read from the GUIDs of the creatures around you: the
-- fifth part of a Creature or Vehicle GUID is the same for every creature
-- of one layer and differs between layers. It is an observed fingerprint,
-- not an official layer number, and it can change with the zone. GUIDs are
-- read only while they are plain values and never in an instance.
--
-- A hop: joining a group led by a player on another layer moves you to
-- that layer after a moment; you leave the group again. EldoUI asks the
-- players who offer help, with addon messages only:
--   * your guild (EldoUI players who turned on "Help others hop");
--   * the layer network, a hidden chat channel that the layer addon's
--     players share too (opt-in, off by default). EldoUI speaks that
--     addon's messages, written from scratch; its names and message
--     prefix live in Data/AddonFit.lua.
-- No chat text is ever sent to anyone. Every step that touches the group
-- is a click: the helper's Invite, the game's own invite popup on your
-- side (EldoUI never accepts it), and Leave group once the layer changed.
-- Nothing is sent in combat or in an instance, and a packet EldoUI does
-- not understand is ignored.
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
	maps = {},          -- [mapID] = { [key] = last seen (GetTime) }
	offered = {},       -- [sender .. "#" .. id] = { sender, id, key, at } (as helper)
	lastOffer = {},     -- [sender] = time of the last accepted request
	cards = {},         -- [sender .. "#" .. id] = { sender, id, timer } (as helper)
}
M.Layer = Layer

local CHANGE_WINDOW = 10      -- two creatures within this many seconds confirm a new layer
local OFFER_WAIT = 3          -- seconds the asker collects offers
local ANSWER_WAIT = 25        -- seconds a chosen helper has to answer
local DECIDE_WAIT = 20        -- seconds a helper's card waits for a click
local HOP_LIMIT = 120         -- the whole hop ends after this, unless the game has a move scheduled
local MOVE_RECHECK = 5        -- seconds between looks at a scheduled move once HOP_LIMIT has passed
local MAX_KNOWN = 12          -- layer keys sent along with a request
local OFFER_COOLDOWN = 10     -- seconds between offers to the same asker
local MAX_OFFERS = 32         -- simultaneous choices and recent askers
local MARK_TIME = 60          -- the chip stays marked this long after a hop

local function Now() return GetTime() end

---------------------------------------------------------------------------
-- Reading the layer
---------------------------------------------------------------------------
-- The layer key of a GUID: its fifth part for a Creature or Vehicle, a
-- whole number above 0; nil for anything else.
function Layer.KeyFromGUID(guid)
	if IsSecret(guid) or type(guid) ~= "string" or guid == "" then return nil end
	local kind, _, _, _, zone = strsplit("-", guid)
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	if type(zone) ~= "string" or not zone:match("^%d+$") or tonumber(zone) == 0 then return nil end
	return zone
end

local function InInstance()
	local ok, inside, kind = pcall(IsInInstance)
	if not ok or IsSecret(inside) or IsSecret(kind) then return true end
	return inside and true or false
end

local function InCombat()
	return InCombatLockdown() or Read(UnitAffectingCombat, "player") and true or false
end

local function CurrentMap()
	local map = C_Map and C_Map.GetBestMapForUnit and Read(C_Map.GetBestMapForUnit, "player")
	if type(map) ~= "number" then return nil end
	return map
end

function Layer.Reset()
	Layer.key, Layer.map, Layer.confirmed, Layer.candidate = nil, nil, nil, nil
end

-- "2:41" for a number of seconds.
local function Clock(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- The keys seen on a map, the current one first, then the newest.
function Layer.Known(map)
	local seen = Layer.maps[map or Layer.map or 0]
	local keys = {}
	if not seen then return keys end
	for key in pairs(seen) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b)
		if a == Layer.key then return true end
		if b == Layer.key then return false end
		return seen[a] > seen[b]
	end)
	return keys
end

local function Short(key)
	key = tostring(key or "")
	return #key > 4 and key:sub(-4) or key
end
Layer.Short = Short

-- One creature seen. The first key on a map is taken at once; a different
-- key afterwards needs a second creature within CHANGE_WINDOW seconds.
function Layer.Observe(guid)
	if not M.active or InInstance() then return end
	local key = Layer.KeyFromGUID(guid)
	if not key then return end
	local map = CurrentMap()
	if not map then return end
	if map ~= Layer.map then
		Layer.key, Layer.map, Layer.candidate = nil, map, nil
	end
	local now = Now()
	local seen = Layer.maps[map] or {}
	Layer.maps[map] = seen
	-- After the game moved you, the first creature names the new layer.
	local moved = Layer.movedFrom
	if not Layer.key and moved then
		Layer.movedFrom = nil
		Layer.key, Layer.confirmed, Layer.candidate = key, now, nil
		seen[key] = now
		if moved.map == map and moved.key ~= key then Layer.Changed(moved.key, key) end
		Layer.Refresh()
		return
	end
	if key == Layer.key then
		Layer.confirmed, Layer.candidate = now, nil
		seen[key] = now
		return
	end
	local candidate = Layer.candidate
	if Layer.key and not (candidate and candidate.key == key and candidate.guid ~= guid and now - candidate.at <= CHANGE_WINDOW) then
		if not (candidate and candidate.key == key and now - candidate.at <= CHANGE_WINDOW) then
			Layer.candidate = { key = key, guid = guid, at = now }
		end
		return
	end
	local before = Layer.key
	Layer.key, Layer.confirmed, Layer.candidate = key, now, nil
	seen[key] = now
	if before then Layer.Changed(before, key) end
	Layer.Refresh()
end

local function ObserveUnit(unit)
	local guid = Read(UnitGUID, unit)
	if guid then Layer.Observe(guid) end
end

function Layer.Changed(before, after)
	Layer.changedAt = Now()
	local hop = Layer.request
	if hop and hop.from == before and (hop.state == "invited" or hop.state == "pending" or hop.state == "asked" or hop.state == "queued") then
		hop.state = "changed"
		Layer.OfferLeave()
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
local function ClientID()
	local guid = Read(UnitGUID, "player")
	local id = type(guid) == "string" and guid ~= "" and guid or (E:PlayerName() or "player")
	return (id:gsub("[|:]", "_"))
end

local function Wire(payload)
	local wire = payload .. "|CID=" .. ClientID()
	if #wire > 255 then wire = payload end
	return wire
end

-- The channel number of the layer network while EldoUI is in it.
function Layer.NetworkID()
	if not (M.db.layerNetwork and NET.channel) or Layer.Integrated() then return nil end
	local id = GetChannelName and Read(GetChannelName, NET.channel)
	if type(id) ~= "number" or id <= 0 then return nil end
	return id
end

local function Send(payload, channel, target)
	if not NET.prefix or E:CommRestricted() then return false end
	return E:SendComm(NET.prefix, Wire(payload), channel, target, { raw = true }) and true or false
end

local function Whisper(target, payload) return Send(payload, "WHISPER", target) end

local function Compact(name)
	name = tostring(name or ""):gsub("^%s*%d+%.%s*", "")
	return (name:lower():gsub("[^%a%d]", ""))
end

-- Fields of a packet, without the CID tail. Every field is plain text.
local function Fields(text)
	local parts = { strsplit("|", text) }
	if parts[#parts] and parts[#parts]:find("^CID=") then parts[#parts] = nil end
	return parts
end

local function Number(value)
	local n = tonumber(value)
	if not n or n ~= n or n % 1 ~= 0 then return nil end
	return n
end

local function ValidKey(value)
	return type(value) == "string" and value:match("^%d+$") and tonumber(value) > 0 and value or nil
end

---------------------------------------------------------------------------
-- Asking for a hop
---------------------------------------------------------------------------
-- Why a hop can't start now, or nil.
function Layer.CantAsk()
	if not M.active then return L["The minimap is off."] end
	if InInstance() then return L["Layers don't apply in an instance."] end
	if InCombat() then return L["Not in combat."] end
	if not (Layer.key and Layer.map) then return L["Your layer isn't known yet. Look at a creature nearby first."] end
	if Read(IsInRaid) then return L["Leave the raid first."] end
	if not (Layer.NetworkID() or (Read(IsInGuild) and true)) then
		return L["Join the layer network or a guild first."]
	end
end

local function KnownCSV()
	local keys = {}
	for _, key in ipairs(Layer.Known()) do
		if #keys >= MAX_KNOWN then break end
		keys[#keys + 1] = key
	end
	return table.concat(keys, ",")
end

local function Status(text)
	local hop = Layer.request
	if hop then hop.status = text end
	Layer.Refresh()
end

function Layer.Ask(wanted)
	local why = Layer.CantAsk()
	if why then E:Print(why) return false end
	if Layer.request and Layer.request.state ~= "done" then return false end
	wanted = ValidKey(wanted) or "*"
	local id = math.random(100000, 999999)
	local hop = { id = id, wanted = wanted, map = Layer.map, from = Layer.key, offers = {}, tried = {},
		state = "asking", at = Now() }
	Layer.request = hop
	local payload = ("LQ|%d|%d|%s|%s|%s|LANG=any"):format(id, Layer.map, wanted, Layer.key, KnownCSV())
	local sent = false
	local network = Layer.NetworkID()
	if network then sent = Send(payload, "CHANNEL", network) or sent end
	if Read(IsInGuild) then sent = Send(payload, "GUILD") or sent end
	if not sent then
		Layer.Finish(L["The hop request could not be sent."])
		return false
	end
	Status(L["Asking for a hop..."])
	C_Timer.After(OFFER_WAIT, function() if Layer.request == hop and hop.state == "asking" then Layer.Choose() end end)
	-- The hop ends after HOP_LIMIT, but never while the game has a move
	-- scheduled: its own countdown can be longer.
	local function Expire()
		if Layer.request ~= hop or hop.state == "done" or hop.state == "changed" then return end
		if hop.moving then C_Timer.After(MOVE_RECHECK, Expire) return end
		-- Invited but never moved: the game limits how often a layer changes.
		Layer.Finish(hop.state == "invited" and L["The game limits how often you can change layer. Try again in a few minutes."]
			or L["No hop this time."])
	end
	C_Timer.After(HOP_LIMIT, Expire)
	return true
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
	if text then E:Print(text) end
	Layer.request = nil
	E:DismissAlert("EldoUI.LayerLeave")
	Layer.Refresh()
end

-- The next helper: the least busy one, then the smallest group.
function Layer.Choose()
	local hop = Layer.request
	if not hop then return end
	local best
	for name, offer in pairs(hop.offers) do
		if not hop.tried[name] and (not best or offer.load < best.load
			or (offer.load == best.load and offer.group < best.group)) then
			best = offer
		end
	end
	if not best then
		Layer.Finish(L["No player could help this time."])
		return
	end
	hop.tried[best.sender] = true
	hop.helper, hop.state = best.sender, "asked"
	Whisper(best.sender, ("LR|%d|%d|%s|%s"):format(hop.id, hop.map, best.key, NET.wire or "0.1.3"))
	Status(L["Asked %s to invite you."]:format(Ambiguate and Ambiguate(best.sender, "none") or best.sender))
	local helper = best.sender
	C_Timer.After(ANSWER_WAIT, function()
		if Layer.request == hop and hop.helper == helper and (hop.state == "asked" or hop.state == "pending" or hop.state == "queued") then
			Layer.Choose()
		end
	end)
end

function Layer.OfferLeave()
	Status(L["You are on a new layer."])
	M:PushAlert({
		key = "EldoUI.LayerLeave", title = L["Layer changed"],
		text = L["You are on a new layer. Leave the group to stay here."],
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
-- WoW: Forever does not move you the moment you join a group on another
-- layer: it schedules the move (SHARD_TRANSFER_IMMINENT, the time left in
-- GetEvictionTimeRemaining), shows its own window with a countdown and a
-- Transfer now button, and moves you (SHARD_TRANSFER) or calls it off
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
	if hop and hop.state ~= "done" and hop.state ~= "changed" then
		hop.moving = true
		Status(L["The game moves you to the group's layer."])
	end
	Layer.Refresh()
end

function Layer.MoveCancelled()
	Layer.moveEnds = nil
	local hop = Layer.request
	if hop and hop.moving then
		hop.moving = nil
		E:Print(L["The game called off the layer move."])
		if hop.state ~= "done" and hop.state ~= "changed" then Layer.Choose() end
	end
	Layer.Refresh()
end

function Layer.Moved()
	Layer.moveEnds = nil
	Layer.movedAt = Now()
	-- The old key no longer holds; the next creature names the new one.
	if Layer.key then Layer.movedFrom = { key = Layer.key, map = Layer.map } end
	Layer.key, Layer.confirmed, Layer.candidate = nil, nil, nil
	local hop = Layer.request
	if hop then
		hop.moving = nil
		if hop.state ~= "done" and hop.state ~= "changed" and Read(UnitInPartyShard, "player") then
			hop.state = "changed"
			Layer.OfferLeave()
		end
	end
	Layer.Refresh()
end

-- Answers to the asker.
local function OnOffer(sender, parts)
	local hop = Layer.request
	local id, map, key = Number(parts[2]), Number(parts[3]), ValidKey(parts[4])
	if not hop or hop.state ~= "asking" or id ~= hop.id or map ~= hop.map or not key or key == hop.from then return end
	if hop.wanted ~= "*" and key ~= hop.wanted then return end
	hop.offers[sender] = { sender = sender, key = key, group = Number(parts[5]) or 0, load = Number(parts[6]) or 0 }
end

local function OnReply(sender, parts)
	local hop = Layer.request
	local command, id = parts[1], Number(parts[2])
	if not hop or id ~= hop.id or sender ~= hop.helper then return end
	if command == "LW" then
		hop.state = "pending"
		Status(L["Waiting for %s to invite you."]:format(Ambiguate and Ambiguate(sender, "none") or sender))
	elseif command == "HQ" then
		hop.state = "queued"
		Status(L["In line for an invite."])
	elseif command == "LI" then
		hop.state = "invited"
		Status(L["If an invite appears, accept it in the game's popup."])
	elseif command == "LN" or command == "LD" or command == "LA" then
		Layer.Choose()
	end
end

---------------------------------------------------------------------------
-- Helping others
---------------------------------------------------------------------------
local function CanInvite()
	if not Read(IsInGroup) then return true end
	if Read(IsInRaid) then return false end
	return Read(UnitIsGroupLeader, "player") and (Read(GetNumGroupMembers) or 5) < 5 and true or false
end

-- Whether this character answers a request that came on `channel`.
function Layer.Helping(channel)
	if not (M.active and M.db.layerHelp) or Layer.Integrated() then return false end
	if channel == "GUILD" then return true end
	if channel == "CHANNEL" or channel == "WHISPER" then return Layer.NetworkID() ~= nil end
	return false
end

local function OnRequest(sender, parts, channel)
	if not Layer.Helping(channel) or InInstance() or InCombat() or not CanInvite() then return end
	local id, map, wanted, theirs = Number(parts[2]), Number(parts[3]), parts[4], ValidKey(parts[5])
	local mine = Layer.key
	if not (id and map and mine) or map ~= Layer.map or theirs == mine then return end
	if wanted ~= "*" and wanted ~= mine then return end
	local tag = sender .. "#" .. id
	local now = Now()
	if Layer.offered[tag] or (Layer.lastOffer[sender] and now - Layer.lastOffer[sender] < OFFER_COOLDOWN) then return end
	local offers, askers = 0, 0
	for _ in pairs(Layer.offered) do offers = offers + 1 end
	for asker, at in pairs(Layer.lastOffer) do
		if now - at >= OFFER_COOLDOWN then Layer.lastOffer[asker] = nil else askers = askers + 1 end
	end
	if offers >= MAX_OFFERS or askers >= MAX_OFFERS then return end
	Layer.lastOffer[sender] = now
	local offer = { sender = sender, id = id, key = mine, map = map, at = now }
	Layer.offered[tag] = offer
	-- Most askers choose someone else: the offer is forgotten once the
	-- asker could no longer pick it (OnChosen refuses it after 60 s too).
	offer.expiry = C_Timer.NewTimer(61, function()
		if Layer.offered[tag] == offer and not Layer.cards[tag] then Layer.offered[tag] = nil end
	end)
	C_Timer.After(0.2 + math.random() * 1.0, function()
		if Layer.offered[tag] ~= offer or not Layer.Helping(channel) or Layer.key ~= mine or Layer.map ~= map
			or InCombat() or not CanInvite() then return end
		local group = Read(IsInGroup) and (Read(GetNumGroupMembers) or 0) or 0
		Whisper(sender, ("LO|%d|%d|%s|%d|%d|ACT=1|LANG=any"):format(id, map, mine, group, Layer.Load()))
	end)
end

local function ForgetOffer(tag)
	local offer = Layer.offered[tag]
	if offer and offer.expiry then offer.expiry:Cancel() end
	Layer.offered[tag] = nil
end

-- How many hops this character helped with in the last ten minutes.
function Layer.Load()
	local now, count = Now(), 0
	for at in pairs(Layer.helped or {}) do
		if now - at < 600 then count = count + 1 else Layer.helped[at] = nil end
	end
	return count
end

function Layer.Decide(tag, invite)
	local card = Layer.cards[tag]
	if not card then return end
	if card.expiry then card.expiry:Cancel() end
	Layer.cards[tag] = nil
	ForgetOffer(tag)
	if invite and not InCombat() and C_PartyInfo and C_PartyInfo.InviteUnit then
		local called, result = pcall(C_PartyInfo.InviteUnit, card.sender)
		-- The client returns no result for an attempt and can still ask for
		-- confirmation. An explicit refusal must not send the invite reply.
		if called and not E.Secret(result) and result ~= false then
			Layer.helped = Layer.helped or {}
			Layer.helped[Now()] = true
			Whisper(card.sender, "LI|" .. card.id)
			return
		end
		Whisper(card.sender, ("LN|%d|invite failed"):format(card.id))
		return
	end
	Whisper(card.sender, (invite and "LN|%d|busy" or "LD|%d"):format(card.id))
end

local function OnChosen(sender, parts)
	local id = Number(parts[2])
	if not id then return end
	local tag = sender .. "#" .. id
	local offer = Layer.offered[tag]
	if offer and Now() - offer.at > 60 then
		ForgetOffer(tag)
		offer = nil
	end
	if not offer or not (Layer.Helping("WHISPER") or Layer.Helping("GUILD")) then
		Whisper(sender, ("LN|%d|busy"):format(id))
		return
	end
	if InCombat() or InInstance() or not CanInvite() or Layer.key ~= offer.key then
		ForgetOffer(tag)
		Whisper(sender, ("LN|%d|layer changed"):format(id))
		return
	end
	if Layer.cards[tag] then return end
	if next(Layer.cards) then
		Whisper(sender, ("LN|%d|busy"):format(id))
		return
	end
	Whisper(sender, "LW|" .. id)
	local name = Ambiguate and Ambiguate(sender, "none") or sender
	local card = { sender = sender, id = id }
	Layer.cards[tag] = card
	M:PushAlert({
		key = "EldoUI.LayerHelp", title = L["Layer hop"],
		text = L["%s wants to hop to your layer."]:format(name),
		icon = 134400, duration = DECIDE_WAIT,
		actions = {
			{ label = L["Invite"], func = function() Layer.Decide(tag, true) end },
			{ label = L["Not now"], func = function() Layer.Decide(tag, false) end },
		},
	})
	card.expiry = C_Timer.NewTimer(DECIDE_WAIT, function()
		if Layer.cards[tag] == card then
			Layer.cards[tag] = nil
			ForgetOffer(tag)
			E:DismissAlert("EldoUI.LayerHelp")
			Whisper(sender, "LA|" .. id)
		end
	end)
end

local function OnPresence(sender, parts)
	local id = Number(parts[2])
	if not id or not Layer.NetworkID() then return end
	local realm = (GetNormalizedRealmName and Read(GetNormalizedRealmName)) or ""
	Whisper(sender, ("WR|%d|%s|%s|%d|%s|%d|LANG=any|POP=0|BUILD=EldoUI"):format(id, realm, NET.wire or "0.1.3",
		Layer.map or 0, Layer.key or "", Layer.Helping("CHANNEL") and 1 or 0))
end

-- CHAT_MSG_ADDON on the layer prefix. Only plain text from another
-- player; the network channel only when it is ours.
function Layer.OnMessage(prefix, text, channel, sender, target, _, _, channelName)
	if IsSecret(prefix) or IsSecret(text) or IsSecret(channel) or IsSecret(sender) then return end
	if prefix ~= NET.prefix or type(text) ~= "string" or type(sender) ~= "string" or #text > 255 then return end
	if not M.active or Layer.Integrated() or E:IsMe(Ambiguate and Ambiguate(sender, "none") or sender) then return end
	if channel == "CHANNEL" then
		local network = NET.channel and Compact(NET.channel)
		if not Layer.NetworkID() or IsSecret(channelName) or IsSecret(target) then return end
		local named = Compact(channelName)
		if named ~= "" and named ~= network then return end
		if named == "" and Compact(target) ~= network then return end
	elseif channel ~= "WHISPER" and channel ~= "GUILD" then
		return
	end
	local parts = Fields(text)
	local command = parts[1]
	if command == "LQ" then
		OnRequest(sender, parts, channel)
	elseif channel ~= "WHISPER" then
		if command == "WP" and channel == "CHANNEL" then OnPresence(sender, parts) end
	elseif command == "LO" then
		OnOffer(sender, parts)
	elseif command == "LR" then
		OnChosen(sender, parts)
	elseif command == "LW" or command == "LI" or command == "HQ" or command == "LN" or command == "LD" or command == "LA" then
		OnReply(sender, parts)
	end
	Layer.Refresh()
end

---------------------------------------------------------------------------
-- The layer network channel
---------------------------------------------------------------------------
function Layer.ApplyNetwork()
	if not NET.channel then return end
	local want = M.active and M.db.layerNetwork and not Layer.Integrated()
	local id = GetChannelName and Read(GetChannelName, NET.channel)
	local inside = type(id) == "number" and id > 0
	if want and not inside then
		if JoinChannelByName then pcall(JoinChannelByName, NET.channel) end
		-- A hidden channel: it never shows in a chat window.
		for index = 1, (NUM_CHAT_WINDOWS or 10) do
			local frame = _G["ChatFrame" .. index]
			if frame and type(frame.RemoveChannel) == "function" then pcall(frame.RemoveChannel, frame, NET.channel) end
		end
		Layer.joined = true
	elseif not want and inside and Layer.joined then
		Send("BY|" .. (NET.wire or "0.1.3"), "CHANNEL", id)
		C_Timer.After(1, function()
			if not (M.active and M.db.layerNetwork) and LeaveChannelByName then pcall(LeaveChannelByName, NET.channel) end
		end)
		Layer.joined = nil
	end
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
		if Layer.confirmed then E.UIKit.TipPair(GameTooltip, L["Last seen"], Ago(math.floor(Now() - Layer.confirmed))) end
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
		local map = CurrentMap()
		if map ~= Layer.map then Layer.Reset() end
		Layer.Refresh()
	end,
	PLAYER_ENTERING_WORLD = function()
		Layer.Reset()
		Layer.Refresh()
		C_Timer.After(5, function() if M.active then Layer.ApplyNetwork() end end)
	end,
	CHAT_MSG_ADDON = function(_, _, ...) Layer.OnMessage(...) end,
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
	local on = M.active and (M.db.layer or M.db.layerHelp or M.db.layerNetwork)
	for event, handler in pairs(EVENTS) do
		if on and EventKnown(event) then E:RegisterEvent(event, handler, Layer) else E:UnregisterEvent(event, Layer) end
	end
	if on and NET.prefix and C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, NET.prefix)
	end
	Layer.ApplyNetwork()
	Layer.Refresh()
end

function Layer.Disable()
	for event in pairs(EVENTS) do E:UnregisterEvent(event, Layer) end
	if Layer.request then Layer.Finish() end
	for tag in pairs(Layer.offered) do ForgetOffer(tag) end
	for _, card in pairs(Layer.cards) do if card.expiry then card.expiry:Cancel() end end
	if next(Layer.cards) then E:DismissAlert("EldoUI.LayerHelp") end
	wipe(Layer.cards)
	wipe(Layer.lastOffer)
	Layer.ApplyNetwork()
	if Layer.chip then Layer.chip:Hide() end
end
