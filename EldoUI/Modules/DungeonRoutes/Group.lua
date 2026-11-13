-- EldoUI Dungeon Routes: routes to and from your group.
--
-- Send: "Send to group" (the side of the Dungeons window, the route menu)
-- sends the route's !EUR1! string to your party, raid or instance group as
-- one addon message on the prefix EUI_ROUTE, cut into parts by E:SendComm
-- (Core/Comm.lua: at most 255 bytes a part, the game's allowance per
-- prefix). One click is one send; a route bigger than MAX_SEND bytes is not
-- sent (export it as a string instead), and the same player sends at most
-- once every SEND_GAP seconds. While the game holds addon messages back
-- (boss fights, Mythic+, PvP matches: E:CommRestricted) nothing is sent and
-- the window says so.
--
-- Receive: only with "Get routes your group sends" on (off by default) is
-- the prefix listened to, and only from people in your party or raid. A
-- route that arrives is read by EldoUI's own share reader (never run as
-- code), cleaned like a pasted string and put in the "From your group" list
-- of the Dungeons window, at most MAX_INBOX, newest first, one per sender
-- and route name. Nothing is ever answered or sent back, nothing is added to
-- your routes until you click Keep, and a notice says a route came (off
-- with "Notice when a route arrives"). The list lives until you log out.
local _, E = ...
local L = E.L
local M = E.DungeonRoutes
local Kit = E.UIKit

local PREFIX = "EUI_ROUTE"
local MARK = "R1\t"
local MAX_SEND = 4000        -- bytes of the share string
local MAX_RECEIVE = 4200
local SEND_GAP = 10          -- seconds between two sends
local SENDER_GAP = 5         -- seconds between two routes from one sender
local MAX_INBOX = 12

M.GROUP_PREFIX = PREFIX
M.MAX_SEND = MAX_SEND

local inbox = {}             -- { { sender, route, text, at }, ... } newest first
local lastSend = -SEND_GAP
local lastFrom = {}          -- sender -> time
local listening = false

local Secret = E.Secret

local function ShortName(name)
	if type(name) ~= "string" then return "?" end
	if Ambiguate then return Ambiguate(name, "none") end
	return (name:gsub("%-.*$", ""))
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local function InGroup()
	return IsInGroup() or IsInRaid()
end

-- Sends a route to the group. Returns true, or false and a reason the
-- player can read.
function M:SendToGroup(route)
	if not self.active then return false, E:ModuleOffNote("DungeonRoutes") end
	if type(route) ~= "table" then return false, L["There is no route to send."] end
	if not InGroup() then return false, L["You are not in a group."] end
	if E:CommRestricted() then
		return false, L["The game holds addon messages back right now. Try again later."]
	end
	local now = GetTime()
	if now - lastSend < SEND_GAP then
		return false, (L["Wait %d seconds before you send again."]):format(math.ceil(SEND_GAP - (now - lastSend)))
	end
	local text = self:ExportString(route.id or ("shipped:" .. tostring(route.key)))
	if type(text) ~= "string" then return false, L["This route can't be sent."] end
	if #text > MAX_SEND then
		return false, L["This route is too big to send to the group (too many lines). Export it as a string instead."]
	end
	local ok, reason = E:SendComm(PREFIX, MARK .. text, "GROUP")
	if not ok then
		if reason == "channel" then return false, L["You are not in a group."] end
		return false, L["The route could not be sent."]
	end
	lastSend = now
	return true
end

-- The window's button: send and say how it went.
function M:SendFromWindow(route)
	local ok, reason = self:SendToGroup(route)
	local win = self:Browser()
	local text = ok and (L["\"%s\" sent to your group. Players with \"Get routes your group sends\" on see it in their list."]):format(route.name or "?") or reason
	if win and win.frame then
		Kit.Toast(win.frame, text, { warn = not ok })
	elseif not self.active then
		E:Print(E:ModuleOffHint("DungeonRoutes"))
	else
		E:Print(text)
	end
	return ok
end

---------------------------------------------------------------------------
-- Receiving (opt-in)
---------------------------------------------------------------------------
function M:Inbox()
	return inbox
end

local function Notify(entry)
	if not M.db.groupAlert then return end
	M:PushAlert({
		key = "dungeonroutes-group",
		title = L["A route from your group"],
		text = (L["%s sent \"%s\" (%s)."]):format(entry.sender, entry.route.name, M:DungeonName(entry.route.key)),
		icon = 134269,
		actions = {
			{ label = L["Show"], func = function() M:OpenGroupTab() end },
			{ label = L["Later"] },
		},
	})
end

-- One message from the group (plugins may call it too). Returns the
-- inbox entry, or nil when the message was dropped.
function M:OnGroupRoute(payload, sender)
	if not (self.active and self.db.groupReceive) then return nil end
	if type(payload) ~= "string" or Secret(payload) or type(sender) ~= "string" or Secret(sender) then return nil end
	if #payload > MAX_RECEIVE or payload:sub(1, #MARK) ~= MARK then return nil end
	local now = GetTime()
	local short = ShortName(sender)
	if lastFrom[short] and now - lastFrom[short] < SENDER_GAP then return nil end
	local kind, data = E:DecodeShareData(payload:sub(#MARK + 1))
	if kind ~= self.KIND then return nil end
	local route = self:SanitizeRoute(data)
	if not route then return nil end
	lastFrom[short] = now
	for index = #inbox, 1, -1 do
		local old = inbox[index]
		if old.sender == short and old.route.name == route.name and old.route.key == route.key then table.remove(inbox, index) end
	end
	local entry = { sender = short, route = route, at = time and time() or 0, got = now }
	table.insert(inbox, 1, entry)
	while #inbox > MAX_INBOX do table.remove(inbox) end
	Notify(entry)
	self:Changed("inbox")
	return entry
end

function M:KeepGroupRoute(entry)
	local route, err = self:SaveRoute(entry and entry.route, entry and entry.route and entry.route.name)
	if not route then
		local win = self:Browser()
		local text = (L["Dungeon Routes: the route was not added (%s)."]):format(tostring(err))
		if win and win.frame then Kit.Toast(win.frame, text, { warn = true }) else E:Print(text) end
		return nil
	end
	self:DismissGroupRoute(entry)
	self:SetActiveRoute(route.key, route)
	return route
end

function M:DismissGroupRoute(entry)
	for index, other in ipairs(inbox) do
		if other == entry then
			table.remove(inbox, index)
			self:Changed("inbox")
			return true
		end
	end
	return false
end

-- Listen only while the option is on.
function M:UpdateGroupListen()
	local want = self.active and self.db.groupReceive and true or false
	if want == listening then return listening end
	if want then
		listening = E:RegisterComm(PREFIX, function(payload, sender) M:OnGroupRoute(payload, sender) end, { trusted = "group" }) and true or false
	else
		E:UnregisterComm(PREFIX)
		listening = false
	end
	return listening
end

function M:GroupListening()
	return listening
end

M:Hook("enable", function() M:UpdateGroupListen() end)
M:Hook("disable", function() M:UpdateGroupListen() end)
M:Hook("profile", function() M:UpdateGroupListen() end)

---------------------------------------------------------------------------
-- The "From your group" tab of the Dungeons window
---------------------------------------------------------------------------
local function Age(entry)
	local seconds = math.max(0, GetTime() - (entry.got or GetTime()))
	if seconds < 60 then return L["just now"] end
	return (L["%d min ago"]):format(math.floor(seconds / 60))
end

local function EntryMenu(row, entry)
	E.UIKit.ContextMenu(row, function(_, root)
		root:CreateTitle(entry.route.name)
		root:CreateButton(L["Keep and open on the map"], function()
			local route = M:KeepGroupRoute(entry)
			if route then M:OpenRoute(route) end
		end)
		root:CreateButton(L["Keep"], function() M:KeepGroupRoute(entry) end)
		root:CreateButton(L["Dismiss"], function() M:DismissGroupRoute(entry) end)
	end)
end

local function CreateTab(content)
	local frame = CreateFrame("Frame", nil, content)
	frame:SetAllPoints()
	frame.toggle = Kit.Button(frame, "", 200, 22, function()
		M.db.groupReceive = not M.db.groupReceive
		M:UpdateGroupListen()
		M:Changed("inbox")
	end, L["Get routes your group sends"], L["Listen for routes people in your party or raid send. They wait in this list until you keep or dismiss them; nothing is ever sent back."])
	frame.toggle:SetPoint("TOPRIGHT", 0, 0)
	frame.help = Kit.Text(frame, 11, "LEFT", "secondary")
	frame.help:SetPoint("TOPLEFT", 2, -4)
	frame.help:SetPoint("TOPRIGHT", frame.toggle, "TOPLEFT", -12, -4)
	frame.help:SetWordWrap(false)
	frame.table = Kit.CreateTable(frame, {
		{ key = "sender", title = L["From"], width = 140, value = function(entry) return entry.sender end },
		{ key = "dungeon", title = L["Dungeon"], width = 200, value = function(entry) return M:DungeonName(entry.route.key) end },
		{ key = "name", title = L["Route"], value = function(entry) return entry.route.name end },
		{ key = "pulls", title = L["Pulls"], width = 60, align = "RIGHT", value = function(entry) return #entry.route.pulls end },
		{ key = "got", title = L["Came"], width = 90, align = "RIGHT", value = function(entry) return entry.got or 0 end,
			text = function(entry) return Age(entry) end },
	}, {
		sortKey = "got",
		sortDown = true,
		empty = { L["No routes from your group yet"], L["When someone in your group clicks Send to group, their route shows here."] },
		onClick = function(entry, _, row) EntryMenu(row, entry) end,
	})
	frame.table:SetPoint("TOPLEFT", 0, -30)
	frame.table:SetPoint("BOTTOMRIGHT")
	local win = M:Browser()
	if win then win.groupFrame = frame end
	M.groupFrame = frame
	return frame
end

local function RefreshTab(frame)
	frame.toggle:SetText(M.db.groupReceive and L["Stop getting routes"] or L["Get routes your group sends"])
	Kit.FitButton(frame.toggle, 160)
	frame.help:SetText(M.db.groupReceive and L["Click a route to keep it or dismiss it. Nothing is added to your routes until you keep one."]
		or L["Off: routes your group sends are not listened to."])
	if M.db.groupReceive then
		frame.table.list:SetEmpty(L["No routes from your group yet"], L["When someone in your group clicks Send to group, their route shows here."])
	else
		frame.table.list:SetEmpty(L["Routes from your group are off"], L["Turn on \"Get routes your group sends\" (top right) to see routes people in your group send you."])
	end
	frame.table:SetData(inbox)
end

function M:GroupTab()
	return { key = "group", title = L["From your group"], desc = L["Routes people in your group sent you. Keep one to add it to your routes."],
		create = CreateTab, show = RefreshTab, refresh = RefreshTab, count = function() return #inbox end }
end

function M:OpenGroupTab()
	if InCombatLockdown() or not self.active then return false end
	self:BuildBrowser()
	local win = self:Browser()
	return win:Open("group")
end

-- Test hook: forget the list and the gaps.
function M:ResetGroup()
	wipe(inbox)
	wipe(lastFrom)
	lastSend = -SEND_GAP
end
